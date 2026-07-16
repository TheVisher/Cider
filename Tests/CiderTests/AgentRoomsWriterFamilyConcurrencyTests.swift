import Foundation
import Testing
@testable import Cider

@Suite("Agent Rooms Writer Family Concurrency Tests")
@MainActor
struct AgentRoomsWriterFamilyConcurrencyTests {
    @Test("assignment rejects an archive committed after service preflight without family mutation")
    func assignmentRejectsArchiveAfterPreflight() throws {
        let fixture = try makeFixture(title: "Assignment lifecycle race")
        defer { fixture.cleanup() }
        let before = try fingerprint(fixture.primaryRepository, roomID: fixture.room.id)
        let archiveAt = timestamp(10)
        var archived = false
        let assignments = AgentRoomsAgentAssignmentService(
            repository: fixture.primaryRepository,
            catalog: fixture.catalog,
            now: {
                if !archived {
                    archived = true
                    _ = try! fixture.secondaryActions.archiveConversation(id: fixture.room.id)
                }
                return archiveAt
            }
        )

        #expect(throws: ConversationRepositoryError.invalidDraft(
            "Archived or trashed conversations cannot change acting agent."
        )) {
            try assignments.assign(profileID: fixture.headB.id, roomID: fixture.room.id)
        }

        let after = try fingerprint(fixture.primaryRepository, roomID: fixture.room.id)
        #expect(archived)
        #expect(after.room.lifecycleState == .archived)
        #expect(after.room.archivedAt != nil)
        #expect(after.withoutLifecycle == before.withoutLifecycle)
        #expect(after.assignment == before.assignment)
        #expect(after.roster == before.roster)
        #expect(after.messages == before.messages)
        #expect(after.turns == before.turns)
        #expect(after.routingAcceptanceHistory == before.routingAcceptanceHistory)
        try assertArchivedPhysicalReopen(fixture, expected: after)
    }

    @Test("roster rejects an archive committed after service preflight without family mutation")
    func rosterRejectsArchiveAfterPreflight() throws {
        let fixture = try makeFixture(title: "Roster lifecycle race")
        defer { fixture.cleanup() }
        let before = try fingerprint(fixture.primaryRepository, roomID: fixture.room.id)
        let archiveAt = timestamp(20)
        var archived = false
        let participants = AgentRoomsParticipantService(
            repository: fixture.primaryRepository,
            catalog: fixture.catalog,
            now: {
                if !archived {
                    archived = true
                    _ = try! fixture.secondaryActions.archiveConversation(id: fixture.room.id)
                }
                return archiveAt
            }
        )

        #expect(throws: ConversationParticipantInvocationError.invalid(
            "Archived or trashed conversations cannot change participants."
        )) {
            try participants.configureRoster(
                roomID: fixture.room.id,
                members: [
                    .init(profileID: fixture.headB.id, role: .actingAgent),
                    .init(profileID: fixture.advisor.id, role: .advisor),
                ]
            )
        }

        let after = try fingerprint(fixture.primaryRepository, roomID: fixture.room.id)
        #expect(archived)
        #expect(after.room.lifecycleState == .archived)
        #expect(after.room.archivedAt != nil)
        #expect(after.withoutLifecycle == before.withoutLifecycle)
        #expect(after.assignment == before.assignment)
        #expect(after.roster == before.roster)
        #expect(after.messages == before.messages)
        #expect(after.turns == before.turns)
        #expect(after.routingAcceptanceHistory == before.routingAcceptanceHistory)
        try assertArchivedPhysicalReopen(fixture, expected: after)
    }

    @Test("active assignment refresh and roster replacement each commit truthful metadata once")
    func activeWriterControlsSucceedOnce() throws {
        let fixture = try makeFixture(title: "Active writer controls")
        defer { fixture.cleanup() }
        let initialRoster = try #require(
            try fixture.primaryRepository.participantRoster(roomID: fixture.room.id)
        )
        let assignments = AgentRoomsAgentAssignmentService(
            repository: fixture.primaryRepository,
            catalog: fixture.catalog,
            now: { timestamp(30) }
        )

        let changed = try assignments.assign(
            profileID: fixture.headB.id,
            roomID: fixture.room.id
        )
        let refreshedHead = try profile(
            id: fixture.headB.id,
            displayName: "Codex Refreshed",
            providerID: "openai",
            runtimeID: "codex-refreshed"
        )
        let refreshedCatalog = try ConversationAgentProfileCatalog(
            profiles: [fixture.headA, refreshedHead, fixture.advisor],
            defaultProfileID: fixture.headA.id
        )
        let refreshed = try AgentRoomsAgentAssignmentService(
            repository: fixture.primaryRepository,
            catalog: refreshedCatalog,
            now: { timestamp(31) }
        ).assign(profileID: refreshedHead.id, roomID: fixture.room.id)
        let roster = try AgentRoomsParticipantService(
            repository: fixture.primaryRepository,
            catalog: refreshedCatalog,
            now: { timestamp(32) }
        ).configureRoster(
            roomID: fixture.room.id,
            members: [
                .init(profileID: refreshedHead.id, role: .actingAgent),
                .init(profileID: fixture.advisor.id, role: .advisor),
            ]
        )

        let messages = try fixture.primaryRepository.messages(roomID: fixture.room.id)
        let events = try messages.compactMap(headChangeEvent)
        #expect(changed.headRoutingEpoch == 2)
        #expect(refreshed.headRoutingEpoch == changed.headRoutingEpoch)
        #expect(refreshed.profile == refreshedHead)
        #expect(events.count == 1)
        #expect(events[0].oldHead?.profileID == fixture.headA.id)
        #expect(events[0].newHead.profileID == fixture.headB.id)
        #expect(events[0].newHeadRoutingEpoch == changed.headRoutingEpoch)
        #expect(messages.map(\.sequence) == [1])
        #expect(
            try fixture.primaryRepository.room(id: fixture.room.id)?.nextMessageSequence == 2
        )
        #expect(roster.members.map(\.profile.id) == [
            refreshedHead.id, fixture.advisor.id,
        ])
        #expect(
            roster.members[0].id
                == initialRoster.members.first(where: {
                    $0.profile.id == fixture.headB.id
                })?.id
        )
        #expect(
            roster.members[1].id
                == initialRoster.members.first(where: {
                    $0.profile.id == fixture.advisor.id
                })?.id
        )
        try assertActivePhysicalReopen(
            fixture,
            defaultProfile: fixture.headA,
            profiles: refreshedCatalog.profiles
        )
    }

    @Test("assignment and roster writer locks are typed zero-mutation conflicts and retry once")
    func writerLockConflictsThenRetriesOnce() throws {
        let fixture = try makeFixture(title: "Writer lock controls")
        defer { fixture.cleanup() }
        try fixture.primaryDatabase.runSQL("PRAGMA busy_timeout=1;")
        let assignments = AgentRoomsAgentAssignmentService(
            repository: fixture.primaryRepository,
            catalog: fixture.catalog,
            now: { timestamp(40) }
        )
        let participants = AgentRoomsParticipantService(
            repository: fixture.primaryRepository,
            catalog: fixture.catalog,
            now: { timestamp(41) }
        )

        let beforeAssignment = try fingerprint(
            fixture.primaryRepository,
            roomID: fixture.room.id
        )
        try fixture.secondaryDatabase.runSQL("BEGIN IMMEDIATE TRANSACTION;")
        do {
            _ = try assignments.assign(
                profileID: fixture.headB.id,
                roomID: fixture.room.id
            )
            Issue.record("Expected assignment writer contention")
        } catch let error as CiderDatabaseError {
            #expect(error.isBusyConflict)
        } catch {
            Issue.record("Expected typed database contention, got \(error)")
        }
        #expect(
            try fingerprint(fixture.primaryRepository, roomID: fixture.room.id)
                == beforeAssignment
        )
        try fixture.secondaryDatabase.runSQL("ROLLBACK;")

        let assignment = try assignments.assign(
            profileID: fixture.headB.id,
            roomID: fixture.room.id
        )
        #expect(assignment.headRoutingEpoch == 2)
        #expect(
            try fixture.primaryRepository.messages(roomID: fixture.room.id)
                .compactMap(headChangeEvent).count == 1
        )

        let beforeRoster = try fingerprint(
            fixture.primaryRepository,
            roomID: fixture.room.id
        )
        try fixture.secondaryDatabase.runSQL("BEGIN IMMEDIATE TRANSACTION;")
        do {
            _ = try participants.configureRoster(
                roomID: fixture.room.id,
                members: [
                    .init(profileID: fixture.headB.id, role: .actingAgent),
                    .init(profileID: fixture.advisor.id, role: .advisor),
                ]
            )
            Issue.record("Expected roster writer contention")
        } catch let error as CiderDatabaseError {
            #expect(error.isBusyConflict)
        } catch {
            Issue.record("Expected typed database contention, got \(error)")
        }
        #expect(
            try fingerprint(fixture.primaryRepository, roomID: fixture.room.id)
                == beforeRoster
        )
        try fixture.secondaryDatabase.runSQL("ROLLBACK;")

        let roster = try participants.configureRoster(
            roomID: fixture.room.id,
            members: [
                .init(profileID: fixture.headB.id, role: .actingAgent),
                .init(profileID: fixture.advisor.id, role: .advisor),
            ]
        )
        #expect(roster.members.map(\.profile.id) == [
            fixture.headB.id, fixture.advisor.id,
        ])
        #expect(
            try fixture.primaryRepository.messages(roomID: fixture.room.id)
                .compactMap(headChangeEvent).count == 1
        )
        try assertActivePhysicalReopen(
            fixture,
            defaultProfile: fixture.headA,
            profiles: fixture.catalog.profiles
        )
    }

    @Test("TEMP trigger failures roll back assignment event and roster replacement units")
    func writerFamilyTriggerFailuresRollback() throws {
        let fixture = try makeFixture(title: "Writer trigger rollback")
        defer { fixture.cleanup() }
        let assignments = AgentRoomsAgentAssignmentService(
            repository: fixture.primaryRepository,
            catalog: fixture.catalog,
            now: { timestamp(50) }
        )
        let participants = AgentRoomsParticipantService(
            repository: fixture.primaryRepository,
            catalog: fixture.catalog,
            now: { timestamp(51) }
        )
        let beforeAssignment = try fingerprint(
            fixture.primaryRepository,
            roomID: fixture.room.id
        )
        try fixture.primaryDatabase.runSQL("""
            CREATE TEMP TRIGGER cid841_assignment_event_failure
            BEFORE INSERT ON conversation_messages
            WHEN NEW.source_namespace = '\(ConversationRepository.headChangeEventSourceNamespace)'
            BEGIN
                SELECT RAISE(ABORT, 'assignment event failure');
            END;
            """)

        #expect(throws: Error.self) {
            try assignments.assign(profileID: fixture.headB.id, roomID: fixture.room.id)
        }
        #expect(
            try fingerprint(fixture.primaryRepository, roomID: fixture.room.id)
                == beforeAssignment
        )
        try fixture.primaryDatabase.runSQL(
            "DROP TRIGGER cid841_assignment_event_failure;"
        )

        let beforeRoster = try fingerprint(
            fixture.primaryRepository,
            roomID: fixture.room.id
        )
        try fixture.primaryDatabase.runSQL("""
            CREATE TEMP TRIGGER cid841_roster_replacement_failure
            AFTER UPDATE OF metadata_json ON conversation_rooms
            WHEN NEW.id = '\(fixture.room.id.uuidString)'
              AND NEW.metadata_json != OLD.metadata_json
              AND instr(
                  NEW.metadata_json,
                  '\(ConversationRepository.participantRosterMetadataKey)'
              ) > 0
            BEGIN
                SELECT RAISE(ABORT, 'roster replacement failure');
            END;
            """)

        #expect(throws: Error.self) {
            try participants.configureRoster(
                roomID: fixture.room.id,
                members: [
                    .init(profileID: fixture.headB.id, role: .actingAgent),
                    .init(profileID: fixture.advisor.id, role: .advisor),
                ]
            )
        }
        #expect(
            try fingerprint(fixture.primaryRepository, roomID: fixture.room.id)
                == beforeRoster
        )
        try fixture.primaryDatabase.runSQL(
            "DROP TRIGGER cid841_roster_replacement_failure;"
        )
        try assertActivePhysicalReopen(
            fixture,
            defaultProfile: fixture.headA,
            profiles: fixture.catalog.profiles
        )
    }

    @Test("every room writer reserves and the full production conversation scope has no orchestration seam")
    func productionWriterFamilyReservationAudit() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let repositoryURL = root.appendingPathComponent(
            "Sources/Cider/Services/Conversation/ConversationRepository.swift"
        )
        let repository = try String(contentsOf: repositoryURL, encoding: .utf8)
        let participant = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Cider/Services/Conversation/AgentRoomsParticipantService.swift"
            ),
            encoding: .utf8
        )
        let persistence = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Cider/Services/Conversation/AgentRoomsConversationPersistence.swift"
            ),
            encoding: .utf8
        )
        let shadow = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Cider/Services/Conversation/ConversationShadowWriter.swift"
            ),
            encoding: .utf8
        )

        let assignment = try sourceSlice(
            repository,
            from: "    func setAgentAssignment(",
            through: "\n    func continuationParentMessageID("
        )
        try assertAppearsFirst(
            "database.withImmediateTransaction",
            before: [
                "requiredRoom(id: roomID)",
                "room.lifecycleState == .active",
                "agentAssignment(roomID: roomID)",
                "continuationParentMessageID(",
                "upsertMessage(",
            ],
            in: assignment
        )
        let roster = try sourceSlice(
            repository,
            from: "    func setParticipantRoster(",
            through: "\n    /// Returns a bounded lifecycle projection"
        )
        try assertAppearsFirst(
            "database.withImmediateTransaction",
            before: [
                "requiredRoom(id: roomID)",
                "room.lifecycleState == .active",
                "participantRoster(roomID: roomID)",
                "UPDATE conversation_rooms",
            ],
            in: roster
        )
        let configureRoster = try sourceSlice(
            participant,
            from: "        let room = try requireParticipantRoom(id: roomID)",
            through: "\n    func presentation("
        )
        #expect(!configureRoster.contains("repository.participantRoster"))

        for function in [
            "renameRoom", "setLifecycle", "advanceRoomActivity",
            "finalizeHistoricalRoomImport", "upsertRuntimeBinding", "beginTurn",
            "bindActiveTurnExecution", "transitionTurn",
            "upsertMessage", "recordTurnSnapshot",
        ] {
            let body = try functionSlice(function, in: repository)
            #expect(
                body.contains("withImmediateTransaction"),
                "Missing immediate root in \(function)"
            )
        }
        #expect(
            try functionSlice("createRoom", in: repository)
                .contains("withTransaction")
        )
        let exportSource = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Cider/Services/Conversation/AgentRoomsRoomExportService.swift"
            ),
            encoding: .utf8
        )
        let exportRender = try sourceSlice(
            exportSource,
            from: "final class AgentRoomsRoomExportService",
            through: "\n    func export("
        )
        #expect(exportRender.contains("withTransaction"))
        let concretePersistence = try sourceSlice(
            persistence,
            from: "final class AgentRoomsConversationPersistence",
            through: "\n    private struct ValidatedTerminal"
        )
        #expect(
            try functionSlice("markRunStarted", in: concretePersistence)
                .contains("withImmediateTransaction")
        )
        #expect(
            try functionSlice("validatedRecoverySnapshot", in: persistence)
                .contains("withImmediateTransaction")
        )
        #expect(!participant.contains("repository.withTransaction {"))
        #expect(
            try functionSlice("write", in: shadow)
                .contains("withImmediateTransaction")
        )
        #expect(
            try functionSlice(
                "writeVerifiedSequentialCompletedSnapshot",
                in: shadow
            ).contains("withImmediateTransaction")
        )

        let sourcesRoot = root.appendingPathComponent("Sources/Cider")
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: sourcesRoot,
                includingPropertiesForKeys: nil
            )
        )
        var directConversationWriters: [String] = []
        var relevantProductionSources: [String: String] = [:]
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            let relativePath = file.path.replacingOccurrences(
                of: root.path + "/",
                with: ""
            )
            if source.range(
                of: #"(INSERT INTO|UPDATE|DELETE FROM)\s+conversation_"#,
                options: .regularExpression
            ) != nil {
                directConversationWriters.append(relativePath)
            }
            let name = file.deletingPathExtension().lastPathComponent
            if relativePath.contains("/Services/Conversation/")
                || relativePath.contains("/Views/AgentRooms/")
                || name.contains("Conversation")
                || name.contains("AgentRooms")
                || relativePath == "Sources/Cider/App/AppDelegate.swift"
            {
                relevantProductionSources[relativePath] = source
            }
        }
        #expect(directConversationWriters.sorted() == [
            "Sources/Cider/Services/Conversation/ConversationRepository.swift",
        ])

        let requiredBoundaryFiles = [
            "Sources/Cider/App/AppDelegate.swift",
            "Sources/Cider/App/ConversationShadowRuntimeComposition.swift",
            "Sources/Cider/Services/Conversation/ConversationShadowWriter.swift",
            "Sources/Cider/Services/Conversation/ConversationRepository.swift",
            "Sources/Cider/Services/Conversation/AgentRoomsConversationPersistence.swift",
            "Sources/Cider/Services/Conversation/AgentRoomsParticipantService.swift",
            "Sources/Cider/Services/Conversation/AgentRoomsAgentAssignmentService.swift",
            "Sources/Cider/Services/Conversation/LegacyConversationEligiblePreviewService.swift",
        ]
        #expect(
            requiredBoundaryFiles.allSatisfy {
                relevantProductionSources[$0] != nil
            }
        )
        #expect(relevantProductionSources.count > 30)

        let forbiddenIdentifiers = [
            "ConversationShadowWriterCheckpoint",
            "writerCheckpoint",
            "beforeRevalidation",
            "checkpoint: @escaping",
            "testHook",
            "testCallback",
        ]
        for (path, source) in relevantProductionSources {
            for identifier in forbiddenIdentifiers {
                #expect(
                    !source.contains(identifier),
                    "Forbidden production seam \(identifier) in \(path)"
                )
            }
            #expect(
                source.range(
                    of: #"(?i)(checkpoint|hook|callback|before(?:write|read|commit|mutation)|after(?:write|read|commit|mutation))\s*:\s*@escaping"#,
                    options: .regularExpression
                ) == nil,
                "Suspicious production orchestration callback in \(path)"
            )
        }

        let writerBoundaryPaths = [
            "Sources/Cider/Services/Conversation/ConversationRepository.swift",
            "Sources/Cider/Services/Conversation/AgentRoomsConversationPersistence.swift",
            "Sources/Cider/Services/Conversation/AgentRoomsParticipantService.swift",
            "Sources/Cider/Services/Conversation/AgentRoomsAgentAssignmentService.swift",
            "Sources/Cider/Services/Conversation/ConversationShadowWriter.swift",
        ]
        for path in writerBoundaryPaths {
            let source = try #require(relevantProductionSources[path])
            #expect(
                source.range(
                    of: #"private let \w+\s*:\s*\([^)]*\)\s*throws\s*->"#,
                    options: .regularExpression
                ) == nil,
                "Stored arbitrary throwing closure in writer boundary \(path)"
            )
        }

        let assignmentPublisher = try #require(relevantProductionSources[
            "Sources/Cider/Services/Conversation/AgentRoomsAgentAssignmentService.swift"
        ])
        let liveModel = try #require(relevantProductionSources[
            "Sources/Cider/Services/Conversation/AgentRoomsLiveChatModel.swift"
        ])
        #expect(assignmentPublisher.contains("assignmentObservers"))
        #expect(liveModel.contains("observeAssignmentChanges("))
        #expect(liveModel.contains("AgentRoomsCanonicalSavedBookmarkResolver.matches"))
        #expect(liveModel.contains("AgentRoomsCanonicalAssetResolver.openRoute"))

        let attachment = try #require(relevantProductionSources[
            "Sources/Cider/Services/Conversation/AgentRoomsAttachmentService.swift"
        ])
        let session = try #require(relevantProductionSources[
            "Sources/Cider/Services/Conversation/AgentRoomsSessionModel.swift"
        ])
        #expect(attachment.contains("didMaterialize()"))
        #expect(session.contains("VaultFileService.shared.scan()"))

        let eligiblePreview = try #require(relevantProductionSources[
            "Sources/Cider/Services/Conversation/LegacyConversationEligiblePreviewService.swift"
        ])
        #expect(eligiblePreview.contains("private let fileManager: FileManager"))
        #expect(eligiblePreview.contains("snapshotIsUnchanged"))
        #expect(!eligiblePreview.contains("beforeRevalidation"))

        let readService = try #require(relevantProductionSources[
            "Sources/Cider/Services/Conversation/AgentRoomsReadService.swift"
        ])
        #expect(readService.contains("Internal injection keeps tests temporary"))
        #expect(
            readService.range(
                of: #"(INSERT INTO|UPDATE|DELETE FROM)\s+conversation_"#,
                options: .regularExpression
            ) == nil
        )
    }

    private struct Fixture {
        let url: URL
        let primaryDatabase: CiderDatabase
        let secondaryDatabase: CiderDatabase
        let primaryRepository: ConversationRepository
        let secondaryRepository: ConversationRepository
        let secondaryActions: AgentRoomsActionService
        let catalog: ConversationAgentProfileCatalog
        let headA: ConversationAgentProfile
        let headB: ConversationAgentProfile
        let advisor: ConversationAgentProfile
        let room: ConversationRoom

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
            .appendingPathComponent(
                "cider-writer-family-\(UUID().uuidString).db"
            )
        let headA = try profile(
            id: "hermes",
            displayName: "Hermes",
            providerID: "hermes",
            runtimeID: "hermes"
        )
        let headB = try profile(
            id: "codex",
            displayName: "Codex",
            providerID: "openai",
            runtimeID: "codex"
        )
        let advisor = try profile(
            id: "research",
            displayName: "Research",
            providerID: "local",
            runtimeID: "research"
        )
        let catalog = try ConversationAgentProfileCatalog(
            profiles: [headA, headB, advisor],
            defaultProfileID: headA.id
        )
        let primaryDatabase = CiderDatabase()
        try primaryDatabase.open(at: url)
        let primaryRepository = ConversationRepository(database: primaryDatabase)
        let primaryAssignments = AgentRoomsAgentAssignmentService(
            repository: primaryRepository,
            catalog: catalog,
            now: { timestamp(1) }
        )
        let room = try AgentRoomsActionService(
            repository: primaryRepository,
            agentAssignments: primaryAssignments,
            now: { timestamp(1) }
        ).createConversation(title: title)

        let secondaryDatabase = CiderDatabase()
        try secondaryDatabase.open(at: url)
        let secondaryRepository = ConversationRepository(database: secondaryDatabase)
        let secondaryAssignments = AgentRoomsAgentAssignmentService(
            repository: secondaryRepository,
            catalog: catalog,
            now: { timestamp(2) }
        )
        return Fixture(
            url: url,
            primaryDatabase: primaryDatabase,
            secondaryDatabase: secondaryDatabase,
            primaryRepository: primaryRepository,
            secondaryRepository: secondaryRepository,
            secondaryActions: AgentRoomsActionService(
                repository: secondaryRepository,
                agentAssignments: secondaryAssignments,
                now: { timestamp(2) }
            ),
            catalog: catalog,
            headA: headA,
            headB: headB,
            advisor: advisor,
            room: room
        )
    }

    private func profile(
        id: String,
        displayName: String,
        providerID: String,
        runtimeID: String
    ) throws -> ConversationAgentProfile {
        try ConversationAgentProfile.validated(
            id: id,
            displayName: displayName,
            runtimeBinding: .init(
                providerID: providerID,
                runtimeID: runtimeID
            ),
            capabilities: [
                .init(id: "text-chat", displayName: "Text chat"),
                .init(id: "streaming", displayName: "Streaming"),
            ],
            availability: .available
        )
    }

    private func fingerprint(
        _ repository: ConversationRepository,
        roomID: UUID
    ) throws -> WriterFamilyFingerprint {
        let room = try #require(try repository.room(id: roomID))
        return WriterFamilyFingerprint(
            room: room,
            turns: try repository.turns(roomID: roomID),
            messages: try repository.messages(roomID: roomID),
            bindings: try repository.bindings(roomID: roomID),
            assignment: try repository.agentAssignment(roomID: roomID),
            roster: try repository.participantRoster(roomID: roomID),
            routingAcceptanceHistory: try repository.routingAcceptanceHistory(
                roomID: roomID
            )
        )
    }

    private func assertArchivedPhysicalReopen(
        _ fixture: Fixture,
        expected: WriterFamilyFingerprint
    ) throws {
        fixture.primaryDatabase.close()
        fixture.secondaryDatabase.close()
        let database = CiderDatabase()
        try database.open(at: fixture.url)
        defer { database.close() }
        let repository = ConversationRepository(database: database)
        let reopened = try fingerprint(repository, roomID: fixture.room.id)
        #expect(reopened == expected)
        #expect(try database.integrityCheck().isHealthy)

        let assignments = AgentRoomsAgentAssignmentService(
            repository: repository,
            catalog: fixture.catalog,
            now: { timestamp(90) }
        )
        _ = try AgentRoomsActionService(
            repository: repository,
            agentAssignments: assignments,
            now: { timestamp(90) }
        ).restoreConversation(id: fixture.room.id)
        let persistence = AgentRoomsConversationPersistence(
            database: database,
            repository: repository,
            defaultAgentProfile: fixture.headA,
            participantProfiles: fixture.catalog.profiles
        )
        #expect(try persistence.restoreCanonicalRoom(id: fixture.room.id) != nil)
        #expect(
            try fingerprint(repository, roomID: fixture.room.id).withoutLifecycle
                == expected.withoutLifecycle
        )
    }

    private func assertActivePhysicalReopen(
        _ fixture: Fixture,
        defaultProfile: ConversationAgentProfile,
        profiles: [ConversationAgentProfile]
    ) throws {
        let expected = try fingerprint(
            fixture.primaryRepository,
            roomID: fixture.room.id
        )
        fixture.primaryDatabase.close()
        fixture.secondaryDatabase.close()
        let database = CiderDatabase()
        try database.open(at: fixture.url)
        defer { database.close() }
        let repository = ConversationRepository(database: database)
        #expect(
            try fingerprint(repository, roomID: fixture.room.id) == expected
        )
        #expect(try database.integrityCheck().isHealthy)
        let persistence = AgentRoomsConversationPersistence(
            database: database,
            repository: repository,
            defaultAgentProfile: defaultProfile,
            participantProfiles: profiles
        )
        #expect(try persistence.restoreCanonicalRoom(id: fixture.room.id) != nil)
    }

    private func headChangeEvent(
        _ message: ConversationMessage
    ) throws -> ConversationHeadRoutingChangeEvent? {
        guard let raw = message.metadata[
            ConversationRepository.headChangeEventMetadataKey
        ] else {
            return nil
        }
        return DatabaseHelpers.decodeJSON(
            ConversationHeadRoutingChangeEvent.self,
            from: raw
        )
    }

    private func functionSlice(
        _ name: String,
        in source: String
    ) throws -> String {
        let signature = try #require(
            source.range(
                of: #"\bfunc\s+\#(name)\s*\("#,
                options: .regularExpression
            )
        )
        let next = source.range(
            of: #"\n\s*(?:private\s+)?(?:@discardableResult\s+)?func\s+"#,
            options: .regularExpression,
            range: signature.upperBound..<source.endIndex
        )
        return String(source[
            signature.lowerBound..<(next?.lowerBound ?? source.endIndex)
        ])
    }

    private func sourceSlice(
        _ source: String,
        from startNeedle: String,
        through endNeedle: String
    ) throws -> String {
        let start = try #require(source.range(of: startNeedle))
        let end = try #require(
            source.range(
                of: endNeedle,
                range: start.upperBound..<source.endIndex
            )
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
        Date(timeIntervalSince1970: 1_808_000_000 + offset)
    }
}

private struct WriterFamilyFingerprint: Equatable {
    let room: ConversationRoom
    let turns: [ConversationTurn]
    let messages: [ConversationMessage]
    let bindings: [ConversationRuntimeBinding]
    let assignment: ConversationRoomAgentAssignment?
    let roster: ConversationRoomParticipantRoster?
    let routingAcceptanceHistory: ConversationRoutingAcceptanceHistory?

    var withoutLifecycle: WriterFamilyNonLifecycleFingerprint {
        WriterFamilyNonLifecycleFingerprint(
            roomID: room.id,
            stableKey: room.stableKey,
            title: room.title,
            kind: room.kind,
            nextTurnSequence: room.nextTurnSequence,
            nextMessageSequence: room.nextMessageSequence,
            metadata: room.metadata,
            createdAt: room.createdAt,
            turns: turns,
            messages: messages,
            bindings: bindings,
            assignment: assignment,
            roster: roster,
            routingAcceptanceHistory: routingAcceptanceHistory
        )
    }
}

private struct WriterFamilyNonLifecycleFingerprint: Equatable {
    let roomID: UUID
    let stableKey: String?
    let title: String
    let kind: String
    let nextTurnSequence: Int64
    let nextMessageSequence: Int64
    let metadata: [String: String]
    let createdAt: Date
    let turns: [ConversationTurn]
    let messages: [ConversationMessage]
    let bindings: [ConversationRuntimeBinding]
    let assignment: ConversationRoomAgentAssignment?
    let roster: ConversationRoomParticipantRoster?
    let routingAcceptanceHistory: ConversationRoutingAcceptanceHistory?
}
