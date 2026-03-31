import SwiftUI

/// Root SwiftUI content for the canvas window.
/// Sidebar + canvas side by side.
struct CanvasWindowContentView: View {
    @ObservedObject var viewModel: CanvasViewModel
    @ObservedObject var bookmarksViewModel: BookmarksViewModel
    @State private var showSidebar = true

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                CanvasSidebarView(
                    bookmarksViewModel: bookmarksViewModel,
                    onSelectFolder: { folderID in
                        viewModel.panToFolder(folderID)
                    },
                    onSelectAll: {
                        viewModel.fitAll()
                    }
                )
                .transition(.move(edge: .leading))

                Divider()
            }

            CanvasView(viewModel: viewModel)
                .frame(minWidth: 400, minHeight: 300)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        showSidebar.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .foregroundColor(CiderColors.secondary)
                }
                .help("Toggle Sidebar")
            }
        }
    }
}
