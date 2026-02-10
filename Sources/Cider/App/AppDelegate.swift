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

    // Tiling Hotkeys
    private var tileHotkeyDetector: TileHotkeyDetector?
    private let tileActionHandler = TileActionHandler()

    // Notes
    private var notesPanel: NotesPanel?
    private var notesViewModel: NotesViewModel?
    private var notesHotkeyDetector: NotesHotkeyDetector?
    private let notesPanelPositionStore = NotesPanelPositionStore.shared
    private var notesPanelRestoreFrame: NSRect?

    // Tile Zone Overlay
    private var tileZoneOverlayPanels: [TileZoneOverlayPanel] = []
    private var dragMouseMonitor: Any?
    private var dragMouseUpLocalMonitor: Any?
    private var dragMouseUpGlobalMonitor: Any?
    private var dragPollingTimer: Timer?
    private var isDragOverlayShown = false
    private var tileActionCompleted = false
    private var dragGeneration: UInt = 0

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
        configureNotes()
        configureStatusItem()
        observeCommandPaletteNotifications()
        observeSettingsNotifications()
        observeNotesNotifications()
        observeConfigChanges()
        startDoubleTapDetection()
        startOptionTabDetection()
        startTileHotkeyDetection()
        startNotesHotkeyDetection()

        // Initialize DynamicTileManager (triggers screen change subscription)
        _ = DynamicTileManager.shared

        // Initialize TileHandleManager (observes group changes)
        _ = TileHandleManager.shared
    }

    func applicationWillTerminate(_ notification: Notification) {
        flushNotesDraftIfNeeded()

        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
        }
        stopDragMonitoring()
        hideTileZoneOverlays()
    }

    func applicationWillResignActive(_ notification: Notification) {
        flushNotesDraftIfNeeded()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        optionTabDetector?.reclaimPriority()
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

        // Handle tiling hotkeys enabled/disabled
        if config.enableTilingHotkeys {
            if tileHotkeyDetector == nil {
                startTileHotkeyDetection()
            } else {
                tileHotkeyDetector?.setEnabled(true)
            }
        } else {
            tileHotkeyDetector?.setEnabled(false)
        }

        // Handle notes hotkey enabled/disabled
        if config.enableNotesHotkey {
            if notesHotkeyDetector == nil {
                startNotesHotkeyDetection()
            } else {
                notesHotkeyDetector?.setEnabled(true)
            }
        } else {
            notesHotkeyDetector?.setEnabled(false)
        }

        updateGlobalHotkeyEnablement()

        // Update notes directory if changed
        let expandedDir = NSString(string: config.notesDirectory).expandingTildeInPath
        NotesStorage.shared.updateDirectory(to: expandedDir)
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
        observeDragState()
        observeTileCompletion()
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

        TileHandleManager.shared.setVisible(false)

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
        hideTileZoneOverlays()
        TileHandleManager.shared.setVisible(true)

        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    // MARK: - Drag-to-Tile Overlay

    private func observeTileCompletion() {
        NotificationCenter.default.publisher(for: .ciderTileActionCompleted)
            .sink { [weak self] _ in
                self?.tileActionCompleted = true
                self?.hideTileZoneOverlays()
                self?.stopDragMonitoring()
                self?.commandPaletteViewModel?.isDraggingWindow = false
            }
            .store(in: &cancellables)
    }

    private func observeDragState() {
        commandPaletteViewModel?.$isDraggingWindow
            .removeDuplicates()
            .sink { [weak self] isDragging in
                self?.debugLog("[DragState] isDraggingWindow changed to \(isDragging)")
                self?.dragMoveLogCount = 0
                if isDragging {
                    self?.startDragMonitoring()
                } else {
                    self?.hideTileZoneOverlays()
                    self?.stopDragMonitoring()
                }
            }
            .store(in: &cancellables)
    }

    private func startDragMonitoring() {
        let config = CiderConfig.load()
        debugLog("[DragMonitor] startDragMonitoring called, enableDragToTile=\(config.enableDragToTile), dragPollingTimer=\(dragPollingTimer != nil)")
        guard config.enableDragToTile else { return }
        guard dragPollingTimer == nil else { return }
        dragGeneration &+= 1
        tileActionCompleted = false
        debugLog("[DragMonitor] Installing polling timer + mouse-up monitors")

        // SwiftUI's .onDrag captures leftMouseDragged events, so NSEvent monitors
        // don't fire. Instead, poll NSEvent.mouseLocation at ~60Hz.
        dragPollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.handleDragMouseMoved()
            }
        }

        // Mouse-up monitors to clean up overlay after drop
        dragMouseUpLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            Task { @MainActor in
                self?.handleDragEnd()
            }
            return event
        }
        dragMouseUpGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor in
                self?.handleDragEnd()
            }
        }
    }

    private func stopDragMonitoring() {
        dragPollingTimer?.invalidate()
        dragPollingTimer = nil
        if let monitor = dragMouseMonitor {
            NSEvent.removeMonitor(monitor)
            dragMouseMonitor = nil
        }
        if let monitor = dragMouseUpLocalMonitor {
            NSEvent.removeMonitor(monitor)
            dragMouseUpLocalMonitor = nil
        }
        if let monitor = dragMouseUpGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            dragMouseUpGlobalMonitor = nil
        }
    }

    private var dragMoveLogCount = 0

    private func handleDragMouseMoved() {
        guard let panel = commandPalettePanel, panel.isVisible else { return }

        let mouseLocation = NSEvent.mouseLocation
        let paletteFrame = panel.frame

        dragMoveLogCount += 1
        if dragMoveLogCount <= 3 {
            debugLog("[DragMonitor] handleDragMouseMoved #\(dragMoveLogCount), mouse=\(mouseLocation), palette=\(paletteFrame), insidePalette=\(paletteFrame.contains(mouseLocation)), draggedWindowID=\(String(describing: commandPaletteViewModel?.currentDraggedWindowID))")
        }

        if paletteFrame.contains(mouseLocation) {
            // Cursor is inside palette — hide overlays if shown
            if isDragOverlayShown {
                hideTileZoneOverlays()
            }
        } else {
            // Cursor is outside palette — show overlays if not shown
            if !isDragOverlayShown {
                showTileZoneOverlays()
            }
        }
    }

    private func handleDragEnd() {
        debugLog("[DragEnd] handleDragEnd called, tileActionCompleted=\(tileActionCompleted)")

        // If tile action already handled cleanup, nothing to do
        if tileActionCompleted {
            tileActionCompleted = false
            return
        }

        // Safety timeout: wait up to 300ms for tile action to complete, then clean up.
        // Capture the current drag generation so a new drag started within the delay
        // doesn't get torn down by this stale cleanup block.
        let gen = dragGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.dragGeneration == gen else { return }
            self.tileActionCompleted = false
            self.hideTileZoneOverlays()
            self.stopDragMonitoring()
            self.commandPaletteViewModel?.isDraggingWindow = false
            self.commandPaletteViewModel?.currentDraggedWindowID = nil
            self.commandPaletteViewModel?.currentDraggedWindowPID = 0
        }
    }

    private func showTileZoneOverlays() {
        guard !isDragOverlayShown else { return }
        isDragOverlayShown = true

        let monitors = MonitorManager.shared.monitors
        guard !monitors.isEmpty else { return }

        for monitor in monitors {
            let overlayPanel = TileZoneOverlayPanel(monitor: monitor)

            let overlayView = TileZoneOverlayView(
                monitor: monitor,
                onTile: { [weak self] windowIDs, position in
                    guard let self, !windowIDs.isEmpty else { return }

                    let initialDropPoint = NSEvent.mouseLocation
                    let primaryDraggedID = self.commandPaletteViewModel?.currentDraggedWindowID
                    let primaryDraggedPID = self.commandPaletteViewModel?.currentDraggedWindowPID ?? 0

                    for (index, windowID) in windowIDs.enumerated() {
                        let pid: pid_t
                        if windowID == primaryDraggedID {
                            pid = primaryDraggedPID != 0 ? primaryDraggedPID : self.findPIDForWindow(windowID)
                        } else {
                            pid = self.findPIDForWindow(windowID)
                        }

                        guard pid != 0 else { continue }
                        DynamicTileManager.shared.tileToZone(
                            windowID: windowID,
                            pid: pid,
                            position: position,
                            monitor: monitor,
                            dropPoint: index == 0 ? initialDropPoint : nil
                        )
                    }

                    self.commandPaletteViewModel?.dismiss()
                    self.tileActionCompleted = true
                    self.hideTileZoneOverlays()
                    self.stopDragMonitoring()
                    self.commandPaletteViewModel?.isDraggingWindow = false
                    self.commandPaletteViewModel?.currentDraggedWindowID = nil
                    self.commandPaletteViewModel?.currentDraggedWindowPID = 0
                    NotificationCenter.default.post(name: .ciderTileActionCompleted, object: nil)
                }
            )

            let hostingView = NSHostingView(rootView: overlayView)
            overlayPanel.contentView = hostingView
            overlayPanel.setFrame(monitor.frame, display: true)
            overlayPanel.orderFront(nil)

            tileZoneOverlayPanels.append(overlayPanel)
        }
    }

    private func hideTileZoneOverlays() {
        guard isDragOverlayShown else { return }
        isDragOverlayShown = false

        for panel in tileZoneOverlayPanels {
            panel.orderOut(nil)
        }
        tileZoneOverlayPanels.removeAll()
    }

    /// Find PID for a window ID by checking the current window list.
    private func findPIDForWindow(_ windowID: CGWindowID) -> pid_t {
        let cgOptions: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(cgOptions, kCGNullWindowID) as? [[String: Any]] else {
            return 0
        }
        for info in infoList {
            if let wid = info[kCGWindowNumber as String] as? CGWindowID, wid == windowID,
               let pid = info[kCGWindowOwnerPID as String] as? pid_t {
                return pid
            }
        }

        // Try the view model's window list
        for monitorGroup in windowListViewModel.monitorGroups {
            for group in monitorGroup.windowGroups {
                if let window = group.windows.first(where: { $0.id == windowID }) {
                    return window.ownerPID
                }
            }
        }
        return 0
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
            },
            isCycleSessionActive: { [weak self] in
                self?.windowCyclingManager?.isActive == true
            }
        )
        optionTabDetector?.start()
    }

    private func startTileHotkeyDetection() {
        let config = CiderConfig.load()
        guard config.enableTilingHotkeys else { return }

        tileHotkeyDetector = TileHotkeyDetector(
            onAction: { [weak self] action in
                self?.handleTileHotkeyAction(action)
            }
        )
        tileHotkeyDetector?.start()
    }

    private func handleCycleStart(direction: Int) {
        let notesVisible = notesPanel?.isVisible == true
        debugLog(
            "[OptionTab] handleCycleStart direction=\(direction) " +
            "notesVisible=\(notesVisible) paletteVisible=\(commandPalettePanel?.isVisible == true) " +
            "managerActiveBefore=\(windowCyclingManager?.isActive == true)"
        )

        // Don't start cycling if command palette is open
        if commandPalettePanel?.isVisible == true {
            debugLog("[OptionTab] handleCycleStart blocked: command palette visible")
            return
        }

        windowCyclingManager?.startCycling(initialDirection: direction)
        debugLog(
            "[OptionTab] handleCycleStart after start managerActive=\(windowCyclingManager?.isActive == true) " +
            "windowCount=\(windowCyclingManager?.windows.count ?? 0)"
        )
        showWindowCyclingPanel()
    }

    private func handleCycleNext() {
        windowCyclingManager?.cycleNext()
    }

    private func handleCyclePrevious() {
        windowCyclingManager?.cyclePrevious()
    }

    private func handleCycleEnd(committed: Bool) {
        debugLog(
            "[OptionTab] handleCycleEnd committed=\(committed) " +
            "managerActiveBefore=\(windowCyclingManager?.isActive == true)"
        )
        if committed {
            windowCyclingManager?.commitSelection()
        } else {
            windowCyclingManager?.cancelCycling()
        }
        debugLog("[OptionTab] handleCycleEnd managerActiveAfter=\(windowCyclingManager?.isActive == true)")
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

    // MARK: - Notes

    private func configureNotes() {
        let viewModel = NotesViewModel()
        self.notesViewModel = viewModel

        let panel = NotesPanel()
        self.notesPanel = panel

        updateNotesPanelView()
    }

    private func updateNotesPanelView() {
        guard let panel = notesPanel, let viewModel = notesViewModel else { return }

        let notesView = NotesPanelView(viewModel: viewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        let hostingView = NotesPanelHostingView(rootView: notesView)
        panel.contentView = hostingView

        // Size panel to fit content plus shadow padding
        let width = NotesDesign.panelDefaultWidth
        let height = NotesDesign.panelDefaultHeight
        panel.setContentSize(NSSize(width: width, height: height))
    }

    private func startNotesHotkeyDetection() {
        let config = CiderConfig.load()
        guard config.enableNotesHotkey else { return }

        notesHotkeyDetector = NotesHotkeyDetector(
            onToggle: { [weak self] in
                self?.toggleNotesPanel()
            }
        )
        notesHotkeyDetector?.start()
    }

    private func observeNotesNotifications() {
        NotificationCenter.default.publisher(for: .toggleNotes)
            .sink { [weak self] _ in
                self?.toggleNotesPanel()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .dismissNotes)
            .sink { [weak self] _ in
                self?.hideNotesPanel()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .openNoteInPanel)
            .sink { [weak self] notification in
                if let note = notification.object as? Note {
                    self?.showNotesPanel(with: note)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .toggleNotesCollapse)
            .sink { [weak self] _ in
                self?.toggleNotesCollapsed()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .moveNotesToNextDisplay)
            .sink { [weak self] _ in
                self?.moveNotesPanelToAdjacentDisplay(direction: 1)
            }
            .store(in: &cancellables)
    }

    private func toggleNotesPanel() {
        guard let panel = notesPanel else { return }

        if panel.isVisible {
            hideNotesPanel()
        } else {
            showNotesPanel()
        }
    }

    private func showNotesPanel(with note: Note? = nil) {
        guard let panel = notesPanel, let viewModel = notesViewModel else { return }

        debugLog("[Notes] showNotesPanel called")
        if panel.isVisible {
            persistCurrentNotePanelFrameIfNeeded()
        }

        if let note {
            viewModel.selectNote(note)
        }
        viewModel.show()

        let config = CiderConfig.load()
        let noteToRestore = note ?? viewModel.selectedNote
        if config.rememberNotesPanelPositionPerNote,
           let noteToRestore,
           let savedFrame = notesPanelPositionStore.frame(for: noteToRestore.id) {
            panel.show(frame: savedFrame)
        } else {
            panel.showAtMouse()
        }

        viewModel.setCollapsed(false)
        updateGlobalHotkeyEnablement()
        optionTabDetector?.reclaimPriority()

        // Ensure the editor takes keyboard focus after the panel appears.
        DispatchQueue.main.async { [weak viewModel] in
            viewModel?.focusEditor()
        }
    }

    private func hideNotesPanel() {
        debugLog("[Notes] hideNotesPanel called")
        persistCurrentNotePanelFrameIfNeeded()
        flushNotesDraftIfNeeded()
        notesPanel?.orderOut(nil)
        notesViewModel?.isVisible = false
        updateGlobalHotkeyEnablement()
    }

    private func updateGlobalHotkeyEnablement() {
        let config = CiderConfig.load()
        let notesVisible = notesPanel?.isVisible == true

        debugLog(
            "[Hotkeys] updateGlobalHotkeyEnablement " +
            "notesVisible=\(notesVisible) " +
            "optionTabEnabled=\(config.enableOptionTabCycling) " +
            "tileHotkeysEnabled=\(config.enableTilingHotkeys) " +
            "notesHotkeyEnabled=\(config.enableNotesHotkey)"
        )

        optionTabDetector?.setEnabled(config.enableOptionTabCycling)
        tileHotkeyDetector?.setEnabled(config.enableTilingHotkeys)
        notesHotkeyDetector?.setEnabled(config.enableNotesHotkey)
    }

    private func persistCurrentNotePanelFrameIfNeeded() {
        let config = CiderConfig.load()
        guard config.rememberNotesPanelPositionPerNote else { return }
        guard let panel = notesPanel, panel.isVisible else { return }
        guard let noteID = notesViewModel?.selectedNote?.id else { return }

        notesPanelPositionStore.setFrame(panel.persistableFrame, for: noteID)
    }

    private func flushNotesDraftIfNeeded() {
        guard notesViewModel?.selectedNote != nil else { return }
        notesViewModel?.flushSave()
    }

    private func toggleNotesCollapsed() {
        guard let panel = notesPanel, panel.isVisible else { return }
        panel.toggleCollapsed()
        notesViewModel?.setCollapsed(panel.isCollapsed)
        persistCurrentNotePanelFrameIfNeeded()

        if !panel.isCollapsed {
            DispatchQueue.main.async { [weak self] in
                self?.notesViewModel?.focusEditor()
            }
        }
    }

    private func moveNotesPanelToAdjacentDisplay(direction: Int) {
        guard let panel = notesPanel, panel.isVisible else { return }
        guard let currentMonitor = monitorForNotesPanelFrame(panel.persistableFrame) else { return }

        let monitors = MonitorManager.shared.monitors
        guard monitors.count > 1 else { return }
        guard let currentIndex = monitors.firstIndex(where: { $0.id == currentMonitor.id }) else { return }

        let nextIndex = (currentIndex + direction + monitors.count) % monitors.count
        let targetMonitor = monitors[nextIndex]
        let sourceVisible = currentMonitor.visibleFrame
        let targetVisible = targetMonitor.visibleFrame
        let frame = panel.persistableFrame

        let sourceWidthRange = max(sourceVisible.width - frame.width, 1)
        let sourceHeightRange = max(sourceVisible.height - frame.height, 1)
        let relativeX = (frame.minX - sourceVisible.minX) / sourceWidthRange
        let relativeY = (frame.minY - sourceVisible.minY) / sourceHeightRange

        let targetWidthRange = max(targetVisible.width - frame.width, 0)
        let targetHeightRange = max(targetVisible.height - frame.height, 0)
        let targetX = targetVisible.minX + targetWidthRange * min(max(relativeX, 0), 1)
        let targetY = targetVisible.minY + targetHeightRange * min(max(relativeY, 0), 1)
        let targetFrame = NSRect(x: targetX, y: targetY, width: frame.width, height: frame.height)

        applyFrameToNotesPanel(targetFrame, preserveCollapsedState: panel.isCollapsed)
    }

    private func handleTileHotkeyAction(_ action: TileAction) {
        if routeTileActionToNotesPanelIfNeeded(action) {
            return
        }
        tileActionHandler.execute(action)
    }

    private func routeTileActionToNotesPanelIfNeeded(_ action: TileAction) -> Bool {
        guard let panel = notesPanel, panel.isVisible else { return false }
        guard shouldRouteTileActionToNotesPanel(panel: panel) else { return false }

        let baseFrame = panel.persistableFrame
        guard let monitor = monitorForNotesPanelFrame(baseFrame) else { return false }

        switch action {
        case .tile(let position):
            notesPanelRestoreFrame = baseFrame
            let target = WindowManager.calculateTileFrameStatic(position: position, on: monitor)
            applyFrameToNotesPanel(NSRect(x: target.minX, y: target.minY, width: target.width, height: target.height),
                                   preserveCollapsedState: panel.isCollapsed)
            return true

        case .larger:
            notesPanelRestoreFrame = baseFrame
            let target = resizedNotesPanelFrame(baseFrame, visibleFrame: monitor.visibleFrame, direction: .larger)
            applyFrameToNotesPanel(target, preserveCollapsedState: panel.isCollapsed)
            return true

        case .smaller:
            notesPanelRestoreFrame = baseFrame
            let target = resizedNotesPanelFrame(baseFrame, visibleFrame: monitor.visibleFrame, direction: .smaller)
            applyFrameToNotesPanel(target, preserveCollapsedState: panel.isCollapsed)
            return true

        case .restore:
            guard let restoreFrame = notesPanelRestoreFrame else { return true }
            applyFrameToNotesPanel(restoreFrame, preserveCollapsedState: panel.isCollapsed)
            return true

        case .nextDisplay:
            notesPanelRestoreFrame = baseFrame
            moveNotesPanelToAdjacentDisplay(direction: 1)
            return true

        case .previousDisplay:
            notesPanelRestoreFrame = baseFrame
            moveNotesPanelToAdjacentDisplay(direction: -1)
            return true
        }
    }

    private func shouldRouteTileActionToNotesPanel(panel: NotesPanel) -> Bool {
        if panel.isKeyWindow || NSApp.keyWindow === panel || NSApp.mainWindow === panel {
            return true
        }

        return panel.frame.contains(NSEvent.mouseLocation)
    }

    private func applyFrameToNotesPanel(_ frame: NSRect, preserveCollapsedState: Bool) {
        guard let panel = notesPanel else { return }

        panel.show(frame: frame)
        if preserveCollapsedState {
            panel.setCollapsed(true, animated: false)
        }

        notesViewModel?.setCollapsed(panel.isCollapsed)
        persistCurrentNotePanelFrameIfNeeded()
    }

    private enum NotesPanelResizeDirection {
        case larger
        case smaller
    }

    private func resizedNotesPanelFrame(
        _ frame: NSRect,
        visibleFrame: CGRect,
        direction: NotesPanelResizeDirection
    ) -> NSRect {
        let step = WindowManager.windowPadding
        let insetLeft = frame.minX - visibleFrame.minX
        let insetRight = visibleFrame.maxX - frame.maxX
        let insetTop = visibleFrame.maxY - frame.maxY
        let insetBottom = frame.minY - visibleFrame.minY
        let currentPadding = max(0, min(insetLeft, insetRight, insetTop, insetBottom))

        let newPadding: CGFloat
        switch direction {
        case .larger:
            newPadding = max(0, currentPadding - step)
        case .smaller:
            let maxPadding = min(visibleFrame.width, visibleFrame.height) / 4
            newPadding = min(maxPadding, currentPadding + step)
        }

        let newWidth = visibleFrame.width - newPadding * 2
        let newHeight = visibleFrame.height - newPadding * 2
        let newX = visibleFrame.minX + newPadding
        let newY = visibleFrame.minY + newPadding

        return NSRect(x: newX, y: newY, width: newWidth, height: newHeight)
    }

    private func monitorForNotesPanelFrame(_ frame: NSRect) -> MonitorInfo? {
        MonitorManager.shared.refresh()
        let monitors = MonitorManager.shared.monitors
        guard !monitors.isEmpty else { return nil }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        if let exact = monitors.first(where: { $0.visibleFrame.contains(center) }) {
            return exact
        }

        var bestMonitor: MonitorInfo?
        var maxOverlap: CGFloat = 0
        for monitor in monitors {
            let overlapRect = monitor.visibleFrame.intersection(frame)
            guard !overlapRect.isNull else { continue }
            let overlap = overlapRect.width * overlapRect.height
            if overlap > maxOverlap {
                maxOverlap = overlap
                bestMonitor = monitor
            }
        }

        return bestMonitor ?? monitors.first
    }

    // MARK: - Debug Logging

    private func debugLog(_ message: String) {
        let path = "/tmp/cider-debug.log"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        guard let lineData = line.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { handle.closeFile() }
            handle.seekToEndOfFile()
            handle.write(lineData)
        } else {
            FileManager.default.createFile(atPath: path, contents: lineData)
        }
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
