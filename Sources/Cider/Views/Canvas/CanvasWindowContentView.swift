import SwiftUI

/// Root SwiftUI content for the canvas window.
struct CanvasWindowContentView: View {
    @ObservedObject var viewModel: CanvasViewModel
    @State private var panelDocked = false
    @State private var sidebarVisible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .leading) {
            NativeCanvasView(viewModel: viewModel)
                .frame(minWidth: 400, minHeight: 300)

            CanvasSidebarOverlay(isVisible: $sidebarVisible)

            if viewModel.selectedItemID != nil {
                CanvasDetailOverlay(viewModel: viewModel)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .animation(reduceMotion ? .none : .snappy(duration: 0.3), value: viewModel.selectedItemID)
            .onReceive(NotificationCenter.default.publisher(for: .panelDockStateChanged)) { notification in
                if let docked = notification.userInfo?["docked"] as? Bool {
                    panelDocked = docked
                }
            }
            .background {
                // Hidden button for Escape to deselect
                Button("") {
                    viewModel.deselectAll()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        NotificationCenter.default.post(name: .canvasFitAll, object: nil)
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .foregroundColor(CiderColors.secondary)
                    }
                    .help("Fit All (⌘0)")
                    .keyboardShortcut("0", modifiers: .command)
                }

                ToolbarItem(placement: .automatic) {
                    Button {
                        NotificationCenter.default.post(name: .canvasResetZoom, object: nil)
                    } label: {
                        Text("\(Int(viewModel.viewport.zoom * 100))%")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.secondary)
                            .frame(minWidth: 36)
                    }
                    .help("Reset to 100%")
                }

                ToolbarItem(placement: .automatic) {
                    Button {
                        sidebarVisible.toggle()
                    } label: {
                        Image(systemName: "sidebar.left")
                            .foregroundColor(CiderColors.secondary)
                    }
                    .help("Toggle Sidebar (⌘\\)")
                    .keyboardShortcut("\\", modifiers: .command)
                }

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
