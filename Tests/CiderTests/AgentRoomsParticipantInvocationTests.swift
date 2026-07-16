import Foundation
import Testing
@testable import Cider

@Suite("Agent Rooms Participant Invocation Tests")
@MainActor
struct AgentRoomsParticipantInvocationTests {
    @Test("participant acceptance uses the transaction-current sequence and parent across connections")
    func participantAcceptanceUsesCurrentSequenceAndParent() async throws {
        let fixture = try makeAcceptanceFixture(title: "Participant append race")
        defer { fixture.cleanup() }
        let runtime = ParticipantProbeRuntime(
            binding: fixture.advisor.runtimeBinding,
            response: "Current-sequence participant answer",
            update: "Accepted after ordinary append"
        )
        let persistenceB = AgentRoomsConversationPersistence(
            database: fixture.secondaryDatabase,
            repository: fixture.secondaryRepository,
            defaultAgentProfile: fixture.headA,
            participantProfiles: fixture.catalog.profiles
        )
        let attempt = try persistenceB.beginAttempt(
            roomID: fixture.room.id,
            roomTitle: fixture.room.title,
            isReservedTestChat: false,
            attemptID: UUID(),
            clientMessageID: "cider-room-client:participant-append-race",
            userMessageID: UUID(),
            assistantMessageID: UUID(),
            text: "Ordinary message committed on connection B",
            at: Date(timeIntervalSince1970: 1_800_100_001)
        )
        let service = AgentRoomsParticipantInvocationService(
            repository: fixture.primaryRepository,
            participants: fixture.primaryParticipants,
            runtimes: try ConversationParticipantRuntimeRegistry(executors: [runtime])
        )
        let result = try await service.invoke(.init(
            roomID: fixture.room.id,
            prompt: "Participant must follow current sequence",
            selectedParticipantIDs: [fixture.advisorParticipantID],
            origin: .user,
            limits: .checkpoint
        ))

        #expect(result.runs.map(\.status) == [.completed])
        #expect(await runtime.executionCount() == 1)
        let messages = try fixture.primaryRepository.messages(roomID: fixture.room.id)
        let participantUser = try #require(messages.first {
            $0.source?.namespace == AgentRoomsParticipantService.submissionSourceNamespace
        })
        let routing = try submissionRouting(participantUser)
        let acceptance = try #require(
            try fixture.primaryRepository.routingAcceptanceHistory(roomID: fixture.room.id)?
                .records.first(where: { $0.userMessageID == participantUser.id })
        )
        let ancestry = try fixture.primaryRepository.messages(
            roomID: fixture.room.id,
            throughHead: participantUser.id
        )

        #expect(participantUser.sequence == 2)
        #expect(participantUser.parentMessageID == attempt.userMessageID)
        #expect(routing.observedRoomMessageSequence == participantUser.sequence - 1)
        #expect(routing.observedRoomMessageSequence == 1)
        #expect(acceptance.routing == routing)
        #expect(ancestry.map(\.id) == [attempt.userMessageID, participantUser.id])
        try assertPhysicalReopenSucceeds(fixture)
    }

    @Test("participant acceptance uses the transaction-current head epoch but keeps explicit recipient")
    func participantAcceptanceUsesCurrentHeadEpoch() async throws {
        let fixture = try makeAcceptanceFixture(title: "Participant head race")
        defer { fixture.cleanup() }
        let runtime = ParticipantProbeRuntime(
            binding: fixture.advisor.runtimeBinding,
            response: "Explicit advisor answer",
            update: "Accepted after head change"
        )
        let assignmentsB = AgentRoomsAgentAssignmentService(
            repository: fixture.secondaryRepository,
            catalog: fixture.catalog,
            now: { Date(timeIntervalSince1970: 1_800_100_010) }
        )
        let changedAssignment = try assignmentsB.assign(
            profileID: fixture.headB.id,
            roomID: fixture.room.id
        )
        let service = AgentRoomsParticipantInvocationService(
            repository: fixture.primaryRepository,
            participants: fixture.primaryParticipants,
            runtimes: try ConversationParticipantRuntimeRegistry(executors: [runtime])
        )
        _ = try await service.invoke(.init(
            roomID: fixture.room.id,
            prompt: "Keep the advisor explicit after the head changes",
            selectedParticipantIDs: [fixture.advisorParticipantID],
            origin: .user,
            limits: .checkpoint
        ))

        let messages = try fixture.primaryRepository.messages(roomID: fixture.room.id)
        let event = try #require(messages.first(where: { $0.role == "system" }))
        let participantUser = try #require(messages.first {
            $0.source?.namespace == AgentRoomsParticipantService.submissionSourceNamespace
        })
        let participantTurn = try #require(
            try fixture.primaryRepository.turns(roomID: fixture.room.id).last
        )
        let submission = try submissionRouting(participantUser)
        let generated = try generatedRouting(participantTurn)

        #expect(changedAssignment.headRoutingEpoch == 2)
        #expect(participantUser.sequence == 2)
        #expect(participantUser.parentMessageID == event.id)
        #expect(
            submission.observedHeadRoutingEpoch
                == changedAssignment.headRoutingEpoch
        )
        #expect(submission.observedRoomMessageSequence == event.sequence)
        #expect(submission.recipients == [
            ConversationRoutingRecipient(profile: fixture.advisor),
        ])
        #expect(generated.recipient == ConversationRoutingRecipient(profile: fixture.advisor))
        #expect(
            generated.observedHeadRoutingEpoch
                == changedAssignment.headRoutingEpoch
        )
        #expect(generated.observedRoomMessageSequence == event.sequence)
        try assertPhysicalReopenSucceeds(fixture)
    }

    @Test("participant acceptance rejects a roster removed on another connection without stale writes")
    func participantAcceptanceRejectsCurrentRosterMismatch() async throws {
        let fixture = try makeAcceptanceFixture(title: "Participant roster race")
        defer { fixture.cleanup() }
        let runtime = ParticipantProbeRuntime(
            binding: fixture.advisor.runtimeBinding,
            response: "Must not run",
            update: "Must not persist"
        )
        _ = try fixture.secondaryParticipants.configureRoster(
            roomID: fixture.room.id,
            members: [
                .init(profileID: fixture.headA.id, role: .actingAgent),
                .init(profileID: fixture.headB.id, role: .advisor),
            ]
        )
        let service = AgentRoomsParticipantInvocationService(
            repository: fixture.primaryRepository,
            participants: fixture.primaryParticipants,
            runtimes: try ConversationParticipantRuntimeRegistry(executors: [runtime])
        )
        do {
            _ = try await service.invoke(.init(
                roomID: fixture.room.id,
                prompt: "Removed advisor must not be accepted",
                selectedParticipantIDs: [fixture.advisorParticipantID],
                origin: .user,
                limits: .checkpoint
            ))
            Issue.record("Expected transaction-current roster rejection")
        } catch let error as ConversationParticipantInvocationError {
            guard case .invalid = error else {
                Issue.record("Expected invalid roster conflict, got \(error)")
                return
            }
        }

        #expect(await runtime.executionCount() == 0)
        #expect(try fixture.primaryRepository.messages(roomID: fixture.room.id).isEmpty)
        #expect(try fixture.primaryRepository.turns(roomID: fixture.room.id).isEmpty)
        #expect(
            try fixture.primaryRepository.routingAcceptanceHistory(roomID: fixture.room.id) == nil
        )
        #expect(
            try fixture.primaryRepository.participantRoster(roomID: fixture.room.id)?
                .members.map(\.profile.id) == [fixture.headA.id, fixture.headB.id]
        )
        try assertPhysicalReopenSucceeds(fixture)
    }

    @Test("participant writer contention is a typed bounded conflict with zero mutation")
    func participantAcceptanceWriterContentionIsTyped() async throws {
        let fixture = try makeAcceptanceFixture(title: "Participant writer contention")
        defer { fixture.cleanup() }
        let runtime = ParticipantProbeRuntime(
            binding: fixture.advisor.runtimeBinding,
            response: "Must not run",
            update: "Must not persist"
        )
        try fixture.primaryDatabase.runSQL("PRAGMA busy_timeout=1;")
        try fixture.secondaryDatabase.runSQL("BEGIN IMMEDIATE TRANSACTION;")
        defer { try? fixture.secondaryDatabase.runSQL("ROLLBACK;") }
        let service = AgentRoomsParticipantInvocationService(
            repository: fixture.primaryRepository,
            participants: fixture.primaryParticipants,
            runtimes: try ConversationParticipantRuntimeRegistry(executors: [runtime])
        )

        do {
            _ = try await service.invoke(.init(
                roomID: fixture.room.id,
                prompt: "Fail closed behind another physical writer",
                selectedParticipantIDs: [fixture.advisorParticipantID],
                origin: .user,
                limits: .checkpoint
            ))
            Issue.record("Expected a bounded participant acceptance conflict")
        } catch let error as ConversationParticipantInvocationError {
            #expect(error == .conflict(
                "Participant acceptance conflicted with another room update. Nothing was sent."
            ))
        }

        try fixture.secondaryDatabase.runSQL("ROLLBACK;")
        #expect(await runtime.executionCount() == 0)
        #expect(try fixture.primaryRepository.messages(roomID: fixture.room.id).isEmpty)
        #expect(try fixture.primaryRepository.turns(roomID: fixture.room.id).isEmpty)
        #expect(
            try fixture.primaryRepository.routingAcceptanceHistory(roomID: fixture.room.id) == nil
        )
        try assertPhysicalReopenSucceeds(fixture)
    }

    @Test("every participant acceptance write checkpoint rolls back the whole unit")
    func participantAcceptanceWriteCheckpointsRollbackAtomically() async throws {
        for checkpoint in ParticipantAcceptanceFailureCheckpoint.allCases {
            let fixture = try makeAcceptanceFixture(title: "Rollback \(checkpoint)")
            defer { fixture.cleanup() }
            let runtime = ParticipantProbeRuntime(
                binding: fixture.advisor.runtimeBinding,
                response: "Must not run",
                update: "Must not persist"
            )
            try installAcceptanceFailureTrigger(
                checkpoint,
                database: fixture.primaryDatabase
            )
            let service = AgentRoomsParticipantInvocationService(
                repository: fixture.primaryRepository,
                participants: fixture.primaryParticipants,
                runtimes: try ConversationParticipantRuntimeRegistry(executors: [runtime])
            )

            await #expect(throws: CiderDatabaseError.self) {
                try await service.invoke(.init(
                    roomID: fixture.room.id,
                    prompt: "Rollback after \(checkpoint)",
                    selectedParticipantIDs: [fixture.advisorParticipantID],
                    origin: .user,
                    limits: .checkpoint
                ))
            }

            #expect(await runtime.executionCount() == 0)
            #expect(try fixture.primaryRepository.messages(roomID: fixture.room.id).isEmpty)
            #expect(try fixture.primaryRepository.turns(roomID: fixture.room.id).isEmpty)
            #expect(
                try fixture.primaryRepository.routingAcceptanceHistory(roomID: fixture.room.id)
                    == nil
            )
            try assertPhysicalReopenSucceeds(fixture)
        }
    }

    @Test("production participant source contains no acceptance callback seams")
    func productionParticipantSourceContainsNoAcceptanceHooks() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appendingPathComponent(
            "Sources/Cider/Services/Conversation/AgentRoomsParticipantService.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let modelsURL = repositoryRoot.appendingPathComponent(
            "Sources/Cider/Models/ConversationParticipantModels.swift"
        )
        let models = try String(contentsOf: modelsURL, encoding: .utf8)

        #expect(!source.contains("acceptanceBoundaryHook"))
        #expect(!source.contains("acceptanceWriteHook"))
        #expect(!source.contains("AgentRoomsParticipantAcceptanceWriteCheckpoint"))
        #expect(!source.lowercased().contains("hook"))
        #expect(!source.contains("@MainActor () throws -> Void"))
        #expect(!source.contains("ConversationParticipantRuntimeResolving"))
        #expect(!source.contains("await runtimes.executor"))
        #expect(!models.contains("ConversationParticipantRuntimeResolving"))
    }

    @Test("single-connection participant acceptance stays exact and duplicate invocation is immutable")
    func participantAcceptanceSingleConnectionAndDuplicateStayExact() async throws {
        let fixture = try makeAcceptanceFixture(title: "Participant exact retry")
        defer { fixture.cleanup() }
        fixture.secondaryDatabase.close()
        let runtime = ParticipantProbeRuntime(
            binding: fixture.advisor.runtimeBinding,
            response: "One exact participant answer",
            update: "Executed once"
        )
        let service = AgentRoomsParticipantInvocationService(
            repository: fixture.primaryRepository,
            participants: fixture.primaryParticipants,
            runtimes: try ConversationParticipantRuntimeRegistry(executors: [runtime])
        )
        let request = ConversationParticipantInvocationRequest(
            id: UUID(),
            roomID: fixture.room.id,
            prompt: "Accept exactly once",
            selectedParticipantIDs: [fixture.advisorParticipantID],
            origin: .user,
            limits: .checkpoint
        )

        let result = try await service.invoke(request)
        let canonicalMessages = try fixture.primaryRepository.messages(roomID: fixture.room.id)
        let canonicalTurns = try fixture.primaryRepository.turns(roomID: fixture.room.id)
        let canonicalHistory = try fixture.primaryRepository.routingAcceptanceHistory(
            roomID: fixture.room.id
        )

        #expect(result.runs.map(\.status) == [.completed])
        #expect(await runtime.executionCount() == 1)
        #expect(canonicalMessages.map(\.contentText) == [
            "Accept exactly once", "One exact participant answer",
        ])
        #expect(canonicalTurns.count == 1)
        #expect(canonicalHistory?.records.count == 1)
        await #expect(throws: ConversationParticipantInvocationError.self) {
            try await service.invoke(request)
        }
        #expect(await runtime.executionCount() == 1)
        #expect(
            try fixture.primaryRepository.messages(roomID: fixture.room.id)
                == canonicalMessages
        )
        #expect(try fixture.primaryRepository.turns(roomID: fixture.room.id) == canonicalTurns)
        #expect(
            try fixture.primaryRepository.routingAcceptanceHistory(roomID: fixture.room.id)
                == canonicalHistory
        )
        try assertPhysicalReopenSucceeds(fixture)
    }

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
        #expect(manifest.schemaVersion == 3)
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
            displayName: profile.displayName,
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

    private struct AcceptanceFixture {
        let url: URL
        let primaryDatabase: CiderDatabase
        let secondaryDatabase: CiderDatabase
        let primaryRepository: ConversationRepository
        let secondaryRepository: ConversationRepository
        let primaryParticipants: AgentRoomsParticipantService
        let secondaryParticipants: AgentRoomsParticipantService
        let catalog: ConversationAgentProfileCatalog
        let headA: ConversationAgentProfile
        let headB: ConversationAgentProfile
        let advisor: ConversationAgentProfile
        let room: ConversationRoom
        let advisorParticipantID: UUID

        @MainActor
        func cleanup() {
            primaryDatabase.close()
            secondaryDatabase.close()
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(atPath: url.path + "-wal")
            try? FileManager.default.removeItem(atPath: url.path + "-shm")
        }
    }

    private func makeAcceptanceFixture(title: String) throws -> AcceptanceFixture {
        let url = disposableDatabaseURL()
        let headA = try profile(id: "hermes", displayName: "Hermes")
        let headB = try profile(id: "codex", displayName: "Codex")
        let advisor = try profile(id: "research", displayName: "Research")
        let catalog = try ConversationAgentProfileCatalog(
            profiles: [headA, headB, advisor],
            defaultProfileID: headA.id
        )
        let primaryDatabase = CiderDatabase()
        try primaryDatabase.open(at: url)
        let primaryRepository = ConversationRepository(database: primaryDatabase)
        let primaryAssignments = AgentRoomsAgentAssignmentService(
            repository: primaryRepository,
            catalog: catalog
        )
        let room = try AgentRoomsActionService(
            repository: primaryRepository,
            agentAssignments: primaryAssignments
        ).createConversation(title: title)
        let primaryParticipants = AgentRoomsParticipantService(
            repository: primaryRepository,
            catalog: catalog
        )
        let advisorParticipantID = try #require(
            try primaryParticipants.roster(roomID: room.id)?
                .members.first(where: { $0.profile.id == advisor.id })?.id
        )
        let secondaryDatabase = CiderDatabase()
        try secondaryDatabase.open(at: url)
        let secondaryRepository = ConversationRepository(database: secondaryDatabase)
        return AcceptanceFixture(
            url: url,
            primaryDatabase: primaryDatabase,
            secondaryDatabase: secondaryDatabase,
            primaryRepository: primaryRepository,
            secondaryRepository: secondaryRepository,
            primaryParticipants: primaryParticipants,
            secondaryParticipants: AgentRoomsParticipantService(
                repository: secondaryRepository,
                catalog: catalog
            ),
            catalog: catalog,
            headA: headA,
            headB: headB,
            advisor: advisor,
            room: room,
            advisorParticipantID: advisorParticipantID
        )
    }

    private func submissionRouting(
        _ message: ConversationMessage
    ) throws -> ConversationSubmissionRoutingContext {
        try #require(DatabaseHelpers.decodeJSON(
            ConversationSubmissionRoutingContext.self,
            from: message.metadata[
                AgentRoomsConversationPersistence.submissionRoutingMetadataKey
            ]
        ))
    }

    private func generatedRouting(
        _ turn: ConversationTurn
    ) throws -> ConversationGeneratedRoutingContext {
        try #require(DatabaseHelpers.decodeJSON(
            ConversationGeneratedRoutingContext.self,
            from: turn.metadata[AgentRoomsConversationPersistence.generatedRoutingMetadataKey]
        ))
    }

    private func installAcceptanceFailureTrigger(
        _ checkpoint: ParticipantAcceptanceFailureCheckpoint,
        database: CiderDatabase
    ) throws {
        let sql = switch checkpoint {
        case .userMessage:
            """
            CREATE TEMP TRIGGER participant_acceptance_fail_user
            AFTER INSERT ON conversation_messages
            WHEN NEW.source_namespace = '\(AgentRoomsParticipantService.submissionSourceNamespace)'
            BEGIN
                SELECT RAISE(ABORT, 'participant acceptance user-message failure');
            END;
            """
        case .routingAcceptance:
            """
            CREATE TEMP TRIGGER participant_acceptance_fail_routing
            BEFORE UPDATE OF metadata_json ON conversation_rooms
            WHEN instr(
                NEW.metadata_json,
                '\(ConversationRepository.routingAcceptanceHistoryMetadataKey)'
            ) > 0
            AND instr(
                OLD.metadata_json,
                '\(ConversationRepository.routingAcceptanceHistoryMetadataKey)'
            ) = 0
            BEGIN
                SELECT RAISE(ABORT, 'participant acceptance routing failure');
            END;
            """
        case .firstTurn:
            """
            CREATE TEMP TRIGGER participant_acceptance_fail_turn
            AFTER INSERT ON conversation_turns
            WHEN NEW.source_namespace = '\(AgentRoomsParticipantService.runSourceNamespace)'
            BEGIN
                SELECT RAISE(ABORT, 'participant acceptance first-turn failure');
            END;
            """
        }
        try database.runSQL(sql)
    }

    private func assertPhysicalReopenSucceeds(_ fixture: AcceptanceFixture) throws {
        fixture.primaryDatabase.close()
        fixture.secondaryDatabase.close()
        let reopenedDatabase = CiderDatabase()
        try reopenedDatabase.open(at: fixture.url)
        defer { reopenedDatabase.close() }
        let reopenedPersistence = AgentRoomsConversationPersistence(
            database: reopenedDatabase,
            repository: ConversationRepository(database: reopenedDatabase),
            defaultAgentProfile: fixture.headA,
            participantProfiles: fixture.catalog.profiles
        )
        #expect(try reopenedPersistence.restoreCanonicalRoom(id: fixture.room.id) != nil)
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

private enum ParticipantAcceptanceFailureCheckpoint: CaseIterable {
    case userMessage
    case routingAcceptance
    case firstTurn
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
