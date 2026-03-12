import AppKit
import SwiftUI
import Combine
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    // Double-tap detection
    private var doubleTapDetector: DoubleTapDetector?

    // Notes
    private var notesViewModel: NotesViewModel?
    private var notesHotkeyDetector: NotesHotkeyDetector?

    // Bookmarks
    private var bookmarksViewModel: BookmarksViewModel?
    private var bookmarksHotkeyDetector: BookmarksHotkeyDetector?
    private var bookmarkCaptureToastPanel: BookmarkCaptureToastPanel?
    private var bookmarkCaptureToastHideWorkItem: DispatchWorkItem?
    private let bookmarkClipboardReviewToastModel = BookmarkClipboardReviewToastModel()
    private var bookmarkClipboardReviewTimer: Timer?
    private var bookmarkClipboardReviewIsHovering = false
    private var bookmarkClipboardReviewRemaining: TimeInterval = BookmarksToastDesign.reviewAutoHideDuration
    private var bookmarkClipboardReviewLastTick: Date?

    // Main Cider panel
    private var ciderPanel: CiderPanel?
    private var ciderShadowPanel: CiderShadowPanel?
    private var panelFrameObservation: NSKeyValueObservation?
    private let ciderPanelPositionStore = CiderPanelPositionStore.shared
    private var frameBeforeSlideOut: NSRect?

    // Undo toast
    private var undoToastPanel: BookmarkCaptureToastPanel?
    private let undoToastModel = UndoToastModel()
    private var undoToastTimer: Timer?
    private var undoToastIsHovering = false
    private var undoToastRemaining: TimeInterval = UndoToastDesign.autoHideDuration
    private var undoToastLastTick: Date?

    // Screen capture
    private var screenCaptureHotkeyDetector: ScreenCaptureHotkeyDetector?
    private var screenCaptureToastPanel: ScreenCaptureToastPanel?
    private let screenCaptureToastModel = ScreenCaptureToastModel()
    private var screenCaptureToastTimer: Timer?
    private var screenCaptureToastIsHovering = false
    private var screenCaptureToastRemaining: TimeInterval = ScreenCaptureToastDesign.autoHideDuration
    private var screenCaptureToastLastTick: Date?
    private var screenCaptureWasVisible = false

    // Clipboard
    private var clipboardHotkeyDetector: ClipboardHotkeyDetector?
    private var clipboardPanel: ClipboardPanel?
    private var clipboardShadowPanel: CiderShadowPanel?
    private var clipboardPanelFrameObservation: NSKeyValueObservation?

    // AI Chat
    private var aiChatPanel: AIChatPanel?
    private var aiChatShadowPanel: CiderShadowPanel?
    private var aiChatPanelFrameObservation: NSKeyValueObservation?
    // AI Chat view model is AIChatViewModel.shared (singleton)

    // Services
    private var servicesProvider: CiderServicesProvider?

    // Spotlight
    private var spotlightIndexer: SpotlightIndexer?

    // Notifications
    private var dateCardNotificationService: DateCardNotificationService?
    private var dateCardNotificationCancellable: AnyCancellable?

    // Settings
    private var settingsWindow: SettingsWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        AccessibilityHelpers.promptIfNeeded()
        VaultStructureMigration.migrateIfNeeded()
        StoragePaths.ensureVaultStructure()

        // Ensure Unsorted directory exists for unfiled items (visible in Finder, hidden in Cider)
        let unsortedURL = StoragePaths.cachedVaultDirectoryURL.appendingPathComponent("Unsorted")
        StoragePaths.ensureDirectory(unsortedURL)

        configureSettings()
        configureNotes()
        configureBookmarks()
        configureCiderPanel()
        configureStatusItem()
        observeSettingsNotifications()
        observeBookmarksNotifications()
        observeCiderPanelNotifications()
        observeConfigChanges()
        observeWorkspaceApplicationActivation()
        startDoubleTapDetection()
        startNotesHotkeyDetection()
        startBookmarksHotkeyDetection()
        observeUndoNotifications()
        observeSourcesNotifications()
        startScreenCaptureHotkeyDetection()
        observeScreenCaptureNotifications()
        startClipboardHotkeyDetection()
        configureClipboardHistory()
        configureClipboardPanel()
        observeClipboardViewerNotifications()
        configureAIChatPanel()
        observeAIChatNotifications()

        // Build vault index if empty (first run or rebuild needed)
        if VaultIndexService.shared.entries.isEmpty {
            VaultIndexService.shared.rebuildFromCurrentState()
        }

        // Load sidecar metadata and scan vault files
        SidecarService.shared.loadAll()
        VaultFileService.shared.scan()

        // Start Cider Web sync if configured
        SyncService.shared.startIfEnabled()

        // Start Spotlight indexing.
        // Note: Core Spotlight requires a proper .app bundle to surface results in
        // Spotlight/Raycast. During development (bare SPM executable), items are indexed
        // but won't appear in system search. Works once packaged as .app for distribution.
        if Bundle.main.bundleURL.pathExtension == "app" {
            LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
            NSUpdateDynamicServices()
        }
        spotlightIndexer = SpotlightIndexer.shared
        spotlightIndexer?.start()

        // Register macOS Services provider ("Send to Cider" in Services menu)
        let provider = CiderServicesProvider()
        NSApp.servicesProvider = provider
        servicesProvider = provider

        // Start Sparkle auto-updater
        SparkleUpdaterService.shared.start()

        Task { @MainActor in
            let config = CiderConfig.load()
            if config.trashRetentionDays > 0 {
                TrashStorage.shared.purgeExpired(olderThan: config.trashRetentionDays)
            }
            ClipboardStorage.shared.purgeExpired(config: config)
            // Load persisted embeddings so similarity search works immediately,
            // then backfill any bookmarks that have no vector yet.
            EmbeddingStore.shared.load()
            if config.enableEmbeddings {
                EmbeddingStore.shared.backfillMissing(bookmarks: BookmarksStorage.shared.bookmarks)
            }

            // Date card notifications — always subscribe, service gates on config internally
            let notificationService = DateCardNotificationService.shared
            self.dateCardNotificationService = notificationService
            if config.enableDateCardNotifications {
                Task {
                    let granted = await notificationService.requestPermission()
                    if granted {
                        notificationService.rescheduleAll()
                    }
                }
            }
            self.dateCardNotificationCancellable = DateCardStorage.shared.$dateCards
                .debounce(for: .seconds(2), scheduler: RunLoop.main)
                .sink { dateCards in
                    notificationService.scheduleNotifications(for: dateCards)
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
        stopScreenCaptureToastTimer()
        screenCaptureToastPanel?.orderOut(nil)
        clipboardShadowPanel?.orderOut(nil)
        clipboardPanel?.orderOut(nil)
        aiChatShadowPanel?.orderOut(nil)
        aiChatPanel?.orderOut(nil)
    }

    func applicationWillResignActive(_ notification: Notification) {
        flushNotesDraftIfNeeded()
    }

    // MARK: - Spotlight Deep Links

    func application(_ application: NSApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        SpotlightIndexer.handleUserActivity(userActivity)
    }

    // MARK: - File Open Handler

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

            if isDirectory.boolValue {
                // User opened a directory URL — link it as a new source
                ExternalSourceStorage.shared.addSource(
                    path: url.path,
                    displayName: url.lastPathComponent
                )
                // Bring Cider panel to front
                NotificationCenter.default.post(name: .toggleCiderPanel, object: nil)
            } else if url.pathExtension.lowercased() == "md" {
                // Markdown file — find or create its parent source, then select file
                let parentPath = url.deletingLastPathComponent().path
                let existingSource = ExternalSourceStorage.shared.sources.first(where: { $0.path == parentPath })
                let source: ExternalSource
                if let existing = existingSource {
                    source = existing
                } else {
                    source = ExternalSourceStorage.shared.addSource(
                        path: parentPath,
                        displayName: url.deletingLastPathComponent().lastPathComponent
                    )
                }
                NotificationCenter.default.post(name: .toggleCiderPanel, object: nil)
                NotificationCenter.default.post(
                    name: .openExternalSourceAndSelectFile,
                    object: nil,
                    userInfo: [
                        "sourceID": source.id,
                        "fileURL": url
                    ]
                )
            }
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
            if let iconURL = Bundle.main.url(forResource: "menubar-icon", withExtension: "png"),
               let icon = NSImage(contentsOf: iconURL) {
                icon.size = NSSize(width: 18, height: 18)
                icon.isTemplate = true
                button.image = icon
            } else {
                button.image = NSImage(systemSymbolName: "command", accessibilityDescription: "Cider")
            }
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
        CiderFont.invalidateScale()
        StoragePaths.invalidateCachedDirectory()

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

        // Update storage directories from vault paths
        let notesDir = StoragePaths.directoryURL(for: .notes).path
        NotesStorage.shared.updateDirectory(to: notesDir)

        let bookmarksDir = StoragePaths.directoryURL(for: .bookmarks).path
        BookmarksStorage.shared.updateDirectory(to: bookmarksDir)

        // Reload shared-data storages (they use computed fileURL, just need a fresh load)
        ContactStorage.shared.reload()
        DateCardStorage.shared.reload()
        CardLabelStorage.shared.reload()
        CardStackStorage.shared.reload()
        SavedViewStorage.shared.reload()
        ExternalSourceStorage.shared.reload()
        ClipboardStorage.shared.reload()

        // Toggle automatic bookmark capture from copied URLs/images
        BookmarksClipboardMonitor.shared.setEnabled(config.autoCaptureCopiedURLs || config.autoCaptureCopiedImages)

        // Toggle Spotlight indexing
        if config.enableSpotlightIndexing {
            spotlightIndexer?.start()
        } else {
            spotlightIndexer?.stop()
        }

        // Toggle date card notifications
        if config.enableDateCardNotifications {
            Task {
                let granted = await DateCardNotificationService.shared.requestPermission()
                if granted {
                    DateCardNotificationService.shared.rescheduleAll()
                }
            }
        } else {
            DateCardNotificationService.shared.rescheduleAll() // clears all when disabled
        }

        // Toggle clipboard history
        ClipboardHistoryService.shared.setEnabled(config.enableClipboardHistory)

        // Toggle clipboard hotkey
        if config.enableClipboardHotkey {
            if clipboardHotkeyDetector == nil {
                startClipboardHotkeyDetection()
            } else {
                clipboardHotkeyDetector?.setEnabled(true)
            }
        } else {
            clipboardHotkeyDetector?.setEnabled(false)
        }

        // Toggle Cider Web sync
        SyncService.shared.startIfEnabled()
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
        notesViewModel = NotesViewModel()
    }

    private func startNotesHotkeyDetection() {
        let config = CiderConfig.load()
        guard config.enableNotesHotkey else { return }

        notesHotkeyDetector = NotesHotkeyDetector()
        notesHotkeyDetector?.start()
    }

    private func updateGlobalHotkeyEnablement() {
        let config = CiderConfig.load()
        notesHotkeyDetector?.setEnabled(config.enableNotesHotkey)
        bookmarksHotkeyDetector?.setEnabled(config.enableBookmarksHotkey || config.enableBookmarksCaptureHotkey)
    }

    private func flushNotesDraftIfNeeded() {
        guard notesViewModel?.selectedNote != nil || notesViewModel?.activeExternalFile != nil else { return }
        notesViewModel?.flushSave()
    }

    // MARK: - Bookmarks

    private func configureBookmarks() {
        bookmarksViewModel = BookmarksViewModel()

        let config = CiderConfig.load()
        BookmarksClipboardMonitor.shared.setEnabled(config.autoCaptureCopiedURLs || config.autoCaptureCopiedImages)
    }

    private func startBookmarksHotkeyDetection() {
        let config = CiderConfig.load()
        guard config.enableBookmarksHotkey || config.enableBookmarksCaptureHotkey else { return }

        bookmarksHotkeyDetector = BookmarksHotkeyDetector()
        bookmarksHotkeyDetector?.start()
    }

    private func captureBookmarkFromHotkey() {
        guard let viewModel = bookmarksViewModel else { return }
        _ = viewModel.captureBookmarkFromActiveBrowserOrClipboard()
    }

    private func observeBookmarksNotifications() {
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

        NotificationCenter.default.publisher(for: .showImageClipboardReviewToast)
            .sink { [weak self] _ in
                self?.showImageClipboardReviewToast()
            }
            .store(in: &cancellables)
    }

    // MARK: - External Sources

    private func observeSourcesNotifications() {
        NotificationCenter.default.publisher(for: .openExternalFile)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let url = notification.userInfo?["fileURL"] as? URL,
                      let viewModel = self.notesViewModel else { return }
                let file = ExternalSourceRegistry.shared.libraryFiles.first(where: { $0.path == url })
                    ?? ExternalFile(
                        id: ExternalFile.stableID(for: url.path),
                        title: url.deletingPathExtension().lastPathComponent,
                        path: url,
                        sourceID: UUID(),
                        sourceName: url.deletingLastPathComponent().lastPathComponent,
                        createdAt: Date(),
                        modifiedAt: Date()
                    )
                viewModel.openExternalFile(file)
                self.showCiderPanel()
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
        CiderSoundEffect.trash.play()
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
                    userInfo: ["category": "data"])
            },
            onHoverChanged: { [weak self] hovering in
                guard let self else { return }
                if hovering {
                    self.undoToastIsHovering = true
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

    private func showBookmarkCaptureToast(message: String, isSuccess: Bool) {
        if isSuccess { CiderSoundEffect.save.play() }
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

    private func showImageClipboardReviewToast() {
        CiderSoundEffect.clipboardReview.play()
        stopBookmarkClipboardReviewTimer()
        bookmarkClipboardReviewIsHovering = false
        bookmarkClipboardReviewRemaining = BookmarksToastDesign.reviewAutoHideDuration
        bookmarkClipboardReviewToastModel.progress = 1
        bookmarkCaptureToastHideWorkItem?.cancel()
        bookmarkCaptureToastHideWorkItem = nil

        let panel = resolveBookmarkCaptureToastPanel()
        let toastView = ImageClipboardReviewToastView(
            model: bookmarkClipboardReviewToastModel,
            onHoverChanged: { [weak self] hovering in
                self?.handleBookmarkClipboardReviewHoverChange(hovering)
            },
            onSave: { [weak self] in
                guard let self else { return }
                guard let imageData = BookmarksClipboardMonitor.readImageFromClipboard() else {
                    self.showBookmarkCaptureToast(message: "Image no longer on clipboard", isSuccess: false)
                    return
                }
                // Suspend monitor so the same clipboard image isn't re-detected
                BookmarksClipboardMonitor.shared.suspendFor(seconds: 3)
                // Try to get context from the frontmost browser (page title + URL)
                let browserCapture = ActiveBrowserCaptureService.captureFromFrontmostBrowser()
                let title = browserCapture?.title ?? "Saved Image"
                let bookmark = BookmarksStorage.shared.addImageBookmark(title: title)
                if let urlString = browserCapture?.urlString {
                    BookmarksStorage.shared.updateURL(for: bookmark.id, urlString: urlString)
                }
                BookmarksStorage.shared.assignThumbnail(for: bookmark.id, imageData: imageData)
                self.showBookmarkCaptureToast(message: "Saved copied image", isSuccess: true)
            },
            onDiscard: { [weak self] in
                BookmarksClipboardMonitor.shared.suspendFor(seconds: 3)
                self?.dismissBookmarkCaptureToast()
            }
        )
        let hostingView = BookmarkCaptureToastHostingView(rootView: toastView)
        panel.contentView = hostingView
        showBookmarkToastPanel(panel, contentHeight: BookmarksToastDesign.reviewHeight)
        startBookmarkClipboardReviewTimer(resetToFull: true)
    }

    private func showBookmarkClipboardReviewToast(urlString: String) {
        CiderSoundEffect.clipboardReview.play()
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
            BookmarksClipboardMonitor.shared.suspendFor(seconds: 3)
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

        let shadowPanel = CiderShadowPanel()
        self.ciderShadowPanel = shadowPanel

        // Keep shadow panel frame in sync with main panel at every step —
        // including during user dragging, programmatic setFrame, and animations.
        panelFrameObservation = panel.observe(\.frame, options: [.new]) { [weak self] _, change in
            guard let frame = change.newValue else { return }
            DispatchQueue.main.async {
                self?.ciderShadowPanel?.updateFrame(for: frame)
            }
        }

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

        NotificationCenter.default.publisher(for: .snapCiderPanel)
            .sink { [weak self] notification in
                guard let raw = notification.userInfo?["target"] as? String,
                      let target = SnapTarget(rawValue: raw) else { return }
                self?.snapCiderPanel(to: target)
            }
            .store(in: &cancellables)

        // Note editor hotkey — show panel if hidden, CiderPanelView handles the rest
        NotificationCenter.default.publisher(for: .toggleNoteEditor)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.ciderPanel?.isVisible != true {
                    self.showCiderPanel()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .expandCiderPanelForSlideOut)
            .sink { [weak self] notification in
                let minWidth = notification.userInfo?["minimumWidth"] as? CGFloat
                    ?? BookmarksDesign.detailsSlideOutExpandedPanelMinWidth
                self?.expandCiderPanelForSlideOut(minimumWidth: minWidth)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .restoreCiderPanelAfterSlideOut)
            .sink { [weak self] _ in
                self?.restoreCiderPanelAfterSlideOut()
            }
            .store(in: &cancellables)

        // Bookmark capture hotkey
        NotificationCenter.default.publisher(for: .captureBookmark)
            .sink { [weak self] _ in
                self?.captureBookmarkFromHotkey()
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
        if panel.isVisible {
            persistCurrentCiderPanelFrameIfNeeded()
        }

        panel.setCollapsed(false, animated: false)

        let config = CiderConfig.load()
        if config.rememberPanelPosition, let savedFrame = ciderPanelPositionStore.frame() {
            panel.show(frame: savedFrame)
        } else {
            panel.showAtMouse()
        }

        // Show shadow behind the main panel.
        ciderShadowPanel?.updateFrame(for: panel.frame)
        ciderShadowPanel?.orderFront(nil)
        panel.orderFront(nil)
    }

    private func hideCiderPanel() {
        persistCurrentCiderPanelFrameIfNeeded()
        ciderShadowPanel?.orderOut(nil)
        ciderPanel?.orderOut(nil)
    }

    private func toggleCiderPanelCollapsed() {
        guard let panel = ciderPanel, panel.isVisible else { return }
        panel.toggleCollapsed()
        persistCurrentCiderPanelFrameIfNeeded()
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

    private func expandCiderPanelForSlideOut(minimumWidth: CGFloat) {
        guard let panel = ciderPanel, panel.isVisible else { return }
        guard panel.frame.width < minimumWidth else { return }

        // Save full frame so restore can return to exact position and size
        frameBeforeSlideOut = panel.frame

        let currentFrame = panel.frame
        let delta = minimumWidth - currentFrame.width
        let center = NSPoint(x: currentFrame.midX, y: currentFrame.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(center) })
            ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? currentFrame

        // Anchor the right edge when near screen edge; otherwise expand to the right
        var newOriginX = currentFrame.minX
        if currentFrame.maxX + delta > visibleFrame.maxX {
            newOriginX = max(visibleFrame.minX, currentFrame.maxX - minimumWidth)
        }

        let newFrame = NSRect(
            x: newOriginX,
            y: currentFrame.minY,
            width: minimumWidth,
            height: currentFrame.height
        )
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.setFrame(newFrame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.0, 0.0, 0.2, 1.0)
            panel.animator().setFrame(newFrame, display: true)
        }
    }

    private func restoreCiderPanelAfterSlideOut() {
        guard let panel = ciderPanel, let savedFrame = frameBeforeSlideOut else { return }
        frameBeforeSlideOut = nil

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.setFrame(savedFrame, display: true)
            persistCurrentCiderPanelFrameIfNeeded()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.0, 0.0, 0.2, 1.0)
            panel.animator().setFrame(savedFrame, display: true)
        }
        persistCurrentCiderPanelFrameIfNeeded()
    }

    private func snapCiderPanel(to target: SnapTarget) {
        guard let panel = ciderPanel, panel.isVisible else { return }

        let panelCenter = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(panelCenter) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let vf = screen.visibleFrame
        let gap: CGFloat = 15
        let minW = CiderPanelDesign.panelMinWidth

        let targetFrame: NSRect
        switch target {
        case .almostMaximized:
            targetFrame = NSRect(
                x: vf.minX + gap,
                y: vf.minY + gap,
                width: vf.width - gap * 2,
                height: vf.height - gap * 2
            )
        case .leftHalf:
            targetFrame = NSRect(
                x: vf.minX + gap,
                y: vf.minY + gap,
                width: vf.width / 2 - gap * 2,
                height: vf.height - gap * 2
            )
        case .rightHalf:
            targetFrame = NSRect(
                x: vf.midX + gap,
                y: vf.minY + gap,
                width: vf.width / 2 - gap * 2,
                height: vf.height - gap * 2
            )
        case .leftEdge:
            targetFrame = NSRect(
                x: vf.minX + gap,
                y: vf.minY + gap,
                width: minW,
                height: vf.height - gap * 2
            )
        case .rightEdge:
            targetFrame = NSRect(
                x: vf.maxX - gap - minW,
                y: vf.minY + gap,
                width: minW,
                height: vf.height - gap * 2
            )
        }

        panel.isMaximized = false
        panel.frameBeforeMaximize = nil
        panel.setCollapsed(false, animated: false)
        panel.setFrame(targetFrame, display: true)
        persistCurrentCiderPanelFrameIfNeeded()
    }

    private func persistCurrentCiderPanelFrameIfNeeded() {
        guard let panel = ciderPanel, panel.isVisible else { return }
        ciderPanelPositionStore.setFrame(panel.persistableFrame)
    }

    // MARK: - Screen Capture

    private func startScreenCaptureHotkeyDetection() {
        screenCaptureHotkeyDetector = ScreenCaptureHotkeyDetector()
        screenCaptureHotkeyDetector?.start()
    }

    private func observeScreenCaptureNotifications() {
        NotificationCenter.default.publisher(for: .requestScreenCapture)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.performScreenCapture()
                }
            }
            .store(in: &cancellables)
    }

    private func performScreenCapture() {
        // Hide the Cider panel so it doesn't appear in the captured region
        let wasVisible = ciderPanel?.isVisible ?? false
        screenCaptureWasVisible = wasVisible
        if wasVisible { hideCiderPanel() }

        Task { @MainActor in
            // Small delay to allow the panel to fully hide before capture
            try? await Task.sleep(for: .milliseconds(150))

            let image: NSImage?
            do {
                image = try await ScreenCaptureService.capture()
            } catch ScreenCaptureService.CaptureError.permissionDenied {
                screenCaptureWasVisible = false
                if wasVisible { self.showCiderPanel() }
                self.showBookmarkCaptureToast(
                    message: "Enable Screen Recording for Cider in System Settings",
                    isSuccess: false
                )
                return
            } catch {
                screenCaptureWasVisible = false
                if wasVisible { self.showCiderPanel() }
                return
            }

            guard let image else {
                // User cancelled — restore panel immediately
                screenCaptureWasVisible = false
                if wasVisible { self.showCiderPanel() }
                return
            }

            // Give the selection overlay a frame to fully dismiss before anything appears
            try? await Task.sleep(for: .milliseconds(100))

            // Run OCR and routing analysis — Cider stays hidden until toast action or expiry
            let ocrText = await ScreenCaptureService.extractText(from: image)
            let route = ScreenCaptureOCRRouter.detectRoute(in: ocrText ?? "")

            self.showScreenCaptureToast(route: route, image: image, ocrText: ocrText)
        }
    }

    private func showScreenCaptureToast(route: CaptureRoute, image: NSImage, ocrText: String?) {
        stopScreenCaptureToastTimer()
        screenCaptureToastIsHovering = false
        let config = CiderConfig.load()
        screenCaptureToastRemaining = TimeInterval(config.screenCaptureToastTimeout > 0
            ? config.screenCaptureToastTimeout
            : Int(ScreenCaptureToastDesign.autoHideDuration))
        screenCaptureToastModel.progress = 1

        if screenCaptureToastPanel == nil {
            screenCaptureToastPanel = ScreenCaptureToastPanel()
        }
        guard let panel = screenCaptureToastPanel else { return }

        let toastView = ScreenCaptureRoutingToastView(
            model: screenCaptureToastModel,
            route: route,
            captureImage: image,
            onHoverChanged: { [weak self] hovering in
                guard let self else { return }
                self.screenCaptureToastIsHovering = hovering
                if hovering {
                    self.stopScreenCaptureToastTimer()
                } else {
                    self.startScreenCaptureToastTimer()
                }
            },
            onCreateNote: { [weak self] in
                self?.dismissScreenCaptureToast()
                NotesStorage.shared.createFromCapture(
                    title: route.suggestedTitle.isEmpty ? "Screen Capture" : route.suggestedTitle,
                    ocrText: ocrText ?? "",
                    screenshot: image,
                    sourceURL: nil
                )
                self?.showCiderPanel()
            },
            onCreateDateCard: { [weak self] in
                self?.dismissScreenCaptureToast()
                self?.showCiderPanel()
                var info: [String: Any] = ["initialStep": "event"]
                if !route.suggestedTitle.isEmpty { info["suggestedTitle"] = route.suggestedTitle }
                if !route.detectedDates.isEmpty { info["detectedDates"] = route.detectedDates }
                if !route.suggestedLocation.isEmpty { info["suggestedLocation"] = route.suggestedLocation }
                if let ocrText, !ocrText.isEmpty { info["ocrText"] = ocrText }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .openNewItemPopover, object: nil, userInfo: info)
                }
            },
            onCreateContact: { [weak self] in
                self?.dismissScreenCaptureToast()
                self?.showCiderPanel()
                var info: [String: Any] = ["initialStep": "contact"]
                if !route.suggestedTitle.isEmpty { info["suggestedTitle"] = route.suggestedTitle }
                if !route.detectedEmails.isEmpty { info["detectedEmails"] = route.detectedEmails }
                if !route.detectedPhones.isEmpty { info["detectedPhones"] = route.detectedPhones }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .openNewItemPopover, object: nil, userInfo: info)
                }
            }
        )

        let hostingView = BookmarkCaptureToastHostingView(rootView: toastView)
        hostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: ScreenCaptureToastDesign.panelWidth,
                         height: ScreenCaptureToastDesign.panelHeight)
        )
        panel.contentView = hostingView
        panel.setContentSize(NSSize(width: ScreenCaptureToastDesign.panelWidth,
                                    height: ScreenCaptureToastDesign.panelHeight))

        let frame = screenCaptureToastFrame()
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()

        startScreenCaptureToastTimer()
    }

    private func screenCaptureToastFrame() -> NSRect {
        let w = ScreenCaptureToastDesign.panelWidth
        let h = ScreenCaptureToastDesign.panelHeight
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? .zero
        let x = visibleFrame.midX - w / 2
        let y = visibleFrame.maxY - h - Spacing.xxxl
        return NSRect(x: x, y: y, width: w, height: h)
    }

    private func startScreenCaptureToastTimer() {
        stopScreenCaptureToastTimer()
        screenCaptureToastLastTick = Date()

        let timer = Timer(timeInterval: ScreenCaptureToastDesign.progressTickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.screenCaptureToastTimerTick()
            }
        }
        screenCaptureToastTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopScreenCaptureToastTimer() {
        screenCaptureToastTimer?.invalidate()
        screenCaptureToastTimer = nil
        screenCaptureToastLastTick = nil
    }

    private func screenCaptureToastTimerTick() {
        guard !screenCaptureToastIsHovering else { return }
        guard let lastTick = screenCaptureToastLastTick else {
            screenCaptureToastLastTick = Date()
            return
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastTick)
        screenCaptureToastLastTick = now
        guard elapsed.isFinite, elapsed > 0 else { return }

        screenCaptureToastRemaining -= elapsed
        let config = CiderConfig.load()
        let duration = max(
            TimeInterval(config.screenCaptureToastTimeout > 0
                ? config.screenCaptureToastTimeout
                : Int(ScreenCaptureToastDesign.autoHideDuration)),
            0.01
        )

        if screenCaptureToastRemaining <= 0 {
            screenCaptureToastModel.progress = 0
            // Execute default action when timer expires
            executeScreenCaptureDefaultAction()
            return
        }

        screenCaptureToastModel.progress = max(0, min(1, screenCaptureToastRemaining / duration))
    }

    private func executeScreenCaptureDefaultAction() {
        let shouldRestorePanel = screenCaptureWasVisible
        dismissScreenCaptureToast()
        if shouldRestorePanel { showCiderPanel() }
    }

    private func dismissScreenCaptureToast() {
        stopScreenCaptureToastTimer()
        screenCaptureToastPanel?.orderOut(nil)
        screenCaptureWasVisible = false
    }

    // MARK: - Clipboard Viewer

    private func startClipboardHotkeyDetection() {
        let config = CiderConfig.load()
        guard config.enableClipboardHotkey else { return }
        clipboardHotkeyDetector = ClipboardHotkeyDetector()
        clipboardHotkeyDetector?.start()
    }

    private func configureClipboardHistory() {
        let config = CiderConfig.load()
        ClipboardHistoryService.shared.setEnabled(config.enableClipboardHistory)
    }

    private func configureClipboardPanel() {
        let panel = ClipboardPanel()
        self.clipboardPanel = panel

        let shadowPanel = CiderShadowPanel()
        self.clipboardShadowPanel = shadowPanel

        clipboardPanelFrameObservation = panel.observe(\.frame, options: [.new]) { [weak self] _, change in
            guard let frame = change.newValue else { return }
            DispatchQueue.main.async {
                self?.clipboardShadowPanel?.updateFrame(for: frame)
            }
        }

        let panelView = ClipboardPanelView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        let hostingView = CiderPanelHostingView(rootView: panelView)
        panel.contentView = hostingView
    }

    private func observeClipboardViewerNotifications() {
        NotificationCenter.default.publisher(for: .toggleClipboardViewer)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let panel = self.clipboardPanel else { return }
                if panel.isVisible {
                    self.hideClipboardPanel()
                } else {
                    self.showClipboardPanel()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .dismissClipboardPanel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.hideClipboardPanel()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .toggleClipboardPanelWidth)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.toggleClipboardPanelWidth()
            }
            .store(in: &cancellables)
    }

    private func showClipboardPanel() {
        guard let panel = clipboardPanel else { return }

        let config = CiderConfig.load()
        let isWide = UserDefaults.standard.bool(forKey: "cider.clipboardWideMode")
        let targetWidth = isWide ? ClipboardPanelDesign.wideWidth : ClipboardPanelDesign.narrowWidth

        // Lock width constraints for current mode
        panel.minSize = NSSize(width: targetWidth, height: ClipboardPanelDesign.minHeight)
        panel.maxSize = NSSize(width: targetWidth, height: .greatestFiniteMagnitude)

        let width = targetWidth
        let savedHeight = UserDefaults.standard.double(forKey: "cider.clipboardPanelHeight")
        let preferredHeight = savedHeight >= ClipboardPanelDesign.minHeight ? savedHeight : ClipboardPanelDesign.defaultHeight

        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
                ?? NSScreen.main else { return }

        // Clamp height to fit the target screen (with padding)
        let height = min(preferredHeight, screen.visibleFrame.height - Spacing.lg * 2)

        let frame: NSRect
        switch config.clipboardPanelPosition {
        case .followMouse:
            let x = max(screen.visibleFrame.minX, min(mouseLocation.x - width / 2, screen.visibleFrame.maxX - width))
            let y = max(screen.visibleFrame.minY, min(mouseLocation.y - height / 2, screen.visibleFrame.maxY - height))
            frame = NSRect(x: x, y: y, width: width, height: height)
        case .leftEdge:
            let x = screen.visibleFrame.minX + Spacing.md
            let y = screen.visibleFrame.midY - height / 2
            frame = NSRect(x: x, y: y, width: width, height: height)
        case .rightEdge:
            let x = screen.visibleFrame.maxX - width - Spacing.md
            let y = screen.visibleFrame.midY - height / 2
            frame = NSRect(x: x, y: y, width: width, height: height)
        }

        panel.setFrame(frame, display: true)
        // Order main panel first, then shadow behind it — avoids flash of shadow-only
        panel.makeKeyAndOrderFront(nil)
        clipboardShadowPanel?.updateFrame(for: panel.frame)
        clipboardShadowPanel?.order(.below, relativeTo: panel.windowNumber)
    }

    private func hideClipboardPanel() {
        if let panel = clipboardPanel, panel.frame.height >= ClipboardPanelDesign.minHeight {
            // Save the larger of current frame and previously saved height,
            // so clamping on a smaller screen doesn't shrink the preference.
            let previousSaved = UserDefaults.standard.double(forKey: "cider.clipboardPanelHeight")
            let toSave = max(panel.frame.height, previousSaved)
            UserDefaults.standard.set(toSave, forKey: "cider.clipboardPanelHeight")
        }
        // Order both out together to prevent ghost shadow
        clipboardPanel?.orderOut(nil)
        clipboardShadowPanel?.orderOut(nil)
    }

    private func toggleClipboardPanelWidth() {
        guard let panel = clipboardPanel else { return }

        let isWide = UserDefaults.standard.bool(forKey: "cider.clipboardWideMode")
        let targetWidth = isWide ? ClipboardPanelDesign.wideWidth : ClipboardPanelDesign.narrowWidth

        // Temporarily relax constraints so animation can interpolate
        let flexMin = min(ClipboardPanelDesign.narrowWidth, ClipboardPanelDesign.wideWidth)
        let flexMax = max(ClipboardPanelDesign.narrowWidth, ClipboardPanelDesign.wideWidth)
        panel.minSize = NSSize(width: flexMin, height: ClipboardPanelDesign.minHeight)
        panel.maxSize = NSSize(width: flexMax, height: .greatestFiniteMagnitude)

        // Calculate new frame
        var newFrame = panel.frame
        let isExpanding = targetWidth > panel.frame.width

        if let screen = panel.screen ?? NSScreen.main {
            if isExpanding {
                let widthDelta = targetWidth - panel.frame.width
                if panel.frame.maxX + widthDelta <= screen.visibleFrame.maxX {
                    // Room to expand right — keep left edge
                    newFrame.size.width = targetWidth
                } else {
                    // Expand left — keep right edge
                    newFrame.origin.x = max(screen.visibleFrame.minX, panel.frame.maxX - targetWidth)
                    newFrame.size.width = targetWidth
                }
            } else {
                // Collapsing — anchor to whichever screen edge is closer
                let distToRight = screen.visibleFrame.maxX - panel.frame.maxX
                let distToLeft = panel.frame.minX - screen.visibleFrame.minX

                if distToRight < distToLeft {
                    // Closer to right edge — keep right edge fixed
                    newFrame.origin.x = panel.frame.maxX - targetWidth
                }
                // Else: closer to left — keep left edge (origin stays)
                newFrame.size.width = targetWidth
            }
        } else {
            newFrame.size.width = targetWidth
        }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            panel.setFrame(newFrame, display: true)
            panel.minSize = NSSize(width: targetWidth, height: ClipboardPanelDesign.minHeight)
            panel.maxSize = NSSize(width: targetWidth, height: .greatestFiniteMagnitude)
        } else {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(newFrame, display: true)
            }, completionHandler: {
                DispatchQueue.main.async { [weak panel] in
                    guard let panel else { return }
                    panel.minSize = NSSize(width: targetWidth, height: ClipboardPanelDesign.minHeight)
                    panel.maxSize = NSSize(width: targetWidth, height: .greatestFiniteMagnitude)
                }
            })
        }
    }

    // MARK: - AI Chat Panel

    private func configureAIChatPanel() {
        let panel = AIChatPanel()
        self.aiChatPanel = panel

        let shadowPanel = CiderShadowPanel()
        self.aiChatShadowPanel = shadowPanel

        aiChatPanelFrameObservation = panel.observe(\.frame, options: [.new]) { [weak self] _, change in
            guard let frame = change.newValue else { return }
            DispatchQueue.main.async {
                self?.aiChatShadowPanel?.updateFrame(for: frame)
            }
        }

        // Host the pure SwiftUI chat view in the floating panel
        let chatView = AIChatView(viewModel: AIChatViewModel.shared, isDocked: false)
        let hostingView = NSHostingView(rootView: chatView)
        hostingView.sizingOptions = []  // Prevent hosting view from auto-resizing the window
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
    }

    private func observeAIChatNotifications() {
        NotificationCenter.default.publisher(for: .toggleAIChatPanel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let panel = self.aiChatPanel else { return }
                if panel.isVisible {
                    self.hideAIChatPanel()
                } else {
                    self.showAIChatPanel()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .dismissAIChatPanel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.hideAIChatPanel()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .dockAIChat)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.dockAIChat()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .undockAIChat)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.undockAIChat()
            }
            .store(in: &cancellables)
    }

    private func dockAIChat() {
        hideAIChatPanel()
        NotificationCenter.default.post(name: .selectAIChatTab, object: nil)
        var config = CiderConfig.load()
        config.aiChatDocked = true
        config.save()
    }

    private func undockAIChat() {
        showAIChatPanel()
        var config = CiderConfig.load()
        config.aiChatDocked = false
        config.save()
    }

    private func showAIChatPanel() {
        guard let panel = aiChatPanel else { return }

        let width = AIChatPanelDesign.defaultWidth
        let savedHeight = UserDefaults.standard.double(forKey: "cider.aiChatPanelHeight")
        let preferredHeight = savedHeight >= AIChatPanelDesign.minHeight ? savedHeight : AIChatPanelDesign.defaultHeight

        // Position next to CiderPanel if visible, otherwise at mouse
        let frame: NSRect
        if let ciderFrame = ciderPanel?.frame, ciderPanel?.isVisible == true {
            // Place to the right of the Cider panel
            let screen = NSScreen.screens.first(where: { $0.frame.contains(ciderFrame.origin) })
                ?? NSScreen.main ?? NSScreen.screens.first!
            let height = min(preferredHeight, screen.visibleFrame.height - Spacing.lg * 2)

            var x = ciderFrame.maxX + Spacing.sm
            // If it would go off-screen, place to the left instead
            if x + width > screen.visibleFrame.maxX {
                x = ciderFrame.minX - width - Spacing.sm
            }
            // Clamp to screen
            x = max(screen.visibleFrame.minX, min(x, screen.visibleFrame.maxX - width))

            // Align top edge with Cider panel
            let y = max(screen.visibleFrame.minY, ciderFrame.maxY - height)
            frame = NSRect(x: x, y: y, width: width, height: height)
        } else {
            let mouseLocation = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
                    ?? NSScreen.main else { return }
            let height = min(preferredHeight, screen.visibleFrame.height - Spacing.lg * 2)
            let x = max(screen.visibleFrame.minX, min(mouseLocation.x - width / 2, screen.visibleFrame.maxX - width))
            let y = max(screen.visibleFrame.minY, min(mouseLocation.y - height / 2, screen.visibleFrame.maxY - height))
            frame = NSRect(x: x, y: y, width: width, height: height)
        }

        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        aiChatShadowPanel?.updateFrame(for: panel.frame)
        aiChatShadowPanel?.order(.below, relativeTo: panel.windowNumber)
    }

    private func hideAIChatPanel() {
        if let panel = aiChatPanel, panel.frame.height >= AIChatPanelDesign.minHeight {
            let previousSaved = UserDefaults.standard.double(forKey: "cider.aiChatPanelHeight")
            let toSave = max(panel.frame.height, previousSaved)
            UserDefaults.standard.set(toSave, forKey: "cider.aiChatPanelHeight")
        }
        aiChatPanel?.orderOut(nil)
        aiChatShadowPanel?.orderOut(nil)
    }

    // MARK: - Debug Logging

    private let logger = Logger(subsystem: "com.cider.app", category: "AppDelegate")

    private func debugLog(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }
}
