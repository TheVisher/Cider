import Foundation
import Testing
@testable import Cider

@Suite("Journal Voice Capture Session Controller Tests", .serialized)
@MainActor
struct JournalVoiceCaptureSessionControllerTests {
    @Test("production Journal detail composes one accessible push-to-talk control")
    func productionJournalComposition() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let panel = try String(
            contentsOf: root.appendingPathComponent("Sources/Cider/Views/CiderPanelView.swift"),
            encoding: .utf8
        )
        let detail = try String(
            contentsOf: root.appendingPathComponent("Sources/Cider/Views/CiderPanelView+DetailViews.swift"),
            encoding: .utf8
        )
        let journal = try String(
            contentsOf: root.appendingPathComponent("Sources/Cider/Views/Journal/JournalLibraryViews.swift"),
            encoding: .utf8
        )

        #expect(panel.contains("@StateObject var journalVoiceCaptureSession = JournalVoiceCaptureSessionController.production()"))
        #expect(detail.contains("voiceCaptureSession: journalVoiceCaptureSession"))
        #expect(journal.contains("JournalVoiceCaptureControl("))
        #expect(journal.contains("Record a voice note for"))
        #expect(journal.contains("Stop and save Journal voice note"))
        #expect(journal.contains("Cancel Journal voice note"))
        #expect(journal.contains("NSApplication.didResignActiveNotification"))
    }

    @Test("permissions are requested only after Record and success cleans the working audio")
    func permissionTimingStateTransitionsAndCleanup() async throws {
        let fixture = try SessionFixture(permission: .notDetermined)
        defer { fixture.cleanup() }

        #expect(fixture.authorizer.stateCount == 0)
        #expect(fixture.authorizer.requestCount == 0)
        #expect(fixture.recorder.startCount == 0)

        await fixture.controller.startRecording(journalDate: "2026-07-15")
        #expect(fixture.authorizer.requestCount == 1)
        #expect(fixture.recorder.startCount == 1)
        guard case .recording = fixture.controller.state else {
            Issue.record("Expected recording state")
            return
        }
        let workingURL = try #require(fixture.recorder.fileURL)
        #expect(FileManager.default.fileExists(atPath: workingURL.path))

        fixture.recorder.elapsedTime = 7.8
        fixture.controller.refreshRecordingBounds()
        #expect(fixture.controller.state == .recording(elapsed: 7.8))
        await fixture.controller.stopRecording()

        guard case .succeeded(let receipt) = fixture.controller.state else {
            Issue.record("Expected success state")
            return
        }
        #expect(receipt.journalDate == "2026-07-15")
        #expect(receipt.time == "18:24")
        #expect(receipt.providerID == "fixture-journal-provider")
        #expect(fixture.capture.requests.count == 1)
        #expect(fixture.recorder.stopCount == 1)
        #expect(!FileManager.default.fileExists(atPath: workingURL.path))
        let request = try #require(fixture.capture.requests.first)
        #expect(request.sourceID.hasPrefix("cider-journal-voice:"))
        #expect(request.idempotencyKey.hasPrefix("cider-journal-voice-capture:"))
        #expect(request.sourceContext?.surface == "macos-journal")
        #expect(request.sourceContext?.channel == "journal-day")
        #expect(request.sourceContext?.messageID != nil)
        #expect(!String(describing: fixture.controller.state).contains(fixture.root.path))
    }

    @Test("permission composition requests microphone and selected-provider authorization only on demand")
    func selectedProviderPermissionComposition() async {
        let microphone = FakeMicrophoneAuthorization(.notDetermined)
        let provider = PermissionProviderFake(authorization: .notDetermined)
        let request = CiderStoredAudioTranscriptionProviderRequest(providerID: provider.provider.id)
        let authorizer = JournalVoiceCaptureAuthorizationService(
            microphone: microphone,
            providerResolver: { requested in
                .success(.init(
                    requestedProviderID: requested.providerID,
                    service: provider,
                    usedSharedDefault: false
                ))
            }
        )

        #expect(authorizer.state(for: request) == .notDetermined)
        #expect(microphone.requestCount == 0)
        #expect(provider.requestCount == 0)
        #expect(await authorizer.requestAuthorization(for: request) == .ready)
        #expect(microphone.requestCount == 1)
        #expect(provider.requestCount == 1)

        let unavailableMicrophone = FakeMicrophoneAuthorization(.notDetermined)
        let unavailable = JournalVoiceCaptureAuthorizationService(
            microphone: unavailableMicrophone,
            providerResolver: { _ in
                .failure(.init(code: .unsupportedInput, message: "unsupported fixture"))
            }
        )
        #expect(await unavailable.requestAuthorization(for: .init(providerID: "unknown")) == .unavailable)
        #expect(unavailableMicrophone.requestCount == 0)
    }

    @Test("denied permission is truthful recoverable and never starts recording")
    func deniedPermissionIsRecoverable() async throws {
        let fixture = try SessionFixture(permission: .denied)
        defer { fixture.cleanup() }

        await fixture.controller.startRecording(journalDate: "2026-07-15")
        #expect(fixture.controller.state == .failed(.permissionDenied))
        #expect(fixture.authorizer.requestCount == 0)
        #expect(fixture.recorder.startCount == 0)
        #expect(fixture.capture.requests.isEmpty)

        fixture.authorizer.permission = .ready
        fixture.controller.reset()
        await fixture.controller.startRecording(journalDate: "2026-07-15")
        guard case .recording = fixture.controller.state else {
            Issue.record("Expected recovery after permission becomes ready")
            return
        }
        fixture.controller.cancel()
    }

    @Test("cancel during recording removes temporary audio and makes no capture")
    func cancelRecordingCleansUp() async throws {
        let fixture = try SessionFixture()
        defer { fixture.cleanup() }
        await fixture.controller.startRecording(journalDate: "2026-07-15")
        let workingURL = try #require(fixture.recorder.fileURL)

        fixture.controller.cancel()

        #expect(fixture.controller.state == .cancelled)
        #expect(fixture.recorder.cancelCount >= 1)
        #expect(fixture.capture.requests.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: workingURL.path))
    }

    @Test("recorder failure callback cleans temporary audio and commits nothing")
    func recorderFailureCallbackCleansUp() async throws {
        let fixture = try SessionFixture()
        defer { fixture.cleanup() }
        await fixture.controller.startRecording(journalDate: "2026-07-15")
        let workingURL = try #require(fixture.recorder.fileURL)

        fixture.recorder.finishAutomatically(success: false)

        #expect(fixture.controller.state == .failed(.recorderUnavailable))
        #expect(fixture.capture.requests.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: workingURL.path))
    }

    @Test("provider or atomic capture failure removes temporary audio and leaks no path")
    func captureFailureCleansUpWithoutPathLeak() async throws {
        let fixture = try SessionFixture(captureMode: .failure)
        defer { fixture.cleanup() }
        await fixture.controller.startRecording(journalDate: "2026-07-15")
        let workingURL = try #require(fixture.recorder.fileURL)

        await fixture.controller.stopRecording()

        #expect(fixture.controller.state == .failed(.captureFailed))
        #expect(fixture.capture.requests.count == 1)
        #expect(!FileManager.default.fileExists(atPath: workingURL.path))
        #expect(!String(describing: fixture.controller.state).contains(fixture.root.path))
    }

    @Test("duplicate start stop and save attempts produce one recording and one receipt")
    func duplicateOperationsAreBounded() async throws {
        let fixture = try SessionFixture(captureMode: .delayedSuccess)
        defer { fixture.cleanup() }
        await fixture.controller.startRecording(journalDate: "2026-07-15")
        await fixture.controller.startRecording(journalDate: "2026-07-15")
        #expect(fixture.recorder.startCount == 1)

        let first = Task { @MainActor in await fixture.controller.stopRecording() }
        await Task.yield()
        let second = Task { @MainActor in await fixture.controller.stopRecording() }
        await first.value
        await second.value

        #expect(fixture.recorder.stopCount == 1)
        #expect(fixture.capture.requests.count == 1)
        guard case .succeeded = fixture.controller.state else {
            Issue.record("Expected one terminal success")
            return
        }
    }

    @Test("cancel during transcription cancels work and ignores a late terminal result")
    func cancelDuringTranscription() async throws {
        let fixture = try SessionFixture(captureMode: .waitForCancellation)
        defer { fixture.cleanup() }
        await fixture.controller.startRecording(journalDate: "2026-07-15")
        let workingURL = try #require(fixture.recorder.fileURL)

        let stop = Task { @MainActor in await fixture.controller.stopRecording() }
        while fixture.capture.requests.isEmpty { await Task.yield() }
        fixture.controller.cancel()
        await stop.value

        #expect(fixture.controller.state == .cancelled)
        #expect(fixture.capture.observedCancellation)
        #expect(fixture.controller.lastReceipt == nil)
        #expect(!FileManager.default.fileExists(atPath: workingURL.path))
    }

    @Test("working byte limit fails closed and removes the temporary file")
    func workingByteLimitFailsClosed() async throws {
        let fixture = try SessionFixture()
        defer { fixture.cleanup() }
        await fixture.controller.startRecording(journalDate: "2026-07-15")
        let workingURL = try #require(fixture.recorder.fileURL)
        fixture.recorder.byteSize = JournalVoiceCaptureSessionController.maximumWorkingBytes + 1

        fixture.controller.refreshRecordingBounds()

        #expect(fixture.controller.state == .failed(.recordingLimitExceeded))
        #expect(fixture.capture.requests.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: workingURL.path))
    }

    @Test("disposable non-microphone smoke reaches the real coordinator and native source-card readback")
    func disposableRealCoordinatorAcceptanceSmoke() async throws {
        let fixture = try RealCoordinatorFixture()
        defer { fixture.cleanup() }
        let controller = fixture.controller()

        await controller.startRecording(journalDate: "2026-07-15")
        let workingURL = try #require(fixture.recorder.fileURL)
        await controller.stopRecording()

        guard case .succeeded(let publicReceipt) = controller.state else {
            Issue.record("Expected real coordinator acceptance success")
            return
        }
        #expect(!publicReceipt.wasReused)
        #expect(!FileManager.default.fileExists(atPath: workingURL.path))
        #expect(try fixture.count("capture_events") == 1)
        #expect(try fixture.count("capture_attachments") == 1)
        #expect(try fixture.count("items", where: "type = 'note'") == 1)
        #expect(try fixture.count("items", where: "type = 'vaultFile'") == 1)
        let receipt = try #require(controller.lastReceipt)
        let noteID = try #require(UUID(uuidString: receipt.atomicReceipt.item.id))
        let cards = try JournalMediaSourceCardReadService(
            database: fixture.database,
            vaultRoot: fixture.vault
        ).sourceCards(noteIDs: [noteID])
        let card = try #require(cards.first)
        #expect(card.kind == .audio)
        #expect(card.transcription?.text == SessionStoredProvider.transcriptText)
        #expect(card.isOriginalAvailable)
        #expect(try Data(contentsOf: fixture.vault.appendingPathComponent(card.relativePath)) == FakeJournalVoiceRecorder.syntheticBytes)
    }

    @Test("real atomic writer failure leaves zero Journal mutation and no working file")
    func disposableAtomicWriterFailureRollsBack() async throws {
        let fixture = try RealCoordinatorFixture(failAtomicWriter: true)
        defer { fixture.cleanup() }
        let controller = fixture.controller()
        await controller.startRecording(journalDate: "2026-07-15")
        let workingURL = try #require(fixture.recorder.fileURL)

        await controller.stopRecording()

        #expect(controller.state == .failed(.captureFailed))
        #expect(!FileManager.default.fileExists(atPath: workingURL.path))
        #expect(try fixture.count("capture_events") == 0)
        #expect(try fixture.count("capture_attachments") == 0)
        #expect(try fixture.count("items") == 0)
        #expect(fixture.notes.notes.isEmpty)
    }
}

@MainActor
private final class FakeJournalVoiceAuthorizer: JournalVoiceCaptureAuthorizing {
    var permission: JournalVoiceCapturePermissionState
    private(set) var stateCount = 0
    private(set) var requestCount = 0

    init(_ permission: JournalVoiceCapturePermissionState) {
        self.permission = permission
    }

    func state(for provider: CiderStoredAudioTranscriptionProviderRequest) -> JournalVoiceCapturePermissionState {
        stateCount += 1
        return permission
    }

    func requestAuthorization(
        for provider: CiderStoredAudioTranscriptionProviderRequest
    ) async -> JournalVoiceCapturePermissionState {
        requestCount += 1
        permission = .ready
        return permission
    }
}

@MainActor
private final class FakeMicrophoneAuthorization: CiderMicrophoneAuthorizationServicing {
    var value: TranscriptionAuthorization
    private(set) var requestCount = 0

    init(_ value: TranscriptionAuthorization) { self.value = value }

    func authorization() -> TranscriptionAuthorization { value }

    func requestAuthorization() async -> TranscriptionAuthorization {
        requestCount += 1
        value = .authorized
        return value
    }
}

@MainActor
private final class PermissionProviderFake: CiderTranscriptionServicing {
    let provider = TranscriptionProviderMetadata(
        id: "permission-fixture-provider",
        adapterVersion: "test-1",
        execution: .onDevice,
        supportedInputs: [.storedAudioFile],
        allowsNetworkFallback: false
    )
    var value: TranscriptionAuthorization
    private(set) var requestCount = 0

    init(authorization: TranscriptionAuthorization) { value = authorization }
    func authorization(for input: TranscriptionInputKind) -> TranscriptionAuthorization { value }
    func readiness(for input: TranscriptionInputKind) -> TranscriptionReadiness { .ready }
    func requestAuthorization(for input: TranscriptionInputKind) async -> TranscriptionAuthorization {
        requestCount += 1
        value = .authorized
        return value
    }
    func startLive(
        _ request: LiveTranscriptionRequest,
        onEvent: @escaping @MainActor @Sendable (TranscriptionEvent) -> Void
    ) throws { throw TranscriptionFailure(code: .unsupportedInput, message: "Stored audio only.") }
    func stopLive() {}
    func cancelLive() {}
    func transcribeStoredAudio(_ request: StoredAudioTranscriptionRequest) async -> TranscriptionResult {
        .failure(.init(code: .recognitionFailed, message: "Permission test only."))
    }
    func cancelStoredAudio() {}
}

@MainActor
private final class FakeJournalVoiceRecorder: JournalVoiceAudioRecording {
    static let syntheticBytes = Data("generated disposable journal voice audio".utf8)

    var elapsedTime: TimeInterval = 2.5
    var byteSize: Int64 = Int64(syntheticBytes.count)
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var cancelCount = 0
    private(set) var fileURL: URL?
    private var automaticFinish: (@MainActor @Sendable (Bool) -> Void)?

    func start(
        at fileURL: URL,
        maximumDuration: TimeInterval,
        onAutomaticFinish: @escaping @MainActor @Sendable (Bool) -> Void
    ) throws {
        startCount += 1
        self.fileURL = fileURL
        automaticFinish = onAutomaticFinish
        try Self.syntheticBytes.write(to: fileURL, options: .atomic)
    }

    func stop() throws -> JournalVoiceRecordedAudio {
        stopCount += 1
        guard let fileURL else { throw JournalVoiceAudioRecorderError.unavailable }
        return .init(fileURL: fileURL, duration: elapsedTime, byteSize: byteSize)
    }

    func cancel() {
        cancelCount += 1
    }

    func finishAutomatically(success: Bool) {
        automaticFinish?(success)
    }
}

@MainActor
private final class FakeJournalVoiceCapture: JournalStoredVoiceCapturing {
    enum Mode { case success, failure, delayedSuccess, waitForCancellation }

    let mode: Mode
    private(set) var requests: [JournalStoredVoiceCaptureRequest] = []
    private(set) var observedCancellation = false

    init(_ mode: Mode) { self.mode = mode }

    func capture(_ request: JournalStoredVoiceCaptureRequest) async throws -> JournalStoredVoiceCaptureReceipt {
        requests.append(request)
        switch mode {
        case .success:
            return Self.receipt(for: request)
        case .failure:
            throw JournalStoredVoiceCaptureError(.transcriptionFailed, transcriptionFailureCode: .recognitionFailed)
        case .delayedSuccess:
            try await Task.sleep(for: .milliseconds(50))
            return Self.receipt(for: request)
        case .waitForCancellation:
            do {
                try await Task.sleep(for: .seconds(30))
                return Self.receipt(for: request)
            } catch {
                observedCancellation = true
                throw error
            }
        }
    }

    private static func receipt(for request: JournalStoredVoiceCaptureRequest) -> JournalStoredVoiceCaptureReceipt {
        let transcript = TranscriptionTranscript(
            text: SessionStoredProvider.transcriptText,
            isFinal: true,
            provenance: .init(
                provider: SessionStoredProvider.metadata,
                source: .storedAudio(sourceID: request.sourceID, displayName: request.displayTitle),
                locale: .init(identifier: "en_US"),
                timing: .init(startedAt: request.capturedAt, completedAt: request.capturedAt, audioDuration: 2.5)
            )
        )
        return .init(
            atomicReceipt: .init(
                receiptID: "fixture-receipt",
                journalDate: request.journalDate,
                time: "18:24",
                item: .init(type: "note", id: UUID().uuidString, title: "Journal", relativePath: nil),
                textSource: .init(
                    id: "text-source",
                    kind: "text",
                    capturedAt: request.capturedAt,
                    sourceID: request.sourceID,
                    displayTitle: "Voice transcript",
                    rawFilename: nil,
                    mediaItem: nil
                ),
                mediaSources: [],
                captureEventRef: "capture_event:fixture",
                wasReused: false
            ),
            transcription: .init(
                transcript: transcript,
                sourceAudioSHA256: LocalFileIntakeValidator.sha256(FakeJournalVoiceRecorder.syntheticBytes)
            )
        )
    }
}

@MainActor
private final class SessionFixture {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cider-journal-session-\(UUID().uuidString)", isDirectory: true)
    let authorizer: FakeJournalVoiceAuthorizer
    let recorder = FakeJournalVoiceRecorder()
    let capture: FakeJournalVoiceCapture
    let controller: JournalVoiceCaptureSessionController

    init(
        permission: JournalVoiceCapturePermissionState = .ready,
        captureMode: FakeJournalVoiceCapture.Mode = .success
    ) throws {
        authorizer = FakeJournalVoiceAuthorizer(permission)
        capture = FakeJournalVoiceCapture(captureMode)
        let files = JournalVoiceTemporaryFileStore(root: root.appendingPathComponent("working", isDirectory: true))
        controller = JournalVoiceCaptureSessionController(
            authorizer: authorizer,
            recorder: recorder,
            temporaryFiles: files,
            coordinator: capture,
            provider: .init(providerID: "fixture-journal-provider"),
            now: { Date(timeIntervalSince1970: 1_784_165_040) }
        )
    }

    func cleanup() {
        controller.cancel()
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private final class RealCoordinatorFixture {
    enum Injected: Error { case atomicFailure }

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cider-journal-session-real-\(UUID().uuidString)", isDirectory: true)
    lazy var vault = root.appendingPathComponent("vault", isDirectory: true)
    lazy var notesDirectory = vault.appendingPathComponent(".cider/notes", isDirectory: true)
    lazy var databaseURL = root.appendingPathComponent("cider.sqlite")
    let database = CiderDatabase()
    lazy var notes = NotesStorage(database: database, notesDirectoryURL: notesDirectory, vaultRootURL: vault)
    let authorizer = FakeJournalVoiceAuthorizer(.ready)
    let recorder = FakeJournalVoiceRecorder()
    let provider = SessionStoredProvider()
    private let failAtomicWriter: Bool

    init(failAtomicWriter: Bool = false) throws {
        self.failAtomicWriter = failAtomicWriter
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Inbox/Notes"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        try database.open(at: databaseURL)
        notes.loadNotesFromDatabase(database)
    }

    func controller() -> JournalVoiceCaptureSessionController {
        let writer = JournalAtomicCaptureWriter(
            database: database,
            notesStorage: notes,
            vaultRoot: vault,
            hooks: .init(atStage: { [failAtomicWriter] stage in
                if failAtomicWriter, stage == .afterSourceCards { throw Injected.atomicFailure }
            })
        )
        let coordinator = JournalStoredVoiceCaptureCoordinator(
            database: database,
            notesStorage: notes,
            vaultRoot: vault,
            atomicWriter: writer,
            providerResolver: { [provider] request in
                .success(.init(requestedProviderID: request.providerID, service: provider, usedSharedDefault: false))
            }
        )
        return JournalVoiceCaptureSessionController(
            authorizer: authorizer,
            recorder: recorder,
            temporaryFiles: JournalVoiceTemporaryFileStore(root: root.appendingPathComponent("working", isDirectory: true)),
            coordinator: coordinator,
            provider: .init(providerID: provider.provider.id),
            now: { Date(timeIntervalSince1970: 1_784_165_040) }
        )
    }

    func count(_ table: String, where predicate: String? = nil) throws -> Int {
        let statement = try database.prepare("SELECT COUNT(*) FROM \(table)\(predicate.map { " WHERE \($0)" } ?? "");")
        try statement.step()
        return statement.int(at: 0)
    }

    func cleanup() {
        database.close()
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private final class SessionStoredProvider: CiderTranscriptionServicing {
    static let transcriptText = "The generated disposable voice note remembers a calm evening walk."
    static let metadata = TranscriptionProviderMetadata(
        id: "fixture-journal-provider",
        adapterVersion: "session-test-1",
        modelIdentity: "synthetic-fixture",
        execution: .onDevice,
        supportedInputs: [.storedAudioFile],
        supportsSegmentTimestamps: true,
        allowsNetworkFallback: false
    )
    let provider = metadata

    func authorization(for input: TranscriptionInputKind) -> TranscriptionAuthorization { .authorized }
    func readiness(for input: TranscriptionInputKind) -> TranscriptionReadiness { .ready }
    func requestAuthorization(for input: TranscriptionInputKind) async -> TranscriptionAuthorization { .authorized }
    func startLive(
        _ request: LiveTranscriptionRequest,
        onEvent: @escaping @MainActor @Sendable (TranscriptionEvent) -> Void
    ) throws { throw TranscriptionFailure(code: .unsupportedInput, message: "Stored audio only.") }
    func stopLive() {}
    func cancelLive() {}
    func cancelStoredAudio() {}

    func transcribeStoredAudio(_ request: StoredAudioTranscriptionRequest) async -> TranscriptionResult {
        .success(.init(
            text: Self.transcriptText,
            isFinal: true,
            provenance: .init(
                provider: provider,
                source: request.source,
                locale: .init(identifier: "en_US"),
                timing: .init(
                    startedAt: Date(timeIntervalSince1970: 100),
                    completedAt: Date(timeIntervalSince1970: 102),
                    audioDuration: 2.5
                )
            ),
            segments: [
                .init(text: Self.transcriptText, timestamp: 0, duration: 2.5),
            ]
        ))
    }
}
