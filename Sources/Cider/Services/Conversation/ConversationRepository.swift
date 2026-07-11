import Foundation

enum ConversationRepositoryError: Error, Equatable, LocalizedError {
    case invalidDraft(String)
    case notFound(String)
    case integrity(String)
    case invalidTransition(from: ConversationTurnStatus, to: ConversationTurnStatus)

    var errorDescription: String? {
        switch self {
        case .invalidDraft(let message), .notFound(let message), .integrity(let message): message
        case .invalidTransition(let from, let to): "Invalid conversation turn transition from \(from.rawValue) to \(to.rawValue)."
        }
    }
}

@MainActor
final class ConversationRepository {
    private let database: CiderDatabase

    init(database: CiderDatabase = .shared) {
        self.database = database
    }

    func createRoom(_ draft: ConversationRoomDraft) throws -> ConversationRoom {
        try database.withTransaction {
            try requireNonempty(draft.title, field: "room title")
            try requireNonempty(draft.kind, field: "room kind")
            let metadata = DatabaseHelpers.encodeJSON(draft.metadata) ?? "{}"
            let timestamp = DatabaseHelpers.encode(draft.createdAt)
            let statement = try database.prepare("""
                INSERT INTO conversation_rooms (
                    id, stable_key, title, kind, lifecycle_state,
                    next_turn_sequence, next_message_sequence, metadata_json,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, 1, 1, ?, ?, ?);
                """)
            statement.bind(draft.id.uuidString, at: 1)
                .bind(draft.stableKey, at: 2)
                .bind(draft.title, at: 3)
                .bind(draft.kind, at: 4)
                .bind(ConversationRoomLifecycle.active.rawValue, at: 5)
                .bind(metadata, at: 6)
                .bind(timestamp, at: 7)
                .bind(timestamp, at: 8)
            try statement.step()
            return try requiredRoom(id: draft.id)
        }
    }

    func room(id: UUID) throws -> ConversationRoom? {
        let statement = try database.prepare("""
            SELECT id, stable_key, title, kind, lifecycle_state,
                   next_turn_sequence, next_message_sequence, metadata_json,
                   created_at, updated_at, archived_at, trashed_at
            FROM conversation_rooms WHERE id = ?;
            """)
        statement.bind(id.uuidString, at: 1)
        return try statement.step() ? try decodeRoom(statement) : nil
    }

    func room(stableKey: String) throws -> ConversationRoom? {
        let statement = try database.prepare("""
            SELECT id, stable_key, title, kind, lifecycle_state,
                   next_turn_sequence, next_message_sequence, metadata_json,
                   created_at, updated_at, archived_at, trashed_at
            FROM conversation_rooms WHERE stable_key = ?;
            """)
        statement.bind(stableKey, at: 1)
        return try statement.step() ? try decodeRoom(statement) : nil
    }

    func setLifecycle(roomID: UUID, state: ConversationRoomLifecycle, at date: Date) throws {
        try database.withTransaction {
            _ = try requiredRoom(id: roomID)
            let archivedAt: Double? = state == .archived ? DatabaseHelpers.encode(date) : nil
            let trashedAt: Double? = state == .trashed ? DatabaseHelpers.encode(date) : nil
            let statement = try database.prepare("""
                UPDATE conversation_rooms
                SET lifecycle_state = ?, updated_at = ?, archived_at = ?, trashed_at = ?
                WHERE id = ?;
                """)
            statement.bind(state.rawValue, at: 1)
                .bind(DatabaseHelpers.encode(date), at: 2)
                .bind(archivedAt, at: 3)
                .bind(trashedAt, at: 4)
                .bind(roomID.uuidString, at: 5)
            try statement.step()
        }
    }

    func upsertRuntimeBinding(_ draft: ConversationRuntimeBindingDraft) throws -> ConversationRuntimeBinding {
        try database.withTransaction {
            _ = try requiredRoom(id: draft.roomID)
            try requireNonempty(draft.runtimeID, field: "runtime id")
            try requireNonempty(draft.transportID, field: "transport id")
            try requireNonempty(draft.sourceNamespace, field: "source namespace")

            let existing = try bindingForUpsert(draft)
            let bindingID = existing?.id ?? draft.id
            try validateBindingParent(draft.parentBindingID, bindingID: bindingID, roomID: draft.roomID)

            let createdAt = existing?.createdAt ?? draft.createdAt
            let updatedAt = Date()
            let statement = try database.prepare("""
                INSERT INTO conversation_runtime_bindings (
                    id, room_id, parent_binding_id, runtime_id, transport_id,
                    source_namespace, external_session_id, binding_state,
                    cursor_message_id, cursor_timestamp, metadata_json,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    parent_binding_id = excluded.parent_binding_id,
                    runtime_id = excluded.runtime_id,
                    transport_id = excluded.transport_id,
                    source_namespace = excluded.source_namespace,
                    external_session_id = excluded.external_session_id,
                    binding_state = excluded.binding_state,
                    cursor_message_id = excluded.cursor_message_id,
                    cursor_timestamp = excluded.cursor_timestamp,
                    metadata_json = excluded.metadata_json,
                    updated_at = excluded.updated_at;
                """)
            statement.bind(bindingID.uuidString, at: 1)
                .bind(draft.roomID.uuidString, at: 2)
                .bind(draft.parentBindingID?.uuidString, at: 3)
                .bind(draft.runtimeID, at: 4)
                .bind(draft.transportID, at: 5)
                .bind(draft.sourceNamespace, at: 6)
                .bind(draft.externalSessionID, at: 7)
                .bind(draft.state.rawValue, at: 8)
                .bind(draft.cursorMessageID, at: 9)
                .bind(draft.cursorTimestamp.map(DatabaseHelpers.encode), at: 10)
                .bind(DatabaseHelpers.encodeJSON(draft.metadata) ?? "{}", at: 11)
                .bind(DatabaseHelpers.encode(createdAt), at: 12)
                .bind(DatabaseHelpers.encode(updatedAt), at: 13)
            try statement.step()
            return try requiredBinding(id: bindingID)
        }
    }

    func bindings(roomID: UUID) throws -> [ConversationRuntimeBinding] {
        let statement = try database.prepare("""
            SELECT id, room_id, parent_binding_id, runtime_id, transport_id,
                   source_namespace, external_session_id, binding_state,
                   cursor_message_id, cursor_timestamp, metadata_json,
                   created_at, updated_at
            FROM conversation_runtime_bindings
            WHERE room_id = ?
            ORDER BY created_at, id;
            """)
        statement.bind(roomID.uuidString, at: 1)
        var results: [ConversationRuntimeBinding] = []
        while try statement.step() { results.append(try decodeBinding(statement)) }
        return results
    }

    func beginTurn(_ draft: ConversationTurnDraft) throws -> ConversationTurn {
        try database.withTransaction {
            _ = try requiredRoom(id: draft.roomID)
            if let bindingID = draft.runtimeBindingID {
                let binding = try requiredBinding(id: bindingID)
                guard binding.roomID == draft.roomID else {
                    throw ConversationRepositoryError.integrity("Runtime binding belongs to another room.")
                }
            }
            try validateSource(draft.source)
            if let source = draft.source, let existing = try turn(source: source) {
                guard existing.roomID == draft.roomID else {
                    throw ConversationRepositoryError.integrity("Turn source identity already belongs to another room.")
                }
                return existing
            }
            if let existing = try turn(id: draft.id) {
                guard existing.roomID == draft.roomID else {
                    throw ConversationRepositoryError.integrity("Turn id already belongs to another room.")
                }
                return existing
            }

            let sequence = try allocateSequence(roomID: draft.roomID, column: "next_turn_sequence")
            let created = DatabaseHelpers.encode(draft.createdAt)
            let started: Double? = draft.status == .running ? created : nil
            let completed: Double? = draft.status.isTerminal ? created : nil
            let statement = try database.prepare("""
                INSERT INTO conversation_turns (
                    id, room_id, sequence, runtime_binding_id,
                    source_namespace, source_turn_id, status,
                    error_code, error_detail, metadata_json,
                    created_at, started_at, completed_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, ?, ?, ?, ?);
                """)
            statement.bind(draft.id.uuidString, at: 1)
                .bind(draft.roomID.uuidString, at: 2)
                .bind(sequence, at: 3)
                .bind(draft.runtimeBindingID?.uuidString, at: 4)
                .bind(draft.source?.namespace, at: 5)
                .bind(draft.source?.id, at: 6)
                .bind(draft.status.rawValue, at: 7)
                .bind(DatabaseHelpers.encodeJSON(draft.metadata) ?? "{}", at: 8)
                .bind(created, at: 9)
                .bind(started, at: 10)
                .bind(completed, at: 11)
                .bind(created, at: 12)
            try statement.step()
            return try requiredTurn(id: draft.id)
        }
    }

    func turn(id: UUID) throws -> ConversationTurn? {
        let statement = try database.prepare("""
            SELECT id, room_id, sequence, runtime_binding_id,
                   source_namespace, source_turn_id, status,
                   error_code, error_detail, metadata_json,
                   created_at, started_at, completed_at, updated_at
            FROM conversation_turns WHERE id = ?;
            """)
        statement.bind(id.uuidString, at: 1)
        return try statement.step() ? try decodeTurn(statement) : nil
    }

    func transitionTurn(
        id: UUID,
        to status: ConversationTurnStatus,
        error: ConversationTurnError? = nil,
        at date: Date
    ) throws -> ConversationTurn {
        try database.withTransaction {
            let current = try requiredTurn(id: id)
            guard isValidTransition(from: current.status, to: status) else {
                throw ConversationRepositoryError.invalidTransition(from: current.status, to: status)
            }
            let startedAt = current.startedAt ?? ((status == .running || status == .waiting) ? date : nil)
            let completedAt = status.isTerminal ? date : current.completedAt
            let statement = try database.prepare("""
                UPDATE conversation_turns
                SET status = ?, error_code = ?, error_detail = ?,
                    started_at = ?, completed_at = ?, updated_at = ?
                WHERE id = ?;
                """)
            statement.bind(status.rawValue, at: 1)
                .bind(error?.code, at: 2)
                .bind(error?.detail, at: 3)
                .bind(startedAt.map(DatabaseHelpers.encode), at: 4)
                .bind(completedAt.map(DatabaseHelpers.encode), at: 5)
                .bind(DatabaseHelpers.encode(date), at: 6)
                .bind(id.uuidString, at: 7)
            try statement.step()
            return try requiredTurn(id: id)
        }
    }

    func upsertMessage(_ draft: ConversationMessageDraft) throws -> ConversationMessageUpsertResult {
        try database.withTransaction {
            try requireNonempty(draft.role, field: "message role")
            try validateSource(draft.source)
            _ = try requiredRoom(id: draft.roomID)

            let existing = try messageForUpsert(draft)
            let messageID = existing?.id ?? draft.id
            if let existing, existing.roomID != draft.roomID {
                throw ConversationRepositoryError.integrity("Message identity already belongs to another room.")
            }
            try validateMessageReferences(draft, messageID: messageID)

            if let existing {
                var updateDraft = draft
                updateDraft.source = draft.source ?? existing.source
                updateDraft.sourceCreatedAt = draft.sourceCreatedAt ?? existing.sourceCreatedAt
                let proposed = ConversationMessage(
                    id: existing.id,
                    roomID: draft.roomID,
                    turnID: updateDraft.turnID,
                    runtimeBindingID: updateDraft.runtimeBindingID,
                    parentMessageID: updateDraft.parentMessageID,
                    sequence: existing.sequence,
                    role: updateDraft.role,
                    contentText: updateDraft.contentText,
                    status: updateDraft.status,
                    finishReason: updateDraft.finishReason,
                    source: updateDraft.source,
                    sourceCreatedAt: updateDraft.sourceCreatedAt,
                    metadata: updateDraft.metadata,
                    createdAt: existing.createdAt,
                    updatedAt: existing.updatedAt
                )
                if samePersistedMessage(existing, proposed) {
                    return .init(disposition: .unchangedReplay, message: existing)
                }
                let updatedAt = Date()
                let statement = try database.prepare("""
                    UPDATE conversation_messages
                    SET turn_id = ?, runtime_binding_id = ?, parent_message_id = ?,
                        role = ?, content_text = ?, status = ?, finish_reason = ?,
                        source_namespace = ?, source_message_id = ?, source_created_at = ?,
                        metadata_json = ?, updated_at = ?
                    WHERE id = ?;
                    """)
                bindMessageFields(updateDraft, to: statement, startingAt: 1)
                statement.bind(DatabaseHelpers.encode(updatedAt), at: 12)
                    .bind(existing.id.uuidString, at: 13)
                try statement.step()
                return .init(disposition: .updatedSameSource, message: try requiredMessage(id: existing.id))
            }

            let sequence = try allocateSequence(roomID: draft.roomID, column: "next_message_sequence")
            let timestamp = DatabaseHelpers.encode(draft.createdAt)
            let statement = try database.prepare("""
                INSERT INTO conversation_messages (
                    id, room_id, turn_id, runtime_binding_id, parent_message_id,
                    sequence, role, content_text, status, finish_reason,
                    source_namespace, source_message_id, source_created_at,
                    metadata_json, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """)
            statement.bind(draft.id.uuidString, at: 1)
                .bind(draft.roomID.uuidString, at: 2)
                .bind(draft.turnID?.uuidString, at: 3)
                .bind(draft.runtimeBindingID?.uuidString, at: 4)
                .bind(draft.parentMessageID?.uuidString, at: 5)
                .bind(sequence, at: 6)
                .bind(draft.role, at: 7)
                .bind(draft.contentText, at: 8)
                .bind(draft.status.rawValue, at: 9)
                .bind(draft.finishReason?.rawValue, at: 10)
                .bind(draft.source?.namespace, at: 11)
                .bind(draft.source?.id, at: 12)
                .bind(draft.sourceCreatedAt.map(DatabaseHelpers.encode), at: 13)
                .bind(DatabaseHelpers.encodeJSON(draft.metadata) ?? "{}", at: 14)
                .bind(timestamp, at: 15)
                .bind(timestamp, at: 16)
            try statement.step()
            return .init(disposition: .inserted, message: try requiredMessage(id: draft.id))
        }
    }

    func recordTurnSnapshot(
        turn draft: ConversationTurnDraft,
        messages drafts: [ConversationMessageDraft]
    ) throws -> ConversationTurnSnapshot {
        try database.withTransaction {
            let turn = try beginTurn(draft)
            var messages: [ConversationMessage] = []
            for draft in drafts {
                guard draft.roomID == turn.roomID, draft.turnID == turn.id else {
                    throw ConversationRepositoryError.integrity("Snapshot messages must reference the snapshot turn and room.")
                }
                messages.append(try upsertMessage(draft).message)
            }
            return ConversationTurnSnapshot(turn: turn, messages: messages)
        }
    }

    func messages(roomID: UUID, throughHead headMessageID: UUID? = nil) throws -> [ConversationMessage] {
        guard let headMessageID else { return try allMessages(roomID: roomID) }
        var ancestry: [ConversationMessage] = []
        var cursor: UUID? = headMessageID
        var visited = Set<UUID>()
        while let id = cursor {
            guard visited.insert(id).inserted else {
                throw ConversationRepositoryError.integrity("Message ancestry contains a cycle.")
            }
            let message = try requiredMessage(id: id)
            guard message.roomID == roomID else {
                throw ConversationRepositoryError.integrity("Message ancestry crosses room boundaries.")
            }
            ancestry.append(message)
            cursor = message.parentMessageID
        }
        return ancestry.reversed()
    }

    private func allMessages(roomID: UUID) throws -> [ConversationMessage] {
        let statement = try database.prepare("""
            SELECT id, room_id, turn_id, runtime_binding_id, parent_message_id,
                   sequence, role, content_text, status, finish_reason,
                   source_namespace, source_message_id, source_created_at,
                   metadata_json, created_at, updated_at
            FROM conversation_messages
            WHERE room_id = ?
            ORDER BY sequence;
            """)
        statement.bind(roomID.uuidString, at: 1)
        var results: [ConversationMessage] = []
        while try statement.step() { results.append(try decodeMessage(statement)) }
        return results
    }

    private func allocateSequence(roomID: UUID, column: String) throws -> Int64 {
        guard column == "next_turn_sequence" || column == "next_message_sequence" else {
            throw ConversationRepositoryError.invalidDraft("Unsupported sequence allocator.")
        }
        let statement = try database.prepare("""
            UPDATE conversation_rooms
            SET \(column) = \(column) + 1, updated_at = ?
            WHERE id = ?
            RETURNING \(column) - 1;
            """)
        statement.bind(DatabaseHelpers.encode(Date()), at: 1)
            .bind(roomID.uuidString, at: 2)
        guard try statement.step() else {
            throw ConversationRepositoryError.notFound("Conversation room was not found.")
        }
        return statement.int64(at: 0)
    }

    private func validateMessageReferences(_ draft: ConversationMessageDraft, messageID: UUID) throws {
        if let turnID = draft.turnID {
            let turn = try requiredTurn(id: turnID)
            guard turn.roomID == draft.roomID else {
                throw ConversationRepositoryError.integrity("Message turn belongs to another room.")
            }
        }
        if let bindingID = draft.runtimeBindingID {
            let binding = try requiredBinding(id: bindingID)
            guard binding.roomID == draft.roomID else {
                throw ConversationRepositoryError.integrity("Message runtime binding belongs to another room.")
            }
        }
        guard let parentID = draft.parentMessageID else { return }
        guard parentID != messageID else {
            throw ConversationRepositoryError.integrity("A message cannot parent itself.")
        }
        let parent = try requiredMessage(id: parentID)
        guard parent.roomID == draft.roomID else {
            throw ConversationRepositoryError.integrity("Message parent belongs to another room.")
        }
        var cursor: UUID? = parentID
        var visited = Set<UUID>()
        while let id = cursor {
            guard visited.insert(id).inserted else {
                throw ConversationRepositoryError.integrity("Message parent ancestry already contains a cycle.")
            }
            guard id != messageID else {
                throw ConversationRepositoryError.integrity("Message parent would create a cycle.")
            }
            cursor = try requiredMessage(id: id).parentMessageID
        }
    }

    private func validateBindingParent(_ parentID: UUID?, bindingID: UUID, roomID: UUID) throws {
        guard let parentID else { return }
        guard parentID != bindingID else {
            throw ConversationRepositoryError.integrity("A runtime binding cannot parent itself.")
        }
        let parent = try requiredBinding(id: parentID)
        guard parent.roomID == roomID else {
            throw ConversationRepositoryError.integrity("Runtime binding parent belongs to another room.")
        }
        var cursor: UUID? = parentID
        var visited = Set<UUID>()
        while let id = cursor {
            guard visited.insert(id).inserted else {
                throw ConversationRepositoryError.integrity("Runtime binding ancestry already contains a cycle.")
            }
            guard id != bindingID else {
                throw ConversationRepositoryError.integrity("Runtime binding parent would create a cycle.")
            }
            cursor = try requiredBinding(id: id).parentBindingID
        }
    }

    private func isValidTransition(from: ConversationTurnStatus, to: ConversationTurnStatus) -> Bool {
        guard from != to, !from.isTerminal else { return false }
        return switch (from, to) {
        case (.pending, .running), (.pending, .waiting), (.pending, .completed),
             (.pending, .failed), (.pending, .cancelled),
             (.running, .waiting), (.running, .completed), (.running, .failed), (.running, .cancelled),
             (.waiting, .running), (.waiting, .completed), (.waiting, .failed), (.waiting, .cancelled):
            true
        default:
            false
        }
    }

    private func validateSource(_ source: ConversationSourceIdentity?) throws {
        guard let source else { return }
        try requireNonempty(source.namespace, field: "source namespace")
        try requireNonempty(source.id, field: "source id")
    }

    private func requireNonempty(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConversationRepositoryError.invalidDraft("Conversation \(field) must not be empty.")
        }
    }

    private func requiredRoom(id: UUID) throws -> ConversationRoom {
        guard let room = try room(id: id) else {
            throw ConversationRepositoryError.notFound("Conversation room \(id) was not found.")
        }
        return room
    }

    private func requiredTurn(id: UUID) throws -> ConversationTurn {
        guard let turn = try turn(id: id) else {
            throw ConversationRepositoryError.notFound("Conversation turn \(id) was not found.")
        }
        return turn
    }

    private func requiredBinding(id: UUID) throws -> ConversationRuntimeBinding {
        guard let binding = try binding(id: id) else {
            throw ConversationRepositoryError.notFound("Conversation runtime binding \(id) was not found.")
        }
        return binding
    }

    private func requiredMessage(id: UUID) throws -> ConversationMessage {
        guard let message = try message(id: id) else {
            throw ConversationRepositoryError.notFound("Conversation message \(id) was not found.")
        }
        return message
    }

    private func binding(id: UUID) throws -> ConversationRuntimeBinding? {
        let statement = try database.prepare("""
            SELECT id, room_id, parent_binding_id, runtime_id, transport_id,
                   source_namespace, external_session_id, binding_state,
                   cursor_message_id, cursor_timestamp, metadata_json,
                   created_at, updated_at
            FROM conversation_runtime_bindings WHERE id = ?;
            """)
        statement.bind(id.uuidString, at: 1)
        return try statement.step() ? try decodeBinding(statement) : nil
    }

    private func bindingForUpsert(_ draft: ConversationRuntimeBindingDraft) throws -> ConversationRuntimeBinding? {
        if let externalID = draft.externalSessionID {
            let statement = try database.prepare("""
                SELECT id, room_id, parent_binding_id, runtime_id, transport_id,
                       source_namespace, external_session_id, binding_state,
                       cursor_message_id, cursor_timestamp, metadata_json,
                       created_at, updated_at
                FROM conversation_runtime_bindings
                WHERE source_namespace = ? AND external_session_id = ?;
                """)
            statement.bind(draft.sourceNamespace, at: 1).bind(externalID, at: 2)
            if try statement.step() {
                let existing = try decodeBinding(statement)
                guard existing.roomID == draft.roomID else {
                    throw ConversationRepositoryError.integrity("Runtime session identity already belongs to another room.")
                }
                return existing
            }
        }
        return try binding(id: draft.id)
    }

    private func turn(source: ConversationSourceIdentity) throws -> ConversationTurn? {
        let statement = try database.prepare("""
            SELECT id, room_id, sequence, runtime_binding_id,
                   source_namespace, source_turn_id, status,
                   error_code, error_detail, metadata_json,
                   created_at, started_at, completed_at, updated_at
            FROM conversation_turns
            WHERE source_namespace = ? AND source_turn_id = ?;
            """)
        statement.bind(source.namespace, at: 1).bind(source.id, at: 2)
        return try statement.step() ? try decodeTurn(statement) : nil
    }

    private func message(id: UUID) throws -> ConversationMessage? {
        let statement = try database.prepare("""
            SELECT id, room_id, turn_id, runtime_binding_id, parent_message_id,
                   sequence, role, content_text, status, finish_reason,
                   source_namespace, source_message_id, source_created_at,
                   metadata_json, created_at, updated_at
            FROM conversation_messages WHERE id = ?;
            """)
        statement.bind(id.uuidString, at: 1)
        return try statement.step() ? try decodeMessage(statement) : nil
    }

    private func message(source: ConversationSourceIdentity) throws -> ConversationMessage? {
        let statement = try database.prepare("""
            SELECT id, room_id, turn_id, runtime_binding_id, parent_message_id,
                   sequence, role, content_text, status, finish_reason,
                   source_namespace, source_message_id, source_created_at,
                   metadata_json, created_at, updated_at
            FROM conversation_messages
            WHERE source_namespace = ? AND source_message_id = ?;
            """)
        statement.bind(source.namespace, at: 1).bind(source.id, at: 2)
        return try statement.step() ? try decodeMessage(statement) : nil
    }

    private func messageForUpsert(_ draft: ConversationMessageDraft) throws -> ConversationMessage? {
        if let source = draft.source, let existing = try message(source: source) { return existing }
        return try message(id: draft.id)
    }

    private func bindMessageFields(_ draft: ConversationMessageDraft, to statement: SQLStatement, startingAt index: Int32) {
        statement.bind(draft.turnID?.uuidString, at: index)
            .bind(draft.runtimeBindingID?.uuidString, at: index + 1)
            .bind(draft.parentMessageID?.uuidString, at: index + 2)
            .bind(draft.role, at: index + 3)
            .bind(draft.contentText, at: index + 4)
            .bind(draft.status.rawValue, at: index + 5)
            .bind(draft.finishReason?.rawValue, at: index + 6)
            .bind(draft.source?.namespace, at: index + 7)
            .bind(draft.source?.id, at: index + 8)
            .bind(draft.sourceCreatedAt.map(DatabaseHelpers.encode), at: index + 9)
            .bind(DatabaseHelpers.encodeJSON(draft.metadata) ?? "{}", at: index + 10)
    }

    private func samePersistedMessage(_ lhs: ConversationMessage, _ rhs: ConversationMessage) -> Bool {
        lhs.roomID == rhs.roomID && lhs.turnID == rhs.turnID &&
        lhs.runtimeBindingID == rhs.runtimeBindingID && lhs.parentMessageID == rhs.parentMessageID &&
        lhs.role == rhs.role && lhs.contentText == rhs.contentText && lhs.status == rhs.status &&
        lhs.finishReason == rhs.finishReason && lhs.source == rhs.source &&
        lhs.sourceCreatedAt == rhs.sourceCreatedAt && lhs.metadata == rhs.metadata
    }

    private func decodeRoom(_ statement: SQLStatement) throws -> ConversationRoom {
        guard let id = UUID(uuidString: statement.string(at: 0)),
              let lifecycle = ConversationRoomLifecycle(rawValue: statement.string(at: 4)) else {
            throw ConversationRepositoryError.integrity("Conversation room contains invalid persisted values.")
        }
        return ConversationRoom(
            id: id,
            stableKey: statement.optionalString(at: 1),
            title: statement.string(at: 2),
            kind: statement.string(at: 3),
            lifecycleState: lifecycle,
            nextTurnSequence: statement.int64(at: 5),
            nextMessageSequence: statement.int64(at: 6),
            metadata: DatabaseHelpers.decodeJSON([String: String].self, from: statement.optionalString(at: 7)) ?? [:],
            createdAt: DatabaseHelpers.decodeDate(statement.double(at: 8)),
            updatedAt: DatabaseHelpers.decodeDate(statement.double(at: 9)),
            archivedAt: statement.optionalDouble(at: 10).map(DatabaseHelpers.decodeDate),
            trashedAt: statement.optionalDouble(at: 11).map(DatabaseHelpers.decodeDate)
        )
    }

    private func decodeBinding(_ statement: SQLStatement) throws -> ConversationRuntimeBinding {
        guard let id = UUID(uuidString: statement.string(at: 0)),
              let roomID = UUID(uuidString: statement.string(at: 1)),
              let state = ConversationRuntimeBindingState(rawValue: statement.string(at: 7)) else {
            throw ConversationRepositoryError.integrity("Conversation runtime binding contains invalid persisted values.")
        }
        return ConversationRuntimeBinding(
            id: id,
            roomID: roomID,
            parentBindingID: statement.optionalString(at: 2).flatMap(UUID.init(uuidString:)),
            runtimeID: statement.string(at: 3),
            transportID: statement.string(at: 4),
            sourceNamespace: statement.string(at: 5),
            externalSessionID: statement.optionalString(at: 6),
            state: state,
            cursorMessageID: statement.optionalString(at: 8),
            cursorTimestamp: statement.optionalDouble(at: 9).map(DatabaseHelpers.decodeDate),
            metadata: DatabaseHelpers.decodeJSON([String: String].self, from: statement.optionalString(at: 10)) ?? [:],
            createdAt: DatabaseHelpers.decodeDate(statement.double(at: 11)),
            updatedAt: DatabaseHelpers.decodeDate(statement.double(at: 12))
        )
    }

    private func decodeTurn(_ statement: SQLStatement) throws -> ConversationTurn {
        guard let id = UUID(uuidString: statement.string(at: 0)),
              let roomID = UUID(uuidString: statement.string(at: 1)),
              let status = ConversationTurnStatus(rawValue: statement.string(at: 6)) else {
            throw ConversationRepositoryError.integrity("Conversation turn contains invalid persisted values.")
        }
        let source = sourceIdentity(namespace: statement.optionalString(at: 4), id: statement.optionalString(at: 5))
        let errorCode = statement.optionalString(at: 7)
        return ConversationTurn(
            id: id,
            roomID: roomID,
            sequence: statement.int64(at: 2),
            runtimeBindingID: statement.optionalString(at: 3).flatMap(UUID.init(uuidString:)),
            source: source,
            status: status,
            error: errorCode.map { .init(code: $0, detail: statement.optionalString(at: 8)) },
            metadata: DatabaseHelpers.decodeJSON([String: String].self, from: statement.optionalString(at: 9)) ?? [:],
            createdAt: DatabaseHelpers.decodeDate(statement.double(at: 10)),
            startedAt: statement.optionalDouble(at: 11).map(DatabaseHelpers.decodeDate),
            completedAt: statement.optionalDouble(at: 12).map(DatabaseHelpers.decodeDate),
            updatedAt: DatabaseHelpers.decodeDate(statement.double(at: 13))
        )
    }

    private func decodeMessage(_ statement: SQLStatement) throws -> ConversationMessage {
        guard let id = UUID(uuidString: statement.string(at: 0)),
              let roomID = UUID(uuidString: statement.string(at: 1)),
              let status = ConversationMessageStatus(rawValue: statement.string(at: 8)) else {
            throw ConversationRepositoryError.integrity("Conversation message contains invalid persisted values.")
        }
        let finishReason: ConversationMessageFinishReason?
        if let rawReason = statement.optionalString(at: 9) {
            guard let decoded = ConversationMessageFinishReason(rawValue: rawReason) else {
                throw ConversationRepositoryError.integrity("Conversation message contains an invalid finish reason.")
            }
            finishReason = decoded
        } else {
            finishReason = nil
        }
        return ConversationMessage(
            id: id,
            roomID: roomID,
            turnID: statement.optionalString(at: 2).flatMap(UUID.init(uuidString:)),
            runtimeBindingID: statement.optionalString(at: 3).flatMap(UUID.init(uuidString:)),
            parentMessageID: statement.optionalString(at: 4).flatMap(UUID.init(uuidString:)),
            sequence: statement.int64(at: 5),
            role: statement.string(at: 6),
            contentText: statement.string(at: 7),
            status: status,
            finishReason: finishReason,
            source: sourceIdentity(namespace: statement.optionalString(at: 10), id: statement.optionalString(at: 11)),
            sourceCreatedAt: statement.optionalDouble(at: 12).map(DatabaseHelpers.decodeDate),
            metadata: DatabaseHelpers.decodeJSON([String: String].self, from: statement.optionalString(at: 13)) ?? [:],
            createdAt: DatabaseHelpers.decodeDate(statement.double(at: 14)),
            updatedAt: DatabaseHelpers.decodeDate(statement.double(at: 15))
        )
    }

    private func sourceIdentity(namespace: String?, id: String?) -> ConversationSourceIdentity? {
        guard let namespace, let id else { return nil }
        return ConversationSourceIdentity(namespace: namespace, id: id)
    }
}
