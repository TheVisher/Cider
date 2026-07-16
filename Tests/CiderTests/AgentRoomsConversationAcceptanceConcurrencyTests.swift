import Foundation
import Testing
@testable import Cider

@Suite("Agent Rooms Conversation Acceptance Concurrency Tests")
@MainActor
struct AgentRoomsConversationAcceptanceConcurrencyTests {
    @Test("native acceptance follows a second-connection append with current sequence and parent")
    func nativeAcceptanceUsesCurrentSequenceAndParent() throws {
        let fixture = try makeFixture(title: "Native append reservation")
        defer { fixture.cleanup() }
        let writerPersistence = fixture.persistence(
            database: fixture.secondaryDatabase,
            repository: fixture.secondaryRepository
        )
        let prior = try writerPersistence.beginAttempt(
            roomID: fixture.room.id,
            roomTitle: fixture.room.title,
            isReservedTestChat: false,
            attemptID: UUID(),
            clientMessageID: "cider-room-client:connection-b-append",
            userMessageID: UUID(),
            assistantMessageID: UUID(),
            text: "Connection B committed first",
            at: timestamp(1)
        )
        _ = try writerPersistence.terminate(
            prior,
            status: .cancelled,
            runID: nil,
            partialAssistantText: nil,
            activity: [],
            at: timestamp(2)
        )

        let accepted = try fixture.primaryPersistence.beginAttempt(
            roomID: fixture.room.id,
            roomTitle: fixture.room.title,
            isReservedTestChat: false,
            attemptID: UUID(),
            clientMessageID: "cider-room-client:connection-a-current",
            userMessageID: UUID(),
            assistantMessageID: UUID(),
            text: "Connection A must follow current truth",
            at: timestamp(3)
        )
        let user = try #require(
            try fixture.primaryRepository.messages(roomID: fixture.room.id)
                .first(where: { $0.id == accepted.userMessageID })
        )
        let routing = try submissionRouting(user)

        #expect(user.sequence == 2)
        #expect(user.parentMessageID == prior.userMessageID)
        #expect(routing.observedRoomMessageSequence == 1)
        #expect(accepted.routingContext.observedRoomMessageSequence == 1)
        #expect(accepted.routingContext.originatingUserMessageID == user.id)
        try assertPhysicalReopenSucceeds(fixture)
    }

    @Test("native acceptance binds a second-connection head change before reservation")
    func nativeAcceptanceUsesCurrentHeadAndEpoch() throws {
        let fixture = try makeFixture(title: "Native head reservation")
        defer { fixture.cleanup() }
        let writerAssignments = AgentRoomsAgentAssignmentService(
            repository: fixture.secondaryRepository,
            catalog: fixture.catalog,
            now: { timestamp(10) }
        )
        let currentAssignment = try writerAssignments.assign(
            profileID: fixture.headB.id,
            roomID: fixture.room.id
        )
        let event = try #require(
            try fixture.primaryRepository.messages(roomID: fixture.room.id)
                .first(where: { $0.role == "system" })
        )

        let accepted = try fixture.primaryPersistence.beginAttempt(
            roomID: fixture.room.id,
            roomTitle: fixture.room.title,
            isReservedTestChat: false,
            attemptID: UUID(),
            clientMessageID: "cider-room-client:after-current-head",
            userMessageID: UUID(),
            assistantMessageID: UUID(),
            text: "Bind the current selected head",
            at: timestamp(11)
        )
        let user = try #require(
            try fixture.primaryRepository.messages(roomID: fixture.room.id)
                .first(where: { $0.id == accepted.userMessageID })
        )
        let routing = try submissionRouting(user)

        #expect(currentAssignment.headRoutingEpoch == 2)
        #expect(user.parentMessageID == event.id)
        #expect(routing.recipients == [ConversationRoutingRecipient(profile: fixture.headB)])
        #expect(routing.observedHeadRoutingEpoch == currentAssignment.headRoutingEpoch)
        #expect(routing.observedRoomMessageSequence == event.sequence)
        #expect(accepted.routingContext.recipient.profileID == fixture.headB.id)
        #expect(
            accepted.routingContext.observedHeadRoutingEpoch
                == currentAssignment.headRoutingEpoch
        )
        try assertPhysicalReopenSucceeds(fixture)
    }

    @Test("attributed acceptance rejects stale roster identity then accepts current attribution")
    func attributedAcceptanceUsesCurrentRoster() throws {
        let fixture = try makeFixture(title: "Attributed roster reservation")
        defer { fixture.cleanup() }
        let originalRoster = try #require(
            try fixture.primaryRepository.participantRoster(roomID: fixture.room.id)
        )
        let staleMember = try #require(
            originalRoster.members.first(where: { $0.profile.id == fixture.advisor.id })
        )
        let staleAttribution = attribution(member: staleMember)
        let currentRoster = try fixture.secondaryParticipants.configureRoster(
            roomID: fixture.room.id,
            members: [
                .init(profileID: fixture.headA.id, role: .actingAgent),
                .init(profileID: fixture.headB.id, role: .advisor),
            ]
        )
        let beforeStaleAttempt = try fingerprint(fixture)

        #expect(throws: AgentRoomsConversationPersistenceError.authorityMismatch) {
            try fixture.primaryPersistence.beginAttributedAttempt(
                roomID: fixture.room.id,
                roomTitle: fixture.room.title,
                isReservedTestChat: false,
                attemptID: staleAttribution.invocationID,
                clientMessageID: "cider-room-client:stale-attribution",
                userMessageID: UUID(),
                assistantMessageID: UUID(),
                text: "Stale attribution must not commit",
                attribution: staleAttribution,
                at: timestamp(20)
            )
        }
        #expect(try fingerprint(fixture) == beforeStaleAttempt)

        let currentMember = try #require(
            currentRoster.members.first(where: { $0.profile.id == fixture.headB.id })
        )
        let currentAttribution = attribution(member: currentMember)
        let accepted = try fixture.primaryPersistence.beginAttributedAttempt(
            roomID: fixture.room.id,
            roomTitle: fixture.room.title,
            isReservedTestChat: false,
            attemptID: currentAttribution.invocationID,
            clientMessageID: "cider-room-client:current-attribution",
            userMessageID: UUID(),
            assistantMessageID: UUID(),
            text: "Current attribution may commit",
            attribution: currentAttribution,
            at: timestamp(21)
        )

        #expect(accepted.participantAttribution == currentAttribution)
        #expect(accepted.routingContext.recipient == ConversationRoutingRecipient(
            profile: currentMember.profile
        ))
        #expect(
            try fixture.primaryRepository.routingAcceptanceHistory(roomID: fixture.room.id)?
                .records.count == 1
        )
        try assertPhysicalReopenSucceeds(fixture)
    }

    @Test("native writer contention is a typed zero-mutation conflict and retry commits once")
    func nativeWriterContentionIsTypedAndRetryable() throws {
        let fixture = try makeFixture(title: "Native writer contention")
        defer { fixture.cleanup() }
        try fixture.primaryDatabase.runSQL("PRAGMA busy_timeout=1;")
        let attemptID = UUID()
        let userMessageID = UUID()
        let assistantMessageID = UUID()
        let clientMessageID = "cider-room-client:writer-conflict"
        let createdAt = timestamp(30)
        let before = try fingerprint(fixture)

        try fixture.secondaryDatabase.runSQL("BEGIN IMMEDIATE TRANSACTION;")
        do {
            _ = try fixture.primaryPersistence.beginAttempt(
                roomID: fixture.room.id,
                roomTitle: fixture.room.title,
                isReservedTestChat: false,
                attemptID: attemptID,
                clientMessageID: clientMessageID,
                userMessageID: userMessageID,
                assistantMessageID: assistantMessageID,
                text: "Retry only after writer release",
                at: createdAt
            )
            Issue.record("Expected a typed bounded writer conflict")
        } catch let error as AgentRoomsConversationPersistenceError {
            #expect(error == .writerConflict)
            #expect(
                error.errorDescription
                    == "Conversation acceptance conflicted with another room update. Nothing was sent."
            )
        }
        #expect(try fingerprint(fixture) == before)

        try fixture.secondaryDatabase.runSQL("ROLLBACK;")
        let accepted = try fixture.primaryPersistence.beginAttempt(
            roomID: fixture.room.id,
            roomTitle: fixture.room.title,
            isReservedTestChat: false,
            attemptID: attemptID,
            clientMessageID: clientMessageID,
            userMessageID: userMessageID,
            assistantMessageID: assistantMessageID,
            text: "Retry only after writer release",
            at: createdAt
        )

        #expect(accepted.turnID == attemptID)
        #expect(accepted.userMessageID == userMessageID)
        #expect(try fixture.primaryRepository.messages(roomID: fixture.room.id).count == 1)
        #expect(try fixture.primaryRepository.turns(roomID: fixture.room.id).count == 1)
        #expect(
            try fixture.primaryRepository.routingAcceptanceHistory(roomID: fixture.room.id)?
                .records.count == 1
        )
        try assertPhysicalReopenSucceeds(fixture)
    }

    @Test("every native acceptance write checkpoint rolls back the complete unit")
    func nativeAcceptanceWriteCheckpointsRollbackAtomically() throws {
        for checkpoint in NativeAcceptanceFailureCheckpoint.allCases {
            let fixture = try makeFixture(title: "Native rollback \(checkpoint)")
            defer { fixture.cleanup() }
            try installFailureTrigger(checkpoint, database: fixture.primaryDatabase)
            let before = try fingerprint(fixture)

            #expect(throws: CiderDatabaseError.self) {
                try fixture.primaryPersistence.beginAttempt(
                    roomID: fixture.room.id,
                    roomTitle: fixture.room.title,
                    isReservedTestChat: false,
                    attemptID: UUID(),
                    clientMessageID: "cider-room-client:rollback-\(checkpoint)",
                    userMessageID: UUID(),
                    assistantMessageID: UUID(),
                    text: "Rollback the complete native acceptance",
                    at: timestamp(40)
                )
            }

            #expect(try fingerprint(fixture) == before)
            try assertPhysicalReopenSucceeds(fixture)
        }
    }

    @Test("exact native duplicate remains immutable and the normal path reopens")
    func exactNativeDuplicateRemainsImmutable() throws {
        let fixture = try makeFixture(title: "Exact native duplicate")
        defer { fixture.cleanup() }
        let attemptID = UUID()
        let userMessageID = UUID()
        let assistantMessageID = UUID()
        let createdAt = timestamp(50)
        let first = try fixture.primaryPersistence.beginAttempt(
            roomID: fixture.room.id,
            roomTitle: fixture.room.title,
            isReservedTestChat: false,
            attemptID: attemptID,
            clientMessageID: "cider-room-client:exact-duplicate",
            userMessageID: userMessageID,
            assistantMessageID: assistantMessageID,
            text: "Accept exactly once",
            at: createdAt
        )
        let afterFirst = try fingerprint(fixture)
        let duplicate = try fixture.primaryPersistence.beginAttempt(
            roomID: fixture.room.id,
            roomTitle: fixture.room.title,
            isReservedTestChat: false,
            attemptID: attemptID,
            clientMessageID: "cider-room-client:exact-duplicate",
            userMessageID: userMessageID,
            assistantMessageID: assistantMessageID,
            text: "Accept exactly once",
            at: createdAt
        )

        #expect(duplicate == first)
        #expect(try fingerprint(fixture) == afterFirst)
        try assertPhysicalReopenSucceeds(fixture)
    }

    @Test("live model presents writer conflict as unaccepted and never calls transport")
    func liveModelPresentsWriterConflictTruthfully() async throws {
        let fixture = try makeFixture(title: "Live writer conflict")
        defer { fixture.cleanup() }
        let transport = NativeAcceptanceProbeTransport()
        let model = AgentRoomsLiveChatModel(
            transport: transport,
            turnCoordinator: HermesTurnCoordinator(),
            persistence: fixture.primaryPersistence
        )
        #expect(model.activateCanonicalRoom(id: fixture.room.id))
        await model.refreshTransportReadiness()
        try fixture.primaryDatabase.runSQL("PRAGMA busy_timeout=1;")
        let before = try fingerprint(fixture)
        try fixture.secondaryDatabase.runSQL("BEGIN IMMEDIATE TRANSACTION;")

        await model.send(
            "Do not claim canonical acceptance",
            selectedRoomID: fixture.room.id.uuidString
        )

        #expect(
            model.composerMessage
                == "Conversation acceptance conflicted with another room update. Nothing was sent."
        )
        #expect(model.statusPresentation.state == .failed)
        #expect(model.activeRoom?.transcript.receipt == nil)
        #expect(model.activeRoom?.transcript.messages.isEmpty == true)
        #expect(await transport.sendCount() == 0)
        #expect(try fingerprint(fixture) == before)
        try fixture.secondaryDatabase.runSQL("ROLLBACK;")
    }

    @Test("native and participant production writers reserve before authoritative reads")
    func productionWritersReserveBeforeAuthorityReads() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let persistenceSource = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Cider/Services/Conversation/AgentRoomsConversationPersistence.swift"
            ),
            encoding: .utf8
        )
        let participantSource = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Cider/Services/Conversation/AgentRoomsParticipantService.swift"
            ),
            encoding: .utf8
        )
        let persistenceBody = try sourceSlice(
            persistenceSource,
            from: "    private func beginAttempt(",
            through: "\n    func markRunStarted("
        )
        let participantBody = try sourceSlice(
            participantSource,
            from: "            accepted = try repository.withImmediateTransaction {",
            through: "\n        } catch let error as CiderDatabaseError"
        )

        try assertAppearsFirst(
            "database.withImmediateTransaction",
            before: [
                "requireOrCreateRoom(",
                "repository.agentAssignment(",
                "repository.messages(",
                "repository.participantRoster(",
                "repository.recordRoutingAcceptance(",
                "repository.beginTurn(",
                "repository.continuationParentMessageID(",
                "repository.upsertMessage(",
            ],
            in: persistenceBody
        )
        try assertAppearsFirst(
            "repository.withImmediateTransaction",
            before: [
                "repository.turns(",
                "participants.invocationPlan(",
                "repository.room(",
                "repository.agentAssignment(",
                "repository.continuationParentMessageID(",
                "repository.upsertMessage(",
                "repository.recordRoutingAcceptance(",
                "beginParticipantTurn(",
            ],
            in: participantBody
        )
        #expect(!persistenceBody.lowercased().contains("hook"))
        #expect(!persistenceBody.lowercased().contains("checkpoint"))
        #expect(!participantBody.lowercased().contains("hook"))
        #expect(!participantBody.lowercased().contains("checkpoint"))
    }

    private struct Fixture {
        let url: URL
        let primaryDatabase: CiderDatabase
        let secondaryDatabase: CiderDatabase
        let primaryRepository: ConversationRepository
        let secondaryRepository: ConversationRepository
        let primaryPersistence: AgentRoomsConversationPersistence
        let secondaryParticipants: AgentRoomsParticipantService
        let catalog: ConversationAgentProfileCatalog
        let headA: ConversationAgentProfile
        let headB: ConversationAgentProfile
        let advisor: ConversationAgentProfile
        let room: ConversationRoom

        @MainActor
        func persistence(
            database: CiderDatabase,
            repository: ConversationRepository
        ) -> AgentRoomsConversationPersistence {
            AgentRoomsConversationPersistence(
                database: database,
                repository: repository,
                defaultAgentProfile: headA,
                participantProfiles: catalog.profiles
            )
        }

        @MainActor
        func cleanup() {
            primaryDatabase.close()
            secondaryDatabase.close()
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(atPath: url.path + "-wal")
            try? FileManager.default.removeItem(atPath: url.path + "-shm")
        }
    }

    private func makeFixture(title: String) throws -> Fixture {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-native-acceptance-\(UUID().uuidString).db")
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
        let assignments = AgentRoomsAgentAssignmentService(
            repository: primaryRepository,
            catalog: catalog
        )
        let room = try AgentRoomsActionService(
            repository: primaryRepository,
            agentAssignments: assignments
        ).createConversation(title: title)
        let secondaryDatabase = CiderDatabase()
        try secondaryDatabase.open(at: url)
        let secondaryRepository = ConversationRepository(database: secondaryDatabase)
        return Fixture(
            url: url,
            primaryDatabase: primaryDatabase,
            secondaryDatabase: secondaryDatabase,
            primaryRepository: primaryRepository,
            secondaryRepository: secondaryRepository,
            primaryPersistence: AgentRoomsConversationPersistence(
                database: primaryDatabase,
                repository: primaryRepository,
                defaultAgentProfile: headA,
                participantProfiles: catalog.profiles
            ),
            secondaryParticipants: AgentRoomsParticipantService(
                repository: secondaryRepository,
                catalog: catalog
            ),
            catalog: catalog,
            headA: headA,
            headB: headB,
            advisor: advisor,
            room: room
        )
    }

    private func profile(id: String, displayName: String) throws -> ConversationAgentProfile {
        try ConversationAgentProfile.validated(
            id: id,
            displayName: displayName,
            runtimeBinding: .init(providerID: "local", runtimeID: id),
            capabilities: [.init(id: "text-chat", displayName: "Text chat")],
            availability: .available
        )
    }

    private func attribution(
        member: ConversationRoomParticipant
    ) -> ConversationParticipantRunAttribution {
        let invocationID = UUID()
        return ConversationParticipantRunAttribution(
            invocationID: invocationID,
            runID: invocationID,
            participantID: member.id,
            profileID: member.profile.id,
            displayName: member.profile.displayName,
            participantRole: member.role,
            selectionSequence: 1
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

    private func fingerprint(_ fixture: Fixture) throws -> NativeAcceptanceFingerprint {
        let messages = try fixture.primaryRepository.messages(roomID: fixture.room.id)
        return NativeAcceptanceFingerprint(
            room: try #require(try fixture.primaryRepository.room(id: fixture.room.id)),
            turns: try fixture.primaryRepository.turns(roomID: fixture.room.id),
            messages: messages,
            bindings: try fixture.primaryRepository.bindings(roomID: fixture.room.id),
            assignment: try fixture.primaryRepository.agentAssignment(roomID: fixture.room.id),
            roster: try fixture.primaryRepository.participantRoster(roomID: fixture.room.id),
            routingAcceptanceHistory: try fixture.primaryRepository.routingAcceptanceHistory(
                roomID: fixture.room.id
            ),
            events: messages.compactMap { message in
                guard let raw = message.metadata[
                    ConversationRepository.headChangeEventMetadataKey
                ] else { return nil }
                return DatabaseHelpers.decodeJSON(
                    ConversationHeadRoutingChangeEvent.self,
                    from: raw
                )
            }
        )
    }

    private func assertPhysicalReopenSucceeds(_ fixture: Fixture) throws {
        fixture.primaryDatabase.close()
        fixture.secondaryDatabase.close()
        let reopenedDatabase = CiderDatabase()
        try reopenedDatabase.open(at: fixture.url)
        defer { reopenedDatabase.close() }
        let persistence = AgentRoomsConversationPersistence(
            database: reopenedDatabase,
            repository: ConversationRepository(database: reopenedDatabase),
            defaultAgentProfile: fixture.headA,
            participantProfiles: fixture.catalog.profiles
        )
        #expect(try persistence.restoreCanonicalRoom(id: fixture.room.id) != nil)
    }

    private func installFailureTrigger(
        _ checkpoint: NativeAcceptanceFailureCheckpoint,
        database: CiderDatabase
    ) throws {
        let sql = switch checkpoint {
        case .routingAcceptance:
            """
            CREATE TEMP TRIGGER native_acceptance_fail_routing
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
                SELECT RAISE(ABORT, 'native acceptance routing failure');
            END;
            """
        case .firstTurn:
            """
            CREATE TEMP TRIGGER native_acceptance_fail_turn
            AFTER INSERT ON conversation_turns
            WHEN instr(NEW.metadata_json, 'attempt_id') > 0
            BEGIN
                SELECT RAISE(ABORT, 'native acceptance first-turn failure');
            END;
            """
        case .userMessage:
            """
            CREATE TEMP TRIGGER native_acceptance_fail_user
            AFTER INSERT ON conversation_messages
            WHEN NEW.source_namespace = 'cider.rooms.client.v1'
            BEGIN
                SELECT RAISE(ABORT, 'native acceptance user-message failure');
            END;
            """
        }
        try database.runSQL(sql)
    }

    private func sourceSlice(
        _ source: String,
        from startNeedle: String,
        through endNeedle: String
    ) throws -> String {
        let start = try #require(source.range(of: startNeedle))
        let end = try #require(
            source.range(of: endNeedle, range: start.upperBound..<source.endIndex)
        )
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private func assertAppearsFirst(
        _ reservation: String,
        before authoritativeReads: [String],
        in source: String
    ) throws {
        let reservationRange = try #require(source.range(of: reservation))
        for read in authoritativeReads {
            let readRange = try #require(source.range(of: read))
            #expect(reservationRange.lowerBound < readRange.lowerBound)
        }
    }

    private func timestamp(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_807_000_000 + offset)
    }
}

private enum NativeAcceptanceFailureCheckpoint: CaseIterable {
    case routingAcceptance
    case firstTurn
    case userMessage
}

private struct NativeAcceptanceFingerprint: Equatable {
    let room: ConversationRoom
    let turns: [ConversationTurn]
    let messages: [ConversationMessage]
    let bindings: [ConversationRuntimeBinding]
    let assignment: ConversationRoomAgentAssignment?
    let roster: ConversationRoomParticipantRoster?
    let routingAcceptanceHistory: ConversationRoutingAcceptanceHistory?
    let events: [ConversationHeadRoutingChangeEvent]
}

private enum NativeAcceptanceProbeError: Error {
    case unexpectedTransportCall
}

private actor NativeAcceptanceProbeTransport: HermesBridgeTransport {
    private var sends = 0

    func availability() async -> HermesBridgeAvailability { .apiRuns }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        sends += 1
        throw NativeAcceptanceProbeError.unexpectedTransportCall
    }

    func stop(runID: String) async throws {}

    func sendCount() -> Int { sends }
}
