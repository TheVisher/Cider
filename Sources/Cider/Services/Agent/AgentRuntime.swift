import Foundation

// MARK: - Agent Runtime

/// Top-level abstraction for any backend Cider can use as "the agent".
/// This keeps channel ownership in Cider while allowing the backend to be
/// a model adapter today and a process-backed runtime later.
protocol AgentRuntime: Sendable {
    var id: String { get }
    var displayName: String { get }
    var kind: AgentRuntimeKind { get }
    var capabilities: AgentRuntimeCapabilities { get }

    func start() async throws
    func stop() async
    func health() async -> AgentRuntimeHealth
    func send(_ request: AgentRuntimeRequest) async throws -> AgentRuntimeResponse
    func stream(_ request: AgentRuntimeRequest) -> AsyncThrowingStream<AgentRuntimeEvent, Error>
    func resetThread(_ threadID: UUID) async
}

enum AgentRuntimeKind: String, Sendable {
    case model
    case process
}

struct AgentRuntimeCapabilities: Sendable {
    let supportsToolCalling: Bool
    let supportsStreaming: Bool
    let maxContextTokens: Int

    static func from(provider capabilities: AgentProviderCapabilities) -> AgentRuntimeCapabilities {
        AgentRuntimeCapabilities(
            supportsToolCalling: capabilities.supportsToolCalling,
            supportsStreaming: capabilities.supportsStreaming,
            maxContextTokens: capabilities.maxContextTokens
        )
    }
}

struct AgentRuntimeRequest: Sendable {
    let threadID: UUID
    let channel: AgentChannel
    let systemPrompt: String
    let messages: [AgentMessage]
    let tools: [AgentToolDefinition]
}

struct AgentRuntimeResponse: Sendable {
    let text: String
    let toolRequests: [AgentToolRequest]

    static func from(provider response: AgentProviderResponse) -> AgentRuntimeResponse {
        AgentRuntimeResponse(text: response.text, toolRequests: response.toolRequests)
    }
}

enum AgentRuntimeEvent: Sendable {
    case textDelta(String)
    case toolCallRequest(AgentToolRequest)
    case done(AgentRuntimeResponse)
}

enum AgentRuntimeStatus: String, Sendable {
    case idle
    case starting
    case running
    case restarting
    case stopped
    case failed
    case unavailable
}

struct AgentRuntimeHealth: Sendable {
    let status: AgentRuntimeStatus
    let detail: String
    let lastStartedAt: Date?
    let lastActivityAt: Date?
    let lastError: String?

    static let idle = AgentRuntimeHealth(
        status: .idle,
        detail: "Runtime is idle",
        lastStartedAt: nil,
        lastActivityAt: nil,
        lastError: nil
    )
}

extension AgentRuntime {
    func start() async throws {}
    func stop() async {}
    func health() async -> AgentRuntimeHealth { .idle }
}
