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

    @Test("Verified sequential snapshots append terminal rows and exact retry consumes nothing")
    func verifiedSequentialProgression() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let writer = ConversationShadowWriter(database: fixture.database, repository: fixture.repository)
        let firstPayload = try fixture.payload()

        try writer.writeVerifiedSequentialCompletedSnapshot(firstPayload)
        let first = try fixture.coreSnapshot()
        let safety = DatabaseSafetyService()
        let preRunBackup = try safety.createRollingBackup(
            reason: "cid776-pre-run",
            database: fixture.database
        )
        let backupDatabase = CiderDatabase()
        try backupDatabase.open(at: preRunBackup)
        #expect(try backupDatabase.integrityCheck().isHealthy)
        backupDatabase.close()
        let isolatedRestoreURL = fixture.root.appendingPathComponent("isolated-restore.db")
        try FileManager.default.copyItem(at: preRunBackup, to: isolatedRestoreURL)
        let isolatedRestore = CiderDatabase()
        try isolatedRestore.open(at: isolatedRestoreURL)
        let restoredRepository = ConversationRepository(database: isolatedRestore)
        let restored = Fixture.CoreSnapshot(
            room: try restoredRepository.room(id: fixture.record.conversationID),
            bindings: try restoredRepository.bindings(roomID: fixture.record.conversationID),
            turns: try restoredRepository.turns(roomID: fixture.record.conversationID),
            messages: try restoredRepository.messages(roomID: fixture.record.conversationID)
        )
        #expect(restored == first)
        isolatedRestore.close()
        let advanced = advancedSnapshot(fixture, appendLineage: true)
        let secondPayload = try fixture.payload(
            record: advanced.record,
            messages: advanced.messages,
            hermesState: advanced.state
        )
        try writer.writeVerifiedSequentialCompletedSnapshot(secondPayload)
        let second = try fixture.coreSnapshot()

        #expect(second.messages.count == first.messages.count + 2)
        #expect(second.turns.count == first.turns.count + 1)
        #expect(second.messages.map(\.sequence) == Array(1...Int64(second.messages.count)))
        #expect(second.messages.suffix(2).map(\.role) == ["user", "assistant"])
        #expect(second.messages.suffix(2).map(\.contentText) == ["repeat", "repeat"])
        #expect(second.messages.suffix(2).map(\.createdAt).allSatisfy { $0 == advanced.appendedAt })
        #expect(second.room?.updatedAt == advanced.record.updatedAt)
        #expect(second.room?.nextMessageSequence == Int64(second.messages.count + 1))
        #expect(second.room?.nextTurnSequence == Int64(second.turns.count + 1))
        #expect(second.bindings.count == first.bindings.count + 1)
        let activeBinding = second.bindings.first { $0.externalSessionID == advanced.record.activeRuntimeSessionID }
        #expect(activeBinding?.cursorMessageID == advanced.record.lastSyncedMessageID)
        #expect(activeBinding?.cursorTimestamp == advanced.record.lastSyncedTimestamp)
        #expect(try writer.hasVerifiedSequentialCompletedSnapshotParity(secondPayload))

        let beforeRetry = second
        let retryPayload = try fixture.payload(
            record: advanced.record,
            messages: advanced.messages,
            hermesState: advanced.state
        )
        try writer.writeVerifiedSequentialCompletedSnapshot(retryPayload)
        #expect(try fixture.coreSnapshot() == beforeRetry)
    }

    @Test("Sequential mode rejects stale and divergent snapshots without mutation")
    func sequentialStaleAndDivergentFailClosed() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let writer = ConversationShadowWriter(database: fixture.database, repository: fixture.repository)
        try writer.writeVerifiedSequentialCompletedSnapshot(try fixture.payload())
        let before = try fixture.coreSnapshot()

        var staleRecord = fixture.record
        staleRecord.updatedAt = fixture.record.updatedAt.addingTimeInterval(-1)
        let staleState = state(for: staleRecord, source: fixture.hermesState.source)
        let stale = try fixture.payload(record: staleRecord, messages: fixture.messages, hermesState: staleState)
        #expect(throws: ConversationShadowWriterError.self) {
            try writer.writeVerifiedSequentialCompletedSnapshot(stale)
        }
        #expect(try fixture.coreSnapshot() == before)

        var cursorRegressionRecord = fixture.record
        cursorRegressionRecord.updatedAt = fixture.record.updatedAt.addingTimeInterval(1)
        cursorRegressionRecord.lastSyncedTimestamp = fixture.now.addingTimeInterval(-1)
        let cursorRegression = try fixture.payload(
            record: cursorRegressionRecord,
            messages: fixture.messages,
            hermesState: state(for: cursorRegressionRecord, source: fixture.hermesState.source)
        )
        #expect(throws: ConversationShadowWriterError.self) {
            try writer.writeVerifiedSequentialCompletedSnapshot(cursorRegression)
        }
        #expect(try fixture.coreSnapshot() == before)

        let truncated = try fixture.payload(
            record: fixture.record,
            messages: Array(fixture.messages.prefix(2)),
            hermesState: fixture.hermesState
        )
        #expect(throws: ConversationShadowWriterError.self) {
            try writer.writeVerifiedSequentialCompletedSnapshot(truncated)
        }
        #expect(try fixture.coreSnapshot() == before)

        var replacement = fixture.messages
        replacement[0].content = "replacement"
        let divergent = try fixture.payload(
            record: fixture.record,
            messages: replacement,
            hermesState: fixture.hermesState
        )
        #expect(throws: ConversationShadowWriterError.self) {
            try writer.writeVerifiedSequentialCompletedSnapshot(divergent)
        }
        #expect(try fixture.coreSnapshot() == before)
    }

    @Test("Historical content parent source role and created timestamp are immutable")
    func sequentialHistoricalFieldsAreImmutable() throws {
        enum Mutation: CaseIterable { case content, parent, source, role, createdAt }
        for mutation in Mutation.allCases {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let writer = ConversationShadowWriter(database: fixture.database, repository: fixture.repository)
            try writer.writeVerifiedSequentialCompletedSnapshot(try fixture.payload())
            let before = try fixture.coreSnapshot()
            var changed = fixture.messages
            switch mutation {
            case .content:
                changed[1].content = "changed"
            case .parent:
                changed.swapAt(0, 1)
            case .source:
                changed[1].sourceID = "future-source:different"
            case .role:
                changed[1] = replacing(changed[1], role: .user)
            case .createdAt:
                changed[1] = replacing(
                    changed[1],
                    timestamp: changed[1].timestamp.addingTimeInterval(1)
                )
            }
            let payload = try fixture.payload(
                record: fixture.record,
                messages: changed,
                hermesState: fixture.hermesState
            )
            #expect(throws: ConversationShadowWriterError.self) {
                try writer.writeVerifiedSequentialCompletedSnapshot(payload)
            }
            #expect(try fixture.coreSnapshot() == before)
        }
    }

    @Test("Sequential transaction rolls back after every mutation and parity phase", arguments: [
        ConversationShadowWriterCheckpoint.room,
        .roomUpdate,
        .bindings,
        .bindingUpdates,
        .turns,
        .messages,
        .counterFinalization,
        .parity,
    ])
    func sequentialRollbackAtEveryPhase(checkpoint: ConversationShadowWriterCheckpoint) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let seed = ConversationShadowWriter(database: fixture.database, repository: fixture.repository)
        try seed.writeVerifiedSequentialCompletedSnapshot(try fixture.payload())
        let before = try fixture.coreSnapshot()
        let advanced = advancedSnapshot(fixture, appendLineage: true)
        let payload = try fixture.payload(
            record: advanced.record,
            messages: advanced.messages,
            hermesState: advanced.state
        )
        let failing = ConversationShadowWriter(database: fixture.database, repository: fixture.repository) {
            if $0 == checkpoint { throw ForcedFailure.checkpoint }
        }

        #expect(throws: ForcedFailure.self) {
            try failing.writeVerifiedSequentialCompletedSnapshot(payload)
        }
        #expect(try fixture.coreSnapshot() == before)
    }

    @Test("Later exact-prefix parity reconciles older semantic evidence after restart")
    func laterPrefixReconcilesOlderEvidence() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let firstPayload = try fixture.payload()
        let record = try fixture.healthStore.reserve(payload: firstPayload, at: fixture.now)
        try fixture.healthStore.markRepairNeeded(
            correlationID: record.correlationID,
            code: .shadowRepositoryFailed,
            detail: "fixture failure",
            at: fixture.now
        )
        let restarted = try ConversationShadowHealthStore(
            diagnosticsDirectoryURL: fixture.diagnosticsDirectory
        )
        let advanced = advancedSnapshot(fixture, appendLineage: true)
        let newerPayload = try fixture.payload(
            record: advanced.record,
            messages: advanced.messages,
            hermesState: advanced.state
        )
        let writer = ConversationShadowWriter(database: fixture.database, repository: fixture.repository)
        try writer.writeVerifiedSequentialCompletedSnapshot(newerPayload)
        let reconciler = ConversationShadowReconciler(
            writer: writer,
            healthStore: restarted,
            now: { fixture.now.addingTimeInterval(20) }
        )

        #expect(try reconciler.reconcileAfterExactRetry(newerPayload) == 1)
        #expect(restarted.snapshot().unresolved.isEmpty)
        #expect(restarted.snapshot().resolvedHistory.first?.correlationID == record.correlationID)
    }

    @Test("Health v1 remains decodable and uses exact-hash fallback")
    func healthV1BackwardDecode() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let payload = try fixture.payload()
        _ = try fixture.healthStore.reserve(payload: payload, at: fixture.now)
        var json = try String(contentsOf: fixture.healthStore.fileURL, encoding: .utf8)
        json = json.replacingOccurrences(
            of: "\"formatVersion\" : \"cider.conversation-shadow-health.v2\"",
            with: "\"formatVersion\" : \"cider.conversation-shadow-health.v1\""
        )
        json = json.replacingOccurrences(
            of: #",\n      "semanticFingerprint" : \{[\s\S]*?\n      \}"#,
            with: "",
            options: .regularExpression
        )
        try Data(json.utf8).write(to: fixture.healthStore.fileURL, options: .atomic)

        let restarted = try ConversationShadowHealthStore(
            diagnosticsDirectoryURL: fixture.diagnosticsDirectory
        )
        #expect(restarted.snapshot().unresolved.count == 1)
        #expect(restarted.snapshot().unresolved.first?.semanticFingerprint == nil)
    }

    @Test("Activation receipts are content-free and bounded for success closed DB and saturation")
    func boundedActivationReceipts() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let reporter = ConversationShadowActivationReceiptReporter(maximumRecords: 2)
        let writer = ConversationShadowWriter(database: fixture.database, repository: fixture.repository)
        let success = fixture.coordinator(
            writer: writer,
            healthStore: fixture.healthStore,
            reporter: reporter
        ).save(
            record: fixture.record,
            title: fixture.record.title,
            messages: fixture.messages,
            model: "hermes",
            hermesState: fixture.hermesState
        )
        #expect(success.primaryReceipt.isCommitted)
        #expect(reporter.receipts.last?.planFingerprint != nil)
        #expect(reporter.receipts.last?.messageCount == fixture.messages.count)
        #expect(reporter.receipts.last?.terminalSourceNamespace == "hermes.live.v1")
        #expect(!String(
            data: try Data(contentsOf: fixture.healthStore.fileURL),
            encoding: .utf8
        )!.contains("repeat"))

        fixture.database.close()
        let closed = fixture.coordinator(
            writer: writer,
            healthStore: fixture.healthStore,
            reporter: reporter
        ).save(
            record: fixture.record,
            title: fixture.record.title,
            messages: fixture.messages,
            model: "hermes",
            hermesState: fixture.hermesState
        )
        #expect(closed.primaryReceipt.isCommitted)
        #expect(closed.shadowStatus == .repairNeeded)
        #expect(reporter.receipts.last?.shadowCode == .shadowRepositoryFailed)

        let zeroStore = try ConversationShadowHealthStore(
            diagnosticsDirectoryURL: fixture.root.appendingPathComponent("saturated"),
            maximumUnresolvedRecords: 0
        )
        let saturated = fixture.coordinator(
            writer: writer,
            healthStore: zeroStore,
            reporter: reporter
        ).save(
            record: fixture.record,
            title: fixture.record.title,
            messages: fixture.messages,
            model: "hermes",
            hermesState: fixture.hermesState
        )
        #expect(saturated.primaryReceipt.isCommitted)
        #expect(saturated.shadowCode == .diagnosticStoreSaturated)
        #expect(reporter.receipts.count == 2)
        #expect(reporter.droppedCount == 1)
        #expect(reporter.receipts.last?.shadowCode == .diagnosticStoreSaturated)
    }

    @Test("Gate-blocked attempts emit one bounded receipt without invoking SQLite")
    func gateBlockedReceipt() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let reporter = ConversationShadowActivationReceiptReporter(maximumRecords: 1)
        var sqliteCalled = false
        let writer = ConversationShadowWriter(database: fixture.database, repository: fixture.repository) {
            _ in sqliteCalled = true
        }
        let reconciler = ConversationShadowReconciler(
            writer: writer,
            healthStore: fixture.healthStore,
            now: { fixture.now.addingTimeInterval(600) }
        )
        let coordinator = LegacyConversationPrimarySaveCoordinator(
            registry: fixture.registry,
            conversationStorage: fixture.storage,
            healthStore: fixture.healthStore,
            shadowWriter: writer,
            reconciler: reconciler,
            receiptReporter: reporter,
            now: { fixture.now.addingTimeInterval(600) }
        )

        let result = coordinator.save(
            record: fixture.record,
            title: fixture.record.title,
            messages: fixture.messages,
            model: "hermes",
            hermesState: fixture.hermesState
        )

        #expect(result.primaryReceipt.isCommitted)
        #expect(result.shadowCode == .gateStale)
        #expect(!sqliteCalled)
        #expect(reporter.receipts.count == 1)
        #expect(reporter.receipts[0].generationID == result.generation.id)
        #expect(reporter.receipts[0].conversationID == fixture.record.conversationID)
        #expect(reporter.receipts[0].shadowCode == .gateStale)
        #expect(reporter.receipts[0].planFingerprint != nil)
    }

    @Test("Completed snapshot eligibility includes only explicit completed Hermes Runs")
    func completedSnapshotEligibility() {
        let eligible = ConversationCompletedSnapshotEligibility(
            provenance: .hermesRunsAPI,
            runState: .completed,
            containsTools: false,
            containsReasoning: false,
            containsApproval: false,
            sessionSyncComplete: true
        )
        #expect(eligible.isEligible)
        let excluded: [ConversationCompletedSnapshotEligibility] = [
            .init(provenance: .hermesStreamingOrDelta, runState: .completed, containsTools: false, containsReasoning: false, containsApproval: false, sessionSyncComplete: true),
            .init(provenance: .commandLineOrExportMerge, runState: .completed, containsTools: false, containsReasoning: false, containsApproval: false, sessionSyncComplete: true),
            .init(provenance: .other, runState: .completed, containsTools: false, containsReasoning: false, containsApproval: false, sessionSyncComplete: true),
            .init(provenance: .hermesRunsAPI, runState: .pending, containsTools: false, containsReasoning: false, containsApproval: false, sessionSyncComplete: true),
            .init(provenance: .hermesRunsAPI, runState: .failed, containsTools: false, containsReasoning: false, containsApproval: false, sessionSyncComplete: true),
            .init(provenance: .hermesRunsAPI, runState: .cancelled, containsTools: false, containsReasoning: false, containsApproval: false, sessionSyncComplete: true),
            .init(provenance: .hermesRunsAPI, runState: .completed, containsTools: true, containsReasoning: false, containsApproval: false, sessionSyncComplete: true),
            .init(provenance: .hermesRunsAPI, runState: .completed, containsTools: false, containsReasoning: true, containsApproval: false, sessionSyncComplete: true),
            .init(provenance: .hermesRunsAPI, runState: .completed, containsTools: false, containsReasoning: false, containsApproval: true, sessionSyncComplete: true),
            .init(provenance: .hermesRunsAPI, runState: .completed, containsTools: false, containsReasoning: false, containsApproval: false, sessionSyncComplete: false),
        ]
        #expect(excluded.allSatisfy { !$0.isEligible })
    }

    private func advancedSnapshot(
        _ fixture: Fixture,
        appendLineage: Bool
    ) -> (record: CiderAgentChatRecord, state: HermesConversationState, messages: [AIAssistantMessage], appendedAt: Date) {
        let appendedAt = fixture.now.addingTimeInterval(10)
        var record = fixture.record
        record.title = "Cider Sequential"
        record.updatedAt = appendedAt
        record.lastSyncedMessageID = "cursor-message-2"
        record.lastSyncedTimestamp = appendedAt
        if appendLineage {
            record.activeRuntimeSessionID = "session-next"
            record.runtimeSessionLineage.append("session-next")
        }
        var messages = fixture.messages
        messages.append(.init(
            id: UUID(uuidString: "20000000-0000-4000-8000-000000000006")!,
            role: .user,
            content: "repeat",
            timestamp: appendedAt,
            sourceID: "hermes-run:run-8:user",
            sourceSessionID: record.activeRuntimeSessionID,
            sourceName: "Hermes"
        ))
        messages.append(.init(
            id: UUID(uuidString: "20000000-0000-4000-8000-000000000007")!,
            role: .assistant,
            content: "repeat",
            timestamp: appendedAt,
            sourceID: "hermes-run:run-8:assistant",
            sourceSessionID: record.activeRuntimeSessionID,
            sourceName: "Hermes"
        ))
        return (record, state(for: record, source: fixture.hermesState.source), messages, appendedAt)
    }

    private func state(for record: CiderAgentChatRecord, source: String?) -> HermesConversationState {
        HermesConversationState(
            conversationID: record.conversationID,
            runtimeID: record.runtimeID,
            activeRuntimeSessionID: record.activeRuntimeSessionID,
            runtimeSessionLineage: record.runtimeSessionLineage,
            title: record.title,
            source: source,
            lastSyncedAt: record.lastSyncedTimestamp,
            lastSyncedMessageID: record.lastSyncedMessageID,
            lastSyncedTimestamp: record.lastSyncedTimestamp,
            lastImportedRuntimeSessionID: record.lastImportedRuntimeSessionID
        )
    }

    private func replacing(
        _ message: AIAssistantMessage,
        role: AIAssistantMessage.Role? = nil,
        timestamp: Date? = nil
    ) -> AIAssistantMessage {
        .init(
            id: message.id,
            role: role ?? message.role,
            content: message.content,
            timestamp: timestamp ?? message.timestamp,
            sourceID: message.sourceID,
            sourceSessionID: message.sourceSessionID,
            sourceName: message.sourceName,
            attachments: message.attachments
        )
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
        coordinator(writer: writer, healthStore: healthStore, reporter: nil)
    }

    func coordinator(
        writer: ConversationShadowWriter,
        healthStore: ConversationShadowHealthStore,
        reporter: ConversationShadowActivationReceiptReporter?
    ) -> LegacyConversationPrimarySaveCoordinator {
        let reconciler = ConversationShadowReconciler(writer: writer, healthStore: healthStore, now: { self.now })
        return LegacyConversationPrimarySaveCoordinator(
            registry: registry,
            conversationStorage: storage,
            healthStore: healthStore,
            shadowWriter: writer,
            reconciler: reconciler,
            receiptReporter: reporter,
            now: { self.now }
        )
    }

    func payload() throws -> ConversationShadowPayload {
        try payload(record: record, messages: messages, hermesState: hermesState)
    }

    func payload(
        record: CiderAgentChatRecord,
        messages: [AIAssistantMessage],
        hermesState: HermesConversationState
    ) throws -> ConversationShadowPayload {
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
