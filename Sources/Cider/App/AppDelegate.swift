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
    var ciderMainWindow: CiderMainWindow?
    var ciderPanel: CiderPanel?
    var ciderShadowPanel: CiderShadowPanel?
    var panelFrameObservation: NSKeyValueObservation?
    let ciderPanelPositionStore = CiderPanelPositionStore.shared
    var frameBeforeSlideOut: NSRect?
    var floatingPanelManager: CiderFloatingPanelManager?

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
    var todoReminderCancellable: AnyCancellable?
    var telegramBridgeStarted = false

    // Settings
    var settingsWindow: SettingsWindow?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        AccessibilityHelpers.promptIfNeeded()
        VaultStructureMigration.migrateIfNeeded()
        VaultStructureMigration.migrateContentToInboxIfNeeded()
        VaultStructureMigration.migrateContactsToPerFileIfNeeded()
        VaultStructureMigration.migrateTodosToPerFileIfNeeded()
        VaultStructureMigration.migrateDateCardsToPerFileIfNeeded()
        StoragePaths.ensureVaultStructure()

        // Open SQLite database before any storage service is touched. All services
        // check CiderDatabase.shared.isOpen on first access and use it as the primary
        // store when available, falling back to JSON otherwise.
        do {
            let vaultRoot = StoragePaths.cachedVaultDirectoryURL
            let dbPath = vaultRoot.appendingPathComponent(".cider/cider.db")
            try FileManager.default.createDirectory(
                at: dbPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            DatabaseSafetyService.shared.capturePreOpenSnapshotIfNeeded(databaseURL: dbPath)
            try CiderDatabase.shared.open(at: dbPath)
            DatabaseSafetyService.shared.performStartupSafetyPass(database: CiderDatabase.shared)
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "Cider", category: "Startup")
                .error("Failed to open SQLite database: \(error.localizedDescription). Falling back to JSON.")
        }

        // Force-initialize foundational services in FK dependency order BEFORE any
        // ViewModel touches VaultBookmarkService / NotesStorage / etc. Item-type
        // services have `folder_id REFERENCES folders(id)` and `label_id REFERENCES
        // labels(id)`, so labels and folders must exist in SQLite before any item
        // migration runs. Without this, the first ViewModel's singleton access
        // lazy-inits VaultBookmarkService, which tries to migrate 142 bookmarks
        // with folder_id FKs to an empty folders table — every insert fails.
        _ = CardLabelStorage.shared   // no FK deps; referenced by item_labels
        _ = VaultFolderService.shared // no FK deps; referenced by items.folder_id

        configureSettings()
        configureNotes()
        configureBookmarks()
        configureCiderMainWindow()
        configureCiderPanel()
        configureStatusItem()
        observeSettingsNotifications()
        observeBookmarksNotifications()
        observeCiderMainWindowNotifications()
        observeCiderPanelNotifications()
        observeConfigChanges()
        observeWorkspaceApplicationActivation()
        startDoubleTapDetection()
        startNotesHotkeyDetection()
        startBookmarksHotkeyDetection()
        observeUndoNotifications()
        startScreenCaptureHotkeyDetection()
        observeScreenCaptureNotifications()
        startClipboardHotkeyDetection()
        configureClipboardHistory()
        configureClipboardPanel()
        observeClipboardViewerNotifications()
        configureAIAssistantPanel()
        observeAIAssistantNotifications()
        startAIAssistantHotkeyDetection()
        configureFloatingPanels()

        // Redirect Cmd+, to our real settings window instead of the blank SwiftUI Settings scene
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let appMenu = NSApp.mainMenu?.item(at: 0)?.submenu {
                for item in appMenu.items where item.keyEquivalent == "," {
                    item.target = self
                    item.action = #selector(self.openSettingsFromMenu)
                }
            }
            self.installCiderApplicationMenuItems()
        }

        transitionToCiderMainWindow()

        // Build vault index if empty (first run or rebuild needed)
        if VaultIndexService.shared.entries.isEmpty {
            VaultIndexService.shared.rebuildFromCurrentState()
        }

        VaultFileService.shared.ensureInboxDirectories()
        // Reconcile SQLite with filesystem (handles external changes while app was closed).
        // This triggers VaultFileService.scan() and rescans content services.
        VaultReconciler.reconcile()
        VaultFileService.shared.startWatching()

        // Sync Kanban board YAML files with tab entries and start file watching
        KanbanStorage.shared.syncTabsWithBoards()
        KanbanStorage.shared.startWatching()

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
                EmbeddingStore.shared.backfillMissing(bookmarks: VaultBookmarkService.shared.bookmarks)
            }

            // Reminder engine — reconciler handles local notifications + outbox
            let notificationService = DateCardNotificationService.shared
            self.dateCardNotificationService = notificationService
            if config.enableDateCardNotifications {
                Task {
                    let _ = await notificationService.requestPermission()
                }
            }
            // Start reconciler (handles notifications + agent outbox on launch, wake, day rollover, tz change)
            ReminderReconciler.shared.start()

            // Register agent tools and enable orchestrator for AI panel
            await AgentToolRegistration.registerAll()
            AIAssistantViewModel.shared.enableOrchestrator()
            await TelegramBridge.shared.startIfConfigured()
            self.telegramBridgeStarted = true
            ReminderReconciler.shared.reconcile()

            // Re-reconcile on vault changes (debounced)
            self.dateCardNotificationCancellable = DateCardStorage.shared.$dateCards
                .debounce(for: .seconds(2), scheduler: RunLoop.main)
                .sink { _ in
                    ReminderReconciler.shared.reconcile()
                }
            self.todoReminderCancellable = TodoCardStorage.shared.$todoCards
                .debounce(for: .seconds(2), scheduler: RunLoop.main)
                .sink { _ in
                    ReminderReconciler.shared.reconcile()
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
        floatingPanelManager?.closeDropZone()
        ciderMainWindow?.orderOut(nil)
        if telegramBridgeStarted {
            Task {
                await TelegramBridge.shared.stop()
            }
        }
        Task {
            await AgentOrchestrator.shared.stopRuntimeIfNeeded()
        }
    }

    func applicationWillResignActive(_ notification: Notification) {
        flushNotesDraftIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        transitionToCiderMainWindow()
        return true
    }

    // MARK: - Spotlight Deep Links

    func application(_ application: NSApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        SpotlightIndexer.handleUserActivity(userActivity)
    }

    // MARK: - File Open Handler

    func application(_ application: NSApplication, open urls: [URL]) {
        // Bring Cider panel to front for opened URLs
        if !urls.isEmpty {
            NotificationCenter.default.post(name: .toggleCiderPanel, object: nil)
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    private func installCiderApplicationMenuItems() {
        guard let mainMenu = NSApp.mainMenu else { return }

        let ciderMenu: NSMenu
        if let existing = mainMenu.item(withTitle: "Surfaces")?.submenu {
            ciderMenu = existing
            ciderMenu.removeAllItems()
        } else {
            ciderMenu = NSMenu(title: "Surfaces")
            let ciderMenuItem = NSMenuItem(title: "Surfaces", action: nil, keyEquivalent: "")
            ciderMenuItem.submenu = ciderMenu
            let insertIndex = max(1, mainMenu.items.count - 1)
            mainMenu.insertItem(ciderMenuItem, at: insertIndex)
        }

        ciderMenu.addItem(statusMenuItem(title: "Show Cider Window", action: #selector(openCiderMainWindowFromMenu), keyEquivalent: "1"))
        ciderMenu.addItem(statusMenuItem(title: "Show Quick Panel", action: #selector(showCiderPanelFromMenu), keyEquivalent: "2"))
        ciderMenu.addItem(NSMenuItem.separator())
        ciderMenu.addItem(statusMenuItem(title: "Show AI Panel", action: #selector(showAIAssistantPanelFromMenu), keyEquivalent: "3"))
        ciderMenu.addItem(statusMenuItem(title: "Show Clipboard Panel", action: #selector(showClipboardPanelFromMenu), keyEquivalent: "4"))
        ciderMenu.addItem(statusMenuItem(title: "Show Drop Zone", action: #selector(showDropZoneFromMenu), keyEquivalent: "5"))
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
        menu.addItem(statusMenuItem(title: "Show Cider Window", action: #selector(openCiderMainWindowFromMenu), keyEquivalent: ""))
        menu.addItem(statusMenuItem(title: "Show Quick Panel", action: #selector(showCiderPanelFromMenu), keyEquivalent: " "))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(statusMenuItem(title: "Show AI Panel", action: #selector(showAIAssistantPanelFromMenu), keyEquivalent: ""))
        menu.addItem(statusMenuItem(title: "Show Clipboard Panel", action: #selector(showClipboardPanelFromMenu), keyEquivalent: ""))
        menu.addItem(statusMenuItem(title: "Show Drop Zone", action: #selector(showDropZoneFromMenu), keyEquivalent: ""))
        #if DEBUG
        menu.addItem(NSMenuItem.separator())
        menu.addItem(debugMenuItem(title: "Simulate Update Available", action: #selector(simulateUpdateAvailableFromMenu)))
        menu.addItem(debugMenuItem(title: "Clear Simulated Update", action: #selector(clearSimulatedUpdateFromMenu)))
        #endif
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Cider", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    private func statusMenuItem(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc func toggleCiderPanelFromMenu() {
        toggleCiderPanel()
    }

    @objc func showCiderPanelFromMenu() {
        transitionToQuickPanel()
    }

    @objc func showAIAssistantPanelFromMenu() {
        showAIAssistantPanel()
    }

    @objc func showClipboardPanelFromMenu() {
        showClipboardPanel()
    }

    @objc func showDropZoneFromMenu() {
        NotificationCenter.default.post(name: .showCiderDropZone, object: nil)
    }

    func configureFloatingPanels() {
        floatingPanelManager = CiderFloatingPanelManager()
    }

    #if DEBUG
    private func debugMenuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc func simulateUpdateAvailableFromMenu() {
        SparkleUpdaterService.shared.simulateSidebarUpdateAvailableForDebug()
        showCiderPanel()
    }

    @objc func clearSimulatedUpdateFromMenu() {
        SparkleUpdaterService.shared.clearAvailableUpdate()
        showCiderPanel()
    }
    #endif

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
        SavedViewStorage.shared.reload()
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
        guard notesViewModel?.selectedNote != nil else { return }
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

    // MARK: - Debug Logging

    let logger = Logger(subsystem: "com.cider.app", category: "AppDelegate")

    func debugLog(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }
}
