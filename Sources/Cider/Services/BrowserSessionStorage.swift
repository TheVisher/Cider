import Foundation
import os

@MainActor
final class BrowserSessionStorage: ObservableObject {
    static let shared = BrowserSessionStorage()

    private static let logger = Logger(subsystem: "com.cider", category: "BrowserSessionStorage")

    @Published private(set) var sessions: [BrowserSession] = []

    // MARK: - Database

    /// Explicit database reference for testing. Production uses `CiderDatabase.shared`.
    private var database: CiderDatabase?

    /// Resolve which database instance to use: explicit (testing) or shared (production).
    private var resolvedDatabase: CiderDatabase? {
        database ?? (CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil)
    }

    private init() {
        if let db = resolvedDatabase {
            loadSessionsFromDatabase(db)
        }
    }

    /// Testing-only initializer with an explicit database.
    init(database: CiderDatabase) {
        self.database = database
    }

    func reload() {
        if let db = resolvedDatabase {
            loadSessionsFromDatabase(db)
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
        persistSessionToDatabase(session)
        return session
    }

    func rename(_ id: UUID, to name: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sessions[idx].name = trimmed
        sessions[idx].updatedAt = Date()
        persistSessionToDatabase(sessions[idx])
    }

    @discardableResult
    func delete(_ id: UUID) -> TrashItem? {
        guard let session = sessions.first(where: { $0.id == id }) else { return nil }
        let sessionsDir = StoragePaths.directoryURL(for: .sessions)
        let trashItem = TrashStorage.shared.trashSession(session, sessionsDir: sessionsDir)
        sessions.removeAll { $0.id == id }
        deleteSessionFromDatabase(id)
        return trashItem
    }

    func assignSession(_ id: UUID, toFolder folderID: UUID?) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].folderID = folderID
        sessions[idx].updatedAt = Date()
        persistSessionToDatabase(sessions[idx])
    }

    func restoreFromTrash(_ session: BrowserSession) {
        guard !sessions.contains(where: { $0.id == session.id }) else { return }
        sessions.append(session)
        persistSessionToDatabase(session)
    }

    func removeLabelsFromAll(labelID: UUID) {
        var modified: [BrowserSession] = []
        for index in sessions.indices where sessions[index].labelIDs.contains(labelID) {
            sessions[index].labelIDs.removeAll { $0 == labelID }
            sessions[index].updatedAt = Date()
            modified.append(sessions[index])
        }
        guard !modified.isEmpty, let db = resolvedDatabase else { return }
        do {
            try db.withTransaction {
                for session in modified {
                    try self.persistSessionToDatabaseInner(db, session: session)
                }
            }
        } catch {
            Self.logger.error("Failed to batch-persist sessions after label removal: \(error.localizedDescription)")
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
        let folderIDText = resolveSafeFolderID(db, folderID: session.folderID)

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

    private func resolveSafeFolderID(_ db: CiderDatabase, folderID: UUID?) -> String? {
        guard let folderID else { return nil }
        do {
            let stmt = try db.prepare("SELECT 1 FROM folders WHERE id = ? LIMIT 1;")
            stmt.bind(DatabaseHelpers.encode(folderID), at: 1)
            if try stmt.step() {
                return DatabaseHelpers.encode(folderID)
            }
            Self.logger.warning("Clearing stale folder reference for session folder \(folderID)")
        } catch {
            Self.logger.error("Failed to validate session folder \(folderID): \(error.localizedDescription)")
        }
        return nil
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
