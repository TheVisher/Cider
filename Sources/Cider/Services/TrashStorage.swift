import Foundation

/// Manages `.trash/` staging areas inside bookmark and notes directories.
/// Deleted items are moved here before permanent removal, enabling undo and
/// user-visible trash management in Settings → Storage.
@MainActor
final class TrashStorage {
    static let shared = TrashStorage()

    private let trashDirName = ".trash"
    private let manifestFileName = "_cider_trash_manifest.json"
    private let thumbnailsDirName = "thumbnails"
    private let originalsDirName = "originals"

    private init() {}

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

        let bookmarksDir = StoragePaths.directoryURL(for: .bookmarks)
        let trashDir = bookmarksDir.appendingPathComponent(trashDirName)
        let fm = FileManager.default

        var restoredBookmark = payload.bookmark
        restoredBookmark.isEnriching = false

        // Move thumbnail back
        if let trashRelPath = payload.trashThumbnailRelativePath,
           let originalRelPath = restoredBookmark.thumbnailRelativePath {
            let srcURL = trashDir.appendingPathComponent(trashRelPath)
            let destURL = bookmarksDir.appendingPathComponent(originalRelPath)
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
            let destURL = bookmarksDir.appendingPathComponent(originalRelPath)
            if fm.fileExists(atPath: srcURL.path) {
                try? fm.createDirectory(
                    at: destURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? fm.moveItem(at: srcURL, to: destURL)
            }
        }

        BookmarksStorage.shared.restoreFromTrash(restoredBookmark)
        removeFromManifest(trashItem.id, trashDir: trashDir)
    }

    // MARK: - Note Trash

    /// Moves a note's `.md` file into the notes `.trash/` directory.
    func trashNote(_ note: Note, notesDir: URL) -> TrashItem {
        let trashDir = notesDir.appendingPathComponent(trashDirName)
        let fm = FileManager.default
        try? fm.createDirectory(at: trashDir, withIntermediateDirectories: true)

        let srcURL = notesDir.appendingPathComponent(note.relativePath)
        let destURL = trashDir.appendingPathComponent(note.relativePath)
        if fm.fileExists(atPath: srcURL.path) {
            try? fm.moveItem(at: srcURL, to: destURL)
        }

        let payload = NoteTrashPayload(
            noteFilename: note.relativePath,
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

        let notesDir = StoragePaths.directoryURL(for: .notes)
        let trashDir = notesDir.appendingPathComponent(trashDirName)
        let fm = FileManager.default

        let srcURL = trashDir.appendingPathComponent(payload.noteFilename)
        var destURL = notesDir.appendingPathComponent(payload.noteFilename)

        // Avoid overwriting a file with the same name
        if fm.fileExists(atPath: destURL.path) {
            let base = (payload.noteFilename as NSString).deletingPathExtension
            let ext = (payload.noteFilename as NSString).pathExtension
            destURL = notesDir.appendingPathComponent("\(base) Restored.\(ext)")
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
        }

        removeFromManifest(trashItem.id, trashDir: trashDir)
    }

    // MARK: - Date Card Trash

    func trashDateCard(_ dateCard: DateCard, dateCardsDir: URL) -> TrashItem {
        let trashDir = dateCardsDir.appendingPathComponent(trashDirName)
        try? FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)

        let payload = DateCardTrashPayload(dateCard: dateCard)
        let trashItem = TrashItem(
            itemID: dateCard.id,
            itemType: .dateCard,
            title: dateCard.title,
            originalFolderID: nil,
            dateCardPayload: payload
        )

        addToManifest(trashItem, trashDir: trashDir)
        return trashItem
    }

    func restoreDateCard(_ trashItem: TrashItem) {
        guard let payload = trashItem.dateCardPayload else { return }

        let dateCardsDir = StoragePaths.directoryURL(for: .dateCards)
        let trashDir = dateCardsDir.appendingPathComponent(trashDirName)

        DateCardStorage.shared.restoreFromTrash(payload.dateCard)
        removeFromManifest(trashItem.id, trashDir: trashDir)
    }

    // MARK: - Todo Card Trash

    func trashTodoCard(_ todoCard: TodoCard, todoCardsDir: URL) -> TrashItem {
        let trashDir = todoCardsDir.appendingPathComponent(trashDirName)
        try? FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)

        let payload = TodoCardTrashPayload(todoCard: todoCard)
        let trashItem = TrashItem(
            itemID: todoCard.id,
            itemType: .todo,
            title: todoCard.title,
            originalFolderID: nil,
            todoCardPayload: payload
        )

        addToManifest(trashItem, trashDir: trashDir)
        return trashItem
    }

    func restoreTodoCard(_ trashItem: TrashItem) {
        guard let payload = trashItem.todoCardPayload else { return }

        let todoCardsDir = StoragePaths.directoryURL(for: .todos)
        let trashDir = todoCardsDir.appendingPathComponent(trashDirName)

        TodoCardStorage.shared.restoreFromTrash(payload.todoCard)
        removeFromManifest(trashItem.id, trashDir: trashDir)
    }

    // MARK: - Contact Trash

    func trashContact(_ contact: ContactCard, contactsDir: URL) -> TrashItem {
        let trashDir = contactsDir.appendingPathComponent(trashDirName)
        let fm = FileManager.default
        try? fm.createDirectory(at: trashDir, withIntermediateDirectories: true)

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
            trashAvatarRelativePath: trashAvatarRelPath,
            cascadedDateCardTrashIDs: cascadedIDs
        )

        let trashItem = TrashItem(
            itemID: contact.id,
            itemType: .contact,
            title: contact.displayName,
            originalFolderID: nil,
            contactPayload: payload
        )

        addToManifest(trashItem, trashDir: trashDir)
        return trashItem
    }

    func restoreContact(_ trashItem: TrashItem) {
        guard let payload = trashItem.contactPayload else { return }

        let contactsDir = StoragePaths.directoryURL(for: .contacts)
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

        // Restore cascaded birthday date cards
        let manifest = loadManifest(trashDir: trashDir)
        for cascadedID in payload.cascadedDateCardTrashIDs {
            if let cascadedItem = manifest.first(where: { $0.id == cascadedID }) {
                restoreDateCard(cascadedItem)
            }
        }

        removeFromManifest(trashItem.id, trashDir: trashDir)
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
        case .contact:
            restoreContact(trashItem)
        }
    }

    // MARK: - All Items

    func allTrashItems() -> [TrashItem] {
        let bookmarksDir = StoragePaths.directoryURL(for: .bookmarks)
        let notesDir = StoragePaths.directoryURL(for: .notes)
        let dateCardsDir = StoragePaths.directoryURL(for: .dateCards)
        let contactsDir = StoragePaths.directoryURL(for: .contacts)
        var items: [TrashItem] = []
        items += loadManifest(trashDir: bookmarksDir.appendingPathComponent(trashDirName))
        items += loadManifest(trashDir: notesDir.appendingPathComponent(trashDirName))
        items += loadManifest(trashDir: dateCardsDir.appendingPathComponent(trashDirName))
        items += loadManifest(trashDir: contactsDir.appendingPathComponent(trashDirName))
        return items.sorted { $0.deletedAt > $1.deletedAt }
    }

    // MARK: - Purge

    func purgeExpired(olderThan days: Int) {
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 3600)
        let trashTypes: [StorageType] = [.bookmarks, .notes, .dateCards, .todos, .contacts]
        for type in trashTypes {
            purgeExpired(
                olderThan: cutoff,
                in: StoragePaths.directoryURL(for: type).appendingPathComponent(trashDirName)
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
            let trashDir = StoragePaths.directoryURL(for: .bookmarks).appendingPathComponent(trashDirName)
            deleteFilesForItem(trashItem, trashDir: trashDir)
            removeFromManifest(trashItem.id, trashDir: trashDir)
        case .note:
            let trashDir = StoragePaths.directoryURL(for: .notes).appendingPathComponent(trashDirName)
            deleteFilesForItem(trashItem, trashDir: trashDir)
            removeFromManifest(trashItem.id, trashDir: trashDir)
        case .folder:
            for content in trashItem.folderContents ?? [] {
                permanentlyDelete(content)
            }
        case .dateCard:
            let trashDir = StoragePaths.directoryURL(for: .dateCards).appendingPathComponent(trashDirName)
            removeFromManifest(trashItem.id, trashDir: trashDir)
        case .todo:
            let trashDir = StoragePaths.directoryURL(for: .todos).appendingPathComponent(trashDirName)
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
        }
    }

    func emptyTrash() {
        let trashTypes: [StorageType] = [.bookmarks, .notes, .dateCards, .todos, .contacts]
        for type in trashTypes {
            let trashDir = StoragePaths.directoryURL(for: type).appendingPathComponent(trashDirName)
            let items = loadManifest(trashDir: trashDir)
            for item in items { deleteFilesForItem(item, trashDir: trashDir) }
            saveManifest([], trashDir: trashDir)
        }
    }

    // MARK: - Private Helpers

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
            break // No files to delete — data is in the manifest payload
        case .todo:
            break // No files to delete — data is in the manifest payload
        case .contact:
            if let payload = trashItem.contactPayload, let avatarRelPath = payload.trashAvatarRelativePath {
                try? fm.removeItem(at: trashDir.appendingPathComponent(avatarRelPath))
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
        manifest.insert(item, at: 0)
        saveManifest(manifest, trashDir: trashDir)
        NotificationCenter.default.post(name: .trashContentsChanged, object: nil)
    }

    private func removeFromManifest(_ itemID: UUID, trashDir: URL) {
        var manifest = loadManifest(trashDir: trashDir)
        manifest.removeAll { $0.id == itemID }
        saveManifest(manifest, trashDir: trashDir)
        NotificationCenter.default.post(name: .trashContentsChanged, object: nil)
    }
}
