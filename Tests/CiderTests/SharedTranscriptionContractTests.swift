import Foundation
import Testing
@testable import Cider

@Suite("Shared Transcription Contract Tests")
@MainActor
struct SharedTranscriptionContractTests {
    @Test("live and stored audio share normalization, provider, locale, timing, and failure vocabulary")
    func liveAndStoredAudioUseOneContract() async throws {
        let service = DeterministicSharedTranscriptionService()
        let rawText = "  shared\u{0007} transcript  "
        var liveEvents: [TranscriptionEvent] = []

        try service.startLive(.init(sourceID: "chat-live-source")) { event in
            liveEvents.append(event)
        }
        service.completeLive(rawText)

        let fileURL = URL(fileURLWithPath: "/contract-fixtures/original-voice-note.m4a")
        let storedResult = await service.transcribeStoredAudio(.init(
            fileURL: fileURL,
            sourceID: "capture-attachment:voice-1",
            displayName: "Original Voice Note.m4a"
        ))

        let liveTranscript = try #require(liveEvents.compactMap { event -> TranscriptionTranscript? in
            guard case .final(let transcript) = event else { return nil }
            return transcript
        }.first)
        let storedTranscript = try #require(storedResult.success)

        #expect(liveTranscript.text == "shared  transcript")
        #expect(storedTranscript.text == liveTranscript.text)
        #expect(liveTranscript.provenance.provider == service.provider)
        #expect(storedTranscript.provenance.provider == service.provider)
        #expect(liveTranscript.provenance.locale == storedTranscript.provenance.locale)
        #expect(liveTranscript.provenance.timing.startedAt == storedTranscript.provenance.timing.startedAt)
        #expect(liveTranscript.provenance.timing.completedAt == storedTranscript.provenance.timing.completedAt)
        #expect(liveTranscript.provenance.source.kind == .liveMicrophone)
        #expect(liveTranscript.provenance.source.retention == .doNotRetain)
        #expect(storedTranscript.provenance.source.kind == .storedAudioFile)
        #expect(storedTranscript.provenance.source.sourceID == "capture-attachment:voice-1")
        #expect(storedTranscript.provenance.source.retention == .preserveOriginal)
        #expect(storedTranscript.provenance.usedNetworkFallback == false)
        #expect(service.lastStoredFileURL == fileURL)
        #expect(service.storedFileMutationCount == 0)

        let failure = service.failure(for: .storedAudioFile, source: storedTranscript.provenance.source)
        #expect(failure.code == .offline)
        #expect(failure.provenance?.provider == liveTranscript.provenance.provider)
        #expect(failure.provenance?.source == storedTranscript.provenance.source)
    }

    @Test("stored audio identity is stable while the path remains an input-only handle")
    func storedAudioSourceIdentityIsExplicitAndImmutable() {
        let fileURL = URL(fileURLWithPath: "/private/input/voice-note.caf")
        let request = StoredAudioTranscriptionRequest(
            fileURL: fileURL,
            sourceID: "photon-message:42:attachment:1",
            displayName: "Audio Message.caf"
        )

        #expect(request.fileURL == fileURL)
        #expect(request.source.sourceID == "photon-message:42:attachment:1")
        #expect(request.source.displayName == "Audio Message.caf")
        #expect(request.source.kind == .storedAudioFile)
        #expect(request.source.retention == .preserveOriginal)
        #expect(Mirror(reflecting: request.source).children.allSatisfy { $0.label != "fileURL" })
    }

    @Test("shared stored transcripts are not silently truncated to the Chat composer limit")
    func storedTranscriptPreservesContentBeyondChatLimit() {
        let longTranscript = String(repeating: "voice journal words ", count: 400)
        let service = DeterministicSharedTranscriptionService()
        let transcript = TranscriptionTranscript(
            text: longTranscript,
            isFinal: true,
            provenance: .init(
                provider: service.provider,
                source: .storedAudio(sourceID: "journal-audio:long", displayName: "Long Journal.m4a"),
                locale: .init(identifier: "en_US"),
                timing: .init(
                    startedAt: Date(timeIntervalSince1970: 1),
                    completedAt: Date(timeIntervalSince1970: 2),
                    audioDuration: 600
                )
            )
        )

        #expect(transcript.text == longTranscript.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(transcript.text.count > AgentRoomsSpeechDraft.maximumTranscriptLength)
        #expect(AgentRoomsSpeechDraft.boundedTranscript(transcript.text).count == AgentRoomsSpeechDraft.maximumTranscriptLength)
    }

    @Test("Apple is one on-device adapter for both inputs with no fallback or source mutation")
    func appleAdapterIsSharedAndFailClosed() throws {
        let service = CiderTranscriptionProviderSelection.makeDefault(locale: Locale(identifier: "en_US"))
        #expect(CiderTranscriptionProviderSelection.defaultProviderID == "apple-speech-on-device")
        #expect(service.provider.id == "apple-speech-on-device")
        #expect(service.provider.adapterVersion == "1")
        #expect(service.provider.execution == .onDevice)
        #expect(service.provider.supportedInputs == [.liveMicrophone, .storedAudioFile])
        #expect(service.provider.allowsNetworkFallback == false)

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/Cider/Services/Transcription/AppleSpeechTranscriptionService.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("SFSpeechAudioBufferRecognitionRequest"))
        #expect(source.contains("SFSpeechURLRecognitionRequest"))
        #expect(source.components(separatedBy: "requiresOnDeviceRecognition = true").count == 3)
        #expect(!source.contains("URLSession"))
        #expect(!source.contains("write(to:"))
        #expect(!source.contains("removeItem"))
        #expect(!source.contains("CiderVault"))
    }

    @Test("Chat composes the neutral shared boundary and no feature owns a second protocol")
    func conversationUsesNeutralSharedCapability() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sharedModels = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/Cider/Models/TranscriptionModels.swift"),
            encoding: .utf8
        )
        let conversationModels = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/Cider/Models/ConversationTranscriptionModels.swift"),
            encoding: .utf8
        )
        let session = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/Cider/Services/Conversation/AgentRoomsSessionModel.swift"
            ),
            encoding: .utf8
        )

        #expect(sharedModels.contains("protocol CiderTranscriptionServicing"))
        #expect(sharedModels.contains("func transcribeStoredAudio"))
        #expect(conversationModels.contains("typealias ConversationTranscriptionServicing = CiderTranscriptionServicing"))
        #expect(!conversationModels.contains("protocol ConversationTranscriptionServicing"))
        #expect(session.contains("private let transcriptionService: any CiderTranscriptionServicing"))
        #expect(session.contains("CiderTranscriptionProviderSelection.makeDefault()"))
        #expect(!session.contains("AppleSpeechTranscriptionService()"))
        #expect(session.contains("transcriptionService.startLive"))
    }
}
@MainActor
private final class DeterministicSharedTranscriptionService: CiderTranscriptionServicing {
    let provider = TranscriptionProviderMetadata(
        id: "deterministic-shared-provider",
        adapterVersion: "test-1",
        execution: .localProcess,
        supportedInputs: [.liveMicrophone, .storedAudioFile],
        allowsNetworkFallback: false
    )
    private let timestamp = Date(timeIntervalSince1970: 1_826_100_000)
    private let locale = TranscriptionLocaleMetadata(identifier: "en_US")
    private var liveRequest: LiveTranscriptionRequest?
    private var handler: (@MainActor @Sendable (TranscriptionEvent) -> Void)?
    private(set) var lastStoredFileURL: URL?
    private(set) var storedFileMutationCount = 0

    func authorization(for input: TranscriptionInputKind) -> TranscriptionAuthorization { .authorized }
    func readiness(for input: TranscriptionInputKind) -> TranscriptionReadiness { .ready }
    func requestAuthorization(for input: TranscriptionInputKind) async -> TranscriptionAuthorization { .authorized }

    func startLive(
        _ request: LiveTranscriptionRequest,
        onEvent: @escaping @MainActor @Sendable (TranscriptionEvent) -> Void
    ) throws {
        liveRequest = request
        handler = onEvent
    }

    func stopLive() {}

    func cancelLive() {
        liveRequest = nil
        handler = nil
    }

    func completeLive(_ text: String) {
        guard let liveRequest else { return }
        handler?(.final(.init(
            text: text,
            isFinal: true,
            provenance: provenance(source: liveRequest.source)
        )))
        self.liveRequest = nil
    }

    func transcribeStoredAudio(_ request: StoredAudioTranscriptionRequest) async -> TranscriptionResult {
        lastStoredFileURL = request.fileURL
        return .success(.init(
            text: "  shared\u{0007} transcript  ",
            isFinal: true,
            provenance: provenance(source: request.source)
        ))
    }

    func cancelStoredAudio() {}

    func failure(for input: TranscriptionInputKind, source: TranscriptionSourceIdentity) -> TranscriptionFailure {
        .init(
            code: .offline,
            message: "The selected provider is offline.",
            provenance: provenance(source: source)
        )
    }

    private func provenance(source: TranscriptionSourceIdentity) -> TranscriptionProvenance {
        .init(
            provider: provider,
            source: source,
            locale: locale,
            timing: .init(startedAt: timestamp, completedAt: timestamp, audioDuration: 2.5)
        )
    }
}

private extension TranscriptionResult {
    var success: TranscriptionTranscript? {
        guard case .success(let transcript) = self else { return nil }
        return transcript
    }
}
