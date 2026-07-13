import Foundation
import Testing
@testable import Cider

@MainActor
struct AgentRoomsSessionModelTests {
    @Test("drafts are isolated per canonical room and restored across session reconstruction")
    func perRoomDraftContinuity() throws {
        let suiteName = "AgentRoomsSessionModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let selectionStore = AgentRoomsSelectionStore(defaults: defaults, key: "selection")
        let draftStore = AgentRoomsDraftStore(defaults: defaults, key: "drafts")
        let firstRoomID = UUID().uuidString
        let secondRoomID = UUID().uuidString
        let session = AgentRoomsSessionModel(
            liveChat: AgentRoomsLiveChatModel(transport: SessionContinuityTransport()),
            selectionStore: selectionStore,
            draftStore: draftStore
        )

        session.selectRoom(id: firstRoomID, persistIfCanonical: true)
        session.composerText = "First room draft"
        session.selectRoom(id: secondRoomID, persistIfCanonical: true)
        #expect(session.composerText.isEmpty)
        session.composerText = "Second room draft"
        session.selectRoom(id: firstRoomID, persistIfCanonical: true)
        #expect(session.composerText == "First room draft")
        session.selectRoom(id: secondRoomID, persistIfCanonical: true)
        #expect(session.composerText == "Second room draft")

        let reconstructed = AgentRoomsSessionModel(
            liveChat: AgentRoomsLiveChatModel(transport: SessionContinuityTransport()),
            selectionStore: selectionStore,
            draftStore: AgentRoomsDraftStore(defaults: defaults, key: "drafts")
        )
        #expect(reconstructed.selectedRoomID == secondRoomID)
        #expect(reconstructed.composerText == "Second room draft")
        reconstructed.selectRoom(id: firstRoomID, persistIfCanonical: true)
        #expect(reconstructed.composerText == "First room draft")
    }

    @Test("a recovered failed draft is stored for its originating room without leaking into selection")
    func recoveredDraftStaysWithOriginatingRoom() async throws {
        let session = AgentRoomsSessionModel(
            liveChat: AgentRoomsLiveChatModel(
                transport: SessionPreAcceptFailureTransport(),
                turnCoordinator: HermesTurnCoordinator()
            )
        )
        await session.startTestChat()
        let originRoomID = try #require(session.liveChat.activeRoom?.id)
        await session.liveChat.send("Recover only here", selectedRoomID: originRoomID)
        let otherRoomID = UUID().uuidString
        session.selectRoom(id: otherRoomID, persistIfCanonical: false)

        #expect(!session.restoreRecoveredDraftIfNeeded())
        #expect(session.composerText.isEmpty)
        session.selectRoom(id: originRoomID, persistIfCanonical: false)
        #expect(session.composerText == "Recover only here")
    }

    @Test("Rooms view reconstruction keeps the explicit process-lifetime test chat session")
    func viewReconstructionKeepsSession() async throws {
        let transport = SessionContinuityTransport()
        let session = AgentRoomsSessionModel(
            liveChat: AgentRoomsLiveChatModel(
                transport: transport,
                turnCoordinator: HermesTurnCoordinator()
            )
        )
        let legacyRoom = AgentRoom(
            id: "legacy-room",
            title: "Legacy room",
            preview: "Historical only",
            updatedAt: .distantPast,
            relativeTime: "Earlier",
            transcript: .init(runtimeLabel: "Legacy", messages: [], link: nil, receipt: nil, futureArtifact: nil),
            continuity: .historicalReplay
        )
        let workspace = AgentRoomsWorkspaceState.loaded(
            authority: .canonicalIncomplete,
            rooms: [legacyRoom],
            selectedRoomID: legacyRoom.id
        )

        _ = AgentRoomsWorkspaceView(state: workspace, session: session, onOpenLiveChat: {})
        await session.startTestChat()
        let testRoomID = try #require(session.liveChat.testRoom?.id)
        session.selectedRoomID = testRoomID
        session.composerText = "Keep this draft"
        await session.liveChat.send("Keep this turn", selectedRoomID: testRoomID)

        _ = AgentRoomsWorkspaceView(state: workspace, session: session, onOpenLiveChat: {})

        #expect(session.selectedRoomID == testRoomID)
        #expect(session.composerText == "Keep this draft")
        #expect(session.liveChat.testRoom?.transcript.messages.map(\.body) == ["Keep this turn", "Still here"])
        #expect(session.liveChat.testRoom?.transcript.receipt?.status == .completed)
        #expect(session.liveChat.testRoom?.transcript.receipt?.runIdentity == "run-session")
        guard case .loaded(_, _, let selectedLegacyRoom) = workspace.projection(selectedRoomID: legacyRoom.id) else {
            Issue.record("Expected the legacy workspace to remain loaded")
            return
        }
        #expect(selectedLegacyRoom.id == legacyRoom.id)
        #expect(legacyRoom.transcript.messages.isEmpty)
        #expect(legacyRoom.continuity == .historicalReplay)
    }

    @Test("an explicitly nonpersistent test session starts clean")
    func explicitlyNonpersistentSessionStartsClean() async throws {
        let first = AgentRoomsSessionModel(
            liveChat: AgentRoomsLiveChatModel(
                transport: SessionContinuityTransport(),
                turnCoordinator: HermesTurnCoordinator()
            )
        )
        await first.startTestChat()
        first.selectedRoomID = first.liveChat.testRoom?.id
        first.composerText = "Process one draft"

        let next = AgentRoomsSessionModel(
            liveChat: AgentRoomsLiveChatModel(
                transport: SessionContinuityTransport(),
                turnCoordinator: HermesTurnCoordinator()
            )
        )

        #expect(next.liveChat.testRoom == nil)
        #expect(next.selectedRoomID == nil)
        #expect(next.composerText.isEmpty)
        #expect(next.liveChat.turnState == .idle)
        #expect(next.liveChat.liveActivity.isEmpty)
    }

    @Test("production composition restores through canonical conversation persistence only")
    func productionCompositionUsesCanonicalPersistence() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appDelegate = try String(
            contentsOf: root.appendingPathComponent("Sources/Cider/App/AppDelegate.swift"),
            encoding: .utf8
        )
        let mainWindow = try String(
            contentsOf: root.appendingPathComponent("Sources/Cider/App/AppDelegate+CiderMainWindow.swift"),
            encoding: .utf8
        )
        let contentArea = try String(
            contentsOf: root.appendingPathComponent("Sources/Cider/Views/CiderPanelView+ContentArea.swift"),
            encoding: .utf8
        )
        let sessionModel = try String(
            contentsOf: root.appendingPathComponent("Sources/Cider/Services/Conversation/AgentRoomsSessionModel.swift"),
            encoding: .utf8
        )

        #expect(appDelegate.contains("let agentRoomsSession = AgentRoomsSessionModel"))
        #expect(mainWindow.contains("agentRoomsSession: agentRoomsSession"))
        #expect(contentArea.contains("session: agentRoomsSession"))
        #expect(!contentArea.contains("AgentRoomsLiveChatModel(transport:"))
        #expect(sessionModel.contains("AgentRoomsConversationPersistence"))
        #expect(appDelegate.contains("restoreDurableTestChat"))
        for forbidden in ["CiderVault", "UserDefaults", "FileManager", "JSONL"] {
            #expect(!sessionModel.contains(forbidden))
        }
    }
}

private actor SessionContinuityTransport: HermesBridgeTransport {
    func availability() async -> HermesBridgeAvailability { .apiRuns }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        let runID = "run-session"
        let sessionID = "runtime-session"
        let timestamp = Date(timeIntervalSince1970: 1_750_000_000)
        let userSourceID = "hermes-run:\(runID):user"
        let assistantSourceID = "hermes-run:\(runID):assistant"
        await onEvent?(.runStarted(runID))
        await onEvent?(.messageDelta("Still here"))
        return HermesBridgeSendResult(completion: HermesRunCompletionEnvelope(
            provenance: .hermesRunsAPI,
            runID: runID,
            terminalStatus: .completed,
            observedFacts: .none,
            finalSessionSynchronizationComplete: true,
            finalMessages: [
                AIAssistantMessage(
                    role: .user,
                    content: text,
                    timestamp: timestamp,
                    sourceID: userSourceID,
                    sourceSessionID: sessionID
                ),
                AIAssistantMessage(
                    role: .assistant,
                    content: "Still here",
                    timestamp: timestamp,
                    sourceID: assistantSourceID,
                    sourceSessionID: sessionID
                ),
            ],
            finalState: HermesConversationState(
                conversationID: state.conversationID,
                runtimeID: "hermes",
                activeRuntimeSessionID: sessionID,
                runtimeSessionLineage: [sessionID],
                title: state.title,
                source: state.source,
                lastSyncedMessageID: assistantSourceID,
                lastSyncedTimestamp: timestamp,
                lastImportedRuntimeSessionID: sessionID
            ),
            modelIdentity: "gpt-test",
            terminalSourceEvidence: .init(
                reportedTerminalRunID: runID,
                userSourceID: userSourceID,
                assistantSourceID: assistantSourceID,
                userSourceSessionID: sessionID,
                assistantSourceSessionID: sessionID
            )
        ))
    }

    func stop(runID: String) async throws {}
}

private actor SessionPreAcceptFailureTransport: HermesBridgeTransport {
    func availability() async -> HermesBridgeAvailability { .apiRuns }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        throw SessionPreAcceptFailure.disconnected
    }

    func stop(runID: String) async throws {}
}

private enum SessionPreAcceptFailure: Error { case disconnected }
