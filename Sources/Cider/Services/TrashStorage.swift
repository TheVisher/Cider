import Foundation
import os

/// Manages `.trash/` staging areas inside bookmark and notes directories.
/// Deleted items are moved here before permanent removal, enabling undo and
/// user-visible trash management in Settings → Storage.
@MainActor
final class TrashStorage {
    static let shared = TrashStorage()

    private static let logger = Logger(subsystem: "com.cider", category: "TrashStorage")

    private let trashDirName = ".trash"
    private let manifestFileName = "_cider_trash_manifest.json"
    private let thumbnailsDirName = "thumbnails"
    private let originalsDirName = "originals"

    // MARK: - Database

    /// Explicit database reference for testing. Production uses `CiderDatabase.shared`.
    private var database: CiderDatabase?

    /// Resolve which database instance to use: explicit (testing) or shared (production).
    private var resolvedDatabase: CiderDatabase? {
        database ?? (CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil)
    }

    private init() {
        performOneTimeMigrationIfNeeded()
    }

    /// Testing-only initializer with an explicit database.
    /// Does NOT read the legacy JSON manifests or run the migration.
    init(database: CiderDatabase) {
        self.database = database
    }

    // MARK: - Bookmark Trash

    /// Moves a bookmark's image assets into the bookmarks `.trash/` directory and
    /// records the item in the trash manifest. Returns the created `TrashItem`.
    func trashBookmark(_ bookmark: Bookmark, bookmarksDir: URL) -> TrashItem {
        let trashDir = bookmarksDir.appendingPathComponent(trashDirName)
        let trashThumbDir = trashDir.appendingPathComponent(thumbnailsDirName)
        let trashOrigDir = trashDir.appendingPathComponent(originalsDirName)
        let fm = FileManager.default

        try? fm.createDirectory(at: trashThumbDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: trashOrigDir, withIntermediateDirectories: true)

        // Move thumbnail
        var trashThumbnailRelPath: String?
        if let relPath = bookmark.thumbnailRelativePath, !relPath.isEmpty {
            let srcURL = bookmarksDir.appendingPathComponent(relPath)
            let filename = srcURL.lastPathComponent
            let destURL = trashThumbDir.appendingPathComponent(filename)
            if fm.fileExists(atPath: srcURL.path) {
                try? fm.moveItem(at: srcURL, to: destURL)
                trashThumbnailRelPath = "\(thumbnailsDirName)/\(filename)"
            }
        }

        // Move original image
        var trashOriginalRelPath: String?
        if let relPath = bookmark.originalImageRelativePath, !relPath.isEmpty {
            let srcURL = bookmarksDir.appendingPathComponent(relPath)
            let filename = srcURL.lastPathComponent
            let destURL = trashOrigDir.appendingPathComponent(filename)
            if fm.fileExists(atPath: srcURL.path) {
                try? fm.moveItem(at: srcURL, to: destURL)
                trashOriginalRelPath = "\(originalsDirName)/\(filename)"
            }
        }

        let payload = BookmarkTrashPayload(
            bookmark: bookmark,
            trashThumbnailRelativePath: trashThumbnailRelPath,
            trashOriginalRelativePath: trashOriginalRelPath
        )

        let trashItem = TrashItem(
            itemID: bookmark.id,
            itemType: .bookmark,
            title: bookmark.title,
            originalFolderID: bookmark.folderID,
            bookmarkPayload: payload
        )

        addToManifest(trashItem, trashDir: trashDir)
        return trashItem
    }

    func restoreBookmark(_ trashItem: TrashItem) {
        guard let payload = trashItem.bookmarkPayload else { return }

        let fm = FileManager.default

        // Determine the correct target directory based on the bookmark's folderID
        let targetDir: URL
        if let folderID = payload.bookmark.folderID,
           let vaultFolder = VaultFolderService.shared.folder(for: folderID) {
            targetDir = StoragePaths.cachedVaultDirectoryURL.appendingPathComponent(vaultFolder.relativePath)
            try? fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
        } else {
            targetDir = StoragePaths.cachedInboxSubdirectoryURL(for: .bookmarks)
        }

        // Resolve trash dir: check Inbox first, then legacy .cider/bookmarks/
        let inboxTrashDir = StoragePaths.cachedInboxSubdirectoryURL(for: .bookmarks).appendingPathComponent(trashDirName)
        let legacyTrashDir = StoragePaths.directoryURL(for: .bookmarks).appendingPathComponent(trashDirName)

        let trashDir: URL
        if fm.fileExists(atPath: inboxTrashDir.appendingPathComponent(manifestFileName).path) {
            let manifest = loadManifest(trashDir: inboxTrashDir)
            trashDir = manifest.contains(where: { $0.id == trashItem.id }) ? inboxTrashDir : legacyTrashDir
        } else {
            trashDir = legacyTrashDir
        }

        var restoredBookmark = payload.bookmark
        restoredBookmark.isEnriching = false

        // Move thumbnail back
        if let trashRelPath = payload.trashThumbnailRelativePath,
           let originalRelPath = restoredBookmark.thumbnailRelativePath {
            let srcURL = trashDir.appendingPathComponent(trashRelPath)
            let destURL = targetDir.appendingPathComponent(originalRelPath)
            if fm.fileExists(atPath: srcURL.path) {
                try? fm.createDirectory(
                    at: destURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? fm.moveItem(at: srcURL, to: destURL)
            }
        }

        // Move original image back
        if let trashRelPath = payload.trashOriginalRelativePath,
           let originalRelPath = restoredBookmark.originalImageRelativePath {
            let srcURL = trashDir.appendingPathComponent(trashRelPath)
            let destURL = targetDir.appendingPathComponent(originalRelPath)
            if fm.fileExists(atPath: srcURL.path) {
                try? fm.createDirectory(
                    at: destURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? fm.moveItem(at: srcURL, to: destURL)
            }
        }

        VaultBookmarkService.shared.restoreFromTrash(restoredBookmark)
        removeFromManifest(trashItem.id, trashDir: trashDir)
    }

    // MARK: - Note Trash

    /// Moves a note's `.md` file into the notes `.trash/` directory.
    func trashNote(_ note: Note, notesDir: URL) -> TrashItem {
        let trashDir = notesDir.appendingPathComponent(trashDirName)
        let fm = FileManager.default
        try? fm.createDirectory(at: trashDir, withIntermediateDirectories: true)

        let filename = (note.relativePath as NSString).lastPathComponent
        let srcURL = notesDir.appendingPathComponent(filename)
        let destURL = trashDir.appendingPathComponent(filename)
        if fm.fileExists(atPath: srcURL.path) {
            try? fm.moveItem(at: srcURL, to: destURL)
        }

        let payload = NoteTrashPayload(
            noteFilename: filename,
            folderID: note.folderID,
            createdAt: note.createdAt
        )

        let trashItem = TrashItem(
            itemID: note.id,
            itemType: .note,
            title: note.title,
            originalFolderID: note.folderID,
            notePayload: payload
        )

        addToManifest(trashItem, trashDir: trashDir)
        return trashItem
    }

    func restoreNote(_ trashItem: TrashItem) {
        guard let payload = trashItem.notePayload else { return }

        let inboxNotesDir = StoragePaths.cachedInboxSubdirectoryURL(for: .notes)
        // Trash is stored in Inbox/Notes/.trash/
        let trashDir = inboxNotesDir.appendingPathComponent(trashDirName)
        let fm = FileManager.default

        // Also check legacy trash location (.cider/notes/.trash/)
        let legacyTrashDir = StoragePaths.directoryURL(for: .notes).appendingPathComponent(trashDirName)

        var srcURL = trashDir.appendingPathComponent(payload.noteFilename)
        if !fm.fileExists(atPath: srcURL.path) {
            srcURL = legacyTrashDir.appendingPathComponent(payload.noteFilename)
        }

        // Determine destination: vault folder if the note had one, otherwise Inbox/Notes/
        let destDir: URL
        if let folderID = payload.folderID,
           let vaultFolder = VaultFolderService.shared.folder(for: folderID) {
            destDir = StoragePaths.cachedVaultDirectoryURL.appendingPathComponent(vaultFolder.relativePath)
            try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        } else {
            destDir = inboxNotesDir
            try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        }

        var destURL = destDir.appendingPathComponent(payload.noteFilename)

        // Avoid overwriting a file with the same name
        if fm.fileExists(atPath: destURL.path) {
            let base = (payload.noteFilename as NSString).deletingPathExtension
            let ext = (payload.noteFilename as NSString).pathExtension
            destURL = destDir.appendingPathComponent("\(base) Restored.\(ext)")
        }

        if fm.fileExists(atPath: srcURL.path) {
            do {
                try fm.moveItem(at: srcURL, to: destURL)
            } catch {
                return  // bail — leave manifest intact so item remains visible in trash
            }
            NotesStorage.shared.restoreFromTrash(
                noteID: trashItem.itemID,
                filename: destURL.lastPathComponent,
                folderID: payload.folderID,
                createdAt: payload.createdAt
            )
        } else {
            // Source file missing — leave manifest intact so item stays visible in trash
            return
        }

        // Remove from whichever manifest actually contains this item
        let resolvedTrashDir: URL
        if loadManifest(trashDir: trashDir).contains(where: { $0.id == trashItem.id }) {
            resolvedTrashDir = trashDir
        } else {
            resolvedTrashDir = legacyTrashDir
        }
        removeFromManifest(trashItem.id, trashDir: resolvedTrashDir)
    }

    // MARK: - Date Card Trash

    func trashDateCard(_ dateCard: DateCard, dateCardsDir: URL, icsFileURL: URL? = nil) -> TrashItem {
        let trashDir = dateCardsDir.appendingPathComponent(trashDirName)
        let fm = FileManager.default
        try? fm.createDirectory(at: trashDir, withIntermediateDirectories: true)

        // Move the .ics content file to trash if provided
        if let icsFileURL, fm.fileExists(atPath: icsFileURL.path) {
            let destURL = trashDir.appendingPathComponent(icsFileURL.lastPathComponent)
            try? fm.moveItem(at: icsFileURL, to: destURL)
        }

        let payload = DateCardTrashPayload(
            dateCard: dateCard,
            trashICSFilename: icsFileURL?.lastPathComponent
        )
        let trashItem = TrashItem(
            itemID: dateCard.id,
            itemType: .dateCard,
            title: dateCard.title,
            originalFolderID: dateCard.folderID,
            dateCardPayload: payload
        )

        addToManifest(trashItem, trashDir: trashDir)
        return trashItem
    }

    func restoreDateCard(_ trashItem: TrashItem) {
        guard let payload = trashItem.dateCardPayload else { return }

        let dateCardsDir = StoragePaths.cachedDirectoryURL(for: .dateCards)
        let trashDir = dateCardsDir.appendingPathComponent(trashDirName)
        let fm = FileManager.default

        // Move the .ics file back from trash
        if let icsFilename = payload.trashICSFilename {
            let srcURL = trashDir.appendingPathComponent(icsFilename)
            let destDir: URL
            if let folderID = payload.dateCard.folderID,
               let folder = VaultFolderService.shared.folder(for: folderID) {
                destDir = StoragePaths.cachedVaultDirectoryURL.appendingPathComponent(folder.relativePath)
            } else {
                destDir = StoragePaths.cachedInboxSubdirectoryURL(for: .dateCards)
            }
            try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            var destURL = destDir.appendingPathComponent(icsFilename)
            if fm.fileExists(atPath: destURL.path) {
                let base = (icsFilename as NSString).deletingPathExtension
                destURL = destDir.appendingPathComponent("\(base) Restored.ics")
            }
            if fm.fileExists(atPath: srcURL.path) {
                try? fm.moveItem(at: srcURL, to: destURL)
            }
        }

        DateCardStorage.shared.restoreFromTrash(payload.dateCard)
        removeFromManifest(trashItem.id, trashDir: trashDir)
    }

    // MARK: - Todo Card Trash

    func trashTodoCard(_ todoCard: TodoCard, todoCardsDir: URL, icsFileURL: URL? = nil) -> TrashItem {
        let trashDir = todoCardsDir.appendingPathComponent(trashDirName)
        let fm = FileManager.default
        try? fm.createDirectory(at: trashDir, withIntermediateDirectories: true)

        // Move the .ics content file to trash if provided
        if let icsFileURL, fm.fileExists(atPath: icsFileURL.path) {
            let destURL = trashDir.appendingPathComponent(icsFileURL.lastPathComponent)
            try? fm.moveItem(at: icsFileURL, to: destURL)
        }

        let payload = TodoCardTrashPayload(
            todoCard: todoCard,
            trashICSFilename: icsFileURL?.lastPathComponent
        )
        let trashItem = TrashItem(
            itemID: todoCard.id,
            itemType: .todo,
            title: todoCard.title,
            originalFolderID: todoCard.folderID,
            todoCardPayload: payload
        )

        addToManifest(trashItem, trashDir: trashDir)
        return trashItem
    }

    func restoreTodoCard(_ trashItem: TrashItem) {
        guard let payload = trashItem.todoCardPayload else { return }

        let todoCardsDir = StoragePaths.cachedDirectoryURL(for: .todos)
        let trashDir = todoCardsDir.appendingPathComponent(trashDirName)
        let fm = FileManager.default

        // Move the .ics file back from trash
        if let icsFilename = payload.trashICSFilename {
            let srcURL = trashDir.appendingPathComponent(icsFilename)
            let destDir: URL
            if let folderID = payload.todoCard.folderID,
               let folder = VaultFolderService.shared.folder(for: folderID) {
                destDir = StoragePaths.cachedVaultDirectoryURL.appendingPathComponent(folder.relativePath)
            } else {
                destDir = StoragePaths.cachedInboxSubdirectoryURL(for: .todos)
            }
            try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            var destURL = destDir.appendingPathComponent(icsFilename)
            if fm.fileExists(atPath: destURL.path) {
                let base = (icsFilename as NSString).deletingPathExtension
                destURL = destDir.appendingPathComponent("\(base) Restored.ics")
            }
            if fm.fileExists(atPath: srcURL.path) {
                try? fm.moveItem(at: srcURL, to: destURL)
            }
        }

        TodoCardStorage.shared.restoreFromTrash(payload.todoCard)
        removeFromManifest(trashItem.id, trashDir: trashDir)
    }

    // MARK: - Whiteboard Trash

    func trashWhiteboard(_ canvas: WhiteboardCanvas, whiteboardsDir: URL) -> TrashItem {
        let trashDir = whiteboardsDir.appendingPathComponent(trashDirName)
        try? FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)

        let payload = WhiteboardTrashPayload(canvas: canvas)
        let trashItem = TrashItem(
            itemID: canvas.id,
            itemType: .whiteboard,
            title: canvas.name,
            originalFolderID: nil,
            whiteboardPayload: payload
        )

        addToManifest(trashItem, trashDir: trashDir)
        return trashItem
    }

    func restoreWhiteboard(_ trashItem: TrashItem) {
        guard let payload = trashItem.whiteboardPayload else { return }

        let whiteboardsDir = StoragePaths.directoryURL(for: .whiteboards)
        let trashDir = whiteboardsDir.appendingPathComponent(trashDirName)

        WhiteboardStorage.shared.restoreFromTrash(payload.canvas)

        // Recreate the SavedView tab pointing to this canvas so it appears in the tab bar
        let savedView = SavedViewStorage.shared.createWhiteboardView(
            name: payload.canvas.name,
            canvasID: payload.canvas.id
        )
        SavedViewStorage.shared.addToTabOrder(savedView.id)

        removeFromManifest(trashItem.id, trashDir: trashDir)
    }

    // MARK: - Kanban Board Trash

    func trashKanbanBoard(boardID: String, name: String, yamlContent: String) -> TrashItem {
        let boardsDir = StoragePaths.directoryURL(for: .kanbanBoards)
        let trashDir = boardsDir.appendingPathComponent(trashDirName)
        try? FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)

        let payload = KanbanBoardTrashPayload(yamlContent: yamlContent, boardID: boardID)
        let trashItem = TrashItem(
            itemID: UUID(),
            itemType: .kanbanBoard,
            title: name,
            originalFolderID: nil,
            kanbanBoardPayload: payload
        )

        addToManifest(trashItem, trashDir: trashDir)
        return trashItem
    }

    func restoreKanbanBoard(_ trashItem: TrashItem) {
        guard let payload = trashItem.kanbanBoardPayload else { return }

        let boardsDir = StoragePaths.directoryURL(for: .kanbanBoards)
        let trashDir = boardsDir.appendingPathComponent(trashDirName)

        // Write the YAML back
        let fileURL = boardsDir.appendingPathComponent("\(payload.boardID).yaml")
        try? payload.yamlContent.write(to: fileURL, atomically: true, encoding: .utf8)

        // Reload and re-create the tab
        KanbanStorage.shared.reload()
        let savedView = SavedViewStorage.shared.createKanbanView(name: trashItem.title, boardID: payload.boardID)
        SavedViewStorage.shared.addToTabOrder(savedView.id)

        removeFromManifest(trashItem.id, trashDir: trashDir)
    }

    // MARK: - Contact Trash

    func trashContact(_ contact: ContactCard, contactsDir: URL, vcfFileURL: URL? = nil) -> TrashItem {
        let trashDir = contactsDir.appendingPathComponent(trashDirName)
        let fm = FileManager.default
        try? fm.createDirectory(at: trashDir, withIntermediateDirectories: true)

        // Move the .vcf content file to trash if provided
        if let vcfFileURL, fm.fileExists(atPath: vcfFileURL.path) {
            let destURL = trashDir.appendingPathComponent(vcfFileURL.lastPathComponent)
            try? fm.moveItem(at: vcfFileURL, to: destURL)
        }

        // Move avatar file to trash if it exists
        let contactAvatarsDirName = "contact-avatars"
        var trashAvatarRelPath: String?
        if contact.hasAvatar {
            let avatarSrc = contactsDir.appendingPathComponent(".contact-avatars/\(contact.id.uuidString).jpg")
            if fm.fileExists(atPath: avatarSrc.path) {
                let trashAvatarsDir = trashDir.appendingPathComponent(contactAvatarsDirName)
                try? fm.createDirectory(at: trashAvatarsDir, withIntermediateDirectories: true)
                let avatarDest = trashAvatarsDir.appendingPathComponent("\(contact.id.uuidString).jpg")
                try? fm.moveItem(at: avatarSrc, to: avatarDest)
                trashAvatarRelPath = "\(contactAvatarsDirName)/\(contact.id.uuidString).jpg"
            }
        }

        // Cascade-trash linked birthday date cards
        var cascadedIDs: [UUID] = []
        for ref in contact.linkedEntities where ref.type == .dateCard {
            if let trashItem = DateCardStorage.shared.deleteDateCard(ref.entityID) {
                cascadedIDs.append(trashItem.id)
            }
        }

        let payload = ContactTrashPayload(
            contact: contact,
            trashVCFFilename: vcfFileURL?.lastPathComponent,
            trashAvatarRelativePath: trashAvatarRelPath,
            cascadedDateCardTrashIDs: cascadedIDs
        )

        let trashItem = TrashItem(
            itemID: contact.id,
            itemType: .contact,
            title: contact.displayName,
            originalFolderID: contact.folderID,
            contactPayload: payload
        )

        addToManifest(trashItem, trashDir: trashDir)
        return trashItem
    }

    func restoreContact(_ trashItem: TrashItem) {
        guard let payload = trashItem.contactPayload else { return }

        let contactsDir = StoragePaths.cachedDirectoryURL(for: .contacts)
        let trashDir = contactsDir.appendingPathComponent(trashDirName)
        let fm = FileManager.default

        // Restore avatar file
        if let avatarRelPath = payload.trashAvatarRelativePath {
            let srcURL = trashDir.appendingPathComponent(avatarRelPath)
            let destURL = contactsDir.appendingPathComponent(".contact-avatars/\(payload.contact.id.uuidString).jpg")
            if fm.fileExists(atPath: srcURL.path) {
                try? fm.createDirectory(
                    at: destURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? fm.moveItem(at: srcURL, to: destURL)
            }
        }

        // Restore the contact
        ContactStorage.shared.restoreFromTrash(payload.contact)

        // Restore cascaded birthday date cards — search all trash locations since
        // the date card could have been trashed from Inbox, vault folder, or legacy path
        let allItems = allTrashItems()
        let manifest = allItems
        for cascadedID in payload.cascadedDateCardTrashIDs {
            if let cascadedItem = manifest.first(where: { $0.id == cascadedID }) {
                restoreDateCard(cascadedItem)
            }
        }

        removeFromManifest(trashItem.id, trashDir: trashDir)
    }

    // MARK: - Session Trash

    func trashSession(_ session: BrowserSession, sessionsDir: URL) -> TrashItem {
        let trashDir = sessionsDir.appendingPathComponent(trashDirName)
        try? FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)

        let payload = BrowserSessionTrashPayload(session: session)
        let trashItem = TrashItem(
            itemID: session.id,
            itemType: .session,
            title: session.name,
            originalFolderID: nil,
            sessionPayload: payload
        )

        addToManifest(trashItem, trashDir: trashDir)
        return trashItem
    }

    func restoreSession(_ trashItem: TrashItem) {
        guard let payload = trashItem.sessionPayload else { return }

        let sessionsDir = StoragePaths.directoryURL(for: .sessions)
        let trashDir = sessionsDir.appendingPathComponent(trashDirName)

        BrowserSessionStorage.shared.restoreFromTrash(payload.session)
        removeFromManifest(trashItem.id, trashDir: trashDir)
    }

    // MARK: - Vault File Trash

    private var vaultFilesTrashDir: URL {
        StoragePaths.cachedVaultDirectoryURL
            .appendingPathComponent(".cider/vault-files")
            .appendingPathComponent(trashDirName)
    }

    func trashVaultFile(_ file: VaultFile) -> TrashItem {
        let trashDir = vaultFilesTrashDir
        let fm = FileManager.default
        try? fm.createDirectory(at: trashDir, withIntermediateDirectories: true)

        var trashFilename: String?
        if fm.fileExists(atPath: file.absoluteURL.path) {
            let destURL = trashDir.appendingPathComponent(file.filename)
            try? fm.moveItem(at: file.absoluteURL, to: destURL)
            trashFilename = file.filename
        }

        let payload = VaultFileTrashPayload(vaultFile: file, trashFilename: trashFilename)
        let trashItem = TrashItem(
            itemID: file.id,
            itemType: .vaultFile,
            title: file.displayTitle,
            originalFolderID: file.folderID,
            vaultFilePayload: payload
        )

        addToManifest(trashItem, trashDir: trashDir)
        VaultFileStorage.shared.removeMetadata(for: file.id)
        VaultFileService.shared.scan()
        return trashItem
    }

    func restoreVaultFile(_ trashItem: TrashItem) {
        guard let payload = trashItem.vaultFilePayload else { return }
        let trashDir = vaultFilesTrashDir
        let fm = FileManager.default
        let vaultRoot = StoragePaths.cachedVaultDirectoryURL

        // Determine target directory — use the original relativePath's parent to restore
        // to the correct Inbox subdirectory (Images/, Videos/, Files/) rather than bare Inbox/
        let targetDir: URL
        if let folderID = payload.vaultFile.folderID,
           let folder = VaultFolderService.shared.folder(for: folderID) {
            targetDir = vaultRoot.appendingPathComponent(folder.relativePath)
        } else {
            let originalParent = (payload.vaultFile.relativePath as NSString).deletingLastPathComponent
            if !originalParent.isEmpty {
                targetDir = vaultRoot.appendingPathComponent(originalParent)
            } else {
                targetDir = vaultRoot.appendingPathComponent("Inbox/Files")
            }
        }
        try? fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

        // The effective restored URL (may differ from original if a collision
        // forces a "Restored" rename). We reinstate the id-map entry for the
        // ACTUAL path before the rescan so the original UUID is preserved.
        var restoredURL: URL?
        if let trashFilename = payload.trashFilename {
            let srcURL = trashDir.appendingPathComponent(trashFilename)
            var destURL = targetDir.appendingPathComponent(payload.vaultFile.filename)

            // Avoid overwriting existing file with same name
            if fm.fileExists(atPath: destURL.path) {
                let base = (payload.vaultFile.filename as NSString).deletingPathExtension
                let ext = (payload.vaultFile.filename as NSString).pathExtension
                destURL = targetDir.appendingPathComponent("\(base) Restored.\(ext)")
            }

            guard fm.fileExists(atPath: srcURL.path) else {
                return // source file missing — leave manifest intact
            }
            do {
                try fm.moveItem(at: srcURL, to: destURL)
                restoredURL = destURL
            } catch {
                return // move failed — leave manifest intact so item remains visible in trash
            }
        } else {
            // No file in trash storage (e.g. the original disk file was
            // missing at trash time). Reinstate the id-map at the original
            // relative path so a future rescan that finds the file preserves
            // the UUID.
            restoredURL = vaultRoot.appendingPathComponent(payload.vaultFile.relativePath)
        }

        // Reinstate the id-map entry BEFORE the rescan so the file reclaims
        // its original UUID. Without this, scan() sees the file, finds no
        // id-map entry, mints a fresh UUID, and all label/link associations
        // are silently orphaned.
        if let restoredURL {
            let vaultRootPath = vaultRoot.path.hasSuffix("/") ? vaultRoot.path : vaultRoot.path + "/"
            let restoredRelativePath: String
            if restoredURL.path.hasPrefix(vaultRootPath) {
                restoredRelativePath = String(restoredURL.path.dropFirst(vaultRootPath.count))
            } else {
                restoredRelativePath = payload.vaultFile.relativePath
            }
            VaultFileService.shared.reinstateIDMapEntry(
                relativePath: restoredRelativePath,
                uuid: payload.vaultFile.id
            )
        }

        removeFromManifest(trashItem.id, trashDir: trashDir)
        VaultFileStorage.shared.restoreMetadata(from: payload.vaultFile)
        VaultFileService.shared.scan()
    }

    // MARK: - Generic Restore

    func restore(_ trashItem: TrashItem) {
        switch trashItem.itemType {
        case .bookmark:
            restoreBookmark(trashItem)
        case .note:
            restoreNote(trashItem)
        case .folder:
            for content in trashItem.folderContents ?? [] {
                restore(content)
            }
        case .dateCard:
            restoreDateCard(trashItem)
        case .todo:
            restoreTodoCard(trashItem)
        case .whiteboard:
            restoreWhiteboard(trashItem)
        case .contact:
            restoreContact(trashItem)
        case .vaultFolder:
            VaultFolderService.shared.restoreFolder(trashItem)
        case .session:
            restoreSession(trashItem)
        case .kanbanBoard:
            restoreKanbanBoard(trashItem)
        case .vaultFile:
            restoreVaultFile(trashItem)
        }
    }

    // MARK: - All Items

    func allTrashItems() -> [TrashItem] {
        let bookmarksDir = StoragePaths.directoryURL(for: .bookmarks)
        let notesDir = StoragePaths.directoryURL(for: .notes)
        let dateCardsDir = StoragePaths.directoryURL(for: .dateCards)
        let contactsDir = StoragePaths.directoryURL(for: .contacts)
        let todosDir = StoragePaths.directoryURL(for: .todos)
        let whiteboardsDir = StoragePaths.directoryURL(for: .whiteboards)
        let sessionsDir = StoragePaths.directoryURL(for: .sessions)
        let kanbanDir = StoragePaths.directoryURL(for: .kanbanBoards)
        var items: [TrashItem] = []
        items += loadManifest(trashDir: bookmarksDir.appendingPathComponent(trashDirName))
        items += loadManifest(trashDir: notesDir.appendingPathComponent(trashDirName))
        items += loadManifest(trashDir: dateCardsDir.appendingPathComponent(trashDirName))
        items += loadManifest(trashDir: contactsDir.appendingPathComponent(trashDirName))
        items += loadManifest(trashDir: todosDir.appendingPathComponent(trashDirName))
        items += loadManifest(trashDir: whiteboardsDir.appendingPathComponent(trashDirName))
        items += loadManifest(trashDir: sessionsDir.appendingPathComponent(trashDirName))
        items += loadManifest(trashDir: kanbanDir.appendingPathComponent(trashDirName))
        // Also check Inbox trash locations
        let inboxBookmarksDir = StoragePaths.cachedInboxSubdirectoryURL(for: .bookmarks)
        let inboxNotesDir = StoragePaths.cachedInboxSubdirectoryURL(for: .notes)
        items += loadManifest(trashDir: inboxBookmarksDir.appendingPathComponent(trashDirName))
        items += loadManifest(trashDir: inboxNotesDir.appendingPathComponent(trashDirName))
        items += loadManifest(trashDir: vaultFilesTrashDir)
        // Scan trash inside every vault folder (bookmarks in user folders trash to {folder}/.trash/)
        let vaultRoot = StoragePaths.cachedVaultDirectoryURL
        for folder in VaultFolderService.shared.folders {
            let folderTrashDir = vaultRoot.appendingPathComponent(folder.relativePath).appendingPathComponent(trashDirName)
            items += loadManifest(trashDir: folderTrashDir)
        }
        items += VaultFolderService.shared.trashedFolders()
        return items.sorted { $0.deletedAt > $1.deletedAt }
    }

    // MARK: - Purge

    func purgeExpired(olderThan days: Int) {
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 3600)
        let trashTypes: [StorageType] = [.bookmarks, .notes, .dateCards, .todos, .contacts, .sessions, .kanbanBoards, .whiteboards]
        for type in trashTypes {
            purgeExpired(
                olderThan: cutoff,
                in: StoragePaths.directoryURL(for: type).appendingPathComponent(trashDirName)
            )
        }
        // Also purge from Inbox trash locations
        for type in [StorageType.bookmarks, .notes] {
            purgeExpired(
                olderThan: cutoff,
                in: StoragePaths.cachedInboxSubdirectoryURL(for: type).appendingPathComponent(trashDirName)
            )
        }
        // Purge vault file trash
        purgeExpired(olderThan: cutoff, in: vaultFilesTrashDir)
        // Purge trash inside vault folders
        let vaultRoot = StoragePaths.cachedVaultDirectoryURL
        for folder in VaultFolderService.shared.folders {
            purgeExpired(
                olderThan: cutoff,
                in: vaultRoot.appendingPathComponent(folder.relativePath).appendingPathComponent(trashDirName)
            )
        }
    }

    private func purgeExpired(olderThan cutoff: Date, in trashDir: URL) {
        var manifest = loadManifest(trashDir: trashDir)
        let expired = manifest.filter { $0.deletedAt < cutoff }
        guard !expired.isEmpty else { return }
        for item in expired {
            deleteFilesForItem(item, trashDir: trashDir)
            manifest.removeAll { $0.id == item.id }
        }
        saveManifest(manifest, trashDir: trashDir)
        NotificationCenter.default.post(name: .trashContentsChanged, object: nil)
    }

    // MARK: - Permanent Delete

    func permanentlyDelete(_ trashItem: TrashItem) {
        switch trashItem.itemType {
        case .bookmark:
            let trashDir = resolveTrashDir(for: .bookmarks, itemID: trashItem.id)
            deleteFilesForItem(trashItem, trashDir: trashDir)
            removeFromManifest(trashItem.id, trashDir: trashDir)
        case .note:
            let trashDir = resolveTrashDir(for: .notes, itemID: trashItem.id)
            deleteFilesForItem(trashItem, trashDir: trashDir)
            removeFromManifest(trashItem.id, trashDir: trashDir)
        case .folder:
            for content in trashItem.folderContents ?? [] {
                permanentlyDelete(content)
            }
        case .dateCard:
            let trashDir = StoragePaths.directoryURL(for: .dateCards).appendingPathComponent(trashDirName)
            deleteFilesForItem(trashItem, trashDir: trashDir)
            removeFromManifest(trashItem.id, trashDir: trashDir)
        case .todo:
            let trashDir = StoragePaths.directoryURL(for: .todos).appendingPathComponent(trashDirName)
            deleteFilesForItem(trashItem, trashDir: trashDir)
            removeFromManifest(trashItem.id, trashDir: trashDir)
        case .whiteboard:
            let trashDir = StoragePaths.directoryURL(for: .whiteboards).appendingPathComponent(trashDirName)
            // Delete the trashed scene file
            let trashSceneURL = trashDir.appendingPathComponent("\(trashItem.itemID.uuidString).excalidraw")
            try? FileManager.default.removeItem(at: trashSceneURL)
            removeFromManifest(trashItem.id, trashDir: trashDir)
        case .contact:
            let trashDir = StoragePaths.directoryURL(for: .contacts).appendingPathComponent(trashDirName)
            deleteFilesForItem(trashItem, trashDir: trashDir)
            // Permanently delete cascaded date cards
            if let payload = trashItem.contactPayload {
                let dateCardsTrashDir = StoragePaths.directoryURL(for: .dateCards).appendingPathComponent(trashDirName)
                let manifest = loadManifest(trashDir: dateCardsTrashDir)
                for cascadedID in payload.cascadedDateCardTrashIDs {
                    if let cascadedItem = manifest.first(where: { $0.id == cascadedID }) {
                        permanentlyDelete(cascadedItem)
                    }
                }
            }
            removeFromManifest(trashItem.id, trashDir: trashDir)
        case .vaultFolder:
            // Vault folder trash is managed by VaultFolderService
            if let payload = trashItem.vaultFolderPayload {
                let vaultRoot = StoragePaths.cachedVaultDirectoryURL
                let trashDir = vaultRoot.appendingPathComponent(".cider/folders/.trash")
                let trashFolderURL = trashDir.appendingPathComponent(payload.folder.id.uuidString)
                try? FileManager.default.removeItem(at: trashFolderURL)
                removeFromManifest(trashItem.id, trashDir: trashDir)
            }
        case .session:
            let trashDir = StoragePaths.directoryURL(for: .sessions).appendingPathComponent(trashDirName)
            removeFromManifest(trashItem.id, trashDir: trashDir)
        case .kanbanBoard:
            let trashDir = StoragePaths.directoryURL(for: .kanbanBoards).appendingPathComponent(trashDirName)
            removeFromManifest(trashItem.id, trashDir: trashDir)
        case .vaultFile:
            if let payload = trashItem.vaultFilePayload, let trashFilename = payload.trashFilename {
                try? FileManager.default.removeItem(at: vaultFilesTrashDir.appendingPathComponent(trashFilename))
            }
            removeFromManifest(trashItem.id, trashDir: vaultFilesTrashDir)
        }
    }

    func emptyTrash() {
        let trashTypes: [StorageType] = [.bookmarks, .notes, .dateCards, .todos, .contacts, .sessions, .whiteboards, .kanbanBoards]
        for type in trashTypes {
            let trashDir = StoragePaths.directoryURL(for: type).appendingPathComponent(trashDirName)
            let items = loadManifest(trashDir: trashDir)
            for item in items { deleteFilesForItem(item, trashDir: trashDir) }
            saveManifest([], trashDir: trashDir)
        }
        // Also empty Inbox trash locations
        for type in [StorageType.bookmarks, .notes] {
            let trashDir = StoragePaths.cachedInboxSubdirectoryURL(for: type).appendingPathComponent(trashDirName)
            let items = loadManifest(trashDir: trashDir)
            for item in items { deleteFilesForItem(item, trashDir: trashDir) }
            saveManifest([], trashDir: trashDir)
        }
        // Empty vault file trash
        let vfTrashDir = vaultFilesTrashDir
        let vfItems = loadManifest(trashDir: vfTrashDir)
        for item in vfItems { deleteFilesForItem(item, trashDir: vfTrashDir) }
        saveManifest([], trashDir: vfTrashDir)
        // Empty trash inside vault folders
        let vaultRoot = StoragePaths.cachedVaultDirectoryURL
        for folder in VaultFolderService.shared.folders {
            let folderTrashDir = vaultRoot.appendingPathComponent(folder.relativePath).appendingPathComponent(trashDirName)
            let folderItems = loadManifest(trashDir: folderTrashDir)
            for item in folderItems { deleteFilesForItem(item, trashDir: folderTrashDir) }
            saveManifest([], trashDir: folderTrashDir)
        }
        // Empty vault folder trash
        VaultFolderService.shared.emptyFolderTrash()
        // Clear the SQLite trash table in one shot
        deleteAllTrashItemsFromDatabase()
        // Clear any pending undo action that references trashed items — prevents ghost restores
        CiderUndoManager.shared.discard()
    }

    // MARK: - Private Helpers

    /// Finds the correct trash directory for an item — checks Inbox, .cider/, and vault folders.
    private func resolveTrashDir(for type: StorageType, itemID: UUID) -> URL {
        let inboxTrashDir = StoragePaths.cachedInboxSubdirectoryURL(for: type).appendingPathComponent(trashDirName)
        if loadManifest(trashDir: inboxTrashDir).contains(where: { $0.id == itemID }) {
            return inboxTrashDir
        }
        // Check vault folder trash directories
        let vaultRoot = StoragePaths.cachedVaultDirectoryURL
        for folder in VaultFolderService.shared.folders {
            let folderTrashDir = vaultRoot.appendingPathComponent(folder.relativePath).appendingPathComponent(trashDirName)
            if loadManifest(trashDir: folderTrashDir).contains(where: { $0.id == itemID }) {
                return folderTrashDir
            }
        }
        return StoragePaths.directoryURL(for: type).appendingPathComponent(trashDirName)
    }

    private func deleteFilesForItem(_ trashItem: TrashItem, trashDir: URL) {
        let fm = FileManager.default
        switch trashItem.itemType {
        case .bookmark:
            if let payload = trashItem.bookmarkPayload {
                if let relPath = payload.trashThumbnailRelativePath {
                    try? fm.removeItem(at: trashDir.appendingPathComponent(relPath))
                }
                if let relPath = payload.trashOriginalRelativePath {
                    try? fm.removeItem(at: trashDir.appendingPathComponent(relPath))
                }
            }
        case .note:
            if let payload = trashItem.notePayload {
                try? fm.removeItem(at: trashDir.appendingPathComponent(payload.noteFilename))
            }
        case .folder:
            for content in trashItem.folderContents ?? [] {
                deleteFilesForItem(content, trashDir: trashDir)
            }
        case .dateCard:
            if let payload = trashItem.dateCardPayload,
               let icsFilename = payload.trashICSFilename {
                try? fm.removeItem(at: trashDir.appendingPathComponent(icsFilename))
            }
        case .todo:
            if let payload = trashItem.todoCardPayload,
               let icsFilename = payload.trashICSFilename {
                try? fm.removeItem(at: trashDir.appendingPathComponent(icsFilename))
            }
        case .whiteboard:
            let trashSceneURL = trashDir.appendingPathComponent("\(trashItem.itemID.uuidString).excalidraw")
            try? fm.removeItem(at: trashSceneURL)
        case .contact:
            if let payload = trashItem.contactPayload {
                if let vcfFilename = payload.trashVCFFilename {
                    try? fm.removeItem(at: trashDir.appendingPathComponent(vcfFilename))
                }
                if let avatarRelPath = payload.trashAvatarRelativePath {
                    try? fm.removeItem(at: trashDir.appendingPathComponent(avatarRelPath))
                }
            }
        case .vaultFolder:
            break // Handled by permanentlyDelete above
        case .session:
            break // Sessions are metadata-only, no separate files to delete
        case .kanbanBoard:
            break // YAML content stored in payload, no separate files
        case .vaultFile:
            if let payload = trashItem.vaultFilePayload, let trashFilename = payload.trashFilename {
                try? fm.removeItem(at: trashDir.appendingPathComponent(trashFilename))
            }
        }
    }

    private func loadManifest(trashDir: URL) -> [TrashItem] {
        let manifestURL = trashDir.appendingPathComponent(manifestFileName)
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }
        return (try? JSONDecoder().decode([TrashItem].self, from: data)) ?? []
    }

    private func saveManifest(_ items: [TrashItem], trashDir: URL) {
        let manifestURL = trashDir.appendingPathComponent(manifestFileName)
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    private func addToManifest(_ item: TrashItem, trashDir: URL) {
        var manifest = loadManifest(trashDir: trashDir)
        // Prevent duplicate entries for the same item
        manifest.removeAll { $0.id == item.id }
        manifest.insert(item, at: 0)
        saveManifest(manifest, trashDir: trashDir)
        persistTrashItemToDatabase(item)
        NotificationCenter.default.post(name: .trashContentsChanged, object: nil)
    }

    private func removeFromManifest(_ itemID: UUID, trashDir: URL) {
        var manifest = loadManifest(trashDir: trashDir)
        manifest.removeAll { $0.id == itemID }
        saveManifest(manifest, trashDir: trashDir)
        deleteTrashItemFromDatabase(itemID)
        NotificationCenter.default.post(name: .trashContentsChanged, object: nil)
    }

    // MARK: - Database Persistence

    // Internal for testing
    /// SELECT all trash items from the database, decoding each payload back into a `TrashItem`.
    func loadTrashItemsFromDatabase(_ db: CiderDatabase) -> [TrashItem] {
        do {
            let stmt = try db.prepare("""
                SELECT payload FROM trash
                ORDER BY deleted_at DESC;
                """)
            var items: [TrashItem] = []
            let decoder = JSONDecoder()
            while try stmt.step() {
                guard let payload = stmt.optionalString(at: 0),
                      let data = payload.data(using: .utf8) else { continue }
                do {
                    let item = try decoder.decode(TrashItem.self, from: data)
                    items.append(item)
                } catch {
                    Self.logger.error("Failed to decode trash payload: \(error.localizedDescription)")
                }
            }
            return items
        } catch {
            Self.logger.error("Failed to load trash items from database: \(error.localizedDescription)")
            return []
        }
    }

    /// UPSERT a single trash item into the database (public wrapper).
    func persistTrashItemToDatabase(_ item: TrashItem) {
        guard let db = resolvedDatabase else {
            Self.logger.warning("No database available, skipping SQLite persist for trash item \(item.id)")
            return
        }
        persistTrashItemToDatabase(db, item: item)
    }

    // Internal for testing
    /// UPSERT a single trash item into the given database inside its own transaction.
    func persistTrashItemToDatabase(_ db: CiderDatabase, item: TrashItem) {
        do {
            try db.withTransaction {
                try persistTrashItemToDatabaseInner(db, item: item)
            }
        } catch {
            Self.logger.error("Failed to persist trash item \(item.id) to database: \(error.localizedDescription)")
        }
    }

    // Internal for testing
    /// Core persist logic — must be called inside a transaction.
    func persistTrashItemToDatabaseInner(_ db: CiderDatabase, item: TrashItem) throws {
        let encoder = JSONEncoder()
        let payloadData = try encoder.encode(item)
        guard let payloadJSON = String(data: payloadData, encoding: .utf8) else {
            throw CiderDatabaseError.runExec("Failed to encode trash payload as UTF-8")
        }

        let stmt = try db.prepare("""
            INSERT INTO trash (
                id, item_id, item_type, title, original_folder_id, deleted_at, payload
            )
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                item_id = excluded.item_id,
                item_type = excluded.item_type,
                title = excluded.title,
                original_folder_id = excluded.original_folder_id,
                deleted_at = excluded.deleted_at,
                payload = excluded.payload;
            """)

        let originalFolderIDText: String? = item.originalFolderID.map { DatabaseHelpers.encode($0) }

        stmt.bind(DatabaseHelpers.encode(item.id), at: 1)
            .bind(DatabaseHelpers.encode(item.itemID), at: 2)
            .bind(item.itemType.rawValue, at: 3)
            .bind(item.title, at: 4)
            .bind(originalFolderIDText, at: 5)
            .bind(DatabaseHelpers.encode(item.deletedAt), at: 6)
            .bind(payloadJSON, at: 7)
        try stmt.step()
    }

    /// DELETE a trash item from the database by ID (public wrapper).
    func deleteTrashItemFromDatabase(_ id: UUID) {
        guard let db = resolvedDatabase else {
            Self.logger.warning("No database available, skipping SQLite delete for trash item \(id)")
            return
        }
        deleteTrashItemFromDatabase(db, trashItemID: id)
    }

    // Internal for testing
    /// DELETE a trash item from the given database by ID.
    func deleteTrashItemFromDatabase(_ db: CiderDatabase, trashItemID: UUID) {
        do {
            let stmt = try db.prepare("DELETE FROM trash WHERE id = ?;")
            stmt.bind(DatabaseHelpers.encode(trashItemID), at: 1)
            try stmt.step()
        } catch {
            Self.logger.error("Failed to delete trash item \(trashItemID) from database: \(error.localizedDescription)")
        }
    }

    /// DELETE every row from the trash table. Used by `emptyTrash()`.
    // Internal for testing
    func deleteAllTrashItemsFromDatabase() {
        guard let db = resolvedDatabase else { return }
        do {
            let stmt = try db.prepare("DELETE FROM trash;")
            try stmt.step()
        } catch {
            Self.logger.error("Failed to delete all trash items from database: \(error.localizedDescription)")
        }
    }

    // MARK: - One-Time Migration

    /// If the SQLite trash table is empty but the JSON manifests contain items,
    /// copy every item over in a single transaction. Runs once on startup.
    private func performOneTimeMigrationIfNeeded() {
        guard let db = resolvedDatabase else { return }

        // Bail if the table already has rows — we don't want to clobber SQLite.
        do {
            let countStmt = try db.prepare("SELECT count(*) FROM trash;")
            try countStmt.step()
            if countStmt.int(at: 0) > 0 { return }
        } catch {
            Self.logger.error("Failed to count trash rows: \(error.localizedDescription)")
            return
        }

        let legacyItems = allTrashItems()
        guard !legacyItems.isEmpty else { return }

        Self.logger.info("Migrating \(legacyItems.count) trash items from JSON to SQLite")
        do {
            try db.withTransaction {
                for item in legacyItems {
                    try persistTrashItemToDatabaseInner(db, item: item)
                }
            }
        } catch {
            Self.logger.error("Failed to migrate trash items to SQLite: \(error.localizedDescription)")
        }
    }
}
