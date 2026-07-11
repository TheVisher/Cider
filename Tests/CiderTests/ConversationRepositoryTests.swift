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

    @Test("Equal timestamps read in allocated message sequence order")
    func deterministicMessageOrdering() throws {
        try withRepository { _, repository in
            let room = try repository.createRoom(roomDraft())
            let timestamp = Date(timeIntervalSince1970: 1_000)
            let first = try repository.upsertMessage(.init(roomID: room.id, role: "user", contentText: "first", createdAt: timestamp))
            let second = try repository.upsertMessage(.init(roomID: room.id, role: "assistant", contentText: "second", createdAt: timestamp))

            #expect(first.message.sequence == 1)
            #expect(second.message.sequence == 2)
            #expect(try repository.messages(roomID: room.id).map(\.contentText) == ["first", "second"])
        }
    }

    @Test("Source replay is idempotent and does not consume a sequence")
    func sourceReplayDoesNotConsumeSequence() throws {
        try withRepository { _, repository in
            let room = try repository.createRoom(roomDraft())
            let source = ConversationSourceIdentity(namespace: "hermes.export.v1", id: "session:message")
            let draft = ConversationMessageDraft(roomID: room.id, role: "user", contentText: "hello", source: source)

            let inserted = try repository.upsertMessage(draft)
            let replayed = try repository.upsertMessage(draft)
            let local = try repository.upsertMessage(.init(roomID: room.id, role: "assistant", contentText: "next"))

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
            ))
            _ = try repository.upsertMessage(.init(
                roomID: secondRoom.id,
                role: "user",
                contentText: "Codex",
                source: .init(namespace: "codex.rollout.v1", id: sharedID)
            ))

            #expect(throws: ConversationRepositoryError.self) {
                try repository.upsertMessage(.init(
                    roomID: secondRoom.id,
                    role: "user",
                    contentText: "conflict",
                    source: .init(namespace: "hermes.export.v1", id: sharedID)
                ))
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

    @Test("Message parents require an acyclic same-room ancestry")
    func parentIntegrity() throws {
        try withRepository { _, repository in
            let firstRoom = try repository.createRoom(roomDraft())
            let secondRoom = try repository.createRoom(roomDraft())
            let root = try repository.upsertMessage(.init(roomID: firstRoom.id, role: "user", contentText: "root")).message
            let child = try repository.upsertMessage(.init(roomID: firstRoom.id, parentMessageID: root.id, role: "assistant", contentText: "child")).message
            #expect(try repository.messages(roomID: firstRoom.id, throughHead: child.id).map(\.id) == [root.id, child.id])

            #expect(throws: ConversationRepositoryError.self) {
                try repository.upsertMessage(.init(roomID: firstRoom.id, parentMessageID: UUID(), role: "user", contentText: "missing"))
            }
            #expect(throws: ConversationRepositoryError.self) {
                try repository.upsertMessage(.init(roomID: secondRoom.id, parentMessageID: root.id, role: "user", contentText: "cross-room"))
            }
            #expect(throws: ConversationRepositoryError.self) {
                try repository.upsertMessage(.init(id: root.id, roomID: firstRoom.id, parentMessageID: root.id, role: "user", contentText: "self"))
            }
            #expect(throws: ConversationRepositoryError.self) {
                try repository.upsertMessage(.init(id: root.id, roomID: firstRoom.id, parentMessageID: child.id, role: "user", contentText: "cycle"))
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
            )).message
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
            )).message
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
            let message = try repository.upsertMessage(.init(roomID: room.id, turnID: turn.id, role: "user", contentText: "after")).message
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
