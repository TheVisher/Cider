import Foundation
import os.log

/// Metadata header for a conversation JSONL file (first line).
struct AIConversationMeta: Codable {
    let id: UUID
    var title: String
    let created: Date
    var updated: Date
    var model: String
    var messageCount: Int
    let type: String // always "metadata"
    var runtimeID: String?
    var activeRuntimeSessionID: String?
    var runtimeSessionLineage: [String]?
    var runtimeSource: String?
    var runtimeLastSyncedAt: Date?
    var runtimeLastSyncedMessageID: String?
    var runtimeLastSyncedTimestamp: Date?
    var runtimeLastImportedSessionID: String?

    init(id: UUID = UUID(), title: String = "New Chat", model: String = "apple-intelligence") {
        self.id = id
        self.title = title
        self.created = Date()
        self.updated = Date()
        self.model = model
        self.messageCount = 0
        self.type = "metadata"
    }
}

/// A conversation summary for the conversation list.
struct AIConversationSummary: Identifiable {
    let id: UUID
    var title: String
    let created: Date
    var updated: Date
    var messageCount: Int
    let filename: String
    var runtimeID: String?
    var activeRuntimeSessionID: String?
    var runtimeSessionLineage: [String]?
    var runtimeSource: String?
    var runtimeLastSyncedAt: Date?
    var runtimeLastSyncedMessageID: String?
    var runtimeLastSyncedTimestamp: Date?
    var runtimeLastImportedSessionID: String?
}

/// Persists AI conversations as JSONL files in the vault.
/// Each file has a metadata line followed by one line per message.
@MainActor
final class AIConversationStorage: ObservableObject {
    static let shared = AIConversationStorage()

    @Published var conversations: [AIConversationSummary] = []

    private let logger = Logger(subsystem: "com.cider.app", category: "AIConversationStorage")
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private var conversationsDir: URL {
        let vault = StoragePaths.vaultDirectoryURL()
        return vault
            .appendingPathComponent(StoragePaths.ciderInternalDir, isDirectory: true)
            .appendingPathComponent("ai-conversations", isDirectory: true)
    }

    init() {
        ensureDirectory()
        loadConversationList()
    }

    // MARK: - Directory

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: conversationsDir, withIntermediateDirectories: true)
    }

    // MARK: - List Conversations

    func loadConversationList() {
        ensureDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: conversationsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            conversations = []
            return
        }

        var summaries: [AIConversationSummary] = []
        for file in files where file.pathExtension == "jsonl" {
            guard let meta = readMeta(from: file) else { continue }
            summaries.append(AIConversationSummary(
                id: meta.id,
                title: meta.title,
                created: meta.created,
                updated: meta.updated,
                messageCount: meta.messageCount,
                filename: file.lastPathComponent,
                runtimeID: meta.runtimeID,
                activeRuntimeSessionID: meta.activeRuntimeSessionID,
                runtimeSessionLineage: meta.runtimeSessionLineage,
                runtimeSource: meta.runtimeSource,
                runtimeLastSyncedAt: meta.runtimeLastSyncedAt,
                runtimeLastSyncedMessageID: meta.runtimeLastSyncedMessageID,
                runtimeLastSyncedTimestamp: meta.runtimeLastSyncedTimestamp,
                runtimeLastImportedSessionID: meta.runtimeLastImportedSessionID
            ))
        }

        conversations = Self.collapsingDuplicateHermesRuntimeSummaries(summaries)
            .sorted { $0.updated > $1.updated }
    }

    static func collapsingDuplicateHermesRuntimeSummaries(
        _ summaries: [AIConversationSummary]
    ) -> [AIConversationSummary] {
        var unkeyed: [AIConversationSummary] = []
        var keyed: [String: AIConversationSummary] = [:]

        for summary in summaries {
            guard summary.runtimeID == CiderAgentChatRegistry.hermesRuntimeID,
                  let activeRuntimeSessionID = summary.activeRuntimeSessionID,
                  !activeRuntimeSessionID.isEmpty
            else {
                unkeyed.append(summary)
                continue
            }

            let key = "hermes:\(activeRuntimeSessionID)"
            if let existing = keyed[key] {
                if summary.updated > existing.updated {
                    keyed[key] = summary
                }
            } else {
                keyed[key] = summary
            }
        }

        return unkeyed + keyed.values
    }

    // MARK: - Save Conversation

    /// Save a full conversation (overwrites existing file if same ID).
    func save(
        id: UUID,
        title: String,
        messages: [AIAssistantMessage],
        model: String,
        hermesState: HermesConversationState? = nil
    ) {
        ensureDirectory()
        let existingMeta = metadata(for: id)
        let meta = existingMeta ?? AIConversationMeta(
            id: id,
            title: title,
            model: model
        )
        var updatedMeta = meta
        updatedMeta.title = title
        updatedMeta.model = model
        updatedMeta.updated = Date()
        updatedMeta.messageCount = messages.count
        updatedMeta.runtimeID = hermesState?.runtimeID
        updatedMeta.activeRuntimeSessionID = hermesState?.activeRuntimeSessionID
        updatedMeta.runtimeSessionLineage = hermesState?.runtimeSessionLineage
        updatedMeta.runtimeSource = hermesState?.source
        updatedMeta.runtimeLastSyncedAt = hermesState?.lastSyncedAt
        updatedMeta.runtimeLastSyncedMessageID = hermesState?.lastSyncedMessageID
        updatedMeta.runtimeLastSyncedTimestamp = hermesState?.lastSyncedTimestamp
        updatedMeta.runtimeLastImportedSessionID = hermesState?.lastImportedRuntimeSessionID

        var lines: [String] = []

        // First line: metadata
        if let metaData = try? encoder.encode(updatedMeta),
           let metaLine = String(data: metaData, encoding: .utf8) {
            lines.append(metaLine)
        }

        // One line per message
        for message in messages {
            if let msgData = try? encoder.encode(message),
               let msgLine = String(data: msgData, encoding: .utf8) {
                lines.append(msgLine)
            }
        }

        let filename = filenameFo(id: id, title: title, date: meta.created)
        let fileURL = conversationsDir.appendingPathComponent(filename)

        // Remove old file with same ID but different name
        cleanupOldFile(for: id, except: filename)

        let content = lines.joined(separator: "\n") + "\n"
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)

        loadConversationList()
    }

    // MARK: - Load Conversation

    /// Load all messages from a conversation file.
    func loadMessages(for conversationID: UUID) -> [AIAssistantMessage]? {
        guard let summary = conversations.first(where: { $0.id == conversationID }) else { return nil }
        let fileURL = conversationsDir.appendingPathComponent(summary.filename)
        return loadMessages(from: fileURL)
    }

    func metadata(for conversationID: UUID) -> AIConversationMeta? {
        guard let summary = conversations.first(where: { $0.id == conversationID }) else { return nil }
        let fileURL = conversationsDir.appendingPathComponent(summary.filename)
        return readMeta(from: fileURL)
    }

    private func loadMessages(from fileURL: URL) -> [AIAssistantMessage]? {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        var messages: [AIAssistantMessage] = []
        for line in lines.dropFirst() { // skip metadata line
            if let data = line.data(using: .utf8),
               let message = try? decoder.decode(AIAssistantMessage.self, from: data) {
                messages.append(message)
            }
        }
        return messages
    }

    // MARK: - Delete Conversation

    func delete(conversationID: UUID) {
        guard let summary = conversations.first(where: { $0.id == conversationID }) else { return }
        let fileURL = conversationsDir.appendingPathComponent(summary.filename)
        try? FileManager.default.removeItem(at: fileURL)
        loadConversationList()
    }

    // MARK: - Export as Markdown

    func exportAsMarkdown(conversationID: UUID) -> String? {
        guard let summary = conversations.first(where: { $0.id == conversationID }),
              let messages = loadMessages(for: conversationID) else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short

        var md = "# \(summary.title)\n\n"
        md += "*\(dateFormatter.string(from: summary.created))*\n\n---\n\n"

        for message in messages {
            let role = message.role == .user ? "**You**" : "**AI**"
            md += "\(role): \(message.content)\n\n"
        }

        return md
    }

    // MARK: - Helpers

    private func readMeta(from fileURL: URL) -> AIConversationMeta? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        // Read first line only
        let data = handle.readData(ofLength: 4096)
        guard let content = String(data: data, encoding: .utf8) else { return nil }
        let firstLine = content.components(separatedBy: "\n").first ?? ""
        guard let lineData = firstLine.data(using: .utf8) else { return nil }
        return try? decoder.decode(AIConversationMeta.self, from: lineData)
    }

    private func filenameFo(id: UUID, title: String, date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: date)

        // Slugify title
        let slug = title
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(5)
            .joined(separator: "-")

        let shortID = id.uuidString.prefix(8).lowercased()
        return "\(dateStr)-\(slug)-\(shortID).jsonl"
    }

    private func cleanupOldFile(for id: UUID, except currentFilename: String) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: conversationsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }

        for file in files where file.pathExtension == "jsonl" && file.lastPathComponent != currentFilename {
            if let meta = readMeta(from: file), meta.id == id {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
