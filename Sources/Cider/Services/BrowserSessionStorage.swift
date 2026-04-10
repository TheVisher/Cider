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

    // MARK: - Database

    /// Explicit database reference for testing. Production uses `CiderDatabase.shared`.
    private var database: CiderDatabase?

    /// Resolve which database instance to use: explicit (testing) or shared (production).
    private var resolvedDatabase: CiderDatabase? {
        database ?? (CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil)
    }

    private init() {
        // Try SQLite first — if it returns any rows, that's the source of truth.
        if let db = resolvedDatabase {
            loadSessionsFromDatabase(db)
            if !sessions.isEmpty {
                return
            }
        }

        // Fall back to the legacy JSON index. If we loaded anything, run a
        // one-time migration into SQLite so the next launch reads from DB.
        loadFromJSON()
        if !sessions.isEmpty, let db = resolvedDatabase {
            Self.logger.info("Migrating \(self.sessions.count) sessions from JSON to SQLite")
            do {
                try db.withTransaction {
                    for session in sessions {
                        try persistSessionToDatabaseInner(db, session: session)
                    }
                }
            } catch {
                Self.logger.error("Failed to migrate JSON sessions to SQLite: \(error.localizedDescription)")
            }
        }
    }

    /// Testing-only initializer with an explicit database.
    /// Does NOT read the legacy JSON index.
    init(database: CiderDatabase) {
        self.database = database
    }

    func reload() {
        if let db = resolvedDatabase {
            loadSessionsFromDatabase(db)
        } else {
            loadFromJSON()
        }
    }

    // MARK: - CRUD

    @discardableResult
    func save(_ session: BrowserSession) -> BrowserSession {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.append(session)
        }
        persistJSON()
        persistSessionToDatabase(session)
        return session
    }

    func rename(_ id: UUID, to name: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sessions[idx].name = trimmed
        sessions[idx].updatedAt = Date()
        persistJSON()
        persistSessionToDatabase(sessions[idx])
    }

    @discardableResult
    func delete(_ id: UUID) -> TrashItem? {
        guard let session = sessions.first(where: { $0.id == id }) else { return nil }
        let sessionsDir = StoragePaths.directoryURL(for: .sessions)
        let trashItem = TrashStorage.shared.trashSession(session, sessionsDir: sessionsDir)
        sessions.removeAll { $0.id == id }
        persistJSON()
        deleteSessionFromDatabase(id)
        return trashItem
    }

    func assignSession(_ id: UUID, toFolder folderID: UUID?) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].folderID = folderID
        sessions[idx].updatedAt = Date()
        persistJSON()
        persistSessionToDatabase(sessions[idx])
    }

    func restoreFromTrash(_ session: BrowserSession) {
        guard !sessions.contains(where: { $0.id == session.id }) else { return }
        sessions.append(session)
        persistJSON()
        persistSessionToDatabase(session)
    }

    // MARK: - JSON Persistence (legacy load + mirror write)

    private func loadFromJSON() {
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

    /// Writes the in-memory sessions list back to the legacy JSON index.
    /// Retained so the one-time SQLite migration path remains reversible until
    /// Task 13 removes the JSON fallback entirely.
    private func persistJSON() {
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

    // MARK: - Database Persistence

    // Internal for testing
    /// SELECT all sessions from the database.
    func loadSessionsFromDatabase(_ db: CiderDatabase) {
        do {
            let stmt = try db.prepare("""
                SELECT id, name, source_browser_id, source_browser_name, tabs,
                       folder_id, label_ids, created_at, updated_at
                FROM sessions
                ORDER BY created_at DESC;
                """)
            var loaded: [BrowserSession] = []
            while try stmt.step() {
                guard let id = DatabaseHelpers.decodeUUID(stmt.string(at: 0)) else { continue }
                let name = stmt.string(at: 1)
                let sourceBrowserID = stmt.optionalString(at: 2)
                let sourceBrowserName = stmt.optionalString(at: 3)
                let tabsJSON = stmt.optionalString(at: 4)
                let folderID = stmt.optionalString(at: 5).flatMap { DatabaseHelpers.decodeUUID($0) }
                let labelIDsJSON = stmt.optionalString(at: 6)
                let createdAt = DatabaseHelpers.decodeDate(stmt.double(at: 7))
                let updatedAt = DatabaseHelpers.decodeDate(stmt.double(at: 8))

                let tabs: [BrowserSessionTab] = DatabaseHelpers.decodeJSON([BrowserSessionTab].self, from: tabsJSON) ?? []
                let labelIDs: [UUID] = DatabaseHelpers.decodeUUIDArray(labelIDsJSON)

                let session = BrowserSession(
                    id: id,
                    name: name,
                    tabs: tabs,
                    sourceBrowserBundleID: sourceBrowserID,
                    sourceBrowserName: sourceBrowserName,
                    folderID: folderID,
                    labelIDs: labelIDs,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
                loaded.append(session)
            }
            sessions = loaded
            Self.logger.info("Loaded \(loaded.count) sessions from database")
        } catch {
            Self.logger.error("Failed to load sessions from database: \(error.localizedDescription)")
            sessions = []
        }
    }

    /// UPSERT a single session into the database (public wrapper).
    func persistSessionToDatabase(_ session: BrowserSession) {
        guard let db = resolvedDatabase else {
            Self.logger.warning("No database available, skipping SQLite persist for session \(session.id)")
            return
        }
        persistSessionToDatabase(db, session: session)
    }

    // Internal for testing
    /// UPSERT a single session into the given database inside its own transaction.
    func persistSessionToDatabase(_ db: CiderDatabase, session: BrowserSession) {
        do {
            try db.withTransaction {
                try persistSessionToDatabaseInner(db, session: session)
            }
        } catch {
            Self.logger.error("Failed to persist session \(session.id) to database: \(error.localizedDescription)")
        }
    }

    // Internal for testing
    /// Core persist logic — must be called inside a transaction.
    func persistSessionToDatabaseInner(_ db: CiderDatabase, session: BrowserSession) throws {
        let stmt = try db.prepare("""
            INSERT INTO sessions (
                id, name, source_browser_id, source_browser_name, tabs,
                folder_id, label_ids, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                source_browser_id = excluded.source_browser_id,
                source_browser_name = excluded.source_browser_name,
                tabs = excluded.tabs,
                folder_id = excluded.folder_id,
                label_ids = excluded.label_ids,
                updated_at = excluded.updated_at;
            """)

        // Store nil (NULL) for empty collections rather than '[]' for consistency
        // with other services (VaultFileStorage dominant_colors, etc.).
        let tabsJSON: String? = session.tabs.isEmpty ? nil : DatabaseHelpers.encodeJSON(session.tabs)
        let labelIDsJSON: String? = session.labelIDs.isEmpty ? nil : DatabaseHelpers.encode(session.labelIDs)
        let folderIDText: String? = session.folderID.map { DatabaseHelpers.encode($0) }

        stmt.bind(DatabaseHelpers.encode(session.id), at: 1)
            .bind(session.name, at: 2)
            .bind(session.sourceBrowserBundleID, at: 3)
            .bind(session.sourceBrowserName, at: 4)
            .bind(tabsJSON, at: 5)
            .bind(folderIDText, at: 6)
            .bind(labelIDsJSON, at: 7)
            .bind(DatabaseHelpers.encode(session.createdAt), at: 8)
            .bind(DatabaseHelpers.encode(session.updatedAt), at: 9)
        try stmt.step()
    }

    /// DELETE a session from the database by ID (public wrapper).
    func deleteSessionFromDatabase(_ id: UUID) {
        guard let db = resolvedDatabase else {
            Self.logger.warning("No database available, skipping SQLite delete for session \(id)")
            return
        }
        deleteSessionFromDatabase(db, sessionID: id)
    }

    // Internal for testing
    /// DELETE a session from the given database by ID.
    func deleteSessionFromDatabase(_ db: CiderDatabase, sessionID: UUID) {
        do {
            let stmt = try db.prepare("DELETE FROM sessions WHERE id = ?;")
            stmt.bind(DatabaseHelpers.encode(sessionID), at: 1)
            try stmt.step()
        } catch {
            Self.logger.error("Failed to delete session \(sessionID) from database: \(error.localizedDescription)")
        }
    }
}
