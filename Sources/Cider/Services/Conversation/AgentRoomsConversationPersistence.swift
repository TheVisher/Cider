import Foundation

struct AgentRoomsConversationSnapshot: Sendable {
    let room: ConversationRoom
    let conversationState: HermesConversationState
    let transportMessages: [AIAssistantMessage]
    let presentationMessages: [AgentRoomMessage]
    let latestTurnStatus: ConversationTurnStatus?
    let latestRunID: String?
    let latestErrorCode: String?
    let latestCiderReferences: [HermesCiderReference]
    let latestActivity: [AgentRoomsLiveActivity]
    let latestContextCheckpointFactState: HermesStructuredFactState
    let latestContextCheckpoint: HermesCiderContextCheckpoint?
    let latestApprovalFactState: HermesStructuredFactState
    let latestApprovalRequests: [HermesApprovalRequest]
    let latestAttachmentFactState: HermesStructuredFactState
    let latestAttachments: [HermesCiderAttachment]
    let latestGeneratedArtifactFactState: HermesStructuredFactState
    let latestGeneratedArtifacts: [HermesCiderGeneratedArtifact]
}

struct AgentRoomsConversationAttempt: Equatable, Sendable {
    let roomID: UUID
    let turnID: UUID
    let clientMessageID: String
    let userMessageID: UUID
    let assistantMessageID: UUID
    let createdAt: Date
}

@MainActor
protocol AgentRoomsConversationPersisting: AnyObject {
    func prepareReservedTestChat(id: UUID, at date: Date) throws -> AgentRoomsConversationSnapshot?
    func restoreCanonicalRoom(id: UUID) throws -> AgentRoomsConversationSnapshot?
    func restoreReservedTestChat() throws -> AgentRoomsConversationSnapshot?
    func beginAttempt(
        roomID: UUID,
        roomTitle: String,
        isReservedTestChat: Bool,
        attemptID: UUID,
        clientMessageID: String,
        userMessageID: UUID,
        assistantMessageID: UUID,
        text: String,
        at date: Date
    ) throws -> AgentRoomsConversationAttempt
    func markRunStarted(
        _ attempt: AgentRoomsConversationAttempt,
        runID: String,
        activity: [AgentRoomsLiveActivity],
        at date: Date
    ) throws
    func complete(
        _ attempt: AgentRoomsConversationAttempt,
        completion: HermesRunCompletionEnvelope,
        expectedText: String,
        activity: [AgentRoomsLiveActivity]
    ) throws
    func terminate(
        _ attempt: AgentRoomsConversationAttempt,
        status: ConversationTurnStatus,
        runID: String?,
        partialAssistantText: String?,
        activity: [AgentRoomsLiveActivity],
        at date: Date
    ) throws
}

extension AgentRoomsConversationPersisting {
    func prepareReservedTestChat(id: UUID, at date: Date) throws -> AgentRoomsConversationSnapshot? { nil }
}

enum AgentRoomsConversationPersistenceError: Error, Equatable {
    case ineligibleRoom
    case ineligibleCompletion
    case authorityMismatch
    case corruptHistory
}

/// Provider-neutral durable conversation boundary shared by the reserved Test Chat
/// and ordinary Cider-owned canonical rooms. Runtime sessions are bindings only;
/// the Conversation Core room UUID remains product identity.
@MainActor
final class AgentRoomsConversationPersistence: AgentRoomsConversationPersisting {
    static let nativeRoomAuthority = "cider.rooms.native.v1"

    private static let schemaVersion = "1"
    private static let nativeRoomKind = "chat"
    private static let testRoomKind = "cider-test-chat"
    static let testRoomAuthority = "cider-test-chat.hermes-runs.v1"
    private static let source = "cider-rooms-live-continuation"
    private static let sourceNamespace = "hermes.runs.v1"
    private static let clientSourceNamespace = "cider.rooms.client.v1"
    private static let transportID = "runs-api"
    private static let attemptAuthority = "cider.rooms.hermes-runs.v1"

    private let database: CiderDatabase
    private let repository: ConversationRepository
    private let defaultAgentProfile: ConversationAgentProfile

    init(
        database: CiderDatabase = .shared,
        repository: ConversationRepository? = nil,
        defaultAgentProfile: ConversationAgentProfile = AgentRoomsProductionAgentProfiles.catalog.defaultProfile
    ) {
        self.database = database
        self.repository = repository ?? ConversationRepository(database: database)
        self.defaultAgentProfile = defaultAgentProfile
    }

    func prepareReservedTestChat(id: UUID, at date: Date) throws -> AgentRoomsConversationSnapshot? {
        let room = try requireOrCreateRoom(
            id: id,
            title: AgentRoomsLiveChatModel.roomTitle,
            reserved: true,
            at: date
        )
        return try snapshot(room: room)
    }

    func restoreCanonicalRoom(id: UUID) throws -> AgentRoomsConversationSnapshot? {
        guard let room = try repository.room(id: id) else { return nil }
        try requireRoomAuthority(room, reserved: false)
        try recoverInterruptedTurnIfNeeded(roomID: room.id)
        guard let recoveredRoom = try repository.room(id: room.id) else {
            throw AgentRoomsConversationPersistenceError.corruptHistory
        }
        return try snapshot(room: recoveredRoom)
    }

    func restoreReservedTestChat() throws -> AgentRoomsConversationSnapshot? {
        guard let room = try repository.room(stableKey: AgentRoomsTestChatPersistence.stableRoomKey) else {
            return nil
        }
        try requireRoomAuthority(room, reserved: true)
        try recoverInterruptedTurnIfNeeded(roomID: room.id)
        guard let recoveredRoom = try repository.room(id: room.id) else {
            throw AgentRoomsConversationPersistenceError.corruptHistory
        }
        return try snapshot(room: recoveredRoom)
    }

    /// Compatibility entry point for callers that already hold a verified terminal
    /// Test Chat envelope. Validation happens before the single outer transaction so
    /// an ineligible completion cannot create a room, turn, or message.
    func persistCompletedReservedTestChat(
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
            let attemptID = UUID()
            let attempt = try beginAttempt(
                roomID: expectedConversationID,
                roomTitle: AgentRoomsLiveChatModel.roomTitle,
                isReservedTestChat: true,
                attemptID: attemptID,
                clientMessageID: "cider-room-client:\(UUID().uuidString)",
                userMessageID: UUID(),
                assistantMessageID: UUID(),
                text: expectedText,
                at: terminal.user.timestamp
            )
            try markRunStarted(attempt, runID: terminal.runID, activity: [], at: terminal.user.timestamp)
            try complete(attempt, completion: completion, expectedText: expectedText, activity: [])
        }
    }

    func beginAttempt(
        roomID: UUID,
        roomTitle: String,
        isReservedTestChat: Bool,
        attemptID: UUID,
        clientMessageID: String,
        userMessageID: UUID,
        assistantMessageID: UUID,
        text: String,
        at date: Date
    ) throws -> AgentRoomsConversationAttempt {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { throw AgentRoomsConversationPersistenceError.ineligibleCompletion }

        return try database.withTransaction {
            let room = try requireOrCreateRoom(
                id: roomID,
                title: roomTitle,
                reserved: isReservedTestChat,
                at: date
            )
            let metadata = attemptMetadata(
                attemptID: attemptID,
                clientMessageID: clientMessageID,
                runID: nil,
                activity: []
            )
            let turn = try repository.beginTurn(.init(
                id: attemptID,
                roomID: room.id,
                status: .pending,
                metadata: metadata,
                createdAt: date
            ))
            guard turn.roomID == room.id,
                  turn.status == .pending,
                  turn.metadata == metadata
            else { throw AgentRoomsConversationPersistenceError.authorityMismatch }

            let source = ConversationSourceIdentity(namespace: Self.clientSourceNamespace, id: clientMessageID)
            let existingUser = try repository.messages(roomID: room.id).first { $0.source == source }
            let canonicalUserID: UUID
            if let existingUser {
                guard existingUser.role == "user",
                      existingUser.contentText == normalizedText,
                      existingUser.status == .complete,
                      existingUser.finishReason == .stop
                else { throw AgentRoomsConversationPersistenceError.authorityMismatch }
                canonicalUserID = existingUser.id
            } else {
                let previousMessageID = try repository.messages(roomID: room.id).last?.id
                canonicalUserID = try repository.upsertMessage(.init(
                    id: userMessageID,
                    roomID: room.id,
                    turnID: turn.id,
                    parentMessageID: previousMessageID,
                    role: "user",
                    contentText: normalizedText,
                    status: .complete,
                    finishReason: .stop,
                    source: source,
                    sourceCreatedAt: date,
                    metadata: [
                        "authority": Self.attemptAuthority,
                        "schema_version": Self.schemaVersion,
                        "client_message_id": clientMessageID,
                    ],
                    createdAt: date
                ), intent: .historicalReplay).message.id
            }
            try repository.advanceRoomActivity(roomID: room.id, at: date)
            return AgentRoomsConversationAttempt(
                roomID: room.id,
                turnID: turn.id,
                clientMessageID: clientMessageID,
                userMessageID: canonicalUserID,
                assistantMessageID: assistantMessageID,
                createdAt: date
            )
        }
    }

    func markRunStarted(
        _ attempt: AgentRoomsConversationAttempt,
        runID: String,
        activity: [AgentRoomsLiveActivity],
        at date: Date
    ) throws {
        let runID = try required(runID)
        try database.withTransaction {
            let turn = try repository.bindActiveTurnExecution(
                id: attempt.turnID,
                runtimeBindingID: nil,
                source: .init(namespace: Self.sourceNamespace, id: runID),
                metadata: attemptMetadata(
                    attemptID: attempt.turnID,
                    clientMessageID: attempt.clientMessageID,
                    runID: runID,
                    activity: activity
                ),
                at: date
            )
            if turn.status == .pending {
                _ = try repository.transitionTurn(id: turn.id, to: .running, at: date)
            } else if turn.status != .running && turn.status != .waiting {
                throw AgentRoomsConversationPersistenceError.authorityMismatch
            }
        }
    }

    func complete(
        _ attempt: AgentRoomsConversationAttempt,
        completion: HermesRunCompletionEnvelope,
        expectedText: String,
        activity: [AgentRoomsLiveActivity]
    ) throws {
        let terminal = try validatedTerminal(
            completion,
            expectedText: expectedText,
            expectedConversationID: attempt.roomID
        )
        let structuredFacts = normalizedStructuredFacts(completion)
        try database.withTransaction {
            let room = try requiredRoom(id: attempt.roomID)
            let reserved = room.stableKey == AgentRoomsTestChatPersistence.stableRoomKey
            try requireRoomAuthority(room, reserved: reserved)
            guard completion.finalState.title == room.title else {
                throw AgentRoomsConversationPersistenceError.authorityMismatch
            }
            let binding = try reconcileBindings(
                room: room,
                state: completion.finalState,
                reserved: reserved,
                at: terminal.assistant.timestamp
            )
            let metadata = terminalMetadata(
                attempt: attempt,
                runID: terminal.runID,
                modelIdentity: terminal.modelIdentity,
                references: completion.ciderReferences,
                contextCheckpointFactState: structuredFacts.contextState,
                contextCheckpoint: structuredFacts.context,
                approvalFactState: structuredFacts.approvalState,
                approvalRequests: structuredFacts.approvals,
                attachmentFactState: structuredFacts.attachmentState,
                attachments: structuredFacts.attachments,
                generatedArtifactFactState: structuredFacts.generatedArtifactState,
                generatedArtifacts: structuredFacts.generatedArtifacts,
                activity: activity,
                userSourceID: terminal.userSourceID,
                assistantSourceID: terminal.assistantSourceID
            )
            let turn = try repository.bindActiveTurnExecution(
                id: attempt.turnID,
                runtimeBindingID: binding.id,
                source: .init(namespace: Self.sourceNamespace, id: terminal.runID),
                metadata: metadata,
                at: terminal.assistant.timestamp
            )
            if turn.status == .pending {
                _ = try repository.transitionTurn(id: turn.id, to: .running, at: terminal.assistant.timestamp)
            }

            let existingAssistant = try repository.messages(roomID: room.id).first {
                $0.id == attempt.assistantMessageID
            }
            let assistantCreatedAt = existingAssistant?.createdAt ?? attempt.createdAt
            let assistantSourceCreatedAt = existingAssistant?.sourceCreatedAt ?? terminal.assistant.timestamp
            _ = try repository.upsertMessage(.init(
                id: attempt.assistantMessageID,
                roomID: room.id,
                turnID: attempt.turnID,
                runtimeBindingID: binding.id,
                parentMessageID: attempt.userMessageID,
                role: "assistant",
                contentText: terminal.assistant.content,
                status: .complete,
                finishReason: .stop,
                source: .init(namespace: Self.sourceNamespace, id: terminal.assistantSourceID),
                sourceCreatedAt: assistantSourceCreatedAt,
                metadata: messageMetadata(
                    runID: terminal.runID,
                    sessionID: terminal.sessionID,
                    modelIdentity: terminal.modelIdentity,
                    transportTimestamp: terminal.assistant.timestamp
                ),
                createdAt: assistantCreatedAt
            ), intent: existingAssistant == nil ? .historicalReplay : .liveContinuation)
            _ = try repository.transitionTurn(
                id: attempt.turnID,
                to: .completed,
                at: terminal.assistant.timestamp
            )
            try repository.advanceRoomActivity(roomID: room.id, at: terminal.assistant.timestamp)
        }
    }

    func terminate(
        _ attempt: AgentRoomsConversationAttempt,
        status: ConversationTurnStatus,
        runID: String?,
        partialAssistantText: String?,
        activity: [AgentRoomsLiveActivity],
        at date: Date
    ) throws {
        guard status == .failed || status == .cancelled else {
            throw AgentRoomsConversationPersistenceError.ineligibleCompletion
        }
        try database.withTransaction {
            let turn = try requiredTurn(id: attempt.turnID)
            guard !turn.status.isTerminal else {
                throw AgentRoomsConversationPersistenceError.authorityMismatch
            }
            let normalizedRunID = try runID.map(required)
            let metadata = attemptMetadata(
                attemptID: attempt.turnID,
                clientMessageID: attempt.clientMessageID,
                runID: normalizedRunID,
                activity: activity
            )
            _ = try repository.bindActiveTurnExecution(
                id: attempt.turnID,
                runtimeBindingID: nil,
                source: normalizedRunID.map { .init(namespace: Self.sourceNamespace, id: $0) },
                metadata: metadata,
                at: date
            )

            let partial = partialAssistantText?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let normalizedRunID, let partial, !partial.isEmpty {
                _ = try repository.upsertMessage(.init(
                    id: attempt.assistantMessageID,
                    roomID: attempt.roomID,
                    turnID: attempt.turnID,
                    parentMessageID: attempt.userMessageID,
                    role: "assistant",
                    contentText: partial,
                    status: .incomplete,
                    finishReason: status == .cancelled ? .cancelled : .error,
                    source: .init(namespace: Self.sourceNamespace, id: "hermes-run:\(normalizedRunID):assistant"),
                    sourceCreatedAt: attempt.createdAt,
                    metadata: [
                        "authority": Self.attemptAuthority,
                        "schema_version": Self.schemaVersion,
                        "run_id": normalizedRunID,
                    ],
                    createdAt: attempt.createdAt
                ), intent: .historicalReplay)
            }
            _ = try repository.transitionTurn(
                id: attempt.turnID,
                to: status,
                error: .init(
                    code: normalizedRunID == nil ? "pre_accept_interruption" : "accepted_interruption",
                    detail: nil
                ),
                at: date
            )
            try repository.advanceRoomActivity(roomID: attempt.roomID, at: date)
        }
    }

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
              let runID = try? required(completion.runID),
              let modelIdentity = try? required(completion.modelIdentity),
              completion.terminalSourceEvidence.reportedTerminalRunID == runID,
              completion.ciderReferences.count <= AgentRoomsCiderReceiptProjector.maximumReferenceCount,
              completion.finalMessages.count >= 2,
              completion.finalState.conversationID == expectedConversationID
        else { throw AgentRoomsConversationPersistenceError.ineligibleCompletion }

        let user = completion.finalMessages[completion.finalMessages.count - 2]
        let assistant = completion.finalMessages[completion.finalMessages.count - 1]
        let userSourceID = "hermes-run:\(runID):user"
        let assistantSourceID = "hermes-run:\(runID):assistant"
        guard user.role == .user,
              assistant.role == .assistant,
              user.content == expectedText,
              !(assistant.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
              user.sourceID == userSourceID,
              assistant.sourceID == assistantSourceID,
              user.attachments.isEmpty,
              assistant.attachments.isEmpty,
              let sessionID = try? required(user.sourceSessionID),
              assistant.sourceSessionID == sessionID,
              completion.terminalSourceEvidence.userSourceID == userSourceID,
              completion.terminalSourceEvidence.assistantSourceID == assistantSourceID,
              completion.terminalSourceEvidence.userSourceSessionID == sessionID,
              completion.terminalSourceEvidence.assistantSourceSessionID == sessionID,
              completion.finalState.runtimeID == "hermes",
              completion.finalState.source == Self.source,
              completion.finalState.activeRuntimeSessionID == sessionID,
              completion.finalState.runtimeSessionLineage.last == sessionID,
              Set(completion.finalState.runtimeSessionLineage).count == completion.finalState.runtimeSessionLineage.count,
              completion.finalState.lastSyncedAt == assistant.timestamp,
              completion.finalState.lastSyncedMessageID == assistantSourceID,
              completion.finalState.lastSyncedTimestamp == assistant.timestamp,
              completion.finalState.lastImportedRuntimeSessionID == sessionID
        else { throw AgentRoomsConversationPersistenceError.ineligibleCompletion }
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

    private func requireOrCreateRoom(
        id: UUID,
        title: String,
        reserved: Bool,
        at date: Date
    ) throws -> ConversationRoom {
        if let existing = try repository.room(id: id) {
            try requireRoomAuthority(existing, reserved: reserved)
            guard existing.title == title else { throw AgentRoomsConversationPersistenceError.authorityMismatch }
            return existing
        }
        guard reserved,
              try repository.room(stableKey: AgentRoomsTestChatPersistence.stableRoomKey) == nil,
              title == AgentRoomsLiveChatModel.roomTitle
        else { throw AgentRoomsConversationPersistenceError.ineligibleRoom }
        return try repository.createRoom(.init(
            id: id,
            stableKey: AgentRoomsTestChatPersistence.stableRoomKey,
            title: AgentRoomsLiveChatModel.roomTitle,
            kind: Self.testRoomKind,
            metadata: testRoomMetadata,
            agentAssignment: ConversationRoomAgentAssignment(
                profile: defaultAgentProfile,
                assignedAt: date
            ),
            createdAt: date,
            updatedAt: date
        ))
    }

    private func requireRoomAuthority(_ room: ConversationRoom, reserved: Bool) throws {
        guard room.lifecycleState == .active,
              room.archivedAt == nil,
              room.trashedAt == nil
        else { throw AgentRoomsConversationPersistenceError.ineligibleRoom }
        let baseMetadata = ConversationRepository.metadataWithoutAgentAssignment(room.metadata)
        if room.metadata[ConversationRepository.agentAssignmentMetadataKey] != nil {
            _ = try repository.agentAssignment(roomID: room.id)
        }
        if reserved {
            guard room.stableKey == AgentRoomsTestChatPersistence.stableRoomKey,
                  room.title == AgentRoomsLiveChatModel.roomTitle,
                  room.kind == Self.testRoomKind,
                  baseMetadata == testRoomMetadata
            else { throw AgentRoomsConversationPersistenceError.authorityMismatch }
        } else {
            guard room.stableKey == nil,
                  room.kind == Self.nativeRoomKind,
                  baseMetadata.isEmpty || baseMetadata == nativeRoomMetadata
            else { throw AgentRoomsConversationPersistenceError.ineligibleRoom }
        }
    }

    private var nativeRoomMetadata: [String: String] {
        ["authority": Self.nativeRoomAuthority, "schema_version": Self.schemaVersion]
    }

    private var testRoomMetadata: [String: String] {
        [
            "authority": Self.testRoomAuthority,
            "schema_version": Self.schemaVersion,
            "source": Self.source,
        ]
    }

    private func snapshot(room: ConversationRoom) throws -> AgentRoomsConversationSnapshot {
        let turns = try repository.turns(roomID: room.id)
        let messages = try repository.messages(roomID: room.id)
        let bindings = try repository.bindings(roomID: room.id)
        guard room.nextTurnSequence == Int64(turns.count + 1),
              room.nextMessageSequence == Int64(messages.count + 1),
              messages.allSatisfy({ $0.roomID == room.id }),
              turns.allSatisfy({ $0.roomID == room.id }),
              bindings.allSatisfy({ $0.roomID == room.id })
        else { throw AgentRoomsConversationPersistenceError.corruptHistory }
        try validateSnapshotRows(turns: turns, messages: messages, bindings: bindings)

        let orderedBindings = orderedSessionBindings(bindings)
        let bindingByID = Dictionary(uniqueKeysWithValues: bindings.map { ($0.id, $0) })
        var latestAttemptByClient: [String: ConversationTurn] = [:]
        for turn in turns {
            if let clientID = turn.metadata["client_message_id"] {
                latestAttemptByClient[clientID] = turn
            }
        }
        let presentationMessages = messages.compactMap { message -> AgentRoomMessage? in
            switch message.role.lowercased() {
            case "user":
                let clientID = message.source?.namespace == Self.clientSourceNamespace
                    ? message.source?.id
                    : nil
                let attempt = clientID.flatMap { latestAttemptByClient[$0] }
                let failed = attempt?.status == .failed || attempt?.status == .cancelled
                let accepted = attempt?.source?.namespace == Self.sourceNamespace
                return AgentRoomMessage(
                    id: clientID ?? message.id.uuidString,
                    role: .human,
                    author: "You",
                    body: message.contentText,
                    deliveryState: failed ? .failed : .sent,
                    canRetry: failed && !accepted
                )
            case "assistant":
                return AgentRoomMessage(
                    id: message.id.uuidString,
                    role: .agent,
                    author: "Hermes",
                    body: message.contentText
                )
            default:
                return nil
            }
        }
        let transportMessages = messages.compactMap { message -> AIAssistantMessage? in
            let role: AIAssistantMessage.Role
            switch message.role.lowercased() {
            case "user": role = .user
            case "assistant": role = .assistant
            default: return nil
            }
            return AIAssistantMessage(
                role: role,
                content: message.contentText,
                timestamp: message.sourceCreatedAt ?? message.createdAt,
                sourceID: message.source?.id,
                sourceSessionID: message.runtimeBindingID.flatMap { bindingByID[$0]?.externalSessionID },
                sourceName: "Hermes"
            )
        }

        let sessions = orderedBindings.compactMap(\.externalSessionID)
        let activeSession = orderedBindings.last(where: { $0.state == .active })?.externalSessionID
            ?? sessions.last
            ?? ""
        let lastSyncedMessage = messages.last { message in
            message.role.lowercased() == "assistant"
                && message.status == .complete
                && message.runtimeBindingID.flatMap { bindingByID[$0]?.externalSessionID } != nil
        }
        let lastSession = lastSyncedMessage?.runtimeBindingID.flatMap { bindingByID[$0]?.externalSessionID }
        let latestTurn = turns.last
        let latestRunID = latestTurn?.source?.namespace == Self.sourceNamespace
            ? latestTurn?.source?.id
            : nil
        return AgentRoomsConversationSnapshot(
            room: room,
            conversationState: HermesConversationState(
                conversationID: room.id,
                runtimeID: "hermes",
                activeRuntimeSessionID: activeSession,
                runtimeSessionLineage: sessions,
                title: room.title,
                source: Self.source,
                lastSyncedAt: lastSyncedMessage?.sourceCreatedAt,
                lastSyncedMessageID: lastSyncedMessage?.source?.id,
                lastSyncedTimestamp: lastSyncedMessage?.sourceCreatedAt,
                lastImportedRuntimeSessionID: lastSession
            ),
            transportMessages: transportMessages,
            presentationMessages: presentationMessages,
            latestTurnStatus: latestTurn?.status,
            latestRunID: latestRunID,
            latestErrorCode: latestTurn?.error?.code,
            latestCiderReferences: try decodeReferences(latestTurn?.metadata["cider_references_json"]),
            latestActivity: decodeActivity(latestTurn?.metadata["activity_json"]),
            latestContextCheckpointFactState: try decodeFactState(
                latestTurn?.metadata["context_checkpoint_fact_state"]
            ),
            latestContextCheckpoint: try decodeContextCheckpoint(
                latestTurn?.metadata["context_checkpoint_json"]
            ),
            latestApprovalFactState: try decodeFactState(
                latestTurn?.metadata["approval_fact_state"]
            ),
            latestApprovalRequests: try decodeApprovalRequests(
                latestTurn?.metadata["approval_requests_json"]
            ),
            latestAttachmentFactState: try decodeFactState(
                latestTurn?.metadata["attachment_fact_state"]
            ),
            latestAttachments: try decodeAttachments(
                latestTurn?.metadata["attachments_json"]
            ),
            latestGeneratedArtifactFactState: try decodeFactState(
                latestTurn?.metadata["generated_artifact_fact_state"]
            ),
            latestGeneratedArtifacts: try decodeGeneratedArtifacts(
                latestTurn?.metadata["generated_artifacts_json"]
            )
        )
    }

    /// A process-local active attempt cannot survive app teardown. On the next
    /// activation, close only the newest nonterminal turn using its durable run
    /// acceptance evidence. This makes retry truth durable without guessing a
    /// provider result or inventing an assistant message.
    private func recoverInterruptedTurnIfNeeded(roomID: UUID) throws {
        guard let latest = try repository.turns(roomID: roomID).last,
              latest.status == .pending || latest.status == .running || latest.status == .waiting
        else { return }
        let accepted = latest.source?.namespace == Self.sourceNamespace
            && latest.source?.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let recoveryDate = max(Date(), latest.updatedAt)
        _ = try repository.transitionTurn(
            id: latest.id,
            to: .failed,
            error: .init(
                code: accepted ? "accepted_interruption" : "pre_accept_interruption",
                detail: nil
            ),
            at: recoveryDate
        )
    }

    private func validateSnapshotRows(
        turns: [ConversationTurn],
        messages: [ConversationMessage],
        bindings: [ConversationRuntimeBinding]
    ) throws {
        guard turns.enumerated().allSatisfy({ $0.element.sequence == Int64($0.offset + 1) }),
              messages.enumerated().allSatisfy({ $0.element.sequence == Int64($0.offset + 1) })
        else { throw AgentRoomsConversationPersistenceError.corruptHistory }

        let turnIDs = Set(turns.map(\.id))
        let bindingIDs = Set(bindings.map(\.id))
        let orderedBindings = orderedSessionBindings(bindings)
        guard orderedBindings.count == bindings.count else {
            throw AgentRoomsConversationPersistenceError.corruptHistory
        }
        for (index, binding) in orderedBindings.enumerated() {
            guard binding.runtimeID == "hermes",
                  binding.transportID == Self.transportID,
                  binding.sourceNamespace == Self.sourceNamespace,
                  binding.externalSessionID.flatMap({ try? required($0) }) != nil,
                  binding.parentBindingID == (index == 0 ? nil : orderedBindings[index - 1].id),
                  binding.state == (index == orderedBindings.count - 1 ? .active : .inactive),
                  binding.metadata["lineage_index"] == String(index),
                  binding.cursorMessageID != nil,
                  binding.cursorTimestamp != nil
            else { throw AgentRoomsConversationPersistenceError.corruptHistory }
        }

        for turn in turns {
            guard turn.runtimeBindingID.map(bindingIDs.contains) ?? true,
                  turn.source.map({ $0.namespace == Self.sourceNamespace && !(($0.id).isEmpty) }) ?? true,
                  turn.metadata["authority"] == Self.attemptAuthority
                    || turn.metadata["authority"] == Self.testRoomAuthority
            else { throw AgentRoomsConversationPersistenceError.corruptHistory }
            if turn.status == .completed {
                guard turn.runtimeBindingID != nil, turn.source != nil else {
                    throw AgentRoomsConversationPersistenceError.corruptHistory
                }
            }
            try validateStructuredFactMetadata(turn.metadata)
        }

        for (index, message) in messages.enumerated() {
            guard message.turnID.map(turnIDs.contains) ?? true,
                  message.runtimeBindingID.map(bindingIDs.contains) ?? true,
                  message.parentMessageID == (index == 0 ? nil : messages[index - 1].id),
                  message.sourceCreatedAt != nil,
                  message.metadata["authority"] == Self.attemptAuthority
                    || message.metadata["authority"] == Self.testRoomAuthority,
                  let source = message.source,
                  source.namespace == Self.clientSourceNamespace || source.namespace == Self.sourceNamespace,
                  !source.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !message.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { throw AgentRoomsConversationPersistenceError.corruptHistory }
            switch message.role.lowercased() {
            case "user":
                guard message.status == .complete, message.finishReason == .stop else {
                    throw AgentRoomsConversationPersistenceError.corruptHistory
                }
            case "assistant":
                let isComplete = message.status == .complete && message.finishReason == .stop
                let isPartial = message.status == .incomplete
                    && (message.finishReason == .cancelled || message.finishReason == .error)
                guard isComplete || isPartial else {
                    throw AgentRoomsConversationPersistenceError.corruptHistory
                }
            default:
                throw AgentRoomsConversationPersistenceError.corruptHistory
            }
        }

        if messages.isEmpty {
            guard turns.isEmpty, bindings.isEmpty else {
                throw AgentRoomsConversationPersistenceError.corruptHistory
            }
        }
    }

    private func reconcileBindings(
        room: ConversationRoom,
        state: HermesConversationState,
        reserved: Bool,
        at date: Date
    ) throws -> ConversationRuntimeBinding {
        let allBindings = try repository.bindings(roomID: room.id)
        let existing = orderedSessionBindings(allBindings)
        let existingSessions = existing.compactMap(\.externalSessionID)
        guard !state.runtimeSessionLineage.isEmpty,
              state.runtimeSessionLineage.starts(with: existingSessions)
        else { throw AgentRoomsConversationPersistenceError.authorityMismatch }

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
                    metadata: bindingMetadata(index: index, reserved: reserved),
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
                    metadata: bindingMetadata(index: index, reserved: reserved),
                    createdAt: date.addingTimeInterval(Double(index) / 1_000),
                    updatedAt: date
                )))
            }
        }
        guard let active = result.last else { throw AgentRoomsConversationPersistenceError.corruptHistory }
        return active
    }

    private func orderedSessionBindings(_ bindings: [ConversationRuntimeBinding]) -> [ConversationRuntimeBinding] {
        bindings
            .filter { $0.externalSessionID != nil && $0.sourceNamespace == Self.sourceNamespace }
            .sorted { lhs, rhs in
                let left = Int(lhs.metadata["lineage_index"] ?? "")
                let right = Int(rhs.metadata["lineage_index"] ?? "")
                if let left, let right, left != right { return left < right }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private func bindingMetadata(index: Int, reserved: Bool) -> [String: String] {
        [
            "authority": reserved ? Self.testRoomAuthority : Self.attemptAuthority,
            "schema_version": Self.schemaVersion,
            "lineage_index": String(index),
        ]
    }

    private func attemptMetadata(
        attemptID: UUID,
        clientMessageID: String,
        runID: String?,
        activity: [AgentRoomsLiveActivity]
    ) -> [String: String] {
        var metadata = [
            "authority": Self.attemptAuthority,
            "schema_version": Self.schemaVersion,
            "attempt_id": attemptID.uuidString,
            "client_message_id": clientMessageID,
            "activity_json": encodeActivity(activity),
        ]
        if let runID { metadata["run_id"] = runID }
        return metadata
    }

    private func terminalMetadata(
        attempt: AgentRoomsConversationAttempt,
        runID: String,
        modelIdentity: String,
        references: [HermesCiderReference],
        contextCheckpointFactState: HermesStructuredFactState,
        contextCheckpoint: HermesCiderContextCheckpoint?,
        approvalFactState: HermesStructuredFactState,
        approvalRequests: [HermesApprovalRequest],
        attachmentFactState: HermesStructuredFactState,
        attachments: [HermesCiderAttachment],
        generatedArtifactFactState: HermesStructuredFactState,
        generatedArtifacts: [HermesCiderGeneratedArtifact],
        activity: [AgentRoomsLiveActivity],
        userSourceID: String,
        assistantSourceID: String
    ) -> [String: String] {
        var metadata = attemptMetadata(
            attemptID: attempt.turnID,
            clientMessageID: attempt.clientMessageID,
            runID: runID,
            activity: activity
        )
        metadata["model_identity"] = modelIdentity
        metadata["cider_references_json"] = encodeReferences(references)
        metadata["context_checkpoint_fact_state"] = contextCheckpointFactState.rawValue
        metadata["approval_fact_state"] = approvalFactState.rawValue
        metadata["attachment_fact_state"] = attachmentFactState.rawValue
        metadata["generated_artifact_fact_state"] = generatedArtifactFactState.rawValue
        if let contextCheckpoint {
            metadata["context_checkpoint_json"] = encode(contextCheckpoint)
        }
        if !approvalRequests.isEmpty {
            metadata["approval_requests_json"] = encode(approvalRequests)
        }
        if !attachments.isEmpty {
            metadata["attachments_json"] = encode(attachments)
        }
        if !generatedArtifacts.isEmpty {
            metadata["generated_artifacts_json"] = encode(generatedArtifacts)
        }
        metadata["terminal_user_source_id"] = userSourceID
        metadata["terminal_assistant_source_id"] = assistantSourceID
        return metadata
    }

    private func messageMetadata(
        runID: String,
        sessionID: String,
        modelIdentity: String,
        transportTimestamp: Date
    ) -> [String: String] {
        [
            "authority": Self.attemptAuthority,
            "schema_version": Self.schemaVersion,
            "run_id": runID,
            "session_id": sessionID,
            "model_identity": modelIdentity,
            "transport_timestamp": String(transportTimestamp.timeIntervalSince1970),
        ]
    }

    private struct PersistedActivity: Codable {
        let kind: String
        let detail: String
    }

    private func encodeActivity(_ activity: [AgentRoomsLiveActivity]) -> String {
        let values = activity.map { PersistedActivity(kind: String(describing: $0.kind), detail: $0.detail) }
        guard let data = try? JSONEncoder().encode(values),
              let value = String(data: data, encoding: .utf8)
        else { return "[]" }
        return value
    }

    private func decodeActivity(_ raw: String?) -> [AgentRoomsLiveActivity] {
        guard let raw, let data = raw.data(using: .utf8),
              let values = try? JSONDecoder().decode([PersistedActivity].self, from: data)
        else { return [] }
        return values.compactMap { value in
            let kind: AgentRoomsLiveActivity.Kind
            switch value.kind {
            case "reasoning": kind = .reasoning
            case "toolStarted": kind = .toolStarted
            case "toolCompleted": kind = .toolCompleted
            default: return nil
            }
            return AgentRoomsLiveActivity(id: UUID(), kind: kind, detail: value.detail)
        }
    }

    private func encodeReferences(_ references: [HermesCiderReference]) -> String {
        guard references.count <= AgentRoomsCiderReceiptProjector.maximumReferenceCount,
              let data = try? JSONEncoder().encode(references),
              let value = String(data: data, encoding: .utf8)
        else { return "[]" }
        return value
    }

    private func decodeReferences(_ raw: String?) throws -> [HermesCiderReference] {
        guard let raw else { return [] }
        guard let data = raw.data(using: .utf8),
              let references = try? JSONDecoder().decode([HermesCiderReference].self, from: data),
              references.count <= AgentRoomsCiderReceiptProjector.maximumReferenceCount
        else { throw AgentRoomsConversationPersistenceError.corruptHistory }
        return references
    }

    private struct NormalizedStructuredFacts {
        let contextState: HermesStructuredFactState
        let context: HermesCiderContextCheckpoint?
        let approvalState: HermesStructuredFactState
        let approvals: [HermesApprovalRequest]
        let attachmentState: HermesStructuredFactState
        let attachments: [HermesCiderAttachment]
        let generatedArtifactState: HermesStructuredFactState
        let generatedArtifacts: [HermesCiderGeneratedArtifact]
    }

    private func normalizedStructuredFacts(
        _ completion: HermesRunCompletionEnvelope
    ) -> NormalizedStructuredFacts {
        let contextProjection = AgentRoomsContextCheckpointProjector.project(
            factState: completion.contextCheckpointFactState,
            checkpoint: completion.contextCheckpoint,
            bookmarkThumbnail: { _ in nil }
        )
        let contextValid = contextProjection != nil
        let contextState = contextValid ? completion.contextCheckpointFactState : .rejected
        let context = contextState == .validated ? completion.contextCheckpoint : nil

        let approvalCheckpoint = AgentRoomsApprovalProjector.checkpoint(
            factState: completion.approvalFactState,
            requests: completion.approvalRequests,
            bookmarkThumbnail: { _ in nil }
        )
        let approvalValid = completion.approvalFactState == .notReported
            ? completion.approvalRequests.isEmpty
            : approvalCheckpoint?.state == .available
        let approvalState = approvalValid ? completion.approvalFactState : .rejected
        let approvals = approvalState == .validated ? completion.approvalRequests : []

        let normalizedAttachments = HermesCiderAssetFactContract.normalizedAttachments(
            completion.attachments
        )
        let attachmentValid: Bool
        switch completion.attachmentFactState {
        case .notReported:
            attachmentValid = completion.attachments.isEmpty
        case .rejected:
            attachmentValid = completion.attachments.isEmpty
        case .validated:
            attachmentValid = normalizedAttachments.state == .validated
        }
        let attachmentState = attachmentValid ? completion.attachmentFactState : .rejected
        let attachments = attachmentState == .validated ? normalizedAttachments.values : []

        let normalizedArtifacts = HermesCiderAssetFactContract.normalizedGeneratedArtifacts(
            completion.generatedArtifacts
        )
        let generatedArtifactValid: Bool
        switch completion.generatedArtifactFactState {
        case .notReported:
            generatedArtifactValid = completion.generatedArtifacts.isEmpty
        case .rejected:
            generatedArtifactValid = completion.generatedArtifacts.isEmpty
        case .validated:
            generatedArtifactValid = normalizedArtifacts.state == .validated
        }
        let generatedArtifactState = generatedArtifactValid
            ? completion.generatedArtifactFactState
            : .rejected
        let generatedArtifacts = generatedArtifactState == .validated
            ? normalizedArtifacts.values
            : []
        return NormalizedStructuredFacts(
            contextState: contextState,
            context: context,
            approvalState: approvalState,
            approvals: approvals,
            attachmentState: attachmentState,
            attachments: attachments,
            generatedArtifactState: generatedArtifactState,
            generatedArtifacts: generatedArtifacts
        )
    }

    private func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8)
        else { return "" }
        return encoded
    }

    private func decodeFactState(_ raw: String?) throws -> HermesStructuredFactState {
        guard let raw else { return .notReported }
        guard let state = HermesStructuredFactState(rawValue: raw) else {
            throw AgentRoomsConversationPersistenceError.corruptHistory
        }
        return state
    }

    private func decodeContextCheckpoint(_ raw: String?) throws -> HermesCiderContextCheckpoint? {
        guard let raw else { return nil }
        guard let data = raw.data(using: .utf8),
              let value = try? JSONDecoder().decode(HermesCiderContextCheckpoint.self, from: data)
        else { throw AgentRoomsConversationPersistenceError.corruptHistory }
        return value
    }

    private func decodeApprovalRequests(_ raw: String?) throws -> [HermesApprovalRequest] {
        guard let raw else { return [] }
        guard let data = raw.data(using: .utf8),
              let values = try? JSONDecoder().decode([HermesApprovalRequest].self, from: data),
              values.count <= AgentRoomsApprovalProjector.maximumApprovalCount
        else { throw AgentRoomsConversationPersistenceError.corruptHistory }
        return values
    }

    private func decodeAttachments(_ raw: String?) throws -> [HermesCiderAttachment] {
        guard let raw else { return [] }
        guard let data = raw.data(using: .utf8),
              let values = try? JSONDecoder().decode([HermesCiderAttachment].self, from: data),
              values.count <= AgentRoomsAssetProjector.maximumFactCount
        else { throw AgentRoomsConversationPersistenceError.corruptHistory }
        return values
    }

    private func decodeGeneratedArtifacts(_ raw: String?) throws -> [HermesCiderGeneratedArtifact] {
        guard let raw else { return [] }
        guard let data = raw.data(using: .utf8),
              let values = try? JSONDecoder().decode([HermesCiderGeneratedArtifact].self, from: data),
              values.count <= AgentRoomsAssetProjector.maximumFactCount
        else { throw AgentRoomsConversationPersistenceError.corruptHistory }
        return values
    }

    private func validateStructuredFactMetadata(_ metadata: [String: String]) throws {
        let attachmentState = try decodeFactState(metadata["attachment_fact_state"])
        let attachments = try decodeAttachments(metadata["attachments_json"])
        switch attachmentState {
        case .notReported, .rejected:
            guard attachments.isEmpty else { throw AgentRoomsConversationPersistenceError.corruptHistory }
        case .validated:
            guard HermesCiderAssetFactContract.normalizedAttachments(attachments).state == .validated else {
                throw AgentRoomsConversationPersistenceError.corruptHistory
            }
        }

        let artifactState = try decodeFactState(metadata["generated_artifact_fact_state"])
        let artifacts = try decodeGeneratedArtifacts(metadata["generated_artifacts_json"])
        switch artifactState {
        case .notReported, .rejected:
            guard artifacts.isEmpty else { throw AgentRoomsConversationPersistenceError.corruptHistory }
        case .validated:
            guard HermesCiderAssetFactContract.normalizedGeneratedArtifacts(artifacts).state == .validated else {
                throw AgentRoomsConversationPersistenceError.corruptHistory
            }
        }
    }

    private func requiredRoom(id: UUID) throws -> ConversationRoom {
        guard let room = try repository.room(id: id) else {
            throw AgentRoomsConversationPersistenceError.ineligibleRoom
        }
        return room
    }

    private func requiredTurn(id: UUID) throws -> ConversationTurn {
        guard let turn = try repository.turn(id: id) else {
            throw AgentRoomsConversationPersistenceError.corruptHistory
        }
        return turn
    }

    private func required(_ value: String?) throws -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            throw AgentRoomsConversationPersistenceError.ineligibleCompletion
        }
        return value
    }
}

extension AgentRoomsTestChatPersistence: AgentRoomsConversationPersisting {
    private var sharedConversationPersistence: AgentRoomsConversationPersistence {
        AgentRoomsConversationPersistence(database: database, repository: repository)
    }

    func restoreCanonicalRoom(id: UUID) throws -> AgentRoomsConversationSnapshot? {
        try sharedConversationPersistence.restoreCanonicalRoom(id: id)
    }

    func restoreReservedTestChat() throws -> AgentRoomsConversationSnapshot? {
        try sharedConversationPersistence.restoreReservedTestChat()
    }

    func beginAttempt(
        roomID: UUID,
        roomTitle: String,
        isReservedTestChat: Bool,
        attemptID: UUID,
        clientMessageID: String,
        userMessageID: UUID,
        assistantMessageID: UUID,
        text: String,
        at date: Date
    ) throws -> AgentRoomsConversationAttempt {
        try sharedConversationPersistence.beginAttempt(
            roomID: roomID,
            roomTitle: roomTitle,
            isReservedTestChat: isReservedTestChat,
            attemptID: attemptID,
            clientMessageID: clientMessageID,
            userMessageID: userMessageID,
            assistantMessageID: assistantMessageID,
            text: text,
            at: date
        )
    }

    func markRunStarted(
        _ attempt: AgentRoomsConversationAttempt,
        runID: String,
        activity: [AgentRoomsLiveActivity],
        at date: Date
    ) throws {
        try sharedConversationPersistence.markRunStarted(attempt, runID: runID, activity: activity, at: date)
    }

    func complete(
        _ attempt: AgentRoomsConversationAttempt,
        completion: HermesRunCompletionEnvelope,
        expectedText: String,
        activity: [AgentRoomsLiveActivity]
    ) throws {
        try sharedConversationPersistence.complete(
            attempt,
            completion: completion,
            expectedText: expectedText,
            activity: activity
        )
    }

    func terminate(
        _ attempt: AgentRoomsConversationAttempt,
        status: ConversationTurnStatus,
        runID: String?,
        partialAssistantText: String?,
        activity: [AgentRoomsLiveActivity],
        at date: Date
    ) throws {
        try sharedConversationPersistence.terminate(
            attempt,
            status: status,
            runID: runID,
            partialAssistantText: partialAssistantText,
            activity: activity,
            at: date
        )
    }
}
