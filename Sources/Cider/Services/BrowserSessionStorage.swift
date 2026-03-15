import Foundation
import os

private struct SessionsSnapshot: Codable {
    var sessions: [BrowserSession]
}

@MainActor
final class BrowserSessionStorage: ObservableObject {
    static let shared = BrowserSessionStorage()

    private static let logger = Logger(subsystem: "com.cider", category: "BrowserSessionStorage")

    @Published private(set) var sessions: [BrowserSession] = []

    private let indexFileName = "_cider_sessions.json"
    private var indexFileURL: URL {
        let dir = StoragePaths.directoryURL(for: .sessions)
        StoragePaths.ensureDirectory(dir)
        return StoragePaths.jsonFileURL(fileName: indexFileName, in: dir)
    }

    private init() {
        load()
    }

    func reload() {
        load()
    }

    // MARK: - CRUD

    @discardableResult
    func save(_ session: BrowserSession) -> BrowserSession {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.append(session)
        }
        persist()
        return session
    }

    func rename(_ id: UUID, to name: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sessions[idx].name = trimmed
        sessions[idx].updatedAt = Date()
        persist()
    }

    @discardableResult
    func delete(_ id: UUID) -> TrashItem? {
        guard let session = sessions.first(where: { $0.id == id }) else { return nil }
        let sessionsDir = StoragePaths.cachedDirectoryURL(for: .sessions)
        let trashItem = TrashStorage.shared.trashSession(session, sessionsDir: sessionsDir)
        sessions.removeAll { $0.id == id }
        persist()
        return trashItem
    }

    func restoreFromTrash(_ session: BrowserSession) {
        guard !sessions.contains(where: { $0.id == session.id }) else { return }
        sessions.append(session)
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: indexFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: indexFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(SessionsSnapshot.self, from: data)
            sessions = snapshot.sessions
        } catch {
            Self.logger.error("Failed to decode sessions index: \(error)")
            sessions = []
        }
    }

    private func persist() {
        let snapshot = SessionsSnapshot(sessions: sessions)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: indexFileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to persist sessions index: \(error)")
        }
    }
}
