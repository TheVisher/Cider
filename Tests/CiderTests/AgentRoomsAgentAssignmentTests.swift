import Foundation
import Testing
@testable import Cider

@Suite("Agent Rooms Agent Assignment Tests")
@MainActor
struct AgentRoomsAgentAssignmentTests {
    @Test("custom provider-neutral profiles validate without a hardcoded roster")
    func customProfilesValidate() throws {
        let profile = try profile(
            id: "studio-advisor",
            displayName: "Studio Advisor",
            providerID: "local-runtime",
            runtimeID: "advisor-v2"
        )
        let catalog = try ConversationAgentProfileCatalog(
            profiles: [profile],
            defaultProfileID: profile.id
        )

        #expect(catalog.profiles == [profile])
        #expect(catalog.defaultProfile == profile)
        #expect(throws: ConversationAgentProfileValidationError.self) {
            try ConversationAgentProfileCatalog(
                profiles: [try self.profile(id: "bad id", displayName: "Unsafe")],
                defaultProfileID: "bad id"
            )
        }
    }

    @Test("room assignment survives physical reopen and runtime session rotation")
    func assignmentSurvivesReopenAndRuntimeRotation() throws {
        let url = disposableDatabaseURL()
        defer { removeDatabase(at: url) }
        let firstProfile = try profile(id: "research", displayName: "Research")
        let catalog = try ConversationAgentProfileCatalog(
            profiles: [firstProfile],
            defaultProfileID: firstProfile.id
        )

        let firstDatabase = CiderDatabase()
        try firstDatabase.open(at: url)
        let firstRepository = ConversationRepository(database: firstDatabase)
        let assignments = AgentRoomsAgentAssignmentService(repository: firstRepository, catalog: catalog)
        let actions = AgentRoomsActionService(
            repository: firstRepository,
            agentAssignments: assignments
        )
        let room = try actions.createConversation(title: "Durable assignment")
        _ = try firstRepository.upsertMessage(.init(
            roomID: room.id,
            role: "user",
            contentText: "Keep this transcript"
        ), intent: .historicalReplay)
        _ = try firstRepository.upsertRuntimeBinding(.init(
            roomID: room.id,
            runtimeID: "hermes",
            transportID: "runs-api",
            sourceNamespace: "hermes.runs.v1",
            externalSessionID: "session-one"
        ))
        firstDatabase.close()

        let reopenedDatabase = CiderDatabase()
        try reopenedDatabase.open(at: url)
        defer { reopenedDatabase.close() }
        let reopenedRepository = ConversationRepository(database: reopenedDatabase)
        let reopenedAssignments = AgentRoomsAgentAssignmentService(
            repository: reopenedRepository,
            catalog: catalog
        )
        _ = try reopenedRepository.upsertRuntimeBinding(.init(
            roomID: room.id,
            runtimeID: "hermes",
            transportID: "runs-api",
            sourceNamespace: "hermes.runs.v1",
            externalSessionID: "session-two"
        ))

        #expect(try reopenedAssignments.assignment(roomID: room.id)?.profile == firstProfile)
        #expect(try reopenedRepository.room(id: room.id)?.id == room.id)
        #expect(try reopenedRepository.messages(roomID: room.id).map(\.contentText) == ["Keep this transcript"])
        #expect(try reopenedRepository.bindings(roomID: room.id).compactMap(\.externalSessionID) == [
            "session-one", "session-two",
        ])
    }

    @Test("unavailable assignment is durable and send-ineligible without fallback")
    func unavailableAssignmentFailsHonestly() throws {
        try withRepository { repository in
            let hermes = try profile(id: "hermes", displayName: "Hermes")
            let unavailable = try profile(
                id: "private-advisor",
                displayName: "Private Advisor",
                providerID: "paid-provider",
                runtimeID: "advisor",
                availability: .unavailable(reason: "Provider credentials are not configured.")
            )
            let catalog = try ConversationAgentProfileCatalog(
                profiles: [hermes, unavailable],
                defaultProfileID: hermes.id
            )
            let assignments = AgentRoomsAgentAssignmentService(repository: repository, catalog: catalog)
            let room = try AgentRoomsActionService(
                repository: repository,
                agentAssignments: assignments
            ).createConversation(title: "Explicit provider")

            _ = try assignments.assign(profileID: unavailable.id, roomID: room.id)
            let persisted = try #require(try assignments.assignment(roomID: room.id))
            let eligibility = try assignments.sendEligibility(roomID: room.id)

            #expect(persisted.profile.id == unavailable.id)
            #expect(eligibility == .ineligible(
                profileID: unavailable.id,
                displayName: unavailable.displayName,
                reason: "Provider credentials are not configured."
            ))
            #expect(persisted.profile.runtimeBinding.providerID == "paid-provider")
        }
    }

    @Test("read service exposes the persisted acting agent independently of runtime bindings")
    func readServiceProjectsAssignment() throws {
        try withRepository { repository in
            let profile = try profile(id: "cider", displayName: "Cider")
            let catalog = try ConversationAgentProfileCatalog(
                profiles: [profile],
                defaultProfileID: profile.id
            )
            let assignments = AgentRoomsAgentAssignmentService(repository: repository, catalog: catalog)
            let room = try AgentRoomsActionService(
                repository: repository,
                agentAssignments: assignments
            ).createConversation(title: "Assigned room")
            let state = AgentRoomsReadService(
                repository: repository,
                agentAssignments: assignments
            ).loadWorkspace()

            guard case .loaded(_, let rooms, _) = state else {
                Issue.record("Expected a canonical room projection")
                return
            }
            let projected = try #require(rooms.first(where: { $0.id == room.id.uuidString }))
            #expect(projected.actingAgent?.profileID == profile.id)
            #expect(projected.actingAgent?.displayName == profile.displayName)
            #expect(projected.actingAgent?.sendEligible == true)
        }
    }

    @Test("unavailable assigned provider blocks before transport and preserves an empty transcript")
    func unavailableProviderNeverReachesTransport() async throws {
        try await withRepository { repository in
            let unavailable = try profile(
                id: "paid-advisor",
                displayName: "Paid Advisor",
                providerID: "paid-provider",
                runtimeID: "advisor",
                availability: .unavailable(reason: "Paid Advisor is offline.")
            )
            let catalog = try ConversationAgentProfileCatalog(
                profiles: [unavailable],
                defaultProfileID: unavailable.id
            )
            let assignments = AgentRoomsAgentAssignmentService(repository: repository, catalog: catalog)
            let room = try AgentRoomsActionService(
                repository: repository,
                agentAssignments: assignments
            ).createConversation(title: "No fallback")
            let transport = AssignmentProbeTransport()
            let liveChat = AgentRoomsLiveChatModel(
                transport: transport,
                turnCoordinator: HermesTurnCoordinator(),
                persistence: AgentRoomsConversationPersistence(
                    repository: repository,
                    defaultAgentProfile: unavailable
                ),
                agentAssignments: assignments
            )

            #expect(liveChat.activateCanonicalRoom(id: room.id))
            await liveChat.refreshTransportReadiness()
            await liveChat.send("Do not send this", selectedRoomID: room.id.uuidString)

            #expect(liveChat.transportState == .blocked)
            #expect(liveChat.composerMessage == "Paid Advisor is offline.")
            #expect(await transport.sendCount() == 0)
            #expect(try repository.turns(roomID: room.id).isEmpty)
            #expect(try repository.messages(roomID: room.id).isEmpty)
        }
    }

    @Test("assignment changes fail closed for archived and noncanonical rooms")
    func assignmentChangesRespectRoomAuthority() throws {
        try withRepository { repository in
            let profile = try profile(id: "hermes", displayName: "Hermes")
            let catalog = try ConversationAgentProfileCatalog(
                profiles: [profile],
                defaultProfileID: profile.id
            )
            let assignments = AgentRoomsAgentAssignmentService(repository: repository, catalog: catalog)
            let actions = AgentRoomsActionService(
                repository: repository,
                agentAssignments: assignments
            )
            let archived = try actions.createConversation(title: "Archived")
            _ = try actions.archiveConversation(id: archived.id)
            let legacy = try repository.createRoom(.init(
                stableKey: "legacy.private.room",
                title: "Legacy",
                metadata: ["authority": "legacy-authoritative"]
            ))

            #expect(throws: ConversationRepositoryError.self) {
                try assignments.assign(profileID: profile.id, roomID: archived.id)
            }
            #expect(throws: ConversationRepositoryError.self) {
                try assignments.assign(profileID: profile.id, roomID: legacy.id)
            }
            #expect(try assignments.assignment(roomID: legacy.id) == nil)
        }
    }

    @Test("reserved Test Chat is created with an explicit selectable assignment")
    func reservedTestChatAssignment() throws {
        try withRepository { repository in
            let hermes = try profile(id: "hermes", displayName: "Hermes")
            let advisor = try profile(
                id: "advisor",
                displayName: "Advisor",
                providerID: "local",
                runtimeID: "advisor",
                availability: .unavailable(reason: "Advisor is offline.")
            )
            let catalog = try ConversationAgentProfileCatalog(
                profiles: [hermes, advisor],
                defaultProfileID: hermes.id
            )
            let assignments = AgentRoomsAgentAssignmentService(repository: repository, catalog: catalog)
            let roomID = UUID()
            let persistence = AgentRoomsConversationPersistence(
                repository: repository,
                defaultAgentProfile: hermes
            )

            let snapshot = try #require(try persistence.prepareReservedTestChat(
                id: roomID,
                at: Date(timeIntervalSince1970: 1_800_000_000)
            ))
            #expect(snapshot.room.id == roomID)
            #expect(try assignments.assignment(roomID: roomID)?.profile.id == hermes.id)

            _ = try assignments.assign(profileID: advisor.id, roomID: roomID)
            #expect(try assignments.assignment(roomID: roomID)?.profile.id == advisor.id)
            #expect(try assignments.sendEligibility(roomID: roomID) == .ineligible(
                profileID: advisor.id,
                displayName: advisor.displayName,
                reason: "Advisor is offline."
            ))
        }
    }

    @Test("production Hermes composition accepts an explicit roster participant and rejects unavailable advisor before transport")
    func productionCompositionRoutesExplicitParticipantOnly() async throws {
        try await withDatabaseAndRepository { database, repository in
            let hermes = try profile(id: "hermes", displayName: "Hermes")
            let codex = try profile(
                id: "codex",
                displayName: "Codex",
                providerID: "openai",
                runtimeID: "codex",
                availability: .unavailable(reason: "Codex is not connected.")
            )
            let catalog = try ConversationAgentProfileCatalog(
                profiles: [hermes, codex],
                defaultProfileID: hermes.id
            )
            let assignments = AgentRoomsAgentAssignmentService(repository: repository, catalog: catalog)
            let participants = AgentRoomsParticipantService(repository: repository, catalog: catalog)
            let room = try AgentRoomsActionService(
                repository: repository,
                agentAssignments: assignments
            ).createConversation(title: "Production participant routing")
            let roster = try #require(try participants.roster(roomID: room.id))
            let hermesID = try #require(roster.members.first(where: { $0.profile.id == hermes.id })?.id)
            let codexID = try #require(roster.members.first(where: { $0.profile.id == codex.id })?.id)
            let transport = AssignmentProbeTransport()
            let liveChat = AgentRoomsLiveChatModel(
                transport: transport,
                turnCoordinator: HermesTurnCoordinator(),
                persistence: AgentRoomsConversationPersistence(
                    database: database,
                    repository: repository,
                    defaultAgentProfile: hermes,
                    participantProfiles: catalog.profiles
                ),
                agentAssignments: assignments,
                participants: participants
            )

            #expect(liveChat.activateCanonicalRoom(id: room.id))
            await liveChat.refreshTransportReadiness()
            let disposition = liveChat.startSubmission(
                "Invoke Hermes explicitly",
                selectedRoomID: room.id.uuidString,
                invokedParticipantIDs: [hermesID]
            )
            guard disposition == .accepted else {
                Issue.record("Explicit Hermes invocation was rejected: \(liveChat.composerMessage ?? "no reason")")
                return
            }
            for _ in 0..<200 where await transport.sendCount() == 0 {
                try await Task.sleep(for: .milliseconds(5))
            }
            for _ in 0..<200 where liveChat.turnState != .failed {
                try await Task.sleep(for: .milliseconds(5))
            }

            let acceptedTurns = try repository.turns(roomID: room.id)
            let acceptedMessages = try repository.messages(roomID: room.id)
            #expect(acceptedTurns.count == 1)
            #expect(try participants.turnAttribution(acceptedTurns[0])?.participantID == hermesID)
            #expect(try participants.messageAttribution(acceptedMessages[0])?.invocationID
                == participants.turnAttribution(acceptedTurns[0])?.invocationID)
            #expect(await transport.sendCount() == 1)

            #expect(liveChat.startSubmission(
                "Do not invoke Codex",
                selectedRoomID: room.id.uuidString,
                invokedParticipantIDs: [codexID]
            ) == .rejected)
            #expect(liveChat.composerMessage == "Codex is not connected. Nothing was sent.")
            #expect(await transport.sendCount() == 1)
            #expect(try repository.turns(roomID: room.id).count == 1)
            #expect(try repository.messages(roomID: room.id).count == 1)
        }
    }

    private func profile(
        id: String,
        displayName: String,
        providerID: String = "hermes",
        runtimeID: String = "hermes",
        availability: ConversationAgentAvailability = .available
    ) throws -> ConversationAgentProfile {
        try ConversationAgentProfile.validated(
            id: id,
            displayName: displayName,
            runtimeBinding: .init(providerID: providerID, runtimeID: runtimeID),
            capabilities: [
                .init(id: "text-chat", displayName: "Text chat"),
                .init(id: "streaming", displayName: "Streaming"),
            ],
            availability: availability
        )
    }

    private func withRepository<T>(_ body: (ConversationRepository) throws -> T) throws -> T {
        let url = disposableDatabaseURL()
        let database = CiderDatabase()
        try database.open(at: url)
        defer {
            database.close()
            removeDatabase(at: url)
        }
        return try body(ConversationRepository(database: database))
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

    private func withDatabaseAndRepository<T>(
        _ body: (CiderDatabase, ConversationRepository) async throws -> T
    ) async throws -> T {
        let url = disposableDatabaseURL()
        let database = CiderDatabase()
        try database.open(at: url)
        defer {
            database.close()
            removeDatabase(at: url)
        }
        return try await body(database, ConversationRepository(database: database))
    }

    private func disposableDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-agent-assignment-\(UUID().uuidString).db")
    }

    private func removeDatabase(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
    }
}

private actor AssignmentProbeTransport: HermesBridgeTransport {
    private var sends = 0

    func availability() async -> HermesBridgeAvailability { .apiRuns }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        sends += 1
        throw CancellationError()
    }

    func stop(runID: String) async throws {}
    func sendCount() -> Int { sends }
}
