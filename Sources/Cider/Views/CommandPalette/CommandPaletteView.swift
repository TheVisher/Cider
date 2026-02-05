import SwiftUI

// MARK: - Text Scale Environment

private struct TextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var textScale: CGFloat {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

struct CommandPaletteView: View {
    @ObservedObject var viewModel: CommandPaletteViewModel
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    let paletteSize: PaletteSize
    let textSize: TextSize

    init(viewModel: CommandPaletteViewModel, paletteSize: PaletteSize = .medium, textSize: TextSize = .medium) {
        self.viewModel = viewModel
        self.paletteSize = paletteSize
        self.textSize = textSize
    }

    /// Sync SwiftUI focus state with our section focus
    private func syncSearchFocus() {
        isSearchFocused = viewModel.focusState.section == .search
    }

    var body: some View {
        ZStack {
            // Background with shadow (not clipped)
            PaletteBackgroundView(cornerRadius: CommandPaletteDesign.cornerRadius)

            // Content (clipped to rounded rect)
            VStack(spacing: 0) {
                // Search bar
                PaletteSearchBar(text: $searchText, isFocused: $isSearchFocused)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.md)

                Divider()
                    .padding(.horizontal, 1.5)
                    .opacity(0.3)

                // Pinned apps row
                PaletteAppsRow(
                    apps: viewModel.pinnedApps,
                    folders: viewModel.folders,
                    focusedIndex: viewModel.focusState.section == .apps ? viewModel.focusState.appsIndex : nil,
                    onAppClick: { viewModel.launchApp($0) },
                    onFolderClick: { viewModel.toggleFolder($0) },
                    isRunning: { viewModel.isRunning($0) },
                    onQuitApp: { viewModel.quitApp($0) }
                )
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)

                Divider()
                    .padding(.horizontal, 1.5)
                    .opacity(0.3)

                // Flexible content area (windows for now)
                PaletteContentArea(
                    activeTab: viewModel.activeTab,
                    windowGroups: viewModel.windowGroups,
                    monitors: viewModel.monitors,
                    focusedIndex: viewModel.focusState.section == .content ? viewModel.focusState.contentIndex : nil,
                    onWindowClick: { viewModel.focusWindow($0) },
                    onCloseWindow: { viewModel.closeWindow($0) },
                    onMinimizeWindow: { viewModel.minimizeWindow($0) },
                    onQuitApp: { viewModel.quitWindowApp($0) },
                    onMoveWindow: { window, monitor in viewModel.moveWindow(window, to: monitor) },
                    onTabChange: { viewModel.activeTab = $0 }
                )
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)

                Spacer(minLength: 0)

                // Footer divider - thinner than window border
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 1)
                    .padding(.horizontal, 1.5)

                // Footer bar with actions
                PaletteFooterBar(onSettingsClick: { viewModel.openSettings() })
            }
            .clipShape(RoundedRectangle(cornerRadius: CommandPaletteDesign.cornerRadius, style: .continuous))
        }
        .frame(width: paletteSize.width)
        .frame(minHeight: paletteSize.minHeight, maxHeight: paletteSize.maxHeight)
        .environment(\.textScale, textSize.scale)
        .onAppear {
            isSearchFocused = true
        }
        .onExitCommand {
            viewModel.dismiss()
        }
        .onKeyPress(.downArrow) {
            viewModel.moveFocusDown()
            syncSearchFocus()
            return .handled
        }
        .onKeyPress(.upArrow) {
            viewModel.moveFocusUp()
            syncSearchFocus()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            viewModel.moveFocusLeft()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            viewModel.moveFocusRight()
            return .handled
        }
        .onKeyPress(.tab, phases: .down) { keyPress in
            let forward = !keyPress.modifiers.contains(.shift)
            viewModel.cycleSection(forward: forward)
            syncSearchFocus()
            return .handled
        }
        .onKeyPress(.return) {
            viewModel.activateFocusedItem()
            return .handled
        }
    }
}

// MARK: - Design Constants

enum CommandPaletteDesign {
    static let cornerRadius: CGFloat = Radius.lg
    static let appIconSize: CGFloat = 48
    static let folderIconSize: CGFloat = 48
    static let appGridSpacing: CGFloat = Spacing.md

    // Shadow padding for the window
    static let shadowPadding: CGFloat = 45

    // Legacy - for backwards compatibility
    static let width: CGFloat = 600
    static let minHeight: CGFloat = 400
    static let maxHeight: CGFloat = 600
}
