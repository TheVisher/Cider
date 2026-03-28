import Combine
import Foundation
import os

/// Legacy format — kept only for migration from the old single-JSON store.
struct DateCardsSnapshot: Codable {
    var dateCards: [DateCard]
}

/// Manages date cards as individual .ics (VEVENT) files on disk with a lightweight JSON index.
///
/// File layout:
/// - Unfiled date cards: `Inbox/Date Cards/{title}.ics`
/// - Filed date cards: `{UserFolder}/{title}.ics`
/// - Index: `.cider/date-cards/_cider_date_cards_index.json`
/// - Trash: `.cider/date-cards/.trash/`
@MainActor
final class DateCardStorage: ObservableObject {
    static let shared = DateCardStorage()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Cider",
        category: "DateCardStorage"
    )

    @Published private(set) var dateCards: [DateCard] = []

    private let indexFileName = "_cider_date_cards_index.json"
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

    private var metadataDirectoryURL: URL {
        StoragePaths.cachedDirectoryURL(for: .dateCards)
    }

    private var inboxDirectoryURL: URL {
        StoragePaths.cachedInboxSubdirectoryURL(for: .dateCards)
    }

    private var vaultRoot: URL {
        StoragePaths.cachedVaultDirectoryURL
    }

    private var indexURL: URL {
        metadataDirectoryURL.appendingPathComponent(indexFileName)
    }

    private var inboxWatcher: FSEventsWatcher?
    private var isScanning = false
    private var pendingRescan = false

    private init() {
        ensureDirectories()
        loadIndex()
        scanAndLoad()
        startWatching()
    }

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
        writeICSFile(for: dateCard, to: inboxDirectoryURL.appendingPathComponent(filename))

        index[dateCard.id] = IndexEntry(
            filename: filename, folderID: nil, labelIDs: nil,
            createdAt: dateCard.createdAt, isCompleted: false,
            startAt: startAt
        )
        saveIndex()

        dateCards.append(dateCard)
        sortCards()
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

        writeICSFile(for: copy, to: dirURL.appendingPathComponent(filename))

        dateCards[idx] = copy
        index[updated.id] = IndexEntry(
            filename: filename, folderID: copy.folderID,
            labelIDs: copy.labelIDs.isEmpty ? nil : copy.labelIDs,
            createdAt: oldEntry?.createdAt ?? copy.createdAt,
            isCompleted: copy.isCompleted, startAt: copy.startAt
        )
        saveIndex()
        sortCards()
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
            for dc in dateCards where modifiedIDs.contains(dc.id) {
                writeAndUpdateIndex(for: dc)
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
            writeICSFile(for: dateCard, to: dirURL.appendingPathComponent(filename))
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
    }

    // MARK: - File I/O

    private func writeICSFile(for dateCard: DateCard, to url: URL) {
        let icsString = ICalendarSerializer.serializeDateCard(dateCard)
        try? icsString.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Convenience: write file and update index for an already-in-memory dateCard.
    private func writeAndUpdateIndex(for dateCard: DateCard) {
        guard let entry = index[dateCard.id] else { return }
        let dirURL = resolveDirectoryURL(folderID: dateCard.folderID)
        writeICSFile(for: dateCard, to: dirURL.appendingPathComponent(entry.filename))
        var updated = entry
        updated.isCompleted = dateCard.isCompleted
        updated.startAt = dateCard.startAt
        updated.labelIDs = dateCard.labelIDs.isEmpty ? nil : dateCard.labelIDs
        index[dateCard.id] = updated
        saveIndex()
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
        var loadedCards: [DateCard] = []
        var needsSave = false

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
                    needsSave = true
                }
            }
        }

        dateCards = loadedCards
        sortCards()
        if needsSave { saveIndex() }
        logger.info("Loaded \(self.dateCards.count) date cards from .ics files")
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
}
