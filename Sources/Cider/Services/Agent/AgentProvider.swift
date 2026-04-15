import Foundation

// MARK: - Agent Provider Protocol

/// Protocol for AI backends. Providers generate responses and may request tool calls.
/// The orchestrator owns tool execution, permissions, and retry logic — providers just
/// report what tools they want to call.
protocol AgentProvider: Sendable {
    var isAvailable: Bool { get }
    var displayName: String { get }
    var capabilities: AgentProviderCapabilities { get }

    /// Generate a response. May include tool call requests.
    func generate(
        systemPrompt: String,
        messages: [AgentMessage],
        tools: [AgentToolDefinition]
    ) async throws -> AgentProviderResponse

    /// Streaming variant for UI display.
    func streamGenerate(
        systemPrompt: String,
        messages: [AgentMessage],
        tools: [AgentToolDefinition]
    ) -> AsyncThrowingStream<AgentProviderStreamEvent, Error>

    /// Reset conversation state.
    func resetSession()
}

// MARK: - Provider Capabilities

struct AgentProviderCapabilities: Sendable {
    let supportsToolCalling: Bool
    let supportsStreaming: Bool
    let maxContextTokens: Int
    let estimatedTokensPerChar: Double

    static let appleIntelligence = AgentProviderCapabilities(
        supportsToolCalling: true, supportsStreaming: true,
        maxContextTokens: 4096, estimatedTokensPerChar: 0.25
    )

    static let mlxLocal = AgentProviderCapabilities(
        supportsToolCalling: true, supportsStreaming: true,
        maxContextTokens: 32000, estimatedTokensPerChar: 0.25
    )

    static let claudeAPI = AgentProviderCapabilities(
        supportsToolCalling: true, supportsStreaming: true,
        maxContextTokens: 200000, estimatedTokensPerChar: 0.25
    )

    static let openAIAPI = AgentProviderCapabilities(
        supportsToolCalling: true, supportsStreaming: true,
        maxContextTokens: 128000, estimatedTokensPerChar: 0.25
    )

    static let geminiAPI = AgentProviderCapabilities(
        supportsToolCalling: true, supportsStreaming: true,
        maxContextTokens: 1000000, estimatedTokensPerChar: 0.25
    )
}

// MARK: - Provider Response

struct AgentProviderResponse: Sendable {
    let text: String
    let toolRequests: [AgentToolRequest]

    static func text(_ text: String) -> AgentProviderResponse {
        AgentProviderResponse(text: text, toolRequests: [])
    }
}

struct AgentToolRequest: Sendable {
    let name: String
    let arguments: [String: String]
}

// MARK: - Stream Events

enum AgentProviderStreamEvent: Sendable {
    case textDelta(String)
    case toolCallRequest(AgentToolRequest)
    case done(AgentProviderResponse)
}
