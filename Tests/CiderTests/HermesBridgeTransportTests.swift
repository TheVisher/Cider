import Foundation
import Testing
@testable import Cider

struct HermesBridgeTransportTests {
    @MainActor
    @Test("production Runs completion projects the real tracked backpack bookmark into an Open receipt")
    func productionRunsCompletionProjectsTrackedBackpackBookmark() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HermesRunTransportURLProtocol.self]
        let transport = HermesRunTransport(
            apiClient: HermesAPIClient(
                baseURL: URL(string: "https://backpack.invalid")!,
                apiKey: nil,
                session: URLSession(configuration: configuration)
            ),
            fallbackService: HermesSessionService()
        )
        let saved = AgentRoomsSavedBookmarkReference(
            id: UUID(uuidString: "7ED86324-2913-4380-935B-39A4B2C0E066")!,
            title: "Cohesive 2.0 38L Pack",
            url: URL(string: "https://chromeindustries.com/products/cohesive-2-0-38l-pack?_kx=ysfLHMryHXrUFPlLqSSjJTYoPgmPGthSU2ocd8ZnNi8.SCV5Ym&variant=43962733953084")!
        )
        let session = AgentRoomsSessionModel(
            liveChat: AgentRoomsLiveChatModel(
                transport: transport,
                turnCoordinator: HermesTurnCoordinator(),
                savedBookmarkMatches: { candidate in
                    guard let candidateIdentity = VaultDuplicateAuditor.canonicalBookmarkURL(candidate.absoluteString),
                          VaultDuplicateAuditor.canonicalBookmarkURL(saved.url.absoluteString) == candidateIdentity
                    else { return [] }
                    return [saved]
                }
            )
        )

        await session.startTestChat()
        let roomID = try #require(session.selectedRoomID)
        await session.liveChat.send("what's the backpack bookmark I saved?", selectedRoomID: roomID)

        let receipt = try #require(session.liveChat.testRoom?.transcript.receipt?.objectReceipts.first)
        #expect(receipt.kind == .bookmark)
        #expect(receipt.title == "Cohesive 2.0 38L Pack")
        #expect(receipt.openRoute == .bookmark(bookmarkID: saved.id))
    }

    @Test("Runs transport returns the exact immutable terminal completion envelope")
    func runsTransportReturnsTerminalEnvelope() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HermesRunTransportURLProtocol.self]
        let apiClient = HermesAPIClient(
            baseURL: URL(string: "https://hermes.invalid")!,
            apiKey: nil,
            session: URLSession(configuration: configuration)
        )
        let transport = HermesRunTransport(apiClient: apiClient, fallbackService: HermesSessionService())
        let initialState = HermesConversationState(
            conversationID: UUID(uuidString: "78000000-0000-4000-8000-000000000000")!,
            activeRuntimeSessionID: "parent-session",
            runtimeSessionLineage: ["parent-session"],
            title: "CID-780",
            source: "cider"
        )
        let recorder = HermesRunEventRecorder()

        let result = try await transport.send(
            text: "Hello",
            state: initialState,
            existingMessages: [],
            onEvent: { event in await recorder.append(event) }
        )

        #expect(result.completion.provenance == .hermesRunsAPI)
        #expect(result.completion.runID == "run-780")
        #expect(result.completion.modelIdentity == "hermes-model-5")
        #expect(result.completion.terminalStatus == .completed)
        #expect(result.completion.finalSessionSynchronizationComplete)
        #expect(result.messages.map(\.content) == ["Hello", "Hi"])
        #expect(result.messages.map(\.sourceID) == [
            "hermes-run:run-780:user",
            "hermes-run:run-780:assistant",
        ])
        #expect(result.messages.map(\.sourceSessionID) == ["session-780", "session-780"])
        #expect(result.state.activeRuntimeSessionID == "session-780")
        #expect(result.state.runtimeSessionLineage == ["parent-session", "session-780"])
        #expect(result.state.lastSyncedMessageID == "hermes-run:run-780:assistant")
        #expect(result.completion.terminalSourceEvidence.reportedTerminalRunID == "run-780")
        #expect(result.completion.ciderReferences == [
            HermesCiderReference(
                kind: "task",
                id: "card-780",
                title: "Transport-backed task",
                boardID: "board-780",
                projectID: nil,
                artifactType: nil,
                source: "cider",
                sourceRef: "kanban_card:board-780/card-780"
            )
        ])
        #expect(result.completion.isEligibleForFutureShadowPersistence)
        #expect(await recorder.snapshot() == [
            .runStarted("run-780"),
            .completed(output: "Hi"),
        ])
    }

    @Test("Runs transport preserves cancellation callback and thrown cancellation behavior")
    func runsTransportPreservesCancellation() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HermesRunTransportURLProtocol.self]
        let transport = HermesRunTransport(
            apiClient: HermesAPIClient(
                baseURL: URL(string: "https://cancelled.invalid")!,
                apiKey: nil,
                session: URLSession(configuration: configuration)
            ),
            fallbackService: HermesSessionService()
        )
        let recorder = HermesRunEventRecorder()

        await #expect(throws: CancellationError.self) {
            _ = try await transport.send(
                text: "Cancel",
                state: HermesConversationState(activeRuntimeSessionID: "parent-session"),
                existingMessages: [],
                onEvent: { event in await recorder.append(event) }
            )
        }
        #expect(await recorder.snapshot() == [
            .runStarted("run-780"),
            .cancelled,
            .cancelled,
        ])
    }

    @Test("run snapshot accumulates message deltas and final output")
    func runSnapshotAccumulatesDeltas() {
        let snapshot = HermesRunSnapshot.empty
            .reducing(.messageDelta("Hello"))
            .reducing(.messageDelta(", Cider"))
            .reducing(.completed(output: "Hello, Cider"))

        #expect(snapshot.visibleText == "Hello, Cider")
        #expect(snapshot.status == .completed("Hello, Cider"))
    }

    @Test("run snapshot uses final output when no deltas arrived")
    func runSnapshotUsesFinalOutputWhenNoDeltasArrived() {
        let snapshot = HermesRunSnapshot.empty
            .reducing(.completed(output: "Done"))

        #expect(snapshot.visibleText == "Done")
        #expect(snapshot.status == .completed("Done"))
    }

    @Test("run snapshot tracks tool preview separately from assistant text")
    func runSnapshotTracksToolPreviewSeparately() {
        let snapshot = HermesRunSnapshot.empty
            .reducing(.toolStarted(name: "terminal", preview: "swift test"))
            .reducing(.messageDelta("Tests passed"))

        #expect(snapshot.visibleText == "Tests passed")
        #expect(snapshot.toolSummary == "swift test")
    }

    @Test("run snapshot tracks approval requests")
    func runSnapshotTracksApprovalRequests() {
        let snapshot = HermesRunSnapshot.empty
            .reducing(.runStarted("run_1"))
            .reducing(.approvalRequested("Allow file edit?"))

        #expect(snapshot.status == .waitingForApproval("Allow file edit?"))
        #expect(snapshot.toolSummary == "Allow file edit?")
    }

    @Test("clean Runs completion envelope preserves exact terminal provenance and is eligible")
    func cleanRunsCompletionEnvelopeIsEligible() throws {
        let envelope = eligibleEnvelope()

        #expect(envelope.provenance == .hermesRunsAPI)
        #expect(envelope.runID == "run-780")
        #expect(envelope.terminalStatus == .completed)
        #expect(envelope.modelIdentity == "hermes-model-5")
        #expect(envelope.finalState == expectedState())
        #expect(envelope.finalMessages == expectedMessages())
        #expect(envelope.terminalSourceEvidence == .init(
            reportedTerminalRunID: "run-780",
            userSourceID: "hermes-run:run-780:user",
            assistantSourceID: "hermes-run:run-780:assistant",
            userSourceSessionID: "session-780",
            assistantSourceSessionID: "session-780"
        ))
        #expect(envelope.isEligibleForFutureShadowPersistence)
    }

    @Test("CLI fallback has explicit provenance and is ineligible")
    func cliFallbackIsExplicitlyIneligible() {
        let envelope = replacing(
            eligibleEnvelope(),
            provenance: .cliFallback,
            runID: nil,
            terminalStatus: .unknown,
            modelIdentity: nil
        )

        #expect(envelope.provenance == .cliFallback)
        #expect(envelope.terminalStatus == .unknown)
        #expect(!envelope.isEligibleForFutureShadowPersistence)
    }

    @Test("structured context or approval facts cannot enter the legacy shadow envelope")
    func structuredFactsRemainIneligibleForLegacyShadow() {
        let context = HermesCiderContextCheckpoint(
            id: "checkpoint-826", selected: [], citations: [], omissionReason: "no_context_selected",
            source: "cider", sourceRef: "context_checkpoint:checkpoint-826"
        )
        let withContext = replacing(
            eligibleEnvelope(),
            contextCheckpointFactState: .validated,
            contextCheckpoint: context
        )
        let approval = HermesApprovalRequest(
            id: "approval-826", action: "Update note", target: nil, risk: "medium",
            scope: "write", status: "requested", source: "hermes_runs_api",
            sourceRef: "approval:approval-826"
        )
        let withApproval = replacing(
            eligibleEnvelope(),
            approvalFactState: .validated,
            approvalRequests: [approval]
        )

        #expect(!withContext.isEligibleForFutureShadowPersistence)
        #expect(!withApproval.isEligibleForFutureShadowPersistence)
    }

    @Test("every excluded event or content fact independently fails closed", arguments: [
        HermesRunObservedFacts(containedToolEvent: true, containedReasoningEvent: false, containedApprovalEvent: false, containedAttachmentContentOrEvent: false, containedPendingContentOrEvent: false, containedStreamingContentOrEvent: false, runIdentityConsistent: true),
        HermesRunObservedFacts(containedToolEvent: false, containedReasoningEvent: true, containedApprovalEvent: false, containedAttachmentContentOrEvent: false, containedPendingContentOrEvent: false, containedStreamingContentOrEvent: false, runIdentityConsistent: true),
        HermesRunObservedFacts(containedToolEvent: false, containedReasoningEvent: false, containedApprovalEvent: true, containedAttachmentContentOrEvent: false, containedPendingContentOrEvent: false, containedStreamingContentOrEvent: false, runIdentityConsistent: true),
        HermesRunObservedFacts(containedToolEvent: false, containedReasoningEvent: false, containedApprovalEvent: false, containedAttachmentContentOrEvent: true, containedPendingContentOrEvent: false, containedStreamingContentOrEvent: false, runIdentityConsistent: true),
        HermesRunObservedFacts(containedToolEvent: false, containedReasoningEvent: false, containedApprovalEvent: false, containedAttachmentContentOrEvent: false, containedPendingContentOrEvent: true, containedStreamingContentOrEvent: false, runIdentityConsistent: true),
        HermesRunObservedFacts(containedToolEvent: false, containedReasoningEvent: false, containedApprovalEvent: false, containedAttachmentContentOrEvent: false, containedPendingContentOrEvent: false, containedStreamingContentOrEvent: true, runIdentityConsistent: true),
    ])
    func excludedFactsFailClosed(facts: HermesRunObservedFacts) {
        #expect(!replacing(eligibleEnvelope(), observedFacts: facts).isEligibleForFutureShadowPersistence)
    }

    @Test("attachment, pending, and live message content independently fail closed")
    func excludedFinalMessageContentFailsClosed() {
        var attached = expectedMessages()
        attached[0].attachments = [.init(id: "image-1", kind: .image)]
        #expect(!replacing(eligibleEnvelope(), finalMessages: attached).isEligibleForFutureShadowPersistence)

        var pending = expectedMessages()
        pending[0].sourceID = "hermes:pending:local"
        #expect(!replacing(eligibleEnvelope(), finalMessages: pending).isEligibleForFutureShadowPersistence)

        var streaming = expectedMessages()
        streaming[0].sourceID = "hermes-live:run-780:user"
        #expect(!replacing(eligibleEnvelope(), finalMessages: streaming).isEligibleForFutureShadowPersistence)
    }

    @Test("missing and mismatched run or terminal source identities fail closed")
    func runAndSourceIdentityFailures() {
        #expect(!replacing(eligibleEnvelope(), runID: nil).isEligibleForFutureShadowPersistence)
        #expect(!replacing(
            eligibleEnvelope(),
            terminalSourceEvidence: .init(
                reportedTerminalRunID: "different-run",
                userSourceID: "hermes-run:run-780:user",
                assistantSourceID: "hermes-run:run-780:assistant",
                userSourceSessionID: "session-780",
                assistantSourceSessionID: "session-780"
            )
        ).isEligibleForFutureShadowPersistence)

        var mismatched = expectedMessages()
        mismatched[1].sourceID = "hermes-run:different-run:assistant"
        #expect(!replacing(eligibleEnvelope(), finalMessages: mismatched).isEligibleForFutureShadowPersistence)

        #expect(!replacing(eligibleEnvelope(), finalMessages: [expectedMessages()[1]]).isEligibleForFutureShadowPersistence)
    }

    @Test("nonterminal, cancelled, failed, and disconnected statuses fail closed", arguments: [
        HermesRunTerminalStatus.unknown,
        .cancelled,
        .failed,
        .disconnected,
    ])
    func terminalStatusFailures(status: HermesRunTerminalStatus) {
        #expect(!replacing(eligibleEnvelope(), terminalStatus: status).isEligibleForFutureShadowPersistence)
    }

    @Test("incomplete synchronization and inconsistent cursor or session lineage fail closed")
    func synchronizationAndLineageFailures() {
        #expect(!replacing(
            eligibleEnvelope(),
            finalSessionSynchronizationComplete: false
        ).isEligibleForFutureShadowPersistence)

        var cursorMismatch = expectedState()
        cursorMismatch.lastSyncedMessageID = "hermes-run:run-780:user"
        #expect(!replacing(eligibleEnvelope(), finalState: cursorMismatch).isEligibleForFutureShadowPersistence)

        var sessionMismatch = expectedState()
        sessionMismatch.activeRuntimeSessionID = "other-session"
        #expect(!replacing(eligibleEnvelope(), finalState: sessionMismatch).isEligibleForFutureShadowPersistence)

        var lineageMismatch = expectedState()
        lineageMismatch.runtimeSessionLineage = ["session-780", "stale-session"]
        #expect(!replacing(eligibleEnvelope(), finalState: lineageMismatch).isEligibleForFutureShadowPersistence)

        var duplicateLineage = expectedState()
        duplicateLineage.runtimeSessionLineage = ["session-780", "session-780"]
        #expect(!replacing(eligibleEnvelope(), finalState: duplicateLineage).isEligibleForFutureShadowPersistence)

        #expect(!replacing(eligibleEnvelope(), modelIdentity: nil).isEligibleForFutureShadowPersistence)
        #expect(!replacing(
            eligibleEnvelope(),
            observedFacts: .init(
                containedToolEvent: false,
                containedReasoningEvent: false,
                containedApprovalEvent: false,
                containedAttachmentContentOrEvent: false,
                containedPendingContentOrEvent: false,
                containedStreamingContentOrEvent: false,
                runIdentityConsistent: false
            )
        ).isEligibleForFutureShadowPersistence)
    }

    @Test("observed event flags aggregate across the full run and never reset")
    func observedEventFactsAreSticky() {
        var accumulator = HermesRunObservationAccumulator(runID: "run-780")
        accumulator.recordInitialStatus("queued")
        accumulator.record(.init(event: "tool.started", runID: "run-780", delta: nil, output: nil, error: nil, tool: "terminal", preview: nil, status: nil))
        accumulator.record(.init(event: "reasoning.available", runID: "run-780", delta: nil, output: nil, error: nil, tool: nil, preview: "thinking", status: nil))
        accumulator.record(.init(event: "approval.requested", runID: "run-780", delta: nil, output: nil, error: nil, tool: nil, preview: "approve", status: nil))
        accumulator.record(.init(event: "attachment.created", runID: "run-780", delta: nil, output: nil, error: nil, tool: nil, preview: nil, status: nil))
        accumulator.record(.init(event: "message.delta", runID: "run-780", delta: "partial", output: nil, error: nil, tool: nil, preview: nil, status: nil))
        accumulator.record(.init(event: "run.completed", runID: "run-780", delta: nil, output: "final", error: nil, tool: nil, preview: nil, status: "completed"))

        let facts = accumulator.finalized(messages: expectedMessages(), terminalRunID: "run-780")
        #expect(facts.containedToolEvent)
        #expect(facts.containedReasoningEvent)
        #expect(facts.containedApprovalEvent)
        #expect(facts.containedAttachmentContentOrEvent)
        #expect(facts.containedPendingContentOrEvent)
        #expect(facts.containedStreamingContentOrEvent)
        #expect(facts.runIdentityConsistent)
    }

    @Test("approval event accumulator keeps only normalized structured current status")
    func approvalEventAccumulatorKeepsStructuredStatus() {
        let target = HermesCiderReference(
            kind: "note", id: "A1000000-0000-4000-8000-000000000001", title: "Trip plan",
            boardID: nil, projectID: nil, artifactType: nil, source: "cider",
            sourceRef: "note:A1000000-0000-4000-8000-000000000001"
        )
        let requested = HermesApprovalRequest(
            id: "approval-826", action: "Update note", target: target, risk: "medium",
            scope: "write", status: "requested", source: "hermes_runs_api",
            sourceRef: "approval:approval-826"
        )
        let approved = HermesApprovalRequest(
            id: requested.id, action: requested.action, target: target, risk: requested.risk,
            scope: requested.scope, status: "approved", source: requested.source,
            sourceRef: requested.sourceRef
        )
        var accumulator = HermesRunObservationAccumulator(runID: "run-826")
        accumulator.record(.init(
            event: "approval.requested", runID: "run-826", delta: nil, output: nil,
            error: nil, tool: nil, preview: "ignored raw preview", status: nil,
            approval: requested, approvalFactState: .validated
        ))
        accumulator.record(.init(
            event: "approval.approved", runID: "run-826", delta: nil, output: nil,
            error: nil, tool: nil, preview: nil, status: nil,
            approval: approved, approvalFactState: .validated
        ))

        let projection = accumulator.approvalProjection()
        #expect(projection.state == .validated)
        #expect(projection.requests == [approved])
    }

    @Test("context event accumulator preserves only a normalized checkpoint")
    func contextEventAccumulatorKeepsStructuredCheckpoint() {
        let note = HermesCiderReference(
            kind: "note", id: "A1000000-0000-4000-8000-000000000001", title: "Trip plan",
            boardID: nil, projectID: nil, artifactType: nil, source: "cider",
            sourceRef: "note:A1000000-0000-4000-8000-000000000001"
        )
        let checkpoint = HermesCiderContextCheckpoint(
            id: "checkpoint-826", selected: [note], citations: [], omissionReason: nil,
            source: "cider", sourceRef: "context_checkpoint:checkpoint-826"
        )
        var accumulator = HermesRunObservationAccumulator(runID: "run-826")
        accumulator.record(.init(
            event: "context.checkpoint", runID: "run-826", delta: nil, output: nil,
            error: nil, tool: nil, preview: nil, status: nil,
            contextCheckpoint: checkpoint, contextCheckpointFactState: .validated
        ))

        let projection = accumulator.contextProjection()
        #expect(projection.state == .validated)
        #expect(projection.checkpoint == checkpoint)
    }

    @Test("raw approval preview never becomes structured approval authority")
    func rawApprovalPreviewFailsClosed() {
        var accumulator = HermesRunObservationAccumulator(runID: "run-826")
        accumulator.record(.init(
            event: "approval.requested", runID: "run-826", delta: nil, output: nil,
            error: nil, tool: nil, preview: "Edit /Users/private/.env", status: nil
        ))

        let projection = accumulator.approvalProjection()
        #expect(projection.state == .rejected)
        #expect(projection.requests.isEmpty)
    }

    @Test("completion envelope owns immutable value copies of final messages and state")
    func envelopeIsUnaffectedByLaterFixtureMutation() {
        var sourceMessages = expectedMessages()
        var sourceState = expectedState()
        let envelope = HermesRunCompletionEnvelope(
            provenance: .hermesRunsAPI,
            runID: "run-780",
            terminalStatus: .completed,
            observedFacts: .none,
            finalSessionSynchronizationComplete: true,
            finalMessages: sourceMessages,
            finalState: sourceState,
            modelIdentity: "hermes-model-5",
            terminalSourceEvidence: expectedEvidence()
        )

        sourceMessages[0].content = "mutated after completion"
        sourceMessages.removeLast()
        sourceState.activeRuntimeSessionID = "mutated-session"
        sourceState.runtimeSessionLineage.removeAll()

        #expect(envelope.finalMessages == expectedMessages())
        #expect(envelope.finalState == expectedState())
        #expect(envelope.isEligibleForFutureShadowPersistence)
    }

    private func eligibleEnvelope() -> HermesRunCompletionEnvelope {
        HermesRunCompletionEnvelope(
            provenance: .hermesRunsAPI,
            runID: "run-780",
            terminalStatus: .completed,
            observedFacts: .none,
            finalSessionSynchronizationComplete: true,
            finalMessages: expectedMessages(),
            finalState: expectedState(),
            modelIdentity: "hermes-model-5",
            terminalSourceEvidence: expectedEvidence()
        )
    }

    private func expectedMessages() -> [AIAssistantMessage] {
        let timestamp = Date(timeIntervalSince1970: 1_780_000_000)
        return [
            .init(id: UUID(uuidString: "78000000-0000-4000-8000-000000000001")!, role: .user, content: "Hello", timestamp: timestamp, sourceID: "hermes-run:run-780:user", sourceSessionID: "session-780", sourceName: "Hermes"),
            .init(id: UUID(uuidString: "78000000-0000-4000-8000-000000000002")!, role: .assistant, content: "Hi", timestamp: timestamp, sourceID: "hermes-run:run-780:assistant", sourceSessionID: "session-780", sourceName: "Hermes"),
        ]
    }

    private func expectedState() -> HermesConversationState {
        let timestamp = Date(timeIntervalSince1970: 1_780_000_000)
        return HermesConversationState(
            conversationID: UUID(uuidString: "78000000-0000-4000-8000-000000000000")!,
            runtimeID: "hermes",
            activeRuntimeSessionID: "session-780",
            runtimeSessionLineage: ["parent-session", "session-780"],
            title: "CID-780",
            source: "cider",
            lastSyncedAt: timestamp,
            lastSyncedMessageID: "hermes-run:run-780:assistant",
            lastSyncedTimestamp: timestamp,
            lastImportedRuntimeSessionID: "session-780"
        )
    }

    private func expectedEvidence() -> HermesTerminalSourceIdentityEvidence {
        .init(
            reportedTerminalRunID: "run-780",
            userSourceID: "hermes-run:run-780:user",
            assistantSourceID: "hermes-run:run-780:assistant",
            userSourceSessionID: "session-780",
            assistantSourceSessionID: "session-780"
        )
    }

    private func replacing(
        _ envelope: HermesRunCompletionEnvelope,
        provenance: HermesTransportProvenance? = nil,
        runID: String? = "run-780",
        terminalStatus: HermesRunTerminalStatus? = nil,
        observedFacts: HermesRunObservedFacts? = nil,
        finalSessionSynchronizationComplete: Bool? = nil,
        finalMessages: [AIAssistantMessage]? = nil,
        finalState: HermesConversationState? = nil,
        modelIdentity: String? = "hermes-model-5",
        terminalSourceEvidence: HermesTerminalSourceIdentityEvidence? = nil,
        contextCheckpointFactState: HermesStructuredFactState? = nil,
        contextCheckpoint: HermesCiderContextCheckpoint? = nil,
        approvalFactState: HermesStructuredFactState? = nil,
        approvalRequests: [HermesApprovalRequest]? = nil
    ) -> HermesRunCompletionEnvelope {
        HermesRunCompletionEnvelope(
            provenance: provenance ?? envelope.provenance,
            runID: runID,
            terminalStatus: terminalStatus ?? envelope.terminalStatus,
            observedFacts: observedFacts ?? envelope.observedFacts,
            finalSessionSynchronizationComplete: finalSessionSynchronizationComplete ?? envelope.finalSessionSynchronizationComplete,
            finalMessages: finalMessages ?? envelope.finalMessages,
            finalState: finalState ?? envelope.finalState,
            modelIdentity: modelIdentity,
            terminalSourceEvidence: terminalSourceEvidence ?? envelope.terminalSourceEvidence,
            ciderReferences: envelope.ciderReferences,
            contextCheckpointFactState: contextCheckpointFactState ?? envelope.contextCheckpointFactState,
            contextCheckpoint: contextCheckpoint ?? envelope.contextCheckpoint,
            approvalFactState: approvalFactState ?? envelope.approvalFactState,
            approvalRequests: approvalRequests ?? envelope.approvalRequests
        )
    }
}

private actor HermesRunEventRecorder {
    private var events: [HermesRunEvent] = []

    func append(_ event: HermesRunEvent) {
        events.append(event)
    }

    func snapshot() -> [HermesRunEvent] {
        events
    }
}

private final class HermesRunTransportURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: HermesAPIClientError.unavailable)
            return
        }
        let path = url.path
        let (status, contentType, body): (Int, String, String)
        switch (request.httpMethod, path) {
        case ("GET", "/v1/capabilities"):
            status = 200
            contentType = "application/json"
            body = """
            {
              "object":"hermes.api_server.capabilities",
              "platform":"hermes-agent",
              "model":"hermes-model-5",
              "features":{
                "chat_completions":true,
                "chat_completions_streaming":true,
                "responses_api":true,
                "responses_streaming":true,
                "run_submission":true,
                "run_status":true,
                "run_events_sse":true,
                "run_stop":true,
                "tool_progress_events":true,
                "session_continuity_header":"X-Hermes-Session-Id"
              }
            }
            """
        case ("POST", "/v1/runs"):
            status = 202
            contentType = "application/json"
            body = #"{"run_id":"run-780","status":"running"}"#
        case ("GET", "/v1/runs/run-780/events"):
            status = 200
            contentType = "text/event-stream"
            if url.host == "cancelled.invalid" {
                body = """
                data: {"event":"run.cancelled","run_id":"run-780"}

                """
            } else if url.host == "backpack.invalid" {
                body = """
                data: {"event":"run.completed","run_id":"run-780","output":"You saved the Chrome Industries “Cohesive 2.0 38L Pack.”\\n\\nIt’s a 38-liter backpack with dual main compartments, a padded laptop sleeve, recycled/PFAS-free materials, and a lifetime warranty.\\n\\nhttps://chromeindustries.com/products/cohesive-2-0-38l-pack?variant=43962733953084"}

                """
            } else {
                body = """
                data: {"event":"run.completed","run_id":"run-780","output":"Hi"}

                """
            }
        case ("GET", "/v1/runs/run-780"):
            status = 200
            contentType = "application/json"
            if url.host == "cancelled.invalid" {
                body = #"{"object":"run","run_id":"run-780","status":"cancelled","session_id":"session-780"}"#
            } else if url.host == "backpack.invalid" {
                body = #"{"object":"hermes.run","run_id":"run-780","status":"completed","session_id":"session-780","output":"You saved the Chrome Industries “Cohesive 2.0 38L Pack.”\n\nIt’s a 38-liter backpack with dual main compartments, a padded laptop sleeve, recycled/PFAS-free materials, and a lifetime warranty.\n\nhttps://chromeindustries.com/products/cohesive-2-0-38l-pack?variant=43962733953084","usage":{"input_tokens":126640,"output_tokens":383,"total_tokens":127023},"last_event":"run.completed"}"#
            } else {
                body = #"{"object":"run","run_id":"run-780","status":"completed","session_id":"session-780","output":"Hi","cider_references":[{"kind":"task","id":"card-780","title":"Transport-backed task","board_id":"board-780","source":"cider","source_ref":"kanban_card:board-780/card-780"}]}"#
            }
        default:
            status = 404
            contentType = "application/json"
            body = #"{"error":"unexpected request"}"#
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
