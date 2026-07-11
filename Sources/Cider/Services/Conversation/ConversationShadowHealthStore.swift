import Foundation

enum ConversationShadowHealthStoreError: Error, Equatable {
    case persistence(String)
    case saturated
    case missingReservation(UUID)
}

struct ConversationShadowHealthRecord: Codable, Equatable, Sendable {
    let correlationID: UUID
    let conversationID: UUID
    let generationID: UUID
    var status: ConversationShadowHealthStatus
    var code: ConversationShadowDiagnosticCode?
    let jsonlHash: String
    let registryHash: String
    let firstSeenAt: Date
    var lastSeenAt: Date
    var occurrenceCount: Int
    var errorDetail: String?
}

struct ConversationShadowHealthSnapshot: Equatable, Sendable {
    let unresolved: [ConversationShadowHealthRecord]
    let resolvedHistory: [ConversationShadowHealthRecord]
    let aggregateEvidence: [String: Int]
}

@MainActor
final class ConversationShadowHealthStore {
    struct Persistence {
        var writeAtomically: (Data, URL) throws -> Void
        var read: (URL) throws -> Data

        static func live() -> Persistence {
            Persistence(
                writeAtomically: { try $0.write(to: $1, options: .atomic) },
                read: { try Data(contentsOf: $0) }
            )
        }
    }

    private struct State: Codable, Equatable {
        var formatVersion = "cider.conversation-shadow-health.v1"
        var unresolved: [ConversationShadowHealthRecord] = []
        var resolvedHistory: [ConversationShadowHealthRecord] = []
        var aggregateEvidence: [String: Int] = [:]
    }

    static let maximumUnresolved = 1_000
    static let maximumResolvedHistory = 100
    static let maximumReadCount = 100
    static let maximumDetailCharacters = 512

    let fileURL: URL
    private let fileManager: FileManager
    private let persistence: Persistence
    private let maximumUnresolvedRecords: Int
    private let maximumResolvedRecords: Int
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var state: State

    init(
        diagnosticsDirectoryURL: URL = StoragePaths.vaultDirectoryURL()
            .appendingPathComponent(StoragePaths.ciderInternalDir, isDirectory: true)
            .appendingPathComponent("diagnostics", isDirectory: true),
        fileManager: FileManager = .default,
        persistence: Persistence = .live(),
        maximumUnresolvedRecords: Int = ConversationShadowHealthStore.maximumUnresolved,
        maximumResolvedRecords: Int = ConversationShadowHealthStore.maximumResolvedHistory
    ) throws {
        fileURL = diagnosticsDirectoryURL.appendingPathComponent("conversation-shadow-health.json")
        self.fileManager = fileManager
        self.persistence = persistence
        self.maximumUnresolvedRecords = min(maximumUnresolvedRecords, Self.maximumUnresolved)
        self.maximumResolvedRecords = min(maximumResolvedRecords, Self.maximumResolvedHistory)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        try fileManager.createDirectory(at: diagnosticsDirectoryURL, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: fileURL.path) {
            state = try decoder.decode(State.self, from: persistence.read(fileURL))
            guard state.unresolved.count <= self.maximumUnresolvedRecords,
                  state.resolvedHistory.count <= self.maximumResolvedRecords
            else {
                throw ConversationShadowHealthStoreError.persistence(
                    "Persisted conversation shadow health exceeds configured bounds."
                )
            }
        } else {
            state = State()
        }
    }

    @discardableResult
    func reserve(
        payload: ConversationShadowPayload,
        correlationID: UUID = UUID(),
        at date: Date
    ) throws -> ConversationShadowHealthRecord {
        guard state.unresolved.count < maximumUnresolvedRecords else {
            var next = state
            next.aggregateEvidence[ConversationShadowDiagnosticCode.diagnosticStoreSaturated.rawValue, default: 0] += 1
            try commit(next)
            throw ConversationShadowHealthStoreError.saturated
        }
        let record = ConversationShadowHealthRecord(
            correlationID: correlationID,
            conversationID: payload.conversation.metadata.id,
            generationID: payload.generation.id,
            status: .reserved,
            code: nil,
            jsonlHash: payload.conversation.sha256,
            registryHash: payload.registry.sha256,
            firstSeenAt: date,
            lastSeenAt: date,
            occurrenceCount: 1,
            errorDetail: nil
        )
        var next = state
        next.unresolved.insert(record, at: 0)
        try commit(next)
        return record
    }

    func markRepairNeeded(
        correlationID: UUID,
        code: ConversationShadowDiagnosticCode,
        detail: String,
        at date: Date
    ) throws {
        try updateUnresolved(correlationID: correlationID) { record in
            record.status = .repairNeeded
            record.code = code
            record.lastSeenAt = date
            record.occurrenceCount += 1
            record.errorDetail = Self.bounded(detail)
        }
    }

    func markOutcomeUnknown(correlationID: UUID, detail: String, at date: Date) throws {
        try updateUnresolved(correlationID: correlationID) { record in
            record.status = .outcomeUnknown
            record.lastSeenAt = date
            record.occurrenceCount += 1
            record.errorDetail = Self.bounded(detail)
        }
    }

    func markSynchronized(correlationID: UUID, at date: Date) throws {
        try finish(correlationID: correlationID, status: .synchronized, code: nil, detail: nil, at: date)
    }

    func resolve(
        correlationID: UUID,
        detail: String? = nil,
        at date: Date
    ) throws {
        try finish(correlationID: correlationID, status: .resolved, code: nil, detail: detail, at: date)
    }

    @discardableResult
    func resolveMatching(
        conversationID: UUID,
        jsonlHash: String,
        registryHash: String,
        detail: String,
        at date: Date
    ) throws -> Int {
        var next = state
        let indexes = next.unresolved.indices.filter {
            next.unresolved[$0].conversationID == conversationID &&
            next.unresolved[$0].jsonlHash == jsonlHash &&
            next.unresolved[$0].registryHash == registryHash
        }
        guard !indexes.isEmpty else { return 0 }
        var resolved: [ConversationShadowHealthRecord] = []
        for index in indexes.reversed() {
            var record = next.unresolved.remove(at: index)
            record.status = .resolved
            record.code = nil
            record.lastSeenAt = date
            record.occurrenceCount += 1
            record.errorDetail = Self.bounded(detail)
            resolved.append(record)
        }
        next.resolvedHistory.insert(contentsOf: resolved.reversed(), at: 0)
        next.resolvedHistory = Array(next.resolvedHistory.prefix(maximumResolvedRecords))
        try commit(next)
        return resolved.count
    }

    func snapshot(limit: Int = 100) -> ConversationShadowHealthSnapshot {
        let boundedLimit = max(0, min(limit, Self.maximumReadCount))
        return ConversationShadowHealthSnapshot(
            unresolved: Array(state.unresolved.prefix(boundedLimit)),
            resolvedHistory: Array(state.resolvedHistory.prefix(boundedLimit)),
            aggregateEvidence: state.aggregateEvidence
        )
    }

    private func updateUnresolved(
        correlationID: UUID,
        mutation: (inout ConversationShadowHealthRecord) -> Void
    ) throws {
        var next = state
        guard let index = next.unresolved.firstIndex(where: { $0.correlationID == correlationID }) else {
            throw ConversationShadowHealthStoreError.missingReservation(correlationID)
        }
        mutation(&next.unresolved[index])
        try commit(next)
    }

    private func finish(
        correlationID: UUID,
        status: ConversationShadowHealthStatus,
        code: ConversationShadowDiagnosticCode?,
        detail: String?,
        at date: Date
    ) throws {
        var next = state
        guard let index = next.unresolved.firstIndex(where: { $0.correlationID == correlationID }) else {
            throw ConversationShadowHealthStoreError.missingReservation(correlationID)
        }
        var record = next.unresolved.remove(at: index)
        record.status = status
        record.code = code
        record.lastSeenAt = date
        record.occurrenceCount += 1
        record.errorDetail = detail.map(Self.bounded)
        next.resolvedHistory.insert(record, at: 0)
        next.resolvedHistory = Array(next.resolvedHistory.prefix(maximumResolvedRecords))
        try commit(next)
    }

    private func commit(_ next: State) throws {
        do {
            let data = try encoder.encode(next)
            try persistence.writeAtomically(data, fileURL)
            let readBack = try persistence.read(fileURL)
            guard readBack == data, try decoder.decode(State.self, from: readBack) == next else {
                throw CocoaError(.fileReadCorruptFile)
            }
            state = next
        } catch {
            throw ConversationShadowHealthStoreError.persistence(Self.bounded(String(describing: error)))
        }
    }

    private static func bounded(_ value: String) -> String {
        String(value.prefix(maximumDetailCharacters))
    }
}
