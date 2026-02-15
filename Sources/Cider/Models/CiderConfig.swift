import Foundation

enum ActivationMode: String, Codable, CaseIterable {
    case doubleTap
    case singleTap

    var displayName: String {
        switch self {
        case .doubleTap: return "Double tap"
        case .singleTap: return "Single tap"
        }
    }
}

enum TextSize: String, Codable, CaseIterable {
    case small
    case medium
    case large

    var displayName: String {
        rawValue.capitalized
    }

    var scale: CGFloat {
        switch self {
        case .small: return 0.85
        case .medium: return 1.0
        case .large: return 1.18
        }
    }

    var bodySize: CGFloat {
        switch self {
        case .small: return 12
        case .medium: return 14
        case .large: return 16
        }
    }

    var captionSize: CGFloat {
        switch self {
        case .small: return 10
        case .medium: return 12
        case .large: return 14
        }
    }

    var headlineSize: CGFloat {
        switch self {
        case .small: return 14
        case .medium: return 16
        case .large: return 18
        }
    }
}

enum NotesEditorTextSize: String, Codable, CaseIterable {
    case small
    case normal
    case large
    case extraLarge

    var displayName: String {
        switch self {
        case .small:
            "Small"
        case .normal:
            "Normal"
        case .large:
            "Large"
        case .extraLarge:
            "Extra Large"
        }
    }

    var cssFontSize: String {
        switch self {
        case .small:
            "12px"
        case .normal:
            "14px"
        case .large:
            "16px"
        case .extraLarge:
            "18px"
        }
    }
}


struct CiderConfig: Codable {
    var showMenuBarIcon: Bool
    var textSize: TextSize
    var activationMode: ActivationMode
    var notesDirectory: String  // Directory for notes .md files
    var enableNotesHotkey: Bool  // Enable Option+N to open notes
    var rememberNotesPanelPositionPerNote: Bool  // Reopen each note at its last panel position
    var notesEditorTextSize: NotesEditorTextSize  // Global display text size for note editor
    var enableBookmarksHotkey: Bool  // Enable Option+B to open bookmarks
    var enableBookmarksCaptureHotkey: Bool  // Enable Option+Shift+B to capture active browser tab
    var autoCaptureCopiedURLs: Bool  // Automatically save copied URLs as bookmarks
    var confirmCopiedURLBeforeSave: Bool  // Require explicit save/discard for copied URLs
    var bookmarksDirectory: String  // Directory for bookmark files
    var rememberBookmarksPanelPosition: Bool  // Reopen bookmarks panel where it was last shown
    var bookmarksDefaultViewMode: BookmarkDisplayMode  // Default bookmarks layout mode
    var bookmarksCardSize: BookmarkCardSize  // Default bookmark card size preset

    static let storageKey = "CiderConfig"

    static var `default`: CiderConfig {
        CiderConfig(
            showMenuBarIcon: true,
            textSize: .medium,
            activationMode: .doubleTap,
            notesDirectory: "~/Documents/Cider/Notes",
            enableNotesHotkey: true,
            rememberNotesPanelPositionPerNote: true,
            notesEditorTextSize: .normal,
            enableBookmarksHotkey: true,
            enableBookmarksCaptureHotkey: true,
            autoCaptureCopiedURLs: false,
            confirmCopiedURLBeforeSave: false,
            bookmarksDirectory: "~/Documents/Cider/Bookmarks",
            rememberBookmarksPanelPosition: false,
            bookmarksDefaultViewMode: .masonry,
            bookmarksCardSize: .comfortable
        )
    }

    static func load() -> CiderConfig {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return .default
        }

        // Try to decode, handling missing fields gracefully
        do {
            var config = try JSONDecoder().decode(CiderConfig.self, from: data)
            var didMigrate = false

            if config.notesDirectory == "~/Documents/Cider Notes" {
                config.notesDirectory = "~/Documents/Cider/Notes"
                didMigrate = true
            }

            let expandedLegacyNotes = NSString(string: "~/Documents/Cider Notes").expandingTildeInPath
            if config.notesDirectory == expandedLegacyNotes {
                config.notesDirectory = "~/Documents/Cider/Notes"
                didMigrate = true
            }

            if config.bookmarksDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                config.bookmarksDirectory = "~/Documents/Cider/Bookmarks"
                didMigrate = true
            }

            if didMigrate {
                config.save()
            }

            return config
        } catch {
            NSLog("[Cider] Config decode error: \(error). Resetting to defaults.")
            UserDefaults.standard.removeObject(forKey: storageKey)
            let defaults = CiderConfig.default
            defaults.save()
            return defaults
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: CiderConfig.storageKey)
            UserDefaults.standard.synchronize() // Force immediate write
            NSLog("[Cider] Config saved: textSize=\(textSize)")
        }
    }

    // Custom decoding to handle missing fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        textSize = try container.decodeIfPresent(TextSize.self, forKey: .textSize) ?? .medium
        activationMode = try container.decodeIfPresent(ActivationMode.self, forKey: .activationMode) ?? .doubleTap
        notesDirectory = try container.decodeIfPresent(String.self, forKey: .notesDirectory) ?? "~/Documents/Cider/Notes"
        enableNotesHotkey = try container.decodeIfPresent(Bool.self, forKey: .enableNotesHotkey) ?? true
        rememberNotesPanelPositionPerNote = try container.decodeIfPresent(
            Bool.self, forKey: .rememberNotesPanelPositionPerNote
        ) ?? true
        notesEditorTextSize = try container.decodeIfPresent(
            NotesEditorTextSize.self,
            forKey: .notesEditorTextSize
        ) ?? .normal
        enableBookmarksHotkey = try container.decodeIfPresent(Bool.self, forKey: .enableBookmarksHotkey) ?? true
        enableBookmarksCaptureHotkey = try container.decodeIfPresent(
            Bool.self,
            forKey: .enableBookmarksCaptureHotkey
        ) ?? true
        autoCaptureCopiedURLs = try container.decodeIfPresent(
            Bool.self,
            forKey: .autoCaptureCopiedURLs
        ) ?? false
        confirmCopiedURLBeforeSave = try container.decodeIfPresent(
            Bool.self,
            forKey: .confirmCopiedURLBeforeSave
        ) ?? false
        bookmarksDirectory = try container.decodeIfPresent(
            String.self,
            forKey: .bookmarksDirectory
        ) ?? "~/Documents/Cider/Bookmarks"
        rememberBookmarksPanelPosition = try container.decodeIfPresent(
            Bool.self,
            forKey: .rememberBookmarksPanelPosition
        ) ?? false
        bookmarksDefaultViewMode = try container.decodeIfPresent(
            BookmarkDisplayMode.self,
            forKey: .bookmarksDefaultViewMode
        ) ?? .masonry
        bookmarksCardSize = try container.decodeIfPresent(
            BookmarkCardSize.self,
            forKey: .bookmarksCardSize
        ) ?? .comfortable
    }

    init(
        showMenuBarIcon: Bool = true,
        textSize: TextSize = .medium,
        activationMode: ActivationMode = .doubleTap,
        notesDirectory: String = "~/Documents/Cider/Notes",
        enableNotesHotkey: Bool = true,
        rememberNotesPanelPositionPerNote: Bool = true,
        notesEditorTextSize: NotesEditorTextSize = .normal,
        enableBookmarksHotkey: Bool = true,
        enableBookmarksCaptureHotkey: Bool = true,
        autoCaptureCopiedURLs: Bool = false,
        confirmCopiedURLBeforeSave: Bool = false,
        bookmarksDirectory: String = "~/Documents/Cider/Bookmarks",
        rememberBookmarksPanelPosition: Bool = false,
        bookmarksDefaultViewMode: BookmarkDisplayMode = .masonry,
        bookmarksCardSize: BookmarkCardSize = .comfortable
    ) {
        self.showMenuBarIcon = showMenuBarIcon
        self.textSize = textSize
        self.activationMode = activationMode
        self.notesDirectory = notesDirectory
        self.enableNotesHotkey = enableNotesHotkey
        self.rememberNotesPanelPositionPerNote = rememberNotesPanelPositionPerNote
        self.notesEditorTextSize = notesEditorTextSize
        self.enableBookmarksHotkey = enableBookmarksHotkey
        self.enableBookmarksCaptureHotkey = enableBookmarksCaptureHotkey
        self.autoCaptureCopiedURLs = autoCaptureCopiedURLs
        self.confirmCopiedURLBeforeSave = confirmCopiedURLBeforeSave
        self.bookmarksDirectory = bookmarksDirectory
        self.rememberBookmarksPanelPosition = rememberBookmarksPanelPosition
        self.bookmarksDefaultViewMode = bookmarksDefaultViewMode
        self.bookmarksCardSize = bookmarksCardSize
    }
}
