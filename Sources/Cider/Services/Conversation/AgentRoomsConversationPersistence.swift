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
    let participantAttributionByClientMessageID: [String: ConversationParticipantRunAttribution]
}

struct AgentRoomsConversationAttempt: Equatable, Sendable {
    let roomID: UUID
    let turnID: UUID
    let clientMessageID: String
    let userMessageID: UUID
    let assistantMessageID: UUID
    let createdAt: Date
    let routingContext: ConversationGeneratedRoutingContext
    var participantAttribution: ConversationParticipantRunAttribution? = nil
    var inputAttachments: [HermesCiderAttachment] = []
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
    func beginAttributedAttempt(
        roomID: UUID,
        roomTitle: String,
        isReservedTestChat: Bool,
        attemptID: UUID,
        clientMessageID: String,
        userMessageID: UUID,
        assistantMessageID: UUID,
        text: String,
        attribution: ConversationParticipantRunAttribution,
        at date: Date
    ) throws -> AgentRoomsConversationAttempt
    func beginAttempt(
        roomID: UUID, roomTitle: String, isReservedTestChat: Bool, attemptID: UUID,
        clientMessageID: String, userMessageID: UUID, assistantMessageID: UUID,
        text: String, attachments: [HermesCiderAttachment], at date: Date
    ) throws -> AgentRoomsConversationAttempt
    func beginAttributedAttempt(
        roomID: UUID, roomTitle: String, isReservedTestChat: Bool, attemptID: UUID,
        clientMessageID: String, userMessageID: UUID, assistantMessageID: UUID,
        text: String, attachments: [HermesCiderAttachment],
        attribution: ConversationParticipantRunAttribution, at date: Date
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
    ) throws -> ConversationResultPublicationOutcome
    @discardableResult
    func terminate(
        _ attempt: AgentRoomsConversationAttempt,
        status: ConversationTurnStatus,
        runID: String?,
        partialAssistantText: String?,
        activity: [AgentRoomsLiveActivity],
        at date: Date
    ) throws -> ConversationResultPublicationOutcome
}

extension AgentRoomsConversationPersisting {
    func prepareReservedTestChat(id: UUID, at date: Date) throws -> AgentRoomsConversationSnapshot? { nil }

    func beginAttributedAttempt(
        roomID: UUID,
        roomTitle: String,
        isReservedTestChat: Bool,
        attemptID: UUID,
        clientMessageID: String,
        userMessageID: UUID,
        assistantMessageID: UUID,
        text: String,
        attribution: ConversationParticipantRunAttribution,
        at date: Date
    ) throws -> AgentRoomsConversationAttempt {
        var attempt = try beginAttempt(
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
        attempt.participantAttribution = attribution
        return attempt
    }

    func beginAttempt(
        roomID: UUID, roomTitle: String, isReservedTestChat: Bool, attemptID: UUID,
        clientMessageID: String, userMessageID: UUID, assistantMessageID: UUID,
        text: String, attachments: [HermesCiderAttachment], at date: Date
    ) throws -> AgentRoomsConversationAttempt {
        var attempt = try beginAttempt(roomID: roomID, roomTitle: roomTitle, isReservedTestChat: isReservedTestChat, attemptID: attemptID, clientMessageID: clientMessageID, userMessageID: userMessageID, assistantMessageID: assistantMessageID, text: text, at: date)
        attempt.inputAttachments = attachments
        return attempt
    }

    func beginAttributedAttempt(
        roomID: UUID, roomTitle: String, isReservedTestChat: Bool, attemptID: UUID,
        clientMessageID: String, userMessageID: UUID, assistantMessageID: UUID,
        text: String, attachments: [HermesCiderAttachment],
        attribution: ConversationParticipantRunAttribution, at date: Date
    ) throws -> AgentRoomsConversationAttempt {
        var attempt = try beginAttributedAttempt(roomID: roomID, roomTitle: roomTitle, isReservedTestChat: isReservedTestChat, attemptID: attemptID, clientMessageID: clientMessageID, userMessageID: userMessageID, assistantMessageID: assistantMessageID, text: text, attribution: attribution, at: date)
        attempt.inputAttachments = attachments
        return attempt
    }
}

enum AgentRoomsConversationPersistenceError: Error, Equatable, LocalizedError {
    case ineligibleRoom
    case ineligibleCompletion
    case authorityMismatch
    case corruptHistory
    case writerConflict

    var errorDescription: String? {
        switch self {
        case .writerConflict:
            "Conversation acceptance conflicted with another room update. Nothing was sent."
        case .ineligibleRoom, .ineligibleCompletion, .authorityMismatch, .corruptHistory:
            nil
        }
    }
}

/// Provider-neutral durable conversation boundary shared by the reserved Test Chat
/// and ordinary Cider-owned canonical rooms. Runtime sessions are bindings only;
/// the Conversation Core room UUID remains product identity.
@MainActor
final class AgentRoomsConversationPersistence: AgentRoomsConversationPersisting {
    static let nativeRoomAuthority = "cider.rooms.native.v1"
    static let submissionRoutingMetadataKey = "cider.rooms.submission-routing.v1"
    static let generatedRoutingMetadataKey = "cider.rooms.generated-routing.v1"
    static let publicationStateMetadataKey = "cider.rooms.publication-state.v1"

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
    private let participantProfiles: [ConversationAgentProfile]

    init(
        database: CiderDatabase = .shared,
        repository: ConversationRepository? = nil,
        defaultAgentProfile: ConversationAgentProfile = AgentRoomsProductionAgentProfiles.catalog.defaultProfile,
        participantProfiles: [ConversationAgentProfile] = AgentRoomsProductionAgentProfiles.catalog.profiles
    ) {
        self.database = database
        self.repository = repository ?? ConversationRepository(database: database)
        self.defaultAgentProfile = defaultAgentProfile
        self.participantProfiles = participantProfiles
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
        return try validatedRecoverySnapshot(room: room)
    }

    func restoreReservedTestChat() throws -> AgentRoomsConversationSnapshot? {
        guard let room = try repository.room(stableKey: AgentRoomsTestChatPersistence.stableRoomKey) else {
            return nil
        }
        try requireRoomAuthority(room, reserved: true)
        return try validatedRecoverySnapshot(room: room)
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
        try database.withImmediateTransaction {
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
            _ = try complete(attempt, completion: completion, expectedText: expectedText, activity: [])
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
        try beginAttempt(
            roomID: roomID,
            roomTitle: roomTitle,
            isReservedTestChat: isReservedTestChat,
            attemptID: attemptID,
            clientMessageID: clientMessageID,
            userMessageID: userMessageID,
            assistantMessageID: assistantMessageID,
            text: text,
            attribution: nil,
            at: date
        )
    }

    func beginAttempt(
        roomID: UUID, roomTitle: String, isReservedTestChat: Bool, attemptID: UUID,
        clientMessageID: String, userMessageID: UUID, assistantMessageID: UUID,
        text: String, attachments: [HermesCiderAttachment], at date: Date
    ) throws -> AgentRoomsConversationAttempt {
        try beginAttempt(roomID: roomID, roomTitle: roomTitle, isReservedTestChat: isReservedTestChat, attemptID: attemptID, clientMessageID: clientMessageID, userMessageID: userMessageID, assistantMessageID: assistantMessageID, text: text, attachments: attachments, attribution: nil, at: date)
    }

    func beginAttributedAttempt(
        roomID: UUID,
        roomTitle: String,
        isReservedTestChat: Bool,
        attemptID: UUID,
        clientMessageID: String,
        userMessageID: UUID,
        assistantMessageID: UUID,
        text: String,
        attribution: ConversationParticipantRunAttribution,
        at date: Date
    ) throws -> AgentRoomsConversationAttempt {
        try beginAttempt(
            roomID: roomID,
            roomTitle: roomTitle,
            isReservedTestChat: isReservedTestChat,
            attemptID: attemptID,
            clientMessageID: clientMessageID,
            userMessageID: userMessageID,
            assistantMessageID: assistantMessageID,
            text: text,
            attribution: attribution,
            at: date
        )
    }

    func beginAttributedAttempt(
        roomID: UUID, roomTitle: String, isReservedTestChat: Bool, attemptID: UUID,
        clientMessageID: String, userMessageID: UUID, assistantMessageID: UUID,
        text: String, attachments: [HermesCiderAttachment],
        attribution: ConversationParticipantRunAttribution, at date: Date
    ) throws -> AgentRoomsConversationAttempt {
        try beginAttempt(roomID: roomID, roomTitle: roomTitle, isReservedTestChat: isReservedTestChat, attemptID: attemptID, clientMessageID: clientMessageID, userMessageID: userMessageID, assistantMessageID: assistantMessageID, text: text, attachments: attachments, attribution: attribution, at: date)
    }

    private func beginAttempt(
        roomID: UUID,
        roomTitle: String,
        isReservedTestChat: Bool,
        attemptID: UUID,
        clientMessageID: String,
        userMessageID: UUID,
        assistantMessageID: UUID,
        text: String,
        attachments: [HermesCiderAttachment] = [],
        attribution: ConversationParticipantRunAttribution?,
        at date: Date
    ) throws -> AgentRoomsConversationAttempt {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { throw AgentRoomsConversationPersistenceError.ineligibleCompletion }

        return try translatingWriterConflict(database.withImmediateTransaction {
            let room = try requireOrCreateRoom(
                id: roomID,
                title: roomTitle,
                reserved: isReservedTestChat,
                at: date
            )
            let assignment = try repository.agentAssignment(roomID: room.id)
            let sourceNamespace = attribution == nil
                ? Self.clientSourceNamespace
                : AgentRoomsParticipantService.submissionSourceNamespace
            let source = ConversationSourceIdentity(
                namespace: sourceNamespace,
                id: clientMessageID
            )
            let existingUser = try repository.messages(roomID: room.id).first { $0.source == source }
            let existingSubmissionRouting = try existingUser.flatMap { message in
                try submissionRouting(message)
            }
            let recipient: ConversationRoutingRecipient
            let canonicalAttribution: ConversationParticipantRunAttribution?
            if let existingSubmissionRouting,
               let persistedRecipient = existingSubmissionRouting.recipients.first {
                recipient = persistedRecipient
                if let attribution {
                    canonicalAttribution = ConversationParticipantRunAttribution(
                        invocationID: attribution.invocationID,
                        runID: attribution.runID,
                        participantID: attribution.participantID,
                        profileID: attribution.profileID,
                        displayName: persistedRecipient.displayName,
                        participantRole: attribution.participantRole,
                        selectionSequence: attribution.selectionSequence
                    )
                } else {
                    canonicalAttribution = nil
                }
            } else if let attribution {
                guard let member = try repository.participantRoster(roomID: room.id)?
                    .members.first(where: {
                        $0.id == attribution.participantID
                            && $0.profile.id == attribution.profileID
                    })
                else {
                    throw AgentRoomsConversationPersistenceError.authorityMismatch
                }
                recipient = ConversationRoutingRecipient(profile: member.profile)
                canonicalAttribution = ConversationParticipantRunAttribution(
                    invocationID: attribution.invocationID,
                    runID: attribution.runID,
                    participantID: attribution.participantID,
                    profileID: attribution.profileID,
                    displayName: member.profile.displayName,
                    participantRole: attribution.participantRole,
                    selectionSequence: attribution.selectionSequence
                )
            } else {
                recipient = ConversationRoutingRecipient(
                    profile: assignment?.profile ?? defaultAgentProfile
                )
                canonicalAttribution = nil
            }
            let observedHeadRoutingEpoch = existingSubmissionRouting?.observedHeadRoutingEpoch
                ?? assignment?.headRoutingEpoch
                ?? 0
            let observedRoomMessageSequence = existingSubmissionRouting?.observedRoomMessageSequence
                ?? max(0, room.nextMessageSequence - 1)
            let canonicalUserID = existingUser?.id ?? userMessageID
            let submissionContext = ConversationSubmissionRoutingContext(
                recipients: [recipient],
                observedHeadRoutingEpoch: observedHeadRoutingEpoch,
                observedRoomMessageSequence: observedRoomMessageSequence
            )
            try submissionContext.validate()
            _ = try repository.recordRoutingAcceptance(
                roomID: room.id,
                record: ConversationRoutingAcceptanceRecord(
                    userMessageID: canonicalUserID,
                    sourceNamespace: sourceNamespace,
                    routing: submissionContext
                ),
                at: date
            )
            let generatedRouting = ConversationGeneratedRoutingContext(
                recipient: recipient,
                observedHeadRoutingEpoch: observedHeadRoutingEpoch,
                observedRoomMessageSequence: observedRoomMessageSequence,
                originatingUserMessageID: canonicalUserID
            )
            try generatedRouting.validate()
            let metadata = attemptMetadata(
                attemptID: attemptID,
                clientMessageID: clientMessageID,
                runID: nil,
                activity: [],
                routingContext: generatedRouting,
                attribution: canonicalAttribution,
                attachments: attachments
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
                  try attemptMetadata(
                    turn.metadata,
                    matches: metadata,
                    routingContext: generatedRouting
                  )
            else { throw AgentRoomsConversationPersistenceError.authorityMismatch }

            if let existingUser {
                guard existingUser.role == "user",
                      existingUser.contentText == normalizedText,
                      existingUser.status == .complete,
                      existingUser.finishReason == .stop,
                      try decodeAttachments(existingUser.metadata["attachments_json"]) == attachments,
                      existingSubmissionRouting == nil
                        || existingSubmissionRouting == submissionContext
                else { throw AgentRoomsConversationPersistenceError.authorityMismatch }
            } else {
                let previousMessageID = try repository.continuationParentMessageID(
                    roomID: room.id,
                    assignment: assignment
                )
                _ = try repository.upsertMessage(.init(
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
                    metadata: participantMessageMetadata(
                        base: [
                        "authority": persistenceAuthority(attribution: canonicalAttribution),
                        "schema_version": Self.schemaVersion,
                        "client_message_id": clientMessageID,
                        Self.submissionRoutingMetadataKey: encode(submissionContext),
                        ],
                        invocationID: canonicalAttribution?.invocationID,
                        attribution: nil
                    ).merging(attachmentMetadata(attachments), uniquingKeysWith: { current, _ in current }),
                    createdAt: date
                ), intent: .historicalReplay)
            }
            try repository.advanceRoomActivity(roomID: room.id, at: date)
            return AgentRoomsConversationAttempt(
                roomID: room.id,
                turnID: turn.id,
                clientMessageID: clientMessageID,
                userMessageID: canonicalUserID,
                assistantMessageID: assistantMessageID,
                createdAt: date,
                routingContext: generatedRouting,
                participantAttribution: canonicalAttribution,
                inputAttachments: attachments
            )
        })
    }

    private func translatingWriterConflict<T>(
        _ operation: @autoclosure @MainActor () throws -> T
    ) throws -> T {
        do {
            return try operation()
        } catch let error as CiderDatabaseError where error.isBusyConflict {
            throw AgentRoomsConversationPersistenceError.writerConflict
        }
    }

    func markRunStarted(
        _ attempt: AgentRoomsConversationAttempt,
        runID: String,
        activity: [AgentRoomsLiveActivity],
        at date: Date
    ) throws {
        let runID = try required(runID)
        try database.withImmediateTransaction {
            let turn = try repository.bindActiveTurnExecution(
                id: attempt.turnID,
                runtimeBindingID: nil,
                source: .init(
                    namespace: executionSourceNamespace(attribution: attempt.participantAttribution),
                    id: runID
                ),
                metadata: attemptMetadata(
                    attemptID: attempt.turnID,
                    clientMessageID: attempt.clientMessageID,
                    runID: runID,
                    activity: activity,
                    routingContext: attempt.routingContext,
                    attribution: attempt.participantAttribution,
                    attachments: attempt.inputAttachments
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
    ) throws -> ConversationResultPublicationOutcome {
        let terminal = try validatedTerminal(
            completion,
            expectedText: expectedText,
            expectedConversationID: attempt.roomID,
            allowsAttachmentContent: !attempt.inputAttachments.isEmpty
        )
        let structuredFacts = normalizedStructuredFacts(completion)
        let durableAttachments = mergedAttachments(
            local: attempt.inputAttachments,
            remote: structuredFacts.attachments
        )
        return try database.withImmediateTransaction { () -> ConversationResultPublicationOutcome in
            let room = try requiredRoom(id: attempt.roomID)
            let reserved = room.stableKey == AgentRoomsTestChatPersistence.stableRoomKey
            try requireRoomAuthority(room, reserved: reserved)
            guard completion.finalState.title == room.title else {
                throw AgentRoomsConversationPersistenceError.authorityMismatch
            }
            if let durableOutcome = try canonicalTerminalOutcome(for: attempt) {
                try validateCompletionReplay(
                    outcome: durableOutcome,
                    attempt: attempt,
                    terminal: terminal,
                    completion: completion,
                    activity: activity
                )
                return durableOutcome
            }
            let currentHeadRoutingEpoch = try repository.agentAssignment(
                roomID: room.id
            )?.headRoutingEpoch ?? 0
            if attempt.participantAttribution == nil,
               currentHeadRoutingEpoch != attempt.routingContext.observedHeadRoutingEpoch {
                let metadata = terminalMetadata(
                    attempt: attempt,
                    runID: terminal.runID,
                    modelIdentity: terminal.modelIdentity,
                    references: completion.ciderReferences,
                    contextCheckpointFactState: structuredFacts.contextState,
                    contextCheckpoint: structuredFacts.context,
                    approvalFactState: structuredFacts.approvalState,
                    approvalRequests: structuredFacts.approvals,
                    attachmentFactState: durableAttachments.isEmpty
                        ? structuredFacts.attachmentState : .validated,
                    attachments: durableAttachments,
                    generatedArtifactFactState: structuredFacts.generatedArtifactState,
                    generatedArtifacts: structuredFacts.generatedArtifacts,
                    activity: activity,
                    userSourceID: terminal.userSourceID,
                    assistantSourceID: terminal.assistantSourceID
                ).merging([
                    Self.publicationStateMetadataKey:
                        ConversationPublicationState.heldStale.rawValue,
                    "current_head_routing_epoch": String(currentHeadRoutingEpoch),
                ], uniquingKeysWith: { _, new in new })
                let turn = try repository.bindActiveTurnExecution(
                    id: attempt.turnID,
                    runtimeBindingID: nil,
                    source: .init(
                        namespace: executionSourceNamespace(
                            attribution: attempt.participantAttribution
                        ),
                        id: terminal.runID
                    ),
                    metadata: metadata,
                    at: terminal.assistant.timestamp
                )
                if turn.status == .pending {
                    _ = try repository.transitionTurn(
                        id: turn.id,
                        to: .running,
                        at: terminal.assistant.timestamp
                    )
                }
                _ = try repository.upsertMessage(.init(
                    id: attempt.assistantMessageID,
                    roomID: room.id,
                    turnID: attempt.turnID,
                    parentMessageID: attempt.userMessageID,
                    role: "assistant",
                    contentText: terminal.assistant.content,
                    status: .incomplete,
                    finishReason: .other,
                    source: .init(
                        namespace: executionSourceNamespace(
                            attribution: attempt.participantAttribution
                        ),
                        id: terminal.assistantSourceID
                    ),
                    sourceCreatedAt: terminal.assistant.timestamp,
                    metadata: messageMetadata(
                        runID: terminal.runID,
                        sessionID: terminal.sessionID,
                        modelIdentity: terminal.modelIdentity,
                        transportTimestamp: terminal.assistant.timestamp,
                        routingContext: attempt.routingContext,
                        attribution: attempt.participantAttribution
                    ).merging([
                        Self.publicationStateMetadataKey:
                            ConversationPublicationState.heldStale.rawValue,
                        "current_head_routing_epoch": String(currentHeadRoutingEpoch),
                    ], uniquingKeysWith: { _, new in new }),
                    createdAt: attempt.createdAt
                ), intent: .historicalReplay)
                _ = try repository.transitionTurn(
                    id: attempt.turnID,
                    to: .failed,
                    error: .init(
                        code: "stale_head_routing_epoch",
                        detail: "Generated for routing version \(attempt.routingContext.observedHeadRoutingEpoch); current version is \(currentHeadRoutingEpoch)."
                    ),
                    at: terminal.assistant.timestamp
                )
                try repository.advanceRoomActivity(roomID: room.id, at: terminal.assistant.timestamp)
                return .heldStale
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
                attachmentFactState: durableAttachments.isEmpty ? structuredFacts.attachmentState : .validated,
                attachments: durableAttachments,
                generatedArtifactFactState: structuredFacts.generatedArtifactState,
                generatedArtifacts: structuredFacts.generatedArtifacts,
                activity: activity,
                userSourceID: terminal.userSourceID,
                assistantSourceID: terminal.assistantSourceID
            )
            let turn = try repository.bindActiveTurnExecution(
                id: attempt.turnID,
                runtimeBindingID: binding.id,
                source: .init(
                    namespace: executionSourceNamespace(
                        attribution: attempt.participantAttribution
                    ),
                    id: terminal.runID
                ),
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
                source: .init(
                    namespace: executionSourceNamespace(
                        attribution: attempt.participantAttribution
                    ),
                    id: terminal.assistantSourceID
                ),
                sourceCreatedAt: assistantSourceCreatedAt,
                metadata: messageMetadata(
                    runID: terminal.runID,
                    sessionID: terminal.sessionID,
                    modelIdentity: terminal.modelIdentity,
                    transportTimestamp: terminal.assistant.timestamp,
                    routingContext: attempt.routingContext,
                    attribution: attempt.participantAttribution
                ),
                createdAt: assistantCreatedAt
            ), intent: existingAssistant == nil ? .historicalReplay : .liveContinuation)
            _ = try repository.transitionTurn(
                id: attempt.turnID,
                to: .completed,
                at: terminal.assistant.timestamp
            )
            try repository.advanceRoomActivity(roomID: room.id, at: terminal.assistant.timestamp)
            return .published
        }
    }

    @discardableResult
    func terminate(
        _ attempt: AgentRoomsConversationAttempt,
        status: ConversationTurnStatus,
        runID: String?,
        partialAssistantText: String?,
        activity: [AgentRoomsLiveActivity],
        at date: Date
    ) throws -> ConversationResultPublicationOutcome {
        guard status == .failed || status == .cancelled else {
            throw AgentRoomsConversationPersistenceError.ineligibleCompletion
        }
        return try database.withImmediateTransaction {
            let turn = try requiredTurn(id: attempt.turnID)
            if turn.status.isTerminal {
                let outcome = try canonicalTerminalOutcome(for: attempt)
                    ?? { throw AgentRoomsConversationPersistenceError.authorityMismatch }()
                try validateTerminationReplay(
                    outcome: outcome,
                    attempt: attempt,
                    status: status,
                    runID: runID,
                    partialAssistantText: partialAssistantText,
                    activity: activity
                )
                return outcome
            }
            let normalizedRunID = try runID.map(required)
            let currentHeadRoutingEpoch = try repository.agentAssignment(
                roomID: attempt.roomID
            )?.headRoutingEpoch ?? 0
            let isStale = attempt.participantAttribution == nil
                && currentHeadRoutingEpoch != attempt.routingContext.observedHeadRoutingEpoch
            var metadata = attemptMetadata(
                attemptID: attempt.turnID,
                clientMessageID: attempt.clientMessageID,
                runID: normalizedRunID,
                activity: activity,
                routingContext: attempt.routingContext,
                attribution: attempt.participantAttribution,
                attachments: attempt.inputAttachments
            )
            if isStale {
                metadata[Self.publicationStateMetadataKey] =
                    ConversationPublicationState.heldStale.rawValue
                metadata["current_head_routing_epoch"] = String(currentHeadRoutingEpoch)
            }
            _ = try repository.bindActiveTurnExecution(
                id: attempt.turnID,
                runtimeBindingID: nil,
                source: normalizedRunID.map {
                    .init(
                        namespace: executionSourceNamespace(
                            attribution: attempt.participantAttribution
                        ),
                        id: $0
                    )
                },
                metadata: metadata,
                at: date
            )

            let partial = partialAssistantText?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let normalizedRunID, let partial, !partial.isEmpty {
                var messageMetadata = participantMessageMetadata(
                    base: [
                    "authority": persistenceAuthority(
                        attribution: attempt.participantAttribution
                    ),
                    "schema_version": Self.schemaVersion,
                    "run_id": normalizedRunID,
                    Self.generatedRoutingMetadataKey: encode(attempt.routingContext),
                    ],
                    invocationID: attempt.participantAttribution?.invocationID,
                    attribution: attempt.participantAttribution
                )
                if isStale {
                    messageMetadata[Self.publicationStateMetadataKey] =
                        ConversationPublicationState.heldStale.rawValue
                    messageMetadata["current_head_routing_epoch"] = String(currentHeadRoutingEpoch)
                }
                _ = try repository.upsertMessage(.init(
                    id: attempt.assistantMessageID,
                    roomID: attempt.roomID,
                    turnID: attempt.turnID,
                    parentMessageID: attempt.userMessageID,
                    role: "assistant",
                    contentText: partial,
                    status: .incomplete,
                    finishReason: isStale ? .other : (status == .cancelled ? .cancelled : .error),
                    source: .init(
                        namespace: executionSourceNamespace(
                            attribution: attempt.participantAttribution
                        ),
                        id: "hermes-run:\(normalizedRunID):assistant"
                    ),
                    sourceCreatedAt: attempt.createdAt,
                    metadata: messageMetadata,
                    createdAt: attempt.createdAt
                ), intent: .historicalReplay)
            }
            _ = try repository.transitionTurn(
                id: attempt.turnID,
                to: status,
                error: .init(
                    code: isStale
                        ? "stale_head_routing_epoch"
                        : (normalizedRunID == nil
                            ? "pre_accept_interruption" : "accepted_interruption"),
                    detail: nil
                ),
                at: date
            )
            try repository.advanceRoomActivity(roomID: attempt.roomID, at: date)
            return isStale ? .heldStale : .terminated
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

    /// Version 1 binds the complete durable meaning of a completion request.
    /// Set-like structured fact families are normalized before construction;
    /// transcript, activity, and runtime-session lineage order remains exact.
    private struct CompletionReplayEnvelope: Equatable {
        static let version = 1

        let version: Int
        let roomID: UUID
        let turnID: UUID
        let turnSequence: Int64
        let clientMessageID: String
        let userMessageID: UUID
        let userMessageSequence: Int64
        let assistantMessageID: UUID
        let assistantMessageSequence: Int64
        let routingContext: ConversationGeneratedRoutingContext
        let participantAttribution: ConversationParticipantRunAttribution?
        let executionSourceNamespace: String
        let runID: String
        let modelIdentity: String
        let sessionID: String
        let userSourceID: String
        let assistantSourceID: String
        let userContent: String
        let assistantContent: String
        let assistantTransportTimestamp: TimeInterval
        let runtimeSessionLineage: [String]
        let activity: [ReplayActivity]
        let ciderReferences: [HermesCiderReference]
        let contextCheckpointFactState: HermesStructuredFactState
        let contextCheckpoint: HermesCiderContextCheckpoint?
        let approvalFactState: HermesStructuredFactState
        let approvalRequests: [HermesApprovalRequest]
        let attachmentFactState: HermesStructuredFactState
        let attachments: [HermesCiderAttachment]
        let generatedArtifactFactState: HermesStructuredFactState
        let generatedArtifacts: [HermesCiderGeneratedArtifact]
    }

    private struct ReplayActivity: Codable, Equatable {
        let kind: String
        let detail: String
    }

    private func canonicalTerminalOutcome(
        for attempt: AgentRoomsConversationAttempt
    ) throws -> ConversationResultPublicationOutcome? {
        let turn = try requiredTurn(id: attempt.turnID)
        guard turn.roomID == attempt.roomID,
              turn.metadata["attempt_id"] == attempt.turnID.uuidString,
              turn.metadata["client_message_id"] == attempt.clientMessageID,
              try generatedRouting(turn.metadata) == attempt.routingContext
        else {
            throw AgentRoomsConversationPersistenceError.authorityMismatch
        }
        guard turn.status.isTerminal else { return nil }

        let messages = try repository.messages(roomID: attempt.roomID)
        guard let user = messages.first(where: { $0.id == attempt.userMessageID }),
              user.role.lowercased() == "user",
              user.source == .init(
                  namespace: attempt.participantAttribution == nil
                    ? Self.clientSourceNamespace
                    : AgentRoomsParticipantService.submissionSourceNamespace,
                  id: attempt.clientMessageID
              ),
              let submission = try submissionRouting(user),
              submission.observedHeadRoutingEpoch
                == attempt.routingContext.observedHeadRoutingEpoch,
              submission.observedRoomMessageSequence
                == attempt.routingContext.observedRoomMessageSequence,
              submission.recipients.contains(attempt.routingContext.recipient),
              attempt.routingContext.originatingUserMessageID == user.id
        else {
            throw AgentRoomsConversationPersistenceError.authorityMismatch
        }

        let assistant = messages.first(where: { $0.turnID == attempt.turnID && $0.role == "assistant" })
        if let assistant {
            guard assistant.id == attempt.assistantMessageID,
                  assistant.parentMessageID == user.id,
                  try generatedRouting(assistant.metadata) == attempt.routingContext
            else {
                throw AgentRoomsConversationPersistenceError.authorityMismatch
            }
        }
        let publication = turn.metadata[Self.publicationStateMetadataKey]
        switch turn.status {
        case .completed:
            guard turn.error == nil,
                  publication == nil,
                  let assistant,
                  assistant.status == .complete,
                  assistant.finishReason == .stop,
                  assistant.metadata[Self.publicationStateMetadataKey] == nil
            else {
                throw AgentRoomsConversationPersistenceError.authorityMismatch
            }
            return .published
        case .failed, .cancelled:
            if turn.error?.code == "stale_head_routing_epoch" {
                guard publication == ConversationPublicationState.heldStale.rawValue,
                      assistant.map({
                          $0.status == .incomplete
                              && $0.finishReason == .other
                              && $0.metadata[Self.publicationStateMetadataKey]
                                  == ConversationPublicationState.heldStale.rawValue
                      }) ?? true
                else {
                    throw AgentRoomsConversationPersistenceError.authorityMismatch
                }
                return .heldStale
            }
            guard publication == nil,
                  assistant.map({
                      $0.status == .incomplete
                          && ($0.finishReason == .cancelled || $0.finishReason == .error)
                          && $0.metadata[Self.publicationStateMetadataKey] == nil
                  }) ?? true
            else {
                throw AgentRoomsConversationPersistenceError.authorityMismatch
            }
            return .terminated
        case .unknown:
            throw AgentRoomsConversationPersistenceError.authorityMismatch
        case .pending, .running, .waiting:
            return nil
        }
    }

    private func validateCompletionReplay(
        outcome: ConversationResultPublicationOutcome,
        attempt: AgentRoomsConversationAttempt,
        terminal: ValidatedTerminal,
        completion: HermesRunCompletionEnvelope,
        activity: [AgentRoomsLiveActivity]
    ) throws {
        let turn = try requiredTurn(id: attempt.turnID)
        guard turn.metadata["terminal_assistant_source_id"] != nil else {
            throw AgentRoomsConversationPersistenceError.authorityMismatch
        }
        let structuredFacts = normalizedStructuredFacts(completion)
        let durableAttachments = mergedAttachments(
            local: attempt.inputAttachments,
            remote: structuredFacts.attachments
        )
        let requested = try completionReplayEnvelope(
            outcome: outcome,
            attempt: attempt,
            terminal: terminal,
            completion: completion,
            structuredFacts: structuredFacts,
            durableAttachments: durableAttachments,
            activity: activity
        )
        let canonical = try canonicalCompletionReplayEnvelope(
            outcome: outcome,
            attempt: attempt,
            turn: turn
        )
        guard requested == canonical else {
            throw AgentRoomsConversationPersistenceError.authorityMismatch
        }
    }

    private func validateTerminationReplay(
        outcome: ConversationResultPublicationOutcome,
        attempt: AgentRoomsConversationAttempt,
        status: ConversationTurnStatus,
        runID: String?,
        partialAssistantText: String?,
        activity: [AgentRoomsLiveActivity]
    ) throws {
        let turn = try requiredTurn(id: attempt.turnID)
        let normalizedRunID = try runID.map(required)
        let canonicalActivity = try replayActivity(turn.metadata)
        if turn.metadata["terminal_assistant_source_id"] != nil {
            guard let canonicalRunID = turn.source?.id,
                  turn.source?.namespace == executionSourceNamespace(
                      attribution: attempt.participantAttribution
                  ),
                  normalizedRunID == canonicalRunID,
                  status == .cancelled,
                  replayActivity(activity) == canonicalActivity,
                  let assistant = try repository.messages(roomID: attempt.roomID).first(where: {
                      $0.turnID == attempt.turnID && $0.role == "assistant"
                  })
            else {
                throw AgentRoomsConversationPersistenceError.authorityMismatch
            }
            let partial = partialAssistantText?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard partial == assistant.contentText else {
                throw AgentRoomsConversationPersistenceError.authorityMismatch
            }
            return
        }
        guard turn.status == status else {
            throw AgentRoomsConversationPersistenceError.authorityMismatch
        }
        let expectedSource = normalizedRunID.map {
            ConversationSourceIdentity(
                namespace: executionSourceNamespace(
                    attribution: attempt.participantAttribution
                ),
                id: $0
            )
        }
        guard turn.source == expectedSource else {
            throw AgentRoomsConversationPersistenceError.authorityMismatch
        }
        let partial = partialAssistantText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let assistant = try repository.messages(roomID: attempt.roomID).first(where: {
            $0.turnID == attempt.turnID && $0.role == "assistant"
        })
        guard (partial?.isEmpty == false) == (assistant != nil),
              assistant.map({ $0.contentText == partial }) ?? true,
              replayActivity(activity) == canonicalActivity
        else {
            throw AgentRoomsConversationPersistenceError.authorityMismatch
        }
    }

    private func completionReplayEnvelope(
        outcome: ConversationResultPublicationOutcome,
        attempt: AgentRoomsConversationAttempt,
        terminal: ValidatedTerminal,
        completion: HermesRunCompletionEnvelope,
        structuredFacts: NormalizedStructuredFacts,
        durableAttachments: [HermesCiderAttachment],
        activity: [AgentRoomsLiveActivity]
    ) throws -> CompletionReplayEnvelope {
        let turn = try requiredTurn(id: attempt.turnID)
        let messages = try repository.messages(roomID: attempt.roomID)
        guard let user = messages.first(where: { $0.id == attempt.userMessageID }),
              let assistant = messages.first(where: {
                  $0.id == attempt.assistantMessageID
              })
        else {
            throw AgentRoomsConversationPersistenceError.authorityMismatch
        }
        return CompletionReplayEnvelope(
            version: CompletionReplayEnvelope.version,
            roomID: attempt.roomID,
            turnID: attempt.turnID,
            turnSequence: turn.sequence,
            clientMessageID: attempt.clientMessageID,
            userMessageID: attempt.userMessageID,
            userMessageSequence: user.sequence,
            assistantMessageID: attempt.assistantMessageID,
            assistantMessageSequence: assistant.sequence,
            routingContext: attempt.routingContext,
            participantAttribution: attempt.participantAttribution,
            executionSourceNamespace: executionSourceNamespace(
                attribution: attempt.participantAttribution
            ),
            runID: terminal.runID,
            modelIdentity: terminal.modelIdentity,
            sessionID: terminal.sessionID,
            userSourceID: terminal.userSourceID,
            assistantSourceID: terminal.assistantSourceID,
            userContent: terminal.user.content,
            assistantContent: terminal.assistant.content,
            assistantTransportTimestamp:
                terminal.assistant.timestamp.timeIntervalSince1970,
            runtimeSessionLineage: outcome == .published
                ? completion.finalState.runtimeSessionLineage : [],
            activity: replayActivity(activity),
            ciderReferences: normalizedReferences(completion.ciderReferences),
            contextCheckpointFactState: structuredFacts.contextState,
            contextCheckpoint: normalizedContextCheckpoint(
                structuredFacts.context
            ),
            approvalFactState: structuredFacts.approvalState,
            approvalRequests: normalizedApprovalRequests(
                structuredFacts.approvals
            ),
            attachmentFactState: durableAttachments.isEmpty
                ? structuredFacts.attachmentState : .validated,
            attachments: normalizedAttachments(durableAttachments),
            generatedArtifactFactState:
                structuredFacts.generatedArtifactState,
            generatedArtifacts: normalizedGeneratedArtifacts(
                structuredFacts.generatedArtifacts
            )
        )
    }

    private func canonicalCompletionReplayEnvelope(
        outcome: ConversationResultPublicationOutcome,
        attempt: AgentRoomsConversationAttempt,
        turn: ConversationTurn
    ) throws -> CompletionReplayEnvelope {
        let messages = try repository.messages(roomID: attempt.roomID)
        guard let user = messages.first(where: { $0.id == attempt.userMessageID }),
              let assistant = messages.first(where: {
                  $0.id == attempt.assistantMessageID
              }),
              let runID = turn.source?.id,
              let executionSourceNamespace = turn.source?.namespace,
              let modelIdentity = turn.metadata["model_identity"],
              let sessionID = assistant.metadata["session_id"],
              let userSourceID = turn.metadata["terminal_user_source_id"],
              let assistantSourceID =
                turn.metadata["terminal_assistant_source_id"],
              assistant.source == .init(
                  namespace: executionSourceNamespace,
                  id: assistantSourceID
              ),
              assistant.metadata["run_id"] == runID,
              assistant.metadata["model_identity"] == modelIdentity,
              let rawTimestamp = assistant.metadata["transport_timestamp"],
              let assistantTransportTimestamp = TimeInterval(rawTimestamp),
              let routingContext = try generatedRouting(assistant.metadata)
        else {
            throw AgentRoomsConversationPersistenceError.authorityMismatch
        }
        let participantAttribution: ConversationParticipantRunAttribution?
        if let raw = turn.metadata[
            AgentRoomsParticipantService.runAttributionMetadataKey
        ] {
            guard let decoded = DatabaseHelpers.decodeJSON(
                ConversationParticipantRunAttribution.self,
                from: raw
            ) else {
                throw AgentRoomsConversationPersistenceError.authorityMismatch
            }
            participantAttribution = decoded
        } else {
            participantAttribution = nil
        }
        return CompletionReplayEnvelope(
            version: CompletionReplayEnvelope.version,
            roomID: turn.roomID,
            turnID: turn.id,
            turnSequence: turn.sequence,
            clientMessageID: turn.metadata["client_message_id"] ?? "",
            userMessageID: user.id,
            userMessageSequence: user.sequence,
            assistantMessageID: assistant.id,
            assistantMessageSequence: assistant.sequence,
            routingContext: routingContext,
            participantAttribution: participantAttribution,
            executionSourceNamespace: executionSourceNamespace,
            runID: runID,
            modelIdentity: modelIdentity,
            sessionID: sessionID,
            userSourceID: userSourceID,
            assistantSourceID: assistantSourceID,
            userContent: user.contentText,
            assistantContent: assistant.contentText,
            assistantTransportTimestamp: assistantTransportTimestamp,
            runtimeSessionLineage: try terminalRuntimeSessionLineage(
                outcome: outcome,
                turn: turn
            ),
            activity: try replayActivity(turn.metadata),
            ciderReferences: normalizedReferences(
                try decodeReferences(turn.metadata["cider_references_json"])
            ),
            contextCheckpointFactState: try decodeFactState(
                turn.metadata["context_checkpoint_fact_state"]
            ),
            contextCheckpoint: normalizedContextCheckpoint(
                try decodeContextCheckpoint(
                    turn.metadata["context_checkpoint_json"]
                )
            ),
            approvalFactState: try decodeFactState(
                turn.metadata["approval_fact_state"]
            ),
            approvalRequests: normalizedApprovalRequests(
                try decodeApprovalRequests(
                    turn.metadata["approval_requests_json"]
                )
            ),
            attachmentFactState: try decodeFactState(
                turn.metadata["attachment_fact_state"]
            ),
            attachments: normalizedAttachments(
                try decodeAttachments(turn.metadata["attachments_json"])
            ),
            generatedArtifactFactState: try decodeFactState(
                turn.metadata["generated_artifact_fact_state"]
            ),
            generatedArtifacts: normalizedGeneratedArtifacts(
                try decodeGeneratedArtifacts(
                    turn.metadata["generated_artifacts_json"]
                )
            )
        )
    }

    private func terminalRuntimeSessionLineage(
        outcome: ConversationResultPublicationOutcome,
        turn: ConversationTurn
    ) throws -> [String] {
        guard outcome == .published else { return [] }
        guard let terminalBindingID = turn.runtimeBindingID else {
            throw AgentRoomsConversationPersistenceError.authorityMismatch
        }
        let bindings = orderedSessionBindings(
            try repository.bindings(roomID: turn.roomID)
        )
        guard let terminalIndex = bindings.firstIndex(where: {
            $0.id == terminalBindingID
        }) else {
            throw AgentRoomsConversationPersistenceError.authorityMismatch
        }
        return bindings[...terminalIndex].compactMap(\.externalSessionID)
    }

    private func replayActivity(
        _ metadata: [String: String]
    ) throws -> [ReplayActivity] {
        guard let raw = metadata["activity_json"],
              let data = raw.data(using: .utf8),
              let values = try? JSONDecoder().decode(
                  [PersistedActivity].self,
                  from: data
              )
        else {
            throw AgentRoomsConversationPersistenceError.authorityMismatch
        }
        return values.map { ReplayActivity(kind: $0.kind, detail: $0.detail) }
    }

    private func normalizedReferences(
        _ values: [HermesCiderReference]
    ) -> [HermesCiderReference] {
        normalizedSet(values, key: referenceSortKey)
    }

    private func normalizedContextCheckpoint(
        _ value: HermesCiderContextCheckpoint?
    ) -> HermesCiderContextCheckpoint? {
        value.map {
            HermesCiderContextCheckpoint(
                id: $0.id,
                selected: normalizedReferences($0.selected),
                citations: normalizedReferences($0.citations),
                omissionReason: $0.omissionReason,
                source: $0.source,
                sourceRef: $0.sourceRef
            )
        }
    }

    private func normalizedApprovalRequests(
        _ values: [HermesApprovalRequest]
    ) -> [HermesApprovalRequest] {
        normalizedSet(values) {
            framed([
                $0.id, $0.action, $0.target.map(referenceSortKey) ?? "",
                $0.risk, $0.scope, $0.status, $0.source, $0.sourceRef,
            ])
        }
    }

    private func normalizedAttachments(
        _ values: [HermesCiderAttachment]
    ) -> [HermesCiderAttachment] {
        let normalized = HermesCiderAssetFactContract.normalizedAttachments(
            values
        )
        return normalized.state == .validated ? normalized.values : []
    }

    private func normalizedGeneratedArtifacts(
        _ values: [HermesCiderGeneratedArtifact]
    ) -> [HermesCiderGeneratedArtifact] {
        let normalized =
            HermesCiderAssetFactContract.normalizedGeneratedArtifacts(values)
        return normalized.state == .validated ? normalized.values : []
    }

    private func normalizedSet<Value: Equatable>(
        _ values: [Value],
        key: (Value) -> String
    ) -> [Value] {
        values.sorted {
            let lhs = key($0)
            let rhs = key($1)
            return lhs == rhs ? false : lhs < rhs
        }.reduce(into: []) { result, value in
            if !result.contains(value) {
                result.append(value)
            }
        }
    }

    private func referenceSortKey(_ value: HermesCiderReference) -> String {
        framed([
            value.kind, value.id, value.title, value.boardID ?? "",
            value.projectID ?? "", value.artifactType ?? "", value.source,
            value.sourceRef,
        ])
    }

    private func framed(_ values: [String]) -> String {
        values.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
    }

    private func replayActivity(
        _ activity: [AgentRoomsLiveActivity]
    ) -> [ReplayActivity] {
        activity.map {
            ReplayActivity(kind: String(describing: $0.kind), detail: $0.detail)
        }
    }

    private func validatedTerminal(
        _ completion: HermesRunCompletionEnvelope,
        expectedText: String,
        expectedConversationID: UUID,
        allowsAttachmentContent: Bool = false
    ) throws -> ValidatedTerminal {
        guard completion.provenance == .hermesRunsAPI,
              completion.terminalStatus == .completed,
              completion.finalSessionSynchronizationComplete,
              completion.observedFacts.runIdentityConsistent,
              (!completion.observedFacts.containedAttachmentContentOrEvent || allowsAttachmentContent),
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
            participantRoster: ConversationRoomParticipantRoster(
                members: ([defaultAgentProfile] + participantProfiles.filter {
                    $0.id != defaultAgentProfile.id
                }.prefix(ConversationRoomParticipantRoster.maximumParticipantCount - 1)).enumerated().map {
                    index, profile in ConversationRoomParticipant(
                        id: UUID(),
                        profile: profile,
                        role: index == 0 ? .actingAgent : .advisor,
                        addedAt: date
                    )
                },
                updatedAt: date
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
        let baseMetadata = ConversationRepository.metadataWithoutAgentConfiguration(room.metadata)
        if room.metadata[ConversationRepository.agentAssignmentMetadataKey] != nil {
            _ = try repository.agentAssignment(roomID: room.id)
        }
        if room.metadata[ConversationRepository.participantRosterMetadataKey] != nil {
            _ = try repository.participantRoster(roomID: room.id)
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

    /// A physical reopen must prove the existing canonical rows valid before any
    /// interrupted-turn recovery can write. Recovery and its immediate validation
    /// share one rollback-capable transaction, followed by a post-commit read.
    private func validatedRecoverySnapshot(
        room: ConversationRoom
    ) throws -> AgentRoomsConversationSnapshot {
        _ = try snapshot(room: room)
        try repository.withImmediateTransaction {
            try recoverInterruptedTurnIfNeeded(roomID: room.id)
            guard let recoveredRoom = try repository.room(id: room.id) else {
                throw AgentRoomsConversationPersistenceError.corruptHistory
            }
            _ = try snapshot(room: recoveredRoom)
        }
        guard let recoveredRoom = try repository.room(id: room.id) else {
            throw AgentRoomsConversationPersistenceError.corruptHistory
        }
        return try snapshot(room: recoveredRoom)
    }

    private func snapshot(room: ConversationRoom) throws -> AgentRoomsConversationSnapshot {
        let turns = try repository.turns(roomID: room.id)
        let messages = try repository.messages(roomID: room.id)
        let bindings = try repository.bindings(roomID: room.id)
        let assignment = try repository.agentAssignment(roomID: room.id)
        guard room.nextTurnSequence == Int64(turns.count + 1),
              room.nextMessageSequence == Int64(messages.count + 1),
              messages.allSatisfy({ $0.roomID == room.id }),
              turns.allSatisfy({ $0.roomID == room.id }),
              bindings.allSatisfy({ $0.roomID == room.id })
        else { throw AgentRoomsConversationPersistenceError.corruptHistory }
        try validateSnapshotRows(
            room: room,
            assignment: assignment,
            turns: turns,
            messages: messages,
            bindings: bindings
        )

        let orderedBindings = orderedSessionBindings(bindings)
        let bindingByID = Dictionary(uniqueKeysWithValues: bindings.map { ($0.id, $0) })
        var latestAttemptByClient: [String: ConversationTurn] = [:]
        var participantAttributionByClientMessageID: [String: ConversationParticipantRunAttribution] = [:]
        for turn in turns {
            if let clientID = turn.metadata["client_message_id"] {
                latestAttemptByClient[clientID] = turn
                if let encoded = turn.metadata[AgentRoomsParticipantService.runAttributionMetadataKey] {
                    guard let attribution = DatabaseHelpers.decodeJSON(
                        ConversationParticipantRunAttribution.self,
                        from: encoded
                    ) else { throw AgentRoomsConversationPersistenceError.corruptHistory }
                    participantAttributionByClientMessageID[clientID] = attribution
                }
            }
        }
        let participantNames = try repository.participantRoster(roomID: room.id).map { roster in
            Dictionary(uniqueKeysWithValues: roster.members.map { ($0.id, $0.profile.displayName) })
        } ?? [:]
        let presentationMessages = try messages.compactMap { message -> AgentRoomMessage? in
            switch message.role.lowercased() {
            case "user":
                let clientID: String?
                if message.source?.namespace == Self.clientSourceNamespace {
                    clientID = message.source?.id
                } else if message.source?.namespace
                    == AgentRoomsParticipantService.submissionSourceNamespace {
                    clientID = message.metadata["client_message_id"]
                } else {
                    clientID = nil
                }
                let attempt = clientID.flatMap { latestAttemptByClient[$0] }
                let failed = attempt?.status == .failed || attempt?.status == .cancelled
                let accepted = attempt?.source?.namespace == Self.sourceNamespace
                    || attempt?.source?.namespace
                        == AgentRoomsParticipantService.runSourceNamespace
                return AgentRoomMessage(
                    id: clientID ?? message.id.uuidString,
                    role: .human,
                    author: "You",
                    body: message.contentText,
                    deliveryState: failed ? .failed : .sent,
                    canRetry: failed && !accepted,
                    attachments: try decodeAttachments(message.metadata["attachments_json"])
                )
            case "assistant":
                let routing = try generatedRouting(message.metadata)
                let participantName: String?
                if let encoded = message.metadata[AgentRoomsParticipantService.messageAttributionMetadataKey] {
                    guard let attribution = DatabaseHelpers.decodeJSON(
                        ConversationParticipantMessageAttribution.self,
                        from: encoded
                    ) else { throw AgentRoomsConversationPersistenceError.corruptHistory }
                    participantName = attribution.participantID.flatMap { participantNames[$0] }
                } else {
                    participantName = nil
                }
                return AgentRoomMessage(
                    id: message.id.uuidString,
                    role: .agent,
                    author: routing?.recipient.displayName ?? participantName ?? "Hermes",
                    body: message.contentText,
                    deliveryState: message.metadata[Self.publicationStateMetadataKey] == "held_stale"
                        ? .held : .sent
                )
            case "system":
                return AgentRoomMessage(
                    id: message.id.uuidString,
                    role: .agent,
                    author: "Cider",
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
            case "assistant" where message.status == .complete
                    && message.metadata[Self.publicationStateMetadataKey] == nil:
                role = .assistant
            default: return nil
            }
            let routing = try? generatedRouting(message.metadata)
            return AIAssistantMessage(
                role: role,
                content: message.contentText,
                timestamp: message.sourceCreatedAt ?? message.createdAt,
                sourceID: message.source?.id,
                sourceSessionID: message.runtimeBindingID.flatMap { bindingByID[$0]?.externalSessionID },
                sourceName: routing?.recipient.displayName ?? "Hermes"
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
        let latestRunID = (
            latestTurn?.source?.namespace == Self.sourceNamespace
                || latestTurn?.source?.namespace
                    == AgentRoomsParticipantService.runSourceNamespace
        )
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
            ),
            participantAttributionByClientMessageID: participantAttributionByClientMessageID
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
        let accepted = (
            latest.source?.namespace == Self.sourceNamespace
                || latest.source?.namespace
                    == AgentRoomsParticipantService.runSourceNamespace
        )
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
        room: ConversationRoom,
        assignment: ConversationRoomAgentAssignment?,
        turns: [ConversationTurn],
        messages: [ConversationMessage],
        bindings: [ConversationRuntimeBinding]
    ) throws {
        guard turns.enumerated().allSatisfy({ $0.element.sequence == Int64($0.offset + 1) }),
              messages.enumerated().allSatisfy({ $0.element.sequence == Int64($0.offset + 1) })
        else { throw AgentRoomsConversationPersistenceError.corruptHistory }

        let turnByID = Dictionary(uniqueKeysWithValues: turns.map { ($0.id, $0) })
        let turnIDs = Set(turnByID.keys)
        let bindingIDs = Set(bindings.map(\.id))
        let participantRoster = try repository.participantRoster(roomID: room.id)
        let participantByID = Dictionary(
            uniqueKeysWithValues: participantRoster?.members.map { ($0.id, $0) } ?? []
        )
        let participantProfileIDs = Set(
            participantRoster?.members.map(\.profile.id) ?? []
        )
        let routingAcceptanceHistory = try repository.routingAcceptanceHistory(
            roomID: room.id
        )
        let routingAcceptanceByUserMessageID = Dictionary(
            uniqueKeysWithValues: routingAcceptanceHistory?.records.map {
                ($0.userMessageID, $0)
            } ?? []
        )
        var participantRunAttributionByTurnID:
            [UUID: ConversationParticipantRunAttribution] = [:]
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
            guard turn.runtimeBindingID.map(bindingIDs.contains) ?? true else {
                throw AgentRoomsConversationPersistenceError.corruptHistory
            }
            let runAttribution: ConversationParticipantRunAttribution?
            if let raw = turn.metadata[
                AgentRoomsParticipantService.runAttributionMetadataKey
            ] {
                guard let decoded = DatabaseHelpers.decodeJSON(
                    ConversationParticipantRunAttribution.self,
                    from: raw
                ) else { throw AgentRoomsConversationPersistenceError.corruptHistory }
                runAttribution = decoded
            } else {
                runAttribution = nil
            }
            if turn.metadata["authority"]
                == AgentRoomsParticipantService.participantAuthority {
                guard let runAttribution,
                      runAttribution.selectionSequence > 0,
                      let participant = participantByID[runAttribution.participantID],
                      participant.profile.id == runAttribution.profileID,
                      runAttribution.displayName != nil,
                      participant.role == runAttribution.participantRole,
                      turn.source.map({
                          $0.namespace == AgentRoomsParticipantService.runSourceNamespace
                              && !$0.id.isEmpty
                      }) ?? true,
                      turn.metadata["source_created_at"].flatMap(Double.init) != nil
                        || turn.metadata["attempt_id"] != nil
                else { throw AgentRoomsConversationPersistenceError.corruptHistory }
                participantRunAttributionByTurnID[turn.id] = runAttribution
            } else {
                guard turn.metadata["authority"] == Self.attemptAuthority
                        || turn.metadata["authority"] == Self.testRoomAuthority,
                      runAttribution == nil,
                      turn.source.map({
                          $0.namespace == Self.sourceNamespace && !$0.id.isEmpty
                      }) ?? true
                else { throw AgentRoomsConversationPersistenceError.corruptHistory }
            }
            if turn.status == .completed {
                let isParticipant = turn.metadata["authority"]
                    == AgentRoomsParticipantService.participantAuthority
                guard turn.source != nil, isParticipant || turn.runtimeBindingID != nil else {
                    throw AgentRoomsConversationPersistenceError.corruptHistory
                }
            }
            if let routing = try generatedRouting(turn.metadata) {
                try routing.validate()
            }
            try validateStructuredFactMetadata(turn.metadata)
        }

        let messageIndexByID = Dictionary(uniqueKeysWithValues: messages.enumerated().map {
            ($0.element.id, $0.offset)
        })
        var submissionByUserID: [UUID: ConversationSubmissionRoutingContext] = [:]
        var participantMessageAttributionByMessageID:
            [UUID: ConversationParticipantMessageAttribution] = [:]
        var events: [(message: ConversationMessage, event: ConversationHeadRoutingChangeEvent)] = []
        for (index, message) in messages.enumerated() {
            let parentIsEarlier = message.parentMessageID.map {
                messageIndexByID[$0].map { $0 < index } ?? false
            } ?? (index == 0)
            guard message.turnID.map(turnIDs.contains) ?? true,
                  message.runtimeBindingID.map(bindingIDs.contains) ?? true,
                  parentIsEarlier,
                  message.sourceCreatedAt != nil,
                  message.metadata["authority"] == Self.attemptAuthority
                    || message.metadata["authority"] == Self.testRoomAuthority
                    || message.metadata["authority"] == ConversationRepository.headChangeEventAuthority
                    || message.metadata["authority"]
                        == AgentRoomsParticipantService.participantAuthority,
                  let source = message.source,
                  source.namespace == Self.clientSourceNamespace
                    || source.namespace == Self.sourceNamespace
                    || source.namespace == ConversationRepository.headChangeEventSourceNamespace
                    || source.namespace == AgentRoomsParticipantService.submissionSourceNamespace
                    || source.namespace == AgentRoomsParticipantService.runSourceNamespace,
                  !source.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !message.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { throw AgentRoomsConversationPersistenceError.corruptHistory }
            let submission = try submissionRouting(message)
            if let routing = submission {
                try routing.validate()
            }
            if let routing = try generatedRouting(message.metadata) {
                try routing.validate()
            }
            let messageAttribution: ConversationParticipantMessageAttribution?
            if let raw = message.metadata[
                AgentRoomsParticipantService.messageAttributionMetadataKey
            ] {
                guard let decoded = DatabaseHelpers.decodeJSON(
                    ConversationParticipantMessageAttribution.self,
                    from: raw
                ) else { throw AgentRoomsConversationPersistenceError.corruptHistory }
                messageAttribution = decoded
                participantMessageAttributionByMessageID[message.id] = decoded
            } else {
                messageAttribution = nil
            }
            switch message.role.lowercased() {
            case "user":
                guard message.status == .complete,
                      message.finishReason == .stop,
                      source.namespace == Self.clientSourceNamespace
                        || source.namespace
                            == AgentRoomsParticipantService.submissionSourceNamespace
                        || source.namespace == Self.sourceNamespace
                else {
                    throw AgentRoomsConversationPersistenceError.corruptHistory
                }
                let requiresSubmissionRouting =
                    source.namespace == Self.clientSourceNamespace
                    || source.namespace
                        == AgentRoomsParticipantService.submissionSourceNamespace
                guard !requiresSubmissionRouting || submission != nil else {
                    throw AgentRoomsConversationPersistenceError.corruptHistory
                }
                if let submission {
                    guard submission.observedRoomMessageSequence == message.sequence - 1 else {
                        throw AgentRoomsConversationPersistenceError.corruptHistory
                    }
                    guard let acceptance = routingAcceptanceByUserMessageID[message.id],
                          acceptance.sourceNamespace == source.namespace,
                          acceptance.routing == submission
                    else {
                        throw AgentRoomsConversationPersistenceError.corruptHistory
                    }
                    submissionByUserID[message.id] = submission
                }
                if source.namespace == Self.clientSourceNamespace {
                    guard message.metadata["authority"] == Self.attemptAuthority
                            || message.metadata["authority"] == Self.testRoomAuthority,
                          messageAttribution == nil
                    else { throw AgentRoomsConversationPersistenceError.corruptHistory }
                } else if source.namespace
                    == AgentRoomsParticipantService.submissionSourceNamespace {
                    guard message.metadata["authority"]
                            == AgentRoomsParticipantService.participantAuthority,
                          let messageAttribution,
                          messageAttribution.runID == nil,
                          messageAttribution.participantID == nil,
                          messageAttribution.profileID == nil,
                          messageAttribution.displayName == nil,
                          messageAttribution.participantRole == nil,
                          submission != nil
                    else { throw AgentRoomsConversationPersistenceError.corruptHistory }
                } else {
                    guard submission == nil,
                          message.metadata["authority"] == Self.attemptAuthority
                            || message.metadata["authority"] == Self.testRoomAuthority,
                          messageAttribution == nil
                    else { throw AgentRoomsConversationPersistenceError.corruptHistory }
                }
            case "assistant":
                let isComplete = message.status == .complete && message.finishReason == .stop
                let isPartial = message.status == .incomplete
                    && (message.finishReason == .cancelled || message.finishReason == .error)
                let isHeldStale = message.status == .incomplete
                    && message.finishReason == .other
                    && message.metadata[Self.publicationStateMetadataKey]
                        == ConversationPublicationState.heldStale.rawValue
                let publication = message.metadata[Self.publicationStateMetadataKey]
                guard (isHeldStale && !isComplete && !isPartial)
                        || ((isComplete || isPartial) && publication == nil),
                      publication == nil
                        || publication == ConversationPublicationState.heldStale.rawValue,
                      source.namespace == Self.sourceNamespace
                        || source.namespace
                            == AgentRoomsParticipantService.runSourceNamespace
                else {
                    throw AgentRoomsConversationPersistenceError.corruptHistory
                }
                if source.namespace == AgentRoomsParticipantService.runSourceNamespace {
                    guard message.metadata["authority"]
                            == AgentRoomsParticipantService.participantAuthority,
                          let messageAttribution,
                          messageAttribution.runID != nil,
                          messageAttribution.participantID != nil,
                          messageAttribution.profileID != nil,
                          messageAttribution.displayName != nil,
                          messageAttribution.participantRole != nil
                    else { throw AgentRoomsConversationPersistenceError.corruptHistory }
                } else {
                    guard message.metadata["authority"] == Self.attemptAuthority
                            || message.metadata["authority"] == Self.testRoomAuthority,
                          messageAttribution == nil
                    else { throw AgentRoomsConversationPersistenceError.corruptHistory }
                }
            case "system":
                guard message.turnID == nil,
                      message.runtimeBindingID == nil,
                      message.status == .complete,
                      message.finishReason == .stop,
                      source.namespace == ConversationRepository.headChangeEventSourceNamespace,
                      message.metadata["authority"]
                        == ConversationRepository.headChangeEventAuthority,
                      messageAttribution == nil,
                      let raw = message.metadata[ConversationRepository.headChangeEventMetadataKey],
                      let event = DatabaseHelpers.decodeJSON(
                          ConversationHeadRoutingChangeEvent.self,
                          from: raw
                      )
                else {
                    throw AgentRoomsConversationPersistenceError.corruptHistory
                }
                try event.validate()
                let sourceTimeMatches = message.sourceCreatedAt.map {
                    abs($0.timeIntervalSince(event.changedAt)) < 0.001
                } ?? false
                guard event.id == message.id,
                      source.id == event.id.uuidString,
                      sourceTimeMatches
                else { throw AgentRoomsConversationPersistenceError.corruptHistory }
                events.append((message, event))
            default:
                throw AgentRoomsConversationPersistenceError.corruptHistory
            }
        }
        guard Set(routingAcceptanceByUserMessageID.keys)
                == Set(submissionByUserID.keys)
        else {
            throw AgentRoomsConversationPersistenceError.corruptHistory
        }

        for pair in zip(events, events.dropFirst()) {
            guard pair.1.event.oldHeadRoutingEpoch == pair.0.event.newHeadRoutingEpoch,
                  pair.1.event.oldHead?.profileID == pair.0.event.newHead.profileID,
                  pair.1.event.changedAt >= pair.0.event.changedAt
            else { throw AgentRoomsConversationPersistenceError.corruptHistory }
        }
        let messageByID = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        for (eventIndex, entry) in events.enumerated() {
            let precedingMessages = messages.prefix {
                $0.sequence < entry.message.sequence
            }
            var expectedParentMessageID: UUID?
            for candidate in precedingMessages.reversed() {
                if candidate.metadata[Self.publicationStateMetadataKey]
                    == ConversationPublicationState.heldStale.rawValue {
                    continue
                }
                switch candidate.role.lowercased() {
                case "system":
                    guard let raw = candidate.metadata[
                        ConversationRepository.headChangeEventMetadataKey
                    ],
                    let priorEvent = DatabaseHelpers.decodeJSON(
                        ConversationHeadRoutingChangeEvent.self,
                        from: raw
                    )
                    else { continue }
                    try priorEvent.validate()
                    if let oldHead = entry.event.oldHead,
                       priorEvent.newHead.profileID == oldHead.profileID,
                       priorEvent.newHeadRoutingEpoch
                        == entry.event.oldHeadRoutingEpoch {
                        expectedParentMessageID = candidate.id
                    }
                case "assistant":
                    guard candidate.status == .complete,
                          candidate.finishReason == .stop,
                          candidate.metadata[
                            AgentRoomsParticipantService.messageAttributionMetadataKey
                          ] == nil
                    else { continue }
                    if let routing = try generatedRouting(candidate.metadata) {
                        if routing.observedHeadRoutingEpoch
                            == entry.event.oldHeadRoutingEpoch,
                           entry.event.oldHead.map({
                               routing.recipient.profileID == $0.profileID
                           }) ?? true {
                            expectedParentMessageID = candidate.id
                        }
                    } else if entry.event.oldHead == nil {
                        expectedParentMessageID = candidate.id
                    }
                case "user":
                    if let routing = try submissionRouting(candidate) {
                        if routing.observedHeadRoutingEpoch
                            == entry.event.oldHeadRoutingEpoch,
                           entry.event.oldHead.map({ oldHead in
                               routing.recipients.contains {
                                   $0.profileID == oldHead.profileID
                               }
                           }) ?? true {
                            expectedParentMessageID = candidate.id
                        }
                    } else {
                        expectedParentMessageID = candidate.id
                    }
                default:
                    continue
                }
                if expectedParentMessageID != nil { break }
            }
            guard entry.message.parentMessageID == expectedParentMessageID else {
                throw AgentRoomsConversationPersistenceError.corruptHistory
            }

            var cursor = entry.message.parentMessageID
            var visited = Set<UUID>()
            var includesPriorEvent = eventIndex == 0
            while let id = cursor {
                guard visited.insert(id).inserted,
                      let ancestor = messageByID[id],
                      ancestor.metadata[Self.publicationStateMetadataKey]
                        != ConversationPublicationState.heldStale.rawValue
                else { throw AgentRoomsConversationPersistenceError.corruptHistory }
                if eventIndex > 0, id == events[eventIndex - 1].message.id {
                    includesPriorEvent = true
                }
                cursor = ancestor.parentMessageID
            }
            guard includesPriorEvent else {
                throw AgentRoomsConversationPersistenceError.corruptHistory
            }
        }
        if let first = events.first {
            guard first.event.oldHeadRoutingEpoch == 0
                    || first.event.oldHeadRoutingEpoch == 1
            else { throw AgentRoomsConversationPersistenceError.corruptHistory }
        }
        if let final = events.last?.event {
            guard let assignment,
                  final.newHeadRoutingEpoch == assignment.headRoutingEpoch,
                  final.newHead.profileID == assignment.profile.id
            else { throw AgentRoomsConversationPersistenceError.corruptHistory }
        }

        for message in messages where message.role.lowercased() == "user" {
            guard let submission = submissionByUserID[message.id] else { continue }
            let priorEvent = events.last(where: {
                $0.message.sequence < message.sequence
            })
            let expectedEpoch: Int64
            let canonicalHead: ConversationRoutingRecipient?
            if let priorEvent {
                expectedEpoch = priorEvent.event.newHeadRoutingEpoch
                canonicalHead = priorEvent.event.newHead
            } else if let firstEvent = events.first?.event {
                expectedEpoch = firstEvent.oldHeadRoutingEpoch
                canonicalHead = firstEvent.oldHead
            } else {
                expectedEpoch = assignment?.headRoutingEpoch ?? 0
                canonicalHead = assignment.map {
                    ConversationRoutingRecipient(profile: $0.profile)
                } ?? (expectedEpoch == 0
                    ? ConversationRoutingRecipient(profile: defaultAgentProfile)
                    : nil)
            }
            guard submission.observedHeadRoutingEpoch == expectedEpoch else {
                throw AgentRoomsConversationPersistenceError.corruptHistory
            }
            if message.source?.namespace == Self.clientSourceNamespace {
                guard submission.recipients.count == 1,
                      let canonicalHead,
                      submission.recipients[0].profileID == canonicalHead.profileID
                else {
                    throw AgentRoomsConversationPersistenceError.corruptHistory
                }
            } else if message.source?.namespace
                == AgentRoomsParticipantService.submissionSourceNamespace {
                guard participantMessageAttributionByMessageID[message.id] != nil,
                      submission.recipients.allSatisfy({
                          participantProfileIDs.contains($0.profileID)
                      })
                else {
                    throw AgentRoomsConversationPersistenceError.corruptHistory
                }
            } else {
                throw AgentRoomsConversationPersistenceError.corruptHistory
            }
        }

        var assistantByTurnID: [UUID: ConversationMessage] = [:]
        for message in messages where message.role.lowercased() == "assistant" {
            let messageRouting = try generatedRouting(message.metadata)
            guard let turnID = message.turnID else {
                guard messageRouting == nil,
                      message.source?.namespace
                        != AgentRoomsParticipantService.runSourceNamespace
                else { throw AgentRoomsConversationPersistenceError.corruptHistory }
                continue
            }
            guard let turn = turnByID[turnID],
                  assistantByTurnID.updateValue(message, forKey: turnID) == nil
            else { throw AgentRoomsConversationPersistenceError.corruptHistory }
            let turnRouting = try generatedRouting(turn.metadata)
            let requiresGeneratedRouting =
                turn.metadata["attempt_id"] != nil
                || turn.metadata["authority"]
                    == AgentRoomsParticipantService.participantAuthority
            if !requiresGeneratedRouting, messageRouting == nil, turnRouting == nil {
                continue
            }
            guard let messageRouting,
                  let turnRouting,
                  messageRouting == turnRouting,
                  let userIndex = messageIndexByID[messageRouting.originatingUserMessageID],
                  userIndex < (messageIndexByID[message.id] ?? 0),
                  message.parentMessageID == messageRouting.originatingUserMessageID,
                  let submission = submissionByUserID[
                      messageRouting.originatingUserMessageID
                  ],
                  submission.observedHeadRoutingEpoch
                    == messageRouting.observedHeadRoutingEpoch,
                  submission.observedRoomMessageSequence
                    == messageRouting.observedRoomMessageSequence,
                  submission.recipients.contains(messageRouting.recipient)
            else { throw AgentRoomsConversationPersistenceError.corruptHistory }
            if message.source?.namespace
                == AgentRoomsParticipantService.runSourceNamespace {
                guard let runAttribution = participantRunAttributionByTurnID[turnID],
                      let messageAttribution =
                        participantMessageAttributionByMessageID[message.id],
                      let userAttribution =
                        participantMessageAttributionByMessageID[
                            messageRouting.originatingUserMessageID
                        ],
                      userAttribution.invocationID == runAttribution.invocationID,
                      messageAttribution.invocationID == runAttribution.invocationID,
                      messageAttribution.runID == runAttribution.runID,
                      messageAttribution.participantID
                        == runAttribution.participantID,
                      messageAttribution.profileID == runAttribution.profileID,
                      messageAttribution.displayName == runAttribution.displayName,
                      messageAttribution.participantRole
                        == runAttribution.participantRole,
                      messageRouting.recipient == ConversationRoutingRecipient(
                        profileID: runAttribution.profileID,
                        displayName: runAttribution.displayName ?? ""
                      )
                else { throw AgentRoomsConversationPersistenceError.corruptHistory }
            } else {
                guard participantRunAttributionByTurnID[turnID] == nil else {
                    throw AgentRoomsConversationPersistenceError.corruptHistory
                }
            }
        }
        for turn in turns {
            let routing = try generatedRouting(turn.metadata)
            let requiresGeneratedRouting =
                turn.metadata["attempt_id"] != nil
                || turn.metadata["authority"]
                    == AgentRoomsParticipantService.participantAuthority
            guard !requiresGeneratedRouting || routing != nil else {
                throw AgentRoomsConversationPersistenceError.corruptHistory
            }
            guard let routing else { continue }
            guard let userIndex = messageIndexByID[routing.originatingUserMessageID],
                  let submission = submissionByUserID[routing.originatingUserMessageID],
                  submission.observedHeadRoutingEpoch == routing.observedHeadRoutingEpoch,
                  submission.observedRoomMessageSequence
                    == routing.observedRoomMessageSequence,
                  submission.recipients.contains(routing.recipient)
            else { throw AgentRoomsConversationPersistenceError.corruptHistory }
            if let runAttribution = participantRunAttributionByTurnID[turn.id] {
                guard let userAttribution =
                        participantMessageAttributionByMessageID[
                            routing.originatingUserMessageID
                        ],
                      userAttribution.invocationID == runAttribution.invocationID,
                      routing.recipient == ConversationRoutingRecipient(
                        profileID: runAttribution.profileID,
                        displayName: runAttribution.displayName ?? ""
                      )
                else { throw AgentRoomsConversationPersistenceError.corruptHistory }
            } else {
                guard participantMessageAttributionByMessageID[
                    routing.originatingUserMessageID
                ] == nil else {
                    throw AgentRoomsConversationPersistenceError.corruptHistory
                }
            }
            if let assistant = assistantByTurnID[turn.id] {
                guard userIndex < (messageIndexByID[assistant.id] ?? 0) else {
                    throw AgentRoomsConversationPersistenceError.corruptHistory
                }
            }
            let turnHeld = turn.metadata[Self.publicationStateMetadataKey]
                == ConversationPublicationState.heldStale.rawValue
            let messageHeld = assistantByTurnID[turn.id]?.metadata[
                Self.publicationStateMetadataKey
            ] == ConversationPublicationState.heldStale.rawValue
            if turnHeld || messageHeld || turn.error?.code == "stale_head_routing_epoch" {
                guard turnHeld,
                      turn.error?.code == "stale_head_routing_epoch",
                      turn.status == .failed || turn.status == .cancelled,
                      let observedCurrent = turn.metadata[
                          "current_head_routing_epoch"
                      ].flatMap(Int64.init),
                      observedCurrent > routing.observedHeadRoutingEpoch,
                      events.contains(where: {
                          $0.event.newHeadRoutingEpoch == observedCurrent
                      }) || assignment?.headRoutingEpoch == observedCurrent,
                      assistantByTurnID[turn.id].map({
                          $0.status == .incomplete
                              && $0.finishReason == .other
                              && $0.metadata["current_head_routing_epoch"]
                                  == String(observedCurrent)
                      }) ?? true,
                      messageHeld == (assistantByTurnID[turn.id] != nil)
                else { throw AgentRoomsConversationPersistenceError.corruptHistory }
            } else {
                guard turn.metadata[Self.publicationStateMetadataKey] == nil,
                      assistantByTurnID[turn.id]?.metadata[
                          Self.publicationStateMetadataKey
                      ] == nil
                else { throw AgentRoomsConversationPersistenceError.corruptHistory }
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
        activity: [AgentRoomsLiveActivity],
        routingContext: ConversationGeneratedRoutingContext,
        attribution: ConversationParticipantRunAttribution? = nil,
        attachments: [HermesCiderAttachment] = []
    ) -> [String: String] {
        var metadata = [
            "authority": persistenceAuthority(attribution: attribution),
            "schema_version": Self.schemaVersion,
            "attempt_id": attemptID.uuidString,
            "client_message_id": clientMessageID,
            "activity_json": encodeActivity(activity),
            Self.generatedRoutingMetadataKey: encode(routingContext),
        ]
        if let runID { metadata["run_id"] = runID }
        metadata.merge(attachmentMetadata(attachments), uniquingKeysWith: { current, _ in current })
        if let attribution,
           let encoded = DatabaseHelpers.encodeJSON(attribution) {
            metadata[AgentRoomsParticipantService.runAttributionMetadataKey] = encoded
            let participantActivity = activity.prefix(
                ConversationParticipantInvocationLimits.checkpoint.maximumUpdatesPerParticipant
            ).enumerated().map { index, update in
                let kind: ConversationParticipantActivityKind
                switch update.kind {
                case .reasoning: kind = .work
                case .toolStarted, .toolCompleted: kind = .tool
                }
                return ConversationParticipantActivity(
                    id: UUID(),
                    invocationID: attribution.invocationID,
                    runID: attribution.runID,
                    participantID: attribution.participantID,
                    sequence: index + 1,
                    kind: kind,
                    summary: AgentRoomsActivityPresentation.project(update).summary
                )
            }
            if let activityJSON = DatabaseHelpers.encodeJSON(participantActivity) {
                metadata[AgentRoomsParticipantService.activityMetadataKey] = activityJSON
            }
        }
        return metadata
    }

    private func attemptMetadata(
        _ persisted: [String: String],
        matches expected: [String: String],
        routingContext: ConversationGeneratedRoutingContext
    ) throws -> Bool {
        guard try generatedRouting(persisted) == routingContext else { return false }
        var persisted = persisted
        var expected = expected
        persisted.removeValue(forKey: Self.generatedRoutingMetadataKey)
        expected.removeValue(forKey: Self.generatedRoutingMetadataKey)
        return persisted == expected
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
            activity: activity,
            routingContext: attempt.routingContext,
            attribution: attempt.participantAttribution,
            attachments: attempt.inputAttachments
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

    private func attachmentMetadata(_ attachments: [HermesCiderAttachment]) -> [String: String] {
        guard !attachments.isEmpty,
              HermesCiderAssetFactContract.normalizedAttachments(attachments).state == .validated
        else { return [:] }
        return [
            "attachment_fact_state": HermesStructuredFactState.validated.rawValue,
            "attachments_json": encode(attachments),
        ]
    }

    private func mergedAttachments(
        local: [HermesCiderAttachment],
        remote: [HermesCiderAttachment]
    ) -> [HermesCiderAttachment] {
        var values = local
        var ids = Set(local.map(\.id))
        var targets = Set(local.map(\.target.sourceRef))
        for fact in remote where !ids.contains(fact.id) && !targets.contains(fact.target.sourceRef) {
            values.append(fact)
            ids.insert(fact.id)
            targets.insert(fact.target.sourceRef)
        }
        return HermesCiderAssetFactContract.normalizedAttachments(values).state == .validated ? values : local
    }

    private func messageMetadata(
        runID: String,
        sessionID: String,
        modelIdentity: String,
        transportTimestamp: Date,
        routingContext: ConversationGeneratedRoutingContext,
        attribution: ConversationParticipantRunAttribution?
    ) -> [String: String] {
        participantMessageMetadata(base: [
            "authority": persistenceAuthority(attribution: attribution),
            "schema_version": Self.schemaVersion,
            "run_id": runID,
            "session_id": sessionID,
            "model_identity": modelIdentity,
            "transport_timestamp": String(transportTimestamp.timeIntervalSince1970),
            Self.generatedRoutingMetadataKey: encode(routingContext),
        ], invocationID: attribution?.invocationID, attribution: attribution)
    }

    private func participantMessageMetadata(
        base: [String: String],
        invocationID: UUID?,
        attribution: ConversationParticipantRunAttribution?
    ) -> [String: String] {
        guard let invocationID else { return base }
        var metadata = base
        let messageAttribution = ConversationParticipantMessageAttribution(
            invocationID: invocationID,
            runID: attribution?.runID,
            participantID: attribution?.participantID,
            profileID: attribution?.profileID,
            displayName: attribution?.displayName,
            participantRole: attribution?.participantRole
        )
        if let encoded = DatabaseHelpers.encodeJSON(messageAttribution) {
            metadata[AgentRoomsParticipantService.messageAttributionMetadataKey] = encoded
        }
        return metadata
    }

    private func persistenceAuthority(
        attribution: ConversationParticipantRunAttribution?
    ) -> String {
        attribution == nil
            ? Self.attemptAuthority
            : AgentRoomsParticipantService.participantAuthority
    }

    private func executionSourceNamespace(
        attribution: ConversationParticipantRunAttribution?
    ) -> String {
        attribution == nil
            ? Self.sourceNamespace
            : AgentRoomsParticipantService.runSourceNamespace
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

    private func submissionRouting(
        _ message: ConversationMessage
    ) throws -> ConversationSubmissionRoutingContext? {
        guard let raw = message.metadata[Self.submissionRoutingMetadataKey] else { return nil }
        guard let value = DatabaseHelpers.decodeJSON(
            ConversationSubmissionRoutingContext.self,
            from: raw
        ) else {
            throw AgentRoomsConversationPersistenceError.corruptHistory
        }
        try value.validate()
        return value
    }

    private func generatedRouting(
        _ metadata: [String: String]
    ) throws -> ConversationGeneratedRoutingContext? {
        guard let raw = metadata[Self.generatedRoutingMetadataKey] else { return nil }
        guard let value = DatabaseHelpers.decodeJSON(
            ConversationGeneratedRoutingContext.self,
            from: raw
        ) else {
            throw AgentRoomsConversationPersistenceError.corruptHistory
        }
        try value.validate()
        return value
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
    ) throws -> ConversationResultPublicationOutcome {
        try sharedConversationPersistence.complete(
            attempt,
            completion: completion,
            expectedText: expectedText,
            activity: activity
        )
    }

    @discardableResult
    func terminate(
        _ attempt: AgentRoomsConversationAttempt,
        status: ConversationTurnStatus,
        runID: String?,
        partialAssistantText: String?,
        activity: [AgentRoomsLiveActivity],
        at date: Date
    ) throws -> ConversationResultPublicationOutcome {
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
