import Foundation
import Testing
@testable import Cider

@Suite("Agent Rooms Head Routing Hardening Tests")
@MainActor
struct AgentRoomsHeadRoutingHardeningTests {
    @Test("held former-head output never parents the next current-head submission")
    func heldOutputIsNotContinuationParent() throws {
        let fixture = try makeFixture(title: "Canonical branch")
        defer { fixture.cleanup() }
        let initialState = try #require(
            try fixture.persistence.restoreCanonicalRoom(id: fixture.room.id)?.conversationState
        )
        let first = try beginAttempt(
            fixture,
            clientID: "cider-room-client:branch-a",
            text: "Question for A"
        )
        try fixture.persistence.markRunStarted(
            first,
            runID: "run-branch-a",
            activity: [],
            at: timestamp(1)
        )
        _ = try fixture.assignments.assign(profileID: fixture.headB.id, roomID: fixture.room.id)
        #expect(try fixture.persistence.complete(
            first,
            completion: completion(
                state: initialState,
                text: "Question for A",
                answer: "Held A",
                runID: "run-branch-a",
                sessionID: "session-branch-a"
            ),
            expectedText: "Question for A",
            activity: []
        ) == .heldStale)

        let second = try beginAttempt(
            fixture,
            clientID: "cider-room-client:branch-b",
            text: "Question for B"
        )
        let messages = try fixture.repository.messages(roomID: fixture.room.id)
        let event = try #require(messages.first(where: { $0.role == "system" }))
        let held = try #require(messages.first(where: {
            $0.metadata[AgentRoomsConversationPersistence.publicationStateMetadataKey]
                == ConversationPublicationState.heldStale.rawValue
        }))
        let secondUser = try #require(messages.first(where: { $0.id == second.userMessageID }))
        let ancestry = try fixture.repository.messages(
            roomID: fixture.room.id,
            throughHead: secondUser.id
        )

        #expect(secondUser.parentMessageID == event.id)
        #expect(ancestry.map(\.id).contains(event.id))
        #expect(!ancestry.map(\.id).contains(held.id))
        #expect(ancestry.map(\.role) == ["user", "system", "user"])
    }

    @Test("every head event descends from the prior canonical event and never from held output")
    func laterHeadEventCannotDescendFromHeldOutput() throws {
        let fixture = try makeFixture(title: "Canonical event ancestry")
        defer { fixture.cleanup() }
        let state = try #require(
            try fixture.persistence.restoreCanonicalRoom(id: fixture.room.id)?.conversationState
        )
        let attempt = try beginAttempt(
            fixture,
            clientID: "cider-room-client:event-parent-a",
            text: "Question before two changes"
        )
        _ = try fixture.assignments.assign(
            profileID: fixture.headB.id,
            roomID: fixture.room.id
        )
        #expect(try fixture.persistence.complete(
            attempt,
            completion: completion(
                state: state,
                text: "Question before two changes",
                answer: "Held A result",
                runID: "run-event-parent-a",
                sessionID: "session-event-parent-a"
            ),
            expectedText: "Question before two changes",
            activity: []
        ) == .heldStale)
        _ = try fixture.assignments.assign(
            profileID: fixture.headC.id,
            roomID: fixture.room.id
        )

        let messages = try fixture.repository.messages(roomID: fixture.room.id)
        let events = messages.filter { $0.role == "system" }
        let held = try #require(messages.first(where: {
            $0.metadata[AgentRoomsConversationPersistence.publicationStateMetadataKey]
                == ConversationPublicationState.heldStale.rawValue
        }))
        #expect(events.count == 2)
        let ancestry = try fixture.repository.messages(
            roomID: fixture.room.id,
            throughHead: events[1].id
        )
        #expect(events[1].parentMessageID == events[0].id)
        #expect(ancestry.map(\.id).contains(events[0].id))
        #expect(ancestry.map(\.id).contains(events[1].id))
        #expect(!ancestry.map(\.id).contains(held.id))

        let tamper = try fixture.database.prepare("""
            UPDATE conversation_messages
            SET parent_message_id = ?
            WHERE id = ?;
            """)
        tamper.bind(held.id.uuidString, at: 1)
            .bind(events[1].id.uuidString, at: 2)
        try tamper.step()

        fixture.database.close()
        let reopenedDatabase = CiderDatabase()
        try reopenedDatabase.open(at: fixture.url)
        defer { reopenedDatabase.close() }
        let reopenedPersistence = AgentRoomsConversationPersistence(
            database: reopenedDatabase,
            repository: ConversationRepository(database: reopenedDatabase),
            defaultAgentProfile: fixture.headA,
            participantProfiles: fixture.catalog.profiles
        )
        #expect(throws: AgentRoomsConversationPersistenceError.corruptHistory) {
            try reopenedPersistence.restoreCanonicalRoom(id: fixture.room.id)
        }
    }

    @Test("participant success and failure stay independent of head changes and physically reopen")
    func participantOutcomesSurviveHeadChangesAndReopen() async throws {
        for shouldFail in [false, true] {
            let fixture = try makeFixture(title: shouldFail ? "Participant failure" : "Participant success")
            let participants = AgentRoomsParticipantService(
                repository: fixture.repository,
                catalog: fixture.catalog
            )
            let roster = try #require(try participants.roster(roomID: fixture.room.id))
            let participantID = try #require(
                roster.members.first(where: { $0.profile.id == fixture.headA.id })?.id
            )
            let runtime = ParticipantHardeningGateRuntime(
                binding: fixture.headA.runtimeBinding,
                shouldFail: shouldFail
            )
            let service = AgentRoomsParticipantInvocationService(
                repository: fixture.repository,
                participants: participants,
                runtimes: try ConversationParticipantRuntimeRegistry(executors: [runtime])
            )
            let task = Task {
                try await service.invoke(.init(
                    roomID: fixture.room.id,
                    prompt: shouldFail ? "Fail after change" : "Finish after change",
                    selectedParticipantIDs: [participantID],
                    origin: .user,
                    limits: .checkpoint
                ))
            }
            await runtime.waitUntilStarted()
            _ = try fixture.assignments.assign(profileID: fixture.headB.id, roomID: fixture.room.id)
            await runtime.release()
            let result = try await task.value

            #expect(result.runs.map(\.status) == [shouldFail ? .failed : .completed])
            let turn = try #require(try fixture.repository.turns(roomID: fixture.room.id).last)
            #expect(turn.status == (shouldFail ? .failed : .completed))
            #expect(turn.error?.code == (shouldFail ? "participant_execution_failed" : nil))
            #expect(turn.source?.namespace == AgentRoomsParticipantService.runSourceNamespace)
            #expect(turn.metadata["authority"] == AgentRoomsParticipantService.participantAuthority)
            #expect(turn.metadata["source_created_at"].flatMap(Double.init) != nil)
            #expect(
                turn.metadata[AgentRoomsParticipantService.runAttributionMetadataKey] != nil
            )
            #expect(
                turn.metadata[
                    AgentRoomsConversationPersistence.generatedRoutingMetadataKey
                ] != nil
            )
            let participantUser = try #require(
                try fixture.repository.messages(roomID: fixture.room.id)
                    .first(where: { $0.role == "user" })
            )
            #expect(
                participantUser.source?.namespace
                    == AgentRoomsParticipantService.submissionSourceNamespace
            )
            #expect(participantUser.sourceCreatedAt != nil)
            #expect(
                participantUser.metadata["authority"]
                    == AgentRoomsParticipantService.participantAuthority
            )
            if let assistant = try fixture.repository.messages(roomID: fixture.room.id)
                .first(where: { $0.role == "assistant" }) {
                #expect(!shouldFail)
                #expect(assistant.status == .complete)
                #expect(
                    assistant.source?.namespace
                        == AgentRoomsParticipantService.runSourceNamespace
                )
                #expect(assistant.sourceCreatedAt != nil)
                #expect(
                    assistant.metadata["authority"]
                        == AgentRoomsParticipantService.participantAuthority
                )
                #expect(
                    assistant.metadata[
                        AgentRoomsConversationPersistence.publicationStateMetadataKey
                    ] == nil
                )
            } else {
                #expect(shouldFail)
            }

            fixture.database.close()
            let reopenedDatabase = CiderDatabase()
            try reopenedDatabase.open(at: fixture.url)
            let reopenedRepository = ConversationRepository(database: reopenedDatabase)
            let reopenedPersistence = AgentRoomsConversationPersistence(
                database: reopenedDatabase,
                repository: reopenedRepository,
                defaultAgentProfile: fixture.headA,
                participantProfiles: fixture.catalog.profiles
            )
            let snapshot = try #require(
                try reopenedPersistence.restoreCanonicalRoom(id: fixture.room.id)
            )
            #expect(snapshot.latestTurnStatus == (shouldFail ? .failed : .completed))
            #expect(snapshot.presentationMessages.last?.author == (shouldFail ? "Cider" : "Hermes"))
            reopenedDatabase.close()
            fixture.cleanup()
        }
    }

    @Test("participant acceptance rolls back when its first run cannot persist")
    func participantAcceptanceIsAtomic() async throws {
        let fixture = try makeFixture(title: "Participant atomicity")
        defer { fixture.cleanup() }
        let participants = AgentRoomsParticipantService(
            repository: fixture.repository,
            catalog: fixture.catalog
        )
        let roster = try #require(try participants.roster(roomID: fixture.room.id))
        let participantID = try #require(
            roster.members.first(where: { $0.profile.id == fixture.headA.id })?.id
        )
        let runtime = ParticipantHardeningGateRuntime(
            binding: fixture.headA.runtimeBinding,
            shouldFail: false,
            startsReleased: true
        )
        let service = AgentRoomsParticipantInvocationService(
            repository: fixture.repository,
            participants: participants,
            runtimes: try ConversationParticipantRuntimeRegistry(executors: [runtime])
        )
        try fixture.database.runSQL("""
            CREATE TRIGGER cid841_fail_participant_turn
            BEFORE INSERT ON conversation_turns
            BEGIN
                SELECT RAISE(ABORT, 'cid841 injected participant turn failure');
            END;
            """)

        await #expect(throws: Error.self) {
            try await service.invoke(.init(
                roomID: fixture.room.id,
                prompt: "Must roll back",
                selectedParticipantIDs: [participantID],
                origin: .user,
                limits: .checkpoint
            ))
        }
        #expect(try fixture.repository.messages(roomID: fixture.room.id).isEmpty)
        #expect(try fixture.repository.turns(roomID: fixture.room.id).isEmpty)
        #expect(await runtime.executionCount() == 0)
    }

    @Test("same profile identity refreshes metadata without changing routing epoch or staling work")
    func sameIdentityRefreshIsEpochStable() throws {
        let oldProfile = try makeProfile(
            id: "hermes",
            displayName: "Hermes",
            providerID: "hermes",
            runtimeID: "hermes-v1"
        )
        let refreshedProfile = try makeProfile(
            id: "hermes",
            displayName: "Hermes Updated",
            providerID: "hermes",
            runtimeID: "hermes-v2"
        )
        let nextProfile = try makeProfile(
            id: "codex",
            displayName: "Codex",
            providerID: "openai",
            runtimeID: "codex"
        )
        let oldCatalog = try ConversationAgentProfileCatalog(
            profiles: [oldProfile, nextProfile],
            defaultProfileID: oldProfile.id
        )
        let fixture = try makeFixture(title: "Same identity", catalog: oldCatalog)
        defer { fixture.cleanup() }
        let initialState = try #require(
            try fixture.persistence.restoreCanonicalRoom(id: fixture.room.id)?.conversationState
        )
        let attempt = try beginAttempt(
            fixture,
            clientID: "cider-room-client:same-id",
            text: "Stay current"
        )
        try fixture.persistence.markRunStarted(
            attempt,
            runID: "run-same-id",
            activity: [],
            at: timestamp(1)
        )
        let refreshedCatalog = try ConversationAgentProfileCatalog(
            profiles: [refreshedProfile, nextProfile],
            defaultProfileID: refreshedProfile.id
        )
        let refreshedAssignments = AgentRoomsAgentAssignmentService(
            repository: fixture.repository,
            catalog: refreshedCatalog,
            now: { timestamp(2) }
        )
        let refreshed = try refreshedAssignments.assign(
            profileID: refreshedProfile.id,
            roomID: fixture.room.id
        )

        #expect(refreshed.profile == refreshedProfile)
        #expect(refreshed.headRoutingEpoch == 1)
        #expect(try fixture.repository.messages(roomID: fixture.room.id).allSatisfy {
            $0.role != "system"
        })
        #expect(try fixture.persistence.complete(
            attempt,
            completion: completion(
                state: initialState,
                text: "Stay current",
                answer: "Still published",
                runID: "run-same-id",
                sessionID: "session-same-id"
            ),
            expectedText: "Stay current",
            activity: []
        ) == .published)

        let changed = try refreshedAssignments.assign(
            profileID: nextProfile.id,
            roomID: fixture.room.id
        )
        let repeated = try refreshedAssignments.assign(
            profileID: nextProfile.id,
            roomID: fixture.room.id
        )
        #expect(changed.headRoutingEpoch == 2)
        #expect(repeated.headRoutingEpoch == 2)
        #expect(try fixture.repository.messages(roomID: fixture.room.id)
            .filter { $0.role == "system" }.count == 1)
    }

    @Test("event continuity uses profile identity across an in-between metadata refresh")
    func eventContinuitySurvivesSameIdentityMetadataRefresh() throws {
        let fixture = try makeFixture(title: "Historical event snapshots")
        defer { fixture.cleanup() }
        _ = try fixture.assignments.assign(
            profileID: fixture.headB.id,
            roomID: fixture.room.id
        )
        let refreshedB = try makeProfile(
            id: fixture.headB.id,
            displayName: "Codex Refreshed",
            providerID: "openai",
            runtimeID: "codex-refreshed"
        )
        let refreshedCatalog = try ConversationAgentProfileCatalog(
            profiles: [fixture.headA, refreshedB, fixture.headC],
            defaultProfileID: fixture.headA.id
        )
        let refreshedAssignments = AgentRoomsAgentAssignmentService(
            repository: fixture.repository,
            catalog: refreshedCatalog,
            now: { timestamp(9) }
        )
        let refreshed = try refreshedAssignments.assign(
            profileID: refreshedB.id,
            roomID: fixture.room.id
        )
        #expect(refreshed.headRoutingEpoch == 2)
        _ = try refreshedAssignments.assign(
            profileID: fixture.headC.id,
            roomID: fixture.room.id
        )

        let eventMessages = try fixture.repository.messages(roomID: fixture.room.id)
            .filter { $0.role == "system" }
        let events = try eventMessages.map { try decodeEvent($0.metadata) }
        #expect(events.count == 2)
        #expect(events[0].newHead.profileID == refreshedB.id)
        #expect(events[0].newHead.displayName == fixture.headB.displayName)
        #expect(events[1].oldHead?.profileID == refreshedB.id)
        #expect(events[1].oldHead?.displayName == refreshedB.displayName)

        fixture.database.close()
        let reopenedDatabase = CiderDatabase()
        try reopenedDatabase.open(at: fixture.url)
        defer { reopenedDatabase.close() }
        let reopenedPersistence = AgentRoomsConversationPersistence(
            database: reopenedDatabase,
            repository: ConversationRepository(database: reopenedDatabase),
            defaultAgentProfile: fixture.headA,
            participantProfiles: refreshedCatalog.profiles
        )
        let reopened = try #require(
            try reopenedPersistence.restoreCanonicalRoom(id: fixture.room.id)
        )
        #expect(reopened.room.id == fixture.room.id)
    }

    @Test("native submissions bind to the canonical epoch head while explicit participants stay separate")
    func nativeSubmissionRecipientIsCanonicalForEpoch() throws {
        do {
            let fixture = try makeFixture(title: "Canonical native recipient")
            let state = try #require(
                try fixture.persistence.restoreCanonicalRoom(id: fixture.room.id)?
                    .conversationState
            )
            let native = try beginAttempt(
                fixture,
                clientID: "cider-room-client:canonical-native",
                text: "Native head request"
            )
            _ = try fixture.persistence.complete(
                native,
                completion: completion(
                    state: state,
                    text: "Native head request",
                    answer: "Native head answer",
                    runID: "run-canonical-native",
                    sessionID: "session-canonical-native"
                ),
                expectedText: "Native head request",
                activity: []
            )
            let participantID = try #require(
                try fixture.repository.participantRoster(roomID: fixture.room.id)?
                    .members.first(where: { $0.profile.id == fixture.headB.id })?.id
            )
            let participant = try fixture.persistence.beginAttributedAttempt(
                roomID: fixture.room.id,
                roomTitle: fixture.room.title,
                isReservedTestChat: false,
                attemptID: UUID(),
                clientMessageID: "cider-room-client:explicit-participant",
                userMessageID: UUID(),
                assistantMessageID: UUID(),
                text: "Explicit participant request",
                attribution: .init(
                    invocationID: UUID(),
                    runID: UUID(),
                    participantID: participantID,
                    profileID: fixture.headB.id,
                    participantRole: .advisor,
                    selectionSequence: 1
                ),
                at: timestamp(2)
            )
            try fixture.persistence.markRunStarted(
                participant,
                runID: "run-explicit-participant",
                activity: [],
                at: timestamp(3)
            )
            _ = try fixture.persistence.terminate(
                participant,
                status: .cancelled,
                runID: "run-explicit-participant",
                partialAssistantText: "Participant partial",
                activity: [],
                at: timestamp(4)
            )

            fixture.database.close()
            let reopenedDatabase = CiderDatabase()
            try reopenedDatabase.open(at: fixture.url)
            let reopenedPersistence = AgentRoomsConversationPersistence(
                database: reopenedDatabase,
                repository: ConversationRepository(database: reopenedDatabase),
                defaultAgentProfile: fixture.headA,
                participantProfiles: fixture.catalog.profiles
            )
            #expect(try reopenedPersistence.restoreCanonicalRoom(id: fixture.room.id) != nil)
            reopenedDatabase.close()
            fixture.cleanup()
        }

        do {
            let fixture = try makeFixture(title: "Forged native recipient")
            defer { fixture.cleanup() }
            let state = try #require(
                try fixture.persistence.restoreCanonicalRoom(id: fixture.room.id)?
                    .conversationState
            )
            let attempt = try beginAttempt(
                fixture,
                clientID: "cider-room-client:forged-native",
                text: "Forge all routing"
            )
            _ = try fixture.persistence.complete(
                attempt,
                completion: completion(
                    state: state,
                    text: "Forge all routing",
                    answer: "Forged answer",
                    runID: "run-forged-native",
                    sessionID: "session-forged-native"
                ),
                expectedText: "Forge all routing",
                activity: []
            )
            let forgedRecipient = ConversationRoutingRecipient(
                profileID: fixture.headC.id,
                displayName: fixture.headC.displayName
            )
            try mutateMessageMetadata(fixture, id: attempt.userMessageID) { metadata in
                metadata[
                    AgentRoomsParticipantService.messageAttributionMetadataKey
                ] = try encode(
                    ConversationParticipantMessageAttribution(
                        invocationID: UUID(),
                        runID: nil,
                        participantID: nil,
                        profileID: nil,
                        participantRole: nil
                    )
                )
            }
            try mutateSubmissionRouting(fixture, messageID: attempt.userMessageID) {
                .init(
                    recipients: [forgedRecipient],
                    observedHeadRoutingEpoch: $0.observedHeadRoutingEpoch,
                    observedRoomMessageSequence: $0.observedRoomMessageSequence
                )
            }
            try mutateTurnGeneratedRouting(fixture, turnID: attempt.turnID) {
                .init(
                    recipient: forgedRecipient,
                    observedHeadRoutingEpoch: $0.observedHeadRoutingEpoch,
                    observedRoomMessageSequence: $0.observedRoomMessageSequence,
                    originatingUserMessageID: $0.originatingUserMessageID
                )
            }
            try mutateGeneratedRouting(fixture, messageID: attempt.assistantMessageID) {
                .init(
                    recipient: forgedRecipient,
                    observedHeadRoutingEpoch: $0.observedHeadRoutingEpoch,
                    observedRoomMessageSequence: $0.observedRoomMessageSequence,
                    originatingUserMessageID: $0.originatingUserMessageID
                )
            }
            let expectedMessages = try fixture.repository.messages(roomID: fixture.room.id)
            let expectedTurns = try fixture.repository.turns(roomID: fixture.room.id)

            fixture.database.close()
            let reopenedDatabase = CiderDatabase()
            try reopenedDatabase.open(at: fixture.url)
            defer { reopenedDatabase.close() }
            let reopenedPersistence = AgentRoomsConversationPersistence(
                database: reopenedDatabase,
                repository: ConversationRepository(database: reopenedDatabase),
                defaultAgentProfile: fixture.headA,
                participantProfiles: fixture.catalog.profiles
            )
            #expect(throws: AgentRoomsConversationPersistenceError.corruptHistory) {
                try reopenedPersistence.restoreCanonicalRoom(id: fixture.room.id)
            }
            let reopenedRepository = ConversationRepository(database: reopenedDatabase)
            #expect(try reopenedRepository.messages(roomID: fixture.room.id) == expectedMessages)
            #expect(try reopenedRepository.turns(roomID: fixture.room.id) == expectedTurns)
        }

        for tamper in ["source", "authority", "attribution"] {
            let fixture = try makeFixture(title: "Participant \(tamper) tamper")
            let member = try #require(
                try fixture.repository.participantRoster(roomID: fixture.room.id)?
                    .members.first(where: { $0.profile.id == fixture.headB.id })
            )
            let attribution = ConversationParticipantRunAttribution(
                invocationID: UUID(),
                runID: UUID(),
                participantID: member.id,
                profileID: member.profile.id,
                participantRole: member.role,
                selectionSequence: 1
            )
            let attempt = try fixture.persistence.beginAttributedAttempt(
                roomID: fixture.room.id,
                roomTitle: fixture.room.title,
                isReservedTestChat: false,
                attemptID: attribution.runID,
                clientMessageID: "cider-room-client:participant-\(tamper)",
                userMessageID: UUID(),
                assistantMessageID: UUID(),
                text: "Participant authority check",
                attribution: attribution,
                at: timestamp(2)
            )
            try fixture.persistence.markRunStarted(
                attempt,
                runID: "run-participant-\(tamper)",
                activity: [],
                at: timestamp(3)
            )
            _ = try fixture.persistence.terminate(
                attempt,
                status: .cancelled,
                runID: "run-participant-\(tamper)",
                partialAssistantText: "Participant partial",
                activity: [],
                at: timestamp(4)
            )
            switch tamper {
            case "source":
                let statement = try fixture.database.prepare("""
                    UPDATE conversation_messages
                    SET source_namespace = 'cider.rooms.client.v1'
                    WHERE id = ?;
                    """)
                statement.bind(attempt.userMessageID.uuidString, at: 1)
                try statement.step()
            case "authority":
                try mutateMessageMetadata(fixture, id: attempt.userMessageID) { metadata in
                    metadata["authority"] = "cider.rooms.hermes-runs.v1"
                }
            default:
                try mutateMessageMetadata(fixture, id: attempt.userMessageID) { metadata in
                    metadata.removeValue(
                        forKey: AgentRoomsParticipantService.messageAttributionMetadataKey
                    )
                }
            }
            let expectedMessages = try fixture.repository.messages(roomID: fixture.room.id)
            let expectedTurns = try fixture.repository.turns(roomID: fixture.room.id)
            fixture.database.close()

            let reopenedDatabase = CiderDatabase()
            try reopenedDatabase.open(at: fixture.url)
            let reopenedRepository = ConversationRepository(database: reopenedDatabase)
            let reopenedPersistence = AgentRoomsConversationPersistence(
                database: reopenedDatabase,
                repository: reopenedRepository,
                defaultAgentProfile: fixture.headA,
                participantProfiles: fixture.catalog.profiles
            )
            #expect(throws: AgentRoomsConversationPersistenceError.corruptHistory) {
                try reopenedPersistence.restoreCanonicalRoom(id: fixture.room.id)
            }
            #expect(try reopenedRepository.messages(roomID: fixture.room.id) == expectedMessages)
            #expect(try reopenedRepository.turns(roomID: fixture.room.id) == expectedTurns)
            reopenedDatabase.close()
            fixture.cleanup()
        }
    }

    @Test("invalid nonterminal reopen is read-only for normal and reserved rooms")
    func invalidInterruptedReopenNeverMutatesCanonicalState() throws {
        for reserved in [false, true] {
            for status in [
                ConversationTurnStatus.pending,
                .running,
                .waiting,
            ] {
                let fixture = try reserved
                    ? makeReservedFixture(title: "Reserved invalid \(status.rawValue)")
                    : makeFixture(title: "Native invalid \(status.rawValue)")
                let attempt = try beginAttempt(
                    fixture,
                    clientID: "cider-room-client:invalid-\(reserved)-\(status.rawValue)",
                    text: "Invalid interrupted reopen",
                    reserved: reserved
                )
                if status == .running || status == .waiting {
                    try fixture.persistence.markRunStarted(
                        attempt,
                        runID: "run-invalid-\(reserved)-\(status.rawValue)",
                        activity: [],
                        at: timestamp(1)
                    )
                }
                if status == .waiting {
                    _ = try fixture.repository.transitionTurn(
                        id: attempt.turnID,
                        to: .waiting,
                        at: timestamp(2)
                    )
                }
                try mutateSubmissionRouting(fixture, messageID: attempt.userMessageID) {
                    .init(
                        recipients: $0.recipients,
                        observedHeadRoutingEpoch: $0.observedHeadRoutingEpoch,
                        observedRoomMessageSequence:
                            $0.observedRoomMessageSequence + 10
                    )
                }
                fixture.database.close()

                let before = try durableFingerprint(
                    url: fixture.url,
                    roomID: fixture.room.id
                )
                let reopenDatabase = CiderDatabase()
                try reopenDatabase.open(at: fixture.url)
                let reopenPersistence = AgentRoomsConversationPersistence(
                    database: reopenDatabase,
                    repository: ConversationRepository(database: reopenDatabase),
                    defaultAgentProfile: fixture.headA,
                    participantProfiles: fixture.catalog.profiles
                )
                #expect(throws: AgentRoomsConversationPersistenceError.corruptHistory) {
                    if reserved {
                        try reopenPersistence.restoreReservedTestChat()
                    } else {
                        try reopenPersistence.restoreCanonicalRoom(id: fixture.room.id)
                    }
                }
                reopenDatabase.close()

                let after = try durableFingerprint(
                    url: fixture.url,
                    roomID: fixture.room.id
                )
                #expect(after == before)
                fixture.cleanup()
            }
        }
    }

    @Test("valid nonterminal reopen recovers once and is stable on the next physical reopen")
    func validInterruptedReopenRecoversExactlyOnce() throws {
        for reserved in [false, true] {
            for status in [
                ConversationTurnStatus.pending,
                .running,
                .waiting,
            ] {
                let fixture = try reserved
                    ? makeReservedFixture(title: "Reserved valid \(status.rawValue)")
                    : makeFixture(title: "Native valid \(status.rawValue)")
                let attempt = try beginAttempt(
                    fixture,
                    clientID: "cider-room-client:valid-\(reserved)-\(status.rawValue)",
                    text: "Valid interrupted reopen",
                    reserved: reserved
                )
                if status == .running || status == .waiting {
                    try fixture.persistence.markRunStarted(
                        attempt,
                        runID: "run-valid-\(reserved)-\(status.rawValue)",
                        activity: [],
                        at: timestamp(1)
                    )
                }
                if status == .waiting {
                    _ = try fixture.repository.transitionTurn(
                        id: attempt.turnID,
                        to: .waiting,
                        at: timestamp(2)
                    )
                }
                fixture.database.close()

                let firstDatabase = CiderDatabase()
                try firstDatabase.open(at: fixture.url)
                let firstPersistence = AgentRoomsConversationPersistence(
                    database: firstDatabase,
                    repository: ConversationRepository(database: firstDatabase),
                    defaultAgentProfile: fixture.headA,
                    participantProfiles: fixture.catalog.profiles
                )
                let firstSnapshot = try #require(
                    reserved
                        ? try firstPersistence.restoreReservedTestChat()
                        : try firstPersistence.restoreCanonicalRoom(id: fixture.room.id)
                )
                #expect(firstSnapshot.latestTurnStatus == .failed)
                #expect(firstSnapshot.latestErrorCode == (
                    status == .pending
                        ? "pre_accept_interruption"
                        : "accepted_interruption"
                ))
                firstDatabase.close()
                let afterFirst = try durableFingerprint(
                    url: fixture.url,
                    roomID: fixture.room.id
                )

                let secondDatabase = CiderDatabase()
                try secondDatabase.open(at: fixture.url)
                let secondPersistence = AgentRoomsConversationPersistence(
                    database: secondDatabase,
                    repository: ConversationRepository(database: secondDatabase),
                    defaultAgentProfile: fixture.headA,
                    participantProfiles: fixture.catalog.profiles
                )
                let secondSnapshot = try #require(
                    reserved
                        ? try secondPersistence.restoreReservedTestChat()
                        : try secondPersistence.restoreCanonicalRoom(id: fixture.room.id)
                )
                #expect(secondSnapshot.latestTurnStatus == .failed)
                #expect(secondSnapshot.latestErrorCode == firstSnapshot.latestErrorCode)
                secondDatabase.close()
                let afterSecond = try durableFingerprint(
                    url: fixture.url,
                    roomID: fixture.room.id
                )
                #expect(afterSecond == afterFirst)
                fixture.cleanup()
            }
        }
    }

    @Test("historical display snapshots survive refresh and forged native or participant actors fail closed")
    func fullHistoricalRecipientIdentityIsReopenBound() throws {
        do {
            let oldHead = try makeProfile(
                id: "hermes",
                displayName: "Hermes Before Refresh",
                providerID: "hermes",
                runtimeID: "hermes-v1"
            )
            let refreshedHead = try makeProfile(
                id: "hermes",
                displayName: "Hermes After Refresh",
                providerID: "hermes",
                runtimeID: "hermes-v2"
            )
            let otherHead = try makeProfile(
                id: "codex",
                displayName: "Codex",
                providerID: "openai",
                runtimeID: "codex"
            )
            let oldCatalog = try ConversationAgentProfileCatalog(
                profiles: [oldHead, otherHead],
                defaultProfileID: oldHead.id
            )
            let fixture = try makeFixture(
                title: "Historical native recipient snapshots",
                catalog: oldCatalog
            )
            let first = try beginAttempt(
                fixture,
                clientID: "cider-room-client:before-refresh",
                text: "Before refresh"
            )
            try fixture.persistence.markRunStarted(
                first,
                runID: "run-before-refresh",
                activity: [],
                at: timestamp(1)
            )
            _ = try fixture.persistence.terminate(
                first,
                status: .cancelled,
                runID: "run-before-refresh",
                partialAssistantText: "Before refresh partial",
                activity: [],
                at: timestamp(2)
            )
            let refreshedCatalog = try ConversationAgentProfileCatalog(
                profiles: [refreshedHead, otherHead],
                defaultProfileID: refreshedHead.id
            )
            let refreshedAssignments = AgentRoomsAgentAssignmentService(
                repository: fixture.repository,
                catalog: refreshedCatalog,
                now: { timestamp(3) }
            )
            let refreshed = try refreshedAssignments.assign(
                profileID: refreshedHead.id,
                roomID: fixture.room.id
            )
            let second = try beginAttempt(
                fixture,
                clientID: "cider-room-client:after-refresh",
                text: "After refresh"
            )
            try fixture.persistence.markRunStarted(
                second,
                runID: "run-after-refresh",
                activity: [],
                at: timestamp(4)
            )
            _ = try fixture.persistence.terminate(
                second,
                status: .cancelled,
                runID: "run-after-refresh",
                partialAssistantText: "After refresh partial",
                activity: [],
                at: timestamp(5)
            )
            #expect(refreshed.headRoutingEpoch == 1)
            #expect(
                try fixture.repository.messages(roomID: fixture.room.id)
                    .allSatisfy { $0.role != "system" }
            )
            fixture.database.close()

            let reopenDatabase = CiderDatabase()
            try reopenDatabase.open(at: fixture.url)
            let reopened = try #require(
                try AgentRoomsConversationPersistence(
                    database: reopenDatabase,
                    repository: ConversationRepository(database: reopenDatabase),
                    defaultAgentProfile: refreshedHead,
                    participantProfiles: refreshedCatalog.profiles
                ).restoreCanonicalRoom(id: fixture.room.id)
            )
            #expect(
                reopened.presentationMessages
                    .filter { $0.role == .agent }
                    .map(\.author)
                    == [oldHead.displayName, refreshedHead.displayName]
            )
            reopenDatabase.close()
            fixture.cleanup()
        }

        do {
            let fixture = try makeFixture(title: "Forged native display identity")
            let attempt = try beginAttempt(
                fixture,
                clientID: "cider-room-client:forged-native-display",
                text: "Forge native display"
            )
            try fixture.persistence.markRunStarted(
                attempt,
                runID: "run-forged-native-display",
                activity: [],
                at: timestamp(1)
            )
            _ = try fixture.persistence.terminate(
                attempt,
                status: .cancelled,
                runID: "run-forged-native-display",
                partialAssistantText: "Native partial",
                activity: [],
                at: timestamp(2)
            )
            let forged = ConversationRoutingRecipient(
                profileID: fixture.headA.id,
                displayName: "Forged Native Actor"
            )
            try rewriteRecipientIdentity(
                fixture,
                attempt: attempt,
                recipient: forged,
                participant: false
            )
            try assertCorruptReopenPreservesFingerprint(fixture)
            fixture.cleanup()
        }

        do {
            let fixture = try makeFixture(title: "Forged participant display identity")
            let member = try #require(
                try fixture.repository.participantRoster(roomID: fixture.room.id)?
                    .members.first(where: { $0.profile.id == fixture.headB.id })
            )
            let attempt = try fixture.persistence.beginAttributedAttempt(
                roomID: fixture.room.id,
                roomTitle: fixture.room.title,
                isReservedTestChat: false,
                attemptID: UUID(),
                clientMessageID: "cider-room-client:forged-participant-display",
                userMessageID: UUID(),
                assistantMessageID: UUID(),
                text: "Forge participant display",
                attribution: .init(
                    invocationID: UUID(),
                    runID: UUID(),
                    participantID: member.id,
                    profileID: member.profile.id,
                    participantRole: member.role,
                    selectionSequence: 1
                ),
                at: timestamp(0)
            )
            try fixture.persistence.markRunStarted(
                attempt,
                runID: "run-forged-participant-display",
                activity: [],
                at: timestamp(1)
            )
            _ = try fixture.persistence.terminate(
                attempt,
                status: .cancelled,
                runID: "run-forged-participant-display",
                partialAssistantText: "Participant partial",
                activity: [],
                at: timestamp(2)
            )
            let persistedAttribution = try #require(attempt.participantAttribution)
            #expect(persistedAttribution.displayName == member.profile.displayName)
            let forged = ConversationRoutingRecipient(
                profileID: member.profile.id,
                displayName: "Forged Participant Actor"
            )
            try rewriteRecipientIdentity(
                fixture,
                attempt: attempt,
                recipient: forged,
                participant: true
            )
            try assertCorruptReopenPreservesFingerprint(fixture)
            fixture.cleanup()
        }
    }

    @Test("legacy epoch-zero same-ID refresh remains epoch zero and emits no event")
    func legacySameIdentityRefreshIsEpochStable() throws {
        let fixture = try makeFixture(title: "Legacy same identity")
        defer { fixture.cleanup() }
        let refreshed = try makeProfile(
            id: fixture.headA.id,
            displayName: "Hermes Refreshed",
            providerID: "hermes",
            runtimeID: "hermes-refreshed"
        )
        let legacy = LegacyAssignment(
            schemaVersion: 1,
            profile: fixture.headA,
            assignedAt: timestamp(0)
        )
        try replaceRoomAssignment(
            fixture,
            encodedAssignment: try #require(DatabaseHelpers.encodeJSON(legacy))
        )
        let catalog = try ConversationAgentProfileCatalog(
            profiles: [refreshed, fixture.headB],
            defaultProfileID: refreshed.id
        )
        let service = AgentRoomsAgentAssignmentService(
            repository: fixture.repository,
            catalog: catalog,
            now: { timestamp(3) }
        )
        let assignment = try service.assign(profileID: refreshed.id, roomID: fixture.room.id)

        #expect(assignment.schemaVersion == 1)
        #expect(assignment.profile == refreshed)
        #expect(assignment.headRoutingEpoch == 0)
        #expect(try fixture.repository.messages(roomID: fixture.room.id).isEmpty)
    }

    @Test("head mutation boundary persists the validated caller actor")
    func explicitHeadMutationActorIsPreserved() throws {
        let fixture = try makeFixture(title: "Attributed mutation")
        defer { fixture.cleanup() }
        let assignment = try fixture.repository.setAgentAssignment(
            roomID: fixture.room.id,
            assignment: .init(profile: fixture.headB, assignedAt: timestamp(4)),
            actor: .migration,
            at: timestamp(4)
        )
        let eventMessage = try #require(
            try fixture.repository.messages(roomID: fixture.room.id)
                .first(where: { $0.role == "system" })
        )
        let event = try decodeEvent(eventMessage.metadata)

        #expect(assignment.headRoutingEpoch == 2)
        #expect(event.actor == .migration)
    }

    @Test("published held terminated and race terminal outcomes are idempotent")
    func terminalOutcomesAreIdempotent() throws {
        do {
            let fixture = try makeFixture(title: "Published replay")
            defer { fixture.cleanup() }
            let state = try #require(
                try fixture.persistence.restoreCanonicalRoom(id: fixture.room.id)?.conversationState
            )
            let attempt = try beginAttempt(
                fixture,
                clientID: "cider-room-client:published-replay",
                text: "Publish once"
            )
            let envelope = completion(
                state: state,
                text: "Publish once",
                answer: "One durable answer",
                runID: "run-published-replay",
                sessionID: "session-published-replay"
            )
            #expect(try fixture.persistence.complete(
                attempt,
                completion: envelope,
                expectedText: "Publish once",
                activity: []
            ) == .published)
            #expect(try fixture.persistence.complete(
                attempt,
                completion: envelope,
                expectedText: "Publish once",
                activity: []
            ) == .published)
            #expect(try fixture.persistence.terminate(
                attempt,
                status: .cancelled,
                runID: "run-published-replay",
                partialAssistantText: "One durable answer",
                activity: [],
                at: timestamp(5)
            ) == .published)
            #expect(throws: AgentRoomsConversationPersistenceError.authorityMismatch) {
                try fixture.persistence.terminate(
                    attempt,
                    status: .cancelled,
                    runID: nil,
                    partialAssistantText: "One durable answer",
                    activity: [],
                    at: timestamp(6)
                )
            }
            let canonicalPublishedTurn = try #require(
                try fixture.repository.turn(id: attempt.turnID)
            )
            let canonicalPublishedMessages = try fixture.repository.messages(
                roomID: fixture.room.id
            )
            #expect(throws: AgentRoomsConversationPersistenceError.authorityMismatch) {
                try fixture.persistence.terminate(
                    attempt,
                    status: .failed,
                    runID: "run-published-replay",
                    partialAssistantText: "One durable answer",
                    activity: [],
                    at: timestamp(7)
                )
            }
            #expect(throws: AgentRoomsConversationPersistenceError.authorityMismatch) {
                try fixture.persistence.terminate(
                    attempt,
                    status: .cancelled,
                    runID: "run-published-replay",
                    partialAssistantText: "Changed terminal partial",
                    activity: [],
                    at: timestamp(7)
                )
            }
            #expect(try fixture.repository.turn(id: attempt.turnID)
                == canonicalPublishedTurn)
            #expect(try fixture.repository.messages(roomID: fixture.room.id)
                == canonicalPublishedMessages)
            #expect(try fixture.repository.messages(roomID: fixture.room.id)
                .filter { $0.role == "assistant" }.count == 1)
            #expect(throws: AgentRoomsConversationPersistenceError.authorityMismatch) {
                try fixture.persistence.complete(
                    attempt,
                    completion: completion(
                        state: state,
                        text: "Publish once",
                        answer: "Changed answer",
                        runID: "run-published-replay",
                        sessionID: "session-published-replay"
                    ),
                    expectedText: "Publish once",
                    activity: []
                )
            }
            let forged = AgentRoomsConversationAttempt(
                roomID: attempt.roomID,
                turnID: attempt.turnID,
                clientMessageID: attempt.clientMessageID,
                userMessageID: attempt.userMessageID,
                assistantMessageID: attempt.assistantMessageID,
                createdAt: attempt.createdAt,
                routingContext: .init(
                    recipient: attempt.routingContext.recipient,
                    observedHeadRoutingEpoch:
                        attempt.routingContext.observedHeadRoutingEpoch + 1,
                    observedRoomMessageSequence:
                        attempt.routingContext.observedRoomMessageSequence,
                    originatingUserMessageID:
                        attempt.routingContext.originatingUserMessageID
                )
            )
            #expect(throws: AgentRoomsConversationPersistenceError.authorityMismatch) {
                try fixture.persistence.complete(
                    forged,
                    completion: envelope,
                    expectedText: "Publish once",
                    activity: []
                )
            }
        }

        do {
            let fixture = try makeFixture(title: "Held replay")
            defer { fixture.cleanup() }
            let state = try #require(
                try fixture.persistence.restoreCanonicalRoom(id: fixture.room.id)?.conversationState
            )
            let attempt = try beginAttempt(
                fixture,
                clientID: "cider-room-client:held-replay",
                text: "Hold once"
            )
            _ = try fixture.assignments.assign(profileID: fixture.headB.id, roomID: fixture.room.id)
            let envelope = completion(
                state: state,
                text: "Hold once",
                answer: "One held answer",
                runID: "run-held-replay",
                sessionID: "session-held-replay"
            )
            #expect(try fixture.persistence.complete(
                attempt,
                completion: envelope,
                expectedText: "Hold once",
                activity: []
            ) == .heldStale)
            #expect(try fixture.persistence.complete(
                attempt,
                completion: envelope,
                expectedText: "Hold once",
                activity: []
            ) == .heldStale)
        }

        do {
            let fixture = try makeFixture(title: "Termination replay")
            defer { fixture.cleanup() }
            let state = try #require(
                try fixture.persistence.restoreCanonicalRoom(id: fixture.room.id)?.conversationState
            )
            let attempt = try beginAttempt(
                fixture,
                clientID: "cider-room-client:terminate-replay",
                text: "Cancel once"
            )
            try fixture.persistence.markRunStarted(
                attempt,
                runID: "run-terminate-replay",
                activity: [],
                at: timestamp(1)
            )
            #expect(try fixture.persistence.terminate(
                attempt,
                status: .cancelled,
                runID: "run-terminate-replay",
                partialAssistantText: "Durable partial",
                activity: [],
                at: timestamp(2)
            ) == .terminated)
            #expect(try fixture.persistence.terminate(
                attempt,
                status: .cancelled,
                runID: "run-terminate-replay",
                partialAssistantText: "Durable partial",
                activity: [],
                at: timestamp(3)
            ) == .terminated)
            #expect(throws: AgentRoomsConversationPersistenceError.authorityMismatch) {
                try fixture.persistence.terminate(
                    attempt,
                    status: .cancelled,
                    runID: "run-terminate-replay",
                    partialAssistantText: "Changed partial",
                    activity: [],
                    at: timestamp(4)
                )
            }
            #expect(throws: AgentRoomsConversationPersistenceError.authorityMismatch) {
                try fixture.persistence.complete(
                    attempt,
                    completion: completion(
                        state: state,
                        text: "Cancel once",
                        answer: "Durable partial",
                        runID: "run-terminate-replay",
                        sessionID: "session-terminate-replay"
                    ),
                    expectedText: "Cancel once",
                    activity: []
                )
            }
            let canonicalTerminatedTurn = try #require(
                try fixture.repository.turn(id: attempt.turnID)
            )
            let canonicalTerminatedMessages = try fixture.repository.messages(
                roomID: fixture.room.id
            )
            let conflictingCompletions = [
                completion(
                    state: state,
                    text: "Cancel once",
                    answer: "Changed body",
                    runID: "run-terminate-replay",
                    sessionID: "session-terminate-replay"
                ),
                completion(
                    state: state,
                    text: "Cancel once",
                    answer: "Durable partial",
                    runID: "run-terminate-replay",
                    sessionID: "changed-session"
                ),
                completion(
                    state: state,
                    text: "Cancel once",
                    answer: "Durable partial",
                    runID: "run-terminate-replay",
                    sessionID: "session-terminate-replay",
                    modelIdentity: "changed-model"
                ),
                completion(
                    state: state,
                    text: "Cancel once",
                    answer: "Durable partial",
                    runID: "run-terminate-replay",
                    sessionID: "session-terminate-replay",
                    sourceName: "Changed source"
                ),
            ]
            for conflicting in conflictingCompletions {
                #expect(throws: AgentRoomsConversationPersistenceError.authorityMismatch) {
                    try fixture.persistence.complete(
                        attempt,
                        completion: conflicting,
                        expectedText: "Cancel once",
                        activity: []
                    )
                }
            }
            #expect(try fixture.repository.turn(id: attempt.turnID)
                == canonicalTerminatedTurn)
            #expect(try fixture.repository.messages(roomID: fixture.room.id)
                == canonicalTerminatedMessages)

            fixture.database.close()
            let reopenedDatabase = CiderDatabase()
            try reopenedDatabase.open(at: fixture.url)
            let reopenedPersistence = AgentRoomsConversationPersistence(
                database: reopenedDatabase,
                repository: ConversationRepository(database: reopenedDatabase),
                defaultAgentProfile: fixture.headA,
                participantProfiles: fixture.catalog.profiles
            )
            #expect(throws: AgentRoomsConversationPersistenceError.authorityMismatch) {
                try reopenedPersistence.complete(
                    attempt,
                    completion: completion(
                        state: state,
                        text: "Cancel once",
                        answer: "Durable partial",
                        runID: "run-terminate-replay",
                        sessionID: "session-terminate-replay"
                    ),
                    expectedText: "Cancel once",
                    activity: []
                )
            }
            #expect(try reopenedPersistence.restoreCanonicalRoom(id: fixture.room.id) != nil)
            reopenedDatabase.close()
        }

        do {
            let fixture = try makeFixture(title: "Held termination replay")
            defer { fixture.cleanup() }
            let attempt = try beginAttempt(
                fixture,
                clientID: "cider-room-client:held-terminate-replay",
                text: "Cancel after change"
            )
            try fixture.persistence.markRunStarted(
                attempt,
                runID: "run-held-terminate-replay",
                activity: [],
                at: timestamp(1)
            )
            _ = try fixture.assignments.assign(profileID: fixture.headB.id, roomID: fixture.room.id)
            #expect(try fixture.persistence.terminate(
                attempt,
                status: .cancelled,
                runID: "run-held-terminate-replay",
                partialAssistantText: "Held cancellation partial",
                activity: [],
                at: timestamp(2)
            ) == .heldStale)
            #expect(try fixture.persistence.terminate(
                attempt,
                status: .cancelled,
                runID: "run-held-terminate-replay",
                partialAssistantText: "Held cancellation partial",
                activity: [],
                at: timestamp(3)
            ) == .heldStale)
        }
    }

    @Test("complete replay envelope is exact and zero-mutation across physical reopen")
    func completionReplayEnvelopeIsExactAcrossReopen() throws {
        let fixture = try makeFixture(title: "Complete envelope reopen")
        defer { fixture.cleanup() }
        let state = try #require(
            try fixture.persistence.restoreCanonicalRoom(id: fixture.room.id)?
                .conversationState
        )
        let attempt = try beginAttempt(
            fixture,
            clientID: "cider-room-client:complete-envelope-reopen",
            text: "Persist every completion fact"
        )
        let facts = completionReplayFacts()
        let activity = completionReplayActivity()
        let envelope = completion(
            state: state,
            text: "Persist every completion fact",
            answer: "Every fact is durable.",
            runID: "run-complete-envelope-reopen",
            sessionID: "session-complete-envelope-reopen",
            ciderReferences: facts.references,
            contextCheckpointFactState: .validated,
            contextCheckpoint: facts.context,
            approvalFactState: .validated,
            approvalRequests: facts.approvals,
            attachmentFactState: .validated,
            attachments: facts.attachments,
            generatedArtifactFactState: .validated,
            generatedArtifacts: facts.generatedArtifacts
        )

        #expect(try fixture.persistence.complete(
            attempt,
            completion: envelope,
            expectedText: "Persist every completion fact",
            activity: activity
        ) == .published)
        let committed = try durableFingerprint(
            url: fixture.url,
            roomID: fixture.room.id
        )
        #expect(try fixture.persistence.complete(
            attempt,
            completion: envelope,
            expectedText: "Persist every completion fact",
            activity: activity
        ) == .published)
        #expect(try durableFingerprint(
            url: fixture.url,
            roomID: fixture.room.id
        ) == committed)

        fixture.database.close()
        let reopenedDatabase = CiderDatabase()
        try reopenedDatabase.open(at: fixture.url)
        let reopenedPersistence = AgentRoomsConversationPersistence(
            database: reopenedDatabase,
            repository: ConversationRepository(database: reopenedDatabase),
            defaultAgentProfile: fixture.headA,
            participantProfiles: fixture.catalog.profiles
        )
        #expect(try reopenedPersistence.complete(
            attempt,
            completion: envelope,
            expectedText: "Persist every completion fact",
            activity: activity
        ) == .published)
        #expect(try reopenedPersistence.restoreCanonicalRoom(
            id: fixture.room.id
        ) != nil)
        let reopenedRepository = ConversationRepository(
            database: reopenedDatabase
        )
        #expect(try reopenedRepository.turns(roomID: fixture.room.id).count == 1)
        #expect(try reopenedRepository.messages(roomID: fixture.room.id)
            .filter { $0.role == "assistant" }.count == 1)
        reopenedDatabase.close()
        #expect(try durableFingerprint(
            url: fixture.url,
            roomID: fixture.room.id
        ) == committed)
    }

    @Test("activity-only completion replay conflict is typed and zero-mutation")
    func completionReplayRejectsActivityConflict() throws {
        let fixture = try makeFixture(title: "Activity envelope conflict")
        defer { fixture.cleanup() }
        let state = try #require(
            try fixture.persistence.restoreCanonicalRoom(id: fixture.room.id)?
                .conversationState
        )
        let attempt = try beginAttempt(
            fixture,
            clientID: "cider-room-client:activity-envelope-conflict",
            text: "Bind activity"
        )
        let envelope = completion(
            state: state,
            text: "Bind activity",
            answer: "Activity is ordered.",
            runID: "run-activity-envelope-conflict",
            sessionID: "session-activity-envelope-conflict"
        )
        let activity = completionReplayActivity()
        #expect(try fixture.persistence.complete(
            attempt,
            completion: envelope,
            expectedText: "Bind activity",
            activity: activity
        ) == .published)
        let committed = try durableFingerprint(
            url: fixture.url,
            roomID: fixture.room.id
        )
        let changed = [
            activity[0],
            AgentRoomsLiveActivity(
                id: UUID(),
                kind: activity[1].kind,
                detail: "Changed tool provenance"
            ),
        ]
        #expect(throws: AgentRoomsConversationPersistenceError.authorityMismatch) {
            try fixture.persistence.complete(
                attempt,
                completion: envelope,
                expectedText: "Bind activity",
                activity: changed
            )
        }
        #expect(try durableFingerprint(
            url: fixture.url,
            roomID: fixture.room.id
        ) == committed)
    }

    @Test("every structured completion fact family rejects an independent conflict")
    func completionReplayRejectsEveryStructuredFactConflict() throws {
        let fixture = try makeFixture(title: "Structured envelope conflicts")
        defer { fixture.cleanup() }
        let state = try #require(
            try fixture.persistence.restoreCanonicalRoom(id: fixture.room.id)?
                .conversationState
        )
        let attempt = try beginAttempt(
            fixture,
            clientID: "cider-room-client:structured-envelope-conflicts",
            text: "Bind structured facts"
        )
        let facts = completionReplayFacts()
        let activity = completionReplayActivity()
        let canonical = completionWithReplayFacts(
            state: state,
            text: "Bind structured facts",
            answer: "Structured facts are exact.",
            runID: "run-structured-envelope-conflicts",
            sessionID: "session-structured-envelope-conflicts",
            facts: facts
        )
        #expect(try fixture.persistence.complete(
            attempt,
            completion: canonical,
            expectedText: "Bind structured facts",
            activity: activity
        ) == .published)
        let committed = try durableFingerprint(
            url: fixture.url,
            roomID: fixture.room.id
        )

        var variants: [CompletionReplayTestFacts] = []
        var references = facts
        references.references[0] = changedReference(
            references.references[0],
            title: "Changed reference title"
        )
        variants.append(references)

        var context = facts
        context.context = HermesCiderContextCheckpoint(
            id: "context-envelope-b",
            selected: context.context.selected,
            citations: context.context.citations,
            omissionReason: nil,
            source: "cider",
            sourceRef: "context_checkpoint:context-envelope-b"
        )
        variants.append(context)

        var approvals = facts
        let approval = approvals.approvals[0]
        approvals.approvals[0] = HermesApprovalRequest(
            id: approval.id,
            action: approval.action,
            target: approval.target,
            risk: approval.risk,
            scope: approval.scope,
            status: "approved",
            source: approval.source,
            sourceRef: approval.sourceRef
        )
        variants.append(approvals)

        var attachments = facts
        let attachment = attachments.attachments[0]
        attachments.attachments[0] = HermesCiderAttachment(
            id: attachment.id,
            target: attachment.target,
            displayName: "changed-input.pdf",
            contentType: attachment.contentType,
            byteSize: attachment.byteSize,
            provenance: attachment.provenance,
            source: attachment.source,
            sourceRef: attachment.sourceRef,
            sha256: attachment.sha256,
            inputSource: attachment.inputSource,
            lifecycle: attachment.lifecycle
        )
        variants.append(attachments)

        var artifacts = facts
        let artifact = artifacts.generatedArtifacts[0]
        artifacts.generatedArtifacts[0] = HermesCiderGeneratedArtifact(
            id: artifact.id,
            target: artifact.target,
            displayName: "Changed output.md",
            contentType: artifact.contentType,
            byteSize: artifact.byteSize,
            provenance: artifact.provenance,
            source: artifact.source,
            sourceRef: artifact.sourceRef
        )
        variants.append(artifacts)

        for variant in variants {
            #expect(throws: AgentRoomsConversationPersistenceError.authorityMismatch) {
                try fixture.persistence.complete(
                    attempt,
                    completion: completionWithReplayFacts(
                        state: state,
                        text: "Bind structured facts",
                        answer: "Structured facts are exact.",
                        runID: "run-structured-envelope-conflicts",
                        sessionID: "session-structured-envelope-conflicts",
                        facts: variant
                    ),
                    expectedText: "Bind structured facts",
                    activity: activity
                )
            }
            #expect(try durableFingerprint(
                url: fixture.url,
                roomID: fixture.room.id
            ) == committed)
        }
    }

    @Test("completion identity body model session and routing controls remain exact")
    func completionReplayRejectsIdentityAndRoutingConflicts() throws {
        let fixture = try makeFixture(title: "Completion control conflicts")
        defer { fixture.cleanup() }
        let state = try #require(
            try fixture.persistence.restoreCanonicalRoom(id: fixture.room.id)?
                .conversationState
        )
        let attempt = try beginAttempt(
            fixture,
            clientID: "cider-room-client:completion-control-conflicts",
            text: "Bind controls"
        )
        let envelope = completion(
            state: state,
            text: "Bind controls",
            answer: "Control answer",
            runID: "run-completion-control-conflicts",
            sessionID: "session-completion-control-conflicts"
        )
        #expect(try fixture.persistence.complete(
            attempt,
            completion: envelope,
            expectedText: "Bind controls",
            activity: []
        ) == .published)
        let committed = try durableFingerprint(
            url: fixture.url,
            roomID: fixture.room.id
        )
        let conflicts = [
            completion(
                state: state,
                text: "Bind controls",
                answer: "Changed answer",
                runID: "run-completion-control-conflicts",
                sessionID: "session-completion-control-conflicts"
            ),
            completion(
                state: state,
                text: "Bind controls",
                answer: "Control answer",
                runID: "run-completion-control-conflicts",
                sessionID: "changed-session"
            ),
            completion(
                state: state,
                text: "Bind controls",
                answer: "Control answer",
                runID: "run-completion-control-conflicts",
                sessionID: "session-completion-control-conflicts",
                modelIdentity: "changed-model"
            ),
            completion(
                state: state,
                text: "Changed accepted user",
                answer: "Control answer",
                runID: "run-completion-control-conflicts",
                sessionID: "session-completion-control-conflicts"
            ),
        ]
        for (index, conflict) in conflicts.enumerated() {
            #expect(throws: AgentRoomsConversationPersistenceError.authorityMismatch) {
                try fixture.persistence.complete(
                    attempt,
                    completion: conflict,
                    expectedText: index == 3
                        ? "Changed accepted user" : "Bind controls",
                    activity: []
                )
            }
        }
        let forgedAttempt = AgentRoomsConversationAttempt(
            roomID: attempt.roomID,
            turnID: attempt.turnID,
            clientMessageID: attempt.clientMessageID,
            userMessageID: attempt.userMessageID,
            assistantMessageID: attempt.assistantMessageID,
            createdAt: attempt.createdAt,
            routingContext: .init(
                recipient: attempt.routingContext.recipient,
                observedHeadRoutingEpoch:
                    attempt.routingContext.observedHeadRoutingEpoch,
                observedRoomMessageSequence:
                    attempt.routingContext.observedRoomMessageSequence + 1,
                originatingUserMessageID:
                    attempt.routingContext.originatingUserMessageID
            )
        )
        #expect(throws: AgentRoomsConversationPersistenceError.authorityMismatch) {
            try fixture.persistence.complete(
                forgedAttempt,
                completion: envelope,
                expectedText: "Bind controls",
                activity: []
            )
        }
        #expect(try durableFingerprint(
            url: fixture.url,
            roomID: fixture.room.id
        ) == committed)
    }

    @Test("set-like completion facts reorder while ordered activity conflicts")
    func completionReplayNormalizationIsDeliberate() throws {
        let fixture = try makeFixture(title: "Completion normalization")
        defer { fixture.cleanup() }
        let state = try #require(
            try fixture.persistence.restoreCanonicalRoom(id: fixture.room.id)?
                .conversationState
        )
        let attempt = try beginAttempt(
            fixture,
            clientID: "cider-room-client:completion-normalization",
            text: "Normalize only sets"
        )
        let facts = completionReplayFacts()
        let activity = completionReplayActivity()
        #expect(try fixture.persistence.complete(
            attempt,
            completion: completionWithReplayFacts(
                state: state,
                text: "Normalize only sets",
                answer: "Set order is presentation-neutral.",
                runID: "run-completion-normalization",
                sessionID: "session-completion-normalization",
                facts: facts
            ),
            expectedText: "Normalize only sets",
            activity: activity
        ) == .published)
        let committed = try durableFingerprint(
            url: fixture.url,
            roomID: fixture.room.id
        )
        var reordered = facts
        reordered.references.reverse()
        reordered.context = HermesCiderContextCheckpoint(
            id: reordered.context.id,
            selected: Array(reordered.context.selected.reversed()),
            citations: Array(reordered.context.citations.reversed()),
            omissionReason: reordered.context.omissionReason,
            source: reordered.context.source,
            sourceRef: reordered.context.sourceRef
        )
        reordered.approvals.reverse()
        reordered.attachments.reverse()
        reordered.generatedArtifacts.reverse()
        #expect(try fixture.persistence.complete(
            attempt,
            completion: completionWithReplayFacts(
                state: state,
                text: "Normalize only sets",
                answer: "Set order is presentation-neutral.",
                runID: "run-completion-normalization",
                sessionID: "session-completion-normalization",
                facts: reordered
            ),
            expectedText: "Normalize only sets",
            activity: activity
        ) == .published)
        #expect(try durableFingerprint(
            url: fixture.url,
            roomID: fixture.room.id
        ) == committed)

        var exactDuplicate = reordered
        exactDuplicate.references.append(exactDuplicate.references[0])
        #expect(try fixture.persistence.complete(
            attempt,
            completion: completionWithReplayFacts(
                state: state,
                text: "Normalize only sets",
                answer: "Set order is presentation-neutral.",
                runID: "run-completion-normalization",
                sessionID: "session-completion-normalization",
                facts: exactDuplicate
            ),
            expectedText: "Normalize only sets",
            activity: activity
        ) == .published)

        var conflictingProvenance = reordered
        conflictingProvenance.references.append(changedReference(
            conflictingProvenance.references[0],
            title: "Conflicting duplicate provenance"
        ))
        #expect(throws: AgentRoomsConversationPersistenceError.authorityMismatch) {
            try fixture.persistence.complete(
                attempt,
                completion: completionWithReplayFacts(
                    state: state,
                    text: "Normalize only sets",
                    answer: "Set order is presentation-neutral.",
                    runID: "run-completion-normalization",
                    sessionID: "session-completion-normalization",
                    facts: conflictingProvenance
                ),
                expectedText: "Normalize only sets",
                activity: activity
            )
        }

        #expect(throws: AgentRoomsConversationPersistenceError.authorityMismatch) {
            try fixture.persistence.complete(
                attempt,
                completion: completionWithReplayFacts(
                    state: state,
                    text: "Normalize only sets",
                    answer: "Set order is presentation-neutral.",
                    runID: "run-completion-normalization",
                    sessionID: "session-completion-normalization",
                    facts: reordered
                ),
                expectedText: "Normalize only sets",
                activity: Array(activity.reversed())
            )
        }
        #expect(try durableFingerprint(
            url: fixture.url,
            roomID: fixture.room.id
        ) == committed)
    }

    @Test("held attributed and termination outcomes use exact replay envelopes")
    func allTerminalShapesUseExactReplayValidation() throws {
        do {
            let fixture = try makeFixture(title: "Held complete envelope")
            defer { fixture.cleanup() }
            let state = try #require(
                try fixture.persistence.restoreCanonicalRoom(id: fixture.room.id)?
                    .conversationState
            )
            let attempt = try beginAttempt(
                fixture,
                clientID: "cider-room-client:held-complete-envelope",
                text: "Hold complete envelope"
            )
            _ = try fixture.assignments.assign(
                profileID: fixture.headB.id,
                roomID: fixture.room.id
            )
            let facts = completionReplayFacts()
            let envelope = completionWithReplayFacts(
                state: state,
                text: "Hold complete envelope",
                answer: "Held exact answer",
                runID: "run-held-complete-envelope",
                sessionID: "session-held-complete-envelope",
                facts: facts
            )
            #expect(try fixture.persistence.complete(
                attempt,
                completion: envelope,
                expectedText: "Hold complete envelope",
                activity: completionReplayActivity()
            ) == .heldStale)
            let committed = try durableFingerprint(
                url: fixture.url,
                roomID: fixture.room.id
            )
            #expect(try fixture.persistence.complete(
                attempt,
                completion: envelope,
                expectedText: "Hold complete envelope",
                activity: completionReplayActivity()
            ) == .heldStale)
            var changed = facts
            changed.references[0] = changedReference(
                changed.references[0],
                title: "Changed held reference"
            )
            #expect(throws: AgentRoomsConversationPersistenceError.authorityMismatch) {
                try fixture.persistence.complete(
                    attempt,
                    completion: completionWithReplayFacts(
                        state: state,
                        text: "Hold complete envelope",
                        answer: "Held exact answer",
                        runID: "run-held-complete-envelope",
                        sessionID: "session-held-complete-envelope",
                        facts: changed
                    ),
                    expectedText: "Hold complete envelope",
                    activity: completionReplayActivity()
                )
            }
            #expect(try durableFingerprint(
                url: fixture.url,
                roomID: fixture.room.id
            ) == committed)
        }

        do {
            let fixture = try makeFixture(title: "Attributed complete envelope")
            defer { fixture.cleanup() }
            let state = try #require(
                try fixture.persistence.restoreCanonicalRoom(id: fixture.room.id)?
                    .conversationState
            )
            let member = try #require(
                try fixture.repository.participantRoster(roomID: fixture.room.id)?
                    .members.first(where: { $0.profile.id == fixture.headB.id })
            )
            let attribution = ConversationParticipantRunAttribution(
                invocationID: UUID(),
                runID: UUID(),
                participantID: member.id,
                profileID: member.profile.id,
                displayName: member.profile.displayName,
                participantRole: member.role,
                selectionSequence: 1
            )
            let attempt = try fixture.persistence.beginAttributedAttempt(
                roomID: fixture.room.id,
                roomTitle: fixture.room.title,
                isReservedTestChat: false,
                attemptID: attribution.invocationID,
                clientMessageID: "cider-room-client:attributed-complete-envelope",
                userMessageID: UUID(),
                assistantMessageID: UUID(),
                text: "Attributed exactness",
                attribution: attribution,
                at: timestamp(0)
            )
            let envelope = completion(
                state: state,
                text: "Attributed exactness",
                answer: "Attributed answer",
                runID: "run-attributed-complete-envelope",
                sessionID: "session-attributed-complete-envelope"
            )
            #expect(try fixture.persistence.complete(
                attempt,
                completion: envelope,
                expectedText: "Attributed exactness",
                activity: []
            ) == .published)
            let committed = try durableFingerprint(
                url: fixture.url,
                roomID: fixture.room.id
            )
            #expect(try fixture.persistence.complete(
                attempt,
                completion: envelope,
                expectedText: "Attributed exactness",
                activity: []
            ) == .published)
            #expect(try durableFingerprint(
                url: fixture.url,
                roomID: fixture.room.id
            ) == committed)
        }

        for status in [ConversationTurnStatus.cancelled, .failed] {
            let fixture = try makeFixture(
                title: status == .cancelled
                    ? "Cancelled exact envelope" : "Failed exact envelope"
            )
            let attempt = try beginAttempt(
                fixture,
                clientID: "cider-room-client:terminal-\(status.rawValue)",
                text: "Terminate exactly"
            )
            try fixture.persistence.markRunStarted(
                attempt,
                runID: "run-terminal-\(status.rawValue)",
                activity: completionReplayActivity(),
                at: timestamp(1)
            )
            #expect(try fixture.persistence.terminate(
                attempt,
                status: status,
                runID: "run-terminal-\(status.rawValue)",
                partialAssistantText: "Durable terminal partial",
                activity: completionReplayActivity(),
                at: timestamp(2)
            ) == .terminated)
            let committed = try durableFingerprint(
                url: fixture.url,
                roomID: fixture.room.id
            )
            #expect(try fixture.persistence.terminate(
                attempt,
                status: status,
                runID: "run-terminal-\(status.rawValue)",
                partialAssistantText: "Durable terminal partial",
                activity: completionReplayActivity(),
                at: timestamp(3)
            ) == .terminated)
            #expect(throws: AgentRoomsConversationPersistenceError.authorityMismatch) {
                try fixture.persistence.terminate(
                    attempt,
                    status: status,
                    runID: "run-terminal-\(status.rawValue)",
                    partialAssistantText: "Durable terminal partial",
                    activity: Array(completionReplayActivity().reversed()),
                    at: timestamp(4)
                )
            }
            #expect(try durableFingerprint(
                url: fixture.url,
                roomID: fixture.room.id
            ) == committed)
            fixture.cleanup()
        }
    }

    @Test("terminal replay source shape has one complete envelope comparison and no replay writes")
    func terminalReplaySourceShapeUsesCompleteEnvelope() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent(
                "Sources/Cider/Services/Conversation/AgentRoomsConversationPersistence.swift"
            )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let productionRoot = repositoryRoot.appendingPathComponent("Sources/Cider")
        let swiftFiles = try #require(
            FileManager.default.enumerator(
                at: productionRoot,
                includingPropertiesForKeys: nil
            )?.allObjects as? [URL]
        ).filter { $0.pathExtension == "swift" }
        #expect(swiftFiles.count > 100)
        let productionSource = try swiftFiles
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        #expect(source.components(
            separatedBy: "canonicalTerminalOutcome(for: attempt)"
        ).count - 1 == 2)
        #expect(source.contains("try validateCompletionReplay("))
        #expect(source.contains("try validateTerminationReplay("))
        #expect(source.contains("let requested = try completionReplayEnvelope("))
        #expect(source.contains("let canonical = try canonicalCompletionReplayEnvelope("))
        #expect(source.contains("guard requested == canonical else"))
        #expect(!source.contains("recordExactReplay("))
        #expect(!source.contains("updateTerminalTurnMetadata("))
        #expect(!productionSource.contains("cross-operation-completion-replay"))
        #expect(!productionSource.contains("CompletionReplayFacts"))
        #expect(!productionSource.contains("completionReplayFacts("))
        #expect(!productionSource.contains("updateTerminalTurnMetadata("))
    }

    @Test("live stream and cancellation show former-head output as held before and after reopen")
    func liveStaleTruthIsImmediate() async throws {
        for cancel in [false, true] {
            let fixture = try makeFixture(title: cancel ? "Live cancel" : "Live completion")
            let state = try #require(
                try fixture.persistence.restoreCanonicalRoom(id: fixture.room.id)?.conversationState
            )
            let transport = HeadRoutingHardeningTransport(
                completion: completion(
                    state: state,
                    text: "Stream across change",
                    answer: "Former-head final",
                    runID: cancel ? "run-live-cancel" : "run-live-complete",
                    sessionID: cancel ? "session-live-cancel" : "session-live-complete"
                )
            )
            let model = AgentRoomsLiveChatModel(
                transport: transport,
                turnCoordinator: HermesTurnCoordinator(),
                savedBookmarkMatches: { _ in [] },
                persistence: fixture.persistence,
                agentAssignments: fixture.assignments
            )
            #expect(model.activateCanonicalRoom(id: fixture.room.id))
            await model.refreshTransportReadiness()
            let sendTask = Task {
                await model.send(
                    "Stream across change",
                    selectedRoomID: fixture.room.id.uuidString
                )
            }
            await transport.waitUntilStarted()
            await transport.emit(.messageDelta("Former "))
            #expect(model.activeRoom?.transcript.messages.last?.deliveryState == .sent)
            _ = try fixture.assignments.assign(profileID: fixture.headB.id, roomID: fixture.room.id)
            let live = try #require(model.activeRoom?.transcript.messages.last)
            #expect(live.author == fixture.headA.displayName)
            #expect(live.body == "Former ")
            #expect(live.deliveryState == .held)

            if cancel {
                await model.cancelActiveSend()
            } else {
                await transport.release()
            }
            await sendTask.value
            let final = try #require(model.activeRoom?.transcript.messages.last)
            #expect(final.author == fixture.headA.displayName)
            #expect(final.deliveryState == .held)
            #expect(model.activeRoom?.transcript.receipt?.detail.contains("Held for review") == true)
            let reopened = try #require(
                try fixture.persistence.restoreCanonicalRoom(id: fixture.room.id)
            )
            #expect(reopened.presentationMessages.last?.deliveryState == .held)
            fixture.cleanup()
        }
    }

    @Test("cancellation reports terminal persistence failure instead of ordinary cancellation")
    func cancellationPersistenceFailureIsTruthful() async throws {
        let fixture = try makeFixture(title: "Cancellation persistence failure")
        defer { fixture.cleanup() }
        let state = try #require(
            try fixture.persistence.restoreCanonicalRoom(id: fixture.room.id)?.conversationState
        )
        let transport = HeadRoutingHardeningTransport(
            completion: completion(
                state: state,
                text: "Cancel with storage failure",
                answer: "Never committed",
                runID: "run-cancel-persistence-failure",
                sessionID: "session-cancel-persistence-failure"
            )
        )
        let model = AgentRoomsLiveChatModel(
            transport: transport,
            turnCoordinator: HermesTurnCoordinator(),
            savedBookmarkMatches: { _ in [] },
            persistence: FailingTerminationPersistence(base: fixture.persistence),
            agentAssignments: fixture.assignments
        )
        #expect(model.activateCanonicalRoom(id: fixture.room.id))
        await model.refreshTransportReadiness()
        let sendTask = Task {
            await model.send(
                "Cancel with storage failure",
                selectedRoomID: fixture.room.id.uuidString
            )
        }
        await transport.waitUntilStarted()
        await transport.emit(.messageDelta("Uncommitted partial"))
        await model.cancelActiveSend()
        await sendTask.value

        #expect(model.turnState == .failed)
        #expect(model.composerMessage?.contains("could not durably record") == true)
        #expect(model.activeRoom?.transcript.receipt?.title
            == "Cancellation persistence failed")
        #expect(model.activeRoom?.transcript.receipt?.status == .failed)
        #expect(model.activeRoom?.transcript.receipt?.detail
            == "Provider stop requested · Durable terminal state unconfirmed")
        #expect(try fixture.repository.turns(roomID: fixture.room.id).last?.status == .running)
    }

    @Test("transport CancellationError preserves unresolved truth when termination persistence fails")
    func transportCancellationPersistenceFailureIsTruthful() async throws {
        try await verifyTransportTermination(
            failure: .cancellation,
            injectedPersistenceFailure: true
        )
        try await verifyTransportTermination(
            failure: .cancellation,
            injectedPersistenceFailure: false
        )
    }

    @Test("generic transport error preserves unresolved truth when termination persistence fails")
    func transportErrorPersistenceFailureIsTruthful() async throws {
        try await verifyTransportTermination(
            failure: .generic,
            injectedPersistenceFailure: true
        )
        try await verifyTransportTermination(
            failure: .generic,
            injectedPersistenceFailure: false
        )
    }

    @Test("portable schema retains deterministic routing held and head-event provenance")
    func portableRoutingExportRoundTrip() throws {
        let fixture = try makeFixture(title: "Portable routing")
        defer { fixture.cleanup() }
        let state = try #require(
            try fixture.persistence.restoreCanonicalRoom(id: fixture.room.id)?.conversationState
        )
        let attempt = try beginAttempt(
            fixture,
            clientID: "cider-room-client:portable-routing",
            text: "Export routing"
        )
        _ = try fixture.assignments.assign(profileID: fixture.headB.id, roomID: fixture.room.id)
        #expect(try fixture.persistence.complete(
            attempt,
            completion: completion(
                state: state,
                text: "Export routing",
                answer: "Held export body",
                runID: "run-portable-routing",
                sessionID: "private-session-must-not-export"
            ),
            expectedText: "Export routing",
            activity: []
        ) == .heldStale)

        let exporter = AgentRoomsRoomExportService(repository: fixture.repository)
        let first = try exporter.render(roomID: fixture.room.id)
        let second = try exporter.render(roomID: fixture.room.id)
        let decoded = try JSONDecoder().decode(
            AgentRoomsRoomExportManifest.self,
            from: first.manifestData
        )
        let reencoded = try JSONDecoder().decode(
            AgentRoomsRoomExportManifest.self,
            from: second.manifestData
        )
        let heldMessage = try #require(decoded.messages.first(where: {
            $0.publicationState == .heldStale
        }))

        #expect(first.manifestData == second.manifestData)
        #expect(decoded == reencoded)
        #expect(decoded.schemaVersion == 3)
        #expect(decoded.room.selectedHead?.profileID == fixture.headB.id)
        #expect(decoded.room.headRoutingEpoch == 2)
        #expect(decoded.headRoutingEvents.count == 1)
        #expect(decoded.headRoutingEvents[0].actor == .user)
        #expect(decoded.messages.first(where: { $0.role == "user" })?.submissionRouting != nil)
        #expect(heldMessage.generatedRouting?.recipient.profileID == fixture.headA.id)
        #expect(heldMessage.observedCurrentHeadRoutingEpoch == 2)
        #expect(decoded.turns.last?.publicationState == .heldStale)
        let raw = String(decoding: first.manifestData, as: UTF8.self)
        #expect(!raw.contains("private-session-must-not-export"))
        #expect(!raw.contains("/Users/"))
        #expect(!raw.contains("file://"))
        #expect(!raw.lowercased().contains("secret"))
    }

    @Test("export uses one SQLite snapshot across a concurrent head change")
    func exportCannotTearAcrossConnections() throws {
        let fixture = try makeFixture(title: "Concurrent export snapshot")
        defer { fixture.cleanup() }
        let writerDatabase = CiderDatabase()
        try writerDatabase.open(at: fixture.url)
        defer { writerDatabase.close() }
        let writerRepository = ConversationRepository(database: writerDatabase)
        let writerAssignments = AgentRoomsAgentAssignmentService(
            repository: writerRepository,
            catalog: fixture.catalog,
            now: { timestamp(10) }
        )
        let beforeChangePackage = try AgentRoomsRoomExportService(
            repository: fixture.repository
        ).render(roomID: fixture.room.id)
        let beforeChange = try JSONDecoder().decode(
            AgentRoomsRoomExportManifest.self,
            from: beforeChangePackage.manifestData
        )
        let snapshot = try fixture.repository.withTransaction {
            let loadedRoom = try fixture.repository.room(id: fixture.room.id)
            let room = try #require(loadedRoom)
            let changedAssignment = try writerAssignments.assign(
                profileID: fixture.headB.id,
                roomID: fixture.room.id
            )
            let bindings = try fixture.repository.bindings(roomID: fixture.room.id)
            let turns = try fixture.repository.turns(roomID: fixture.room.id)
            let messages = try fixture.repository.messages(roomID: fixture.room.id)
            let roster = try fixture.repository.participantRoster(roomID: fixture.room.id)
            let assignment = try fixture.repository.agentAssignment(roomID: fixture.room.id)
            return (
                room,
                bindings,
                turns,
                messages,
                roster,
                assignment,
                changedAssignment
            )
        }
        let afterChangePackage = try AgentRoomsRoomExportService(
            repository: fixture.repository
        ).render(roomID: fixture.room.id)
        let repeatedAfterChangePackage = try AgentRoomsRoomExportService(
            repository: fixture.repository
        ).render(roomID: fixture.room.id)
        let afterChange = try JSONDecoder().decode(
            AgentRoomsRoomExportManifest.self,
            from: afterChangePackage.manifestData
        )

        #expect(snapshot.0.nextMessageSequence == 1)
        #expect(snapshot.1.isEmpty)
        #expect(snapshot.2.isEmpty)
        #expect(snapshot.3.isEmpty)
        #expect(snapshot.4?.members.map(\.profile.id) == fixture.catalog.profiles.map(\.id))
        #expect(snapshot.5?.profile.id == fixture.headA.id)
        #expect(snapshot.5?.headRoutingEpoch == 1)
        #expect(snapshot.6.profile.id == fixture.headB.id)
        #expect(snapshot.6.headRoutingEpoch == 2)
        #expect(beforeChange.room.selectedHead?.profileID == snapshot.5?.profile.id)
        #expect(beforeChange.room.headRoutingEpoch == snapshot.5?.headRoutingEpoch)
        #expect(beforeChange.headRoutingEvents.isEmpty)
        #expect(beforeChange.messages.allSatisfy {
            $0.headRoutingChangeEvent == nil
        })
        #expect(afterChange.room.selectedHead?.profileID == fixture.headB.id)
        #expect(afterChange.room.headRoutingEpoch == 2)
        #expect(afterChange.headRoutingEvents.count == 1)
        #expect(afterChange.headRoutingEvents.last?.newHead.profileID == fixture.headB.id)
        #expect(afterChange.headRoutingEvents.last?.newHeadRoutingEpoch == 2)
        #expect(afterChangePackage == repeatedAfterChangePackage)

        writerDatabase.close()
        fixture.database.close()
        let reopenedDatabase = CiderDatabase()
        try reopenedDatabase.open(at: fixture.url)
        defer { reopenedDatabase.close() }
        let reopenedPackage = try AgentRoomsRoomExportService(
            repository: ConversationRepository(database: reopenedDatabase)
        ).render(roomID: fixture.room.id)
        #expect(reopenedPackage == afterChangePackage)
        let raw = String(
            decoding: reopenedPackage.manifestData,
            as: UTF8.self
        )
        #expect(!raw.contains("/Users/"))
        #expect(!raw.contains("file://"))
    }

    @Test("production export source has no transactional callback or checkpoint seam")
    func productionExportSourceContainsNoTransactionalHooks() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appendingPathComponent(
            "Sources/Cider/Services/Conversation/AgentRoomsRoomExportService.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let renderStart = try #require(source.range(
            of: "func render(roomID: UUID) throws -> AgentRoomsRoomExportPackage"
        ))
        let exportStart = try #require(source.range(
            of: "func export(roomID: UUID, to destination: URL)",
            range: renderStart.upperBound..<source.endIndex
        ))
        let renderSource = source[renderStart.lowerBound..<exportStart.lowerBound]

        #expect(!source.contains("afterRoomRead"))
        #expect(!source.contains("beforeDiskWrite"))
        #expect(!source.contains("@MainActor () throws -> Void"))
        #expect(!source.contains("@Sendable () -> Void"))
        #expect(!source.contains("@escaping"))
        #expect(!renderSource.lowercased().contains("hook"))
        #expect(!renderSource.lowercased().contains("callback"))
        #expect(!renderSource.lowercased().contains("checkpoint"))
    }

    @Test(arguments: RoutingTamper.allCases)
    func relationalTamperingFailsPhysicalReopen(_ tamper: RoutingTamper) throws {
        if tamper == .contradictoryHeldState {
            let fixture = try makeFixture(title: "Held tamper")
            defer { fixture.cleanup() }
            let state = try #require(
                try fixture.persistence.restoreCanonicalRoom(id: fixture.room.id)?.conversationState
            )
            let attempt = try beginAttempt(
                fixture,
                clientID: "cider-room-client:held-tamper",
                text: "Hold for tamper"
            )
            _ = try fixture.assignments.assign(profileID: fixture.headB.id, roomID: fixture.room.id)
            _ = try fixture.persistence.complete(
                attempt,
                completion: completion(
                    state: state,
                    text: "Hold for tamper",
                    answer: "Held then contradicted",
                    runID: "run-held-tamper",
                    sessionID: "session-held-tamper"
                ),
                expectedText: "Hold for tamper",
                activity: []
            )
            try fixture.database.runSQL("""
                UPDATE conversation_messages
                SET status = 'complete', finish_reason = 'stop'
                WHERE role = 'assistant';
                """)
            #expect(throws: AgentRoomsConversationPersistenceError.corruptHistory) {
                try fixture.persistence.restoreCanonicalRoom(id: fixture.room.id)
            }
            return
        }

        let fixture = try makeTamperFixture()
        defer { fixture.cleanup() }
        let messages = try fixture.repository.messages(roomID: fixture.room.id)
        let users = messages.filter { $0.role == "user" }
        let assistant = try #require(messages.first(where: { $0.role == "assistant" }))
        let events = messages.filter { $0.role == "system" }
        let turn = try #require(try fixture.repository.turns(roomID: fixture.room.id).first)

        switch tamper {
        case .eventIdentity:
            try mutateMessageMetadata(fixture, id: events[0].id) { metadata in
                var event = try decodeEvent(metadata)
                event = .init(
                    id: UUID(),
                    actor: event.actor,
                    oldHead: event.oldHead,
                    newHead: event.newHead,
                    oldHeadRoutingEpoch: event.oldHeadRoutingEpoch,
                    newHeadRoutingEpoch: event.newHeadRoutingEpoch,
                    changedAt: event.changedAt
                )
                metadata[ConversationRepository.headChangeEventMetadataKey] =
                    try encode(event)
            }
        case .skippedEpoch:
            try mutateMessageMetadata(fixture, id: events[1].id) { metadata in
                let event = try decodeEvent(metadata)
                metadata[ConversationRepository.headChangeEventMetadataKey] = try encode(
                    ConversationHeadRoutingChangeEvent(
                        id: event.id,
                        actor: event.actor,
                        oldHead: event.oldHead,
                        newHead: event.newHead,
                        oldHeadRoutingEpoch: 3,
                        newHeadRoutingEpoch: 4,
                        changedAt: event.changedAt
                    )
                )
            }
            try replaceRoomAssignment(
                fixture,
                assignment: .init(
                    profile: fixture.headC,
                    assignedAt: timestamp(9),
                    headRoutingEpoch: 4
                )
            )
        case .finalAssignment:
            try replaceRoomAssignment(
                fixture,
                assignment: .init(
                    profile: fixture.headA,
                    assignedAt: timestamp(9),
                    headRoutingEpoch: 3
                )
            )
        case .crossUserOrigin:
            try mutateGeneratedRouting(fixture, messageID: assistant.id) { routing in
                .init(
                    recipient: routing.recipient,
                    observedHeadRoutingEpoch: routing.observedHeadRoutingEpoch,
                    observedRoomMessageSequence: routing.observedRoomMessageSequence,
                    originatingUserMessageID: users[1].id
                )
            }
        case .crossRoomOrigin:
            let otherRoom = try AgentRoomsActionService(
                repository: fixture.repository,
                agentAssignments: fixture.assignments
            ).createConversation(title: "Other room")
            let other = try fixture.persistence.beginAttempt(
                roomID: otherRoom.id,
                roomTitle: otherRoom.title,
                isReservedTestChat: false,
                attemptID: UUID(),
                clientMessageID: "cider-room-client:other-origin",
                userMessageID: UUID(),
                assistantMessageID: UUID(),
                text: "Other origin",
                at: timestamp(10)
            )
            try mutateGeneratedRouting(fixture, messageID: assistant.id) { routing in
                .init(
                    recipient: routing.recipient,
                    observedHeadRoutingEpoch: routing.observedHeadRoutingEpoch,
                    observedRoomMessageSequence: routing.observedRoomMessageSequence,
                    originatingUserMessageID: other.userMessageID
                )
            }
        case .wrongSequence:
            try mutateMessageMetadata(fixture, id: users[0].id) { metadata in
                let routing = try decodeSubmission(metadata)
                metadata[AgentRoomsConversationPersistence.submissionRoutingMetadataKey] =
                    try encode(ConversationSubmissionRoutingContext(
                        recipients: routing.recipients,
                        observedHeadRoutingEpoch: routing.observedHeadRoutingEpoch,
                        observedRoomMessageSequence: 99
                    ))
            }
        case .turnMessageRouting:
            try mutateGeneratedRouting(fixture, messageID: assistant.id) { routing in
                .init(
                    recipient: .init(
                        profileID: fixture.headB.id,
                        displayName: fixture.headB.displayName
                    ),
                    observedHeadRoutingEpoch: routing.observedHeadRoutingEpoch,
                    observedRoomMessageSequence: routing.observedRoomMessageSequence,
                    originatingUserMessageID: routing.originatingUserMessageID
                )
            }
            #expect(try fixture.repository.turn(id: turn.id) != nil)
        case .generatedSequence:
            try mutateGeneratedRouting(fixture, messageID: assistant.id) { routing in
                .init(
                    recipient: routing.recipient,
                    observedHeadRoutingEpoch: routing.observedHeadRoutingEpoch,
                    observedRoomMessageSequence: 99,
                    originatingUserMessageID: routing.originatingUserMessageID
                )
            }
            try mutateTurnGeneratedRouting(fixture, turnID: turn.id) { routing in
                .init(
                    recipient: routing.recipient,
                    observedHeadRoutingEpoch: routing.observedHeadRoutingEpoch,
                    observedRoomMessageSequence: 99,
                    originatingUserMessageID: routing.originatingUserMessageID
                )
            }
        case .generatedRecipient:
            let recipient = ConversationRoutingRecipient(
                profileID: fixture.headC.id,
                displayName: fixture.headC.displayName
            )
            try mutateGeneratedRouting(fixture, messageID: assistant.id) { routing in
                .init(
                    recipient: recipient,
                    observedHeadRoutingEpoch: routing.observedHeadRoutingEpoch,
                    observedRoomMessageSequence: routing.observedRoomMessageSequence,
                    originatingUserMessageID: routing.originatingUserMessageID
                )
            }
            try mutateTurnGeneratedRouting(fixture, turnID: turn.id) { routing in
                .init(
                    recipient: recipient,
                    observedHeadRoutingEpoch: routing.observedHeadRoutingEpoch,
                    observedRoomMessageSequence: routing.observedRoomMessageSequence,
                    originatingUserMessageID: routing.originatingUserMessageID
                )
            }
        case .contradictoryHeldState:
            Issue.record("Handled above")
        }

        #expect(throws: AgentRoomsConversationPersistenceError.corruptHistory) {
            try fixture.persistence.restoreCanonicalRoom(id: fixture.room.id)
        }
    }

    private func makeFixture(
        title: String,
        catalog: ConversationAgentProfileCatalog? = nil
    ) throws -> HardeningFixture {
        let headA: ConversationAgentProfile
        if let catalog,
           let configured = catalog.profiles.first(where: { $0.id == catalog.defaultProfileID }) {
            headA = configured
        } else {
            headA = try makeProfile(
                id: "hermes",
                displayName: "Hermes",
                providerID: "hermes",
                runtimeID: "hermes"
            )
        }
        let headB: ConversationAgentProfile
        if let configured = catalog?.profiles.first(where: { $0.id == "codex" }) {
            headB = configured
        } else {
            headB = try makeProfile(
                id: "codex",
                displayName: "Codex",
                providerID: "openai",
                runtimeID: "codex"
            )
        }
        let headC: ConversationAgentProfile
        if let configured = catalog?.profiles.first(where: { $0.id == "research" }) {
            headC = configured
        } else {
            headC = try makeProfile(
                id: "research",
                displayName: "Research",
                providerID: "local",
                runtimeID: "research"
            )
        }
        let resolvedCatalog = try catalog ?? ConversationAgentProfileCatalog(
            profiles: [headA, headB, headC],
            defaultProfileID: headA.id
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-head-hardening-\(UUID().uuidString).sqlite")
        let database = CiderDatabase()
        try database.open(at: url)
        let repository = ConversationRepository(database: database)
        let assignments = AgentRoomsAgentAssignmentService(
            repository: repository,
            catalog: resolvedCatalog,
            now: { timestamp(8) }
        )
        let room = try AgentRoomsActionService(
            repository: repository,
            agentAssignments: assignments
        ).createConversation(title: title)
        let persistence = AgentRoomsConversationPersistence(
            database: database,
            repository: repository,
            defaultAgentProfile: headA,
            participantProfiles: resolvedCatalog.profiles
        )
        return HardeningFixture(
            url: url,
            database: database,
            repository: repository,
            assignments: assignments,
            persistence: persistence,
            room: room,
            catalog: resolvedCatalog,
            headA: headA,
            headB: headB,
            headC: headC
        )
    }

    private func makeReservedFixture(title: String) throws -> HardeningFixture {
        let headA = try makeProfile(
            id: "hermes",
            displayName: "Hermes",
            providerID: "hermes",
            runtimeID: "hermes"
        )
        let headB = try makeProfile(
            id: "codex",
            displayName: "Codex",
            providerID: "openai",
            runtimeID: "codex"
        )
        let headC = try makeProfile(
            id: "research",
            displayName: "Research",
            providerID: "local",
            runtimeID: "research"
        )
        let catalog = try ConversationAgentProfileCatalog(
            profiles: [headA, headB, headC],
            defaultProfileID: headA.id
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "cider-head-hardening-reserved-\(UUID().uuidString).sqlite"
            )
        let database = CiderDatabase()
        try database.open(at: url)
        let repository = ConversationRepository(database: database)
        let assignments = AgentRoomsAgentAssignmentService(
            repository: repository,
            catalog: catalog,
            now: { timestamp(8) }
        )
        let persistence = AgentRoomsConversationPersistence(
            database: database,
            repository: repository,
            defaultAgentProfile: headA,
            participantProfiles: catalog.profiles
        )
        let snapshot = try #require(
            try persistence.prepareReservedTestChat(id: UUID(), at: timestamp(0))
        )
        return HardeningFixture(
            url: url,
            database: database,
            repository: repository,
            assignments: assignments,
            persistence: persistence,
            room: snapshot.room,
            catalog: catalog,
            headA: headA,
            headB: headB,
            headC: headC
        )
    }

    private func makeTamperFixture() throws -> HardeningFixture {
        let fixture = try makeFixture(title: "Relational tamper")
        let state = try #require(
            try fixture.persistence.restoreCanonicalRoom(id: fixture.room.id)?.conversationState
        )
        let first = try beginAttempt(
            fixture,
            clientID: "cider-room-client:tamper-a",
            text: "First user"
        )
        _ = try fixture.persistence.complete(
            first,
            completion: completion(
                state: state,
                text: "First user",
                answer: "First assistant",
                runID: "run-tamper-a",
                sessionID: "session-tamper-a"
            ),
            expectedText: "First user",
            activity: []
        )
        _ = try fixture.assignments.assign(profileID: fixture.headB.id, roomID: fixture.room.id)
        let second = try beginAttempt(
            fixture,
            clientID: "cider-room-client:tamper-b",
            text: "Second user"
        )
        try fixture.persistence.markRunStarted(
            second,
            runID: "run-tamper-b",
            activity: [],
            at: timestamp(4)
        )
        _ = try fixture.persistence.terminate(
            second,
            status: .failed,
            runID: "run-tamper-b",
            partialAssistantText: nil,
            activity: [],
            at: timestamp(5)
        )
        _ = try fixture.assignments.assign(profileID: fixture.headC.id, roomID: fixture.room.id)
        _ = try #require(try fixture.persistence.restoreCanonicalRoom(id: fixture.room.id))
        return fixture
    }

    private func verifyTransportTermination(
        failure: HeadRoutingTransportFailure,
        injectedPersistenceFailure: Bool
    ) async throws {
        let fixture = try makeFixture(
            title: "\(failure.rawValue) transport \(injectedPersistenceFailure ? "unresolved" : "terminal")"
        )
        let runID = "run-transport-\(failure.rawValue)-\(injectedPersistenceFailure)"
        let transport = HeadRoutingThrowingTransport(
            runID: runID,
            failure: failure
        )
        let persistence: any AgentRoomsConversationPersisting =
            injectedPersistenceFailure
                ? FailingTerminationPersistence(base: fixture.persistence)
                : fixture.persistence
        let model = AgentRoomsLiveChatModel(
            transport: transport,
            turnCoordinator: HermesTurnCoordinator(),
            savedBookmarkMatches: { _ in [] },
            persistence: persistence,
            agentAssignments: fixture.assignments
        )
        #expect(model.activateCanonicalRoom(id: fixture.room.id))
        await model.refreshTransportReadiness()
        await model.send(
            "Transport \(failure.rawValue)",
            selectedRoomID: fixture.room.id.uuidString
        )

        let receipt = try #require(model.activeRoom?.transcript.receipt)
        let partial = try #require(
            model.activeRoom?.transcript.messages.last(where: { $0.role == .agent })
        )
        #expect(partial.author == fixture.headA.displayName)
        #expect(partial.body == "Transport partial")
        #expect(receipt.runIdentity == runID)
        #expect(receipt.sourceBackedTransport)

        if injectedPersistenceFailure {
            let expectedTitle = failure == .cancellation
                ? "Cancellation persistence failed"
                : "Failure persistence failed"
            let expectedDetail = failure == .cancellation
                ? "Transport cancellation observed · Durable terminal state unconfirmed"
                : "Transport failure observed · Durable terminal state unconfirmed"
            let expectedComposer = failure == .cancellation
                ? "Cider could not durably record the transport cancellation. Reopen this conversation before continuing."
                : "Cider could not durably record the transport failure. Reopen this conversation before continuing."
            #expect(receipt.title == expectedTitle)
            #expect(receipt.detail == expectedDetail)
            #expect(receipt.status == .failed)
            #expect(model.composerMessage == expectedComposer)
            #expect(model.turnState == .failed)
            #expect(
                try fixture.repository.turns(roomID: fixture.room.id).last?.status
                    == .running
            )
            #expect(
                try fixture.repository.messages(roomID: fixture.room.id)
                    .contains(where: { $0.role == "assistant" }) == false
            )

            fixture.database.close()
            let reopenedDatabase = CiderDatabase()
            try reopenedDatabase.open(at: fixture.url)
            let reopenedRepository = ConversationRepository(database: reopenedDatabase)
            #expect(
                try reopenedRepository.turns(roomID: fixture.room.id).last?.status
                    == .running
            )
            let reopenedPersistence = AgentRoomsConversationPersistence(
                database: reopenedDatabase,
                repository: reopenedRepository,
                defaultAgentProfile: fixture.headA,
                participantProfiles: fixture.catalog.profiles
            )
            let recovered = try #require(
                try reopenedPersistence.restoreCanonicalRoom(id: fixture.room.id)
            )
            #expect(recovered.latestTurnStatus == .failed)
            #expect(recovered.latestErrorCode == "accepted_interruption")
            #expect(recovered.presentationMessages.contains(where: {
                $0.role == .agent && $0.body == "Transport partial"
            }) == false)
            #expect(
                try reopenedRepository.turns(roomID: fixture.room.id).last?.status
                    != .cancelled
            )
            reopenedDatabase.close()
        } else {
            let expectedStatus: ConversationTurnStatus = failure == .cancellation
                ? .cancelled
                : .failed
            #expect(
                try fixture.repository.turns(roomID: fixture.room.id).last?.status
                    == expectedStatus
            )
            #expect(receipt.title == (
                failure == .cancellation
                    ? "Hermes turn interrupted"
                    : "Hermes response interrupted"
            ))
            #expect(receipt.detail
                == "Accepted by Hermes · Partial response kept · Cannot retry safely")
            #expect(receipt.status == (
                failure == .cancellation ? .cancelled : .failed
            ))
            fixture.database.close()
            let reopenedDatabase = CiderDatabase()
            try reopenedDatabase.open(at: fixture.url)
            let reopenedPersistence = AgentRoomsConversationPersistence(
                database: reopenedDatabase,
                repository: ConversationRepository(database: reopenedDatabase),
                defaultAgentProfile: fixture.headA,
                participantProfiles: fixture.catalog.profiles
            )
            let reopened = try #require(
                try reopenedPersistence.restoreCanonicalRoom(id: fixture.room.id)
            )
            #expect(reopened.latestTurnStatus == expectedStatus)
            #expect(reopened.latestErrorCode == "accepted_interruption")
            #expect(reopened.presentationMessages.last?.body == "Transport partial")
            reopenedDatabase.close()
        }
        fixture.cleanup()
    }

    private func beginAttempt(
        _ fixture: HardeningFixture,
        clientID: String,
        text: String,
        reserved: Bool = false
    ) throws -> AgentRoomsConversationAttempt {
        try fixture.persistence.beginAttempt(
            roomID: fixture.room.id,
            roomTitle: fixture.room.title,
            isReservedTestChat: reserved,
            attemptID: UUID(),
            clientMessageID: clientID,
            userMessageID: UUID(),
            assistantMessageID: UUID(),
            text: text,
            at: timestamp(0)
        )
    }

    private func rewriteRecipientIdentity(
        _ fixture: HardeningFixture,
        attempt: AgentRoomsConversationAttempt,
        recipient: ConversationRoutingRecipient,
        participant: Bool
    ) throws {
        try mutateSubmissionRouting(fixture, messageID: attempt.userMessageID) {
            .init(
                recipients: [recipient],
                observedHeadRoutingEpoch: $0.observedHeadRoutingEpoch,
                observedRoomMessageSequence: $0.observedRoomMessageSequence
            )
        }
        try mutateTurnGeneratedRouting(fixture, turnID: attempt.turnID) {
            .init(
                recipient: recipient,
                observedHeadRoutingEpoch: $0.observedHeadRoutingEpoch,
                observedRoomMessageSequence: $0.observedRoomMessageSequence,
                originatingUserMessageID: $0.originatingUserMessageID
            )
        }
        try mutateGeneratedRouting(fixture, messageID: attempt.assistantMessageID) {
            .init(
                recipient: recipient,
                observedHeadRoutingEpoch: $0.observedHeadRoutingEpoch,
                observedRoomMessageSequence: $0.observedRoomMessageSequence,
                originatingUserMessageID: $0.originatingUserMessageID
            )
        }
        guard participant else { return }
        try mutateTurnMetadata(fixture, id: attempt.turnID) { metadata in
            let key = AgentRoomsParticipantService.runAttributionMetadataKey
            let raw = try #require(metadata[key])
            let attribution = try JSONDecoder().decode(
                ConversationParticipantRunAttribution.self,
                from: Data(raw.utf8)
            )
            metadata[key] = try encode(ConversationParticipantRunAttribution(
                invocationID: attribution.invocationID,
                runID: attribution.runID,
                participantID: attribution.participantID,
                profileID: attribution.profileID,
                displayName: recipient.displayName,
                participantRole: attribution.participantRole,
                selectionSequence: attribution.selectionSequence
            ))
        }
        try mutateMessageMetadata(fixture, id: attempt.assistantMessageID) { metadata in
            let key = AgentRoomsParticipantService.messageAttributionMetadataKey
            let raw = try #require(metadata[key])
            let attribution = try JSONDecoder().decode(
                ConversationParticipantMessageAttribution.self,
                from: Data(raw.utf8)
            )
            metadata[key] = try encode(ConversationParticipantMessageAttribution(
                invocationID: attribution.invocationID,
                runID: attribution.runID,
                participantID: attribution.participantID,
                profileID: attribution.profileID,
                displayName: recipient.displayName,
                participantRole: attribution.participantRole
            ))
        }
    }

    private func assertCorruptReopenPreservesFingerprint(
        _ fixture: HardeningFixture
    ) throws {
        fixture.database.close()
        let before = try durableFingerprint(
            url: fixture.url,
            roomID: fixture.room.id
        )
        let reopenDatabase = CiderDatabase()
        try reopenDatabase.open(at: fixture.url)
        let persistence = AgentRoomsConversationPersistence(
            database: reopenDatabase,
            repository: ConversationRepository(database: reopenDatabase),
            defaultAgentProfile: fixture.headA,
            participantProfiles: fixture.catalog.profiles
        )
        #expect(throws: AgentRoomsConversationPersistenceError.corruptHistory) {
            try persistence.restoreCanonicalRoom(id: fixture.room.id)
        }
        reopenDatabase.close()
        let after = try durableFingerprint(
            url: fixture.url,
            roomID: fixture.room.id
        )
        #expect(after == before)
    }

    private func durableFingerprint(
        url: URL,
        roomID: UUID
    ) throws -> ReopenDurableFingerprint {
        let database = CiderDatabase()
        try database.open(at: url)
        defer { database.close() }
        let repository = ConversationRepository(database: database)
        let room = try #require(try repository.room(id: roomID))
        let messages = try repository.messages(roomID: roomID)
        let events = try messages.compactMap {
            message -> ConversationHeadRoutingChangeEvent? in
            guard let raw = message.metadata[
                ConversationRepository.headChangeEventMetadataKey
            ] else { return nil }
            return try JSONDecoder().decode(
                ConversationHeadRoutingChangeEvent.self,
                from: Data(raw.utf8)
            )
        }
        return ReopenDurableFingerprint(
            room: room,
            turns: try repository.turns(roomID: roomID),
            messages: messages,
            bindings: try repository.bindings(roomID: roomID),
            assignment: try repository.agentAssignment(roomID: roomID),
            roster: try repository.participantRoster(roomID: roomID),
            routingAcceptanceHistory: try repository.routingAcceptanceHistory(
                roomID: roomID
            ),
            events: events
        )
    }

    private func replaceRoomAssignment(
        _ fixture: HardeningFixture,
        assignment: ConversationRoomAgentAssignment
    ) throws {
        try replaceRoomAssignment(
            fixture,
            encodedAssignment: try #require(DatabaseHelpers.encodeJSON(assignment))
        )
    }

    private func replaceRoomAssignment(
        _ fixture: HardeningFixture,
        encodedAssignment: String
    ) throws {
        let room = try #require(try fixture.repository.room(id: fixture.room.id))
        var metadata = room.metadata
        metadata[ConversationRepository.agentAssignmentMetadataKey] = encodedAssignment
        let statement = try fixture.database.prepare("""
            UPDATE conversation_rooms SET metadata_json = ? WHERE id = ?;
            """)
        statement.bind(try #require(DatabaseHelpers.encodeJSON(metadata)), at: 1)
            .bind(fixture.room.id.uuidString, at: 2)
        try statement.step()
    }

    private func mutateMessageMetadata(
        _ fixture: HardeningFixture,
        id: UUID,
        mutate: (inout [String: String]) throws -> Void
    ) throws {
        let message = try #require(
            try fixture.repository.messages(roomID: fixture.room.id).first(where: { $0.id == id })
        )
        var metadata = message.metadata
        try mutate(&metadata)
        let statement = try fixture.database.prepare("""
            UPDATE conversation_messages SET metadata_json = ? WHERE id = ?;
            """)
        statement.bind(try #require(DatabaseHelpers.encodeJSON(metadata)), at: 1)
            .bind(id.uuidString, at: 2)
        try statement.step()
    }

    private func mutateTurnMetadata(
        _ fixture: HardeningFixture,
        id: UUID,
        mutate: (inout [String: String]) throws -> Void
    ) throws {
        let turn = try #require(try fixture.repository.turn(id: id))
        var metadata = turn.metadata
        try mutate(&metadata)
        let statement = try fixture.database.prepare("""
            UPDATE conversation_turns SET metadata_json = ? WHERE id = ?;
            """)
        statement.bind(try #require(DatabaseHelpers.encodeJSON(metadata)), at: 1)
            .bind(id.uuidString, at: 2)
        try statement.step()
    }

    private func mutateGeneratedRouting(
        _ fixture: HardeningFixture,
        messageID: UUID,
        mutate: (ConversationGeneratedRoutingContext) throws
            -> ConversationGeneratedRoutingContext
    ) throws {
        try mutateMessageMetadata(fixture, id: messageID) { metadata in
            let raw = try #require(
                metadata[AgentRoomsConversationPersistence.generatedRoutingMetadataKey]
            )
            let routing = try JSONDecoder().decode(
                ConversationGeneratedRoutingContext.self,
                from: Data(raw.utf8)
            )
            metadata[AgentRoomsConversationPersistence.generatedRoutingMetadataKey] =
                try encode(mutate(routing))
        }
    }

    private func mutateSubmissionRouting(
        _ fixture: HardeningFixture,
        messageID: UUID,
        mutate: (ConversationSubmissionRoutingContext) throws
            -> ConversationSubmissionRoutingContext
    ) throws {
        try mutateMessageMetadata(fixture, id: messageID) { metadata in
            let raw = try #require(
                metadata[AgentRoomsConversationPersistence.submissionRoutingMetadataKey]
            )
            let routing = try JSONDecoder().decode(
                ConversationSubmissionRoutingContext.self,
                from: Data(raw.utf8)
            )
            metadata[AgentRoomsConversationPersistence.submissionRoutingMetadataKey] =
                try encode(mutate(routing))
        }
    }

    private func mutateTurnGeneratedRouting(
        _ fixture: HardeningFixture,
        turnID: UUID,
        mutate: (ConversationGeneratedRoutingContext) throws
            -> ConversationGeneratedRoutingContext
    ) throws {
        let turn = try #require(try fixture.repository.turn(id: turnID))
        var metadata = turn.metadata
        let raw = try #require(
            metadata[AgentRoomsConversationPersistence.generatedRoutingMetadataKey]
        )
        let routing = try JSONDecoder().decode(
            ConversationGeneratedRoutingContext.self,
            from: Data(raw.utf8)
        )
        metadata[AgentRoomsConversationPersistence.generatedRoutingMetadataKey] =
            try encode(mutate(routing))
        let statement = try fixture.database.prepare("""
            UPDATE conversation_turns SET metadata_json = ? WHERE id = ?;
            """)
        statement.bind(try #require(DatabaseHelpers.encodeJSON(metadata)), at: 1)
            .bind(turnID.uuidString, at: 2)
        try statement.step()
    }

    private func decodeEvent(
        _ metadata: [String: String]
    ) throws -> ConversationHeadRoutingChangeEvent {
        let raw = try #require(metadata[ConversationRepository.headChangeEventMetadataKey])
        return try JSONDecoder().decode(
            ConversationHeadRoutingChangeEvent.self,
            from: Data(raw.utf8)
        )
    }

    private func decodeSubmission(
        _ metadata: [String: String]
    ) throws -> ConversationSubmissionRoutingContext {
        let raw = try #require(
            metadata[AgentRoomsConversationPersistence.submissionRoutingMetadataKey]
        )
        return try JSONDecoder().decode(
            ConversationSubmissionRoutingContext.self,
            from: Data(raw.utf8)
        )
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return try #require(String(data: data, encoding: .utf8))
    }

    private func completion(
        state: HermesConversationState,
        text: String,
        answer: String,
        runID: String,
        sessionID: String,
        modelIdentity: String = "head-hardening-runtime",
        sourceName: String = "Hermes",
        ciderReferences: [HermesCiderReference] = [],
        contextCheckpointFactState: HermesStructuredFactState = .notReported,
        contextCheckpoint: HermesCiderContextCheckpoint? = nil,
        approvalFactState: HermesStructuredFactState = .notReported,
        approvalRequests: [HermesApprovalRequest] = [],
        attachmentFactState: HermesStructuredFactState = .notReported,
        attachments: [HermesCiderAttachment] = [],
        generatedArtifactFactState: HermesStructuredFactState = .notReported,
        generatedArtifacts: [HermesCiderGeneratedArtifact] = []
    ) -> HermesRunCompletionEnvelope {
        let date = timestamp(6)
        let userSourceID = "hermes-run:\(runID):user"
        let assistantSourceID = "hermes-run:\(runID):assistant"
        let user = AIAssistantMessage(
            role: .user,
            content: text,
            timestamp: date,
            sourceID: userSourceID,
            sourceSessionID: sessionID,
            sourceName: sourceName
        )
        let assistant = AIAssistantMessage(
            role: .assistant,
            content: answer,
            timestamp: date,
            sourceID: assistantSourceID,
            sourceSessionID: sessionID,
            sourceName: sourceName
        )
        var finalState = state
        finalState.activeRuntimeSessionID = sessionID
        finalState.runtimeSessionLineage.append(sessionID)
        finalState.lastSyncedAt = date
        finalState.lastSyncedMessageID = assistantSourceID
        finalState.lastSyncedTimestamp = date
        finalState.lastImportedRuntimeSessionID = sessionID
        return HermesRunCompletionEnvelope(
            provenance: .hermesRunsAPI,
            runID: runID,
            terminalStatus: .completed,
            observedFacts: .none,
            finalSessionSynchronizationComplete: true,
            finalMessages: [user, assistant],
            finalState: finalState,
            modelIdentity: modelIdentity,
            terminalSourceEvidence: .init(
                reportedTerminalRunID: runID,
                userSourceID: userSourceID,
                assistantSourceID: assistantSourceID,
                userSourceSessionID: sessionID,
                assistantSourceSessionID: sessionID
            ),
            ciderReferences: ciderReferences,
            contextCheckpointFactState: contextCheckpointFactState,
            contextCheckpoint: contextCheckpoint,
            approvalFactState: approvalFactState,
            approvalRequests: approvalRequests,
            attachmentFactState: attachmentFactState,
            attachments: attachments,
            generatedArtifactFactState: generatedArtifactFactState,
            generatedArtifacts: generatedArtifacts
        )
    }

    private func completionWithReplayFacts(
        state: HermesConversationState,
        text: String,
        answer: String,
        runID: String,
        sessionID: String,
        facts: CompletionReplayTestFacts
    ) -> HermesRunCompletionEnvelope {
        completion(
            state: state,
            text: text,
            answer: answer,
            runID: runID,
            sessionID: sessionID,
            ciderReferences: facts.references,
            contextCheckpointFactState: .validated,
            contextCheckpoint: facts.context,
            approvalFactState: .validated,
            approvalRequests: facts.approvals,
            attachmentFactState: .validated,
            attachments: facts.attachments,
            generatedArtifactFactState: .validated,
            generatedArtifacts: facts.generatedArtifacts
        )
    }

    private func completionReplayFacts() -> CompletionReplayTestFacts {
        let noteID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let attachmentID1 = UUID(
            uuidString: "20000000-0000-0000-0000-000000000001"
        )!
        let attachmentID2 = UUID(
            uuidString: "20000000-0000-0000-0000-000000000002"
        )!
        let attachmentTarget1 = UUID(
            uuidString: "30000000-0000-0000-0000-000000000001"
        )!
        let attachmentTarget2 = UUID(
            uuidString: "30000000-0000-0000-0000-000000000002"
        )!
        let artifactID1 = UUID(
            uuidString: "40000000-0000-0000-0000-000000000001"
        )!
        let artifactID2 = UUID(
            uuidString: "40000000-0000-0000-0000-000000000002"
        )!
        let artifactTarget1 = UUID(
            uuidString: "50000000-0000-0000-0000-000000000001"
        )!
        let artifactTarget2 = UUID(
            uuidString: "50000000-0000-0000-0000-000000000002"
        )!
        let note = HermesCiderReference(
            kind: "note",
            id: noteID.uuidString,
            title: "Completion replay note",
            boardID: nil,
            projectID: nil,
            artifactType: nil,
            source: "cider",
            sourceRef: "note:\(noteID.uuidString)"
        )
        let card = HermesCiderReference(
            kind: "kanban_card",
            id: "CID-841",
            title: "Completion replay closure",
            boardID: "2afee0",
            projectID: nil,
            artifactType: nil,
            source: "cider",
            sourceRef: "kanban_card:2afee0/CID-841"
        )
        return CompletionReplayTestFacts(
            references: [note, card],
            context: HermesCiderContextCheckpoint(
                id: "context-envelope-a",
                selected: [note, card],
                citations: [note, card],
                omissionReason: nil,
                source: "cider",
                sourceRef: "context_checkpoint:context-envelope-a"
            ),
            approvals: [
                HermesApprovalRequest(
                    id: "approval-envelope-a",
                    action: "Update note",
                    target: note,
                    risk: "medium",
                    scope: "write",
                    status: "requested",
                    source: "hermes_runs_api",
                    sourceRef: "approval:approval-envelope-a"
                ),
                HermesApprovalRequest(
                    id: "approval-envelope-b",
                    action: "Read note",
                    target: note,
                    risk: "low",
                    scope: "read",
                    status: "approved",
                    source: "hermes_runs_api",
                    sourceRef: "approval:approval-envelope-b"
                ),
            ],
            attachments: [
                HermesCiderAttachment(
                    id: attachmentID1.uuidString,
                    target: HermesCiderAssetReference(
                        kind: "vault_file",
                        id: attachmentTarget1.uuidString,
                        title: "input-a.pdf",
                        projectID: nil,
                        artifactType: nil,
                        source: "cider",
                        sourceRef: "vaultFile:\(attachmentTarget1.uuidString)"
                    ),
                    displayName: "input-a.pdf",
                    contentType: "application/pdf",
                    byteSize: 1_024,
                    provenance: "user_attachment",
                    source: "cider",
                    sourceRef: "attachment:\(attachmentID1.uuidString)"
                ),
                HermesCiderAttachment(
                    id: attachmentID2.uuidString,
                    target: HermesCiderAssetReference(
                        kind: "vault_file",
                        id: attachmentTarget2.uuidString,
                        title: "input-b.txt",
                        projectID: nil,
                        artifactType: nil,
                        source: "cider",
                        sourceRef: "vaultFile:\(attachmentTarget2.uuidString)"
                    ),
                    displayName: "input-b.txt",
                    contentType: "text/plain",
                    byteSize: 2_048,
                    provenance: "source_attachment",
                    source: "cider",
                    sourceRef: "attachment:\(attachmentID2.uuidString)"
                ),
            ],
            generatedArtifacts: [
                HermesCiderGeneratedArtifact(
                    id: artifactID1.uuidString,
                    target: HermesCiderAssetReference(
                        kind: "project_artifact",
                        id: artifactTarget1.uuidString,
                        title: "Output A",
                        projectID: "cider",
                        artifactType: "plan",
                        source: "cider",
                        sourceRef: "note:\(artifactTarget1.uuidString)"
                    ),
                    displayName: "Output A.md",
                    contentType: "text/markdown",
                    byteSize: 4_096,
                    provenance: "cider_generated",
                    source: "cider",
                    sourceRef: "generated_artifact:\(artifactID1.uuidString)"
                ),
                HermesCiderGeneratedArtifact(
                    id: artifactID2.uuidString,
                    target: HermesCiderAssetReference(
                        kind: "project_artifact",
                        id: artifactTarget2.uuidString,
                        title: "Output B",
                        projectID: "cider",
                        artifactType: "qa",
                        source: "cider",
                        sourceRef: "note:\(artifactTarget2.uuidString)"
                    ),
                    displayName: "Output B.md",
                    contentType: "text/markdown",
                    byteSize: 8_192,
                    provenance: "cider_generated",
                    source: "cider",
                    sourceRef: "generated_artifact:\(artifactID2.uuidString)"
                ),
            ]
        )
    }

    private func completionReplayActivity() -> [AgentRoomsLiveActivity] {
        [
            AgentRoomsLiveActivity(
                id: UUID(),
                kind: .reasoning,
                detail: "Checked canonical context"
            ),
            AgentRoomsLiveActivity(
                id: UUID(),
                kind: .toolCompleted,
                detail: "Created durable output"
            ),
        ]
    }

    private func changedReference(
        _ value: HermesCiderReference,
        title: String
    ) -> HermesCiderReference {
        HermesCiderReference(
            kind: value.kind,
            id: value.id,
            title: title,
            boardID: value.boardID,
            projectID: value.projectID,
            artifactType: value.artifactType,
            source: value.source,
            sourceRef: value.sourceRef
        )
    }

    private func makeProfile(
        id: String,
        displayName: String,
        providerID: String,
        runtimeID: String
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

    private func timestamp(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_806_500_000 + offset)
    }

    private struct LegacyAssignment: Encodable {
        let schemaVersion: Int
        let profile: ConversationAgentProfile
        let assignedAt: Date
    }
}

private struct ReopenDurableFingerprint: Equatable {
    let room: ConversationRoom
    let turns: [ConversationTurn]
    let messages: [ConversationMessage]
    let bindings: [ConversationRuntimeBinding]
    let assignment: ConversationRoomAgentAssignment?
    let roster: ConversationRoomParticipantRoster?
    let routingAcceptanceHistory: ConversationRoutingAcceptanceHistory?
    let events: [ConversationHeadRoutingChangeEvent]
}

private struct CompletionReplayTestFacts {
    var references: [HermesCiderReference]
    var context: HermesCiderContextCheckpoint
    var approvals: [HermesApprovalRequest]
    var attachments: [HermesCiderAttachment]
    var generatedArtifacts: [HermesCiderGeneratedArtifact]
}

enum RoutingTamper: String, CaseIterable, Sendable {
    case eventIdentity
    case skippedEpoch
    case finalAssignment
    case crossUserOrigin
    case crossRoomOrigin
    case wrongSequence
    case turnMessageRouting
    case generatedSequence
    case generatedRecipient
    case contradictoryHeldState
}

@MainActor
private struct HardeningFixture {
    let url: URL
    let database: CiderDatabase
    let repository: ConversationRepository
    let assignments: AgentRoomsAgentAssignmentService
    let persistence: AgentRoomsConversationPersistence
    let room: ConversationRoom
    let catalog: ConversationAgentProfileCatalog
    let headA: ConversationAgentProfile
    let headB: ConversationAgentProfile
    let headC: ConversationAgentProfile

    func cleanup() {
        database.close()
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
}

private enum ParticipantHardeningError: Error {
    case expectedFailure
}

private actor ParticipantHardeningGateRuntime: ConversationParticipantRuntimeExecuting {
    let binding: ConversationAgentRuntimeBinding
    private let shouldFail: Bool
    private var released: Bool
    private var started = false
    private var executions = 0
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        binding: ConversationAgentRuntimeBinding,
        shouldFail: Bool,
        startsReleased: Bool = false
    ) {
        self.binding = binding
        self.shouldFail = shouldFail
        released = startsReleased
    }

    func execute(
        _ request: ConversationParticipantExecutionRequest
    ) async throws -> ConversationParticipantExecutionResult {
        executions += 1
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        if !released {
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
        if shouldFail { throw ParticipantHardeningError.expectedFailure }
        return .init(
            text: "Participant result",
            source: .init(
                namespace: "provider.participant.runtime",
                id: request.runID.uuidString
            ),
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

    func executionCount() -> Int { executions }
}

private enum HeadRoutingTransportFailure: String, Sendable {
    case cancellation
    case generic
}

private enum HeadRoutingInjectedTransportError: Error {
    case failed
}

private actor HeadRoutingThrowingTransport: HermesBridgeTransport {
    let runID: String
    let failure: HeadRoutingTransportFailure

    init(runID: String, failure: HeadRoutingTransportFailure) {
        self.runID = runID
        self.failure = failure
    }

    func availability() async -> HermesBridgeAvailability { .apiRuns }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        await onEvent?(.runStarted(runID))
        await onEvent?(.messageDelta("Transport partial"))
        switch failure {
        case .cancellation:
            throw CancellationError()
        case .generic:
            throw HeadRoutingInjectedTransportError.failed
        }
    }

    func stop(runID: String) async throws {}
}

private actor HeadRoutingHardeningTransport: HermesBridgeTransport {
    let result: HermesRunCompletionEnvelope
    private var started = false
    private var released = false
    private var cancelled = false
    private var handler: (@Sendable (HermesRunEvent) async -> Void)?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(completion: HermesRunCompletionEnvelope) {
        result = completion
    }

    func availability() async -> HermesBridgeAvailability { .apiRuns }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        handler = onEvent
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await onEvent?(.runStarted(result.runID ?? ""))
        if !released {
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
        if cancelled { throw CancellationError() }
        return .init(completion: result)
    }

    func stop(runID: String) async throws {
        cancelled = true
        release()
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func emit(_ event: HermesRunEvent) async {
        await handler?(event)
    }

    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private enum HeadRoutingHardeningPersistenceFailure: Error {
    case injectedTerminationFailure
}

@MainActor
private final class FailingTerminationPersistence: AgentRoomsConversationPersisting {
    private let base: any AgentRoomsConversationPersisting

    init(base: any AgentRoomsConversationPersisting) {
        self.base = base
    }

    func restoreCanonicalRoom(id: UUID) throws -> AgentRoomsConversationSnapshot? {
        try base.restoreCanonicalRoom(id: id)
    }

    func restoreReservedTestChat() throws -> AgentRoomsConversationSnapshot? {
        try base.restoreReservedTestChat()
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
        try base.beginAttempt(
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
        try base.markRunStarted(attempt, runID: runID, activity: activity, at: date)
    }

    func complete(
        _ attempt: AgentRoomsConversationAttempt,
        completion: HermesRunCompletionEnvelope,
        expectedText: String,
        activity: [AgentRoomsLiveActivity]
    ) throws -> ConversationResultPublicationOutcome {
        try base.complete(
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
    ) throws -> ConversationResultPublicationOutcome {
        throw HeadRoutingHardeningPersistenceFailure.injectedTerminationFailure
    }
}
