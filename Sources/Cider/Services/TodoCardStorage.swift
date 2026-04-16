import Combine
import Foundation
import os

/// Manages todos as individual .ics (VTODO) files on disk, mirrored to SQLite.
///
/// File layout:
/// - Unfiled todos: `Inbox/Todos/{title}.ics`
/// - Filed todos: `{UserFolder}/{title}.ics`
/// - Trash: `.cider/todos/.trash/`
@MainActor
final class TodoCardStorage: ObservableObject {
    static let shared = TodoCardStorage()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Cider",
        category: "TodoCardStorage"
    )

    @Published private(set) var todoCards: [TodoCard] = []

    private let fileExtension = "ics"

    /// Per-todo metadata persisted in the index file.
    private struct IndexEntry: Codable, Equatable {
        var filename: String
        var folderID: UUID?
        var labelIDs: [UUID]?
        var createdAt: Date?
        var isCompleted: Bool?
        var dueDate: Date?
        var priority: TodoPriority?
    }

    private var index: [UUID: IndexEntry] = [:]
    private var inboxWatcher: FSEventsWatcher?
    private var vaultFilesystemObserver: NSObjectProtocol?
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
        StoragePaths.cachedDirectoryURL(for: .todos)
    }

    private var inboxDirectoryURL: URL {
        StoragePaths.cachedInboxSubdirectoryURL(for: .todos)
    }

    private var vaultRoot: URL {
        StoragePaths.cachedVaultDirectoryURL
    }

    private init() {
        ensureDirectories()
        loadIndex()

        // Try SQLite first (mirrors NotesStorage/VaultBookmarkService pattern).
        if let db = resolvedDatabase {
            loadTodosFromDatabase(db)
            if !todoCards.isEmpty {
                startWatching()
                startVaultFilesystemObservation()
                return
            }
        }

        scanAndLoad()
        startWatching()
        startVaultFilesystemObservation()

        // One-time migration: persist JSON-sourced todos to SQLite.
        // `persistTodoToDatabaseInner` scrubs dangling folder_id references
        // at the lowest level so a single stale reference can't abort the
        // whole migration.
        if !todoCards.isEmpty, let db = resolvedDatabase {
            logger.info("Migrating \(self.todoCards.count) todos from .ics/JSON to SQLite")
            do {
                try db.withTransaction {
                    for todo in self.todoCards {
                        try self.persistTodoToDatabaseInner(db, todo: todo)
                    }
                }
            } catch {
                logger.error("Failed to migrate todos to SQLite: \(error.localizedDescription)")
            }
        }
    }

    /// Testing-only initializer with an explicit database.
    /// Does NOT scan the file system — tests call loadTodosFromDatabase() directly
    /// or use the persist/delete helpers.
    init(database: CiderDatabase) {
        self.database = database
    }

    /// Testing-only: seed the in-memory index so that `persistTodoToDatabase`
    /// picks up a specific filename (used to verify that uniquified filenames
    /// like "Title (2).ics" round-trip through items.relative_path).
    func _setIndexEntryForTesting(
        todoID: UUID,
        filename: String,
        folderID: UUID? = nil
    ) {
        index[todoID] = IndexEntry(
            filename: filename,
            folderID: folderID,
            labelIDs: nil,
            createdAt: Date(),
            isCompleted: false,
            dueDate: nil,
            priority: nil
        )
    }

    /// Testing-only: read the filename currently tracked in the index for a todo.
    func _indexFilenameForTesting(todoID: UUID) -> String? {
        index[todoID]?.filename
    }

    /// Testing-only: parse an orphan .ics file, add it to the in-memory index
    /// and `todoCards`, and persist it to SQLite — mirrors the production
    /// "adopted during scanAndLoad" code path in a form tests can invoke
    /// without depending on the real vault filesystem.
    @discardableResult
    func _adoptOrphanForTesting(at url: URL, folderID: UUID? = nil) -> TodoCard? {
        guard let todo = adoptOrphanICS(at: url, folderID: folderID) else { return nil }
        todoCards.append(todo)
        if let db = resolvedDatabase {
            do {
                try db.withTransaction {
                    try self.persistTodoToDatabaseInner(db, todo: todo)
                }
            } catch {
                logger.error("Failed to persist adopted todo (test): \(error.localizedDescription)")
            }
        }
        return todo
    }

    /// Watches the Inbox/Todos directory for new .ics files dropped externally (e.g. via iMessage agent).
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

    /// Rescans for new or changed .ics files without full reinitialization.
    func rescan() {
        guard !isScanning else { pendingRescan = true; return }
        isScanning = true
        let previousIDs = Set(todoCards.map(\.id))
        defer {
            isScanning = false
            if pendingRescan {
                pendingRescan = false
                rescan()
            }
        }
        scanAndLoad()
        syncScanToDatabase(previousIDs: previousIDs)
    }

    private func ensureDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: metadataDirectoryURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: inboxDirectoryURL, withIntermediateDirectories: true)
    }

    private func startVaultFilesystemObservation() {
        vaultFilesystemObserver = NotificationCenter.default.addObserver(
            forName: .vaultFilesystemDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rescan()
            }
        }
    }

    // MARK: - CRUD

    @discardableResult
    func createTodoCard(title: String, dueDate: Date? = nil, priority: TodoPriority? = nil) -> TodoCard {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmed.isEmpty ? "Untitled Todo" : trimmed
        let todoCard = TodoCard(title: finalTitle, dueDate: dueDate, priority: priority)

        let filename = uniqueFilename(for: finalTitle, in: inboxDirectoryURL)
        guard writeICSFile(for: todoCard, to: inboxDirectoryURL.appendingPathComponent(filename)) else {
            logger.error("createTodoCard aborted for \(todoCard.id): initial .ics write failed")
            return todoCard
        }

        index[todoCard.id] = IndexEntry(
            filename: filename, folderID: nil, labelIDs: nil,
            createdAt: todoCard.createdAt, isCompleted: false,
            dueDate: dueDate, priority: priority
        )
        saveIndex()

        todoCards.append(todoCard)
        sortCards()
        persistTodoToDatabase(todoCard)
        return todoCard
    }

    @discardableResult
    func addTodoCard(_ card: TodoCard) -> TodoCard {
        let dirURL = resolveDirectoryURL(folderID: card.folderID)
        let filename = uniqueFilename(for: card.title, in: dirURL)
        guard writeICSFile(for: card, to: dirURL.appendingPathComponent(filename)) else {
            logger.error("addTodoCard aborted for \(card.id): .ics write failed")
            return card
        }

        index[card.id] = IndexEntry(
            filename: filename, folderID: card.folderID,
            labelIDs: card.labelIDs.isEmpty ? nil : card.labelIDs,
            createdAt: card.createdAt, isCompleted: card.isCompleted,
            dueDate: card.dueDate, priority: card.priority
        )
        saveIndex()

        todoCards.append(card)
        sortCards()
        persistTodoToDatabase(card)
        return card
    }

    @discardableResult
    func updateTodoCard(_ updated: TodoCard) -> Bool {
        guard let idx = todoCards.firstIndex(where: { $0.id == updated.id }) else { return false }
        var copy = updated
        copy.updatedAt = Date()

        let oldEntry = index[updated.id]
        let oldFilename = oldEntry?.filename
        let newBaseName = sanitizedFilename(copy.title)
        let dirURL = resolveDirectoryURL(folderID: copy.folderID)
        var filename = oldFilename ?? uniqueFilename(for: newBaseName, in: dirURL)

        // Rename file if title changed
        if let oldFilename, sanitizedFilename(todoCards[idx].title) != newBaseName {
            let newFilename = uniqueFilename(for: newBaseName, in: dirURL, excluding: oldFilename)
            let oldURL = dirURL.appendingPathComponent(oldFilename)
            let newURL = dirURL.appendingPathComponent(newFilename)
            if FileManager.default.fileExists(atPath: oldURL.path) {
                try? FileManager.default.moveItem(at: oldURL, to: newURL)
                filename = newFilename
            }
        }

        guard writeICSFile(for: copy, to: dirURL.appendingPathComponent(filename)) else {
            logger.error("updateTodoCard aborted for \(updated.id): .ics write failed")
            return false
        }

        todoCards[idx] = copy
        index[updated.id] = IndexEntry(
            filename: filename, folderID: copy.folderID,
            labelIDs: copy.labelIDs.isEmpty ? nil : copy.labelIDs,
            createdAt: oldEntry?.createdAt ?? copy.createdAt,
            isCompleted: copy.isCompleted, dueDate: copy.dueDate,
            priority: copy.priority
        )
        saveIndex()
        sortCards()
        persistTodoToDatabase(copy)
        return true
    }

    @discardableResult
    func deleteTodoCard(_ id: UUID) -> TrashItem? {
        guard let todoCard = todoCards.first(where: { $0.id == id }) else { return nil }

        let icsFileURL = resolveFileURL(for: id)
        let trashItem = TrashStorage.shared.trashTodoCard(
            todoCard,
            todoCardsDir: metadataDirectoryURL,
            icsFileURL: icsFileURL
        )

        todoCards.removeAll { $0.id == id }
        index.removeValue(forKey: id)
        saveIndex()
        deleteTodoFromDatabase(id)
        return trashItem
    }

    @discardableResult
    func markCompleted(_ id: UUID, completed: Bool) -> Bool {
        guard let idx = todoCards.firstIndex(where: { $0.id == id }) else { return false }
        todoCards[idx].isCompleted = completed
        todoCards[idx].completedAt = completed ? Date() : nil
        todoCards[idx].updatedAt = Date()
        writeAndUpdateIndex(for: todoCards[idx])
        return true
    }

    @discardableResult
    func toggleChecklistItem(_ todoID: UUID, checklistItemID: UUID) -> Bool {
        guard let todoIdx = todoCards.firstIndex(where: { $0.id == todoID }),
              let itemIdx = todoCards[todoIdx].checklist.firstIndex(where: { $0.id == checklistItemID }) else {
            return false
        }
        let wasCompleted = todoCards[todoIdx].checklist[itemIdx].isCompleted
        let itemTitle = todoCards[todoIdx].checklist[itemIdx].title
        todoCards[todoIdx].checklist[itemIdx].isCompleted = !wasCompleted
        todoCards[todoIdx].checklist[itemIdx].completedAt = wasCompleted ? nil : Date()
        let dateStr = Date().formatted(.dateTime.month(.abbreviated).day())
        let logEntry = wasCompleted ? "↩ \(itemTitle) unmarked — \(dateStr)" : "✓ \(itemTitle) completed — \(dateStr)"
        appendToNotes(todoIdx: todoIdx, entry: logEntry)
        todoCards[todoIdx].updatedAt = Date()
        writeAndUpdateIndex(for: todoCards[todoIdx])
        return true
    }

    @discardableResult
    func toggleSubtask(_ todoID: UUID, checklistItemID: UUID, subtaskID: UUID) -> Bool {
        guard let todoIdx = todoCards.firstIndex(where: { $0.id == todoID }),
              let itemIdx = todoCards[todoIdx].checklist.firstIndex(where: { $0.id == checklistItemID }),
              let subIdx = todoCards[todoIdx].checklist[itemIdx].subtasks.firstIndex(where: { $0.id == subtaskID }) else {
            return false
        }
        let wasCompleted = todoCards[todoIdx].checklist[itemIdx].subtasks[subIdx].isCompleted
        todoCards[todoIdx].checklist[itemIdx].subtasks[subIdx].isCompleted = !wasCompleted
        todoCards[todoIdx].checklist[itemIdx].subtasks[subIdx].completedAt = wasCompleted ? nil : Date()
        todoCards[todoIdx].updatedAt = Date()
        writeAndUpdateIndex(for: todoCards[todoIdx])
        return true
    }

    private func appendToNotes(todoIdx: Int, entry: String) {
        if todoCards[todoIdx].notes.isEmpty {
            todoCards[todoIdx].notes = entry
        } else {
            todoCards[todoIdx].notes += "\n" + entry
        }
    }

    @discardableResult
    func assignTodoCard(_ id: UUID, toFolder folderID: UUID?) -> Bool {
        guard let idx = todoCards.firstIndex(where: { $0.id == id }) else { return false }
        guard todoCards[idx].folderID != folderID else { return true }

        let todoCard = todoCards[idx]
        guard let entry = index[id] else { return false }

        let oldDirURL = resolveDirectoryURL(folderID: todoCard.folderID)
        let newDirURL = resolveDirectoryURL(folderID: folderID)
        let oldFileURL = oldDirURL.appendingPathComponent(entry.filename)
        let newFilename = uniqueFilename(for: todoCard.title, in: newDirURL)
        let newFileURL = newDirURL.appendingPathComponent(newFilename)

        if oldFileURL != newFileURL {
            let fm = FileManager.default
            try? fm.createDirectory(at: newDirURL, withIntermediateDirectories: true)
            do {
                try fm.moveItem(at: oldFileURL, to: newFileURL)
            } catch {
                logger.error("Failed to move todo file: \(error.localizedDescription)")
                return false
            }
        }

        todoCards[idx].folderID = folderID
        todoCards[idx].updatedAt = Date()

        var updatedEntry = entry
        updatedEntry.folderID = folderID
        updatedEntry.filename = newFilename
        index[id] = updatedEntry
        saveIndex()
        persistTodoToDatabase(todoCards[idx])
        return true
    }

    func todoCard(for id: UUID) -> TodoCard? {
        todoCards.first { $0.id == id }
    }

    func removeLabelsFromAll(labelID: UUID) {
        var modifiedIDs: Set<UUID> = []
        for i in todoCards.indices where todoCards[i].labelIDs.contains(labelID) {
            todoCards[i].labelIDs.removeAll { $0 == labelID }
            todoCards[i].updatedAt = Date()
            modifiedIDs.insert(todoCards[i].id)
        }
        if !modifiedIDs.isEmpty {
            let modified = todoCards.filter { modifiedIDs.contains($0.id) }
            // Only persist to SQLite for todos whose on-disk write actually happened.
            var persistable: [TodoCard] = []
            for todoCard in modified {
                if writeICSAndIndex(for: todoCard) {
                    persistable.append(todoCard)
                }
            }
            // Persist all affected todos in a single transaction.
            if !persistable.isEmpty, let db = resolvedDatabase {
                do {
                    try db.withTransaction {
                        for todoCard in persistable {
                            try self.persistTodoToDatabaseInner(db, todo: todoCard)
                        }
                    }
                } catch {
                    logger.error("Failed to batch-persist todos after label removal: \(error.localizedDescription)")
                }
            }
        }
    }

    func reload() {
        loadIndex()
        scanAndLoad()
    }

    // MARK: - Restore from Trash

    func restoreFromTrash(_ todoCard: TodoCard) {
        guard !todoCards.contains(where: { $0.id == todoCard.id }) else { return }

        let dirURL = resolveDirectoryURL(folderID: todoCard.folderID)
        let trashDir = metadataDirectoryURL.appendingPathComponent(".trash")
        let fm = FileManager.default
        let trashFiles = (try? fm.contentsOfDirectory(at: trashDir, includingPropertiesForKeys: nil)) ?? []
        var filename = uniqueFilename(for: todoCard.title, in: dirURL)
        var restored = false

        if let liveFiles = try? fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil) {
            for file in liveFiles where file.pathExtension == fileExtension {
                if let parsed = ICalendarSerializer.parseTodo((try? String(contentsOf: file, encoding: .utf8)) ?? ""),
                   parsed.id == todoCard.id {
                    filename = file.lastPathComponent
                    restored = true
                    break
                }
            }
        }

        for file in trashFiles where file.pathExtension == fileExtension {
            guard !restored else { break }
            if let parsed = ICalendarSerializer.parseTodo((try? String(contentsOf: file, encoding: .utf8)) ?? ""),
               parsed.id == todoCard.id {
                let destURL = dirURL.appendingPathComponent(filename)
                try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
                try? fm.moveItem(at: file, to: destURL)
                restored = true
                break
            }
        }

        if !restored {
            try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
            guard writeICSFile(for: todoCard, to: dirURL.appendingPathComponent(filename)) else {
                logger.error("restoreFromTrash aborted for todo \(todoCard.id): .ics write failed")
                return
            }
        }

        index[todoCard.id] = IndexEntry(
            filename: filename, folderID: todoCard.folderID,
            labelIDs: todoCard.labelIDs.isEmpty ? nil : todoCard.labelIDs,
            createdAt: todoCard.createdAt, isCompleted: todoCard.isCompleted,
            dueDate: todoCard.dueDate, priority: todoCard.priority
        )
        saveIndex()

        todoCards.append(todoCard)
        sortCards()
        persistTodoToDatabase(todoCard)
    }

    // MARK: - File I/O

    /// Writes a todo to disk as a .ics file. Returns `true` on success,
    /// `false` on failure (error is logged). Callers MUST check the result
    /// before mirroring to SQLite — a failed disk write must not be mirrored.
    @discardableResult
    func writeICSFile(for todoCard: TodoCard, to url: URL) -> Bool {
        let icsString = ICalendarSerializer.serializeTodo(todoCard)
        do {
            try icsString.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            logger.error("Failed to write .ics for todo \(todoCard.id) at \(url.path): \(error.localizedDescription)")
            return false
        }
    }

    /// Convenience: write file and update index for an already-in-memory todoCard.
    /// Only persists to SQLite when the on-disk write actually happened — otherwise
    /// DB and disk would diverge, violating "files are source of truth".
    private func writeAndUpdateIndex(for todoCard: TodoCard) {
        guard writeICSAndIndex(for: todoCard) else { return }
        persistTodoToDatabase(todoCard)
    }

    /// Write the .ics file and update the in-memory + on-disk index. Does NOT touch SQLite.
    /// Used when callers want to batch SQLite writes separately.
    /// Returns `true` if the write and index update happened, `false` if the index
    /// entry was missing (caller should NOT proceed to persist the DB mirror).
    @discardableResult
    private func writeICSAndIndex(for todoCard: TodoCard) -> Bool {
        guard let entry = index[todoCard.id] else {
            logger.warning("writeICSAndIndex skipped for todo \(todoCard.id): missing index entry — neither disk nor DB will be updated")
            return false
        }
        let dirURL = resolveDirectoryURL(folderID: todoCard.folderID)
        guard writeICSFile(for: todoCard, to: dirURL.appendingPathComponent(entry.filename)) else {
            return false
        }
        var updated = entry
        updated.isCompleted = todoCard.isCompleted
        updated.dueDate = todoCard.dueDate
        updated.priority = todoCard.priority
        updated.labelIDs = todoCard.labelIDs.isEmpty ? nil : todoCard.labelIDs
        index[todoCard.id] = updated
        saveIndex()
        return true
    }

    func resolveFileURL(for todoID: UUID) -> URL? {
        guard let entry = index[todoID] else { return nil }
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
    // rebuilt on launch from SQLite (`loadTodosFromDatabase`) and from .ics
    // scan (`scanAndLoad`). The stubs below are retained only so the numerous
    // mutation call sites remain unchanged.
    private func loadIndex() { /* no-op */ }
    private func saveIndex() { /* no-op */ }

    // MARK: - Scan & Load

    private func scanAndLoad() {
        let fm = FileManager.default
        var loadedCards: [TodoCard] = []
        var needsSave = false
        var adoptedCards: [TodoCard] = []

        var filenameToUUID: [String: UUID] = [:]
        for (uuid, entry) in index {
            filenameToUUID[entry.filename] = uuid
        }

        // Scan Inbox/Todos/ for unfiled .ics files
        if let files = try? fm.contentsOfDirectory(at: inboxDirectoryURL, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == fileExtension {
                let filename = file.lastPathComponent
                if let uuid = filenameToUUID[filename], let entry = index[uuid] {
                    if let todo = parseICSFile(at: file, expectedID: uuid, entry: entry) {
                        loadedCards.append(todo)
                    }
                } else {
                    if let todo = adoptOrphanICS(at: file, folderID: nil) {
                        loadedCards.append(todo)
                        adoptedCards.append(todo)
                        needsSave = true
                    }
                }
            }
        }

        // Scan vault folders for filed .ics VTODO files
        let loadedIDs = Set(loadedCards.map(\.id))
        for (uuid, entry) in index {
            guard let folderID = entry.folderID else { continue }
            guard !loadedIDs.contains(uuid) else { continue }

            guard let vaultFolder = VaultFolderService.shared.folder(for: folderID) else { continue }
            let filePath = vaultRoot.appendingPathComponent(vaultFolder.relativePath)
                .appendingPathComponent(entry.filename)
            guard fm.fileExists(atPath: filePath.path) else { continue }

            if let todo = parseICSFile(at: filePath, expectedID: uuid, entry: entry) {
                loadedCards.append(todo)
            }
        }

        // Adopt orphan .ics files in vault folders
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

                // Only adopt VTODO files, not VEVENT (date cards share .ics extension)
                if let todo = adoptOrphanICS(at: file, folderID: folder.id),
                   !allLoadedIDs.contains(todo.id) {
                    loadedCards.append(todo)
                    adoptedCards.append(todo)
                    needsSave = true
                }
            }
        }

        todoCards = loadedCards
        sortCards()
        if needsSave { saveIndex() }
        logger.info("Loaded \(self.todoCards.count) todos from .ics files")

        // Persist adopted orphan todos to SQLite so future DB-first cold loads find them.
        if !adoptedCards.isEmpty, let db = resolvedDatabase {
            do {
                try db.withTransaction {
                    for todo in adoptedCards {
                        try self.persistTodoToDatabaseInner(db, todo: todo)
                    }
                }
            } catch {
                logger.error("Failed to persist adopted todos: \(error.localizedDescription)")
            }
        }
    }

    private func syncScanToDatabase(previousIDs: Set<UUID>) {
        guard let db = resolvedDatabase else { return }
        let currentIDs = Set(todoCards.map(\.id))
        let removedIDs = previousIDs.subtracting(currentIDs)
        do {
            try db.withTransaction {
                for todo in self.todoCards {
                    try self.persistTodoToDatabaseInner(db, todo: todo)
                }
                for removedID in removedIDs {
                    let stmt = try db.prepare("DELETE FROM items WHERE id = ?;")
                    stmt.bind(DatabaseHelpers.encode(removedID), at: 1)
                    try stmt.step()
                }
            }
            logger.info("Rescan synced \(self.todoCards.count) todos to SQLite (removed \(removedIDs.count))")
        } catch {
            logger.error("Failed to sync todo rescan to SQLite: \(error.localizedDescription)")
        }
    }

    private func parseICSFile(at url: URL, expectedID: UUID, entry: IndexEntry) -> TodoCard? {
        guard let content = try? String(contentsOf: url, encoding: .utf8),
              var todo = ICalendarSerializer.parseTodo(content) else { return nil }
        guard todo.id == expectedID else { return nil }
        todo.folderID = entry.folderID
        return todo
    }

    private func adoptOrphanICS(at url: URL, folderID: UUID?) -> TodoCard? {
        guard let content = try? String(contentsOf: url, encoding: .utf8),
              var todo = ICalendarSerializer.parseTodo(content) else { return nil }

        todo.folderID = folderID
        let filename = url.lastPathComponent

        index[todo.id] = IndexEntry(
            filename: filename, folderID: folderID,
            labelIDs: todo.labelIDs.isEmpty ? nil : todo.labelIDs,
            createdAt: todo.createdAt, isCompleted: todo.isCompleted,
            dueDate: todo.dueDate, priority: todo.priority
        )

        logger.info("Adopted orphan .ics VTODO: \(filename)")
        return todo
    }

    // MARK: - Filename Helpers

    private func sanitizedFilename(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: ":/\\?*\"<>|")
        var sanitized = title.components(separatedBy: invalid).joined(separator: "-")
        while sanitized.hasPrefix(".") { sanitized = String(sanitized.dropFirst()) }
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.count > 200 { sanitized = String(sanitized.prefix(200)) }
        return sanitized.isEmpty ? "Untitled Todo" : sanitized
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
        todoCards.sort { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted
            }
            switch (lhs.dueDate, rhs.dueDate) {
            case (let l?, let r?):
                if l != r { return l < r }
            case (nil, .some):
                return false
            case (.some, nil):
                return true
            case (nil, nil):
                break
            }
            return lhs.createdAt > rhs.createdAt
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
    /// SELECT all todos from the database (items JOIN todos), loading labelIDs from
    /// item_labels and linkedEntities from item_links. Also rehydrates `self.index`
    /// so mutation paths can find their entries after a DB-first cold launch.
    func loadTodosFromDatabase(_ db: CiderDatabase) {
        do {
        let stmt = try db.prepare("""
                SELECT i.id, i.title, i.created_at, i.updated_at, i.folder_id, i.relative_path,
                       t.details, t.due_date, t.priority, t.is_completed, t.completed_at,
                       t.notes, t.checklist, t.surfacing_rules
                FROM items i
                JOIN todos t ON t.item_id = i.id
                WHERE i.type = 'todo';
                """)
            var loaded: [TodoCard] = []
            var rebuiltIndex: [UUID: IndexEntry] = [:]
            while try stmt.step() {
                guard let id = DatabaseHelpers.decodeUUID(stmt.string(at: 0)) else { continue }
                let title = stmt.string(at: 1)
                let createdAt = DatabaseHelpers.decodeDate(stmt.double(at: 2))
                let updatedAt = DatabaseHelpers.decodeDate(stmt.double(at: 3))
                let folderID = DatabaseHelpers.decodeUUID(stmt.optionalString(at: 4) ?? "")
                let relativePath = stmt.optionalString(at: 5)
                let details = stmt.string(at: 6)
                let dueDate = stmt.optionalDouble(at: 7).map(DatabaseHelpers.decodeDate)
                let priority = stmt.optionalString(at: 8).flatMap { TodoPriority(rawValue: $0) }
                let isCompleted = stmt.bool(at: 9)
                let completedAt = stmt.optionalDouble(at: 10).map(DatabaseHelpers.decodeDate)
                let notes = stmt.string(at: 11)
                let checklistJSON = stmt.optionalString(at: 12)
                let rulesJSON = stmt.optionalString(at: 13)
                let checklist: [TodoChecklistItem] =
                    DatabaseHelpers.decodeJSON([TodoChecklistItem].self, from: checklistJSON) ?? []
                let rules: [SurfacingRule] =
                    DatabaseHelpers.decodeJSON([SurfacingRule].self, from: rulesJSON) ?? []

                let labelIDs = (try? loadLabelIDs(db, itemID: id)) ?? []
                let linkedEntities = (try? loadLinkedEntities(db, sourceID: id)) ?? []

                let todo = TodoCard(
                    id: id,
                    title: title,
                    details: details,
                    checklist: checklist,
                    dueDate: dueDate,
                    priority: priority,
                    isCompleted: isCompleted,
                    completedAt: completedAt,
                    labelIDs: labelIDs,
                    notes: notes,
                    linkedEntities: linkedEntities,
                    folderID: folderID,
                    rules: rules,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
                loaded.append(todo)

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
                    dueDate: dueDate,
                    priority: priority
                )
            }
            todoCards = loaded
            index = rebuiltIndex
            sortCards()
            logger.info("Loaded \(loaded.count) todos from database")
        } catch {
            logger.error("Failed to load todos from database: \(error.localizedDescription)")
            todoCards = []
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
    /// Persist a single todo to the database (items + todos + item_labels + item_links)
    /// using the resolved (shared or explicit) database inside a transaction.
    func persistTodoToDatabase(_ todo: TodoCard) {
        guard let db = resolvedDatabase else {
            logger.warning("No database available, skipping SQLite persist for todo \(todo.id)")
            return
        }
        persistTodoToDatabase(db, todo: todo)
    }

    // Internal for testing
    /// Persist a single todo to the given database inside its own transaction.
    func persistTodoToDatabase(_ db: CiderDatabase, todo: TodoCard) {
        do {
            try db.withTransaction {
                try persistTodoToDatabaseInner(db, todo: todo)
            }
        } catch {
            logger.error("Failed to persist todo \(todo.id) to database: \(error.localizedDescription)")
        }
    }

    /// Compute the vault-relative path for a todo, preferring the real filename tracked
    /// in the in-memory index. Falls back to the sanitized title when the index hasn't
    /// been populated yet (e.g. initial one-time JSON migration inside `init`).
    private func relativePathForPersistence(_ todo: TodoCard) -> String? {
        let filename: String
        if let entryFilename = index[todo.id]?.filename {
            filename = entryFilename
        } else {
            filename = "\(sanitizedFilename(todo.title)).\(fileExtension)"
        }

        if let folderID = todo.folderID,
           let vaultFolder = VaultFolderService.shared.folder(for: folderID) {
            return "\(vaultFolder.relativePath)/\(filename)"
        }
        // Inbox todos live under `Inbox/Todos/{filename}`.
        return "Inbox/Todos/\(filename)"
    }

    /// Core persist logic for a single todo — must be called inside a transaction.
    private func persistTodoToDatabaseInner(_ db: CiderDatabase, todo: TodoCard) throws {
        // Scrub folder_id against target DB to defuse FK failures during the
        // first-run migration (or any drift between in-memory state and DB).
        let folderIDText = try resolveSafeFolderID(db, folderID: todo.folderID)

        // 1. UPSERT into items.
        // `relative_path` stores the vault-relative .ics path so that DB-first cold
        // loads can recover the EXACT on-disk filename (including collision suffixes
        // like "Title (2).ics"). Guessing from the title would orphan real files.
        let itemStmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, 'todo', ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                updated_at = excluded.updated_at,
                folder_id = excluded.folder_id,
                relative_path = excluded.relative_path;
            """)
        let itemID = DatabaseHelpers.encode(todo.id)
        let relativePath: String? = relativePathForPersistence(todo)
        itemStmt.bind(itemID, at: 1)
            .bind(todo.title, at: 2)
            .bind(DatabaseHelpers.encode(todo.createdAt), at: 3)
            .bind(DatabaseHelpers.encode(todo.updatedAt), at: 4)
            .bind(folderIDText, at: 5)
            .bind(relativePath, at: 6)
        try itemStmt.step()

        // 2. UPSERT into todos
        let todoStmt = try db.prepare("""
            INSERT INTO todos (item_id, details, due_date, priority, is_completed, completed_at, notes, checklist, surfacing_rules)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(item_id) DO UPDATE SET
                details = excluded.details,
                due_date = excluded.due_date,
                priority = excluded.priority,
                is_completed = excluded.is_completed,
                completed_at = excluded.completed_at,
                notes = excluded.notes,
                checklist = excluded.checklist,
                surfacing_rules = excluded.surfacing_rules;
            """)
        let checklistJSON: String? = todo.checklist.isEmpty
            ? nil
            : DatabaseHelpers.encodeJSON(todo.checklist)
        let rulesJSON: String? = todo.rules.isEmpty
            ? nil
            : DatabaseHelpers.encodeJSON(todo.rules)
        todoStmt.bind(itemID, at: 1)
            .bind(todo.details, at: 2)
            .bind(todo.dueDate.map(DatabaseHelpers.encode), at: 3)
            .bind(todo.priority?.rawValue, at: 4)
            .bind(todo.isCompleted ? Int64(1) : Int64(0), at: 5)
            .bind(todo.completedAt.map(DatabaseHelpers.encode), at: 6)
            .bind(todo.notes, at: 7)
            .bind(checklistJSON, at: 8)
            .bind(rulesJSON, at: 9)
        try todoStmt.step()

        // 3. Sync item_labels: delete all, re-insert current.
        let delLabels = try db.prepare("DELETE FROM item_labels WHERE item_id = ?;")
        delLabels.bind(itemID, at: 1)
        try delLabels.step()

        if !todo.labelIDs.isEmpty {
            let insLabel = try db.prepare("INSERT OR IGNORE INTO item_labels (item_id, label_id) VALUES (?, ?);")
            for labelID in todo.labelIDs {
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
        // When TodoCardStorage runs its one-time migration loop in `init`, other
        // services (bookmarks, notes, contacts, etc.) may not have migrated yet, so
        // their target rows in `items` don't exist. The `WHERE EXISTS` guard below
        // therefore silently drops any cross-type links for those not-yet-migrated
        // targets. This is acceptable because:
        //   1. `todo.linkedEntities` remains authoritative in memory and inside the
        //      .ics file — nothing is lost on disk.
        //   2. Any subsequent user edit to the todo re-runs this persist path, by
        //      which point all services have finished migrating and the targets do
        //      exist — so the links will be correctly re-persisted.
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
        for ref in todo.linkedEntities where Self.linkableEntityTypes.contains(ref.type.rawValue) {
            let target = DatabaseHelpers.encode(ref.entityID)
            insLink.reset()
            insLink.bind(itemID, at: 1)
                .bind(target, at: 2)
                .bind(now, at: 3)
                .bind(target, at: 4)
            try insLink.step()
        }
    }

    /// Delete a todo from the database by ID. CASCADE handles detail + join tables.
    func deleteTodoFromDatabase(_ todoID: UUID) {
        guard let db = resolvedDatabase else {
            logger.warning("No database available, skipping SQLite delete for todo \(todoID)")
            return
        }
        deleteTodoFromDatabase(db, todoID: todoID)
    }

    // Internal for testing
    /// DELETE a todo from the given database by ID.
    func deleteTodoFromDatabase(_ db: CiderDatabase, todoID: UUID) {
        do {
            let stmt = try db.prepare("DELETE FROM items WHERE id = ?;")
            stmt.bind(DatabaseHelpers.encode(todoID), at: 1)
            try stmt.step()
        } catch {
            logger.error("Failed to delete todo \(todoID) from database: \(error.localizedDescription)")
        }
    }
}
