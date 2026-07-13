import Foundation
import Testing
@testable import Cider

@Suite("Agent Rooms Room Management Tests")
@MainActor
struct AgentRoomsRoomManagementTests {
    @Test("action service creates renames archives restores and reopens one Cider-owned room")
    func durableRoomLifecycle() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-room-management-\(UUID().uuidString).db")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(atPath: url.path + "-wal")
            try? FileManager.default.removeItem(atPath: url.path + "-shm")
        }

        let firstDatabase = CiderDatabase()
        try firstDatabase.open(at: url)
        let firstRepository = ConversationRepository(database: firstDatabase)
        let actions = AgentRoomsActionService(repository: firstRepository)
        let created = try actions.createConversation(title: "  Daily room  ")
        let binding = try firstRepository.upsertRuntimeBinding(.init(
            roomID: created.id,
            runtimeID: "hermes",
            transportID: "runs-api",
            sourceNamespace: "hermes.runs.v1",
            externalSessionID: "replaceable-session-id"
        ))
        let turn = try firstRepository.beginTurn(.init(
            roomID: created.id,
            runtimeBindingID: binding.id,
            source: .init(namespace: "hermes.runs.v1", id: "durable-run"),
            status: .completed
        ))
        let message = try firstRepository.upsertMessage(.init(
            roomID: created.id,
            turnID: turn.id,
            runtimeBindingID: binding.id,
            role: "assistant",
            contentText: "Durable response",
            source: .init(namespace: "hermes.runs.v1", id: "durable-message")
        ), intent: .historicalReplay).message
        let renamed = try actions.renameConversation(id: created.id, title: "  Trip planning  ")
        let archived = try actions.archiveConversation(id: created.id)
        let restored = try actions.restoreConversation(id: created.id)
        firstDatabase.close()

        let reopenedDatabase = CiderDatabase()
        try reopenedDatabase.open(at: url)
        defer { reopenedDatabase.close() }
        let reopenedRepository = ConversationRepository(database: reopenedDatabase)
        let reopened = try #require(try reopenedRepository.room(id: created.id))

        #expect(created.title == "Daily room")
        #expect(renamed.id == created.id)
        #expect(renamed.title == "Trip planning")
        #expect(archived.id == created.id)
        #expect(archived.lifecycleState == .archived)
        #expect(restored.id == created.id)
        #expect(restored.lifecycleState == .active)
        #expect(reopened.id == created.id)
        #expect(reopened.title == "Trip planning")
        #expect(reopened.lifecycleState == .active)
        #expect(try reopenedRepository.bindings(roomID: created.id).map(\.id) == [binding.id])
        #expect(try reopenedRepository.turns(roomID: created.id).map(\.id) == [turn.id])
        #expect(try reopenedRepository.messages(roomID: created.id).map(\.id) == [message.id])
    }

    @Test("read service intentionally filters active and archived rooms and searches durable history")
    func filteredSearchProjection() throws {
        try withRepository { repository in
            let active = try repository.createRoom(.init(title: "Active conversation"))
            let archived = try repository.createRoom(.init(title: "Cold storage"))
            _ = try repository.upsertMessage(.init(
                roomID: archived.id,
                role: "user",
                contentText: "Find the orchard note"
            ), intent: .historicalReplay)
            try repository.setLifecycle(roomID: archived.id, state: .archived, at: Date())

            let service = AgentRoomsReadService(repository: repository)
            let activeState = service.loadWorkspace(request: .init(scope: .active))
            let archivedSearch = service.loadWorkspace(request: .init(scope: .archived, searchText: "orchard"))

            guard case .loaded(_, let activeRooms, _) = activeState else {
                Issue.record("Expected active rooms")
                return
            }
            guard case .loaded(_, let archivedRooms, _) = archivedSearch else {
                Issue.record("Expected archived search results")
                return
            }
            #expect(activeRooms.map(\.id) == [active.id.uuidString])
            #expect(activeRooms.allSatisfy { $0.lifecycleState == .active })
            #expect(archivedRooms.map(\.id) == [archived.id.uuidString])
            #expect(archivedRooms.allSatisfy { $0.lifecycleState == .archived })
        }
    }

    @Test("reserved Test Chat authority fails closed under generic room actions")
    func reservedTestChatCannotBeMutatedGenerically() throws {
        try withRepository { repository in
            let reserved = try repository.createRoom(.init(
                stableKey: AgentRoomsTestChatPersistence.stableRoomKey,
                title: AgentRoomsLiveChatModel.roomTitle,
                kind: "cider-test-chat",
                metadata: ["authority": "reserved"]
            ))
            let actions = AgentRoomsActionService(repository: repository)

            #expect(throws: ConversationRepositoryError.self) {
                try actions.renameConversation(id: reserved.id, title: "Guessed ownership")
            }
            #expect(throws: ConversationRepositoryError.self) {
                try actions.archiveConversation(id: reserved.id)
            }
            let unchanged = try #require(try repository.room(id: reserved.id))
            #expect(unchanged.title == AgentRoomsLiveChatModel.roomTitle)
            #expect(unchanged.lifecycleState == .active)
        }
    }

    @Test("only safe canonical selections survive session reconstruction")
    func safeSelectedRoomPersistence() {
        let suiteName = "cider-agent-rooms-selection-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AgentRoomsSelectionStore(defaults: defaults, key: "selected-room")
        let canonicalID = UUID().uuidString

        let first = AgentRoomsSessionModel(
            liveChat: AgentRoomsLiveChatModel(transport: RoomManagementTransport()),
            selectionStore: store
        )
        first.selectRoom(id: canonicalID, persistIfCanonical: true)
        first.selectRoom(id: "ambiguous-legacy-room", persistIfCanonical: false)

        let reconstructed = AgentRoomsSessionModel(
            liveChat: AgentRoomsLiveChatModel(transport: RoomManagementTransport()),
            selectionStore: store
        )
        #expect(first.selectedRoomID == "ambiguous-legacy-room")
        #expect(reconstructed.selectedRoomID == canonicalID)
        #expect(reconstructed.preferredCanonicalRoomID == canonicalID)
    }

    @Test("native Rooms source exposes calm searchable lifecycle actions with accessibility labels")
    func nativeAffordances() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/Cider/Views/AgentRooms/AgentRoomsWorkspaceView.swift"),
            encoding: .utf8
        )

        for required in [
            "Search conversations",
            "Active conversations",
            "Archived conversations",
            "No archived conversations",
            "Conversations you archive will appear here and can be restored.",
            "New Conversation",
            "Rename Conversation",
            "Archive Conversation",
            "Restore Conversation",
            ".keyboardShortcut(\"n\", modifiers: .command)",
            ".keyboardShortcut(\"f\", modifiers: .command)",
        ] {
            #expect(source.contains(required), "Missing Rooms affordance: \(required)")
        }
        #expect(!source.contains("CiderDatabase.shared"))
        #expect(!source.contains("ConversationRepository"))
    }

    private func withRepository<T>(_ body: (ConversationRepository) throws -> T) throws -> T {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-room-management-read-\(UUID().uuidString).db")
        let database = CiderDatabase()
        try database.open(at: url)
        defer {
            database.close()
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(atPath: url.path + "-wal")
            try? FileManager.default.removeItem(atPath: url.path + "-shm")
        }
        return try body(ConversationRepository(database: database))
    }
}

private actor RoomManagementTransport: HermesBridgeTransport {
    func availability() async -> HermesBridgeAvailability { .unavailable("test") }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        throw CancellationError()
    }

    func stop(runID: String) async throws {}
}
