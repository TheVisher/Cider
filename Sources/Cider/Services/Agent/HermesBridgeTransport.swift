import Foundation

enum HermesBridgeAvailability: Equatable, Sendable {
    case apiRuns
    case cliFallback
    case unavailable(String)
}

enum HermesRunStatus: Equatable, Sendable {
    case queued
    case running(runID: String)
    case waitingForApproval(String?)
    case completed(String)
    case failed(String)
    case cancelled
}

enum HermesRunEvent: Equatable, Sendable {
    case runStarted(String)
    case messageDelta(String)
    case toolStarted(name: String?, preview: String?)
    case toolCompleted(name: String?, isError: Bool)
    case reasoningAvailable(String)
    case completed(output: String)
    case failed(String)
    case cancelled
}

struct HermesRunSnapshot: Equatable, Sendable {
    var status: HermesRunStatus
    var visibleText: String
    var toolSummary: String?

    static let empty = HermesRunSnapshot(status: .queued, visibleText: "", toolSummary: nil)

    func reducing(_ event: HermesRunEvent) -> HermesRunSnapshot {
        var next = self
        switch event {
        case .runStarted(let runID):
            next.status = .running(runID: runID)
        case .messageDelta(let delta):
            next.visibleText += delta
        case .toolStarted(let name, let preview):
            next.toolSummary = preview ?? name
        case .toolCompleted(let name, let isError):
            if isError {
                next.toolSummary = "\(name ?? "Tool") failed"
            }
        case .reasoningAvailable:
            break
        case .completed(let output):
            next.status = .completed(output)
            if next.visibleText.isEmpty {
                next.visibleText = output
            }
        case .failed(let message):
            next.status = .failed(message)
        case .cancelled:
            next.status = .cancelled
        }
        return next
    }
}

struct HermesBridgeSendResult: Sendable {
    let state: HermesConversationState
    let messages: [AIAssistantMessage]
}

protocol HermesBridgeTransport: Sendable {
    func availability() async -> HermesBridgeAvailability
    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult
    func stop(runID: String) async throws
}

extension HermesBridgeTransport {
    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage]
    ) async throws -> HermesBridgeSendResult {
        try await send(text: text, state: state, existingMessages: existingMessages, onEvent: nil)
    }
}

actor HermesTurnCoordinator {
    static let shared = HermesTurnCoordinator()

    private var activeTurnID: UUID?

    func beginTurn() throws -> UUID {
        if activeTurnID != nil {
            throw HermesSessionClientError.hermesCommandFailed("Hermes is already handling a Cider message")
        }
        let id = UUID()
        activeTurnID = id
        return id
    }

    func endTurn(_ id: UUID) {
        guard activeTurnID == id else { return }
        activeTurnID = nil
    }
}
