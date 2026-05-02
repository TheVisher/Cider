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
        switch await availability() {
        case .apiRuns:
            return try await sendWithRunsAPI(
                text: text,
                state: state,
                existingMessages: existingMessages,
                onEvent: onEvent
            )
        case .cliFallback:
            let result = try await fallbackService.send(
                text: text,
                state: state,
                existingMessages: existingMessages
            )
            return HermesBridgeSendResult(state: result.state, messages: result.messages)
        case .unavailable(let message):
            throw HermesSessionClientError.hermesCommandFailed(message)
        }
    }

    func stop(runID: String) async throws {
        try await apiClient.stopRun(runID: runID)
    }

    private func sendWithRunsAPI(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        let created = try await apiClient.createRun(input: text, sessionID: state.activeRuntimeSessionID)
        var snapshot = HermesRunSnapshot(status: .running(runID: created.runID), visibleText: "", toolSummary: nil)
        await onEvent?(.runStarted(created.runID))

        let stream = apiClient.runEvents(runID: created.runID)
        for try await event in stream {
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

            return HermesBridgeSendResult(
                state: nextState,
                messages: existingMessages + [userMessage, assistantMessage]
            )
        case "cancelled":
            await onEvent?(.cancelled)
            throw CancellationError()
        default:
            let message = status.error ?? "Hermes run \(status.status)"
            await onEvent?(.failed(message))
            throw HermesSessionClientError.hermesCommandFailed(message)
        }
    }
}
