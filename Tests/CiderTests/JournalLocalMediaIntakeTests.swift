import Foundation
import Testing
@testable import Cider

@Suite("Journal Local Media Intake Tests")
@MainActor
struct JournalLocalMediaIntakeTests {
    @Test("audio and photo originals preserve exact bytes hashes topology source identity and ordering")
    func originalsPreserveBytesAndSourceIdentity() throws {
        let fixture = try JournalMediaFixture()
        defer { fixture.cleanup() }
        let audioBytes = Data(repeating: 0x41, count: Int(AgentRoomsAttachmentService.maximumImageByteSize + 1))
        let photoBytes = JournalMediaFixture.pngData
        let audioURL = try fixture.write("voice.m4a", audioBytes)
        let photoURL = try fixture.write("photo.png", photoBytes)
        let service = fixture.makeService()

        let audio = try service.ingest(.init(
            sourceURL: audioURL,
            sourceID: "transport:voice:1",
            kind: .audio,
            capturedAt: Date(timeIntervalSince1970: 1_826_200_001)
        ))
        let photo = try service.ingest(.init(
            sourceURL: photoURL,
            sourceID: "transport:photo:2",
            kind: .photo,
            capturedAt: Date(timeIntervalSince1970: 1_826_200_002)
        ))

        #expect(audio.file.relativePath.hasPrefix("Journal/Audio/"))
        #expect(photo.file.relativePath.hasPrefix("Journal/Photos/"))
        #expect(try Data(contentsOf: fixture.vaultRoot.appendingPathComponent(audio.file.relativePath)) == audioBytes)
        #expect(try Data(contentsOf: fixture.vaultRoot.appendingPathComponent(photo.file.relativePath)) == photoBytes)
        #expect(audio.sha256 == LocalFileIntakeValidator.sha256(audioBytes))
        #expect(photo.sha256 == LocalFileIntakeValidator.sha256(photoBytes))
        #expect(audio.sourceID == "transport:voice:1")
        #expect(audio.retention == .preserveOriginal)
        #expect(audio.sourceCardID != photo.sourceCardID)
        #expect([photo, audio].sorted().map(\.sourceID) == ["transport:voice:1", "transport:photo:2"])
        #expect(try fixture.vaultFileCount() == 2)
    }

    @Test("source mutation and database failure restore exact filesystem and database fingerprints")
    func mutationAndDatabaseFailureRollback() throws {
        let fixture = try JournalMediaFixture()
        defer { fixture.cleanup() }
        let source = try fixture.write("voice.m4a", Data("original".utf8))
        let filesystemBefore = try fixture.filesystemFingerprint()
        let databaseBefore = try fixture.databaseFingerprint()
        let validator = LocalFileIntakeValidator(hooks: .init(afterInitialSnapshot: {
            try Data("changed".utf8).write(to: source, options: .atomic)
        }))
        let mutationService = fixture.makeService(validator: validator)

        #expect(throws: JournalMediaIntakeError.self) {
            try mutationService.ingest(.init(
                sourceURL: source,
                sourceID: "mutation",
                kind: .audio,
                capturedAt: Date(timeIntervalSince1970: 1)
            ))
        }
        #expect(try fixture.filesystemFingerprint() == filesystemBefore)
        #expect(try fixture.databaseFingerprint() == databaseBefore)

        try Data("stable".utf8).write(to: source, options: .atomic)
        let failingIngestion = fixture.makeIngestion(hooks: .init(beforeDatabasePersist: { _ in
            throw JournalMediaInjectedFailure.database
        }))
        let persistenceService = fixture.makeService(ingestionService: failingIngestion)
        let filesystemBeforePersistence = try fixture.filesystemFingerprint()
        let databaseBeforePersistence = try fixture.databaseFingerprint()
        #expect(throws: JournalMediaIntakeError.self) {
            try persistenceService.ingest(.init(
                sourceURL: source,
                sourceID: "db-failure",
                kind: .audio,
                capturedAt: Date(timeIntervalSince1970: 2)
            ))
        }
        #expect(try fixture.filesystemFingerprint() == filesystemBeforePersistence)
        #expect(try fixture.databaseFingerprint() == databaseBeforePersistence)
        #expect(try fixture.vaultFileCount() == 0)
    }

    @Test("source-card finalization failure rolls back original row file and directories")
    func sourceCardFailureRollback() throws {
        let fixture = try JournalMediaFixture()
        defer { fixture.cleanup() }
        let source = try fixture.write("photo.png", JournalMediaFixture.pngData)
        let filesystemBefore = try fixture.filesystemFingerprint()
        let databaseBefore = try fixture.databaseFingerprint()

        #expect(throws: JournalMediaIntakeError.self) {
            try fixture.makeService().ingest(.init(
                sourceURL: source,
                sourceID: "source-card-failure",
                kind: .photo,
                capturedAt: Date(timeIntervalSince1970: 2.5)
            )) { _ in
                throw JournalMediaInjectedFailure.sourceCard
            }
        }
        #expect(try fixture.filesystemFingerprint() == filesystemBefore)
        #expect(try fixture.databaseFingerprint() == databaseBefore)
        #expect(try fixture.vaultFileCount() == 0)
    }

    @Test("caller security scope balances on success and failure")
    func securityScopeBalances() throws {
        let fixture = try JournalMediaFixture()
        defer { fixture.cleanup() }
        let source = try fixture.write("voice.m4a", Data("voice".utf8))
        let tracker = JournalMediaScopeTracker()
        let validator = LocalFileIntakeValidator(hooks: .init(
            startAccessingSecurityScopedResource: tracker.start,
            stopAccessingSecurityScopedResource: tracker.stop,
            beforeFileRead: tracker.read
        ))
        let service = fixture.makeService(validator: validator)
        _ = try service.ingest(.init(
            sourceURL: source,
            sourceID: "scope-success",
            kind: .audio,
            capturedAt: Date(timeIntervalSince1970: 3)
        ))
        #expect(tracker.isBalanced)
        #expect(tracker.active.isEmpty)
        #expect(tracker.reads.allSatisfy { $0.wasActive })

        tracker.failReads = true
        #expect(throws: JournalMediaIntakeError.self) {
            try service.ingest(.init(
                sourceURL: source,
                sourceID: "scope-failure",
                kind: .audio,
                capturedAt: Date(timeIntervalSince1970: 4)
            ))
        }
        #expect(tracker.isBalanced)
        #expect(tracker.active.isEmpty)
    }

    @Test("retry and physical reopen reuse one immutable canonical original")
    func retryAndReopenReuseIdentity() throws {
        let fixture = try JournalMediaFixture()
        defer { fixture.cleanup() }
        let bytes = Data("reopen original".utf8)
        let source = try fixture.write("voice.ogg", bytes)
        let request = JournalMediaIntakeRequest(
            sourceURL: source,
            sourceID: "discord:message:9:voice",
            kind: .audio,
            capturedAt: Date(timeIntervalSince1970: 5)
        )
        let first = try fixture.makeService().ingest(request)
        let retry = try fixture.makeService().ingest(request)
        #expect(retry.file == first.file)
        #expect(retry.wasReused)
        #expect(try fixture.vaultFileCount() == 1)

        fixture.database.close()
        let reopened = CiderDatabase()
        try reopened.open(at: fixture.databaseURL)
        defer { reopened.close() }
        let reopenedService = fixture.makeService(database: reopened)
        let afterReopen = try reopenedService.ingest(request)
        #expect(afterReopen.file == first.file)
        #expect(afterReopen.sourceCardID == first.sourceCardID)
        #expect(afterReopen.wasReused)
        #expect(try Data(contentsOf: fixture.vaultRoot.appendingPathComponent(first.file.relativePath)) == bytes)
    }

    @Test("complete long source identities remain distinct while public identity stays bounded")
    func completeLongSourceIdentityDrivesStableIdentity() async throws {
        let fixture = try JournalMediaFixture()
        defer { fixture.cleanup() }
        let source = try fixture.write("voice.m4a", Data("same canonical bytes".utf8))
        let prefix = String(repeating: "private-transport-identity-", count: 12)
        #expect(prefix.count > 256)
        let firstRequest = JournalMediaIntakeRequest(
            sourceURL: source,
            sourceID: prefix + "suffix-a",
            kind: .audio,
            capturedAt: Date(timeIntervalSince1970: 5.1)
        )
        let secondRequest = JournalMediaIntakeRequest(
            sourceURL: source,
            sourceID: prefix + "suffix-b",
            kind: .audio,
            capturedAt: Date(timeIntervalSince1970: 5.1)
        )

        let transcription = JournalMediaTranscriptionFake()
        let service = fixture.makeService(transcriptionService: transcription)
        let first = try service.ingest(firstRequest)
        let second = try service.ingest(secondRequest)
        #expect(first.file.id != second.file.id)
        #expect(first.sourceCardID != second.sourceCardID)
        #expect(first.sourceID != second.sourceID)
        #expect(first.sourceID.count <= 256)
        #expect(second.sourceID.count <= 256)
        #expect(first.file.relativePath != second.file.relativePath)
        #expect(!first.file.relativePath.contains("suffix-a"))
        #expect(!second.file.relativePath.contains("suffix-b"))
        #expect(!first.sourceID.contains("suffix-a"))
        #expect(!second.sourceID.contains("suffix-b"))

        _ = await service.transcribeStoredAudio(first)
        _ = await service.transcribeStoredAudio(second)
        #expect(transcription.requests.map(\.source.sourceID) == [first.sourceID, second.sourceID])
        #expect(transcription.requests[0].source.sourceID != transcription.requests[1].source.sourceID)

        let firstRetry = try service.ingest(firstRequest)
        let secondRetry = try service.ingest(secondRequest)
        #expect(firstRetry.file == first.file)
        #expect(secondRetry.file == second.file)
        #expect(firstRetry.sourceCardID == first.sourceCardID)
        #expect(secondRetry.sourceCardID == second.sourceCardID)
        #expect(firstRetry.sourceID == first.sourceID)
        #expect(secondRetry.sourceID == second.sourceID)
        #expect(try fixture.vaultFileCount() == 2)

        fixture.database.close()
        let reopened = CiderDatabase()
        try reopened.open(at: fixture.databaseURL)
        defer { reopened.close() }
        let reopenedTranscription = JournalMediaTranscriptionFake()
        let reopenedService = fixture.makeService(database: reopened, transcriptionService: reopenedTranscription)
        let firstAfterReopen = try reopenedService.ingest(firstRequest)
        let secondAfterReopen = try reopenedService.ingest(secondRequest)
        #expect(firstAfterReopen.sourceID == first.sourceID)
        #expect(secondAfterReopen.sourceID == second.sourceID)
        _ = await reopenedService.transcribeStoredAudio(firstAfterReopen)
        _ = await reopenedService.transcribeStoredAudio(secondAfterReopen)
        #expect(reopenedTranscription.requests.map(\.source.sourceID) == [first.sourceID, second.sourceID])
        let count = try reopened.prepare("SELECT COUNT(*) FROM items WHERE type = 'vaultFile';")
        try count.step()
        #expect(count.int(at: 0) == 2)
    }

    @Test("stored canonical audio is transcribed read-only without re-ingestion")
    func canonicalAudioTranscriptionIsReadOnly() async throws {
        let fixture = try JournalMediaFixture()
        defer { fixture.cleanup() }
        let bytes = Data("immutable audio".utf8)
        let source = try fixture.write("voice.m4a", bytes)
        let transcription = JournalMediaTranscriptionFake()
        let service = fixture.makeService(transcriptionService: transcription)
        let original = try service.ingest(.init(
            sourceURL: source,
            sourceID: "journal:voice:read-only",
            kind: .audio,
            capturedAt: Date(timeIntervalSince1970: 6)
        ))
        let before = try fixture.filesystemFingerprint()
        let databaseBefore = try fixture.databaseFingerprint()

        let result = await service.transcribeStoredAudio(original)
        let transcript = try #require(result.success)
        #expect(transcript.text == "derived transcript")
        #expect(transcription.requests.count == 1)
        #expect(transcription.requests[0].fileURL != fixture.vaultRoot.appendingPathComponent(original.file.relativePath))
        #expect(transcription.requests[0].fileURL.pathExtension == (original.file.relativePath as NSString).pathExtension)
        #expect(!FileManager.default.fileExists(atPath: transcription.requests[0].fileURL.path))
        #expect(transcription.requests[0].source.sourceID == original.sourceID)
        #expect(transcription.requests[0].source.retention == .preserveOriginal)
        #expect(try fixture.filesystemFingerprint() == before)
        #expect(try fixture.databaseFingerprint() == databaseBefore)
        #expect(try fixture.vaultFileCount() == 1)
        #expect(try Data(contentsOf: fixture.vaultRoot.appendingPathComponent(original.file.relativePath)) == bytes)
        #expect(!FileManager.default.fileExists(atPath: fixture.transcriptionWorkingRoot.path))
    }

    @Test("malicious transcription provider cannot mutate the canonical original and staging is removed")
    func maliciousProviderCannotMutateCanonicalOriginal() async throws {
        let fixture = try JournalMediaFixture()
        defer { fixture.cleanup() }
        let bytes = Data("immutable canonical audio".utf8)
        let source = try fixture.write("voice.m4a", bytes)
        let transcription = JournalMediaMutatingTranscriptionFake()
        let service = fixture.makeService(transcriptionService: transcription)
        let original = try service.ingest(.init(
            sourceURL: source,
            sourceID: "journal:voice:malicious-provider",
            kind: .audio,
            capturedAt: Date(timeIntervalSince1970: 6.1)
        ))
        let canonicalURL = fixture.vaultRoot.appendingPathComponent(original.file.relativePath)
        let filesystemBefore = try fixture.filesystemFingerprint()
        let databaseBefore = try fixture.databaseFingerprint()

        _ = await service.transcribeStoredAudio(original)

        #expect(transcription.didOverwriteDeleteAndReplace)
        #expect(transcription.inputURL != canonicalURL)
        #expect(try Data(contentsOf: canonicalURL) == bytes)
        #expect(LocalFileIntakeValidator.sha256(try Data(contentsOf: canonicalURL)) == original.sha256)
        #expect(try fixture.filesystemFingerprint() == filesystemBefore)
        #expect(try fixture.databaseFingerprint() == databaseBefore)
        #expect(try fixture.vaultFileCount() == 1)
        #expect(!FileManager.default.fileExists(atPath: fixture.transcriptionWorkingRoot.path))
    }

    @Test("transcription cancellation preserves canonical original and removes staging deterministically")
    func transcriptionCancellationCleansStaging() async throws {
        let fixture = try JournalMediaFixture()
        defer { fixture.cleanup() }
        let bytes = Data("cancel-safe canonical audio".utf8)
        let source = try fixture.write("voice.m4a", bytes)
        let transcription = JournalMediaCancellableTranscriptionFake()
        let service = fixture.makeService(transcriptionService: transcription)
        let original = try service.ingest(.init(
            sourceURL: source,
            sourceID: "journal:voice:cancel",
            kind: .audio,
            capturedAt: Date(timeIntervalSince1970: 6.15)
        ))
        let canonicalURL = fixture.vaultRoot.appendingPathComponent(original.file.relativePath)
        let filesystemBefore = try fixture.filesystemFingerprint()
        let databaseBefore = try fixture.databaseFingerprint()

        let task = Task { @MainActor in await service.transcribeStoredAudio(original) }
        await transcription.waitUntilStarted()
        #expect(FileManager.default.fileExists(atPath: transcription.inputURL?.path ?? ""))
        service.cancelTranscription()
        let result = await task.value

        guard case .failure(let failure) = result else {
            Issue.record("Expected cancellation")
            return
        }
        #expect(failure.code == .cancelled)
        #expect(try Data(contentsOf: canonicalURL) == bytes)
        #expect(try fixture.filesystemFingerprint() == filesystemBefore)
        #expect(try fixture.databaseFingerprint() == databaseBefore)
        #expect(!FileManager.default.fileExists(atPath: fixture.transcriptionWorkingRoot.path))
    }

    @Test("stored original traversal is rejected before any outside read or provider call")
    func storedOriginalTraversalIsRejected() async throws {
        let fixture = try JournalMediaFixture()
        defer { fixture.cleanup() }
        let source = try fixture.write("voice.m4a", Data("inside".utf8))
        let outside = fixture.root.appendingPathComponent("outside.m4a")
        try Data("outside secret".utf8).write(to: outside, options: .atomic)
        let transcription = JournalMediaTranscriptionFake()
        let service = fixture.makeService(transcriptionService: transcription)
        let original = try service.ingest(.init(
            sourceURL: source,
            sourceID: "journal:voice:traversal",
            kind: .audio,
            capturedAt: Date(timeIntervalSince1970: 6.2)
        ))
        var escapedFile = original.file
        escapedFile.relativePath = "../outside.m4a"
        let escaped = JournalStoredOriginal(
            file: escapedFile,
            sourceID: original.sourceID,
            sourceCardID: original.sourceCardID,
            capturedAt: original.capturedAt,
            kind: original.kind,
            byteSize: Int64(Data("outside secret".utf8).count),
            sha256: LocalFileIntakeValidator.sha256(Data("outside secret".utf8)),
            retention: original.retention,
            wasReused: original.wasReused
        )

        let result = await service.transcribeStoredAudio(escaped)
        guard case .failure(let failure) = result else {
            Issue.record("Expected traversal to fail")
            return
        }
        #expect(failure.code == .sourceUnreadable)
        #expect(transcription.requests.isEmpty)
        #expect(try Data(contentsOf: outside) == Data("outside secret".utf8))
        #expect(!FileManager.default.fileExists(atPath: fixture.transcriptionWorkingRoot.path))
    }

    @Test("photo payloads must decode and generic media remains explicitly byte bounded")
    func photoPayloadDecodeAndGenericBound() throws {
        let fixture = try JournalMediaFixture()
        defer { fixture.cleanup() }
        let corruptPhoto = try fixture.write("corrupt.png", Data("not an image".utf8))
        let before = try fixture.filesystemFingerprint()
        let databaseBefore = try fixture.databaseFingerprint()

        #expect(throws: JournalMediaIntakeError.self) {
            try fixture.makeService().ingest(.init(
                sourceURL: corruptPhoto,
                sourceID: "journal:photo:corrupt",
                kind: .photo,
                capturedAt: Date(timeIntervalSince1970: 6.3)
            ))
        }
        #expect(try fixture.filesystemFingerprint() == before)
        #expect(try fixture.databaseFingerprint() == databaseBefore)

        let generic = try fixture.write("clip.mp4", Data(repeating: 0x31, count: 9))
        #expect(throws: JournalMediaIntakeError.self) {
            try fixture.makeService(policy: .init(maximumByteSize: 8)).ingest(.init(
                sourceURL: generic,
                sourceID: "journal:media:bounded",
                kind: .media,
                capturedAt: Date(timeIntervalSince1970: 6.4)
            ))
        }
        #expect(try fixture.vaultFileCount() == 0)
    }

    @Test("Journal type size and duration policy is local and does not inherit Chat limits")
    func policyDoesNotLeakChatLimits() throws {
        let fixture = try JournalMediaFixture()
        defer { fixture.cleanup() }
        let bytes = Data(repeating: 0x42, count: Int(AgentRoomsAttachmentService.maximumImageByteSize + 1))
        let source = try fixture.write("long.m4a", bytes)
        let service = fixture.makeService(policy: .init(maximumByteSize: nil, maximumAudioDuration: 30)) { _ in 31 }

        do {
            _ = try service.ingest(.init(
                sourceURL: source,
                sourceID: "duration-policy",
                kind: .audio,
                capturedAt: Date(timeIntervalSince1970: 7)
            ))
            Issue.record("Expected Journal duration policy to reject the source")
        } catch let error as JournalMediaIntakeError {
            #expect(error.code == .durationExceeded)
            #expect(error.localizedDescription.count <= 240)
            #expect(!error.localizedDescription.contains(fixture.root.path))
        }
        #expect(try fixture.vaultFileCount() == 0)

        let unbounded = fixture.makeService(policy: .init(maximumByteSize: nil, maximumAudioDuration: nil))
        let accepted = try unbounded.ingest(.init(
            sourceURL: source,
            sourceID: "journal-large-audio",
            kind: .audio,
            capturedAt: Date(timeIntervalSince1970: 8)
        ))
        #expect(accepted.byteSize == Int64(bytes.count))
    }
}

private enum JournalMediaInjectedFailure: Error { case database, sourceCard }

private final class JournalMediaScopeTracker {
    struct Read { let wasActive: Bool }
    var active: [URL: Int] = [:]
    var starts: [URL] = []
    var stops: [URL] = []
    var reads: [Read] = []
    var failReads = false
    var isBalanced: Bool {
        Dictionary(grouping: starts, by: { $0 }).mapValues(\.count)
            == Dictionary(grouping: stops, by: { $0 }).mapValues(\.count)
    }
    func start(_ url: URL) -> Bool { starts.append(url); active[url, default: 0] += 1; return true }
    func stop(_ url: URL) { stops.append(url); active[url, default: 0] -= 1; if active[url] == 0 { active.removeValue(forKey: url) } }
    func read(_ accessURL: URL, _: URL) throws {
        reads.append(.init(wasActive: (active[accessURL] ?? 0) > 0))
        if failReads { throw JournalMediaInjectedFailure.database }
    }
}

@MainActor
private final class JournalMediaTranscriptionFake: CiderTranscriptionServicing {
    let provider = TranscriptionProviderMetadata(id: "journal-test", adapterVersion: "1", execution: .onDevice, supportedInputs: [.storedAudioFile], allowsNetworkFallback: false)
    private(set) var requests: [StoredAudioTranscriptionRequest] = []
    func authorization(for input: TranscriptionInputKind) -> TranscriptionAuthorization { .authorized }
    func readiness(for input: TranscriptionInputKind) -> TranscriptionReadiness { .ready }
    func requestAuthorization(for input: TranscriptionInputKind) async -> TranscriptionAuthorization { .authorized }
    func startLive(_ request: LiveTranscriptionRequest, onEvent: @escaping @MainActor @Sendable (TranscriptionEvent) -> Void) throws {}
    func stopLive() {}
    func cancelLive() {}
    func cancelStoredAudio() {}
    func transcribeStoredAudio(_ request: StoredAudioTranscriptionRequest) async -> TranscriptionResult {
        requests.append(request)
        return .success(.init(text: "derived transcript", isFinal: true, provenance: .init(
            provider: provider,
            source: request.source,
            locale: .init(identifier: "en_US"),
            timing: .init(startedAt: Date(timeIntervalSince1970: 1), completedAt: Date(timeIntervalSince1970: 2), audioDuration: 1)
        )))
    }
}

@MainActor
private final class JournalMediaMutatingTranscriptionFake: CiderTranscriptionServicing {
    let provider = TranscriptionProviderMetadata(id: "journal-malicious-test", adapterVersion: "1", execution: .localProcess, supportedInputs: [.storedAudioFile], allowsNetworkFallback: false)
    private(set) var inputURL: URL?
    private(set) var didOverwriteDeleteAndReplace = false
    func authorization(for input: TranscriptionInputKind) -> TranscriptionAuthorization { .authorized }
    func readiness(for input: TranscriptionInputKind) -> TranscriptionReadiness { .ready }
    func requestAuthorization(for input: TranscriptionInputKind) async -> TranscriptionAuthorization { .authorized }
    func startLive(_ request: LiveTranscriptionRequest, onEvent: @escaping @MainActor @Sendable (TranscriptionEvent) -> Void) throws {}
    func stopLive() {}
    func cancelLive() {}
    func cancelStoredAudio() {}
    func transcribeStoredAudio(_ request: StoredAudioTranscriptionRequest) async -> TranscriptionResult {
        inputURL = request.fileURL
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: request.fileURL.path)
        try? Data("overwritten".utf8).write(to: request.fileURL, options: .atomic)
        try? FileManager.default.removeItem(at: request.fileURL)
        try? Data("replacement".utf8).write(to: request.fileURL, options: .atomic)
        didOverwriteDeleteAndReplace = true
        return .failure(.init(code: .recognitionFailed, message: "malicious fake completed"))
    }
}

@MainActor
private final class JournalMediaCancellableTranscriptionFake: CiderTranscriptionServicing {
    let provider = TranscriptionProviderMetadata(id: "journal-cancel-test", adapterVersion: "1", execution: .onDevice, supportedInputs: [.storedAudioFile], allowsNetworkFallback: false)
    private(set) var inputURL: URL?
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var resultContinuation: CheckedContinuation<TranscriptionResult, Never>?
    func authorization(for input: TranscriptionInputKind) -> TranscriptionAuthorization { .authorized }
    func readiness(for input: TranscriptionInputKind) -> TranscriptionReadiness { .ready }
    func requestAuthorization(for input: TranscriptionInputKind) async -> TranscriptionAuthorization { .authorized }
    func startLive(_ request: LiveTranscriptionRequest, onEvent: @escaping @MainActor @Sendable (TranscriptionEvent) -> Void) throws {}
    func stopLive() {}
    func cancelLive() {}
    func transcribeStoredAudio(_ request: StoredAudioTranscriptionRequest) async -> TranscriptionResult {
        inputURL = request.fileURL
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
        }
    }
    func cancelStoredAudio() {
        resultContinuation?.resume(returning: .failure(.init(code: .cancelled, message: "cancelled")))
        resultContinuation = nil
    }
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }
}

@MainActor
private final class JournalMediaFixture {
    static let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("cider-journal-media-\(UUID().uuidString)", isDirectory: true)
    lazy var vaultRoot = root.appendingPathComponent("vault", isDirectory: true)
    lazy var databaseURL = root.appendingPathComponent("journal.sqlite")
    lazy var transcriptionWorkingRoot = root.appendingPathComponent("transcription-staging", isDirectory: true)
    let database = CiderDatabase()
    init() throws { try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true); try database.open(at: databaseURL) }
    func write(_ name: String, _ data: Data) throws -> URL { let url = root.appendingPathComponent(name); try data.write(to: url, options: .atomic); return url }
    func makeIngestion(database: CiderDatabase? = nil, validator: LocalFileIntakeValidator = .init(), hooks: VaultFileIngestionService.Hooks = .init()) -> VaultFileIngestionService {
        let db = database ?? self.database
        return VaultFileIngestionService(database: db, vaultRoot: vaultRoot, storage: VaultFileStorage(database: db), validator: validator, hooks: hooks)
    }
    func makeService(
        database: CiderDatabase? = nil,
        validator: LocalFileIntakeValidator = .init(),
        ingestionService: VaultFileIngestionService? = nil,
        transcriptionService: (any CiderTranscriptionServicing)? = nil,
        policy: JournalMediaIntakePolicy = .init(),
        duration: @escaping (URL) throws -> TimeInterval? = { _ in nil }
    ) -> JournalMediaIntakeService {
        let db = database ?? self.database
        return JournalMediaIntakeService(database: db, vaultRoot: vaultRoot, validator: validator, ingestionService: ingestionService ?? makeIngestion(database: db, validator: validator), transcriptionService: transcriptionService, policy: policy, audioDuration: duration, transcriptionWorkingRoot: transcriptionWorkingRoot)
    }
    func vaultFileCount() throws -> Int { let s = try database.prepare("SELECT COUNT(*) FROM items WHERE type = 'vaultFile';"); try s.step(); return s.int(at: 0) }
    func filesystemFingerprint() throws -> [String] { try FileManager.default.subpathsOfDirectory(atPath: vaultRoot.path).sorted().map { path in let url = vaultRoot.appendingPathComponent(path); let regular = (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true; return regular ? "file:\(path):\(LocalFileIntakeValidator.sha256(try Data(contentsOf: url)))" : "directory:\(path)" } }
    func databaseFingerprint() throws -> [String] { let s = try database.prepare("SELECT id, type, COALESCE(relative_path, '') FROM items ORDER BY id;"); var rows: [String] = []; while try s.step() { rows.append("\(s.string(at: 0))|\(s.string(at: 1))|\(s.string(at: 2))") }; return rows }
    func cleanup() { database.close(); try? FileManager.default.removeItem(at: root) }
}

private extension TranscriptionResult {
    var success: TranscriptionTranscript? { guard case .success(let value) = self else { return nil }; return value }
}
