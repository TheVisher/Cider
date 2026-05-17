import Foundation
import SQLite3
import os

/// Version-based migration runner for the Cider SQLite database.
/// Tracks the current schema version and applies incremental migrations.
enum DatabaseMigrations {

    private static let logger = Logger(subsystem: "com.cider.app", category: "DatabaseMigrations")

    /// Highest schema version this build knows how to run against.
    /// Bump together with any new `migrateToVN` function.
    static let latestVersion: Int = 12

    /// Run all pending migrations on the given database connection.
    /// Creates the schema_version table if it does not exist.
    static func runMigrations(on db: OpaquePointer) throws {
        // Ensure schema_version table exists
        try runOnDB(db, CiderSchema.createSchemaVersion)

        var currentVersion = try readVersion(db)
        logger.info("Current schema version: \(currentVersion)")

        // Fail fast on a DB from a newer build. Silently running forward-only
        // migrations would leave an unknown schema in place and crash downstream
        // when columns/tables disagree.
        if currentVersion > latestVersion {
            logger.error("Schema version \(currentVersion) is newer than supported (\(latestVersion))")
            throw CiderDatabaseError.schemaTooNew(current: currentVersion, supported: latestVersion)
        }

        if currentVersion < 1 {
            try migrateToV1(db)
            currentVersion = try readVersion(db)
        }
        if currentVersion < 2 {
            try migrateToV2(db)
            currentVersion = try readVersion(db)
        }
        if currentVersion < 3 {
            try migrateToV3(db)
            currentVersion = try readVersion(db)
        }
        if currentVersion < 4 {
            try migrateToV4(db)
            currentVersion = try readVersion(db)
        }
        if currentVersion < 5 {
            try migrateToV5(db)
            currentVersion = try readVersion(db)
        }
        if currentVersion < 6 {
            try migrateToV6(db)
            currentVersion = try readVersion(db)
        }
        if currentVersion < 7 {
            try migrateToV7(db)
            currentVersion = try readVersion(db)
        }
        if currentVersion < 8 {
            try migrateToV8(db)
            currentVersion = try readVersion(db)
        }
        if currentVersion < 9 {
            try migrateToV9(db)
            currentVersion = try readVersion(db)
        }
        if currentVersion < 10 {
            try migrateToV10(db)
            currentVersion = try readVersion(db)
        }
        if currentVersion < 11 {
            try migrateToV11(db)
            currentVersion = try readVersion(db)
        }
        if currentVersion < 12 {
            try migrateToV12(db)
        }
    }

    // MARK: - V11 -> V12: Durable sync folder alias/quarantine decisions

    private static func migrateToV12(_ db: OpaquePointer) throws {
        logger.info("Migrating to schema version 12...")

        try withTransaction(db) {
            try runOnDB(db, CiderSchema.createFolderSyncDecisions)
            try runOnDB(db, "CREATE INDEX IF NOT EXISTS idx_folder_sync_decisions_local ON folder_sync_decisions(local_folder_id);")
            try runOnDB(db, "CREATE INDEX IF NOT EXISTS idx_folder_sync_decisions_decision ON folder_sync_decisions(decision, updated_at);")
            try runOnDB(db, "DELETE FROM schema_version;")
            try runOnDB(db, "INSERT INTO schema_version (version) VALUES (12);")
        }

        logger.info("Migration to v12 complete")
    }

    // MARK: - V10 -> V11: Reminder snooze state

    private static func migrateToV11(_ db: OpaquePointer) throws {
        logger.info("Migrating to schema version 11...")

        try withTransaction(db) {
            if !(try columnExists(db, table: "todos", column: "snoozed_until")) {
                try runOnDB(db, "ALTER TABLE todos ADD COLUMN snoozed_until REAL;")
            }
            if !(try columnExists(db, table: "events", column: "snoozed_until")) {
                try runOnDB(db, "ALTER TABLE events ADD COLUMN snoozed_until REAL;")
            }
            try runOnDB(db, "DELETE FROM schema_version;")
            try runOnDB(db, "INSERT INTO schema_version (version) VALUES (11);")
        }

        logger.info("Migration to v11 complete")
    }

    // MARK: - V9 -> V10: Repair legacy routing_decisions table shape

    private struct LegacyRoutingDecisionRow {
        var id: String
        var itemID: String
        var ownerType: String
        var targetType: String
        var targetID: String?
        var targetPath: String?
        var confidence: Double
        var reason: String
        var status: String
        var actor: String
        var source: String
        var createdAt: Double
    }

    private static func migrateToV10(_ db: OpaquePointer) throws {
        logger.info("Migrating to schema version 10...")

        try withTransaction(db) {
            try repairRoutingDecisionsSchemaIfNeeded(db)
            try runOnDB(db, CiderSchema.createSecondBrainRoutingDecisions)
            try runOnDB(db, "CREATE INDEX IF NOT EXISTS idx_routing_decisions_item ON routing_decisions(item_id, created_at);")
            try runOnDB(db, "CREATE INDEX IF NOT EXISTS idx_routing_decisions_review ON routing_decisions(review_state);")
            try runOnDB(db, "CREATE INDEX IF NOT EXISTS idx_second_brain_routing_owner ON second_brain_routing_decisions(owner_type, owner_id, created_at);")
            try runOnDB(db, "CREATE INDEX IF NOT EXISTS idx_second_brain_routing_status ON second_brain_routing_decisions(status, created_at);")
            try runOnDB(db, "DELETE FROM schema_version;")
            try runOnDB(db, "INSERT INTO schema_version (version) VALUES (10);")
        }

        logger.info("Migration to v10 complete")
    }

    private static func repairRoutingDecisionsSchemaIfNeeded(_ db: OpaquePointer) throws {
        guard try tableExists(db, table: "routing_decisions") else {
            try runOnDB(db, CiderSchema.createRoutingDecisions)
            return
        }

        let hasCurrentColumns = try columnExists(db, table: "routing_decisions", column: "item_type")
            && columnExists(db, table: "routing_decisions", column: "target_kind")
            && columnExists(db, table: "routing_decisions", column: "review_state")
        if hasCurrentColumns { return }

        let legacyTableName = try nextAvailableLegacyRoutingTableName(db)
        try runOnDB(db, "ALTER TABLE routing_decisions RENAME TO \(quoteIdentifier(legacyTableName));")
        try runOnDB(db, "DROP INDEX IF EXISTS idx_routing_decisions_item;")
        try runOnDB(db, "DROP INDEX IF EXISTS idx_routing_decisions_review;")
        try runOnDB(db, CiderSchema.createRoutingDecisions)

        let legacyRows = try readLegacyRoutingDecisionRows(db, table: legacyTableName)
        for legacyRow in legacyRows {
            guard let itemType = try itemType(for: legacyRow.itemID, fallback: legacyRow.ownerType, db: db) else {
                continue
            }
            try insertMigratedRoutingDecision(legacyRow, itemType: itemType, db: db)
        }
    }

    private static func nextAvailableLegacyRoutingTableName(_ db: OpaquePointer) throws -> String {
        let base = "routing_decisions_legacy_v9"
        if !(try tableExists(db, table: base)) { return base }

        var index = 2
        while try tableExists(db, table: "\(base)_\(index)") {
            index += 1
        }
        return "\(base)_\(index)"
    }

    private static func readLegacyRoutingDecisionRows(_ db: OpaquePointer, table: String) throws -> [LegacyRoutingDecisionRow] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        let sql = """
            SELECT id, item_id, owner_type, target_type, target_id, target_path,
                   confidence, reason, status, actor, source, created_at
            FROM \(quoteIdentifier(table));
            """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw CiderDatabaseError.prepare(String(cString: sqlite3_errmsg(db)))
        }

        var rows: [LegacyRoutingDecisionRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(LegacyRoutingDecisionRow(
                id: sqliteString(stmt, 0) ?? UUID().uuidString,
                itemID: sqliteString(stmt, 1) ?? "",
                ownerType: sqliteString(stmt, 2) ?? "item",
                targetType: sqliteString(stmt, 3) ?? "folder",
                targetID: sqliteString(stmt, 4),
                targetPath: sqliteString(stmt, 5),
                confidence: sqlite3_column_double(stmt, 6),
                reason: sqliteString(stmt, 7) ?? "Migrated from legacy routing decision schema.",
                status: sqliteString(stmt, 8) ?? "needs_review",
                actor: sqliteString(stmt, 9) ?? "unknown",
                source: sqliteString(stmt, 10) ?? "routing.migration.v10",
                createdAt: sqlite3_column_double(stmt, 11)
            ))
        }
        return rows
    }

    private static func insertMigratedRoutingDecision(
        _ row: LegacyRoutingDecisionRow,
        itemType: String,
        db: OpaquePointer
    ) throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        let sql = """
            INSERT INTO routing_decisions (
                id, item_id, item_type, target_kind, target_name, target_relative_path,
                target_folder_id, confidence, reason, actor, source, review_state,
                created_at, supersedes_decision_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL);
            """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw CiderDatabaseError.prepare(String(cString: sqlite3_errmsg(db)))
        }

        let targetPath = normalizedTargetPath(row.targetPath)
        let targetFolderID = try existingFolderID(row.targetID, db: db)
        bindText(stmt, 1, row.id)
        bindText(stmt, 2, row.itemID)
        bindText(stmt, 3, itemType)
        bindText(stmt, 4, normalizedTargetKind(row.targetType, targetPath: targetPath))
        bindText(stmt, 5, targetName(path: targetPath, folderID: targetFolderID, db: db))
        bindText(stmt, 6, targetPath)
        bindText(stmt, 7, targetFolderID)
        sqlite3_bind_double(stmt, 8, row.confidence)
        bindText(stmt, 9, row.reason.isEmpty ? "Migrated from legacy routing decision schema." : row.reason)
        bindText(stmt, 10, row.actor.isEmpty ? "unknown" : row.actor)
        bindText(stmt, 11, row.source.isEmpty ? "routing.migration.v10" : row.source)
        bindText(stmt, 12, normalizedReviewState(row.status))
        sqlite3_bind_double(stmt, 13, row.createdAt)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw CiderDatabaseError.step(String(cString: sqlite3_errmsg(db)))
        }
    }

    private static func itemType(for itemID: String, fallback: String, db: OpaquePointer) throws -> String? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, "SELECT type FROM items WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK else {
            throw CiderDatabaseError.prepare(String(cString: sqlite3_errmsg(db)))
        }
        bindText(stmt, 1, itemID)
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }
        if let type = sqliteString(stmt, 0), !type.isEmpty {
            return type
        }
        let trimmed = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "item" : trimmed
    }

    private static func existingFolderID(_ candidate: String?, db: OpaquePointer) throws -> String? {
        guard let candidate, !candidate.isEmpty else { return nil }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, "SELECT id FROM folders WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK else {
            throw CiderDatabaseError.prepare(String(cString: sqlite3_errmsg(db)))
        }
        bindText(stmt, 1, candidate)
        return sqlite3_step(stmt) == SQLITE_ROW ? candidate : nil
    }

    private static func folderRelativePath(for folderID: String?, db: OpaquePointer) -> String? {
        guard let folderID, !folderID.isEmpty else { return nil }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, "SELECT relative_path FROM folders WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        bindText(stmt, 1, folderID)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqliteString(stmt, 0)
    }

    private static func normalizedTargetPath(_ path: String?) -> String {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Inbox/Bookmarks" : trimmed
    }

    private static func normalizedTargetKind(_ kind: String, targetPath: String) -> String {
        let normalized = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !normalized.isEmpty { return normalized }
        return targetPath.lowercased().hasPrefix("inbox") ? "inbox" : "folder"
    }

    private static func targetName(path: String, folderID: String?, db: OpaquePointer) -> String {
        let folderPath = folderRelativePath(for: folderID, db: db)
        let source = folderPath?.isEmpty == false ? folderPath! : path
        return source.split(separator: "/").last.map(String.init) ?? source
    }

    private static func normalizedReviewState(_ state: String) -> String {
        let normalized = state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "accepted", "corrected", "deferred", "suggested", "needs_review":
            return normalized
        case "approved":
            return "accepted"
        case "defer":
            return "deferred"
        default:
            return "needs_review"
        }
    }

    // MARK: - V8 -> V9: Second brain sections, chunks, routing, and agent provenance

    private static func migrateToV9(_ db: OpaquePointer) throws {
        logger.info("Migrating to schema version 9...")

        try withTransaction(db) {
            try runOnDB(db, CiderSchema.createItemSections)
            try runOnDB(db, CiderSchema.createContentChunks)
            try runOnDB(db, CiderSchema.createContentChunksFTS)
            try runOnDB(db, CiderSchema.createContentChunksFTSInsertTrigger)
            try runOnDB(db, CiderSchema.createContentChunksFTSDeleteTrigger)
            try runOnDB(db, CiderSchema.createContentChunksFTSUpdateTrigger)
            try runOnDB(db, CiderSchema.createRoutingDecisions)
            try runOnDB(db, CiderSchema.createSecondBrainRoutingDecisions)
            try runOnDB(db, CiderSchema.createAgentActions)

            for sql in CiderSchema.createIndexes {
                try runOnDB(db, sql)
            }

            try runOnDB(db, "DELETE FROM schema_version;")
            try runOnDB(db, "INSERT INTO schema_version (version) VALUES (9);")
        }

        logger.info("Migration to v9 complete")
    }

    // MARK: - V7 -> V8: Direct action URLs for todos and events

    private static func migrateToV8(_ db: OpaquePointer) throws {
        logger.info("Migrating to schema version 8...")

        try withTransaction(db) {
            if try tableExists(db, table: "todos"),
               !(try columnExists(db, table: "todos", column: "action_url")) {
                try runOnDB(db, "ALTER TABLE todos ADD COLUMN action_url TEXT;")
            }
            if try tableExists(db, table: "events"),
               !(try columnExists(db, table: "events", column: "action_url")) {
                try runOnDB(db, "ALTER TABLE events ADD COLUMN action_url TEXT;")
            }
            try runOnDB(db, "DELETE FROM schema_version;")
            try runOnDB(db, "INSERT INTO schema_version (version) VALUES (8);")
        }

        logger.info("Migration to v8 complete")
    }

    // MARK: - V6 -> V7: Contact custom fields

    private static func migrateToV7(_ db: OpaquePointer) throws {
        logger.info("Migrating to schema version 7...")

        try withTransaction(db) {
            if try tableExists(db, table: "contacts"),
               !(try columnExists(db, table: "contacts", column: "custom_fields")) {
                try runOnDB(db, "ALTER TABLE contacts ADD COLUMN custom_fields TEXT NOT NULL DEFAULT '[]';")
            }
            try runOnDB(db, "DELETE FROM schema_version;")
            try runOnDB(db, "INSERT INTO schema_version (version) VALUES (7);")
        }

        logger.info("Migration to v7 complete")
    }

    // MARK: - V5 -> V6: mutation audit log

    private static func migrateToV6(_ db: OpaquePointer) throws {
        logger.info("Migrating to schema version 6...")

        try withTransaction(db) {
            try runOnDB(db, CiderSchema.createMutationAudit)
            try runOnDB(db, "CREATE INDEX IF NOT EXISTS idx_mutation_audit_time ON mutation_audit(occurred_at);")
            try runOnDB(db, "CREATE INDEX IF NOT EXISTS idx_mutation_audit_item ON mutation_audit(item_type, item_id, occurred_at);")
            try runOnDB(db, "DELETE FROM schema_version;")
            try runOnDB(db, "INSERT INTO schema_version (version) VALUES (6);")
        }

        logger.info("Migration to v6 complete")
    }

    // MARK: - V4 -> V5: Note summaries move into SQLite

    private static func migrateToV5(_ db: OpaquePointer) throws {
        logger.info("Migrating to schema version 5...")

        try withTransaction(db) {
            if try tableExists(db, table: "notes"),
               !(try columnExists(db, table: "notes", column: "summary")) {
                try runOnDB(db, "ALTER TABLE notes ADD COLUMN summary TEXT;")
            }
            try runOnDB(db, "DELETE FROM schema_version;")
            try runOnDB(db, "INSERT INTO schema_version (version) VALUES (5);")
        }

        logger.info("Migration to v5 complete")
    }

    // MARK: - V3 -> V4: Todo surfacing rules

    private static func migrateToV4(_ db: OpaquePointer) throws {
        logger.info("Migrating to schema version 4...")

        try withTransaction(db) {
            if try tableExists(db, table: "todos"),
               !(try columnExists(db, table: "todos", column: "surfacing_rules")) {
                try runOnDB(db, "ALTER TABLE todos ADD COLUMN surfacing_rules TEXT;")
            }
            try runOnDB(db, "DELETE FROM schema_version;")
            try runOnDB(db, "INSERT INTO schema_version (version) VALUES (4);")
        }

        logger.info("Migration to v4 complete")
    }

    // MARK: - V2 -> V3: Clean up ghost storage-type folder rows
    //
    // Older code paths wrote folder rows for paths under reserved top-level
    // directories (Inbox/Bookmarks, Unsorted/..., etc.). These aren't real
    // user folders — they're storage-type subtrees that the reconciler
    // correctly excludes from disk scans. The stale rows linger in the
    // `folders` table with live items attached, causing every reconcile to
    // log "Skipping removal of missing folder …" and blocking cleanup.
    //
    // This migration:
    //   1. Identifies folder rows whose path starts with a reserved top
    //      component.
    //   2. Re-parents any items and sessions pointing at them to NULL
    //      (semantically "unfiled", which puts them back in the Inbox view).
    //   3. Deletes the ghost folder rows.
    private static func migrateToV3(_ db: OpaquePointer) throws {
        logger.info("Migrating to schema version 3...")

        // Top-level reserved directory names. Kept in sync with
        // VaultFolderService.reservedDirectoryNames — duplicated here so the
        // migration stays self-contained (no service-layer imports into the
        // DB layer).
        let reservedTopComponents: [String] = [
            "Inbox", "Unsorted",
            "Bookmarks", "Contacts", "DateCards", "Labels", "Notes",
            "SavedViews", "Sources", "Stacks", "Tags",
        ]

        try withTransaction(db) {
            var ghostIDs: [String] = []
            for top in reservedTopComponents {
                let escaped = top.replacingOccurrences(of: "'", with: "''")
                // Match "<reserved>" exactly OR "<reserved>/…". Don't match
                // "Inboxed" or similar unrelated prefixes.
                let pattern1 = "\(escaped)"
                let pattern2 = "\(escaped)/%"
                let sql = """
                    SELECT id FROM folders
                    WHERE relative_path = '\(pattern1)'
                       OR relative_path LIKE '\(pattern2)';
                    """
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    sqlite3_finalize(stmt)
                    throw CiderDatabaseError.prepare(String(cString: sqlite3_errmsg(db)))
                }
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let cID = sqlite3_column_text(stmt, 0) {
                        ghostIDs.append(String(cString: cID))
                    }
                }
                sqlite3_finalize(stmt)
            }

            if ghostIDs.isEmpty {
                logger.info("No ghost storage-type folders to clean up")
            } else {
                logger.info("Cleaning up \(ghostIDs.count) ghost storage-type folder(s)")
                for ghostID in ghostIDs {
                    let escaped = ghostID.replacingOccurrences(of: "'", with: "''")
                    // Re-parent dependents to NULL before deleting the row so
                    // the FK constraint doesn't reject the delete.
                    try runOnDB(db, "UPDATE items SET folder_id = NULL WHERE folder_id = '\(escaped)';")
                    try runOnDB(db, "UPDATE sessions SET folder_id = NULL WHERE folder_id = '\(escaped)';")
                    try runOnDB(db, "DELETE FROM folders WHERE id = '\(escaped)';")
                }
            }

            try runOnDB(db, "DELETE FROM schema_version;")
            try runOnDB(db, "INSERT INTO schema_version (version) VALUES (3);")
        }

        logger.info("Migration to v3 complete")
    }

    // MARK: - V1 -> V2: vault_files.title_manually_set + schema_migrations table

    private static func migrateToV2(_ db: OpaquePointer) throws {
        logger.info("Migrating to schema version 2...")

        try withTransaction(db) {
            if try tableExists(db, table: "vault_files") {
                // Idempotent ALTER: only add the column if it's not already present.
                if !(try columnExists(db, table: "vault_files", column: "title_manually_set")) {
                    try runOnDB(db, "ALTER TABLE vault_files ADD COLUMN title_manually_set INTEGER NOT NULL DEFAULT 0;")
                }
            } else {
                logger.warning("Schema version 1 is missing vault_files; skipping v2 ALTER TABLE")
            }
            // Ensure the named-migration ledger exists (harmless if already created by v1 fresh installs).
            try runOnDB(db, CiderSchema.createSchemaMigrations)
            try runOnDB(db, "DELETE FROM schema_version;")
            try runOnDB(db, "INSERT INTO schema_version (version) VALUES (2);")
        }

        logger.info("Migration to v2 complete")
    }

    private static func tableExists(_ db: OpaquePointer, table: String) throws -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        let escapedTable = table.replacingOccurrences(of: "'", with: "''")
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '\(escapedTable)' LIMIT 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw CiderDatabaseError.prepare(String(cString: sqlite3_errmsg(db)))
        }

        let step = sqlite3_step(stmt)
        if step == SQLITE_ROW {
            return true
        }
        if step == SQLITE_DONE {
            return false
        }
        throw CiderDatabaseError.step(String(cString: sqlite3_errmsg(db)))
    }

    /// Returns true if `column` exists on `table` (queries PRAGMA table_info).
    private static func columnExists(_ db: OpaquePointer, table: String, column: String) throws -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "PRAGMA table_info(\(table));"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw CiderDatabaseError.prepare(String(cString: sqlite3_errmsg(db)))
        }
        while sqlite3_step(stmt) == SQLITE_ROW {
            // Column 1 of table_info is the column name.
            if let cName = sqlite3_column_text(stmt, 1) {
                let name = String(cString: cName)
                if name == column { return true }
            }
        }
        return false
    }

    private static func quoteIdentifier(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func sqliteString(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let text = sqlite3_column_text(stmt, index) else {
            return nil
        }
        return String(cString: text)
    }

    private static func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        guard let value else {
            sqlite3_bind_null(stmt, index)
            return
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, transient)
    }

    // MARK: - V0 -> V1: Create all tables

    private static func migrateToV1(_ db: OpaquePointer) throws {
        logger.info("Migrating to schema version 1...")

        try withTransaction(db) {
            // Create all tables in dependency order
            for sql in CiderSchema.allTables {
                try runOnDB(db, sql)
            }

            // Create all indexes
            for sql in CiderSchema.createIndexes {
                try runOnDB(db, sql)
            }

            // Set version to 1 (keep schema_version as a single-row table).
            try runOnDB(db, "DELETE FROM schema_version;")
            try runOnDB(db, "INSERT INTO schema_version (version) VALUES (1);")
        }

        logger.info("Migration to v1 complete")
    }

    // MARK: - Helpers

    private static func readVersion(_ db: OpaquePointer) throws -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        let rc = sqlite3_prepare_v2(db, "SELECT MAX(version) FROM schema_version;", -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw CiderDatabaseError.prepare(message)
        }

        let stepResult = sqlite3_step(stmt)
        if stepResult == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        // No rows means version 0 (fresh database)
        return 0
    }

    private static func withTransaction(_ db: OpaquePointer, body: () throws -> Void) throws {
        try runOnDB(db, "BEGIN TRANSACTION;")
        do {
            try body()
            try runOnDB(db, "COMMIT;")
        } catch {
            try? runOnDB(db, "ROLLBACK;")
            throw error
        }
    }

    private static func runOnDB(_ db: OpaquePointer, _ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorMessage) }
        let rc = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if rc != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown error"
            throw CiderDatabaseError.runExec(message)
        }
    }
}
