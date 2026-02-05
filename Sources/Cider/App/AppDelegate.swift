import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Sidebar
    private var panel: CiderPanel?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private var edgeMonitor: Any?
    private var isLocked = false

    // Command Palette
    private var commandPalettePanel: CommandPalettePanel?
    private var commandPaletteViewModel: CommandPaletteViewModel?
    private var doubleTapDetector: DoubleTapDetector?
    private var clickOutsideMonitor: Any?

    // Window Cycling
    private var windowCyclingPanel: WindowCyclingPanel?
    private var windowCyclingManager: WindowCyclingManager?
    private var optionTabDetector: OptionTabDetector?

    // Settings
    private var settingsWindow: SettingsWindow?

    // Shared ViewModels
    private let sidebarViewModel = SidebarViewModel()
    private let pinnedAppsViewModel = PinnedAppsViewModel()
    private let windowListViewModel = WindowListViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        AccessibilityHelpers.promptIfNeeded()

        // Unhide all apps on startup so Cider can see them
        // (Apps may have been hidden by a previous Cider session)
        WindowManager().unhideAllAppsOnStartup()

        configurePanel()
        configureCommandPalette()
        configureWindowCycling()
        configureSettings()
        configureStatusItem()
        observeScreenChanges()
        observeSidebarState()
        observeCommandPaletteNotifications()
        observeSettingsNotifications()
        observeConfigChanges()
        startEdgeDetection()
        startDoubleTapDetection()
        startOptionTabDetection()
    }

    @objc private func toggleSidebar() {
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func configurePanel() {
        // Always use expanded width - visual collapsed state is handled by SwiftUI content
        // This prevents hover oscillation caused by tracking area invalidation during resize
        let frame = panelFrame(for: CiderDesign.sidebarWidthExpanded)

        let panel = CiderPanel(contentRect: frame)
        let rootView = SidebarView(viewModel: sidebarViewModel,
                                   pinnedAppsViewModel: pinnedAppsViewModel,
                                   windowListViewModel: windowListViewModel)

        // Simplified hierarchy for Liquid Glass - hosting view directly as content
        let hostingView = FirstMouseHostingView(rootView: rootView)
        panel.contentView = hostingView
        panel.setFrame(frame, display: true)

        // Start hidden - will show when mouse enters edge zone
        panel.orderOut(nil)
        self.panel = panel
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Cider")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Command Palette", action: #selector(toggleCommandPalette), keyEquivalent: " "))
        menu.addItem(NSMenuItem(title: "Toggle Sidebar", action: #selector(toggleSidebar), keyEquivalent: "t"))

        let lockItem = NSMenuItem(title: "Lock Open", action: #selector(toggleLock), keyEquivalent: "l")
        lockItem.state = isLocked ? .on : .off
        menu.addItem(lockItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Cider", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleLock() {
        isLocked.toggle()
        // Update menu item state
        if let menu = statusItem?.menu,
           let lockItem = menu.item(withTitle: "Lock Open") {
            lockItem.state = isLocked ? .on : .off
        }
        // If locked, show the panel; if unlocked and not expanded, hide it
        if isLocked {
            showPanel()
        } else if !sidebarViewModel.isExpanded {
            hidePanel()
        }
    }

    private func observeScreenChanges() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.updatePanelFrame()
            }
            .store(in: &cancellables)
    }

    private func observeSidebarState() {
        sidebarViewModel.$isExpanded
            .removeDuplicates()
            .sink { [weak self] isExpanded in
                guard let self, !self.isLocked else { return }
                if isExpanded {
                    self.showPanel()
                } else {
                    self.hidePanel()
                }
            }
            .store(in: &cancellables)
    }

    private func observeConfigChanges() {
        NotificationCenter.default.publisher(for: .ciderConfigChanged)
            .sink { [weak self] _ in
                self?.handleConfigChanged()
            }
            .store(in: &cancellables)
    }

    private func handleConfigChanged() {
        // Reload config
        sidebarViewModel.reloadConfig()
        let config = CiderConfig.load()

        // Update panel position based on edge setting
        updatePanelFrame()

        // Handle sidebar enabled/disabled
        if !sidebarViewModel.config.sidebarEnabled {
            hidePanel()
        }

        // Update command palette size (will apply on next open)
        updateCommandPaletteSize()

        // Handle Option+Tab cycling enabled/disabled
        if config.enableOptionTabCycling {
            if optionTabDetector == nil {
                startOptionTabDetection()
            } else {
                optionTabDetector?.setEnabled(true)
            }
        } else {
            optionTabDetector?.setEnabled(false)
        }
    }

    private func startEdgeDetection() {
        // Monitor global mouse movements to detect when cursor is at the left edge
        edgeMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isLocked else { return }
                guard self.sidebarViewModel.config.sidebarEnabled else { return }
                guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

                let mouseLocation = NSEvent.mouseLocation
                let edgeThreshold: CGFloat = 3 // pixels from edge to trigger

                let isAtEdge: Bool
                switch self.sidebarViewModel.config.sidebarEdge {
                case .left:
                    isAtEdge = mouseLocation.x <= screen.visibleFrame.minX + edgeThreshold
                case .right:
                    isAtEdge = mouseLocation.x >= screen.visibleFrame.maxX - edgeThreshold
                }

                if isAtEdge && !(self.panel?.isVisible ?? false) {
                    self.sidebarViewModel.isExpanded = true
                    self.showPanel()
                }
            }
        }
    }

    private func showPanel() {
        panel?.orderFrontRegardless()
        // Make panel key to capture mouse events and prevent click-through
        panel?.makeKey()
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }

    private func updatePanelFrame() {
        // Panel always stays at expanded width - only reposition on screen changes
        let frame = panelFrame(for: CiderDesign.sidebarWidthExpanded)
        panel?.setFrame(frame, display: true, animate: false)
    }

    private func panelFrame(for width: CGFloat) -> NSRect {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return NSRect(x: 0, y: 0, width: width, height: 600)
        }
        let visible = screen.visibleFrame
        let insetX = CiderDesign.sidebarInset
        let insetY = CiderDesign.sidebarVerticalInset

        // Add shadow padding to window size
        let shadowH = CiderDesign.shadowPaddingHorizontal
        let shadowTop = CiderDesign.shadowPaddingTop
        let shadowBottom = CiderDesign.shadowPaddingBottom
        let totalWidth = width + shadowH * 2
        let totalHeight = max(0, visible.height - insetY * 2 + shadowTop + shadowBottom)

        let x: CGFloat
        switch sidebarViewModel.config.sidebarEdge {
        case .left:
            x = visible.minX + insetX - shadowH  // Offset left for shadow
        case .right:
            x = visible.maxX - totalWidth - insetX + shadowH
        }
        return NSRect(x: x, y: visible.minY + insetY - shadowBottom, width: totalWidth, height: totalHeight)
    }

    // MARK: - Command Palette

    private func configureCommandPalette() {
        let viewModel = CommandPaletteViewModel(
            windowListViewModel: windowListViewModel,
            pinnedAppsViewModel: pinnedAppsViewModel
        )
        self.commandPaletteViewModel = viewModel

        let panel = CommandPalettePanel()
        self.commandPalettePanel = panel

        updateCommandPaletteSize()
    }

    private func updateCommandPaletteSize() {
        guard let panel = commandPalettePanel, let viewModel = commandPaletteViewModel else { return }

        let config = CiderConfig.load()
        let paletteSize = config.paletteSize
        let textSize = config.textSize

        // Add shadow padding around the palette
        let shadowPadding = CommandPaletteDesign.shadowPadding
        let paletteView = CommandPaletteView(viewModel: viewModel, paletteSize: paletteSize, textSize: textSize)
            .padding(.horizontal, shadowPadding)
            .padding(.top, 20)                   // Small top padding for shadow fade
            .padding(.bottom, shadowPadding + 15) // Extra bottom padding for shadow

        let hostingView = CommandPaletteHostingView(rootView: paletteView)
        panel.contentView = hostingView

        // Size the panel to fit content plus shadow padding
        let width = paletteSize.width + shadowPadding * 2
        let height = paletteSize.maxHeight + 20 + shadowPadding + 15
        panel.setContentSize(NSSize(width: width, height: height))
    }

    private func observeCommandPaletteNotifications() {
        NotificationCenter.default.publisher(for: .dismissCommandPalette)
            .sink { [weak self] _ in
                self?.hideCommandPalette()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .toggleCommandPalette)
            .sink { [weak self] _ in
                self?.toggleCommandPalette()
            }
            .store(in: &cancellables)
    }

    private func startDoubleTapDetection() {
        doubleTapDetector = DoubleTapDetector(key: .option, maxInterval: 0.3) { [weak self] in
            Task { @MainActor in
                self?.toggleCommandPalette()
            }
        }
        doubleTapDetector?.start()
    }

    @objc private func toggleCommandPalette() {
        guard let panel = commandPalettePanel else { return }

        if panel.isVisible {
            // Check if mouse is on a different screen
            let mouseLocation = NSEvent.mouseLocation
            let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            let panelScreen = panel.screen

            if let mouseScreen, let panelScreen, mouseScreen != panelScreen {
                // Different screen - close and reopen on new screen
                hideCommandPalette()
                // Small delay to ensure clean transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.showCommandPalette()
                }
            } else {
                // Same screen or can't determine - just close
                hideCommandPalette()
            }
        } else {
            showCommandPalette()
        }
    }

    private func showCommandPalette() {
        guard let panel = commandPalettePanel else { return }

        commandPaletteViewModel?.show()
        panel.centerOnScreen()
        panel.makeKeyAndOrderFront(nil)

        // Monitor for clicks outside to dismiss
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.commandPalettePanel else { return }

            let panelFrame = panel.frame
            let screenLocation = NSEvent.mouseLocation

            if !panelFrame.contains(screenLocation) {
                Task { @MainActor in
                    self.hideCommandPalette()
                }
            }
        }
    }

    private func hideCommandPalette() {
        commandPalettePanel?.orderOut(nil)
        commandPaletteViewModel?.isVisible = false

        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    // MARK: - Settings

    private func configureSettings() {
        let window = SettingsWindow()

        // Add shadow padding around the settings view
        let shadowPadding = SettingsDesign.shadowPadding
        let settingsView = SettingsView()
            .padding(.horizontal, shadowPadding)
            .padding(.top, 20)
            .padding(.bottom, shadowPadding + 15)

        let hostingView = SettingsHostingView(rootView: settingsView)
        window.contentView = hostingView

        // Size the window to fit content plus shadow padding
        let width = SettingsDesign.width + shadowPadding * 2
        let height = SettingsDesign.height + 20 + shadowPadding + 15
        window.setContentSize(NSSize(width: width, height: height))

        self.settingsWindow = window
    }

    private func observeSettingsNotifications() {
        NotificationCenter.default.publisher(for: .openCiderSettings)
            .sink { [weak self] _ in
                self?.showSettings()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .dismissSettings)
            .sink { [weak self] _ in
                self?.hideSettings()
            }
            .store(in: &cancellables)
    }

    private func showSettings() {
        // Hide command palette first
        hideCommandPalette()

        settingsWindow?.showCentered()
    }

    private func hideSettings() {
        settingsWindow?.orderOut(nil)
    }

    // MARK: - Window Cycling

    private func configureWindowCycling() {
        let manager = WindowCyclingManager(
            windowManager: windowListViewModel.windowManager,
            cycleAllScreens: {
                CiderConfig.load().optionTabCycleAllScreens
            }
        )
        self.windowCyclingManager = manager

        let panel = WindowCyclingPanel()
        self.windowCyclingPanel = panel

        updateWindowCyclingView()
    }

    private func updateWindowCyclingView() {
        guard let panel = windowCyclingPanel, let manager = windowCyclingManager else { return }

        let shadowPadding: CGFloat = 40
        let cyclingView = WindowCyclingOverlayView(cyclingManager: manager)
            .padding(shadowPadding)

        let hostingView = WindowCyclingHostingView(rootView: cyclingView)
        panel.contentView = hostingView
    }

    private func startOptionTabDetection() {
        let config = CiderConfig.load()
        guard config.enableOptionTabCycling else { return }

        optionTabDetector = OptionTabDetector(
            onCycleStart: { [weak self] in
                self?.handleCycleStart()
            },
            onCycleNext: { [weak self] in
                self?.handleCycleNext()
            },
            onCyclePrevious: { [weak self] in
                self?.handleCyclePrevious()
            },
            onCycleEnd: { [weak self] committed in
                self?.handleCycleEnd(committed: committed)
            }
        )
        optionTabDetector?.start()
    }

    private func handleCycleStart() {
        // Don't start cycling if command palette is open
        if commandPalettePanel?.isVisible == true {
            return
        }

        windowCyclingManager?.startCycling()
        showWindowCyclingPanel()
    }

    private func handleCycleNext() {
        windowCyclingManager?.cycleNext()
    }

    private func handleCyclePrevious() {
        windowCyclingManager?.cyclePrevious()
    }

    private func handleCycleEnd(committed: Bool) {
        if committed {
            windowCyclingManager?.commitSelection()
        } else {
            windowCyclingManager?.cancelCycling()
        }
        hideWindowCyclingPanel()
    }

    private func showWindowCyclingPanel() {
        guard let panel = windowCyclingPanel else { return }
        updateWindowCyclingPanelSize()
        panel.showCentered()
    }

    private func hideWindowCyclingPanel() {
        windowCyclingPanel?.orderOut(nil)
    }

    private func updateWindowCyclingPanelSize() {
        guard let panel = windowCyclingPanel, let manager = windowCyclingManager else { return }

        let itemWidth: CGFloat = 100
        let itemSpacing: CGFloat = Spacing.md
        let padding: CGFloat = Spacing.lg * 2
        let shadowPadding: CGFloat = 40 * 2

        let windowCount = CGFloat(max(1, manager.windows.count))
        let contentWidth = windowCount * itemWidth + (windowCount - 1) * itemSpacing + padding
        let maxWidth: CGFloat = 800
        let width = min(contentWidth, maxWidth) + shadowPadding

        let height: CGFloat = 120 + shadowPadding

        panel.setContentSize(NSSize(width: width, height: height))
    }
}
