import Foundation
import os.log

/// AI assistant backend using a local MLX model (Qwen 3.5).
@MainActor
final class MLXProvider: AIAssistantProvider {
    private let logger = Logger(subsystem: "com.cider.app", category: "MLXProvider")
    private let modelManager = MLXModelManager.shared

    var isAvailable: Bool {
        modelManager.isLocalModelEnabled
    }

    var displayName: String {
        let tier = MLXModelManager.ModelTier(rawValue: modelManager.selectedModelID)
        return tier?.displayName ?? "Local AI (Qwen 3.5)"
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

                guard let lastUserMessage = messages.last(where: { $0.role == .user }) else {
                    continuation.finish(throwing: AIAssistantError.noUserMessage)
                    return
                }

                let systemPrompt = buildSystemPrompt(context: context)
                let prompt = buildConversationPrompt(
                    messages: messages,
                    latestMessage: lastUserMessage.content
                )

                do {
                    let response = try await modelManager.generate(
                        prompt: prompt,
                        systemPrompt: systemPrompt
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

    // MARK: - Prompt Building

    private func buildSystemPrompt(context: AIAssistantContext) -> String {
        var prompt = """
        You are a helpful assistant built into Cider, a macOS app for managing \
        bookmarks, notes, events, todos, contacts, and projects. Be concise, \
        friendly, and accurate. Use markdown formatting for readability.
        """

        let contextDesc = context.contextDescription
        if !contextDesc.isEmpty {
            prompt += "\n\nThe user is currently viewing:\n\(contextDesc)"
        }

        return prompt
    }

    private func buildConversationPrompt(
        messages: [AIAssistantMessage],
        latestMessage: String
    ) -> String {
        // Include recent conversation history for context
        var parts: [String] = []

        // Add last few exchanges (skip the latest which we're responding to)
        let history = messages.dropLast()
        for msg in history.suffix(6) {
            let role = msg.role == .user ? "User" : "Assistant"
            parts.append("\(role): \(msg.content)")
        }

        parts.append("User: \(latestMessage)")
        return parts.joined(separator: "\n\n")
    }
}
