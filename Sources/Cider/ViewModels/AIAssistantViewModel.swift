import Foundation
import os.log

/// ViewModel for the AI chat floating panel.
@MainActor
final class AIAssistantViewModel: ObservableObject {
    static let shared = AIAssistantViewModel()

    @Published var messages: [AIAssistantMessage] = []
    @Published var isStreaming = false
    @Published var context = AIAssistantContext()

    /// Full text received from the provider so far (not yet committed as a message).
    @Published var streamingText = ""
    /// Text revealed to the UI via typewriter effect — lags behind `streamingText`.
    @Published var displayedStreamingText = ""

    /// Current conversation ID (nil = no active conversation yet).
    @Published var currentConversationID: UUID?

    private let logger = Logger(subsystem: "com.cider.app", category: "AIAssistant")
    private var provider: AIAssistantProvider
    private let storage = AIConversationStorage.shared
    private var streamTask: Task<Void, Never>?
    private var typewriterTask: Task<Void, Never>?

    var isAvailable: Bool { provider.isAvailable }
    var providerName: String { provider.displayName }

    /// Context window usage (0.0–1.0). Only available for Foundation Models.
    var contextUsage: Double {
        (provider as? FoundationModelsProvider)?.contextUsage ?? 0
    }

    init(provider: AIAssistantProvider? = nil) {
        self.provider = provider ?? FoundationModelsProvider()
    }

    // MARK: - Send Message

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        // Start a new conversation if none active
        if currentConversationID == nil {
            currentConversationID = UUID()
        }

        let userMessage = AIAssistantMessage(role: .user, content: trimmed)
        messages.append(userMessage)

        isStreaming = true
        streamingText = ""
        displayedStreamingText = ""

        startTypewriterLoop()

        streamTask = Task {
            let stream = provider.streamResponse(messages: messages, context: context)
            do {
                for try await chunk in stream {
                    streamingText += chunk
                }
                await finishTypewriter()
                let assistantMessage = AIAssistantMessage(role: .assistant, content: streamingText)
                messages.append(assistantMessage)
            } catch {
                logger.error("AI response error: \(error.localizedDescription, privacy: .public)")
                await finishTypewriter()
                if streamingText.isEmpty {
                    let errorMessage = AIAssistantMessage(
                        role: .assistant,
                        content: "Sorry, I couldn't generate a response. Please try again."
                    )
                    messages.append(errorMessage)
                } else {
                    let partialMessage = AIAssistantMessage(role: .assistant, content: streamingText)
                    messages.append(partialMessage)
                }
            }

            streamingText = ""
            displayedStreamingText = ""
            isStreaming = false

            // Auto-save after each exchange
            saveCurrentConversation()
        }
    }

    // MARK: - Typewriter Effect

    private func startTypewriterLoop() {
        typewriterTask?.cancel()
        typewriterTask = Task {
            var charOffset = 0
            while !Task.isCancelled {
                let current = streamingText
                let chars = Array(current)

                guard charOffset < chars.count else {
                    if !isStreaming {
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(20))
                    continue
                }

                while charOffset < chars.count && chars[charOffset].isWhitespace {
                    charOffset += 1
                }
                while charOffset < chars.count && !chars[charOffset].isWhitespace {
                    charOffset += 1
                }

                displayedStreamingText = String(chars.prefix(charOffset))
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    private func finishTypewriter() async {
        typewriterTask?.cancel()
        typewriterTask = nil
        displayedStreamingText = streamingText
    }

    // MARK: - Stop / Clear

    func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        typewriterTask?.cancel()
        typewriterTask = nil
        if !streamingText.isEmpty {
            let partialMessage = AIAssistantMessage(role: .assistant, content: streamingText)
            messages.append(partialMessage)
        }
        streamingText = ""
        displayedStreamingText = ""
        isStreaming = false
        saveCurrentConversation()
    }

    func clearConversation() {
        stopStreaming()
        messages.removeAll()
        currentConversationID = nil
        provider.resetSession()
    }

    /// Start a new conversation (saves current one first).
    func newConversation() {
        saveCurrentConversation()
        stopStreaming()
        messages.removeAll()
        currentConversationID = nil
        provider.resetSession()
    }

    // MARK: - Persistence

    /// Save the current conversation to disk.
    private func saveCurrentConversation() {
        guard let id = currentConversationID, !messages.isEmpty else { return }
        let title = conversationTitle
        storage.save(id: id, title: title, messages: messages, model: providerName)
    }

    /// Load a previous conversation by ID.
    func loadConversation(_ conversationID: UUID) {
        guard let loadedMessages = storage.loadMessages(for: conversationID) else { return }
        // Save current conversation first
        saveCurrentConversation()

        stopStreaming()
        messages = loadedMessages
        currentConversationID = conversationID
        provider.resetSession()
    }

    /// Delete a conversation from disk.
    func deleteConversation(_ conversationID: UUID) {
        storage.delete(conversationID: conversationID)
        if currentConversationID == conversationID {
            clearConversation()
        }
    }

    /// Export current conversation as markdown.
    func exportCurrentAsMarkdown() -> String? {
        guard let id = currentConversationID else { return nil }
        saveCurrentConversation()
        return storage.exportAsMarkdown(conversationID: id)
    }

    /// Auto-generated title from the first user message.
    private var conversationTitle: String {
        guard let firstUserMessage = messages.first(where: { $0.role == .user }) else {
            return "New Chat"
        }
        let title = firstUserMessage.content
        if title.count <= 50 { return title }
        return String(title.prefix(47)) + "..."
    }

    // MARK: - Context Updates

    func updateContext(bookmark: (title: String, url: String, summary: String?)? = nil,
                       note: (title: String, excerpt: String)? = nil,
                       folder: (name: String, itemCount: Int)? = nil,
                       selectedCount: Int = 0) {
        context.currentBookmark = bookmark
        context.currentNote = note
        context.currentFolder = folder
        context.selectedItemCount = selectedCount
    }

    func clearContext() {
        context = AIAssistantContext()
    }
}
