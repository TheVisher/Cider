import Foundation
import FoundationModels
import os.log

/// Adapter wrapping FoundationModelsProvider for the AgentProvider protocol.
///
/// Apple's LanguageModelSession handles tool calling internally via @Generable
/// tool structs — we let it keep that behavior. The orchestrator's tool loop is
/// effectively bypassed for this provider since the session manages its own tools.
///
/// All session state is accessed on MainActor via explicit dispatch. The class
/// itself is nonisolated + @unchecked Sendable so it can conform to AgentProvider.
final class FoundationModelsAgentProvider: @unchecked Sendable, AgentProvider {
    private let logger = Logger(subsystem: "com.cider.app", category: "FoundationModelsAgentProvider")

    /// Mutable state guarded by MainActor access.
    @MainActor private var session: LanguageModelSession?
    @MainActor private var contextUsage: Double = 0

    private let contextWindowSize = 4096
    private let summarizationThreshold = 0.70

    /// Same tools as the original FoundationModelsProvider.
    @MainActor private let tools: [any Tool] = [
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
        UnfileItemsTool(),
        CreateReminderTool(),
        CancelReminderTool()
    ]

    // MARK: - AgentProvider

    var isAvailable: Bool {
        AIAvailability.isFoundationModelsAvailable
    }

    var displayName: String { "Apple Intelligence" }

    var capabilities: AgentProviderCapabilities { .appleIntelligence }

    func generate(
        systemPrompt: String,
        messages: [AgentMessage],
        tools toolDefinitions: [AgentToolDefinition]
    ) async throws -> AgentProviderResponse {
        try await generateOnMainActor(systemPrompt: systemPrompt, messages: messages)
    }

    @MainActor
    private func generateOnMainActor(
        systemPrompt: String,
        messages: [AgentMessage]
    ) async throws -> AgentProviderResponse {
        guard isAvailable else { throw AgentError.providerUnavailable }

        guard let lastUserMessage = messages.last(where: { $0.role == .user }) else {
            return .text("No message to respond to.")
        }

        var activeSession = getOrCreateSession(systemPrompt: systemPrompt)

        if contextUsage >= summarizationThreshold {
            logger.info("Context at \(Int(self.contextUsage * 100))% — summarizing")
            if let refreshed = await summarizeAndReset(messages: messages, systemPrompt: systemPrompt) {
                activeSession = refreshed
            }
        }

        do {
            let response = try await activeSession.respond(to: lastUserMessage.content)
            await updateContextUsage()
            return .text(response.content)
        } catch {
            if "\(error)".contains("exceededContextWindowSize") {
                logger.warning("Context exceeded — resetting session")
                if let refreshed = await summarizeAndReset(messages: messages, systemPrompt: systemPrompt) {
                    let retryResponse = try await refreshed.respond(to: lastUserMessage.content)
                    await updateContextUsage()
                    return .text(retryResponse.content)
                }
            }
            throw error
        }
    }

    func streamGenerate(
        systemPrompt: String,
        messages: [AgentMessage],
        tools toolDefinitions: [AgentToolDefinition]
    ) -> AsyncThrowingStream<AgentProviderStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                guard self.isAvailable else {
                    continuation.finish(throwing: AgentError.providerUnavailable)
                    return
                }

                guard let lastUserMessage = messages.last(where: { $0.role == .user }) else {
                    continuation.finish(throwing: AIAssistantError.noUserMessage)
                    return
                }

                var activeSession = self.getOrCreateSession(systemPrompt: systemPrompt)

                if self.contextUsage >= self.summarizationThreshold {
                    self.logger.info("Context at \(Int(self.contextUsage * 100))% — summarizing")
                    if let refreshed = await self.summarizeAndReset(
                        messages: messages,
                        systemPrompt: systemPrompt
                    ) {
                        activeSession = refreshed
                    }
                }

                do {
                    let stream = activeSession.streamResponse(to: lastUserMessage.content)
                    var previousContent = ""
                    for try await partial in stream {
                        let fullText = partial.content
                        if fullText.count > previousContent.count {
                            let delta = String(fullText.dropFirst(previousContent.count))
                            continuation.yield(.textDelta(delta))
                            previousContent = fullText
                        }
                    }
                    await self.updateContextUsage()
                    continuation.yield(.done(.text(previousContent)))
                    continuation.finish()
                } catch {
                    if "\(error)".contains("exceededContextWindowSize") {
                        self.logger.warning("Context exceeded during stream — resetting")
                        if let refreshed = await self.summarizeAndReset(
                            messages: messages,
                            systemPrompt: systemPrompt
                        ) {
                            do {
                                let retryStream = refreshed.streamResponse(to: lastUserMessage.content)
                                var prev = ""
                                for try await partial in retryStream {
                                    let fullText = partial.content
                                    if fullText.count > prev.count {
                                        continuation.yield(.textDelta(String(fullText.dropFirst(prev.count))))
                                        prev = fullText
                                    }
                                }
                                await self.updateContextUsage()
                                continuation.yield(.done(.text(prev)))
                                continuation.finish()
                                return
                            } catch {
                                self.logger.error("Retry after summarization failed: \(error.localizedDescription, privacy: .public)")
                            }
                        }
                    }
                    self.logger.error("Stream error: \(error.localizedDescription, privacy: .public)")
                    self.session = nil
                    self.contextUsage = 0
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func resetSession() {
        Task { @MainActor in
            session = nil
            contextUsage = 0
        }
    }

    // MARK: - Session Management

    @MainActor
    private func getOrCreateSession(systemPrompt: String) -> LanguageModelSession {
        if let existing = session { return existing }
        let s = LanguageModelSession(tools: tools, instructions: systemPrompt)
        session = s
        contextUsage = 0
        return s
    }

    // MARK: - Context Management

    @MainActor
    private func updateContextUsage() async {
        guard let session else { contextUsage = 0; return }

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
                charCount += 200
            }
        }

        let estimatedTokens = charCount / 4
        let totalEstimate = estimatedTokens + 1450
        contextUsage = min(1.0, Double(totalEstimate) / Double(contextWindowSize))
    }

    @MainActor
    private func summarizeAndReset(
        messages: [AgentMessage],
        systemPrompt: String
    ) async -> LanguageModelSession? {
        let conversationText = messages.map { msg in
            let role = msg.role == .user ? "User" : "AI"
            return "\(role): \(msg.content)"
        }.joined(separator: "\n")

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
            session = nil
            contextUsage = 0
            return getOrCreateSession(systemPrompt: systemPrompt)
        }

        let extendedPrompt = systemPrompt + "\n\nConversation summary so far:\n\(summary)"
        let freshSession = LanguageModelSession(tools: tools, instructions: extendedPrompt)
        session = freshSession
        contextUsage = 0.15
        logger.info("Session refreshed with conversation summary")
        return freshSession
    }
}
