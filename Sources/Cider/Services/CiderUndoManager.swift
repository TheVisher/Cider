import Foundation

struct BulkMoveItem {
    let itemID: UUID
    let itemType: TrashItemType
    let title: String
    let fromFolderID: UUID?
}

enum UndoAction {
    case deletedToTrash(itemType: TrashItemType, trashItem: TrashItem)
    case bulkDeletedToTrash([TrashItem])
    case movedToFolder(
        itemType: TrashItemType,
        itemID: UUID,
        title: String,
        fromFolderID: UUID?,
        toFolderID: UUID?,
        folderName: String
    )
    case bulkMoved([BulkMoveItem], toFolderID: UUID?, folderName: String)
    case renamed(itemType: TrashItemType, itemID: UUID, oldTitle: String, newTitle: String)
}

@MainActor
final class CiderUndoManager {
    static let shared = CiderUndoManager()
    private(set) var pendingAction: UndoAction?

    private init() {}

    func record(_ action: UndoAction) {
        pendingAction = action

        let message: String
        let showViewTrash: Bool

        switch action {
        case .deletedToTrash(_, let trashItem):
            message = "Moved '\(trashItem.title)' to Trash"
            showViewTrash = true

        case .bulkDeletedToTrash(let items):
            if items.count == 1 {
                message = "Moved '\(items[0].title)' to Trash"
            } else {
                message = "Moved \(items.count) items to Trash"
            }
            showViewTrash = true

        case .movedToFolder(_, _, let title, _, _, let folderName):
            message = "Moved '\(title)' to \(folderName)"
            showViewTrash = false

        case .bulkMoved(let items, _, let folderName):
            if items.count == 1 {
                message = "Moved '\(items[0].title)' to \(folderName)"
            } else {
                message = "Moved \(items.count) items to \(folderName)"
            }
            showViewTrash = false

        case .renamed(_, _, _, let newTitle):
            message = "Renamed to '\(newTitle)'"
            showViewTrash = false
        }

        NotificationCenter.default.post(
            name: .showUndoToast,
            object: nil,
            userInfo: ["message": message, "showViewTrash": showViewTrash]
        )
    }

    func undo() {
        guard let action = pendingAction else { return }
        pendingAction = nil

        switch action {
        case .deletedToTrash(_, let trashItem):
            TrashStorage.shared.restore(trashItem)

        case .bulkDeletedToTrash(let items):
            for item in items {
                TrashStorage.shared.restore(item)
            }

        case .movedToFolder(let itemType, let itemID, _, let fromFolderID, _, _):
            switch itemType {
            case .bookmark:
                VaultBookmarkService.shared.assignBookmark(itemID, toFolder: fromFolderID)
            case .note:
                NotesStorage.shared.assignNote(itemID, toFolder: fromFolderID)
            case .dateCard:
                DateCardStorage.shared.assignDateCard(itemID, toFolder: fromFolderID)
            case .contact:
                ContactStorage.shared.assignContact(itemID, toFolder: fromFolderID)
            case .todo:
                TodoCardStorage.shared.assignTodoCard(itemID, toFolder: fromFolderID)
            case .session:
                break // Sessions feature removed
            case .vaultFile:
                VaultFileService.shared.assignFile(itemID, toFolder: fromFolderID)
            case .folder, .vaultFolder, .kanbanBoard:
                break
            }

        case .bulkMoved(let items, _, _):
            for item in items {
                switch item.itemType {
                case .bookmark:
                    VaultBookmarkService.shared.assignBookmark(item.itemID, toFolder: item.fromFolderID)
                case .note:
                    NotesStorage.shared.assignNote(item.itemID, toFolder: item.fromFolderID)
                case .dateCard:
                    DateCardStorage.shared.assignDateCard(item.itemID, toFolder: item.fromFolderID)
                case .contact:
                    ContactStorage.shared.assignContact(item.itemID, toFolder: item.fromFolderID)
                case .todo:
                    TodoCardStorage.shared.assignTodoCard(item.itemID, toFolder: item.fromFolderID)
                case .session:
                    break // Sessions feature removed
                case .vaultFile:
                    VaultFileService.shared.assignFile(item.itemID, toFolder: item.fromFolderID)
                case .folder, .vaultFolder, .kanbanBoard:
                    break
                }
            }

        case .renamed(let itemType, let itemID, let oldTitle, _):
            switch itemType {
            case .bookmark:
                if let bm = VaultBookmarkService.shared.bookmarks.first(where: { $0.id == itemID }) {
                    VaultBookmarkService.shared.updateDetails(
                        for: itemID,
                        title: oldTitle,
                        notes: bm.notes,
                        tags: bm.tags
                    )
                }
            case .note:
                if let note = NotesStorage.shared.notes.first(where: { $0.id == itemID }) {
                    NotesStorage.shared.rename(note: note, to: oldTitle)
                }
            case .dateCard:
                if var dateCard = DateCardStorage.shared.dateCard(for: itemID) {
                    dateCard.title = oldTitle
                    _ = DateCardStorage.shared.updateDateCard(dateCard)
                }
            case .contact:
                if var contact = ContactStorage.shared.contact(for: itemID) {
                    contact.displayName = oldTitle
                    _ = ContactStorage.shared.updateContact(contact)
                }
            case .todo:
                if var todoCard = TodoCardStorage.shared.todoCard(for: itemID) {
                    todoCard.title = oldTitle
                    _ = TodoCardStorage.shared.updateTodoCard(todoCard)
                }
            case .folder:
                break
            case .vaultFolder:
                _ = VaultFolderService.shared.renameFolder(itemID, to: oldTitle)
            case .session:
                break // Sessions feature removed
            case .kanbanBoard:
                break
            case .vaultFile:
                if let file = VaultFileService.shared.file(for: itemID) {
                    VaultFileStorage.shared.updateTitle(file, title: oldTitle)
                }
                VaultFileService.shared.scan()
            }
        }
    }

    func discard() {
        pendingAction = nil
    }
}
