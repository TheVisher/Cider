import Foundation
import Testing
@testable import Cider

@Suite("Journal Stored Voice Capture Coordinator Tests")
@MainActor
struct JournalStoredVoiceCaptureCoordinatorTests {
    @Test("stored audio becomes one source-backed Journal voice capture with exact provenance")
    func successfulCaptureAndReadback() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let provider = VoiceProviderFake()
        let audio = try fixture.audio(named: "generated.aiff", bytes: Data("generated disposable audio".utf8))

        let receipt = try await fixture.coordinator(provider: provider).capture(
            fixture.request(audioURL: audio)
        )

        #expect(!receipt.wasReused)
        #expect(receipt.transcription.status == .completed)
        #expect(receipt.transcription.text == VoiceProviderFake.transcriptText)
        #expect(receipt.transcription.providerID == provider.provider.id)
        #expect(receipt.transcription.modelIdentity == provider.provider.modelIdentity)
        #expect(receipt.transcription.localeIdentifier == "en_US")
        #expect(receipt.transcription.segments.count == 2)
        #expect(receipt.transcription.sourceAudioID == "fixture:voice:1")
        #expect(receipt.transcription.sourceAudioSHA256 == LocalFileIntakeValidator.sha256(Data("generated disposable audio".utf8)))
        #expect(receipt.transcription.retention == .preserveOriginal)
        #expect(!receipt.transcription.usedNetworkFallback)
        #expect(receipt.atomicReceipt.mediaSources.count == 1)
        #expect(try fixture.count("items", where: "type = 'note'") == 1)
        #expect(try fixture.count("items", where: "type = 'vaultFile'") == 1)
        #expect(try fixture.count("capture_events") == 1)
        #expect(try fixture.count("capture_attachments") == 1)

        let note = try #require(fixture.notes.notes.first)
        #expect(fixture.notes.loadContent(for: note).contains(VoiceProviderFake.transcriptText))
        let cards = try JournalMediaSourceCardReadService(
            database: fixture.database,
            vaultRoot: fixture.vault
        ).sourceCards(noteIDs: [note.id])
        let source = try #require(cards.first)
        #expect(source.kind == .audio)
        #expect(source.isOriginalAvailable)
        #expect(source.transcription == receipt.transcription)
        #expect(source.transcription?.text == VoiceProviderFake.transcriptText)
        #expect(source.transcription?.segments.map(\.timestamp) == [0, 1.25])
        let captureCard = try #require(
            JournalLibraryReadModel.build(from: [note], mediaSources: cards).defaultDay?.captureCards.first
        )
        #expect(captureCard.sourceContent.contains(VoiceProviderFake.transcriptText))
        #expect(captureCard.mediaSources.first?.canonicalItemRef.type == .vaultFile)
        let relativePath = try #require(receipt.atomicReceipt.mediaSources.first?.mediaItem?.relativePath)
        #expect(relativePath.hasPrefix("Journal/Audio/"))
        #expect(try Data(contentsOf: fixture.vault.appendingPathComponent(relativePath)) == Data("generated disposable audio".utf8))
        #expect(!receipt.descriptionForPublicOutput.contains(fixture.root.path))
    }

    @Test("unchanged retry and reopen reuse the durable receipt without provider work or duplicates")
    func unchangedRetryReusesReceipt() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let provider = VoiceProviderFake()
        let audio = try fixture.audio(named: "retry.wav", bytes: Data("same generated audio".utf8))
        let request = fixture.request(audioURL: audio)

        let first = try await fixture.coordinator(provider: provider).capture(request)
        let retry = try await fixture.coordinator(provider: provider).capture(request)
        #expect(retry.atomicReceipt.receiptID == first.atomicReceipt.receiptID)
        #expect(retry.transcription == first.transcription)
        #expect(retry.wasReused)
        #expect(provider.transcriptionRequests.count == 1)

        fixture.database.close()
        let reopened = CiderDatabase()
        try reopened.open(at: fixture.databaseURL)
        defer { reopened.close() }
        let reopenedNotes = NotesStorage(
            database: reopened,
            notesDirectoryURL: fixture.notesDirectory,
            vaultRootURL: fixture.vault
        )
        reopenedNotes.loadNotesFromDatabase(reopened)
        let reopenedReceipt = try await fixture.coordinator(
            database: reopened,
            notes: reopenedNotes,
            provider: provider
        ).capture(request)
        #expect(reopenedReceipt.atomicReceipt.receiptID == first.atomicReceipt.receiptID)
        #expect(reopenedReceipt.wasReused)
        #expect(provider.transcriptionRequests.count == 1)
        #expect(try fixture.count("items", where: "type = 'note'", database: reopened) == 1)
        #expect(try fixture.count("items", where: "type = 'vaultFile'", database: reopened) == 1)
        #expect(try fixture.count("capture_events", database: reopened) == 1)
        #expect(try fixture.count("capture_attachments", database: reopened) == 1)

        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: first.atomicReceipt.item.id)
        let firstCandidates = try JournalCaptureCandidateService(database: reopened).generate(
            captureEventID: first.atomicReceipt.receiptID,
            journalOwner: owner
        )
        let retryCandidates = try JournalCaptureCandidateService(database: reopened).generate(
            captureEventID: first.atomicReceipt.receiptID,
            journalOwner: owner
        )
        #expect(retryCandidates.outputs.map(\.id) == firstCandidates.outputs.map(\.id))
        #expect(retryCandidates.wasReused)
    }

    @Test("reusing retry identity with changed audio fails before provider or canonical mutation")
    func changedAudioFailsClosed() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let provider = VoiceProviderFake()
        let audio = try fixture.audio(named: "changed.caf", bytes: Data("version one".utf8))
        let request = fixture.request(audioURL: audio)
        _ = try await fixture.coordinator(provider: provider).capture(request)
        let before = try fixture.fingerprint()
        try Data("version two".utf8).write(to: audio, options: .atomic)

        do {
            _ = try await fixture.coordinator(provider: provider).capture(request)
            Issue.record("Expected changed bytes to conflict")
        } catch let error as JournalStoredVoiceCaptureError {
            #expect(error.code == .idempotencyConflict)
            #expect(!error.localizedDescription.contains(fixture.root.path))
        }
        #expect(provider.transcriptionRequests.count == 1)
        #expect(try fixture.fingerprint() == before)
    }

    @Test("unavailable unauthorized unsupported timeout and fabricated results commit nothing")
    func providerFailuresCommitNothing() async throws {
        for mode in VoiceProviderFake.Mode.failureCases {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            let provider = VoiceProviderFake(mode: mode)
            let audio = try fixture.audio(named: "failure.m4a", bytes: Data("disposable failure audio".utf8))
            let before = try fixture.fingerprint()

            do {
                _ = try await fixture.coordinator(provider: provider).capture(fixture.request(audioURL: audio))
                Issue.record("Expected \(mode) to fail")
            } catch let error as JournalStoredVoiceCaptureError {
                #expect(error.code == .transcriptionFailed || error.code == .providerUnavailable)
                #expect(error.transcriptionFailureCode == mode.expectedFailureCode)
                #expect(!error.localizedDescription.contains(fixture.root.path))
            }
            #expect(try fixture.fingerprint() == before)
            #expect(try fixture.count("capture_events") == 0)
            #expect(try fixture.count("capture_attachments") == 0)
            #expect(try fixture.count("items") == 0)
            #expect(provider.authorizationRequestCount == 0)
        }
    }

    @Test("missing and symlink audio fail through existing intake safety without path disclosure")
    func localFileSafetyAndPrivacy() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let provider = VoiceProviderFake()
        let missing = fixture.sources.appendingPathComponent("private-missing.aiff")
        let real = try fixture.audio(named: "real.aiff", bytes: Data("safe fixture".utf8))
        let link = fixture.sources.appendingPathComponent("private-link.aiff")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        for url in [missing, link] {
            do {
                _ = try await fixture.coordinator(provider: provider).capture(fixture.request(audioURL: url))
                Issue.record("Expected unsafe local input to fail")
            } catch let error as JournalStoredVoiceCaptureError {
                #expect(error.code == .validationFailed)
                #expect(!error.localizedDescription.contains(url.path))
                #expect(!error.localizedDescription.contains(fixture.root.path))
            }
        }
        #expect(provider.transcriptionRequests.isEmpty)
        #expect(try fixture.count("items") == 0)
        #expect(try fixture.count("capture_events") == 0)
    }

    @Test("private path-shaped source identities are projected to stable public provenance")
    func privatePathSourceIdentityIsProjected() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let provider = VoiceProviderFake()
        let audio = try fixture.audio(named: "private-source.aiff", bytes: Data("safe generated fixture".utf8))
        let privateSourceID = fixture.root.appendingPathComponent("caller/private-source.aiff").path
        let base = fixture.request(audioURL: audio)
        let request = JournalStoredVoiceCaptureRequest(
            journalDate: base.journalDate,
            time: base.time,
            audioURL: base.audioURL,
            sourceID: privateSourceID,
            displayTitle: base.displayTitle,
            mimeType: base.mimeType,
            source: base.source,
            capturedAt: base.capturedAt,
            idempotencyKey: base.idempotencyKey,
            sourceContext: base.sourceContext,
            provider: base.provider
        )

        let receipt = try await fixture.coordinator(provider: provider).capture(request)
        #expect(receipt.transcription.sourceAudioID.hasPrefix("journal-audio-sha256-"))
        #expect(!receipt.transcription.sourceAudioID.contains(fixture.root.path))
        #expect(!receipt.descriptionForPublicOutput.contains(fixture.root.path))
    }

    @Test("atomic writer failure rolls back transcript Journal media event source card and receipt")
    func atomicRollbackAfterTranscription() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let provider = VoiceProviderFake()
        let audio = try fixture.audio(named: "rollback.aiff", bytes: Data("rollback fixture".utf8))
        let writer = JournalAtomicCaptureWriter(
            database: fixture.database,
            notesStorage: fixture.notes,
            vaultRoot: fixture.vault,
            hooks: .init(atStage: { stage in
                if stage == .afterSourceCards { throw Injected.failure }
            })
        )
        let before = try fixture.fingerprint()

        do {
            _ = try await fixture.coordinator(provider: provider, writer: writer).capture(
                fixture.request(audioURL: audio)
            )
            Issue.record("Expected injected atomic failure")
        } catch let error as JournalStoredVoiceCaptureError {
            #expect(error.code == .persistenceFailed)
        }
        #expect(provider.transcriptionRequests.count == 1)
        #expect(try fixture.fingerprint() == before)
        #expect(fixture.notes.notes.isEmpty)
    }

    @Test("central stored provider selection is explicit and never falls back")
    func centralProviderSelectionNeverFallsBack() throws {
        let apple = try CiderTranscriptionProviderSelection.resolveStoredAudio(.init(
            providerID: "apple-speech-on-device",
            localeIdentifier: "en_US"
        )).get()
        #expect(apple.requestedProviderID == "apple-speech-on-device")
        #expect(apple.service.provider.id == "apple-speech-on-device")
        #expect(!apple.usedFallback)

        let unavailableLocal = CiderTranscriptionProviderSelection.resolveStoredAudio(.init(
            providerID: "local-faster-whisper",
            localeIdentifier: "en_US"
        ))
        guard case .failure(let localFailure) = unavailableLocal else {
            Issue.record("Missing local configuration must fail")
            return
        }
        #expect(localFailure.code == .unavailable)

        let unknown = CiderTranscriptionProviderSelection.resolveStoredAudio(.init(
            providerID: "not-a-provider"
        ))
        guard case .failure(let unknownFailure) = unknown else {
            Issue.record("Unknown provider must fail")
            return
        }
        #expect(unknownFailure.code == .unsupportedInput)
        #expect(CiderTranscriptionProviderSelection.defaultProviderID == "apple-speech-on-device")
    }
}

private extension JournalStoredVoiceCaptureCoordinatorTests {
    enum Injected: Error { case failure }

    @MainActor
    final class Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-journal-voice-\(UUID().uuidString)", isDirectory: true)
        lazy var vault = root.appendingPathComponent("vault", isDirectory: true)
        lazy var sources = root.appendingPathComponent("sources", isDirectory: true)
        lazy var notesDirectory = vault.appendingPathComponent(".cider/notes", isDirectory: true)
        lazy var databaseURL = root.appendingPathComponent("cider.sqlite")
        let database = CiderDatabase()
        lazy var notes = NotesStorage(
            database: database,
            notesDirectoryURL: notesDirectory,
            vaultRootURL: vault
        )

        init() throws {
            try FileManager.default.createDirectory(at: vault.appendingPathComponent("Inbox/Notes"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
            try database.open(at: databaseURL)
            notes.loadNotesFromDatabase(database)
        }

        func cleanup() {
            database.close()
            try? FileManager.default.removeItem(at: root)
        }

        func audio(named name: String, bytes: Data) throws -> URL {
            let url = sources.appendingPathComponent(name)
            try bytes.write(to: url, options: .atomic)
            return url
        }

        func request(audioURL: URL) -> JournalStoredVoiceCaptureRequest {
            .init(
                journalDate: "2026-07-15",
                time: "18:24",
                audioURL: audioURL,
                sourceID: "fixture:voice:1",
                displayTitle: "Evening voice reflection",
                mimeType: "audio/aiff",
                source: "voice",
                capturedAt: Date(timeIntervalSince1970: 1_768_525_440),
                idempotencyKey: "fixture:voice:retry:1",
                sourceContext: CaptureSourceContext(
                    surface: "test",
                    channel: "fixture",
                    messageID: "voice-1",
                    originalText: nil
                ),
                provider: .init(providerID: "fixture-stored-provider", localeIdentifier: "en_US")
            )
        }

        func coordinator(
            database: CiderDatabase? = nil,
            notes: NotesStorage? = nil,
            provider: VoiceProviderFake,
            writer: JournalAtomicCaptureWriter? = nil
        ) -> JournalStoredVoiceCaptureCoordinator {
            let database = database ?? self.database
            let notes = notes ?? self.notes
            return JournalStoredVoiceCaptureCoordinator(
                database: database,
                notesStorage: notes,
                vaultRoot: vault,
                atomicWriter: writer,
                providerResolver: { request in
                    .success(.init(
                        requestedProviderID: request.providerID,
                        service: provider,
                        usedSharedDefault: false
                    ))
                }
            )
        }

        func count(_ table: String, where predicate: String? = nil, database: CiderDatabase? = nil) throws -> Int {
            let database = database ?? self.database
            let statement = try database.prepare("SELECT COUNT(*) FROM \(table)\(predicate.map { " WHERE \($0)" } ?? "");")
            try statement.step()
            return statement.int(at: 0)
        }

        func fingerprint() throws -> String {
            let tables = [
                "items", "notes", "vault_files", "capture_events", "capture_attachments",
                "owner_relations", "content_chunks", "enrichment_outputs",
            ]
            let counts = try tables.map { "\($0)=\(try count($0))" }.joined(separator: "|")
            let files = (try? FileManager.default.subpathsOfDirectory(atPath: vault.path)) ?? []
            let fileFacts = try files.sorted().map { path -> String in
                let url = vault.appendingPathComponent(path)
                let isRegular = try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
                return isRegular
                    ? "\(path):\(LocalFileIntakeValidator.sha256(try Data(contentsOf: url)))"
                    : "\(path):directory"
            }.joined(separator: "|")
            return counts + "||" + fileFacts
        }
    }
}

@MainActor
private final class VoiceProviderFake: CiderTranscriptionServicing {
    enum Mode: CustomStringConvertible {
        case success
        case unavailable
        case unauthorized
        case unsupported
        case timedOut
        case nonFinal
        case mismatchedSource

        static let failureCases: [Mode] = [
            .unavailable, .unauthorized, .unsupported, .timedOut, .nonFinal, .mismatchedSource,
        ]

        var expectedFailureCode: TranscriptionFailureCode {
            switch self {
            case .success: .recognitionFailed
            case .unavailable: .unavailable
            case .unauthorized: .authorizationDenied
            case .unsupported: .unsupportedInput
            case .timedOut: .timedOut
            case .nonFinal, .mismatchedSource: .recognitionFailed
            }
        }

        var description: String {
            switch self {
            case .success: "success"
            case .unavailable: "unavailable"
            case .unauthorized: "unauthorized"
            case .unsupported: "unsupported"
            case .timedOut: "timedOut"
            case .nonFinal: "nonFinal"
            case .mismatchedSource: "mismatchedSource"
            }
        }
    }

    static let transcriptText = "The generated fixture says the evening walk felt calm and worth remembering."
    let mode: Mode
    let provider: TranscriptionProviderMetadata
    private(set) var transcriptionRequests: [StoredAudioTranscriptionRequest] = []
    private(set) var authorizationRequestCount = 0

    init(mode: Mode = .success) {
        self.mode = mode
        provider = .init(
            id: "fixture-stored-provider",
            adapterVersion: "test-3",
            modelIdentity: "fixture-model-v1",
            execution: .localProcess,
            supportedInputs: mode == .unsupported ? [] : [.storedAudioFile],
            supportsSegmentTimestamps: true,
            allowsNetworkFallback: false
        )
    }

    func authorization(for input: TranscriptionInputKind) -> TranscriptionAuthorization {
        mode == .unauthorized ? .denied : .authorized
    }

    func readiness(for input: TranscriptionInputKind) -> TranscriptionReadiness {
        mode == .unavailable ? .unavailable(reason: "fixture unavailable") : .ready
    }

    func requestAuthorization(for input: TranscriptionInputKind) async -> TranscriptionAuthorization {
        authorizationRequestCount += 1
        return authorization(for: input)
    }

    func startLive(
        _ request: LiveTranscriptionRequest,
        onEvent: @escaping @MainActor @Sendable (TranscriptionEvent) -> Void
    ) throws {
        throw TranscriptionFailure(code: .unsupportedInput, message: "Stored audio only.")
    }

    func stopLive() {}
    func cancelLive() {}
    func cancelStoredAudio() {}

    func transcribeStoredAudio(_ request: StoredAudioTranscriptionRequest) async -> TranscriptionResult {
        transcriptionRequests.append(request)
        if mode == .timedOut {
            return .failure(.init(code: .timedOut, message: "Fixture timed out."))
        }
        let source = mode == .mismatchedSource
            ? TranscriptionSourceIdentity.storedAudio(sourceID: "wrong-source", displayName: nil)
            : request.source
        return .success(.init(
            text: Self.transcriptText,
            isFinal: mode != .nonFinal,
            provenance: .init(
                provider: provider,
                source: source,
                locale: .init(identifier: "en_US"),
                timing: .init(
                    startedAt: Date(timeIntervalSince1970: 100),
                    completedAt: Date(timeIntervalSince1970: 102),
                    audioDuration: 2.5
                )
            ),
            segments: [
                .init(text: "The generated fixture says the evening walk felt calm", timestamp: 0, duration: 1.1),
                .init(text: "and worth remembering.", timestamp: 1.25, duration: 1.25),
            ]
        ))
    }
}
