import Foundation
import FoundationModels
import os.log

/// AI assistant backend using Apple's on-device Foundation Models.
@MainActor
final class FoundationModelsProvider: AIAssistantProvider {
    private let logger = Logger(subsystem: "com.cider.app", category: "FoundationModelsProvider")
    private var session: LanguageModelSession?

    /// Approximate token usage as a fraction of the context window (0.0–1.0).
    private(set) var contextUsage: Double = 0

    /// Context window size (4096 tokens for Apple's on-device model).
    private let contextWindowSize = 4096

    /// Summarize when usage exceeds this fraction.
    private let summarizationThreshold = 0.70

    /// All tools the AI can call to query or act on Cider's data.
    private let tools: [any Tool] = [
        // Read tools
        CountItemsTool(),
        SearchItemsTool(),
        ListFoldersTool(),
        ListTagsTool(),
        GetRecentItemsTool(),
        GetItemsByTagTool(),
        GetUpcomingEventsTool(),
        GetOverdueTodosTool(),
        GetFolderContentsTool(),
        FindSimilarTool(),
        // Write tools
        CreateFolderTool(),
        MoveToFolderTool(),
        ApplyTagTool(),
        RemoveTagTool(),
        RenameBookmarkTool(),
        CreateNoteTool(),
        SummarizeTextTool(),
        AddBookmarkTool(),
        GetCurrentItemTool(),
        DeleteItemTool(),
        RenameFolderTool(),
        UnfileItemsTool()
    ]

    var isAvailable: Bool {
        AIAvailability.isFoundationModelsAvailable
    }

    var displayName: String { "Apple Intelligence" }

    private func getOrCreateSession(context: AIAssistantContext) -> LanguageModelSession {
        if let existing = session { return existing }
        let instructions = buildInstructions(context: context)
        let s = LanguageModelSession(
            tools: tools,
            instructions: instructions
        )
        session = s
        contextUsage = 0
        return s
    }

    /// Reset the session (called when conversation is cleared).
    func resetSession() {
        session = nil
        contextUsage = 0
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

                var activeSession = getOrCreateSession(context: context)

                // Check if we need to summarize before sending
                if contextUsage >= summarizationThreshold {
                    logger.info("Context at \(Int(self.contextUsage * 100))% — summarizing conversation")
                    if let refreshed = await self.summarizeAndReset(
                        messages: messages,
                        context: context
                    ) {
                        activeSession = refreshed
                    }
                }

                do {
                    let prompt = lastUserMessage.content
                    let stream = activeSession.streamResponse(to: prompt)
                    var previousContent = ""
                    for try await partial in stream {
                        let fullText = partial.content
                        if fullText.count > previousContent.count {
                            let newText = String(fullText.dropFirst(previousContent.count))
                            continuation.yield(newText)
                            previousContent = fullText
                        }
                    }

                    // Update context usage estimate after response
                    await self.updateContextUsage()

                    continuation.finish()
                } catch {
                    // If context exceeded, try to recover
                    if "\(error)".contains("exceededContextWindowSize") {
                        logger.warning("Context window exceeded — resetting session")
                        if let refreshed = await self.summarizeAndReset(
                            messages: messages,
                            context: context
                        ) {
                            // Retry with fresh session
                            do {
                                let retryStream = refreshed.streamResponse(to: lastUserMessage.content)
                                var prev = ""
                                for try await partial in retryStream {
                                    let fullText = partial.content
                                    if fullText.count > prev.count {
                                        continuation.yield(String(fullText.dropFirst(prev.count)))
                                        prev = fullText
                                    }
                                }
                                await self.updateContextUsage()
                                continuation.finish()
                                return
                            } catch {
                                logger.error("Retry after summarization failed: \(error.localizedDescription, privacy: .public)")
                            }
                        }
                    }

                    logger.error("Foundation Models stream error: \(error.localizedDescription, privacy: .public)")
                    session = nil
                    contextUsage = 0
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Context Management

    /// Estimate current context usage from transcript character count.
    private func updateContextUsage() async {
        guard let session else { contextUsage = 0; return }

        // Use character count heuristic: ~4 chars per token
        var charCount = 0
        for entry in session.transcript {
            switch entry {
            case .instructions(let inst):
                for segment in inst.segments {
                    if case .text(let t) = segment { charCount += t.content.count }
                }
            case .prompt(let p):
                for segment in p.segments {
                    if case .text(let t) = segment { charCount += t.content.count }
                }
            case .response(let r):
                for segment in r.segments {
                    if case .text(let t) = segment { charCount += t.content.count }
                }
            default:
                charCount += 200 // rough estimate for tool calls/output
            }
        }

        let estimatedTokens = charCount / 4
        // Add ~1450 tokens for tool definitions (23 tools × ~63 tokens each)
        let totalEstimate = estimatedTokens + 1450
        contextUsage = min(1.0, Double(totalEstimate) / Double(contextWindowSize))
    }

    /// Summarize the conversation and create a fresh session with the summary.
    private func summarizeAndReset(
        messages: [AIAssistantMessage],
        context: AIAssistantContext
    ) async -> LanguageModelSession? {
        // Build a summary of the conversation so far
        let conversationText = messages.map { msg in
            let role = msg.role == .user ? "User" : "AI"
            return "\(role): \(msg.content)"
        }.joined(separator: "\n")

        // Use a separate session to summarize
        let summarizer = LanguageModelSession(instructions: """
        Summarize this conversation in 2-3 sentences, capturing the key topics \
        discussed and any actions taken. Be concise.
        """)

        let summary: String
        do {
            let response = try await summarizer.respond(to: conversationText)
            summary = response.content
        } catch {
            logger.error("Summarization failed: \(error.localizedDescription, privacy: .public)")
            // Fall back to just resetting with no summary
            session = nil
            contextUsage = 0
            return getOrCreateSession(context: context)
        }

        // Create fresh session with summary as context
        var instructions = buildInstructions(context: context)
        instructions += "\n\nConversation summary so far:\n\(summary)"

        let freshSession = LanguageModelSession(
            tools: tools,
            instructions: instructions
        )
        session = freshSession
        contextUsage = 0.15 // summary uses some context
        logger.info("Session refreshed with conversation summary")
        return freshSession
    }

    // MARK: - Prompt Building

    private func buildInstructions(context: AIAssistantContext) -> String {
        var instructions = """
        You are a helpful assistant built into Cider, a macOS app for managing \
        bookmarks, notes, events, todos, contacts, and projects.

        Rules:
        - Always use tools to answer questions about the user's data. Never guess.
        - When the user says "this", "this bookmark", "this note", etc., use \
        getCurrentItem to find what they're viewing.
        - For multi-step requests like "find X and move it to Y", use searchItems \
        first, then the appropriate action tool.
        - Be concise. Present tool results clearly without repeating raw data.
        - If a tool returns no results, say so honestly.
        - When creating or modifying items, confirm what you did.
        - Use markdown formatting (bold, lists) for readability.
        """

        let contextDesc = context.contextDescription
        if !contextDesc.isEmpty {
            instructions += "\n\nThe user is currently viewing:\n\(contextDesc)"
        }

        return instructions
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
