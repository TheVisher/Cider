import SwiftUI

struct UtilityPanelRootView: View {
    @ObservedObject var coordinator: UtilityPanelCoordinator
    @ObservedObject var bookmarksViewModel: BookmarksViewModel
    @ObservedObject var notesViewModel: NotesViewModel
    let onClose: () -> Void
    let onMaximize: () -> Void

    var body: some View {
        UtilityPanelShell(
            coordinator: coordinator,
            onClose: onClose,
            onMaximize: onMaximize
        ) {
            UtilityPanelContentView(
                coordinator: coordinator,
                bookmarksViewModel: bookmarksViewModel,
                notesViewModel: notesViewModel
            )
        }
    }
}
