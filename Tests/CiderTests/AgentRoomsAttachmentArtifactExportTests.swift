import Foundation
import Testing
@testable import Cider

@Suite("Agent Rooms Attachment Artifact Export Tests")
@MainActor
struct AgentRoomsAttachmentArtifactExportTests {
    private let attachmentID = UUID(uuidString: "A8260000-0000-4000-8000-000000000001")!
    private let attachmentFileID = UUID(uuidString: "A8260000-0000-4000-8000-000000000002")!
    private let artifactID = UUID(uuidString: "A8260000-0000-4000-8000-000000000003")!
    private let artifactNoteID = UUID(uuidString: "A8260000-0000-4000-8000-000000000004")!

    @Test("bounded attachment and generated artifact facts project safe native routes or honest unavailable rows")
    func boundedNativeProjection() throws {
        let attachment = makeAttachment()
        let artifact = makeArtifact()

        let projectedAttachment = AgentRoomsAssetProjector.attachments(
            factState: .validated,
            facts: [attachment],
            canonicalOpenRoute: { target in
                target.id == self.attachmentFileID.uuidString
                    ? .vaultFile(fileID: self.attachmentFileID)
                    : nil
            }
        )
        let attachmentCollection = try #require(projectedAttachment)
        #expect(attachmentCollection.state == .available)
        #expect(attachmentCollection.rows.count == 1)
        #expect(attachmentCollection.rows[0].title == "roadmap.pdf")
        #expect(attachmentCollection.rows[0].contentType == "application/pdf")
        #expect(attachmentCollection.rows[0].sizeLabel == "24 KB")
        #expect(attachmentCollection.rows[0].provenance == "User attachment · Cider-owned")
        #expect(attachmentCollection.rows[0].openRoute == .vaultFile(fileID: attachmentFileID))

        let projectedArtifact = AgentRoomsAssetProjector.generatedArtifacts(
            factState: .validated,
            facts: [artifact],
            canonicalOpenRoute: { _ in nil }
        )
        let artifactCollection = try #require(projectedArtifact)
        #expect(artifactCollection.state == .available)
        #expect(artifactCollection.rows.count == 1)
        #expect(artifactCollection.rows[0].title == "Export plan.md")
        #expect(artifactCollection.rows[0].openRoute == nil)
        #expect(artifactCollection.rows[0].availability == "Open unavailable")
        #expect(!String(describing: artifactCollection).contains("/Users/"))
        #expect(!String(describing: artifactCollection).contains("file://"))
    }

    @Test("private conflicting unbounded and raw transport-shaped facts fail closed without partial projection")
    func unsafeFactsFailClosed() throws {
        let safe = makeAttachment()
        let conflicting = HermesCiderAttachment(
            id: safe.id,
            target: safe.target,
            displayName: "different.pdf",
            contentType: safe.contentType,
            byteSize: safe.byteSize,
            provenance: safe.provenance,
            source: safe.source,
            sourceRef: safe.sourceRef
        )
        let privateID = UUID()
        let privateFact = HermesCiderAttachment(
            id: privateID.uuidString,
            target: safe.target,
            displayName: "/Users/private/.env",
            contentType: "text/plain",
            byteSize: 42,
            provenance: "user_attachment",
            source: "cider",
            sourceRef: "attachment:\(privateID.uuidString)"
        )

        let projectedConflict = AgentRoomsAssetProjector.attachments(
            factState: .validated,
            facts: [safe, conflicting],
            canonicalOpenRoute: { _ in .vaultFile(fileID: self.attachmentFileID) }
        )
        let conflictingProjection = try #require(projectedConflict)
        #expect(conflictingProjection.state == .rejected)
        #expect(conflictingProjection.rows.isEmpty)

        let projectedPrivate = AgentRoomsAssetProjector.attachments(
            factState: .validated,
            facts: [privateFact],
            canonicalOpenRoute: { _ in .vaultFile(fileID: self.attachmentFileID) }
        )
        let privateProjection = try #require(projectedPrivate)
        #expect(privateProjection.state == .rejected)
        #expect(privateProjection.rows.isEmpty)
        #expect(!String(describing: privateProjection).contains("/Users/private"))

        let overBound = Array(repeating: safe, count: AgentRoomsAssetProjector.maximumFactCount + 1)
        let projectedOverBound = AgentRoomsAssetProjector.attachments(
            factState: .validated,
            facts: overBound,
            canonicalOpenRoute: { _ in nil }
        )
        let overBoundProjection = try #require(projectedOverBound)
        #expect(overBoundProjection.state == .rejected)
        #expect(overBoundProjection.rows.isEmpty)

        let rawTransportJSON = """
        {
          "object":"run", "run_id":"run-raw", "status":"completed",
          "cider_attachments":[{
            "id":"\(attachmentID.uuidString)",
            "target":{
              "kind":"vault_file", "id":"\(attachmentFileID.uuidString)",
              "title":"roadmap.pdf", "source":"cider",
              "source_ref":"vaultFile:\(attachmentFileID.uuidString)"
            },
            "display_name":"roadmap.pdf", "content_type":"application/pdf",
            "byte_size":24576, "provenance":"user_attachment", "source":"cider",
            "source_ref":"attachment:\(attachmentID.uuidString)",
            "raw_jsonrpc":{"path":"/Users/private/.env"}
          }]
        }
        """
        let decoded = try JSONDecoder().decode(HermesRunStatusResponse.self, from: Data(rawTransportJSON.utf8))
        #expect(decoded.attachmentFactState == .rejected)
        #expect(decoded.attachments.isEmpty)

        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-room-rejected-assets-\(UUID().uuidString).sqlite")
        defer { removeDatabase(at: databaseURL) }
        let database = CiderDatabase()
        try database.open(at: databaseURL)
        defer { database.close() }
        let repository = ConversationRepository(database: database)
        let room = try AgentRoomsActionService(repository: repository)
            .createConversation(title: "Rejected assets")
        let persistence = AgentRoomsConversationPersistence(database: database, repository: repository)
        try persistTurn(
            room: room,
            persistence: persistence,
            repository: repository,
            runID: "run-rejected-assets",
            sessionID: "session-rejected-assets",
            question: "Inspect this attachment",
            answer: "I could not verify it.",
            attachments: [privateFact],
            artifacts: []
        )
        let rejectedTurn = try #require(repository.turns(roomID: room.id).first)
        #expect(rejectedTurn.metadata["attachment_fact_state"] == "rejected")
        #expect(rejectedTurn.metadata["attachments_json"] == nil)
        let restored = try #require(try persistence.restoreCanonicalRoom(id: room.id))
        #expect(restored.latestAttachmentFactState == .rejected)
        #expect(restored.latestAttachments.isEmpty)
    }

    @Test("attachment and artifact truth remains on its exact terminal turn through physical reopen and runtime rotation")
    func exactTurnFactsSurviveReopen() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-room-assets-\(UUID().uuidString).sqlite")
        defer { removeDatabase(at: databaseURL) }

        let firstDatabase = CiderDatabase()
        try firstDatabase.open(at: databaseURL)
        let firstRepository = ConversationRepository(database: firstDatabase)
        let room = try AgentRoomsActionService(repository: firstRepository)
            .createConversation(title: "Portable room")
        let firstPersistence = AgentRoomsConversationPersistence(database: firstDatabase, repository: firstRepository)
        try persistTurn(
            room: room,
            persistence: firstPersistence,
            repository: firstRepository,
            runID: "run-assets-one",
            sessionID: "session-assets-one",
            question: "Use the attached roadmap",
            answer: "I created the export plan.",
            attachments: [makeAttachment()],
            artifacts: [makeArtifact()]
        )
        let firstTurn = try #require(firstRepository.turns(roomID: room.id).first)
        #expect(firstTurn.metadata["attachment_fact_state"] == "validated")
        #expect(firstTurn.metadata["generated_artifact_fact_state"] == "validated")
        firstDatabase.close()

        let secondDatabase = CiderDatabase()
        try secondDatabase.open(at: databaseURL)
        let secondRepository = ConversationRepository(database: secondDatabase)
        let secondPersistence = AgentRoomsConversationPersistence(database: secondDatabase, repository: secondRepository)
        let reopened = try #require(try secondPersistence.restoreCanonicalRoom(id: room.id))
        #expect(reopened.latestAttachmentFactState == .validated)
        #expect(reopened.latestAttachments == [makeAttachment()])
        #expect(reopened.latestGeneratedArtifactFactState == .validated)
        #expect(reopened.latestGeneratedArtifacts == [makeArtifact()])

        let liveModel = AgentRoomsLiveChatModel(
            transport: AssetUnavailableTransport(),
            canonicalAssetOpenRoute: { target in
                switch target.kind {
                case "vault_file": .vaultFile(fileID: self.attachmentFileID)
                case "project_artifact": .note(noteID: self.artifactNoteID)
                default: nil
                }
            },
            persistence: secondPersistence
        )
        #expect(liveModel.activateCanonicalRoom(id: room.id))
        let nativeReceipt = try #require(liveModel.activeRoom?.transcript.receipt)
        #expect(nativeReceipt.attachments?.rows.first?.openRoute == .vaultFile(fileID: attachmentFileID))
        #expect(nativeReceipt.generatedArtifacts?.rows.first?.openRoute == .note(noteID: artifactNoteID))
        #expect(nativeReceipt.attachments?.rows.first?.availability == "Cider-owned · Ready to open")

        try persistTurn(
            room: room,
            persistence: secondPersistence,
            repository: secondRepository,
            runID: "run-assets-two",
            sessionID: "session-assets-two",
            question: "Continue without assets",
            answer: "No new attachment or artifact.",
            attachments: [],
            artifacts: []
        )
        let turns = try secondRepository.turns(roomID: room.id)
        #expect(turns.count == 2)
        #expect(turns[0].metadata["attachment_fact_state"] == "validated")
        #expect(turns[0].metadata["generated_artifact_fact_state"] == "validated")
        #expect(turns[1].metadata["attachment_fact_state"] == "notReported")
        #expect(turns[1].metadata["generated_artifact_fact_state"] == "notReported")
        #expect(try secondRepository.bindings(roomID: room.id).compactMap(\.externalSessionID) == [
            "session-assets-one", "session-assets-two",
        ])
        secondDatabase.close()

        let finalDatabase = CiderDatabase()
        try finalDatabase.open(at: databaseURL)
        defer { finalDatabase.close() }
        let finalRepository = ConversationRepository(database: finalDatabase)
        let finalPersistence = AgentRoomsConversationPersistence(database: finalDatabase, repository: finalRepository)
        let finalSnapshot = try #require(try finalPersistence.restoreCanonicalRoom(id: room.id))
        #expect(finalSnapshot.latestAttachmentFactState == .notReported)
        #expect(finalSnapshot.latestAttachments.isEmpty)
        #expect(finalSnapshot.latestGeneratedArtifactFactState == .notReported)
        #expect(finalSnapshot.latestGeneratedArtifacts.isEmpty)
        #expect(try finalRepository.turns(roomID: room.id)[0].metadata["attachments_json"] != nil)
        #expect(try finalRepository.turns(roomID: room.id)[0].metadata["generated_artifacts_json"] != nil)
        #expect(try finalDatabase.integrityCheck().isHealthy)
    }

    @Test("room export is deterministic readable machine-readable non-overwriting and path-free")
    func deterministicPortableExport() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-room-export-\(UUID().uuidString).sqlite")
        let exportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-room-export-root-\(UUID().uuidString)", isDirectory: true)
        defer {
            removeDatabase(at: databaseURL)
            try? FileManager.default.removeItem(at: exportRoot)
        }

        let database = CiderDatabase()
        try database.open(at: databaseURL)
        defer { database.close() }
        let repository = ConversationRepository(database: database)
        let room = try AgentRoomsActionService(repository: repository)
            .createConversation(title: "Portable room")
        let persistence = AgentRoomsConversationPersistence(database: database, repository: repository)
        try persistTurn(
            room: room,
            persistence: persistence,
            repository: repository,
            runID: "run-export",
            sessionID: "session-export",
            question: "Keep **this** body exact.",
            answer: "Done.\n\n- exact list",
            attachments: [makeAttachment()],
            artifacts: [makeArtifact()]
        )
        try persistTerminatedTurn(
            room: room,
            persistence: persistence,
            repository: repository,
            runID: "run-export-cancelled",
            question: "Stop here.",
            status: .cancelled,
            partialAssistantText: "Partial response kept."
        )
        try persistTerminatedTurn(
            room: room,
            persistence: persistence,
            repository: repository,
            runID: "run-export-failed",
            question: "Try once more.",
            status: .failed,
            partialAssistantText: nil
        )

        let exporter = AgentRoomsRoomExportService(repository: repository)
        let first = try exporter.render(roomID: room.id)
        let second = try exporter.render(roomID: room.id)
        #expect(first.markdown == second.markdown)
        #expect(first.manifestData == second.manifestData)
        #expect(first.markdown.contains("Keep **this** body exact."))
        #expect(first.markdown.contains("Done.\n\n- exact list"))
        #expect(first.markdown.contains("roadmap.pdf · application/pdf · 24 KB · user_attachment"))
        #expect(first.markdown.contains("Terminal truth: Cancelled"))
        #expect(first.markdown.contains("_Incomplete · cancelled_"))
        #expect(first.markdown.contains("Terminal truth: Failed"))
        #expect(!first.markdown.contains(databaseURL.path))
        #expect(!String(decoding: first.manifestData, as: UTF8.self).contains("/Users/"))
        #expect(!String(decoding: first.manifestData, as: UTF8.self).contains("file://"))
        #expect(!String(decoding: first.manifestData, as: UTF8.self).contains("session-export"))

        let decoded = try JSONDecoder().decode(AgentRoomsRoomExportManifest.self, from: first.manifestData)
        #expect(decoded.room.id == room.id)
        #expect(decoded.turns.map(\.status) == [.completed, .cancelled, .failed])
        #expect(decoded.messages.map(\.body) == [
            "Keep **this** body exact.",
            "Done.\n\n- exact list",
            "Stop here.",
            "Partial response kept.",
            "Try once more.",
        ])
        #expect(decoded.turns[0].attachments.state == .validated)
        #expect(decoded.turns[0].attachments.values == [makeAttachment()])
        #expect(decoded.turns[0].generatedArtifacts.values == [makeArtifact()])
        #expect(decoded.runtimeBindings.count == 1)
        #expect(decoded.runtimeBindings[0].externalSessionID == nil)

        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        let destination = exportRoot.appendingPathComponent("Portable Room.cider-room", isDirectory: true)
        let result = try exporter.export(roomID: room.id, to: destination)
        #expect(result.packageURL == destination)
        #expect(try String(contentsOf: result.markdownURL, encoding: .utf8) == first.markdown)
        #expect(try Data(contentsOf: result.manifestURL) == first.manifestData)
        #expect(throws: AgentRoomsRoomExportError.destinationExists) {
            try exporter.export(roomID: room.id, to: destination)
        }

        let privateRoom = try AgentRoomsActionService(repository: repository)
            .createConversation(title: "Private source guard")
        try persistTurn(
            room: privateRoom,
            persistence: persistence,
            repository: repository,
            runID: "run-private-export",
            sessionID: "session-private-export",
            question: "Read /Users/private/.env",
            answer: "Withheld.",
            attachments: [],
            artifacts: []
        )
        let privateDestination = exportRoot.appendingPathComponent("Private.cider-room", isDirectory: true)
        #expect(throws: AgentRoomsRoomExportError.privateContent) {
            try exporter.export(roomID: privateRoom.id, to: privateDestination)
        }
        #expect(!FileManager.default.fileExists(atPath: privateDestination.path))
    }

    private func makeAttachment() -> HermesCiderAttachment {
        HermesCiderAttachment(
            id: attachmentID.uuidString,
            target: .init(
                kind: "vault_file",
                id: attachmentFileID.uuidString,
                title: "roadmap.pdf",
                projectID: nil,
                artifactType: nil,
                source: "cider",
                sourceRef: "vaultFile:\(attachmentFileID.uuidString)"
            ),
            displayName: "roadmap.pdf",
            contentType: "application/pdf",
            byteSize: 24_576,
            provenance: "user_attachment",
            source: "cider",
            sourceRef: "attachment:\(attachmentID.uuidString)"
        )
    }

    private func makeArtifact() -> HermesCiderGeneratedArtifact {
        HermesCiderGeneratedArtifact(
            id: artifactID.uuidString,
            target: .init(
                kind: "project_artifact",
                id: artifactNoteID.uuidString,
                title: "Export plan",
                projectID: "cider",
                artifactType: "plan",
                source: "cider",
                sourceRef: "note:\(artifactNoteID.uuidString)"
            ),
            displayName: "Export plan.md",
            contentType: "text/markdown",
            byteSize: 4_096,
            provenance: "cider_generated",
            source: "cider",
            sourceRef: "generated_artifact:\(artifactID.uuidString)"
        )
    }

    private func persistTurn(
        room: ConversationRoom,
        persistence: AgentRoomsConversationPersistence,
        repository: ConversationRepository,
        runID: String,
        sessionID: String,
        question: String,
        answer: String,
        attachments: [HermesCiderAttachment],
        artifacts: [HermesCiderGeneratedArtifact]
    ) throws {
        let createdAt = Date(timeIntervalSince1970: 1_826_000_000 + Double(try repository.messages(roomID: room.id).count))
        let attempt = try persistence.beginAttempt(
            roomID: room.id,
            roomTitle: room.title,
            isReservedTestChat: false,
            attemptID: UUID(),
            clientMessageID: "cider-room-client:\(UUID().uuidString)",
            userMessageID: UUID(),
            assistantMessageID: UUID(),
            text: question,
            at: createdAt
        )
        try persistence.markRunStarted(attempt, runID: runID, activity: [], at: createdAt)
        try persistence.complete(
            attempt,
            completion: completion(
                room: room,
                runID: runID,
                sessionID: sessionID,
                question: question,
                answer: answer,
                timestamp: createdAt,
                attachments: attachments,
                artifacts: artifacts,
                runtimeSessionLineage: try repository.bindings(roomID: room.id).compactMap(\.externalSessionID) + [sessionID]
            ),
            expectedText: question,
            activity: []
        )
    }

    private func completion(
        room: ConversationRoom,
        runID: String,
        sessionID: String,
        question: String,
        answer: String,
        timestamp: Date,
        attachments: [HermesCiderAttachment],
        artifacts: [HermesCiderGeneratedArtifact],
        runtimeSessionLineage: [String]
    ) -> HermesRunCompletionEnvelope {
        let userSourceID = "hermes-run:\(runID):user"
        let assistantSourceID = "hermes-run:\(runID):assistant"
        let user = AIAssistantMessage(
            role: .user, content: question, timestamp: timestamp,
            sourceID: userSourceID, sourceSessionID: sessionID, sourceName: "Hermes"
        )
        let assistant = AIAssistantMessage(
            role: .assistant, content: answer, timestamp: timestamp,
            sourceID: assistantSourceID, sourceSessionID: sessionID, sourceName: "Hermes"
        )
        var state = HermesConversationState(
            conversationID: room.id,
            activeRuntimeSessionID: sessionID,
            runtimeSessionLineage: runtimeSessionLineage,
            title: room.title,
            source: "cider-rooms-live-continuation"
        )
        state.lastSyncedAt = timestamp
        state.lastSyncedMessageID = assistantSourceID
        state.lastSyncedTimestamp = timestamp
        state.lastImportedRuntimeSessionID = sessionID
        return HermesRunCompletionEnvelope(
            provenance: .hermesRunsAPI,
            runID: runID,
            terminalStatus: .completed,
            observedFacts: .none,
            finalSessionSynchronizationComplete: true,
            finalMessages: [user, assistant],
            finalState: state,
            modelIdentity: "fake-hermes",
            terminalSourceEvidence: .init(
                reportedTerminalRunID: runID,
                userSourceID: userSourceID,
                assistantSourceID: assistantSourceID,
                userSourceSessionID: sessionID,
                assistantSourceSessionID: sessionID
            ),
            attachmentFactState: attachments.isEmpty ? .notReported : .validated,
            attachments: attachments,
            generatedArtifactFactState: artifacts.isEmpty ? .notReported : .validated,
            generatedArtifacts: artifacts
        )
    }

    private func persistTerminatedTurn(
        room: ConversationRoom,
        persistence: AgentRoomsConversationPersistence,
        repository: ConversationRepository,
        runID: String,
        question: String,
        status: ConversationTurnStatus,
        partialAssistantText: String?
    ) throws {
        let date = Date(timeIntervalSince1970: 1_826_000_100 + Double(try repository.turns(roomID: room.id).count))
        let attempt = try persistence.beginAttempt(
            roomID: room.id,
            roomTitle: room.title,
            isReservedTestChat: false,
            attemptID: UUID(),
            clientMessageID: "cider-room-client:\(UUID().uuidString)",
            userMessageID: UUID(),
            assistantMessageID: UUID(),
            text: question,
            at: date
        )
        try persistence.markRunStarted(attempt, runID: runID, activity: [], at: date)
        try persistence.terminate(
            attempt,
            status: status,
            runID: runID,
            partialAssistantText: partialAssistantText,
            activity: [],
            at: date
        )
    }

    private func removeDatabase(at url: URL) {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: url)
        try? fileManager.removeItem(atPath: url.path + "-wal")
        try? fileManager.removeItem(atPath: url.path + "-shm")
    }
}

private struct AssetUnavailableTransport: HermesBridgeTransport {
    func availability() async -> HermesBridgeAvailability { .unavailable("Test transport") }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        throw AssetUnavailableTransportError.unavailable
    }

    func stop(runID: String) async throws {}
}

private enum AssetUnavailableTransportError: Error { case unavailable }
