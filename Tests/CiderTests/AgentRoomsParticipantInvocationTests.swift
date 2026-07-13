import Foundation
import Testing
@testable import Cider

@Suite("Agent Rooms Participant Invocation Tests")
@MainActor
struct AgentRoomsParticipantInvocationTests {
    @Test("two explicitly selected named participants keep deterministic attribution across reopen")
    func explicitParticipantsPersistAcrossReopen() async throws {
        let url = disposableDatabaseURL()
        defer { removeDatabase(at: url) }
        let actor = try profile(id: "cider", displayName: "Cider")
        let advisor = try profile(id: "research", displayName: "Research")
        let catalog = try ConversationAgentProfileCatalog(
            profiles: [actor, advisor],
            defaultProfileID: actor.id
        )
        let invocationID = UUID(uuidString: "82700000-0000-0000-0000-000000000001")!

        let database = CiderDatabase()
        try database.open(at: url)
        let repository = ConversationRepository(database: database)
        let assignments = AgentRoomsAgentAssignmentService(repository: repository, catalog: catalog)
        let room = try AgentRoomsActionService(
            repository: repository,
            agentAssignments: assignments
        ).createConversation(title: "Explicit participants")
        let participants = AgentRoomsParticipantService(repository: repository, catalog: catalog)
        let roster = try participants.configureRoster(
            roomID: room.id,
            members: [
                .init(profileID: actor.id, role: .actingAgent),
                .init(profileID: advisor.id, role: .advisor),
            ]
        )
        let actorID = try #require(roster.members.first(where: { $0.profile.id == actor.id })?.id)
        let advisorID = try #require(roster.members.first(where: { $0.profile.id == advisor.id })?.id)
        let actorRuntime = ParticipantProbeRuntime(
            binding: actor.runtimeBinding,
            response: "Cider answer",
            update: "Cider checked the request"
        )
        let advisorRuntime = ParticipantProbeRuntime(
            binding: advisor.runtimeBinding,
            response: "Research answer",
            update: "Research reviewed the evidence"
        )
        let invocations = AgentRoomsParticipantInvocationService(
            repository: repository,
            participants: participants,
            runtimes: try ConversationParticipantRuntimeRegistry(executors: [
                actorRuntime, advisorRuntime,
            ])
        )

        let result = try await invocations.invoke(.init(
            id: invocationID,
            roomID: room.id,
            prompt: "Give both perspectives",
            selectedParticipantIDs: [advisorID, actorID],
            origin: .user,
            limits: .checkpoint
        ))

        #expect(result.runs.map(\.participantID) == [actorID, advisorID])
        #expect(result.runs.map(\.status) == [.completed, .completed])
        #expect(await actorRuntime.executionCount() == 1)
        #expect(await advisorRuntime.executionCount() == 1)
        _ = try repository.upsertRuntimeBinding(.init(
            roomID: room.id,
            runtimeID: "local-router",
            transportID: "participant-test",
            sourceNamespace: "cider.tests.participant-runtime",
            externalSessionID: "session-one"
        ))
        database.close()

        let reopenedDatabase = CiderDatabase()
        try reopenedDatabase.open(at: url)
        defer { reopenedDatabase.close() }
        let reopenedRepository = ConversationRepository(database: reopenedDatabase)
        let reopenedParticipants = AgentRoomsParticipantService(
            repository: reopenedRepository,
            catalog: catalog
        )
        _ = try reopenedRepository.upsertRuntimeBinding(.init(
            roomID: room.id,
            runtimeID: "local-router",
            transportID: "participant-test",
            sourceNamespace: "cider.tests.participant-runtime",
            externalSessionID: "session-two"
        ))
        let reopenedRoster = try #require(try reopenedParticipants.roster(roomID: room.id))
        let messages = try reopenedRepository.messages(roomID: room.id)
        let turns = try reopenedRepository.turns(roomID: room.id)
        let attributedMessages = try messages.map {
            ($0.contentText, try reopenedParticipants.messageAttribution($0))
        }
        let attributedTurns = try turns.map {
            try reopenedParticipants.turnAttribution($0)
        }
        let activity = try reopenedParticipants.activity(roomID: room.id, invocationID: invocationID)

        #expect(reopenedRoster == roster)
        #expect(messages.map(\.sequence) == [1, 2, 3])
        #expect(attributedMessages.map(\.0) == [
            "Give both perspectives", "Cider answer", "Research answer",
        ])
        #expect(attributedMessages.compactMap { $0.1?.participantID } == [actorID, advisorID])
        #expect(attributedTurns.compactMap { $0?.participantID } == [actorID, advisorID])
        #expect(attributedTurns.compactMap { $0?.runID } == result.runs.map(\.runID))
        #expect(activity.map(\.sequence) == [1, 2])
        #expect(activity.map(\.participantID) == [actorID, advisorID])
        #expect(activity.map(\.summary) == [
            "Cider checked the request", "Research reviewed the evidence",
        ])
        #expect(try reopenedRepository.bindings(roomID: room.id).compactMap(\.externalSessionID) == [
            "session-one", "session-two",
        ])

        let reopenedAssignments = AgentRoomsAgentAssignmentService(
            repository: reopenedRepository,
            catalog: catalog
        )
        let workspace = AgentRoomsReadService(
            repository: reopenedRepository,
            agentAssignments: reopenedAssignments,
            participants: reopenedParticipants
        ).loadWorkspace()
        guard case .loaded(_, let rooms, _) = workspace else {
            Issue.record("Expected attributed canonical room presentation")
            return
        }
        let presented = try #require(rooms.first(where: { $0.id == room.id.uuidString }))
        #expect(presented.participantRoster?.members.map(\.displayName) == ["Cider", "Research"])
        #expect(presented.transcript.messages.map(\.author) == ["You", "Cider", "Research"])
        #expect(presented.participantActivity?.participantCount == 2)
        #expect(presented.participantActivity?.updateCount == 2)
        #expect(presented.participantActivity?.updates.map(\.summary) == activity.map(\.summary))

        let exported = try AgentRoomsRoomExportService(repository: reopenedRepository).render(
            roomID: room.id
        )
        let manifest = try JSONDecoder().decode(
            AgentRoomsRoomExportManifest.self,
            from: exported.manifestData
        )
        #expect(manifest.schemaVersion == 2)
        #expect(manifest.participants.map(\.displayName) == ["Cider", "Research"])
        #expect(manifest.turns.compactMap(\.participantAttribution?.participantID) == [
            actorID, advisorID,
        ])
        #expect(manifest.turns.flatMap(\.participantActivity).map(\.summary) == activity.map(\.summary))
        #expect(manifest.messages.compactMap(\.participantAttribution?.participantID) == [
            actorID, advisorID,
        ])
        #expect(exported.markdown.contains("### Cider"))
        #expect(exported.markdown.contains("### Research"))
        #expect(!String(decoding: exported.manifestData, as: UTF8.self).contains("session-one"))
        #expect(!String(decoding: exported.manifestData, as: UTF8.self).contains("session-two"))
    }

    @Test("participant-origin and unavailable runtime fail before durable acceptance")
    func noAutonomousLoopOrUnavailableFallback() async throws {
        try await withRepository { repository in
            let actor = try profile(id: "cider", displayName: "Cider")
            let unavailable = try profile(
                id: "codex",
                displayName: "Codex",
                providerID: "openai",
                runtimeID: "codex",
                availability: .unavailable(reason: "Codex is not connected.")
            )
            let catalog = try ConversationAgentProfileCatalog(
                profiles: [actor, unavailable],
                defaultProfileID: actor.id
            )
            let assignments = AgentRoomsAgentAssignmentService(repository: repository, catalog: catalog)
            let room = try AgentRoomsActionService(
                repository: repository,
                agentAssignments: assignments
            ).createConversation(title: "No loops")
            let participants = AgentRoomsParticipantService(repository: repository, catalog: catalog)
            let roster = try participants.configureRoster(
                roomID: room.id,
                members: [
                    .init(profileID: actor.id, role: .actingAgent),
                    .init(profileID: unavailable.id, role: .advisor),
                ]
            )
            let actorID = roster.members[0].id
            let unavailableID = roster.members[1].id
            let runtime = ParticipantProbeRuntime(
                binding: actor.runtimeBinding,
                response: "Should not run",
                update: "Should not persist"
            )
            let invocations = AgentRoomsParticipantInvocationService(
                repository: repository,
                participants: participants,
                runtimes: try ConversationParticipantRuntimeRegistry(executors: [runtime])
            )

            await #expect(throws: ConversationParticipantInvocationError.self) {
                try await invocations.invoke(.init(
                    roomID: room.id,
                    prompt: "Agent-triggered follow-up",
                    selectedParticipantIDs: [actorID],
                    origin: .participant(actorID),
                    limits: .checkpoint
                ))
            }
            await #expect(throws: ConversationParticipantInvocationError.self) {
                try await invocations.invoke(.init(
                    roomID: room.id,
                    prompt: "Try both",
                    selectedParticipantIDs: [actorID, unavailableID],
                    origin: .user,
                    limits: .checkpoint
                ))
            }

            #expect(await runtime.executionCount() == 0)
            #expect(try repository.turns(roomID: room.id).isEmpty)
            #expect(try repository.messages(roomID: room.id).isEmpty)
        }
    }

    @Test("cancellation terminates one active run and never starts the next participant")
    func cancellationIsBoundedAndOrdered() async throws {
        try await withRepository { repository in
            let actor = try profile(id: "cider", displayName: "Cider")
            let advisor = try profile(id: "research", displayName: "Research")
            let catalog = try ConversationAgentProfileCatalog(
                profiles: [actor, advisor],
                defaultProfileID: actor.id
            )
            let assignments = AgentRoomsAgentAssignmentService(repository: repository, catalog: catalog)
            let room = try AgentRoomsActionService(
                repository: repository,
                agentAssignments: assignments
            ).createConversation(title: "Cancel participants")
            let participants = AgentRoomsParticipantService(repository: repository, catalog: catalog)
            let roster = try participants.configureRoster(
                roomID: room.id,
                members: [
                    .init(profileID: actor.id, role: .actingAgent),
                    .init(profileID: advisor.id, role: .advisor),
                ]
            )
            let blockingRuntime = BlockingParticipantRuntime(binding: actor.runtimeBinding)
            let advisorRuntime = ParticipantProbeRuntime(
                binding: advisor.runtimeBinding,
                response: "Must not start",
                update: "Must not persist"
            )
            let invocations = AgentRoomsParticipantInvocationService(
                repository: repository,
                participants: participants,
                runtimes: try ConversationParticipantRuntimeRegistry(executors: [
                    blockingRuntime, advisorRuntime,
                ])
            )
            let invocationID = UUID()
            let task = Task {
                try await invocations.invoke(.init(
                    id: invocationID,
                    roomID: room.id,
                    prompt: "Stop safely",
                    selectedParticipantIDs: roster.members.map(\.id),
                    origin: .user,
                    limits: .checkpoint
                ))
            }
            while await !blockingRuntime.hasStarted() { await Task.yield() }

            await #expect(throws: ConversationParticipantInvocationError.self) {
                try await invocations.invoke(.init(
                    roomID: room.id,
                    prompt: "Do not overlap",
                    selectedParticipantIDs: [roster.members[0].id],
                    origin: .user,
                    limits: .checkpoint
                ))
            }
            #expect(try repository.turns(roomID: room.id).count == 1)
            #expect(try repository.messages(roomID: room.id).count == 1)

            await invocations.cancel(invocationID: invocationID)
            let result = try await task.value

            #expect(result.runs.map(\.status) == [.cancelled])
            #expect(await blockingRuntime.cancellationCount() == 1)
            #expect(await blockingRuntime.cancelledExecutionMatchesRun())
            #expect(await advisorRuntime.executionCount() == 0)
            #expect(try repository.turns(roomID: room.id).map(\.status) == [.cancelled])
            #expect(try repository.messages(roomID: room.id).map(\.contentText) == ["Stop safely"])
        }
    }

    @Test("participant, concurrency, update, budget, and recursion ceilings fail before acceptance")
    func invocationCeilingsFailClosed() async throws {
        try await withRepository { repository in
            let profiles = try (0..<5).map {
                try profile(id: "participant-\($0)", displayName: "Participant \($0)")
            }
            let catalog = try ConversationAgentProfileCatalog(
                profiles: profiles,
                defaultProfileID: profiles[0].id
            )
            let assignments = AgentRoomsAgentAssignmentService(repository: repository, catalog: catalog)
            let room = try AgentRoomsActionService(
                repository: repository,
                agentAssignments: assignments
            ).createConversation(title: "Bounded invocation")
            let participants = AgentRoomsParticipantService(repository: repository, catalog: catalog)
            let roster = try #require(try participants.roster(roomID: room.id))
            let runtime = ParticipantProbeRuntime(
                binding: profiles[0].runtimeBinding,
                response: "Must not run",
                update: "Must not persist"
            )
            let invocations = AgentRoomsParticipantInvocationService(
                repository: repository,
                participants: participants,
                runtimes: try ConversationParticipantRuntimeRegistry(executors: [runtime])
            )
            let invalidLimits = ConversationParticipantInvocationLimits(
                maximumParticipants: 4,
                maximumConcurrency: 2,
                maximumUpdatesPerParticipant: 25,
                maximumOutputCharactersPerParticipant: 24_001,
                tokenBudgetPerParticipant: 8_001,
                recursionDepth: 1
            )

            await #expect(throws: ConversationParticipantInvocationError.self) {
                try await invocations.invoke(.init(
                    roomID: room.id,
                    prompt: "Reject unsafe limits",
                    selectedParticipantIDs: [roster.members[0].id],
                    origin: .user,
                    limits: invalidLimits
                ))
            }
            await #expect(throws: ConversationParticipantInvocationError.self) {
                try await invocations.invoke(.init(
                    roomID: room.id,
                    prompt: "Reject five participants",
                    selectedParticipantIDs: roster.members.map(\.id),
                    origin: .user,
                    limits: .checkpoint
                ))
            }

            #expect(await runtime.executionCount() == 0)
            #expect(try repository.turns(roomID: room.id).isEmpty)
            #expect(try repository.messages(roomID: room.id).isEmpty)
        }
    }

    @Test("attributed live activity remains bounded and display-safe after reopen")
    func attributedLiveActivityIsPortableAndCalm() throws {
        let url = disposableDatabaseURL()
        defer { removeDatabase(at: url) }
        let profile = try profile(
            id: "hermes",
            displayName: "Hermes",
            providerID: "hermes",
            runtimeID: "hermes"
        )
        let catalog = try ConversationAgentProfileCatalog(
            profiles: [profile],
            defaultProfileID: profile.id
        )
        let database = CiderDatabase()
        try database.open(at: url)
        let repository = ConversationRepository(database: database)
        let assignments = AgentRoomsAgentAssignmentService(repository: repository, catalog: catalog)
        let participants = AgentRoomsParticipantService(repository: repository, catalog: catalog)
        let room = try AgentRoomsActionService(
            repository: repository,
            agentAssignments: assignments
        ).createConversation(title: "Calm attributed activity")
        let participantID = try #require(
            try participants.roster(roomID: room.id)?.actingAgent?.id
        )
        let invocationID = UUID()
        let attribution = ConversationParticipantRunAttribution(
            invocationID: invocationID,
            runID: invocationID,
            participantID: participantID,
            profileID: profile.id,
            participantRole: .actingAgent,
            selectionSequence: 1
        )
        let persistence = AgentRoomsConversationPersistence(
            database: database,
            repository: repository,
            defaultAgentProfile: profile,
            participantProfiles: catalog.profiles
        )
        let attempt = try persistence.beginAttributedAttempt(
            roomID: room.id,
            roomTitle: room.title,
            isReservedTestChat: false,
            attemptID: invocationID,
            clientMessageID: "cider-room-client:\(UUID().uuidString)",
            userMessageID: UUID(),
            assistantMessageID: UUID(),
            text: "Keep activity calm",
            attribution: attribution,
            at: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let activity = AgentRoomsLiveActivity(
            id: UUID(),
            kind: .reasoning,
            detail: "\u{001B}[31mBounded progress\u{001B}[0m"
        )
        try persistence.markRunStarted(
            attempt,
            runID: "hermes-run-827",
            activity: [activity],
            at: Date(timeIntervalSince1970: 1_800_000_001)
        )
        try persistence.terminate(
            attempt,
            status: .cancelled,
            runID: "hermes-run-827",
            partialAssistantText: nil,
            activity: [activity],
            at: Date(timeIntervalSince1970: 1_800_000_002)
        )
        database.close()

        let reopenedDatabase = CiderDatabase()
        try reopenedDatabase.open(at: url)
        defer { reopenedDatabase.close() }
        let reopenedRepository = ConversationRepository(database: reopenedDatabase)
        let reopenedParticipants = AgentRoomsParticipantService(
            repository: reopenedRepository,
            catalog: catalog
        )
        let persistedActivity = try reopenedParticipants.activity(
            roomID: room.id,
            invocationID: invocationID
        )

        #expect(persistedActivity.count == 1)
        #expect(persistedActivity[0].participantID == participantID)
        #expect(persistedActivity[0].summary == "Bounded progress")
        #expect(!persistedActivity[0].summary.contains("\u{001B}"))
        #expect(try reopenedParticipants.turnAttribution(
            #require(try reopenedRepository.turns(roomID: room.id).last)
        ) == attribution)
    }

    private func profile(
        id: String,
        displayName: String,
        providerID: String = "local",
        runtimeID: String? = nil,
        availability: ConversationAgentAvailability = .available
    ) throws -> ConversationAgentProfile {
        try ConversationAgentProfile.validated(
            id: id,
            displayName: displayName,
            runtimeBinding: .init(providerID: providerID, runtimeID: runtimeID ?? id),
            capabilities: [.init(id: "text-chat", displayName: "Text chat")],
            availability: availability
        )
    }

    private func withRepository<T>(
        _ body: (ConversationRepository) async throws -> T
    ) async throws -> T {
        let url = disposableDatabaseURL()
        let database = CiderDatabase()
        try database.open(at: url)
        defer {
            database.close()
            removeDatabase(at: url)
        }
        return try await body(ConversationRepository(database: database))
    }

    private func disposableDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-participant-invocation-\(UUID().uuidString).db")
    }

    private func removeDatabase(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
    }
}

private actor ParticipantProbeRuntime: ConversationParticipantRuntimeExecuting {
    nonisolated let binding: ConversationAgentRuntimeBinding
    private let response: String
    private let update: String
    private var executions = 0

    init(binding: ConversationAgentRuntimeBinding, response: String, update: String) {
        self.binding = binding
        self.response = response
        self.update = update
    }

    func execute(_ request: ConversationParticipantExecutionRequest) async throws
        -> ConversationParticipantExecutionResult {
        executions += 1
        return .init(
            text: response,
            source: .init(namespace: "cider.tests.participant-runtime", id: request.runID.uuidString),
            updates: [.init(kind: .work, summary: update)]
        )
    }

    func cancel(executionID: UUID) async {}
    func executionCount() -> Int { executions }
}

private actor BlockingParticipantRuntime: ConversationParticipantRuntimeExecuting {
    nonisolated let binding: ConversationAgentRuntimeBinding
    private var started = false
    private var cancelled = false
    private var cancellations = 0
    private var runID: UUID?
    private var cancelledExecutionID: UUID?

    init(binding: ConversationAgentRuntimeBinding) {
        self.binding = binding
    }

    func execute(_ request: ConversationParticipantExecutionRequest) async throws
        -> ConversationParticipantExecutionResult {
        runID = request.runID
        started = true
        while !cancelled { await Task.yield() }
        throw CancellationError()
    }

    func cancel(executionID: UUID) async {
        cancellations += 1
        cancelledExecutionID = executionID
        cancelled = true
    }

    func hasStarted() -> Bool { started }
    func cancellationCount() -> Int { cancellations }
    func cancelledExecutionMatchesRun() -> Bool {
        runID != nil && cancelledExecutionID == runID
    }
}
