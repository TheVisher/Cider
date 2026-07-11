import CryptoKit
import Foundation
import Testing
@testable import Cider

@Suite("Conversation Shadow Writer Tests")
@MainActor
struct ConversationShadowWriterTests {
    private enum ForcedFailure: Error { case checkpoint }

    @Test("Coordinator owns one generation and orders registry, JSONL, reservation, then SQLite")
    func coordinatedOrdering() throws {
        var events: [String] = []
        var registryPersistence = CiderAgentChatRegistry.Persistence.live()
        let registryWrite = registryPersistence.writeAtomically
        registryPersistence.writeAtomically = { data, url in
            events.append("registry")
            try registryWrite(data, url)
        }
        var conversationPersistence = AIConversationStorage.Persistence.live()
        let conversationWrite = conversationPersistence.writeAtomically
        conversationPersistence.writeAtomically = { data, url in
            events.append("jsonl")
            try conversationWrite(data, url)
        }
        let fixture = try Fixture(registryPersistence: registryPersistence, conversationPersistence: conversationPersistence)
        defer { fixture.remove() }
        var primaryTree: Fixture.LegacyTreeSnapshot?
        let writer = ConversationShadowWriter(database: fixture.database, repository: fixture.repository) { checkpoint in
            if checkpoint == .room {
                #expect(fixture.healthStore.snapshot().unresolved.first?.status == .reserved)
                primaryTree = try fixture.legacyTree()
                events.append("sqlite")
            }
        }
        let result = fixture.coordinator(writer: writer).save(
            record: fixture.record,
            title: fixture.record.title,
            messages: fixture.messages,
            model: "hermes",
            hermesState: fixture.hermesState
        )

        #expect(events == ["registry", "jsonl", "sqlite"])
        #expect(result.registryReceipt?.generation == result.generation)
        #expect(result.primaryReceipt.generation == result.generation)
        #expect(result.registryReceipt?.snapshot.generation == result.generation)
        #expect(result.primaryReceipt.snapshot?.generation == result.generation)
        #expect(result.primaryReceipt.isCommitted)
        #expect(result.invokedShadowWriter)
        #expect(result.shadowStatus == .synchronized)
        #expect(try fixture.legacyTree() == primaryTree)
    }

    @Test("Both split-success primary outcomes skip shadow writes")
    func splitSuccessSkipsShadow() throws {
        do {
            var conversationPersistence = AIConversationStorage.Persistence.live()
            conversationPersistence.writeAtomically = { _, _ in throw ForcedFailure.checkpoint }
            let fixture = try Fixture(conversationPersistence: conversationPersistence)
            defer { fixture.remove() }
            var sqliteCalled = false
            let writer = ConversationShadowWriter(database: fixture.database, repository: fixture.repository) { _ in sqliteCalled = true }
            let result = fixture.coordinator(writer: writer).save(
                record: fixture.record,
                title: fixture.record.title,
                messages: fixture.messages,
                model: "hermes",
                hermesState: fixture.hermesState
            )
            #expect(result.registryReceipt != nil)
            #expect(!result.primaryReceipt.isCommitted)
            #expect(!result.invokedShadowWriter)
            #expect(!sqliteCalled)
            #expect(try fixture.coreSnapshot().isEmpty)
        }
        do {
            var registryPersistence = CiderAgentChatRegistry.Persistence.live()
            registryPersistence.writeAtomically = { _, _ in throw ForcedFailure.checkpoint }
            let fixture = try Fixture(registryPersistence: registryPersistence)
            defer { fixture.remove() }
            var sqliteCalled = false
            let writer = ConversationShadowWriter(database: fixture.database, repository: fixture.repository) { _ in sqliteCalled = true }
            let result = fixture.coordinator(writer: writer).save(
                record: fixture.record,
                title: fixture.record.title,
                messages: fixture.messages,
                model: "hermes",
                hermesState: fixture.hermesState
            )
            #expect(result.registryReceipt == nil)
            #expect(result.registryFailureDetail != nil)
            #expect(result.primaryReceipt.isCommitted)
            #expect(!result.invokedShadowWriter)
            #expect(!sqliteCalled)
            #expect(try fixture.coreSnapshot().isEmpty)
        }
    }

    @Test("Reservation failure prevents every SQLite operation")
    func reservationFailurePreventsWrite() throws {
        let fixture = try Fixture(healthPersistence: .init(
            writeAtomically: { _, _ in throw ForcedFailure.checkpoint },
            read: { try Data(contentsOf: $0) }
        ))
        defer { fixture.remove() }
        var sqliteCalled = false
        let writer = ConversationShadowWriter(database: fixture.database, repository: fixture.repository) { _ in sqliteCalled = true }
        let result = fixture.coordinator(writer: writer).save(
            record: fixture.record,
            title: fixture.record.title,
            messages: fixture.messages,
            model: "hermes",
            hermesState: fixture.hermesState
        )

        #expect(result.primaryReceipt.isCommitted)
        #expect(!result.invokedShadowWriter)
        #expect(result.shadowCode == .gateBlocked)
        #expect(!sqliteCalled)
        #expect(try fixture.coreSnapshot().isEmpty)
    }

    @Test("A throw after every table family and parity rolls back all rows, counters, and timestamps", arguments: [
        ConversationShadowWriterCheckpoint.room,
        .bindings,
        .turns,
        .messages,
        .parity,
    ])
    func rollbackAtEveryCheckpoint(checkpoint: ConversationShadowWriterCheckpoint) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let payload = try fixture.payload()
        let before = try fixture.coreSnapshot()
        let writer = ConversationShadowWriter(database: fixture.database, repository: fixture.repository) {
            if $0 == checkpoint { throw ForcedFailure.checkpoint }
        }

        #expect(throws: ForcedFailure.self) { try writer.write(payload) }
        #expect(try fixture.coreSnapshot() == before)
    }

    @Test("Exact retry is idempotent without sequence or timestamp consumption")
    func exactRetryIsIdempotent() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let payload = try fixture.payload()
        let writer = ConversationShadowWriter(database: fixture.database, repository: fixture.repository)

        try writer.write(payload)
        let first = try fixture.coreSnapshot()
        try writer.write(payload)
        let second = try fixture.coreSnapshot()

        #expect(first == second)
        #expect(first.room?.nextTurnSequence == 2)
        #expect(first.room?.nextMessageSequence == Int64(fixture.messages.count + 1))
        #expect(first.room?.createdAt == fixture.record.createdAt)
        #expect(first.room?.updatedAt == fixture.record.updatedAt)
        #expect(first.bindings.allSatisfy { $0.createdAt == fixture.record.createdAt })
        #expect(first.bindings.allSatisfy { $0.updatedAt == fixture.record.updatedAt })
        #expect(try writer.hasExactParity(payload))
    }

    @Test("Room and binding timestamps exactly match the mapper plan when created and updated differ")
    func exactMapperTimestamps() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let payload = try fixture.payload()
        let plan = LegacyConversationSnapshotMapper().map(
            record: payload.registry.record,
            metadata: payload.conversation.metadata,
            messages: payload.conversation.messages.enumerated().map {
                .init(physicalLine: $0.offset + 2, message: $0.element)
            }
        )
        let writer = ConversationShadowWriter(database: fixture.database, repository: fixture.repository)

        try writer.write(payload)

        let room = try #require(try fixture.repository.room(id: fixture.record.conversationID))
        let plannedRoom = try #require(plan.rooms.first)
        let bindings = try fixture.repository.bindings(roomID: fixture.record.conversationID)
        #expect(plannedRoom.createdAt != plannedRoom.updatedAt)
        #expect(room.createdAt == plannedRoom.createdAt)
        #expect(room.updatedAt == plannedRoom.updatedAt)
        let bindingsByID = Dictionary(uniqueKeysWithValues: bindings.map { ($0.id, $0) })
        for plannedBinding in plan.bindings {
            #expect(bindingsByID[plannedBinding.id]?.createdAt == plannedBinding.createdAt)
            #expect(bindingsByID[plannedBinding.id]?.updatedAt == plannedBinding.updatedAt)
        }
    }

    @Test("Conflicting room updated timestamp fails closed without changing repository state")
    func conflictingRoomUpdatedAtRollsBack() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let payload = try fixture.payload()
        let plan = fixture.map(payload)
        let plannedRoom = try #require(plan.rooms.first)
        _ = try fixture.repository.createRoom(.init(
            id: plannedRoom.id,
            stableKey: plannedRoom.stableKey,
            title: plannedRoom.title,
            kind: plannedRoom.kind,
            metadata: plannedRoom.metadata,
            createdAt: plannedRoom.createdAt,
            updatedAt: plannedRoom.updatedAt.addingTimeInterval(-1)
        ))
        let before = try fixture.coreSnapshot()
        let writer = ConversationShadowWriter(database: fixture.database, repository: fixture.repository)

        #expect(throws: ConversationShadowWriterError.conflict("Existing room conflicts with the mapped legacy snapshot.")) {
            try writer.write(payload)
        }
        #expect(try fixture.coreSnapshot() == before)
        #expect(try !writer.hasExactParity(payload))
    }

    @Test("Conflicting binding updated timestamp fails closed without changing repository state")
    func conflictingBindingUpdatedAtRollsBack() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let payload = try fixture.payload()
        let plan = fixture.map(payload)
        let plannedRoom = try #require(plan.rooms.first)
        let plannedBinding = try #require(plan.bindings.first)
        _ = try fixture.repository.createRoom(.init(
            id: plannedRoom.id,
            stableKey: plannedRoom.stableKey,
            title: plannedRoom.title,
            kind: plannedRoom.kind,
            metadata: plannedRoom.metadata,
            createdAt: plannedRoom.createdAt,
            updatedAt: plannedRoom.updatedAt
        ))
        _ = try fixture.repository.upsertRuntimeBinding(.init(
            id: plannedBinding.id,
            roomID: plannedBinding.roomID,
            parentBindingID: plannedBinding.parentBindingID,
            runtimeID: plannedBinding.runtimeID,
            transportID: plannedBinding.transportID,
            sourceNamespace: plannedBinding.sourceNamespace,
            externalSessionID: plannedBinding.externalSessionID,
            state: plannedBinding.state,
            cursorMessageID: plannedBinding.cursorMessageID,
            cursorTimestamp: plannedBinding.cursorTimestamp,
            metadata: plannedBinding.metadata,
            createdAt: plannedBinding.createdAt,
            updatedAt: plannedBinding.updatedAt.addingTimeInterval(-1)
        ))
        let before = try fixture.coreSnapshot()
        let writer = ConversationShadowWriter(database: fixture.database, repository: fixture.repository)

        #expect(throws: ConversationShadowWriterError.conflict("Existing runtime binding conflicts with the mapped legacy snapshot.")) {
            try writer.write(payload)
        }
        #expect(try fixture.coreSnapshot() == before)
        #expect(try !writer.hasExactParity(payload))
    }

    @Test("Archived room preserves exact mapped updated and archived timestamps")
    func archivedRoomTimestamps() throws {
        let fixture = try Fixture(archived: true)
        defer { fixture.remove() }
        let payload = try fixture.payload()
        let plannedRoom = try #require(fixture.map(payload).rooms.first)
        let writer = ConversationShadowWriter(database: fixture.database, repository: fixture.repository)

        try writer.write(payload)

        let room = try #require(try fixture.repository.room(id: fixture.record.conversationID))
        #expect(room.lifecycleState == .archived)
        #expect(room.createdAt == plannedRoom.createdAt)
        #expect(room.updatedAt == plannedRoom.updatedAt)
        #expect(room.archivedAt == plannedRoom.archivedAt)
        #expect(try writer.hasExactParity(payload))
    }

    @Test("Mapper and writer preserve physical order, namespaces, lineage, proven turns, and parents")
    func exactIdentityMapping() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let payload = try fixture.payload()
        let mapper = LegacyConversationSnapshotMapper()
        let plan = mapper.map(
            record: payload.registry.record,
            metadata: payload.conversation.metadata,
            messages: payload.conversation.messages.enumerated().map {
                .init(physicalLine: $0.offset + 2, message: $0.element)
            }
        )
        let writer = ConversationShadowWriter(database: fixture.database, repository: fixture.repository)
        try writer.write(payload)
        let persisted = try fixture.repository.messages(roomID: fixture.record.conversationID)

        #expect(persisted.map(\.id) == fixture.messages.map(\.id))
        #expect(persisted.map(\.contentText) == fixture.messages.map(\.content))
        #expect(persisted.map(\.sourceCreatedAt) == fixture.messages.map(\.timestamp))
        #expect(persisted.map(\.source?.namespace) == [nil, "legacy.message-source.v1", "hermes.runs.v1", "hermes.runs.v1", "hermes.live.v1"])
        #expect(persisted.map(\.parentMessageID) == [nil] + Array(fixture.messages.dropLast().map(\.id)))
        #expect(persisted.dropFirst().allSatisfy { $0.metadata["parentProvenance"] == "legacy-linear" })
        #expect(plan.bindings.count == 2)
        #expect(plan.bindings[1].parentBindingID == plan.bindings[0].id)
        #expect(plan.bindings.map(\.sourceNamespace) == ["legacy.runtime-binding.v1.hermes", "legacy.runtime-binding.v1.hermes"])
        #expect(plan.turns.count == 1)
        #expect(plan.turns[0].status == .unknown)
        #expect(plan.turns[0].source == .init(namespace: "hermes.runs.v1", id: "run-7"))
        #expect(plan.messages[0].turnID == nil)
        #expect(plan.messages[1].turnID == nil)
        #expect(plan.messages[2].turnID == plan.turns[0].id)
        #expect(plan.messages[3].turnID == plan.turns[0].id)
        #expect(plan.messages[4].turnID == nil)
        #expect(try writer.hasExactParity(payload))
    }

    @Test("Repository failure is durable repair-needed and leaves legacy bytes authoritative")
    func repositoryFailureIsDurable() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var primaryTree: Fixture.LegacyTreeSnapshot?
        let writer = ConversationShadowWriter(database: fixture.database, repository: fixture.repository) { checkpoint in
            if checkpoint == .room { primaryTree = try fixture.legacyTree() }
            if checkpoint == .messages { throw ForcedFailure.checkpoint }
        }
        let result = fixture.coordinator(writer: writer).save(
            record: fixture.record,
            title: fixture.record.title,
            messages: fixture.messages,
            model: "hermes",
            hermesState: fixture.hermesState
        )

        #expect(result.primaryReceipt.isCommitted)
        #expect(result.shadowStatus == .repairNeeded)
        #expect(result.shadowCode == .shadowRepositoryFailed)
        #expect(try fixture.coreSnapshot().isEmpty)
        #expect(try fixture.legacyTree() == primaryTree)
        let restarted = try ConversationShadowHealthStore(diagnosticsDirectoryURL: fixture.diagnosticsDirectory)
        #expect(restarted.snapshot().unresolved.first?.status == .repairNeeded)
    }

    @Test("Mapper parity failure rolls back the entire transaction and records durable repair")
    func parityFailureRollsBackAndRepairs() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var primaryTree: Fixture.LegacyTreeSnapshot?
        let writer = ConversationShadowWriter(database: fixture.database, repository: fixture.repository) { checkpoint in
            guard checkpoint == .messages else {
                if checkpoint == .room { primaryTree = try fixture.legacyTree() }
                return
            }
            _ = try fixture.repository.upsertMessage(.init(
                roomID: fixture.record.conversationID,
                parentMessageID: fixture.messages.last?.id,
                role: "assistant",
                contentText: "not in legacy snapshot",
                createdAt: fixture.now
            ), intent: .historicalReplay)
        }
        let result = fixture.coordinator(writer: writer).save(
            record: fixture.record,
            title: fixture.record.title,
            messages: fixture.messages,
            model: "hermes",
            hermesState: fixture.hermesState
        )

        #expect(result.primaryReceipt.isCommitted)
        #expect(result.shadowStatus == .repairNeeded)
        #expect(result.shadowCode == .shadowParityFailed)
        #expect(try fixture.coreSnapshot().isEmpty)
        #expect(try fixture.legacyTree() == primaryTree)
        let restarted = try ConversationShadowHealthStore(diagnosticsDirectoryURL: fixture.diagnosticsDirectory)
        #expect(restarted.snapshot().unresolved.first?.code == .shadowParityFailed)
    }

    @Test("Finalization uncertainty survives restart")
    func outcomeUnknownSurvivesRestart() throws {
        var writes = 0
        let live = ConversationShadowHealthStore.Persistence.live()
        let persistence = ConversationShadowHealthStore.Persistence(
            writeAtomically: { data, url in
                writes += 1
                if writes == 2 { throw ForcedFailure.checkpoint }
                try live.writeAtomically(data, url)
            },
            read: live.read
        )
        let fixture = try Fixture(healthPersistence: persistence)
        defer { fixture.remove() }
        let writer = ConversationShadowWriter(database: fixture.database, repository: fixture.repository)
        let result = fixture.coordinator(writer: writer).save(
            record: fixture.record,
            title: fixture.record.title,
            messages: fixture.messages,
            model: "hermes",
            hermesState: fixture.hermesState
        )

        #expect(result.primaryReceipt.isCommitted)
        #expect(result.shadowStatus == .outcomeUnknown)
        let restarted = try ConversationShadowHealthStore(diagnosticsDirectoryURL: fixture.diagnosticsDirectory)
        #expect(restarted.snapshot().unresolved.first?.status == .outcomeUnknown)
        #expect(try fixture.repository.messages(roomID: fixture.record.conversationID).count == fixture.messages.count)
    }

    @Test("A later exact same-hash retry resolves older durable health only after parity")
    func sameHashRetryReconciles() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let failing = ConversationShadowWriter(database: fixture.database, repository: fixture.repository) {
            if $0 == .messages { throw ForcedFailure.checkpoint }
        }
        let first = fixture.coordinator(writer: failing).save(
            record: fixture.record,
            title: fixture.record.title,
            messages: fixture.messages,
            model: "hermes",
            hermesState: fixture.hermesState
        )
        #expect(first.shadowStatus == .repairNeeded)
        let oldCorrelation = try #require(first.shadowCorrelationID)
        let restartedHealth = try ConversationShadowHealthStore(diagnosticsDirectoryURL: fixture.diagnosticsDirectory)
        #expect(restartedHealth.snapshot().unresolved.map(\.correlationID).contains(oldCorrelation))

        let succeeding = ConversationShadowWriter(database: fixture.database, repository: fixture.repository)
        let reconciler = ConversationShadowReconciler(writer: succeeding, healthStore: restartedHealth, now: { fixture.now })
        let coordinator = LegacyConversationPrimarySaveCoordinator(
            registry: fixture.registry,
            conversationStorage: fixture.storage,
            healthStore: restartedHealth,
            shadowWriter: succeeding,
            reconciler: reconciler,
            now: { fixture.now }
        )
        let second = coordinator.save(
            record: fixture.record,
            title: fixture.record.title,
            messages: fixture.messages,
            model: "hermes",
            hermesState: fixture.hermesState
        )

        #expect(second.shadowStatus == .synchronized)
        #expect(first.primaryReceipt.sha256 == second.primaryReceipt.sha256)
        #expect(first.registryReceipt?.sha256 == second.registryReceipt?.sha256)
        #expect(restartedHealth.snapshot().unresolved.isEmpty)
        #expect(restartedHealth.snapshot().resolvedHistory.contains { $0.correlationID == oldCorrelation && $0.status == .resolved })
        #expect(try succeeding.hasExactParity(try fixture.payloadFrom(result: second)))
    }
}

@MainActor
private final class Fixture {
    struct LegacyTreeSnapshot: Equatable {
        let paths: [String]
        let bytes: [String: Data]
        let hashes: [String: String]
    }

    struct CoreSnapshot: Equatable {
        let room: ConversationRoom?
        let bindings: [ConversationRuntimeBinding]
        let turns: [ConversationTurn]
        let messages: [ConversationMessage]
        var isEmpty: Bool { room == nil && bindings.isEmpty && turns.isEmpty && messages.isEmpty }
    }

    let root: URL
    let registryDirectory: URL
    let conversationDirectory: URL
    let diagnosticsDirectory: URL
    let database: CiderDatabase
    let repository: ConversationRepository
    let registry: CiderAgentChatRegistry
    let storage: AIConversationStorage
    let healthStore: ConversationShadowHealthStore
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let record: CiderAgentChatRecord
    let hermesState: HermesConversationState
    let messages: [AIAssistantMessage]

    init(
        archived: Bool = false,
        registryPersistence: CiderAgentChatRegistry.Persistence = .live(),
        conversationPersistence: AIConversationStorage.Persistence? = nil,
        healthPersistence: ConversationShadowHealthStore.Persistence = .live()
    ) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("cider-shadow-writer-\(UUID().uuidString)", isDirectory: true)
        registryDirectory = root.appendingPathComponent("registry", isDirectory: true)
        conversationDirectory = root.appendingPathComponent("conversations", isDirectory: true)
        diagnosticsDirectory = root.appendingPathComponent("diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: registryDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: conversationDirectory, withIntermediateDirectories: true)
        database = CiderDatabase()
        try database.open(at: root.appendingPathComponent("temporary-v30.db"))
        repository = ConversationRepository(database: database)
        let roomID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        hermesState = HermesConversationState(
            conversationID: roomID,
            activeRuntimeSessionID: "session-active",
            runtimeSessionLineage: ["session-parent", "session-active"],
            title: "Cider",
            source: "legacy-jsonl",
            lastSyncedAt: now,
            lastSyncedMessageID: "cursor-message",
            lastSyncedTimestamp: now,
            lastImportedRuntimeSessionID: "session-parent"
        )
        record = CiderAgentChatRecord(
            stableID: "cider.main",
            title: "Cider",
            hermesTitle: "Cider Runtime",
            kind: "main-brain",
            conversationID: roomID,
            runtimeID: "hermes",
            activeRuntimeSessionID: "session-active",
            runtimeSessionLineage: ["session-parent", "session-active"],
            lastSyncedMessageID: "cursor-message",
            lastSyncedTimestamp: now,
            lastImportedRuntimeSessionID: "session-parent",
            scope: "main",
            archived: archived,
            createdAt: now.addingTimeInterval(-100),
            updatedAt: now,
            defaultInCider: true
        )
        let timestamp = now.addingTimeInterval(-50)
        messages = [
            .init(id: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!, role: .user, content: "repeat", timestamp: timestamp),
            .init(id: UUID(uuidString: "20000000-0000-4000-8000-000000000002")!, role: .assistant, content: "repeat", timestamp: timestamp, sourceID: "future-source:opaque", sourceSessionID: "session-active", sourceName: "Hermes"),
            .init(id: UUID(uuidString: "20000000-0000-4000-8000-000000000003")!, role: .user, content: "repeat", timestamp: timestamp, sourceID: "hermes-run:run-7:user", sourceSessionID: "session-parent", sourceName: "Hermes"),
            .init(id: UUID(uuidString: "20000000-0000-4000-8000-000000000004")!, role: .assistant, content: "repeat", timestamp: timestamp, sourceID: "hermes-run:run-7:assistant", sourceSessionID: "session-active", sourceName: "Hermes"),
            .init(id: UUID(uuidString: "20000000-0000-4000-8000-000000000005")!, role: .assistant, content: "repeat", timestamp: timestamp, sourceID: "hermes-live:session-active:five", sourceSessionID: "session-active", sourceName: "Hermes"),
        ]
        let persistedNow = Date(timeIntervalSince1970: 1_800_000_000)
        registry = CiderAgentChatRegistry(storageDirectoryURL: registryDirectory, persistence: registryPersistence, now: { persistedNow })
        storage = AIConversationStorage(
            conversationsDirectoryURL: conversationDirectory,
            persistence: conversationPersistence ?? Self.deterministicConversationPersistence(),
            now: { persistedNow }
        )
        healthStore = try ConversationShadowHealthStore(diagnosticsDirectoryURL: diagnosticsDirectory, persistence: healthPersistence)
    }

    func remove() {
        database.close()
        try? FileManager.default.removeItem(at: root)
    }

    func coordinator(writer: ConversationShadowWriter) -> LegacyConversationPrimarySaveCoordinator {
        let reconciler = ConversationShadowReconciler(writer: writer, healthStore: healthStore, now: { self.now })
        return LegacyConversationPrimarySaveCoordinator(
            registry: registry,
            conversationStorage: storage,
            healthStore: healthStore,
            shadowWriter: writer,
            reconciler: reconciler,
            now: { self.now }
        )
    }

    func payload() throws -> ConversationShadowPayload {
        let generation = LegacyConversationWriteGeneration()
        let registryReceipt = try registry.updateChat(record, generation: generation)
        let conversationReceipt = storage.save(
            id: record.conversationID,
            title: record.title,
            messages: messages,
            model: "hermes",
            hermesState: hermesState,
            generation: generation
        )
        return ConversationShadowPayload(
            generation: generation,
            registry: registryReceipt.snapshot,
            conversation: try #require(conversationReceipt.snapshot)
        )
    }

    func payloadFrom(result: LegacyConversationCoordinatedSaveResult) throws -> ConversationShadowPayload {
        ConversationShadowPayload(
            generation: result.generation,
            registry: try #require(result.registryReceipt?.snapshot),
            conversation: try #require(result.primaryReceipt.snapshot)
        )
    }

    func map(_ payload: ConversationShadowPayload) -> LegacyConversationImportPlan {
        LegacyConversationSnapshotMapper().map(
            record: payload.registry.record,
            metadata: payload.conversation.metadata,
            messages: payload.conversation.messages.enumerated().map {
                .init(physicalLine: $0.offset + 2, message: $0.element)
            }
        )
    }

    func coreSnapshot() throws -> CoreSnapshot {
        CoreSnapshot(
            room: try repository.room(id: record.conversationID),
            bindings: try repository.bindings(roomID: record.conversationID),
            turns: try repository.turns(roomID: record.conversationID),
            messages: try repository.messages(roomID: record.conversationID)
        )
    }

    func legacyTree() throws -> LegacyTreeSnapshot {
        var bytes: [String: Data] = [:]
        var hashes: [String: String] = [:]
        for (prefix, directory) in [("registry", registryDirectory), ("conversation", conversationDirectory)] {
            for name in try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() {
                let data = try Data(contentsOf: directory.appendingPathComponent(name))
                let path = "\(prefix)/\(name)"
                bytes[path] = data
                hashes[path] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            }
        }
        return .init(paths: bytes.keys.sorted(), bytes: bytes, hashes: hashes)
    }

    private static func deterministicConversationPersistence() -> AIConversationStorage.Persistence {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return .init(
            encodeMetadata: { try encoder.encode($0) },
            encodeMessage: { try encoder.encode($0) },
            writeAtomically: { try $0.write(to: $1, options: .atomic) },
            read: { try Data(contentsOf: $0) }
        )
    }
}
