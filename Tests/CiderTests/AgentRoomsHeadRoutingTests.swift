import Foundation
import Testing
@testable import Cider

@Suite("Agent Rooms Head Routing Tests")
@MainActor
struct AgentRoomsHeadRoutingTests {
    @Test("explicit recipient and observed routing version survive physical reopen")
    func explicitRecipientSurvivesPhysicalReopen() throws {
        let url = disposableDatabaseURL()
        defer { removeDatabase(at: url) }
        let hermes = try profile(id: "hermes", displayName: "Hermes")
        let catalog = try ConversationAgentProfileCatalog(
            profiles: [hermes],
            defaultProfileID: hermes.id
        )

        let database = CiderDatabase()
        try database.open(at: url)
        let repository = ConversationRepository(database: database)
        let assignments = AgentRoomsAgentAssignmentService(repository: repository, catalog: catalog)
        let room = try AgentRoomsActionService(
            repository: repository,
            agentAssignments: assignments
        ).createConversation(title: "Durable routing")
        let persistence = AgentRoomsConversationPersistence(
            database: database,
            repository: repository,
            defaultAgentProfile: hermes,
            participantProfiles: catalog.profiles
        )
        let attempt = try persistence.beginAttempt(
            roomID: room.id,
            roomTitle: room.title,
            isReservedTestChat: false,
            attemptID: UUID(),
            clientMessageID: "cider-room-client:routing-reopen",
            userMessageID: UUID(),
            assistantMessageID: UUID(),
            text: "Keep the intended recipient",
            at: Date(timeIntervalSince1970: 1_806_000_000)
        )
        try persistence.markRunStarted(
            attempt,
            runID: "run-routing-reopen",
            activity: [],
            at: Date(timeIntervalSince1970: 1_806_000_001)
        )
        try persistence.terminate(
            attempt,
            status: .cancelled,
            runID: "run-routing-reopen",
            partialAssistantText: "Former-head partial",
            activity: [],
            at: Date(timeIntervalSince1970: 1_806_000_002)
        )
        database.close()

        let reopenedDatabase = CiderDatabase()
        try reopenedDatabase.open(at: url)
        defer { reopenedDatabase.close() }
        let reopenedRepository = ConversationRepository(database: reopenedDatabase)
        let reopenedAssignment = try #require(
            try reopenedRepository.agentAssignment(roomID: room.id)
        )
        let messages = try reopenedRepository.messages(roomID: room.id)
        let turn = try #require(try reopenedRepository.turns(roomID: room.id).first)
        let user = try #require(messages.first(where: { $0.role == "user" }))
        let assistant = try #require(messages.first(where: { $0.role == "assistant" }))
        let submission = try decode(
            ConversationSubmissionRoutingContext.self,
            from: user.metadata[AgentRoomsConversationPersistence.submissionRoutingMetadataKey]
        )
        let turnRouting = try decode(
            ConversationGeneratedRoutingContext.self,
            from: turn.metadata[AgentRoomsConversationPersistence.generatedRoutingMetadataKey]
        )
        let responseRouting = try decode(
            ConversationGeneratedRoutingContext.self,
            from: assistant.metadata[AgentRoomsConversationPersistence.generatedRoutingMetadataKey]
        )

        #expect(reopenedAssignment.headRoutingEpoch == 1)
        #expect(submission.recipients == [
            ConversationRoutingRecipient(profileID: hermes.id, displayName: hermes.displayName),
        ])
        #expect(submission.observedHeadRoutingEpoch == 1)
        #expect(submission.observedRoomMessageSequence == 0)
        #expect(turnRouting.recipient.profileID == hermes.id)
        #expect(turnRouting.observedHeadRoutingEpoch == 1)
        #expect(responseRouting == turnRouting)
        #expect(responseRouting.originatingUserMessageID == user.id)
    }

    @Test("head change holds a racing former-head result with durable attribution")
    func headChangeHoldsRacingFormerHeadResult() throws {
        let url = disposableDatabaseURL()
        defer { removeDatabase(at: url) }
        let hermes = try profile(id: "hermes", displayName: "Hermes")
        let codex = try profile(
            id: "codex",
            displayName: "Codex",
            providerID: "openai",
            runtimeID: "codex"
        )
        let catalog = try ConversationAgentProfileCatalog(
            profiles: [hermes, codex],
            defaultProfileID: hermes.id
        )
        let database = CiderDatabase()
        try database.open(at: url)
        defer { database.close() }
        let repository = ConversationRepository(database: database)
        let assignments = AgentRoomsAgentAssignmentService(repository: repository, catalog: catalog)
        let room = try AgentRoomsActionService(
            repository: repository,
            agentAssignments: assignments
        ).createConversation(title: "Routing race")
        let originalRoster = try repository.participantRoster(roomID: room.id)
        let persistence = AgentRoomsConversationPersistence(
            database: database,
            repository: repository,
            defaultAgentProfile: hermes,
            participantProfiles: catalog.profiles
        )
        let initialState = try #require(
            try persistence.restoreCanonicalRoom(id: room.id)?.conversationState
        )
        let attempt = try persistence.beginAttempt(
            roomID: room.id,
            roomTitle: room.title,
            isReservedTestChat: false,
            attemptID: UUID(),
            clientMessageID: "cider-room-client:routing-race",
            userMessageID: UUID(),
            assistantMessageID: UUID(),
            text: "Finish against the observed head",
            at: Date(timeIntervalSince1970: 1_806_100_000)
        )
        try persistence.markRunStarted(
            attempt,
            runID: "run-routing-race",
            activity: [],
            at: Date(timeIntervalSince1970: 1_806_100_001)
        )

        _ = try assignments.assign(profileID: codex.id, roomID: room.id)
        let outcome = try persistence.complete(
            attempt,
            completion: completion(
                state: initialState,
                text: "Finish against the observed head",
                answer: "Late Hermes result",
                runID: "run-routing-race",
                sessionID: "session-routing-race"
            ),
            expectedText: "Finish against the observed head",
            activity: []
        )

        let currentAssignment = try #require(try assignments.assignment(roomID: room.id))
        let messages = try repository.messages(roomID: room.id)
        let eventMessage = try #require(messages.first(where: { $0.role == "system" }))
        let heldMessage = try #require(messages.first(where: { $0.role == "assistant" }))
        let event = try decode(
            ConversationHeadRoutingChangeEvent.self,
            from: eventMessage.metadata[ConversationRepository.headChangeEventMetadataKey]
        )
        let heldRouting = try decode(
            ConversationGeneratedRoutingContext.self,
            from: heldMessage.metadata[AgentRoomsConversationPersistence.generatedRoutingMetadataKey]
        )
        let reopened = try #require(try persistence.restoreCanonicalRoom(id: room.id))

        #expect(outcome == .heldStale)
        #expect(currentAssignment.profile.id == codex.id)
        #expect(currentAssignment.headRoutingEpoch == 2)
        #expect(event.oldHead?.profileID == hermes.id)
        #expect(event.newHead.profileID == codex.id)
        #expect(event.oldHeadRoutingEpoch == 1)
        #expect(event.newHeadRoutingEpoch == 2)
        #expect(event.actor == .user)
        #expect(try repository.participantRoster(roomID: room.id) == originalRoster)
        #expect(heldMessage.status == .incomplete)
        #expect(heldMessage.finishReason == .other)
        #expect(
            heldMessage.metadata[AgentRoomsConversationPersistence.publicationStateMetadataKey]
                == "held_stale"
        )
        #expect(heldRouting.recipient.profileID == hermes.id)
        #expect(heldRouting.observedHeadRoutingEpoch == 1)
        #expect(try repository.turns(roomID: room.id).last?.error?.code == "stale_head_routing_epoch")
        #expect(reopened.presentationMessages.last?.author == "Hermes")
        #expect(reopened.presentationMessages.last?.deliveryState == .held)
        #expect(reopened.transportMessages.allSatisfy { $0.content != "Late Hermes result" })
    }

    @Test("legacy assignment reopens at epoch zero and migrates on explicit head change")
    func legacyAssignmentMigratesOnHeadChange() throws {
        let url = disposableDatabaseURL()
        defer { removeDatabase(at: url) }
        let hermes = try profile(id: "hermes", displayName: "Hermes")
        let codex = try profile(
            id: "codex",
            displayName: "Codex",
            providerID: "openai",
            runtimeID: "codex"
        )
        let catalog = try ConversationAgentProfileCatalog(
            profiles: [hermes, codex],
            defaultProfileID: hermes.id
        )
        let database = CiderDatabase()
        try database.open(at: url)
        let repository = ConversationRepository(database: database)
        let room = try repository.createRoom(.init(
            title: "Legacy assignment",
            metadata: [
                "authority": AgentRoomsConversationPersistence.nativeRoomAuthority,
                "schema_version": "1",
            ]
        ))
        let legacy = LegacyAssignment(
            schemaVersion: 1,
            profile: hermes,
            assignedAt: Date(timeIntervalSince1970: 1_805_000_000)
        )
        var metadata = room.metadata
        metadata[ConversationRepository.agentAssignmentMetadataKey] = DatabaseHelpers.encodeJSON(legacy)
        let statement = try database.prepare("""
            UPDATE conversation_rooms SET metadata_json = ? WHERE id = ?;
            """)
        statement.bind(DatabaseHelpers.encodeJSON(metadata), at: 1)
            .bind(room.id.uuidString, at: 2)
        try statement.step()
        database.close()

        let reopenedDatabase = CiderDatabase()
        try reopenedDatabase.open(at: url)
        defer { reopenedDatabase.close() }
        let reopenedRepository = ConversationRepository(database: reopenedDatabase)
        let assignments = AgentRoomsAgentAssignmentService(
            repository: reopenedRepository,
            catalog: catalog
        )
        let legacyRead = try #require(try assignments.assignment(roomID: room.id))
        #expect(legacyRead.schemaVersion == 1)
        #expect(legacyRead.headRoutingEpoch == 0)

        let migrated = try assignments.assign(profileID: codex.id, roomID: room.id)
        let eventMessage = try #require(
            try reopenedRepository.messages(roomID: room.id).first(where: { $0.role == "system" })
        )
        let event = try decode(
            ConversationHeadRoutingChangeEvent.self,
            from: eventMessage.metadata[ConversationRepository.headChangeEventMetadataKey]
        )

        #expect(migrated.schemaVersion == ConversationRoomAgentAssignment.schemaVersion)
        #expect(migrated.headRoutingEpoch == 1)
        #expect(event.oldHeadRoutingEpoch == 0)
        #expect(event.newHeadRoutingEpoch == 1)
    }

    @Test("retry preserves the accepted submission routing after a head change")
    func retryPreservesAcceptedSubmissionRouting() throws {
        let hermes = try profile(id: "hermes", displayName: "Hermes")
        let codex = try profile(
            id: "codex",
            displayName: "Codex",
            providerID: "openai",
            runtimeID: "codex"
        )
        let catalog = try ConversationAgentProfileCatalog(
            profiles: [hermes, codex],
            defaultProfileID: hermes.id
        )
        let url = disposableDatabaseURL()
        defer { removeDatabase(at: url) }
        let database = CiderDatabase()
        try database.open(at: url)
        defer { database.close() }
        let repository = ConversationRepository(database: database)
        let assignments = AgentRoomsAgentAssignmentService(repository: repository, catalog: catalog)
        let room = try AgentRoomsActionService(
            repository: repository,
            agentAssignments: assignments
        ).createConversation(title: "Retry routing")
        let persistence = AgentRoomsConversationPersistence(
            database: database,
            repository: repository,
            defaultAgentProfile: hermes,
            participantProfiles: catalog.profiles
        )
        let initialState = try #require(
            try persistence.restoreCanonicalRoom(id: room.id)?.conversationState
        )
        let attemptID = UUID()
        let userMessageID = UUID()
        let assistantMessageID = UUID()
        let clientMessageID = "cider-room-client:routing-retry"
        let createdAt = Date(timeIntervalSince1970: 1_806_050_000)
        do {
            _ = try persistence.beginAttempt(
                roomID: room.id,
                roomTitle: room.title,
                isReservedTestChat: false,
                attemptID: attemptID,
                clientMessageID: clientMessageID,
                userMessageID: userMessageID,
                assistantMessageID: assistantMessageID,
                text: "Retry against accepted routing",
                at: createdAt
            )
        } catch {
            Issue.record("Initial attempt failed: \(error)")
            throw error
        }
        let acceptedTurn = try #require(
            try repository.turns(roomID: room.id).first(where: { $0.id == attemptID })
        )
        var acceptedMetadata = acceptedTurn.metadata
        let acceptedRouting = try #require(
            acceptedMetadata[AgentRoomsConversationPersistence.generatedRoutingMetadataKey]
        )
        let acceptedRoutingObject = try JSONSerialization.jsonObject(
            with: Data(acceptedRouting.utf8)
        )
        let reformattedRoutingData = try JSONSerialization.data(
            withJSONObject: acceptedRoutingObject,
            options: [.prettyPrinted, .sortedKeys]
        )
        let reformattedRouting = try #require(
            String(data: reformattedRoutingData, encoding: .utf8)
        )
        #expect(reformattedRouting != acceptedRouting)
        acceptedMetadata[AgentRoomsConversationPersistence.generatedRoutingMetadataKey]
            = reformattedRouting
        let encodedAcceptedMetadata: String? = DatabaseHelpers.encodeJSON(acceptedMetadata)
        let metadataStatement = try database.prepare("""
            UPDATE conversation_turns SET metadata_json = ? WHERE id = ?;
            """)
        metadataStatement.bind(
            try #require(encodedAcceptedMetadata),
            at: 1
        ).bind(attemptID.uuidString, at: 2)
        try metadataStatement.step()

        do {
            _ = try assignments.assign(profileID: codex.id, roomID: room.id)
        } catch {
            Issue.record("Head change failed: \(error)")
            throw error
        }

        let retry: AgentRoomsConversationAttempt
        do {
            retry = try persistence.beginAttempt(
                roomID: room.id,
                roomTitle: room.title,
                isReservedTestChat: false,
                attemptID: attemptID,
                clientMessageID: clientMessageID,
                userMessageID: userMessageID,
                assistantMessageID: assistantMessageID,
                text: "Retry against accepted routing",
                at: createdAt
            )
        } catch {
            Issue.record("Retry attempt failed: \(error)")
            throw error
        }
        let outcome: ConversationResultPublicationOutcome
        do {
            outcome = try persistence.complete(
                retry,
                completion: completion(
                    state: initialState,
                    text: "Retry against accepted routing",
                    answer: "Late retried Hermes result",
                    runID: "run-routing-retry",
                    sessionID: "session-routing-retry"
                ),
                expectedText: "Retry against accepted routing",
                activity: []
            )
        } catch {
            Issue.record("Retry completion failed: \(error)")
            throw error
        }

        #expect(retry.routingContext.recipient.profileID == hermes.id)
        #expect(retry.routingContext.observedHeadRoutingEpoch == 1)
        #expect(outcome == .heldStale)
    }

    @Test("explicit participant success remains complete when the default head changes")
    func participantRunCompletesAfterHeadChange() async throws {
        let actor = try profile(id: "cider", displayName: "Cider")
        let nextHead = try profile(id: "research", displayName: "Research")
        let catalog = try ConversationAgentProfileCatalog(
            profiles: [actor, nextHead],
            defaultProfileID: actor.id
        )
        let url = disposableDatabaseURL()
        defer { removeDatabase(at: url) }
        let database = CiderDatabase()
        try database.open(at: url)
        defer { database.close() }
        let repository = ConversationRepository(database: database)
        let assignments = AgentRoomsAgentAssignmentService(repository: repository, catalog: catalog)
        let room = try AgentRoomsActionService(
            repository: repository,
            agentAssignments: assignments
        ).createConversation(title: "Participant routing race")
        let participants = AgentRoomsParticipantService(repository: repository, catalog: catalog)
        let roster = try #require(try participants.roster(roomID: room.id))
        let actorID = try #require(
            roster.members.first(where: { $0.profile.id == actor.id })?.id
        )
        let runtime = HeadRoutingGateRuntime(binding: actor.runtimeBinding)
        let invocations = AgentRoomsParticipantInvocationService(
            repository: repository,
            participants: participants,
            runtimes: try ConversationParticipantRuntimeRegistry(executors: [runtime])
        )

        let task = Task {
            try await invocations.invoke(.init(
                roomID: room.id,
                prompt: "Finish after the switch",
                selectedParticipantIDs: [actorID],
                origin: .user,
                limits: .checkpoint
            ))
        }
        await runtime.waitUntilStarted()
        _ = try assignments.assign(profileID: nextHead.id, roomID: room.id)
        await runtime.release()
        let result = try await task.value
        let assistant = try #require(
            try repository.messages(roomID: room.id).first(where: { $0.role == "assistant" })
        )
        let routing = try decode(
            ConversationGeneratedRoutingContext.self,
            from: assistant.metadata[AgentRoomsConversationPersistence.generatedRoutingMetadataKey]
        )

        #expect(result.runs.map(\.status) == [.completed])
        #expect(assistant.status == .complete)
        #expect(assistant.finishReason == .stop)
        #expect(assistant.metadata[AgentRoomsConversationPersistence.publicationStateMetadataKey] == nil)
        #expect(routing.recipient.profileID == actor.id)
        #expect(try repository.turns(roomID: room.id).last?.status == .completed)
        #expect(try repository.turns(roomID: room.id).last?.error == nil)
    }

    @Test("reselecting the unchanged head is an epoch and event no-op")
    func unchangedHeadIsNoOp() throws {
        let hermes = try profile(id: "hermes", displayName: "Hermes")
        let catalog = try ConversationAgentProfileCatalog(
            profiles: [hermes],
            defaultProfileID: hermes.id
        )
        let url = disposableDatabaseURL()
        defer { removeDatabase(at: url) }
        let database = CiderDatabase()
        try database.open(at: url)
        defer { database.close() }
        let repository = ConversationRepository(database: database)
        let assignments = AgentRoomsAgentAssignmentService(repository: repository, catalog: catalog)
        let room = try AgentRoomsActionService(
            repository: repository,
            agentAssignments: assignments
        ).createConversation(title: "Unchanged head")
        let originalRoster = try repository.participantRoster(roomID: room.id)

        let assignment = try assignments.assign(profileID: hermes.id, roomID: room.id)

        #expect(assignment.headRoutingEpoch == 1)
        #expect(try repository.messages(roomID: room.id).isEmpty)
        #expect(try repository.participantRoster(roomID: room.id) == originalRoster)
    }

    private func profile(
        id: String,
        displayName: String,
        providerID: String = "local",
        runtimeID: String = "runtime"
    ) throws -> ConversationAgentProfile {
        try ConversationAgentProfile.validated(
            id: id,
            displayName: displayName,
            runtimeBinding: .init(providerID: providerID, runtimeID: runtimeID),
            capabilities: [
                .init(id: "text-chat", displayName: "Text chat"),
                .init(id: "cancel", displayName: "Cancel"),
            ],
            availability: .available
        )
    }

    private func completion(
        state: HermesConversationState,
        text: String,
        answer: String,
        runID: String,
        sessionID: String
    ) -> HermesRunCompletionEnvelope {
        let timestamp = Date(timeIntervalSince1970: 1_806_100_002)
        let userSourceID = "hermes-run:\(runID):user"
        let assistantSourceID = "hermes-run:\(runID):assistant"
        let user = AIAssistantMessage(
            role: .user,
            content: text,
            timestamp: timestamp,
            sourceID: userSourceID,
            sourceSessionID: sessionID,
            sourceName: "Hermes"
        )
        let assistant = AIAssistantMessage(
            role: .assistant,
            content: answer,
            timestamp: timestamp,
            sourceID: assistantSourceID,
            sourceSessionID: sessionID,
            sourceName: "Hermes"
        )
        var finalState = state
        finalState.activeRuntimeSessionID = sessionID
        finalState.runtimeSessionLineage.append(sessionID)
        finalState.lastSyncedAt = timestamp
        finalState.lastSyncedMessageID = assistantSourceID
        finalState.lastSyncedTimestamp = timestamp
        finalState.lastImportedRuntimeSessionID = sessionID
        return HermesRunCompletionEnvelope(
            provenance: .hermesRunsAPI,
            runID: runID,
            terminalStatus: .completed,
            observedFacts: .none,
            finalSessionSynchronizationComplete: true,
            finalMessages: [user, assistant],
            finalState: finalState,
            modelIdentity: "fake-hermes",
            terminalSourceEvidence: .init(
                reportedTerminalRunID: runID,
                userSourceID: userSourceID,
                assistantSourceID: assistantSourceID,
                userSourceSessionID: sessionID,
                assistantSourceSessionID: sessionID
            )
        )
    }

    private func decode<T: Decodable>(_ type: T.Type, from raw: String?) throws -> T {
        let raw = try #require(raw)
        return try JSONDecoder().decode(type, from: Data(raw.utf8))
    }

    private func disposableDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-head-routing-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
    }

    private func removeDatabase(at url: URL) {
        let manager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? manager.removeItem(atPath: url.path + suffix)
        }
    }

    private struct LegacyAssignment: Encodable {
        let schemaVersion: Int
        let profile: ConversationAgentProfile
        let assignedAt: Date
    }
}

private actor HeadRoutingGateRuntime: ConversationParticipantRuntimeExecuting {
    let binding: ConversationAgentRuntimeBinding
    private var started = false
    private var released = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(binding: ConversationAgentRuntimeBinding) {
        self.binding = binding
    }

    func execute(
        _ request: ConversationParticipantExecutionRequest
    ) async throws -> ConversationParticipantExecutionResult {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        if !released {
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
        return ConversationParticipantExecutionResult(
            text: "Late participant result",
            source: .init(namespace: "cider.tests.routing", id: request.runID.uuidString),
            updates: []
        )
    }

    func cancel(executionID: UUID) async {}

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}
