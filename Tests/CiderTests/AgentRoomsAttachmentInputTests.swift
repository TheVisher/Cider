import Foundation
import Testing
@testable import Cider

@Suite("Agent Rooms Attachment Input Tests")
@MainActor
struct AgentRoomsAttachmentInputTests {
    @Test("native composer exposes accessible picker drop target and truthful staged status")
    func nativeComposerAttachmentAffordances() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/Cider/Views/AgentRooms/AgentRoomsWorkspaceView.swift"),
            encoding: .utf8
        )
        #expect(source.contains("Attach text or image files"))
        #expect(source.contains(".fileImporter("))
        #expect(source.contains(".dropDestination(for: URL.self)"))
        #expect(source.contains("local draft only"))
        #expect(!source.contains(".accessibilityLabel(\"Message composer and file drop target\")"))
    }

    @Test("picker and drop stage locally without transport or Conversation Core writes")
    func stagingDoesNotSendOrPersist() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let transport = AttachmentInputTransport(capability: .supported)
        let model = fixture.makeModel(transport: transport)
        #expect(model.activateCanonicalRoom(id: fixture.room.id))
        await model.refreshTransportReadiness()

        let text = try fixture.writeText("draft.txt", "staged only")
        let image = try fixture.writePNG("pixel.png")
        model.stageAttachments(from: [text], source: .filePicker)
        model.stageAttachments(from: [image], source: .dragAndDrop)

        #expect(model.stagedAttachments.count == 2)
        #expect(model.stagedAttachments.map(\.inputSource) == [.filePicker, .dragAndDrop])
        #expect(try fixture.repository.turns(roomID: fixture.room.id).isEmpty)
        #expect(try fixture.repository.messages(roomID: fixture.room.id).isEmpty)
        #expect(await transport.sendCount == 0)
    }

    @Test("explicit send persists hashed text and image facts across physical reopen without private paths")
    func explicitSendPersistsFactsAcrossReopen() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let transport = AttachmentInputTransport(capability: .supported)
        let model = fixture.makeModel(transport: transport)
        #expect(model.activateCanonicalRoom(id: fixture.room.id))
        await model.refreshTransportReadiness()
        model.stageAttachments(from: [
            try fixture.writeText("notes.txt", "durable attachment"),
            try fixture.writePNG("preview.png"),
        ], source: .filePicker)

        await model.send("Use both files", selectedRoomID: fixture.room.id.uuidString)
        #expect(await transport.sendCount == 1)
        #expect(await transport.lastAttachments.count == 2)
        let firstTurn = try #require(try fixture.repository.turns(roomID: fixture.room.id).first)
        #expect(firstTurn.metadata["attachment_fact_state"] == "validated")
        #expect(!(firstTurn.metadata["attachments_json"] ?? "").contains(fixture.root.path))
        #expect(!(firstTurn.metadata["attachments_json"] ?? "").contains("file://"))
        fixture.database.close()

        let reopened = CiderDatabase()
        try reopened.open(at: fixture.databaseURL)
        defer { reopened.close() }
        let persistence = AgentRoomsConversationPersistence(
            database: reopened,
            repository: ConversationRepository(database: reopened)
        )
        let snapshot = try #require(try persistence.restoreCanonicalRoom(id: fixture.room.id))
        #expect(snapshot.latestAttachments.count == 2)
        #expect(snapshot.latestAttachments.allSatisfy { $0.sha256?.count == 64 })
        #expect(Set(snapshot.latestAttachments.compactMap(\.inputSource)) == ["file_picker"])
        #expect(snapshot.latestAttachments.allSatisfy { $0.lifecycle == "accepted" })
        #expect(!String(describing: snapshot.latestAttachments).contains(fixture.root.path))
    }

    @Test("unsupported oversize over-count missing symlink and duplicate inputs reject without losing valid staging")
    func rejectsInvalidInputsWithoutLosingDraftAttachments() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let service = fixture.attachmentService
        let validURL = try fixture.writeText("valid.txt", "valid")
        let valid = try service.stage(validURL, source: .filePicker, existing: [])

        let unsupported = fixture.root.appendingPathComponent("payload.pdf")
        try Data("pdf".utf8).write(to: unsupported)
        #expect(throws: ConversationAttachmentInputError.self) {
            try service.stage(unsupported, source: .dragAndDrop, existing: [valid])
        }
        let oversized = fixture.root.appendingPathComponent("huge.txt")
        try Data(repeating: 65, count: Int(AgentRoomsAttachmentService.maximumTextByteSize + 1)).write(to: oversized)
        #expect(throws: ConversationAttachmentInputError.self) {
            try service.stage(oversized, source: .filePicker, existing: [valid])
        }
        #expect(throws: ConversationAttachmentInputError.self) {
            try service.stage(fixture.root.appendingPathComponent("missing.txt"), source: .filePicker, existing: [valid])
        }
        let link = fixture.root.appendingPathComponent("alias.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: validURL)
        #expect(throws: ConversationAttachmentInputError.self) {
            try service.stage(link, source: .dragAndDrop, existing: [valid])
        }
        let duplicate = try fixture.writeText("duplicate.txt", "valid")
        #expect(throws: ConversationAttachmentInputError.self) {
            try service.stage(duplicate, source: .dragAndDrop, existing: [valid])
        }

        var staged = [valid]
        for index in 1..<AgentRoomsAttachmentService.maximumCount {
            staged.append(try service.stage(
                try fixture.writeText("file-\(index).txt", "value-\(index)"),
                source: .filePicker,
                existing: staged
            ))
        }
        #expect(throws: ConversationAttachmentInputError.self) {
            try service.stage(try fixture.writeText("too-many.txt", "fifth"), source: .filePicker, existing: staged)
        }
        #expect(staged.count == AgentRoomsAttachmentService.maximumCount)
        #expect(staged.first == valid)
    }

    @Test("unsupported runtime rejects before durable acceptance and preserves typed and staged draft state")
    func unsupportedRuntimePreservesDraft() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let transport = AttachmentInputTransport(capability: .unsupported(reason: "Images are unavailable on this runtime."))
        let model = fixture.makeModel(transport: transport)
        #expect(model.activateCanonicalRoom(id: fixture.room.id))
        await model.refreshTransportReadiness()
        model.stageAttachments(from: [try fixture.writeText("draft.txt", "draft")], source: .filePicker)

        #expect(model.startSubmission("Keep this typed draft", selectedRoomID: fixture.room.id.uuidString) == .rejected)
        #expect(model.stagedAttachments.count == 1)
        #expect(model.composerMessage == "Images are unavailable on this runtime.")
        #expect(try fixture.repository.turns(roomID: fixture.room.id).isEmpty)
        #expect(try fixture.repository.messages(roomID: fixture.room.id).isEmpty)
        #expect(await transport.sendCount == 0)
    }

    @Test("pre-accept failure retries the same durable attachment without duplicate user facts")
    func failureRetryKeepsAttachmentTruth() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let transport = AttachmentRetryTransport()
        let model = fixture.makeModel(transport: transport)
        #expect(model.activateCanonicalRoom(id: fixture.room.id))
        await model.refreshTransportReadiness()
        model.stageAttachments(from: [try fixture.writeText("retry.txt", "retry")], source: .dragAndDrop)
        await model.send("Retry this", selectedRoomID: fixture.room.id.uuidString)
        let clientID = try #require(model.activeRoom?.transcript.messages.last(where: { $0.role == .human })?.id)
        #expect(model.activeRoom?.transcript.messages.last?.deliveryState == .failed)

        await model.retry(clientMessageID: clientID, selectedRoomID: fixture.room.id.uuidString)
        #expect(await transport.sendCount == 2)
        #expect(try fixture.repository.messages(roomID: fixture.room.id).filter { $0.role == "user" }.count == 1)
        let turns = try fixture.repository.turns(roomID: fixture.room.id)
        #expect(turns.count == 2)
        #expect(turns.allSatisfy { $0.metadata["attachment_fact_state"] == "validated" })
        let turnFacts = try turns.map { turn in
            try JSONDecoder().decode(
                [HermesCiderAttachment].self,
                from: Data(try #require(turn.metadata["attachments_json"]).utf8)
            )
        }
        #expect(turnFacts[0] == turnFacts[1])
        #expect(turnFacts.allSatisfy { $0.count == 1 })
    }

    @Test("cancelled durable attempt reopens with accepted attachment facts")
    func cancelledAttemptReopensFacts() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let staged = try fixture.attachmentService.stage(
            try fixture.writeText("cancel.txt", "cancel"), source: .filePicker, existing: []
        )
        let accepted = try fixture.attachmentService.materialize([staged], at: Date())
        let persistence = AgentRoomsConversationPersistence(database: fixture.database, repository: fixture.repository)
        let attempt = try persistence.beginAttempt(
            roomID: fixture.room.id, roomTitle: fixture.room.title, isReservedTestChat: false,
            attemptID: UUID(), clientMessageID: "cider-room-client:\(UUID().uuidString)",
            userMessageID: UUID(), assistantMessageID: UUID(), text: "Cancel",
            attachments: accepted.map(\.fact), at: Date()
        )
        try persistence.terminate(attempt, status: .cancelled, runID: nil, partialAssistantText: nil, activity: [], at: Date())
        let reopened = try #require(try persistence.restoreCanonicalRoom(id: fixture.room.id))
        #expect(reopened.latestTurnStatus == .cancelled)
        #expect(reopened.latestAttachments == accepted.map(\.fact))
    }
}

@MainActor
private final class Fixture {
    let root: URL
    let databaseURL: URL
    let database: CiderDatabase
    let repository: ConversationRepository
    let room: ConversationRoom
    let attachmentService: AgentRoomsAttachmentService

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-room-attachment-input-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        databaseURL = root.appendingPathComponent("conversation.sqlite")
        database = CiderDatabase()
        try database.open(at: databaseURL)
        repository = ConversationRepository(database: database)
        room = try AgentRoomsActionService(repository: repository).createConversation(title: "Attachment room")
        attachmentService = AgentRoomsAttachmentService(
            database: database,
            vaultRoot: root.appendingPathComponent("vault", isDirectory: true)
        )
    }

    func makeModel(transport: any HermesBridgeTransport) -> AgentRoomsLiveChatModel {
        AgentRoomsLiveChatModel(
            transport: transport,
            turnCoordinator: HermesTurnCoordinator(),
            persistence: AgentRoomsConversationPersistence(database: database, repository: repository),
            attachmentService: attachmentService
        )
    }

    func writeText(_ name: String, _ value: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(value.utf8).write(to: url)
        return url
    }

    func writePNG(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        try data.write(to: url)
        return url
    }

    func cleanup() {
        database.close()
        try? FileManager.default.removeItem(at: root)
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
}

private actor AttachmentInputTransport: HermesBridgeTransport {
    let capability: ConversationAttachmentTransportCapability
    private(set) var sendCount = 0
    private(set) var lastAttachments: [ConversationAttachmentTransportPayload] = []

    init(capability: ConversationAttachmentTransportCapability) {
        self.capability = capability
    }

    func availability() async -> HermesBridgeAvailability { .apiRuns }
    func attachmentCapability() async -> ConversationAttachmentTransportCapability { capability }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        try await send(text: text, state: state, existingMessages: existingMessages, attachments: [], onEvent: onEvent)
    }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        attachments: [ConversationAttachmentTransportPayload],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        sendCount += 1
        lastAttachments = attachments
        let runID = "attachment-run-\(sendCount)"
        let sessionID = "attachment-session-\(sendCount)"
        await onEvent?(.runStarted(runID))
        let date = Date(timeIntervalSince1970: 1_820_000_000 + Double(sendCount))
        let user = AIAssistantMessage(role: .user, content: text, timestamp: date, sourceID: "hermes-run:\(runID):user", sourceSessionID: sessionID, sourceName: "Hermes")
        let assistant = AIAssistantMessage(role: .assistant, content: "Received \(attachments.count) files.", timestamp: date, sourceID: "hermes-run:\(runID):assistant", sourceSessionID: sessionID, sourceName: "Hermes")
        var next = state
        next.activeRuntimeSessionID = sessionID
        next.runtimeSessionLineage.append(sessionID)
        next.lastSyncedAt = date
        next.lastSyncedMessageID = assistant.sourceID
        next.lastSyncedTimestamp = date
        next.lastImportedRuntimeSessionID = sessionID
        return HermesBridgeSendResult(completion: .init(
            provenance: .hermesRunsAPI,
            runID: runID,
            terminalStatus: .completed,
            observedFacts: .none,
            finalSessionSynchronizationComplete: true,
            finalMessages: existingMessages + [user, assistant],
            finalState: next,
            modelIdentity: "attachment-test",
            terminalSourceEvidence: .init(reportedTerminalRunID: runID, userSourceID: user.sourceID, assistantSourceID: assistant.sourceID, userSourceSessionID: sessionID, assistantSourceSessionID: sessionID)
        ))
    }

    func stop(runID: String) async throws {}
}

private actor AttachmentRetryTransport: HermesBridgeTransport {
    private(set) var sendCount = 0
    func availability() async -> HermesBridgeAvailability { .apiRuns }
    func attachmentCapability() async -> ConversationAttachmentTransportCapability { .supported }
    func send(text: String, state: HermesConversationState, existingMessages: [AIAssistantMessage], onEvent: (@Sendable (HermesRunEvent) async -> Void)?) async throws -> HermesBridgeSendResult {
        try await send(text: text, state: state, existingMessages: existingMessages, attachments: [], onEvent: onEvent)
    }
    func send(text: String, state: HermesConversationState, existingMessages: [AIAssistantMessage], attachments: [ConversationAttachmentTransportPayload], onEvent: (@Sendable (HermesRunEvent) async -> Void)?) async throws -> HermesBridgeSendResult {
        sendCount += 1
        if sendCount == 1 { throw ConversationAttachmentInputError.rejected("pre-accept test failure") }
        let delegate = AttachmentInputTransport(capability: .supported)
        return try await delegate.send(text: text, state: state, existingMessages: existingMessages, attachments: attachments, onEvent: onEvent)
    }
    func stop(runID: String) async throws {}
}
