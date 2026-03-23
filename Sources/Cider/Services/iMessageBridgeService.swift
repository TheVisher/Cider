import Foundation
import SQLite3
import os.log

/// Watches the local iMessage database for incoming messages and responds via Claude CLI.
///
/// Opens `~/Library/Messages/chat.db` read-only, polls every 2 seconds for new messages,
/// then spawns a `claude` process for each message and sends the reply back through Messages.app.
/// Requires Full Disk Access to read the iMessage database.
@MainActor
final class iMessageBridgeService: ObservableObject {
    static let shared = iMessageBridgeService()

    @Published var isEnabled: Bool = false {
        didSet {
            var config = CiderConfig.load()
            config.iMessageBridgeEnabled = isEnabled
            config.save()
            if isEnabled { start() } else { stop() }
        }
    }
    @Published var isRunning: Bool = false
    @Published var lastMessageAt: Date?
    @Published var messageCount: Int = 0

    private var pollingTask: Task<Void, Never>?
    private var lastSeenRowID: Int64 = 0
    private var cachedClaudePath: String?
    /// Track recently sent reply texts to avoid self-reply loops
    private var recentReplies: Set<String> = []
    /// Whether we're currently processing a message (prevents overlapping responses)
    private var isProcessing = false

    private var chatDBURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Messages/chat.db")
    }

    private let pollingInterval: TimeInterval = 2
    private let maxResponseLength = 2000

    private let logger = Logger(subsystem: "com.cider.app", category: "iMessageBridge")

    private init() {
        let config = CiderConfig.load()
        // Read initial state without triggering didSet
        isEnabled = config.iMessageBridgeEnabled
    }

    // MARK: - Start / Stop

    func start() {
        guard pollingTask == nil else { return }

        // Verify chat.db is accessible
        guard FileManager.default.isReadableFile(atPath: chatDBURL.path) else {
            logger.error("Cannot read iMessage database at \(self.chatDBURL.path). Full Disk Access required.")
            return
        }

        // Seed lastSeenRowID to the current max so we don't process old messages
        if lastSeenRowID == 0 {
            lastSeenRowID = fetchMaxRowID() ?? 0
        }

        logger.info("iMessage bridge starting. Last seen ROWID: \(self.lastSeenRowID)")
        isRunning = true

        pollingTask = Task { [weak self] in
            await self?.pollForNewMessages()
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        isRunning = false
        logger.info("iMessage bridge stopped.")
    }

    // MARK: - Polling

    private func pollForNewMessages() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
            } catch {
                break
            }

            guard !Task.isCancelled else { break }

            // Skip if we're already processing a message
            guard !isProcessing else { continue }

            let messages = fetchNewMessages()
            let config = CiderConfig.load()
            let allowedContacts = config.iMessageAllowedContacts

            for msg in messages {
                // Update tracking
                if msg.rowID > lastSeenRowID {
                    lastSeenRowID = msg.rowID
                }

                // Skip messages that match our recent replies (self-loop prevention)
                let trimmedText = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if recentReplies.contains(trimmedText) {
                    recentReplies.remove(trimmedText)
                    continue
                }

                // Filter by allowed contacts if the list is non-empty
                if !allowedContacts.isEmpty {
                    guard allowedContacts.contains(msg.sender) else {
                        logger.info("Ignoring message from non-allowed sender: \(msg.sender, privacy: .private)")
                        continue
                    }
                }

                // Skip empty messages
                guard !trimmedText.isEmpty else {
                    continue
                }

                // Only respond to messages that start with "Hey Cider" (case-insensitive)
                let triggerPrefix = "hey cider"
                guard trimmedText.lowercased().hasPrefix(triggerPrefix) else {
                    continue
                }
                // Strip the trigger phrase from the message before processing
                let strippedText = String(trimmedText.dropFirst(triggerPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)

                let messageToProcess = strippedText.isEmpty ? trimmedText : strippedText
                logger.info("Processing message from \(msg.sender, privacy: .private): \(messageToProcess.prefix(50), privacy: .private)")
                messageCount += 1
                lastMessageAt = Date()
                isProcessing = true

                await processMessage(messageToProcess, from: msg.sender, chatID: msg.chatID)

                // Re-seed lastSeenRowID after processing to skip any messages
                // generated during processing (including our own reply)
                if let currentMax = fetchMaxRowID() {
                    lastSeenRowID = currentMax
                }
                isProcessing = false
            }
        }
    }

    // MARK: - SQLite Reading

    private struct IncomingMessage {
        let rowID: Int64
        let text: String
        let sender: String
        let chatID: String
    }

    private func openDB() -> OpaquePointer? {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let result = sqlite3_open_v2(chatDBURL.path, &db, flags, nil)
        if result != SQLITE_OK {
            logger.error("Failed to open chat.db: \(String(cString: sqlite3_errmsg(db)))")
            sqlite3_close(db)
            return nil
        }
        return db
    }

    private func fetchMaxRowID() -> Int64? {
        guard let db = openDB() else { return nil }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let sql = "SELECT MAX(ROWID) FROM message"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_int64(stmt, 0)
        }
        return nil
    }

    private func fetchNewMessages() -> [IncomingMessage] {
        guard let db = openDB() else { return [] }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let sql = """
            SELECT m.ROWID, COALESCE(m.text, '') as message_text, h.id as sender,
                   COALESCE(m.cache_roomnames, '') as chat_room
            FROM message m
            LEFT JOIN handle h ON m.handle_id = h.ROWID
            WHERE m.ROWID > ? AND m.is_from_me = 0
            ORDER BY m.ROWID ASC
            """

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("Failed to prepare query: \(String(cString: sqlite3_errmsg(db)))")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, lastSeenRowID)

        var messages: [IncomingMessage] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowID = sqlite3_column_int64(stmt, 0)
            let text: String
            if let ptr = sqlite3_column_text(stmt, 1) {
                text = String(cString: ptr)
            } else {
                text = ""
            }
            let sender: String
            if let senderPtr = sqlite3_column_text(stmt, 2) {
                sender = String(cString: senderPtr)
            } else {
                sender = "unknown"
            }
            let chatRoom: String
            if let ptr = sqlite3_column_text(stmt, 3) {
                chatRoom = String(cString: ptr)
            } else {
                chatRoom = ""
            }

            // Build a chat identifier — for group chats use cache_roomnames, for 1:1 use the sender handle
            let chatID = chatRoom.isEmpty ? "iMessage;\(sender)" : chatRoom

            // Resolve the actual chat ID from the chat_message_join table
            let resolvedChatID = resolveChatID(db: db, messageRowID: rowID) ?? chatID

            messages.append(IncomingMessage(
                rowID: rowID,
                text: text,
                sender: sender,
                chatID: resolvedChatID
            ))
        }

        return messages
    }

    /// Look up the actual chat identifier string from the chat + chat_message_join tables.
    private func resolveChatID(db: OpaquePointer, messageRowID: Int64) -> String? {
        var stmt: OpaquePointer?
        let sql = """
            SELECT c.chat_identifier
            FROM chat c
            JOIN chat_message_join cmj ON c.ROWID = cmj.chat_id
            WHERE cmj.message_id = ?
            LIMIT 1
            """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, messageRowID)
        if sqlite3_step(stmt) == SQLITE_ROW, let ptr = sqlite3_column_text(stmt, 0) {
            return String(cString: ptr)
        }
        return nil
    }

    // MARK: - Claude Processing

    private func processMessage(_ text: String, from sender: String, chatID: String) async {
        guard let claudePath = resolveClaudePath() else {
            logger.error("Claude CLI not found — cannot process iMessage.")
            return
        }

        let config = CiderConfig.load()
        let vaultPath = (config.iMessageVaultPath as NSString).expandingTildeInPath

        let prompt = "You are responding to an iMessage from \(sender). Keep your response concise and conversational (under 300 words). Here is their message:\n\n\(text)"

        // Run Claude in a detached task to avoid blocking the main actor
        let responseText: String = await Task.detached { [maxResponseLength] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: claudePath)
            process.arguments = [
                "-p", prompt,
                "--output-format", "stream-json",
                "--verbose",
                "--dangerously-skip-permissions"
            ]
            process.currentDirectoryURL = URL(fileURLWithPath: vaultPath)
            process.standardInput = FileHandle.nullDevice

            // Build environment with expanded PATH
            var env = ProcessInfo.processInfo.environment
            let extraPaths = [
                "/usr/local/bin",
                "/opt/homebrew/bin",
                "\(NSHomeDirectory())/.npm/bin",
                "\(NSHomeDirectory())/.local/bin",
            ]
            let existing = env["PATH"] ?? "/usr/bin:/bin"
            env["PATH"] = (extraPaths + [existing]).joined(separator: ":")
            process.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                return ""
            }

            // Read all stdout data, then wait for exit
            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let output = String(data: data, encoding: .utf8) ?? ""
            let assembled = iMessageBridgeService.extractAssistantText(from: output)

            // Truncate for iMessage
            if assembled.count > maxResponseLength {
                return String(assembled.prefix(maxResponseLength)) + "..."
            }
            return assembled
        }.value

        guard !responseText.isEmpty else {
            logger.warning("Claude returned empty response for message from \(sender, privacy: .private)")
            return
        }

        logger.info("Sending reply (\(responseText.count) chars) to chat \(chatID, privacy: .private)")
        // Track this reply so we don't process it as an incoming message
        recentReplies.insert(responseText.trimmingCharacters(in: .whitespacesAndNewlines))
        iMessageSender.send(responseText, toChatID: chatID)
    }

    /// Parse Claude's stream-json output and extract the final assistant text.
    /// The stream-json format has one JSON object per line. We look for `result` type events
    /// that contain the assistant's response text.
    nonisolated static func extractAssistantText(from streamOutput: String) -> String {
        var assistantText = ""

        for line in streamOutput.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // Look for assistant content blocks
            if let type = json["type"] as? String {
                if type == "content_block_delta",
                   let delta = json["delta"] as? [String: Any],
                   let text = delta["text"] as? String {
                    assistantText += text
                } else if type == "result",
                          let result = json["result"] as? String {
                    // Some formats put the final text in result
                    if !result.isEmpty {
                        assistantText = result
                    }
                }
            }
        }

        return assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Reply

    private func sendReply(_ text: String, to chatID: String) {
        iMessageSender.send(text, toChatID: chatID)
    }

    // MARK: - Claude Path Resolution

    /// Resolve the full path to the `claude` binary by checking common locations
    /// and falling back to a login shell lookup (since GUI apps don't inherit shell PATH).
    private func resolveClaudePath() -> String? {
        if let cached = cachedClaudePath, FileManager.default.isExecutableFile(atPath: cached) {
            return cached
        }
        let knownPaths = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(NSHomeDirectory())/.npm/bin/claude",
            "\(NSHomeDirectory())/.local/bin/claude",
            "/Applications/cmux.app/Contents/Resources/bin/claude",
        ]
        for path in knownPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                cachedClaudePath = path
                return path
            }
        }
        // Fall back to login shell resolution
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
        whichProcess.arguments = ["-l", "-c", "which claude"]
        let pipe = Pipe()
        whichProcess.standardOutput = pipe
        whichProcess.standardError = FileHandle.nullDevice
        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !result.isEmpty && FileManager.default.isExecutableFile(atPath: result) {
                cachedClaudePath = result
                return result
            }
        } catch {
            logger.error("Failed to resolve claude path via shell: \(error.localizedDescription)")
        }
        return nil
    }

    /// Build an environment dictionary that includes the user's login shell PATH.
    private func buildShellEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Ensure PATH includes common locations
        let extraPaths = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "\(NSHomeDirectory())/.npm/bin",
            "\(NSHomeDirectory())/.local/bin",
        ]
        let existing = env["PATH"] ?? "/usr/bin:/bin"
        let combined = (extraPaths + [existing]).joined(separator: ":")
        env["PATH"] = combined
        return env
    }
}
