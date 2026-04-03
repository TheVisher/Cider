import SwiftUI

struct UtilityPanelContentView: View {
    @ObservedObject var coordinator: UtilityPanelCoordinator
    @ObservedObject var bookmarksViewModel: BookmarksViewModel
    @ObservedObject var notesViewModel: NotesViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let tool = coordinator.activeTool {
                toolView(for: tool)
            } else {
                itemView
            }
        }
        .animation(reduceMotion ? .none : .snappy, value: coordinator.activeTool)
        .animation(reduceMotion ? .none : .snappy, value: coordinator.activeItem)
    }

    @ViewBuilder
    private func toolView(for tool: ToolMode) -> some View {
        switch tool {
        case .search:
            PanelSearchResultsView(coordinator: coordinator)
        case .clipboard:
            ClipboardViewerView()
        case .aiChat:
            AIAssistantPanelView(viewModel: AIAssistantViewModel.shared, isStandalone: false)
        case .capture:
            PlaceholderMode().contentView
        }
    }

    @ViewBuilder
    private var itemView: some View {
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
}
