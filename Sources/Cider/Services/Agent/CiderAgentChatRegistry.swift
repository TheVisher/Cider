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

    func loadMainBrain() throws -> CiderAgentChatRecord? {
        lock.lock()
        defer { lock.unlock() }

        try ensureDirectory()
        let url = recordURL(for: Self.mainBrainStableID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try decoder.decode(CiderAgentChatRecord.self, from: data)
    }

    func createMainBrain(from state: HermesConversationState) throws -> CiderAgentChatRecord {
        let now = persistedDate()
        let record = CiderAgentChatRecord(
            stableID: Self.mainBrainStableID,
            title: Self.mainBrainTitle,
            kind: Self.mainBrainKind,
            conversationID: state.conversationID,
            runtimeID: state.runtimeID,
            activeRuntimeSessionID: state.activeRuntimeSessionID,
            runtimeSessionLineage: state.runtimeSessionLineage,
            createdAt: now,
            updatedAt: now,
            defaultInCider: true
        )
        try saveMainBrain(record)
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
        guard var record = try loadMainBrain() else {
            return try createMainBrain(from: state)
        }

        record.conversationID = state.conversationID
        record.runtimeID = state.runtimeID
        record.activeRuntimeSessionID = state.activeRuntimeSessionID
        record.runtimeSessionLineage = state.runtimeSessionLineage
        record.title = Self.mainBrainTitle
        record.kind = Self.mainBrainKind
        record.defaultInCider = true
        record.updatedAt = persistedDate()
        try saveMainBrain(record)
        return record
    }

    private func persistedDate() -> Date {
        Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
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

}
