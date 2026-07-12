import XCTest
@testable import Cider

@MainActor
final class AgentRoomsWorkspaceModelsTests: XCTestCase {
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testFixtureIsDeterministicAndDemonstratesRoomsThreadReceiptAndLink() throws {
        guard case .loaded(let rooms, let selectedRoomID) = AgentRoomsFixtureProvider.workspaceState else {
            return XCTFail("Expected loaded fixture state")
        }

        XCTAssertEqual(rooms.map(\.id), ["cider-product", "weekly-review", "capture-quality"])
        XCTAssertEqual(rooms.map(\.title), ["Cider Product", "Weekly Review", "Capture Quality"])
        XCTAssertEqual(selectedRoomID, "cider-product")

        let selectedRoom = try XCTUnwrap(rooms.first)
        XCTAssertEqual(selectedRoom.transcript.runtimeLabel, "Hermes")
        XCTAssertEqual(selectedRoom.transcript.messages.map(\.role), [.human, .agent, .human, .agent])
        XCTAssertEqual(selectedRoom.transcript.receipt?.title, "Reviewed CID-786")
        XCTAssertEqual(selectedRoom.transcript.receipt?.status, .completed)
        XCTAssertEqual(selectedRoom.transcript.link?.title, "Cider")
        XCTAssertEqual(selectedRoom.transcript.link?.subtitle, "Project")
        XCTAssertNotNil(selectedRoom.transcript.futureArtifact)
    }

    func testWorkspaceStateProjectsLoadingEmptyFailureAndLoadedStates() {
        XCTAssertEqual(AgentRoomsWorkspaceState.loading.projection(), .loading)
        XCTAssertEqual(AgentRoomsWorkspaceState.empty.projection(), .empty)
        XCTAssertEqual(
            AgentRoomsWorkspaceState.failed(message: "Fixture unavailable").projection(),
            .failed(message: "Fixture unavailable")
        )

        guard case .loaded(let rooms, _) = AgentRoomsFixtureProvider.workspaceState,
              case .loaded(let projectedRooms, let selectedRoom) = AgentRoomsFixtureProvider.workspaceState.projection() else {
            return XCTFail("Expected loaded fixture projection")
        }
        XCTAssertEqual(projectedRooms, rooms)
        XCTAssertEqual(selectedRoom.id, "cider-product")
    }

    func testLoadedProjectionFallsBackToFirstRoomForInvalidSelection() {
        guard case .loaded(let rooms, _) = AgentRoomsFixtureProvider.workspaceState else {
            return XCTFail("Expected loaded fixture state")
        }

        let invalidStoredSelection = AgentRoomsWorkspaceState.loaded(
            rooms: rooms,
            selectedRoomID: "missing-room"
        )
        guard case .loaded(_, let storedFallback) = invalidStoredSelection.projection() else {
            return XCTFail("Expected loaded fallback projection")
        }
        XCTAssertEqual(storedFallback.id, rooms[0].id)

        guard case .loaded(_, let localFallback) = AgentRoomsFixtureProvider.workspaceState.projection(
            selectedRoomID: "missing-local-room"
        ) else {
            return XCTFail("Expected loaded local fallback projection")
        }
        XCTAssertEqual(localFallback.id, rooms[0].id)
        XCTAssertEqual(
            AgentRoomsWorkspaceState.loaded(rooms: [], selectedRoomID: "missing").projection(),
            .empty
        )
    }

    func testReadServiceMapsCanonicalRoomsMessagesRuntimeAndSelection() throws {
        try withRepository { _, repository in
            let now = Date(timeIntervalSince1970: 10_000)
            let olderRoom = try repository.createRoom(.init(
                title: "Older Room",
                createdAt: now.addingTimeInterval(-7_200),
                updatedAt: now.addingTimeInterval(-7_200)
            ))
            let newestRoom = try repository.createRoom(.init(
                title: "Newest Room",
                createdAt: now.addingTimeInterval(-60),
                updatedAt: now.addingTimeInterval(-60)
            ))
            _ = try repository.upsertRuntimeBinding(.init(
                roomID: newestRoom.id,
                runtimeID: "hermes",
                transportID: "runs",
                sourceNamespace: "hermes.runs.v1",
                createdAt: now.addingTimeInterval(-50),
                updatedAt: now.addingTimeInterval(-50)
            ))
            let user = try repository.upsertMessage(.init(
                roomID: newestRoom.id,
                role: "user",
                contentText: "Map this room",
                createdAt: now.addingTimeInterval(-40)
            ), intent: .historicalReplay).message
            _ = try repository.upsertMessage(.init(
                roomID: newestRoom.id,
                role: "system",
                contentText: "Do not show this",
                createdAt: now.addingTimeInterval(-30)
            ), intent: .historicalReplay)
            let assistant = try repository.upsertMessage(.init(
                roomID: newestRoom.id,
                role: "assistant",
                contentText: "Mapped response",
                createdAt: now.addingTimeInterval(-20)
            ), intent: .historicalReplay).message
            _ = try repository.upsertMessage(.init(
                roomID: newestRoom.id,
                role: "tool",
                contentText: "Do not preview this",
                createdAt: now.addingTimeInterval(-10)
            ), intent: .historicalReplay)
            try repository.finalizeHistoricalRoomImport(
                roomID: newestRoom.id,
                nextTurnSequence: 1,
                nextMessageSequence: 5,
                updatedAt: newestRoom.updatedAt
            )

            let state = AgentRoomsReadService(repository: repository, now: { now }).loadWorkspace()
            guard case .loaded(let rooms, let selectedRoomID) = state else {
                return XCTFail("Expected loaded canonical projection")
            }

            XCTAssertEqual(rooms.map(\.id), [newestRoom.id.uuidString, olderRoom.id.uuidString])
            XCTAssertEqual(selectedRoomID, newestRoom.id.uuidString)
            let mapped = try XCTUnwrap(rooms.first)
            XCTAssertEqual(mapped.title, "Newest Room")
            XCTAssertEqual(mapped.updatedAt, newestRoom.updatedAt)
            XCTAssertEqual(mapped.relativeTime, "1m")
            XCTAssertEqual(mapped.preview, "Mapped response")
            XCTAssertEqual(mapped.transcript.runtimeLabel, "Hermes")
            XCTAssertEqual(mapped.transcript.messages.map(\.id), [user.id.uuidString, assistant.id.uuidString])
            XCTAssertEqual(mapped.transcript.messages.map(\.role), [.human, .agent])
            XCTAssertEqual(mapped.transcript.messages.map(\.author), ["You", "Hermes"])
            XCTAssertEqual(mapped.transcript.messages.map(\.body), ["Map this room", "Mapped response"])
            XCTAssertNil(mapped.transcript.link)
            XCTAssertNil(mapped.transcript.receipt)
            XCTAssertNil(mapped.transcript.futureArtifact)
            XCTAssertEqual(rooms[1].preview, AgentRoomsReadService.fallbackPreview)
        }
    }

    func testReadServiceReturnsEmptyAndSanitizesFailureThenRetryRecovers() {
        var attempts = 0
        let service = AgentRoomsReadService(
            loadRooms: { _, _ in
                attempts += 1
                if attempts == 1 { throw NSError(domain: "SQL /private/live/path.db", code: 1) }
                return []
            },
            loadRecentMessages: { _, _ in [] },
            loadRuntimeBindings: { _, _ in [] },
            now: { Date(timeIntervalSince1970: 10_000) }
        )

        XCTAssertEqual(
            service.loadWorkspace(),
            .failed(message: AgentRoomsReadService.unavailableMessage)
        )
        XCTAssertFalse(AgentRoomsReadService.unavailableMessage.contains("SQL"))
        XCTAssertFalse(AgentRoomsReadService.unavailableMessage.contains("/private"))
        XCTAssertEqual(service.loadWorkspace(), .empty)
        XCTAssertEqual(attempts, 2)
    }

    func testReadServiceAppliesHardRoomMessageAndRuntimeBounds() {
        let room = ConversationRoom(
            id: UUID(),
            stableKey: nil,
            title: "Bounded",
            kind: "chat",
            lifecycleState: .active,
            nextTurnSequence: 1,
            nextMessageSequence: 1,
            metadata: [:],
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000),
            archivedAt: nil,
            trashedAt: nil
        )
        var observedRoomLimit: Int?
        var observedMessageLimit: Int?
        var observedBindingLimit: Int?
        let service = AgentRoomsReadService(
            loadRooms: { lifecycle, limit in
                XCTAssertEqual(lifecycle, .active)
                observedRoomLimit = limit
                return [room]
            },
            loadRecentMessages: { roomID, limit in
                XCTAssertEqual(roomID, room.id)
                observedMessageLimit = limit
                return []
            },
            loadRuntimeBindings: { roomID, limit in
                XCTAssertEqual(roomID, room.id)
                observedBindingLimit = limit
                return []
            }
        )

        guard case .loaded = service.loadWorkspace() else { return XCTFail("Expected loaded projection") }
        XCTAssertEqual(observedRoomLimit, 20)
        XCTAssertEqual(observedMessageLimit, 100)
        XCTAssertEqual(observedBindingLimit, 20)
    }

    func testReadServiceDoesNotMutateCanonicalRowsOrSequences() throws {
        try withRepository { database, repository in
            let now = Date(timeIntervalSince1970: 20_000)
            let room = try repository.createRoom(.init(title: "Immutable", createdAt: now, updatedAt: now))
            let binding = try repository.upsertRuntimeBinding(.init(
                roomID: room.id,
                runtimeID: "codex",
                transportID: "process",
                sourceNamespace: "codex.process.v1",
                createdAt: now,
                updatedAt: now
            ))
            _ = try repository.upsertMessage(.init(
                roomID: room.id,
                runtimeBindingID: binding.id,
                role: "assistant",
                contentText: "Read only",
                createdAt: now
            ), intent: .historicalReplay)

            let roomBefore = try XCTUnwrap(repository.room(id: room.id))
            let messagesBefore = try repository.messages(roomID: room.id)
            let bindingsBefore = try repository.bindings(roomID: room.id)
            let countsBefore = try conversationRowCounts(database)

            let state = AgentRoomsReadService(repository: repository, now: { now }).loadWorkspace()
            guard case .loaded = state else { return XCTFail("Expected loaded projection") }

            XCTAssertEqual(try repository.room(id: room.id), roomBefore)
            XCTAssertEqual(try repository.messages(roomID: room.id), messagesBefore)
            XCTAssertEqual(try repository.bindings(roomID: room.id), bindingsBefore)
            XCTAssertEqual(try conversationRowCounts(database), countsBefore)
        }
    }

    func testRoomsSourcesContainNoWriteOrLegacyTransportDependencies() throws {
        let relativePaths = [
            "Sources/Cider/Models/AgentRoomsWorkspaceModels.swift",
            "Sources/Cider/Services/Conversation/AgentRoomsReadService.swift",
            "Sources/Cider/Views/AgentRooms/AgentRoomsWorkspaceView.swift",
        ]
        let prohibitedTerms = [
            "AIConversationStorage",
            "coordinator.save",
            "createRoom(",
            "upsert",
            "setLifecycle",
            "transition",
            "append",
            "ConversationShadow",
            "shadow activation",
            "registry write",
            "HermesBridgeTransport",
        ]

        for relativePath in relativePaths {
            let source = try String(
                contentsOf: Self.repositoryRoot.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            for term in prohibitedTerms {
                XCTAssertFalse(source.contains(term), "\(relativePath) must not reference \(term)")
            }
        }
    }

    func testProductionRoomsCompositionUsesCanonicalReaderWithoutFixtureFallback() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(
                "Sources/Cider/Views/CiderPanelView+ContentArea.swift"
            ),
            encoding: .utf8
        )
        let roomsComposition = try XCTUnwrap(
            source.range(of: "case .agentRooms:").flatMap { start in
                source.range(of: "case .aiAssistant:", range: start.upperBound..<source.endIndex)
                    .map { source[start.lowerBound..<$0.lowerBound] }
            }
        )
        XCTAssertTrue(roomsComposition.contains("AgentRoomsReadService"))
        XCTAssertTrue(roomsComposition.contains("ConversationRepository"))
        XCTAssertTrue(roomsComposition.contains("CiderDatabase.shared"))
        XCTAssertFalse(roomsComposition.contains("AgentRoomsFixtureProvider"))
    }

    private func withRepository<T>(_ body: (CiderDatabase, ConversationRepository) throws -> T) throws -> T {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-agent-rooms-\(UUID().uuidString).db")
        let database = CiderDatabase()
        try database.open(at: url)
        defer {
            database.close()
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(atPath: url.path + "-wal")
            try? FileManager.default.removeItem(atPath: url.path + "-shm")
        }
        return try body(database, ConversationRepository(database: database))
    }

    private func conversationRowCounts(_ database: CiderDatabase) throws -> [Int64] {
        let tables = [
            "conversation_rooms",
            "conversation_runtime_bindings",
            "conversation_turns",
            "conversation_messages",
        ]
        return try tables.map { table in
            let statement = try database.prepare("SELECT COUNT(*) FROM \(table);")
            XCTAssertTrue(try statement.step())
            return statement.int64(at: 0)
        }
    }
}
