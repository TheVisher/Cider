import Foundation
import Combine

struct NoteSnapshotInfo: Identifiable, Hashable {
    let id: String
    let url: URL
    let modifiedAt: Date
}

/// Manages notes as .md files on disk with a lightweight JSON index for UUID mapping.
@MainActor
final class NotesStorage: ObservableObject {
    static let shared = NotesStorage()

    @Published private(set) var notes: [Note] = []

    private var directoryURL: URL
    private var directoryFileDescriptor: Int32 = -1
    private var directorySource: DispatchSourceFileSystemObject?
    private var saveWorkItem: DispatchWorkItem?
    private var attachmentCleanupWorkItem: DispatchWorkItem?
    private let indexFileName = "_cider_notes_index.json"
    private let snapshotsDirectoryName = ".history"
    private let attachmentsDirectoryName = ".attachments"
    private let maxSnapshotsPerNote = 20
    private let maxSnapshotAgeDays = 30
    private let attachmentCleanupDelaySeconds: TimeInterval = 2
    private let orphanAttachmentGracePeriodSeconds: TimeInterval = 5 * 60

    /// Per-note metadata persisted in the index file.
private struct NoteIndexEntry: Codable, Equatable {
        var filename: String
        var folderID: UUID?
        var createdAt: Date?
    }

    /// UUID-to-metadata mapping persisted on disk
    private var index: [UUID: NoteIndexEntry] = [:]

    private init() {
        let config = CiderConfig.load()
        let path = NSString(string: config.notesDirectory).expandingTildeInPath
        self.directoryURL = URL(fileURLWithPath: path)
        ensureDirectory()
        loadIndex()
        scanNotes()
        startDirectoryWatcher()
    }

    /// The base directory URL where notes are stored.
    var notesDirectoryURL: URL { directoryURL }

    // MARK: - Directory Management

    func updateDirectory(to newPath: String) {
        stopDirectoryWatcher()
        attachmentCleanupWorkItem?.cancel()
        attachmentCleanupWorkItem = nil
        let expanded = NSString(string: newPath).expandingTildeInPath
        directoryURL = URL(fileURLWithPath: expanded)
        ensureDirectory()
        loadIndex()
        scanNotes()
        startDirectoryWatcher()
    }

    private func ensureDirectory() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directoryURL.path) {
            try? fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    // MARK: - Index (UUID mapping)

    private var indexURL: URL {
        directoryURL.appendingPathComponent(indexFileName)
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL) else {
            index = [:]
            return
        }

        // Try new format first: [String: NoteIndexEntry]
        if let decoded = try? JSONDecoder().decode([String: NoteIndexEntry].self, from: data) {
            index = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
                guard let uuid = UUID(uuidString: key) else { return nil }
                return (uuid, value)
            })
            return
        }

        // Fallback: legacy format [String: String] (UUID → filename)
        if let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            index = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
                guard let uuid = UUID(uuidString: key) else { return nil }
                return (uuid, NoteIndexEntry(filename: value, folderID: nil))
            })
            return
        }

        index = [:]
    }

    private func saveIndex() {
        let encoded = Dictionary(uniqueKeysWithValues: index.map { ($0.key.uuidString, $0.value) })
        if let data = try? JSONEncoder().encode(encoded) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    // MARK: - Scanning

    func scanNotes() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey]) else {
            notes = []
            return
        }

        // Build a resilient reverse map (filename -> UUID). If the index was
        // corrupted with duplicate filenames, keep the first UUID and ignore
        // the rest so scanning never crashes.
        var filenameToUUID: [String: UUID] = [:]
        for (uuid, entry) in index.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            if filenameToUUID[entry.filename] == nil {
                filenameToUUID[entry.filename] = uuid
            }
        }

        var scannedNotes: [Note] = []
        for fileURL in files {
            guard fileURL.pathExtension == "md" else { continue }
            let filename = fileURL.lastPathComponent
            guard filename != indexFileName else { continue }

            let title = String(filename.dropLast(3)) // Remove .md
            let uuid = filenameToUUID[filename] ?? UUID()
            let folderID = index[uuid]?.folderID

            let attrs = try? fm.attributesOfItem(atPath: fileURL.path)
            let modDate = attrs?[.modificationDate] as? Date ?? Date()
            let fsCreateDate = attrs?[.creationDate] as? Date ?? Date()

            // Use persisted createdAt from index (survives atomic file writes).
            // Fall back to filesystem creation date for legacy notes without it.
            let existingEntry = index[uuid]
            let createDate = existingEntry?.createdAt ?? fsCreateDate

            // Register in index if new, or backfill createdAt if missing
            if filenameToUUID[filename] == nil || existingEntry?.createdAt == nil {
                index[uuid] = NoteIndexEntry(filename: filename, folderID: folderID, createdAt: createDate)
            }

            // Lazy: don't load content during scan
            scannedNotes.append(Note(
                id: uuid,
                title: title,
                content: "",
                createdAt: createDate,
                modifiedAt: modDate,
                relativePath: filename,
                folderID: folderID
            ))
        }

        // Rebuild the index from scanned files so duplicates/stale entries are
        // cleaned up automatically. Preserve folderID and createdAt from existing entries.
        let previousIndex = index
        let rebuiltIndex = Dictionary(uniqueKeysWithValues: scannedNotes.map {
            ($0.id, NoteIndexEntry(filename: $0.relativePath, folderID: $0.folderID, createdAt: $0.createdAt))
        })
        index = rebuiltIndex

        // Sort by newest created first
        scannedNotes.sort { $0.createdAt > $1.createdAt }
        notes = scannedNotes
        if rebuiltIndex != previousIndex {
            saveIndex()
        }
    }

    // MARK: - CRUD

    func createNew() -> Note {
        let title = uniqueTitle("Untitled")
        let filename = "\(title).md"
        let fileURL = directoryURL.appendingPathComponent(filename)
        let uuid = UUID()
        let now = Date()

        // Write empty file
        try? "".write(to: fileURL, atomically: true, encoding: .utf8)

        index[uuid] = NoteIndexEntry(filename: filename, folderID: nil, createdAt: now)
        saveIndex()

        let note = Note(id: uuid, title: title, content: "", createdAt: now, modifiedAt: now, relativePath: filename)
        notes.insert(note, at: 0)
        return note
    }

    func loadContent(for note: Note) -> String {
        let fileURL = directoryURL.appendingPathComponent(note.relativePath)
        return (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    /// Convert stored markdown to editor-friendly markdown (absolute image paths).
    func markdownForEditor(_ markdown: String) -> String {
        NotesMarkdownPathCodec.markdownForEditor(markdown, notesDirectoryURL: directoryURL)
    }

    /// Convert editor markdown to portable markdown (relative image paths).
    func markdownForPersistence(_ markdown: String) -> String {
        NotesMarkdownPathCodec.markdownForPersistence(markdown, notesDirectoryURL: directoryURL)
    }

    func save(note: Note) {
        let fileURL = directoryURL.appendingPathComponent(note.relativePath)
        let previousContent = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""

        if previousContent != note.content {
            saveSnapshot(content: previousContent, for: note)
        }

        try? note.content.write(to: fileURL, atomically: true, encoding: .utf8)

        if previousContent != note.content {
            scheduleAttachmentCleanup()
        }

        // Update in-memory list
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx].modifiedAt = Date()
            notes[idx].content = note.content
        }
    }

    func scheduleSave(note: Note) {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.save(note: note)
            }
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    func rename(note: Note, to newTitle: String) {
        let sanitized = newTitle.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard !sanitized.isEmpty else { return }

        let oldPath = directoryURL.appendingPathComponent(note.relativePath)
        let newFilename = "\(sanitized).md"
        let newPath = directoryURL.appendingPathComponent(newFilename)

        guard !FileManager.default.fileExists(atPath: newPath.path) else { return }

        do {
            try FileManager.default.moveItem(at: oldPath, to: newPath)
            if var entry = index[note.id] {
                entry.filename = newFilename
                index[note.id] = entry
            } else {
                index[note.id] = NoteIndexEntry(filename: newFilename, folderID: note.folderID, createdAt: note.createdAt)
            }
            saveIndex()

            if let idx = notes.firstIndex(where: { $0.id == note.id }) {
                notes[idx].title = sanitized
                notes[idx].relativePath = newFilename
            }
        } catch {
            NSLog("[NotesStorage] Rename failed: \(error)")
        }
    }

    @discardableResult
    func assignNote(_ noteID: UUID, toFolder folderID: UUID?) -> Bool {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return false }
        guard notes[idx].folderID != folderID else { return true }

        notes[idx].folderID = folderID
        if var entry = index[noteID] {
            entry.folderID = folderID
            index[noteID] = entry
        }
        saveIndex()
        return true
    }

    @discardableResult
    func delete(note: Note) -> TrashItem {
        let trashItem = TrashStorage.shared.trashNote(note, notesDir: directoryURL)
        try? FileManager.default.removeItem(at: snapshotDirectoryURL(for: note))
        index.removeValue(forKey: note.id)
        saveIndex()
        notes.removeAll { $0.id == note.id }
        scheduleAttachmentCleanup()
        return trashItem
    }

    func restoreFromTrash(noteID: UUID, filename: String, folderID: UUID?, createdAt: Date) {
        index[noteID] = NoteIndexEntry(filename: filename, folderID: folderID, createdAt: createdAt)
        saveIndex()
        scanNotes()
    }

    func hasSnapshots(for note: Note) -> Bool {
        !snapshots(for: note).isEmpty
    }

    func loadMostRecentSnapshot(for note: Note) -> String? {
        guard let latest = snapshots(for: note).first else { return nil }
        return loadSnapshotContent(at: latest.url)
    }

    func mostRecentSnapshotDate(for note: Note) -> Date? {
        snapshots(for: note).first?.modifiedAt
    }

    func snapshots(for note: Note) -> [NoteSnapshotInfo] {
        snapshotFiles(for: note).map { url in
            let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return NoteSnapshotInfo(
                id: url.path,
                url: url,
                modifiedAt: modifiedAt
            )
        }
    }

    func loadSnapshotContent(at snapshotURL: URL) -> String? {
        try? String(contentsOf: snapshotURL, encoding: .utf8)
    }

    // MARK: - Directory Watcher

    private func startDirectoryWatcher() {
        let fd = open(directoryURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        directoryFileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.scanNotes()
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        directorySource = source
    }

    private func stopDirectoryWatcher() {
        directorySource?.cancel()
        directorySource = nil
        directoryFileDescriptor = -1
    }

    // MARK: - Image Storage

    /// Save image data to the `.attachments` subdirectory, returning the file URL.
    func saveImage(data: Data, filename: String, for note: Note) -> URL {
        let attachmentsDir = attachmentsDirectoryURL()
        let fm = FileManager.default
        if !fm.fileExists(atPath: attachmentsDir.path) {
            try? fm.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
        }

        // Prefix with short UUID to avoid collisions
        let uniqueName = "\(UUID().uuidString.prefix(8))-\(filename)"
        let fileURL = attachmentsDir.appendingPathComponent(uniqueName)
        try? data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    // MARK: - Helpers

    private func uniqueTitle(_ base: String) -> String {
        let existingTitles = Set(notes.map(\.title))
        if !existingTitles.contains(base) { return base }
        for i in 2...100 {
            let candidate = "\(base) \(i)"
            if !existingTitles.contains(candidate) { return candidate }
        }
        return "\(base) \(UUID().uuidString.prefix(4))"
    }

    private func snapshotsRootURL() -> URL {
        directoryURL.appendingPathComponent(snapshotsDirectoryName, isDirectory: true)
    }

    private func snapshotDirectoryURL(for note: Note) -> URL {
        snapshotsRootURL().appendingPathComponent(note.id.uuidString, isDirectory: true)
    }

    private func snapshotFiles(for note: Note) -> [URL] {
        let noteSnapshotDir = snapshotDirectoryURL(for: note)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: noteSnapshotDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: []
        ) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "md" }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return lhsDate > rhsDate
            }
    }

    private func saveSnapshot(content: String, for note: Note) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let fm = FileManager.default
        let noteSnapshotDir = snapshotDirectoryURL(for: note)

        if !fm.fileExists(atPath: noteSnapshotDir.path) {
            try? fm.createDirectory(at: noteSnapshotDir, withIntermediateDirectories: true)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let snapshotURL = noteSnapshotDir.appendingPathComponent("\(timestamp).md")

        try? content.write(to: snapshotURL, atomically: true, encoding: .utf8)
        pruneSnapshots(for: note)
    }

    private func pruneSnapshots(for note: Note) {
        let files = snapshotFiles(for: note)

        for overflow in files.dropFirst(maxSnapshotsPerNote) {
            try? FileManager.default.removeItem(at: overflow)
        }

        let expirationDate = Calendar.current.date(byAdding: .day, value: -maxSnapshotAgeDays, to: Date()) ?? .distantPast
        for file in files {
            let modifiedAt = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantFuture
            if modifiedAt < expirationDate {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func attachmentsDirectoryURL() -> URL {
        directoryURL.appendingPathComponent(attachmentsDirectoryName, isDirectory: true)
    }

    private func scheduleAttachmentCleanup() {
        attachmentCleanupWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.removeOrphanAttachments()
            }
        }

        attachmentCleanupWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + attachmentCleanupDelaySeconds,
            execute: workItem
        )
    }

    private func removeOrphanAttachments() {
        let fm = FileManager.default
        let attachmentsDir = attachmentsDirectoryURL()
        guard fm.fileExists(atPath: attachmentsDir.path) else { return }

        guard let attachmentURLs = try? fm.contentsOfDirectory(
            at: attachmentsDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let referencedFiles = referencedAttachmentFilenames()
        let orphanCutoff = Date().addingTimeInterval(-orphanAttachmentGracePeriodSeconds)

        for fileURL in attachmentURLs {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey]
            ) else {
                continue
            }

            guard values.isRegularFile == true else { continue }
            let filename = fileURL.lastPathComponent
            guard !referencedFiles.contains(filename) else { continue }

            let modifiedAt = values.contentModificationDate ?? .distantFuture
            guard modifiedAt < orphanCutoff else { continue }

            try? fm.removeItem(at: fileURL)
        }
    }

    private func referencedAttachmentFilenames() -> Set<String> {
        let markdownReferencePattern = #"\((?:\./)?\.attachments/([^)]+)\)"#
        let htmlReferencePattern = #"(?:src|href)=["'](?:\./)?\.attachments/([^"']+)["']"#

        let markdownRegex = try? NSRegularExpression(pattern: markdownReferencePattern, options: [])
        let htmlRegex = try? NSRegularExpression(pattern: htmlReferencePattern, options: [])

        var referenced = Set<String>()

        for note in notes {
            let noteURL = directoryURL.appendingPathComponent(note.relativePath)
            guard let content = try? String(contentsOf: noteURL, encoding: .utf8) else {
                continue
            }

            if let markdownRegex {
                extractAttachmentFilenames(
                    from: content,
                    regex: markdownRegex,
                    into: &referenced
                )
            }

            if let htmlRegex {
                extractAttachmentFilenames(
                    from: content,
                    regex: htmlRegex,
                    into: &referenced
                )
            }
        }

        return referenced
    }

    private func extractAttachmentFilenames(
        from content: String,
        regex: NSRegularExpression,
        into referenced: inout Set<String>
    ) {
        let nsContent = content as NSString
        let searchRange = NSRange(location: 0, length: nsContent.length)

        regex.enumerateMatches(in: content, options: [], range: searchRange) { match, _, _ in
            guard let match else { return }
            guard match.numberOfRanges > 1 else { return }
            let pathRange = match.range(at: 1)
            guard pathRange.location != NSNotFound else { return }

            var rawPath = nsContent.substring(with: pathRange)
            rawPath = rawPath.replacingOccurrences(of: "\\)", with: ")")
            rawPath = rawPath.replacingOccurrences(of: "\\(", with: "(")

            let decodedPath = rawPath.removingPercentEncoding ?? rawPath
            let filename = (decodedPath as NSString).lastPathComponent
            guard !filename.isEmpty else { return }

            referenced.insert(filename)
        }
    }

    deinit {
        directorySource?.cancel()
    }
}
