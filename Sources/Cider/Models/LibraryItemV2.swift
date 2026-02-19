import Foundation

enum LibraryItemV2: Identifiable, Hashable {
    case bookmark(Bookmark)
    case note(Note)
    case dateCard(DateCard)
    case contact(ContactCard)

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
        }
    }

    var folderID: UUID? {
        switch self {
        case .bookmark(let bookmark):
            bookmark.folderID
        case .note(let note):
            note.folderID
        case .dateCard:
            nil
        case .contact:
            nil
        }
    }

    var labelIDs: Set<UUID> {
        switch self {
        case .bookmark:
            return []
        case .note:
            return []
        case .dateCard(let dateCard):
            return Set(dateCard.labelIDs)
        case .contact(let contact):
            return Set(contact.labelIDs)
        }
    }

    var dateAnchor: Date? {
        switch self {
        case .dateCard(let dateCard):
            return dateCard.startAt
        case .contact(let contact):
            return contact.birthday
        case .bookmark, .note:
            return nil
        }
    }

    var isCompleted: Bool {
        switch self {
        case .dateCard(let dateCard):
            return dateCard.isCompleted
        case .bookmark, .note, .contact:
            return false
        }
    }
}
