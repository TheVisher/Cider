import Foundation
import CryptoKit

struct CiderAgentChatRecord: Codable, Equatable, Sendable {
    var stableID: String
    var title: String
    var hermesTitle: String?
    var kind: String
    var conversationID: UUID
    var runtimeID: String
    var activeRuntimeSessionID: String
    var runtimeSessionLineage: [String]
    var lastSyncedMessageID: String?
    var lastSyncedTimestamp: Date?
    var lastImportedRuntimeSessionID: String?
    var scope: String?
    var archived: Bool
    var createdAt: Date
    var updatedAt: Date
    var defaultInCider: Bool

    init(
        stableID: String,
        title: String,
        hermesTitle: String? = nil,
        kind: String,
        conversationID: UUID,
        runtimeID: String,
        activeRuntimeSessionID: String,
        runtimeSessionLineage: [String],
        lastSyncedMessageID: String? = nil,
        lastSyncedTimestamp: Date? = nil,
        lastImportedRuntimeSessionID: String? = nil,
        scope: String? = nil,
        archived: Bool = false,
        createdAt: Date,
        updatedAt: Date,
        defaultInCider: Bool
    ) {
        self.stableID = stableID
        self.title = title
        self.hermesTitle = hermesTitle
        self.kind = kind
        self.conversationID = conversationID
        self.runtimeID = runtimeID
        self.activeRuntimeSessionID = activeRuntimeSessionID
        self.runtimeSessionLineage = runtimeSessionLineage
        self.lastSyncedMessageID = lastSyncedMessageID
        self.lastSyncedTimestamp = lastSyncedTimestamp
        self.lastImportedRuntimeSessionID = lastImportedRuntimeSessionID
        self.scope = scope
        self.archived = archived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.defaultInCider = defaultInCider
    }

    enum CodingKeys: String, CodingKey {
        case stableID
        case title
        case hermesTitle
        case kind
        case conversationID
        case runtimeID
        case activeRuntimeSessionID
        case runtimeSessionLineage
        case lastSyncedMessageID
        case lastSyncedTimestamp
        case lastImportedRuntimeSessionID
        case scope
        case archived
        case createdAt
        case updatedAt
        case defaultInCider
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stableID = try container.decode(String.self, forKey: .stableID)
        title = try container.decode(String.self, forKey: .title)
        hermesTitle = try container.decodeIfPresent(String.self, forKey: .hermesTitle)
        kind = try container.decode(String.self, forKey: .kind)
        conversationID = try container.decode(UUID.self, forKey: .conversationID)
        runtimeID = try container.decode(String.self, forKey: .runtimeID)
        activeRuntimeSessionID = try container.decode(String.self, forKey: .activeRuntimeSessionID)
        runtimeSessionLineage = try container.decode([String].self, forKey: .runtimeSessionLineage)
        lastSyncedMessageID = try container.decodeIfPresent(String.self, forKey: .lastSyncedMessageID)
        lastSyncedTimestamp = try container.decodeIfPresent(Date.self, forKey: .lastSyncedTimestamp)
        lastImportedRuntimeSessionID = try container.decodeIfPresent(String.self, forKey: .lastImportedRuntimeSessionID)
        scope = try container.decodeIfPresent(String.self, forKey: .scope)
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        defaultInCider = try container.decodeIfPresent(Bool.self, forKey: .defaultInCider) ?? false
    }
}

enum CiderAgentChatRegistryError: Error, Equatable {
    case invalidStableID(String)
    case persistence(ConversationShadowDiagnosticCode, String)
}

final class CiderAgentChatRegistry: @unchecked Sendable {
    struct Persistence {
        var encode: (CiderAgentChatRecord) throws -> Data
        var writeAtomically: (Data, URL) throws -> Void
        var read: (URL) throws -> Data

        static func live() -> Persistence {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return Persistence(
                encode: { try encoder.encode($0) },
                writeAtomically: { try $0.write(to: $1, options: .atomic) },
                read: { try Data(contentsOf: $0) }
            )
        }
    }

    static let shared = CiderAgentChatRegistry()

    static let mainBrainStableID = "cider.main"
    static let mainBrainTitle = "Cider"
    static let mainBrainKind = "main-brain"
    static let hermesChatKind = "hermes-chat"
    static let hermesRuntimeID = "hermes"

    private let storageDirectoryURL: URL
    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let persistence: Persistence
    private let now: () -> Date
    private let lock = NSLock()

    init(
        storageDirectoryURL: URL = StoragePaths.vaultDirectoryURL()
            .appendingPathComponent(StoragePaths.ciderInternalDir, isDirectory: true)
            .appendingPathComponent("agent-chats", isDirectory: true),
        fileManager: FileManager = .default,
        persistence: Persistence = .live(),
        now: @escaping () -> Date = Date.init
    ) {
        self.storageDirectoryURL = storageDirectoryURL
        self.fileManager = fileManager
        self.persistence = persistence
        self.now = now

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadMainBrain() throws -> CiderAgentChatRecord? {
        try loadChat(stableID: Self.mainBrainStableID)
    }

    func listChats(includeArchived: Bool = false) throws -> [CiderAgentChatRecord] {
        lock.lock()
        defer { lock.unlock() }

        try ensureDirectory()
        let urls = try fileManager.contentsOfDirectory(
            at: storageDirectoryURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        let records = urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> CiderAgentChatRecord? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(CiderAgentChatRecord.self, from: data)
            }
            .filter { includeArchived || !$0.archived }

        return records.sorted { lhs, rhs in
            if lhs.defaultInCider != rhs.defaultInCider {
                return lhs.defaultInCider && !rhs.defaultInCider
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    func loadChat(stableID: String) throws -> CiderAgentChatRecord? {
        lock.lock()
        defer { lock.unlock() }

        try ensureDirectory()
        let url = recordURL(for: stableID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try decoder.decode(CiderAgentChatRecord.self, from: data)
    }

    func createMainBrain(from state: HermesConversationState) throws -> CiderAgentChatRecord {
        let now = persistedDate()
        let record = CiderAgentChatRecord(
            stableID: Self.mainBrainStableID,
            title: Self.mainBrainTitle,
            hermesTitle: Self.mainBrainTitle,
            kind: Self.mainBrainKind,
            conversationID: state.conversationID,
            runtimeID: state.runtimeID,
            activeRuntimeSessionID: state.activeRuntimeSessionID,
            runtimeSessionLineage: state.runtimeSessionLineage,
            lastSyncedMessageID: state.lastSyncedMessageID,
            lastSyncedTimestamp: state.lastSyncedTimestamp,
            lastImportedRuntimeSessionID: state.lastImportedRuntimeSessionID,
            scope: "main",
            createdAt: now,
            updatedAt: now,
            defaultInCider: true
        )
        try saveMainBrain(record)
        return record
    }

    @discardableResult
    func saveMainBrain(
        _ record: CiderAgentChatRecord,
        generation: LegacyConversationWriteGeneration = .init()
    ) throws -> LegacyRegistryWriteReceipt {
        guard record.stableID == Self.mainBrainStableID else {
            throw CiderAgentChatRegistryError.invalidStableID(record.stableID)
        }

        lock.lock()
        defer { lock.unlock() }
        try ensureDirectory()
        return try saveUnlocked(record, generation: generation)
    }

    func updateMainBrain(from state: HermesConversationState) throws -> CiderAgentChatRecord {
        guard var record = try loadMainBrain() else {
            return try createMainBrain(from: state)
        }

        record.conversationID = state.conversationID
        record.runtimeID = state.runtimeID
        record.activeRuntimeSessionID = state.activeRuntimeSessionID
        record.runtimeSessionLineage = state.runtimeSessionLineage
        record.lastSyncedMessageID = state.lastSyncedMessageID
        record.lastSyncedTimestamp = state.lastSyncedTimestamp
        record.lastImportedRuntimeSessionID = state.lastImportedRuntimeSessionID
        record.title = Self.mainBrainTitle
        record.hermesTitle = Self.mainBrainTitle
        record.kind = Self.mainBrainKind
        record.scope = record.scope ?? "main"
        record.archived = false
        record.defaultInCider = true
        record.updatedAt = persistedDate()
        try saveMainBrain(record)
        return record
    }

    func createHermesChat(title: String, scope: String? = nil) throws -> CiderAgentChatRecord {
        let sanitizedTitle = Self.sanitizedHermesTitle(title)
        let now = persistedDate()
        let stableID = try uniqueStableID(for: sanitizedTitle)
        let record = CiderAgentChatRecord(
            stableID: stableID,
            title: sanitizedTitle,
            hermesTitle: sanitizedTitle,
            kind: Self.hermesChatKind,
            conversationID: UUID(),
            runtimeID: Self.hermesRuntimeID,
            activeRuntimeSessionID: "",
            runtimeSessionLineage: [],
            lastSyncedMessageID: nil,
            lastSyncedTimestamp: nil,
            lastImportedRuntimeSessionID: nil,
            scope: scope,
            archived: false,
            createdAt: now,
            updatedAt: now,
            defaultInCider: false
        )
        try updateChat(record)
        return record
    }

    @discardableResult
    func updateChat(
        _ record: CiderAgentChatRecord,
        generation: LegacyConversationWriteGeneration = .init()
    ) throws -> LegacyRegistryWriteReceipt {
        lock.lock()
        defer { lock.unlock() }
        try ensureDirectory()
        return try saveUnlocked(record, generation: generation)
    }

    func archiveChat(stableID: String) throws {
        guard var record = try loadChat(stableID: stableID) else { return }
        record.archived = true
        record.updatedAt = persistedDate()
        try updateChat(record)
    }

    func renameChat(stableID: String, title: String) throws -> CiderAgentChatRecord {
        guard var record = try loadChat(stableID: stableID) else {
            throw CiderAgentChatRegistryError.invalidStableID(stableID)
        }
        let sanitizedTitle = Self.sanitizedHermesTitle(title)
        record.title = sanitizedTitle
        record.hermesTitle = sanitizedTitle
        record.updatedAt = persistedDate()
        try updateChat(record)
        return record
    }

    func chat(forConversationID conversationID: UUID) throws -> CiderAgentChatRecord? {
        try listChats(includeArchived: true).first { $0.conversationID == conversationID }
    }

    static func telegramResumeCommand(for record: CiderAgentChatRecord) -> String {
        "/resume \(record.hermesTitle ?? record.title)"
    }

    static func sanitizedHermesTitle(_ title: String) -> String {
        let collapsed = title
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let withoutControls = String(collapsed.unicodeScalars.filter {
            !$0.properties.isDefaultIgnorableCodePoint && !CharacterSet.controlCharacters.contains($0)
        })
        let trimmed = withoutControls.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "Cider Chat" : trimmed
        return String(fallback.prefix(100))
    }

    private func persistedDate() -> Date {
        Date(timeIntervalSince1970: floor(now().timeIntervalSince1970))
    }

    private func uniqueStableID(for title: String) throws -> String {
        let base = "cider.\(Self.slug(for: title))"
        let existing = Set(try listChats(includeArchived: true).map(\.stableID))
        guard existing.contains(base) else { return base }

        var suffix = 2
        while existing.contains("\(base)-\(suffix)") {
            suffix += 1
        }
        return "\(base)-\(suffix)"
    }

    private static func slug(for title: String) -> String {
        let folded = title
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        let parts = folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let slug = parts.joined(separator: "-")
        return slug.isEmpty ? "chat" : slug
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: storageDirectoryURL, withIntermediateDirectories: true)
    }

    private func saveUnlocked(
        _ record: CiderAgentChatRecord,
        generation: LegacyConversationWriteGeneration
    ) throws -> LegacyRegistryWriteReceipt {
        let url = recordURL(for: record.stableID)
        let priorBytes = try? Data(contentsOf: url)
        let data: Data
        do {
            data = try persistence.encode(record)
        } catch {
            throw CiderAgentChatRegistryError.persistence(.primaryEncodeFailed, bounded(error))
        }
        do {
            try persistence.writeAtomically(data, url)
        } catch {
            restore(at: url, priorBytes: priorBytes)
            throw CiderAgentChatRegistryError.persistence(.primaryWriteFailed, bounded(error))
        }
        do {
            let readBack = try persistence.read(url)
            let decoded = try decoder.decode(CiderAgentChatRecord.self, from: readBack)
            guard readBack == data, decoded == record else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let hash = SHA256.hash(data: readBack).map { String(format: "%02x", $0) }.joined()
            let snapshot = LegacyRegistrySnapshot(
                generation: generation,
                record: decoded,
                filename: url.lastPathComponent,
                bytes: readBack,
                sha256: hash
            )
            return LegacyRegistryWriteReceipt(
                generation: generation,
                conversationID: record.conversationID,
                committedAt: now(),
                filename: url.lastPathComponent,
                sha256: hash,
                snapshot: snapshot
            )
        } catch {
            restore(at: url, priorBytes: priorBytes)
            throw CiderAgentChatRegistryError.persistence(.primaryVerificationFailed, bounded(error))
        }
    }

    private func restore(at url: URL, priorBytes: Data?) {
        if let priorBytes {
            try? priorBytes.write(to: url, options: .atomic)
        } else {
            try? fileManager.removeItem(at: url)
        }
    }

    private func bounded(_ error: Error) -> String {
        String(String(describing: error).prefix(512))
    }

    private func recordURL(for stableID: String) -> URL {
        let filename = stableID
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return storageDirectoryURL.appendingPathComponent("\(filename).json")
    }

}
