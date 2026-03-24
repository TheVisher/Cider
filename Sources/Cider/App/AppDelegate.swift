import AppKit
import SwiftUI
import Combine
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var cancellables = Set<AnyCancellable>()

    // Double-tap detection
    var doubleTapDetector: DoubleTapDetector?

    // Notes
    var notesViewModel: NotesViewModel?
    var notesHotkeyDetector: NotesHotkeyDetector?

    // Bookmarks
    var bookmarksViewModel: BookmarksViewModel?
    var bookmarksHotkeyDetector: BookmarksHotkeyDetector?
    var bookmarkCaptureToastPanel: BookmarkCaptureToastPanel?
    var bookmarkCaptureToastHideWorkItem: DispatchWorkItem?
    let bookmarkClipboardReviewToastModel = BookmarkClipboardReviewToastModel()
    var bookmarkClipboardReviewTimer: Timer?
    var bookmarkClipboardReviewIsHovering = false
    var bookmarkClipboardReviewRemaining: TimeInterval = BookmarksToastDesign.reviewAutoHideDuration
    var bookmarkClipboardReviewLastTick: Date?

    // Main Cider panel
    var ciderPanel: CiderPanel?
    var ciderShadowPanel: CiderShadowPanel?
    var panelFrameObservation: NSKeyValueObservation?
    let ciderPanelPositionStore = CiderPanelPositionStore.shared
    var frameBeforeSlideOut: NSRect?

    // Undo toast
    var undoToastPanel: BookmarkCaptureToastPanel?
    let undoToastModel = UndoToastModel()
    var undoToastTimer: Timer?
    var undoToastIsHovering = false
    var undoToastRemaining: TimeInterval = UndoToastDesign.autoHideDuration
    var undoToastLastTick: Date?

    // Screen capture
    var screenCaptureHotkeyDetector: ScreenCaptureHotkeyDetector?
    var screenCaptureToastPanel: ScreenCaptureToastPanel?
    let screenCaptureToastModel = ScreenCaptureToastModel()
    var screenCaptureToastTimer: Timer?
    var screenCaptureToastIsHovering = false
    var screenCaptureToastRemaining: TimeInterval = ScreenCaptureToastDesign.autoHideDuration
    var screenCaptureToastLastTick: Date?
    var screenCaptureWasVisible = false

    // Clipboard
    var clipboardHotkeyDetector: ClipboardHotkeyDetector?
    var clipboardPanel: ClipboardPanel?
    var clipboardShadowPanel: CiderShadowPanel?
    var clipboardPanelFrameObservation: NSKeyValueObservation?

    // AI Assistant
    var aiAssistantPanel: AIAssistantPanel?
    var aiAssistantShadowPanel: CiderShadowPanel?
    var aiAssistantPanelFrameObservation: NSKeyValueObservation?
    var aiAssistantHotkeyDetector: AIAssistantHotkeyDetector?

    // Services
    var servicesProvider: CiderServicesProvider?

    // Spotlight
    var spotlightIndexer: SpotlightIndexer?

    // Notifications
    var dateCardNotificationService: DateCardNotificationService?
    var dateCardNotificationCancellable: AnyCancellable?

    // Settings
    var settingsWindow: SettingsWindow?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        AccessibilityHelpers.promptIfNeeded()
        VaultStructureMigration.migrateIfNeeded()
        VaultStructureMigration.migrateContentToInboxIfNeeded()
        VaultStructureMigration.migrateContactsToPerFileIfNeeded()
        VaultStructureMigration.migrateTodosToPerFileIfNeeded()
        VaultStructureMigration.migrateDateCardsToPerFileIfNeeded()
        StoragePaths.ensureVaultStructure()

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
        configureAIAssistantPanel()
        observeAIAssistantNotifications()
        startAIAssistantHotkeyDetection()

        // Redirect Cmd+, to our real settings window instead of the blank SwiftUI Settings scene
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let appMenu = NSApp.mainMenu?.item(at: 0)?.submenu {
                for item in appMenu.items where item.keyEquivalent == "," {
                    item.target = self
                    item.action = #selector(self.openSettingsFromMenu)
                }
            }
        }

        // Build vault index if empty (first run or rebuild needed)
        if VaultIndexService.shared.entries.isEmpty {
            VaultIndexService.shared.rebuildFromCurrentState()
        }

        // Load sidecar metadata and scan vault files
        SidecarService.shared.loadAll()
        VaultFileService.shared.scan()

        // Sync Kanban board YAML files with tab entries and start file watching
        KanbanStorage.shared.syncTabsWithBoards()
        KanbanStorage.shared.startWatching()

        // Start Cider Web sync if configured
        SyncService.shared.startIfEnabled()

        // Start iMessage bridge if enabled
        if CiderConfig.load().iMessageBridgeEnabled {
            iMessageBridgeService.shared.start()
        }

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
                EmbeddingStore.shared.backfillMissing(bookmarks: VaultBookmarkService.shared.bookmarks)
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
        aiAssistantShadowPanel?.orderOut(nil)
        aiAssistantPanel?.orderOut(nil)
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

    @objc func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Status Item

    func configureStatusItem() {
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

    @objc func toggleCiderPanelFromMenu() {
        toggleCiderPanel()
    }

    // MARK: - Config Changes

    func observeConfigChanges() {
        NotificationCenter.default.publisher(for: .ciderConfigChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleConfigChanged()
            }
            .store(in: &cancellables)
    }

    func handleConfigChanged() {
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
        VaultBookmarkService.shared.updateDirectory(to: bookmarksDir)

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

    func observeWorkspaceApplicationActivation() {
        ActiveBrowserCaptureService.registerActivatedApplication(NSWorkspace.shared.frontmostApplication)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                ActiveBrowserCaptureService.registerActivatedApplication(app)
            }
            .store(in: &cancellables)
    }

    // MARK: - Double-Tap Detection

    func startDoubleTapDetection() {
        let config = CiderConfig.load()
        doubleTapDetector = DoubleTapDetector(
            key: .option,
            maxInterval: config.activationSpeed,
            mode: config.activationMode
        ) { [weak self] in
            Task { @MainActor in
                self?.toggleCiderPanel()
            }
        }
        doubleTapDetector?.start()
    }

    // MARK: - Settings

    func configureSettings() {
        let window = SettingsWindow()

        // Add shadow padding around the settings view
        let shadowPadding = SettingsDesign.shadowPadding
        let settingsView = SettingsView()
            .padding(.horizontal, shadowPadding)
            .padding(.top, Spacing.xl)
            .padding(.bottom, shadowPadding + Spacing.lg)

        let hostingView = SettingsHostingView(rootView: settingsView)
        window.contentView = hostingView

        // Size the window to fit content plus shadow padding
        let width = SettingsDesign.width + shadowPadding * 2
        let height = SettingsDesign.height + Spacing.xl + shadowPadding + Spacing.lg
        window.setContentSize(NSSize(width: width, height: height))

        self.settingsWindow = window
    }

    func observeSettingsNotifications() {
        NotificationCenter.default.publisher(for: .openCiderSettings)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.showSettings()
                if let category = notification.userInfo?["category"] as? String {
                    var info: [String: String] = ["category": category]
                    if let subcategory = notification.userInfo?["subcategory"] as? String {
                        info["subcategory"] = subcategory
                    }
                    NotificationCenter.default.post(
                        name: .settingsNavigate,
                        object: nil,
                        userInfo: info
                    )
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .dismissSettings)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.hideSettings()
            }
            .store(in: &cancellables)
    }

    @objc func openSettingsFromMenu() {
        showSettings()
    }

    func showSettings() {
        settingsWindow?.showCentered()
    }

    func hideSettings() {
        settingsWindow?.orderOut(nil)
    }

    // MARK: - Notes

    func configureNotes() {
        notesViewModel = NotesViewModel()
    }

    func startNotesHotkeyDetection() {
        let config = CiderConfig.load()
        guard config.enableNotesHotkey else { return }

        notesHotkeyDetector = NotesHotkeyDetector()
        notesHotkeyDetector?.start()
    }

    func updateGlobalHotkeyEnablement() {
        let config = CiderConfig.load()
        notesHotkeyDetector?.setEnabled(config.enableNotesHotkey)
        bookmarksHotkeyDetector?.setEnabled(config.enableBookmarksHotkey || config.enableBookmarksCaptureHotkey)
    }

    func flushNotesDraftIfNeeded() {
        guard notesViewModel?.selectedNote != nil || notesViewModel?.activeExternalFile != nil else { return }
        notesViewModel?.flushSave()
    }

    // MARK: - Bookmarks

    func configureBookmarks() {
        bookmarksViewModel = BookmarksViewModel()

        let config = CiderConfig.load()
        BookmarksClipboardMonitor.shared.setEnabled(config.autoCaptureCopiedURLs || config.autoCaptureCopiedImages)
    }

    func startBookmarksHotkeyDetection() {
        let config = CiderConfig.load()
        guard config.enableBookmarksHotkey || config.enableBookmarksCaptureHotkey else { return }

        bookmarksHotkeyDetector = BookmarksHotkeyDetector()
        bookmarksHotkeyDetector?.start()
    }

    func captureBookmarkFromHotkey() {
        guard let viewModel = bookmarksViewModel else { return }
        _ = viewModel.captureBookmarkFromActiveBrowserOrClipboard()
    }

    func observeBookmarksNotifications() {
        NotificationCenter.default.publisher(for: .showBookmarkCaptureToast)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                let message = notification.userInfo?["message"] as? String ?? "Bookmark updated"
                let isSuccess = notification.userInfo?["isSuccess"] as? Bool ?? true
                self?.showBookmarkCaptureToast(message: message, isSuccess: isSuccess)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .showBookmarkClipboardReviewToast)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let urlString = notification.userInfo?["urlString"] as? String else { return }
                self?.showBookmarkClipboardReviewToast(urlString: urlString)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .showImageClipboardReviewToast)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.showImageClipboardReviewToast()
            }
            .store(in: &cancellables)
    }

    // MARK: - External Sources

    func observeSourcesNotifications() {
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

    // MARK: - Debug Logging

    let logger = Logger(subsystem: "com.cider.app", category: "AppDelegate")

    func debugLog(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }
}
