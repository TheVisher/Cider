import Foundation
import os.log

enum AIAgentRuntimeSelection: String, Sendable {
    case appleIntelligence
    case localModel
    case codexCLI
    case hermes
}

enum HermesPanelSyncStatus: Equatable {
    case idle
    case syncing
    case sending
    case error(String)
}

/// ViewModel for the AI chat floating panel.
@MainActor
final class AIAssistantViewModel: ObservableObject {
    static let shared = AIAssistantViewModel()
    private static let runtimeSelectionDefaultsKey = "cider.aiRuntimeSelection"

    @Published var messages: [AIAssistantMessage] = []
    @Published var isStreaming = false
    @Published var context = AIAssistantContext()

    /// Full text received from the provider so far (not yet committed as a message).
    @Published var streamingText = ""
    /// Text revealed to the UI via typewriter effect — lags behind `streamingText`.
    @Published var displayedStreamingText = ""

    /// Current conversation ID (nil = no active conversation yet).
    @Published var currentConversationID: UUID?
    @Published private(set) var runtimeSelection: AIAgentRuntimeSelection = .appleIntelligence
    @Published private(set) var runtimeHealth: AgentRuntimeHealth = .idle
    @Published private(set) var hermesConversationState: HermesConversationState?
    @Published private(set) var hermesSyncStatus: HermesPanelSyncStatus = .idle

    private let logger = Logger(subsystem: "com.cider.app", category: "AIAssistant")
    private var provider: AIAssistantProvider
    private let storage = AIConversationStorage.shared
    private let hermesSessionService = HermesSessionService()
    private var streamTask: Task<Void, Never>?
    private var typewriterTask: Task<Void, Never>?

    /// When true, messages are routed through AgentOrchestrator instead of
    /// the legacy AIAssistantProvider path.
    private var useOrchestrator = false

    /// Thread ID for the current orchestrator conversation.
    private var orchestratorThreadID: UUID?

    var isAvailable: Bool {
        if runtimeSelection == .hermes {
            return FileManager.default.fileExists(atPath: HermesPaths.defaultStateDatabaseURL.path)
        }
        if useOrchestrator {
            return runtimeHealth.status != .unavailable
        }
        return provider.isAvailable
    }
    var providerName: String {
        if runtimeSelection == .hermes {
            return "Hermes"
        }
        if useOrchestrator, let runtime = currentAgentRuntime {
            return runtime.displayName
        }
        return provider.displayName
    }

    /// Whether the local MLX model is active.
    var isUsingLocalModel: Bool {
        if useOrchestrator {
            return runtimeSelection == .localModel
        }
        return provider is MLXProvider
    }

    var isUsingProcessRuntime: Bool {
        useOrchestrator && runtimeSelection == .codexCLI
    }

    var hermesStatusTitle: String {
        switch hermesSyncStatus {
        case .idle:
            guard runtimeSelection == .hermes else { return "" }
            if let lastSyncedAt = hermesConversationState?.lastSyncedAt {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .abbreviated
                return "Synced \(formatter.localizedString(for: lastSyncedAt, relativeTo: Date()))"
            }
            return hermesConversationState == nil ? "Attach Hermes" : "Auto-sync on"
        case .syncing:
            return "Syncing..."
        case .sending:
            return "Sending..."
        case .error(let message):
            return message
        }
    }

    var hermesSessionLabel: String {
        guard let sessionID = hermesConversationState?.activeRuntimeSessionID else {
            return "No session"
        }
        return String(sessionID.suffix(8))
    }

    /// Context window usage (0.0–1.0). Only available for Foundation Models.
    var contextUsage: Double {
        if useOrchestrator, runtimeSelection != .appleIntelligence { return 0 }
        return (provider as? FoundationModelsProvider)?.contextUsage ?? 0
    }

    private let foundationModelsProvider = FoundationModelsProvider()
    private let mlxProvider = MLXProvider()

    /// Agent provider adapters for the orchestrator path.
    private let foundationModelsAgentProvider = FoundationModelsAgentProvider()
    private let mlxAgentProvider = MLXAgentProvider()
    private lazy var foundationModelsRuntime = ModelAgentRuntime(
        provider: foundationModelsAgentProvider,
        id: "model.apple-intelligence"
    )
    private lazy var mlxRuntime = ModelAgentRuntime(
        provider: mlxAgentProvider,
        id: "model.local-qwen"
    )
    private lazy var codexRuntime = CodexProcessRuntime(
        workingDirectoryURL: StoragePaths.cachedVaultDirectoryURL
    )

    /// The currently active runtime (for orchestrator mode).
    private var currentAgentRuntime: (any AgentRuntime)? {
        guard useOrchestrator else { return nil }
        switch runtimeSelection {
        case .appleIntelligence:
            return foundationModelsRuntime
        case .localModel:
            return mlxRuntime
        case .codexCLI:
            return codexRuntime
        case .hermes:
            return nil
        }
    }

    init(provider: AIAssistantProvider? = nil) {
        let initialRuntimeSelection = Self.loadPersistedRuntimeSelection()
        runtimeSelection = initialRuntimeSelection
        if let provider {
            self.provider = provider
        } else if initialRuntimeSelection == .codexCLI {
            self.provider = FoundationModelsProvider()
        } else if MLXModelManager.shared.isLocalModelEnabled || initialRuntimeSelection == .localModel {
            self.provider = MLXProvider()
        } else {
            self.provider = FoundationModelsProvider()
        }
        // Auto-resume most recent conversation
        resumeLastConversation()
        if initialRuntimeSelection == .hermes {
            restoreHermesStateForCurrentConversation()
            Task {
                await activateHermesConversation()
            }
        }
    }

    /// Switch between Apple Intelligence and local MLX model.
    func switchProvider(useLocalModel: Bool) {
        clearConversation()
        hermesConversationState = nil
        hermesSyncStatus = .idle
        if useLocalModel {
            provider = mlxProvider
            runtimeSelection = .localModel
        } else {
            provider = foundationModelsProvider
            runtimeSelection = .appleIntelligence
            // Unload MLX model to free memory
            MLXModelManager.shared.unloadModel()
        }
        MLXModelManager.shared.isLocalModelEnabled = useLocalModel

        // Update orchestrator runtime if active
        if useOrchestrator {
            Task {
                await configureOrchestratorRuntime(startIfNeeded: false)
            }
        }
    }

    func switchRuntime(to selection: AIAgentRuntimeSelection) {
        clearConversation()
        runtimeSelection = selection
        persistRuntimeSelection(selection)

        switch selection {
        case .appleIntelligence:
            provider = foundationModelsProvider
            MLXModelManager.shared.isLocalModelEnabled = false
            MLXModelManager.shared.unloadModel()
        case .localModel:
            provider = mlxProvider
            MLXModelManager.shared.isLocalModelEnabled = true
        case .codexCLI:
            MLXModelManager.shared.isLocalModelEnabled = false
            MLXModelManager.shared.unloadModel()
        case .hermes:
            provider = foundationModelsProvider
            MLXModelManager.shared.isLocalModelEnabled = false
            MLXModelManager.shared.unloadModel()
        }

        if useOrchestrator {
            Task {
                await configureOrchestratorRuntime(startIfNeeded: selection == .codexCLI)
            }
        }

        if selection == .hermes {
            Task {
                await activateHermesConversation()
            }
        } else {
            hermesConversationState = nil
            hermesSyncStatus = .idle
        }
    }

    /// Runtime switch path for external channels/admin commands that need to await
    /// the orchestrator reconfiguration before replying.
    func switchRuntimeFromExternalCommand(to selection: AIAgentRuntimeSelection) async {
        clearConversation()
        runtimeSelection = selection
        persistRuntimeSelection(selection)

        switch selection {
        case .appleIntelligence:
            provider = foundationModelsProvider
            MLXModelManager.shared.isLocalModelEnabled = false
            MLXModelManager.shared.unloadModel()
        case .localModel:
            provider = mlxProvider
            MLXModelManager.shared.isLocalModelEnabled = true
        case .codexCLI:
            MLXModelManager.shared.isLocalModelEnabled = false
            MLXModelManager.shared.unloadModel()
        case .hermes:
            provider = foundationModelsProvider
            MLXModelManager.shared.isLocalModelEnabled = false
            MLXModelManager.shared.unloadModel()
        }

        if useOrchestrator {
            await configureOrchestratorRuntime(startIfNeeded: false)
        }

        if selection == .hermes {
            await activateHermesConversation()
        } else {
            hermesConversationState = nil
            hermesSyncStatus = .idle
        }
    }

    /// Enable the orchestrator-backed code path. Called once tools are registered.
    func enableOrchestrator() {
        useOrchestrator = true
        orchestratorThreadID = currentConversationID ?? UUID()
        if runtimeSelection != .codexCLI && runtimeSelection != .hermes {
            runtimeSelection = MLXModelManager.shared.isLocalModelEnabled ? .localModel : .appleIntelligence
        }
        Task {
            await configureOrchestratorRuntime(startIfNeeded: false)
        }
        logger.info("Orchestrator mode enabled")
    }

    /// Load the most recent conversation on startup.
    private func resumeLastConversation() {
        guard let recent = storage.conversations.first else { return }
        if let loaded = storage.loadMessages(for: recent.id) {
            messages = loaded
            currentConversationID = recent.id
        }
    }

    // MARK: - Send Message

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        if runtimeSelection == .hermes {
            sendViaHermes(trimmed)
            return
        }

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

        if useOrchestrator {
            sendViaOrchestrator(trimmed)
        } else {
            sendViaLegacyProvider()
        }
    }

    func syncHermesConversation() {
        guard runtimeSelection == .hermes,
              !isStreaming,
              hermesSyncStatus != .syncing,
              hermesSyncStatus != .sending
        else { return }
        Task {
            await syncHermesConversation(attachIfNeeded: true)
        }
    }

    private func activateHermesConversation() async {
        if currentConversationID == nil,
           let summary = storage.conversations.first(where: { $0.runtimeID == "hermes" }) {
            loadConversation(summary.id)
        }

        await syncHermesConversation(attachIfNeeded: true)
    }

    private func sendViaHermes(_ text: String) {
        streamTask = Task {
            isStreaming = true
            streamingText = "Waiting for Hermes..."
            displayedStreamingText = ""
            hermesSyncStatus = .sending
            startTypewriterLoop()

            do {
                let state = try await ensureHermesConversationState()
                let pendingMessage = AIAssistantMessage(
                    role: .user,
                    content: text,
                    sourceID: "hermes:pending:\(UUID().uuidString)",
                    sourceName: "Hermes Pending"
                )
                messages.append(pendingMessage)

                let existingMessages = messages.filter { $0.id != pendingMessage.id }
                let result = try await hermesSessionService.send(
                    text: text,
                    state: state,
                    existingMessages: existingMessages
                )
                hermesConversationState = result.state
                messages = result.messages
                hermesSyncStatus = .idle
                saveCurrentConversation()
            } catch is CancellationError {
                logger.debug("Hermes send cancelled")
            } catch {
                logger.error("Hermes send error: \(error.localizedDescription, privacy: .public)")
                hermesSyncStatus = .error(error.localizedDescription)
                if !messages.contains(where: { $0.role == .user && $0.content == text }) {
                    messages.append(AIAssistantMessage(role: .user, content: text))
                }
                messages.append(AIAssistantMessage(
                    role: .assistant,
                    content: "Hermes error: \(error.localizedDescription)"
                ))
                saveCurrentConversation()
            }

            await finishTypewriter()
            streamingText = ""
            displayedStreamingText = ""
            isStreaming = false
        }
    }

    private func syncHermesConversation(attachIfNeeded: Bool) async {
        guard runtimeSelection == .hermes else { return }
        hermesSyncStatus = .syncing

        do {
            let state = try await ensureHermesConversationState(attachIfNeeded: attachIfNeeded)
            let result = try await hermesSessionService.sync(state: state, existingMessages: messages)
            hermesConversationState = result.state
            messages = result.messages
            hermesSyncStatus = .idle
            saveCurrentConversation()
        } catch {
            logger.error("Hermes sync error: \(error.localizedDescription, privacy: .public)")
            hermesSyncStatus = .error(error.localizedDescription)
        }
    }

    private func ensureHermesConversationState(attachIfNeeded: Bool = true) async throws -> HermesConversationState {
        if let hermesConversationState {
            return hermesConversationState
        }

        if currentConversationID == nil {
            currentConversationID = UUID()
        }

        restoreHermesStateForCurrentConversation()
        if let hermesConversationState {
            return hermesConversationState
        }

        guard attachIfNeeded, let conversationID = currentConversationID else {
            throw HermesSessionClientError.sessionNotFound("active Cider conversation")
        }

        let result = try await hermesSessionService.attachLatestTelegramConversation(
            conversationID: conversationID
        )
        hermesConversationState = result.state
        messages = result.messages
        saveCurrentConversation()
        return result.state
    }

    /// Route message through the AgentOrchestrator, streaming text back for typewriter.
    private func sendViaOrchestrator(_ text: String) {
        if orchestratorThreadID == nil {
            orchestratorThreadID = currentConversationID ?? UUID()
        }

        let threadID = orchestratorThreadID!

        // Build AgentContext from the current AIAssistantContext
        let agentContext = buildAgentContext()

        streamTask = Task {
            do {
                try await AgentOrchestrator.shared.startRuntimeIfNeeded()
                let envelope = AgentEnvelope.uiPanel(
                    text: text,
                    threadID: threadID,
                    context: agentContext
                )
                let response = try await AgentOrchestrator.shared.handleMessage(envelope)

                // Stream the full response through typewriter
                streamingText = response.text
                await finishTypewriter()

                let assistantMessage = AIAssistantMessage(role: .assistant, content: response.text)
                messages.append(assistantMessage)

                if !response.toolCallsMade.isEmpty {
                    logger.info("Orchestrator made \(response.toolCallsMade.count) tool call(s)")
                }
            } catch is CancellationError {
                logger.debug("Orchestrator stream cancelled")
            } catch {
                logger.error("Orchestrator error: \(error.localizedDescription, privacy: .public)")
                await finishTypewriter()
                let errorMessage = AIAssistantMessage(
                    role: .assistant,
                    content: "Error: \(error.localizedDescription)"
                )
                messages.append(errorMessage)
            }

            streamingText = ""
            displayedStreamingText = ""
            isStreaming = false
            saveCurrentConversation()
        }
    }

    private func configureOrchestratorRuntime(startIfNeeded: Bool) async {
        guard let runtime = currentAgentRuntime else { return }
        await AgentOrchestrator.shared.stopRuntimeIfNeeded()
        await AgentOrchestrator.shared.setRuntime(runtime)
        if startIfNeeded {
            do {
                try await AgentOrchestrator.shared.startRuntimeIfNeeded()
            } catch {
                logger.error("Failed to start runtime: \(error.localizedDescription, privacy: .public)")
            }
        }
        runtimeHealth = await AgentOrchestrator.shared.runtimeHealth()
    }

    /// Original provider-based send path (streaming text chunks).
    private func sendViaLegacyProvider() {
        streamTask = Task {
            let stream = provider.streamResponse(messages: messages, context: context)
            do {
                for try await chunk in stream {
                    streamingText += chunk
                }
                await finishTypewriter()
                let assistantMessage = AIAssistantMessage(role: .assistant, content: streamingText)
                messages.append(assistantMessage)
            } catch is CancellationError {
                logger.debug("AI response stream cancelled")
            } catch {
                logger.error("AI response error: \(error.localizedDescription, privacy: .public)")
                await finishTypewriter()
                if streamingText.isEmpty {
                    let errorDetail = error.localizedDescription
                    let errorMessage = AIAssistantMessage(
                        role: .assistant,
                        content: "Error: \(errorDetail)"
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

    /// Convert the current AIAssistantContext to an AgentContext for the orchestrator.
    private func buildAgentContext() -> AgentContext {
        var agentCtx = AgentContext.empty

        if let bookmark = context.currentBookmark {
            agentCtx.currentBookmark = .init(
                title: bookmark.title,
                url: bookmark.url,
                summary: bookmark.summary
            )
        }
        if let note = context.currentNote {
            agentCtx.currentNote = .init(title: note.title, excerpt: note.excerpt)
        }
        if let folder = context.currentFolder {
            agentCtx.currentFolder = .init(
                name: folder.name,
                directItemCount: folder.directItemCount,
                childFolderCount: folder.childFolderCount
            )
        }
        if let event = context.currentEvent {
            agentCtx.currentEvent = .init(title: event.title, date: event.date, location: event.location)
        }
        if let contact = context.currentContact {
            agentCtx.currentContact = .init(name: contact.name, email: contact.email)
        }
        if let todo = context.currentTodo {
            agentCtx.currentTodo = .init(title: todo.title, status: todo.status)
        }
        agentCtx.selectedItemCount = context.selectedItemCount

        return agentCtx
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
        if runtimeSelection != .hermes, !streamingText.isEmpty {
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
        orchestratorThreadID = nil
        hermesConversationState = nil
        hermesSyncStatus = .idle
        provider.resetSession()
    }

    /// Start a new conversation (saves current one first).
    func newConversation() {
        saveCurrentConversation()
        stopStreaming()
        messages.removeAll()
        currentConversationID = nil
        orchestratorThreadID = nil
        hermesConversationState = nil
        hermesSyncStatus = .idle
        provider.resetSession()
    }

    // MARK: - Persistence

    /// Save the current conversation to disk.
    private func saveCurrentConversation() {
        guard let id = currentConversationID, !messages.isEmpty else { return }
        let title = conversationTitle
        storage.save(
            id: id,
            title: title,
            messages: messages,
            model: providerName,
            hermesState: runtimeSelection == .hermes ? hermesConversationState : nil
        )
    }

    /// Load a previous conversation by ID.
    func loadConversation(_ conversationID: UUID) {
        guard let loadedMessages = storage.loadMessages(for: conversationID) else { return }
        // Save current conversation first
        saveCurrentConversation()

        stopStreaming()
        messages = loadedMessages
        currentConversationID = conversationID
        restoreHermesStateForCurrentConversation()
        if hermesConversationState != nil {
            runtimeSelection = .hermes
            provider = foundationModelsProvider
            MLXModelManager.shared.isLocalModelEnabled = false
            MLXModelManager.shared.unloadModel()
            persistRuntimeSelection(.hermes)
        }
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

    private func restoreHermesStateForCurrentConversation() {
        guard let currentConversationID,
              let meta = storage.metadata(for: currentConversationID),
              meta.runtimeID == "hermes",
              let activeRuntimeSessionID = meta.activeRuntimeSessionID
        else {
            hermesConversationState = nil
            return
        }

        hermesConversationState = HermesConversationState(
            conversationID: currentConversationID,
            runtimeID: meta.runtimeID ?? "hermes",
            activeRuntimeSessionID: activeRuntimeSessionID,
            runtimeSessionLineage: meta.runtimeSessionLineage,
            title: meta.title,
            source: meta.runtimeSource,
            lastSyncedAt: meta.runtimeLastSyncedAt
        )
    }

    // MARK: - Context Updates

    func updateContext(bookmark: (title: String, url: String, summary: String?)? = nil,
                       note: (title: String, excerpt: String)? = nil,
                       folder: (name: String, directItemCount: Int, childFolderCount: Int)? = nil,
                       event: (title: String, date: String, location: String)? = nil,
                       contact: (name: String, email: String)? = nil,
                       todo: (title: String, status: String)? = nil,
                       selectedCount: Int = 0) {
        context.currentBookmark = bookmark
        context.currentNote = note
        context.currentFolder = folder
        context.currentEvent = event
        context.currentContact = contact
        context.currentTodo = todo
        context.selectedItemCount = selectedCount
    }

    func clearContext() {
        context = AIAssistantContext()
    }

    func refreshRuntimeHealth() {
        guard useOrchestrator else { return }
        Task {
            runtimeHealth = await AgentOrchestrator.shared.runtimeHealth()
        }
    }

    private func persistRuntimeSelection(_ selection: AIAgentRuntimeSelection) {
        UserDefaults.standard.set(selection.rawValue, forKey: Self.runtimeSelectionDefaultsKey)
    }

    private static func loadPersistedRuntimeSelection() -> AIAgentRuntimeSelection {
        guard let raw = UserDefaults.standard.string(forKey: runtimeSelectionDefaultsKey),
              let selection = AIAgentRuntimeSelection(rawValue: raw)
        else {
            return MLXModelManager.shared.isLocalModelEnabled ? .localModel : .appleIntelligence
        }
        return selection
    }
}
