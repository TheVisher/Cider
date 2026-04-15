import Foundation

enum TrashItemType: String, Codable {
    case bookmark
    case note
    case folder
    case dateCard
    case contact
    case todo
    case vaultFolder
    case session
    case kanbanBoard
    case vaultFile
}

/// Payload stored alongside a trashed bookmark, containing the full bookmark data
/// and the trash-relative paths of moved image assets.
struct BookmarkTrashPayload: Codable {
    let bookmark: Bookmark
    /// Path of thumbnail relative to the `.trash/` directory (e.g. `"thumbnails/{id}.png"`).
    let trashThumbnailRelativePath: String?
    /// Path of original image relative to the `.trash/` directory.
    let trashOriginalRelativePath: String?
    /// Paths of carousel images relative to the `.trash/` directory.
    let trashCarouselRelativePaths: [String]?

    init(bookmark: Bookmark, trashThumbnailRelativePath: String?, trashOriginalRelativePath: String?, trashCarouselRelativePaths: [String]? = nil) {
        self.bookmark = bookmark
        self.trashThumbnailRelativePath = trashThumbnailRelativePath
        self.trashOriginalRelativePath = trashOriginalRelativePath
        self.trashCarouselRelativePaths = trashCarouselRelativePaths
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bookmark = try c.decode(Bookmark.self, forKey: .bookmark)
        trashThumbnailRelativePath = try c.decodeIfPresent(String.self, forKey: .trashThumbnailRelativePath)
        trashOriginalRelativePath = try c.decodeIfPresent(String.self, forKey: .trashOriginalRelativePath)
        trashCarouselRelativePaths = try c.decodeIfPresent([String].self, forKey: .trashCarouselRelativePaths)
    }
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
    /// The .ics filename moved to `.trash/`, if any.
    let trashICSFilename: String?

    /// Backward-compatible decoder: trashICSFilename may not exist in older payloads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dateCard = try c.decode(DateCard.self, forKey: .dateCard)
        trashICSFilename = try c.decodeIfPresent(String.self, forKey: .trashICSFilename)
    }

    init(dateCard: DateCard, trashICSFilename: String? = nil) {
        self.dateCard = dateCard
        self.trashICSFilename = trashICSFilename
    }
}

/// Payload stored alongside a trashed todo card.
struct TodoCardTrashPayload: Codable {
    let todoCard: TodoCard
    /// The .ics filename moved to `.trash/`, if any.
    let trashICSFilename: String?

    /// Backward-compatible decoder: trashICSFilename may not exist in older payloads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        todoCard = try c.decode(TodoCard.self, forKey: .todoCard)
        trashICSFilename = try c.decodeIfPresent(String.self, forKey: .trashICSFilename)
    }

    init(todoCard: TodoCard, trashICSFilename: String? = nil) {
        self.todoCard = todoCard
        self.trashICSFilename = trashICSFilename
    }
}

/// Payload stored alongside a trashed kanban board.
struct KanbanBoardTrashPayload: Codable {
    let yamlContent: String
    let boardID: String
}

/// Payload stored alongside a trashed contact.
struct ContactTrashPayload: Codable {
    let contact: ContactCard
    /// The .vcf filename moved to `.trash/`, if any.
    let trashVCFFilename: String?
    /// Avatar path relative to `.trash/` if avatar was moved there.
    let trashAvatarRelativePath: String?
    /// IDs of birthday date cards trashed as part of this contact deletion.
    let cascadedDateCardTrashIDs: [UUID]

    /// Backward-compatible decoder: trashVCFFilename may not exist in older payloads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        contact = try c.decode(ContactCard.self, forKey: .contact)
        trashVCFFilename = try c.decodeIfPresent(String.self, forKey: .trashVCFFilename)
        trashAvatarRelativePath = try c.decodeIfPresent(String.self, forKey: .trashAvatarRelativePath)
        cascadedDateCardTrashIDs = (try c.decodeIfPresent([UUID].self, forKey: .cascadedDateCardTrashIDs)) ?? []
    }

    init(contact: ContactCard, trashVCFFilename: String? = nil, trashAvatarRelativePath: String?, cascadedDateCardTrashIDs: [UUID]) {
        self.contact = contact
        self.trashVCFFilename = trashVCFFilename
        self.trashAvatarRelativePath = trashAvatarRelativePath
        self.cascadedDateCardTrashIDs = cascadedDateCardTrashIDs
    }
}

/// Payload stored alongside a trashed vault file.
struct VaultFileTrashPayload: Codable {
    let vaultFile: VaultFile
    /// The filename moved to `.trash/`, if any.
    let trashFilename: String?

    /// Backward-compatible decoder: trashFilename may not exist in older payloads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vaultFile = try c.decode(VaultFile.self, forKey: .vaultFile)
        trashFilename = try c.decodeIfPresent(String.self, forKey: .trashFilename)
    }

    init(vaultFile: VaultFile, trashFilename: String?) {
        self.vaultFile = vaultFile
        self.trashFilename = trashFilename
    }
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

    // Vault folder-specific
    var vaultFolderPayload: VaultFolderTrashPayload?

    // Kanban board-specific
    var kanbanBoardPayload: KanbanBoardTrashPayload?

    // Vault file-specific
    var vaultFilePayload: VaultFileTrashPayload?

    /// User-facing title for trash listings.
    /// Some older/generated items carried Unix timestamp suffixes in their raw
    /// title (for example test/import names like "CodexNote-1775948805 2").
    /// We keep the stored value intact for restore/debugging, but hide that
    /// suffix in the trash UI so rows read like normal item names.
    var displayTitle: String {
        Self.cleanedDisplayTitle(title)
    }

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
        contactPayload: ContactTrashPayload? = nil,
        vaultFolderPayload: VaultFolderTrashPayload? = nil,
        kanbanBoardPayload: KanbanBoardTrashPayload? = nil,
        vaultFilePayload: VaultFileTrashPayload? = nil
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
        self.vaultFolderPayload = vaultFolderPayload
        self.kanbanBoardPayload = kanbanBoardPayload
        self.vaultFilePayload = vaultFilePayload
    }

    private static func cleanedDisplayTitle(_ rawTitle: String) -> String {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rawTitle }

        let pattern = #"^(.*?)(?:[- ]\d{10,})(?: (\d+))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return trimmed }
        let nsRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: nsRange),
              match.numberOfRanges >= 2,
              let baseRange = Range(match.range(at: 1), in: trimmed) else {
            return trimmed
        }

        var cleaned = String(trimmed[baseRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if match.numberOfRanges >= 3,
           let suffixRange = Range(match.range(at: 2), in: trimmed) {
            let suffix = trimmed[suffixRange].trimmingCharacters(in: .whitespacesAndNewlines)
            if !suffix.isEmpty {
                cleaned = "\(cleaned) \(suffix)"
            }
        }

        return cleaned.isEmpty ? trimmed : cleaned
    }
}
