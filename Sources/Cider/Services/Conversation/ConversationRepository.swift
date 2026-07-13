import Foundation

enum ConversationRepositoryError: Error, Equatable, LocalizedError {
    case invalidDraft(String)
    case notFound(String)
    case integrity(String)
    case invalidTransition(from: ConversationTurnStatus, to: ConversationTurnStatus)
    case invalidMessageTransition(from: ConversationMessageStatus, to: ConversationMessageStatus)

    var errorDescription: String? {
        switch self {
        case .invalidDraft(let message), .notFound(let message), .integrity(let message): message
        case .invalidTransition(let from, let to): "Invalid conversation turn transition from \(from.rawValue) to \(to.rawValue)."
        case .invalidMessageTransition(let from, let to): "Invalid conversation message transition from \(from.rawValue) to \(to.rawValue)."
        }
    }
}

@MainActor
final class ConversationRepository {
    private static let maximumBoundedReadLimit = 500
    static let agentAssignmentMetadataKey = "cider.rooms.acting-agent.v1"
    static let participantRosterMetadataKey = "cider.rooms.participant-roster.v1"
    private let database: CiderDatabase

    init(database: CiderDatabase = .shared) {
        self.database = database
    }

    func createRoom(_ draft: ConversationRoomDraft) throws -> ConversationRoom {
        try database.withTransaction {
            try requireNonempty(draft.title, field: "room title")
            try requireNonempty(draft.kind, field: "room kind")
            guard draft.metadata[Self.agentAssignmentMetadataKey] == nil else {
                throw ConversationRepositoryError.invalidDraft(
                    "Conversation room agent assignment metadata must use the typed assignment field."
                )
            }
            guard draft.metadata[Self.participantRosterMetadataKey] == nil else {
                throw ConversationRepositoryError.invalidDraft(
                    "Conversation room participant roster metadata must use the typed roster field."
                )
            }
            var roomMetadata = draft.metadata
            if let assignment = draft.agentAssignment {
                try assignment.validate()
                guard let encoded = DatabaseHelpers.encodeJSON(assignment) else {
                    throw ConversationRepositoryError.invalidDraft(
                        "Conversation room agent assignment could not be encoded."
                    )
                }
                roomMetadata[Self.agentAssignmentMetadataKey] = encoded
            }
            if let roster = draft.participantRoster {
                try roster.validate()
                guard roster.actingAgent?.profile.id == draft.agentAssignment?.profile.id else {
                    throw ConversationRepositoryError.invalidDraft(
                        "The participant roster acting agent must match the room assignment."
                    )
                }
                guard let encoded = DatabaseHelpers.encodeJSON(roster) else {
                    throw ConversationRepositoryError.invalidDraft(
                        "Conversation room participant roster could not be encoded."
                    )
                }
                roomMetadata[Self.participantRosterMetadataKey] = encoded
            }
            let metadata = DatabaseHelpers.encodeJSON(roomMetadata) ?? "{}"
            let createdAt = DatabaseHelpers.encode(draft.createdAt)
            let updatedAt = DatabaseHelpers.encode(draft.updatedAt ?? draft.createdAt)
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
                .bind(createdAt, at: 7)
                .bind(updatedAt, at: 8)
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

    func agentAssignment(roomID: UUID) throws -> ConversationRoomAgentAssignment? {
        let room = try requiredRoom(id: roomID)
        guard let encoded = room.metadata[Self.agentAssignmentMetadataKey] else { return nil }
        guard let assignment = DatabaseHelpers.decodeJSON(
            ConversationRoomAgentAssignment.self,
            from: encoded
        ) else {
            throw ConversationRepositoryError.integrity(
                "Conversation room contains an invalid acting-agent assignment."
            )
        }
        do {
            try assignment.validate()
        } catch {
            throw ConversationRepositoryError.integrity(
                "Conversation room contains an invalid acting-agent assignment."
            )
        }
        return assignment
    }

    func participantRoster(roomID: UUID) throws -> ConversationRoomParticipantRoster? {
        let room = try requiredRoom(id: roomID)
        guard let encoded = room.metadata[Self.participantRosterMetadataKey] else { return nil }
        guard let roster = DatabaseHelpers.decodeJSON(
            ConversationRoomParticipantRoster.self,
            from: encoded
        ) else {
            throw ConversationRepositoryError.integrity(
                "Conversation room contains an invalid participant roster."
            )
        }
        do {
            try roster.validate()
        } catch {
            throw ConversationRepositoryError.integrity(
                "Conversation room contains an invalid participant roster."
            )
        }
        return roster
    }

    @discardableResult
    func setAgentAssignment(
        roomID: UUID,
        assignment: ConversationRoomAgentAssignment,
        at date: Date
    ) throws -> ConversationRoomAgentAssignment {
        try database.withTransaction {
            let room = try requiredRoom(id: roomID)
            try assignment.validate()
            guard let encoded = DatabaseHelpers.encodeJSON(assignment) else {
                throw ConversationRepositoryError.invalidDraft(
                    "Conversation room agent assignment could not be encoded."
                )
            }
            var metadata = room.metadata
            metadata[Self.agentAssignmentMetadataKey] = encoded
            if let roster = try participantRoster(roomID: roomID) {
                var members = roster.members
                if let selectedIndex = members.firstIndex(where: { $0.profile.id == assignment.profile.id }),
                   let actingIndex = members.firstIndex(where: { $0.role == .actingAgent }) {
                    members[actingIndex].role = .advisor
                    members[selectedIndex].role = .actingAgent
                    members[selectedIndex] = ConversationRoomParticipant(
                        id: members[selectedIndex].id,
                        profile: assignment.profile,
                        role: .actingAgent,
                        addedAt: members[selectedIndex].addedAt
                    )
                } else if let actingIndex = members.firstIndex(where: { $0.role == .actingAgent }) {
                    members[actingIndex] = ConversationRoomParticipant(
                        id: members[actingIndex].id,
                        profile: assignment.profile,
                        role: .actingAgent,
                        addedAt: members[actingIndex].addedAt
                    )
                }
                let synchronized = ConversationRoomParticipantRoster(
                    members: members,
                    updatedAt: date
                )
                try synchronized.validate()
                guard let rosterJSON = DatabaseHelpers.encodeJSON(synchronized) else {
                    throw ConversationRepositoryError.invalidDraft(
                        "Conversation room participant roster could not be encoded."
                    )
                }
                metadata[Self.participantRosterMetadataKey] = rosterJSON
            }
            let statement = try database.prepare("""
                UPDATE conversation_rooms
                SET metadata_json = ?, updated_at = MAX(updated_at, ?)
                WHERE id = ?;
                """)
            statement.bind(DatabaseHelpers.encodeJSON(metadata) ?? "{}", at: 1)
                .bind(DatabaseHelpers.encode(date), at: 2)
                .bind(roomID.uuidString, at: 3)
            try statement.step()
            return try agentAssignment(roomID: roomID) ?? assignment
        }
    }

    static func metadataWithoutAgentAssignment(_ metadata: [String: String]) -> [String: String] {
        metadataWithoutAgentConfiguration(metadata)
    }

    static func metadataWithoutAgentConfiguration(_ metadata: [String: String]) -> [String: String] {
        var result = metadata
        result.removeValue(forKey: agentAssignmentMetadataKey)
        result.removeValue(forKey: participantRosterMetadataKey)
        return result
    }

    @discardableResult
    func setParticipantRoster(
        roomID: UUID,
        roster: ConversationRoomParticipantRoster,
        at date: Date
    ) throws -> ConversationRoomParticipantRoster {
        try database.withTransaction {
            let room = try requiredRoom(id: roomID)
            try roster.validate()
            guard roster.actingAgent?.profile.id == (try agentAssignment(roomID: roomID))?.profile.id else {
                throw ConversationRepositoryError.invalidDraft(
                    "The participant roster acting agent must match the room assignment."
                )
            }
            guard let encoded = DatabaseHelpers.encodeJSON(roster) else {
                throw ConversationRepositoryError.invalidDraft(
                    "Conversation room participant roster could not be encoded."
                )
            }
            var metadata = room.metadata
            metadata[Self.participantRosterMetadataKey] = encoded
            let statement = try database.prepare("""
                UPDATE conversation_rooms
                SET metadata_json = ?, updated_at = MAX(updated_at, ?)
                WHERE id = ?;
                """)
            statement.bind(DatabaseHelpers.encodeJSON(metadata) ?? "{}", at: 1)
                .bind(DatabaseHelpers.encode(date), at: 2)
                .bind(roomID.uuidString, at: 3)
            try statement.step()
            return try participantRoster(roomID: roomID) ?? roster
        }
    }

    /// Returns a bounded lifecycle projection ordered newest first with stable UUID ties.
    func rooms(lifecycle: ConversationRoomLifecycle, limit: Int) throws -> [ConversationRoom] {
        let boundedLimit = try validatedReadLimit(limit)
        let statement = try database.prepare("""
            SELECT id, stable_key, title, kind, lifecycle_state,
                   next_turn_sequence, next_message_sequence, metadata_json,
                   created_at, updated_at, archived_at, trashed_at
            FROM conversation_rooms
            WHERE lifecycle_state = ?
            ORDER BY updated_at DESC, id ASC
            LIMIT ?;
            """)
        statement.bind(lifecycle.rawValue, at: 1).bind(boundedLimit, at: 2)
        var results: [ConversationRoom] = []
        while try statement.step() { results.append(try decodeRoom(statement)) }
        return results
    }

    /// Searches titles and durable transcript text inside one explicit lifecycle.
    func searchRooms(
        query: String,
        lifecycle: ConversationRoomLifecycle,
        limit: Int
    ) throws -> [ConversationRoom] {
        let boundedLimit = try validatedReadLimit(limit)
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return try rooms(lifecycle: lifecycle, limit: boundedLimit)
        }
        guard normalizedQuery.count <= 240 else {
            throw ConversationRepositoryError.invalidDraft("Room search query is too long.")
        }
        let escapedQuery = normalizedQuery
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let pattern = "%\(escapedQuery)%"
        let statement = try database.prepare("""
            SELECT r.id, r.stable_key, r.title, r.kind, r.lifecycle_state,
                   r.next_turn_sequence, r.next_message_sequence, r.metadata_json,
                   r.created_at, r.updated_at, r.archived_at, r.trashed_at
            FROM conversation_rooms r
            WHERE r.lifecycle_state = ?
              AND (
                LOWER(r.title) LIKE LOWER(?) ESCAPE '\\'
                OR EXISTS (
                    SELECT 1 FROM conversation_messages m
                    WHERE m.room_id = r.id
                      AND LOWER(m.content_text) LIKE LOWER(?) ESCAPE '\\'
                )
              )
            ORDER BY r.updated_at DESC, r.id ASC
            LIMIT ?;
            """)
        statement.bind(lifecycle.rawValue, at: 1)
            .bind(pattern, at: 2)
            .bind(pattern, at: 3)
            .bind(boundedLimit, at: 4)
        var results: [ConversationRoom] = []
        while try statement.step() { results.append(try decodeRoom(statement)) }
        return results
    }

    @discardableResult
    func renameRoom(roomID: UUID, title: String, at date: Date) throws -> ConversationRoom {
        try database.withTransaction {
            try requireNonempty(title, field: "room title")
            _ = try requiredRoom(id: roomID)
            let statement = try database.prepare("""
                UPDATE conversation_rooms
                SET title = ?, updated_at = ?
                WHERE id = ?;
                """)
            statement.bind(title, at: 1)
                .bind(DatabaseHelpers.encode(date), at: 2)
                .bind(roomID.uuidString, at: 3)
            try statement.step()
            return try requiredRoom(id: roomID)
        }
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

    func advanceRoomActivity(roomID: UUID, at date: Date) throws {
        try database.withTransaction {
            _ = try requiredRoom(id: roomID)
            let statement = try database.prepare("""
                UPDATE conversation_rooms
                SET updated_at = MAX(updated_at, ?)
                WHERE id = ?;
                """)
            statement.bind(DatabaseHelpers.encode(date), at: 1)
                .bind(roomID.uuidString, at: 2)
            try statement.step()
        }
    }

    func finalizeHistoricalRoomImport(
        roomID: UUID,
        nextTurnSequence: Int64,
        nextMessageSequence: Int64,
        updatedAt: Date
    ) throws {
        try database.withTransaction {
            let statement = try database.prepare("""
                UPDATE conversation_rooms
                SET updated_at = ?
                WHERE id = ? AND next_turn_sequence = ? AND next_message_sequence = ?
                    AND updated_at != ?
                RETURNING id;
                """)
            statement.bind(DatabaseHelpers.encode(updatedAt), at: 1)
                .bind(roomID.uuidString, at: 2)
                .bind(nextTurnSequence, at: 3)
                .bind(nextMessageSequence, at: 4)
                .bind(DatabaseHelpers.encode(updatedAt), at: 5)
            _ = try statement.step()
        }
    }

    /// Applies only mapper-proven mutable fields for a verified historical snapshot.
    /// Callers must validate immutable identity and monotonicity before invoking it.
    func advanceVerifiedHistoricalRoomSnapshot(
        roomID: UUID,
        title: String,
        lifecycleState: ConversationRoomLifecycle,
        metadata: [String: String],
        updatedAt: Date,
        archivedAt: Date?
    ) throws {
        try database.withTransaction {
            _ = try requiredRoom(id: roomID)
            let statement = try database.prepare("""
                UPDATE conversation_rooms
                SET title = ?, lifecycle_state = ?, metadata_json = ?,
                    updated_at = ?, archived_at = ?, trashed_at = NULL
                WHERE id = ?;
                """)
            statement.bind(title, at: 1)
                .bind(lifecycleState.rawValue, at: 2)
                .bind(DatabaseHelpers.encodeJSON(metadata) ?? "{}", at: 3)
                .bind(DatabaseHelpers.encode(updatedAt), at: 4)
                .bind(archivedAt.map(DatabaseHelpers.encode), at: 5)
                .bind(roomID.uuidString, at: 6)
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
            let updatedAt = draft.updatedAt ?? Date()
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

    /// Returns a bounded runtime-binding projection, newest first, for read-only labels.
    func runtimeBindings(roomID: UUID, limit: Int) throws -> [ConversationRuntimeBinding] {
        let boundedLimit = try validatedReadLimit(limit)
        let statement = try database.prepare("""
            SELECT id, room_id, parent_binding_id, runtime_id, transport_id,
                   source_namespace, external_session_id, binding_state,
                   cursor_message_id, cursor_timestamp, metadata_json,
                   created_at, updated_at
            FROM conversation_runtime_bindings
            WHERE room_id = ?
            ORDER BY updated_at DESC, id ASC
            LIMIT ?;
            """)
        statement.bind(roomID.uuidString, at: 1).bind(boundedLimit, at: 2)
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

    /// Attaches provider-neutral execution identity to a nonterminal turn without
    /// changing its stable Cider UUID or sequence. Existing runtime/source identity
    /// may only be filled once or replayed exactly.
    func bindActiveTurnExecution(
        id: UUID,
        runtimeBindingID: UUID?,
        source: ConversationSourceIdentity?,
        metadata: [String: String],
        at date: Date
    ) throws -> ConversationTurn {
        try database.withTransaction {
            let current = try requiredTurn(id: id)
            guard !current.status.isTerminal else {
                throw ConversationRepositoryError.integrity("Terminal conversation turn execution identity is immutable.")
            }
            if let runtimeBindingID {
                let binding = try requiredBinding(id: runtimeBindingID)
                guard binding.roomID == current.roomID else {
                    throw ConversationRepositoryError.integrity("Turn runtime binding belongs to another room.")
                }
            }
            try validateSource(source)
            guard current.runtimeBindingID == nil || current.runtimeBindingID == runtimeBindingID else {
                throw ConversationRepositoryError.integrity("Conversation turn runtime binding is already assigned.")
            }
            guard current.source == nil || current.source == source else {
                throw ConversationRepositoryError.integrity("Conversation turn source identity is already assigned.")
            }
            if let source, let existing = try turn(source: source), existing.id != current.id {
                throw ConversationRepositoryError.integrity("Turn source identity already belongs to another turn.")
            }

            let statement = try database.prepare("""
                UPDATE conversation_turns
                SET runtime_binding_id = COALESCE(runtime_binding_id, ?),
                    source_namespace = COALESCE(source_namespace, ?),
                    source_turn_id = COALESCE(source_turn_id, ?),
                    metadata_json = ?, updated_at = ?
                WHERE id = ?;
                """)
            statement.bind(runtimeBindingID?.uuidString, at: 1)
                .bind(source?.namespace, at: 2)
                .bind(source?.id, at: 3)
                .bind(DatabaseHelpers.encodeJSON(metadata) ?? "{}", at: 4)
                .bind(DatabaseHelpers.encode(date), at: 5)
                .bind(id.uuidString, at: 6)
            try statement.step()
            return try requiredTurn(id: id)
        }
    }

    func turns(roomID: UUID) throws -> [ConversationTurn] {
        let statement = try database.prepare("""
            SELECT id, room_id, sequence, runtime_binding_id,
                   source_namespace, source_turn_id, status,
                   error_code, error_detail, metadata_json,
                   created_at, started_at, completed_at, updated_at
            FROM conversation_turns
            WHERE room_id = ?
            ORDER BY sequence;
            """)
        statement.bind(roomID.uuidString, at: 1)
        var results: [ConversationTurn] = []
        while try statement.step() { results.append(try decodeTurn(statement)) }
        return results
    }

    /// Returns a bounded turn projection in newest-first canonical sequence order.
    func recentTurns(roomID: UUID, limit: Int) throws -> [ConversationTurn] {
        let boundedLimit = try validatedReadLimit(limit)
        let statement = try database.prepare("""
            SELECT id, room_id, sequence, runtime_binding_id,
                   source_namespace, source_turn_id, status,
                   error_code, error_detail, metadata_json,
                   created_at, started_at, completed_at, updated_at
            FROM conversation_turns
            WHERE room_id = ?
            ORDER BY sequence DESC
            LIMIT ?;
            """)
        statement.bind(roomID.uuidString, at: 1).bind(boundedLimit, at: 2)
        var results: [ConversationTurn] = []
        while try statement.step() { results.append(try decodeTurn(statement)) }
        return results
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

    func upsertMessage(
        _ draft: ConversationMessageDraft,
        intent: ConversationMessageWriteIntent
    ) throws -> ConversationMessageUpsertResult {
        try database.withTransaction {
            try requireNonempty(draft.role, field: "message role")
            try validateSource(draft.source)
            _ = try requiredRoom(id: draft.roomID)

            let existing = try messageForUpsert(draft)
            let messageID = existing?.id ?? draft.id
            if let existing { try validateMessageIdentity(existing, against: draft) }
            try validateMessageReferences(draft, messageID: messageID)

            if let existing {
                let proposed = ConversationMessage(
                    id: draft.id,
                    roomID: draft.roomID,
                    turnID: draft.turnID,
                    runtimeBindingID: draft.runtimeBindingID,
                    parentMessageID: draft.parentMessageID,
                    sequence: existing.sequence,
                    role: draft.role,
                    contentText: draft.contentText,
                    status: draft.status,
                    finishReason: draft.finishReason,
                    source: draft.source,
                    sourceCreatedAt: draft.sourceCreatedAt,
                    metadata: draft.metadata,
                    createdAt: draft.createdAt,
                    updatedAt: existing.updatedAt
                )
                if samePersistedMessage(existing, proposed) {
                    return .init(disposition: .unchangedReplay, message: existing)
                }

                guard intent == .liveContinuation else {
                    throw ConversationRepositoryError.integrity("Historical message replay conflicts with persisted values.")
                }
                try validateLiveContinuation(existing, against: draft)

                let updatedAt = Date()
                let statement = try database.prepare("""
                    UPDATE conversation_messages
                    SET content_text = ?, status = ?, finish_reason = ?,
                        metadata_json = ?, updated_at = ?
                    WHERE id = ?;
                    """)
                statement.bind(draft.contentText, at: 1)
                    .bind(draft.status.rawValue, at: 2)
                    .bind(draft.finishReason?.rawValue, at: 3)
                    .bind(DatabaseHelpers.encodeJSON(draft.metadata) ?? "{}", at: 4)
                    .bind(DatabaseHelpers.encode(updatedAt), at: 5)
                    .bind(existing.id.uuidString, at: 6)
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
                messages.append(try upsertMessage(draft, intent: .historicalReplay).message)
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

    /// Selects the newest bounded messages, then returns them in transcript sequence order.
    func recentMessages(roomID: UUID, limit: Int) throws -> [ConversationMessage] {
        let boundedLimit = try validatedReadLimit(limit)
        let statement = try database.prepare("""
            SELECT id, room_id, turn_id, runtime_binding_id, parent_message_id,
                   sequence, role, content_text, status, finish_reason,
                   source_namespace, source_message_id, source_created_at,
                   metadata_json, created_at, updated_at
            FROM conversation_messages
            WHERE room_id = ?
            ORDER BY sequence DESC
            LIMIT ?;
            """)
        statement.bind(roomID.uuidString, at: 1).bind(boundedLimit, at: 2)
        var newestFirst: [ConversationMessage] = []
        while try statement.step() { newestFirst.append(try decodeMessage(statement)) }
        return newestFirst.reversed()
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

    private func validatedReadLimit(_ requestedLimit: Int) throws -> Int {
        guard requestedLimit > 0 else {
            throw ConversationRepositoryError.invalidDraft("Read limit must be positive.")
        }
        return min(requestedLimit, Self.maximumBoundedReadLimit)
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

    private func validateMessageIdentity(
        _ existing: ConversationMessage,
        against draft: ConversationMessageDraft
    ) throws {
        guard existing.roomID == draft.roomID else {
            throw ConversationRepositoryError.integrity("Message identity already belongs to another room.")
        }
        guard existing.id == draft.id else {
            throw ConversationRepositoryError.integrity("Message source identity conflicts with its UUID.")
        }
        guard existing.source == draft.source else {
            throw ConversationRepositoryError.integrity("Message UUID conflicts with its source identity.")
        }
    }

    private func validateLiveContinuation(
        _ existing: ConversationMessage,
        against draft: ConversationMessageDraft
    ) throws {
        guard existing.turnID == draft.turnID,
              existing.runtimeBindingID == draft.runtimeBindingID,
              existing.parentMessageID == draft.parentMessageID,
              existing.role == draft.role,
              existing.sourceCreatedAt == draft.sourceCreatedAt,
              existing.createdAt == draft.createdAt else {
            throw ConversationRepositoryError.integrity("Live message continuation cannot change structural values.")
        }
        guard isValidMessageTransition(from: existing.status, to: draft.status) else {
            throw ConversationRepositoryError.invalidMessageTransition(from: existing.status, to: draft.status)
        }
    }

    private func isValidMessageTransition(
        from: ConversationMessageStatus,
        to: ConversationMessageStatus
    ) -> Bool {
        switch (from, to) {
        case (.pending, .pending), (.pending, .streaming), (.pending, .complete), (.pending, .incomplete),
             (.streaming, .streaming), (.streaming, .complete), (.streaming, .incomplete):
            true
        default:
            false
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
        if let existing = try binding(id: draft.id) {
            guard existing.roomID == draft.roomID else {
                throw ConversationRepositoryError.integrity("Runtime binding id already belongs to another room.")
            }
            return existing
        }
        return nil
    }

    func turn(source: ConversationSourceIdentity) throws -> ConversationTurn? {
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

    private func samePersistedMessage(_ lhs: ConversationMessage, _ rhs: ConversationMessage) -> Bool {
        lhs.id == rhs.id && lhs.roomID == rhs.roomID && lhs.turnID == rhs.turnID &&
        lhs.runtimeBindingID == rhs.runtimeBindingID && lhs.parentMessageID == rhs.parentMessageID &&
        lhs.role == rhs.role && lhs.contentText == rhs.contentText && lhs.status == rhs.status &&
        lhs.finishReason == rhs.finishReason && lhs.source == rhs.source &&
        lhs.sourceCreatedAt == rhs.sourceCreatedAt && lhs.metadata == rhs.metadata &&
        lhs.createdAt == rhs.createdAt
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
