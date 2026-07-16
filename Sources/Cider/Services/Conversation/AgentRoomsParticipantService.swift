import Foundation

@MainActor
protocol AgentRoomsParticipantReading: AnyObject {
    func roster(roomID: UUID) throws -> ConversationRoomParticipantRoster?
    func presentation(roomID: UUID) throws -> AgentRoomParticipantRoster?
    func messageAttribution(
        _ message: ConversationMessage
    ) throws -> ConversationParticipantMessageAttribution?
    func turnAttribution(
        _ turn: ConversationTurn
    ) throws -> ConversationParticipantRunAttribution?
    func activity(roomID: UUID, invocationID: UUID) throws -> [ConversationParticipantActivity]
    func latestActivitySummary(roomID: UUID) throws -> AgentRoomParticipantActivitySummary?
}

@MainActor
protocol AgentRoomsParticipantActing: AgentRoomsParticipantReading {
    @discardableResult
    func configureRoster(
        roomID: UUID,
        members: [ConversationRoomParticipantDraft]
    ) throws -> ConversationRoomParticipantRoster
}

@MainActor
final class AgentRoomsParticipantService: AgentRoomsParticipantActing {
    static let rosterMetadataKey = ConversationRepository.participantRosterMetadataKey
    static let runAttributionMetadataKey = "cider.rooms.participant-run.v1"
    static let messageAttributionMetadataKey = "cider.rooms.participant-message.v1"
    static let activityMetadataKey = "cider.rooms.participant-activity.v1"
    static let participantAuthority = "cider.rooms.participant-execution.v1"
    static let submissionSourceNamespace = "cider.rooms.participant-submissions.v1"
    static let runSourceNamespace = "cider.rooms.participant-runs.v1"
    static let runtimeSourceMetadataKey = "cider.rooms.participant-runtime-source.v1"
    static let maximumPromptLength = 12_000

    private let repository: ConversationRepository
    private let catalog: ConversationAgentProfileCatalog
    private let now: () -> Date

    init(
        repository: ConversationRepository,
        catalog: ConversationAgentProfileCatalog = AgentRoomsProductionAgentProfiles.catalog,
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.catalog = catalog
        self.now = now
    }

    func roster(roomID: UUID) throws -> ConversationRoomParticipantRoster? {
        try repository.participantRoster(roomID: roomID)
    }

    @discardableResult
    func configureRoster(
        roomID: UUID,
        members drafts: [ConversationRoomParticipantDraft]
    ) throws -> ConversationRoomParticipantRoster {
        let room = try requireParticipantRoom(id: roomID)
        guard room.lifecycleState == .active else {
            throw ConversationParticipantInvocationError.invalid(
                "Archived or trashed conversations cannot change participants."
            )
        }
        guard !drafts.isEmpty,
              drafts.count <= ConversationRoomParticipantRoster.maximumParticipantCount
        else {
            throw ConversationParticipantInvocationError.invalid("The participant roster is out of bounds.")
        }
        let timestamp = now()
        var seen = Set<String>()
        let members = try drafts.map { draft -> ConversationRoomParticipant in
            guard seen.insert(draft.profileID).inserted,
                  let profile = catalog.profile(id: draft.profileID)
            else {
                throw ConversationParticipantInvocationError.invalid(
                    "Participant profiles must be configured and unique."
                )
            }
            return ConversationRoomParticipant(
                id: UUID(),
                profile: profile,
                role: draft.role,
                addedAt: timestamp
            )
        }
        let roster = ConversationRoomParticipantRoster(members: members, updatedAt: timestamp)
        try roster.validate()
        return try repository.setParticipantRoster(roomID: roomID, roster: roster, at: timestamp)
    }

    func presentation(roomID: UUID) throws -> AgentRoomParticipantRoster? {
        guard let roster = try roster(roomID: roomID) else { return nil }
        return AgentRoomParticipantRoster(
            members: roster.members.map { member in
                let configured = catalog.profile(id: member.profile.id)
                let matches = configured.map {
                    $0.displayName == member.profile.displayName
                        && $0.runtimeBinding == member.profile.runtimeBinding
                        && $0.capabilities == member.profile.capabilities
                } ?? false
                let available = matches && configured?.availability.isAvailable == true
                let reason: String?
                if !matches {
                    reason = "This participant’s runtime configuration changed."
                } else {
                    reason = configured?.availability.reason
                }
                return AgentRoomParticipant(
                    id: member.id,
                    profileID: member.profile.id,
                    displayName: member.profile.displayName,
                    role: member.role,
                    available: available,
                    unavailableReason: reason
                )
            }
        )
    }

    func invocationPlan(
        _ request: ConversationParticipantInvocationRequest
    ) throws -> [ConversationRoomParticipant] {
        guard request.origin == .user else {
            throw ConversationParticipantInvocationError.invalid(
                "Only an explicit user action can invoke room participants."
            )
        }
        try request.limits.validate()
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, prompt.count <= Self.maximumPromptLength else {
            throw ConversationParticipantInvocationError.invalid(
                "Participant prompts must be nonempty and at most \(Self.maximumPromptLength) characters."
            )
        }
        guard !request.selectedParticipantIDs.isEmpty,
              request.selectedParticipantIDs.count <= request.limits.maximumParticipants,
              Set(request.selectedParticipantIDs).count == request.selectedParticipantIDs.count
        else {
            throw ConversationParticipantInvocationError.invalid(
                "Explicit participant selection is required and must stay within the participant ceiling."
            )
        }
        let room = try requireParticipantRoom(id: request.roomID)
        guard room.lifecycleState == .active,
              let roster = try repository.participantRoster(roomID: request.roomID)
        else {
            throw ConversationParticipantInvocationError.invalid(
                "Only active canonical rooms with a participant roster can invoke participants."
            )
        }
        let selected = Set(request.selectedParticipantIDs)
        let ordered = roster.members.filter { selected.contains($0.id) }
        guard ordered.count == selected.count else {
            throw ConversationParticipantInvocationError.invalid(
                "Every selected participant must belong to this room roster."
            )
        }
        for member in ordered {
            guard let configured = catalog.profile(id: member.profile.id),
                  configured.displayName == member.profile.displayName,
                  configured.runtimeBinding == member.profile.runtimeBinding,
                  configured.capabilities == member.profile.capabilities
            else {
                throw ConversationParticipantInvocationError.unavailable(
                    "\(member.profile.displayName)’s runtime configuration changed. Nothing was sent."
                )
            }
            guard configured.availability.isAvailable else {
                throw ConversationParticipantInvocationError.unavailable(
                    "\(configured.availability.reason ?? "The participant runtime is unavailable.") Nothing was sent."
                )
            }
        }
        return ordered
    }

    func messageAttribution(
        _ message: ConversationMessage
    ) throws -> ConversationParticipantMessageAttribution? {
        try decode(
            ConversationParticipantMessageAttribution.self,
            metadata: message.metadata,
            key: Self.messageAttributionMetadataKey,
            corruption: "Conversation message contains invalid participant attribution."
        )
    }

    func turnAttribution(
        _ turn: ConversationTurn
    ) throws -> ConversationParticipantRunAttribution? {
        try decode(
            ConversationParticipantRunAttribution.self,
            metadata: turn.metadata,
            key: Self.runAttributionMetadataKey,
            corruption: "Conversation turn contains invalid participant attribution."
        )
    }

    func activity(roomID: UUID, invocationID: UUID) throws -> [ConversationParticipantActivity] {
        let values = try repository.recentTurns(
            roomID: roomID,
            limit: ConversationRoomParticipantRoster.maximumParticipantCount
        ).flatMap { turn in
            let attribution = try turnAttribution(turn)
            let values = try decode(
                [ConversationParticipantActivity].self,
                metadata: turn.metadata,
                key: Self.activityMetadataKey,
                corruption: "Conversation turn contains invalid participant activity."
            ) ?? []
            guard values.count <= ConversationParticipantInvocationLimits.checkpoint.maximumUpdatesPerParticipant,
                  values.allSatisfy({ activity in
                      activity.summary == activity.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                          && !activity.summary.isEmpty
                          && activity.summary.count <= 240
                          && !activity.summary.unicodeScalars.contains(
                              where: CharacterSet.controlCharacters.contains
                          )
                          && activity.sequence > 0
                          && activity.invocationID == attribution?.invocationID
                          && activity.runID == attribution?.runID
                          && activity.participantID == attribution?.participantID
                  })
            else {
                throw ConversationRepositoryError.integrity(
                    "Conversation turn contains unbounded participant activity."
                )
            }
            return values.filter { $0.invocationID == invocationID }
        }.sorted { lhs, rhs in
            if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        guard values.count
                <= ConversationParticipantInvocationLimits.checkpoint.maximumParticipants
                    * ConversationParticipantInvocationLimits.checkpoint.maximumUpdatesPerParticipant,
              Set(values.map(\.sequence)).count == values.count
        else {
            throw ConversationRepositoryError.integrity(
                "Conversation invocation contains invalid participant activity ordering."
            )
        }
        return values
    }

    func latestActivitySummary(roomID: UUID) throws -> AgentRoomParticipantActivitySummary? {
        guard let turn = try repository.recentTurns(roomID: roomID, limit: 1).first,
              let attribution = try turnAttribution(turn)
        else { return nil }
        let updates = try activity(roomID: roomID, invocationID: attribution.invocationID)
        let status: ConversationParticipantRunStatus
        switch turn.status {
        case .completed: status = .completed
        case .cancelled: status = .cancelled
        case .pending, .running, .waiting: status = .running
        case .unknown, .failed: status = .failed
        }
        return AgentRoomParticipantActivitySummary(
            participantCount: max(1, Set(updates.map(\.participantID)).count),
            updateCount: updates.count,
            status: status,
            updates: updates
        )
    }

    static func encoded<T: Encodable>(_ value: T) throws -> String {
        guard let encoded = DatabaseHelpers.encodeJSON(value) else {
            throw ConversationParticipantInvocationError.invalid(
                "Participant metadata could not be encoded."
            )
        }
        return encoded
    }

    private func decode<T: Decodable>(
        _ type: T.Type,
        metadata: [String: String],
        key: String,
        corruption: String
    ) throws -> T? {
        guard let encoded = metadata[key] else { return nil }
        guard let value = DatabaseHelpers.decodeJSON(type, from: encoded) else {
            throw ConversationRepositoryError.integrity(corruption)
        }
        return value
    }

    private func requireParticipantRoom(id: UUID) throws -> ConversationRoom {
        guard let room = try repository.room(id: id) else {
            throw ConversationRepositoryError.notFound("Conversation room was not found.")
        }
        let metadata = ConversationRepository.metadataWithoutAgentConfiguration(room.metadata)
        let isNative = room.stableKey == nil
            && room.kind == "chat"
            && metadata["authority"] == AgentRoomsConversationPersistence.nativeRoomAuthority
            && metadata["schema_version"] == "1"
            && metadata.count == 2
        let isReserved = room.stableKey == AgentRoomsTestChatPersistence.stableRoomKey
            && room.kind == "cider-test-chat"
            && metadata["authority"] == AgentRoomsConversationPersistence.testRoomAuthority
            && metadata["schema_version"] == "1"
            && metadata["source"] == "cider-rooms-live-continuation"
            && metadata.count == 3
        guard isNative || isReserved else {
            throw ConversationParticipantInvocationError.invalid(
                "Only Cider-owned canonical rooms can manage participants."
            )
        }
        return room
    }
}

@MainActor
final class AgentRoomsParticipantInvocationService {
    private struct ActiveExecution {
        let executionID: UUID
        let roomID: UUID
        let executor: any ConversationParticipantRuntimeExecuting
    }

    private struct PlannedExecution {
        let participant: ConversationRoomParticipant
        let executor: any ConversationParticipantRuntimeExecuting
        let runID: UUID
        let attribution: ConversationParticipantRunAttribution
    }

    private struct AcceptedInvocation {
        let userMessage: ConversationMessage
        let firstTurn: ConversationTurn
        let submissionRouting: ConversationSubmissionRoutingContext
        let executions: [PlannedExecution]
    }

    private let repository: ConversationRepository
    private let participants: AgentRoomsParticipantService
    private let runtimes: ConversationParticipantRuntimeRegistry
    private let now: () -> Date
    private var active: [UUID: ActiveExecution] = [:]
    private var cancellationRequested = Set<UUID>()

    init(
        repository: ConversationRepository,
        participants: AgentRoomsParticipantService,
        runtimes: ConversationParticipantRuntimeRegistry,
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.participants = participants
        self.runtimes = runtimes
        self.now = now
    }

    func invoke(
        _ request: ConversationParticipantInvocationRequest
    ) async throws -> ConversationParticipantInvocationResult {
        guard active[request.id] == nil else {
            throw ConversationParticipantInvocationError.invalid(
                "This participant invocation is already active."
            )
        }
        guard !active.values.contains(where: { $0.roomID == request.roomID }) else {
            throw ConversationParticipantInvocationError.invalid(
                "This room already has its one allowed participant invocation in progress."
            )
        }
        let existingInvocation = try repository.turns(roomID: request.roomID).contains { turn in
            try participants.turnAttribution(turn)?.invocationID == request.id
        }
        guard !existingInvocation else {
            throw ConversationParticipantInvocationError.invalid(
                "This participant invocation is already recorded."
            )
        }
        let preflightPlan = try participants.invocationPlan(request)
        var preflightExecutors: [UUID: any ConversationParticipantRuntimeExecuting] = [:]
        for participant in preflightPlan {
            guard let executor = runtimes.executor(
                for: participant.profile.runtimeBinding
            ) else {
                throw ConversationParticipantInvocationError.unavailable(
                    "\(participant.profile.displayName) has no connected production runtime. Nothing was sent."
                )
            }
            preflightExecutors[participant.id] = executor
        }

        let acceptedAt = now()
        let accepted: AcceptedInvocation
        do {
            accepted = try repository.withImmediateTransaction {
                let existingInvocation = try repository.turns(roomID: request.roomID).contains {
                    turn in
                    try participants.turnAttribution(turn)?.invocationID == request.id
                }
                guard !existingInvocation else {
                    throw ConversationParticipantInvocationError.invalid(
                        "This participant invocation is already recorded."
                    )
                }
                let authoritativePlan = try participants.invocationPlan(request)
                guard let room = try repository.room(id: request.roomID),
                      let assignment = try repository.agentAssignment(roomID: request.roomID)
                else {
                    throw ConversationParticipantInvocationError.invalid(
                        "The room has no durable head-routing assignment."
                    )
                }
                let submissionRouting = ConversationSubmissionRoutingContext(
                    recipients: authoritativePlan.map {
                        ConversationRoutingRecipient(profile: $0.profile)
                    },
                    observedHeadRoutingEpoch: assignment.headRoutingEpoch,
                    observedRoomMessageSequence: max(0, room.nextMessageSequence - 1)
                )
                try submissionRouting.validate()
                let planned = try authoritativePlan.enumerated().map {
                    selectionIndex, participant -> PlannedExecution in
                    guard let executor = preflightExecutors[participant.id],
                          executor.binding == participant.profile.runtimeBinding
                    else {
                        throw ConversationParticipantInvocationError.unavailable(
                            "\(participant.profile.displayName)’s runtime changed before acceptance. Nothing was sent."
                        )
                    }
                    let runID = UUID()
                    return PlannedExecution(
                        participant: participant,
                        executor: executor,
                        runID: runID,
                        attribution: ConversationParticipantRunAttribution(
                            invocationID: request.id,
                            runID: runID,
                            participantID: participant.id,
                            profileID: participant.profile.id,
                            displayName: participant.profile.displayName,
                            participantRole: participant.role,
                            selectionSequence: selectionIndex + 1
                        )
                    )
                }
                guard let first = planned.first else {
                    throw ConversationParticipantInvocationError.invalid(
                        "At least one participant execution is required."
                    )
                }
                let previousMessageID = try repository.continuationParentMessageID(
                    roomID: request.roomID,
                    assignment: assignment
                )
                let userMessage = try repository.upsertMessage(.init(
                    roomID: request.roomID,
                    parentMessageID: previousMessageID,
                    role: "user",
                    contentText: request.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                    status: .complete,
                    finishReason: .stop,
                    source: .init(
                        namespace: AgentRoomsParticipantService.submissionSourceNamespace,
                        id: request.id.uuidString
                    ),
                    sourceCreatedAt: acceptedAt,
                    metadata: [
                        "authority": AgentRoomsParticipantService.participantAuthority,
                        "schema_version": "1",
                        AgentRoomsConversationPersistence.submissionRoutingMetadataKey:
                            try AgentRoomsParticipantService.encoded(submissionRouting),
                        AgentRoomsParticipantService.messageAttributionMetadataKey:
                            try AgentRoomsParticipantService.encoded(
                                ConversationParticipantMessageAttribution(
                                    invocationID: request.id,
                                    runID: nil,
                                    participantID: nil,
                                    profileID: nil,
                                    participantRole: nil
                                )
                            ),
                    ],
                    createdAt: acceptedAt
                ), intent: .historicalReplay).message
                _ = try repository.recordRoutingAcceptance(
                    roomID: request.roomID,
                    record: ConversationRoutingAcceptanceRecord(
                        userMessageID: userMessage.id,
                        sourceNamespace: AgentRoomsParticipantService.submissionSourceNamespace,
                        routing: submissionRouting
                    ),
                    at: acceptedAt
                )
                let routing = ConversationGeneratedRoutingContext(
                    recipient: ConversationRoutingRecipient(profile: first.participant.profile),
                    observedHeadRoutingEpoch: submissionRouting.observedHeadRoutingEpoch,
                    observedRoomMessageSequence: submissionRouting.observedRoomMessageSequence,
                    originatingUserMessageID: userMessage.id
                )
                try routing.validate()
                let turn = try beginParticipantTurn(
                    roomID: request.roomID,
                    runID: first.runID,
                    attribution: first.attribution,
                    routing: routing,
                    at: acceptedAt
                )
                return AcceptedInvocation(
                    userMessage: userMessage,
                    firstTurn: turn,
                    submissionRouting: submissionRouting,
                    executions: planned
                )
            }
        } catch let error as CiderDatabaseError where error.isBusyConflict {
            throw ConversationParticipantInvocationError.conflict(
                "Participant acceptance conflicted with another room update. Nothing was sent."
            )
        }

        let userMessage = accepted.userMessage
        let firstTurn = accepted.firstTurn
        let submissionRouting = accepted.submissionRouting
        let planned = accepted.executions
        var results: [ConversationParticipantRunResult] = []
        var activitySequence = 0
        for (selectionIndex, entry) in planned.enumerated() {
            if cancellationRequested.contains(request.id) { break }
            let participant = entry.participant
            let executor = entry.executor
            let runID = entry.runID
            let attribution = entry.attribution
            let generatedRouting = ConversationGeneratedRoutingContext(
                recipient: ConversationRoutingRecipient(profile: participant.profile),
                observedHeadRoutingEpoch: submissionRouting.observedHeadRoutingEpoch,
                observedRoomMessageSequence: submissionRouting.observedRoomMessageSequence,
                originatingUserMessageID: userMessage.id
            )
            try generatedRouting.validate()
            let turn = selectionIndex == 0
                ? firstTurn
                : try repository.withImmediateTransaction {
                    try beginParticipantTurn(
                        roomID: request.roomID,
                        runID: runID,
                        attribution: attribution,
                        routing: generatedRouting,
                        at: now()
                    )
                }
            active[request.id] = ActiveExecution(
                executionID: runID,
                roomID: request.roomID,
                executor: executor
            )
            do {
                let output = try await executor.execute(.init(
                    invocationID: request.id,
                    runID: runID,
                    roomID: request.roomID,
                    participant: participant,
                    prompt: request.prompt,
                    limits: request.limits
                ))
                if cancellationRequested.contains(request.id) {
                    try repository.withImmediateTransaction {
                        _ = try repository.transitionTurn(id: turn.id, to: .cancelled, at: now())
                    }
                    results.append(.init(runID: runID, participantID: participant.id, status: .cancelled))
                    active.removeValue(forKey: request.id)
                    break
                }
                let normalized = try validatedOutput(output, limits: request.limits)
                var activities: [ConversationParticipantActivity] = []
                for update in normalized.updates {
                    activitySequence += 1
                    activities.append(.init(
                        id: UUID(),
                        invocationID: request.id,
                        runID: runID,
                        participantID: participant.id,
                        sequence: activitySequence,
                        kind: update.kind,
                        summary: update.summary
                    ))
                }
                let completedAt = now()
                try repository.withImmediateTransaction {
                    var turnMetadata = try participantTurnMetadata(
                        attribution: attribution,
                        routing: generatedRouting,
                        sourceCreatedAt: turn.createdAt
                    )
                    turnMetadata[AgentRoomsParticipantService.activityMetadataKey] =
                        try AgentRoomsParticipantService.encoded(activities)
                    turnMetadata[AgentRoomsParticipantService.runtimeSourceMetadataKey] =
                        try AgentRoomsParticipantService.encoded(normalized.source)
                    _ = try repository.bindActiveTurnExecution(
                        id: turn.id,
                        runtimeBindingID: nil,
                        source: .init(
                            namespace: AgentRoomsParticipantService.runSourceNamespace,
                            id: runID.uuidString
                        ),
                        metadata: turnMetadata,
                        at: completedAt
                    )
                    _ = try repository.upsertMessage(.init(
                        roomID: request.roomID,
                        turnID: turn.id,
                        parentMessageID: userMessage.id,
                        role: "assistant",
                        contentText: normalized.text,
                        status: .complete,
                        finishReason: .stop,
                        source: .init(
                            namespace: AgentRoomsParticipantService.runSourceNamespace,
                            id: "\(runID.uuidString):assistant"
                        ),
                        sourceCreatedAt: completedAt,
                        metadata: [
                            "authority": AgentRoomsParticipantService.participantAuthority,
                            "schema_version": "1",
                            AgentRoomsConversationPersistence.generatedRoutingMetadataKey:
                                try AgentRoomsParticipantService.encoded(generatedRouting),
                            AgentRoomsParticipantService.runtimeSourceMetadataKey:
                                try AgentRoomsParticipantService.encoded(normalized.source),
                            AgentRoomsParticipantService.messageAttributionMetadataKey:
                                try AgentRoomsParticipantService.encoded(
                                    ConversationParticipantMessageAttribution(
                                        invocationID: request.id,
                                        runID: runID,
                                        participantID: participant.id,
                                        profileID: participant.profile.id,
                                        displayName: participant.profile.displayName,
                                        participantRole: participant.role
                                    )
                                ),
                        ],
                        createdAt: completedAt
                    ), intent: .historicalReplay)
                    _ = try repository.transitionTurn(
                        id: turn.id,
                        to: .completed,
                        at: completedAt
                    )
                    try repository.advanceRoomActivity(
                        roomID: request.roomID,
                        at: completedAt
                    )
                }
                results.append(.init(runID: runID, participantID: participant.id, status: .completed))
            } catch is CancellationError {
                try repository.withImmediateTransaction {
                    _ = try repository.transitionTurn(id: turn.id, to: .cancelled, at: now())
                }
                results.append(.init(runID: runID, participantID: participant.id, status: .cancelled))
                active.removeValue(forKey: request.id)
                break
            } catch {
                if cancellationRequested.contains(request.id) {
                    try repository.withImmediateTransaction {
                        _ = try repository.transitionTurn(id: turn.id, to: .cancelled, at: now())
                    }
                    results.append(.init(runID: runID, participantID: participant.id, status: .cancelled))
                } else {
                    try repository.withImmediateTransaction {
                        _ = try repository.transitionTurn(
                            id: turn.id,
                            to: .failed,
                            error: .init(
                                code: "participant_execution_failed",
                                detail: boundedError(error)
                            ),
                            at: now()
                        )
                    }
                    results.append(.init(runID: runID, participantID: participant.id, status: .failed))
                }
                active.removeValue(forKey: request.id)
                break
            }
            active.removeValue(forKey: request.id)
        }
        active.removeValue(forKey: request.id)
        cancellationRequested.remove(request.id)
        try repository.advanceRoomActivity(roomID: request.roomID, at: now())
        return .init(invocationID: request.id, roomID: request.roomID, runs: results)
    }

    func cancel(invocationID: UUID) async {
        guard let execution = active[invocationID] else { return }
        cancellationRequested.insert(invocationID)
        await execution.executor.cancel(executionID: execution.executionID)
    }

    private func beginParticipantTurn(
        roomID: UUID,
        runID: UUID,
        attribution: ConversationParticipantRunAttribution,
        routing: ConversationGeneratedRoutingContext,
        at date: Date
    ) throws -> ConversationTurn {
        try repository.beginTurn(.init(
            id: runID,
            roomID: roomID,
            source: .init(
                namespace: AgentRoomsParticipantService.runSourceNamespace,
                id: runID.uuidString
            ),
            status: .running,
            metadata: try participantTurnMetadata(
                attribution: attribution,
                routing: routing,
                sourceCreatedAt: date
            ),
            createdAt: date
        ))
    }

    private func participantTurnMetadata(
        attribution: ConversationParticipantRunAttribution,
        routing: ConversationGeneratedRoutingContext,
        sourceCreatedAt: Date
    ) throws -> [String: String] {
        [
            "authority": AgentRoomsParticipantService.participantAuthority,
            "schema_version": "1",
            "source_created_at": String(sourceCreatedAt.timeIntervalSince1970),
            AgentRoomsParticipantService.runAttributionMetadataKey:
                try AgentRoomsParticipantService.encoded(attribution),
            AgentRoomsConversationPersistence.generatedRoutingMetadataKey:
                try AgentRoomsParticipantService.encoded(routing),
        ]
    }

    private func validatedOutput(
        _ output: ConversationParticipantExecutionResult,
        limits: ConversationParticipantInvocationLimits
    ) throws -> ConversationParticipantExecutionResult {
        let text = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= limits.maximumOutputCharactersPerParticipant,
              output.updates.count <= limits.maximumUpdatesPerParticipant,
              !output.source.namespace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !output.source.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw ConversationParticipantInvocationError.invalid(
                "Participant output exceeded the bounded response contract."
            )
        }
        for update in output.updates {
            guard update.summary == update.summary.trimmingCharacters(in: .whitespacesAndNewlines),
                  !update.summary.isEmpty,
                  update.summary.count <= 240,
                  !update.summary.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            else {
                throw ConversationParticipantInvocationError.invalid(
                    "Participant activity must be bounded, trimmed, and display-safe."
                )
            }
        }
        return .init(text: text, source: output.source, updates: output.updates)
    }

    private func boundedError(_ error: Error) -> String {
        String((error as? LocalizedError)?.errorDescription?.prefix(240) ?? "Participant execution failed.")
    }
}
