import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
    @FocusState private var isSearchFocused: Bool
    @State private var keyMonitor: Any?

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

    /// Handle keyboard navigation via NSEvent monitor
    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        // Only handle key down events
        guard event.type == .keyDown else { return event }

        // When folder popup is open, handle navigation within it
        if viewModel.expandedFolderID != nil {
            // If a text field is being edited (e.g. folder rename), let all events through
            // except Escape which always closes the popup
            let isEditingText = NSApp.keyWindow?.firstResponder is NSTextView
            if isEditingText && Int(event.keyCode) != 53 {
                return event
            }

            switch Int(event.keyCode) {
            case 53: // Escape — close folder popup
                if !viewModel.handleEscape() {
                    viewModel.dismiss()
                }
                return nil
            case 123: // Left arrow
                viewModel.moveFolderFocusLeft()
                return nil
            case 124: // Right arrow
                viewModel.moveFolderFocusRight()
                return nil
            case 36: // Return/Enter — open focused app
                viewModel.activateFocusedFolderApp()
                return nil
            default:
                return event
            }
        }

        let dominated = viewModel.focusState.section != .search

        switch Int(event.keyCode) {
        case 125: // Down arrow
            viewModel.moveFocusDown()
            syncSearchFocus()
            return nil // Consume event

        case 126: // Up arrow
            if dominated || viewModel.focusState.section != .search {
                viewModel.moveFocusUp()
                syncSearchFocus()
                return nil
            }
            return event

        case 123: // Left arrow
            if dominated {
                viewModel.moveFocusLeft()
                return nil
            }
            return event // Let TextField handle it

        case 124: // Right arrow
            if dominated {
                viewModel.moveFocusRight()
                return nil
            }
            return event // Let TextField handle it

        case 48: // Tab
            let forward = !event.modifierFlags.contains(.shift)
            viewModel.cycleSection(forward: forward)
            syncSearchFocus()
            return nil

        case 36: // Return/Enter
            if dominated {
                viewModel.activateFocusedItem()
                return nil
            }
            return event

        case 53: // Escape
            // First Escape clears search, second dismisses
            if !viewModel.handleEscape() {
                viewModel.dismiss()
            }
            return nil

        default:
            return event
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            return handleKeyEvent(event)
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    var body: some View {
        ZStack {
            // Background with shadow (not clipped)
            PaletteBackgroundView(cornerRadius: CommandPaletteDesign.cornerRadius)

            // Content (clipped to rounded rect)
            VStack(spacing: 0) {
                // Search bar
                PaletteSearchBar(text: $viewModel.searchText, isFocused: $isSearchFocused)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.md)

                // Pinned apps row (filtered) - hide section completely if no apps match
                if !viewModel.isSearching || viewModel.totalAppsCount > 0 {
                    Divider()
                        .padding(.horizontal, 1.5)
                        .opacity(0.3)

                    PaletteAppsRow(
                        items: viewModel.filteredPinnedItems,
                        allFolders: viewModel.folders,
                        searchText: viewModel.searchText,
                        focusedIndex: viewModel.focusState.section == .apps ? viewModel.focusState.appsIndex : nil,
                        canAddMore: viewModel.canAddMoreItems,
                        focusedFolderAppIndex: viewModel.expandedFolderID != nil ? viewModel.focusedFolderAppIndex : nil,
                        expandedFolderID: $viewModel.expandedFolderID,
                        onAppClick: { viewModel.launchApp($0) },
                        onFolderClick: { viewModel.toggleFolder($0) },
                        isRunning: { viewModel.isRunning($0) },
                        onQuitApp: { viewModel.quitApp($0) },
                        onReorderItems: { viewModel.reorderPinnedItems($0) },
                        onCreateFolder: { viewModel.createFolderFromDrop(app1: $0, app2: $1) },
                        onAddToFolder: { viewModel.addAppToFolder(app: $0, folder: $1) },
                        onAddAppToFolderFromPicker: { viewModel.addAppToFolderFromURL($0, folder: $1) },
                        onRemoveFromFolderToPinned: { viewModel.removeAppFromFolderToPinned(app: $0, folder: $1) },
                        onRemoveFromFolderAndCider: { viewModel.removeAppFromFolderAndCider(app: $0, folder: $1) },
                        onMoveAppBetweenFolders: { viewModel.moveAppBetweenFolders(app: $0, from: $1, to: $2) },
                        onRenameFolder: { viewModel.renameFolder($0, to: $1) },
                        onAddApp: {
                            let panel = NSOpenPanel()
                            panel.allowsMultipleSelection = true
                            panel.canChooseDirectories = false
                            panel.canChooseFiles = true
                            panel.allowedContentTypes = [UTType.application]
                            panel.directoryURL = URL(fileURLWithPath: "/Applications")
                            panel.level = .floating
                            let response = panel.runModal()
                            guard response == .OK else { return }
                            for url in panel.urls {
                                viewModel.addPinnedApp(from: url)
                            }
                        }
                    )
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.md)
                }

                Divider()
                    .padding(.horizontal, 1.5)
                    .opacity(0.3)

                // Flexible content area (filtered windows)
                PaletteContentArea(
                    activeTab: viewModel.activeTab,
                    monitorGroups: viewModel.filteredMonitorGroups,
                    monitors: viewModel.monitors,
                    searchText: viewModel.searchText,
                    isSearching: viewModel.isSearching,
                    focusedTabIndex: viewModel.focusState.section == .tabs ? viewModel.focusState.tabsIndex : nil,
                    focusedContentIndex: viewModel.focusState.section == .content ? viewModel.focusState.contentIndex : nil,
                    onWindowClick: { viewModel.focusWindow($0) },
                    onCloseWindow: { viewModel.closeWindow($0) },
                    onMinimizeWindow: { viewModel.minimizeWindow($0) },
                    onQuitApp: { viewModel.quitWindowApp($0) },
                    onMoveWindow: { window, monitor in viewModel.moveWindow(window, to: monitor) },
                    onMoveWindowByID: { windowID, monitor in viewModel.moveWindowByID(windowID, to: monitor) },
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
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
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
