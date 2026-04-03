import SwiftUI

/// Canvas command palette overlay.
/// Wraps the NSPanel's SearchPaletteView. Selecting a result flies the canvas
/// to that card and opens the existing CanvasDetailOverlay modal.
struct CanvasSearchOverlay: View {
    @ObservedObject var viewModel: CanvasViewModel
    let canvasSize: CGSize
    let isSidebarVisible: Bool
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        paletteView
    }

    // MARK: - Palette

    private var paletteView: some View {
        SearchPaletteView(
            bookmarks: Array(viewModel.bookmarkLookup.values),
            notes: Array(viewModel.noteLookup.values),
            onOpenBookmark: { bookmark in
                viewModel.panToItem(bookmark.id.uuidString)
                viewModel.selectedItemID = bookmark.id.uuidString
                if CiderConfig.load().useNewPanel {
                    NotificationCenter.default.post(
                        name: .openBookmarkDetails,
                        object: nil,
                        userInfo: ["bookmarkID": bookmark.id]
                    )
                }
            },
            onOpenNote: { note in
                viewModel.panToItem(note.id.uuidString)
                viewModel.selectedItemID = note.id.uuidString
                if CiderConfig.load().useNewPanel {
                    NotificationCenter.default.post(
                        name: .openNoteDetails,
                        object: nil,
                        userInfo: ["noteID": note.id]
                    )
                }
            },
            onOpenDateCard: nil,
            onOpenContact: nil,
            onOpenTodo: { todo in
                viewModel.panToItem(todo.id.uuidString)
                viewModel.selectedItemID = todo.id.uuidString
                if CiderConfig.load().useNewPanel {
                    NotificationCenter.default.post(
                        name: .openTodoDetails,
                        object: nil,
                        userInfo: ["todoID": todo.id]
                    )
                }
            },
            onSpawnSearchTab: nil,
            onDismiss: { onDismiss() },
            onAction: { _ in
                onDismiss()
            },
            onSelectTag: nil,
            onOpenInPanel: { query, results in
                NotificationCenter.default.post(
                    name: .openSearchInPanel,
                    object: nil,
                    userInfo: ["query": query, "results": results]
                )
            },
            dismissOnResultSelect: false
        )
    }
}
