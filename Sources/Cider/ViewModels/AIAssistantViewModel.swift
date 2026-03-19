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

    private let logger = Logger(subsystem: "com.cider.app", category: "AIAssistant")
    private var provider: AIAssistantProvider
    private var streamTask: Task<Void, Never>?
    private var typewriterTask: Task<Void, Never>?

    var isAvailable: Bool { provider.isAvailable }
    var providerName: String { provider.displayName }

    init(provider: AIAssistantProvider? = nil) {
        self.provider = provider ?? FoundationModelsProvider()
    }

    // MARK: - Send Message

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

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
                // Wait for typewriter to catch up before committing
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
        }
    }

    // MARK: - Typewriter Effect

    /// Reveals text from `streamingText` into `displayedStreamingText` word by word.
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

                // Skip whitespace/newlines (reveal instantly)
                while charOffset < chars.count && chars[charOffset].isWhitespace {
                    charOffset += 1
                }
                // Advance through the next word
                while charOffset < chars.count && !chars[charOffset].isWhitespace {
                    charOffset += 1
                }

                displayedStreamingText = String(chars.prefix(charOffset))
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    /// Instantly reveal remaining text and cancel the typewriter loop.
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
    }

    func clearConversation() {
        stopStreaming()
        messages.removeAll()
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
