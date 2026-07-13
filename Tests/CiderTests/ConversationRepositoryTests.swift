import Foundation
import Testing
@testable import Cider

@Suite("ConversationRepository Tests")
@MainActor
struct ConversationRepositoryTests {
    private func withRepository<T>(_ body: (CiderDatabase, ConversationRepository) throws -> T) throws -> T {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-conversation-\(UUID().uuidString).db")
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

    private func roomDraft(id: UUID = UUID(), stableKey: String? = nil, title: String = "Room") -> ConversationRoomDraft {
        ConversationRoomDraft(id: id, stableKey: stableKey, title: title)
    }

    @Test("Room identity and lifecycle round-trip through repository reads")
    func roomIdentityAndLifecycle() throws {
        try withRepository { _, repository in
            let archivedAt = Date(timeIntervalSince1970: 5_000)
            let room = try repository.createRoom(roomDraft(stableKey: "cider.main", title: "Main Brain"))
            #expect(try repository.room(stableKey: "cider.main")?.id == room.id)
            try repository.setLifecycle(roomID: room.id, state: .archived, at: archivedAt)
            let archived = try #require(try repository.room(id: room.id))
            #expect(archived.lifecycleState == .archived)
            #expect(archived.archivedAt == archivedAt)
        }
    }

    @Test("Historical room and binding drafts preserve explicit updated timestamps")
    func explicitHistoricalUpdatedTimestamps() throws {
        try withRepository { _, repository in
            let createdAt = Date(timeIntervalSince1970: 1_000)
            let updatedAt = Date(timeIntervalSince1970: 2_000)
            let room = try repository.createRoom(.init(
                title: "Historical",
                createdAt: createdAt,
                updatedAt: updatedAt
            ))
            let binding = try repository.upsertRuntimeBinding(.init(
                roomID: room.id,
                runtimeID: "hermes",
                transportID: "legacy",
                sourceNamespace: "legacy.runtime-binding.v1.hermes",
                createdAt: createdAt,
                updatedAt: updatedAt
            ))

            #expect(room.createdAt == createdAt)
            #expect(room.updatedAt == updatedAt)
            #expect(binding.createdAt == createdAt)
            #expect(binding.updatedAt == updatedAt)

            let liveCreatedAt = Date(timeIntervalSince1970: 3_000)
            let liveRoom = try repository.createRoom(.init(title: "Live", createdAt: liveCreatedAt))
            #expect(liveRoom.updatedAt == liveCreatedAt)
        }
    }

    @Test("Equal timestamps read in allocated message sequence order")
    func deterministicMessageOrdering() throws {
        try withRepository { _, repository in
            let room = try repository.createRoom(roomDraft())
            let timestamp = Date(timeIntervalSince1970: 1_000)
            let first = try repository.upsertMessage(.init(roomID: room.id, role: "user", contentText: "first", createdAt: timestamp), intent: .historicalReplay)
            let second = try repository.upsertMessage(.init(roomID: room.id, role: "assistant", contentText: "second", createdAt: timestamp), intent: .historicalReplay)

            #expect(first.message.sequence == 1)
            #expect(second.message.sequence == 2)
            #expect(try repository.messages(roomID: room.id).map(\.contentText) == ["first", "second"])
        }
    }

    @Test("Bounded room reads filter lifecycle and deterministically order equal timestamps")
    func boundedRoomReads() throws {
        try withRepository { _, repository in
            let timestamp = Date(timeIntervalSince1970: 1_000)
            let older = try repository.createRoom(.init(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                title: "Older",
                createdAt: timestamp.addingTimeInterval(-1),
                updatedAt: timestamp.addingTimeInterval(-1)
            ))
            let second = try repository.createRoom(.init(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                title: "Second",
                createdAt: timestamp,
                updatedAt: timestamp
            ))
            let first = try repository.createRoom(.init(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                title: "First",
                createdAt: timestamp,
                updatedAt: timestamp
            ))
            let archived = try repository.createRoom(.init(title: "Archived", createdAt: timestamp.addingTimeInterval(1)))
            try repository.setLifecycle(roomID: archived.id, state: .archived, at: timestamp.addingTimeInterval(2))

            let rooms = try repository.rooms(lifecycle: .active, limit: 2)
            #expect(rooms.map(\.id) == [first.id, second.id])
            #expect(!rooms.contains(where: { $0.id == older.id }))
            #expect(!rooms.contains(where: { $0.id == archived.id }))
            #expect(throws: ConversationRepositoryError.self) {
                try repository.rooms(lifecycle: .active, limit: 0)
            }
        }
    }

    @Test("Room rename and lifecycle changes preserve canonical identity and durable history")
    func roomManagementPreservesIdentityAndHistory() throws {
        try withRepository { _, repository in
            let createdAt = Date(timeIntervalSince1970: 1_000)
            let changedAt = Date(timeIntervalSince1970: 2_000)
            let room = try repository.createRoom(.init(
                stableKey: "cider.room.management-test",
                title: "Planning",
                createdAt: createdAt
            ))
            let binding = try repository.upsertRuntimeBinding(.init(
                roomID: room.id,
                runtimeID: "hermes",
                transportID: "runs-api",
                sourceNamespace: "hermes.runs.v1",
                externalSessionID: "rotating-runtime-session"
            ))
            let message = try repository.upsertMessage(.init(
                roomID: room.id,
                runtimeBindingID: binding.id,
                role: "user",
                contentText: "Keep this durable transcript"
            ), intent: .historicalReplay).message

            let renamed = try repository.renameRoom(
                roomID: room.id,
                title: "Launch Planning",
                at: changedAt
            )
            try repository.setLifecycle(roomID: room.id, state: .archived, at: changedAt)
            let archived = try #require(try repository.room(id: room.id))
            try repository.setLifecycle(roomID: room.id, state: .active, at: changedAt.addingTimeInterval(1))
            let restored = try #require(try repository.room(id: room.id))

            #expect(renamed.id == room.id)
            #expect(renamed.stableKey == room.stableKey)
            #expect(renamed.title == "Launch Planning")
            #expect(archived.id == room.id)
            #expect(archived.lifecycleState == .archived)
            #expect(restored.id == room.id)
            #expect(restored.lifecycleState == .active)
            #expect(restored.archivedAt == nil)
            #expect(try repository.messages(roomID: room.id).map(\.id) == [message.id])
            #expect(try repository.bindings(roomID: room.id).map(\.id) == [binding.id])
        }
    }

    @Test("Room search is lifecycle scoped, history aware, literal, and deterministic")
    func roomSearch() throws {
        try withRepository { _, repository in
            let timestamp = Date(timeIntervalSince1970: 1_000)
            let titleMatch = try repository.createRoom(.init(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                title: "Summer Plans 100%",
                createdAt: timestamp,
                updatedAt: timestamp
            ))
            let transcriptMatch = try repository.createRoom(.init(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                title: "Ideas",
                createdAt: timestamp,
                updatedAt: timestamp
            ))
            let archived = try repository.createRoom(.init(
                title: "Archived Summer Plans",
                createdAt: timestamp.addingTimeInterval(1),
                updatedAt: timestamp.addingTimeInterval(1)
            ))
            _ = try repository.upsertMessage(.init(
                roomID: transcriptMatch.id,
                role: "assistant",
                contentText: "The summer itinerary is ready"
            ), intent: .historicalReplay)
            try repository.setLifecycle(roomID: archived.id, state: .archived, at: timestamp.addingTimeInterval(2))

            let activeSummer = try repository.searchRooms(
                query: "summer",
                lifecycle: .active,
                limit: 20
            )
            let archivedSummer = try repository.searchRooms(
                query: "summer",
                lifecycle: .archived,
                limit: 20
            )
            let literalPercent = try repository.searchRooms(
                query: "%",
                lifecycle: .active,
                limit: 20
            )

            #expect(activeSummer.map(\.id) == [transcriptMatch.id, titleMatch.id])
            #expect(archivedSummer.map(\.id) == [archived.id])
            #expect(literalPercent.map(\.id) == [titleMatch.id])
            #expect(throws: ConversationRepositoryError.self) {
                try repository.searchRooms(query: "summer", lifecycle: .active, limit: 0)
            }
        }
    }

    @Test("Bounded recent messages select newest and return ascending sequence")
    func boundedRecentMessages() throws {
        try withRepository { _, repository in
            let room = try repository.createRoom(roomDraft())
            for index in 1...5 {
                _ = try repository.upsertMessage(.init(
                    roomID: room.id,
                    role: index.isMultiple(of: 2) ? "assistant" : "user",
                    contentText: "message-\(index)"
                ), intent: .historicalReplay)
            }

            let recent = try repository.recentMessages(roomID: room.id, limit: 3)
            #expect(recent.map(\.sequence) == [3, 4, 5])
            #expect(recent.map(\.contentText) == ["message-3", "message-4", "message-5"])
            #expect(throws: ConversationRepositoryError.self) {
                try repository.recentMessages(roomID: room.id, limit: -1)
            }
        }
    }

    @Test("Bounded recent turns require a positive limit, clamp, and return newest first")
    func boundedRecentTurns() throws {
        try withRepository { _, repository in
            let room = try repository.createRoom(roomDraft())
            for _ in 1...501 {
                _ = try repository.beginTurn(.init(roomID: room.id))
            }

            let recent = try repository.recentTurns(roomID: room.id, limit: 3)
            #expect(recent.map(\.sequence) == [501, 500, 499])

            let clamped = try repository.recentTurns(roomID: room.id, limit: 999)
            #expect(clamped.count == 500)
            #expect(clamped.first?.sequence == 501)
            #expect(clamped.last?.sequence == 2)

            #expect(throws: ConversationRepositoryError.self) {
                try repository.recentTurns(roomID: room.id, limit: 0)
            }
            #expect(throws: ConversationRepositoryError.self) {
                try repository.recentTurns(roomID: room.id, limit: -1)
            }
        }
    }

    @Test("Source replay is idempotent and does not consume a sequence")
    func sourceReplayDoesNotConsumeSequence() throws {
        try withRepository { _, repository in
            let room = try repository.createRoom(roomDraft())
            let source = ConversationSourceIdentity(namespace: "hermes.export.v1", id: "session:message")
            let timestamp = Date(timeIntervalSince1970: 1_000)
            let draft = ConversationMessageDraft(
                roomID: room.id,
                role: "user",
                contentText: "hello",
                source: source,
                createdAt: timestamp
            )

            let inserted = try repository.upsertMessage(draft, intent: .historicalReplay)
            let replayed = try repository.upsertMessage(draft, intent: .historicalReplay)
            let local = try repository.upsertMessage(.init(roomID: room.id, role: "assistant", contentText: "next"), intent: .historicalReplay)

            #expect(inserted.disposition == .inserted)
            #expect(replayed.disposition == .unchangedReplay)
            #expect(replayed.message.id == inserted.message.id)
            #expect(local.message.sequence == 2)
        }
    }

    @Test("Turn source replay is idempotent and does not consume a sequence")
    func turnSourceReplayDoesNotConsumeSequence() throws {
        try withRepository { _, repository in
            let room = try repository.createRoom(roomDraft())
            let draft = ConversationTurnDraft(
                roomID: room.id,
                source: .init(namespace: "hermes.runs.v1", id: "run-1")
            )
            let inserted = try repository.beginTurn(draft)
            let replayed = try repository.beginTurn(draft)
            let local = try repository.beginTurn(.init(roomID: room.id))
            #expect(replayed.id == inserted.id)
            #expect(local.sequence == 2)
        }
    }

    @Test("Active turn execution binding preserves room identity and becomes immutable at terminal")
    func activeTurnExecutionBinding() throws {
        try withRepository { _, repository in
            let room = try repository.createRoom(roomDraft(title: "Stable room"))
            let binding = try repository.upsertRuntimeBinding(.init(
                roomID: room.id,
                runtimeID: "hermes",
                transportID: "runs-api",
                sourceNamespace: "hermes.runs.v1",
                externalSessionID: "replaceable-session"
            ))
            let turn = try repository.beginTurn(.init(
                roomID: room.id,
                status: .pending,
                metadata: ["attempt": "local"]
            ))
            let source = ConversationSourceIdentity(namespace: "hermes.runs.v1", id: "run-one")
            let bound = try repository.bindActiveTurnExecution(
                id: turn.id,
                runtimeBindingID: binding.id,
                source: source,
                metadata: ["attempt": "accepted", "run": "run-one"],
                at: Date(timeIntervalSince1970: 2_000)
            )
            let replay = try repository.bindActiveTurnExecution(
                id: turn.id,
                runtimeBindingID: binding.id,
                source: source,
                metadata: bound.metadata,
                at: Date(timeIntervalSince1970: 2_001)
            )

            #expect(bound.id == turn.id)
            #expect(bound.roomID == room.id)
            #expect(bound.runtimeBindingID == binding.id)
            #expect(bound.source == source)
            #expect(replay.roomID == room.id)
            #expect(try repository.room(id: room.id)?.id == room.id)

            _ = try repository.transitionTurn(id: turn.id, to: .completed, at: Date(timeIntervalSince1970: 3_000))
            #expect(throws: ConversationRepositoryError.self) {
                try repository.bindActiveTurnExecution(
                    id: turn.id,
                    runtimeBindingID: binding.id,
                    source: source,
                    metadata: ["attempt": "rewritten"],
                    at: Date(timeIntervalSince1970: 4_000)
                )
            }
            #expect(try repository.turn(id: turn.id)?.status == .completed)
        }
    }

    @Test("Source identity is namespaced globally across rooms")
    func sourceIdentityNamespaceAndRoomRules() throws {
        try withRepository { _, repository in
            let firstRoom = try repository.createRoom(roomDraft())
            let secondRoom = try repository.createRoom(roomDraft())
            let sharedID = "shared"

            _ = try repository.upsertMessage(.init(
                roomID: firstRoom.id,
                role: "user",
                contentText: "Hermes",
                source: .init(namespace: "hermes.export.v1", id: sharedID)
            ), intent: .historicalReplay)
            _ = try repository.upsertMessage(.init(
                roomID: secondRoom.id,
                role: "user",
                contentText: "Codex",
                source: .init(namespace: "codex.rollout.v1", id: sharedID)
            ), intent: .historicalReplay)

            #expect(throws: ConversationRepositoryError.self) {
                try repository.upsertMessage(.init(
                    roomID: secondRoom.id,
                    role: "user",
                    contentText: "conflict",
                    source: .init(namespace: "hermes.export.v1", id: sharedID)
                ), intent: .historicalReplay)
            }
        }
    }

    @Test("Multiple runtime and transport bindings coexist in one room")
    func multipleRuntimeBindings() throws {
        try withRepository { _, repository in
            let room = try repository.createRoom(roomDraft())
            let drafts = [
                ConversationRuntimeBindingDraft(roomID: room.id, runtimeID: "hermes", transportID: "runs", sourceNamespace: "hermes.runs.v1", externalSessionID: "h-1"),
                ConversationRuntimeBindingDraft(roomID: room.id, runtimeID: "hermes", transportID: "api", sourceNamespace: "hermes.api.v1", externalSessionID: "h-2"),
                ConversationRuntimeBindingDraft(roomID: room.id, runtimeID: "cider-cli", transportID: "cli", sourceNamespace: "cider.cli.v1", externalSessionID: "cli-1"),
                ConversationRuntimeBindingDraft(roomID: room.id, runtimeID: "codex", transportID: "process", sourceNamespace: "codex.process.v1", externalSessionID: "c-1"),
            ]
            for draft in drafts { _ = try repository.upsertRuntimeBinding(draft) }

            let bindings = try repository.bindings(roomID: room.id)
            #expect(bindings.count == 4)
            #expect(Set(bindings.map(\.sourceNamespace)) == Set(drafts.map(\.sourceNamespace)))
        }
    }

    @Test("Runtime binding UUID fallback rejects cross-room ownership before mutation")
    func runtimeBindingUUIDFallbackRejectsCrossRoomOwnership() throws {
        try withRepository { _, repository in
            let firstRoom = try repository.createRoom(roomDraft())
            let secondRoom = try repository.createRoom(roomDraft())
            let bindingID = UUID()
            let original = try repository.upsertRuntimeBinding(.init(
                id: bindingID,
                roomID: firstRoom.id,
                runtimeID: "hermes",
                transportID: "runs",
                sourceNamespace: "hermes.runs.v1",
                metadata: ["owner": "first"]
            ))
            let firstRoomBefore = try #require(try repository.room(id: firstRoom.id))
            let secondRoomBefore = try #require(try repository.room(id: secondRoom.id))

            #expect(throws: ConversationRepositoryError.self) {
                try repository.upsertRuntimeBinding(.init(
                    id: bindingID,
                    roomID: secondRoom.id,
                    runtimeID: "codex",
                    transportID: "process",
                    sourceNamespace: "codex.process.v1",
                    externalSessionID: "external-lookup-miss",
                    metadata: ["owner": "second"]
                ))
            }

            #expect(try repository.bindings(roomID: firstRoom.id) == [original])
            #expect(try repository.bindings(roomID: secondRoom.id).isEmpty)
            #expect(try repository.room(id: firstRoom.id) == firstRoomBefore)
            #expect(try repository.room(id: secondRoom.id) == secondRoomBefore)
        }
    }

    @Test("Historical replay accepts only fully equivalent persisted messages")
    func historicalReplayRequiresPersistedEquivalence() throws {
        try withRepository { _, repository in
            let room = try repository.createRoom(roomDraft())
            let binding = try repository.upsertRuntimeBinding(.init(
                roomID: room.id,
                runtimeID: "hermes",
                transportID: "runs",
                sourceNamespace: "hermes.runs.v1"
            ))
            let turn = try repository.beginTurn(.init(roomID: room.id, runtimeBindingID: binding.id))
            let parent = try repository.upsertMessage(.init(
                roomID: room.id,
                turnID: turn.id,
                runtimeBindingID: binding.id,
                role: "user",
                contentText: "parent",
                createdAt: Date(timeIntervalSince1970: 1_000)
            ), intent: .historicalReplay).message
            let createdAt = Date(timeIntervalSince1970: 2_000)
            let sourceCreatedAt = Date(timeIntervalSince1970: 1_900)
            let draft = ConversationMessageDraft(
                id: UUID(),
                roomID: room.id,
                turnID: turn.id,
                runtimeBindingID: binding.id,
                parentMessageID: parent.id,
                role: "assistant",
                contentText: "historical",
                status: .incomplete,
                finishReason: .error,
                source: .init(namespace: "hermes.export.v1", id: "session:message"),
                sourceCreatedAt: sourceCreatedAt,
                metadata: ["kind": "history"],
                createdAt: createdAt
            )
            let inserted = try repository.upsertMessage(draft, intent: .historicalReplay)
            let roomBefore = try #require(try repository.room(id: room.id))
            let messagesBefore = try repository.messages(roomID: room.id)
            let ancestryBefore = try repository.messages(roomID: room.id, throughHead: inserted.message.id)

            let replay = try repository.upsertMessage(draft, intent: .historicalReplay)
            #expect(replay.disposition == .unchangedReplay)
            #expect(replay.message == inserted.message)
            #expect(try repository.room(id: room.id) == roomBefore)

            @MainActor
            func expectRejected(_ conflicting: ConversationMessageDraft) throws {
                #expect(throws: ConversationRepositoryError.self) {
                    try repository.upsertMessage(conflicting, intent: .historicalReplay)
                }
                #expect(try repository.messages(roomID: room.id) == messagesBefore)
                #expect(try repository.messages(roomID: room.id, throughHead: inserted.message.id) == ancestryBefore)
                #expect(try repository.room(id: room.id) == roomBefore)
            }

            var conflict = draft
            conflict.contentText = "changed"
            try expectRejected(conflict)
            conflict = draft
            conflict.role = "user"
            try expectRejected(conflict)
            conflict = draft
            conflict.parentMessageID = nil
            try expectRejected(conflict)
            conflict = draft
            conflict.status = .complete
            try expectRejected(conflict)
            conflict = draft
            conflict.finishReason = .length
            try expectRejected(conflict)
            conflict = draft
            conflict.metadata = ["kind": "changed"]
            try expectRejected(conflict)
            conflict = draft
            conflict.sourceCreatedAt = Date(timeIntervalSince1970: 1_901)
            try expectRejected(conflict)
            conflict = draft
            conflict.createdAt = Date(timeIntervalSince1970: 2_001)
            try expectRejected(conflict)
            conflict = draft
            conflict.turnID = nil
            try expectRejected(conflict)
            conflict = draft
            conflict.runtimeBindingID = nil
            try expectRejected(conflict)
            conflict = draft
            conflict.id = UUID()
            try expectRejected(conflict)
            conflict = draft
            conflict.source = .init(namespace: "hermes.export.v1", id: "different")
            try expectRejected(conflict)

            let localID = UUID()
            let localDraft = ConversationMessageDraft(
                id: localID,
                roomID: room.id,
                role: "system",
                contentText: "local",
                createdAt: Date(timeIntervalSince1970: 3_000)
            )
            _ = try repository.upsertMessage(localDraft, intent: .historicalReplay)
            let localRoomBefore = try #require(try repository.room(id: room.id))
            let localMessagesBefore = try repository.messages(roomID: room.id)
            var localConflict = localDraft
            localConflict.contentText = "rewritten"
            #expect(throws: ConversationRepositoryError.self) {
                try repository.upsertMessage(localConflict, intent: .historicalReplay)
            }
            #expect(try repository.messages(roomID: room.id) == localMessagesBefore)
            #expect(try repository.room(id: room.id) == localRoomBefore)
        }
    }

    @Test("Live continuation advances active messages and rejects structural or terminal rewrites")
    func liveContinuationStateMachineAndImmutability() throws {
        try withRepository { _, repository in
            let room = try repository.createRoom(roomDraft())
            let binding = try repository.upsertRuntimeBinding(.init(
                roomID: room.id,
                runtimeID: "hermes",
                transportID: "runs",
                sourceNamespace: "hermes.runs.v1"
            ))
            let turn = try repository.beginTurn(.init(roomID: room.id, runtimeBindingID: binding.id))
            let parent = try repository.upsertMessage(.init(
                roomID: room.id,
                turnID: turn.id,
                runtimeBindingID: binding.id,
                role: "user",
                contentText: "prompt"
            ), intent: .historicalReplay).message
            let alternateParent = try repository.upsertMessage(.init(
                roomID: room.id,
                turnID: turn.id,
                runtimeBindingID: binding.id,
                role: "user",
                contentText: "alternate"
            ), intent: .historicalReplay).message
            let messageID = UUID()
            let source = ConversationSourceIdentity(namespace: "hermes.live.v1", id: "session:live")
            let createdAt = Date(timeIntervalSince1970: 4_000)
            let sourceCreatedAt = Date(timeIntervalSince1970: 3_900)
            let pendingDraft = ConversationMessageDraft(
                id: messageID,
                roomID: room.id,
                turnID: turn.id,
                runtimeBindingID: binding.id,
                parentMessageID: parent.id,
                role: "assistant",
                contentText: "",
                status: .pending,
                source: source,
                sourceCreatedAt: sourceCreatedAt,
                metadata: ["phase": "pending"],
                createdAt: createdAt
            )
            let pending = try repository.upsertMessage(pendingDraft, intent: .liveContinuation).message

            var streamingDraft = pendingDraft
            streamingDraft.contentText = "partial"
            streamingDraft.status = .streaming
            streamingDraft.metadata = ["phase": "streaming"]
            let streaming = try repository.upsertMessage(streamingDraft, intent: .liveContinuation).message
            #expect(streaming.contentText == "partial")
            #expect(streaming.status == .streaming)

            var completeDraft = streamingDraft
            completeDraft.contentText = "final"
            completeDraft.status = .complete
            completeDraft.finishReason = .stop
            completeDraft.metadata = ["phase": "complete"]
            let complete = try repository.upsertMessage(completeDraft, intent: .liveContinuation).message
            #expect(complete.status == .complete)
            #expect(complete.finishReason == .stop)
            #expect(complete.id == pending.id)
            #expect(complete.sequence == pending.sequence)
            #expect(complete.createdAt == createdAt)
            #expect(complete.sourceCreatedAt == sourceCreatedAt)
            #expect(complete.parentMessageID == parent.id)

            let terminalReplay = try repository.upsertMessage(completeDraft, intent: .liveContinuation)
            #expect(terminalReplay.disposition == .unchangedReplay)
            let terminalRoomBefore = try #require(try repository.room(id: room.id))
            let terminalMessagesBefore = try repository.messages(roomID: room.id)
            var terminalRewrite = completeDraft
            terminalRewrite.contentText = "rewritten terminal"
            #expect(throws: ConversationRepositoryError.self) {
                try repository.upsertMessage(terminalRewrite, intent: .liveContinuation)
            }
            #expect(try repository.messages(roomID: room.id) == terminalMessagesBefore)
            #expect(try repository.room(id: room.id) == terminalRoomBefore)

            let incompleteFromPendingID = UUID()
            var incompleteFromPending = pendingDraft
            incompleteFromPending.id = incompleteFromPendingID
            incompleteFromPending.source = .init(namespace: "hermes.live.v1", id: "session:pending-incomplete")
            _ = try repository.upsertMessage(incompleteFromPending, intent: .liveContinuation)
            incompleteFromPending.contentText = "cancelled"
            incompleteFromPending.status = .incomplete
            incompleteFromPending.finishReason = .cancelled
            #expect(try repository.upsertMessage(incompleteFromPending, intent: .liveContinuation).message.status == .incomplete)

            let incompleteFromStreamingID = UUID()
            var incompleteFromStreaming = pendingDraft
            incompleteFromStreaming.id = incompleteFromStreamingID
            incompleteFromStreaming.source = .init(namespace: "hermes.live.v1", id: "session:streaming-incomplete")
            _ = try repository.upsertMessage(incompleteFromStreaming, intent: .liveContinuation)
            incompleteFromStreaming.contentText = "partial"
            incompleteFromStreaming.status = .streaming
            _ = try repository.upsertMessage(incompleteFromStreaming, intent: .liveContinuation)
            incompleteFromStreaming.status = .incomplete
            incompleteFromStreaming.finishReason = .error
            #expect(try repository.upsertMessage(incompleteFromStreaming, intent: .liveContinuation).message.status == .incomplete)

            let structuralID = UUID()
            var structuralDraft = pendingDraft
            structuralDraft.id = structuralID
            structuralDraft.source = .init(namespace: "hermes.live.v1", id: "session:structural")
            _ = try repository.upsertMessage(structuralDraft, intent: .liveContinuation)
            let structuralRoomBefore = try #require(try repository.room(id: room.id))
            let structuralMessagesBefore = try repository.messages(roomID: room.id)
            let structuralAncestryBefore = try repository.messages(roomID: room.id, throughHead: structuralID)

            @MainActor
            func expectStructuralRejection(_ conflicting: ConversationMessageDraft) throws {
                #expect(throws: ConversationRepositoryError.self) {
                    try repository.upsertMessage(conflicting, intent: .liveContinuation)
                }
                #expect(try repository.messages(roomID: room.id) == structuralMessagesBefore)
                #expect(try repository.messages(roomID: room.id, throughHead: structuralID) == structuralAncestryBefore)
                #expect(try repository.room(id: room.id) == structuralRoomBefore)
            }

            var conflict = structuralDraft
            conflict.role = "user"
            try expectStructuralRejection(conflict)
            conflict = structuralDraft
            conflict.parentMessageID = alternateParent.id
            try expectStructuralRejection(conflict)
            conflict = structuralDraft
            conflict.turnID = nil
            try expectStructuralRejection(conflict)
            conflict = structuralDraft
            conflict.runtimeBindingID = nil
            try expectStructuralRejection(conflict)
            conflict = structuralDraft
            conflict.createdAt = Date(timeIntervalSince1970: 4_001)
            try expectStructuralRejection(conflict)
            conflict = structuralDraft
            conflict.sourceCreatedAt = Date(timeIntervalSince1970: 3_901)
            try expectStructuralRejection(conflict)
            conflict = structuralDraft
            conflict.source = .init(namespace: "hermes.live.v1", id: "different")
            try expectStructuralRejection(conflict)
            conflict = structuralDraft
            conflict.id = UUID()
            try expectStructuralRejection(conflict)
        }
    }

    @Test("Message parents require an acyclic same-room ancestry")
    func parentIntegrity() throws {
        try withRepository { _, repository in
            let firstRoom = try repository.createRoom(roomDraft())
            let secondRoom = try repository.createRoom(roomDraft())
            let root = try repository.upsertMessage(.init(roomID: firstRoom.id, role: "user", contentText: "root"), intent: .historicalReplay).message
            let child = try repository.upsertMessage(.init(roomID: firstRoom.id, parentMessageID: root.id, role: "assistant", contentText: "child"), intent: .historicalReplay).message
            #expect(try repository.messages(roomID: firstRoom.id, throughHead: child.id).map(\.id) == [root.id, child.id])

            #expect(throws: ConversationRepositoryError.self) {
                try repository.upsertMessage(.init(roomID: firstRoom.id, parentMessageID: UUID(), role: "user", contentText: "missing"), intent: .historicalReplay)
            }
            #expect(throws: ConversationRepositoryError.self) {
                try repository.upsertMessage(.init(roomID: secondRoom.id, parentMessageID: root.id, role: "user", contentText: "cross-room"), intent: .historicalReplay)
            }
            #expect(throws: ConversationRepositoryError.self) {
                try repository.upsertMessage(.init(id: root.id, roomID: firstRoom.id, parentMessageID: root.id, role: "user", contentText: "self"), intent: .historicalReplay)
            }
            #expect(throws: ConversationRepositoryError.self) {
                try repository.upsertMessage(.init(id: root.id, roomID: firstRoom.id, parentMessageID: child.id, role: "user", contentText: "cycle"), intent: .historicalReplay)
            }
        }
    }

    @Test("Turn transitions persist terminal outcomes and partial content")
    func turnTransitionsAndPartialContent() throws {
        try withRepository { _, repository in
            let room = try repository.createRoom(roomDraft())
            let completed = try repository.beginTurn(.init(roomID: room.id))
            _ = try repository.transitionTurn(id: completed.id, to: .running, at: Date())
            let final = try repository.transitionTurn(id: completed.id, to: .completed, at: Date())
            #expect(final.status == .completed)
            #expect(throws: ConversationRepositoryError.self) {
                try repository.transitionTurn(id: completed.id, to: .running, at: Date())
            }

            let failed = try repository.beginTurn(.init(roomID: room.id))
            _ = try repository.transitionTurn(id: failed.id, to: .running, at: Date())
            let partial = try repository.upsertMessage(.init(
                roomID: room.id,
                turnID: failed.id,
                role: "assistant",
                contentText: "partial",
                status: .incomplete,
                finishReason: .error
            ), intent: .historicalReplay).message
            let failedFinal = try repository.transitionTurn(
                id: failed.id,
                to: .failed,
                error: .init(code: "transport", detail: "disconnected"),
                at: Date()
            )
            #expect(failedFinal.status == .failed)
            #expect(try repository.messages(roomID: room.id).contains { $0.id == partial.id && $0.contentText == "partial" })

            let partiallyCancelled = try repository.beginTurn(.init(roomID: room.id))
            _ = try repository.transitionTurn(id: partiallyCancelled.id, to: .running, at: Date())
            let cancelledPartial = try repository.upsertMessage(.init(
                roomID: room.id,
                turnID: partiallyCancelled.id,
                role: "assistant",
                contentText: "cancelled partial",
                status: .incomplete,
                finishReason: .cancelled
            ), intent: .historicalReplay).message
            _ = try repository.transitionTurn(id: partiallyCancelled.id, to: .cancelled, at: Date())
            #expect(try repository.messages(roomID: room.id).contains { $0.id == cancelledPartial.id && $0.contentText == "cancelled partial" })

            let cancelled = try repository.beginTurn(.init(roomID: room.id))
            let cancelledFinal = try repository.transitionTurn(id: cancelled.id, to: .cancelled, at: Date())
            #expect(cancelledFinal.status == .cancelled)
            #expect(try repository.messages(roomID: room.id).allSatisfy { $0.turnID != cancelled.id })
        }
    }

    @Test("Atomic snapshot failure rolls back the turn, messages, and sequences")
    func atomicSnapshotRollback() throws {
        try withRepository { _, repository in
            let room = try repository.createRoom(roomDraft())
            let turnID = UUID()
            #expect(throws: ConversationRepositoryError.self) {
                try repository.recordTurnSnapshot(
                    turn: .init(id: turnID, roomID: room.id),
                    messages: [
                        .init(roomID: room.id, turnID: turnID, role: "user", contentText: "valid"),
                        .init(roomID: room.id, turnID: turnID, parentMessageID: UUID(), role: "assistant", contentText: "invalid"),
                    ]
                )
            }

            #expect(try repository.turn(id: turnID) == nil)
            #expect(try repository.messages(roomID: room.id).isEmpty)
            let turn = try repository.beginTurn(.init(roomID: room.id))
            let message = try repository.upsertMessage(.init(roomID: room.id, turnID: turn.id, role: "user", contentText: "after"), intent: .historicalReplay).message
            #expect(turn.sequence == 1)
            #expect(message.sequence == 1)
        }
    }

    @Test("Atomic snapshot records one turn and its ordered messages")
    func atomicSnapshotSuccess() throws {
        try withRepository { _, repository in
            let room = try repository.createRoom(roomDraft())
            let turnID = UUID()
            let firstID = UUID()
            let snapshot = try repository.recordTurnSnapshot(
                turn: .init(id: turnID, roomID: room.id),
                messages: [
                    .init(id: firstID, roomID: room.id, turnID: turnID, role: "user", contentText: "question"),
                    .init(roomID: room.id, turnID: turnID, parentMessageID: firstID, role: "assistant", contentText: "answer"),
                ]
            )
            #expect(snapshot.turn.id == turnID)
            #expect(snapshot.messages.map(\.sequence) == [1, 2])
            #expect(try repository.messages(roomID: room.id, throughHead: snapshot.messages[1].id).map(\.contentText) == ["question", "answer"])
        }
    }
}
