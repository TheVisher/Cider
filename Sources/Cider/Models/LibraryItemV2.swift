import Foundation

enum LibraryItemV2: Identifiable, Hashable {
    case bookmark(Bookmark)
    case note(Note)
    case dateCard(DateCard)
    case contact(ContactCard)
    case todo(TodoCard)
    case externalFile(ExternalFile)

    var id: String {
        switch self {
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
        case .externalFile(let file):
            "externalfile-\(file.id.uuidString)"
        }
    }

    var entityType: LibraryEntityType {
        switch self {
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
        case .externalFile:
            .externalFile
        }
    }

    var createdDate: Date {
        switch self {
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
        case .externalFile(let file):
            file.createdAt
        }
    }

    var updatedDate: Date {
        switch self {
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
        case .externalFile(let file):
            file.modifiedAt
        }
    }

    var title: String {
        switch self {
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
        case .externalFile(let file):
            file.title
        }
    }

    var folderID: UUID? {
        switch self {
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
        case .externalFile:
            nil
        }
    }

    var labelIDs: Set<UUID> {
        switch self {
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
        case .externalFile:
            return []
        }
    }

    var dateAnchor: Date? {
        switch self {
        case .dateCard(let dateCard):
            return dateCard.startAt
        case .contact(let contact):
            return contact.birthday
        case .todo(let todo):
            return todo.dueDate
        case .bookmark, .note, .externalFile:
            return nil
        }
    }

    var isCompleted: Bool {
        switch self {
        case .dateCard(let dateCard):
            return dateCard.isCompleted
        case .todo(let todo):
            return todo.isCompleted
        case .bookmark, .note, .contact, .externalFile:
            return false
        }
    }
}
