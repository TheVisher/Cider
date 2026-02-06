import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

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
    private let pinnedAppsViewModel = PinnedAppsViewModel()
    private let windowListViewModel = WindowListViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        AccessibilityHelpers.promptIfNeeded()

        // Unhide all apps on startup so Cider can see them
        // (Apps may have been hidden by a previous Cider session)
        WindowManager().unhideAllAppsOnStartup()

        configureCommandPalette()
        configureWindowCycling()
        configureSettings()
        configureStatusItem()
        observeCommandPaletteNotifications()
        observeSettingsNotifications()
        observeConfigChanges()
        startDoubleTapDetection()
        startOptionTabDetection()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func configureStatusItem() {
        let config = CiderConfig.load()
        guard config.showMenuBarIcon else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "command", accessibilityDescription: "Cider")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Command Palette", action: #selector(toggleCommandPalette), keyEquivalent: " "))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Cider", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    private func observeConfigChanges() {
        NotificationCenter.default.publisher(for: .ciderConfigChanged)
            .sink { [weak self] _ in
                self?.handleConfigChanged()
            }
            .store(in: &cancellables)
    }

    private func handleConfigChanged() {
        let config = CiderConfig.load()

        // Toggle status item visibility based on config
        if config.showMenuBarIcon {
            if statusItem == nil { configureStatusItem() }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        }

        // Update command palette size (will apply on next open)
        updateCommandPaletteSize()

        // Restart double-tap detector if activation mode changed
        doubleTapDetector?.stop()
        doubleTapDetector = nil
        startDoubleTapDetection()

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
        let config = CiderConfig.load()
        doubleTapDetector = DoubleTapDetector(
            key: .option,
            maxInterval: 0.3,
            mode: config.activationMode
        ) { [weak self] in
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
        guard let vm = commandPaletteViewModel else { return }
        let settingsView = SettingsView(pinnedAppsViewModel: pinnedAppsViewModel, commandPaletteViewModel: vm)
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
            onCycleStart: { [weak self] direction in
                self?.handleCycleStart(direction: direction)
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

    private func handleCycleStart(direction: Int) {
        // Don't start cycling if command palette is open
        if commandPalettePanel?.isVisible == true {
            return
        }

        windowCyclingManager?.startCycling(initialDirection: direction)
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
        let maxVisibleItems: CGFloat = 7

        let windowCount = CGFloat(min(CGFloat(max(1, manager.windows.count)), maxVisibleItems))
        let contentWidth = windowCount * itemWidth + (windowCount - 1) * itemSpacing + padding
        let width = contentWidth + shadowPadding

        // Match the itemHeight from WindowCyclingOverlayView
        let itemHeight: CGFloat = 100
        let verticalPadding: CGFloat = Spacing.md * 2
        let height = itemHeight + verticalPadding + shadowPadding

        panel.setContentSize(NSSize(width: width, height: height))
    }
}
