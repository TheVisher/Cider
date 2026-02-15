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
    @Published var paletteSize: PaletteSize {
        didSet { saveConfig() }
    }

    // Advanced settings
    @Published var autoHideApps: Bool {
        didSet { saveConfig() }
    }

    // Activation settings
    @Published var activationMode: ActivationMode {
        didSet { saveConfig() }
    }

    // Window cycling settings
    @Published var enableOptionTabCycling: Bool {
        didSet { saveConfig() }
    }
    @Published var optionTabCycleAllScreens: Bool {
        didSet { saveConfig() }
    }

    // Palette behavior
    @Published var rememberPaletteState: Bool {
        didSet { saveConfig() }
    }

    // Tiling hotkeys
    @Published var enableTilingHotkeys: Bool {
        didSet { saveConfig() }
    }

    // Dynamic tiling
    @Published var enableDynamicTiling: Bool {
        didSet { saveConfig() }
    }

    // Notes
    @Published var enableNotesHotkey: Bool {
        didSet { saveConfig() }
    }
    @Published var notesDirectory: String {
        didSet { saveConfig() }
    }
    @Published var rememberNotesPanelPositionPerNote: Bool {
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
    @Published var bookmarksDirectory: String {
        didSet { saveConfig() }
    }
    @Published var rememberBookmarksPanelPosition: Bool {
        didSet { saveConfig() }
    }
    @Published var bookmarksDefaultViewMode: BookmarkDisplayMode {
        didSet { saveConfig() }
    }
    @Published var bookmarksCardSize: BookmarkCardSize {
        didSet { saveConfig() }
    }

    private var config: CiderConfig

    init() {
        // Load config
        self.config = CiderConfig.load()
        self.showMenuBarIcon = config.showMenuBarIcon
        self.textSize = config.textSize
        self.paletteSize = config.paletteSize
        self.autoHideApps = config.autoHideApps
        self.activationMode = config.activationMode
        self.enableOptionTabCycling = config.enableOptionTabCycling
        self.optionTabCycleAllScreens = config.optionTabCycleAllScreens
        self.rememberPaletteState = config.rememberPaletteState
        self.enableTilingHotkeys = config.enableTilingHotkeys
        self.enableDynamicTiling = config.enableDynamicTiling
        self.enableNotesHotkey = config.enableNotesHotkey
        self.notesDirectory = config.notesDirectory
        self.rememberNotesPanelPositionPerNote = config.rememberNotesPanelPositionPerNote
        self.notesEditorTextSize = config.notesEditorTextSize
        self.enableBookmarksHotkey = config.enableBookmarksHotkey
        self.enableBookmarksCaptureHotkey = config.enableBookmarksCaptureHotkey
        self.autoCaptureCopiedURLs = config.autoCaptureCopiedURLs
        self.confirmCopiedURLBeforeSave = config.confirmCopiedURLBeforeSave
        self.bookmarksDirectory = config.bookmarksDirectory
        self.rememberBookmarksPanelPosition = config.rememberBookmarksPanelPosition
        self.bookmarksDefaultViewMode = config.bookmarksDefaultViewMode
        self.bookmarksCardSize = config.bookmarksCardSize

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
        config.paletteSize = paletteSize
        config.autoHideApps = autoHideApps
        config.activationMode = activationMode
        config.enableOptionTabCycling = enableOptionTabCycling
        config.optionTabCycleAllScreens = optionTabCycleAllScreens
        config.rememberPaletteState = rememberPaletteState
        config.enableTilingHotkeys = enableTilingHotkeys
        config.enableDynamicTiling = enableDynamicTiling
        config.enableNotesHotkey = enableNotesHotkey
        config.notesDirectory = notesDirectory
        config.rememberNotesPanelPositionPerNote = rememberNotesPanelPositionPerNote
        config.notesEditorTextSize = notesEditorTextSize
        config.enableBookmarksHotkey = enableBookmarksHotkey
        config.enableBookmarksCaptureHotkey = enableBookmarksCaptureHotkey
        config.autoCaptureCopiedURLs = autoCaptureCopiedURLs
        config.confirmCopiedURLBeforeSave = confirmCopiedURLBeforeSave
        config.bookmarksDirectory = bookmarksDirectory
        config.rememberBookmarksPanelPosition = rememberBookmarksPanelPosition
        config.bookmarksDefaultViewMode = bookmarksDefaultViewMode
        config.bookmarksCardSize = bookmarksCardSize
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
