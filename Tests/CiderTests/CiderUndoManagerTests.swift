import Foundation
import Testing
@testable import Cider

private final class UndoToastMessageStore: @unchecked Sendable {
    var messages: [String] = []
}

@MainActor
struct CiderUndoManagerTests {
    @Test("single move undo failure posts a visible failure toast")
    func singleMoveUndoFailurePostsVisibleFailureToast() {
        let store = UndoToastMessageStore()
        let observer = NotificationCenter.default.addObserver(
            forName: .showUndoToast,
            object: nil,
            queue: nil
        ) { notification in
            if let message = notification.userInfo?["message"] as? String {
                store.messages.append(message)
            }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
            CiderUndoManager.shared.discard()
        }

        CiderUndoManager.shared.discard()
        CiderUndoManager.shared.record(.movedToFolder(
            itemType: .note,
            itemID: UUID(),
            title: "Missing Note",
            fromFolderID: nil,
            toFolderID: UUID(),
            folderName: "Target"
        ))

        store.messages.removeAll()
        CiderUndoManager.shared.undo()

        #expect(store.messages == ["Undo failed for 'Missing Note'"])
    }

    @Test("bulk move undo reports failed rollback count")
    func bulkMoveUndoFailurePostsVisibleFailureToast() {
        let store = UndoToastMessageStore()
        let observer = NotificationCenter.default.addObserver(
            forName: .showUndoToast,
            object: nil,
            queue: nil
        ) { notification in
            if let message = notification.userInfo?["message"] as? String {
                store.messages.append(message)
            }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
            CiderUndoManager.shared.discard()
        }

        CiderUndoManager.shared.discard()
        CiderUndoManager.shared.record(.bulkMoved([
            BulkMoveItem(itemID: UUID(), itemType: .note, title: "Missing Note", fromFolderID: nil),
            BulkMoveItem(itemID: UUID(), itemType: .todo, title: "Missing Todo", fromFolderID: nil),
        ], toFolderID: UUID(), folderName: "Target"))

        store.messages.removeAll()
        CiderUndoManager.shared.undo()

        #expect(store.messages == ["Undo restored 0 of 2 moved items; 2 failed"])
    }
}
