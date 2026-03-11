import Foundation
import os

/// Drives the AI Chat UI. Manages conversations, process lifecycle, and model selection.
/// Shared between docked and floating modes — both observe the same instance.
@MainActor
final class AIChatViewModel: ObservableObject {
    static let shared = AIChatViewModel()

    private let logger = Logger(subsystem: "com.cider.app", category: "AIChatVM")

    // MARK: - Published State

    @Published var messages: [AIChatMessage] = []
    @Published var selectedModel: AIModelOption = AIModelOption.aiModels[0]
    @Published var isProcessRunning = false
    @Published var conversations: [ChatConversation] = []
    @Published var currentConversationID: UUID?
    @Published var isSidebarOpen = false
    @Published var isShellExpanded = false

    private let processService = AIChatProcessService()
    private var currentStreamingMessageID: UUID?

    // MARK: - File Paths

    /// Directory for a model's conversations: ~/CiderVault/AI Chat/{modelID}/
    private func conversationsDirectory(for modelID: String) -> URL {
        StoragePaths.cachedVaultDirectoryURL
            .appendingPathComponent("AI Chat")
            .appendingPathComponent(modelID)
    }

    private func conversationFileURL(for conversation: ChatConversation) -> URL {
        conversationsDirectory(for: conversation.modelID)
            .appendingPathComponent("\(conversation.id.uuidString).json")
    }

    // MARK: - Init

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

        loadConversations()
        // Select the most recent conversation, or start a new one
        if let latest = conversations.first {
            currentConversationID = latest.id
            messages = latest.messages
        }

        migrateOldSessionFiles()
    }

    deinit {
        processService.stop()
    }

    // MARK: - Public API

    func selectModel(_ model: AIModelOption) {
        guard selectedModel.id != model.id else { return }
        // Save current conversation before switching
        saveCurrentConversation()
        processService.stop()
        isProcessRunning = false
        currentStreamingMessageID = nil
        selectedModel = model
        // Load conversations for the new model
        loadConversations()
        if let latest = conversations.first {
            currentConversationID = latest.id
            messages = latest.messages
        } else {
            currentConversationID = nil
            messages = []
        }
    }

    func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let model = selectedModel

        // Check CLI availability before running (skip for shell)
        if model.id != "shell" && !isModelInstalled(model) {
            if currentConversationID == nil {
                newConversation(autoTitle: trimmed)
            }
            let userMessage = AIChatMessage(role: .user, content: trimmed)
            messages.append(userMessage)
            let hint = model.installHint.isEmpty ? model.command : model.installHint
            addSystemMessage("\(model.name) CLI not found. Install it with:\n\n\(hint)")
            saveCurrentConversation()
            return
        }

        // Create a conversation if none active
        if currentConversationID == nil {
            newConversation(autoTitle: trimmed)
        }

        // Add user message
        let userMessage = AIChatMessage(role: .user, content: trimmed)
        messages.append(userMessage)

        // Create streaming assistant message
        let assistantMessage = AIChatMessage(role: .assistant, content: "", isStreaming: true, hideWhileStreaming: model.id == "codex")
        currentStreamingMessageID = assistantMessage.id
        messages.append(assistantMessage)

        // Auto-title from first user message
        if let convIndex = conversations.firstIndex(where: { $0.id == currentConversationID }),
           conversations[convIndex].messages.isEmpty {
            let title = String(trimmed.prefix(40))
            conversations[convIndex].title = title.count < trimmed.count ? title + "…" : title
        }

        saveCurrentConversation()

        if model.id == "shell" {
            if !isProcessRunning {
                startShell()
            }
            processService.send(trimmed)
        } else if !model.printArgs.isEmpty {
            // Only add --continue args when this conversation already has prior messages
            let hasHistory = messages.filter({ $0.role == .user }).count > 1
            var args = model.printArgs
            if hasHistory && !model.continueArgs.isEmpty {
                args = model.continueArgs + args
            }
            let ignoreStderr = model.id == "codex"
            processService.runOneShot(command: model.command, arguments: args + [trimmed], ignoreStderr: ignoreStderr)
            isProcessRunning = true
        } else {
            let ignoreStderr = model.id == "codex"
            processService.runOneShot(command: model.command, arguments: [trimmed], ignoreStderr: ignoreStderr)
            isProcessRunning = true
        }
    }

    /// Start a fresh conversation for the current model.
    func newConversation(autoTitle: String? = nil) {
        saveCurrentConversation()
        processService.stop()
        isProcessRunning = false
        currentStreamingMessageID = nil

        let title: String
        if let autoTitle, !autoTitle.isEmpty {
            let truncated = String(autoTitle.prefix(40))
            title = truncated.count < autoTitle.count ? truncated + "…" : truncated
        } else {
            title = "New Chat"
        }

        let conversation = ChatConversation(title: title, modelID: selectedModel.id)
        conversations.insert(conversation, at: 0)
        currentConversationID = conversation.id
        messages = []
    }

    /// Switch to an existing conversation.
    func selectConversation(_ conversation: ChatConversation) {
        guard conversation.id != currentConversationID else { return }
        saveCurrentConversation()
        processService.stop()
        isProcessRunning = false
        currentStreamingMessageID = nil
        currentConversationID = conversation.id
        messages = conversation.messages
    }

    /// Rename a conversation.
    func renameConversation(id: UUID, to newTitle: String) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].title = newTitle
        conversations[index].updatedAt = Date()
        saveConversation(conversations[index])
    }

    /// Delete a conversation.
    func deleteConversation(id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        let conversation = conversations[index]
        let fileURL = conversationFileURL(for: conversation)
        try? FileManager.default.removeItem(at: fileURL)
        conversations.remove(at: index)

        if currentConversationID == id {
            processService.stop()
            isProcessRunning = false
            currentStreamingMessageID = nil
            if let next = conversations.first {
                currentConversationID = next.id
                messages = next.messages
            } else {
                currentConversationID = nil
                messages = []
            }
        }
    }

    func restart() {
        processService.stop()
        isProcessRunning = false
        currentStreamingMessageID = nil
        messages.removeAll()
        saveCurrentConversation()
    }

    func stop() {
        processService.stop()
        isProcessRunning = false
        finalizeCurrentStream()
    }

    func toggleSidebar() {
        isSidebarOpen.toggle()
    }

    func toggleShellExpanded() {
        isShellExpanded.toggle()
    }

    /// Check if a model's CLI tool is installed. Always true for shell.
    func isModelInstalled(_ model: AIModelOption) -> Bool {
        guard !model.command.isEmpty else { return true }
        return processService.isCommandAvailable(model.command)
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
            let msg = AIChatMessage(role: .assistant, content: text, isStreaming: true)
            currentStreamingMessageID = msg.id
            messages.append(msg)
        }
    }

    /// Strip Codex CLI's verbose header, metadata, and deprecation warnings from complete output.
    private static let codexNoisePatterns: [String] = [
        "OpenAI Codex v",
        "--------",
        "workdir:",
        "model:",
        "provider:",
        "approval:",
        "sandbox:",
        "reasoning effort:",
        "reasoning summaries:",
        "session id:",
        "deprecated:",
        "Enable it with",
        "mcp startup:",
        "tokens used",
    ]

    private static func stripCodexNoise(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var filtered: [String] = []
        var skipNextNumber = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            // After a "tokens used" line, skip the next number
            if skipNextNumber {
                skipNextNumber = false
                let digits = trimmed.replacingOccurrences(of: ",", with: "")
                if Int(digits) != nil { continue }
            }

            if trimmed == "tokens used" {
                skipNextNumber = true
                continue
            }

            // Drop lines that are just a role label
            if trimmed == "codex" || trimmed == "user" { continue }

            var isNoise = false
            for pattern in codexNoisePatterns {
                if trimmed.hasPrefix(pattern) { isNoise = true; break }
            }
            if isNoise { continue }

            filtered.append(line)
        }
        return filtered.joined(separator: "\n")
    }

    private func handleProcessExit(_ exitCode: Int32) {
        isProcessRunning = false
        finalizeCurrentStream()

        if selectedModel.id == "shell" || exitCode != 0 {
            addSystemMessage("Session ended (exit code \(exitCode)).")
        }

        saveCurrentConversation()
    }

    private func finalizeCurrentStream() {
        guard let streamID = currentStreamingMessageID,
              let index = messages.firstIndex(where: { $0.id == streamID }) else { return }

        messages[index].isStreaming = false

        // Clean up Codex's verbose metadata from the complete output
        if selectedModel.id == "codex" {
            messages[index].content = Self.stripCodexNoise(messages[index].content)
        }

        messages[index].content = messages[index].content.trimmingCharacters(in: .whitespacesAndNewlines)

        if messages[index].content.isEmpty {
            messages.remove(at: index)
        }

        currentStreamingMessageID = nil
    }

    // MARK: - Persistence

    private func saveCurrentConversation() {
        guard let id = currentConversationID,
              let index = conversations.firstIndex(where: { $0.id == id }) else { return }

        let saveable = messages.filter { !$0.isStreaming && !$0.content.isEmpty }
        conversations[index].messages = saveable
        conversations[index].updatedAt = Date()

        // Remove conversation if empty and it's not the only one
        if saveable.isEmpty {
            let fileURL = conversationFileURL(for: conversations[index])
            try? FileManager.default.removeItem(at: fileURL)
            if conversations.count > 1 {
                conversations.remove(at: index)
                currentConversationID = conversations.first?.id
                messages = conversations.first?.messages ?? []
            }
            return
        }

        saveConversation(conversations[index])
    }

    private func saveConversation(_ conversation: ChatConversation) {
        let fileURL = conversationFileURL(for: conversation)
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(conversation)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save conversation: \(error.localizedDescription)")
        }
    }

    private func loadConversations() {
        let dir = conversationsDirectory(for: selectedModel.id)
        guard FileManager.default.fileExists(atPath: dir.path) else {
            conversations = []
            return
        }

        do {
            let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            var loaded: [ChatConversation] = []
            for file in files {
                let data = try Data(contentsOf: file)
                let conversation = try decoder.decode(ChatConversation.self, from: data)
                loaded.append(conversation)
            }

            // Sort by most recent first
            conversations = loaded.sorted { $0.updatedAt > $1.updatedAt }
            logger.info("Loaded \(self.conversations.count) conversations for \(self.selectedModel.id)")
        } catch {
            logger.error("Failed to load conversations: \(error.localizedDescription)")
            conversations = []
        }
    }

    /// Migrate old single-session files to the new conversation format.
    private func migrateOldSessionFiles() {
        let aiChatDir = StoragePaths.cachedVaultDirectoryURL.appendingPathComponent("AI Chat")
        guard FileManager.default.fileExists(atPath: aiChatDir.path) else { return }

        do {
            let files = try FileManager.default.contentsOfDirectory(at: aiChatDir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasSuffix("_session.json") }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            for file in files {
                let modelID = file.lastPathComponent.replacingOccurrences(of: "_session.json", with: "")
                let data = try Data(contentsOf: file)
                let messages = try decoder.decode([AIChatMessage].self, from: data)

                guard !messages.isEmpty else {
                    try? FileManager.default.removeItem(at: file)
                    continue
                }

                let title: String
                if let firstUser = messages.first(where: { $0.role == .user })?.content {
                    let truncated = String(firstUser.prefix(40))
                    title = truncated.count < firstUser.count ? truncated + "…" : truncated
                } else {
                    title = "Imported Chat"
                }

                let conversation = ChatConversation(
                    title: title,
                    modelID: modelID,
                    createdAt: messages.first?.timestamp ?? Date(),
                    updatedAt: messages.last?.timestamp ?? Date(),
                    messages: messages
                )

                saveConversation(conversation)
                try FileManager.default.removeItem(at: file)
                logger.info("Migrated old session file for \(modelID)")

                // If this is the current model, add to loaded conversations
                if modelID == selectedModel.id {
                    conversations.insert(conversation, at: 0)
                    if currentConversationID == nil {
                        currentConversationID = conversation.id
                        self.messages = conversation.messages
                    }
                }
            }
        } catch {
            logger.error("Migration failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func addSystemMessage(_ text: String) {
        let msg = AIChatMessage(role: .system, content: text)
        messages.append(msg)
    }
}
