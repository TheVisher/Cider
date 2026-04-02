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
            },
            onOpenNote: { note in
                viewModel.panToItem(note.id.uuidString)
                viewModel.selectedItemID = note.id.uuidString
            },
            onOpenDateCard: nil,
            onOpenContact: nil,
            onOpenTodo: { todo in
                viewModel.panToItem(todo.id.uuidString)
                viewModel.selectedItemID = todo.id.uuidString
            },
            onSpawnSearchTab: nil,
            onDismiss: { onDismiss() },
            onAction: { _ in
                onDismiss()
            },
            onSelectTag: nil,
            dismissOnResultSelect: false
        )
    }
}
