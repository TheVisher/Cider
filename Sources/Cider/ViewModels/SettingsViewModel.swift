import SwiftUI
import ServiceManagement

@MainActor
final class SettingsViewModel: ObservableObject {
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
    @Published var notesDirectory: String {
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
    @Published var ciderDataDirectory: String {
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
        self.notesDirectory = config.notesDirectory
        self.notesEditorTextSize = config.notesEditorTextSize
        self.enableBookmarksHotkey = config.enableBookmarksHotkey
        self.enableBookmarksCaptureHotkey = config.enableBookmarksCaptureHotkey
        self.autoCaptureCopiedURLs = config.autoCaptureCopiedURLs
        self.confirmCopiedURLBeforeSave = config.confirmCopiedURLBeforeSave
        self.autoCaptureCopiedImages = config.autoCaptureCopiedImages
        self.ciderDataDirectory = config.ciderDataDirectory
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

    private func saveConfig() {
        config.showMenuBarIcon = showMenuBarIcon
        config.textSize = textSize
        config.activationMode = activationMode
        config.enableNotesHotkey = enableNotesHotkey
        config.notesDirectory = notesDirectory
        config.notesEditorTextSize = notesEditorTextSize
        config.enableBookmarksHotkey = enableBookmarksHotkey
        config.enableBookmarksCaptureHotkey = enableBookmarksCaptureHotkey
        config.autoCaptureCopiedURLs = autoCaptureCopiedURLs
        config.confirmCopiedURLBeforeSave = confirmCopiedURLBeforeSave
        config.autoCaptureCopiedImages = autoCaptureCopiedImages
        config.ciderDataDirectory = ciderDataDirectory
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
                print("Failed to update launch at login: \(error)")
            }
        }
    }

    func dismiss() {
        NotificationCenter.default.post(name: .dismissSettings, object: nil)
    }
}
