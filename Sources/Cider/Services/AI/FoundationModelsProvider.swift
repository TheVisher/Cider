import Foundation
import FoundationModels
import os.log

/// AI assistant backend using Apple's on-device Foundation Models.
@MainActor
final class FoundationModelsProvider: AIAssistantProvider {
    private let logger = Logger(subsystem: "com.cider.app", category: "FoundationModelsProvider")
    private var session: LanguageModelSession?

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
        GetBrowserSessionsTool(),
        FindSimilarTool(),
        // Write tools
        CreateFolderTool(),
        MoveToFolderTool(),
        ApplyTagTool(),
        RenameBookmarkTool(),
        CreateNoteTool(),
        SummarizeTextTool(),
        AddBookmarkTool()
    ]

    var isAvailable: Bool {
        AIAvailability.isFoundationModelsAvailable
    }

    var displayName: String { "Apple Intelligence" }

    private func getOrCreateSession(context: AIAssistantContext) -> LanguageModelSession {
        let instructions = buildInstructions(context: context)
        let s = LanguageModelSession(
            tools: tools,
            instructions: instructions
        )
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
                    let prompt = lastUserMessage.content

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
                    session = nil
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Prompt Building

    private func buildInstructions(context: AIAssistantContext) -> String {
        var instructions = """
        You are a helpful assistant built into Cider, a macOS app for bookmarks, \
        notes, events, todos, contacts, and projects. You have access to tools that \
        let you look up the user's data. Always use the appropriate tool when the \
        user asks about their items, counts, folders, tags, or schedule. \
        Be concise, friendly, and accurate. When reporting results from tools, \
        present the information clearly. If you don't know something, say so — \
        don't make things up.
        """

        let contextDesc = context.contextDescription
        if !contextDesc.isEmpty {
            instructions += "\n\nCurrent context:\n\(contextDesc)"
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
