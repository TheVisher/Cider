import AppKit
import Foundation
import Combine
import os.log

struct NoteSnapshotInfo: Identifiable, Hashable {
    let id: String
    let url: URL
    let modifiedAt: Date
}

struct NoteAttachmentReferenceScan: Equatable, Sendable {
    let referencedFilenames: Set<String>
    let unreadableNoteURLs: [URL]
}

/// Manages notes as .md files on disk with a lightweight JSON index for UUID mapping.
@MainActor
final class NotesStorage: ObservableObject {
    enum ImageTransactionStage: Hashable, Sendable {
        case beforeFileReplace
        case afterFileReplaceBeforeDatabase
        case insideCanonicalDatabasePersist
        case insideContentIndexRebuild
        case postPersistVerification
        case beforeCompensationRestore
    }

    struct ImageTransactionHooks {
        var atStage: (ImageTransactionStage) throws -> Void

        init(atStage: @escaping (ImageTransactionStage) throws -> Void = { _ in }) {
            self.atStage = atStage
        }
    }

    enum ImageTransactionPreviousFile: Equatable, Sendable {
        case missing
        case bytes(Data)
    }

    struct ImageTransactionFileExpectation: Equatable, Sendable {
        let noteID: UUID
        let fileURL: URL
        let previousFile: ImageTransactionPreviousFile
    }

    struct ImageTransactionPersistenceError: Error, Equatable, LocalizedError, Sendable {
        enum Outcome: Equatable, Sendable {
            case notCommitted
            case indeterminate
        }

        let outcome: Outcome

        var errorDescription: String? {
            switch outcome {
            case .notCommitted:
                "Cider could not commit the note image transaction. The prior note was restored."
            case .indeterminate:
                "Cider could not confirm recovery of the note image transaction. The prepared asset was retained."
            }
        }
    }

    static let shared = NotesStorage()

    @Published private(set) var notes: [Note] = []
    @Published private(set) var lastContentIOIssue: NoteContentIOIssue?

    private let logger = Logger(subsystem: "com.cider.app", category: "NotesStorage")

    // MARK: - Database

    /// Explicit database reference for testing. Production uses `CiderDatabase.shared`.
    private var database: CiderDatabase?
    private var directoryURL: URL
    private var vaultRootURLOverride: URL?
    private let imageTransactionHooks: ImageTransactionHooks
    private var directoryFileDescriptor: Int32 = -1
    private var directorySource: DispatchSourceFileSystemObject?
    private var inboxFileDescriptor: Int32 = -1
    private var inboxDirectorySource: DispatchSourceFileSystemObject?
    private var saveWorkItem: DispatchWorkItem?
    private var attachmentCleanupWorkItem: DispatchWorkItem?
    private var vaultFilesystemObserver: NSObjectProtocol?
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
        self.vaultRootURLOverride = nil
        self.imageTransactionHooks = .init()
        ensureDirectory()
        startDirectoryWatcher()
        startVaultFilesystemObservation()

        // Try SQLite first
        if let db = resolvedDatabase {
            loadNotesFromDatabase(db)
            if !notes.isEmpty {
                loadVaultFolderNotes()
                return
            }
        }

        let dirURL = directoryURL
        let idxURL = dirURL.appendingPathComponent(indexFileName)
        let idxName = indexFileName
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await Task.detached(priority: .userInitiated) {
                Self.loadAndScan(directoryURL: dirURL, indexURL: idxURL, indexFileName: idxName)
            }.value
            let scanIndex = result.index
            let scanNotes = result.notes
            self.index = scanIndex
            self.notes = scanNotes
            if result.needsSave || scanIndex != result.index { self.saveIndex() }
            // loadAndScan only walks .cider/notes and Inbox/Notes. Vault-folder
            // .md files that aren't already in the index (fresh installs,
            // externally dropped files) need explicit discovery against the
            // VaultFolderService index, which is guaranteed populated here
            // because AppDelegate force-inits VaultFolderService before any
            // content service touches .shared.
            self.discoverVaultFolderNoteFiles()
            self.loadVaultFolderNotes()

            // One-time migration: persist JSON notes to SQLite
            if !self.notes.isEmpty, let db = self.resolvedDatabase {
                self.logger.info("Migrating \(self.notes.count) notes from JSON to SQLite")
                do {
                    try db.withTransaction {
                        for note in self.notes {
                            try self.persistNoteToDatabaseInner(db, note: note)
                        }
                    }
                } catch {
                    self.logger.error("Failed to migrate JSON notes to SQLite: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Testing-only initializer with an explicit database.
    /// Does NOT call loadNotes() — tests call loadNotesFromDatabase() directly.
    init(
        database: CiderDatabase,
        notesDirectoryURL: URL? = nil,
        vaultRootURL: URL? = nil,
        imageTransactionHooks: ImageTransactionHooks = .init()
    ) {
        self.database = database
        self.directoryURL = (notesDirectoryURL ?? StoragePaths.directoryURL(for: .notes)).standardizedFileURL
        self.vaultRootURLOverride = vaultRootURL?.standardizedFileURL
        self.imageTransactionHooks = imageTransactionHooks
    }

    /// The base directory URL where notes metadata index is stored (.cider/notes/).
    var notesDirectoryURL: URL { directoryURL }

    /// The Inbox/Notes/ directory for unfiled note content files.
    private var inboxNotesDirectoryURL: URL {
        vaultRoot.appendingPathComponent(StoragePaths.inboxDir).appendingPathComponent("Notes")
    }

    /// The vault root directory.
    private var vaultRoot: URL { vaultRootURLOverride ?? StoragePaths.cachedVaultDirectoryURL }

    /// Resolves the absolute file URL for a note.
    /// Uses Note.absoluteFileURL which handles both Notes/-based and vault-folder-based paths.
    func noteFileURL(for note: Note) -> URL {
        if note.relativePath.contains("/") {
            return vaultRoot.appendingPathComponent(note.relativePath)
        }
        return directoryURL.appendingPathComponent(note.relativePath)
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

        // Try SQLite first (mirrors init pattern). loadNotesFromDatabase
        // rehydrates both `notes` and `index`.
        if let db = resolvedDatabase {
            loadNotesFromDatabase(db)
            if !notes.isEmpty {
                loadVaultFolderNotes()
                return
            }
        }

        // CH-C15: Load synchronously so callers see notes immediately after return.
        // Unlike init(), updateDirectory is user-triggered (rare) so brief main-thread
        // I/O is acceptable to avoid the async race that broke callers and tests.
        let result = Self.loadAndScan(
            directoryURL: directoryURL,
            indexURL: directoryURL.appendingPathComponent(indexFileName),
            indexFileName: indexFileName
        )
        let scanIndex = result.index
        let scanNotes = result.notes
        index = scanIndex
        notes = scanNotes
        if result.needsSave || scanIndex != result.index { saveIndex() }
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

    // Task 13: JSON index persistence removed. The in-memory `index` dict is
    // rebuilt on launch from SQLite (`loadNotesFromDatabase`) and from `.md`
    // scans (`scanNotes`/`loadAndScan`). Stubs are retained so older mutation
    // call sites stay put while SQLite-backed indexing remains canonical.
    private func saveIndex() { /* no-op */ }

    // MARK: - Scanning

    private nonisolated static func isRegularMarkdownFile(_ url: URL) -> Bool {
        guard url.pathExtension.localizedCaseInsensitiveCompare("md") == .orderedSame else { return false }
        return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    func scanNotes() {
        contentCache.removeAll()
        let fm = FileManager.default

        // Scan both .cider/notes/ (legacy) and Inbox/Notes/ for unfiled notes
        var allFiles: [(url: URL, relativePrefix: String?)] = []
        if let files = try? fm.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey, .isRegularFileKey]) {
            for f in files { allFiles.append((f, nil)) }
        }
        let inboxDir = inboxNotesDirectoryURL
        if let inboxFiles = try? fm.contentsOfDirectory(at: inboxDir, includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey, .isRegularFileKey]) {
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
        var idByRelativePath: [String: UUID] = [:]
        for note in notes {
            let key = Self.normalizedNoteRelativePath(note.relativePath)
            if !key.isEmpty, idByRelativePath[key] == nil {
                idByRelativePath[key] = note.id
            }
        }
        var scannedUUIDs = Set<UUID>()

        var scannedNotes: [Note] = []
        for (fileURL, relativePrefix) in allFiles {
            guard Self.isRegularMarkdownFile(fileURL) else { continue }
            let filename = fileURL.lastPathComponent
            guard filename != indexFileName else { continue }

            let title = String(filename.dropLast(3)) // Remove .md

            // Build relativePath: Inbox/Notes/file.md for inbox, plain filename for legacy .cider/notes/
            let relativePath: String
            if let prefix = relativePrefix {
                relativePath = "\(prefix)/\(filename)"
            } else {
                relativePath = filename
            }

            // Resolve UUID from the persisted note index when available.
            // If the index does not know about this file yet, assign a fresh ID
            // and persist it back into the index during this scan.
            let relativePathKey = Self.normalizedNoteRelativePath(relativePath)
            let matchedByPath = idByRelativePath[relativePathKey]
            var uuid = matchedByPath
                ?? itemIDFromExistingRelativePath(relativePath: relativePath)
                ?? filenameToUUID[filename]
                ?? UUID()
            if scannedUUIDs.contains(uuid), matchedByPath != uuid {
                uuid = UUID()
            }
            scannedUUIDs.insert(uuid)
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

            // Lazy: don't load content during scan
            scannedNotes.append(Note(
                id: uuid,
                title: title,
                content: "",
                summary: nil,
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
            guard let entryFolderID = entry.folderID else { continue }
            // Verify the file still exists on disk
            if let vaultFolder = VaultFolderService.shared.folder(for: entryFolderID) {
                let filePath = vaultRoot.appendingPathComponent(vaultFolder.relativePath)
                    .appendingPathComponent(entry.filename).path
                if Self.isRegularMarkdownFile(URL(fileURLWithPath: filePath)) {
                    rebuiltIndex[uuid] = entry
                    let fileAttrs = try? fm.attributesOfItem(atPath: filePath)
                    let modDate = (fileAttrs?[.modificationDate] as? Date) ?? Date()
                    scannedNotes.append(Note(
                        id: uuid,
                        title: String(entry.filename.dropLast(3)),
                        content: "",
                        summary: nil,
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

    /// Public rescan entry point for startup reconciliation.
    ///
    /// Re-reads all .md files from Notes directories (legacy .cider/notes/,
    /// Inbox/Notes/, and vault folders) and merges the result with the current
    /// in-memory state, then syncs the full result to SQLite so external
    /// filesystem changes made while the app was closed are picked up on
    /// launch.
    ///
    /// Idempotent and safe to call multiple times.
    func rescan() {
        let previousIDs = Set(notes.map(\.id))
        restoreMissingProjectArtifactFilesFromDatabaseBackedNotes()

        // 1. Rebuild Notes/Inbox state from disk. Also preserves already-indexed
        //    vault-folder notes that still exist on disk.
        scanNotes()

        // 2. Discover brand-new .md files dropped directly into vault folders
        //    while the app was closed. `scanNotes` only carries forward vault
        //    folder entries that were already in the index; it doesn't scan
        //    vault folder contents, so we do that here.
        discoverVaultFolderNoteFiles()

        // 3. Pick up already-indexed vault folder notes (in case step 2 added
        //    new index entries), plus file-backed project notes under project
        //    containers. Project notes do not belong to generic VaultFolderService
        //    folders, so they need an explicit scan path or startup reconcile will
        //    drop their SQLite item rows as "removed" while leaving files behind.
        loadVaultFolderNotes()
        discoverProjectNoteFiles()

        // 4. Hydrate scanned placeholders before duplicate repair. The scan
        // path deliberately avoids reading every file body until now; exact
        // duplicate detection needs the real content so distinct edited notes
        // with similar suffixed titles are preserved.
        guard let db = resolvedDatabase else {
            for i in notes.indices where notes[i].content.isEmpty {
                notes[i].content = loadContent(for: notes[i])
            }
            restoreProjectArtifactMetadataFromPaths()
            let canonicalized = canonicalizedScannedNotes(notes)
            deleteDuplicateNoteFiles(canonicalized.removedNotes)
            notes = canonicalized.notes.map { note in
                var restored = note
                restoreProjectArtifactMetadataFromPathIfNeeded(&restored)
                return restored
            }
            logProjectNoteBoundary(stage: "rescan-after-canonicalize")
            index = rebuiltNoteIndex(from: notes)
            return
        }
        let missingFileIDs = Set(notes.compactMap { note -> UUID? in
            guard note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return Self.isRegularMarkdownFile(noteFileURL(for: note)) ? nil : note.id
        })
        if !missingFileIDs.isEmpty {
            notes.removeAll { missingFileIDs.contains($0.id) }
        }

        for i in notes.indices {
            if notes[i].content.isEmpty {
                let diskContent = loadContent(for: notes[i])
                if !diskContent.isEmpty {
                    notes[i].content = diskContent
                }
            }
            if let existingTags = try? loadTags(db, itemID: notes[i].id), !existingTags.isEmpty {
                notes[i].tags = existingTags
            }
            if let existingSummary = try? loadSummary(db, itemID: notes[i].id),
               !existingSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               (notes[i].summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                notes[i].summary = existingSummary
            }
        }

        restoreProjectArtifactMetadataFromPaths()

        let canonicalized = canonicalizedScannedNotes(notes)
        deleteDuplicateNoteFiles(canonicalized.removedNotes)
        notes = canonicalized.notes.map { note in
            var restored = note
            restoreProjectArtifactMetadataFromPathIfNeeded(&restored)
            return restored
        }
        logProjectNoteBoundary(stage: "rescan-after-canonicalize")
        index = rebuiltNoteIndex(from: notes)

        // 5. Sync the full in-memory state to SQLite. Upsert everything we
        //    have now, and delete rows for notes that disappeared.
        //    `persistNoteToDatabaseInner` scrubs dangling folder_id references
        //    at the lowest level so a single stale reference can't abort the
        //    whole transaction.
        //
        //    IMPORTANT: the disk scan builds lightweight placeholders. Hydrate
        //    file content and DB-only fields before upsert so rescan cannot
        //    erase note bodies, tags, or summaries.
        let currentIDs = Set(notes.map(\.id))
        let staleMissingIDs = staleMissingNoteItemIDs(db, excluding: currentIDs)
        let removedIDs = previousIDs
            .subtracting(currentIDs)
            .union(Set(canonicalized.removedNotes.map(\.id)))
            .union(staleMissingIDs)
        do {
            try db.withTransaction {
                let stmt = try db.prepare("DELETE FROM items WHERE id = ?;")
                for removedID in removedIDs {
                    stmt.reset()
                    stmt.bind(DatabaseHelpers.encode(removedID), at: 1)
                    try stmt.step()
                }
                for note in self.notes {
                    try self.persistNoteToDatabaseInner(db, note: note)
                }
            }
            logger.info("Rescan synced \(self.notes.count, privacy: .public) notes to SQLite (removed \(removedIDs.count, privacy: .public); projectCiderNotes=\(self.projectArtifactNoteCount(projectID: "cider"), privacy: .public))")
        } catch {
            logger.error("Failed to sync rescan to SQLite: \(error.localizedDescription, privacy: .public)")
            contentCache.removeAll()
            loadNotesFromDatabase(db)
            return
        }

        let indexer = SecondBrainItemContentIndexingService(database: db)
        for note in notes {
            do {
                _ = try indexer.rebuild(owner: SecondBrainOwnerRef(ownerType: "note", ownerID: note.id.uuidString))
            } catch {
                logger.error("Failed to refresh note chunks after rescan for \(note.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func staleMissingNoteItemIDs(_ db: CiderDatabase, excluding currentIDs: Set<UUID>) -> Set<UUID> {
        do {
            let stmt = try db.prepare("""
                SELECT id, relative_path
                FROM items
                WHERE type = 'note'
                  AND relative_path IS NOT NULL
                  AND relative_path != '';
                """)
            var staleIDs = Set<UUID>()
            while try stmt.step() {
                guard let id = DatabaseHelpers.decodeUUID(stmt.string(at: 0)),
                      !currentIDs.contains(id) else { continue }
                let relativePath = stmt.string(at: 1)
                let fileURL = relativePath.contains("/")
                    ? vaultRoot.appendingPathComponent(relativePath)
                    : directoryURL.appendingPathComponent(relativePath)
                var isDirectory: ObjCBool = false
                if !FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) || isDirectory.boolValue {
                    staleIDs.insert(id)
                }
            }
            return staleIDs
        } catch {
            logger.error("Failed to inspect stale note item rows: \(error.localizedDescription)")
            return []
        }
    }

    private func restoreMissingProjectArtifactFilesFromDatabaseBackedNotes() {
        let fm = FileManager.default
        for note in notes where note.isProjectArtifact {
            guard note.relativePath.contains("/"),
                  !note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let fileURL = vaultRoot.appendingPathComponent(note.relativePath)
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    logger.error("Cannot restore project artifact note over directory: \(fileURL.path, privacy: .public)")
                }
                continue
            }

            do {
                try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try note.content.write(to: fileURL, atomically: true, encoding: .utf8)
                logger.info("Restored missing project artifact note file from SQLite: \(note.relativePath, privacy: .public)")
            } catch {
                logger.error("Failed to restore missing project artifact note file \(note.relativePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Scans every vault folder directory for .md files that aren't yet in the
    /// index, assigns fresh UUIDs, and adds corresponding entries to `index`
    /// and `notes`.
    private func discoverVaultFolderNoteFiles() {
        let fm = FileManager.default
        // Build a fast lookup of filenames already tracked per folder.
        var knownFolderFiles: Set<String> = []
        for entry in index.values {
            guard let fid = entry.folderID else { continue }
            knownFolderFiles.insert("\(fid.uuidString):\(entry.filename)")
        }

        var addedAny = false
        for folder in VaultFolderService.shared.folders {
            let folderDir = vaultRoot.appendingPathComponent(folder.relativePath)
            guard let files = try? fm.contentsOfDirectory(
                at: folderDir,
                includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey, .isRegularFileKey]
            ) else { continue }

            for file in files where Self.isRegularMarkdownFile(file) {
                let filename = file.lastPathComponent
                if knownFolderFiles.contains("\(folder.id.uuidString):\(filename)") { continue }

                let uuid = UUID()

                let attrs = try? fm.attributesOfItem(atPath: file.path)
                let modDate = attrs?[.modificationDate] as? Date ?? Date()
                let createDate = attrs?[.creationDate] as? Date ?? Date()

                index[uuid] = NoteIndexEntry(
                    filename: filename,
                    folderID: folder.id,
                    labelIDs: nil,
                    createdAt: createDate,
                    isPinned: nil
                )

                notes.append(Note(
                    id: uuid,
                    title: String(filename.dropLast(3)),
                    content: "",
                    summary: nil,
                    createdAt: createDate,
                    modifiedAt: modDate,
                    relativePath: "\(folder.relativePath)/\(filename)",
                    labelIDs: [],
                    folderID: folder.id,
                    isPinned: false
                ))
                addedAny = true
                logger.info("Rescan adopted vault-folder note: \(filename)")
            }
        }

        if addedAny {
            saveIndex()
            notes.sort { a, b in
                if a.isPinned != b.isPinned { return a.isPinned }
                return a.createdAt > b.createdAt
            }
        }
    }

    private func discoverProjectNoteFiles() {
        let fm = FileManager.default
        let projectsRoot = vaultRoot.appendingPathComponent("Projects", isDirectory: true)
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var knownRelativePaths = Set(notes.map { Self.normalizedNoteRelativePath($0.relativePath) })
        var addedAny = false
        for projectDir in projectDirs {
            guard (try? projectDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let projectID = SecondBrainProjectGraphService.normalizedProjectID(projectDir.lastPathComponent)
            guard !projectID.isEmpty else { continue }
            for artifactDirectory in Self.projectArtifactDirectories {
                let artifactDir = projectDir.appendingPathComponent(artifactDirectory.name, isDirectory: true)
                guard let files = try? fm.contentsOfDirectory(
                    at: artifactDir,
                    includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }

                for file in files where Self.isRegularMarkdownFile(file) {
                    let relativePath = "Projects/\(projectDir.lastPathComponent)/\(artifactDirectory.name)/\(file.lastPathComponent)"
                    let normalizedPath = Self.normalizedNoteRelativePath(relativePath)
                    guard !knownRelativePaths.contains(normalizedPath) else { continue }

                    let attrs = try? fm.attributesOfItem(atPath: file.path)
                    let modDate = attrs?[.modificationDate] as? Date ?? Date()
                    let createDate = attrs?[.creationDate] as? Date ?? modDate
                    let uuid = itemIDFromExistingRelativePath(relativePath: relativePath)
                        ?? noteIDFromExistingItem(relativePath: relativePath)
                        ?? projectNoteIDFromExistingRelation(relativePath: relativePath)
                        ?? UUID()
                    index[uuid] = NoteIndexEntry(filename: file.lastPathComponent, folderID: nil, createdAt: createDate)
                    notes.append(Note(
                        id: uuid,
                        title: String(file.lastPathComponent.dropLast(3)),
                        content: (try? String(contentsOf: file, encoding: .utf8)) ?? "",
                        summary: nil,
                        createdAt: createDate,
                        modifiedAt: modDate,
                        relativePath: relativePath,
                        labelIDs: [],
                        folderID: nil,
                        isPinned: false,
                        projectID: projectID,
                        artifactType: artifactDirectory.artifactType
                    ))
                    knownRelativePaths.insert(normalizedPath)
                    addedAny = true
                    logger.info("Rescan adopted project artifact note: \(relativePath, privacy: .public)")
                }
            }
        }

        if addedAny {
            saveIndex()
            notes.sort { a, b in
                if a.isPinned != b.isPinned { return a.isPinned }
                return a.createdAt > b.createdAt
            }
        }
    }

    private func projectNoteIDFromExistingRelation(relativePath: String) -> UUID? {
        guard let db = resolvedDatabase else { return nil }
        do {
            let stmt = try db.prepare("""
                SELECT source_owner_id, metadata
                FROM owner_relations
                WHERE source_owner_type = 'note'
                  AND target_owner_type = 'project'
                  AND relation_type = 'artifact_of';
                """)
            let normalizedPath = Self.normalizedNoteRelativePath(relativePath)
            while try stmt.step() {
                let metadata = DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 1)) ?? [:]
                guard Self.normalizedNoteRelativePath(metadata["path"] ?? "") == normalizedPath else { continue }
                if let id = DatabaseHelpers.decodeUUID(stmt.string(at: 0)) {
                    return id
                }
            }
        } catch {
            logger.error("Failed to inspect existing project note relations: \(error.localizedDescription)")
        }
        return nil
    }

    private func noteIDFromExistingItem(relativePath: String) -> UUID? {
        guard let db = resolvedDatabase else { return nil }
        do {
            let stmt = try db.prepare("""
                SELECT id
                FROM items
                WHERE type = 'note'
                  AND relative_path = ?
                LIMIT 1;
                """)
            stmt.bind(relativePath, at: 1)
            guard try stmt.step() else { return nil }
            return DatabaseHelpers.decodeUUID(stmt.string(at: 0))
        } catch {
            logger.error("Failed to inspect existing note item by relative path: \(error.localizedDescription)")
            return nil
        }
    }

    private func itemIDFromExistingRelativePath(relativePath: String) -> UUID? {
        guard let db = resolvedDatabase else { return nil }
        do {
            let stmt = try db.prepare("""
                SELECT id
                FROM items
                WHERE relative_path = ?
                LIMIT 1;
                """)
            stmt.bind(relativePath, at: 1)
            guard try stmt.step() else { return nil }
            return DatabaseHelpers.decodeUUID(stmt.string(at: 0))
        } catch {
            logger.error("Failed to inspect existing item by relative path: \(error.localizedDescription)")
            return nil
        }
    }

    private func removeDuplicateProjectNoteRelations(relativePath: String, keeping keptID: UUID) {
        do {
            try removeDuplicateProjectNoteRelationsThrowing(relativePath: relativePath, keeping: keptID)
        } catch {
            logger.error("Failed to remove duplicate project note relations: \(error.localizedDescription)")
        }
    }

    private func removeDuplicateProjectNoteRelationsThrowing(relativePath: String, keeping keptID: UUID) throws {
        guard let db = resolvedDatabase else { return }
        let keptOwnerID = DatabaseHelpers.encode(keptID)
        let normalizedPath = Self.normalizedNoteRelativePath(relativePath)
        let select = try db.prepare("""
            SELECT id, source_owner_id, metadata
            FROM owner_relations
            WHERE source_owner_type = 'note'
              AND target_owner_type = 'project'
              AND relation_type = 'artifact_of';
            """)
        var duplicateIDs: [String] = []
        while try select.step() {
            let metadata = DatabaseHelpers.decodeJSON([String: String].self, from: select.optionalString(at: 2)) ?? [:]
            guard Self.normalizedNoteRelativePath(metadata["path"] ?? "") == normalizedPath else { continue }
            guard select.string(at: 1) != keptOwnerID else { continue }
            duplicateIDs.append(select.string(at: 0))
        }
        for relationID in duplicateIDs {
            let delete = try db.prepare("DELETE FROM owner_relations WHERE id = ?;")
            delete.bind(relationID, at: 1)
            try delete.step()
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
            guard Self.isRegularMarkdownFile(filePath) else { continue }

            let attrs = try? fm.attributesOfItem(atPath: filePath.path)
            let modDate = attrs?[.modificationDate] as? Date ?? Date()

            notes.append(Note(
                id: uuid,
                title: String(entry.filename.dropLast(3)),
                content: "",
                summary: nil,
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

    /// Pure, background-safe scan of `.md` files on disk.
    private nonisolated static func loadAndScan(
        directoryURL: URL,
        indexURL: URL,
        indexFileName: String
    ) -> (index: [UUID: NoteIndexEntry], notes: [Note], needsSave: Bool) {
        let loadedIndex: [UUID: NoteIndexEntry] = [:]

        // Scan both .cider/notes/ (legacy) and Inbox/Notes/ for unfiled notes
        let fm = FileManager.default
        var allFiles: [(url: URL, relativePrefix: String?)] = []
        if let files = try? fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey, .isRegularFileKey]
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
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey, .isRegularFileKey]
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
            guard Self.isRegularMarkdownFile(fileURL) else { continue }
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

    func createNew(initialContent: String = "") -> Note {
        let title = uniqueTitle("Untitled")
        let filename = "\(title).md"
        let inboxDir = inboxNotesDirectoryURL
        let fileURL = inboxDir.appendingPathComponent(filename)
        let uuid = UUID()
        let now = Date()

        // Ensure Inbox/Notes/ exists
        try? FileManager.default.createDirectory(at: inboxDir, withIntermediateDirectories: true)

        // Write initial content to Inbox/Notes/
        try? initialContent.write(to: fileURL, atomically: true, encoding: .utf8)

        let inboxRelativePath = "\(StoragePaths.inboxDir)/Notes/\(filename)"
        index[uuid] = NoteIndexEntry(filename: filename, folderID: nil, createdAt: now)
        saveIndex()

        let note = Note(id: uuid, title: title, content: initialContent, createdAt: now, modifiedAt: now, relativePath: inboxRelativePath)
        notes.insert(note, at: 0)
        persistNoteToDatabase(note)
        MutationAuditService.shared.record(
            action: "create",
            itemType: "note",
            itemID: note.id,
            after: MutationAuditSnapshots.note(note)
        )
        return note
    }

    /// Create a Markdown-backed project artifact under `Projects/<Project>/<Artifact Folder>/` and
    /// register explicit project ownership in SQLite via owner_relations.
    func createProjectNote(
        projectID rawProjectID: String,
        title rawTitle: String,
        content: String = "",
        artifactType rawArtifactType: String = "note"
    ) -> Note {
        let projectID = SecondBrainProjectGraphService.normalizedProjectID(rawProjectID)
        let artifactType = rawArtifactType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "note"
            : rawArtifactType.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        let baseTitle = sanitizedNoteTitle(rawTitle).isEmpty ? "Untitled" : sanitizedNoteTitle(rawTitle)
        let projectDirName = projectDirectoryName(for: projectID)
        let artifactDirectoryName = Self.projectArtifactDirectoryName(for: artifactType)
        let notesDir = vaultRoot
            .appendingPathComponent("Projects", isDirectory: true)
            .appendingPathComponent(projectDirName, isDirectory: true)
            .appendingPathComponent(artifactDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)

        let filename = uniqueFilename(baseTitle: baseTitle, in: notesDir)
        let fileURL = notesDir.appendingPathComponent(filename)
        let uuid = UUID()
        let now = Date()
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)

        let relativePath = "Projects/\(projectDirName)/\(artifactDirectoryName)/\(filename)"
        index[uuid] = NoteIndexEntry(filename: filename, folderID: nil, createdAt: now)
        saveIndex()

        let note = Note(
            id: uuid,
            title: String(filename.dropLast(3)),
            content: content,
            createdAt: now,
            modifiedAt: now,
            relativePath: relativePath,
            projectID: projectID,
            artifactType: artifactType
        )
        notes.insert(note, at: 0)
        persistNoteToDatabase(note)
        MutationAuditService.shared.record(
            action: "create",
            itemType: "note",
            itemID: note.id,
            after: MutationAuditSnapshots.note(note),
            metadata: ["projectID": projectID, "artifactType": artifactType]
        )
        return note
    }

    /// Ensure the narrow MVP has one real, visible Cider project note to render.
    /// Idempotent: if any `project:cider` note artifact already exists, returns it;
    /// if the seed Markdown exists on disk but lacks DB ownership, registers it.
    @discardableResult
    func ensureCiderProjectNoteSeedIfNeeded() -> Note? {
        let projectID = "cider"
        ensureProjectContainerDirectories(projectID: projectID)

        if let existing = notes.first(where: { note in
            SecondBrainProjectGraphService.normalizedProjectID(note.projectID ?? "") == projectID
                && (note.artifactType?.localizedLowercase == "note" || note.artifactType == nil)
        }) {
            removeDuplicateProjectNoteRelations(relativePath: existing.relativePath, keeping: existing.id)
            return existing
        }

        let title = "Cider Project Notes"
        let relativePath = "Projects/Cider/Notes/\(title).md"
        if let existingIndex = notes.firstIndex(where: { Self.normalizedNoteRelativePath($0.relativePath) == Self.normalizedNoteRelativePath(relativePath) }) {
            notes[existingIndex].projectID = projectID
            notes[existingIndex].artifactType = "note"
            persistNoteToDatabase(notes[existingIndex])
            removeDuplicateProjectNoteRelations(relativePath: relativePath, keeping: notes[existingIndex].id)
            return notes[existingIndex]
        }

        let seedContent = """
        # Cider Project Notes

        This is Cider's first file-backed project note. It lives under `Projects/Cider/Notes` so project notes can be developed and dogfooded without polluting ordinary Library Notes.

        SQLite records this file as a note artifact owned by `project:cider`; the Markdown file remains the canonical body.
        """
        let seedURL = vaultRoot.appendingPathComponent(relativePath)
        if FileManager.default.fileExists(atPath: seedURL.path) {
            let content = (try? String(contentsOf: seedURL, encoding: .utf8)) ?? seedContent
            let now = Date()
            let noteID = projectNoteIDFromExistingRelation(relativePath: relativePath) ?? UUID()
            let note = Note(
                id: noteID,
                title: title,
                content: content,
                createdAt: now,
                modifiedAt: now,
                relativePath: relativePath,
                projectID: projectID,
                artifactType: "note"
            )
            index[note.id] = NoteIndexEntry(filename: "\(title).md", folderID: nil, createdAt: now)
            notes.insert(note, at: 0)
            persistNoteToDatabase(note)
            removeDuplicateProjectNoteRelations(relativePath: relativePath, keeping: note.id)
            MutationAuditService.shared.record(
                action: "register",
                itemType: "note",
                itemID: note.id,
                after: MutationAuditSnapshots.note(note),
                metadata: ["projectID": projectID, "artifactType": "note", "seed": "cider-project-notes"]
            )
            return note
        }

        return createProjectNote(projectID: projectID, title: title, content: seedContent)
    }

    private func ensureProjectContainerDirectories(projectID: String) {
        let projectDirName = projectDirectoryName(for: projectID)
        let root = vaultRoot
            .appendingPathComponent("Projects", isDirectory: true)
            .appendingPathComponent(projectDirName, isDirectory: true)
        for child in Self.projectArtifactDirectories.map(\.name) + ["Assets"] {
            try? FileManager.default.createDirectory(
                at: root.appendingPathComponent(child, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
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

        // Save screenshot to Attachments if provided.
        // Use the inbox note's directory as the base so the relative .attachments/ path
        // resolves correctly when the editor loads the note.
        var screenshotFilename: String?
        if let image = screenshot,
           let pngData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: pngData),
           let png = bitmap.representation(using: .png, properties: [:]) {
            let attachmentsDir = inboxDir.appendingPathComponent(attachmentsDirectoryName, isDirectory: true)
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
        persistNoteToDatabase(note)
        MutationAuditService.shared.record(
            action: "create",
            itemType: "note",
            itemID: note.id,
            after: MutationAuditSnapshots.note(note),
            metadata: sourceURL.map { ["sourceURL": $0] }
        )
        return note
    }

    func loadContentResult(for note: Note) -> NoteContentResult {
        if let cached = contentCache[note.id], cached.modifiedAt == note.modifiedAt {
            return .success(cached.content)
        }
        let fileURL = noteFileURL(for: note)
        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            contentCache[note.id] = (note.modifiedAt, content)
            lastContentIOIssue = nil
            return .success(content)
        } catch {
            let issue = NoteContentIOIssue(
                noteID: note.id,
                relativePath: note.relativePath,
                fileURL: fileURL,
                operation: .read,
                error: error
            )
            lastContentIOIssue = issue
            logger.error("Failed to read note content at \(fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failure(issue)
        }
    }

    func loadContent(for note: Note) -> String {
        if let content = loadContentResult(for: note).content {
            return content
        }
        return note.content
    }

    /// Convert stored markdown to editor-friendly markdown (absolute image paths).
    func markdownForEditor(_ markdown: String) -> String {
        NotesMarkdownPathCodec.markdownForEditor(markdown, notesDirectoryURL: directoryURL)
    }

    /// Convert stored markdown to editor-friendly markdown, using the note's actual directory
    /// as the base. Required for inbox notes whose .attachments/ live in Inbox/Notes/.
    func markdownForEditor(_ markdown: String, note: Note) -> String {
        let noteDir = note.absoluteFileURL.deletingLastPathComponent()
        return NotesMarkdownPathCodec.markdownForEditor(markdown, notesDirectoryURL: noteDir)
    }

    /// Convert editor markdown to portable markdown (relative image paths).
    func markdownForPersistence(_ markdown: String) -> String {
        NotesMarkdownPathCodec.markdownForPersistence(markdown, notesDirectoryURL: directoryURL)
    }

    /// Convert editor markdown to portable markdown, using the note's actual directory.
    func markdownForPersistence(_ markdown: String, note: Note) -> String {
        let noteDir = note.absoluteFileURL.deletingLastPathComponent()
        return NotesMarkdownPathCodec.markdownForPersistence(markdown, notesDirectoryURL: noteDir)
    }

    /// Throwing, compensating persistence boundary used only by the editor image
    /// transaction. The prior file identity is caller-supplied from the editor's
    /// exact disk-truth snapshot; canonical SQLite state and searchable chunks
    /// commit together, and observable in-memory state is published last.
    @discardableResult
    func persistImageTransaction(
        note: Note,
        expected: ImageTransactionFileExpectation
    ) throws -> Note {
        guard expected.noteID == note.id,
              expected.fileURL.standardizedFileURL == noteFileURL(for: note).standardizedFileURL,
              let db = resolvedDatabase,
              let noteIndex = notes.firstIndex(where: { $0.id == note.id }) else {
            throw ImageTransactionPersistenceError(outcome: .notCommitted)
        }

        let fileURL = expected.fileURL.standardizedFileURL
        let previousNote = notes[noteIndex]
        let previousCache = contentCache[note.id]
        let previousIOIssue = lastContentIOIssue
        let parentURL = fileURL.deletingLastPathComponent()
        let parentExisted = FileManager.default.fileExists(atPath: parentURL.path)

        guard currentImageTransactionFileState(at: fileURL) == expected.previousFile else {
            throw ImageTransactionPersistenceError(outcome: .notCommitted)
        }

        var replacementMayHaveChangedDisk = false
        do {
            try imageTransactionHooks.atStage(.beforeFileReplace)
            guard currentImageTransactionFileState(at: fileURL) == expected.previousFile else {
                throw ImageTransactionPersistenceError(outcome: .notCommitted)
            }
            try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
            replacementMayHaveChangedDisk = true
            try Data(note.content.utf8).write(to: fileURL, options: .atomic)
            guard currentImageTransactionFileState(at: fileURL) == .bytes(Data(note.content.utf8)) else {
                throw ImageTransactionPersistenceError(outcome: .notCommitted)
            }
            try imageTransactionHooks.atStage(.afterFileReplaceBeforeDatabase)

            var committedNote = note
            committedNote.modifiedAt = Date()
            try db.withTransaction {
                try persistNoteToDatabaseInner(db, note: committedNote, failOnProjectRelationCleanupError: true)
                try imageTransactionHooks.atStage(.insideCanonicalDatabasePersist)
                let indexResult = try SecondBrainItemContentIndexingService(database: db).rebuild(
                    owner: SecondBrainOwnerRef(ownerType: "note", ownerID: note.id.uuidString)
                )
                try imageTransactionHooks.atStage(.insideContentIndexRebuild)
                try imageTransactionHooks.atStage(.postPersistVerification)
                try verifyImageTransactionPersistence(
                    db,
                    note: committedNote,
                    fileURL: fileURL,
                    indexResult: indexResult
                )
            }

            notes[noteIndex] = committedNote
            contentCache[note.id] = (committedNote.modifiedAt, committedNote.content)
            lastContentIOIssue = nil
            if expected.previousFile != .bytes(Data(note.content.utf8)) {
                scheduleAttachmentCleanup()
            }
            return committedNote
        } catch let error as ImageTransactionPersistenceError where !replacementMayHaveChangedDisk {
            throw error
        } catch {
            notes[noteIndex] = previousNote
            if let previousCache {
                contentCache[note.id] = previousCache
            } else {
                contentCache.removeValue(forKey: note.id)
            }
            lastContentIOIssue = previousIOIssue

            let currentFileState = currentImageTransactionFileState(at: fileURL)
            if currentFileState == expected.previousFile {
                if !parentExisted,
                   (try? FileManager.default.contentsOfDirectory(atPath: parentURL.path).isEmpty) == true {
                    try? FileManager.default.removeItem(at: parentURL)
                }
                throw ImageTransactionPersistenceError(outcome: .notCommitted)
            }
            guard currentFileState == .bytes(Data(note.content.utf8)) else {
                throw ImageTransactionPersistenceError(outcome: .indeterminate)
            }

            do {
                try imageTransactionHooks.atStage(.beforeCompensationRestore)
                try restoreImageTransactionFile(expected.previousFile, at: fileURL)
                guard currentImageTransactionFileState(at: fileURL) == expected.previousFile else {
                    throw ImageTransactionPersistenceError(outcome: .indeterminate)
                }
                if !parentExisted,
                   (try? FileManager.default.contentsOfDirectory(atPath: parentURL.path).isEmpty) == true {
                    try? FileManager.default.removeItem(at: parentURL)
                }
                throw ImageTransactionPersistenceError(outcome: .notCommitted)
            } catch let persistenceError as ImageTransactionPersistenceError {
                throw persistenceError
            } catch {
                throw ImageTransactionPersistenceError(outcome: .indeterminate)
            }
        }
    }

    private func currentImageTransactionFileState(at fileURL: URL) -> ImageTransactionPreviousFile {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let bytes = try? Data(contentsOf: fileURL) else {
            return .missing
        }
        return .bytes(bytes)
    }

    private func restoreImageTransactionFile(
        _ previous: ImageTransactionPreviousFile,
        at fileURL: URL
    ) throws {
        switch previous {
        case .missing:
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        case .bytes(let bytes):
            try bytes.write(to: fileURL, options: .atomic)
        }
    }

    private func verifyImageTransactionPersistence(
        _ db: CiderDatabase,
        note: Note,
        fileURL: URL,
        indexResult: SecondBrainItemContentIndexResult
    ) throws {
        guard currentImageTransactionFileState(at: fileURL) == .bytes(Data(note.content.utf8)) else {
            throw ImageTransactionPersistenceError(outcome: .notCommitted)
        }

        let item = try db.prepare("""
            SELECT i.title, i.created_at, i.updated_at, i.folder_id, i.relative_path,
                   n.content, n.summary, n.is_pinned
            FROM items i JOIN notes n ON n.item_id = i.id
            WHERE i.id = ? AND i.type = 'note';
            """)
        item.bind(DatabaseHelpers.encode(note.id), at: 1)
        let expectedFolderID = try resolveSafeFolderID(db, folderID: note.folderID)
        guard try item.step(),
              item.string(at: 0) == note.title,
              item.optionalString(at: 3) == expectedFolderID,
              (item.optionalString(at: 4) ?? "") == note.relativePath,
              item.string(at: 5) == note.content,
              item.optionalString(at: 6) == note.summary,
              item.bool(at: 7) == note.isPinned else {
            throw ImageTransactionPersistenceError(outcome: .notCommitted)
        }

        let expectedLabels = Set(try existingLabelIDs(db, candidates: note.labelIDs))
        guard Set(try loadLabelIDs(db, itemID: note.id)) == expectedLabels,
              Set(try loadTags(db, itemID: note.id)) == Set(note.tags),
              indexResult.chunkCount == 1 else {
            throw ImageTransactionPersistenceError(outcome: .notCommitted)
        }

        let chunks = try db.prepare("SELECT body FROM content_chunks WHERE owner_type = 'note' AND owner_id = ? ORDER BY chunk_index;")
        chunks.bind(note.id.uuidString, at: 1)
        var chunkBodies: [String] = []
        while try chunks.step() { chunkBodies.append(chunks.string(at: 0)) }
        guard chunkBodies.count == indexResult.chunkCount,
              chunkBodies.count == 1,
              chunkBodies[0].contains(note.content) else {
            throw ImageTransactionPersistenceError(outcome: .notCommitted)
        }

        if note.isProjectArtifact {
            let relation = try db.prepare("""
                SELECT COUNT(*) FROM owner_relations
                WHERE source_owner_type = 'note' AND source_owner_id = ?
                  AND target_owner_type = 'project' AND relation_type = 'artifact_of'
                  AND source = 'project_notes';
                """)
            relation.bind(note.id.uuidString, at: 1)
            guard try relation.step(), relation.int(at: 0) == 1 else {
                throw ImageTransactionPersistenceError(outcome: .notCommitted)
            }
        }
    }

    private func existingLabelIDs(_ db: CiderDatabase, candidates: [UUID]) throws -> [UUID] {
        let statement = try db.prepare("SELECT 1 FROM labels WHERE id = ? LIMIT 1;")
        var result: [UUID] = []
        for candidate in candidates {
            statement.reset()
            statement.bind(DatabaseHelpers.encode(candidate), at: 1)
            if try statement.step() { result.append(candidate) }
        }
        return result
    }

    var hasPendingAttachmentCleanupForTesting: Bool { attachmentCleanupWorkItem != nil }

    func cachedContentForTesting(noteID: UUID) -> String? { contentCache[noteID]?.content }

    @discardableResult
    func save(note: Note, createSnapshot: Bool = true) -> Bool {
        let fileURL = noteFileURL(for: note)
        let previousContent: String
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                previousContent = try String(contentsOf: fileURL, encoding: .utf8)
            } catch {
                let issue = NoteContentIOIssue(
                    noteID: note.id,
                    relativePath: note.relativePath,
                    fileURL: fileURL,
                    operation: .read,
                    error: error
                )
                lastContentIOIssue = issue
                logger.error("Refusing to save note after unreadable previous content at \(fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return false
            }
        } else {
            previousContent = ""
        }

        if createSnapshot, previousContent != note.content {
            saveSnapshot(content: previousContent, for: note)
        }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try note.content.write(to: fileURL, atomically: true, encoding: .utf8)
            lastContentIOIssue = nil
        } catch {
            let issue = NoteContentIOIssue(
                noteID: note.id,
                relativePath: note.relativePath,
                fileURL: fileURL,
                operation: .write,
                error: error
            )
            lastContentIOIssue = issue
            logger.error("Failed to write note content at \(fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }

        if previousContent != note.content {
            scheduleAttachmentCleanup()
        }

        // Invalidate content cache for this note
        contentCache.removeValue(forKey: note.id)

        // Update in-memory list
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx].modifiedAt = Date()
            notes[idx].content = note.content
            persistNoteToDatabase(notes[idx])
        }
        return true
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
        let before = MutationAuditSnapshots.note(note)
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
            contentCache.removeValue(forKey: note.id)

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
                persistNoteToDatabase(notes[idx])
                MutationAuditService.shared.record(
                    action: "rename",
                    itemType: "note",
                    itemID: note.id,
                    before: before,
                    after: MutationAuditSnapshots.note(notes[idx])
                )
            }
            SyncService.shared.pushAfterLocalChange()
        } catch {
            logger.error("Rename failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult
    func togglePin(_ noteID: UUID) -> Bool {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return false }
        let before = MutationAuditSnapshots.note(notes[idx])
        notes[idx].isPinned.toggle()
        notes[idx].modifiedAt = Date()
        if var entry = index[noteID] {
            entry.isPinned = notes[idx].isPinned ? true : nil
            index[noteID] = entry
        }
        // Re-sort so pinned notes appear at the top immediately
        notes.sort { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.createdAt > b.createdAt
        }
        saveIndex()
        if let pinnedNote = notes.first(where: { $0.id == noteID }) {
            persistNoteToDatabase(pinnedNote)
            MutationAuditService(database: resolvedDatabase).record(
                action: "toggle_pin",
                itemType: "note",
                itemID: noteID,
                before: before,
                after: MutationAuditSnapshots.note(pinnedNote)
            )
        }
        SyncService.shared.pushAfterLocalChange()
        return true
    }

    @discardableResult
    func assignNote(_ noteID: UUID, toFolder folderID: UUID?) -> Bool {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return false }
        if notes[idx].folderID == folderID {
            let projectMetadata = Self.projectArtifactMetadata(forRelativePath: notes[idx].relativePath)
            if notes[idx].projectID != projectMetadata?.projectID || notes[idx].artifactType != projectMetadata?.artifactType {
                notes[idx].projectID = projectMetadata?.projectID
                notes[idx].artifactType = projectMetadata?.artifactType
                persistNoteToDatabase(notes[idx])
            }
            return true
        }

        let note = notes[idx]
        let before = MutationAuditSnapshots.note(note)
        let filename = (note.relativePath as NSString).lastPathComponent
        let oldFileURL = noteFileURL(for: note)

        // Determine the new directory: vault folder or Inbox/Notes/
        let newDirURL: URL
        if let folderID, let vaultFolder = VaultFolderService.shared.folder(for: folderID) {
            newDirURL = vaultRoot.appendingPathComponent(vaultFolder.relativePath)
        } else {
            newDirURL = inboxNotesDirectoryURL
        }

        var newFileURL = newDirURL.appendingPathComponent(filename)

        // Handle filename collision at destination
        if FileManager.default.fileExists(atPath: newFileURL.path), oldFileURL != newFileURL {
            let base = (filename as NSString).deletingPathExtension
            let ext = (filename as NSString).pathExtension
            var counter = 2
            while FileManager.default.fileExists(atPath: newFileURL.path) {
                newFileURL = newDirURL.appendingPathComponent("\(base) (\(counter)).\(ext)")
                counter += 1
            }
        }

        // Physically move the file if source and destination differ
        if oldFileURL != newFileURL {
            let fm = FileManager.default
            // Ensure destination directory exists
            try? fm.createDirectory(at: newDirURL, withIntermediateDirectories: true)
            do {
                try fm.moveItem(at: oldFileURL, to: newFileURL)
            } catch {
                logger.error("Failed to move note file: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }

        // Recalculate relative path using the final filename (may differ after collision-rename)
        let finalFilename = newFileURL.lastPathComponent
        let finalRelativePath: String
        if let folderID, let vaultFolder = VaultFolderService.shared.folder(for: folderID) {
            finalRelativePath = "\(vaultFolder.relativePath)/\(finalFilename)"
        } else {
            finalRelativePath = "\(StoragePaths.inboxDir)/Notes/\(finalFilename)"
        }

        let projectMetadata = Self.projectArtifactMetadata(forRelativePath: finalRelativePath)
        notes[idx].folderID = folderID
        notes[idx].relativePath = finalRelativePath
        notes[idx].projectID = projectMetadata?.projectID
        notes[idx].artifactType = projectMetadata?.artifactType
        notes[idx].modifiedAt = Date()
        contentCache.removeValue(forKey: noteID)

        if var entry = index[noteID] {
            entry.folderID = folderID
            entry.filename = finalFilename
            index[noteID] = entry
        }
        saveIndex()
        persistNoteToDatabase(notes[idx])
        MutationAuditService.shared.record(
            action: "reassign_folder",
            itemType: "note",
            itemID: noteID,
            before: before,
            after: MutationAuditSnapshots.note(notes[idx])
        )
        SyncService.shared.pushAfterLocalChange()
        return true
    }

    @discardableResult
    func assignLabel(_ noteID: UUID, labelID: UUID) -> Bool {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return false }
        guard !notes[idx].labelIDs.contains(labelID) else { return true }
        let before = MutationAuditSnapshots.note(notes[idx])
        notes[idx].labelIDs.append(labelID)
        if var entry = index[noteID] {
            entry.labelIDs = notes[idx].labelIDs
            index[noteID] = entry
        }
        saveIndex()
        persistNoteToDatabase(notes[idx])
        MutationAuditService.shared.record(
            action: "assign_label",
            itemType: "note",
            itemID: noteID,
            before: before,
            after: MutationAuditSnapshots.note(notes[idx]),
            metadata: ["labelID": labelID.uuidString]
        )
        return true
    }

    @discardableResult
    func removeLabel(_ noteID: UUID, labelID: UUID) -> Bool {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return false }
        guard notes[idx].labelIDs.contains(labelID) else { return true }
        let before = MutationAuditSnapshots.note(notes[idx])
        notes[idx].labelIDs.removeAll { $0 == labelID }
        if var entry = index[noteID] {
            entry.labelIDs = notes[idx].labelIDs
            index[noteID] = entry
        }
        saveIndex()
        persistNoteToDatabase(notes[idx])
        MutationAuditService.shared.record(
            action: "remove_label",
            itemType: "note",
            itemID: noteID,
            before: before,
            after: MutationAuditSnapshots.note(notes[idx]),
            metadata: ["labelID": labelID.uuidString]
        )
        return true
    }

    /// Add a free-text tag to a note. Returns true if added (or already
    /// present), false if the note isn't found.
    @discardableResult
    func addTag(_ noteID: UUID, tag: String) -> Bool {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return false }
        if notes[idx].tags.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return true
        }
        let before = MutationAuditSnapshots.note(notes[idx])
        notes[idx].tags.append(trimmed)
        notes[idx].modifiedAt = Date()
        persistNoteToDatabase(notes[idx])
        MutationAuditService(database: resolvedDatabase).record(
            action: "add_tag",
            itemType: "note",
            itemID: noteID,
            before: before,
            after: MutationAuditSnapshots.note(notes[idx]),
            metadata: ["tag": trimmed]
        )
        return true
    }

    /// Remove a free-text tag from a note (case-insensitive match). Returns
    /// true if removed, false if the note isn't found or the tag wasn't set.
    @discardableResult
    func removeTag(_ noteID: UUID, tag: String) -> Bool {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return false }
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let before = notes[idx].tags.count
        let beforeSnapshot = MutationAuditSnapshots.note(notes[idx])
        notes[idx].tags.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        guard notes[idx].tags.count != before else { return false }
        notes[idx].modifiedAt = Date()
        persistNoteToDatabase(notes[idx])
        MutationAuditService(database: resolvedDatabase).record(
            action: "remove_tag",
            itemType: "note",
            itemID: noteID,
            before: beforeSnapshot,
            after: MutationAuditSnapshots.note(notes[idx]),
            metadata: ["tag": trimmed]
        )
        return true
    }

    func removeLabelsFromAll(labelID: UUID) {
        var changed = false
        var affectedNotes: [Note] = []
        for i in notes.indices where notes[i].labelIDs.contains(labelID) {
            notes[i].labelIDs.removeAll { $0 == labelID }
            if var entry = index[notes[i].id] {
                entry.labelIDs = notes[i].labelIDs
                index[notes[i].id] = entry
            }
            affectedNotes.append(notes[i])
            changed = true
        }
        if changed {
            saveIndex()
            if let db = resolvedDatabase {
                do {
                    try db.withTransaction {
                        for note in affectedNotes {
                            try persistNoteToDatabaseInner(db, note: note)
                        }
                    }
                } catch {
                    logger.error("Failed to persist notes after label removal: \(error.localizedDescription)")
                }
            }
        }
    }

    @discardableResult
    func delete(note: Note, trackSync: Bool = true) -> TrashItem {
        let before = MutationAuditSnapshots.note(note)
        contentCache.removeValue(forKey: note.id)

        // For notes in vault/Inbox folders, move the file to Inbox/Notes/ first so trash works correctly
        var noteForTrash = note
        var trashNotesDir = inboxNotesDirectoryURL
        if note.relativePath.contains("/") {
            let filename = (note.relativePath as NSString).lastPathComponent
            let vaultFileURL = noteFileURL(for: note)
            let inboxFileURL = trashNotesDir.appendingPathComponent(filename)
            var moveSucceeded = false
            if FileManager.default.fileExists(atPath: vaultFileURL.path) {
                try? FileManager.default.createDirectory(at: trashNotesDir, withIntermediateDirectories: true)
                do {
                    try FileManager.default.moveItem(at: vaultFileURL, to: inboxFileURL)
                    moveSucceeded = true
                } catch {
                    os.Logger(subsystem: "com.cider", category: "NotesStorage")
                        .error("Failed to move note to Inbox before trash: \(error.localizedDescription)")
                }
            }
            if moveSucceeded {
                noteForTrash = Note(
                    id: note.id, title: note.title, content: note.content, summary: note.summary,
                    createdAt: note.createdAt, modifiedAt: note.modifiedAt,
                    relativePath: "\(StoragePaths.inboxDir)/Notes/\(filename)", labelIDs: note.labelIDs,
                    folderID: note.folderID, isPinned: note.isPinned, tags: note.tags
                )
            } else {
                // Move failed — trash from the original location instead
                trashNotesDir = vaultFileURL.deletingLastPathComponent()
            }
        }
        let trashItem = TrashStorage.shared.trashNote(noteForTrash, notesDir: trashNotesDir)
        try? FileManager.default.removeItem(at: snapshotDirectoryURL(for: note))
        deleteNoteFromDatabase(note.id)
        index.removeValue(forKey: note.id)
        saveIndex()
        notes.removeAll { $0.id == note.id }
        scheduleAttachmentCleanup()

        // Track deletion for sync (skip if this deletion originated from sync)
        if trackSync {
            let config = CiderConfig.load()
            if config.syncEnabled {
                SyncService.shared.trackNoteDeletion(of: note.id)
            }
        }

        MutationAuditService.shared.record(
            action: "delete",
            itemType: "note",
            itemID: note.id,
            before: before,
            after: MutationAuditSnapshots.trashItem(trashItem)
        )

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
        tags: [String],
        createdAt: Date,
        updatedAt: Date
    ) {
        let sanitizedTitle = title.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let safeTitle = sanitizedTitle.isEmpty ? "Untitled" : sanitizedTitle

        if let duplicateIndex = exactDuplicateNoteIndex(title: safeTitle, content: content) {
            mergeExactDuplicateFromSync(
                at: duplicateIndex,
                content: content,
                isPinned: isPinned,
                tags: tags,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
            logger.warning("Sync skipped exact duplicate note pull: \(safeTitle, privacy: .public)")
            return
        }

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
            isPinned: isPinned,
            tags: tags
        )
        notes.insert(note, at: 0)
        persistNoteToDatabase(note)
    }

    private func exactDuplicateNoteIndex(title: String, content: String) -> Int? {
        let incomingKey = noteDedupKey(title: title, content: content, relativePath: "")
        guard !incomingKey.isEmpty else { return nil }

        for index in notes.indices {
            var candidate = notes[index]
            if candidate.content.isEmpty {
                candidate.content = loadContent(for: candidate)
            }
            if noteDedupKey(candidate) == incomingKey {
                return index
            }
        }
        return nil
    }

    private func mergeExactDuplicateFromSync(
        at index: Int,
        content: String,
        isPinned: Bool,
        tags: [String],
        createdAt: Date,
        updatedAt: Date
    ) {
        guard notes.indices.contains(index) else { return }

        if createdAt < notes[index].createdAt {
            notes[index].createdAt = createdAt
        }
        if updatedAt > notes[index].modifiedAt {
            notes[index].modifiedAt = updatedAt
            try? FileManager.default.setAttributes(
                [.modificationDate: updatedAt],
                ofItemAtPath: noteFileURL(for: notes[index]).path
            )
        }
        if notes[index].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes[index].content = content
            try? content.write(to: noteFileURL(for: notes[index]), atomically: true, encoding: .utf8)
        }
        notes[index].isPinned = notes[index].isPinned || isPinned
        notes[index].tags = deduplicatedNoteTags(from: notes[index].tags + tags)
        persistNoteToDatabase(notes[index])
    }

    /// Update an existing note from a sync pull (remote is newer).
    func updateFromSync(
        noteID: UUID,
        title: String,
        content: String,
        folderID: UUID?,
        isPinned: Bool,
        tags: [String],
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
        notes[idx].tags = tags

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
        persistNoteToDatabase(notes[idx])
    }

    /// Permanently remove a note because the server sent a purge tombstone.
    /// Does NOT re-report to SyncService to avoid deletion ping-pong.
    func removeSynced(_ note: Note) {
        MutationAuditContext.withSource(.cleanup) {
            contentCache.removeValue(forKey: note.id)
            try? FileManager.default.removeItem(at: noteFileURL(for: note))
            try? FileManager.default.removeItem(at: snapshotDirectoryURL(for: note))
            deleteNoteFromDatabase(note.id)
            index.removeValue(forKey: note.id)
            saveIndex()
            notes.removeAll { $0.id == note.id }
            scheduleAttachmentCleanup()
            MutationAuditService.shared.record(
                action: "delete",
                itemType: "note",
                itemID: note.id,
                before: MutationAuditSnapshots.note(note),
                after: ["state": "removed_by_sync"],
                metadata: ["reason": "sync_purge"]
            )
        }
    }

    /// Delete a note from a sync pull (remote deleted it).
    /// Routes through TrashStorage so the note can be recovered locally.
    /// Does NOT re-report to SyncService to avoid deletion ping-pong.
    func deleteFromSync(_ note: Note) {
        MutationAuditContext.withSource(.cleanup) {
            contentCache.removeValue(forKey: note.id)
            let _ = delete(note: note, trackSync: false)
        }
    }

    func restoreFromTrash(noteID: UUID, filename: String, folderID: UUID?, createdAt: Date) {
        index[noteID] = NoteIndexEntry(filename: filename, folderID: folderID, createdAt: createdAt)
        saveIndex()
        scanNotes()  // Picks up notes in Notes/ dir
        // Also load vault-folder notes that scanNotes() can't find
        if folderID != nil {
            loadVaultFolderNotes()
        }
        // Persist restored note to the database
        if let restoredNote = notes.first(where: { $0.id == noteID }) {
            persistNoteToDatabase(restoredNote)
            var before: [String: String] = ["trashFilename": filename]
            if let folderID {
                before["folderID"] = folderID.uuidString
            }
            MutationAuditService.shared.record(
                action: "restore",
                itemType: "note",
                itemID: noteID,
                before: before,
                after: MutationAuditSnapshots.note(restoredNote)
            )
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
                self?.rescan()
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
                self?.rescan()
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

    private func sanitizedNoteTitle(_ value: String) -> String {
        value
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func uniqueFilename(baseTitle: String, in directory: URL) -> String {
        let base = sanitizedNoteTitle(baseTitle).isEmpty ? "Untitled" : sanitizedNoteTitle(baseTitle)
        let fm = FileManager.default
        for index in 1...100 {
            let title = index == 1 ? base : "\(base) \(index)"
            let filename = "\(title).md"
            if !fm.fileExists(atPath: directory.appendingPathComponent(filename).path) {
                return filename
            }
        }
        return "\(base) \(UUID().uuidString.prefix(8)).md"
    }

    private func projectDirectoryName(for projectID: String) -> String {
        switch SecondBrainProjectGraphService.normalizedProjectID(projectID) {
        case "cider":
            return "Cider"
        case "cider-web":
            return "Cider Web"
        case "cider-ios":
            return "Cider iOS"
        default:
            return projectID
                .split(separator: "-")
                .map { word in
                    guard let first = word.first else { return "" }
                    return String(first).uppercased() + String(word.dropFirst())
                }
                .joined(separator: " ")
        }
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

        let referenceScan = referencedAttachmentScan(fromNotePaths: notePaths)
        let referencedFiles = referenceScan.referencedFilenames
        if !referenceScan.unreadableNoteURLs.isEmpty {
            let logger = Logger(subsystem: "com.cider.app", category: "NotesStorage")
            logger.error("Attachment cleanup skipped \(referenceScan.unreadableNoteURLs.count, privacy: .public) unreadable note files while scanning references.")
        }
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

    nonisolated static func referencedAttachmentScan(fromNotePaths notePaths: [URL]) -> NoteAttachmentReferenceScan {
        // Matches relative: (.attachments/file) or (./\.attachments/file)
        // Also matches absolute file:// URLs: (file:///path/.attachments/file)
        let markdownReferencePattern = #"\((?:file:///[^)]*?/|(?:\./)?)?\.attachments/([^)]+)\)"#
        let htmlReferencePattern = #"(?:src|href)=["'](?:[^"']*?/)?\.attachments/([^"']+)["']"#

        let markdownRegex = try? NSRegularExpression(pattern: markdownReferencePattern, options: [])
        let htmlRegex = try? NSRegularExpression(pattern: htmlReferencePattern, options: [])

        var referenced = Set<String>()
        var unreadableNoteURLs: [URL] = []

        for noteURL in notePaths {
            guard let content = try? String(contentsOf: noteURL, encoding: .utf8) else {
                unreadableNoteURLs.append(noteURL)
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

        return NoteAttachmentReferenceScan(
            referencedFilenames: referenced,
            unreadableNoteURLs: unreadableNoteURLs
        )
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

    // MARK: - Database Persistence

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

    private func existingItemType(_ db: CiderDatabase, itemID: UUID) throws -> String? {
        let stmt = try db.prepare("SELECT type FROM items WHERE id = ? LIMIT 1;")
        stmt.bind(DatabaseHelpers.encode(itemID), at: 1)
        guard try stmt.step() else { return nil }
        return stmt.optionalString(at: 0)
    }

    private func prepareExistingItemForNotePersist(_ db: CiderDatabase, note: Note) throws {
        guard let existingType = try existingItemType(db, itemID: note.id),
              existingType != "note" else { return }

        let itemID = DatabaseHelpers.encode(note.id)
        for table in ["bookmarks", "todos", "events", "contacts", "vault_files"] {
            let stmt = try db.prepare("DELETE FROM \(table) WHERE item_id = ?;")
            stmt.bind(itemID, at: 1)
            try stmt.step()
        }

        let ownerID = note.id.uuidString
        for table in ["item_sections", "content_chunks", "agent_actions"] {
            let stmt = try db.prepare("DELETE FROM \(table) WHERE owner_type = ? AND owner_id = ?;")
            stmt.bind(existingType, at: 1)
                .bind(ownerID, at: 2)
            try stmt.step()
        }

        let sourceRelations = try db.prepare("DELETE FROM owner_relations WHERE source_owner_type = ? AND source_owner_id = ?;")
        sourceRelations.bind(existingType, at: 1)
            .bind(ownerID, at: 2)
        try sourceRelations.step()

        let targetRelations = try db.prepare("DELETE FROM owner_relations WHERE target_owner_type = ? AND target_owner_id = ?;")
        targetRelations.bind(existingType, at: 1)
            .bind(ownerID, at: 2)
        try targetRelations.step()

        logger.info("Rehomed existing \(existingType, privacy: .public) item \(note.id.uuidString, privacy: .public) to note for \(note.relativePath, privacy: .public)")
    }

    // Internal for testing
    /// Number of entries currently in the in-memory UUID→metadata index.
    /// Used by tests to verify `loadNotesFromDatabase` rehydrates the index.
    var indexEntryCount: Int { index.count }

    // Internal for testing
    /// Returns the filename tracked by the index for a given note ID, if any.
    func indexFilename(for noteID: UUID) -> String? { index[noteID]?.filename }

    // Internal for testing
    /// Exercises the same duplicate repair path used by rescan before SQLite sync.
    func canonicalizedScannedNotesForTesting(_ loaded: [Note]) -> (notes: [Note], removedNotes: [Note]) {
        canonicalizedScannedNotes(loaded)
    }

    // Internal for testing
    /// SELECT all notes from the database (items JOIN notes), loading
    /// labelIDs from the item_labels join table. Also rehydrates `self.index`
    /// so mutation paths (renameNote/togglePin/assignNote/assignLabel/...) can
    /// find their entries after a DB-first cold launch.
    func loadNotesFromDatabase(_ db: CiderDatabase) {
        do {
            let stmt = try db.prepare("""
                SELECT i.id, i.title, i.created_at, i.updated_at, i.folder_id, i.relative_path,
                       n.content, n.summary, n.is_pinned
                FROM items i
                JOIN notes n ON n.item_id = i.id
                WHERE i.type = 'note'
                ORDER BY n.is_pinned DESC, i.created_at DESC;
                """)
            var loaded: [Note] = []
            while try stmt.step() {
                guard let id = DatabaseHelpers.decodeUUID(stmt.string(at: 0)) else { continue }
                let folderID = DatabaseHelpers.decodeUUID(stmt.optionalString(at: 4) ?? "")
                let relativePath = stmt.optionalString(at: 5) ?? ""
                let title = stmt.string(at: 1)
                let isPinned = stmt.bool(at: 8)
                let createdAt = DatabaseHelpers.decodeDate(stmt.double(at: 2))
                let dbProjectMetadata = try projectArtifactMetadata(db, noteID: id)
                let pathProjectMetadata = Self.projectArtifactMetadata(forRelativePath: relativePath)

                var note = Note(
                    id: id,
                    title: title,
                    content: stmt.string(at: 6),
                    summary: stmt.optionalString(at: 7),
                    createdAt: createdAt,
                    modifiedAt: DatabaseHelpers.decodeDate(stmt.double(at: 3)),
                    relativePath: relativePath,
                    labelIDs: [],
                    folderID: folderID,
                    isPinned: isPinned,
                    projectID: dbProjectMetadata.projectID ?? pathProjectMetadata?.projectID,
                    artifactType: dbProjectMetadata.artifactType ?? pathProjectMetadata?.artifactType
                )

                // Load labels and free-text tags from join tables
                note.labelIDs = try loadLabelIDs(db, itemID: id)
                note.tags = try loadTags(db, itemID: id)

                loaded.append(note)
            }
            let canonicalized = canonicalizedLoadedNotes(loaded, repairing: db)
            notes = canonicalized
            index = rebuiltNoteIndex(from: canonicalized)
            logger.info("Loaded \(canonicalized.count) notes from database")
        } catch {
            logger.error("Failed to load notes from database: \(error.localizedDescription)")
            notes = []
            index = [:]
        }
    }

    private func canonicalizedLoadedNotes(_ loaded: [Note], repairing db: CiderDatabase) -> [Note] {
        let result = canonicalizedNoteGroups(loaded)
        repairCanonicalDuplicateNotes(db, mergedNotes: result.mergedNotes, removedIDs: result.removedIDs)
        return result.notes
    }

    private func canonicalizedScannedNotes(_ loaded: [Note]) -> (notes: [Note], removedNotes: [Note]) {
        var seen = Set<UUID>()
        var uuidUniqueNotes: [Note] = []
        for note in loaded where seen.insert(note.id).inserted {
            uuidUniqueNotes.append(note)
        }
        let result = canonicalizedNoteGroups(uuidUniqueNotes)
        let removedIDs = Set(result.removedIDs)
        let removedNotes = uuidUniqueNotes.filter { removedIDs.contains($0.id) }
        return (result.notes, removedNotes)
    }

    private func deleteDuplicateNoteFiles(_ removedNotes: [Note]) {
        guard !removedNotes.isEmpty else { return }
        let fm = FileManager.default
        for note in removedNotes {
            let sourceURL = noteFileURL(for: note)
            guard fm.fileExists(atPath: sourceURL.path) else { continue }
            do {
                try fm.removeItem(at: sourceURL)
                MutationAuditService(database: resolvedDatabase).record(
                    action: "scanner.note.delete_exact_duplicate_file",
                    itemType: LibraryEntityType.note.rawValue,
                    itemID: note.id,
                    before: MutationAuditSnapshots.note(note),
                    metadata: [
                        "scanner": "NotesStorage.rescan",
                        "operation": "delete_exact_duplicate_file",
                        "source": MutationAuditSource.filesystem.rawValue,
                        "relativePath": note.relativePath
                    ],
                    source: .filesystem
                )
                logger.info("Deleted exact duplicate note file: \(sourceURL.path, privacy: .public)")
            } catch {
                logger.error("Failed to delete duplicate note file \(sourceURL.path, privacy: .public): \(error.localizedDescription)")
            }
        }
    }

    private static func normalizedNoteRelativePath(_ relativePath: String) -> String {
        relativePath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private func canonicalizedNoteGroups(_ loaded: [Note]) -> (notes: [Note], mergedNotes: [Note], removedIDs: [UUID]) {
        let pathCollapsed = collapsedDuplicateNotes(loaded) { note in
            let normalizedPath = Self.normalizedNoteRelativePath(note.relativePath)
            return normalizedPath.isEmpty ? "" : "path:\(normalizedPath)"
        }
        let exactCollapsed = collapsedDuplicateNotes(pathCollapsed.notes) { note in
            noteDedupKey(note)
        }

        return (
            notes: exactCollapsed.notes,
            mergedNotes: pathCollapsed.mergedNotes + exactCollapsed.mergedNotes,
            removedIDs: pathCollapsed.removedIDs + exactCollapsed.removedIDs
        )
    }

    private func collapsedDuplicateNotes(
        _ loaded: [Note],
        keyForNote: (Note) -> String
    ) -> (notes: [Note], mergedNotes: [Note], removedIDs: [UUID]) {
        var groups: [String: [Note]] = [:]
        var orderedKeys: [String] = []
        for note in loaded {
            let key = keyForNote(note)
            guard !key.isEmpty else {
                let uniqueKey = "id:\(note.id.uuidString)"
                orderedKeys.append(uniqueKey)
                groups[uniqueKey] = [note]
                continue
            }
            if groups[key] == nil {
                orderedKeys.append(key)
                groups[key] = []
            }
            groups[key]?.append(note)
        }

        var repaired: [Note] = []
        var mergedNotes: [Note] = []
        var removedIDs: [UUID] = []

        for key in orderedKeys {
            guard let group = groups[key], !group.isEmpty else { continue }
            if group.count == 1 {
                repaired.append(group[0])
                continue
            }

            let winner = group.max { lhs, rhs in
                noteCanonicalScore(lhs) < noteCanonicalScore(rhs)
            } ?? group[0]
            var merged = winner
            for duplicate in group where duplicate.id != winner.id {
                merged = mergeLoadedDuplicateNote(existing: merged, duplicate: duplicate)
                removedIDs.append(duplicate.id)
            }
            repaired.append(merged)
            mergedNotes.append(merged)
        }

        return (repaired, mergedNotes, removedIDs)
    }

    private func noteDedupKey(_ note: Note) -> String {
        noteDedupKey(title: note.title, content: note.content, relativePath: note.relativePath)
    }

    private func noteDedupKey(title: String, content: String, relativePath: String) -> String {
        let relativePath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameKey = VaultDuplicateAuditor.normalizedDuplicateName(title.isEmpty ? relativePath : title)
        if !nameKey.isEmpty {
            return "exact:\(nameKey)|\(content)"
        }
        if !relativePath.isEmpty {
            return "path:\(relativePath.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased())"
        }
        return ""
    }

    private func repairCanonicalDuplicateNotes(
        _ db: CiderDatabase,
        mergedNotes: [Note],
        removedIDs: [UUID]
    ) {
        guard !removedIDs.isEmpty else { return }
        do {
            try db.withTransaction {
                let deleteStmt = try db.prepare("DELETE FROM items WHERE id = ?;")
                for id in removedIDs {
                    deleteStmt.reset()
                    deleteStmt.bind(DatabaseHelpers.encode(id), at: 1)
                    try deleteStmt.step()
                }

                for note in mergedNotes {
                    try persistNoteToDatabaseInner(db, note: note)
                }
            }
            logger.info("Repaired \(removedIDs.count) duplicate note row(s)")
        } catch {
            logger.error("Failed to repair duplicate note rows: \(error.localizedDescription)")
        }
    }

    private func noteCanonicalScore(_ note: Note) -> Int {
        var score = 0
        if !hasDuplicateNumericSuffix(note.title) { score += 200 }
        if !hasDuplicateNumericSuffix((note.relativePath as NSString).deletingPathExtension) { score += 100 }
        if note.projectID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { score += 500 }
        if Self.projectArtifactMetadata(forRelativePath: note.relativePath) != nil { score += 400 }
        if !note.relativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 50 }
        if note.folderID != nil { score += 25 }
        if !note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 20 }
        if note.summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { score += 10 }
        if note.isPinned { score += 5 }
        return score
    }

    private func hasDuplicateNumericSuffix(_ rawValue: String) -> Bool {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let normalized = VaultDuplicateAuditor.normalizedDuplicateName(trimmed)
        let strippedExtension = URL(fileURLWithPath: trimmed).deletingPathExtension().lastPathComponent
        let folded = strippedExtension
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !normalized.isEmpty && normalized != folded
    }

    private func mergeLoadedDuplicateNote(existing: Note, duplicate: Note) -> Note {
        var merged = existing
        if duplicate.modifiedAt > merged.modifiedAt {
            merged.modifiedAt = duplicate.modifiedAt
        }
        if merged.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !duplicate.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.content = duplicate.content
        }
        if merged.summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
           duplicate.summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            merged.summary = duplicate.summary
        }
        if merged.folderID == nil { merged.folderID = duplicate.folderID }
        if merged.relativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.relativePath = duplicate.relativePath
        }
        if merged.projectID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
           duplicate.projectID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            merged.projectID = duplicate.projectID
        }
        if merged.artifactType?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
           duplicate.artifactType?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            merged.artifactType = duplicate.artifactType
        }
        restoreProjectArtifactMetadataFromPathIfNeeded(&merged)
        merged.isPinned = merged.isPinned || duplicate.isPinned
        merged.labelIDs = deduplicatedNoteUUIDs(from: merged.labelIDs + duplicate.labelIDs)
        merged.tags = deduplicatedNoteTags(from: merged.tags + duplicate.tags)
        return merged
    }

    private func restoreProjectArtifactMetadataFromPaths() {
        for index in notes.indices {
            restoreProjectArtifactMetadataFromPathIfNeeded(&notes[index])
        }
    }

    private func logProjectNoteBoundary(stage: String) {
        logger.info("NotesStorage \(stage, privacy: .public): projectCiderNotes=\(self.projectArtifactNoteCount(projectID: "cider"), privacy: .public) totalNotes=\(self.notes.count, privacy: .public)")
    }

    private func projectArtifactNoteCount(projectID rawProjectID: String) -> Int {
        let projectID = SecondBrainProjectGraphService.normalizedProjectID(rawProjectID)
        return notes.filter { note in
            SecondBrainProjectGraphService.normalizedProjectID(note.projectID ?? "") == projectID
                && (note.artifactType?.localizedLowercase == "note" || note.artifactType == nil)
        }.count
    }

    private func restoreProjectArtifactMetadataFromPathIfNeeded(_ note: inout Note) {
        guard let metadata = Self.projectArtifactMetadata(forRelativePath: note.relativePath) else { return }
        if note.projectID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            note.projectID = metadata.projectID
        }
        if note.artifactType?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            note.artifactType = metadata.artifactType
        }
    }

    private func rebuiltNoteIndex(from source: [Note]) -> [UUID: NoteIndexEntry] {
        Dictionary(uniqueKeysWithValues: source.map { note in
            let lastComponent = (note.relativePath as NSString).lastPathComponent
            let filename = lastComponent.isEmpty ? "\(note.title).md" : lastComponent
            return (
                note.id,
                NoteIndexEntry(
                    filename: filename,
                    folderID: note.folderID,
                    labelIDs: note.labelIDs.isEmpty ? nil : note.labelIDs,
                    createdAt: note.createdAt,
                    isPinned: note.isPinned ? true : nil
                )
            )
        })
    }

    private func deduplicatedNoteUUIDs(from rawIDs: [UUID]) -> [UUID] {
        var result: [UUID] = []
        result.reserveCapacity(rawIDs.count)
        var seen = Set<UUID>()
        for id in rawIDs where !seen.contains(id) {
            seen.insert(id)
            result.append(id)
        }
        return result
    }

    private func deduplicatedNoteTags(from rawTags: [String]) -> [String] {
        var result: [String] = []
        result.reserveCapacity(rawTags.count)
        var seen = Set<String>()
        for raw in rawTags {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
        }
        return result
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

    /// Load tag names from item_tags JOIN tags for a given item.
    private func loadTags(_ db: CiderDatabase, itemID: UUID) throws -> [String] {
        let stmt = try db.prepare("""
            SELECT t.name FROM item_tags it
            JOIN tags t ON t.id = it.tag_id
            WHERE it.item_id = ?;
            """)
        stmt.bind(DatabaseHelpers.encode(itemID), at: 1)
        var names: [String] = []
        while try stmt.step() {
            names.append(stmt.string(at: 0))
        }
        return names
    }

    private func projectArtifactMetadata(_ db: CiderDatabase, noteID: UUID) throws -> (projectID: String?, artifactType: String?) {
        let noteOwnerID = DatabaseHelpers.encode(noteID)
        let stmt = try db.prepare("""
            SELECT target_owner_id, metadata
            FROM owner_relations
            WHERE source_owner_type = 'note'
              AND source_owner_id = ?
              AND target_owner_type = 'project'
              AND relation_type = 'artifact_of'
            ORDER BY updated_at DESC
            LIMIT 1;
            """)
        stmt.bind(noteOwnerID, at: 1)
        guard try stmt.step() else { return (nil, nil) }
        let projectID = SecondBrainProjectGraphService.normalizedProjectID(stmt.string(at: 0))
        let metadata = DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 1)) ?? [:]
        let artifactType = metadata["artifactType"] ?? metadata["artifact_type"] ?? "note"
        return (projectID.isEmpty ? nil : projectID, artifactType)
    }

    private func replaceProjectArtifactRelationIfNeeded(_ db: CiderDatabase, note: Note) throws {
        let noteOwnerID = DatabaseHelpers.encode(note.id)
        let deleteStale = try db.prepare("""
            DELETE FROM owner_relations
            WHERE source_owner_type = 'note'
              AND source_owner_id = ?
              AND target_owner_type = 'project'
              AND relation_type = 'artifact_of'
              AND source = 'project_notes';
            """)
        deleteStale.bind(noteOwnerID, at: 1)
        try deleteStale.step()

        guard let rawProjectID = note.projectID else { return }
        let projectID = SecondBrainProjectGraphService.normalizedProjectID(rawProjectID)
        guard !projectID.isEmpty else { return }
        let artifactType = note.artifactType?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? note.artifactType!.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
            : "note"
        try SecondBrainProjectGraphService(database: db).upsertProject(
            id: projectID,
            title: projectDirectoryName(for: projectID),
            metadata: ["rootPath": "Projects/\(projectDirectoryName(for: projectID))"]
        )
        try SecondBrainStore(database: db).recordRelation(SecondBrainRelation(
            sourceOwner: SecondBrainOwnerRef(ownerType: "note", ownerID: note.id.uuidString),
            targetOwner: SecondBrainProjectGraphService.owner(projectID: projectID),
            relationType: "artifact_of",
            evidence: "Markdown project \(artifactType) lives at \(note.relativePath).",
            source: "project_notes",
            actor: "cider",
            confidence: 1,
            metadata: [
                "artifactType": artifactType,
                "title": note.title,
                "path": note.relativePath
            ]
        ))
    }

    private func loadSummary(_ db: CiderDatabase, itemID: UUID) throws -> String? {
        let stmt = try db.prepare("SELECT summary FROM notes WHERE item_id = ?;")
        stmt.bind(DatabaseHelpers.encode(itemID), at: 1)
        guard try stmt.step() else { return nil }
        return stmt.optionalString(at: 0)
    }

    // Internal for testing
    /// Persist a single note to the database (items + notes + item_labels) in a transaction.
    func persistNoteToDatabase(_ note: Note) {
        guard let db = resolvedDatabase else {
            logger.warning("No database available, skipping SQLite persist for note \(note.id)")
            return
        }
        persistNoteToDatabase(db, note: note)
    }

    // Internal for testing
    /// Persist a single note to the given database inside its own transaction.
    func persistNoteToDatabase(_ db: CiderDatabase, note: Note) {
        do {
            try persistNoteCanonicalRow(db, note: note)
            try indexNoteContent(db, noteID: note.id)
        } catch {
            logger.error("Failed to persist note \(note.id) to database: \(error.localizedDescription)")
        }
    }

    func persistNoteCanonicalRow(_ db: CiderDatabase, note: Note) throws {
        try db.withTransaction {
            try persistNoteToDatabaseInner(db, note: note)
        }
    }

    private func indexNoteContent(_ db: CiderDatabase, noteID: UUID) throws {
        _ = try SecondBrainItemContentIndexingService(database: db).rebuild(
            owner: SecondBrainOwnerRef(ownerType: "note", ownerID: noteID.uuidString)
        )
    }

    /// Core persist logic for a single note — must be called inside a transaction.
    private func persistNoteToDatabaseInner(
        _ db: CiderDatabase,
        note: Note,
        failOnProjectRelationCleanupError: Bool = false
    ) throws {
        // Scrub folder_id against target DB to defuse FK failures during the
        // first-run migration (or any drift between in-memory state and DB).
        let folderIDText = try resolveSafeFolderID(db, folderID: note.folderID)
        try prepareExistingItemForNotePersist(db, note: note)

        // 1. UPSERT into items (ON CONFLICT avoids DELETE+INSERT that triggers CASCADE)
        let itemStmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, 'note', ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                type = 'note',
                title = excluded.title,
                updated_at = excluded.updated_at,
                folder_id = excluded.folder_id,
                relative_path = excluded.relative_path;
            """)
        let itemID = DatabaseHelpers.encode(note.id)
        let relPath: String? = note.relativePath.isEmpty ? nil : note.relativePath
        itemStmt.bind(itemID, at: 1)
            .bind(note.title, at: 2)
            .bind(DatabaseHelpers.encode(note.createdAt), at: 3)
            .bind(DatabaseHelpers.encode(note.modifiedAt), at: 4)
            .bind(folderIDText, at: 5)
            .bind(relPath, at: 6)
        try itemStmt.step()

        // 2. UPSERT into notes
        let noteStmt = try db.prepare("""
            INSERT INTO notes (item_id, content, summary, is_pinned)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(item_id) DO UPDATE SET
                content = excluded.content,
                summary = excluded.summary,
                is_pinned = excluded.is_pinned;
            """)
        noteStmt.bind(itemID, at: 1)
            .bind(note.content, at: 2)
            .bind(note.summary, at: 3)
            .bind(note.isPinned ? Int64(1) : Int64(0), at: 4)
        try noteStmt.step()

        // 3. Sync item_labels: delete all, re-insert via EXISTS guard so
        //    dangling label_ids are silently dropped instead of tripping FK.
        let delLabels = try db.prepare("DELETE FROM item_labels WHERE item_id = ?;")
        delLabels.bind(itemID, at: 1)
        try delLabels.step()

        if !note.labelIDs.isEmpty {
            let insLabel = try db.prepare("""
                INSERT INTO item_labels (item_id, label_id)
                SELECT ?, ? WHERE EXISTS (SELECT 1 FROM labels WHERE id = ?);
                """)
            for labelID in note.labelIDs {
                insLabel.reset()
                let labelText = DatabaseHelpers.encode(labelID)
                insLabel.bind(itemID, at: 1)
                    .bind(labelText, at: 2)
                    .bind(labelText, at: 3)
                try insLabel.step()
            }
        }

        // 4. Sync item_tags: find-or-create tags by name, delete all, re-insert.
        //    Same pattern bookmarks use (VaultBookmarkService.persistBookmarkToDatabaseInner).
        let delTags = try db.prepare("DELETE FROM item_tags WHERE item_id = ?;")
        delTags.bind(itemID, at: 1)
        try delTags.step()

        if !note.tags.isEmpty {
            let findTag = try db.prepare("SELECT id FROM tags WHERE name = ?;")
            let createTag = try db.prepare("INSERT INTO tags (id, name) VALUES (?, ?);")
            let insItemTag = try db.prepare("INSERT INTO item_tags (item_id, tag_id) VALUES (?, ?);")

            for tagName in note.tags {
                findTag.reset()
                findTag.bind(tagName, at: 1)
                let tagID: String
                if try findTag.step() {
                    tagID = findTag.string(at: 0)
                } else {
                    tagID = DatabaseHelpers.encode(UUID())
                    createTag.reset()
                    createTag.bind(tagID, at: 1).bind(tagName, at: 2)
                    try createTag.step()
                }

                insItemTag.reset()
                insItemTag.bind(itemID, at: 1).bind(tagID, at: 2)
                try insItemTag.step()
            }
        }

        try replaceProjectArtifactRelationIfNeeded(db, note: note)
        if note.isProjectArtifact {
            if failOnProjectRelationCleanupError {
                try removeDuplicateProjectNoteRelationsThrowing(relativePath: note.relativePath, keeping: note.id)
            } else {
                removeDuplicateProjectNoteRelations(relativePath: note.relativePath, keeping: note.id)
            }
        }
    }

    private struct ProjectArtifactDirectory {
        let name: String
        let artifactType: String
    }

    private static let projectArtifactDirectories: [ProjectArtifactDirectory] = [
        ProjectArtifactDirectory(name: "Notes", artifactType: "note"),
        ProjectArtifactDirectory(name: "Plans", artifactType: "plan"),
        ProjectArtifactDirectory(name: "Handoffs", artifactType: "handoff"),
        ProjectArtifactDirectory(name: "Decisions", artifactType: "decision"),
        ProjectArtifactDirectory(name: "QA", artifactType: "qa")
    ]

    private static func projectArtifactDirectoryName(for artifactType: String) -> String {
        let normalized = artifactType.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        return projectArtifactDirectories.first(where: { $0.artifactType == normalized })?.name ?? "Notes"
    }

    private static func projectArtifactMetadata(forRelativePath relativePath: String) -> (projectID: String, artifactType: String)? {
        let components = relativePath.split(separator: "/").map(String.init)
        guard components.count >= 4,
              components[0].localizedCaseInsensitiveCompare("Projects") == .orderedSame
        else { return nil }
        let projectID = SecondBrainProjectGraphService.normalizedProjectID(components[1])
        guard !projectID.isEmpty else { return nil }
        guard let artifact = projectArtifactDirectories.first(where: {
            $0.name.localizedCaseInsensitiveCompare(components[2]) == .orderedSame
        }) else { return nil }
        return (projectID, artifact.artifactType)
    }

    /// Delete a note from the database by ID. CASCADE handles detail + join tables.
    func deleteNoteFromDatabase(_ noteID: UUID) {
        guard let db = resolvedDatabase else {
            logger.warning("No database available, skipping SQLite delete for note \(noteID)")
            return
        }
        deleteNoteFromDatabase(db, noteID: noteID)
    }

    // Internal for testing
    /// DELETE a note from the given database by ID.
    func deleteNoteFromDatabase(_ db: CiderDatabase, noteID: UUID) {
        do {
            try SecondBrainStore(database: db).deleteOwnerFootprint(
                for: SecondBrainOwnerRef(ownerType: "note", ownerID: noteID.uuidString)
            )
            let stmt = try db.prepare("DELETE FROM items WHERE id = ?;")
            stmt.bind(DatabaseHelpers.encode(noteID), at: 1)
            try stmt.step()
        } catch {
            logger.error("Failed to delete note \(noteID) from database: \(error.localizedDescription)")
        }
    }

    deinit {
        directorySource?.cancel()
    }
}
