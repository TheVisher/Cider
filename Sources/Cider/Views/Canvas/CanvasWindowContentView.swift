import SwiftUI

/// Root SwiftUI content for the canvas window.
struct CanvasWindowContentView: View {
    @ObservedObject var viewModel: CanvasViewModel
    @State private var sidebarVisible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .leading) {
            NativeCanvasView(viewModel: viewModel)
                .frame(minWidth: 400, minHeight: 300)

            CanvasSidebarOverlay(
                isVisible: $sidebarVisible,
                zoomLevel: viewModel.viewport.zoom,
                onCollapse: {
                    withAnimation(reduceMotion ? .none : .snappy(duration: 0.3)) {
                        sidebarVisible = false
                    }
                },
                onSelectFolder: { folderID in
                    guard let folderID else { return }
                    viewModel.panToFolder(folderID)
                }
            )

            // Collapsed pill — shows when sidebar is hidden
            if !sidebarVisible {
                collapsedPill
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topLeading)))
            }

            if viewModel.selectedItemID != nil {
                CanvasDetailOverlay(viewModel: viewModel)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? .none : .snappy(duration: 0.3), value: viewModel.selectedItemID)
        .animation(reduceMotion ? .none : .snappy(duration: 0.3), value: sidebarVisible)
        .background {
            // Hidden button for Escape to deselect
            Button("") {
                viewModel.deselectAll()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
        }
        .background {
            // Hidden button for sidebar toggle
            Button("") {
                sidebarVisible.toggle()
            }
            .keyboardShortcut("\\", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
        }
        .background {
            // Hidden button for fit all
            Button("") {
                NotificationCenter.default.post(name: .canvasFitAll, object: nil)
            }
            .keyboardShortcut("0", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
        }
        .onChange(of: sidebarVisible) { _, visible in
            // Sync sidebar state to the window for drag-region calculations
            (NSApp.keyWindow as? CanvasWindow)?.isSidebarVisible = visible
        }
    }

    // MARK: - Collapsed Pill

    /// Small floating pill in the top-left with traffic lights, zoom, and expand button.
    private var collapsedPill: some View {
        HStack(spacing: CiderPanelDesign.trafficLightSpacing) {
            // Traffic lights
            PanelTrafficLightButton(
                color: .systemRed,
                symbol: "xmark",
                help: "Close window"
            ) {
                NSApp.keyWindow?.close()
            }
            PanelTrafficLightButton(
                color: .systemYellow,
                symbol: "minus",
                help: "Minimize"
            ) {
                NSApp.keyWindow?.miniaturize(nil)
            }
            PanelTrafficLightButton(
                color: .systemGreen,
                symbol: "arrow.up.left.and.arrow.down.right",
                help: "Zoom"
            ) {
                NSApp.keyWindow?.zoom(nil)
            }

            Divider()
                .frame(height: CiderPanelDesign.trafficLightDiameter)
                .padding(.horizontal, Spacing.xxs)

            // Zoom level
            Button {
                NotificationCenter.default.post(name: .canvasResetZoom, object: nil)
            } label: {
                Text("\(Int(viewModel.viewport.zoom * 100))%")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
                    .frame(minWidth: 30)
            }
            .buttonStyle(.plain)
            .help("Reset to 100%")

            // Fit all
            Button {
                NotificationCenter.default.post(name: .canvasFitAll, object: nil)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
            }
            .buttonStyle(.plain)
            .help("Fit All (⌘0)")

            Divider()
                .frame(height: CiderPanelDesign.trafficLightDiameter)
                .padding(.horizontal, Spacing.xxs)

            // Expand sidebar
            Button {
                withAnimation(reduceMotion ? .none : .snappy(duration: 0.3)) {
                    sidebarVisible = true
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.secondary)
            }
            .buttonStyle(.plain)
            .help("Show sidebar (⌘\\)")
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background {
            VisualEffectView(
                material: .underWindowBackground,
                blendingMode: .withinWindow
            )
        }
        .clipShape(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(CiderColors.borderDefault, lineWidth: CiderBorder.innerStrokeWidth)
        )
        .shadow(color: CiderColors.shadowLight, radius: 6, x: 0, y: 2)
        .padding(.leading, Spacing.md)
        .padding(.top, Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
