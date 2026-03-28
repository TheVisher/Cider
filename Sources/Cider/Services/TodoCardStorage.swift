import Combine
import Foundation
import os

/// Legacy format — kept only for migration from the old single-JSON store.
struct TodoCardsSnapshot: Codable {
    var todoCards: [TodoCard]
}

/// Manages todos as individual .ics (VTODO) files on disk with a lightweight JSON index.
///
/// File layout:
/// - Unfiled todos: `Inbox/Todos/{title}.ics`
/// - Filed todos: `{UserFolder}/{title}.ics`
/// - Index: `.cider/todos/_cider_todos_index.json`
/// - Trash: `.cider/todos/.trash/`
@MainActor
final class TodoCardStorage: ObservableObject {
    static let shared = TodoCardStorage()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Cider",
        category: "TodoCardStorage"
    )

    @Published private(set) var todoCards: [TodoCard] = []

    private let indexFileName = "_cider_todos_index.json"
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
    private var isScanning = false
    private var pendingRescan = false

    private var metadataDirectoryURL: URL {
        StoragePaths.cachedDirectoryURL(for: .todos)
    }

    private var inboxDirectoryURL: URL {
        StoragePaths.cachedInboxSubdirectoryURL(for: .todos)
    }

    private var vaultRoot: URL {
        StoragePaths.cachedVaultDirectoryURL
    }

    private var indexURL: URL {
        metadataDirectoryURL.appendingPathComponent(indexFileName)
    }

    private init() {
        ensureDirectories()
        loadIndex()
        scanAndLoad()
        startWatching()
    }

    /// Watches the Inbox/Todos directory for new .ics files dropped externally (e.g. via iMessage agent).
    func startWatching() {
        inboxWatcher?.stop()
        inboxWatcher = FSEventsWatcher(path: inboxDirectoryURL.path, latency: 1.0) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isScanning else { return }
                self.rescan()
            }
        }
        inboxWatcher?.start()
    }

    /// Rescans for new or changed .ics files without full reinitialization.
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
    func createTodoCard(title: String, dueDate: Date? = nil, priority: TodoPriority? = nil) -> TodoCard {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmed.isEmpty ? "Untitled Todo" : trimmed
        let todoCard = TodoCard(title: finalTitle, dueDate: dueDate, priority: priority)

        let filename = uniqueFilename(for: finalTitle, in: inboxDirectoryURL)
        writeICSFile(for: todoCard, to: inboxDirectoryURL.appendingPathComponent(filename))

        index[todoCard.id] = IndexEntry(
            filename: filename, folderID: nil, labelIDs: nil,
            createdAt: todoCard.createdAt, isCompleted: false,
            dueDate: dueDate, priority: priority
        )
        saveIndex()

        todoCards.append(todoCard)
        sortCards()
        return todoCard
    }

    @discardableResult
    func addTodoCard(_ card: TodoCard) -> TodoCard {
        let dirURL = resolveDirectoryURL(folderID: card.folderID)
        let filename = uniqueFilename(for: card.title, in: dirURL)
        writeICSFile(for: card, to: dirURL.appendingPathComponent(filename))

        index[card.id] = IndexEntry(
            filename: filename, folderID: card.folderID,
            labelIDs: card.labelIDs.isEmpty ? nil : card.labelIDs,
            createdAt: card.createdAt, isCompleted: card.isCompleted,
            dueDate: card.dueDate, priority: card.priority
        )
        saveIndex()

        todoCards.append(card)
        sortCards()
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

        writeICSFile(for: copy, to: dirURL.appendingPathComponent(filename))

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
            for todoCard in todoCards where modifiedIDs.contains(todoCard.id) {
                writeAndUpdateIndex(for: todoCard)
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
        let filename = uniqueFilename(for: todoCard.title, in: dirURL)

        // Try to find the .ics in trash
        let trashDir = metadataDirectoryURL.appendingPathComponent(".trash")
        let fm = FileManager.default
        let trashFiles = (try? fm.contentsOfDirectory(at: trashDir, includingPropertiesForKeys: nil)) ?? []
        var restored = false

        for file in trashFiles where file.pathExtension == fileExtension {
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
            writeICSFile(for: todoCard, to: dirURL.appendingPathComponent(filename))
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
    }

    // MARK: - File I/O

    private func writeICSFile(for todoCard: TodoCard, to url: URL) {
        let icsString = ICalendarSerializer.serializeTodo(todoCard)
        try? icsString.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Convenience: write file and update index for an already-in-memory todoCard.
    private func writeAndUpdateIndex(for todoCard: TodoCard) {
        guard let entry = index[todoCard.id] else { return }
        let dirURL = resolveDirectoryURL(folderID: todoCard.folderID)
        writeICSFile(for: todoCard, to: dirURL.appendingPathComponent(entry.filename))
        var updated = entry
        updated.isCompleted = todoCard.isCompleted
        updated.dueDate = todoCard.dueDate
        updated.priority = todoCard.priority
        updated.labelIDs = todoCard.labelIDs.isEmpty ? nil : todoCard.labelIDs
        index[todoCard.id] = updated
        saveIndex()
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

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL) else {
            index = [:]
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([String: IndexEntry].self, from: data) {
            index = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
                guard let uuid = UUID(uuidString: key) else { return nil }
                return (uuid, value)
            })
            return
        }
        index = [:]
    }

    private func saveIndex() {
        let encoded = Dictionary(uniqueKeysWithValues: index.map { ($0.key.uuidString, $0.value) })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(encoded) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    // MARK: - Scan & Load

    private func scanAndLoad() {
        let fm = FileManager.default
        var loadedCards: [TodoCard] = []
        var needsSave = false

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
                    needsSave = true
                }
            }
        }

        todoCards = loadedCards
        sortCards()
        if needsSave { saveIndex() }
        logger.info("Loaded \(self.todoCards.count) todos from .ics files")
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
}
