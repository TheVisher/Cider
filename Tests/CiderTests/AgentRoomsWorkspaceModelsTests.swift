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
        guard case .loaded(let authority, let rooms, let selectedRoomID) = AgentRoomsFixtureProvider.workspaceState else {
            return XCTFail("Expected loaded fixture state")
        }

        XCTAssertEqual(authority, .canonicalIncomplete)
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
        XCTAssertEqual(
            AgentRoomsWorkspaceState.loading(authority: .canonicalIncomplete).projection(),
            .loading(authority: .canonicalIncomplete)
        )
        XCTAssertEqual(
            AgentRoomsWorkspaceState.empty(authority: .legacyAuthoritativePreview).projection(),
            .empty(authority: .legacyAuthoritativePreview)
        )
        XCTAssertEqual(
            AgentRoomsWorkspaceState.failed(
                authority: .canonicalIncomplete,
                message: "Fixture unavailable"
            ).projection(),
            .failed(authority: .canonicalIncomplete, message: "Fixture unavailable")
        )

        guard case .loaded(_, let rooms, _) = AgentRoomsFixtureProvider.workspaceState,
              case .loaded(let authority, let projectedRooms, let selectedRoom) = AgentRoomsFixtureProvider.workspaceState.projection() else {
            return XCTFail("Expected loaded fixture projection")
        }
        XCTAssertEqual(authority, .canonicalIncomplete)
        XCTAssertEqual(projectedRooms, rooms)
        XCTAssertEqual(selectedRoom.id, "cider-product")
    }

    func testLoadedProjectionFallsBackToFirstRoomForInvalidSelection() {
        guard case .loaded(_, let rooms, _) = AgentRoomsFixtureProvider.workspaceState else {
            return XCTFail("Expected loaded fixture state")
        }

        let invalidStoredSelection = AgentRoomsWorkspaceState.loaded(
            authority: .canonicalIncomplete,
            rooms: rooms,
            selectedRoomID: "missing-room"
        )
        guard case .loaded(_, _, let storedFallback) = invalidStoredSelection.projection() else {
            return XCTFail("Expected loaded fallback projection")
        }
        XCTAssertEqual(storedFallback.id, rooms[0].id)

        guard case .loaded(_, _, let localFallback) = AgentRoomsFixtureProvider.workspaceState.projection(
            selectedRoomID: "missing-local-room"
        ) else {
            return XCTFail("Expected loaded local fallback projection")
        }
        XCTAssertEqual(localFallback.id, rooms[0].id)
        XCTAssertEqual(
            AgentRoomsWorkspaceState.loaded(
                authority: .legacyAuthoritativePreview,
                rooms: [],
                selectedRoomID: "missing"
            ).projection(),
            .empty(authority: .legacyAuthoritativePreview)
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
            guard case .loaded(let authority, let rooms, let selectedRoomID) = state else {
                return XCTFail("Expected loaded canonical projection")
            }

            XCTAssertEqual(authority, .canonicalIncomplete)
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
            loadRecentTurns: { _, _ in [] },
            now: { Date(timeIntervalSince1970: 10_000) }
        )

        XCTAssertEqual(
            service.loadWorkspace(),
            .failed(authority: .canonicalIncomplete, message: AgentRoomsReadService.unavailableMessage)
        )
        XCTAssertFalse(AgentRoomsReadService.unavailableMessage.contains("SQL"))
        XCTAssertFalse(AgentRoomsReadService.unavailableMessage.contains("/private"))
        XCTAssertEqual(service.loadWorkspace(), .empty(authority: .canonicalIncomplete))
        XCTAssertEqual(attempts, 2)
    }

    func testRecentTurnReadFailureUsesExistingSanitizedUnavailableState() {
        let room = makeRoom()
        let service = AgentRoomsReadService(
            loadRooms: { _, _ in [room] },
            loadRecentMessages: { _, _ in [] },
            loadRuntimeBindings: { _, _ in [] },
            loadRecentTurns: { _, _ in
                throw NSError(
                    domain: "SQL /private/vault.db Authorization: Bearer private-message",
                    code: 1
                )
            }
        )

        XCTAssertEqual(
            service.loadWorkspace(),
            .failed(authority: .canonicalIncomplete, message: AgentRoomsReadService.unavailableMessage)
        )
        XCTAssertEqual(
            AgentRoomsReadService.unavailableMessage,
            "Canonical Rooms data is temporarily unavailable. Try again."
        )
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
        var observedTurnLimit: Int?
        var requestedTurnRoomIDs: [UUID] = []
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
            },
            loadRecentTurns: { roomID, limit in
                requestedTurnRoomIDs.append(roomID)
                observedTurnLimit = limit
                return []
            }
        )

        guard case .loaded = service.loadWorkspace() else { return XCTFail("Expected loaded projection") }
        XCTAssertEqual(observedRoomLimit, 20)
        XCTAssertEqual(observedMessageLimit, 100)
        XCTAssertEqual(observedBindingLimit, 20)
        XCTAssertEqual(observedTurnLimit, 1)
        XCTAssertEqual(requestedTurnRoomIDs, [room.id])
    }

    func testReadServiceRequestsExactlyOneNewestTurnForEveryLoadedRoom() {
        let rooms = [makeRoom(title: "First"), makeRoom(title: "Second")]
        var requests: [(UUID, Int)] = []
        let service = AgentRoomsReadService(
            loadRooms: { _, limit in
                XCTAssertEqual(limit, 20)
                return rooms
            },
            loadRecentMessages: { _, limit in
                XCTAssertEqual(limit, 100)
                return []
            },
            loadRuntimeBindings: { _, limit in
                XCTAssertEqual(limit, 20)
                return []
            },
            loadRecentTurns: { roomID, limit in
                requests.append((roomID, limit))
                return []
            }
        )

        guard case .loaded = service.loadWorkspace() else { return XCTFail("Expected loaded projection") }
        XCTAssertEqual(requests.map(\.0), rooms.map(\.id))
        XCTAssertEqual(requests.map(\.1), [1, 1])
    }

    func testReadServiceMapsEligibleTerminalTurnsToGenericReceipts() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let room = makeRoom()
        let binding = makeBinding(roomID: room.id, runtimeID: "hermes")
        let cases: [(ConversationTurnStatus, AgentRoomReceiptStatus, String)] = [
            (.completed, .completed, "Hermes completed a turn"),
            (.failed, .failed, "Hermes turn failed"),
            (.cancelled, .cancelled, "Hermes turn cancelled"),
        ]

        for (turnStatus, receiptStatus, title) in cases {
            let turn = makeTurn(
                roomID: room.id,
                bindingID: binding.id,
                status: turnStatus,
                completedAt: now.addingTimeInterval(-60)
            )
            let mapped = try loadedRoom(
                room: room,
                bindings: [binding],
                turns: [turn],
                now: now
            )

            XCTAssertEqual(mapped.transcript.receipt, AgentRoomReceipt(
                id: turn.id.uuidString,
                title: title,
                detail: "Source-backed canonical turn · 1m",
                status: receiptStatus
            ))
        }
    }

    func testReceiptRuntimeComesFromTheTurnsExactRoomBinding() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let room = makeRoom()
        let activeHermes = makeBinding(roomID: room.id, runtimeID: "hermes")
        var turnCodex = makeBinding(roomID: room.id, runtimeID: "codex")
        turnCodex.state = .inactive
        let turn = makeTurn(
            roomID: room.id,
            bindingID: turnCodex.id,
            completedAt: now
        )

        let mapped = try loadedRoom(
            room: room,
            bindings: [activeHermes, turnCodex],
            turns: [turn],
            now: now
        )
        XCTAssertEqual(mapped.transcript.runtimeLabel, "Hermes")
        XCTAssertEqual(mapped.transcript.receipt?.title, "Codex completed a turn")
    }

    func testReadServiceOmitsMalformedUnboundAndNonterminalNewestTurns() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let room = makeRoom()
        let binding = makeBinding(roomID: room.id)
        let otherRoomBinding = makeBinding(roomID: UUID())
        let base = makeTurn(roomID: room.id, bindingID: binding.id, completedAt: now)
        var missingSource = base
        missingSource.source = nil
        var missingBinding = base
        missingBinding.runtimeBindingID = nil
        var unknownBinding = base
        unknownBinding.runtimeBindingID = UUID()
        var crossRoomBinding = base
        crossRoomBinding.runtimeBindingID = otherRoomBinding.id
        var missingCompletedAt = base
        missingCompletedAt.completedAt = nil
        let ineligible: [ConversationTurn] = [
            missingSource,
            replacingSource(base, with: .init(namespace: "   ", id: "turn")),
            replacingSource(base, with: .init(namespace: "source", id: "\n\t")),
            missingBinding,
            unknownBinding,
            crossRoomBinding,
            missingCompletedAt,
        ] + [ConversationTurnStatus.unknown, .pending, .running, .waiting].map {
            var copy = base
            copy.status = $0
            return copy
        }

        for turn in ineligible {
            let mapped = try loadedRoom(
                room: room,
                bindings: [binding, otherRoomBinding],
                turns: [turn],
                now: now
            )
            XCTAssertNil(mapped.transcript.receipt, "Expected no receipt for \(turn)")
        }
    }

    func testNewestIneligibleTurnHidesOlderEligibleReceipt() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let room = makeRoom()
        let binding = makeBinding(roomID: room.id)
        let newest = makeTurn(
            roomID: room.id,
            sequence: 2,
            bindingID: binding.id,
            status: .running,
            completedAt: nil
        )
        let older = makeTurn(
            roomID: room.id,
            sequence: 1,
            bindingID: binding.id,
            status: .completed,
            completedAt: now.addingTimeInterval(-60)
        )

        let mapped = try loadedRoom(
            room: room,
            bindings: [binding],
            turns: [newest, older],
            now: now
        )
        XCTAssertNil(mapped.transcript.receipt)
    }

    func testReceiptMappingNeverExposesRawSourceErrorOrPrivateEvidence() throws {
        let privateEvidence = "SQL /private/vault.db Authorization: Bearer secret private-message"
        let now = Date(timeIntervalSince1970: 10_000)
        let room = makeRoom()
        let binding = makeBinding(roomID: room.id, runtimeID: "codex")
        let turn = makeTurn(
            roomID: room.id,
            bindingID: binding.id,
            source: .init(namespace: privateEvidence, id: privateEvidence),
            status: .failed,
            error: .init(code: privateEvidence, detail: privateEvidence),
            completedAt: now
        )

        let mapped = try loadedRoom(room: room, bindings: [binding], turns: [turn], now: now)
        let receipt = try XCTUnwrap(mapped.transcript.receipt)
        XCTAssertEqual(receipt.title, "Codex turn failed")
        XCTAssertEqual(receipt.detail, "Source-backed canonical turn · Now")
        XCTAssertFalse(String(describing: receipt).contains(privateEvidence))

        let viewSource = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(
                "Sources/Cider/Views/AgentRooms/AgentRoomsWorkspaceView.swift"
            ),
            encoding: .utf8
        )
        XCTAssertFalse(viewSource.contains(privateEvidence))
    }

    func testReceiptOutcomesHaveDistinctIconsSemanticColorsAndVoiceOverWording() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(
                "Sources/Cider/Views/AgentRooms/AgentRoomsWorkspaceView.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("checkmark.circle.fill"))
        XCTAssertTrue(source.contains("xmark.octagon.fill"))
        XCTAssertTrue(source.contains("slash.circle.fill"))
        XCTAssertTrue(source.contains("CiderColors.success"))
        XCTAssertTrue(source.contains("CiderColors.destructive"))
        XCTAssertTrue(source.contains("CiderColors.warning"))
        XCTAssertTrue(source.contains("Completed canonical turn receipt"))
        XCTAssertTrue(source.contains("Failed canonical turn receipt"))
        XCTAssertTrue(source.contains("Cancelled canonical turn receipt"))
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
            let turn = try repository.beginTurn(.init(
                roomID: room.id,
                runtimeBindingID: binding.id,
                source: .init(namespace: "codex.process.v1", id: "turn-1")
            ))
            _ = try repository.transitionTurn(id: turn.id, to: .running, at: now)
            _ = try repository.transitionTurn(id: turn.id, to: .completed, at: now)

            let roomBefore = try XCTUnwrap(repository.room(id: room.id))
            let messagesBefore = try repository.messages(roomID: room.id)
            let bindingsBefore = try repository.bindings(roomID: room.id)
            let turnsBefore = try repository.turns(roomID: room.id)
            let countsBefore = try conversationRowCounts(database)

            let state = AgentRoomsReadService(repository: repository, now: { now }).loadWorkspace()
            guard case .loaded = state else { return XCTFail("Expected loaded projection") }

            XCTAssertEqual(try repository.room(id: room.id), roomBefore)
            XCTAssertEqual(try repository.messages(roomID: room.id), messagesBefore)
            XCTAssertEqual(try repository.bindings(roomID: room.id), bindingsBefore)
            XCTAssertEqual(try repository.turns(roomID: room.id), turnsBefore)
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
            "AIAssistantViewModel",
            "AgentOrchestrator",
            "LegacyConversationSnapshotMapper",
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

    func testProductionRoomsCompositionUsesExactStrictEmptyStateArbitrationWithoutForbiddenDependencies() throws {
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
        for required in [
            "let repository = ConversationRepository(database: CiderDatabase.shared)",
            "AgentRoomsReadService(repository: repository)",
            "loadWorkspace: { request in",
            "canonical.loadWorkspace(request: request)",
            "StoragePaths.legacyConversationPreviewDirectories()",
            "let parityReader = ConversationRepositoryParityReader(repository: repository)",
            "LegacyConversationEligiblePreviewService(",
            "canonicalIsHonestlyEmpty:",
            "repository.rooms(lifecycle: .active, limit: 1).isEmpty",
            "EligibleLegacyAgentRoomsPreviewService(loadPreview: eligible.preview)",
            "AgentRoomsWorkspaceLoader(",
            "loadCanonical: canonical.loadWorkspace",
            "loadLegacy: eligibleAdapter.loadWorkspace",
            ").loadWorkspace()",
            "roomActions: AgentRoomsActionService(repository: repository)",
        ] {
            XCTAssertTrue(roomsComposition.contains(required), "Missing strict production composition: \(required)")
        }
        XCTAssertEqual(roomsComposition.components(separatedBy: "ConversationRepository(database:").count - 1, 1)
        XCTAssertNil(roomsComposition.range(of: #"\bLegacyAgentRoomsPreviewService\("#, options: .regularExpression))
        for prohibited in [
            "AgentRoomsFixtureProvider", "AIConversationStorage", "CiderAgentChatRegistry",
            "PrimarySaveCoordinator", "ShadowWriter", "Reconciler", "HealthStore", "backfill",
            "import", "BridgeTransport", "tolerant", "createDirectory",
        ] {
            XCTAssertFalse(
                roomsComposition.localizedCaseInsensitiveContains(prohibited),
                "Production Rooms composition must exclude \(prohibited)"
            )
        }
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

    private func makeRoom(title: String = "Room") -> ConversationRoom {
        ConversationRoom(
            id: UUID(),
            stableKey: nil,
            title: title,
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
    }

    private func makeBinding(
        roomID: UUID,
        runtimeID: String = "hermes"
    ) -> ConversationRuntimeBinding {
        ConversationRuntimeBinding(
            id: UUID(),
            roomID: roomID,
            parentBindingID: nil,
            runtimeID: runtimeID,
            transportID: "bounded-read-test",
            sourceNamespace: "test.runtime.v1",
            externalSessionID: nil,
            state: .active,
            cursorMessageID: nil,
            cursorTimestamp: nil,
            metadata: [:],
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func makeTurn(
        roomID: UUID,
        sequence: Int64 = 1,
        bindingID: UUID?,
        source: ConversationSourceIdentity? = .init(namespace: "test.turn.v1", id: "turn-1"),
        status: ConversationTurnStatus = .completed,
        error: ConversationTurnError? = nil,
        completedAt: Date?
    ) -> ConversationTurn {
        ConversationTurn(
            id: UUID(),
            roomID: roomID,
            sequence: sequence,
            runtimeBindingID: bindingID,
            source: source,
            status: status,
            error: error,
            metadata: [:],
            createdAt: Date(timeIntervalSince1970: 1_000),
            startedAt: Date(timeIntervalSince1970: 1_001),
            completedAt: completedAt,
            updatedAt: completedAt ?? Date(timeIntervalSince1970: 1_001)
        )
    }

    private func replacingSource(
        _ turn: ConversationTurn,
        with source: ConversationSourceIdentity
    ) -> ConversationTurn {
        var copy = turn
        copy.source = source
        return copy
    }

    private func loadedRoom(
        room: ConversationRoom,
        bindings: [ConversationRuntimeBinding],
        turns: [ConversationTurn],
        now: Date
    ) throws -> AgentRoom {
        let service = AgentRoomsReadService(
            loadRooms: { _, _ in [room] },
            loadRecentMessages: { _, _ in [] },
            loadRuntimeBindings: { _, _ in bindings },
            loadRecentTurns: { roomID, limit in
                XCTAssertEqual(roomID, room.id)
                XCTAssertEqual(limit, 1)
                return turns
            },
            now: { now }
        )
        guard case .loaded(_, let rooms, _) = service.loadWorkspace() else {
            throw NSError(domain: "Expected loaded Rooms state", code: 1)
        }
        return try XCTUnwrap(rooms.first)
    }
}
