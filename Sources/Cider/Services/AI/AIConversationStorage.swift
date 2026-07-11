import Foundation
import CryptoKit
import os.log

/// Metadata header for a conversation JSONL file (first line).
struct AIConversationMeta: Codable, Equatable, Sendable {
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
    struct Persistence {
        var encodeMetadata: (AIConversationMeta) throws -> Data
        var encodeMessage: (AIAssistantMessage) throws -> Data
        var writeAtomically: (Data, URL) throws -> Void
        var read: (URL) throws -> Data

        static func live() -> Persistence {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            return Persistence(
                encodeMetadata: { try encoder.encode($0) },
                encodeMessage: { try encoder.encode($0) },
                writeAtomically: { try $0.write(to: $1, options: .atomic) },
                read: { try Data(contentsOf: $0) }
            )
        }
    }

    private let decoder: JSONDecoder
    private let conversationsDir: URL
    private let fileManager: FileManager
    private let persistence: Persistence
    private let now: () -> Date

    init(
        conversationsDirectoryURL: URL? = nil,
        fileManager: FileManager = .default,
        persistence: Persistence = .live(),
        now: @escaping () -> Date = Date.init
    ) {
        conversationsDir = conversationsDirectoryURL ?? StoragePaths.vaultDirectoryURL()
            .appendingPathComponent(StoragePaths.ciderInternalDir, isDirectory: true)
            .appendingPathComponent("ai-conversations", isDirectory: true)
        self.fileManager = fileManager
        self.persistence = persistence
        self.now = now
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        ensureDirectory()
        loadConversationList()
    }

    // MARK: - Directory

    private func ensureDirectory() {
        try? fileManager.createDirectory(at: conversationsDir, withIntermediateDirectories: true)
    }

    // MARK: - List Conversations

    func loadConversationList() {
        ensureDirectory()
        guard let files = try? fileManager.contentsOfDirectory(
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
    @discardableResult
    func save(
        id: UUID,
        title: String,
        messages: [AIAssistantMessage],
        model: String,
        hermesState: HermesConversationState? = nil,
        generation: LegacyConversationWriteGeneration = .init()
    ) -> LegacyConversationWriteReceipt {
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
        updatedMeta.updated = now()
        updatedMeta.messageCount = messages.count
        updatedMeta.runtimeID = hermesState?.runtimeID
        updatedMeta.activeRuntimeSessionID = hermesState?.activeRuntimeSessionID
        updatedMeta.runtimeSessionLineage = hermesState?.runtimeSessionLineage
        updatedMeta.runtimeSource = hermesState?.source
        updatedMeta.runtimeLastSyncedAt = hermesState?.lastSyncedAt
        updatedMeta.runtimeLastSyncedMessageID = hermesState?.lastSyncedMessageID
        updatedMeta.runtimeLastSyncedTimestamp = hermesState?.lastSyncedTimestamp
        updatedMeta.runtimeLastImportedSessionID = hermesState?.lastImportedRuntimeSessionID

        let filename = filenameFo(id: id, title: title, date: meta.created)
        let fileURL = conversationsDir.appendingPathComponent(filename)
        let oldURLs = conversationFiles(for: id).filter { $0 != fileURL }
        let priorTargetBytes = try? Data(contentsOf: fileURL)

        let encoded: Data
        do {
            var rows = [try persistence.encodeMetadata(updatedMeta)]
            rows.append(contentsOf: try messages.map(persistence.encodeMessage))
            guard rows.allSatisfy({ !$0.contains(0x0A) }) else {
                throw CocoaError(.fileWriteInapplicableStringEncoding)
            }
            encoded = rows.reduce(into: Data()) { result, row in
                result.append(row)
                result.append(0x0A)
            }
        } catch {
            return failedReceipt(.primaryEncodeFailed, error, generation: generation, conversationID: id, messageCount: messages.count)
        }

        do {
            try persistence.writeAtomically(encoded, fileURL)
        } catch {
            restoreTarget(at: fileURL, priorBytes: priorTargetBytes)
            return failedReceipt(.primaryWriteFailed, error, generation: generation, conversationID: id, messageCount: messages.count)
        }

        do {
            let readBack = try persistence.read(fileURL)
            let decoded = try strictlyDecode(readBack)
            guard readBack == encoded,
                  decoded.metadata.id == id,
                  decoded.metadata.title == updatedMeta.title,
                  decoded.metadata.model == updatedMeta.model,
                  decoded.metadata.type == updatedMeta.type,
                  decoded.metadata.messageCount == messages.count,
                  decoded.metadata.runtimeID == updatedMeta.runtimeID,
                  decoded.metadata.activeRuntimeSessionID == updatedMeta.activeRuntimeSessionID,
                  decoded.metadata.runtimeSessionLineage == updatedMeta.runtimeSessionLineage,
                  decoded.metadata.runtimeSource == updatedMeta.runtimeSource,
                  decoded.metadata.runtimeLastSyncedMessageID == updatedMeta.runtimeLastSyncedMessageID,
                  decoded.metadata.runtimeLastImportedSessionID == updatedMeta.runtimeLastImportedSessionID,
                  decoded.messages.map(\.id) == messages.map(\.id),
                  decoded.messages.map(\.content) == messages.map(\.content),
                  decoded.messages.map(\.role) == messages.map(\.role),
                  decoded.messages.map(\.sourceID) == messages.map(\.sourceID),
                  decoded.messages.map(\.sourceSessionID) == messages.map(\.sourceSessionID),
                  decoded.messages.map(\.sourceName) == messages.map(\.sourceName),
                  decoded.messages.map(\.attachments) == messages.map(\.attachments)
            else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let hash = Self.sha256(readBack)
            let snapshot = LegacyConversationSnapshot(
                generation: generation,
                metadata: .init(decoded.metadata),
                messages: decoded.messages.map(LegacyConversationMessageSnapshot.init),
                filename: filename,
                bytes: readBack,
                sha256: hash
            )
            for oldURL in oldURLs {
                do {
                    try fileManager.removeItem(at: oldURL)
                } catch {
                    logger.error("Verified replacement saved but old conversation file could not be removed: \(error.localizedDescription, privacy: .public)")
                }
            }
            loadConversationList()
            return LegacyConversationWriteReceipt(
                status: .committed,
                generation: generation,
                conversationID: id,
                committedAt: now(),
                filename: filename,
                sha256: hash,
                messageCount: messages.count,
                code: nil,
                detail: nil,
                snapshot: snapshot
            )
        } catch {
            restoreTarget(at: fileURL, priorBytes: priorTargetBytes)
            loadConversationList()
            return failedReceipt(.primaryVerificationFailed, error, generation: generation, conversationID: id, messageCount: messages.count)
        }
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
        try? fileManager.removeItem(at: fileURL)
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

    private func conversationFiles(for id: UUID) -> [URL] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: conversationsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [] }
        return files.filter { $0.pathExtension == "jsonl" && readMeta(from: $0)?.id == id }
    }

    private func strictlyDecode(_ data: Data) throws -> (metadata: AIConversationMeta, messages: [AIAssistantMessage]) {
        var rows = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        guard rows.last?.isEmpty == true else { throw CocoaError(.fileReadCorruptFile) }
        rows.removeLast()
        guard let first = rows.first, !first.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        let metadata = try decoder.decode(AIConversationMeta.self, from: Data(first))
        guard metadata.type == "metadata" else { throw CocoaError(.fileReadCorruptFile) }
        let messages = try rows.dropFirst().map { row -> AIAssistantMessage in
            guard !row.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            return try decoder.decode(AIAssistantMessage.self, from: Data(row))
        }
        return (metadata, messages)
    }

    private func restoreTarget(at url: URL, priorBytes: Data?) {
        if let priorBytes {
            try? priorBytes.write(to: url, options: .atomic)
        } else {
            try? fileManager.removeItem(at: url)
        }
    }

    private func failedReceipt(
        _ code: ConversationShadowDiagnosticCode,
        _ error: Error,
        generation: LegacyConversationWriteGeneration,
        conversationID: UUID,
        messageCount: Int
    ) -> LegacyConversationWriteReceipt {
        logger.error("Conversation primary save failed [\(code.rawValue, privacy: .public)]: \(error.localizedDescription, privacy: .public)")
        return LegacyConversationWriteReceipt(
            status: .failed,
            generation: generation,
            conversationID: conversationID,
            committedAt: nil,
            filename: nil,
            sha256: nil,
            messageCount: messageCount,
            code: code,
            detail: String(String(describing: error).prefix(512)),
            snapshot: nil
        )
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
