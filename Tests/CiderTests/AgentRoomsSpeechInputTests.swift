import Foundation
import Testing
@testable import Cider

@Suite("Agent Rooms Speech Input Tests")
@MainActor
struct AgentRoomsSpeechInputTests {
    @Test("permission and readiness failures preserve the exact typed draft without canonical work")
    func permissionAndReadinessFailuresAreSafe() async throws {
        let scenarios: [(ConversationTranscriptionAuthorization, ConversationTranscriptionAuthorization, ConversationTranscriptionReadiness, AgentRoomsSpeechInputState)] = [
            (.notDetermined, .denied, .ready, .denied),
            (.denied, .denied, .ready, .denied),
            (.restricted, .restricted, .ready, .restricted),
            (.authorized, .authorized, .unavailable(reason: "On-device transcription is unavailable."), .unavailable),
            (.authorized, .authorized, .offline(reason: "Speech recognition is offline."), .offline),
        ]

        for (initialAuthorization, requestedAuthorization, readiness, expectedState) in scenarios {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            let service = FakeTranscriptionService(
                authorization: initialAuthorization,
                requestedAuthorization: requestedAuthorization,
                readiness: readiness
            )
            let session = fixture.makeSession(transcriptionService: service)
            session.composerText = "Keep this typed draft exactly."

            if initialAuthorization == .notDetermined {
                #expect(session.speechPresentation.state == .notDetermined)
                #expect(service.authorizationRequestCount == 0)
            }
            await session.startTranscription()

            #expect(session.speechPresentation.state == expectedState)
            #expect(session.composerText == "Keep this typed draft exactly.")
            #expect(try fixture.repository.turns(roomID: fixture.room.id).isEmpty)
            #expect(try fixture.repository.messages(roomID: fixture.room.id).isEmpty)
            #expect(await fixture.transport.sendCount == 0)
            #expect(service.startCount == 0)
            #expect(service.authorizationRequestCount == (initialAuthorization == .notDetermined ? 1 : 0))
        }
    }

    @Test("bounded partial and final speech append to the existing draft and never auto-send")
    func partialAndFinalRemainEditableDraftOnly() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let service = FakeTranscriptionService()
        let session = fixture.makeSession(transcriptionService: service)
        session.composerText = "Typed first."

        await session.startTranscription()
        #expect(session.speechPresentation.state == .listening)
        service.emit(.level(9))
        #expect(session.speechPresentation.level == 1)
        service.emit(.partial(String(repeating: "a", count: AgentRoomsSpeechDraft.maximumTranscriptLength + 40)))
        #expect(session.composerText.count == "Typed first. ".count + AgentRoomsSpeechDraft.maximumTranscriptLength)
        service.emit(.final("dictated ending"))

        #expect(session.speechPresentation.state == .completed)
        #expect(session.composerText == "Typed first. dictated ending")
        #expect(session.speechDraft?.roomID == fixture.room.id.uuidString)
        #expect(session.speechDraft?.transcript == "dictated ending")
        #expect(session.speechDraft?.isFinal == true)
        #expect(session.speechDraft?.retainsRawAudio == false)
        #expect(try fixture.repository.turns(roomID: fixture.room.id).isEmpty)
        #expect(try fixture.repository.messages(roomID: fixture.room.id).isEmpty)
        #expect(await fixture.transport.sendCount == 0)

        session.composerText += " edited"
        #expect(session.composerText == "Typed first. dictated ending edited")
        #expect(await fixture.transport.sendCount == 0)
        session.discardSpeechDraft()
        #expect(session.composerText == "Typed first.")
        #expect(session.speechDraft == nil)
    }

    @Test("stop enters bounded processing and cancel restores the original draft without history")
    func stopAndCancelAreDeterministic() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let service = FakeTranscriptionService()
        let session = fixture.makeSession(transcriptionService: service)
        session.composerText = "Original  spacing\n"

        await session.startTranscription()
        service.emit(.partial("temporary words"))
        session.stopTranscription()
        #expect(session.speechPresentation.state == .transcribing)
        #expect(service.stopCount == 1)
        service.emit(.partial("late partial while finishing"))
        #expect(session.speechPresentation.state == .transcribing)
        session.cancelTranscription()

        #expect(session.speechPresentation.state == .cancelled)
        #expect(session.composerText == "Original  spacing\n")
        #expect(service.cancelCount == 1)
        #expect(try fixture.repository.turns(roomID: fixture.room.id).isEmpty)
        #expect(try fixture.repository.messages(roomID: fixture.room.id).isEmpty)
        #expect(await fixture.transport.sendCount == 0)

        await session.startTranscription()
        service.emit(.partial("discard this partial"))
        service.emit(.failure("provider detail that must not escape"))
        #expect(session.speechPresentation.state == .failed)
        #expect(session.speechPresentation.detail == "The original typed draft was preserved. Nothing was sent.")
        #expect(session.composerText == "Original  spacing\n")
        #expect(try fixture.repository.turns(roomID: fixture.room.id).isEmpty)
        #expect(await fixture.transport.sendCount == 0)
    }

    @Test("room switching cancels active speech and late transcripts cannot leak")
    func roomSwitchCancelsWithoutTranscriptLeak() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let secondRoom = try AgentRoomsActionService(repository: fixture.repository)
            .createConversation(title: "Second speech room")
        let service = FakeTranscriptionService()
        let session = fixture.makeSession(transcriptionService: service)
        session.composerText = "Room one original"

        await session.startTranscription()
        service.emit(.partial("room one partial"))
        session.selectRoom(id: secondRoom.id.uuidString, persistIfCanonical: true)

        #expect(service.cancelCount == 1)
        #expect(session.speechPresentation.state == .cancelled)
        #expect(session.composerText == "")
        service.emitLate(.final("must not leak"))
        #expect(session.composerText == "")

        session.composerText = "Room two draft"
        session.selectRoom(id: fixture.room.id.uuidString, persistIfCanonical: true)
        #expect(session.composerText == "Room one original")
        session.selectRoom(id: secondRoom.id.uuidString, persistIfCanonical: true)
        #expect(session.composerText == "Room two draft")
        #expect(try fixture.repository.turns(roomID: fixture.room.id).isEmpty)
        #expect(try fixture.repository.messages(roomID: secondRoom.id).isEmpty)
        #expect(await fixture.transport.sendCount == 0)
    }

    @Test("only explicit send submits the edited speech-derived draft")
    func explicitSendUsesEditedSpeechDraft() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let service = FakeTranscriptionService()
        let session = fixture.makeSession(transcriptionService: service)
        session.composerText = "Plan"

        await session.startTranscription()
        service.emit(.final("the launch"))
        session.composerText = "Plan the quiet launch tomorrow"

        #expect(await fixture.transport.sendCount == 0)
        #expect(try fixture.repository.turns(roomID: fixture.room.id).isEmpty)
        await fixture.model.refreshTransportReadiness()
        await fixture.model.send(session.composerText, selectedRoomID: fixture.room.id.uuidString)

        #expect(await fixture.transport.sendCount == 1)
        #expect(await fixture.transport.sentTexts == ["Plan the quiet launch tomorrow"])
        #expect(try fixture.repository.messages(roomID: fixture.room.id).first?.contentText == "Plan the quiet launch tomorrow")
        #expect(try fixture.repository.turns(roomID: fixture.room.id).count == 1)
    }

    @Test("speech-derived per-room draft survives reconstruction without raw audio persistence")
    func draftReconstructionUsesExistingStoreOnly() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let suiteName = "AgentRoomsSpeechInputTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let selectionStore = AgentRoomsSelectionStore(defaults: defaults, key: "selection")
        let draftStore = AgentRoomsDraftStore(defaults: defaults, key: "drafts")
        let service = FakeTranscriptionService()
        let first = fixture.makeSession(
            transcriptionService: service,
            selectionStore: selectionStore,
            draftStore: draftStore
        )
        first.composerText = "Existing"
        await first.startTranscription()
        service.emit(.final("durable draft"))
        #expect(first.composerText == "Existing durable draft")
        #expect(try fixture.repository.turns(roomID: fixture.room.id).isEmpty)
        fixture.database.close()

        let reopenedDatabase = CiderDatabase()
        try reopenedDatabase.open(at: fixture.databaseURL)
        defer { reopenedDatabase.close() }
        let reopenedRepository = ConversationRepository(database: reopenedDatabase)
        let reopenedModel = AgentRoomsLiveChatModel(
            transport: fixture.transport,
            persistence: AgentRoomsConversationPersistence(database: reopenedDatabase, repository: reopenedRepository)
        )
        let reconstructed = AgentRoomsSessionModel(
            liveChat: reopenedModel,
            selectionStore: selectionStore,
            draftStore: draftStore,
            transcriptionService: FakeTranscriptionService()
        )
        reconstructed.selectRoom(id: fixture.room.id.uuidString, persistIfCanonical: true)

        #expect(reconstructed.composerText == "Existing durable draft")
        #expect(reconstructed.speechDraft == nil)
        #expect(try reopenedRepository.turns(roomID: fixture.room.id).isEmpty)
        #expect(try reopenedRepository.messages(roomID: fixture.room.id).isEmpty)
        let storedFiles = try FileManager.default.contentsOfDirectory(at: fixture.root, includingPropertiesForKeys: nil)
        #expect(storedFiles.allSatisfy { !["wav", "m4a", "caf", "aiff"].contains($0.pathExtension.lowercased()) })
    }

    @Test("native microphone paperclip composer and send keep distinct accessible controls")
    func nativeAccessibilityContract() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/Cider/Views/AgentRooms/AgentRoomsWorkspaceView.swift"),
            encoding: .utf8
        )

        #expect(source.contains("Start microphone transcription"))
        #expect(source.contains("Stop microphone transcription"))
        #expect(source.contains("Cancel microphone transcription"))
        #expect(source.contains("Attach text or image files"))
        #expect(source.contains("composerPlaceholder(roomID: roomID)"))
        #expect(source.contains("composerActionAccessibilityLabel(roomID: roomID)"))
        #expect(!source.contains(".accessibilityLabel(\"Message composer controls\")"))
    }

    @Test("production boundary declares native on-device permission without requiring a provisioning entitlement")
    func productionNativeBoundaryContract() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let service = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/Cider/Services/Conversation/AppleSpeechTranscriptionService.swift"
            ),
            encoding: .utf8
        )
        let info = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/Cider/Resources/Info.plist"),
            encoding: .utf8
        )
        let entitlements = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Cider.entitlements"),
            encoding: .utf8
        )

        #expect(service.contains("import Speech"))
        #expect(service.contains("request.requiresOnDeviceRecognition = true"))
        #expect(service.contains("func requestAuthorization() async"))
        #expect(!service.contains("URLSession"))
        #expect(!service.contains("write(to:"))
        #expect(info.contains("NSMicrophoneUsageDescription"))
        #expect(info.contains("NSSpeechRecognitionUsageDescription"))
        // Speech recognition is authorized at runtime through the usage descriptions.
        // Adding the restricted speech entitlement makes local signed development builds
        // require a provisioning profile and prevents Cider's normal build-and-run loop.
        #expect(!entitlements.contains("com.apple.developer.speech-recognition"))
    }

}

@MainActor
private final class Fixture {
    let root: URL
    let databaseURL: URL
    let database: CiderDatabase
    let repository: ConversationRepository
    let room: ConversationRoom
    let transport = SpeechInputTransport()
    let model: AgentRoomsLiveChatModel

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-room-speech-input-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        databaseURL = root.appendingPathComponent("conversation.sqlite")
        database = CiderDatabase()
        try database.open(at: databaseURL)
        repository = ConversationRepository(database: database)
        room = try AgentRoomsActionService(repository: repository).createConversation(title: "Speech room")
        model = AgentRoomsLiveChatModel(
            transport: transport,
            persistence: AgentRoomsConversationPersistence(database: database, repository: repository)
        )
    }

    func makeSession(
        transcriptionService: any ConversationTranscriptionServicing,
        selectionStore: (any AgentRoomsSelectionPersisting)? = nil,
        draftStore: (any AgentRoomsDraftPersisting)? = nil
    ) -> AgentRoomsSessionModel {
        let session = AgentRoomsSessionModel(
            liveChat: model,
            selectionStore: selectionStore,
            draftStore: draftStore,
            transcriptionService: transcriptionService
        )
        session.selectRoom(id: room.id.uuidString, persistIfCanonical: true)
        return session
    }

    func cleanup() {
        database.close()
        try? FileManager.default.removeItem(at: root)
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
}

@MainActor
private final class FakeTranscriptionService: ConversationTranscriptionServicing {
    let providerID = "deterministic-fake"
    private(set) var authorization: ConversationTranscriptionAuthorization
    let readiness: ConversationTranscriptionReadiness
    private let requestedAuthorization: ConversationTranscriptionAuthorization
    private var handler: (@MainActor @Sendable (ConversationTranscriptionEvent) -> Void)?
    private var lastHandler: (@MainActor @Sendable (ConversationTranscriptionEvent) -> Void)?
    private(set) var authorizationRequestCount = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var cancelCount = 0

    init(
        authorization: ConversationTranscriptionAuthorization = .authorized,
        requestedAuthorization: ConversationTranscriptionAuthorization = .authorized,
        readiness: ConversationTranscriptionReadiness = .ready
    ) {
        self.authorization = authorization
        self.requestedAuthorization = requestedAuthorization
        self.readiness = readiness
    }

    func requestAuthorization() async -> ConversationTranscriptionAuthorization {
        authorizationRequestCount += 1
        authorization = requestedAuthorization
        return authorization
    }

    func start(onEvent: @escaping @MainActor @Sendable (ConversationTranscriptionEvent) -> Void) throws {
        startCount += 1
        handler = onEvent
        lastHandler = onEvent
    }

    func stop() {
        stopCount += 1
    }

    func cancel() {
        cancelCount += 1
        handler = nil
    }

    func emit(_ event: ConversationTranscriptionEvent) {
        handler?(event)
    }

    func emitLate(_ event: ConversationTranscriptionEvent) {
        lastHandler?(event)
    }
}

private actor SpeechInputTransport: HermesBridgeTransport {
    private(set) var sendCount = 0
    private(set) var sentTexts: [String] = []

    func availability() async -> HermesBridgeAvailability { .apiRuns }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        sendCount += 1
        sentTexts.append(text)
        let runID = "speech-run-\(sendCount)"
        let sessionID = "speech-session-\(sendCount)"
        await onEvent?(.runStarted(runID))
        let timestamp = Date(timeIntervalSince1970: 1_826_000_000 + Double(sendCount))
        let user = AIAssistantMessage(
            role: .user, content: text, timestamp: timestamp,
            sourceID: "hermes-run:\(runID):user", sourceSessionID: sessionID, sourceName: "Hermes"
        )
        let assistant = AIAssistantMessage(
            role: .assistant, content: "Received speech draft.", timestamp: timestamp,
            sourceID: "hermes-run:\(runID):assistant", sourceSessionID: sessionID, sourceName: "Hermes"
        )
        var next = state
        next.activeRuntimeSessionID = sessionID
        next.runtimeSessionLineage.append(sessionID)
        next.lastSyncedAt = timestamp
        next.lastSyncedMessageID = assistant.sourceID
        next.lastSyncedTimestamp = timestamp
        next.lastImportedRuntimeSessionID = sessionID
        return HermesBridgeSendResult(completion: .init(
            provenance: .hermesRunsAPI,
            runID: runID,
            terminalStatus: .completed,
            observedFacts: .none,
            finalSessionSynchronizationComplete: true,
            finalMessages: existingMessages + [user, assistant],
            finalState: next,
            modelIdentity: "speech-test",
            terminalSourceEvidence: .init(
                reportedTerminalRunID: runID,
                userSourceID: user.sourceID,
                assistantSourceID: assistant.sourceID,
                userSourceSessionID: sessionID,
                assistantSourceSessionID: sessionID
            )
        ))
    }

    func stop(runID: String) async throws {}
}
