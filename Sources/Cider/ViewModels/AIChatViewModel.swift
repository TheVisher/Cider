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
    }

    deinit {
        processService.stop()
    }

    // MARK: - Public API

    func selectModel(_ model: AIModelOption) {
        guard selectedModel.id != model.id else { return }
        selectedModel = model
        processService.stop()
        isProcessRunning = false
        currentStreamingMessageID = nil
        messages.removeAll()
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

        if model.id == "shell" {
            // Shell mode: persistent process, pipe stdin
            if !isProcessRunning {
                startShell()
            }
            processService.send(trimmed)
        } else if let printFlag = model.printFlag {
            // One-shot mode: run command with print flag per message (e.g. `claude -p "msg"`)
            processService.runOneShot(command: model.command, arguments: [printFlag, trimmed])
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

    // MARK: - Helpers

    private func addSystemMessage(_ text: String) {
        let msg = AIChatMessage(role: .system, content: text)
        messages.append(msg)
    }
}
