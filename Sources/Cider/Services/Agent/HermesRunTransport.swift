import Foundation

struct HermesRunTransport: HermesBridgeTransport {
    let apiClient: HermesAPIClient
    let fallbackService: HermesSessionService

    init(
        apiClient: HermesAPIClient = HermesAPIClient(),
        fallbackService: HermesSessionService = HermesSessionService()
    ) {
        self.apiClient = apiClient
        self.fallbackService = fallbackService
    }

    func availability() async -> HermesBridgeAvailability {
        do {
            _ = try await apiClient.capabilities()
            return .apiRuns
        } catch {
            return .cliFallback
        }
    }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)? = nil
    ) async throws -> HermesBridgeSendResult {
        let capabilities: HermesAPICapabilities
        do {
            capabilities = try await apiClient.capabilities()
        } catch {
            let result = try await fallbackService.send(
                text: text,
                state: state,
                existingMessages: existingMessages
            )
            return HermesBridgeSendResult(completion: HermesRunCompletionEnvelope(
                provenance: .cliFallback,
                runID: nil,
                terminalStatus: .unknown,
                observedFacts: observedContentFacts(in: result.messages),
                finalSessionSynchronizationComplete: true,
                finalMessages: result.messages,
                finalState: result.state,
                modelIdentity: nil,
                terminalSourceEvidence: terminalSourceEvidence(
                    reportedTerminalRunID: nil,
                    messages: result.messages
                )
            ))
        }
        return try await sendWithRunsAPI(
            text: text,
            state: state,
            existingMessages: existingMessages,
            modelIdentity: capabilities.model,
            onEvent: onEvent
        )
    }

    func stop(runID: String) async throws {
        try await apiClient.stopRun(runID: runID)
    }

    private func sendWithRunsAPI(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        modelIdentity: String,
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        let created = try await apiClient.createRun(input: text, sessionID: state.activeRuntimeSessionID)
        var snapshot = HermesRunSnapshot(status: .running(runID: created.runID), visibleText: "", toolSummary: nil)
        var observed = HermesRunObservationAccumulator(runID: created.runID)
        observed.recordInitialStatus(created.status)
        await onEvent?(.runStarted(created.runID))

        let stream = apiClient.runEvents(runID: created.runID)
        for try await event in stream {
            observed.record(event)
            guard let bridgeEvent = event.bridgeEvent else { continue }
            snapshot = snapshot.reducing(bridgeEvent)
            await onEvent?(bridgeEvent)
        }

        let status = try await apiClient.runStatus(runID: created.runID)
        switch status.status {
        case "completed":
            let output = status.output ?? snapshot.visibleText
            if snapshot.visibleText.isEmpty || snapshot.visibleText != output {
                let event = HermesRunEvent.completed(output: output)
                snapshot = snapshot.reducing(event)
                await onEvent?(event)
            }

            let now = Date()
            let userMessage = AIAssistantMessage(
                role: .user,
                content: text,
                timestamp: now,
                sourceID: "hermes-run:\(created.runID):user",
                sourceSessionID: status.sessionID ?? state.activeRuntimeSessionID,
                sourceName: "Hermes"
            )
            let assistantMessage = AIAssistantMessage(
                role: .assistant,
                content: snapshot.visibleText,
                timestamp: now,
                sourceID: "hermes-run:\(created.runID):assistant",
                sourceSessionID: status.sessionID ?? state.activeRuntimeSessionID,
                sourceName: "Hermes"
            )

            var nextState = state
            if let sessionID = status.sessionID, !sessionID.isEmpty {
                nextState.activeRuntimeSessionID = sessionID
                if !nextState.runtimeSessionLineage.contains(sessionID) {
                    nextState.runtimeSessionLineage.append(sessionID)
                }
            }
            nextState.lastSyncedAt = now
            nextState.lastSyncedMessageID = assistantMessage.sourceID
            nextState.lastSyncedTimestamp = assistantMessage.timestamp
            nextState.lastImportedRuntimeSessionID = assistantMessage.sourceSessionID

            let finalMessages = existingMessages + [userMessage, assistantMessage]
            let observedFacts = observed.finalized(
                messages: finalMessages,
                terminalRunID: status.runID
            )
            let sessionSyncComplete = status.sessionID?.isEmpty == false &&
                nextState.activeRuntimeSessionID == status.sessionID &&
                nextState.runtimeSessionLineage.last == status.sessionID &&
                nextState.lastSyncedMessageID == assistantMessage.sourceID &&
                nextState.lastSyncedTimestamp == assistantMessage.timestamp &&
                nextState.lastImportedRuntimeSessionID == status.sessionID
            let approvalFacts = resolvedApprovalFacts(status: status, observed: observed)
            let contextFacts = resolvedContextFacts(status: status, observed: observed)
            return HermesBridgeSendResult(completion: HermesRunCompletionEnvelope(
                provenance: .hermesRunsAPI,
                runID: created.runID,
                terminalStatus: .completed,
                observedFacts: observedFacts,
                finalSessionSynchronizationComplete: sessionSyncComplete,
                finalMessages: finalMessages,
                finalState: nextState,
                modelIdentity: modelIdentity,
                terminalSourceEvidence: terminalSourceEvidence(
                    reportedTerminalRunID: status.runID,
                    messages: finalMessages
                ),
                ciderReferences: status.ciderReferences,
                contextCheckpointFactState: contextFacts.state,
                contextCheckpoint: contextFacts.checkpoint,
                approvalFactState: approvalFacts.state,
                approvalRequests: approvalFacts.requests
            ))
        case "cancelled":
            await onEvent?(.cancelled)
            throw CancellationError()
        default:
            let message = status.error ?? "Hermes run \(status.status)"
            await onEvent?(.failed(message))
            throw HermesSessionClientError.hermesCommandFailed(message)
        }
    }

    private func observedContentFacts(in messages: [AIAssistantMessage]) -> HermesRunObservedFacts {
        let attachment = messages.contains { !$0.attachments.isEmpty }
        let pending = messages.contains { $0.sourceID?.hasPrefix("hermes:pending:") == true }
        let streaming = messages.contains { $0.sourceID?.hasPrefix("hermes-live:") == true }
        return HermesRunObservedFacts(
            containedToolEvent: false,
            containedReasoningEvent: false,
            containedApprovalEvent: false,
            containedAttachmentContentOrEvent: attachment,
            containedPendingContentOrEvent: pending,
            containedStreamingContentOrEvent: streaming,
            runIdentityConsistent: true
        )
    }

    private func terminalSourceEvidence(
        reportedTerminalRunID: String?,
        messages: [AIAssistantMessage]
    ) -> HermesTerminalSourceIdentityEvidence {
        let user = messages.dropLast().last
        let assistant = messages.last
        return HermesTerminalSourceIdentityEvidence(
            reportedTerminalRunID: reportedTerminalRunID,
            userSourceID: user?.role == .user ? user?.sourceID : nil,
            assistantSourceID: assistant?.role == .assistant ? assistant?.sourceID : nil,
            userSourceSessionID: user?.role == .user ? user?.sourceSessionID : nil,
            assistantSourceSessionID: assistant?.role == .assistant ? assistant?.sourceSessionID : nil
        )
    }

    private func resolvedApprovalFacts(
        status: HermesRunStatusResponse,
        observed: HermesRunObservationAccumulator
    ) -> (state: HermesStructuredFactState, requests: [HermesApprovalRequest]) {
        if status.approvalFactState != .notReported {
            return (status.approvalFactState, status.approvalRequests)
        }
        return observed.approvalProjection()
    }

    private func resolvedContextFacts(
        status: HermesRunStatusResponse,
        observed: HermesRunObservationAccumulator
    ) -> (state: HermesStructuredFactState, checkpoint: HermesCiderContextCheckpoint?) {
        if status.contextCheckpointFactState != .notReported {
            return (status.contextCheckpointFactState, status.contextCheckpoint)
        }
        return observed.contextProjection()
    }
}

struct HermesRunObservationAccumulator {
    let runID: String
    private(set) var containedToolEvent = false
    private(set) var containedReasoningEvent = false
    private(set) var containedApprovalEvent = false
    private(set) var containedAttachmentEvent = false
    private(set) var containedPendingEvent = false
    private(set) var containedStreamingEvent = false
    private(set) var runIdentityConsistent = true
    private var approvalFactState: HermesStructuredFactState = .notReported
    private var approvalsByID: [String: HermesApprovalRequest] = [:]
    private var contextCheckpointFactState: HermesStructuredFactState = .notReported
    private var contextCheckpoint: HermesCiderContextCheckpoint?

    init(runID: String) {
        self.runID = runID
    }

    mutating func recordInitialStatus(_ status: String) {
        if status == "pending" || status == "queued" { containedPendingEvent = true }
        if status == "streaming" { containedStreamingEvent = true }
        if status == "failed" || status == "cancelled" || status == "disconnected" {
            runIdentityConsistent = false
        }
    }

    mutating func record(_ event: HermesRunSSEEvent) {
        if let eventRunID = event.runID, eventRunID != runID {
            runIdentityConsistent = false
        }
        if event.event.hasPrefix("tool.") { containedToolEvent = true }
        if event.event.hasPrefix("reasoning.") { containedReasoningEvent = true }
        if event.event.hasPrefix("approval.") {
            containedApprovalEvent = true
            recordApproval(event)
        }
        if event.event.hasPrefix("context.") || event.contextCheckpointFactState != .notReported {
            recordContext(event)
        }
        if event.event.contains("attachment") { containedAttachmentEvent = true }
        if event.event.contains("pending") || event.status == "pending" || event.status == "queued" {
            containedPendingEvent = true
        }
        if event.event == "message.delta" || event.event.contains("stream") || event.status == "streaming" {
            containedStreamingEvent = true
        }
        if event.event == "run.failed" || event.event == "run.cancelled" {
            runIdentityConsistent = false
        }
    }

    func finalized(
        messages: [AIAssistantMessage],
        terminalRunID: String?
    ) -> HermesRunObservedFacts {
        HermesRunObservedFacts(
            containedToolEvent: containedToolEvent,
            containedReasoningEvent: containedReasoningEvent,
            containedApprovalEvent: containedApprovalEvent,
            containedAttachmentContentOrEvent: containedAttachmentEvent || messages.contains { !$0.attachments.isEmpty },
            containedPendingContentOrEvent: containedPendingEvent || messages.contains { $0.sourceID?.hasPrefix("hermes:pending:") == true },
            containedStreamingContentOrEvent: containedStreamingEvent || messages.contains { $0.sourceID?.hasPrefix("hermes-live:") == true },
            runIdentityConsistent: runIdentityConsistent && terminalRunID == runID
        )
    }

    func approvalProjection() -> (state: HermesStructuredFactState, requests: [HermesApprovalRequest]) {
        let requests = approvalsByID.values.sorted { $0.id < $1.id }
        return (approvalFactState, approvalFactState == .validated ? requests : [])
    }

    func contextProjection() -> (state: HermesStructuredFactState, checkpoint: HermesCiderContextCheckpoint?) {
        (contextCheckpointFactState, contextCheckpointFactState == .validated ? contextCheckpoint : nil)
    }

    private mutating func recordApproval(_ event: HermesRunSSEEvent) {
        guard approvalFactState != .rejected,
              event.approvalFactState == .validated,
              let request = event.approval
        else {
            approvalFactState = .rejected
            approvalsByID.removeAll()
            return
        }
        if let existing = approvalsByID[request.id], !sameRequest(existing, request) {
            approvalFactState = .rejected
            approvalsByID.removeAll()
            return
        }
        guard approvalsByID[request.id] != nil || approvalsByID.count < 8 else {
            approvalFactState = .rejected
            approvalsByID.removeAll()
            return
        }
        approvalFactState = .validated
        approvalsByID[request.id] = request
    }

    private func sameRequest(_ lhs: HermesApprovalRequest, _ rhs: HermesApprovalRequest) -> Bool {
        lhs.id == rhs.id && lhs.action == rhs.action && lhs.target == rhs.target &&
            lhs.risk == rhs.risk && lhs.scope == rhs.scope && lhs.source == rhs.source &&
            lhs.sourceRef == rhs.sourceRef
    }

    private mutating func recordContext(_ event: HermesRunSSEEvent) {
        guard contextCheckpointFactState != .rejected,
              event.contextCheckpointFactState == .validated,
              let checkpoint = event.contextCheckpoint,
              contextCheckpoint == nil || contextCheckpoint == checkpoint
        else {
            contextCheckpointFactState = .rejected
            contextCheckpoint = nil
            return
        }
        contextCheckpointFactState = .validated
        contextCheckpoint = checkpoint
    }
}
