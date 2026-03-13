import AppKit
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
    private var inboxFileDescriptor: Int32 = -1
    private var inboxDirectorySource: DispatchSourceFileSystemObject?
    private var saveWorkItem: DispatchWorkItem?
    private var attachmentCleanupWorkItem: DispatchWorkItem?
    private let indexFileName = "_cider_notes_index.json"
    private let snapshotsDirectoryName = ".history"
    private let attachmentsDirectoryName = ".attachments"
    private let maxSnapshotsPerNote = 20
    private let maxSnapshotAgeDays = 30
    private let attachmentCleanupDelaySeconds: TimeInterval = 2
    private let orphanAttachmentGracePeriodSeconds: TimeInterval = 5 * 60

    /// In-memory cache for note content, avoiding disk reads on every search query.
    /// Keyed by note ID, validated against modifiedAt to auto-invalidate on edits.
    private var contentCache: [UUID: (modifiedAt: Date, content: String)] = [:]

    /// Per-note metadata persisted in the index file.
    private struct NoteIndexEntry: Codable, Equatable, Sendable {
        var filename: String
        var folderID: UUID?
        var labelIDs: [UUID]?
        var createdAt: Date?
        /// Source URL captured from (if any), persisted for future metadata panel.
        var sourceURL: String?
        /// Filename under `{notesDir}/.attachments/` for an associated screenshot.
        var sourceImageFilename: String?
        var isPinned: Bool?

        init(filename: String, folderID: UUID? = nil, labelIDs: [UUID]? = nil, createdAt: Date? = nil,
             sourceURL: String? = nil, sourceImageFilename: String? = nil, isPinned: Bool? = nil) {
            self.filename = filename
            self.folderID = folderID
            self.labelIDs = labelIDs
            self.createdAt = createdAt
            self.sourceURL = sourceURL
            self.sourceImageFilename = sourceImageFilename
            self.isPinned = isPinned
        }
    }

    /// UUID-to-metadata mapping persisted on disk
    private var index: [UUID: NoteIndexEntry] = [:]

    private init() {
        self.directoryURL = StoragePaths.directoryURL(for: .notes)
        ensureDirectory()
        startDirectoryWatcher()
        let dirURL = directoryURL
        let idxURL = dirURL.appendingPathComponent(indexFileName)
        let idxName = indexFileName
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await Task.detached(priority: .userInitiated) {
                Self.loadAndScan(directoryURL: dirURL, indexURL: idxURL, indexFileName: idxName)
            }.value
            self.index = result.index
            self.notes = result.notes
            if result.needsSave { self.saveIndex() }
            self.loadVaultFolderNotes()
        }
    }

    /// The base directory URL where notes metadata index is stored (.cider/notes/).
    var notesDirectoryURL: URL { directoryURL }

    /// The Inbox/Notes/ directory for unfiled note content files.
    private var inboxNotesDirectoryURL: URL {
        StoragePaths.cachedInboxSubdirectoryURL(for: .notes)
    }

    /// The vault root directory.
    private var vaultRoot: URL { StoragePaths.cachedVaultDirectoryURL }

    /// Resolves the absolute file URL for a note.
    /// Uses Note.absoluteFileURL which handles both Notes/-based and vault-folder-based paths.
    func noteFileURL(for note: Note) -> URL {
        note.absoluteFileURL
    }

    // MARK: - Directory Management

    func updateDirectory(to newPath: String) {
        contentCache.removeAll()
        stopDirectoryWatcher()
        attachmentCleanupWorkItem?.cancel()
        attachmentCleanupWorkItem = nil
        let expanded = NSString(string: newPath).expandingTildeInPath
        directoryURL = URL(fileURLWithPath: expanded)
        notes = []
        index = [:]
        ensureDirectory()
        startDirectoryWatcher()
        // CH-C15: Load synchronously so callers see notes immediately after return.
        // Unlike init(), updateDirectory is user-triggered (rare) so brief main-thread
        // I/O is acceptable to avoid the async race that broke callers and tests.
        let result = Self.loadAndScan(
            directoryURL: directoryURL,
            indexURL: directoryURL.appendingPathComponent(indexFileName),
            indexFileName: indexFileName
        )
        index = result.index
        notes = result.notes
        if result.needsSave { saveIndex() }
        loadVaultFolderNotes()
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
        contentCache.removeAll()
        let fm = FileManager.default

        // Scan both .cider/notes/ (legacy) and Inbox/Notes/ for unfiled notes
        var allFiles: [(url: URL, relativePrefix: String?)] = []
        if let files = try? fm.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey]) {
            for f in files { allFiles.append((f, nil)) }
        }
        let inboxDir = inboxNotesDirectoryURL
        if let inboxFiles = try? fm.contentsOfDirectory(at: inboxDir, includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey]) {
            for f in inboxFiles { allFiles.append((f, "\(StoragePaths.inboxDir)/Notes")) }
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
        for (fileURL, relativePrefix) in allFiles {
            guard fileURL.pathExtension == "md" else { continue }
            let filename = fileURL.lastPathComponent
            guard filename != indexFileName else { continue }

            let title = String(filename.dropLast(3)) // Remove .md
            let uuid = filenameToUUID[filename] ?? UUID()
            let existingEntry = index[uuid]
            let folderID = existingEntry?.folderID
            let labelIDs = existingEntry?.labelIDs ?? []
            let isPinned = existingEntry?.isPinned ?? false

            let attrs = try? fm.attributesOfItem(atPath: fileURL.path)
            let modDate = attrs?[.modificationDate] as? Date ?? Date()
            let fsCreateDate = attrs?[.creationDate] as? Date ?? Date()

            // Use persisted createdAt from index (survives atomic file writes).
            // Fall back to filesystem creation date for legacy notes without it.
            let createDate = existingEntry?.createdAt ?? fsCreateDate

            // Register in index if new, or backfill createdAt if missing
            if filenameToUUID[filename] == nil || existingEntry?.createdAt == nil {
                index[uuid] = NoteIndexEntry(filename: filename, folderID: folderID, labelIDs: labelIDs, createdAt: createDate, isPinned: isPinned ? true : nil)
            }

            // Build relativePath: Inbox/Notes/file.md for inbox, plain filename for legacy .cider/notes/
            let relativePath: String
            if let prefix = relativePrefix {
                relativePath = "\(prefix)/\(filename)"
            } else {
                relativePath = filename
            }

            // Lazy: don't load content during scan
            scannedNotes.append(Note(
                id: uuid,
                title: title,
                content: "",
                createdAt: createDate,
                modifiedAt: modDate,
                relativePath: relativePath,
                labelIDs: labelIDs,
                folderID: folderID,
                isPinned: isPinned
            ))
        }

        // Rebuild the index from scanned files so duplicates/stale entries are
        // cleaned up automatically. Index stores just the filename, not the full relativePath.
        // Preserve folderID, labelIDs, createdAt, and isPinned from existing entries.
        let previousIndex = index
        var rebuiltIndex = Dictionary(uniqueKeysWithValues: scannedNotes.map {
            let filename = ($0.relativePath as NSString).lastPathComponent
            return ($0.id, NoteIndexEntry(filename: filename, folderID: $0.folderID, labelIDs: $0.labelIDs, createdAt: $0.createdAt, isPinned: $0.isPinned ? true : nil))
        })

        // Carry forward notes that live in vault folders (not in Notes/ dir).
        // These aren't found by the Notes/-only scan but are tracked in the index.
        let scannedIDs = Set(scannedNotes.map(\.id))
        for (uuid, entry) in previousIndex where !scannedIDs.contains(uuid) {
            guard entry.folderID != nil else { continue }
            // Verify the file still exists on disk
            if let vaultFolder = VaultFolderService.shared.folder(for: entry.folderID!) {
                let filePath = vaultRoot.appendingPathComponent(vaultFolder.relativePath)
                    .appendingPathComponent(entry.filename).path
                if fm.fileExists(atPath: filePath) {
                    rebuiltIndex[uuid] = entry
                    let fileAttrs = try? fm.attributesOfItem(atPath: filePath)
                    let modDate = (fileAttrs?[.modificationDate] as? Date) ?? Date()
                    scannedNotes.append(Note(
                        id: uuid,
                        title: String(entry.filename.dropLast(3)),
                        content: "",
                        createdAt: entry.createdAt ?? Date(),
                        modifiedAt: modDate,
                        relativePath: "\(vaultFolder.relativePath)/\(entry.filename)",
                        labelIDs: entry.labelIDs ?? [],
                        folderID: entry.folderID,
                        isPinned: entry.isPinned ?? false
                    ))
                }
            }
        }
        index = rebuiltIndex

        // Sort: pinned first, then by newest created
        scannedNotes.sort { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.createdAt > b.createdAt
        }
        notes = scannedNotes
        if rebuiltIndex != previousIndex {
            saveIndex()
        }
    }

    /// Loads notes that live in vault folders (not in the Notes/ directory).
    /// Called after the initial scan or background load to pick up folder-based notes
    /// that the Notes/-only scan can't find.
    private func loadVaultFolderNotes() {
        let fm = FileManager.default
        let existingIDs = Set(notes.map(\.id))
        var added = false

        for (uuid, entry) in index where !existingIDs.contains(uuid) {
            guard let folderID = entry.folderID,
                  let vaultFolder = VaultFolderService.shared.folder(for: folderID) else { continue }

            let filePath = vaultRoot.appendingPathComponent(vaultFolder.relativePath)
                .appendingPathComponent(entry.filename)
            guard fm.fileExists(atPath: filePath.path) else { continue }

            let attrs = try? fm.attributesOfItem(atPath: filePath.path)
            let modDate = attrs?[.modificationDate] as? Date ?? Date()

            notes.append(Note(
                id: uuid,
                title: String(entry.filename.dropLast(3)),
                content: "",
                createdAt: entry.createdAt ?? Date(),
                modifiedAt: modDate,
                relativePath: "\(vaultFolder.relativePath)/\(entry.filename)",
                labelIDs: entry.labelIDs ?? [],
                folderID: folderID,
                isPinned: entry.isPinned ?? false
            ))
            added = true
        }

        if added {
            notes.sort { a, b in
                if a.isPinned != b.isPinned { return a.isPinned }
                return a.createdAt > b.createdAt
            }
        }
    }

    // MARK: - Background Load & Scan

    /// Combines loadIndex + scanNotes into a pure, background-safe function.
    /// Returns the rebuilt index, scanned notes, and whether the index needs saving.
    private nonisolated static func loadAndScan(
        directoryURL: URL,
        indexURL: URL,
        indexFileName: String
    ) -> (index: [UUID: NoteIndexEntry], notes: [Note], needsSave: Bool) {
        // Load index
        var loadedIndex: [UUID: NoteIndexEntry] = [:]
        if let data = try? Data(contentsOf: indexURL) {
            // Try new format first: [String: NoteIndexEntry]
            if let decoded = try? JSONDecoder().decode([String: NoteIndexEntry].self, from: data) {
                loadedIndex = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
                    guard let uuid = UUID(uuidString: key) else { return nil }
                    return (uuid, value)
                })
            } else if let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                // Fallback: legacy format [String: String] (UUID → filename)
                loadedIndex = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
                    guard let uuid = UUID(uuidString: key) else { return nil }
                    return (uuid, NoteIndexEntry(filename: value, folderID: nil, createdAt: nil))
                })
            }
        }

        // Scan both .cider/notes/ (legacy) and Inbox/Notes/ for unfiled notes
        let fm = FileManager.default
        var allFiles: [(url: URL, relativePrefix: String?)] = []
        if let files = try? fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey]
        ) {
            for f in files { allFiles.append((f, nil)) }
        }
        // Also scan Inbox/Notes/ — compute from directoryURL's vault root
        let vaultRoot = directoryURL
            .deletingLastPathComponent() // .cider/
            .deletingLastPathComponent() // vault root
        let inboxNotesDir = vaultRoot
            .appendingPathComponent(StoragePaths.inboxDir)
            .appendingPathComponent("Notes")
        if let inboxFiles = try? fm.contentsOfDirectory(
            at: inboxNotesDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey]
        ) {
            for f in inboxFiles { allFiles.append((f, "\(StoragePaths.inboxDir)/Notes")) }
        }

        guard !allFiles.isEmpty else {
            return (index: [:], notes: [], needsSave: false)
        }

        // Build a resilient reverse map (filename -> UUID).
        var filenameToUUID: [String: UUID] = [:]
        for (uuid, entry) in loadedIndex.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            if filenameToUUID[entry.filename] == nil {
                filenameToUUID[entry.filename] = uuid
            }
        }

        var workingIndex = loadedIndex
        var scannedNotes: [Note] = []

        for (fileURL, relativePrefix) in allFiles {
            guard fileURL.pathExtension == "md" else { continue }
            let filename = fileURL.lastPathComponent
            guard filename != indexFileName else { continue }

            let title = String(filename.dropLast(3)) // Remove .md
            let uuid = filenameToUUID[filename] ?? UUID()
            let existingEntry = workingIndex[uuid]
            let folderID = existingEntry?.folderID
            let labelIDs = existingEntry?.labelIDs ?? []
            let isPinned = existingEntry?.isPinned ?? false

            let attrs = try? fm.attributesOfItem(atPath: fileURL.path)
            let modDate = attrs?[.modificationDate] as? Date ?? Date()
            let fsCreateDate = attrs?[.creationDate] as? Date ?? Date()

            // Use persisted createdAt from index (survives atomic file writes).
            // Fall back to filesystem creation date for legacy notes without it.
            let createDate = existingEntry?.createdAt ?? fsCreateDate

            // Register in index if new, or backfill createdAt if missing
            if filenameToUUID[filename] == nil || existingEntry?.createdAt == nil {
                workingIndex[uuid] = NoteIndexEntry(filename: filename, folderID: folderID, labelIDs: labelIDs, createdAt: createDate, isPinned: isPinned ? true : nil)
            }

            // Build relativePath: Inbox/Notes/file.md for inbox, plain filename for legacy .cider/notes/
            let relativePath: String
            if let prefix = relativePrefix {
                relativePath = "\(prefix)/\(filename)"
            } else {
                relativePath = filename
            }

            // Lazy: don't load content during scan
            scannedNotes.append(Note(
                id: uuid,
                title: title,
                content: "",
                createdAt: createDate,
                modifiedAt: modDate,
                relativePath: relativePath,
                labelIDs: labelIDs,
                folderID: folderID,
                isPinned: isPinned
            ))
        }

        // Rebuild the index from scanned files so duplicates/stale entries are
        // cleaned up automatically. Index stores just the filename, not the full relativePath.
        // Preserve folderID, labelIDs, createdAt, and isPinned from existing entries.
        let rebuiltIndex = Dictionary(uniqueKeysWithValues: scannedNotes.map {
            let filename = ($0.relativePath as NSString).lastPathComponent
            return ($0.id, NoteIndexEntry(filename: filename, folderID: $0.folderID, labelIDs: $0.labelIDs, createdAt: $0.createdAt, isPinned: $0.isPinned ? true : nil))
        })

        // Sort: pinned first, then by newest created
        scannedNotes.sort { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.createdAt > b.createdAt
        }

        let needsSave = rebuiltIndex != loadedIndex
        return (index: rebuiltIndex, notes: scannedNotes, needsSave: needsSave)
    }

    // MARK: - CRUD

    func createNew() -> Note {
        let title = uniqueTitle("Untitled")
        let filename = "\(title).md"
        let inboxDir = inboxNotesDirectoryURL
        let fileURL = inboxDir.appendingPathComponent(filename)
        let uuid = UUID()
        let now = Date()

        // Ensure Inbox/Notes/ exists
        try? FileManager.default.createDirectory(at: inboxDir, withIntermediateDirectories: true)

        // Write empty file to Inbox/Notes/
        try? "".write(to: fileURL, atomically: true, encoding: .utf8)

        let inboxRelativePath = "\(StoragePaths.inboxDir)/Notes/\(filename)"
        index[uuid] = NoteIndexEntry(filename: filename, folderID: nil, createdAt: now)
        saveIndex()

        let note = Note(id: uuid, title: title, content: "", createdAt: now, modifiedAt: now, relativePath: inboxRelativePath)
        notes.insert(note, at: 0)
        return note
    }

    /// Create a note from a screen capture, saving the screenshot to Attachments.
    /// - Parameters:
    ///   - title: Initial note title (derived from OCR text or a default).
    ///   - ocrText: OCR-extracted text to use as the note body.
    ///   - screenshot: The captured screenshot image (saved as PNG to Attachments).
    ///   - sourceURL: Source URL if the capture was associated with a browser page.
    /// - Returns: The newly created `Note`.
    @discardableResult
    func createFromCapture(
        title: String,
        ocrText: String,
        screenshot: NSImage?,
        sourceURL: String? = nil
    ) -> Note {
        let sanitizedTitle = title.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let safeTitle = sanitizedTitle.isEmpty ? "Screen Capture" : sanitizedTitle
        let uniqued = uniqueTitle(safeTitle)
        let filename = "\(uniqued).md"
        let inboxDir = inboxNotesDirectoryURL
        let fileURL = inboxDir.appendingPathComponent(filename)
        let uuid = UUID()
        let now = Date()

        // Ensure Inbox/Notes/ exists
        try? FileManager.default.createDirectory(at: inboxDir, withIntermediateDirectories: true)

        // Save screenshot to Attachments if provided
        var screenshotFilename: String?
        if let image = screenshot,
           let pngData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: pngData),
           let png = bitmap.representation(using: .png, properties: [:]) {
            let attachmentsDir = attachmentsDirectoryURL()
            let fm = FileManager.default
            if !fm.fileExists(atPath: attachmentsDir.path) {
                try? fm.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
            }
            let fname = "\(uuid.uuidString)-capture.png"
            let imgURL = attachmentsDir.appendingPathComponent(fname)
            if (try? png.write(to: imgURL, options: .atomic)) != nil {
                screenshotFilename = fname
            }
        }

        // Build markdown content: screenshot embed + OCR text
        var lines: [String] = []
        if let fname = screenshotFilename {
            lines.append("<img src=\".attachments/\(fname)\" alt=\"Screen Capture\" />")
            lines.append("")
        }
        if !ocrText.isEmpty {
            lines.append(ocrText)
        }
        let content = lines.joined(separator: "\n")

        try? content.write(to: fileURL, atomically: true, encoding: .utf8)

        let inboxRelativePath = "\(StoragePaths.inboxDir)/Notes/\(filename)"
        index[uuid] = NoteIndexEntry(
            filename: filename,
            folderID: nil,
            createdAt: now,
            sourceURL: sourceURL,
            sourceImageFilename: screenshotFilename
        )
        saveIndex()

        let note = Note(
            id: uuid,
            title: uniqued,
            content: content,
            createdAt: now,
            modifiedAt: now,
            relativePath: inboxRelativePath
        )
        notes.insert(note, at: 0)
        return note
    }

    func loadContent(for note: Note) -> String {
        if let cached = contentCache[note.id], cached.modifiedAt == note.modifiedAt {
            return cached.content
        }
        let fileURL = noteFileURL(for: note)
        let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        contentCache[note.id] = (note.modifiedAt, content)
        return content
    }

    /// Convert stored markdown to editor-friendly markdown (absolute image paths).
    func markdownForEditor(_ markdown: String) -> String {
        NotesMarkdownPathCodec.markdownForEditor(markdown, notesDirectoryURL: directoryURL)
    }

    /// Convert editor markdown to portable markdown (relative image paths).
    func markdownForPersistence(_ markdown: String) -> String {
        NotesMarkdownPathCodec.markdownForPersistence(markdown, notesDirectoryURL: directoryURL)
    }

    func save(note: Note, createSnapshot: Bool = true) {
        let fileURL = noteFileURL(for: note)
        let previousContent = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""

        if createSnapshot, previousContent != note.content {
            saveSnapshot(content: previousContent, for: note)
        }

        try? note.content.write(to: fileURL, atomically: true, encoding: .utf8)

        if previousContent != note.content {
            scheduleAttachmentCleanup()
        }

        // Invalidate content cache for this note
        contentCache.removeValue(forKey: note.id)

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

        let oldFileURL = noteFileURL(for: note)
        let newFilename = "\(sanitized).md"
        // New file goes in the same directory as the old one
        let newFileURL = oldFileURL.deletingLastPathComponent().appendingPathComponent(newFilename)

        guard !FileManager.default.fileExists(atPath: newFileURL.path) else { return }

        // Build the new relativePath: if the note was in a vault folder, preserve the folder prefix
        let newRelativePath: String
        if note.relativePath.contains("/") {
            let parentPath = (note.relativePath as NSString).deletingLastPathComponent
            newRelativePath = "\(parentPath)/\(newFilename)"
        } else {
            newRelativePath = newFilename
        }

        do {
            try FileManager.default.moveItem(at: oldFileURL, to: newFileURL)

            // Move sidecar metadata from old filename to new filename
            let oldFilename = (note.relativePath as NSString).lastPathComponent
            let dirPath = note.relativePath.contains("/")
                ? (note.relativePath as NSString).deletingLastPathComponent
                : "\(StoragePaths.inboxDir)/Notes"
            if let existingMeta = SidecarService.shared.metadata(for: oldFilename, inDirectory: dirPath) {
                SidecarService.shared.removeMetadata(for: oldFilename, inDirectory: dirPath)
                SidecarService.shared.setMetadata(existingMeta, for: newFilename, inDirectory: dirPath)
            }

            if var entry = index[note.id] {
                entry.filename = newFilename
                index[note.id] = entry
            } else {
                index[note.id] = NoteIndexEntry(filename: newFilename, folderID: note.folderID, createdAt: note.createdAt)
            }
            saveIndex()

            if let idx = notes.firstIndex(where: { $0.id == note.id }) {
                notes[idx].title = sanitized
                notes[idx].relativePath = newRelativePath
                notes[idx].modifiedAt = Date()
            }
            SyncService.shared.pushAfterLocalChange()
        } catch {
            NSLog("[NotesStorage] Rename failed: \(error)")
        }
    }

    @discardableResult
    func togglePin(_ noteID: UUID) -> Bool {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return false }
        notes[idx].isPinned.toggle()
        notes[idx].modifiedAt = Date()
        if var entry = index[noteID] {
            entry.isPinned = notes[idx].isPinned ? true : nil
            index[noteID] = entry
        }
        saveIndex()
        SyncService.shared.pushAfterLocalChange()
        return true
    }

    @discardableResult
    func assignNote(_ noteID: UUID, toFolder folderID: UUID?) -> Bool {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return false }
        guard notes[idx].folderID != folderID else { return true }

        let note = notes[idx]
        let filename = (note.relativePath as NSString).lastPathComponent
        let oldFileURL = noteFileURL(for: note)

        // Determine the new directory: vault folder or Inbox/Notes/
        let newDirURL: URL
        let newRelativePath: String
        if let folderID, let vaultFolder = VaultFolderService.shared.folder(for: folderID) {
            newDirURL = vaultRoot.appendingPathComponent(vaultFolder.relativePath)
            newRelativePath = "\(vaultFolder.relativePath)/\(filename)"
        } else {
            newDirURL = inboxNotesDirectoryURL
            newRelativePath = "\(StoragePaths.inboxDir)/Notes/\(filename)"
        }

        let newFileURL = newDirURL.appendingPathComponent(filename)

        // Physically move the file if source and destination differ
        if oldFileURL != newFileURL {
            let fm = FileManager.default
            // Ensure destination directory exists
            try? fm.createDirectory(at: newDirURL, withIntermediateDirectories: true)
            do {
                try fm.moveItem(at: oldFileURL, to: newFileURL)
            } catch {
                NSLog("[NotesStorage] Failed to move note file: \(error)")
                return false
            }
        }

        notes[idx].folderID = folderID
        notes[idx].relativePath = newRelativePath
        notes[idx].modifiedAt = Date()
        contentCache.removeValue(forKey: noteID)

        if var entry = index[noteID] {
            entry.folderID = folderID
            index[noteID] = entry
        }
        saveIndex()
        SyncService.shared.pushAfterLocalChange()
        return true
    }

    @discardableResult
    func assignLabel(_ noteID: UUID, labelID: UUID) -> Bool {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return false }
        guard !notes[idx].labelIDs.contains(labelID) else { return true }
        notes[idx].labelIDs.append(labelID)
        if var entry = index[noteID] {
            entry.labelIDs = notes[idx].labelIDs
            index[noteID] = entry
        }
        saveIndex()
        SidecarService.shared.syncNote(notes[idx])
        return true
    }

    @discardableResult
    func removeLabel(_ noteID: UUID, labelID: UUID) -> Bool {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return false }
        notes[idx].labelIDs.removeAll { $0 == labelID }
        if var entry = index[noteID] {
            entry.labelIDs = notes[idx].labelIDs
            index[noteID] = entry
        }
        saveIndex()
        SidecarService.shared.syncNote(notes[idx])
        return true
    }

    func removeLabelsFromAll(labelID: UUID) {
        var changed = false
        for i in notes.indices where notes[i].labelIDs.contains(labelID) {
            notes[i].labelIDs.removeAll { $0 == labelID }
            if var entry = index[notes[i].id] {
                entry.labelIDs = notes[i].labelIDs
                index[notes[i].id] = entry
            }
            changed = true
        }
        if changed { saveIndex() }
    }

    @discardableResult
    func delete(note: Note) -> TrashItem {
        contentCache.removeValue(forKey: note.id)

        // For notes in vault/Inbox folders, move the file to Inbox/Notes/ first so trash works correctly
        var noteForTrash = note
        let trashNotesDir = inboxNotesDirectoryURL
        if note.relativePath.contains("/") {
            let filename = (note.relativePath as NSString).lastPathComponent
            let vaultFileURL = noteFileURL(for: note)
            let inboxFileURL = trashNotesDir.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: vaultFileURL.path) {
                try? FileManager.default.createDirectory(at: trashNotesDir, withIntermediateDirectories: true)
                try? FileManager.default.moveItem(at: vaultFileURL, to: inboxFileURL)
            }
            noteForTrash = Note(
                id: note.id, title: note.title, content: note.content,
                createdAt: note.createdAt, modifiedAt: note.modifiedAt,
                relativePath: "\(StoragePaths.inboxDir)/Notes/\(filename)", labelIDs: note.labelIDs,
                folderID: note.folderID, isPinned: note.isPinned
            )
        }
        let trashItem = TrashStorage.shared.trashNote(noteForTrash, notesDir: trashNotesDir)
        try? FileManager.default.removeItem(at: snapshotDirectoryURL(for: note))
        index.removeValue(forKey: note.id)
        saveIndex()
        notes.removeAll { $0.id == note.id }
        scheduleAttachmentCleanup()

        // Track deletion for sync
        let config = CiderConfig.load()
        if config.syncEnabled {
            SyncService.shared.trackNoteDeletion(of: note.id)
        }

        return trashItem
    }

    // MARK: - Sync

    /// Create a note from a sync pull (new note from web).
    func addFromSync(
        id: UUID,
        title: String,
        content: String,
        folderID: UUID?,
        isPinned: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        let sanitizedTitle = title.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let safeTitle = sanitizedTitle.isEmpty ? "Untitled" : sanitizedTitle
        let uniqued = uniqueTitle(safeTitle)
        let filename = "\(uniqued).md"

        // Write to Inbox/Notes/ for unfiled, or vault folder for assigned notes
        let targetDir: URL
        let relativePath: String
        if let folderID, let vaultFolder = VaultFolderService.shared.folder(for: folderID) {
            targetDir = vaultRoot.appendingPathComponent(vaultFolder.relativePath)
            relativePath = "\(vaultFolder.relativePath)/\(filename)"
        } else {
            targetDir = inboxNotesDirectoryURL
            relativePath = "\(StoragePaths.inboxDir)/Notes/\(filename)"
        }

        try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        let fileURL = targetDir.appendingPathComponent(filename)
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)

        // Set file modification date to match remote updatedAt
        try? FileManager.default.setAttributes(
            [.modificationDate: updatedAt],
            ofItemAtPath: fileURL.path
        )

        index[id] = NoteIndexEntry(
            filename: filename,
            folderID: folderID,
            createdAt: createdAt,
            isPinned: isPinned ? true : nil
        )
        saveIndex()

        let note = Note(
            id: id,
            title: uniqued,
            content: content,
            createdAt: createdAt,
            modifiedAt: updatedAt,
            relativePath: relativePath,
            folderID: folderID,
            isPinned: isPinned
        )
        notes.insert(note, at: 0)
    }

    /// Update an existing note from a sync pull (remote is newer).
    func updateFromSync(
        noteID: UUID,
        title: String,
        content: String,
        folderID: UUID?,
        isPinned: Bool,
        remoteUpdatedAt: Date
    ) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }

        let note = notes[idx]
        let oldFileURL = noteFileURL(for: note)

        // Handle rename if title changed
        let sanitizedTitle = title.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let newFilename: String
        if sanitizedTitle != notes[idx].title && !sanitizedTitle.isEmpty {
            let uniqued = uniqueTitle(sanitizedTitle)
            newFilename = "\(uniqued).md"
            let newFileURL = oldFileURL.deletingLastPathComponent().appendingPathComponent(newFilename)
            if FileManager.default.fileExists(atPath: oldFileURL.path) {
                try? FileManager.default.moveItem(at: oldFileURL, to: newFileURL)
            }
            notes[idx].title = uniqued
            // Update relativePath preserving the directory prefix
            if note.relativePath.contains("/") {
                let parentPath = (note.relativePath as NSString).deletingLastPathComponent
                notes[idx].relativePath = "\(parentPath)/\(newFilename)"
            } else {
                notes[idx].relativePath = newFilename
            }
        } else {
            newFilename = (note.relativePath as NSString).lastPathComponent
        }

        // Write content
        let fileURL = noteFileURL(for: notes[idx])
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)

        // Set file modification date to match remote timestamp
        try? FileManager.default.setAttributes(
            [.modificationDate: remoteUpdatedAt],
            ofItemAtPath: fileURL.path
        )

        notes[idx].content = content
        notes[idx].modifiedAt = remoteUpdatedAt
        notes[idx].folderID = folderID
        notes[idx].isPinned = isPinned

        // Invalidate caches
        contentCache.removeValue(forKey: noteID)

        // Update index
        index[noteID] = NoteIndexEntry(
            filename: newFilename,
            folderID: folderID,
            createdAt: notes[idx].createdAt,
            isPinned: isPinned ? true : nil
        )
        saveIndex()
    }

    /// Delete a note from a sync pull (remote deleted it).
    func deleteFromSync(_ note: Note) {
        contentCache.removeValue(forKey: note.id)
        let fileURL = noteFileURL(for: note)
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: snapshotDirectoryURL(for: note))
        index.removeValue(forKey: note.id)
        saveIndex()
        notes.removeAll { $0.id == note.id }
    }

    func restoreFromTrash(noteID: UUID, filename: String, folderID: UUID?, createdAt: Date) {
        index[noteID] = NoteIndexEntry(filename: filename, folderID: folderID, createdAt: createdAt)
        saveIndex()
        scanNotes()  // Picks up notes in Notes/ dir
        // Also load vault-folder notes that scanNotes() can't find
        if folderID != nil {
            loadVaultFolderNotes()
        }
        // Cancel pending sync deletion and push so the note reappears on web
        SyncService.shared.cancelNoteDeletion(of: noteID)
        SyncService.shared.pushAfterLocalChange()
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
        // Watch .cider/notes/ (metadata index + legacy notes)
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

        // Watch Inbox/Notes/ for external changes to unfiled notes
        let inboxDir = inboxNotesDirectoryURL
        let fm = FileManager.default
        if !fm.fileExists(atPath: inboxDir.path) {
            try? fm.createDirectory(at: inboxDir, withIntermediateDirectories: true)
        }
        let inboxFd = open(inboxDir.path, O_EVTONLY)
        guard inboxFd >= 0 else { return }
        inboxFileDescriptor = inboxFd

        let inboxSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: inboxFd,
            eventMask: .write,
            queue: .main
        )
        inboxSource.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.scanNotes()
            }
        }
        inboxSource.setCancelHandler {
            close(inboxFd)
        }
        inboxSource.resume()
        inboxDirectorySource = inboxSource
    }

    private func stopDirectoryWatcher() {
        directorySource?.cancel()
        directorySource = nil
        directoryFileDescriptor = -1
        inboxDirectorySource?.cancel()
        inboxDirectorySource = nil
        inboxFileDescriptor = -1
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
        let uniqueName = "\(UUID().uuidString)-\(filename)"
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
        return "\(base) \(UUID().uuidString.prefix(8))"
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
                guard let self else { return }
                let notePaths = self.notes.map { self.noteFileURL(for: $0) }
                let attachmentsDir = self.attachmentsDirectoryURL()
                let gracePeriod = self.orphanAttachmentGracePeriodSeconds
                Task.detached(priority: .background) {
                    Self.removeOrphanAttachmentsInBackground(
                        notePaths: notePaths,
                        attachmentsDir: attachmentsDir,
                        gracePeriodSeconds: gracePeriod
                    )
                }
            }
        }

        attachmentCleanupWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + attachmentCleanupDelaySeconds,
            execute: workItem
        )
    }

    private nonisolated static func removeOrphanAttachmentsInBackground(
        notePaths: [URL],
        attachmentsDir: URL,
        gracePeriodSeconds: TimeInterval
    ) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: attachmentsDir.path) else { return }

        guard let attachmentURLs = try? fm.contentsOfDirectory(
            at: attachmentsDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let referencedFiles = referencedAttachmentFilenamesFromPaths(notePaths)
        let orphanCutoff = Date().addingTimeInterval(-gracePeriodSeconds)

        for fileURL in attachmentURLs {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.contentModificationDateKey, .creationDateKey, .isRegularFileKey]
            ) else {
                continue
            }

            guard values.isRegularFile == true else { continue }
            let filename = fileURL.lastPathComponent
            guard !referencedFiles.contains(filename) else { continue }

            // CH-C05: Check both creation and modification date — a recently
            // created file must survive the grace period even if its mtime is old.
            let modifiedAt = values.contentModificationDate ?? .distantFuture
            let createdAt = values.creationDate ?? .distantFuture
            let newestDate = max(modifiedAt, createdAt)
            guard newestDate < orphanCutoff else { continue }

            try? fm.removeItem(at: fileURL)
        }
    }

    private nonisolated static func referencedAttachmentFilenamesFromPaths(_ notePaths: [URL]) -> Set<String> {
        // Matches relative: (.attachments/file) or (./\.attachments/file)
        // Also matches absolute file:// URLs: (file:///path/.attachments/file)
        let markdownReferencePattern = #"\((?:file:///[^)]*?/|(?:\./)?)?\.attachments/([^)]+)\)"#
        let htmlReferencePattern = #"(?:src|href)=["'](?:[^"']*?/)?\.attachments/([^"']+)["']"#

        let markdownRegex = try? NSRegularExpression(pattern: markdownReferencePattern, options: [])
        let htmlRegex = try? NSRegularExpression(pattern: htmlReferencePattern, options: [])

        var referenced = Set<String>()

        for noteURL in notePaths {
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

    private nonisolated static func extractAttachmentFilenames(
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
