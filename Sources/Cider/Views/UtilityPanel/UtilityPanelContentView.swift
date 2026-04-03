import SwiftUI

struct UtilityPanelContentView: View {
    @ObservedObject var coordinator: UtilityPanelCoordinator
    @ObservedObject var bookmarksViewModel: BookmarksViewModel
    @ObservedObject var notesViewModel: NotesViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch coordinator.activeItem {
            case .bookmark(let id):
                UtilityPanelBookmarkDetail(
                    bookmarkID: id,
                    bookmarksViewModel: bookmarksViewModel
                )
            case .note(let id):
                UtilityPanelNoteDetail(
                    noteID: id,
                    notesViewModel: notesViewModel
                )
            case .todo(let id):
                UtilityPanelTodoDetail(todoID: id)
            case nil:
                PlaceholderMode().contentView
            }
        }
        .animation(reduceMotion ? .none : .snappy, value: coordinator.activeItem)
    }
}
