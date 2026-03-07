import Foundation

enum TrashItemType: String, Codable {
    case bookmark
    case note
    case folder
    case dateCard
    case contact
    case todo
}

/// Payload stored alongside a trashed bookmark, containing the full bookmark data
/// and the trash-relative paths of moved image assets.
struct BookmarkTrashPayload: Codable {
    let bookmark: Bookmark
    /// Path of thumbnail relative to the `.trash/` directory (e.g. `"thumbnails/{id}.png"`).
    let trashThumbnailRelativePath: String?
    /// Path of original image relative to the `.trash/` directory.
    let trashOriginalRelativePath: String?
}

/// Payload stored alongside a trashed note.
struct NoteTrashPayload: Codable {
    let noteFilename: String
    let folderID: UUID?
    let createdAt: Date
}

/// Payload stored alongside a trashed date card.
struct DateCardTrashPayload: Codable {
    let dateCard: DateCard
}

/// Payload stored alongside a trashed todo card.
struct TodoCardTrashPayload: Codable {
    let todoCard: TodoCard
}

/// Payload stored alongside a trashed contact.
struct ContactTrashPayload: Codable {
    let contact: ContactCard
    /// Avatar path relative to `.trash/` if avatar was moved there.
    let trashAvatarRelativePath: String?
    /// IDs of birthday date cards trashed as part of this contact deletion.
    let cascadedDateCardTrashIDs: [UUID]
}

/// Represents a single item that has been moved to the trash.
struct TrashItem: Codable, Identifiable {
    var id: UUID
    let itemID: UUID
    let itemType: TrashItemType
    let title: String
    let originalFolderID: UUID?
    let deletedAt: Date

    // Bookmark-specific
    var bookmarkPayload: BookmarkTrashPayload?

    // Note-specific
    var notePayload: NoteTrashPayload?

    // Folder-specific (folder trash stores contents as child items)
    var folderContents: [TrashItem]?

    // Date card-specific
    var dateCardPayload: DateCardTrashPayload?

    // Todo-specific
    var todoCardPayload: TodoCardTrashPayload?

    // Contact-specific
    var contactPayload: ContactTrashPayload?

    init(
        id: UUID = UUID(),
        itemID: UUID,
        itemType: TrashItemType,
        title: String,
        originalFolderID: UUID?,
        deletedAt: Date = Date(),
        bookmarkPayload: BookmarkTrashPayload? = nil,
        notePayload: NoteTrashPayload? = nil,
        folderContents: [TrashItem]? = nil,
        dateCardPayload: DateCardTrashPayload? = nil,
        todoCardPayload: TodoCardTrashPayload? = nil,
        contactPayload: ContactTrashPayload? = nil
    ) {
        self.id = id
        self.itemID = itemID
        self.itemType = itemType
        self.title = title
        self.originalFolderID = originalFolderID
        self.deletedAt = deletedAt
        self.bookmarkPayload = bookmarkPayload
        self.notePayload = notePayload
        self.folderContents = folderContents
        self.dateCardPayload = dateCardPayload
        self.todoCardPayload = todoCardPayload
        self.contactPayload = contactPayload
    }
}
