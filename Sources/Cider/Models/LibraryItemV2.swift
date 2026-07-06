import Foundation

enum LibraryItemV2: Identifiable, Hashable {
    case journal(JournalLibraryContainer)
    case bookmark(Bookmark)
    case note(Note)
    case dateCard(DateCard)
    case contact(ContactCard)
    case todo(TodoCard)
    case vaultFile(VaultFile)

    var id: String {
        switch self {
        case .journal:
            "journal-\(JournalLibraryContainer.id)"
        case .bookmark(let bookmark):
            "bookmark-\(bookmark.id.uuidString)"
        case .note(let note):
            "note-\(note.id.uuidString)"
        case .dateCard(let dateCard):
            "datecard-\(dateCard.id.uuidString)"
        case .contact(let contact):
            "contact-\(contact.id.uuidString)"
        case .todo(let todo):
            "todo-\(todo.id.uuidString)"
        case .vaultFile(let file):
            "vaultfile-\(file.id.uuidString)"
        }
    }

    var entityType: LibraryEntityType {
        switch self {
        case .journal:
            .note
        case .bookmark:
            .bookmark
        case .note:
            .note
        case .dateCard:
            .dateCard
        case .contact:
            .contact
        case .todo:
            .todo
        case .vaultFile:
            .vaultFile
        }
    }

    var createdDate: Date {
        switch self {
        case .journal(let journal):
            journal.createdDate
        case .bookmark(let bookmark):
            bookmark.createdAt
        case .note(let note):
            note.createdAt
        case .dateCard(let dateCard):
            dateCard.createdAt
        case .contact(let contact):
            contact.createdAt
        case .todo(let todo):
            todo.createdAt
        case .vaultFile(let file):
            file.createdAt
        }
    }

    var updatedDate: Date {
        switch self {
        case .journal(let journal):
            journal.updatedDate
        case .bookmark(let bookmark):
            bookmark.updatedAt
        case .note(let note):
            note.modifiedAt
        case .dateCard(let dateCard):
            dateCard.updatedAt
        case .contact(let contact):
            contact.updatedAt
        case .todo(let todo):
            todo.updatedAt
        case .vaultFile(let file):
            file.modifiedAt
        }
    }

    var title: String {
        switch self {
        case .journal(let journal):
            journal.title
        case .bookmark(let bookmark):
            bookmark.title
        case .note(let note):
            note.title
        case .dateCard(let dateCard):
            dateCard.title
        case .contact(let contact):
            contact.displayName
        case .todo(let todo):
            todo.title
        case .vaultFile(let file):
            file.filename
        }
    }

    var folderID: UUID? {
        switch self {
        case .journal:
            nil
        case .bookmark(let bookmark):
            bookmark.folderID
        case .note(let note):
            note.folderID
        case .dateCard(let dateCard):
            dateCard.folderID
        case .contact(let contact):
            contact.folderID
        case .todo(let todo):
            todo.folderID
        case .vaultFile(let file):
            file.folderID
        }
    }

    var isInboxItem: Bool {
        switch self {
        case .journal:
            return true
        case .bookmark(let bookmark):
            return isInboxPath(bookmark.relativePath) || (bookmark.relativePath?.isEmpty != false && bookmark.folderID == nil)
        case .note(let note):
            return isInboxPath(note.relativePath) || (note.relativePath.isEmpty && note.folderID == nil)
        case .vaultFile(let file):
            return isInboxPath(file.relativePath)
        case .dateCard(let dateCard):
            return dateCard.folderID == nil
        case .contact(let contact):
            return contact.folderID == nil
        case .todo(let todoCard):
            return todoCard.folderID == nil
        }
    }

    var labelIDs: Set<UUID> {
        switch self {
        case .journal:
            return []
        case .bookmark(let bookmark):
            return Set(bookmark.labelIDs)
        case .note(let note):
            return Set(note.labelIDs)
        case .dateCard(let dateCard):
            return Set(dateCard.labelIDs)
        case .contact(let contact):
            return Set(contact.labelIDs)
        case .todo(let todo):
            return Set(todo.labelIDs)
        case .vaultFile(let file):
            return Set(file.labelIDs)
        }
    }

    private func isInboxPath(_ path: String?) -> Bool {
        guard let path else { return false }
        return path.lowercased().hasPrefix("inbox/")
    }

    var dateAnchor: Date? {
        switch self {
        case .journal:
            return nil
        case .dateCard(let dateCard):
            return dateCard.startAt
        case .contact(let contact):
            return contact.birthday
        case .todo(let todo):
            return todo.earliestApproachingDate
        case .bookmark, .note, .vaultFile:
            return nil
        }
    }

    var isCompleted: Bool {
        switch self {
        case .journal:
            return false
        case .dateCard(let dateCard):
            return dateCard.isCompleted
        case .todo(let todo):
            return todo.isCompleted
        case .bookmark, .note, .contact, .vaultFile:
            return false
        }
    }
}
