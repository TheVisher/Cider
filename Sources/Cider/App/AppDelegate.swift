import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    // Double-tap detection
    private var doubleTapDetector: DoubleTapDetector?

    // Notes
    private var notesPanel: NotesPanel?
    private var notesViewModel: NotesViewModel?
    private var notesHotkeyDetector: NotesHotkeyDetector?
    private let notesPanelPositionStore = NotesPanelPositionStore.shared

    // Bookmarks
    private var bookmarksPanel: BookmarksPanel?
    private var bookmarksViewModel: BookmarksViewModel?
    private var bookmarksHotkeyDetector: BookmarksHotkeyDetector?
    private let bookmarksPanelPositionStore = BookmarksPanelPositionStore.shared
    private var bookmarkCaptureToastPanel: BookmarkCaptureToastPanel?
    private var bookmarkCaptureToastHideWorkItem: DispatchWorkItem?
    private let bookmarkClipboardReviewToastModel = BookmarkClipboardReviewToastModel()
    private var bookmarkClipboardReviewTimer: Timer?
    private var bookmarkClipboardReviewIsHovering = false
    private var bookmarkClipboardReviewRemaining: TimeInterval = BookmarksToastDesign.reviewAutoHideDuration
    private var bookmarkClipboardReviewLastTick: Date?

    // Main Cider panel
    private var ciderPanel: CiderPanel?
    private let ciderPanelPositionStore = CiderPanelPositionStore.shared

    // Detail popover
    private var detailPopoverPanel: DetailPopoverPanel?
    private var ciderPanelFrameBeforeDetailModalExpand: NSRect?

    // Notes panel modal behavior (click-outside-to-dismiss from Home tab)
    private var notesPanelModalMonitor: Any?

    // Undo toast
    private var undoToastPanel: BookmarkCaptureToastPanel?
    private let undoToastModel = UndoToastModel()
    private var undoToastTimer: Timer?
    private var undoToastIsHovering = false
    private var undoToastRemaining: TimeInterval = UndoToastDesign.autoHideDuration
    private var undoToastLastTick: Date?

    // Settings
    private var settingsWindow: SettingsWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        AccessibilityHelpers.promptIfNeeded()

        configureSettings()
        configureNotes()
        configureBookmarks()
        configureCiderPanel()
        configureStatusItem()
        observeSettingsNotifications()
        observeNotesNotifications()
        observeBookmarksNotifications()
        observeCiderPanelNotifications()
        observeConfigChanges()
        observeWorkspaceApplicationActivation()
        startDoubleTapDetection()
        startNotesHotkeyDetection()
        startBookmarksHotkeyDetection()
        observeUndoNotifications()

        Task { @MainActor in
            let config = CiderConfig.load()
            if config.trashRetentionDays > 0 {
                TrashStorage.shared.purgeExpired(olderThan: config.trashRetentionDays)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        flushNotesDraftIfNeeded()
        stopBookmarkClipboardReviewTimer()
        bookmarkCaptureToastHideWorkItem?.cancel()
        bookmarkCaptureToastPanel?.orderOut(nil)
        stopUndoToastTimer()
        undoToastPanel?.orderOut(nil)
    }

    func applicationWillResignActive(_ notification: Notification) {
        flushNotesDraftIfNeeded()
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
        menu.addItem(NSMenuItem(title: "Show Cider", action: #selector(toggleCiderPanelFromMenu), keyEquivalent: " "))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Cider", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleCiderPanelFromMenu() {
        toggleCiderPanel()
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

        // Restart double-tap detector if activation mode changed
        doubleTapDetector?.stop()
        doubleTapDetector = nil
        startDoubleTapDetection()

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

        // Handle bookmarks hotkeys enabled/disabled
        if config.enableBookmarksHotkey || config.enableBookmarksCaptureHotkey {
            if bookmarksHotkeyDetector == nil {
                startBookmarksHotkeyDetection()
            } else {
                bookmarksHotkeyDetector?.setEnabled(true)
            }
        } else {
            bookmarksHotkeyDetector?.setEnabled(false)
        }

        updateGlobalHotkeyEnablement()

        // Update notes directory if changed
        let expandedDir = NSString(string: config.notesDirectory).expandingTildeInPath
        NotesStorage.shared.updateDirectory(to: expandedDir)

        // Update bookmarks directory if changed
        let expandedBookmarksDir = NSString(string: config.bookmarksDirectory).expandingTildeInPath
        BookmarksStorage.shared.updateDirectory(to: expandedBookmarksDir)

        // Toggle automatic bookmark capture from copied URLs
        BookmarksClipboardMonitor.shared.setEnabled(config.autoCaptureCopiedURLs)
    }

    private func observeWorkspaceApplicationActivation() {
        ActiveBrowserCaptureService.registerActivatedApplication(NSWorkspace.shared.frontmostApplication)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                ActiveBrowserCaptureService.registerActivatedApplication(app)
            }
            .store(in: &cancellables)
    }

    // MARK: - Double-Tap Detection

    private func startDoubleTapDetection() {
        let config = CiderConfig.load()
        doubleTapDetector = DoubleTapDetector(
            key: .option,
            maxInterval: 0.3,
            mode: config.activationMode
        ) { [weak self] in
            Task { @MainActor in
                self?.toggleCiderPanel()
            }
        }
        doubleTapDetector?.start()
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
            .sink { [weak self] notification in
                self?.showSettings()
                if let category = notification.userInfo?["category"] as? String {
                    NotificationCenter.default.post(
                        name: .settingsNavigate,
                        object: nil,
                        userInfo: ["category": category]
                    )
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .dismissSettings)
            .sink { [weak self] _ in
                self?.hideSettings()
            }
            .store(in: &cancellables)
    }

    private func showSettings() {
        settingsWindow?.showCentered()
    }

    private func hideSettings() {
        settingsWindow?.orderOut(nil)
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
                    let modal = notification.userInfo?["modal"] as? Bool ?? false
                    self?.showNotesPanel(with: note)
                    if modal {
                        self?.installNotesPanelModalMonitor()
                    }
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .toggleNotesCollapse)
            .sink { [weak self] _ in
                self?.toggleNotesCollapsed()
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

        // Ensure the editor takes keyboard focus after the panel appears.
        DispatchQueue.main.async { [weak viewModel] in
            viewModel?.focusEditorIfFindBarHidden()
        }
    }

    private func hideNotesPanel() {
        debugLog("[Notes] hideNotesPanel called")
        removeNotesPanelModalMonitor()
        persistCurrentNotePanelFrameIfNeeded()
        flushNotesDraftIfNeeded()
        notesPanel?.orderOut(nil)
        notesViewModel?.isVisible = false
        updateGlobalHotkeyEnablement()
    }

    private func installNotesPanelModalMonitor() {
        removeNotesPanelModalMonitor()

        // Wait briefly for the panel to fully appear before monitoring
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.notesPanel?.isVisible == true else { return }

            self.notesPanelModalMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self else { return event }

                let mouseScreen = NSEvent.mouseLocation
                let isInsideNotesPanel = self.notesPanel?.frame.contains(mouseScreen) == true

                if isInsideNotesPanel {
                    // Click inside notes panel — remove monitor, let panel behave normally
                    self.removeNotesPanelModalMonitor()
                    return event
                } else {
                    // Click outside notes panel — dismiss and swallow the event
                    // so the underlying panel doesn't open another item
                    self.hideNotesPanel()
                    return nil
                }
            }
        }
    }

    private func removeNotesPanelModalMonitor() {
        if let monitor = notesPanelModalMonitor {
            NSEvent.removeMonitor(monitor)
            notesPanelModalMonitor = nil
        }
    }

    private func updateGlobalHotkeyEnablement() {
        let config = CiderConfig.load()
        let notesVisible = notesPanel?.isVisible == true

        debugLog(
            "[Hotkeys] updateGlobalHotkeyEnablement " +
            "notesVisible=\(notesVisible) " +
            "notesHotkeyEnabled=\(config.enableNotesHotkey) " +
            "bookmarksHotkeyEnabled=\(config.enableBookmarksHotkey) " +
            "bookmarksCaptureHotkeyEnabled=\(config.enableBookmarksCaptureHotkey)"
        )

        notesHotkeyDetector?.setEnabled(config.enableNotesHotkey)
        bookmarksHotkeyDetector?.setEnabled(config.enableBookmarksHotkey || config.enableBookmarksCaptureHotkey)
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

    // MARK: - Bookmarks

    private func configureBookmarks() {
        let viewModel = BookmarksViewModel()
        self.bookmarksViewModel = viewModel

        let panel = BookmarksPanel()
        self.bookmarksPanel = panel

        updateBookmarksPanelView()

        let config = CiderConfig.load()
        BookmarksClipboardMonitor.shared.setEnabled(config.autoCaptureCopiedURLs)
    }

    private func updateBookmarksPanelView() {
        guard let panel = bookmarksPanel, let viewModel = bookmarksViewModel else { return }

        let bookmarksView = BookmarksPanelView(viewModel: viewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        let hostingView = BookmarksPanelHostingView(rootView: bookmarksView)
        panel.contentView = hostingView

        panel.setContentSize(NSSize(
            width: BookmarksDesign.panelContentWidth,
            height: BookmarksDesign.panelContentHeight
        ))
    }

    private func startBookmarksHotkeyDetection() {
        let config = CiderConfig.load()
        guard config.enableBookmarksHotkey || config.enableBookmarksCaptureHotkey else { return }

        bookmarksHotkeyDetector = BookmarksHotkeyDetector(
            onToggle: { [weak self] in
                guard CiderConfig.load().enableBookmarksHotkey else { return }
                self?.toggleBookmarksPanel()
            },
            onCapture: { [weak self] in
                guard CiderConfig.load().enableBookmarksCaptureHotkey else { return }
                self?.captureBookmarkFromHotkey()
            }
        )
        bookmarksHotkeyDetector?.start()
    }

    private func observeBookmarksNotifications() {
        NotificationCenter.default.publisher(for: .toggleBookmarks)
            .sink { [weak self] _ in
                self?.toggleBookmarksPanel()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .showBookmarks)
            .sink { [weak self] _ in
                self?.showBookmarksPanel()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .dismissBookmarks)
            .sink { [weak self] _ in
                self?.hideBookmarksPanel()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .toggleBookmarksCollapse)
            .sink { [weak self] _ in
                self?.toggleBookmarksCollapsed()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .showBookmarkCaptureToast)
            .sink { [weak self] notification in
                let message = notification.userInfo?["message"] as? String ?? "Bookmark updated"
                let isSuccess = notification.userInfo?["isSuccess"] as? Bool ?? true
                self?.showBookmarkCaptureToast(message: message, isSuccess: isSuccess)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .showBookmarkClipboardReviewToast)
            .sink { [weak self] notification in
                guard let urlString = notification.userInfo?["urlString"] as? String else { return }
                self?.showBookmarkClipboardReviewToast(urlString: urlString)
            }
            .store(in: &cancellables)
    }

    // MARK: - Undo Toast

    private func observeUndoNotifications() {
        NotificationCenter.default.publisher(for: .showUndoToast)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                let message = notification.userInfo?["message"] as? String ?? ""
                let showViewTrash = notification.userInfo?["showViewTrash"] as? Bool ?? false
                self?.showUndoToast(message: message, showViewTrash: showViewTrash)
            }
            .store(in: &cancellables)
    }

    private func showUndoToast(message: String, showViewTrash: Bool) {
        stopUndoToastTimer()
        undoToastIsHovering = false
        undoToastRemaining = UndoToastDesign.autoHideDuration
        undoToastModel.progress = 1

        if undoToastPanel == nil {
            undoToastPanel = BookmarkCaptureToastPanel()
        }
        guard let panel = undoToastPanel else { return }

        let toastView = UndoToastView(
            model: undoToastModel,
            message: message,
            showViewTrash: showViewTrash,
            onUndo: { [weak self] in
                CiderUndoManager.shared.undo()
                self?.dismissUndoToast()
            },
            onViewTrash: { [weak self] in
                self?.dismissUndoToast()
                NotificationCenter.default.post(name: .openCiderSettings, object: nil,
                    userInfo: ["category": "storage"])
            },
            onHoverChanged: { [weak self] hovering in
                guard let self else { return }
                if hovering {
                    self.undoToastIsHovering = true
                    self.undoToastRemaining = UndoToastDesign.autoHideDuration
                    self.undoToastModel.progress = 1
                    self.stopUndoToastTimer()
                } else {
                    self.undoToastIsHovering = false
                    self.startUndoToastTimer()
                }
            }
        )
        let hostingView = BookmarkCaptureToastHostingView(rootView: toastView)
        hostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: UndoToastDesign.panelWidth, height: UndoToastDesign.panelHeight)
        )
        panel.contentView = hostingView
        panel.setContentSize(NSSize(width: UndoToastDesign.panelWidth, height: UndoToastDesign.panelHeight))

        let frame = undoToastFrame(position: CiderConfig.load().undoToastPosition)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()

        startUndoToastTimer()
    }

    private func undoToastFrame(position: ToastPosition) -> NSRect {
        let w = UndoToastDesign.panelWidth
        let h = UndoToastDesign.panelHeight
        let inset = UndoToastDesign.panelEdgeInset

        switch position {
        case .topCenterScreen:
            let mouseLocation = NSEvent.mouseLocation
            let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
                ?? NSScreen.main ?? NSScreen.screens.first
            let visibleFrame = screen?.visibleFrame ?? .zero
            let x = visibleFrame.midX - w / 2
            let y = visibleFrame.maxY - h - Spacing.xxxl
            return NSRect(x: x, y: y, width: w, height: h)

        case .bottomRightPanel:
            guard let panelFrame = ciderPanel?.frame else { return .zero }
            let x = panelFrame.maxX - w - inset
            let y = panelFrame.minY + inset
            return NSRect(x: x, y: y, width: w, height: h)

        case .bottomLeftPanel:
            guard let panelFrame = ciderPanel?.frame else { return .zero }
            let x = panelFrame.minX + inset
            let y = panelFrame.minY + inset
            return NSRect(x: x, y: y, width: w, height: h)

        case .topRightPanel:
            guard let panelFrame = ciderPanel?.frame else { return .zero }
            let x = panelFrame.maxX - w - inset
            let y = panelFrame.maxY - h - inset
            return NSRect(x: x, y: y, width: w, height: h)

        case .topLeftPanel:
            guard let panelFrame = ciderPanel?.frame else { return .zero }
            let x = panelFrame.minX + inset
            let y = panelFrame.maxY - h - inset
            return NSRect(x: x, y: y, width: w, height: h)
        }
    }

    private func startUndoToastTimer() {
        stopUndoToastTimer()
        undoToastLastTick = Date()

        let timer = Timer(timeInterval: BookmarksToastDesign.reviewProgressTickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.undoToastTimerTick()
            }
        }
        undoToastTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopUndoToastTimer() {
        undoToastTimer?.invalidate()
        undoToastTimer = nil
        undoToastLastTick = nil
    }

    private func undoToastTimerTick() {
        guard !undoToastIsHovering else { return }
        guard let lastTick = undoToastLastTick else {
            undoToastLastTick = Date()
            return
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastTick)
        undoToastLastTick = now
        guard elapsed.isFinite, elapsed > 0 else { return }

        undoToastRemaining -= elapsed
        let duration = max(UndoToastDesign.autoHideDuration, 0.01)

        if undoToastRemaining <= 0 {
            undoToastModel.progress = 0
            dismissUndoToast()
            return
        }

        undoToastModel.progress = max(0, min(1, undoToastRemaining / duration))
    }

    private func dismissUndoToast() {
        stopUndoToastTimer()
        undoToastPanel?.orderOut(nil)
        CiderUndoManager.shared.discard()
    }

    private func toggleBookmarksPanel() {
        guard let panel = bookmarksPanel else { return }

        if panel.isVisible {
            hideBookmarksPanel()
        } else {
            showBookmarksPanel()
        }
    }

    private func showBookmarksPanel() {
        guard let panel = bookmarksPanel, let viewModel = bookmarksViewModel else { return }

        if panel.isVisible {
            persistCurrentBookmarksPanelFrameIfNeeded()
        }

        viewModel.show()
        viewModel.setCollapsed(false)
        panel.setCollapsed(false, animated: false)

        let config = CiderConfig.load()
        if config.rememberBookmarksPanelPosition,
           let savedFrame = bookmarksPanelPositionStore.frame() {
            panel.show(frame: savedFrame)
        } else {
            panel.showAtMouse()
        }

        updateGlobalHotkeyEnablement()
    }

    private func hideBookmarksPanel() {
        persistCurrentBookmarksPanelFrameIfNeeded()
        bookmarksPanel?.orderOut(nil)
        bookmarksViewModel?.isVisible = false
        updateGlobalHotkeyEnablement()
    }

    private func toggleBookmarksCollapsed() {
        guard let panel = bookmarksPanel, panel.isVisible else { return }
        panel.toggleCollapsed()
        bookmarksViewModel?.setCollapsed(panel.isCollapsed)
        persistCurrentBookmarksPanelFrameIfNeeded()
    }

    private func captureBookmarkFromHotkey() {
        guard let viewModel = bookmarksViewModel else { return }
        _ = viewModel.captureBookmarkFromActiveBrowserOrClipboard()
    }

    private func persistCurrentBookmarksPanelFrameIfNeeded() {
        let config = CiderConfig.load()
        guard config.rememberBookmarksPanelPosition else { return }
        guard let panel = bookmarksPanel, panel.isVisible else { return }
        bookmarksPanelPositionStore.setFrame(panel.persistableFrame)
    }

    private func showBookmarkCaptureToast(message: String, isSuccess: Bool) {
        stopBookmarkClipboardReviewTimer()
        bookmarkClipboardReviewIsHovering = false
        bookmarkClipboardReviewToastModel.progress = 1
        bookmarkCaptureToastHideWorkItem?.cancel()
        bookmarkCaptureToastHideWorkItem = nil

        let panel = resolveBookmarkCaptureToastPanel()

        let toastView = BookmarkCaptureToastView(message: message, isSuccess: isSuccess)
        let hostingView = BookmarkCaptureToastHostingView(rootView: toastView)
        panel.contentView = hostingView
        showBookmarkToastPanel(panel, contentHeight: BookmarksToastDesign.height)

        let hideWork = DispatchWorkItem { [weak self, weak panel] in
            panel?.orderOut(nil)
            self?.bookmarkCaptureToastHideWorkItem = nil
        }
        bookmarkCaptureToastHideWorkItem = hideWork
        DispatchQueue.main.asyncAfter(deadline: .now() + BookmarksToastDesign.autoHideDuration, execute: hideWork)
    }

    private func showBookmarkClipboardReviewToast(urlString: String) {
        stopBookmarkClipboardReviewTimer()
        bookmarkClipboardReviewIsHovering = false
        bookmarkClipboardReviewRemaining = BookmarksToastDesign.reviewAutoHideDuration
        bookmarkClipboardReviewToastModel.progress = 1
        bookmarkCaptureToastHideWorkItem?.cancel()
        bookmarkCaptureToastHideWorkItem = nil

        guard let normalized = BookmarksStorage.shared.previewNormalizedURLString(from: urlString),
              let url = URL(string: normalized) else {
            return
        }

        let panel = resolveBookmarkCaptureToastPanel()
        let urlDisplay = compactURLDisplay(from: url)
        let toastView = BookmarkClipboardReviewToastView(
            model: bookmarkClipboardReviewToastModel,
            urlDisplay: urlDisplay,
            onHoverChanged: { [weak self] hovering in
                self?.handleBookmarkClipboardReviewHoverChange(hovering)
            },
            onSave: { [weak self] in
                guard let self else { return }
                let saved = BookmarksStorage.shared.add(urlString: normalized, title: nil) != nil
                self.showBookmarkCaptureToast(
                    message: saved ? "Saved copied URL" : "Could not save copied URL",
                    isSuccess: saved
                )
            },
            onDiscard: { [weak self] in
                self?.dismissBookmarkCaptureToast()
            }
        )
        let hostingView = BookmarkCaptureToastHostingView(rootView: toastView)
        panel.contentView = hostingView
        showBookmarkToastPanel(panel, contentHeight: BookmarksToastDesign.reviewHeight)
        startBookmarkClipboardReviewTimer(resetToFull: true)
    }

    private func dismissBookmarkCaptureToast() {
        stopBookmarkClipboardReviewTimer()
        bookmarkClipboardReviewIsHovering = false
        bookmarkClipboardReviewToastModel.progress = 1
        bookmarkCaptureToastHideWorkItem?.cancel()
        bookmarkCaptureToastHideWorkItem = nil
        bookmarkCaptureToastPanel?.orderOut(nil)
    }

    private func handleBookmarkClipboardReviewHoverChange(_ hovering: Bool) {
        guard bookmarkClipboardReviewIsHovering != hovering else { return }
        bookmarkClipboardReviewIsHovering = hovering

        if hovering {
            bookmarkClipboardReviewRemaining = BookmarksToastDesign.reviewAutoHideDuration
            bookmarkClipboardReviewToastModel.progress = 1
            stopBookmarkClipboardReviewTimer()
        } else {
            startBookmarkClipboardReviewTimer(resetToFull: true)
        }
    }

    private func startBookmarkClipboardReviewTimer(resetToFull: Bool) {
        stopBookmarkClipboardReviewTimer()

        if resetToFull {
            bookmarkClipboardReviewRemaining = BookmarksToastDesign.reviewAutoHideDuration
            bookmarkClipboardReviewToastModel.progress = 1
        }
        bookmarkClipboardReviewLastTick = Date()

        let timer = Timer(timeInterval: BookmarksToastDesign.reviewProgressTickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.bookmarkClipboardReviewTimerTick()
            }
        }
        bookmarkClipboardReviewTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopBookmarkClipboardReviewTimer() {
        bookmarkClipboardReviewTimer?.invalidate()
        bookmarkClipboardReviewTimer = nil
        bookmarkClipboardReviewLastTick = nil
    }

    private func bookmarkClipboardReviewTimerTick() {
        guard !bookmarkClipboardReviewIsHovering else { return }
        guard let lastTick = bookmarkClipboardReviewLastTick else {
            bookmarkClipboardReviewLastTick = Date()
            return
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastTick)
        bookmarkClipboardReviewLastTick = now
        guard elapsed.isFinite, elapsed > 0 else { return }

        bookmarkClipboardReviewRemaining -= elapsed
        let duration = max(BookmarksToastDesign.reviewAutoHideDuration, 0.01)

        if bookmarkClipboardReviewRemaining <= 0 {
            bookmarkClipboardReviewToastModel.progress = 0
            dismissBookmarkCaptureToast()
            return
        }

        bookmarkClipboardReviewToastModel.progress = max(0, min(1, bookmarkClipboardReviewRemaining / duration))
    }

    private func resolveBookmarkCaptureToastPanel() -> BookmarkCaptureToastPanel {
        if let existingPanel = bookmarkCaptureToastPanel {
            return existingPanel
        }

        let newPanel = BookmarkCaptureToastPanel()
        bookmarkCaptureToastPanel = newPanel
        return newPanel
    }

    private func showBookmarkToastPanel(_ panel: BookmarkCaptureToastPanel, contentHeight: CGFloat) {
        let panelWidth = BookmarksToastDesign.panelWidth
        let panelHeight = contentHeight + BookmarksToastDesign.shadowPadding * 2
        panel.setContentSize(NSSize(width: panelWidth, height: panelHeight))

        let position = CiderConfig.load().captureToastPosition
        let frame = captureToastFrame(position: position, panelWidth: panelWidth, panelHeight: panelHeight)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    private func captureToastFrame(position: ToastPosition, panelWidth: CGFloat, panelHeight: CGFloat) -> NSRect {
        let inset = UndoToastDesign.panelEdgeInset
        switch position {
        case .topCenterScreen:
            let mouseLocation = NSEvent.mouseLocation
            let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
                ?? NSScreen.main ?? NSScreen.screens.first
            let visibleFrame = screen?.visibleFrame ?? .zero
            let x = visibleFrame.midX - panelWidth / 2
            let y = visibleFrame.maxY - panelHeight - BookmarksToastDesign.topInset
            return NSRect(x: x, y: y, width: panelWidth, height: panelHeight)

        case .bottomRightPanel:
            guard let panelFrame = ciderPanel?.frame else { return .zero }
            return NSRect(x: panelFrame.maxX - panelWidth - inset, y: panelFrame.minY + inset,
                          width: panelWidth, height: panelHeight)

        case .bottomLeftPanel:
            guard let panelFrame = ciderPanel?.frame else { return .zero }
            return NSRect(x: panelFrame.minX + inset, y: panelFrame.minY + inset,
                          width: panelWidth, height: panelHeight)

        case .topRightPanel:
            guard let panelFrame = ciderPanel?.frame else { return .zero }
            return NSRect(x: panelFrame.maxX - panelWidth - inset, y: panelFrame.maxY - panelHeight - inset,
                          width: panelWidth, height: panelHeight)

        case .topLeftPanel:
            guard let panelFrame = ciderPanel?.frame else { return .zero }
            return NSRect(x: panelFrame.minX + inset, y: panelFrame.maxY - panelHeight - inset,
                          width: panelWidth, height: panelHeight)
        }
    }

    private func compactURLDisplay(from url: URL) -> String {
        let host = url.host ?? url.absoluteString
        let path = url.path.isEmpty ? "" : url.path
        let query = url.query.map { "?\($0)" } ?? ""
        let compact = "\(host)\(path)\(query)"
        return compact.count > 72 ? "\(compact.prefix(69))..." : compact
    }

    // MARK: - Cider Panel

    private func configureCiderPanel() {
        guard bookmarksViewModel != nil, notesViewModel != nil else { return }

        let panel = CiderPanel()
        self.ciderPanel = panel

        updateCiderPanelView()
    }

    private func updateCiderPanelView() {
        guard let panel = ciderPanel,
              let bookmarksViewModel,
              let notesViewModel else { return }

        let panelView = CiderPanelView(
            bookmarksViewModel: bookmarksViewModel,
            notesViewModel: notesViewModel
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        let hostingView = CiderPanelHostingView(rootView: panelView)
        panel.contentView = hostingView

        panel.setContentSize(NSSize(
            width: CiderPanelDesign.panelContentWidth,
            height: CiderPanelDesign.panelContentHeight
        ))
    }

    private func observeCiderPanelNotifications() {
        NotificationCenter.default.publisher(for: .toggleCiderPanel)
            .sink { [weak self] _ in
                self?.toggleCiderPanel()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .dismissCiderPanel)
            .sink { [weak self] _ in
                self?.hideCiderPanel()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .toggleCiderPanelCollapse)
            .sink { [weak self] _ in
                self?.toggleCiderPanelCollapsed()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .maximizeCiderPanel)
            .sink { [weak self] _ in
                self?.maximizeCiderPanel()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .showDetailPopover)
            .sink { [weak self] notification in
                self?.showDetailPopover(notification)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .dismissDetailPopover)
            .sink { [weak self] _ in
                self?.dismissDetailPopover()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .expandCiderPanelForDetailModal)
            .sink { [weak self] notification in
                self?.expandCiderPanelForDetailModal(notification)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .restoreCiderPanelAfterDetailModal)
            .sink { [weak self] _ in
                self?.restoreCiderPanelAfterDetailModal()
            }
            .store(in: &cancellables)
    }

    private func toggleCiderPanel() {
        guard let panel = ciderPanel else { return }

        if panel.isVisible {
            hideCiderPanel()
        } else {
            showCiderPanel()
        }
    }

    private func showCiderPanel() {
        guard let panel = ciderPanel else { return }
        ciderPanelFrameBeforeDetailModalExpand = nil

        if panel.isVisible {
            persistCurrentCiderPanelFrameIfNeeded()
        }

        panel.setCollapsed(false, animated: false)

        if let savedFrame = ciderPanelPositionStore.frame() {
            panel.show(frame: savedFrame)
        } else {
            panel.showAtMouse()
        }
    }

    private func hideCiderPanel() {
        persistCurrentCiderPanelFrameIfNeeded()
        dismissDetailPopover()
        ciderPanelFrameBeforeDetailModalExpand = nil
        ciderPanel?.orderOut(nil)
    }

    private func toggleCiderPanelCollapsed() {
        guard let panel = ciderPanel, panel.isVisible else { return }
        panel.toggleCollapsed()
        persistCurrentCiderPanelFrameIfNeeded()
    }

    private func showDetailPopover(_ notification: Notification) {
        guard let panel = ciderPanel, panel.isVisible else { return }
        guard let contentView = notification.userInfo?["view"] as? AnyView else { return }
        let preferredWidth = (notification.userInfo?["preferredWidth"] as? CGFloat)
            ?? (notification.userInfo?["preferredWidth"] as? Double).map { CGFloat($0) }
            ?? 600

        let popover = detailPopoverPanel ?? DetailPopoverPanel()
        detailPopoverPanel = popover

        popover.showAdjacent(to: panel, preferredWidth: preferredWidth, content: contentView)
    }

    private func dismissDetailPopover() {
        detailPopoverPanel?.orderOut(nil)
    }

    private func expandCiderPanelForDetailModal(_ notification: Notification) {
        guard let panel = ciderPanel, panel.isVisible else { return }

        let requestedWidth = (notification.userInfo?["minimumWidth"] as? CGFloat)
            ?? (notification.userInfo?["minimumWidth"] as? Double).map { CGFloat($0) }
            ?? BookmarksDesign.detailsRequiredPanelWidth
        let sidebarCompensation = BookmarksDesign.folderSidebarWidth + Spacing.md
        let requiredWidth = max(requestedWidth + sidebarCompensation, CiderPanelDesign.panelMinWidth)

        guard panel.frame.width + 0.5 < requiredWidth else { return }

        if ciderPanelFrameBeforeDetailModalExpand == nil {
            ciderPanelFrameBeforeDetailModalExpand = panel.frame
        }

        let targetFrame = expandedDetailFrame(
            from: panel.frame,
            targetWidth: requiredWidth,
            screenVisibleFrame: panel.screen?.visibleFrame ?? panel.frame
        )

        guard abs(targetFrame.width - panel.frame.width) > 0.5
                || abs(targetFrame.minX - panel.frame.minX) > 0.5 else {
            return
        }

        panel.setFrame(targetFrame, display: true, animate: false)
        persistCurrentCiderPanelFrameIfNeeded()
    }

    private func restoreCiderPanelAfterDetailModal() {
        guard let restoreFrame = ciderPanelFrameBeforeDetailModalExpand else { return }
        guard let panel = ciderPanel, panel.isVisible else {
            ciderPanelFrameBeforeDetailModalExpand = nil
            return
        }

        let targetFrame = expandedDetailFrame(
            from: restoreFrame,
            targetWidth: restoreFrame.width,
            screenVisibleFrame: panel.screen?.visibleFrame ?? panel.frame
        )

        panel.setFrame(targetFrame, display: true, animate: false)
        ciderPanelFrameBeforeDetailModalExpand = nil
        persistCurrentCiderPanelFrameIfNeeded()
    }

    private func expandedDetailFrame(
        from frame: NSRect,
        targetWidth: CGFloat,
        screenVisibleFrame: NSRect
    ) -> NSRect {
        let clampedWidth = min(max(targetWidth, CiderPanelDesign.panelMinWidth), screenVisibleFrame.width)
        let clampedHeight = min(frame.height, screenVisibleFrame.height)
        let preferredX = frame.maxX - clampedWidth
        let x = min(
            max(preferredX, screenVisibleFrame.minX),
            screenVisibleFrame.maxX - clampedWidth
        )
        let y = min(
            max(frame.minY, screenVisibleFrame.minY),
            screenVisibleFrame.maxY - clampedHeight
        )
        return NSRect(x: x, y: y, width: clampedWidth, height: clampedHeight)
    }

    private func maximizeCiderPanel() {
        guard let panel = ciderPanel, panel.isVisible else { return }

        if panel.isMaximized, let restoreFrame = panel.frameBeforeMaximize {
            // Restore to previous size
            panel.isMaximized = false
            panel.frameBeforeMaximize = nil
            panel.setCollapsed(false, animated: false)
            panel.setFrame(restoreFrame, display: true)
            persistCurrentCiderPanelFrameIfNeeded()
            return
        }

        // Save current frame for restore
        panel.frameBeforeMaximize = panel.frame

        let panelCenter = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(panelCenter) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let visibleFrame = screen.visibleFrame
        let padding = CiderPanelDesign.shadowPadding

        let maximizedFrame = NSRect(
            x: visibleFrame.minX - padding,
            y: visibleFrame.minY - CiderPanelDesign.bottomPadding - padding,
            width: visibleFrame.width + padding * 2,
            height: visibleFrame.height + CiderPanelDesign.topPadding + CiderPanelDesign.bottomPadding + padding
        )

        panel.setCollapsed(false, animated: false)
        panel.setFrame(maximizedFrame, display: true)
        panel.isMaximized = true
        persistCurrentCiderPanelFrameIfNeeded()
    }

    private func persistCurrentCiderPanelFrameIfNeeded() {
        guard let panel = ciderPanel, panel.isVisible else { return }
        ciderPanelPositionStore.setFrame(panel.persistableFrame)
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
}
