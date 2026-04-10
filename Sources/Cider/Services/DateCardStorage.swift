import Combine
import Foundation
import os

/// Manages date cards as individual .ics (VEVENT) files on disk, mirrored to SQLite.
///
/// File layout:
/// - Unfiled date cards: `Inbox/Date Cards/{title}.ics`
/// - Filed date cards: `{UserFolder}/{title}.ics`
/// - Trash: `.cider/date-cards/.trash/`
@MainActor
final class DateCardStorage: ObservableObject {
    static let shared = DateCardStorage()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Cider",
        category: "DateCardStorage"
    )

    @Published private(set) var dateCards: [DateCard] = []

    private let fileExtension = "ics"

    /// Per-date-card metadata persisted in the index file.
    private struct IndexEntry: Codable, Equatable {
        var filename: String
        var folderID: UUID?
        var labelIDs: [UUID]?
        var createdAt: Date?
        var isCompleted: Bool?
        var startAt: Date?
    }

    private var index: [UUID: IndexEntry] = [:]
    private var inboxWatcher: FSEventsWatcher?
    private var isScanning = false
    private var pendingRescan = false
    private var database: CiderDatabase?

    /// Resolve which database instance to use: explicit (testing) or shared (production).
    private var resolvedDatabase: CiderDatabase? {
        database ?? (CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil)
    }

    /// Returns the encoded folder_id TEXT if the folder exists in the target
    /// database, otherwise nil. Used to defuse items.folder_id FK violations
    /// when in-memory state has drifted from SQLite.
    private func resolveSafeFolderID(_ db: CiderDatabase, folderID: UUID?) throws -> String? {
        guard let id = folderID else { return nil }
        let encoded = DatabaseHelpers.encode(id)
        let stmt = try db.prepare("SELECT 1 FROM folders WHERE id = ? LIMIT 1;")
        stmt.bind(encoded, at: 1)
        let exists = try stmt.step()
        return exists ? encoded : nil
    }

    private var metadataDirectoryURL: URL {
        StoragePaths.cachedDirectoryURL(for: .dateCards)
    }

    private var inboxDirectoryURL: URL {
        StoragePaths.cachedInboxSubdirectoryURL(for: .dateCards)
    }

    private var vaultRoot: URL {
        StoragePaths.cachedVaultDirectoryURL
    }

    private init() {
        ensureDirectories()
        loadIndex()

        // Try SQLite first (mirrors TodoCardStorage/NotesStorage pattern).
        if let db = resolvedDatabase {
            loadEventsFromDatabase(db)
            if !dateCards.isEmpty {
                startWatching()
                return
            }
        }

        scanAndLoad()
        startWatching()

        // One-time migration: persist JSON-sourced date cards to SQLite.
        // `persistEventToDatabaseInner` scrubs dangling folder_id references
        // at the lowest level so a single stale reference can't abort the
        // whole migration.
        if !dateCards.isEmpty, let db = resolvedDatabase {
            logger.info("Migrating \(self.dateCards.count) date cards from .ics/JSON to SQLite")
            do {
                try db.withTransaction {
                    for card in self.dateCards {
                        try self.persistEventToDatabaseInner(db, dateCard: card)
                    }
                }
            } catch {
                logger.error("Failed to migrate date cards to SQLite: \(error.localizedDescription)")
            }
        }
    }

    /// Testing-only initializer with an explicit database.
    /// Does NOT scan the file system — tests call loadEventsFromDatabase() directly
    /// or use the persist/delete helpers.
    init(database: CiderDatabase) {
        self.database = database
    }

    /// Testing-only: seed the in-memory index so that `persistEventToDatabase`
    /// picks up a specific filename (used to verify that uniquified filenames
    /// like "Title (2).ics" round-trip through items.relative_path).
    func _setIndexEntryForTesting(
        dateCardID: UUID,
        filename: String,
        folderID: UUID? = nil
    ) {
        index[dateCardID] = IndexEntry(
            filename: filename,
            folderID: folderID,
            labelIDs: nil,
            createdAt: Date(),
            isCompleted: false,
            startAt: Date()
        )
    }

    /// Testing-only: read the filename currently tracked in the index for a date card.
    func _indexFilenameForTesting(dateCardID: UUID) -> String? {
        index[dateCardID]?.filename
    }

    func startWatching() {
        inboxWatcher?.stop()
        inboxWatcher = FSEventsWatcher(path: inboxDirectoryURL.path, latency: 1.0) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isScanning {
                    self.pendingRescan = true
                } else {
                    self.rescan()
                }
            }
        }
        inboxWatcher?.start()
    }

    func rescan() {
        guard !isScanning else { pendingRescan = true; return }
        isScanning = true
        defer {
            isScanning = false
            if pendingRescan {
                pendingRescan = false
                rescan()
            }
        }
        scanAndLoad()
    }

    private func ensureDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: metadataDirectoryURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: inboxDirectoryURL, withIntermediateDirectories: true)
    }

    // MARK: - CRUD

    @discardableResult
    func createDateCard(
        title: String,
        startAt: Date,
        endAt: Date? = nil,
        allDay: Bool = false,
        amount: Double? = nil
    ) -> DateCard {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmed.isEmpty ? "Untitled Date Card" : trimmed
        let dateCard = DateCard(
            title: finalTitle,
            startAt: startAt,
            endAt: endAt,
            allDay: allDay,
            amount: amount
        )

        let filename = uniqueFilename(for: finalTitle, in: inboxDirectoryURL)
        guard writeICSFile(for: dateCard, to: inboxDirectoryURL.appendingPathComponent(filename)) else {
            logger.error("createDateCard aborted for \(dateCard.id): initial .ics write failed")
            return dateCard
        }

        index[dateCard.id] = IndexEntry(
            filename: filename, folderID: nil, labelIDs: nil,
            createdAt: dateCard.createdAt, isCompleted: false,
            startAt: startAt
        )
        saveIndex()

        dateCards.append(dateCard)
        sortCards()
        persistEventToDatabase(dateCard)
        return dateCard
    }

    @discardableResult
    func updateDateCard(_ updated: DateCard) -> Bool {
        guard let idx = dateCards.firstIndex(where: { $0.id == updated.id }) else { return false }
        var copy = updated
        copy.updatedAt = Date()

        let oldEntry = index[updated.id]
        let oldFilename = oldEntry?.filename
        let newBaseName = sanitizedFilename(copy.title)
        let dirURL = resolveDirectoryURL(folderID: copy.folderID)
        var filename = oldFilename ?? uniqueFilename(for: newBaseName, in: dirURL)

        // Rename file if title changed
        if let oldFilename, sanitizedFilename(dateCards[idx].title) != newBaseName {
            let newFilename = uniqueFilename(for: newBaseName, in: dirURL, excluding: oldFilename)
            let oldURL = dirURL.appendingPathComponent(oldFilename)
            let newURL = dirURL.appendingPathComponent(newFilename)
            if FileManager.default.fileExists(atPath: oldURL.path) {
                try? FileManager.default.moveItem(at: oldURL, to: newURL)
                filename = newFilename
            }
        }

        guard writeICSFile(for: copy, to: dirURL.appendingPathComponent(filename)) else {
            logger.error("updateDateCard aborted for \(updated.id): .ics write failed")
            return false
        }

        dateCards[idx] = copy
        index[updated.id] = IndexEntry(
            filename: filename, folderID: copy.folderID,
            labelIDs: copy.labelIDs.isEmpty ? nil : copy.labelIDs,
            createdAt: oldEntry?.createdAt ?? copy.createdAt,
            isCompleted: copy.isCompleted, startAt: copy.startAt
        )
        saveIndex()
        sortCards()
        persistEventToDatabase(copy)
        return true
    }

    @discardableResult
    func deleteDateCard(_ id: UUID) -> TrashItem? {
        guard let dateCard = dateCards.first(where: { $0.id == id }) else { return nil }

        let icsFileURL = resolveFileURL(for: id)
        let trashItem = TrashStorage.shared.trashDateCard(
            dateCard,
            dateCardsDir: metadataDirectoryURL,
            icsFileURL: icsFileURL
        )

        dateCards.removeAll { $0.id == id }
        index.removeValue(forKey: id)
        saveIndex()
        deleteEventFromDatabase(id)
        return trashItem
    }

    @discardableResult
    func markCompleted(_ id: UUID, completed: Bool) -> Bool {
        guard let idx = dateCards.firstIndex(where: { $0.id == id }) else { return false }
        dateCards[idx].isCompleted = completed
        dateCards[idx].completedAt = completed ? Date() : nil
        dateCards[idx].updatedAt = Date()
        writeAndUpdateIndex(for: dateCards[idx])
        return true
    }

    @discardableResult
    func assignDateCard(_ id: UUID, toFolder folderID: UUID?) -> Bool {
        guard let idx = dateCards.firstIndex(where: { $0.id == id }) else { return false }
        guard dateCards[idx].folderID != folderID else { return true }

        let dateCard = dateCards[idx]
        guard let entry = index[id] else { return false }

        let oldDirURL = resolveDirectoryURL(folderID: dateCard.folderID)
        let newDirURL = resolveDirectoryURL(folderID: folderID)
        let oldFileURL = oldDirURL.appendingPathComponent(entry.filename)
        let newFilename = uniqueFilename(for: dateCard.title, in: newDirURL)
        let newFileURL = newDirURL.appendingPathComponent(newFilename)

        if oldFileURL != newFileURL {
            let fm = FileManager.default
            try? fm.createDirectory(at: newDirURL, withIntermediateDirectories: true)
            do {
                try fm.moveItem(at: oldFileURL, to: newFileURL)
            } catch {
                logger.error("Failed to move date card file: \(error.localizedDescription)")
                return false
            }
        }

        dateCards[idx].folderID = folderID
        dateCards[idx].updatedAt = Date()

        var updatedEntry = entry
        updatedEntry.folderID = folderID
        updatedEntry.filename = newFilename
        index[id] = updatedEntry
        saveIndex()
        persistEventToDatabase(dateCards[idx])
        return true
    }

    func dateCard(for id: UUID) -> DateCard? {
        dateCards.first { $0.id == id }
    }

    func removeLabelsFromAll(labelID: UUID) {
        var modifiedIDs: Set<UUID> = []
        for i in dateCards.indices where dateCards[i].labelIDs.contains(labelID) {
            dateCards[i].labelIDs.removeAll { $0 == labelID }
            dateCards[i].updatedAt = Date()
            modifiedIDs.insert(dateCards[i].id)
        }
        if !modifiedIDs.isEmpty {
            let modified = dateCards.filter { modifiedIDs.contains($0.id) }
            // Only persist to SQLite for date cards whose on-disk write actually happened.
            var persistable: [DateCard] = []
            for dc in modified {
                if writeICSAndIndex(for: dc) {
                    persistable.append(dc)
                }
            }
            // Persist all affected date cards in a single transaction.
            if !persistable.isEmpty, let db = resolvedDatabase {
                do {
                    try db.withTransaction {
                        for dc in persistable {
                            try self.persistEventToDatabaseInner(db, dateCard: dc)
                        }
                    }
                } catch {
                    logger.error("Failed to batch-persist date cards after label removal: \(error.localizedDescription)")
                }
            }
        }
    }

    func reload() {
        loadIndex()
        scanAndLoad()
    }

    // MARK: - Restore from Trash

    func restoreFromTrash(_ dateCard: DateCard) {
        guard !dateCards.contains(where: { $0.id == dateCard.id }) else { return }

        let dirURL = resolveDirectoryURL(folderID: dateCard.folderID)
        let filename = uniqueFilename(for: dateCard.title, in: dirURL)

        // Try to find the .ics in trash
        let trashDir = metadataDirectoryURL.appendingPathComponent(".trash")
        let fm = FileManager.default
        let trashFiles = (try? fm.contentsOfDirectory(at: trashDir, includingPropertiesForKeys: nil)) ?? []
        var restored = false

        for file in trashFiles where file.pathExtension == fileExtension {
            if let parsed = ICalendarSerializer.parseDateCard((try? String(contentsOf: file, encoding: .utf8)) ?? ""),
               parsed.id == dateCard.id {
                let destURL = dirURL.appendingPathComponent(filename)
                try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
                try? fm.moveItem(at: file, to: destURL)
                restored = true
                break
            }
        }

        if !restored {
            try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
            guard writeICSFile(for: dateCard, to: dirURL.appendingPathComponent(filename)) else {
                logger.error("restoreFromTrash aborted for date card \(dateCard.id): .ics write failed")
                return
            }
        }

        index[dateCard.id] = IndexEntry(
            filename: filename, folderID: dateCard.folderID,
            labelIDs: dateCard.labelIDs.isEmpty ? nil : dateCard.labelIDs,
            createdAt: dateCard.createdAt, isCompleted: dateCard.isCompleted,
            startAt: dateCard.startAt
        )
        saveIndex()

        dateCards.append(dateCard)
        sortCards()
        persistEventToDatabase(dateCard)
    }

    // MARK: - File I/O

    /// Writes a date card to disk as a .ics file. Returns `true` on success,
    /// `false` on failure (error is logged). Callers MUST check the result
    /// before mirroring to SQLite — a failed disk write must not be mirrored.
    @discardableResult
    func writeICSFile(for dateCard: DateCard, to url: URL) -> Bool {
        let icsString = ICalendarSerializer.serializeDateCard(dateCard)
        do {
            try icsString.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            logger.error("Failed to write .ics for date card \(dateCard.id) at \(url.path): \(error.localizedDescription)")
            return false
        }
    }

    /// Convenience: write file and update index for an already-in-memory dateCard.
    /// Only persists to SQLite when the on-disk write actually happened — otherwise
    /// DB and disk would diverge, violating "files are source of truth".
    private func writeAndUpdateIndex(for dateCard: DateCard) {
        guard writeICSAndIndex(for: dateCard) else { return }
        persistEventToDatabase(dateCard)
    }

    /// Write the .ics file and update the in-memory + on-disk index. Does NOT touch SQLite.
    /// Used when callers want to batch SQLite writes separately.
    /// Returns `true` if the write and index update happened, `false` if the index
    /// entry was missing (caller should NOT proceed to persist the DB mirror).
    @discardableResult
    private func writeICSAndIndex(for dateCard: DateCard) -> Bool {
        guard let entry = index[dateCard.id] else {
            logger.warning("writeICSAndIndex skipped for date card \(dateCard.id): missing index entry — neither disk nor DB will be updated")
            return false
        }
        let dirURL = resolveDirectoryURL(folderID: dateCard.folderID)
        guard writeICSFile(for: dateCard, to: dirURL.appendingPathComponent(entry.filename)) else {
            return false
        }
        var updated = entry
        updated.isCompleted = dateCard.isCompleted
        updated.startAt = dateCard.startAt
        updated.labelIDs = dateCard.labelIDs.isEmpty ? nil : dateCard.labelIDs
        index[dateCard.id] = updated
        saveIndex()
        return true
    }

    func resolveFileURL(for dateCardID: UUID) -> URL? {
        guard let entry = index[dateCardID] else { return nil }
        let dirURL = resolveDirectoryURL(folderID: entry.folderID)
        return dirURL.appendingPathComponent(entry.filename)
    }

    private func resolveDirectoryURL(folderID: UUID?) -> URL {
        if let folderID, let vaultFolder = VaultFolderService.shared.folder(for: folderID) {
            return vaultRoot.appendingPathComponent(vaultFolder.relativePath)
        }
        return inboxDirectoryURL
    }

    // MARK: - Index I/O

    // Task 13: JSON index persistence removed. The in-memory `index` dict is
    // rebuilt on launch from SQLite (`loadEventsFromDatabase`) and from .ics
    // scan (`scanAndLoad`). Stubs retained so the mutation call sites stay put.
    private func loadIndex() { /* no-op */ }
    private func saveIndex() { /* no-op */ }

    // MARK: - Scan & Load

    private func scanAndLoad() {
        let fm = FileManager.default
        var loadedCards: [DateCard] = []
        var needsSave = false
        var adoptedCards: [DateCard] = []

        var filenameToUUID: [String: UUID] = [:]
        for (uuid, entry) in index {
            filenameToUUID[entry.filename] = uuid
        }

        // Scan Inbox/Date Cards/ for unfiled .ics files
        if let files = try? fm.contentsOfDirectory(at: inboxDirectoryURL, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == fileExtension {
                let filename = file.lastPathComponent
                if let uuid = filenameToUUID[filename], let entry = index[uuid] {
                    if let dc = parseICSFile(at: file, expectedID: uuid, entry: entry) {
                        loadedCards.append(dc)
                    }
                } else {
                    if let dc = adoptOrphanICS(at: file, folderID: nil) {
                        loadedCards.append(dc)
                        adoptedCards.append(dc)
                        needsSave = true
                    }
                }
            }
        }

        // Scan vault folders for filed .ics VEVENT files
        let loadedIDs = Set(loadedCards.map(\.id))
        for (uuid, entry) in index {
            guard let folderID = entry.folderID else { continue }
            guard !loadedIDs.contains(uuid) else { continue }

            guard let vaultFolder = VaultFolderService.shared.folder(for: folderID) else { continue }
            let filePath = vaultRoot.appendingPathComponent(vaultFolder.relativePath)
                .appendingPathComponent(entry.filename)
            guard fm.fileExists(atPath: filePath.path) else { continue }

            if let dc = parseICSFile(at: filePath, expectedID: uuid, entry: entry) {
                loadedCards.append(dc)
            }
        }

        // Adopt orphan .ics VEVENT files in vault folders
        let allLoadedIDs = Set(loadedCards.map(\.id))
        // Build O(1) lookup for known folder+filename pairs
        let knownFolderFiles: Set<String> = Set(index.values.compactMap { entry in
            guard let fid = entry.folderID else { return nil }
            return "\(fid.uuidString):\(entry.filename)"
        })
        for folder in VaultFolderService.shared.folders {
            let folderDir = vaultRoot.appendingPathComponent(folder.relativePath)
            guard let files = try? fm.contentsOfDirectory(at: folderDir, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.pathExtension == fileExtension {
                let filename = file.lastPathComponent
                if knownFolderFiles.contains("\(folder.id.uuidString):\(filename)") { continue }

                // Only adopt VEVENT files, not VTODO (todos share .ics extension)
                if let dc = adoptOrphanICS(at: file, folderID: folder.id),
                   !allLoadedIDs.contains(dc.id) {
                    loadedCards.append(dc)
                    adoptedCards.append(dc)
                    needsSave = true
                }
            }
        }

        dateCards = loadedCards
        sortCards()
        if needsSave { saveIndex() }
        logger.info("Loaded \(self.dateCards.count) date cards from .ics files")

        // Persist adopted orphan cards to SQLite so future DB-first cold loads find them.
        if !adoptedCards.isEmpty, let db = resolvedDatabase {
            do {
                try db.withTransaction {
                    for dc in adoptedCards {
                        try self.persistEventToDatabaseInner(db, dateCard: dc)
                    }
                }
            } catch {
                logger.error("Failed to persist adopted date cards: \(error.localizedDescription)")
            }
        }
    }

    private func parseICSFile(at url: URL, expectedID: UUID, entry: IndexEntry) -> DateCard? {
        guard let content = try? String(contentsOf: url, encoding: .utf8),
              var dc = ICalendarSerializer.parseDateCard(content) else { return nil }
        guard dc.id == expectedID else { return nil }
        dc.folderID = entry.folderID
        return dc
    }

    private func adoptOrphanICS(at url: URL, folderID: UUID?) -> DateCard? {
        guard let content = try? String(contentsOf: url, encoding: .utf8),
              var dc = ICalendarSerializer.parseDateCard(content) else { return nil }

        dc.folderID = folderID
        let filename = url.lastPathComponent

        index[dc.id] = IndexEntry(
            filename: filename, folderID: folderID,
            labelIDs: dc.labelIDs.isEmpty ? nil : dc.labelIDs,
            createdAt: dc.createdAt, isCompleted: dc.isCompleted,
            startAt: dc.startAt
        )

        logger.info("Adopted orphan .ics VEVENT: \(filename)")
        return dc
    }

    // MARK: - Filename Helpers

    private func sanitizedFilename(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: ":/\\?*\"<>|")
        var sanitized = title.components(separatedBy: invalid).joined(separator: "-")
        while sanitized.hasPrefix(".") { sanitized = String(sanitized.dropFirst()) }
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.count > 200 { sanitized = String(sanitized.prefix(200)) }
        return sanitized.isEmpty ? "Untitled Date Card" : sanitized
    }

    private func uniqueFilename(for title: String, in dirURL: URL, excluding: String? = nil) -> String {
        let baseName = sanitizedFilename(title)
        let candidate = "\(baseName).\(fileExtension)"
        if candidate != excluding && !FileManager.default.fileExists(atPath: dirURL.appendingPathComponent(candidate).path) {
            return candidate
        }
        var counter = 2
        while true {
            let numbered = "\(baseName) (\(counter)).\(fileExtension)"
            if numbered != excluding && !FileManager.default.fileExists(atPath: dirURL.appendingPathComponent(numbered).path) {
                return numbered
            }
            counter += 1
        }
    }

    // MARK: - Sort

    private func sortCards() {
        dateCards.sort { lhs, rhs in
            if lhs.startAt != rhs.startAt {
                return lhs.startAt < rhs.startAt
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    // MARK: - Database Persistence

    /// Link types that may be persisted to `item_links`. Links to non-migrated types
    /// (e.g. `session`, `externalFile`) are silently skipped — their targets don't
    /// exist as rows in `items` and would violate the foreign key.
    private static let linkableEntityTypes: Set<String> = [
        "bookmark", "note", "todo", "dateCard", "contact", "vaultFile"
    ]

    // Internal for testing
    /// SELECT all date cards from the database (items JOIN events), loading labelIDs from
    /// item_labels and linkedEntities from item_links. Also rehydrates `self.index`
    /// so mutation paths can find their entries after a DB-first cold launch.
    func loadEventsFromDatabase(_ db: CiderDatabase) {
        do {
            let stmt = try db.prepare("""
                SELECT i.id, i.title, i.created_at, i.updated_at, i.folder_id, i.relative_path,
                       e.details, e.start_at, e.end_at, e.all_day, e.location, e.amount,
                       e.recurrence_rule, e.is_completed, e.completed_at, e.surfacing_rules
                FROM items i
                JOIN events e ON e.item_id = i.id
                WHERE i.type = 'event';
                """)
            var loaded: [DateCard] = []
            var rebuiltIndex: [UUID: IndexEntry] = [:]
            while try stmt.step() {
                guard let id = DatabaseHelpers.decodeUUID(stmt.string(at: 0)) else { continue }
                let title = stmt.string(at: 1)
                let createdAt = DatabaseHelpers.decodeDate(stmt.double(at: 2))
                let updatedAt = DatabaseHelpers.decodeDate(stmt.double(at: 3))
                let folderID = DatabaseHelpers.decodeUUID(stmt.optionalString(at: 4) ?? "")
                let relativePath = stmt.optionalString(at: 5)
                let details = stmt.string(at: 6)
                let startAt = DatabaseHelpers.decodeDate(stmt.double(at: 7))
                let endAt = stmt.optionalDouble(at: 8).map(DatabaseHelpers.decodeDate)
                let allDay = stmt.bool(at: 9)
                let location = stmt.string(at: 10)
                let amount = stmt.optionalDouble(at: 11)
                let recurrenceJSON = stmt.optionalString(at: 12)
                let isCompleted = stmt.bool(at: 13)
                let completedAt = stmt.optionalDouble(at: 14).map(DatabaseHelpers.decodeDate)
                let surfacingRulesJSON = stmt.optionalString(at: 15)

                let recurrenceRule: DateCardRecurrenceRule? =
                    DatabaseHelpers.decodeJSON(DateCardRecurrenceRule.self, from: recurrenceJSON)
                let rules: [SurfacingRule] =
                    DatabaseHelpers.decodeJSON([SurfacingRule].self, from: surfacingRulesJSON) ?? []

                let labelIDs = (try? loadLabelIDs(db, itemID: id)) ?? []
                let linkedEntities = (try? loadLinkedEntities(db, sourceID: id)) ?? []

                let dateCard = DateCard(
                    id: id,
                    title: title,
                    details: details,
                    startAt: startAt,
                    endAt: endAt,
                    allDay: allDay,
                    location: location,
                    amount: amount,
                    recurrenceRule: recurrenceRule,
                    isCompleted: isCompleted,
                    completedAt: completedAt,
                    labelIDs: labelIDs,
                    linkedEntities: linkedEntities,
                    folderID: folderID,
                    rules: rules,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
                loaded.append(dateCard)

                // Rehydrate the in-memory index so mutation paths work after cold load.
                // Derive the filename from `items.relative_path` (persisted on write)
                // so collision suffixes like "Title (2).ics" are recovered exactly.
                // Fall back to a sanitized guess only if the column is missing (pre-fix
                // rows), which is still better than corrupting later writes.
                let filename: String = {
                    if let rel = relativePath, !rel.isEmpty {
                        let last = (rel as NSString).lastPathComponent
                        if !last.isEmpty { return last }
                    }
                    return "\(sanitizedFilename(title)).\(fileExtension)"
                }()
                rebuiltIndex[id] = IndexEntry(
                    filename: filename,
                    folderID: folderID,
                    labelIDs: labelIDs.isEmpty ? nil : labelIDs,
                    createdAt: createdAt,
                    isCompleted: isCompleted,
                    startAt: startAt
                )
            }
            dateCards = loaded
            index = rebuiltIndex
            sortCards()
            logger.info("Loaded \(loaded.count) date cards from database")
        } catch {
            logger.error("Failed to load date cards from database: \(error.localizedDescription)")
            dateCards = []
            index = [:]
        }
    }

    /// Load label IDs from the item_labels join table for a given item.
    private func loadLabelIDs(_ db: CiderDatabase, itemID: UUID) throws -> [UUID] {
        let stmt = try db.prepare("SELECT label_id FROM item_labels WHERE item_id = ?;")
        stmt.bind(DatabaseHelpers.encode(itemID), at: 1)
        var ids: [UUID] = []
        while try stmt.step() {
            if let id = DatabaseHelpers.decodeUUID(stmt.string(at: 0)) {
                ids.append(id)
            }
        }
        return ids
    }

    /// Load linked entities from the item_links join table (link_type = 'linked').
    /// Infers the entity type from the target item's `items.type` column.
    /// Note: `items.type == 'event'` maps to `LibraryEntityType.dateCard`.
    private func loadLinkedEntities(_ db: CiderDatabase, sourceID: UUID) throws -> [LibraryEntityRef] {
        let stmt = try db.prepare("""
            SELECT l.target_id, i.type
            FROM item_links l
            JOIN items i ON i.id = l.target_id
            WHERE l.source_id = ? AND l.link_type = 'linked';
            """)
        stmt.bind(DatabaseHelpers.encode(sourceID), at: 1)
        var refs: [LibraryEntityRef] = []
        while try stmt.step() {
            guard let targetID = DatabaseHelpers.decodeUUID(stmt.string(at: 0)) else { continue }
            let rawType = stmt.string(at: 1)
            // items.type uses 'event' but LibraryEntityType uses 'dateCard'.
            let resolvedRaw = (rawType == "event") ? "dateCard" : rawType
            guard let type = LibraryEntityType(rawValue: resolvedRaw) else { continue }
            refs.append(LibraryEntityRef(type: type, entityID: targetID))
        }
        return refs
    }

    // Internal for testing
    /// Persist a single date card to the database (items + events + item_labels + item_links)
    /// using the resolved (shared or explicit) database inside a transaction.
    func persistEventToDatabase(_ dateCard: DateCard) {
        guard let db = resolvedDatabase else {
            logger.warning("No database available, skipping SQLite persist for date card \(dateCard.id)")
            return
        }
        persistEventToDatabase(db, dateCard: dateCard)
    }

    // Internal for testing
    /// Persist a single date card to the given database inside its own transaction.
    func persistEventToDatabase(_ db: CiderDatabase, dateCard: DateCard) {
        do {
            try db.withTransaction {
                try persistEventToDatabaseInner(db, dateCard: dateCard)
            }
        } catch {
            logger.error("Failed to persist date card \(dateCard.id) to database: \(error.localizedDescription)")
        }
    }

    /// Compute the vault-relative path for a date card, preferring the real filename tracked
    /// in the in-memory index. Falls back to the sanitized title when the index hasn't
    /// been populated yet (e.g. initial one-time JSON migration inside `init`).
    private func relativePathForPersistence(_ dateCard: DateCard) -> String? {
        let filename: String
        if let entryFilename = index[dateCard.id]?.filename {
            filename = entryFilename
        } else {
            filename = "\(sanitizedFilename(dateCard.title)).\(fileExtension)"
        }

        if let folderID = dateCard.folderID,
           let vaultFolder = VaultFolderService.shared.folder(for: folderID) {
            return "\(vaultFolder.relativePath)/\(filename)"
        }
        // Inbox date cards live under `Inbox/Date Cards/{filename}`.
        return "Inbox/Date Cards/\(filename)"
    }

    /// Core persist logic for a single date card — must be called inside a transaction.
    private func persistEventToDatabaseInner(_ db: CiderDatabase, dateCard: DateCard) throws {
        // Scrub folder_id against target DB to defuse FK failures.
        let folderIDText = try resolveSafeFolderID(db, folderID: dateCard.folderID)

        // 1. UPSERT into items.
        // `relative_path` stores the vault-relative .ics path so that DB-first cold
        // loads can recover the EXACT on-disk filename (including collision suffixes
        // like "Title (2).ics"). Guessing from the title would orphan real files.
        let itemStmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, 'event', ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                updated_at = excluded.updated_at,
                folder_id = excluded.folder_id,
                relative_path = excluded.relative_path;
            """)
        let itemID = DatabaseHelpers.encode(dateCard.id)
        let relativePath: String? = relativePathForPersistence(dateCard)
        itemStmt.bind(itemID, at: 1)
            .bind(dateCard.title, at: 2)
            .bind(DatabaseHelpers.encode(dateCard.createdAt), at: 3)
            .bind(DatabaseHelpers.encode(dateCard.updatedAt), at: 4)
            .bind(folderIDText, at: 5)
            .bind(relativePath, at: 6)
        try itemStmt.step()

        // 2. UPSERT into events
        let eventStmt = try db.prepare("""
            INSERT INTO events (
                item_id, details, start_at, end_at, all_day, location, amount,
                recurrence_rule, is_completed, completed_at, surfacing_rules
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(item_id) DO UPDATE SET
                details = excluded.details,
                start_at = excluded.start_at,
                end_at = excluded.end_at,
                all_day = excluded.all_day,
                location = excluded.location,
                amount = excluded.amount,
                recurrence_rule = excluded.recurrence_rule,
                is_completed = excluded.is_completed,
                completed_at = excluded.completed_at,
                surfacing_rules = excluded.surfacing_rules;
            """)
        let recurrenceJSON: String? = dateCard.recurrenceRule.flatMap { DatabaseHelpers.encodeJSON($0) }
        let surfacingRulesJSON: String? = dateCard.rules.isEmpty
            ? nil
            : DatabaseHelpers.encodeJSON(dateCard.rules)
        eventStmt.bind(itemID, at: 1)
            .bind(dateCard.details, at: 2)
            .bind(DatabaseHelpers.encode(dateCard.startAt), at: 3)
            .bind(dateCard.endAt.map(DatabaseHelpers.encode), at: 4)
            .bind(dateCard.allDay ? Int64(1) : Int64(0), at: 5)
            .bind(dateCard.location, at: 6)
            .bind(dateCard.amount, at: 7)
            .bind(recurrenceJSON, at: 8)
            .bind(dateCard.isCompleted ? Int64(1) : Int64(0), at: 9)
            .bind(dateCard.completedAt.map(DatabaseHelpers.encode), at: 10)
            .bind(surfacingRulesJSON, at: 11)
        try eventStmt.step()

        // 3. Sync item_labels: delete all, re-insert current.
        let delLabels = try db.prepare("DELETE FROM item_labels WHERE item_id = ?;")
        delLabels.bind(itemID, at: 1)
        try delLabels.step()

        if !dateCard.labelIDs.isEmpty {
            let insLabel = try db.prepare("INSERT OR IGNORE INTO item_labels (item_id, label_id) VALUES (?, ?);")
            for labelID in dateCard.labelIDs {
                insLabel.reset()
                insLabel.bind(itemID, at: 1)
                    .bind(DatabaseHelpers.encode(labelID), at: 2)
                try insLabel.step()
            }
        }

        // 4. Sync item_links: delete all 'linked' rows from this source, re-insert current.
        // Non-migrated types and links whose target row doesn't exist are silently dropped.
        //
        // KNOWN LIMITATION — first-run JSON→SQLite migration:
        // When DateCardStorage runs its one-time migration loop in `init`, other
        // services (bookmarks, notes, contacts, etc.) may not have migrated yet, so
        // their target rows in `items` don't exist. The `WHERE EXISTS` guard below
        // therefore silently drops any cross-type links for those not-yet-migrated
        // targets. This is acceptable because:
        //   1. `dateCard.linkedEntities` remains authoritative in memory and inside
        //      the .ics file — nothing is lost on disk.
        //   2. Any subsequent user edit to the date card re-runs this persist path,
        //      by which point all services have finished migrating and the targets
        //      do exist — so the links will be correctly re-persisted.
        //   3. Task 12 (Startup Reconciliation) will add a post-migration pass that
        //      backfills any links dropped during the first run.
        let delLinks = try db.prepare("DELETE FROM item_links WHERE source_id = ? AND link_type = 'linked';")
        delLinks.bind(itemID, at: 1)
        try delLinks.step()

        let now = DatabaseHelpers.encode(Date())
        let insLink = try db.prepare("""
            INSERT OR IGNORE INTO item_links (source_id, target_id, link_type, created_at)
            SELECT ?, ?, 'linked', ?
            WHERE EXISTS (SELECT 1 FROM items WHERE id = ?);
            """)
        for ref in dateCard.linkedEntities where Self.linkableEntityTypes.contains(ref.type.rawValue) {
            let target = DatabaseHelpers.encode(ref.entityID)
            insLink.reset()
            insLink.bind(itemID, at: 1)
                .bind(target, at: 2)
                .bind(now, at: 3)
                .bind(target, at: 4)
            try insLink.step()
        }
    }

    /// Delete a date card from the database by ID. CASCADE handles detail + join tables.
    func deleteEventFromDatabase(_ dateCardID: UUID) {
        guard let db = resolvedDatabase else {
            logger.warning("No database available, skipping SQLite delete for date card \(dateCardID)")
            return
        }
        deleteEventFromDatabase(db, dateCardID: dateCardID)
    }

    // Internal for testing
    /// DELETE a date card from the given database by ID.
    func deleteEventFromDatabase(_ db: CiderDatabase, dateCardID: UUID) {
        do {
            let stmt = try db.prepare("DELETE FROM items WHERE id = ?;")
            stmt.bind(DatabaseHelpers.encode(dateCardID), at: 1)
            try stmt.step()
        } catch {
            logger.error("Failed to delete date card \(dateCardID) from database: \(error.localizedDescription)")
        }
    }
}
