import SwiftUI
import ServiceManagement
import os

@MainActor
final class SettingsViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.cider.app", category: "SettingsViewModel")

    // General settings
    @Published var launchAtLogin: Bool {
        didSet { updateLaunchAtLogin() }
    }
    @Published var hotkeyEnabled: Bool = true
    @Published var hotkeyDoubleTapInterval: Double = 0.3

    // Appearance settings
    @Published var showMenuBarIcon: Bool {
        didSet { saveConfig() }
    }
    @Published var textSize: TextSize {
        didSet { saveConfig() }
    }

    // Activation settings
    @Published var activationMode: ActivationMode {
        didSet { saveConfig() }
    }

    // Notes
    @Published var enableNotesHotkey: Bool {
        didSet { saveConfig() }
    }
    @Published var notesEditorTextSize: NotesEditorTextSize {
        didSet { saveConfig() }
    }

    // Bookmarks
    @Published var enableBookmarksHotkey: Bool {
        didSet { saveConfig() }
    }
    @Published var enableBookmarksCaptureHotkey: Bool {
        didSet { saveConfig() }
    }
    @Published var autoCaptureCopiedURLs: Bool {
        didSet { saveConfig() }
    }
    @Published var confirmCopiedURLBeforeSave: Bool {
        didSet { saveConfig() }
    }
    @Published var autoCaptureCopiedImages: Bool {
        didSet { saveConfig() }
    }

    // Vault
    @Published var vaultDirectory: String {
        didSet { saveConfig() }
    }
    @Published var directoryOverrides: [String: String] {
        didSet { saveConfig() }
    }

    @Published var rememberPanelPosition: Bool {
        didSet { saveConfig() }
    }
    @Published var enableSpotlightIndexing: Bool {
        didSet { saveConfig() }
    }
    @Published var bookmarksDefaultViewMode: BookmarkDisplayMode {
        didSet { saveConfig() }
    }
    @Published var bookmarksCardSize: BookmarkCardSize {
        didSet { saveConfig() }
    }
    @Published var detailViewMode: DetailViewMode {
        didSet { saveConfig() }
    }
    @Published var enableLinkedSources: Bool {
        didSet { saveConfig() }
    }
    @Published var trashRetentionDays: Int {
        didSet { saveConfig() }
    }
    @Published var captureToastPosition: ToastPosition {
        didSet { saveConfig() }
    }
    @Published var undoToastPosition: ToastPosition {
        didSet { saveConfig() }
    }
    @Published var enableSoundEffects: Bool {
        didSet { saveConfig() }
    }

    // Date Card Notifications
    @Published var enableDateCardNotifications: Bool {
        didSet { saveConfig() }
    }
    @Published var dateCardDefaultNotificationMinutes: Int {
        didSet { saveConfig() }
    }

    // Intelligence
    @Published var enableAutoTagging: Bool {
        didSet { saveConfig() }
    }
    @Published var enableEmbeddings: Bool {
        didSet { saveConfig() }
    }
    @Published var enablePageSummaries: Bool {
        didSet { saveConfig() }
    }
    @Published var enableOCRIndexing: Bool {
        didSet { saveConfig() }
    }
    @Published var enableColorExtraction: Bool {
        didSet { saveConfig() }
    }

    private var config: CiderConfig

    init() {
        // Load config
        self.config = CiderConfig.load()
        self.showMenuBarIcon = config.showMenuBarIcon
        self.textSize = config.textSize
        self.activationMode = config.activationMode
        self.enableNotesHotkey = config.enableNotesHotkey
        self.notesEditorTextSize = config.notesEditorTextSize
        self.enableBookmarksHotkey = config.enableBookmarksHotkey
        self.enableBookmarksCaptureHotkey = config.enableBookmarksCaptureHotkey
        self.autoCaptureCopiedURLs = config.autoCaptureCopiedURLs
        self.confirmCopiedURLBeforeSave = config.confirmCopiedURLBeforeSave
        self.autoCaptureCopiedImages = config.autoCaptureCopiedImages
        self.vaultDirectory = config.vaultDirectory
        self.directoryOverrides = config.directoryOverrides
        self.rememberPanelPosition = config.rememberPanelPosition
        self.enableSpotlightIndexing = config.enableSpotlightIndexing
        self.bookmarksDefaultViewMode = config.bookmarksDefaultViewMode
        self.bookmarksCardSize = config.bookmarksCardSize
        self.detailViewMode = config.detailViewMode
        self.enableLinkedSources = config.enableLinkedSources
        self.trashRetentionDays = config.trashRetentionDays
        self.captureToastPosition = config.captureToastPosition
        self.undoToastPosition = config.undoToastPosition
        self.enableSoundEffects = config.enableSoundEffects
        self.enableDateCardNotifications = config.enableDateCardNotifications
        self.dateCardDefaultNotificationMinutes = config.dateCardDefaultNotificationMinutes
        self.enableAutoTagging = config.enableAutoTagging
        self.enableEmbeddings = config.enableEmbeddings
        self.enablePageSummaries = config.enablePageSummaries
        self.enableOCRIndexing = config.enableOCRIndexing
        self.enableColorExtraction = config.enableColorExtraction

        // Check current launch at login status
        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            launchAtLogin = false
        }
    }

    /// Returns the resolved path for a storage type (override or vault default).
    func resolvedPath(for type: StorageType) -> String {
        if let override = directoryOverrides[type.rawValue], !override.isEmpty {
            return override
        }
        let expanded = NSString(string: vaultDirectory).expandingTildeInPath
        return URL(fileURLWithPath: expanded).appendingPathComponent(type.rawValue).path
    }

    /// Returns the display-friendly path with ~ for home directory.
    func displayPath(for type: StorageType) -> String {
        let path = resolvedPath(for: type)
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    /// Whether a storage type has an active override.
    func hasOverride(for type: StorageType) -> Bool {
        if let override = directoryOverrides[type.rawValue], !override.isEmpty {
            return true
        }
        return false
    }

    func setDirectoryOverride(for type: StorageType, path: String) {
        directoryOverrides[type.rawValue] = path
    }

    func clearDirectoryOverride(for type: StorageType) {
        directoryOverrides.removeValue(forKey: type.rawValue)
    }

    private func saveConfig() {
        config.showMenuBarIcon = showMenuBarIcon
        config.textSize = textSize
        config.activationMode = activationMode
        config.enableNotesHotkey = enableNotesHotkey
        config.notesEditorTextSize = notesEditorTextSize
        config.enableBookmarksHotkey = enableBookmarksHotkey
        config.enableBookmarksCaptureHotkey = enableBookmarksCaptureHotkey
        config.autoCaptureCopiedURLs = autoCaptureCopiedURLs
        config.confirmCopiedURLBeforeSave = confirmCopiedURLBeforeSave
        config.autoCaptureCopiedImages = autoCaptureCopiedImages
        config.vaultDirectory = vaultDirectory
        config.directoryOverrides = directoryOverrides
        config.rememberPanelPosition = rememberPanelPosition
        config.enableSpotlightIndexing = enableSpotlightIndexing
        config.bookmarksDefaultViewMode = bookmarksDefaultViewMode
        config.bookmarksCardSize = bookmarksCardSize
        config.bookmarksCardSizeScale = bookmarksCardSize.sliderValue
        config.detailViewMode = detailViewMode
        config.enableLinkedSources = enableLinkedSources
        config.trashRetentionDays = trashRetentionDays
        config.captureToastPosition = captureToastPosition
        config.undoToastPosition = undoToastPosition
        config.enableSoundEffects = enableSoundEffects
        config.enableDateCardNotifications = enableDateCardNotifications
        config.dateCardDefaultNotificationMinutes = dateCardDefaultNotificationMinutes
        config.enableAutoTagging = enableAutoTagging
        config.enableEmbeddings = enableEmbeddings
        config.enablePageSummaries = enablePageSummaries
        config.enableOCRIndexing = enableOCRIndexing
        config.enableColorExtraction = enableColorExtraction
        config.save()

        // Post notification so AppDelegate can respond
        NotificationCenter.default.post(name: .ciderConfigChanged, object: nil)
    }

    private func updateLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                logger.error("Failed to update launch at login: \(error, privacy: .public)")
            }
        }
    }

    func dismiss() {
        NotificationCenter.default.post(name: .dismissSettings, object: nil)
    }
}
