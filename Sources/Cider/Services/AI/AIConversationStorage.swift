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
                filename: file.lastPathComponent
            ))
        }

        conversations = summaries.sorted { $0.updated > $1.updated }
    }

    // MARK: - Save Conversation

    /// Save a full conversation (overwrites existing file if same ID).
    func save(id: UUID, title: String, messages: [AIAssistantMessage], model: String) {
        ensureDirectory()
        let existingMeta = existingMeta(for: id)
        var updatedMeta = existingMeta?.meta ?? AIConversationMeta(
            id: id,
            title: title,
            model: model
        )
        updatedMeta.title = title
        updatedMeta.model = model
        updatedMeta.updated = Date()
        updatedMeta.messageCount = messages.count

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

        let filename = filenameFo(id: id, title: title, date: updatedMeta.created)
        let fileURL = conversationsDir.appendingPathComponent(filename)
        let content = lines.joined(separator: "\n") + "\n"

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            cleanupOldFile(for: id, except: filename)
        } catch {
            logger.error("Failed to save conversation \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        loadConversationList()
    }

    // MARK: - Load Conversation

    /// Load all messages from a conversation file.
    func loadMessages(for conversationID: UUID) -> [AIAssistantMessage]? {
        guard let summary = conversations.first(where: { $0.id == conversationID }) else { return nil }
        let fileURL = conversationsDir.appendingPathComponent(summary.filename)
        return loadMessages(from: fileURL)
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

    private func existingMeta(for id: UUID) -> (meta: AIConversationMeta, fileURL: URL)? {
        if let summary = conversations.first(where: { $0.id == id }) {
            let fileURL = conversationsDir.appendingPathComponent(summary.filename)
            if let meta = readMeta(from: fileURL) {
                return (meta, fileURL)
            }
        }

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: conversationsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            return nil
        }

        for file in files where file.pathExtension == "jsonl" {
            if let meta = readMeta(from: file), meta.id == id {
                return (meta, file)
            }
        }
        return nil
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
