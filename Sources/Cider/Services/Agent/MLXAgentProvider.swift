import Foundation
import os.log

/// Adapter wrapping the MLX local model for the AgentProvider protocol.
///
/// Unlike the old MLXProvider which ran its own tool loop internally, this adapter
/// returns parsed tool requests to the orchestrator and lets IT handle execution.
/// Tool results come back as AgentMessage.toolResult entries, which we convert to
/// `<tool_response>` blocks that Qwen expects.
///
/// All model access is dispatched to MainActor. The class itself is nonisolated
/// + @unchecked Sendable so it can conform to AgentProvider.
final class MLXAgentProvider: @unchecked Sendable, AgentProvider {
    private let logger = Logger(subsystem: "com.cider.app", category: "MLXAgentProvider")

    /// Rough token budget. Qwen 2.5 has 32K context; reserve space for output.
    private let maxContextTokens = 28_000

    // MARK: - AgentProvider

    var isAvailable: Bool {
        MLXModelManager.isLocalModelEnabledStatic
    }

    var displayName: String {
        "Local AI (Qwen 2.5)"
    }

    var capabilities: AgentProviderCapabilities { .mlxLocal }

    func generate(
        systemPrompt: String,
        messages: [AgentMessage],
        tools: [AgentToolDefinition]
    ) async throws -> AgentProviderResponse {
        try await generateOnMainActor(
            systemPrompt: systemPrompt,
            messages: messages,
            tools: tools
        )
    }

    @MainActor
    private func generateOnMainActor(
        systemPrompt: String,
        messages: [AgentMessage],
        tools: [AgentToolDefinition]
    ) async throws -> AgentProviderResponse {
        let modelManager = MLXModelManager.shared

        if !modelManager.isModelLoaded {
            await modelManager.loadModel()
        }
        guard modelManager.isModelLoaded else {
            throw AgentError.providerUnavailable
        }

        let chatMessages = buildChatMessages(
            systemPrompt: systemPrompt,
            messages: messages,
            tools: tools
        )

        let response = try await modelManager.generate(messages: chatMessages)
        let toolCalls = parseToolCalls(from: response)

        if toolCalls.isEmpty {
            return .text(cleanResponse(response))
        }

        // Return tool requests for the orchestrator to execute
        let requests = toolCalls.map { call in
            AgentToolRequest(
                name: call.name,
                arguments: call.arguments.compactMapValues { value in
                    if let str = value as? String { return str }
                    if let num = value as? NSNumber { return num.stringValue }
                    return "\(value)"
                }
            )
        }

        let textPortion = cleanResponse(response)
        return AgentProviderResponse(text: textPortion, toolRequests: requests)
    }

    func streamGenerate(
        systemPrompt: String,
        messages: [AgentMessage],
        tools: [AgentToolDefinition]
    ) -> AsyncThrowingStream<AgentProviderStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // MLX doesn't have true streaming with tool detection,
                    // so we generate the full response then emit it
                    let response = try await self.generate(
                        systemPrompt: systemPrompt,
                        messages: messages,
                        tools: tools
                    )

                    if !response.text.isEmpty {
                        continuation.yield(.textDelta(response.text))
                    }

                    for request in response.toolRequests {
                        continuation.yield(.toolCallRequest(request))
                    }

                    continuation.yield(.done(response))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func resetSession() {
        // No persistent state — full message history is passed each time
    }

    // MARK: - Message Conversion

    /// Convert AgentMessages into the chat format MLXModelManager expects,
    /// including tool schemas in the system prompt and tool results as
    /// `<tool_response>` blocks.
    private func buildChatMessages(
        systemPrompt: String,
        messages: [AgentMessage],
        tools: [AgentToolDefinition]
    ) -> [[String: String]] {
        let toolDocs = buildToolDocs(tools: tools)
        let fullSystemPrompt = """
        \(systemPrompt)

        # Tools

        You have access to tools to query and modify the user's data. Available tools:
        \(toolDocs)

        IMPORTANT: When you need to access or modify user data, you MUST call a tool. \
        Output EXACTLY this format (do NOT output anything else before the tool call):
        <tool_call>
        {"name": "toolName", "arguments": {"param": "value"}}
        </tool_call>

        Rules:
        - ALWAYS use tools to get real data. NEVER guess or make up numbers.
        - After receiving a <tool_response>, write a natural response using that data.
        - If the user asks about their items, counts, or data, call the appropriate tool FIRST.
        - Do NOT include raw JSON in your final response to the user.
        """

        var chatMessages: [[String: String]] = [
            ["role": "system", "content": fullSystemPrompt]
        ]

        // Token budget tracking
        let systemTokens = estimateTokens(fullSystemPrompt)
        var budgetUsed = systemTokens

        // Reserve space for the last user message
        let lastUserMessage = messages.last(where: { $0.role == .user })
        let lastUserTokens = estimateTokens(lastUserMessage?.content ?? "")
        budgetUsed += lastUserTokens

        // Fill history from most recent backwards, converting tool results
        let history = lastUserMessage != nil ? Array(messages.dropLast()) : messages
        var historyMessages: [[String: String]] = []

        for msg in history.suffix(20).reversed() {
            let content: String
            let role: String

            switch msg.role {
            case .user:
                role = "user"
                content = msg.content
            case .assistant:
                role = "assistant"
                content = msg.content
            case .toolResult:
                role = "user"
                content = "<tool_response>\n\(msg.content)\n</tool_response>"
            }

            let msgTokens = estimateTokens(content)
            if budgetUsed + msgTokens > maxContextTokens {
                logger.info("Context budget reached, trimming older history")
                break
            }
            budgetUsed += msgTokens
            historyMessages.insert(["role": role, "content": content], at: 0)
        }

        chatMessages.append(contentsOf: historyMessages)

        if let lastUserMessage {
            chatMessages.append(["role": "user", "content": lastUserMessage.content])
        }

        return chatMessages
    }

    /// Build JSON tool documentation from AgentToolDefinitions.
    private func buildToolDocs(tools: [AgentToolDefinition]) -> String {
        var toolsArray: [[String: Any]] = []
        for tool in tools {
            var properties: [String: Any] = [:]
            var required: [String] = []
            for param in tool.parameters {
                properties[param.name] = [
                    "type": param.type.rawValue,
                    "description": param.description,
                ]
                if param.required {
                    required.append(param.name)
                }
            }
            toolsArray.append([
                "name": tool.name,
                "description": tool.description,
                "parameters": [
                    "type": "object",
                    "properties": properties,
                    "required": required,
                ],
            ])
        }

        guard let data = try? JSONSerialization.data(withJSONObject: toolsArray, options: .prettyPrinted),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return jsonString
    }

    // MARK: - Token Estimation

    private func estimateTokens(_ text: String) -> Int {
        (text.count + 3) / 4
    }

    // MARK: - Tool Call Parsing

    private struct ParsedToolCall {
        let name: String
        let arguments: [String: Any]
    }

    /// Parses tool calls from the model's output.
    /// Supports `<tool_call>{"name":...}</tool_call>` and bare JSON fallback.
    private func parseToolCalls(from response: String) -> [ParsedToolCall] {
        var calls: [ParsedToolCall] = []

        let wrappedPattern = #"<tool_call>\s*(\{.*?\})\s*</tool_call>"#
        if let regex = try? NSRegularExpression(pattern: wrappedPattern, options: .dotMatchesLineSeparators) {
            let nsRange = NSRange(response.startIndex..., in: response)
            let matches = regex.matches(in: response, range: nsRange)
            for match in matches {
                if let call = parseToolCallJSON(from: response, range: match.range(at: 1)) {
                    calls.append(call)
                }
            }
        }

        if calls.isEmpty {
            let barePattern = #"\{\s*"name"\s*:\s*"(\w+)"\s*,\s*"arguments"\s*:\s*\{[^}]*\}\s*\}"#
            if let regex = try? NSRegularExpression(pattern: barePattern, options: .dotMatchesLineSeparators) {
                let nsRange = NSRange(response.startIndex..., in: response)
                let matches = regex.matches(in: response, range: nsRange)
                for match in matches {
                    if let call = parseToolCallJSON(from: response, range: match.range(at: 0)) {
                        calls.append(call)
                    }
                }
            }
        }

        return calls
    }

    private func parseToolCallJSON(from response: String, range: NSRange) -> ParsedToolCall? {
        guard let swiftRange = Range(range, in: response) else { return nil }
        let jsonString = String(response[swiftRange])

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String else {
            logger.warning("Failed to parse tool call JSON: \(jsonString.prefix(200), privacy: .public)")
            return nil
        }

        let arguments = json["arguments"] as? [String: Any] ?? [:]
        return ParsedToolCall(name: name, arguments: arguments)
    }

    /// Remove tool call markup from the response, returning only natural language.
    private func cleanResponse(_ response: String) -> String {
        var cleaned = response

        if let regex = try? NSRegularExpression(
            pattern: #"<tool_call>\s*\{.*?\}\s*</tool_call>"#,
            options: .dotMatchesLineSeparators
        ) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }

        if let regex = try? NSRegularExpression(
            pattern: #"\{\s*"name"\s*:\s*"\w+"\s*,\s*"arguments"\s*:\s*\{[^}]*\}\s*\}"#,
            options: .dotMatchesLineSeparators
        ) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Static Availability Check

extension MLXModelManager {
    /// Non-MainActor check for whether local model is enabled.
    /// Reads from UserDefaults which is thread-safe.
    nonisolated static var isLocalModelEnabledStatic: Bool {
        UserDefaults.standard.bool(forKey: "cider.mlxModelEnabled")
    }
}
