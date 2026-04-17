import Foundation
import os
import AppKit

/// Telegram-first remote chat bridge foundation.
/// This remains transport-only: routing, permissions, and vault actions stay in Cider.
actor TelegramBridge: ChannelBridge {
    static let shared = TelegramBridge()

    let channel: AgentChannel = .telegram
    let displayName = "Telegram"

    private let logger = Logger(subsystem: "com.cider.app", category: "TelegramBridge")
    private var configuration: TelegramBridgeConfiguration = .default
    private var state: TelegramBridgeState = .default
    private var lastInboundAt: Date?
    private var lastOutboundAt: Date?
    private var isRunning = false
    private var pollTask: Task<Void, Never>?
    private var inFlightUpdateIDs: Set<Int> = []
    private let quickAckDelay: Duration = .milliseconds(900)
    private let longTurnNoticeDelay: Duration = .seconds(75)

    private init() {}

    func updateConfiguration(_ configuration: TelegramBridgeConfiguration) {
        self.configuration = configuration
        saveConfiguration()
    }

    func start() async throws {
        try loadPersistedState()

        guard configuration.isEnabled else {
            logger.info("Telegram bridge not enabled")
            return
        }

        guard !configuration.botToken.isEmpty else {
            throw AgentError.deliveryFailed("Telegram bot token is not configured")
        }

        guard pollTask == nil else { return }

        isRunning = true
        pollTask = Task {
            await self.pollLoop()
        }
        logger.info("Telegram bridge started")
    }

    func startIfConfigured() async {
        do {
            try bootstrapFilesIfNeeded()
            loadConfiguration()
            if configuration.isEnabled {
                try await start()
            }
        } catch {
            logger.error("Telegram bridge failed to start: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() async {
        isRunning = false
        pollTask?.cancel()
        pollTask = nil
        logger.info("Telegram bridge stopped")
    }

    func health() async -> ChannelBridgeHealth {
        let status: ChannelBridgeStatus
        let detail: String

        if !configuration.isEnabled {
            status = .idle
            detail = "Bridge is disabled in .cider/telegram/config.json"
        } else if configuration.botToken.isEmpty {
            status = .unavailable
            detail = "Bot token is missing"
        } else if configuration.allowedChatIDs.isEmpty {
            status = .degraded
            detail = configuration.allowFirstChatToPair
                ? "Waiting for first Telegram chat to pair"
                : "No allowed Telegram chat IDs configured"
        } else if isRunning {
            status = .available
            detail = "Ready for Telegram long polling or webhook delivery"
        } else {
            status = .idle
            detail = "Configured but not started"
        }

        return ChannelBridgeHealth(
            status: status,
            detail: detail,
            lastInboundAt: lastInboundAt,
            lastOutboundAt: lastOutboundAt
        )
    }

    func makeEnvelope(from update: TelegramUpdateEnvelope) -> AgentEnvelope {
        lastInboundAt = Date()
        return AgentEnvelope.telegram(
            text: update.text,
            threadID: UUID(),
            channelThreadID: String(update.chatID),
            context: .empty,
            senderID: String(update.senderID),
            senderDisplayName: update.senderDisplayName
        )
    }

    func markOutboundDelivery() {
        lastOutboundAt = Date()
    }

    func processReminders() async {
        loadConfiguration()
        let shouldProcessReminders = configuration.sendReminders
        let shouldProcessDigests = configuration.sendDailyDigest || configuration.sendWeeklyDigest
        guard configuration.isEnabled, !configuration.allowedChatIDs.isEmpty, shouldProcessReminders || shouldProcessDigests else {
            return
        }

        let (dateCards, todos, bookmarks, notes) = await MainActor.run {
            (
                DateCardStorage.shared.dateCards,
                TodoCardStorage.shared.todoCards,
                VaultBookmarkService.shared.bookmarks,
                NotesStorage.shared.notes
            )
        }
        let now = Date()

        if configuration.sendReminders {
            for card in dateCards {
                await processReminder(card, now: now)
            }

            for todo in todos {
                await processTodoReminder(todo, now: now)
            }
        }

        if configuration.sendDailyDigest {
            await processDailyDigest(
                dateCards: dateCards,
                todos: todos,
                bookmarks: bookmarks,
                notes: notes,
                now: now
            )
        }

        if configuration.sendWeeklyDigest {
            await processWeeklyDigest(dateCards: dateCards, now: now)
        }

        saveState()
    }

    // MARK: - Persistence

    private var telegramDirectory: URL {
        StoragePaths.cachedVaultDirectoryURL
            .appendingPathComponent(StoragePaths.ciderInternalDir)
            .appendingPathComponent("telegram")
    }

    private var configurationURL: URL {
        telegramDirectory.appendingPathComponent("config.json")
    }

    private var stateURL: URL {
        telegramDirectory.appendingPathComponent("state.json")
    }

    private var mediaDirectory: URL {
        telegramDirectory.appendingPathComponent("media")
    }

    private func bootstrapFilesIfNeeded() throws {
        try FileManager.default.createDirectory(at: telegramDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: configurationURL.path) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(TelegramBridgeConfiguration.default)
            try data.write(to: configurationURL, options: .atomic)
        }

        if !FileManager.default.fileExists(atPath: stateURL.path) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(TelegramBridgeState.default)
            try data.write(to: stateURL, options: .atomic)
        }
    }

    private func loadConfiguration() {
        do {
            let data = try Data(contentsOf: configurationURL)
            configuration = try JSONDecoder().decode(TelegramBridgeConfiguration.self, from: data)
        } catch {
            logger.error("Failed to load Telegram config: \(error.localizedDescription, privacy: .public)")
            configuration = .default
        }
    }

    private func saveConfiguration() {
        do {
            try FileManager.default.createDirectory(at: telegramDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(configuration)
            try data.write(to: configurationURL, options: .atomic)
            NotificationCenter.default.post(name: .telegramBridgeConfigurationChanged, object: nil)
        } catch {
            logger.error("Failed to save Telegram config: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadPersistedState() throws {
        loadConfiguration()
        do {
            let data = try Data(contentsOf: stateURL)
            state = try JSONDecoder().decode(TelegramBridgeState.self, from: data)
        } catch {
            logger.error("Failed to load Telegram state: \(error.localizedDescription, privacy: .public)")
            state = .default
            saveState()
        }
    }

    private func saveState() {
        do {
            try FileManager.default.createDirectory(at: telegramDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            logger.error("Failed to save Telegram state: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Polling

    private func pollLoop() async {
        logger.info("Telegram poll loop entered")
        while isRunning, !Task.isCancelled {
            do {
                loadConfiguration()
                guard configuration.isEnabled else {
                    isRunning = false
                    break
                }
                let updates = try await fetchUpdates(offset: state.lastProcessedUpdateID + 1)
                if !updates.isEmpty {
                    logger.info("Telegram fetched \(updates.count) update(s) starting at offset \(self.state.lastProcessedUpdateID + 1)")
                }
                for update in updates {
                    state.lastProcessedUpdateID = max(state.lastProcessedUpdateID, update.updateID)
                    if !inFlightUpdateIDs.insert(update.updateID).inserted {
                        continue
                    }
                    Task { [weak self] in
                        await self?.handleUpdateTask(update)
                    }
                }
                saveState()
            } catch {
                logger.error("Telegram poll error: \(error.localizedDescription, privacy: .public)")
                try? await Task.sleep(for: .seconds(3))
            }
        }
        logger.info("Telegram poll loop exited")
    }

    private func handleUpdateTask(_ update: TelegramUpdateEnvelope) async {
        defer { inFlightUpdateIDs.remove(update.updateID) }
        await handle(update: update)
    }

    private func fetchUpdates(offset: Int) async throws -> [TelegramUpdateEnvelope] {
        let request = try apiRequest(
            method: "getUpdates",
            queryItems: [
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "timeout", value: String(max(1, configuration.pollingTimeoutSeconds))),
                URLQueryItem(name: "allowed_updates", value: "[\"message\"]")
            ]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw AgentError.deliveryFailed("Telegram getUpdates failed")
        }

        let apiResponse = try JSONDecoder().decode(TelegramGetUpdatesResponse.self, from: data)
        guard apiResponse.ok else {
            throw AgentError.deliveryFailed(apiResponse.description ?? "Telegram getUpdates returned ok=false")
        }

        var envelopes: [TelegramUpdateEnvelope] = []
        for update in apiResponse.result {
            guard let envelope = await makeEnvelope(from: update) else { continue }
            envelopes.append(envelope)
        }
        return envelopes
    }

    private func handle(update: TelegramUpdateEnvelope) async {
        if configuration.allowedChatIDs.isEmpty, configuration.allowFirstChatToPair {
            configuration.allowedChatIDs = [update.chatID]
            configuration.allowFirstChatToPair = false
            saveConfiguration()
            logger.info("Paired first Telegram chat ID \(update.chatID)")
        }

        guard configuration.allowedChatIDs.contains(update.chatID) else {
            logger.info("Ignoring Telegram chat ID \(update.chatID) because it is not allowlisted")
            return
        }

        if let commandResponse = await handleCommandIfNeeded(update) {
            do {
                logger.info("Sending Telegram command response to chat \(update.chatID)")
                try await sendMessage(commandResponse, to: update.chatID)
            } catch {
                logger.error("Failed to send Telegram command response: \(error.localizedDescription, privacy: .public)")
            }
            return
        }

        let envelope = makeEnvelope(from: update)
        let responseTask = Task {
            try await AgentOrchestrator.shared.handleMessage(envelope)
        }
        let shouldSendQuickAck = Self.shouldSendQuickAcknowledgement(for: update.text)
        let quickAckTask = Task { [weak self] in
            guard shouldSendQuickAck else { return }
            try? await Task.sleep(for: self?.quickAckDelay ?? .seconds(3))
            guard let self, !Task.isCancelled else { return }
            let ack = Self.quickAcknowledgement(for: update.text)
            do {
                logger.info("Sending Telegram quick ack to chat \(update.chatID)")
                try await self.sendMessage(ack, to: update.chatID)
            } catch {
                logger.error("Failed to send Telegram quick ack: \(error.localizedDescription, privacy: .public)")
            }
        }
        let progressTask = Task { [weak self] in
            try? await Task.sleep(for: self?.longTurnNoticeDelay ?? .seconds(75))
            guard let self, !Task.isCancelled else { return }
            do {
                logger.info("Sending Telegram long-turn notice to chat \(update.chatID)")
                try await self.sendMessage("Still working on that. I'll send the answer as soon as it's ready.", to: update.chatID)
            } catch {
                logger.error("Failed to send Telegram long-turn notice: \(error.localizedDescription, privacy: .public)")
            }
        }

        do {
            if let runtime = await AgentOrchestrator.shared.runtimeIdentity() {
                logger.info("Routing Telegram message to runtime \(runtime.id, privacy: .public)")
            }
            let response = try await responseTask.value
            quickAckTask.cancel()
            progressTask.cancel()
            if !response.text.isEmpty {
                logger.info("Sending Telegram runtime response to chat \(update.chatID)")
                try await sendMessage(response.text, to: update.chatID)
            }
        } catch {
            quickAckTask.cancel()
            progressTask.cancel()
            let message = "Cider error: \(error.localizedDescription)"
            do {
                logger.info("Sending Telegram error response to chat \(update.chatID)")
                try await sendMessage(message, to: update.chatID)
            } catch {
                logger.error("Failed to send Telegram error response: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func handleCommandIfNeeded(_ update: TelegramUpdateEnvelope) async -> String? {
        let text = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("/") else { return nil }

        let parts = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let command = parts.first?.lowercased() else { return nil }

        switch command {
        case "/help", "/agent":
            logger.info("Handling Telegram command \(command, privacy: .public)")
            return """
            Cider Telegram commands:
            /status — show bridge and runtime health
            /runtime — show active runtime
            /runtime codex|apple|local — switch runtime
            /restart — restart the active runtime
            """

        case "/status":
            logger.info("Handling Telegram command /status")
            return await statusSummary()

        case "/runtime":
            logger.info("Handling Telegram command /runtime")
            if parts.count == 1 {
                return await runtimeSummary()
            }
            guard let selection = parseRuntimeSelection(parts[1]) else {
                return "Unknown runtime. Use /runtime codex, /runtime apple, or /runtime local."
            }
            await AIAssistantViewModel.shared.switchRuntimeFromExternalCommand(to: selection)
            let summary = await runtimeSummary()
            return "Switched runtime.\n\(summary)"

        case "/restart":
            logger.info("Handling Telegram command /restart")
            await AgentOrchestrator.shared.stopRuntimeIfNeeded()
            do {
                try await AgentOrchestrator.shared.startRuntimeIfNeeded()
            } catch {
                return "Failed to restart runtime: \(error.localizedDescription)"
            }
            return "Runtime restarted.\n\(await runtimeSummary())"

        default:
            return "Unknown command. Send /help for available Telegram commands."
        }
    }

    private func parseRuntimeSelection(_ raw: String) -> AIAgentRuntimeSelection? {
        switch raw.lowercased() {
        case "codex", "codexcli", "codex-cli":
            return .codexCLI
        case "apple", "appleintelligence", "foundation":
            return .appleIntelligence
        case "local", "mlx", "qwen":
            return .localModel
        default:
            return nil
        }
    }

    private func runtimeSummary() async -> String {
        let runtime = await AgentOrchestrator.shared.runtimeIdentity()
        let health = await AgentOrchestrator.shared.runtimeHealth()
        let selection = await MainActor.run { AIAssistantViewModel.shared.runtimeSelection }

        var lines: [String] = []
        lines.append("Runtime selection: \(runtimeLabel(for: selection))")
        if let runtime {
            lines.append("Active runtime: \(runtime.displayName) (\(runtime.id))")
        } else {
            lines.append("Active runtime: none")
        }
        lines.append("Status: \(health.status.rawValue)")
        lines.append("Detail: \(health.detail)")
        if let lastError = health.lastError, !lastError.isEmpty {
            lines.append("Last error: \(lastError)")
        }
        return lines.joined(separator: "\n")
    }

    private func statusSummary() async -> String {
        let bridgeHealth = await health()
        let runtime = await runtimeSummary()
        let bridgeLines = [
            "Telegram bridge: \(bridgeHealth.status.rawValue)",
            "Bridge detail: \(bridgeHealth.detail)"
        ]
        return (bridgeLines + ["", runtime]).joined(separator: "\n")
    }

    private func runtimeLabel(for selection: AIAgentRuntimeSelection) -> String {
        switch selection {
        case .appleIntelligence:
            return "Apple Intelligence"
        case .localModel:
            return "Local Qwen"
        case .codexCLI:
            return "Codex CLI"
        }
    }

    private static func quickAcknowledgement(for text: String) -> String {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.contains("the user sent an image on telegram")
            || normalized.contains("caption:")
            || normalized.contains("ocr text from image:") {
            return "Got it. Let me look at that image."
        }

        if normalized.contains("http://") || normalized.contains("https://") || normalized.contains("www.") {
            return "Got it. Let me save that."
        }

        if ["save this", "save that", "add this", "capture this"].contains(where: normalized.contains) {
            return "Got it. Let me save that."
        }

        if ["how many", "count", "total", "number of"].contains(where: normalized.contains) {
            return "Checking your vault."
        }

        if ["find", "search", "look up", "lookup", "do i have", "what do i have", "show me"].contains(where: normalized.contains) {
            return "Let me look into that."
        }

        if ["birthday", "contact", "contacts", "event", "todo", "note", "bookmark"].contains(where: normalized.contains) {
            return "Okay. Let me check that."
        }

        return "Got it. Working on it now."
    }

    private static func shouldSendQuickAcknowledgement(for text: String) -> Bool {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty { return false }

        if normalized.count > 120 || normalized.contains("\n") {
            return true
        }

        let likelyLongSignals = [
            "http://", "https://", "www.",
            "save", "add", "capture", "bookmark",
            "find", "search", "look up", "lookup", "what do i have",
            "how many", "count", "total",
            "appointment", "event", "reminder", "date card",
            "the user sent an image on telegram", "ocr text from image:"
        ]
        return likelyLongSignals.contains(where: normalized.contains)
    }

    private func makeEnvelope(from update: TelegramUpdate) async -> TelegramUpdateEnvelope? {
        guard let message = update.message else { return nil }

        let displayName = [message.from?.firstName, message.from?.lastName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let text = await inboundText(for: message)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return TelegramUpdateEnvelope(
            updateID: update.updateID,
            chatID: message.chat.id,
            senderID: message.from?.id ?? message.chat.id,
            senderDisplayName: displayName.isEmpty ? message.from?.username : displayName,
            text: trimmed
        )
    }

    private func inboundText(for message: TelegramMessage) async -> String {
        let text = message.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let caption = message.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard let photo = message.photo?.max(by: { lhs, rhs in
            let lhsScore = (lhs.fileSize ?? 0) + lhs.width * lhs.height
            let rhsScore = (rhs.fileSize ?? 0) + rhs.width * rhs.height
            return lhsScore < rhsScore
        }) else {
            return !text.isEmpty ? text : caption
        }

        var lines: [String] = ["The user sent an image on Telegram."]
        if !caption.isEmpty {
            lines.append("Caption: \(caption)")
        } else if !text.isEmpty {
            lines.append("Message text: \(text)")
        }

        if let localURL = try? await downloadPhoto(fileID: photo.fileID) {
            lines.append("Local image copy: \(localURL.path)")
            if let ocrText = await OCRService.extractText(from: localURL)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !ocrText.isEmpty {
                lines.append("OCR text from image: \(ocrText)")
            } else {
                lines.append("OCR text from image: (none detected)")
            }
        } else {
            lines.append("Image download failed, so only caption/text context is available.")
        }

        return lines.joined(separator: "\n")
    }

    private func downloadPhoto(fileID: String) async throws -> URL {
        let request = try apiRequest(
            method: "getFile",
            queryItems: [URLQueryItem(name: "file_id", value: fileID)]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw AgentError.deliveryFailed("Telegram getFile failed")
        }

        let apiResponse = try JSONDecoder().decode(TelegramGetFileResponse.self, from: data)
        guard apiResponse.ok, let filePath = apiResponse.result?.filePath else {
            throw AgentError.deliveryFailed(apiResponse.description ?? "Telegram getFile returned ok=false")
        }

        guard !configuration.botToken.isEmpty else {
            throw AgentError.deliveryFailed("Telegram bot token is not configured")
        }

        let remoteURL = URL(string: "https://api.telegram.org/file/bot\(configuration.botToken)/\(filePath)")!
        let (fileData, fileResponse) = try await URLSession.shared.data(from: remoteURL)
        guard let fileHTTP = fileResponse as? HTTPURLResponse, 200..<300 ~= fileHTTP.statusCode else {
            throw AgentError.deliveryFailed("Telegram file download failed")
        }

        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let ext = URL(fileURLWithPath: filePath).pathExtension
        let localURL = mediaDirectory.appendingPathComponent("\(fileID).\(ext.isEmpty ? "jpg" : ext)")
        try fileData.write(to: localURL, options: .atomic)
        return localURL
    }

    // MARK: - Outbound

    func sendMessage(_ text: String, to chatID: Int64) async throws {
        let payload = TelegramSendMessageRequest(chatID: chatID, text: text)
        let request = try apiRequest(method: "sendMessage", body: payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw AgentError.deliveryFailed("Telegram sendMessage failed")
        }

        markOutboundDelivery()
    }

    private func apiRequest(method: String, queryItems: [URLQueryItem] = []) throws -> URLRequest {
        guard !configuration.botToken.isEmpty else {
            throw AgentError.deliveryFailed("Telegram bot token is not configured")
        }

        var components = URLComponents(string: "https://api.telegram.org/bot\(configuration.botToken)/\(method)")
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else {
            throw AgentError.deliveryFailed("Failed to build Telegram request URL")
        }

        return URLRequest(url: url)
    }

    private func apiRequest<T: Encodable>(method: String, body: T) throws -> URLRequest {
        var request = try apiRequest(method: method)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    // MARK: - Reminders

    private func processReminder(_ card: DateCard, now: Date) async {
        if card.isCompleted, card.recurrenceRule == nil { return }

        let reminderRules = card.rules.filter { $0.type == .remindBeforeMinutes && $0.isEnabled }
        let offsets: [Int]
        if reminderRules.isEmpty {
            let config = CiderConfig.load()
            offsets = [config.dateCardDefaultNotificationMinutes]
        } else {
            offsets = reminderRules.compactMap { $0.integerValue ?? 15 }
        }
        guard !offsets.isEmpty else { return }

        let horizon = now.addingTimeInterval(24 * 60 * 60)
        var cursor = card.effectiveDate(now: now)

        while cursor <= horizon {
            for minutesBefore in offsets {
                let fireDate = cursor.addingTimeInterval(-Double(minutesBefore) * 60)
                if fireDate <= now, fireDate > now.addingTimeInterval(-5 * 60) {
                    let reminderID = reminderIdentifier(cardID: card.id, occurrence: cursor, offset: minutesBefore)
                    if !state.deliveredReminderIDs.contains(reminderID) {
                        let message = reminderMessage(for: card, occurrence: cursor, minutesBefore: minutesBefore)
                        for chatID in configuration.allowedChatIDs {
                            do {
                                try await sendMessage(message, to: chatID)
                            } catch {
                                logger.error("Failed to deliver Telegram reminder: \(error.localizedDescription, privacy: .public)")
                            }
                        }
                        state.deliveredReminderIDs.insert(reminderID)
                    }
                }
            }

            guard let next = card.nextOccurrence(after: cursor) else { break }
            cursor = next
        }
    }

    private func processTodoReminder(_ todo: TodoCard, now: Date) async {
        guard !todo.isCompleted, let dueDate = todo.dueDate, todoHasExplicitTime(dueDate) else { return }

        let reminderRules = todo.rules.filter { $0.type == .remindBeforeMinutes && $0.isEnabled }
        let offsets = reminderRules.isEmpty ? [0] : reminderRules.compactMap { $0.integerValue ?? 0 }

        for minutesBefore in offsets {
            let fireDate = dueDate.addingTimeInterval(-Double(minutesBefore) * 60)
            guard fireDate <= now, fireDate > now.addingTimeInterval(-5 * 60) else { continue }

            let reminderID = todoReminderIdentifier(todoID: todo.id, dueDate: dueDate, offset: minutesBefore)
            guard !state.deliveredReminderIDs.contains(reminderID) else { continue }

            let message = todoReminderMessage(for: todo, dueDate: dueDate, minutesBefore: minutesBefore)
            for chatID in configuration.allowedChatIDs {
                do {
                    try await sendMessage(message, to: chatID)
                } catch {
                    logger.error("Failed to deliver Telegram todo reminder: \(error.localizedDescription, privacy: .public)")
                }
            }
            state.deliveredReminderIDs.insert(reminderID)
        }
    }

    private func processDailyDigest(
        dateCards: [DateCard],
        todos: [TodoCard],
        bookmarks: [Bookmark],
        notes: [Note],
        now: Date
    ) async {
        let calendar = Calendar.current
        let digestHour = min(max(configuration.dailyDigestHour, 0), 23)
        let currentHour = calendar.component(.hour, from: now)
        guard currentHour >= digestHour else { return }
        if configuration.dailyDigestWeekdaysOnly {
            let weekday = calendar.component(.weekday, from: now)
            guard (2...6).contains(weekday) else { return }
        }

        let dayKey = dayDigestKey(for: now)
        guard !state.deliveredDailyDigestKeys.contains(dayKey) else { return }

        state.resurfacedItemDates = DailyVaultReminderService.pruneResurfacedHistory(
            state.resurfacedItemDates,
            now: now,
            config: DailyVaultReminderService.Config(
                resurfacingItemCount: configuration.dailyDigestResurfaceCount,
                resurfacingMinAgeDays: configuration.dailyDigestResurfaceMinAgeDays,
                resurfacingCooldownDays: configuration.dailyDigestResurfaceCooldownDays
            )
        )

        guard let reminder = DailyVaultReminderService.buildReminder(
            now: now,
            dateCards: dateCards,
            todos: todos,
            bookmarks: bookmarks,
            notes: notes,
            resurfacedAt: state.resurfacedItemDates,
            config: DailyVaultReminderService.Config(
                resurfacingItemCount: configuration.dailyDigestResurfaceCount,
                resurfacingMinAgeDays: configuration.dailyDigestResurfaceMinAgeDays,
                resurfacingCooldownDays: configuration.dailyDigestResurfaceCooldownDays
            )
        ) else {
            state.deliveredDailyDigestKeys.insert(dayKey)
            return
        }

        for chatID in configuration.allowedChatIDs {
            do {
                try await sendMessage(reminder.message, to: chatID)
            } catch {
                logger.error("Failed to deliver Telegram daily digest: \(error.localizedDescription, privacy: .public)")
            }
        }
        logger.info("Delivered Telegram daily digest \(dayKey, privacy: .public)")
        state.deliveredDailyDigestKeys.insert(dayKey)
        for key in reminder.resurfacedItemKeys {
            state.resurfacedItemDates[key] = now
        }
    }

    private func processWeeklyDigest(dateCards: [DateCard], now: Date) async {
        let calendar = Calendar.current
        let digestHour = 8
        let currentHour = calendar.component(.hour, from: now)
        guard currentHour >= digestHour else { return }

        let weekKey = weekDigestKey(for: now)
        guard !state.deliveredWeeklyDigestKeys.contains(weekKey) else { return }

        let weekday = calendar.component(.weekday, from: now)
        guard weekday == 2 else { return } // Monday in Gregorian calendar

        let startOfToday = calendar.startOfDay(for: now)
        guard let weekHorizon = calendar.date(byAdding: .day, value: 7, to: startOfToday) else { return }

        let upcomingWeek = upcomingOccurrences(
            for: dateCards,
            from: startOfToday,
            to: weekHorizon.addingTimeInterval(-1),
            now: now
        )

        guard !upcomingWeek.isEmpty else {
            state.deliveredWeeklyDigestKeys.insert(weekKey)
            return
        }

        let message = weeklyDigestMessage(for: upcomingWeek, now: now)
        for chatID in configuration.allowedChatIDs {
            do {
                try await sendMessage(message, to: chatID)
            } catch {
                logger.error("Failed to deliver Telegram weekly digest: \(error.localizedDescription, privacy: .public)")
            }
        }
        logger.info("Delivered Telegram weekly digest \(weekKey, privacy: .public)")
        state.deliveredWeeklyDigestKeys.insert(weekKey)
    }

    private func todoReminderIdentifier(todoID: UUID, dueDate: Date, offset: Int) -> String {
        let iso = ISO8601DateFormatter().string(from: dueDate)
        return "todo-\(todoID.uuidString)-\(iso)-\(offset)min"
    }

    private func todoReminderMessage(for todo: TodoCard, dueDate: Date, minutesBefore: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short

        let timeDescription: String
        if minutesBefore == 0 {
            timeDescription = "now"
        } else if minutesBefore < 60 {
            timeDescription = "in \(minutesBefore) minute\(minutesBefore == 1 ? "" : "s")"
        } else if minutesBefore < 1440 {
            let hours = minutesBefore / 60
            timeDescription = "in \(hours) hour\(hours == 1 ? "" : "s")"
        } else {
            let days = minutesBefore / 1440
            timeDescription = "in \(days) day\(days == 1 ? "" : "s")"
        }

        var lines = [
            "Reminder: \(todo.title) is \(timeDescription).",
            "Date: \(formatter.string(from: dueDate))",
        ]
        if let priority = todo.priority {
            lines.append("Priority: \(priority.displayName)")
        }
        if !todo.details.isEmpty {
            lines.append("Details: \(todo.details)")
        }
        return lines.joined(separator: "\n")
    }

    private func todoHasExplicitTime(_ date: Date) -> Bool {
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return (components.hour ?? 0) != 0 || (components.minute ?? 0) != 0 || (components.second ?? 0) != 0
    }

    private struct ScheduledOccurrence {
        let card: DateCard
        let occurrence: Date
    }

    private func upcomingOccurrences(
        for dateCards: [DateCard],
        from start: Date,
        to end: Date,
        now: Date
    ) -> [ScheduledOccurrence] {
        var results: [ScheduledOccurrence] = []

        for card in dateCards {
            if card.isCompleted, card.recurrenceRule == nil { continue }

            if card.recurrenceRule != nil {
                var cursor = card.effectiveDate(now: now)
                while cursor <= end {
                    if cursor >= start {
                        results.append(ScheduledOccurrence(card: card, occurrence: cursor))
                    }
                    guard let next = card.nextOccurrence(after: cursor) else { break }
                    cursor = next
                }
            } else {
                let target = card.startAt
                if target >= start && target <= end {
                    results.append(ScheduledOccurrence(card: card, occurrence: target))
                }
            }
        }

        return results.sorted { lhs, rhs in
            if lhs.occurrence == rhs.occurrence {
                return lhs.card.title.localizedCaseInsensitiveCompare(rhs.card.title) == .orderedAscending
            }
            return lhs.occurrence < rhs.occurrence
        }
    }

    private func dailyDigestMessage(for occurrences: [ScheduledOccurrence], now: Date) -> String {
        var lines = ["Good morning. Here's what's due today:"]
        lines.append(contentsOf: formattedDigestLines(for: occurrences, now: now, includeWeekday: false))
        return lines.joined(separator: "\n")
    }

    private func weeklyDigestMessage(for occurrences: [ScheduledOccurrence], now: Date) -> String {
        var lines = ["This week's upcoming items:"]
        lines.append(contentsOf: formattedDigestLines(for: occurrences, now: now, includeWeekday: true))
        return lines.joined(separator: "\n")
    }

    private func formattedDigestLines(
        for occurrences: [ScheduledOccurrence],
        now: Date,
        includeWeekday: Bool
    ) -> [String] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.dateFormat = includeWeekday ? "EEE, MMM d" : "MMM d"

        return occurrences.prefix(8).map { scheduled in
            let dayText: String
            if calendar.isDateInToday(scheduled.occurrence) {
                dayText = "Today"
            } else if calendar.isDateInTomorrow(scheduled.occurrence) {
                dayText = "Tomorrow"
            } else {
                dayText = formatter.string(from: scheduled.occurrence)
            }

            let timeText: String
            if scheduled.card.allDay {
                timeText = "all day"
            } else {
                let timeFormatter = DateFormatter()
                timeFormatter.timeStyle = .short
                timeFormatter.dateStyle = .none
                timeFormatter.timeZone = .current
                timeText = timeFormatter.string(from: scheduled.occurrence)
            }

            return "- \(dayText): \(scheduled.card.title) (\(timeText))"
        }
    }

    private func dayDigestKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func weekDigestKey(for date: Date) -> String {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = comps.yearForWeekOfYear ?? calendar.component(.year, from: date)
        let week = comps.weekOfYear ?? 0
        return "\(year)-W\(week)"
    }

    private func reminderIdentifier(cardID: UUID, occurrence: Date, offset: Int) -> String {
        let formatter = ISO8601DateFormatter()
        return "\(cardID.uuidString)-\(formatter.string(from: occurrence))-\(offset)"
    }

    private func reminderMessage(for card: DateCard, occurrence: Date, minutesBefore: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short

        let timeDescription: String
        if minutesBefore == 0 {
            timeDescription = "now"
        } else if minutesBefore < 60 {
            timeDescription = "in \(minutesBefore) minute\(minutesBefore == 1 ? "" : "s")"
        } else if minutesBefore < 1440 {
            let hours = minutesBefore / 60
            timeDescription = "in \(hours) hour\(hours == 1 ? "" : "s")"
        } else {
            let days = minutesBefore / 1440
            timeDescription = "in \(days) day\(days == 1 ? "" : "s")"
        }

        var lines = ["Reminder: \(card.title) is \(timeDescription).", "Date: \(formatter.string(from: occurrence))"]
        if !card.location.isEmpty {
            lines.append("Location: \(card.location)")
        }
        if !card.details.isEmpty {
            lines.append("Details: \(card.details)")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Telegram API Models

private struct TelegramGetUpdatesResponse: Decodable {
    let ok: Bool
    let result: [TelegramUpdate]
    let description: String?
}

private struct TelegramUpdate: Decodable {
    let updateID: Int
    let message: TelegramMessage?

    private enum CodingKeys: String, CodingKey {
        case updateID = "update_id"
        case message
    }
}

private struct TelegramMessage: Decodable {
    let chat: TelegramChat
    let from: TelegramUser?
    let text: String?
    let caption: String?
    let photo: [TelegramPhotoSize]?
}

private struct TelegramPhotoSize: Decodable {
    let fileID: String
    let width: Int
    let height: Int
    let fileSize: Int?

    private enum CodingKeys: String, CodingKey {
        case fileID = "file_id"
        case width
        case height
        case fileSize = "file_size"
    }
}

private struct TelegramChat: Decodable {
    let id: Int64
}

private struct TelegramUser: Decodable {
    let id: Int64
    let username: String?
    let firstName: String?
    let lastName: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case username
        case firstName = "first_name"
        case lastName = "last_name"
    }
}

private struct TelegramSendMessageRequest: Encodable {
    let chatID: Int64
    let text: String

    private enum CodingKeys: String, CodingKey {
        case chatID = "chat_id"
        case text
    }
}

private struct TelegramGetFileResponse: Decodable {
    let ok: Bool
    let result: TelegramFileResult?
    let description: String?
}

private struct TelegramFileResult: Decodable {
    let filePath: String

    private enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
    }
}
