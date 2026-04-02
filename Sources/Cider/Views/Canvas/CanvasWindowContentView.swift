import SwiftUI

/// Root SwiftUI content for the canvas window.
struct CanvasWindowContentView: View {
    @ObservedObject var viewModel: CanvasViewModel
    @State private var sidebarVisible = true
    @State private var isSearchVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
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

                // Detail modal with backdrop
                if viewModel.selectedItemID != nil {
                    CanvasDetailOverlay(
                        viewModel: viewModel,
                        canvasSize: geometry.size,
                        isSidebarVisible: sidebarVisible,
                        onDismiss: { viewModel.deselectAll() }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .zIndex(2)
                }

                // Search palette
                if isSearchVisible {
                    CanvasSearchOverlay(
                        viewModel: viewModel,
                        canvasSize: geometry.size,
                        isSidebarVisible: sidebarVisible,
                        onDismiss: { isSearchVisible = false }
                    )
                    .transition(.opacity)
                    .zIndex(3)
                }
            }
            .ignoresSafeArea()
            .animation(reduceMotion ? .none : .snappy(duration: 0.25), value: viewModel.selectedItemID)
            .animation(reduceMotion ? .none : .snappy(duration: 0.3), value: sidebarVisible)
            .animation(reduceMotion ? .none : .snappy(duration: 0.25), value: isSearchVisible)
        }
        .background {
            // Hidden button for Escape — dismiss search first, then deselect
            Button("") {
                if isSearchVisible {
                    isSearchVisible = false
                } else {
                    viewModel.deselectAll()
                }
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
        .background {
            // Hidden button for search palette
            Button("") {
                isSearchVisible.toggle()
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
        }
        .onChange(of: viewModel.selectedItemID) { _, newID in
            // Dismiss search palette when a card is clicked directly on canvas
            if newID != nil, isSearchVisible {
                isSearchVisible = false
            }
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
