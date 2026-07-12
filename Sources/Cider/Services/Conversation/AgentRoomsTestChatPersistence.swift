import Foundation

struct AgentRoomsTestChatSnapshot: Sendable {
    let roomID: UUID
    let conversationState: HermesConversationState
    let messages: [AIAssistantMessage]
    let latestRunID: String
    let latestCiderReferences: [HermesCiderReference]
}

enum AgentRoomsTestChatPersistenceError: Error, Equatable {
    case ineligibleCompletion
    case authorityMismatch
    case corruptHistory
}

/// Canonical persistence adapter for the single Rooms Test Chat.
/// It stores only source-backed, completed Hermes Runs API turns in Conversation Core.
@MainActor
final class AgentRoomsTestChatPersistence {
    static let stableRoomKey = "cider.rooms.test-chat.v1"

    private static let roomKind = "cider-test-chat"
    private static let authority = "cider-test-chat.hermes-runs.v1"
    private static let schemaVersion = "1"
    private static let sourceNamespace = "hermes.runs.v1"
    private static let transportID = "runs-api"
    private static let source = "cider-rooms-live-continuation"

    private let database: CiderDatabase
    private let repository: ConversationRepository

    init(database: CiderDatabase = .shared, repository: ConversationRepository? = nil) {
        self.database = database
        self.repository = repository ?? ConversationRepository(database: database)
    }

    func persist(
        _ completion: HermesRunCompletionEnvelope,
        expectedText: String,
        expectedConversationID: UUID
    ) throws {
        let terminal = try validatedTerminal(
            completion,
            expectedText: expectedText,
            expectedConversationID: expectedConversationID
        )

        try database.withTransaction {
            let room = try requireOrCreateRoom(id: expectedConversationID, at: terminal.assistant.timestamp)
            let bindings = try reconcileBindings(
                room: room,
                state: completion.finalState,
                at: terminal.assistant.timestamp
            )
            guard let activeBinding = bindings.last else {
                throw AgentRoomsTestChatPersistenceError.corruptHistory
            }

            let referencesJSON = try encodeReferences(completion.ciderReferences)
            let turn = try repository.beginTurn(.init(
                roomID: room.id,
                runtimeBindingID: activeBinding.id,
                source: .init(namespace: Self.sourceNamespace, id: terminal.runID),
                status: .completed,
                metadata: turnMetadata(modelIdentity: terminal.modelIdentity, referencesJSON: referencesJSON),
                createdAt: terminal.assistant.timestamp
            ))
            try requirePersistedTurnIdentity(
                turn,
                roomID: room.id,
                bindingID: activeBinding.id,
                runID: terminal.runID,
                modelIdentity: terminal.modelIdentity,
                referencesJSON: referencesJSON
            )

            let existingMessages = try repository.messages(roomID: room.id)
            let previousAssistantID = existingMessages.last?.id
            let user = try repository.upsertMessage(.init(
                roomID: room.id,
                turnID: turn.id,
                runtimeBindingID: activeBinding.id,
                parentMessageID: previousAssistantID,
                role: "user",
                contentText: terminal.user.content,
                status: .complete,
                finishReason: .stop,
                source: .init(namespace: Self.sourceNamespace, id: terminal.userSourceID),
                sourceCreatedAt: terminal.user.timestamp,
                metadata: messageMetadata(
                    runID: terminal.runID,
                    sessionID: terminal.sessionID,
                    modelIdentity: terminal.modelIdentity
                ),
                createdAt: terminal.user.timestamp
            ), intent: .historicalReplay).message
            _ = try repository.upsertMessage(.init(
                roomID: room.id,
                turnID: turn.id,
                runtimeBindingID: activeBinding.id,
                parentMessageID: user.id,
                role: "assistant",
                contentText: terminal.assistant.content,
                status: .complete,
                finishReason: .stop,
                source: .init(namespace: Self.sourceNamespace, id: terminal.assistantSourceID),
                sourceCreatedAt: terminal.assistant.timestamp,
                metadata: messageMetadata(
                    runID: terminal.runID,
                    sessionID: terminal.sessionID,
                    modelIdentity: terminal.modelIdentity
                ),
                createdAt: terminal.assistant.timestamp
            ), intent: .historicalReplay)
            try repository.advanceRoomActivity(roomID: room.id, at: terminal.assistant.timestamp)
        }
    }

    func restore() throws -> AgentRoomsTestChatSnapshot? {
        guard let room = try repository.room(stableKey: Self.stableRoomKey) else { return nil }
        try requireRoomAuthority(room)

        let unorderedBindings = try repository.bindings(roomID: room.id)
        let bindings = try validatedBindings(unorderedBindings, roomID: room.id)
        guard let activeBinding = bindings.last,
              let activeSessionID = activeBinding.externalSessionID
        else { throw AgentRoomsTestChatPersistenceError.corruptHistory }

        let turns = try repository.turns(roomID: room.id)
        let messages = try repository.messages(roomID: room.id)
        guard !turns.isEmpty,
              turns.count * 2 == messages.count,
              room.nextTurnSequence == Int64(turns.count + 1),
              room.nextMessageSequence == Int64(messages.count + 1)
        else { throw AgentRoomsTestChatPersistenceError.corruptHistory }

        var restoredMessages: [AIAssistantMessage] = []
        var previousAssistantID: UUID?
        var latestRunID = ""
        var latestReferences: [HermesCiderReference] = []
        var latestModelIdentity = ""

        for (index, turn) in turns.enumerated() {
            let pair = Array(messages[(index * 2)..<(index * 2 + 2)])
            let user = pair[0]
            let assistant = pair[1]
            let runID = try requiredSourceID(turn.source, namespace: Self.sourceNamespace)
            let modelIdentity = try requireTurn(turn, roomID: room.id, runID: runID, bindings: bindings)
            let references = try decodeReferences(turn.metadata["cider_references_json"])
            guard let bindingID = turn.runtimeBindingID,
                  let binding = bindings.first(where: { $0.id == bindingID }),
                  let sessionID = binding.externalSessionID,
                  user.sequence == Int64(index * 2 + 1),
                  assistant.sequence == Int64(index * 2 + 2),
                  user.turnID == turn.id,
                  assistant.turnID == turn.id,
                  user.runtimeBindingID == bindingID,
                  assistant.runtimeBindingID == bindingID,
                  turn.sequence == Int64(index + 1),
                  user.parentMessageID == previousAssistantID,
                  assistant.parentMessageID == user.id,
                  user.role == "user",
                  assistant.role == "assistant",
                  user.status == .complete,
                  assistant.status == .complete,
                  user.finishReason == .stop,
                  assistant.finishReason == .stop,
                  !user.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !assistant.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  user.sourceCreatedAt != nil,
                  assistant.sourceCreatedAt != nil,
                  user.metadata == messageMetadata(runID: runID, sessionID: sessionID, modelIdentity: modelIdentity),
                  assistant.metadata == messageMetadata(runID: runID, sessionID: sessionID, modelIdentity: modelIdentity)
            else { throw AgentRoomsTestChatPersistenceError.corruptHistory }

            let expectedUserSourceID = "hermes-run:\(runID):user"
            let expectedAssistantSourceID = "hermes-run:\(runID):assistant"
            guard try requiredSourceID(user.source, namespace: Self.sourceNamespace) == expectedUserSourceID,
                  try requiredSourceID(assistant.source, namespace: Self.sourceNamespace) == expectedAssistantSourceID
            else { throw AgentRoomsTestChatPersistenceError.corruptHistory }

            restoredMessages.append(.init(
                role: .user,
                content: user.contentText,
                timestamp: user.sourceCreatedAt!,
                sourceID: expectedUserSourceID,
                sourceSessionID: sessionID,
                sourceName: "Hermes"
            ))
            restoredMessages.append(.init(
                role: .assistant,
                content: assistant.contentText,
                timestamp: assistant.sourceCreatedAt!,
                sourceID: expectedAssistantSourceID,
                sourceSessionID: sessionID,
                sourceName: "Hermes"
            ))
            previousAssistantID = assistant.id
            latestRunID = runID
            latestReferences = references
            latestModelIdentity = modelIdentity
        }

        guard let last = restoredMessages.last,
              last.role == .assistant,
              let lastSourceID = last.sourceID,
              bindings.map(\.externalSessionID).compactMap({ $0 }).last == activeSessionID,
              !latestModelIdentity.isEmpty
        else { throw AgentRoomsTestChatPersistenceError.corruptHistory }
        let lastTimestamp = last.timestamp

        return AgentRoomsTestChatSnapshot(
            roomID: room.id,
            conversationState: .init(
                conversationID: room.id,
                runtimeID: "hermes",
                activeRuntimeSessionID: activeSessionID,
                runtimeSessionLineage: bindings.compactMap(\.externalSessionID),
                title: Self.roomTitle,
                source: Self.source,
                lastSyncedAt: lastTimestamp,
                lastSyncedMessageID: lastSourceID,
                lastSyncedTimestamp: lastTimestamp,
                lastImportedRuntimeSessionID: activeSessionID
            ),
            messages: restoredMessages,
            latestRunID: latestRunID,
            latestCiderReferences: latestReferences
        )
    }

    private static let roomTitle = "Cider Test Chat"

    private struct ValidatedTerminal {
        let runID: String
        let sessionID: String
        let userSourceID: String
        let assistantSourceID: String
        let modelIdentity: String
        let user: AIAssistantMessage
        let assistant: AIAssistantMessage
    }

    private func validatedTerminal(
        _ completion: HermesRunCompletionEnvelope,
        expectedText: String,
        expectedConversationID: UUID
    ) throws -> ValidatedTerminal {
        guard completion.provenance == .hermesRunsAPI,
              completion.terminalStatus == .completed,
              completion.finalSessionSynchronizationComplete,
              completion.observedFacts.runIdentityConsistent,
              !completion.observedFacts.containedAttachmentContentOrEvent,
              !completion.observedFacts.containedPendingContentOrEvent,
              let runID = nonempty(completion.runID),
              let modelIdentity = nonempty(completion.modelIdentity),
              completion.terminalSourceEvidence.reportedTerminalRunID == runID,
              completion.finalMessages.count >= 2,
              completion.finalState.conversationID == expectedConversationID
        else { throw AgentRoomsTestChatPersistenceError.ineligibleCompletion }

        let user = completion.finalMessages[completion.finalMessages.count - 2]
        let assistant = completion.finalMessages[completion.finalMessages.count - 1]
        let userSourceID = "hermes-run:\(runID):user"
        let assistantSourceID = "hermes-run:\(runID):assistant"
        guard user.role == .user,
              assistant.role == .assistant,
              user.content == expectedText,
              nonempty(assistant.content) != nil,
              user.sourceID == userSourceID,
              assistant.sourceID == assistantSourceID,
              user.attachments.isEmpty,
              assistant.attachments.isEmpty,
              let sessionID = nonempty(user.sourceSessionID),
              assistant.sourceSessionID == sessionID,
              completion.terminalSourceEvidence.userSourceID == userSourceID,
              completion.terminalSourceEvidence.assistantSourceID == assistantSourceID,
              completion.terminalSourceEvidence.userSourceSessionID == sessionID,
              completion.terminalSourceEvidence.assistantSourceSessionID == sessionID,
              completion.finalState.runtimeID == "hermes",
              completion.finalState.title == Self.roomTitle,
              completion.finalState.source == Self.source,
              completion.finalState.activeRuntimeSessionID == sessionID,
              completion.finalState.runtimeSessionLineage.last == sessionID,
              Set(completion.finalState.runtimeSessionLineage).count == completion.finalState.runtimeSessionLineage.count,
              completion.finalState.lastSyncedAt == assistant.timestamp,
              completion.finalState.lastSyncedMessageID == assistantSourceID,
              completion.finalState.lastSyncedTimestamp == assistant.timestamp,
              completion.finalState.lastImportedRuntimeSessionID == sessionID
        else { throw AgentRoomsTestChatPersistenceError.ineligibleCompletion }
        return .init(
            runID: runID,
            sessionID: sessionID,
            userSourceID: userSourceID,
            assistantSourceID: assistantSourceID,
            modelIdentity: modelIdentity,
            user: user,
            assistant: assistant
        )
    }

    private func requireOrCreateRoom(id: UUID, at date: Date) throws -> ConversationRoom {
        if let existing = try repository.room(stableKey: Self.stableRoomKey) {
            guard existing.id == id else { throw AgentRoomsTestChatPersistenceError.authorityMismatch }
            try requireRoomAuthority(existing)
            return existing
        }
        if try repository.room(id: id) != nil {
            throw AgentRoomsTestChatPersistenceError.authorityMismatch
        }
        return try repository.createRoom(.init(
            id: id,
            stableKey: Self.stableRoomKey,
            title: Self.roomTitle,
            kind: Self.roomKind,
            metadata: roomMetadata,
            createdAt: date,
            updatedAt: date
        ))
    }

    private var roomMetadata: [String: String] {
        ["authority": Self.authority, "schema_version": Self.schemaVersion, "source": Self.source]
    }

    private func requireRoomAuthority(_ room: ConversationRoom) throws {
        guard room.stableKey == Self.stableRoomKey,
              room.title == Self.roomTitle,
              room.kind == Self.roomKind,
              room.lifecycleState == .active,
              room.metadata == roomMetadata,
              room.archivedAt == nil,
              room.trashedAt == nil
        else { throw AgentRoomsTestChatPersistenceError.authorityMismatch }
    }

    private func reconcileBindings(
        room: ConversationRoom,
        state: HermesConversationState,
        at date: Date
    ) throws -> [ConversationRuntimeBinding] {
        let existing = try validatedBindings(repository.bindings(roomID: room.id), roomID: room.id, allowEmpty: true)
        let existingSessions = existing.compactMap(\.externalSessionID)
        guard state.runtimeSessionLineage.starts(with: existingSessions) else {
            throw AgentRoomsTestChatPersistenceError.authorityMismatch
        }

        var result = existing
        for (index, sessionID) in state.runtimeSessionLineage.enumerated() {
            let parentID = index == 0 ? nil : result[index - 1].id
            if index < result.count {
                let current = result[index]
                result[index] = try repository.upsertRuntimeBinding(.init(
                    id: current.id,
                    roomID: room.id,
                    parentBindingID: parentID,
                    runtimeID: "hermes",
                    transportID: Self.transportID,
                    sourceNamespace: Self.sourceNamespace,
                    externalSessionID: sessionID,
                    state: index == state.runtimeSessionLineage.count - 1 ? .active : .inactive,
                    cursorMessageID: state.lastSyncedMessageID,
                    cursorTimestamp: state.lastSyncedTimestamp,
                    metadata: bindingMetadata(index: index),
                    createdAt: current.createdAt,
                    updatedAt: date
                ))
            } else {
                result.append(try repository.upsertRuntimeBinding(.init(
                    roomID: room.id,
                    parentBindingID: parentID,
                    runtimeID: "hermes",
                    transportID: Self.transportID,
                    sourceNamespace: Self.sourceNamespace,
                    externalSessionID: sessionID,
                    state: index == state.runtimeSessionLineage.count - 1 ? .active : .inactive,
                    cursorMessageID: state.lastSyncedMessageID,
                    cursorTimestamp: state.lastSyncedTimestamp,
                    metadata: bindingMetadata(index: index),
                    createdAt: date,
                    updatedAt: date
                )))
            }
        }
        return try validatedBindings(result, roomID: room.id)
    }

    private func validatedBindings(
        _ bindings: [ConversationRuntimeBinding],
        roomID: UUID,
        allowEmpty: Bool = false
    ) throws -> [ConversationRuntimeBinding] {
        if bindings.isEmpty {
            if allowEmpty { return [] }
            throw AgentRoomsTestChatPersistenceError.corruptHistory
        }
        let indexed = try bindings.map { binding -> (Int, ConversationRuntimeBinding) in
            guard let rawIndex = binding.metadata["lineage_index"], let index = Int(rawIndex) else {
                throw AgentRoomsTestChatPersistenceError.corruptHistory
            }
            return (index, binding)
        }.sorted { $0.0 < $1.0 }
        guard indexed.map(\.0) == Array(0..<indexed.count) else {
            throw AgentRoomsTestChatPersistenceError.corruptHistory
        }
        let ordered = indexed.map(\.1)
        var sessions = Set<String>()
        for (index, binding) in ordered.enumerated() {
            guard binding.roomID == roomID,
                  binding.runtimeID == "hermes",
                  binding.transportID == Self.transportID,
                  binding.sourceNamespace == Self.sourceNamespace,
                  let sessionID = nonempty(binding.externalSessionID),
                  sessions.insert(sessionID).inserted,
                  binding.metadata == bindingMetadata(index: index),
                  binding.parentBindingID == (index == 0 ? nil : ordered[index - 1].id),
                  binding.state == (index == ordered.count - 1 ? .active : .inactive),
                  binding.cursorMessageID != nil,
                  binding.cursorTimestamp != nil
            else { throw AgentRoomsTestChatPersistenceError.corruptHistory }
        }
        return ordered
    }

    private func bindingMetadata(index: Int) -> [String: String] {
        ["authority": Self.authority, "schema_version": Self.schemaVersion, "lineage_index": String(index)]
    }

    private func turnMetadata(modelIdentity: String, referencesJSON: String) -> [String: String] {
        [
            "authority": Self.authority,
            "schema_version": Self.schemaVersion,
            "model_identity": modelIdentity,
            "cider_references_json": referencesJSON,
        ]
    }

    private func messageMetadata(runID: String, sessionID: String, modelIdentity: String) -> [String: String] {
        [
            "authority": Self.authority,
            "schema_version": Self.schemaVersion,
            "run_id": runID,
            "session_id": sessionID,
            "model_identity": modelIdentity,
        ]
    }

    private func requirePersistedTurnIdentity(
        _ turn: ConversationTurn,
        roomID: UUID,
        bindingID: UUID,
        runID: String,
        modelIdentity: String,
        referencesJSON: String
    ) throws {
        guard turn.roomID == roomID,
              turn.runtimeBindingID == bindingID,
              turn.source == .init(namespace: Self.sourceNamespace, id: runID),
              turn.status == .completed,
              turn.error == nil,
              turn.completedAt != nil,
              turn.metadata == turnMetadata(modelIdentity: modelIdentity, referencesJSON: referencesJSON)
        else { throw AgentRoomsTestChatPersistenceError.authorityMismatch }
    }

    private func requireTurn(
        _ turn: ConversationTurn,
        roomID: UUID,
        runID: String,
        bindings: [ConversationRuntimeBinding]
    ) throws -> String {
        guard turn.roomID == roomID,
              turn.sequence > 0,
              turn.status == .completed,
              turn.error == nil,
              turn.completedAt != nil,
              let bindingID = turn.runtimeBindingID,
              bindings.contains(where: { $0.id == bindingID }),
              turn.source == .init(namespace: Self.sourceNamespace, id: runID),
              turn.metadata["authority"] == Self.authority,
              turn.metadata["schema_version"] == Self.schemaVersion,
              let modelIdentity = nonempty(turn.metadata["model_identity"]),
              turn.metadata.count == 4
        else { throw AgentRoomsTestChatPersistenceError.corruptHistory }
        return modelIdentity
    }

    private func requiredSourceID(_ source: ConversationSourceIdentity?, namespace: String) throws -> String {
        guard source?.namespace == namespace, let id = nonempty(source?.id) else {
            throw AgentRoomsTestChatPersistenceError.corruptHistory
        }
        return id
    }

    private func encodeReferences(_ references: [HermesCiderReference]) throws -> String {
        guard references.count <= AgentRoomsCiderReceiptProjector.maximumReferenceCount,
              let value = String(data: try JSONEncoder().encode(references), encoding: .utf8)
        else { throw AgentRoomsTestChatPersistenceError.ineligibleCompletion }
        return value
    }

    private func decodeReferences(_ value: String?) throws -> [HermesCiderReference] {
        guard let value, let data = value.data(using: .utf8),
              let references = try? JSONDecoder().decode([HermesCiderReference].self, from: data),
              references.count <= AgentRoomsCiderReceiptProjector.maximumReferenceCount
        else { throw AgentRoomsTestChatPersistenceError.corruptHistory }
        return references
    }

    private func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
