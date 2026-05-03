import Foundation
import AppKit
import os.log

enum AIAgentRuntimeSelection: String, Sendable {
    case appleIntelligence
    case localModel
    case codexCLI
    case hermes
}

enum HermesPanelSyncStatus: Equatable {
    case notAttached
    case idle
    case syncing
    case sending
    case running(runID: String?, detail: String?)
    case waitingForApproval(String?)
    case staleSession(String)
    case disconnected(String)
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
    @Published private(set) var scrollToBottomSignal = UUID()
    @Published private(set) var hasLiveHermesResponseForActiveSend = false

    /// Current conversation ID (nil = no active conversation yet).
    @Published var currentConversationID: UUID?
    @Published private(set) var runtimeSelection: AIAgentRuntimeSelection = .appleIntelligence
    @Published private(set) var runtimeHealth: AgentRuntimeHealth = .idle
    @Published private(set) var hermesConversationState: HermesConversationState?
    @Published private(set) var hermesSyncStatus: HermesPanelSyncStatus = .idle
    @Published private(set) var activeHermesRunID: String?
    @Published private(set) var hermesChats: [CiderAgentChatRecord] = []

    private let logger = Logger(subsystem: "com.cider.app", category: "AIAssistant")
    private var provider: AIAssistantProvider
    private let storage = AIConversationStorage.shared
    private let hermesSessionService = HermesSessionService()
    private let hermesBridgeTransport: any HermesBridgeTransport
    private let hermesTurnCoordinator: HermesTurnCoordinator
    private let agentChatRegistry: CiderAgentChatRegistry
    private var streamTask: Task<Void, Never>?
    private var typewriterTask: Task<Void, Never>?
    private var hermesSyncInFlight = false
    private var activeHermesChatStableID: String?

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
        case .notAttached:
            return "Attach Hermes"
        case .idle:
            guard runtimeSelection == .hermes else { return "" }
            if hermesConversationState?.activeRuntimeSessionID.isEmpty == true {
                return "Fresh session"
            }
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
        case .running(_, let detail):
            return detail ?? "Hermes is running"
        case .waitingForApproval(let detail):
            return detail ?? "Waiting for approval"
        case .staleSession(let detail):
            return detail.isEmpty ? "Session needs repair" : detail
        case .disconnected(let detail):
            return detail.isEmpty ? "Hermes disconnected" : detail
        case .error(let message):
            return message
        }
    }

    var hermesSessionLabel: String {
        guard let sessionID = hermesConversationState?.activeRuntimeSessionID else {
            return "No session"
        }
        guard !sessionID.isEmpty else { return "Fresh" }
        return String(sessionID.suffix(8))
    }

    var currentChatTitle: String {
        guard runtimeSelection == .hermes else { return "Main Brain" }
        if hermesConversationState == nil { return "Hermes" }
        if let record = currentHermesChatRecord() {
            return record.title
        }
        return currentHermesConversationIsMainBrain() ? CiderAgentChatRegistry.mainBrainTitle : "Hermes Chat"
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

    init(
        provider: AIAssistantProvider? = nil,
        agentChatRegistry: CiderAgentChatRegistry = .shared,
        hermesBridgeTransport: any HermesBridgeTransport = HermesRunTransport(),
        hermesTurnCoordinator: HermesTurnCoordinator = .shared
    ) {
        let initialRuntimeSelection = Self.loadPersistedRuntimeSelection()
        runtimeSelection = initialRuntimeSelection
        self.agentChatRegistry = agentChatRegistry
        self.hermesBridgeTransport = hermesBridgeTransport
        self.hermesTurnCoordinator = hermesTurnCoordinator
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
        refreshHermesChats()
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
            if handleCiderChatCommandIfNeeded(trimmed) {
                return
            }
            sendViaHermes(trimmed)
            return
        }

        // Start a new conversation if none active
        if currentConversationID == nil {
            currentConversationID = UUID()
        }

        let userMessage = AIAssistantMessage(role: .user, content: trimmed)
        messages.append(userMessage)
        requestScrollToBottom()

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
              hermesConversationState != nil,
              !isStreaming,
              !hermesSyncInFlight,
              hermesSyncStatus != .syncing,
              hermesSyncStatus != .sending,
              shouldStartHermesSync()
        else { return }
        Task {
            await syncHermesConversation(attachIfNeeded: false)
        }
    }

    private func shouldStartHermesSync() -> Bool {
        guard let lastSyncedAt = hermesConversationState?.lastSyncedAt else { return true }
        return Date().timeIntervalSince(lastSyncedAt) > 5
    }

    private func handleCiderChatCommandIfNeeded(_ text: String) -> Bool {
        let command: CiderChatCommand?
        do {
            command = try CiderChatCommandRouter.parse(text)
        } catch {
            appendCiderCommandMessage(error.localizedDescription)
            return true
        }

        guard let command else { return false }

        switch command.action {
        case .localMessage(let message):
            appendCiderCommandMessage(message)
        case .showStatus:
            Task {
                let availability = await hermesBridgeTransport.availability()
                appendCiderCommandMessage(hermesCommandStatusMessage(availability: availability))
            }
        case .showLastResponse:
            appendCiderCommandMessage(lastHermesAssistantResponseMessage())
        case .resume(let title):
            Task {
                await resumeHermesChat(title: title)
            }
        case .sendToHermes(let prompt):
            sendViaHermes(prompt)
        case .startFreshChat:
            startFreshHermesSession()
            appendCiderCommandMessage("Started a fresh Hermes chat. Your canonical Cider brain is still resumable with /resume Cider.")
        case .renameCurrentChat(let title):
            Task {
                await renameCurrentHermesChat(to: title)
            }
        }

        return true
    }

    private func appendCiderCommandMessage(_ content: String) {
        if currentConversationID == nil {
            currentConversationID = UUID()
        }
        messages.append(AIAssistantMessage(
            role: .assistant,
            content: content,
            sourceID: "cider-command:\(UUID().uuidString)",
            sourceName: "Cider"
        ))
        requestScrollToBottom()
        saveCurrentConversation()
    }

    private func hermesCommandStatusMessage(availability: HermesBridgeAvailability) -> String {
        let transport: String
        switch availability {
        case .apiRuns:
            transport = "Hermes Runs/SSE API"
        case .cliFallback:
            transport = "CLI/export fallback"
        case .unavailable(let message):
            transport = "Unavailable: \(message)"
        }

        let activeSessionID = hermesConversationState?.activeRuntimeSessionID ?? ""
        let session = activeSessionID.isEmpty ? "not attached" : activeSessionID
        let title = hermesConversationState?.title
            ?? currentHermesChatRecord()?.hermesTitle
            ?? currentChatTitle
        let lineageCount = hermesConversationState?.runtimeSessionLineage
            .filter { !$0.isEmpty }
            .count ?? 0

        return """
        Cider Hermes status:
        Chat: \(currentChatTitle)
        Hermes title: \(title)
        Session: \(session)
        Lineage sessions: \(lineageCount)
        State: \(hermesStatusTitle)
        Transport: \(transport)
        """
    }

    private func lastHermesAssistantResponseMessage() -> String {
        guard let message = messages.reversed().first(where: {
            $0.role == .assistant
                && $0.sourceName != "Cider"
                && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            return "No cached Hermes assistant response yet."
        }
        return message.content
    }

    private func activateHermesConversation() async {
        do {
            guard let mainBrain = try agentChatRegistry.loadMainBrain() else {
                saveCurrentConversation()
                currentConversationID = currentConversationID ?? UUID()
                activeHermesChatStableID = nil
                messages = []
                hermesConversationState = nil
                hermesSyncStatus = .notAttached
                return
            }

            saveCurrentConversation()
            activeHermesChatStableID = mainBrain.stableID
            currentConversationID = mainBrain.conversationID
            if let loadedMessages = storage.loadMessages(for: mainBrain.conversationID) {
                messages = loadedMessages
            } else {
                messages = []
            }
            hermesConversationState = HermesConversationState(
                conversationID: mainBrain.conversationID,
                runtimeID: mainBrain.runtimeID,
                activeRuntimeSessionID: mainBrain.activeRuntimeSessionID,
                runtimeSessionLineage: mainBrain.runtimeSessionLineage,
                title: mainBrain.hermesTitle ?? mainBrain.title,
                source: nil,
                lastSyncedAt: nil,
                lastSyncedMessageID: mainBrain.lastSyncedMessageID,
                lastSyncedTimestamp: mainBrain.lastSyncedTimestamp,
                lastImportedRuntimeSessionID: mainBrain.lastImportedRuntimeSessionID
            )
        } catch {
            logger.error("Failed to load Cider Main Brain: \(error.localizedDescription, privacy: .public)")
            hermesSyncStatus = .error(error.localizedDescription)
            return
        }

        await syncHermesConversation(attachIfNeeded: false)
    }

    func attachLatestHermesTelegramSession() {
        guard runtimeSelection == .hermes, !hermesSyncInFlight, !isStreaming else { return }
        Task {
            hermesSyncInFlight = true
            defer { hermesSyncInFlight = false }
            hermesSyncStatus = .syncing
            do {
                saveCurrentConversation()
                let conversationID = try mainBrainConversationIDForAttachment()
                currentConversationID = conversationID
                let result = try await hermesSessionService.attachLatestTelegramConversation(
                    conversationID: conversationID
                )
                hermesConversationState = result.state
                persistMainBrainState(result.state)
                messages = result.messages
                hermesSyncStatus = .idle
                saveCurrentConversation()
                requestScrollToBottom()
            } catch {
                logger.error("Hermes attach error: \(error.localizedDescription, privacy: .public)")
                hermesSyncStatus = .error(error.localizedDescription)
            }
        }
    }

    func attachHermesSession(id sessionID: String) {
        guard runtimeSelection == .hermes, !hermesSyncInFlight, !isStreaming else { return }
        Task {
            hermesSyncInFlight = true
            defer { hermesSyncInFlight = false }
            hermesSyncStatus = .syncing
            do {
                saveCurrentConversation()
                let conversationID = try mainBrainConversationIDForAttachment()
                currentConversationID = conversationID
                let result = try await hermesSessionService.attachConversation(
                    sessionID: sessionID,
                    conversationID: conversationID
                )
                hermesConversationState = result.state
                persistMainBrainState(result.state)
                messages = result.messages
                hermesSyncStatus = .idle
                saveCurrentConversation()
                requestScrollToBottom()
            } catch {
                logger.error("Hermes session attach error: \(error.localizedDescription, privacy: .public)")
                hermesSyncStatus = .error(error.localizedDescription)
            }
        }
    }

    func relinkMainBrainToActiveHermesSession() {
        guard runtimeSelection == .hermes,
              !hermesSyncInFlight,
              !isStreaming
        else { return }
        if hermesConversationState == nil {
            attachLatestHermesTelegramSession()
        } else {
            Task {
                await repairHermesConversation()
            }
        }
    }

    private func repairHermesConversation() async {
        guard runtimeSelection == .hermes else { return }
        guard !hermesSyncInFlight else { return }
        hermesSyncInFlight = true
        defer { hermesSyncInFlight = false }
        hermesSyncStatus = .syncing

        do {
            let state = try await ensureHermesConversationState(attachIfNeeded: false)
            let result = try await hermesSessionService.repairConversation(
                state: state,
                existingMessages: messages
            )
            let messagesChanged = messages != result.messages
            let stateChanged = hasDurableHermesStateChange(from: hermesConversationState, to: result.state)
            hermesConversationState = result.state
            persistHermesStateForCurrentChat(result.state)
            if messagesChanged {
                messages = result.messages
                requestScrollToBottom()
            }
            hermesSyncStatus = .idle
            if messagesChanged || stateChanged {
                saveCurrentConversation()
            }
        } catch {
            logger.error("Hermes repair error: \(error.localizedDescription, privacy: .public)")
            setHermesSyncStatus(for: error)
        }
    }

    func startFreshHermesSession() {
        guard runtimeSelection == .hermes, !isStreaming else { return }
        saveCurrentConversation()
        let conversationID = UUID()
        activeHermesChatStableID = nil
        currentConversationID = conversationID
        messages = []
        hermesConversationState = HermesConversationState(
            conversationID: conversationID,
            activeRuntimeSessionID: "",
            runtimeSessionLineage: [],
            title: "Hermes Chat",
            source: "cider"
        )
        hermesSyncStatus = .idle
        requestScrollToBottom()
    }

    func createNamedHermesChat(title: String, scope: String? = nil) {
        guard runtimeSelection == .hermes, !isStreaming else { return }
        do {
            saveCurrentConversation()
            let record = try agentChatRegistry.createHermesChat(title: title, scope: scope)
            refreshHermesChats()
            openHermesChat(record)
        } catch {
            logger.error("Hermes chat create error: \(error.localizedDescription, privacy: .public)")
            hermesSyncStatus = .error(error.localizedDescription)
        }
    }

    func loadHermesChat(stableID: String) {
        guard runtimeSelection == .hermes, !isStreaming else { return }
        do {
            guard let record = try agentChatRegistry.loadChat(stableID: stableID) else { return }
            saveCurrentConversation()
            openHermesChat(record)
        } catch {
            logger.error("Hermes chat load error: \(error.localizedDescription, privacy: .public)")
            hermesSyncStatus = .error(error.localizedDescription)
        }
    }

    func copyTelegramResumeCommandForCurrentHermesChat() {
        guard let record = currentHermesChatRecord() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            CiderAgentChatRegistry.telegramResumeCommand(for: record),
            forType: .string
        )
    }

    func clearHermesError() {
        if case .error = hermesSyncStatus {
            hermesSyncStatus = hermesConversationState == nil ? .notAttached : .idle
        } else if case .staleSession = hermesSyncStatus {
            hermesSyncStatus = hermesConversationState == nil ? .notAttached : .idle
        } else if case .disconnected = hermesSyncStatus {
            hermesSyncStatus = hermesConversationState == nil ? .notAttached : .idle
        }
    }

    private func resumeHermesChat(title: String) async {
        guard runtimeSelection == .hermes, !hermesSyncInFlight, !isStreaming else { return }
        let sanitizedTitle = CiderAgentChatRegistry.sanitizedHermesTitle(title)
        guard !sanitizedTitle.isEmpty else {
            appendCiderCommandMessage("Missing session title. Try /resume Cider.")
            return
        }

        do {
            saveCurrentConversation()
            let record: CiderAgentChatRecord
            if isCanonicalCiderTitle(sanitizedTitle) {
                if let existing = try agentChatRegistry.loadMainBrain() {
                    record = existing
                } else {
                    let state = HermesConversationState(
                        conversationID: UUID(),
                        activeRuntimeSessionID: "",
                        runtimeSessionLineage: [],
                        title: CiderAgentChatRegistry.mainBrainTitle,
                        source: nil
                    )
                    record = try agentChatRegistry.createMainBrain(from: state)
                }
            } else if let existing = try agentChatRegistry
                .listChats(includeArchived: true)
                .first(where: { record in
                    CiderAgentChatRegistry.sanitizedHermesTitle(record.hermesTitle ?? record.title)
                        .caseInsensitiveCompare(sanitizedTitle) == .orderedSame
                }) {
                record = existing
            } else {
                record = try agentChatRegistry.createHermesChat(title: sanitizedTitle)
            }

            openHermesChat(record, syncIfAttached: false)
            await repairHermesConversation()
            if case .idle = hermesSyncStatus {
                appendCiderCommandMessage("Resumed \(record.hermesTitle ?? record.title).")
            } else {
                appendCiderCommandMessage("Could not fully resume \(record.hermesTitle ?? record.title): \(hermesStatusTitle)")
            }
        } catch {
            logger.error("Hermes resume command error: \(error.localizedDescription, privacy: .public)")
            setHermesSyncStatus(for: error)
            appendCiderCommandMessage("Hermes resume error: \(error.localizedDescription)")
        }
    }

    private func renameCurrentHermesChat(to title: String) async {
        guard runtimeSelection == .hermes, !hermesSyncInFlight, !isStreaming else { return }
        let sanitizedTitle = CiderAgentChatRegistry.sanitizedHermesTitle(title)
        guard !sanitizedTitle.isEmpty else {
            appendCiderCommandMessage("Missing title. Try /title Cider Scratchpad.")
            return
        }

        guard let record = currentHermesChatRecord() else {
            appendCiderCommandMessage("This chat is not in the Cider Hermes registry yet. Create or load a named Hermes chat before renaming it.")
            return
        }

        guard record.stableID != CiderAgentChatRegistry.mainBrainStableID else {
            appendCiderCommandMessage("Cider is the canonical Main Brain name. I won't rename its Hermes title away from /resume Cider in v1.")
            return
        }

        do {
            let renamed = try agentChatRegistry.renameChat(stableID: record.stableID, title: sanitizedTitle)
            if !record.activeRuntimeSessionID.isEmpty {
                try await hermesSessionService.renameSession(
                    sessionID: record.activeRuntimeSessionID,
                    title: sanitizedTitle
                )
            }
            activeHermesChatStableID = renamed.stableID
            if var state = hermesConversationState {
                state.title = sanitizedTitle
                hermesConversationState = state
            }
            refreshHermesChats()
            saveCurrentConversation()
            appendCiderCommandMessage("Renamed this Hermes chat to \(sanitizedTitle). Telegram can resume it with /resume \(sanitizedTitle).")
        } catch {
            logger.error("Hermes title command error: \(error.localizedDescription, privacy: .public)")
            setHermesSyncStatus(for: error)
            appendCiderCommandMessage("Hermes title error: \(error.localizedDescription)")
        }
    }

    private func isCanonicalCiderTitle(_ title: String) -> Bool {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["cider", "main brain", "vault", "brain"].contains(normalized)
    }

    private func sendViaHermes(_ text: String) {
        streamTask = Task {
            isStreaming = true
            streamingText = ""
            displayedStreamingText = ""
            hasLiveHermesResponseForActiveSend = false
            activeHermesRunID = nil
            hermesSyncStatus = .sending
            requestScrollToBottom()
            startTypewriterLoop()

            do {
                let turnID = try await hermesTurnCoordinator.beginTurn()
                do {
                let state = try await ensureHermesConversationState(attachIfNeeded: false)
                let chatRecord = currentHermesChatRecord()
                let shouldRenameBackingSession = chatRecord?.kind != CiderAgentChatRegistry.mainBrainKind
                    && state.activeRuntimeSessionID.isEmpty
                let pendingMessage = AIAssistantMessage(
                    role: .user,
                    content: text,
                    sourceID: "hermes:pending:\(UUID().uuidString)",
                    sourceName: "Hermes Pending"
                )
                messages.append(pendingMessage)
                requestScrollToBottom()

                let existingMessages = messages.filter { $0.id != pendingMessage.id }
                var result = try await hermesBridgeTransport.send(
                    text: text,
                    state: state,
                    existingMessages: existingMessages,
                    onEvent: { [weak self] event in
                        await MainActor.run {
                            self?.applyHermesRunEvent(event)
                        }
                    }
                )
                if shouldRenameBackingSession,
                   let chatRecord,
                   let hermesTitle = chatRecord.hermesTitle,
                   !result.state.activeRuntimeSessionID.isEmpty {
                    try await hermesSessionService.renameSession(
                        sessionID: result.state.activeRuntimeSessionID,
                        title: hermesTitle
                    )
                    result = HermesBridgeSendResult(
                        state: HermesConversationState(
                            conversationID: result.state.conversationID,
                            runtimeID: result.state.runtimeID,
                            activeRuntimeSessionID: result.state.activeRuntimeSessionID,
                            runtimeSessionLineage: result.state.runtimeSessionLineage,
                            title: hermesTitle,
                            source: result.state.source,
                            lastSyncedAt: result.state.lastSyncedAt,
                            lastSyncedMessageID: result.state.lastSyncedMessageID,
                            lastSyncedTimestamp: result.state.lastSyncedTimestamp,
                            lastImportedRuntimeSessionID: result.state.lastImportedRuntimeSessionID
                        ),
                        messages: result.messages
                    )
                }
                await hermesTurnCoordinator.endTurn(turnID)
                applyHermesSyncResult(
                    HermesSyncResult(state: result.state, messages: result.messages),
                    forceMessages: true
                )
                hermesSyncStatus = result.state.activeRuntimeSessionID.isEmpty ? .notAttached : .idle
                saveCurrentConversation()
                } catch {
                    await hermesTurnCoordinator.endTurn(turnID)
                    throw error
                }
            } catch is CancellationError {
                logger.debug("Hermes send cancelled")
                hermesSyncStatus = hermesConversationState == nil ? .notAttached : .idle
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
                requestScrollToBottom()
                saveCurrentConversation()
            }

            await finishTypewriter()
            streamingText = ""
            displayedStreamingText = ""
            hasLiveHermesResponseForActiveSend = false
            activeHermesRunID = nil
            isStreaming = false
        }
    }

    private func applyHermesRunEvent(_ event: HermesRunEvent) {
        switch event {
        case .runStarted(let runID):
            activeHermesRunID = runID
            hermesSyncStatus = .running(runID: runID, detail: nil)
        case .messageDelta(let delta):
            streamingText += delta
            hasLiveHermesResponseForActiveSend = true
        case .toolStarted(let name, let preview):
            hermesSyncStatus = .running(runID: activeHermesRunID, detail: preview ?? name)
        case .toolCompleted:
            break
        case .reasoningAvailable(let preview):
            if !preview.isEmpty {
                hermesSyncStatus = .running(runID: activeHermesRunID, detail: preview)
            }
        case .approvalRequested(let detail):
            hermesSyncStatus = .waitingForApproval(detail)
        case .completed(let output):
            if !output.isEmpty, streamingText.isEmpty {
                streamingText = output
            }
            hasLiveHermesResponseForActiveSend = true
            hermesSyncStatus = .idle
        case .failed(let message):
            hermesSyncStatus = .error(message)
        case .cancelled:
            hermesSyncStatus = hermesConversationState == nil ? .notAttached : .idle
        }
        requestScrollToBottom()
    }

    private func makeHermesSendProgressTask(baseMessages: [AIAssistantMessage]) -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            while !Task.isCancelled {
                await self?.syncHermesSendProgress(baseMessages: baseMessages)
                try? await Task.sleep(for: .milliseconds(900))
            }
        }
    }

    private func syncHermesSendProgress(baseMessages: [AIAssistantMessage]) async {
        guard runtimeSelection == .hermes,
              let state = hermesConversationState
        else { return }

        do {
            let result = try await hermesSessionService.syncFromSessionFile(
                state: state,
                existingMessages: baseMessages
            )
            let baseSourceIDs = Set(baseMessages.compactMap(\.sourceID))
            if result.messages.contains(where: { $0.role == .assistant && !baseSourceIDs.contains($0.sourceID ?? "") }) {
                hasLiveHermesResponseForActiveSend = true
            }
            applyHermesSyncResult(result, forceMessages: result.messages.count >= messages.count)
        } catch {
            logger.debug("Hermes live send sync skipped: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func applyHermesSyncResult(_ result: HermesSyncResult, forceMessages: Bool) {
        let messagesChanged = messages != result.messages
        hermesConversationState = result.state
        persistHermesStateForCurrentChat(result.state)

        if forceMessages, messagesChanged {
            messages = result.messages
            requestScrollToBottom()
            saveCurrentConversation()
        }
    }

    func requestScrollToBottom() {
        scrollToBottomSignal = UUID()
    }

    private func syncHermesConversation(attachIfNeeded: Bool) async {
        guard runtimeSelection == .hermes else { return }
        guard !hermesSyncInFlight else { return }
        hermesSyncInFlight = true
        defer { hermesSyncInFlight = false }
        hermesSyncStatus = .syncing

        do {
            let state = try await ensureHermesConversationState(attachIfNeeded: attachIfNeeded)
            guard !state.activeRuntimeSessionID.isEmpty else {
                hermesSyncStatus = .idle
                return
            }
            let result: HermesSyncResult
            if currentHermesConversationIsMainBrain() {
                result = try await hermesSessionService.syncMainBrain(
                    state: state,
                    existingMessages: messages
                )
            } else {
                result = try await hermesSessionService.sync(
                    state: state,
                    existingMessages: messages
                )
            }
            let messagesChanged = messages != result.messages
            let stateChanged = hasDurableHermesStateChange(from: hermesConversationState, to: result.state)
            hermesConversationState = result.state
            persistHermesStateForCurrentChat(result.state)
            if messagesChanged {
                messages = result.messages
                requestScrollToBottom()
            }
            hermesSyncStatus = .idle
            if messagesChanged || stateChanged {
                saveCurrentConversation()
            }
        } catch {
            logger.error("Hermes sync error: \(error.localizedDescription, privacy: .public)")
            setHermesSyncStatus(for: error)
        }
    }

    private func setHermesSyncStatus(for error: Error) {
        if let hermesError = error as? HermesSessionClientError {
            switch hermesError {
            case .sessionNotFound:
                hermesSyncStatus = .staleSession(error.localizedDescription)
            case .stateDatabaseUnavailable:
                hermesSyncStatus = .disconnected(error.localizedDescription)
            default:
                hermesSyncStatus = .error(error.localizedDescription)
            }
        } else {
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

        if let currentConversationID,
           let currentRecord = try agentChatRegistry.chat(forConversationID: currentConversationID) {
            activeHermesChatStableID = currentRecord.stableID
            let state = HermesConversationState(
                conversationID: currentRecord.conversationID,
                runtimeID: currentRecord.runtimeID,
                activeRuntimeSessionID: currentRecord.activeRuntimeSessionID,
                runtimeSessionLineage: currentRecord.runtimeSessionLineage,
                title: currentRecord.hermesTitle ?? currentRecord.title,
                source: nil,
                lastSyncedAt: nil,
                lastSyncedMessageID: currentRecord.lastSyncedMessageID,
                lastSyncedTimestamp: currentRecord.lastSyncedTimestamp,
                lastImportedRuntimeSessionID: currentRecord.lastImportedRuntimeSessionID
            )
            hermesConversationState = state
            return state
        }

        if let mainBrain = try agentChatRegistry.loadMainBrain() {
            saveCurrentConversation()
            activeHermesChatStableID = mainBrain.stableID
            currentConversationID = mainBrain.conversationID
            if let loadedMessages = storage.loadMessages(for: mainBrain.conversationID) {
                messages = loadedMessages
            }
            let state = HermesConversationState(
                conversationID: mainBrain.conversationID,
                runtimeID: mainBrain.runtimeID,
                activeRuntimeSessionID: mainBrain.activeRuntimeSessionID,
                runtimeSessionLineage: mainBrain.runtimeSessionLineage,
                title: mainBrain.hermesTitle ?? mainBrain.title,
                source: nil,
                lastSyncedAt: nil,
                lastSyncedMessageID: mainBrain.lastSyncedMessageID,
                lastSyncedTimestamp: mainBrain.lastSyncedTimestamp,
                lastImportedRuntimeSessionID: mainBrain.lastImportedRuntimeSessionID
            )
            hermesConversationState = state
            return state
        }

        guard attachIfNeeded, let conversationID = currentConversationID else {
            throw HermesSessionClientError.sessionNotFound("Cider Main Brain is not attached to Hermes")
        }

        let result = try await hermesSessionService.attachLatestTelegramConversation(
            conversationID: conversationID
        )
        hermesConversationState = result.state
        persistMainBrainState(result.state)
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

    private func hasDurableHermesStateChange(
        from oldState: HermesConversationState?,
        to newState: HermesConversationState
    ) -> Bool {
        guard let oldState else { return true }
        return oldState.conversationID != newState.conversationID
            || oldState.runtimeID != newState.runtimeID
            || oldState.activeRuntimeSessionID != newState.activeRuntimeSessionID
            || oldState.runtimeSessionLineage != newState.runtimeSessionLineage
            || oldState.title != newState.title
            || oldState.source != newState.source
            || oldState.lastSyncedMessageID != newState.lastSyncedMessageID
            || oldState.lastSyncedTimestamp != newState.lastSyncedTimestamp
            || oldState.lastImportedRuntimeSessionID != newState.lastImportedRuntimeSessionID
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
        if runtimeSelection == .hermes, let runID = activeHermesRunID {
            Task {
                try? await hermesBridgeTransport.stop(runID: runID)
            }
        }
        if runtimeSelection != .hermes, !streamingText.isEmpty {
            let partialMessage = AIAssistantMessage(role: .assistant, content: streamingText)
            messages.append(partialMessage)
        }
        streamingText = ""
        displayedStreamingText = ""
        activeHermesRunID = nil
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

    private func persistMainBrainState(_ state: HermesConversationState) {
        guard runtimeSelection == .hermes else { return }
        do {
            _ = try agentChatRegistry.updateMainBrain(from: state)
            refreshHermesChats()
        } catch {
            logger.error("Failed to persist Cider Main Brain: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persistHermesStateForCurrentChat(_ state: HermesConversationState) {
        guard runtimeSelection == .hermes else { return }
        do {
            guard var record = currentHermesChatRecord() else {
                if currentHermesConversationIsMainBrain() {
                    persistMainBrainState(state)
                }
                return
            }

            if record.stableID == CiderAgentChatRegistry.mainBrainStableID {
                persistMainBrainState(state)
                return
            }

            record.conversationID = state.conversationID
            record.runtimeID = state.runtimeID
            record.activeRuntimeSessionID = state.activeRuntimeSessionID
            record.runtimeSessionLineage = state.runtimeSessionLineage
            record.lastSyncedMessageID = state.lastSyncedMessageID
            record.lastSyncedTimestamp = state.lastSyncedTimestamp
            record.lastImportedRuntimeSessionID = state.lastImportedRuntimeSessionID
            record.updatedAt = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
            try agentChatRegistry.updateChat(record)
            refreshHermesChats()
        } catch {
            logger.error("Failed to persist Hermes chat: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func mainBrainConversationIDForAttachment() throws -> UUID {
        if let mainBrain = try agentChatRegistry.loadMainBrain() {
            return mainBrain.conversationID
        }
        return UUID()
    }

    private func currentHermesConversationIsMainBrain() -> Bool {
        guard runtimeSelection == .hermes,
              let currentConversationID,
              let mainBrain = try? agentChatRegistry.loadMainBrain()
        else { return false }
        return mainBrain.conversationID == currentConversationID
    }

    private func currentHermesChatRecord() -> CiderAgentChatRecord? {
        if let activeHermesChatStableID,
           let record = try? agentChatRegistry.loadChat(stableID: activeHermesChatStableID) {
            return record
        }
        guard let currentConversationID else { return nil }
        return try? agentChatRegistry.chat(forConversationID: currentConversationID)
    }

    private func openHermesChat(_ record: CiderAgentChatRecord, syncIfAttached: Bool = true) {
        stopStreaming()
        activeHermesChatStableID = record.stableID
        currentConversationID = record.conversationID
        messages = storage.loadMessages(for: record.conversationID) ?? []
        hermesConversationState = HermesConversationState(
            conversationID: record.conversationID,
            runtimeID: record.runtimeID,
            activeRuntimeSessionID: record.activeRuntimeSessionID,
            runtimeSessionLineage: record.runtimeSessionLineage,
            title: record.hermesTitle ?? record.title,
            source: record.activeRuntimeSessionID.isEmpty ? "cider" : nil,
            lastSyncedAt: nil,
            lastSyncedMessageID: record.lastSyncedMessageID,
            lastSyncedTimestamp: record.lastSyncedTimestamp,
            lastImportedRuntimeSessionID: record.lastImportedRuntimeSessionID
        )
        hermesSyncStatus = record.activeRuntimeSessionID.isEmpty ? .idle : .syncing
        provider.resetSession()
        requestScrollToBottom()
        if syncIfAttached, !record.activeRuntimeSessionID.isEmpty {
            Task {
                await syncHermesConversation(attachIfNeeded: false)
            }
        }
    }

    private func refreshHermesChats() {
        hermesChats = (try? agentChatRegistry.listChats()) ?? []
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
        if let record = try? agentChatRegistry.chat(forConversationID: conversationID) {
            activeHermesChatStableID = record.stableID
        } else {
            activeHermesChatStableID = nil
        }
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
            lastSyncedAt: meta.runtimeLastSyncedAt,
            lastSyncedMessageID: meta.runtimeLastSyncedMessageID,
            lastSyncedTimestamp: meta.runtimeLastSyncedTimestamp,
            lastImportedRuntimeSessionID: meta.runtimeLastImportedSessionID
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
