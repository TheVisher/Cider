import Foundation

struct CiderAgentChatRecord: Codable, Equatable, Sendable {
    var stableID: String
    var title: String
    var kind: String
    var conversationID: UUID
    var runtimeID: String
    var activeRuntimeSessionID: String
    var runtimeSessionLineage: [String]
    var createdAt: Date
    var updatedAt: Date
    var defaultInCider: Bool
}

enum CiderAgentChatRegistryError: Error {
    case invalidStableID(String)
}

final class CiderAgentChatRegistry: @unchecked Sendable {
    static let shared = CiderAgentChatRegistry()

    static let mainBrainStableID = "cider.main"
    static let mainBrainTitle = "Main Brain"
    static let mainBrainKind = "main-brain"
    static let hermesRuntimeID = "hermes"
    static let seedHermesLineage = [
        "20260501_045533_cce0d1c1",
        "20260501_100416_ebff7f",
        "20260501_114444_443f9e",
        "20260501_120144_e3d994"
    ]

    private let storageDirectoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()

    init(
        storageDirectoryURL: URL = StoragePaths.vaultDirectoryURL()
            .appendingPathComponent(StoragePaths.ciderInternalDir, isDirectory: true)
            .appendingPathComponent("agent-chats", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.storageDirectoryURL = storageDirectoryURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadOrCreateMainBrain() throws -> CiderAgentChatRecord {
        lock.lock()
        defer { lock.unlock() }

        try ensureDirectory()
        let url = recordURL(for: Self.mainBrainStableID)
        if let data = try? Data(contentsOf: url),
           let record = try? decoder.decode(CiderAgentChatRecord.self, from: data) {
            return record
        }

        let now = Date()
        let record = CiderAgentChatRecord(
            stableID: Self.mainBrainStableID,
            title: Self.mainBrainTitle,
            kind: Self.mainBrainKind,
            conversationID: UUID(),
            runtimeID: Self.hermesRuntimeID,
            activeRuntimeSessionID: Self.seedHermesLineage.last ?? "",
            runtimeSessionLineage: Self.seedHermesLineage,
            createdAt: now,
            updatedAt: now,
            defaultInCider: true
        )
        try saveUnlocked(record)
        return record
    }

    func saveMainBrain(_ record: CiderAgentChatRecord) throws {
        guard record.stableID == Self.mainBrainStableID else {
            throw CiderAgentChatRegistryError.invalidStableID(record.stableID)
        }

        lock.lock()
        defer { lock.unlock() }
        try ensureDirectory()
        try saveUnlocked(record)
    }

    func updateMainBrain(from state: HermesConversationState) throws -> CiderAgentChatRecord {
        var record = try loadOrCreateMainBrain()
        record.conversationID = state.conversationID
        record.runtimeID = state.runtimeID
        record.activeRuntimeSessionID = state.activeRuntimeSessionID
        record.runtimeSessionLineage = mergedLineage(record.runtimeSessionLineage, state.runtimeSessionLineage)
        record.title = Self.mainBrainTitle
        record.kind = Self.mainBrainKind
        record.defaultInCider = true
        record.updatedAt = Date()
        try saveMainBrain(record)
        return record
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: storageDirectoryURL, withIntermediateDirectories: true)
    }

    private func saveUnlocked(_ record: CiderAgentChatRecord) throws {
        let data = try encoder.encode(record)
        try data.write(to: recordURL(for: record.stableID), options: .atomic)
    }

    private func recordURL(for stableID: String) -> URL {
        let filename = stableID
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return storageDirectoryURL.appendingPathComponent("\(filename).json")
    }

    private func mergedLineage(_ existing: [String], _ incoming: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in existing + incoming where !id.isEmpty && !seen.contains(id) {
            result.append(id)
            seen.insert(id)
        }
        return result
    }
}
