import Foundation

enum ConversationShadowWriterError: Error, Equatable {
    case conflict(String)
    case parity(String)
}

enum ConversationShadowWriterCheckpoint: Equatable, Sendable {
    case room
    case roomUpdate
    case bindings
    case bindingUpdates
    case turns
    case messages
    case counterFinalization
    case parity
}

/// Dormant, fixture-driven legacy shadow writer. It has no live/shared defaults and no production caller.
@MainActor
final class ConversationShadowWriter {
    private let database: CiderDatabase
    private let repository: ConversationRepository
    private let mapper: LegacyConversationSnapshotMapper
    private let checkpoint: (ConversationShadowWriterCheckpoint) throws -> Void

    init(
        database: CiderDatabase,
        repository: ConversationRepository,
        mapper: LegacyConversationSnapshotMapper = .init(),
        checkpoint: @escaping (ConversationShadowWriterCheckpoint) throws -> Void = { _ in }
    ) {
        self.database = database
        self.repository = repository
        self.mapper = mapper
        self.checkpoint = checkpoint
    }

    func write(_ payload: ConversationShadowPayload) throws {
        let plan = mappedPlan(payload)
        try database.withTransaction {
            try writeRoom(try requiredSingleRoom(plan))
            try checkpoint(.room)
            try writeBindings(plan.bindings)
            try checkpoint(.bindings)
            try writeTurns(plan.turns)
            try checkpoint(.turns)
            try writeMessages(plan.messages)
            try checkpoint(.messages)
            let room = try requiredSingleRoom(plan)
            try repository.finalizeHistoricalRoomImport(
                roomID: room.id,
                nextTurnSequence: room.nextTurnSequence,
                nextMessageSequence: room.nextMessageSequence,
                updatedAt: room.updatedAt
            )
            try requireExactParity(plan)
            try checkpoint(.parity)
        }
    }

    /// Dormant CID-776 mode for a completed snapshot whose persisted state is a proven exact prefix.
    func writeVerifiedSequentialCompletedSnapshot(_ payload: ConversationShadowPayload) throws {
        let plan = mappedPlan(payload)
        try database.withTransaction {
            let room = try requiredSingleRoom(plan)
            try validateVerifiedSequentialPrefix(plan)
            try advanceOrInsertRoom(room)
            try checkpoint(.room)
            try checkpoint(.roomUpdate)
            try advanceOrInsertBindings(plan.bindings)
            try checkpoint(.bindings)
            try checkpoint(.bindingUpdates)
            try writeTurns(plan.turns)
            try checkpoint(.turns)
            try writeMessages(plan.messages)
            try checkpoint(.messages)
            try repository.finalizeHistoricalRoomImport(
                roomID: room.id,
                nextTurnSequence: room.nextTurnSequence,
                nextMessageSequence: room.nextMessageSequence,
                updatedAt: room.updatedAt
            )
            try checkpoint(.counterFinalization)
            try requireExactParity(plan)
            try checkpoint(.parity)
        }
    }

    func hasExactParity(_ payload: ConversationShadowPayload) throws -> Bool {
        do {
            try requireExactParity(mappedPlan(payload))
            return true
        } catch let error as ConversationShadowWriterError {
            if case .parity = error { return false }
            throw error
        }
    }

    func hasVerifiedSequentialCompletedSnapshotParity(
        _ payload: ConversationShadowPayload
    ) throws -> Bool {
        try hasExactParity(payload)
    }

    func semanticFingerprint(
        _ payload: ConversationShadowPayload
    ) throws -> ConversationShadowSemanticFingerprint {
        let plan = mappedPlan(payload)
        _ = try requiredSingleRoom(plan)
        return ConversationShadowSemanticFingerprintBuilder().make(plan)
    }

    func provesRepresentation(
        of older: ConversationShadowSemanticFingerprint,
        by payload: ConversationShadowPayload
    ) throws -> Bool {
        let plan = mappedPlan(payload)
        guard try hasVerifiedSequentialCompletedSnapshotParity(payload) else { return false }
        return ConversationShadowSemanticFingerprintBuilder().provesPrefix(
            older,
            isRepresentedBy: plan
        )
    }

    private func mappedPlan(_ payload: ConversationShadowPayload) -> LegacyConversationImportPlan {
        mapper.map(
            record: payload.registry.record,
            metadata: payload.conversation.metadata,
            messages: payload.conversation.messages.enumerated().map {
                .init(physicalLine: $0.offset + 2, message: $0.element)
            }
        )
    }

    private func requiredSingleRoom(_ plan: LegacyConversationImportPlan) throws -> LegacyConversationRoomPlanRecord {
        guard plan.rooms.count == 1, let room = plan.rooms.first else {
            throw ConversationShadowWriterError.conflict("Snapshot mapper did not produce exactly one room.")
        }
        return room
    }

    private func writeRoom(_ planned: LegacyConversationRoomPlanRecord) throws {
        let byID = try repository.room(id: planned.id)
        let byStableKey = try repository.room(stableKey: planned.stableKey)
        if let byID, let byStableKey, byID.id != byStableKey.id {
            throw ConversationShadowWriterError.conflict("Room ID and stable key resolve to different rooms.")
        }
        if let existing = byID ?? byStableKey {
            guard sameRoomIdentity(existing, planned),
                  existing.nextTurnSequence <= planned.nextTurnSequence,
                  existing.nextMessageSequence <= planned.nextMessageSequence else {
                throw ConversationShadowWriterError.conflict("Existing room conflicts with the mapped legacy snapshot.")
            }
            return
        }
        _ = try repository.createRoom(.init(
            id: planned.id,
            stableKey: planned.stableKey,
            title: planned.title,
            kind: planned.kind,
            metadata: planned.metadata,
            createdAt: planned.createdAt,
            updatedAt: planned.updatedAt
        ))
        if planned.lifecycleState != .active {
            try repository.setLifecycle(roomID: planned.id, state: planned.lifecycleState, at: planned.archivedAt ?? planned.updatedAt)
        }
    }

    private func validateVerifiedSequentialPrefix(_ plan: LegacyConversationImportPlan) throws {
        let plannedRoom = try requiredSingleRoom(plan)
        guard let existingRoom = try repository.room(id: plannedRoom.id) else {
            guard try repository.room(stableKey: plannedRoom.stableKey) == nil else {
                throw ConversationShadowWriterError.conflict("Room stable key belongs to another room.")
            }
            return
        }
        if let stableRoom = try repository.room(stableKey: plannedRoom.stableKey), stableRoom.id != plannedRoom.id {
            throw ConversationShadowWriterError.conflict("Room ID and stable key resolve to different rooms.")
        }
        guard sameRoomImmutable(existingRoom, plannedRoom),
              existingRoom.updatedAt <= plannedRoom.updatedAt,
              lifecycleCanAdvance(from: existingRoom.lifecycleState, to: plannedRoom.lifecycleState),
              existingRoom.trashedAt == nil else {
            throw ConversationShadowWriterError.conflict("Existing room is not a monotonic prefix of the completed snapshot.")
        }

        let existingBindings = try repository.bindings(roomID: plannedRoom.id)
        let orderedBindings = try bindingsInLineageOrder(existingBindings)
        guard orderedBindings.count <= plan.bindings.count else {
            throw ConversationShadowWriterError.conflict("A runtime binding disappeared from the completed snapshot.")
        }
        for (existing, planned) in zip(orderedBindings, plan.bindings) {
            guard sameBindingImmutable(existing, planned),
                  bindingStateCanAdvance(from: existing.state, to: planned.state),
                  existing.updatedAt <= planned.updatedAt else {
                throw ConversationShadowWriterError.conflict("Existing runtime binding is not a monotonic prefix row.")
            }
        }
        let oldCursorHighWater = existingBindings.compactMap(\.cursorTimestamp).max()
        let newCursorHighWater = plan.bindings.compactMap(\.cursorTimestamp).max()
        if let oldCursorHighWater {
            guard let newCursorHighWater, newCursorHighWater >= oldCursorHighWater else {
                throw ConversationShadowWriterError.conflict("Runtime binding cursor high-water regressed.")
            }
        }
        let oldActive = existingBindings.first { $0.state == .active }
        let newActive = plan.bindings.first { $0.state == .active }
        if let oldCursorID = oldActive?.cursorMessageID,
           oldCursorID != newActive?.cursorMessageID {
            guard let oldTimestamp = oldActive?.cursorTimestamp,
                  let newTimestamp = newActive?.cursorTimestamp,
                  newTimestamp >= oldTimestamp else {
                throw ConversationShadowWriterError.conflict(
                    "Runtime binding cursor identity changed without monotonic timestamp proof."
                )
            }
        }

        let existingTurns = try repository.turns(roomID: plannedRoom.id)
        guard existingTurns.count <= plan.turns.count,
              zip(existingTurns, plan.turns).allSatisfy({ sameTurn($0, $1) }),
              plan.turns.dropFirst(existingTurns.count).allSatisfy({ $0.status.isTerminal }) else {
            throw ConversationShadowWriterError.conflict("Existing turns are not an exact terminal prefix.")
        }
        let existingMessages = try repository.messages(roomID: plannedRoom.id)
        guard existingMessages.count <= plan.messages.count,
              zip(existingMessages, plan.messages).allSatisfy({ sameMessage($0, $1) }),
              plan.messages.dropFirst(existingMessages.count).allSatisfy({
                  $0.status == .complete || $0.status == .incomplete
              }) else {
            throw ConversationShadowWriterError.conflict("Existing messages are not an exact terminal prefix.")
        }
        guard existingRoom.nextTurnSequence == Int64(existingTurns.count + 1),
              existingRoom.nextMessageSequence == Int64(existingMessages.count + 1),
              plannedRoom.nextTurnSequence == Int64(plan.turns.count + 1),
              plannedRoom.nextMessageSequence == Int64(plan.messages.count + 1) else {
            throw ConversationShadowWriterError.conflict("Conversation sequence high-water contains a gap.")
        }
    }

    private func advanceOrInsertRoom(_ planned: LegacyConversationRoomPlanRecord) throws {
        guard let existing = try repository.room(id: planned.id) else {
            try writeRoom(planned)
            return
        }
        guard !sameRoomMutable(existing, planned) else { return }
        try repository.advanceVerifiedHistoricalRoomSnapshot(
            roomID: planned.id,
            title: planned.title,
            lifecycleState: planned.lifecycleState,
            metadata: planned.metadata,
            updatedAt: planned.updatedAt,
            archivedAt: planned.archivedAt
        )
    }

    private func advanceOrInsertBindings(
        _ planned: [LegacyConversationBindingPlanRecord]
    ) throws {
        guard let roomID = planned.first?.roomID else { return }
        let existingByID = Dictionary(
            uniqueKeysWithValues: try repository.bindings(roomID: roomID).map { ($0.id, $0) }
        )
        for binding in planned {
            if let existing = existingByID[binding.id], sameBinding(existing, binding) { continue }
            let persisted = try repository.upsertRuntimeBinding(.init(
                id: binding.id,
                roomID: binding.roomID,
                parentBindingID: binding.parentBindingID,
                runtimeID: binding.runtimeID,
                transportID: binding.transportID,
                sourceNamespace: binding.sourceNamespace,
                externalSessionID: binding.externalSessionID,
                state: binding.state,
                cursorMessageID: binding.cursorMessageID,
                cursorTimestamp: binding.cursorTimestamp,
                metadata: binding.metadata,
                createdAt: binding.createdAt,
                updatedAt: binding.updatedAt
            ))
            guard sameBinding(persisted, binding) else {
                throw ConversationShadowWriterError.conflict(
                    "Advanced runtime binding did not match the completed snapshot."
                )
            }
        }
    }

    private func bindingsInLineageOrder(
        _ bindings: [ConversationRuntimeBinding]
    ) throws -> [ConversationRuntimeBinding] {
        let indexed = bindings.compactMap { binding -> (Int, ConversationRuntimeBinding)? in
            guard let raw = binding.metadata["lineageIndex"], let index = Int(raw) else { return nil }
            return (index, binding)
        }.sorted { $0.0 < $1.0 }
        guard indexed.count == bindings.count,
              indexed.map(\.0) == Array(0..<bindings.count) else {
            throw ConversationShadowWriterError.conflict("Runtime binding lineage is not contiguous.")
        }
        return indexed.map(\.1)
    }

    private func lifecycleCanAdvance(
        from existing: ConversationRoomLifecycle,
        to planned: ConversationRoomLifecycle
    ) -> Bool {
        existing == planned || (existing == .active && planned == .archived)
    }

    private func bindingStateCanAdvance(
        from existing: ConversationRuntimeBindingState,
        to planned: ConversationRuntimeBindingState
    ) -> Bool {
        existing == planned || (existing == .active && planned == .inactive)
    }

    private func writeBindings(_ planned: [LegacyConversationBindingPlanRecord]) throws {
        guard let roomID = planned.first?.roomID else { return }
        let existing = try repository.bindings(roomID: roomID)
        for binding in planned {
            let match = existing.first(where: { $0.id == binding.id }) ?? existing.first(where: {
                $0.sourceNamespace == binding.sourceNamespace && $0.externalSessionID == binding.externalSessionID
            })
            if let match {
                guard sameBinding(match, binding) else {
                    throw ConversationShadowWriterError.conflict("Existing runtime binding conflicts with the mapped legacy snapshot.")
                }
                continue
            }
            let inserted = try repository.upsertRuntimeBinding(.init(
                id: binding.id,
                roomID: binding.roomID,
                parentBindingID: binding.parentBindingID,
                runtimeID: binding.runtimeID,
                transportID: binding.transportID,
                sourceNamespace: binding.sourceNamespace,
                externalSessionID: binding.externalSessionID,
                state: binding.state,
                cursorMessageID: binding.cursorMessageID,
                cursorTimestamp: binding.cursorTimestamp,
                metadata: binding.metadata,
                createdAt: binding.createdAt,
                updatedAt: binding.updatedAt
            ))
            guard sameBinding(inserted, binding) else {
                throw ConversationShadowWriterError.conflict("Inserted runtime binding did not match the mapped legacy snapshot.")
            }
        }
    }

    private func writeTurns(_ planned: [LegacyConversationTurnPlanRecord]) throws {
        for turn in planned {
            let byID = try repository.turn(id: turn.id)
            let bySource = try repository.turn(source: turn.source)
            if let byID, let bySource, byID.id != bySource.id {
                throw ConversationShadowWriterError.conflict("Turn ID and source identity resolve to different turns.")
            }
            if let existing = byID ?? bySource {
                guard sameTurn(existing, turn) else {
                    throw ConversationShadowWriterError.conflict("Existing turn conflicts with the mapped legacy snapshot.")
                }
                continue
            }
            let inserted = try repository.beginTurn(.init(
                id: turn.id,
                roomID: turn.roomID,
                runtimeBindingID: turn.runtimeBindingID,
                source: turn.source,
                status: turn.status,
                metadata: turn.metadata,
                createdAt: turn.createdAt
            ))
            guard sameTurn(inserted, turn) else {
                throw ConversationShadowWriterError.conflict("Inserted turn did not match the mapped legacy snapshot.")
            }
        }
    }

    private func writeMessages(_ planned: [LegacyConversationMessagePlanRecord]) throws {
        for message in planned {
            let result = try repository.upsertMessage(.init(
                id: message.id,
                roomID: message.roomID,
                turnID: message.turnID,
                runtimeBindingID: message.runtimeBindingID,
                parentMessageID: message.parentMessageID,
                role: message.role,
                contentText: message.contentText,
                status: message.status,
                finishReason: message.finishReason,
                source: message.source,
                sourceCreatedAt: message.sourceCreatedAt,
                metadata: message.metadata,
                createdAt: message.createdAt
            ), intent: .historicalReplay)
            guard sameMessage(result.message, message) else {
                throw ConversationShadowWriterError.conflict("Persisted message did not match the mapped legacy snapshot.")
            }
        }
    }

    private func requireExactParity(_ plan: LegacyConversationImportPlan) throws {
        let room = try requiredSingleRoom(plan)
        guard let persistedRoom = try repository.room(id: room.id), sameRoom(persistedRoom, room) else {
            throw ConversationShadowWriterError.parity("Room read-back parity failed.")
        }
        let bindings = try repository.bindings(roomID: room.id)
        let bindingsByID = Dictionary(uniqueKeysWithValues: bindings.map { ($0.id, $0) })
        guard bindings.count == plan.bindings.count,
              plan.bindings.allSatisfy({ planned in
                  bindingsByID[planned.id].map { sameBinding($0, planned) } ?? false
              }) else {
            throw ConversationShadowWriterError.parity("Runtime binding read-back parity failed.")
        }
        let persistedTurns = try repository.turns(roomID: room.id)
        guard persistedTurns.count == plan.turns.count,
              zip(persistedTurns, plan.turns).allSatisfy({ sameTurn($0, $1) }) else {
            throw ConversationShadowWriterError.parity("Turn read-back parity failed.")
        }
        let messages = try repository.messages(roomID: room.id)
        guard messages.count == plan.messages.count,
              zip(messages, plan.messages).allSatisfy({ sameMessage($0, $1) }) else {
            throw ConversationShadowWriterError.parity("Message read-back parity failed.")
        }
    }

    private func sameRoomIdentity(_ value: ConversationRoom, _ plan: LegacyConversationRoomPlanRecord) -> Bool {
        value.id == plan.id && value.stableKey == plan.stableKey && value.title == plan.title &&
        value.kind == plan.kind && value.lifecycleState == plan.lifecycleState && value.metadata == plan.metadata &&
        value.createdAt == plan.createdAt && value.updatedAt == plan.updatedAt &&
        value.archivedAt == plan.archivedAt && value.trashedAt == nil
    }

    private func sameRoomImmutable(
        _ value: ConversationRoom,
        _ plan: LegacyConversationRoomPlanRecord
    ) -> Bool {
        value.id == plan.id && value.stableKey == plan.stableKey && value.kind == plan.kind &&
        value.createdAt == plan.createdAt
    }

    private func sameRoomMutable(
        _ value: ConversationRoom,
        _ plan: LegacyConversationRoomPlanRecord
    ) -> Bool {
        value.title == plan.title && value.lifecycleState == plan.lifecycleState &&
        value.metadata == plan.metadata && value.updatedAt == plan.updatedAt &&
        value.archivedAt == plan.archivedAt && value.trashedAt == nil
    }

    private func sameRoom(_ value: ConversationRoom, _ plan: LegacyConversationRoomPlanRecord) -> Bool {
        sameRoomIdentity(value, plan) && value.nextTurnSequence == plan.nextTurnSequence &&
        value.nextMessageSequence == plan.nextMessageSequence
    }

    private func sameBinding(_ value: ConversationRuntimeBinding, _ plan: LegacyConversationBindingPlanRecord) -> Bool {
        value.id == plan.id && value.roomID == plan.roomID && value.parentBindingID == plan.parentBindingID &&
        value.runtimeID == plan.runtimeID && value.transportID == plan.transportID &&
        value.sourceNamespace == plan.sourceNamespace && value.externalSessionID == plan.externalSessionID &&
        value.state == plan.state && value.cursorMessageID == plan.cursorMessageID &&
        value.cursorTimestamp == plan.cursorTimestamp && value.metadata == plan.metadata &&
        value.createdAt == plan.createdAt && value.updatedAt == plan.updatedAt
    }

    private func sameBindingImmutable(
        _ value: ConversationRuntimeBinding,
        _ plan: LegacyConversationBindingPlanRecord
    ) -> Bool {
        value.id == plan.id && value.roomID == plan.roomID &&
        value.parentBindingID == plan.parentBindingID && value.runtimeID == plan.runtimeID &&
        value.transportID == plan.transportID && value.sourceNamespace == plan.sourceNamespace &&
        value.externalSessionID == plan.externalSessionID && value.createdAt == plan.createdAt
    }

    private func sameTurn(_ value: ConversationTurn, _ plan: LegacyConversationTurnPlanRecord) -> Bool {
        value.id == plan.id && value.roomID == plan.roomID && value.sequence == plan.sequence &&
        value.runtimeBindingID == plan.runtimeBindingID && value.source == plan.source && value.status == plan.status &&
        value.error == nil && value.metadata == plan.metadata && value.createdAt == plan.createdAt &&
        value.startedAt == plan.startedAt && value.completedAt == plan.completedAt && value.updatedAt == plan.updatedAt
    }

    private func sameMessage(_ value: ConversationMessage, _ plan: LegacyConversationMessagePlanRecord) -> Bool {
        value.id == plan.id && value.roomID == plan.roomID && value.turnID == plan.turnID &&
        value.runtimeBindingID == plan.runtimeBindingID && value.parentMessageID == plan.parentMessageID &&
        value.sequence == plan.sequence && value.role == plan.role && value.contentText == plan.contentText &&
        value.status == plan.status && value.finishReason == plan.finishReason && value.source == plan.source &&
        value.sourceCreatedAt == plan.sourceCreatedAt && value.metadata == plan.metadata &&
        value.createdAt == plan.createdAt && value.updatedAt == plan.updatedAt
    }
}
