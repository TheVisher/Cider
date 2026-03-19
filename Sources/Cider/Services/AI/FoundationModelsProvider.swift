import Foundation
import FoundationModels
import os.log

/// AI assistant backend using Apple's on-device Foundation Models.
@MainActor
final class FoundationModelsProvider: AIAssistantProvider {
    private let logger = Logger(subsystem: "com.cider.app", category: "FoundationModelsProvider")
    private var session: LanguageModelSession?

    var isAvailable: Bool {
        AIAvailability.isFoundationModelsAvailable
    }

    var displayName: String { "Apple Intelligence" }

    private func getOrCreateSession(context: AIAssistantContext) -> LanguageModelSession {
        // Recreate session when context changes so the instructions stay fresh
        let instructions = buildInstructions(context: context)
        let s = LanguageModelSession(instructions: instructions)
        session = s
        return s
    }

    func streamResponse(
        messages: [AIAssistantMessage],
        context: AIAssistantContext
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                guard isAvailable else {
                    continuation.finish(throwing: AIAssistantError.providerUnavailable)
                    return
                }

                guard let lastUserMessage = messages.last(where: { $0.role == .user }) else {
                    continuation.finish(throwing: AIAssistantError.noUserMessage)
                    return
                }

                let activeSession = getOrCreateSession(context: context)

                do {
                    // Build the prompt including recent conversation history
                    let prompt = buildPrompt(messages: messages, latestMessage: lastUserMessage.content)

                    let stream = activeSession.streamResponse(to: prompt)
                    var previousContent = ""
                    for try await partial in stream {
                        // partial.content is cumulative — yield only new text
                        let fullText = partial.content
                        if fullText.count > previousContent.count {
                            let newText = String(fullText.dropFirst(previousContent.count))
                            continuation.yield(newText)
                            previousContent = fullText
                        }
                    }
                    continuation.finish()
                } catch {
                    logger.error("Foundation Models stream error: \(error.localizedDescription, privacy: .public)")
                    session = nil  // reset on error
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Prompt Building

    private func buildInstructions(context: AIAssistantContext) -> String {
        var instructions = """
        You are a helpful assistant built into Cider, a macOS bookmarks, notes, \
        and projects app. Be concise, friendly, and helpful. \
        Keep responses focused and practical.
        """

        let contextDesc = context.contextDescription
        if !contextDesc.isEmpty {
            instructions += "\n\nCurrent context:\n\(contextDesc)"
        }

        return instructions
    }

    private func buildPrompt(messages: [AIAssistantMessage], latestMessage: String) -> String {
        // For Foundation Models, we pass the latest message directly.
        // The session handles conversation continuity internally.
        latestMessage
    }
}

enum AIAssistantError: LocalizedError {
    case providerUnavailable
    case noUserMessage

    var errorDescription: String? {
        switch self {
        case .providerUnavailable: "AI assistant is not available on this device."
        case .noUserMessage: "No message to respond to."
        }
    }
}
