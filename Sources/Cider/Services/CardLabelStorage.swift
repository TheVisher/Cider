import Foundation
import Combine
import os

private struct CardLabelsSnapshot: Codable {
    var labels: [CardLabel]
}

@MainActor
final class CardLabelStorage: ObservableObject {
    static let shared = CardLabelStorage()

    @Published private(set) var labels: [CardLabel] = []

    private let logger = Logger(subsystem: "com.cider.app", category: "CardLabelStorage")
    private let database: CiderDatabase?

    private let fileName = "_cider_labels.json"
    private let backupFileName = "_cider_labels-backup.json"
    private var fileURL: URL {
        let dir = StoragePaths.directoryURL(for: .labels)
        StoragePaths.ensureDirectory(dir)
        return StoragePaths.jsonFileURL(fileName: fileName, in: dir)
    }
    private var backupFileURL: URL {
        let dir = StoragePaths.vaultDirectoryURL()
            .appendingPathComponent(StoragePaths.ciderInternalDir)
        StoragePaths.ensureDirectory(dir)
        return StoragePaths.jsonFileURL(fileName: backupFileName, in: dir)
    }

    private init() {
        self.database = nil
        loadFromDatabaseOrJSON()
    }

    /// Testing-only initializer that accepts an explicit database instance.
    init(database: CiderDatabase) {
        self.database = database
        loadFromDatabase(database)
    }

    func reload() {
        loadFromDatabaseOrJSON()
    }

    @discardableResult
    func createLabel(
        name: String,
        colorHex: String = "#6B7280",
        kind: CardLabelKind = .custom
    ) -> CardLabel {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Untitled Label" : trimmed
        let label = CardLabel(name: finalName, colorHex: colorHex, kind: kind)
        labels.append(label)
        sortLabels()
        persistToDatabase(label)
        persistBackupJSON()
        return label
    }

    @discardableResult
    func updateLabel(_ updated: CardLabel) -> Bool {
        guard let idx = labels.firstIndex(where: { $0.id == updated.id }) else { return false }
        var copy = updated
        copy.updatedAt = Date()
        labels[idx] = copy
        sortLabels()
        persistToDatabase(copy)
        persistBackupJSON()
        return true
    }

    /// Find an existing label by case-insensitive name match, or create a new one.
    @discardableResult
    func findOrCreate(name: String, colorHex: String? = nil) -> CardLabel {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = labels.first(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        return createLabel(name: trimmed, colorHex: colorHex ?? Self.randomPresetColor())
    }

    @discardableResult
    func deleteLabel(_ id: UUID) -> Bool {
        let oldCount = labels.count
        labels.removeAll { $0.id == id }
        guard labels.count != oldCount else { return false }
        deleteFromDatabase(labelID: id)
        persistBackupJSON()
        // Cascade: remove this label from all items
        VaultBookmarkService.shared.removeLabelsFromAll(labelID: id)
        NotesStorage.shared.removeLabelsFromAll(labelID: id)
        DateCardStorage.shared.removeLabelsFromAll(labelID: id)
        ContactStorage.shared.removeLabelsFromAll(labelID: id)
        TodoCardStorage.shared.removeLabelsFromAll(labelID: id)
        return true
    }

    /// Merge multiple source labels into a single target label.
    /// All items with source labels get the target label, then sources are deleted.
    func mergeLabels(sourceIDs: [UUID], into targetID: UUID) {
        guard labels.contains(where: { $0.id == targetID }) else { return }
        let sources = Set(sourceIDs).subtracting([targetID])
        guard !sources.isEmpty else { return }

        // Reassign items: for each source label, find items and give them the target
        for sourceID in sources {
            reassignLabelOnAllItems(from: sourceID, to: targetID)
            labels.removeAll { $0.id == sourceID }
            deleteFromDatabase(labelID: sourceID)
        }
        persistBackupJSON()
    }

    /// Color presets for tags.
    static let tagColorPresets: [(name: String, hex: String)] = [
        ("Red", "#EF4444"), ("Orange", "#F97316"), ("Yellow", "#EAB308"),
        ("Green", "#22C55E"), ("Teal", "#14B8A6"), ("Blue", "#3B82F6"),
        ("Purple", "#8B5CF6"), ("Pink", "#EC4899"), ("Gray", "#6B7280"),
        ("Brown", "#78716C")
    ]

    static func randomPresetColor() -> String {
        tagColorPresets.randomElement()?.hex ?? "#6B7280"
    }

    private func reassignLabelOnAllItems(from sourceID: UUID, to targetID: UUID) {
        // Bookmarks
        for bookmark in VaultBookmarkService.shared.bookmarks where bookmark.labelIDs.contains(sourceID) {
            VaultBookmarkService.shared.removeLabel(bookmark.id, labelID: sourceID)
            VaultBookmarkService.shared.assignLabel(bookmark.id, labelID: targetID)
        }
        // Notes
        for note in NotesStorage.shared.notes where note.labelIDs.contains(sourceID) {
            NotesStorage.shared.removeLabel(note.id, labelID: sourceID)
            NotesStorage.shared.assignLabel(note.id, labelID: targetID)
        }
        // DateCards
        for card in DateCardStorage.shared.dateCards where card.labelIDs.contains(sourceID) {
            var updated = card
            updated.labelIDs.removeAll { $0 == sourceID }
            if !updated.labelIDs.contains(targetID) { updated.labelIDs.append(targetID) }
            DateCardStorage.shared.updateDateCard(updated)
        }
        // Contacts
        for contact in ContactStorage.shared.contacts where contact.labelIDs.contains(sourceID) {
            var updated = contact
            updated.labelIDs.removeAll { $0 == sourceID }
            if !updated.labelIDs.contains(targetID) { updated.labelIDs.append(targetID) }
            ContactStorage.shared.updateContact(updated)
        }
        // Todos
        for todo in TodoCardStorage.shared.todoCards where todo.labelIDs.contains(sourceID) {
            var updated = todo
            updated.labelIDs.removeAll { $0 == sourceID }
            if !updated.labelIDs.contains(targetID) { updated.labelIDs.append(targetID) }
            TodoCardStorage.shared.updateTodoCard(updated)
        }
    }

    func label(for id: UUID) -> CardLabel? {
        labels.first { $0.id == id }
    }

    /// Total item count across all entity storages for a given label.
    func itemCount(for labelID: UUID) -> Int {
        VaultBookmarkService.shared.bookmarks.filter { $0.labelIDs.contains(labelID) }.count
        + NotesStorage.shared.notes.filter { $0.labelIDs.contains(labelID) }.count
        + DateCardStorage.shared.dateCards.filter { $0.labelIDs.contains(labelID) }.count
        + ContactStorage.shared.contacts.filter { $0.labelIDs.contains(labelID) }.count
    }

    private func sortLabels() {
        labels.sort { lhs, rhs in
            let cmp = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if cmp != .orderedSame {
                return cmp == .orderedAscending
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    // MARK: - Database Persistence

    /// Resolve which database instance to use: explicit (testing) or shared (production).
    private var resolvedDatabase: CiderDatabase? {
        database ?? (CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil)
    }

    /// Load labels from SQLite, falling back to JSON if the database is unavailable.
    /// When JSON labels are loaded and the database later becomes available,
    /// this also performs a one-time migration of JSON labels into SQLite.
    private func loadFromDatabaseOrJSON() {
        if let db = resolvedDatabase {
            loadFromDatabase(db)
        } else {
            loadFromJSON()
            // One-time migration: if we loaded labels from JSON and the database
            // is now available, persist them to SQLite so future launches use the DB.
            if !labels.isEmpty, let db = resolvedDatabase {
                logger.info("Migrating \(self.labels.count) labels from JSON to SQLite")
                for label in labels {
                    persistToDatabase(db, label: label)
                }
            }
        }
    }

    // Internal for testing
    /// SELECT all labels from the database, ordered by name.
    func loadFromDatabase(_ db: CiderDatabase) {
        do {
            let stmt = try db.prepare(
                "SELECT id, name, color_hex, kind, created_at, updated_at FROM labels ORDER BY name COLLATE NOCASE;"
            )
            var loaded: [CardLabel] = []
            while try stmt.step() {
                guard let id = DatabaseHelpers.decodeUUID(stmt.string(at: 0)) else { continue }
                let kindRaw = stmt.string(at: 3)
                let kind = CardLabelKind(rawValue: kindRaw) ?? .custom
                let label = CardLabel(
                    id: id,
                    name: stmt.string(at: 1),
                    colorHex: stmt.string(at: 2),
                    kind: kind,
                    createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 4)),
                    updatedAt: DatabaseHelpers.decodeDate(stmt.double(at: 5))
                )
                loaded.append(label)
            }
            labels = loaded
            sortLabels()
            logger.info("Loaded \(loaded.count) labels from database")
        } catch {
            logger.error("Failed to load labels from database: \(error.localizedDescription)")
            labels = []
        }
    }

    /// INSERT OR REPLACE a single label into the database.
    func persistToDatabase(_ label: CardLabel) {
        guard let db = resolvedDatabase else {
            logger.warning("No database available, skipping SQLite persist for label \(label.id)")
            return
        }
        persistToDatabase(db, label: label)
    }

    // Internal for testing
    /// INSERT OR REPLACE a single label into the given database.
    func persistToDatabase(_ db: CiderDatabase, label: CardLabel) {
        do {
            let stmt = try db.prepare("""
                INSERT OR REPLACE INTO labels (id, name, color_hex, kind, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?);
                """)
            stmt.bind(DatabaseHelpers.encode(label.id), at: 1)
                .bind(label.name, at: 2)
                .bind(label.colorHex, at: 3)
                .bind(label.kind.rawValue, at: 4)
                .bind(DatabaseHelpers.encode(label.createdAt), at: 5)
                .bind(DatabaseHelpers.encode(label.updatedAt), at: 6)
            try stmt.step()
        } catch {
            logger.error("Failed to persist label \(label.id) to database: \(error.localizedDescription)")
        }
    }

    /// DELETE a label from the database by ID.
    func deleteFromDatabase(labelID: UUID) {
        guard let db = resolvedDatabase else {
            logger.warning("No database available, skipping SQLite delete for label \(labelID)")
            return
        }
        deleteFromDatabase(db, labelID: labelID)
    }

    // Internal for testing
    /// DELETE a label from the given database by ID.
    func deleteFromDatabase(_ db: CiderDatabase, labelID: UUID) {
        do {
            let stmt = try db.prepare("DELETE FROM labels WHERE id = ?;")
            stmt.bind(DatabaseHelpers.encode(labelID), at: 1)
            try stmt.step()
        } catch {
            logger.error("Failed to delete label \(labelID) from database: \(error.localizedDescription)")
        }
    }

    // MARK: - JSON Persistence (legacy load + backup)

    /// Load labels from the legacy JSON file (used when database is unavailable).
    private func loadFromJSON() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(CardLabelsSnapshot.self, from: data)
            labels = snapshot.labels
            sortLabels()
        } catch {
            logger.error("Failed to load labels from JSON: \(error.localizedDescription)")
            labels = []
        }
    }

    /// Write a JSON backup after every mutation for rebuild recoverability.
    private func persistBackupJSON() {
        let snapshot = CardLabelsSnapshot(labels: labels)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: backupFileURL, options: .atomic)
        } catch {
            logger.error("Failed to write labels backup JSON: \(error.localizedDescription)")
        }
    }

}
