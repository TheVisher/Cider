import Foundation
import Testing
@testable import Cider

@Suite("Agent Rooms Canonical Conversation Tests")
@MainActor
struct AgentRoomsCanonicalConversationTests {
    @Test("an arbitrary active canonical room can become the live conversation")
    func arbitraryCanonicalRoomActivation() async throws {
        try await withTemporaryConversationDatabase { database, repository in
            let room = try AgentRoomsActionService(repository: repository)
                .createConversation(title: "Daily conversation")
            let model = AgentRoomsLiveChatModel(
                transport: CanonicalConversationUnavailableTransport(),
                turnCoordinator: HermesTurnCoordinator(),
                persistence: AgentRoomsConversationPersistence(
                    database: database,
                    repository: repository
                )
            )

            let session = AgentRoomsSessionModel(liveChat: model)
            session.selectRoom(id: room.id.uuidString, persistIfCanonical: true)
            #expect(session.selectedRoomID == room.id.uuidString)
            #expect(model.activeRoom?.id == room.id.uuidString)
            #expect(model.activeRoom?.title == "Daily conversation")
            #expect(model.activeRoom?.continuity == .liveContinuation)

            _ = try AgentRoomsActionService(repository: repository)
                .renameConversation(id: room.id, title: "Renamed daily conversation")
            session.selectRoom(id: room.id.uuidString, persistIfCanonical: true)
            #expect(model.activeRoom?.id == room.id.uuidString)
            #expect(model.activeRoom?.title == "Renamed daily conversation")
        }
    }

    @Test("arbitrary room streams in order persists and continues after database reopen and runtime rotation")
    func sendStreamReopenAndRotateRuntime() async throws {
        let url = temporaryDatabaseURL()
        defer { removeDatabase(at: url) }

        let firstDatabase = CiderDatabase()
        try firstDatabase.open(at: url)
        let firstRepository = ConversationRepository(database: firstDatabase)
        let room = try AgentRoomsActionService(repository: firstRepository)
            .createConversation(title: "Daily conversation")
        let firstTransport = CanonicalConversationScriptTransport(scripts: [
            .success(runID: "run-one", sessionID: "session-one", chunks: ["First", " answer"]),
        ])
        let firstModel = makeModel(
            database: firstDatabase,
            repository: firstRepository,
            transport: firstTransport
        )
        #expect(firstModel.activateCanonicalRoom(id: room.id))
        await firstModel.refreshTransportReadiness()
        await firstModel.send("First question", selectedRoomID: room.id.uuidString)

        #expect(firstModel.activeRoom?.id == room.id.uuidString)
        #expect(firstModel.activeRoom?.transcript.messages.map(\.body) == ["First question", "First answer"])
        #expect(firstModel.activeRoom?.transcript.receipt?.runIdentity == "run-one")
        #expect(try firstRepository.turns(roomID: room.id).map(\.status) == [.completed])
        #expect(try firstRepository.messages(roomID: room.id).map(\.sequence) == [1, 2])
        #expect(try firstRepository.messages(roomID: room.id).last?.sourceCreatedAt == Date(timeIntervalSince1970: 1_805_000_000))
        #expect(try firstRepository.bindings(roomID: room.id).compactMap(\.externalSessionID) == ["session-one"])
        firstDatabase.close()

        let reopenedDatabase = CiderDatabase()
        try reopenedDatabase.open(at: url)
        defer { reopenedDatabase.close() }
        let reopenedRepository = ConversationRepository(database: reopenedDatabase)
        let rotatedTransport = CanonicalConversationScriptTransport(scripts: [
            .success(runID: "run-two", sessionID: "session-two", chunks: ["Second ", "answer"]),
        ])
        let reconstructed = makeModel(
            database: reopenedDatabase,
            repository: reopenedRepository,
            transport: rotatedTransport
        )
        #expect(reconstructed.activateCanonicalRoom(id: room.id))
        #expect(reconstructed.activeRoom?.transcript.messages.map(\.body) == ["First question", "First answer"])
        await reconstructed.refreshTransportReadiness()
        await reconstructed.send("Second question", selectedRoomID: room.id.uuidString)

        #expect(reconstructed.activeRoom?.id == room.id.uuidString)
        #expect(reconstructed.activeRoom?.transcript.messages.map(\.body) == [
            "First question", "First answer", "Second question", "Second answer",
        ])
        #expect(try reopenedRepository.turns(roomID: room.id).map(\.status) == [.completed, .completed])
        #expect(try reopenedRepository.messages(roomID: room.id).map(\.sequence) == [1, 2, 3, 4])
        #expect(try reopenedRepository.bindings(roomID: room.id).compactMap(\.externalSessionID) == [
            "session-one", "session-two",
        ])
        #expect(try reopenedRepository.room(id: room.id)?.id == room.id)
        #expect(await rotatedTransport.observedRoomIDs() == [room.id])
        #expect(await rotatedTransport.observedSessionIDs() == ["session-one"])
        #expect(await rotatedTransport.observedExistingMessageBodies() == [["First question", "First answer"]])
        #expect(await rotatedTransport.observedCursorTimestamps() == [Date(timeIntervalSince1970: 1_805_000_000)])
        #expect(try reopenedDatabase.integrityCheck().isHealthy)
    }

    @Test("each terminal turn keeps its exact bounded Cider source set across close reopen and runtime rotation")
    func sourceSetsStayWithTheirTerminalTurns() async throws {
        let url = temporaryDatabaseURL()
        defer { removeDatabase(at: url) }
        let noteID = UUID(uuidString: "81100000-0000-4000-8000-000000000001")!
        let bookmarkID = UUID(uuidString: "81100000-0000-4000-8000-000000000002")!
        let artifactID = UUID(uuidString: "81100000-0000-4000-8000-000000000003")!
        let task = HermesCiderReference(
            kind: "task", id: "826abc", title: "Source receipt checkpoint", boardID: "2afee0",
            projectID: nil, artifactType: nil, source: "cider",
            sourceRef: "kanban_card:2afee0/826abc"
        )
        let note = HermesCiderReference(
            kind: "note", id: noteID.uuidString, title: "Daily context", boardID: nil,
            projectID: nil, artifactType: nil, source: "cider",
            sourceRef: "note:\(noteID.uuidString)"
        )
        let bookmark = HermesCiderReference(
            kind: "bookmark", id: bookmarkID.uuidString, title: "Saved source", boardID: nil,
            projectID: nil, artifactType: nil, source: "cider",
            sourceRef: "bookmark:\(bookmarkID.uuidString)"
        )
        let artifact = HermesCiderReference(
            kind: "project_artifact", id: artifactID.uuidString, title: "Receipt plan", boardID: nil,
            projectID: "cider", artifactType: "plan", source: "cider",
            sourceRef: "note:\(artifactID.uuidString)"
        )
        let firstReferences = [task, note, task]
        let secondReferences = [artifact, bookmark]

        let firstDatabase = CiderDatabase()
        try firstDatabase.open(at: url)
        let firstRepository = ConversationRepository(database: firstDatabase)
        let room = try AgentRoomsActionService(repository: firstRepository)
            .createConversation(title: "Source-backed room")
        let firstModel = makeModel(
            database: firstDatabase,
            repository: firstRepository,
            transport: CanonicalConversationScriptTransport(scripts: [
                .successWithReferences(
                    runID: "run-source-one",
                    sessionID: "session-source-one",
                    chunks: ["First answer"],
                    references: firstReferences
                ),
            ])
        )
        #expect(firstModel.activateCanonicalRoom(id: room.id))
        await firstModel.refreshTransportReadiness()
        await firstModel.send("First source turn", selectedRoomID: room.id.uuidString)
        #expect(firstModel.activeRoom?.transcript.receipt?.objectReceipts.map(\.openRoute) == [
            .note(noteID: noteID),
            .card(boardID: "2afee0", cardID: "826abc"),
        ])
        #expect(try decodeReferences(try #require(
            firstRepository.turns(roomID: room.id).first?.metadata["cider_references_json"]
        )) == firstReferences)
        firstDatabase.close()

        let secondDatabase = CiderDatabase()
        try secondDatabase.open(at: url)
        let secondRepository = ConversationRepository(database: secondDatabase)
        let secondModel = makeModel(
            database: secondDatabase,
            repository: secondRepository,
            transport: CanonicalConversationScriptTransport(scripts: [
                .successWithReferences(
                    runID: "run-source-two",
                    sessionID: "session-source-two",
                    chunks: ["Second answer"],
                    references: secondReferences
                ),
            ])
        )
        #expect(secondModel.activateCanonicalRoom(id: room.id))
        #expect(secondModel.activeRoom?.transcript.receipt?.objectReceipts.map(\.openRoute) == [
            .note(noteID: noteID),
            .card(boardID: "2afee0", cardID: "826abc"),
        ])
        await secondModel.refreshTransportReadiness()
        await secondModel.send("Second source turn", selectedRoomID: room.id.uuidString)
        #expect(secondModel.activeRoom?.transcript.receipt?.objectReceipts.map(\.openRoute) == [
            .bookmark(bookmarkID: bookmarkID),
            .note(noteID: artifactID),
        ])
        let durableTurns = try secondRepository.turns(roomID: room.id)
        #expect(durableTurns.count == 2)
        #expect(try decodeReferences(try #require(
            durableTurns[0].metadata["cider_references_json"]
        )) == firstReferences)
        #expect(try decodeReferences(try #require(
            durableTurns[1].metadata["cider_references_json"]
        )) == secondReferences)
        secondDatabase.close()

        let finalDatabase = CiderDatabase()
        try finalDatabase.open(at: url)
        defer { finalDatabase.close() }
        let finalRepository = ConversationRepository(database: finalDatabase)
        let finalModel = makeModel(
            database: finalDatabase,
            repository: finalRepository,
            transport: CanonicalConversationUnavailableTransport()
        )
        #expect(finalModel.activateCanonicalRoom(id: room.id))
        #expect(finalModel.activeRoom?.id == room.id.uuidString)
        #expect(finalModel.activeRoom?.transcript.receipt?.objectReceipts.map(\.openRoute) == [
            .bookmark(bookmarkID: bookmarkID),
            .note(noteID: artifactID),
        ])
        #expect(try finalRepository.bindings(roomID: room.id).compactMap(\.externalSessionID) == [
            "session-source-one", "session-source-two",
        ])
        #expect(try finalDatabase.integrityCheck().isHealthy)
    }

    @Test("context checkpoint and approval truth stay on the exact turn across reopen and runtime rotation")
    func contextAndApprovalStayWithExactTurn() async throws {
        let url = temporaryDatabaseURL()
        defer { removeDatabase(at: url) }
        let noteID = UUID(uuidString: "81200000-0000-4000-8000-000000000001")!
        let bookmarkID = UUID(uuidString: "81200000-0000-4000-8000-000000000002")!
        let note = HermesCiderReference(
            kind: "note", id: noteID.uuidString, title: "Trip plan", boardID: nil,
            projectID: nil, artifactType: nil, source: "cider", sourceRef: "note:\(noteID.uuidString)"
        )
        let bookmark = HermesCiderReference(
            kind: "bookmark", id: bookmarkID.uuidString, title: "Travel source", boardID: nil,
            projectID: nil, artifactType: nil, source: "cider", sourceRef: "bookmark:\(bookmarkID.uuidString)"
        )
        let firstCheckpoint = HermesCiderContextCheckpoint(
            id: "checkpoint-first", selected: [note, bookmark], citations: [bookmark],
            omissionReason: nil, source: "cider", sourceRef: "context_checkpoint:checkpoint-first"
        )
        let firstApproval = HermesApprovalRequest(
            id: "approval-first", action: "Update note", target: note, risk: "medium",
            scope: "write", status: "requested", source: "hermes_runs_api",
            sourceRef: "approval:approval-first"
        )
        let secondCheckpoint = HermesCiderContextCheckpoint(
            id: "checkpoint-second", selected: [], citations: [], omissionReason: "policy_filtered",
            source: "cider", sourceRef: "context_checkpoint:checkpoint-second"
        )

        let firstDatabase = CiderDatabase()
        try firstDatabase.open(at: url)
        let firstRepository = ConversationRepository(database: firstDatabase)
        let room = try AgentRoomsActionService(repository: firstRepository)
            .createConversation(title: "Context-backed room")
        let firstModel = makeModel(
            database: firstDatabase,
            repository: firstRepository,
            transport: CanonicalConversationScriptTransport(scripts: [
                .successWithFacts(
                    runID: "run-context-one", sessionID: "session-context-one", chunks: ["First answer"],
                    context: firstCheckpoint, approvals: [firstApproval]
                ),
            ])
        )
        #expect(firstModel.activateCanonicalRoom(id: room.id))
        await firstModel.refreshTransportReadiness()
        await firstModel.send("First context turn", selectedRoomID: room.id.uuidString)
        let firstReceipt = try #require(firstModel.activeRoom?.transcript.receipt)
        #expect(firstReceipt.contextCheckpoint?.selectedContext.map(\.openRoute) == [
            .bookmark(bookmarkID: bookmarkID), .note(noteID: noteID),
        ])
        #expect(firstReceipt.contextCheckpoint?.citations.map(\.openRoute) == [.bookmark(bookmarkID: bookmarkID)])
        #expect(firstReceipt.approvalCheckpoint?.requests.first?.status == .requested)
        #expect(firstReceipt.approvalCheckpoint?.requests.first?.target == "Trip plan · Note")
        firstDatabase.close()

        let secondDatabase = CiderDatabase()
        try secondDatabase.open(at: url)
        let secondRepository = ConversationRepository(database: secondDatabase)
        let secondModel = makeModel(
            database: secondDatabase,
            repository: secondRepository,
            transport: CanonicalConversationScriptTransport(scripts: [
                .successWithFacts(
                    runID: "run-context-two", sessionID: "session-context-two", chunks: ["Second answer"],
                    context: secondCheckpoint, approvals: []
                ),
            ])
        )
        #expect(secondModel.activateCanonicalRoom(id: room.id))
        #expect(secondModel.activeRoom?.transcript.receipt?.contextCheckpoint?.selectedContext.count == 2)
        #expect(secondModel.activeRoom?.transcript.receipt?.approvalCheckpoint?.requests.first?.id == "approval-first")
        await secondModel.refreshTransportReadiness()
        await secondModel.send("Second context turn", selectedRoomID: room.id.uuidString)
        #expect(secondModel.activeRoom?.transcript.receipt?.contextCheckpoint?.state == .omitted)
        #expect(secondModel.activeRoom?.transcript.receipt?.contextCheckpoint?.detail ==
            "Cider withheld context that did not pass the sharing boundary.")
        #expect(secondModel.activeRoom?.transcript.receipt?.approvalCheckpoint == nil)

        let turns = try secondRepository.turns(roomID: room.id)
        #expect(turns.count == 2)
        #expect(turns[0].metadata["context_checkpoint_fact_state"] == "validated")
        #expect(turns[0].metadata["approval_fact_state"] == "validated")
        #expect(turns[1].metadata["context_checkpoint_fact_state"] == "validated")
        #expect(turns[1].metadata["approval_fact_state"] == "notReported")
        #expect(try decodeContext(try #require(turns[0].metadata["context_checkpoint_json"])) == firstCheckpoint)
        #expect(try decodeApprovals(try #require(turns[0].metadata["approval_requests_json"])) == [firstApproval])
        #expect(try decodeContext(try #require(turns[1].metadata["context_checkpoint_json"])) == secondCheckpoint)
        secondDatabase.close()

        let finalDatabase = CiderDatabase()
        try finalDatabase.open(at: url)
        defer { finalDatabase.close() }
        let finalRepository = ConversationRepository(database: finalDatabase)
        let finalModel = makeModel(
            database: finalDatabase,
            repository: finalRepository,
            transport: CanonicalConversationUnavailableTransport()
        )
        #expect(finalModel.activateCanonicalRoom(id: room.id))
        #expect(finalModel.activeRoom?.transcript.receipt?.contextCheckpoint?.state == .omitted)
        #expect(finalModel.activeRoom?.transcript.receipt?.approvalCheckpoint == nil)
        #expect(try finalRepository.bindings(roomID: room.id).compactMap(\.externalSessionID) == [
            "session-context-one", "session-context-two",
        ])
        #expect(try finalDatabase.integrityCheck().isHealthy)
    }

    @Test("private-shaped structured facts persist only a fail-closed state")
    func privateStructuredFactsPersistOnlyRejectedState() async throws {
        try await withTemporaryConversationDatabase { database, repository in
            let room = try AgentRoomsActionService(repository: repository)
                .createConversation(title: "Fail-closed context room")
            let noteID = UUID(uuidString: "81300000-0000-4000-8000-000000000001")!
            let privateTarget = HermesCiderReference(
                kind: "note", id: noteID.uuidString, title: "/Users/private/.env",
                boardID: nil, projectID: nil, artifactType: nil, source: "cider",
                sourceRef: "note:\(noteID.uuidString)"
            )
            let context = HermesCiderContextCheckpoint(
                id: "checkpoint-private", selected: [privateTarget], citations: [], omissionReason: nil,
                source: "cider", sourceRef: "context_checkpoint:checkpoint-private"
            )
            let approval = HermesApprovalRequest(
                id: "approval-private", action: "Update note", target: privateTarget,
                risk: "high", scope: "write", status: "requested", source: "hermes_runs_api",
                sourceRef: "approval:approval-private"
            )
            let model = makeModel(
                database: database,
                repository: repository,
                transport: CanonicalConversationScriptTransport(scripts: [
                    .successWithFacts(
                        runID: "run-private", sessionID: "session-private", chunks: ["Safe answer"],
                        context: context, approvals: [approval]
                    ),
                ])
            )

            #expect(model.activateCanonicalRoom(id: room.id))
            await model.refreshTransportReadiness()
            await model.send("Private-shaped facts", selectedRoomID: room.id.uuidString)

            let receipt = try #require(model.activeRoom?.transcript.receipt)
            #expect(receipt.contextCheckpoint?.state == .rejected)
            #expect(receipt.contextCheckpoint?.detail == "Cider withheld unsupported or malformed context details.")
            #expect(receipt.approvalCheckpoint?.state == .rejected)
            #expect(receipt.approvalCheckpoint?.requests.isEmpty == true)
            #expect(!String(describing: receipt.contextCheckpoint).contains("/Users/private"))
            #expect(!String(describing: receipt.approvalCheckpoint).contains("/Users/private"))

            let metadata = try #require(repository.turns(roomID: room.id).first?.metadata)
            #expect(metadata["context_checkpoint_fact_state"] == "rejected")
            #expect(metadata["approval_fact_state"] == "rejected")
            #expect(metadata["context_checkpoint_json"] == nil)
            #expect(metadata["approval_requests_json"] == nil)
        }
    }

    @Test("accepted cancellation persists one user and partial truth and rejects late completion")
    func cancellationPersistsPartialAndDropsLateOutput() async throws {
        try await withTemporaryConversationDatabase { database, repository in
            let room = try AgentRoomsActionService(repository: repository)
                .createConversation(title: "Cancellation room")
            let transport = CanonicalConversationGateTransport(
                runID: "run-cancel",
                sessionID: "session-cancel",
                finalAnswer: "Late terminal output"
            )
            let model = makeModel(database: database, repository: repository, transport: transport)
            #expect(model.activateCanonicalRoom(id: room.id))
            await model.refreshTransportReadiness()

            let send = Task { await model.send("Stop this", selectedRoomID: room.id.uuidString) }
            await transport.waitUntilStarted()
            await transport.emit(.messageDelta("Accepted partial"))
            await model.cancelActiveSend()
            await transport.release()
            await send.value

            let turns = try repository.turns(roomID: room.id)
            let messages = try repository.messages(roomID: room.id)
            #expect(turns.map(\.status) == [.cancelled])
            #expect(messages.map(\.role) == ["user", "assistant"])
            #expect(messages.map(\.contentText) == ["Stop this", "Accepted partial"])
            #expect(messages[1].status == .incomplete)
            #expect(messages[1].finishReason == .cancelled)
            #expect(!messages.contains(where: { $0.contentText == "Late terminal output" }))
            #expect(await transport.stoppedRunIDs() == ["run-cancel"])

            let reconstructed = makeModel(
                database: database,
                repository: repository,
                transport: CanonicalConversationUnavailableTransport()
            )
            #expect(reconstructed.activateCanonicalRoom(id: room.id))
            #expect(reconstructed.activeRoom?.transcript.messages.map(\.body) == ["Stop this", "Accepted partial"])
            #expect(reconstructed.activeRoom?.transcript.messages.first?.canRetry == false)
            #expect(reconstructed.activeRoom?.transcript.receipt?.status == .cancelled)
            #expect(reconstructed.activeRoom?.transcript.receipt?.runIdentity == "run-cancel")
        }
    }

    @Test("streaming and terminal reconciliation retain the durable Cider assistant identity")
    func streamingRetainsDurableAssistantIdentity() async throws {
        try await withTemporaryConversationDatabase { database, repository in
            let room = try AgentRoomsActionService(repository: repository)
                .createConversation(title: "Stable identity room")
            let transport = CanonicalConversationGateTransport(
                runID: "run-stable-id",
                sessionID: "session-stable-id",
                finalAnswer: "Stable terminal answer"
            )
            let model = makeModel(database: database, repository: repository, transport: transport)
            #expect(model.activateCanonicalRoom(id: room.id))
            await model.refreshTransportReadiness()

            let send = Task { await model.send("Keep identity", selectedRoomID: room.id.uuidString) }
            await transport.waitUntilStarted()
            await transport.emit(.messageDelta("Stable"))
            let streamingID = try #require(model.activeRoom?.transcript.messages.last?.id)
            await transport.release()
            await send.value

            let terminalID = try #require(model.activeRoom?.transcript.messages.last?.id)
            let durableAssistantID = try #require(
                repository.messages(roomID: room.id).last(where: { $0.role == "assistant" })?.id.uuidString
            )
            #expect(streamingID == terminalID)
            #expect(terminalID == durableAssistantID)

            let reconstructed = makeModel(
                database: database,
                repository: repository,
                transport: CanonicalConversationUnavailableTransport()
            )
            #expect(reconstructed.activateCanonicalRoom(id: room.id))
            #expect(reconstructed.activeRoom?.transcript.messages.last?.id == durableAssistantID)
        }
    }

    @Test("pre-accept failure retry reuses one accepted user identity")
    func retryDoesNotDuplicateAcceptedUser() async throws {
        try await withTemporaryConversationDatabase { database, repository in
            let room = try AgentRoomsActionService(repository: repository)
                .createConversation(title: "Retry room")
            let transport = CanonicalConversationScriptTransport(scripts: [
                .preAcceptFailure,
                .success(runID: "run-retry", sessionID: "session-retry", chunks: ["Recovered"]),
            ])
            let model = makeModel(database: database, repository: repository, transport: transport)
            #expect(model.activateCanonicalRoom(id: room.id))
            await model.refreshTransportReadiness()
            await model.send("Retry this", selectedRoomID: room.id.uuidString)

            let clientID = try #require(model.activeRoom?.transcript.messages.first?.id)
            #expect(model.activeRoom?.transcript.messages.first?.canRetry == true)
            await model.retry(clientMessageID: clientID, selectedRoomID: room.id.uuidString)

            let turns = try repository.turns(roomID: room.id)
            let messages = try repository.messages(roomID: room.id)
            #expect(turns.map(\.status) == [.failed, .completed])
            #expect(messages.filter { $0.role == "user" }.count == 1)
            #expect(messages.filter { $0.role == "assistant" }.count == 1)
            #expect(messages.map(\.contentText) == ["Retry this", "Recovered"])
            #expect(model.activeRoom?.transcript.messages.map(\.body) == ["Retry this", "Recovered"])
            #expect(await transport.sentTexts() == ["Retry this", "Retry this"])

            let reconstructed = makeModel(
                database: database,
                repository: repository,
                transport: CanonicalConversationUnavailableTransport()
            )
            #expect(reconstructed.activateCanonicalRoom(id: room.id))
            #expect(reconstructed.activeRoom?.transcript.messages.map(\.body) == ["Retry this", "Recovered"])
            #expect(reconstructed.activeRoom?.transcript.messages.first?.deliveryState == .sent)
            #expect(reconstructed.activeRoom?.transcript.receipt?.runIdentity == "run-retry")
        }
    }

    @Test("reopen durably terminates a stale pre-accept turn and offers honest retry")
    func stalePreAcceptRecovery() async throws {
        try await withTemporaryConversationDatabase { database, repository in
            let room = try AgentRoomsActionService(repository: repository)
                .createConversation(title: "Pre-accept recovery")
            let persistence = AgentRoomsConversationPersistence(database: database, repository: repository)
            _ = try persistence.beginAttempt(
                roomID: room.id,
                roomTitle: room.title,
                isReservedTestChat: false,
                attemptID: UUID(),
                clientMessageID: "cider-room-client:pre-accept",
                userMessageID: UUID(),
                assistantMessageID: UUID(),
                text: "Was this sent?",
                at: Date(timeIntervalSince1970: 1_805_100_000)
            )

            let reconstructed = makeModel(
                database: database,
                repository: repository,
                transport: CanonicalConversationUnavailableTransport()
            )
            #expect(reconstructed.activateCanonicalRoom(id: room.id))

            let turn = try #require(repository.turns(roomID: room.id).last)
            let message = try #require(reconstructed.activeRoom?.transcript.messages.last)
            #expect(turn.status == .failed)
            #expect(turn.error?.code == "pre_accept_interruption")
            #expect(message.deliveryState == .failed)
            #expect(message.canRetry)
            #expect(reconstructed.activeRoom?.transcript.receipt?.title == "Message interrupted before acceptance")
            #expect(reconstructed.activeRoom?.transcript.receipt?.detail == "Not accepted by Hermes · Safe to retry")
        }
    }

    @Test("reopen durably terminates an accepted stale turn without unsafe retry")
    func staleAcceptedRecovery() async throws {
        try await withTemporaryConversationDatabase { database, repository in
            let room = try AgentRoomsActionService(repository: repository)
                .createConversation(title: "Accepted recovery")
            let persistence = AgentRoomsConversationPersistence(database: database, repository: repository)
            let attempt = try persistence.beginAttempt(
                roomID: room.id,
                roomTitle: room.title,
                isReservedTestChat: false,
                attemptID: UUID(),
                clientMessageID: "cider-room-client:accepted",
                userMessageID: UUID(),
                assistantMessageID: UUID(),
                text: "Continue carefully",
                at: Date(timeIntervalSince1970: 1_805_100_100)
            )
            try persistence.markRunStarted(
                attempt,
                runID: "run-stale-accepted",
                activity: [],
                at: Date(timeIntervalSince1970: 1_805_100_101)
            )

            let reconstructed = makeModel(
                database: database,
                repository: repository,
                transport: CanonicalConversationUnavailableTransport()
            )
            #expect(reconstructed.activateCanonicalRoom(id: room.id))

            let turn = try #require(repository.turns(roomID: room.id).last)
            let message = try #require(reconstructed.activeRoom?.transcript.messages.last)
            #expect(turn.status == .failed)
            #expect(turn.error?.code == "accepted_interruption")
            #expect(message.deliveryState == .failed)
            #expect(!message.canRetry)
            #expect(reconstructed.activeRoom?.transcript.receipt?.title == "Hermes response interrupted")
            #expect(reconstructed.activeRoom?.transcript.receipt?.detail == "Accepted by Hermes · Cannot retry safely")
            #expect(reconstructed.activeRoom?.transcript.receipt?.runIdentity == "run-stale-accepted")
        }
    }

    @Test("legacy and archived rooms remain fail-closed and byte-logically unchanged")
    func blockedRoomOwnershipIsNotActivated() async throws {
        try await withTemporaryConversationDatabase { database, repository in
            let legacy = try repository.createRoom(.init(
                stableKey: "legacy.private.room",
                title: "Private legacy room",
                metadata: ["authority": "legacy-authoritative"]
            ))
            let archived = try AgentRoomsActionService(repository: repository)
                .createConversation(title: "Archived native room")
            try repository.setLifecycle(roomID: archived.id, state: .archived, at: Date())
            let legacyBefore = try repository.room(id: legacy.id)
            let archivedBefore = try repository.room(id: archived.id)
            let model = makeModel(
                database: database,
                repository: repository,
                transport: CanonicalConversationUnavailableTransport()
            )

            #expect(!model.activateCanonicalRoom(id: legacy.id))
            #expect(!model.activateCanonicalRoom(id: archived.id))
            #expect(model.activeRoom == nil)
            #expect(try repository.room(id: legacy.id) == legacyBefore)
            #expect(try repository.room(id: archived.id) == archivedBefore)
            #expect(try repository.turns(roomID: legacy.id).isEmpty)
            #expect(try repository.messages(roomID: legacy.id).isEmpty)
            #expect(try database.integrityCheck().isHealthy)
        }
    }

    @Test("conflicting accepted run events cannot attach terminal output")
    func conflictingRunDoesNotPersistTerminalOutput() async throws {
        try await withTemporaryConversationDatabase { database, repository in
            let room = try AgentRoomsActionService(repository: repository)
                .createConversation(title: "Integrity room")
            let transport = CanonicalConversationScriptTransport(scripts: [
                .conflictingCompletion(
                    runID: "run-authoritative",
                    conflictingRunID: "run-conflict",
                    sessionID: "session-integrity",
                    answer: "Must not persist"
                ),
            ])
            let model = makeModel(database: database, repository: repository, transport: transport)
            #expect(model.activateCanonicalRoom(id: room.id))
            await model.refreshTransportReadiness()
            await model.send("Check integrity", selectedRoomID: room.id.uuidString)

            #expect(try repository.turns(roomID: room.id).map(\.status) == [.failed])
            #expect(try repository.messages(roomID: room.id).map(\.contentText) == ["Check integrity"])
            #expect(model.activeRoom?.transcript.messages.map(\.body) == ["Check integrity"])
            #expect(model.activeRoom?.transcript.receipt?.status == .failed)
            #expect(model.activeRoom?.transcript.receipt?.runIdentity == "run-authoritative")
        }
    }

    @Test("shared canonical restore rejects malformed durable message state")
    func malformedCanonicalHistoryFailsClosed() async throws {
        try await withTemporaryConversationDatabase { database, repository in
            let room = try AgentRoomsActionService(repository: repository)
                .createConversation(title: "Corruption check")
            let writer = makeModel(
                database: database,
                repository: repository,
                transport: CanonicalConversationScriptTransport(scripts: [
                    .success(runID: "run-corrupt", sessionID: "session-corrupt", chunks: ["Before corruption"]),
                ])
            )
            #expect(writer.activateCanonicalRoom(id: room.id))
            await writer.refreshTransportReadiness()
            await writer.send("Persist safely", selectedRoomID: room.id.uuidString)
            try database.runSQL("UPDATE conversation_messages SET status = 'streaming' WHERE role = 'assistant';")

            let reader = makeModel(
                database: database,
                repository: repository,
                transport: CanonicalConversationUnavailableTransport()
            )
            #expect(!reader.activateCanonicalRoom(id: room.id))
            #expect(reader.activeRoom == nil)
            #expect(try database.integrityCheck().isHealthy)
        }
    }

    private func makeModel(
        database: CiderDatabase,
        repository: ConversationRepository,
        transport: some HermesBridgeTransport
    ) -> AgentRoomsLiveChatModel {
        AgentRoomsLiveChatModel(
            transport: transport,
            turnCoordinator: HermesTurnCoordinator(),
            savedBookmarkMatches: { _ in [] },
            persistence: AgentRoomsConversationPersistence(database: database, repository: repository)
        )
    }

    private func withTemporaryConversationDatabase<T>(
        _ body: (CiderDatabase, ConversationRepository) async throws -> T
    ) async throws -> T {
        let url = temporaryDatabaseURL()
        let database = CiderDatabase()
        try database.open(at: url)
        defer {
            database.close()
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(atPath: url.path + "-wal")
            try? FileManager.default.removeItem(atPath: url.path + "-shm")
        }
        return try await body(database, ConversationRepository(database: database))
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-canonical-conversation-\(UUID().uuidString).db")
    }

    private func removeDatabase(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
    }

    private func decodeReferences(_ raw: String) throws -> [HermesCiderReference] {
        try JSONDecoder().decode([HermesCiderReference].self, from: Data(raw.utf8))
    }
}

private actor CanonicalConversationUnavailableTransport: HermesBridgeTransport {
    func availability() async -> HermesBridgeAvailability { .unavailable("test") }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        throw CancellationError()
    }

    func stop(runID: String) async throws {}
}

private enum CanonicalConversationScript: Sendable {
    case preAcceptFailure
    case success(runID: String, sessionID: String, chunks: [String])
    case successWithReferences(
        runID: String,
        sessionID: String,
        chunks: [String],
        references: [HermesCiderReference]
    )
    case successWithFacts(
        runID: String,
        sessionID: String,
        chunks: [String],
        context: HermesCiderContextCheckpoint,
        approvals: [HermesApprovalRequest]
    )
    case conflictingCompletion(runID: String, conflictingRunID: String, sessionID: String, answer: String)
}

private enum CanonicalConversationTransportError: Error, Sendable {
    case disconnected
}

private actor CanonicalConversationScriptTransport: HermesBridgeTransport {
    private var scripts: [CanonicalConversationScript]
    private var roomIDs: [UUID] = []
    private var sessionIDs: [String] = []
    private var existingMessageBodies: [[String]] = []
    private var cursorTimestamps: [Date?] = []
    private var texts: [String] = []

    init(scripts: [CanonicalConversationScript]) { self.scripts = scripts }

    func availability() async -> HermesBridgeAvailability { .apiRuns }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        roomIDs.append(state.conversationID)
        sessionIDs.append(state.activeRuntimeSessionID)
        existingMessageBodies.append(existingMessages.map(\.content))
        cursorTimestamps.append(state.lastSyncedTimestamp)
        texts.append(text)
        guard !scripts.isEmpty else { throw CanonicalConversationTransportError.disconnected }
        switch scripts.removeFirst() {
        case .preAcceptFailure:
            throw CanonicalConversationTransportError.disconnected
        case .success(let runID, let sessionID, let chunks):
            await onEvent?(.runStarted(runID))
            for chunk in chunks { await onEvent?(.messageDelta(chunk)) }
            let answer = chunks.joined()
            await onEvent?(.completed(output: answer))
            return .init(completion: canonicalCompletion(
                state: state,
                existingMessages: existingMessages,
                text: text,
                answer: answer,
                runID: runID,
                sessionID: sessionID
            ))
        case .successWithReferences(let runID, let sessionID, let chunks, let references):
            await onEvent?(.runStarted(runID))
            for chunk in chunks { await onEvent?(.messageDelta(chunk)) }
            let answer = chunks.joined()
            await onEvent?(.completed(output: answer))
            return .init(completion: canonicalCompletion(
                state: state,
                existingMessages: existingMessages,
                text: text,
                answer: answer,
                runID: runID,
                sessionID: sessionID,
                references: references
            ))
        case .successWithFacts(let runID, let sessionID, let chunks, let context, let approvals):
            await onEvent?(.runStarted(runID))
            for chunk in chunks { await onEvent?(.messageDelta(chunk)) }
            let answer = chunks.joined()
            await onEvent?(.completed(output: answer))
            return .init(completion: canonicalCompletion(
                state: state,
                existingMessages: existingMessages,
                text: text,
                answer: answer,
                runID: runID,
                sessionID: sessionID,
                context: context,
                approvals: approvals
            ))
        case .conflictingCompletion(let runID, let conflictingRunID, let sessionID, let answer):
            await onEvent?(.runStarted(runID))
            await onEvent?(.runStarted(conflictingRunID))
            return .init(completion: canonicalCompletion(
                state: state,
                existingMessages: existingMessages,
                text: text,
                answer: answer,
                runID: runID,
                sessionID: sessionID
            ))
        }
    }

    func stop(runID: String) async throws {}
    func observedRoomIDs() -> [UUID] { roomIDs }
    func observedSessionIDs() -> [String] { sessionIDs }
    func observedExistingMessageBodies() -> [[String]] { existingMessageBodies }
    func observedCursorTimestamps() -> [Date?] { cursorTimestamps }
    func sentTexts() -> [String] { texts }
}

private actor CanonicalConversationGateTransport: HermesBridgeTransport {
    let runID: String
    let sessionID: String
    let finalAnswer: String
    private var state: HermesConversationState?
    private var existingMessages: [AIAssistantMessage] = []
    private var text = ""
    private var handler: (@Sendable (HermesRunEvent) async -> Void)?
    private var started = false
    private var released = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var stopped: [String] = []

    init(runID: String, sessionID: String, finalAnswer: String) {
        self.runID = runID
        self.sessionID = sessionID
        self.finalAnswer = finalAnswer
    }

    func availability() async -> HermesBridgeAvailability { .apiRuns }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        self.state = state
        self.existingMessages = existingMessages
        self.text = text
        handler = onEvent
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await onEvent?(.runStarted(runID))
        if !released { await withCheckedContinuation { releaseWaiters.append($0) } }
        return .init(completion: canonicalCompletion(
            state: state,
            existingMessages: existingMessages,
            text: text,
            answer: finalAnswer,
            runID: runID,
            sessionID: sessionID
        ))
    }

    func stop(runID: String) async throws { stopped.append(runID) }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func emit(_ event: HermesRunEvent) async { await handler?(event) }

    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }

    func stoppedRunIDs() -> [String] { stopped }
}

private func canonicalCompletion(
    state: HermesConversationState,
    existingMessages: [AIAssistantMessage],
    text: String,
    answer: String,
    runID: String,
    sessionID: String,
    references: [HermesCiderReference] = [],
    context: HermesCiderContextCheckpoint? = nil,
    approvals: [HermesApprovalRequest] = []
) -> HermesRunCompletionEnvelope {
    let timestamp = Date(timeIntervalSince1970: 1_805_000_000 + Double(existingMessages.count))
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
    var nextState = state
    nextState.activeRuntimeSessionID = sessionID
    if !nextState.runtimeSessionLineage.contains(sessionID) {
        nextState.runtimeSessionLineage.append(sessionID)
    }
    nextState.lastSyncedAt = timestamp
    nextState.lastSyncedMessageID = assistantSourceID
    nextState.lastSyncedTimestamp = timestamp
    nextState.lastImportedRuntimeSessionID = sessionID
    return .init(
        provenance: .hermesRunsAPI,
        runID: runID,
        terminalStatus: .completed,
        observedFacts: .none,
        finalSessionSynchronizationComplete: true,
        finalMessages: existingMessages + [user, assistant],
        finalState: nextState,
        modelIdentity: "fake-hermes",
        terminalSourceEvidence: .init(
            reportedTerminalRunID: runID,
            userSourceID: userSourceID,
            assistantSourceID: assistantSourceID,
            userSourceSessionID: sessionID,
            assistantSourceSessionID: sessionID
        ),
        ciderReferences: references,
        contextCheckpointFactState: context == nil ? .notReported : .validated,
        contextCheckpoint: context,
        approvalFactState: approvals.isEmpty ? .notReported : .validated,
        approvalRequests: approvals
    )
}

private func decodeContext(_ raw: String) throws -> HermesCiderContextCheckpoint {
    try JSONDecoder().decode(HermesCiderContextCheckpoint.self, from: Data(raw.utf8))
}

private func decodeApprovals(_ raw: String) throws -> [HermesApprovalRequest] {
    try JSONDecoder().decode([HermesApprovalRequest].self, from: Data(raw.utf8))
}
