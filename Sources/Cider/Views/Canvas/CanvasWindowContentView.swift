import SwiftUI

/// Root SwiftUI content for the canvas window.
struct CanvasWindowContentView: View {
    @ObservedObject var viewModel: CanvasViewModel
    @State private var panelDocked = false

    var body: some View {
        NativeCanvasView(viewModel: viewModel)
            .frame(minWidth: 400, minHeight: 300)
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
