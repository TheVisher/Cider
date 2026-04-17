import Foundation
import os.log

/// AI assistant backend using a local MLX model (Qwen 2.5).
/// Supports prompt-based tool calling: the model outputs `<tool_call>` blocks,
/// we parse and execute them, inject `<tool_response>` results, and re-prompt.
@MainActor
final class MLXProvider: AIAssistantProvider {
    private let logger = Logger(subsystem: "com.cider.app", category: "MLXProvider")
    private let modelManager = MLXModelManager.shared

    /// Maximum tool-call round-trips before returning whatever we have.
    private let maxToolRounds = 3

    /// Rough token budget. Qwen 2.5 has 32K context; reserve space for output.
    private let maxContextTokens = 28_000

    /// Max characters for a single tool result before truncation.
    private let maxToolResultChars = 2_000

    var isAvailable: Bool {
        modelManager.isLocalModelEnabled
    }

    var displayName: String {
        let tier = MLXModelManager.ModelTier(rawValue: modelManager.selectedModelID)
        return tier?.displayName ?? "Local AI (Qwen 2.5)"
    }

    func resetSession() {
        // No persistent state to clear — conversation context comes from messages parameter
    }

    func streamResponse(
        messages: [AIAssistantMessage],
        context: AIAssistantContext
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                // Ensure model is loaded
                if !modelManager.isModelLoaded {
                    await modelManager.loadModel()
                }

                guard modelManager.isModelLoaded else {
                    let error = modelManager.loadError ?? "Model failed to load"
                    continuation.finish(throwing: MLXError.generationFailed(error))
                    return
                }

                guard messages.last(where: { $0.role == .user }) != nil else {
                    continuation.finish(throwing: AIAssistantError.noUserMessage)
                    return
                }

                do {
                    let response = try await generateWithTools(
                        messages: messages,
                        context: context
                    )
                    continuation.yield(response)
                    continuation.finish()
                } catch {
                    logger.error("MLX error: \(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Tool-calling loop

    /// Runs the generate → parse → execute → re-prompt loop.
    private func generateWithTools(
        messages: [AIAssistantMessage],
        context: AIAssistantContext
    ) async throws -> String {
        let systemPrompt = buildSystemPrompt(context: context)

        // Build the initial messages array for the model
        var chatMessages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]

        // Add conversation history, trimming to fit context budget.
        // Start with the latest user message reserved, then fill backwards.
        let lastUser = messages.last(where: { $0.role == .user })
        let systemTokens = estimateTokens(systemPrompt)
        let userTokens = estimateTokens(lastUser?.content ?? "")
        var budgetUsed = systemTokens + userTokens

        let history = messages.dropLast()
        var historyMessages: [[String: String]] = []
        for msg in history.suffix(10).reversed() {
            let content = msg.content
            let msgTokens = estimateTokens(content)
            if budgetUsed + msgTokens > maxContextTokens {
                logger.info("Context budget reached, trimming older history")
                break
            }
            budgetUsed += msgTokens
            let role = msg.role == .user ? "user" : "assistant"
            historyMessages.insert(["role": role, "content": content], at: 0)
        }

        chatMessages.append(contentsOf: historyMessages)

        if let lastUser {
            chatMessages.append(["role": "user", "content": lastUser.content])
        }

        var lastResponse = ""

        for round in 0..<maxToolRounds {
            let response = try await modelManager.generate(messages: chatMessages)
            let toolCalls = parseToolCalls(from: response)

            if toolCalls.isEmpty {
                return cleanResponse(response)
            }

            logger.info("Tool round \(round + 1): \(toolCalls.count) call(s)")

            chatMessages.append(["role": "assistant", "content": response])
            budgetUsed += estimateTokens(response)

            // Execute each tool call, truncate large results, check budget
            for call in toolCalls {
                var result = MLXToolExecutor.execute(name: call.name, arguments: call.arguments)

                // Truncate oversized tool results
                if result.count > maxToolResultChars {
                    let truncated = String(result.prefix(maxToolResultChars))
                    result = truncated + "\n...(truncated)"
                }

                let wrappedResult = "<tool_response>\n\(result)\n</tool_response>"
                let resultTokens = estimateTokens(wrappedResult)

                // If adding this result would blow the budget, skip remaining tools
                if budgetUsed + resultTokens > maxContextTokens {
                    logger.warning("Context budget exhausted during tool round \(round + 1)")
                    chatMessages.append(["role": "user", "content": "<tool_response>\nResults truncated — context limit reached.\n</tool_response>"])
                    break
                }

                budgetUsed += resultTokens
                logger.info("Tool \(call.name, privacy: .public) result: \(result.prefix(100), privacy: .public)")
                chatMessages.append(["role": "user", "content": wrappedResult])
            }

            lastResponse = response
        }

        return cleanResponse(lastResponse)
    }

    // MARK: - Token estimation

    /// Rough token estimate: ~4 characters per token for English text.
    private func estimateTokens(_ text: String) -> Int {
        (text.count + 3) / 4
    }

    // MARK: - Tool call parsing

    private struct ToolCall {
        let name: String
        let arguments: [String: Any]
    }

    /// Parses tool calls from the model's output.
    /// Supports multiple formats:
    /// - `<tool_call>{"name":...}</tool_call>` (instructed format)
    /// - Bare `{"name": "...", "arguments": {...}}` JSON (common fallback)
    private func parseToolCalls(from response: String) -> [ToolCall] {
        var calls: [ToolCall] = []

        // 1. Try <tool_call> wrapped blocks first
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

        // 2. If no wrapped calls found, try bare JSON with "name" and "arguments"
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

    /// Extracts a ToolCall from a JSON substring at the given NSRange.
    private func parseToolCallJSON(from response: String, range: NSRange) -> ToolCall? {
        guard let swiftRange = Range(range, in: response) else { return nil }
        let jsonString = String(response[swiftRange])

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String else {
            logger.warning("Failed to parse tool call JSON: \(jsonString.prefix(200), privacy: .public)")
            return nil
        }

        let arguments = json["arguments"] as? [String: Any] ?? [:]
        return ToolCall(name: name, arguments: arguments)
    }

    /// Removes tool call markup from the response, returning only natural language.
    private func cleanResponse(_ response: String) -> String {
        var cleaned = response

        // Remove <tool_call> wrapped blocks
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

        // Remove bare tool call JSON objects
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

    // MARK: - Prompt Building

    private func buildSystemPrompt(context: AIAssistantContext) -> String {
        var prompt = """
        You are a helpful assistant built into Cider, a macOS app for managing \
        bookmarks, notes, events, todos, contacts, and projects. Be concise, \
        friendly, and accurate. Use markdown formatting for readability.

        # Tools

        You have access to tools to query and modify the user's data. Available tools:
        \(MLXToolDefinitions.allToolsJSON())

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

        prompt += "\n\n\(AgentRoutingInstructions.vaultSaveRoutingDoctrine)"

        let contextDesc = context.contextDescription
        if !contextDesc.isEmpty {
            prompt += "\n\nThe user is currently viewing:\n\(contextDesc)"
        }

        return prompt
    }

    func _buildSystemPromptForTesting(context: AIAssistantContext) -> String {
        buildSystemPrompt(context: context)
    }
}
