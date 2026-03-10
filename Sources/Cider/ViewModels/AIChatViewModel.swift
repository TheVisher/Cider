import Foundation
import os

/// Drives the AI Chat UI. Manages messages, process lifecycle, and model selection.
/// Shared between docked and floating modes — both observe the same instance.
@MainActor
final class AIChatViewModel: ObservableObject {
    static let shared = AIChatViewModel()

    private let logger = Logger(subsystem: "com.cider.app", category: "AIChatVM")

    @Published var messages: [AIChatMessage] = []
    @Published var selectedModel: AIModelOption = AIModelOption.builtIn[0]
    @Published var isProcessRunning = false

    private let processService = AIChatProcessService()
    private var currentStreamingMessageID: UUID?

    /// Where chat history is persisted — one file per model.
    private func historyFileURL(for modelID: String) -> URL {
        StoragePaths.cachedVaultDirectoryURL
            .appendingPathComponent("AI Chat")
            .appendingPathComponent("\(modelID)_session.json")
    }

    init() {
        processService.onOutput = { [weak self] text in
            Task { @MainActor [weak self] in
                self?.handleOutput(text)
            }
        }

        processService.onProcessExit = { [weak self] exitCode in
            Task { @MainActor [weak self] in
                self?.handleProcessExit(exitCode)
            }
        }

        loadMessages()
    }

    deinit {
        processService.stop()
    }

    // MARK: - Public API

    func selectModel(_ model: AIModelOption) {
        guard selectedModel.id != model.id else { return }
        // Save current model's messages before switching
        saveMessages()
        processService.stop()
        isProcessRunning = false
        currentStreamingMessageID = nil
        selectedModel = model
        // Load the new model's messages
        loadMessages()
    }

    func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let model = selectedModel

        // Add user message
        let userMessage = AIChatMessage(role: .user, content: trimmed)
        messages.append(userMessage)

        // Create streaming assistant message
        let assistantMessage = AIChatMessage(role: .assistant, content: "", isStreaming: true)
        currentStreamingMessageID = assistantMessage.id
        messages.append(assistantMessage)

        saveMessages()

        if model.id == "shell" {
            // Shell mode: persistent process, pipe stdin
            if !isProcessRunning {
                startShell()
            }
            processService.send(trimmed)
        } else if !model.printArgs.isEmpty {
            // One-shot mode with args (e.g. `claude --continue -p "msg"`)
            processService.runOneShot(command: model.command, arguments: model.printArgs + [trimmed])
            isProcessRunning = true
        } else {
            // Fallback: try one-shot with the message as an argument
            processService.runOneShot(command: model.command, arguments: [trimmed])
            isProcessRunning = true
        }
    }

    func restart() {
        processService.stop()
        isProcessRunning = false
        currentStreamingMessageID = nil
        messages.removeAll()
        saveMessages()
    }

    func stop() {
        processService.stop()
        isProcessRunning = false
        finalizeCurrentStream()
    }

    // MARK: - Process Management

    private func startShell() {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        processService.startPersistent(command: shell, arguments: ["-l"])
        isProcessRunning = true
    }

    // MARK: - Output Handling

    private func handleOutput(_ text: String) {
        if let streamID = currentStreamingMessageID,
           let index = messages.firstIndex(where: { $0.id == streamID }) {
            messages[index].content += text
        } else {
            // No active stream — create one (e.g. unsolicited output from shell)
            let msg = AIChatMessage(role: .assistant, content: text, isStreaming: true)
            currentStreamingMessageID = msg.id
            messages.append(msg)
        }
    }

    private func handleProcessExit(_ exitCode: Int32) {
        isProcessRunning = false
        finalizeCurrentStream()

        // Only show exit message for unexpected exits (non-zero) in one-shot mode
        if selectedModel.id == "shell" || exitCode != 0 {
            addSystemMessage("Session ended (exit code \(exitCode)).")
        }

        saveMessages()
    }

    private func finalizeCurrentStream() {
        guard let streamID = currentStreamingMessageID,
              let index = messages.firstIndex(where: { $0.id == streamID }) else { return }

        messages[index].isStreaming = false
        messages[index].content = messages[index].content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove empty assistant messages
        if messages[index].content.isEmpty {
            messages.remove(at: index)
        }

        currentStreamingMessageID = nil
    }

    // MARK: - Persistence

    private func saveMessages() {
        let fileURL = historyFileURL(for: selectedModel.id)
        let saveable = messages.filter { !$0.isStreaming && !$0.content.isEmpty }
        guard !saveable.isEmpty else {
            // Clean up file if no messages
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(saveable)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save chat history: \(error.localizedDescription)")
        }
    }

    private func loadMessages() {
        let fileURL = historyFileURL(for: selectedModel.id)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            messages.removeAll()
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            messages = try decoder.decode([AIChatMessage].self, from: data)
            logger.info("Loaded \(self.messages.count) messages from history")
        } catch {
            logger.error("Failed to load chat history: \(error.localizedDescription)")
            messages.removeAll()
        }
    }

    // MARK: - Helpers

    private func addSystemMessage(_ text: String) {
        let msg = AIChatMessage(role: .system, content: text)
        messages.append(msg)
    }
}
