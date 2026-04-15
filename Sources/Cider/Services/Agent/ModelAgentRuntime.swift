import Foundation

/// Adapter that keeps the current AgentProvider-backed implementation useful
/// while the app moves to an AgentRuntime-first architecture.
final class ModelAgentRuntime: @unchecked Sendable, AgentRuntime {
    let id: String
    let displayName: String
    let kind: AgentRuntimeKind = .model
    let capabilities: AgentRuntimeCapabilities

    private let provider: any AgentProvider

    init(provider: any AgentProvider, id: String? = nil) {
        self.provider = provider
        self.id = id ?? "model.\(provider.displayName.lowercased().replacingOccurrences(of: " ", with: "-"))"
        self.displayName = provider.displayName
        self.capabilities = .from(provider: provider.capabilities)
    }

    func send(_ request: AgentRuntimeRequest) async throws -> AgentRuntimeResponse {
        let response = try await provider.generate(
            systemPrompt: request.systemPrompt,
            messages: request.messages,
            tools: request.tools
        )
        return .from(provider: response)
    }

    func stream(_ request: AgentRuntimeRequest) -> AsyncThrowingStream<AgentRuntimeEvent, Error> {
        let providerStream = provider.streamGenerate(
            systemPrompt: request.systemPrompt,
            messages: request.messages,
            tools: request.tools
        )

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await event in providerStream {
                        switch event {
                        case .textDelta(let delta):
                            continuation.yield(.textDelta(delta))
                        case .toolCallRequest(let request):
                            continuation.yield(.toolCallRequest(request))
                        case .done(let response):
                            continuation.yield(.done(.from(provider: response)))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func resetThread(_ threadID: UUID) async {
        provider.resetSession()
    }
}
