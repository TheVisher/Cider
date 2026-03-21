# User Preferences & Settings Management

> **For Cider**: Systematic approach to settings so features don't ship without corresponding preferences.

---

## Current Settings Model

Cider uses `CiderConfig`, a Codable struct stored in UserDefaults as JSON. The struct has grown significantly and now contains ~60+ fields across behavior, content, capture, appearance, intelligence, data management, and sync categories. Key fields include:

```swift
struct CiderConfig: Codable {
    var showMenuBarIcon: Bool
    var textSize: TextSize
    var activationMode: ActivationMode
    var activationSpeed: Double
    var enableNotesHotkey: Bool
    var enableBookmarksHotkey: Bool
    var enableBookmarksCaptureHotkey: Bool
    var autoCaptureCopiedURLs: Bool
    var vaultDirectory: String                  // Root directory for all Cider data (~/CiderVault)
    var rememberPanelPosition: Bool
    var bookmarksDefaultViewMode: BookmarkDisplayMode
    var notesDefaultViewMode: NoteDisplayMode
    var detailViewMode: DetailViewMode
    var enableLinkedSources: Bool
    var trashRetentionDays: Int
    var enableSpotlightIndexing: Bool
    var enableAutoTagging: Bool
    var enableEmbeddings: Bool
    var enablePageSummaries: Bool
    var enableOCRIndexing: Bool
    var enableColorExtraction: Bool
    var enableClipboardHistory: Bool
    var syncEnabled: Bool
    var openOnMouseScreen: Bool
    // ... and many more — see Models/CiderConfig.swift for the full list
}
```

> **Note:** The full CiderConfig has ~60+ properties. See `Sources/Cider/Models/CiderConfig.swift` for the definitive list. The above shows representative fields.

**Not stored in CiderConfig:**
`launchAtLogin` is managed via `SMAppService`.

### Key Enums

`ActivationMode` and `TextSize` are in `Models/CiderConfig.swift`. `PaletteSize` has been removed (panel is now freely resizable). Other config enums include `NotesEditorTextSize`, `ClipboardPanelPosition`, `BookmarkDisplayMode`, `NoteDisplayMode`, `DetailViewMode`, `LibraryDisplayMode`, `LibrarySortMode`, `ToastPosition`, and more.

```swift
enum ActivationMode: String, Codable, CaseIterable {
    case doubleTap
    case singleTap
}

enum TextSize: String, Codable, CaseIterable {
    case small, medium, large
    // scale: 0.85, 1.0, 1.18
    // bodySize: 12, 14, 16
}
```

---

## Backward Compatibility

When adding new fields to `CiderConfig`, use custom decoding to handle existing user configs:

```swift
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    // Use decodeIfPresent with defaults for all fields — pattern shown for representative fields
    showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
    textSize = try container.decodeIfPresent(TextSize.self, forKey: .textSize) ?? .medium
    activationMode = try container.decodeIfPresent(ActivationMode.self, forKey: .activationMode) ?? .doubleTap
    activationSpeed = try container.decodeIfPresent(Double.self, forKey: .activationSpeed) ?? 0.3
    enableAutoTagging = try container.decodeIfPresent(Bool.self, forKey: .enableAutoTagging) ?? true
    // ... (all ~60+ fields follow the same pattern)
}
```

This ensures old configs without new fields still load correctly.

---

## Loading and Saving

```swift
extension CiderConfig {
    static func load() -> CiderConfig {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return .default
        }
        do {
            return try JSONDecoder().decode(CiderConfig.self, from: data)
        } catch {
            logger.error("Config decode error: \(error, privacy: .public). Using defaults (saved config preserved).")
            return .default
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: CiderConfig.storageKey)
        }
    }
}
```

---

## Settings UI Structure

Settings window uses 7 categories with subcategories (see `Views/Settings/SettingsEnums.swift`):

| Category | Subcategories |
|----------|--------------|
| **General** | Startup, Activation, Panel, Shortcuts |
| **Content** | Bookmarks, Notes |
| **Capture** | Bookmarks, Clipboard, Storage |
| **Appearance** | Text & Menu Bar, Sounds, Toasts |
| **Intelligence** | Features (auto-tagging, embeddings, summaries, OCR, colors) |
| **Data** | Directories, Trash, Notifications, Import & Export |
| **About** | Overview |

> **Note:** The old "5 tabs" structure (General, Pinned Apps, Appearance, Advanced, About) was replaced. Pinned Apps and window cycling features were removed during the pivot from command palette to floating panel.

---

## Settings Management Pattern

### The Problem

Features ship without corresponding settings because:
1. No systematic place to track what needs settings
2. Settings are added ad-hoc after the fact
3. No checklist for "what settings does this feature need?"

### The Solution: Feature Settings Protocol

> **Note:** This protocol is aspirational — not yet implemented. Currently, all settings are fields on `CiderConfig` directly. This pattern would formalize the approach for future features.

**Every feature declares its settings upfront:**

```swift
protocol FeatureSettings {
    /// The feature name (for organization in settings)
    static var featureName: String { get }

    /// All user-configurable options for this feature
    static var configurableOptions: [SettingOption] { get }

    /// Default values for all settings
    static var defaults: [String: Any] { get }
}

struct SettingOption {
    let key: String
    let name: String
    let description: String
    let type: SettingType
    let requiresRestart: Bool

    enum SettingType {
        case toggle
        case picker(options: [String])
        case slider(min: Double, max: Double, step: Double)
        case text
    }
}
```

### Example: Bookmarks Feature

```swift
struct BookmarksSettings: FeatureSettings {
    static let featureName = "Bookmarks"

    static let configurableOptions: [SettingOption] = [
        SettingOption(
            key: "bookmarks.autoCaptureCopiedURLs",
            name: "Auto-Capture Copied URLs",
            description: "Automatically save copied URLs as bookmarks",
            type: .toggle,
            requiresRestart: false
        ),
        SettingOption(
            key: "bookmarks.enableCaptureHotkey",
            name: "Capture Hotkey",
            description: "Enable Option+Shift+B to capture active browser tab",
            type: .toggle,
            requiresRestart: false
        )
    ]

    static let defaults: [String: Any] = [
        "bookmarks.autoCaptureCopiedURLs": false,
        "bookmarks.enableCaptureHotkey": true
    ]
}
```

---

## Proposed Near-Term Settings Additions

### Bookmarks: Thumbnail Quality Profile

Reason:
- Bookmark cards now render from downsampled thumbnails for memory stability while preserving full-size originals for explicit open/export actions.
- This is a good candidate for a user-facing quality/performance toggle.

Proposed config shape:

```swift
enum BookmarkThumbnailQuality: String, Codable, CaseIterable {
    case high      // 720px max thumbnail dimension (current default)
    case balanced  // 512px
    case memorySaver // 360px
}
```

Proposed settings UI:
- Tab: `Appearance` (or `Bookmarks` if feature-specific tabs expand later)
- Label: `Bookmark Thumbnail Quality`
- Options: `High Quality (720)`, `Balanced (512)`, `Memory Saver (360)`

Operational note:
- Changing this setting should trigger a background thumbnail re-normalization pass for existing bookmarks.

---

## Feature Settings Checklist

**When implementing ANY feature, you MUST:**

1. [ ] Define settings in `CiderConfig` struct
2. [ ] Add custom decoding for backward compatibility
3. [ ] Create UI in appropriate settings tab
4. [ ] Wire up settings to feature behavior
5. [ ] Test settings persist across app restarts

**This ensures no feature ships without corresponding settings!**

---

## Usage in Code

### Reading Settings

```swift
// Typical usage pattern:
let config = CiderConfig.load()
if config.enableAutoTagging {
    // run auto-tagging pipeline
}
```

### Observing Settings Changes

For settings that need immediate effect:

```swift
class SomeService {
    private var settingsObserver: NSObjectProtocol?

    init() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadSettings()
        }
    }

    deinit {
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func reloadSettings() {
        let config = CiderConfig.load()
        // Apply new settings
    }
}
```

---

## Text Scaling

Text size is applied via a custom environment key:

```swift
// Define the key
struct TextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var textScale: CGFloat {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

// Apply at root view
CiderPanelView()
    .environment(\.textScale, config.textSize.scale)

// Use in child views
struct SomeView: View {
    @Environment(\.textScale) private var textScale

    var body: some View {
        Text("Hello")
            .font(.system(size: 12 * textScale))
    }
}
```

---

## Testing Settings

Backward compatibility tests exist in `Tests/CiderTests/CiderConfigBackwardCompatTests.swift` using Swift Testing. They verify that empty JSON, minimal JSON, and unknown keys all decode correctly with proper defaults.

---

## Benefits

1. **Single source of truth**: All persisted settings in one Codable struct (except `launchAtLogin` via SMAppService)
2. **Type-safe**: Enums for constrained values
3. **Backward compatible**: Custom decoding handles missing fields
4. **Immediate save**: UserDefaults persistence on every save
5. **Easy to test**: Pure data model, no dependencies

---

**This document is the source of truth for user preferences. When adding settings, update both the code and this documentation.**
