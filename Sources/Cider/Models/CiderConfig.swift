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


enum ClipboardPanelPosition: String, Codable, CaseIterable {
    case followMouse
    case leftEdge
    case rightEdge

    var displayName: String {
        switch self {
        case .followMouse: return "Follow mouse"
        case .leftEdge: return "Left edge"
        case .rightEdge: return "Right edge"
        }
    }
}

struct CiderConfig: Codable {
    // Legacy keys for migration from old config format
    private enum LegacyCodingKeys: String, CodingKey {
        case detailModalMode
    }

    // Legacy keys for reading old config format (pre-vault)
    private enum LegacyDirectoryKeys: String, CodingKey {
        case ciderDataDirectory = "bookmarksDirectory"
        case notesDirectory
    }

    private enum CodingKeys: String, CodingKey {
        case showMenuBarIcon
        case textSize
        case activationMode
        case activationSpeed
        case enableNotesHotkey
        case notesEditorTextSize
        case enableBookmarksHotkey
        case enableBookmarksCaptureHotkey
        case autoCaptureCopiedURLs
        case confirmCopiedURLBeforeSave
        case autoCaptureCopiedImages
        case vaultDirectory
        case directoryOverrides
        case rememberPanelPosition
        case bookmarksDefaultViewMode
        case bookmarksCardSize
        case bookmarksCardSizeScale
        case notesDefaultViewMode
        case notesCardSizeScale
        case detailViewMode
        case bookmarkDetailViewMode
        case noteDetailViewMode
        case detailSlideOutWidth
        case showContinueSection
        case continueSectionCollapsed
        case subFoldersCollapsed
        case homeDisplayMode
        case homeCardSizeScale
        case tagsCollapsed
        case enableLinkedSources
        case trashRetentionDays
        case captureToastPosition
        case undoToastPosition
        case homeSort
        case homeEntityFilter
        case enableSpotlightIndexing
        case enableSoundEffects
        case enableAutoTagging
        case enableEmbeddings
        case enablePageSummaries
        case enableOCRIndexing
        case enableColorExtraction
        case screenCaptureToastTimeout
        case screenCaptureDefaultAction
        case dateCardSurfacingDays
        case enableDateCardNotifications
        case dateCardDefaultNotificationMinutes
        case hasCompletedOnboarding
        case showDragModeHints
        case enableClipboardHistory
        case enableClipboardHotkey
        case clipboardRetentionDays
        case clipboardImageRetentionDays
        case clipboardMaxImageStorageMB
        case clipboardPanelPosition
        case syncEnabled
        case syncURL
        case syncToken
        case lastSyncTimestamp
        case lastSuccessfulPushAt
        case aiChatDocked
        case aiChatVisible
        case didMigrateBookmarkFiles
        case didMigrateVaultToCiderDir
        case didMigrateContentToInbox
        case didMigrateContactsToPerFile
        case didMigrateTodosToPerFile
        case didMigrateDateCardsToPerFile
        case lastReconciliationAt
        case openOnMouseScreen
        case sessionRestoreBrowserBundleID
        case tableColumnConfig
    }

    var showMenuBarIcon: Bool
    var textSize: TextSize
    var activationMode: ActivationMode
    var activationSpeed: Double  // Double-tap: max interval between taps. Single-tap: max hold duration before ignored. Default 0.3s.
    var enableNotesHotkey: Bool  // Enable Option+N to create note
    var notesEditorTextSize: NotesEditorTextSize  // Global display text size for note editor
    var enableBookmarksHotkey: Bool  // Enable Option+B to open bookmarks
    var enableBookmarksCaptureHotkey: Bool  // Enable Option+Shift+B to capture active browser tab
    var autoCaptureCopiedURLs: Bool  // Automatically save copied URLs as bookmarks
    var confirmCopiedURLBeforeSave: Bool  // Require explicit save/discard for copied URLs
    var autoCaptureCopiedImages: Bool  // Detect copied images and offer to save as bookmark
    var vaultDirectory: String  // Root directory for all Cider data (~/CiderVault)
    var directoryOverrides: [String: String]  // Per-StorageType overrides, keyed by StorageType.rawValue
    var rememberPanelPosition: Bool  // Reopen the panel at its last position and size
    var bookmarksDefaultViewMode: BookmarkDisplayMode  // Default bookmarks layout mode
    var bookmarksCardSize: BookmarkCardSize  // Default bookmark card size preset
    var bookmarksCardSizeScale: Double?  // Continuous card size scale (0.0–3.0), overrides bookmarksCardSize
    var notesDefaultViewMode: NoteDisplayMode  // Default notes layout mode
    var notesCardSizeScale: Double?  // Continuous card size scale (0.0–3.0) for notes
    var detailViewMode: DetailViewMode  // Legacy fallback for detail view mode
    var bookmarkDetailViewMode: DetailViewMode?  // Per-type detail view mode for bookmarks
    var noteDetailViewMode: DetailViewMode?  // Per-type detail view mode for notes
    var detailSlideOutWidth: CGFloat?  // Drag-resizable width of slide-out detail view (nil = 400)
    var showContinueSection: Bool  // Show the Continue section on the Home tab
    var continueSectionCollapsed: Bool  // Whether the Continue section is collapsed
    var subFoldersCollapsed: Bool  // Whether sub-folder cards are collapsed in folder view
    var homeDisplayMode: LibraryDisplayMode  // Home tab library feed layout mode
    var homeCardSizeScale: Double?  // Continuous card size scale (0.0–3.0) for home library feed
    var tagsCollapsed: Bool  // Whether the sidebar tags section is collapsed
    var enableLinkedSources: Bool  // Feature flag for external directory linking
    var trashRetentionDays: Int  // 0 = never auto-purge, default 30
    var captureToastPosition: ToastPosition  // Position for bookmark capture toast
    var undoToastPosition: ToastPosition  // Position for undo action toast
    var homeSort: LibrarySortMode  // Sort mode for the Home library feed
    var homeEntityFilter: Set<LibraryEntityType>  // Which entity types to show in Home feed
    var enableSpotlightIndexing: Bool  // Index Cider items in Core Spotlight for system-wide search
    var enableSoundEffects: Bool  // Play sounds for saves, captures, and deletes
    var enableAutoTagging: Bool  // Auto-suggest tags using NaturalLanguage NER + keyword extraction
    var enableEmbeddings: Bool  // Compute NLEmbedding vectors to power "find similar"
    var enablePageSummaries: Bool  // Generate 2-sentence summaries via Foundation Models (Apple Intelligence)
    var enableOCRIndexing: Bool  // OCR thumbnail images via Vision so their text is searchable
    var enableColorExtraction: Bool  // Extract dominant colors from thumbnails for display
    var screenCaptureToastTimeout: Int  // Seconds before routing toast auto-dismisses (0 = skip toast)
    var screenCaptureDefaultAction: String  // Default action: "note", "dateCard", "contact"
    var dateCardSurfacingDays: Int  // Days ahead to surface approaching date cards (0 = disabled)
    var enableDateCardNotifications: Bool  // Send system notifications for approaching date cards
    var dateCardDefaultNotificationMinutes: Int  // Default notification lead time in minutes (15, 30, 60, 120, 1440)
    var hasCompletedOnboarding: Bool  // Whether the user has dismissed the first-run onboarding tab
    var showDragModeHints: Bool  // Show overlay hints when dragging bookmarks that have both image+URL
    var enableClipboardHistory: Bool  // Record clipboard history for the clipboard viewer
    var enableClipboardHotkey: Bool  // Enable Option+V to toggle clipboard viewer
    var clipboardRetentionDays: Int  // 0 = infinite, days to keep text clipboard items
    var clipboardImageRetentionDays: Int  // Days to keep image clipboard items (default 7)
    var clipboardMaxImageStorageMB: Int  // Max total image storage in MB (default 500)
    var clipboardPanelPosition: ClipboardPanelPosition  // Where standalone clipboard panel appears

    // Cider Web sync
    var syncEnabled: Bool  // Whether sync with Cider Web is active
    var syncURL: String  // Convex deployment HTTP URL (e.g. https://foo-123.convex.site)
    var syncToken: String  // Bearer token for authenticating with Cider Web
    var lastSyncTimestamp: Double  // Server timestamp of last successful pull (ms since epoch)
    var lastSuccessfulPushAt: Double  // Local timestamp of last successful push (seconds since epoch)
    var aiChatDocked: Bool  // Whether AI Chat is docked in the tab bar (false = floating panel)
    var aiChatVisible: Bool  // Whether AI Chat is currently open (tab or panel)
    var didMigrateBookmarkFiles: Bool  // Whether one-time .webloc file migration has run
    var didMigrateVaultToCiderDir: Bool  // Whether one-time vault → .cider/ migration has run
    var didMigrateContentToInbox: Bool  // Whether one-time .cider/ → Inbox/ content migration has run
    var didMigrateContactsToPerFile: Bool  // Whether one-time contacts JSON → .vcf migration has run
    var didMigrateTodosToPerFile: Bool  // Whether one-time todos JSON → .ics migration has run
    var didMigrateDateCardsToPerFile: Bool  // Whether one-time date cards JSON → .ics migration has run
    var lastReconciliationAt: Double  // Epoch seconds of last full reconciliation check
    var openOnMouseScreen: Bool  // Whether to open the panel on the screen where the mouse cursor is
    var sessionRestoreBrowserBundleID: String?  // Bundle ID of preferred browser for restoring session tabs (nil = system default)
    var tableColumnConfig: TableColumnConfig  // Persisted table list view column widths, order, visibility

    static let storageKey = "CiderConfig"

    static var `default`: CiderConfig {
        CiderConfig(
            showMenuBarIcon: true,
            textSize: .medium,
            activationMode: .doubleTap,
            activationSpeed: 0.3,
            enableNotesHotkey: true,
            notesEditorTextSize: .normal,
            enableBookmarksHotkey: true,
            enableBookmarksCaptureHotkey: true,
            autoCaptureCopiedURLs: false,
            confirmCopiedURLBeforeSave: false,
            autoCaptureCopiedImages: false,
            vaultDirectory: "~/CiderVault",
            directoryOverrides: [:],
            rememberPanelPosition: true,
            bookmarksDefaultViewMode: .masonry,
            bookmarksCardSize: .comfortable,
            notesDefaultViewMode: .list,
            detailViewMode: .slideOut,
            bookmarkDetailViewMode: nil,
            noteDetailViewMode: nil,
            showContinueSection: true,
            continueSectionCollapsed: false,
            subFoldersCollapsed: false,
            homeDisplayMode: .list,
            tagsCollapsed: false,
            enableLinkedSources: false,
            trashRetentionDays: 30,
            captureToastPosition: .topCenterScreen,
            undoToastPosition: .bottomRightPanel,
            homeSort: .createdDescending,
            homeEntityFilter: Set(LibraryEntityType.allCases),
            enableSpotlightIndexing: false,
            enableSoundEffects: false,
            enableAutoTagging: true,
            enableEmbeddings: true,
            enablePageSummaries: true,
            enableOCRIndexing: false,
            enableColorExtraction: true,
            screenCaptureToastTimeout: 8,
            screenCaptureDefaultAction: "note",
            dateCardSurfacingDays: 7,
            enableDateCardNotifications: false,
            dateCardDefaultNotificationMinutes: 30,
            hasCompletedOnboarding: false,
            showDragModeHints: true,
            enableClipboardHistory: true,
            enableClipboardHotkey: true,
            clipboardRetentionDays: 30,
            clipboardImageRetentionDays: 7,
            clipboardMaxImageStorageMB: 500,
            clipboardPanelPosition: .followMouse,
            syncEnabled: false,
            syncURL: "",
            syncToken: "",
            lastSyncTimestamp: 0,
            lastSuccessfulPushAt: 0,
            aiChatDocked: false,
            aiChatVisible: false,
            didMigrateBookmarkFiles: false,
            didMigrateVaultToCiderDir: false,
            didMigrateContentToInbox: false,
            didMigrateContactsToPerFile: false,
            didMigrateTodosToPerFile: false,
            didMigrateDateCardsToPerFile: false,
            lastReconciliationAt: 0,
            openOnMouseScreen: false,
            sessionRestoreBrowserBundleID: nil,
            tableColumnConfig: .default
        )
    }

    static func load() -> CiderConfig {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return .default
        }

        do {
            let config = try JSONDecoder().decode(CiderConfig.self, from: data)
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

    // Custom decoding to handle missing fields + backward compat from pre-vault config
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        textSize = try container.decodeIfPresent(TextSize.self, forKey: .textSize) ?? .medium
        activationMode = try container.decodeIfPresent(ActivationMode.self, forKey: .activationMode) ?? .doubleTap
        activationSpeed = try container.decodeIfPresent(Double.self, forKey: .activationSpeed) ?? 0.3
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

        // Vault directory + overrides (with backward compat from pre-vault config)
        vaultDirectory = try container.decodeIfPresent(
            String.self,
            forKey: .vaultDirectory
        ) ?? Self.default.vaultDirectory
        var overrides = try container.decodeIfPresent(
            [String: String].self,
            forKey: .directoryOverrides
        ) ?? [:]

        // Migrate legacy keys: if vaultDirectory was missing in JSON, check old keys
        if !container.contains(.vaultDirectory) {
            let legacyContainer = try decoder.container(keyedBy: LegacyDirectoryKeys.self)
            if let oldBookmarksDir = try legacyContainer.decodeIfPresent(String.self, forKey: .ciderDataDirectory),
               oldBookmarksDir != "~/Documents/Cider/Bookmarks" {
                overrides[StorageType.bookmarks.rawValue] = oldBookmarksDir
                // Contacts, date cards, stacks, labels, saved views, sources were also in this dir
                overrides[StorageType.contacts.rawValue] = oldBookmarksDir
                overrides[StorageType.dateCards.rawValue] = oldBookmarksDir
                overrides[StorageType.stacks.rawValue] = oldBookmarksDir
                overrides[StorageType.labels.rawValue] = oldBookmarksDir
                overrides[StorageType.savedViews.rawValue] = oldBookmarksDir
                overrides[StorageType.sources.rawValue] = oldBookmarksDir
            }
            if let oldNotesDir = try legacyContainer.decodeIfPresent(String.self, forKey: .notesDirectory),
               oldNotesDir != "~/Documents/Cider/Notes" {
                overrides[StorageType.notes.rawValue] = oldNotesDir
            }
        }
        directoryOverrides = overrides

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
        bookmarkDetailViewMode = try container.decodeIfPresent(DetailViewMode.self, forKey: .bookmarkDetailViewMode)
        noteDetailViewMode = try container.decodeIfPresent(DetailViewMode.self, forKey: .noteDetailViewMode)
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
        tagsCollapsed = try container.decodeIfPresent(Bool.self, forKey: .tagsCollapsed) ?? false
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
        ) ?? false
        enableSoundEffects = try container.decodeIfPresent(
            Bool.self,
            forKey: .enableSoundEffects
        ) ?? false
        enableAutoTagging = try container.decodeIfPresent(Bool.self, forKey: .enableAutoTagging) ?? true
        enableEmbeddings = try container.decodeIfPresent(Bool.self, forKey: .enableEmbeddings) ?? true
        enablePageSummaries = try container.decodeIfPresent(Bool.self, forKey: .enablePageSummaries) ?? true
        enableOCRIndexing = try container.decodeIfPresent(Bool.self, forKey: .enableOCRIndexing) ?? false
        enableColorExtraction = try container.decodeIfPresent(Bool.self, forKey: .enableColorExtraction) ?? true
        screenCaptureToastTimeout = try container.decodeIfPresent(
            Int.self, forKey: .screenCaptureToastTimeout
        ) ?? 8
        screenCaptureDefaultAction = try container.decodeIfPresent(
            String.self, forKey: .screenCaptureDefaultAction
        ) ?? "note"
        dateCardSurfacingDays = try container.decodeIfPresent(Int.self, forKey: .dateCardSurfacingDays) ?? 7
        enableDateCardNotifications = try container.decodeIfPresent(Bool.self, forKey: .enableDateCardNotifications) ?? false
        dateCardDefaultNotificationMinutes = try container.decodeIfPresent(Int.self, forKey: .dateCardDefaultNotificationMinutes) ?? 30
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        showDragModeHints = try container.decodeIfPresent(Bool.self, forKey: .showDragModeHints) ?? true
        enableClipboardHistory = try container.decodeIfPresent(Bool.self, forKey: .enableClipboardHistory) ?? true
        enableClipboardHotkey = try container.decodeIfPresent(Bool.self, forKey: .enableClipboardHotkey) ?? true
        clipboardRetentionDays = try container.decodeIfPresent(Int.self, forKey: .clipboardRetentionDays) ?? 30
        clipboardImageRetentionDays = try container.decodeIfPresent(Int.self, forKey: .clipboardImageRetentionDays) ?? 7
        clipboardMaxImageStorageMB = try container.decodeIfPresent(Int.self, forKey: .clipboardMaxImageStorageMB) ?? 500
        clipboardPanelPosition = try container.decodeIfPresent(ClipboardPanelPosition.self, forKey: .clipboardPanelPosition) ?? .followMouse
        syncEnabled = try container.decodeIfPresent(Bool.self, forKey: .syncEnabled) ?? false
        syncURL = try container.decodeIfPresent(String.self, forKey: .syncURL) ?? ""
        syncToken = try container.decodeIfPresent(String.self, forKey: .syncToken) ?? ""
        lastSyncTimestamp = try container.decodeIfPresent(Double.self, forKey: .lastSyncTimestamp) ?? 0
        lastSuccessfulPushAt = try container.decodeIfPresent(Double.self, forKey: .lastSuccessfulPushAt) ?? 0
        aiChatDocked = try container.decodeIfPresent(Bool.self, forKey: .aiChatDocked) ?? false
        aiChatVisible = try container.decodeIfPresent(Bool.self, forKey: .aiChatVisible) ?? false
        didMigrateBookmarkFiles = try container.decodeIfPresent(Bool.self, forKey: .didMigrateBookmarkFiles) ?? false
        didMigrateVaultToCiderDir = try container.decodeIfPresent(Bool.self, forKey: .didMigrateVaultToCiderDir) ?? false
        didMigrateContentToInbox = try container.decodeIfPresent(Bool.self, forKey: .didMigrateContentToInbox) ?? false
        didMigrateContactsToPerFile = try container.decodeIfPresent(Bool.self, forKey: .didMigrateContactsToPerFile) ?? false
        didMigrateTodosToPerFile = try container.decodeIfPresent(Bool.self, forKey: .didMigrateTodosToPerFile) ?? false
        didMigrateDateCardsToPerFile = try container.decodeIfPresent(Bool.self, forKey: .didMigrateDateCardsToPerFile) ?? false
        lastReconciliationAt = try container.decodeIfPresent(Double.self, forKey: .lastReconciliationAt) ?? 0
        openOnMouseScreen = try container.decodeIfPresent(Bool.self, forKey: .openOnMouseScreen) ?? false
        sessionRestoreBrowserBundleID = try container.decodeIfPresent(String.self, forKey: .sessionRestoreBrowserBundleID)
        tableColumnConfig = try container.decodeIfPresent(TableColumnConfig.self, forKey: .tableColumnConfig) ?? .default
    }

    init(
        showMenuBarIcon: Bool = true,
        textSize: TextSize = .medium,
        activationMode: ActivationMode = .doubleTap,
        activationSpeed: Double = 0.3,
        enableNotesHotkey: Bool = true,
        notesEditorTextSize: NotesEditorTextSize = .normal,
        enableBookmarksHotkey: Bool = true,
        enableBookmarksCaptureHotkey: Bool = true,
        autoCaptureCopiedURLs: Bool = false,
        confirmCopiedURLBeforeSave: Bool = false,
        autoCaptureCopiedImages: Bool = false,
        vaultDirectory: String = "~/CiderVault",
        directoryOverrides: [String: String] = [:],
        rememberPanelPosition: Bool = true,
        bookmarksDefaultViewMode: BookmarkDisplayMode = .masonry,
        bookmarksCardSize: BookmarkCardSize = .comfortable,
        bookmarksCardSizeScale: Double? = nil,
        notesDefaultViewMode: NoteDisplayMode = .list,
        notesCardSizeScale: Double? = nil,
        detailViewMode: DetailViewMode = .slideOut,
        bookmarkDetailViewMode: DetailViewMode? = nil,
        noteDetailViewMode: DetailViewMode? = nil,
        detailSlideOutWidth: CGFloat? = nil,
        showContinueSection: Bool = true,
        continueSectionCollapsed: Bool = false,
        subFoldersCollapsed: Bool = false,
        homeDisplayMode: LibraryDisplayMode = .list,
        homeCardSizeScale: Double? = nil,
        tagsCollapsed: Bool = false,
        enableLinkedSources: Bool = false,
        trashRetentionDays: Int = 30,
        captureToastPosition: ToastPosition = .topCenterScreen,
        undoToastPosition: ToastPosition = .bottomRightPanel,
        homeSort: LibrarySortMode = .createdDescending,
        homeEntityFilter: Set<LibraryEntityType> = Set(LibraryEntityType.allCases),
        enableSpotlightIndexing: Bool = false,
        enableSoundEffects: Bool = false,
        enableAutoTagging: Bool = true,
        enableEmbeddings: Bool = true,
        enablePageSummaries: Bool = true,
        enableOCRIndexing: Bool = false,
        enableColorExtraction: Bool = true,
        screenCaptureToastTimeout: Int = 8,
        screenCaptureDefaultAction: String = "note",
        dateCardSurfacingDays: Int = 7,
        enableDateCardNotifications: Bool = false,
        dateCardDefaultNotificationMinutes: Int = 30,
        hasCompletedOnboarding: Bool = false,
        showDragModeHints: Bool = true,
        enableClipboardHistory: Bool = true,
        enableClipboardHotkey: Bool = true,
        clipboardRetentionDays: Int = 30,
        clipboardImageRetentionDays: Int = 7,
        clipboardMaxImageStorageMB: Int = 500,
        clipboardPanelPosition: ClipboardPanelPosition = .followMouse,
        syncEnabled: Bool = false,
        syncURL: String = "",
        syncToken: String = "",
        lastSyncTimestamp: Double = 0,
        lastSuccessfulPushAt: Double = 0,
        aiChatDocked: Bool = false,
        aiChatVisible: Bool = false,
        didMigrateBookmarkFiles: Bool = false,
        didMigrateVaultToCiderDir: Bool = false,
        didMigrateContentToInbox: Bool = false,
        didMigrateContactsToPerFile: Bool = false,
        didMigrateTodosToPerFile: Bool = false,
        didMigrateDateCardsToPerFile: Bool = false,
        lastReconciliationAt: Double = 0,
        openOnMouseScreen: Bool = false,
        sessionRestoreBrowserBundleID: String? = nil,
        tableColumnConfig: TableColumnConfig = .default
    ) {
        self.showMenuBarIcon = showMenuBarIcon
        self.textSize = textSize
        self.activationMode = activationMode
        self.activationSpeed = activationSpeed
        self.enableNotesHotkey = enableNotesHotkey
        self.notesEditorTextSize = notesEditorTextSize
        self.enableBookmarksHotkey = enableBookmarksHotkey
        self.enableBookmarksCaptureHotkey = enableBookmarksCaptureHotkey
        self.autoCaptureCopiedURLs = autoCaptureCopiedURLs
        self.confirmCopiedURLBeforeSave = confirmCopiedURLBeforeSave
        self.autoCaptureCopiedImages = autoCaptureCopiedImages
        self.vaultDirectory = vaultDirectory
        self.directoryOverrides = directoryOverrides
        self.rememberPanelPosition = rememberPanelPosition
        self.bookmarksDefaultViewMode = bookmarksDefaultViewMode
        self.bookmarksCardSize = bookmarksCardSize
        self.bookmarksCardSizeScale = bookmarksCardSizeScale
        self.notesDefaultViewMode = notesDefaultViewMode
        self.notesCardSizeScale = notesCardSizeScale
        self.detailViewMode = detailViewMode
        self.bookmarkDetailViewMode = bookmarkDetailViewMode
        self.noteDetailViewMode = noteDetailViewMode
        self.detailSlideOutWidth = detailSlideOutWidth
        self.showContinueSection = showContinueSection
        self.continueSectionCollapsed = continueSectionCollapsed
        self.subFoldersCollapsed = subFoldersCollapsed
        self.homeDisplayMode = homeDisplayMode
        self.homeCardSizeScale = homeCardSizeScale
        self.tagsCollapsed = tagsCollapsed
        self.enableLinkedSources = enableLinkedSources
        self.trashRetentionDays = trashRetentionDays
        self.captureToastPosition = captureToastPosition
        self.undoToastPosition = undoToastPosition
        self.homeSort = homeSort
        self.homeEntityFilter = homeEntityFilter
        self.enableSpotlightIndexing = enableSpotlightIndexing
        self.enableSoundEffects = enableSoundEffects
        self.enableAutoTagging = enableAutoTagging
        self.enableEmbeddings = enableEmbeddings
        self.enablePageSummaries = enablePageSummaries
        self.enableOCRIndexing = enableOCRIndexing
        self.enableColorExtraction = enableColorExtraction
        self.screenCaptureToastTimeout = screenCaptureToastTimeout
        self.screenCaptureDefaultAction = screenCaptureDefaultAction
        self.dateCardSurfacingDays = dateCardSurfacingDays
        self.enableDateCardNotifications = enableDateCardNotifications
        self.dateCardDefaultNotificationMinutes = dateCardDefaultNotificationMinutes
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.showDragModeHints = showDragModeHints
        self.enableClipboardHistory = enableClipboardHistory
        self.enableClipboardHotkey = enableClipboardHotkey
        self.clipboardRetentionDays = clipboardRetentionDays
        self.clipboardImageRetentionDays = clipboardImageRetentionDays
        self.clipboardMaxImageStorageMB = clipboardMaxImageStorageMB
        self.clipboardPanelPosition = clipboardPanelPosition
        self.syncEnabled = syncEnabled
        self.syncURL = syncURL
        self.syncToken = syncToken
        self.lastSyncTimestamp = lastSyncTimestamp
        self.lastSuccessfulPushAt = lastSuccessfulPushAt
        self.aiChatDocked = aiChatDocked
        self.aiChatVisible = aiChatVisible
        self.didMigrateBookmarkFiles = didMigrateBookmarkFiles
        self.didMigrateVaultToCiderDir = didMigrateVaultToCiderDir
        self.didMigrateContentToInbox = didMigrateContentToInbox
        self.didMigrateContactsToPerFile = didMigrateContactsToPerFile
        self.didMigrateTodosToPerFile = didMigrateTodosToPerFile
        self.didMigrateDateCardsToPerFile = didMigrateDateCardsToPerFile
        self.lastReconciliationAt = lastReconciliationAt
        self.openOnMouseScreen = openOnMouseScreen
        self.sessionRestoreBrowserBundleID = sessionRestoreBrowserBundleID
        self.tableColumnConfig = tableColumnConfig
    }
}
