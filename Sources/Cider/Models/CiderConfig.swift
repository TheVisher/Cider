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
    // Legacy keys for migration from old config format
    private enum LegacyCodingKeys: String, CodingKey {
        case detailModalMode
    }

    // CodingKeys: keeps JSON key "bookmarksDirectory" for backward compat with existing UserDefaults data
    private enum CodingKeys: String, CodingKey {
        case showMenuBarIcon
        case textSize
        case activationMode
        case notesDirectory
        case enableNotesHotkey
        case notesEditorTextSize
        case enableBookmarksHotkey
        case enableBookmarksCaptureHotkey
        case autoCaptureCopiedURLs
        case confirmCopiedURLBeforeSave
        case autoCaptureCopiedImages
        case ciderDataDirectory = "bookmarksDirectory"
        case rememberPanelPosition
        case bookmarksDefaultViewMode
        case bookmarksCardSize
        case bookmarksCardSizeScale
        case notesDefaultViewMode
        case notesCardSizeScale
        case detailViewMode
        case detailSlideOutWidth
        case showContinueSection
        case continueSectionCollapsed
        case subFoldersCollapsed
        case homeDisplayMode
        case homeCardSizeScale
        case enableSavedViewTabs
        case enableLinkedSources
        case trashRetentionDays
        case captureToastPosition
        case undoToastPosition
        case homeSort
        case homeEntityFilter
        case enableSpotlightIndexing
        case enableSoundEffects
    }

    var showMenuBarIcon: Bool
    var textSize: TextSize
    var activationMode: ActivationMode
    var notesDirectory: String  // Directory for notes .md files
    var enableNotesHotkey: Bool  // Enable Option+N to create note
    var notesEditorTextSize: NotesEditorTextSize  // Global display text size for note editor
    var enableBookmarksHotkey: Bool  // Enable Option+B to open bookmarks
    var enableBookmarksCaptureHotkey: Bool  // Enable Option+Shift+B to capture active browser tab
    var autoCaptureCopiedURLs: Bool  // Automatically save copied URLs as bookmarks
    var confirmCopiedURLBeforeSave: Bool  // Require explicit save/discard for copied URLs
    var autoCaptureCopiedImages: Bool  // Detect copied images and offer to save as bookmark
    var ciderDataDirectory: String  // Directory for Cider data (bookmarks, contacts, stacks, labels, date cards, saved views, projects)
    var rememberPanelPosition: Bool  // Reopen the panel at its last position and size
    var bookmarksDefaultViewMode: BookmarkDisplayMode  // Default bookmarks layout mode
    var bookmarksCardSize: BookmarkCardSize  // Default bookmark card size preset
    var bookmarksCardSizeScale: Double?  // Continuous card size scale (0.0–3.0), overrides bookmarksCardSize
    var notesDefaultViewMode: NoteDisplayMode  // Default notes layout mode
    var notesCardSizeScale: Double?  // Continuous card size scale (0.0–3.0) for notes
    var detailViewMode: DetailViewMode  // Three-mode detail view: slide-out, full panel, or page
    var detailSlideOutWidth: CGFloat?  // Drag-resizable width of slide-out detail view (nil = 400)
    var showContinueSection: Bool  // Show the Continue section on the Home tab
    var continueSectionCollapsed: Bool  // Whether the Continue section is collapsed
    var subFoldersCollapsed: Bool  // Whether sub-folder cards are collapsed in folder view
    var homeDisplayMode: LibraryDisplayMode  // Home tab library feed layout mode
    var homeCardSizeScale: Double?  // Continuous card size scale (0.0–3.0) for home library feed
    var enableSavedViewTabs: Bool  // Feature flag for custom saved view tabs
    var enableLinkedSources: Bool  // Feature flag for external directory linking
    var trashRetentionDays: Int  // 0 = never auto-purge, default 30
    var captureToastPosition: ToastPosition  // Position for bookmark capture toast
    var undoToastPosition: ToastPosition  // Position for undo action toast
    var homeSort: LibrarySortMode  // Sort mode for the Home library feed
    var homeEntityFilter: Set<LibraryEntityType>  // Which entity types to show in Home feed
    var enableSpotlightIndexing: Bool  // Index Cider items in Core Spotlight for system-wide search
    var enableSoundEffects: Bool  // Play sounds for saves, captures, and deletes

    static let storageKey = "CiderConfig"

    static var `default`: CiderConfig {
        CiderConfig(
            showMenuBarIcon: true,
            textSize: .medium,
            activationMode: .doubleTap,
            notesDirectory: "~/Documents/Cider/Notes",
            enableNotesHotkey: true,
            notesEditorTextSize: .normal,
            enableBookmarksHotkey: true,
            enableBookmarksCaptureHotkey: true,
            autoCaptureCopiedURLs: false,
            confirmCopiedURLBeforeSave: false,
            autoCaptureCopiedImages: false,
            ciderDataDirectory: "~/Documents/Cider/Bookmarks",
            rememberPanelPosition: true,
            bookmarksDefaultViewMode: .masonry,
            bookmarksCardSize: .comfortable,
            notesDefaultViewMode: .list,
            detailViewMode: .slideOut,
            showContinueSection: true,
            continueSectionCollapsed: false,
            subFoldersCollapsed: false,
            homeDisplayMode: .list,
            enableSavedViewTabs: false,
            enableLinkedSources: false,
            trashRetentionDays: 30,
            captureToastPosition: .topCenterScreen,
            undoToastPosition: .bottomRightPanel,
            homeSort: .createdDescending,
            homeEntityFilter: Set(LibraryEntityType.allCases),
            enableSpotlightIndexing: true,
            enableSoundEffects: false
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

            if config.ciderDataDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                config.ciderDataDirectory = "~/Documents/Cider/Bookmarks"
                didMigrate = true
            }

            if didMigrate {
                config.save()
            }

            return config
        } catch {
            NSLog("[Cider] Config decode error: \(error). Using defaults (saved config preserved).")
            return .default
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: CiderConfig.storageKey)
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
        autoCaptureCopiedImages = try container.decodeIfPresent(
            Bool.self,
            forKey: .autoCaptureCopiedImages
        ) ?? false
        ciderDataDirectory = try container.decodeIfPresent(
            String.self,
            forKey: .ciderDataDirectory
        ) ?? "~/Documents/Cider/Bookmarks"
        rememberPanelPosition = try container.decodeIfPresent(
            Bool.self,
            forKey: .rememberPanelPosition
        ) ?? true
        bookmarksDefaultViewMode = try container.decodeIfPresent(
            BookmarkDisplayMode.self,
            forKey: .bookmarksDefaultViewMode
        ) ?? .masonry
        bookmarksCardSize = try container.decodeIfPresent(
            BookmarkCardSize.self,
            forKey: .bookmarksCardSize
        ) ?? .comfortable
        bookmarksCardSizeScale = try container.decodeIfPresent(
            Double.self,
            forKey: .bookmarksCardSizeScale
        )
        notesDefaultViewMode = try container.decodeIfPresent(
            NoteDisplayMode.self,
            forKey: .notesDefaultViewMode
        ) ?? .list
        notesCardSizeScale = try container.decodeIfPresent(
            Double.self,
            forKey: .notesCardSizeScale
        )
        // Migrate from legacy detailModalMode if detailViewMode not yet set
        if let decoded = try container.decodeIfPresent(DetailViewMode.self, forKey: .detailViewMode) {
            detailViewMode = decoded
        } else {
            // Read legacy key: "expand" → .fullPanel, anything else → .slideOut
            let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
            let legacyMode = try legacyContainer.decodeIfPresent(String.self, forKey: .detailModalMode)
            detailViewMode = legacyMode == "expand" ? .fullPanel : .slideOut
        }
        detailSlideOutWidth = try container.decodeIfPresent(CGFloat.self, forKey: .detailSlideOutWidth)
        showContinueSection = try container.decodeIfPresent(
            Bool.self,
            forKey: .showContinueSection
        ) ?? true
        continueSectionCollapsed = try container.decodeIfPresent(
            Bool.self,
            forKey: .continueSectionCollapsed
        ) ?? false
        subFoldersCollapsed = try container.decodeIfPresent(
            Bool.self,
            forKey: .subFoldersCollapsed
        ) ?? false
        homeDisplayMode = try container.decodeIfPresent(
            LibraryDisplayMode.self,
            forKey: .homeDisplayMode
        ) ?? .list
        homeCardSizeScale = try container.decodeIfPresent(
            Double.self,
            forKey: .homeCardSizeScale
        )
        enableSavedViewTabs = try container.decodeIfPresent(
            Bool.self,
            forKey: .enableSavedViewTabs
        ) ?? false
        enableLinkedSources = try container.decodeIfPresent(
            Bool.self,
            forKey: .enableLinkedSources
        ) ?? false
        trashRetentionDays = try container.decodeIfPresent(Int.self, forKey: .trashRetentionDays) ?? 30
        captureToastPosition = try container.decodeIfPresent(
            ToastPosition.self,
            forKey: .captureToastPosition
        ) ?? .topCenterScreen
        undoToastPosition = try container.decodeIfPresent(
            ToastPosition.self,
            forKey: .undoToastPosition
        ) ?? .bottomRightPanel
        homeSort = try container.decodeIfPresent(
            LibrarySortMode.self,
            forKey: .homeSort
        ) ?? .createdDescending
        homeEntityFilter = try container.decodeIfPresent(
            Set<LibraryEntityType>.self,
            forKey: .homeEntityFilter
        ) ?? Set(LibraryEntityType.allCases)
        enableSpotlightIndexing = try container.decodeIfPresent(
            Bool.self,
            forKey: .enableSpotlightIndexing
        ) ?? true
        enableSoundEffects = try container.decodeIfPresent(
            Bool.self,
            forKey: .enableSoundEffects
        ) ?? false
    }

    init(
        showMenuBarIcon: Bool = true,
        textSize: TextSize = .medium,
        activationMode: ActivationMode = .doubleTap,
        notesDirectory: String = "~/Documents/Cider/Notes",
        enableNotesHotkey: Bool = true,
        notesEditorTextSize: NotesEditorTextSize = .normal,
        enableBookmarksHotkey: Bool = true,
        enableBookmarksCaptureHotkey: Bool = true,
        autoCaptureCopiedURLs: Bool = false,
        confirmCopiedURLBeforeSave: Bool = false,
        autoCaptureCopiedImages: Bool = false,
        ciderDataDirectory: String = "~/Documents/Cider/Bookmarks",
        rememberPanelPosition: Bool = true,
        bookmarksDefaultViewMode: BookmarkDisplayMode = .masonry,
        bookmarksCardSize: BookmarkCardSize = .comfortable,
        bookmarksCardSizeScale: Double? = nil,
        notesDefaultViewMode: NoteDisplayMode = .list,
        notesCardSizeScale: Double? = nil,
        detailViewMode: DetailViewMode = .slideOut,
        detailSlideOutWidth: CGFloat? = nil,
        showContinueSection: Bool = true,
        continueSectionCollapsed: Bool = false,
        subFoldersCollapsed: Bool = false,
        homeDisplayMode: LibraryDisplayMode = .list,
        homeCardSizeScale: Double? = nil,
        enableSavedViewTabs: Bool = false,
        enableLinkedSources: Bool = false,
        trashRetentionDays: Int = 30,
        captureToastPosition: ToastPosition = .topCenterScreen,
        undoToastPosition: ToastPosition = .bottomRightPanel,
        homeSort: LibrarySortMode = .createdDescending,
        homeEntityFilter: Set<LibraryEntityType> = Set(LibraryEntityType.allCases),
        enableSpotlightIndexing: Bool = true,
        enableSoundEffects: Bool = false
    ) {
        self.showMenuBarIcon = showMenuBarIcon
        self.textSize = textSize
        self.activationMode = activationMode
        self.notesDirectory = notesDirectory
        self.enableNotesHotkey = enableNotesHotkey
        self.notesEditorTextSize = notesEditorTextSize
        self.enableBookmarksHotkey = enableBookmarksHotkey
        self.enableBookmarksCaptureHotkey = enableBookmarksCaptureHotkey
        self.autoCaptureCopiedURLs = autoCaptureCopiedURLs
        self.confirmCopiedURLBeforeSave = confirmCopiedURLBeforeSave
        self.autoCaptureCopiedImages = autoCaptureCopiedImages
        self.ciderDataDirectory = ciderDataDirectory
        self.rememberPanelPosition = rememberPanelPosition
        self.bookmarksDefaultViewMode = bookmarksDefaultViewMode
        self.bookmarksCardSize = bookmarksCardSize
        self.bookmarksCardSizeScale = bookmarksCardSizeScale
        self.notesDefaultViewMode = notesDefaultViewMode
        self.notesCardSizeScale = notesCardSizeScale
        self.detailViewMode = detailViewMode
        self.detailSlideOutWidth = detailSlideOutWidth
        self.showContinueSection = showContinueSection
        self.continueSectionCollapsed = continueSectionCollapsed
        self.subFoldersCollapsed = subFoldersCollapsed
        self.homeDisplayMode = homeDisplayMode
        self.homeCardSizeScale = homeCardSizeScale
        self.enableSavedViewTabs = enableSavedViewTabs
        self.enableLinkedSources = enableLinkedSources
        self.trashRetentionDays = trashRetentionDays
        self.captureToastPosition = captureToastPosition
        self.undoToastPosition = undoToastPosition
        self.homeSort = homeSort
        self.homeEntityFilter = homeEntityFilter
        self.enableSpotlightIndexing = enableSpotlightIndexing
        self.enableSoundEffects = enableSoundEffects
    }
}
