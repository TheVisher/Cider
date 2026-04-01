import SwiftUI

/// Root SwiftUI content for the canvas window.
/// Sidebar + canvas side by side.
struct CanvasWindowContentView: View {
    @ObservedObject var viewModel: CanvasViewModel
    @State private var panelDocked = false

    var body: some View {
        CanvasView(viewModel: viewModel)
            .frame(minWidth: 400, minHeight: 300)
            .onReceive(NotificationCenter.default.publisher(for: .panelDockStateChanged)) { notification in
                if let docked = notification.userInfo?["docked"] as? Bool {
                    panelDocked = docked
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        NotificationCenter.default.post(name: .togglePanelDock, object: nil)
                    } label: {
                        Image(systemName: panelDocked ? "macwindow.badge.plus" : "macwindow.on.rectangle")
                            .foregroundColor(CiderColors.secondary)
                    }
                    .help(panelDocked ? "Undock Library Panel" : "Dock Library Panel")
                }
            }
    }
}
