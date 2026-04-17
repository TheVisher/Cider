import Foundation
import os

enum MutationAuditSource: String, Codable {
    case ui
    case cli
    case agent
    case migration
    case cleanup
}

@MainActor
enum MutationAuditContext {
    private static var sourceStack: [MutationAuditSource] = []

    static var currentSource: MutationAuditSource {
        sourceStack.last ?? .ui
    }

    static func withSource<T>(
        _ source: MutationAuditSource,
        _ body: () throws -> T
    ) rethrows -> T {
        sourceStack.append(source)
        defer { _ = sourceStack.popLast() }
        return try body()
    }

    static func withSource<T>(
        _ source: MutationAuditSource,
        operation: () async throws -> T
    ) async rethrows -> T {
        sourceStack.append(source)
        defer { _ = sourceStack.popLast() }
        return try await operation()
    }
}

struct MutationAuditEntry: Identifiable, Equatable {
    let id: UUID
    let occurredAt: Date
    let itemType: String
    let itemID: UUID
    let action: String
    let source: MutationAuditSource
    let beforeState: [String: String]
    let afterState: [String: String]
    let metadata: [String: String]
}

@MainActor
final class MutationAuditService {
    static let shared = MutationAuditService()

    private let logger = Logger(subsystem: "com.cider.app", category: "MutationAudit")
    private let database: CiderDatabase?

    private var resolvedDatabase: CiderDatabase? {
        database ?? (CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil)
    }

    init(database: CiderDatabase? = nil) {
        self.database = database
    }

    func record(
        action: String,
        itemType: String,
        itemID: UUID,
        before: [String: String]? = nil,
        after: [String: String]? = nil,
        metadata: [String: String]? = nil,
        source: MutationAuditSource? = nil
    ) {
        guard let db = resolvedDatabase else { return }

        let entry = MutationAuditEntry(
            id: UUID(),
            occurredAt: Date(),
            itemType: itemType,
            itemID: itemID,
            action: action,
            source: source ?? inferredSource(),
            beforeState: before ?? [:],
            afterState: after ?? [:],
            metadata: metadata ?? [:]
        )

        do {
            try db.withTransaction {
                try self.persist(entry, in: db)
            }
        } catch {
            logger.error("Failed to record mutation audit entry: \(error.localizedDescription)")
        }
    }

    func loadEntries(limit: Int? = nil) -> [MutationAuditEntry] {
        guard let db = resolvedDatabase else { return [] }

        do {
            let sql: String
            if let limit, limit > 0 {
                sql = """
                    SELECT id, occurred_at, item_type, item_id, action, source, before_state, after_state, metadata
                    FROM mutation_audit
                    ORDER BY occurred_at DESC, id DESC
                    LIMIT \(limit);
                    """
            } else {
                sql = """
                    SELECT id, occurred_at, item_type, item_id, action, source, before_state, after_state, metadata
                    FROM mutation_audit
                    ORDER BY occurred_at DESC, id DESC;
                    """
            }

            let stmt = try db.prepare(sql)
            var entries: [MutationAuditEntry] = []
            while try stmt.step() {
                guard
                    let id = DatabaseHelpers.decodeUUID(stmt.string(at: 0)),
                    let itemID = DatabaseHelpers.decodeUUID(stmt.string(at: 3)),
                    let source = MutationAuditSource(rawValue: stmt.string(at: 5))
                else {
                    continue
                }

                entries.append(
                    MutationAuditEntry(
                        id: id,
                        occurredAt: DatabaseHelpers.decodeDate(stmt.double(at: 1)),
                        itemType: stmt.string(at: 2),
                        itemID: itemID,
                        action: stmt.string(at: 4),
                        source: source,
                        beforeState: DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 6)) ?? [:],
                        afterState: DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 7)) ?? [:],
                        metadata: DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 8)) ?? [:]
                    )
                )
            }
            return entries
        } catch {
            logger.error("Failed to load mutation audit entries: \(error.localizedDescription)")
            return []
        }
    }

    private func persist(_ entry: MutationAuditEntry, in db: CiderDatabase) throws {
        let stmt = try db.prepare("""
            INSERT INTO mutation_audit (
                id, occurred_at, item_type, item_id, action, source, before_state, after_state, metadata
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)

        stmt.bind(DatabaseHelpers.encode(entry.id), at: 1)
            .bind(DatabaseHelpers.encode(entry.occurredAt), at: 2)
            .bind(entry.itemType, at: 3)
            .bind(DatabaseHelpers.encode(entry.itemID), at: 4)
            .bind(entry.action, at: 5)
            .bind(entry.source.rawValue, at: 6)
            .bind(DatabaseHelpers.encodeJSON(entry.beforeState), at: 7)
            .bind(DatabaseHelpers.encodeJSON(entry.afterState), at: 8)
            .bind(DatabaseHelpers.encodeJSON(entry.metadata), at: 9)
        try stmt.step()
    }

    private func inferredSource() -> MutationAuditSource {
        let contextualSource = MutationAuditContext.currentSource
        if contextualSource != .ui {
            return contextualSource
        }

        let processName = ProcessInfo.processInfo.processName.lowercased()
        if processName == "cider-cli" || processName == "cidercli" {
            return .cli
        }

        return .ui
    }
}

enum MutationAuditSnapshots {
    static func folder(_ folder: VaultFolder) -> [String: String] {
        compact([
            ("name", folder.name),
            ("relativePath", folder.relativePath),
            ("parentRelativePath", folder.parentRelativePath),
            ("icon", folder.icon),
        ])
    }

    static func bookmark(_ bookmark: Bookmark) -> [String: String] {
        compact([
            ("title", bookmark.title),
            ("url", bookmark.urlString),
            ("folderID", bookmark.folderID?.uuidString),
            ("relativePath", bookmark.relativePath),
            ("tagCount", String(bookmark.tags.count)),
            ("labelCount", String(bookmark.labelIDs.count)),
        ])
    }

    static func note(_ note: Note) -> [String: String] {
        compact([
            ("title", note.title),
            ("folderID", note.folderID?.uuidString),
            ("relativePath", note.relativePath),
            ("tagCount", String(note.tags.count)),
            ("labelCount", String(note.labelIDs.count)),
            ("isPinned", boolString(note.isPinned)),
        ])
    }

    static func todo(_ todo: TodoCard) -> [String: String] {
        compact([
            ("title", todo.title),
            ("folderID", todo.folderID?.uuidString),
            ("dueDate", dateString(todo.dueDate)),
            ("priority", todo.priority?.rawValue),
            ("isCompleted", boolString(todo.isCompleted)),
        ])
    }

    static func dateCard(_ card: DateCard) -> [String: String] {
        compact([
            ("title", card.title),
            ("folderID", card.folderID?.uuidString),
            ("startAt", dateString(card.startAt)),
            ("allDay", boolString(card.allDay)),
            ("isCompleted", boolString(card.isCompleted)),
            ("reminderOffsets", reminderOffsetsString(card)),
        ])
    }

    static func contact(_ contact: ContactCard) -> [String: String] {
        compact([
            ("displayName", contact.displayName),
            ("folderID", contact.folderID?.uuidString),
            ("email", contact.email),
            ("phone", contact.phone),
            ("hasAvatar", boolString(contact.hasAvatar)),
        ])
    }

    static func vaultFile(_ file: VaultFile) -> [String: String] {
        compact([
            ("filename", file.filename),
            ("displayTitle", file.displayTitle),
            ("folderID", file.folderID?.uuidString),
            ("relativePath", file.relativePath),
            ("fileType", file.fileType.rawValue),
        ])
    }

    static func trashItem(_ item: TrashItem) -> [String: String] {
        compact([
            ("trashItemID", item.id.uuidString),
            ("title", item.title),
            ("itemType", item.itemType.rawValue),
            ("originalFolderID", item.originalFolderID?.uuidString),
            ("deletedAt", dateString(item.deletedAt)),
        ])
    }

    private static func compact(_ pairs: [(String, String?)]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: pairs.compactMap { key, value in
            value.map { (key, $0) }
        })
    }

    private static func dateString(_ date: Date?) -> String? {
        guard let date else { return nil }
        return String(date.timeIntervalSince1970)
    }

    private static func boolString(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    private static func reminderOffsetsString(_ card: DateCard) -> String? {
        let offsets = card.rules
            .filter { $0.type == .remindBeforeMinutes && $0.isEnabled }
            .compactMap(\.integerValue)
            .sorted()
        guard !offsets.isEmpty else { return nil }
        return offsets.map(String.init).joined(separator: ",")
    }
}
