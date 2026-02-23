import SwiftUI
import AppKit

/// Shared structural shell for all panel windows.
///
/// Encapsulates the two-column layout, sidebar container, traffic lights,
/// title bar, divider, compact mode logic, resize handles, and shadow padding.
/// Callers provide the sidebar content, footer, title bar content, main content,
/// and an optional panel-level overlay (e.g. search palette).
struct CiderPanelShell<
    SidebarContent: View,
    SidebarFooter: View,
    TitleBarContent: View,
    Content: View,
    PanelOverlay: View
>: View {
    let isCollapsed: Bool
    let suppressSidebarAutoExpand: Bool
    let blurRightColumn: Bool
    let onClose: () -> Void
    let onCollapse: () -> Void
    let onMaximize: () -> Void
    let sidebarContent: SidebarContent
    let sidebarFooter: SidebarFooter
    let titleBarContent: TitleBarContent
    let content: Content
    let panelOverlay: PanelOverlay

    @State private var isSidebarVisible = true
    @State private var isCompactMode = false
    @State private var sidebarAutoCollapsed = false
    @State private var showTitleBarToggle = false
    @State private var toggleAppearTask: Task<Void, Never>?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        isCollapsed: Bool,
        suppressSidebarAutoExpand: Bool = false,
        blurRightColumn: Bool = false,
        onClose: @escaping () -> Void,
        onCollapse: @escaping () -> Void,
        onMaximize: @escaping () -> Void,
        @ViewBuilder sidebarContent: () -> SidebarContent,
        @ViewBuilder sidebarFooter: () -> SidebarFooter,
        @ViewBuilder titleBar: () -> TitleBarContent,
        @ViewBuilder content: () -> Content,
        @ViewBuilder overlay: () -> PanelOverlay
    ) {
        self.isCollapsed = isCollapsed
        self.suppressSidebarAutoExpand = suppressSidebarAutoExpand
        self.blurRightColumn = blurRightColumn
        self.onClose = onClose
        self.onCollapse = onCollapse
        self.onMaximize = onMaximize
        self.sidebarContent = sidebarContent()
        self.sidebarFooter = sidebarFooter()
        self.titleBarContent = titleBar()
        self.content = content()
        self.panelOverlay = overlay()
    }

    var body: some View {
        ZStack {
            AcrylicPanelBackground(
                cornerRadius: CiderPanelDesign.cornerRadius,
                shadowStyle: isCollapsed ? .compact : .full
            )

            HStack(spacing: 0) {
                // Left: full-height sidebar column
                if !isCollapsed && !isCompactMode && isSidebarVisible {
                    sidebarColumn
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                // Right: title bar + content
                VStack(spacing: 0) {
                    titleBar

                    if !isCollapsed {
                        Divider()
                            .background(CiderColors.separator)
                            .padding(.horizontal, Spacing.md + Spacing.xxs)

                        content
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    }
                }
                .blur(radius: blurRightColumn ? BookmarksDesign.detailsContentBlurRadius : 0)
                .allowsHitTesting(!blurRightColumn)
                .animation(reduceMotion ? .none : .snappy, value: blurRightColumn)
                .padding(.top, Spacing.sm - 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onChange(of: proxy.size.width) { _, newWidth in
                            let compact = newWidth < CiderPanelDesign.sidebarCompactThreshold
                            if compact && !isCompactMode {
                                isCompactMode = true
                                if isSidebarVisible {
                                    sidebarAutoCollapsed = true
                                    isSidebarVisible = false
                                }
                            } else if !compact && isCompactMode {
                                isCompactMode = false
                                if sidebarAutoCollapsed && !suppressSidebarAutoExpand {
                                    sidebarAutoCollapsed = false
                                    isSidebarVisible = true
                                }
                            }
                        }
                        .onAppear {
                            isCompactMode = proxy.size.width < CiderPanelDesign.sidebarCompactThreshold
                        }
                }
            )
            .overlay { panelOverlay }
            // Clip sidebar slide animation + overlay to panel boundary (not shadow edge)
            .clipShape(RoundedRectangle(cornerRadius: CiderPanelDesign.cornerRadius, style: .continuous))

            // Compact overlay sidebar
            if !isCollapsed && isCompactMode && isSidebarVisible {
                compactOverlaySidebar
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !isCollapsed {
                CiderPanelResizeIcon()
            }
        }
        .padding(.horizontal, CiderPanelDesign.shadowPadding)
        .padding(.top, CiderPanelDesign.topPadding)
        .padding(
            .bottom,
            isCollapsed
                ? CiderPanelDesign.collapsedBottomPadding
                : CiderPanelDesign.shadowPadding + CiderPanelDesign.bottomPadding
        )
        .overlay {
            if !isCollapsed {
                PanelEdgeResizeView()
            }
        }
        .animation(reduceMotion ? .none : .snappy, value: isSidebarVisible)
        .onChange(of: isSidebarVisible) { _, visible in
            toggleAppearTask?.cancel()
            if !visible {
                // Sidebar closing — after a short delay, show title bar toggle
                if reduceMotion {
                    showTitleBarToggle = true
                } else {
                    toggleAppearTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(150))
                        guard !Task.isCancelled else { return }
                        withAnimation(.bouncy) {
                            showTitleBarToggle = true
                        }
                    }
                }
            } else {
                // Sidebar opening — immediately hide title bar toggle
                if reduceMotion {
                    showTitleBarToggle = false
                } else {
                    withAnimation(.snappy) {
                        showTitleBarToggle = false
                    }
                }
            }
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack(spacing: Spacing.sm) {
            if showTitleBarToggle {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.left")
                        .font(CiderFont.bodySemibold)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundColor(CiderColors.secondary)
                .help("Show folder sidebar")
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            titleBarContent
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: CiderPanelDesign.titleBarHeight)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Close", action: onClose)
            Button(isCollapsed ? "Expand" : "Minimize", action: onCollapse)
            Button("Maximize", action: onMaximize)
        }
    }

    // MARK: - Sidebar Column

    private var sidebarColumn: some View {
        VStack(spacing: 0) {
            sidebarHeader
            sidebarContent
            sidebarFooter
        }
        .sectionContainer()
        .padding(.leading, Spacing.md)
        .padding(.vertical, Spacing.md)
    }

    private var sidebarHeader: some View {
        HStack(alignment: .top, spacing: CiderPanelDesign.trafficLightSpacing) {
            PanelTrafficLightButton(color: .systemRed, symbol: "xmark", help: "Close panel", action: onClose)
            PanelTrafficLightButton(
                color: .systemYellow,
                symbol: "minus",
                help: isCollapsed ? "Expand panel" : "Collapse to header",
                action: onCollapse
            )
            PanelTrafficLightButton(
                color: .systemGreen,
                symbol: "arrow.up.left.and.arrow.down.right",
                help: "Maximize panel",
                action: onMaximize
            )

            Spacer(minLength: 0)

            Button(action: toggleSidebar) {
                Image(systemName: "sidebar.left")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.secondary)
                    .frame(width: 28, height: CiderPanelDesign.trafficLightTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Hide sidebar")
        }
        .frame(height: BookmarksDesign.buttonTapTarget, alignment: .top)
        .padding(.horizontal, Spacing.sm)
        .padding(.top, Spacing.sm)
        .frame(maxWidth: BookmarksDesign.folderSidebarWidth, alignment: .leading)
    }

    // MARK: - Compact Overlay Sidebar

    private var compactOverlaySidebar: some View {
        ZStack(alignment: .leading) {
            CiderColors.backdrop
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(reduceMotion ? .none : .snappy) {
                        isSidebarVisible = false
                    }
                }

            VStack(spacing: 0) {
                sidebarHeader
                sidebarContent
                sidebarFooter
            }
            .background(
                VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            )
            .sectionContainer()
            .padding(.leading, Spacing.md)
            .padding(.vertical, Spacing.md)
            .transition(.move(edge: .leading).combined(with: .opacity))
        }
        .clipShape(RoundedRectangle(cornerRadius: CiderPanelDesign.cornerRadius, style: .continuous))
        .animation(reduceMotion ? .none : .snappy, value: isSidebarVisible)
    }

    // MARK: - Sidebar Toggle

    private func toggleSidebar() {
        withAnimation(reduceMotion ? .none : .snappy) {
            isSidebarVisible.toggle()
            sidebarAutoCollapsed = false
        }
    }
}

// MARK: - Convenience Init (no overlay)

extension CiderPanelShell where PanelOverlay == EmptyView {
    init(
        isCollapsed: Bool,
        suppressSidebarAutoExpand: Bool = false,
        blurRightColumn: Bool = false,
        onClose: @escaping () -> Void,
        onCollapse: @escaping () -> Void,
        onMaximize: @escaping () -> Void,
        @ViewBuilder sidebarContent: () -> SidebarContent,
        @ViewBuilder sidebarFooter: () -> SidebarFooter,
        @ViewBuilder titleBar: () -> TitleBarContent,
        @ViewBuilder content: () -> Content
    ) {
        self.isCollapsed = isCollapsed
        self.suppressSidebarAutoExpand = suppressSidebarAutoExpand
        self.blurRightColumn = blurRightColumn
        self.onClose = onClose
        self.onCollapse = onCollapse
        self.onMaximize = onMaximize
        self.sidebarContent = sidebarContent()
        self.sidebarFooter = sidebarFooter()
        self.titleBarContent = titleBar()
        self.content = content()
        self.panelOverlay = EmptyView()
    }
}

// MARK: - Panel Traffic Light Button

struct PanelTrafficLightButton: View {
    let color: NSColor
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(color))
                .frame(width: CiderPanelDesign.trafficLightDiameter, height: CiderPanelDesign.trafficLightDiameter)
                .overlay {
                    if isHovered {
                        Image(systemName: symbol)
                            .font(.system(size: CiderPanelDesign.trafficLightSymbolSize * CiderFont.scale, weight: .semibold))
                            .foregroundColor(CiderColors.trafficLightSymbol)
                    }
                }
                .frame(width: CiderPanelDesign.trafficLightTapTarget, height: CiderPanelDesign.trafficLightTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverState($isHovered)
        .help(help)
    }
}

// MARK: - Resize Icon (decoration only)

struct CiderPanelResizeIcon: View {
    var body: some View {
        Image(systemName: "arrow.down.backward.and.arrow.up.forward")
            .font(CiderFont.microMedium)
            .foregroundColor(CiderColors.quaternary)
            .frame(width: 16, height: 16)
            .allowsHitTesting(false)
    }
}
