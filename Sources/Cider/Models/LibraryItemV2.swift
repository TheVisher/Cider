import Foundation

enum LibraryItemV2: Identifiable, Hashable {
    case bookmark(Bookmark)
    case note(Note)
    case dateCard(DateCard)
    case contact(ContactCard)
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
        case .dateCard:
            nil
        case .contact:
            nil
        case .externalFile:
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
        case .bookmark, .note, .externalFile:
            return nil
        }
    }

    var isCompleted: Bool {
        switch self {
        case .dateCard(let dateCard):
            return dateCard.isCompleted
        case .bookmark, .note, .contact, .externalFile:
            return false
        }
    }
}
