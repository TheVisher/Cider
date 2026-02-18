# User Preferences & Settings Management

> **For Cider**: Systematic approach to settings so features don't ship without corresponding preferences.

---

## Current Settings Model

Cider uses `CiderConfig`, a Codable struct stored in UserDefaults as JSON:

```swift
struct CiderConfig: Codable {
    // Behavior
    var autoHideApps: Bool = false           // Hide other apps when switching, like Stage Manager
    var activationMode: ActivationMode = .doubleTap  // Double tap vs single tap
    var enableOptionTabCycling: Bool = true   // Enable Option+Tab window cycling
    var optionTabCycleAllScreens: Bool = true // Cycle windows on all screens vs current only
    var rememberPaletteState: Bool = false    // Keep folders open between palette sessions

    // System
    var showMenuBarIcon: Bool = true

    // Appearance
    var textSize: TextSize = .medium
    var paletteSize: PaletteSize = .medium
}
```

**Not stored in CiderConfig:**
`launchAtLogin` is managed via `SMAppService`.

### Enums

```swift
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
    case small, medium, large

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

    var displayName: String {
        rawValue.capitalized
    }
}

enum PaletteSize: String, Codable, CaseIterable {
    case small, medium, large

    var width: CGFloat {
        switch self {
        case .small: return 480
        case .medium: return 600
        case .large: return 760
        }
    }

    var minHeight: CGFloat {
        switch self {
        case .small: return 320
        case .medium: return 400
        case .large: return 480
        }
    }

    var maxHeight: CGFloat {
        switch self {
        case .small: return 480
        case .medium: return 600
        case .large: return 720
        }
    }

    var displayName: String {
        rawValue.capitalized
    }
}
```

---

## Backward Compatibility

When adding new fields to `CiderConfig`, use custom decoding to handle existing user configs:

```swift
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    // Use decodeIfPresent with defaults for all fields
    autoHideApps = try container.decodeIfPresent(Bool.self, forKey: .autoHideApps) ?? false
    showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
    textSize = try container.decodeIfPresent(TextSize.self, forKey: .textSize) ?? .medium
    paletteSize = try container.decodeIfPresent(PaletteSize.self, forKey: .paletteSize) ?? .medium
    activationMode = try container.decodeIfPresent(ActivationMode.self, forKey: .activationMode) ?? .doubleTap
    enableOptionTabCycling = try container.decodeIfPresent(Bool.self, forKey: .enableOptionTabCycling) ?? true
    optionTabCycleAllScreens = try container.decodeIfPresent(Bool.self, forKey: .optionTabCycleAllScreens) ?? true
    rememberPaletteState = try container.decodeIfPresent(Bool.self, forKey: .rememberPaletteState) ?? false
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
            UserDefaults.standard.synchronize()  // Force immediate write
        }
    }
}
```

---

## Settings UI Structure

Settings window has 5 tabs: General, Pinned Apps, Appearance, Advanced, About.

### General Tab

| Setting | Type | Default | Notes |
|---------|------|---------|-------|
| Launch at login | Toggle | Off | Via SMAppService |
| Activation mode | Picker | Double tap | Double tap or Single tap |
| Double-tap speed | Slider | 0.3s | 0.2–0.5s range, shown only in double-tap mode. **UI only — not yet persisted in CiderConfig.** |
| Option+Tab cycling | Toggle | On | |
| Cycle all screens | Toggle | On | Shown only when cycling enabled |
| Remember palette state | Toggle | Off | Keep folders open between sessions |

### Pinned Apps Tab

| Setting | Type | Default |
|---------|------|---------|
| Pinned apps list | Drag-to-reorder list | — |
| Add app | Button | — |
| Remove app | Button | — |
| App folders | Folder management | — |
| Import from Dock | Button | — |

### Appearance Tab

| Setting | Type | Default |
|---------|------|---------|
| Text size | Picker | Medium |
| Palette size | Picker | Medium |
| Show menu bar icon | Toggle | On |

### Advanced Tab

| Setting | Type | Default | Notes |
|---------|------|---------|-------|
| Auto-hide inactive apps | Toggle | Off | Stage Manager-like behavior |
| Show Cider on | Picker | Screen containing mouse | **UI only — not yet persisted in CiderConfig.** Also: Main screen, Last used screen |
| Open Accessibility Settings | Button | — | Links to System Settings |
| Reset All Settings | Button | — | **Not yet wired — action is a no-op.** |

### About Tab

| Content | Type |
|---------|------|
| App version | Label |
| Credits | Label |

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

### Example: Command Palette Feature

```swift
struct CommandPaletteSettings: FeatureSettings {
    static let featureName = "Command Palette"

    static let configurableOptions: [SettingOption] = [
        SettingOption(
            key: "palette.activationKey",
            name: "Activation Key",
            description: "Double-tap this key to toggle the palette",
            type: .picker(options: ["Option", "Command", "Control"]),
            requiresRestart: false
        ),
        SettingOption(
            key: "palette.autoHideApps",
            name: "Auto-Hide Apps",
            description: "Hide other apps when focusing a window",
            type: .toggle,
            requiresRestart: false
        ),
        SettingOption(
            key: "palette.showPreviews",
            name: "Show Window Previews",
            description: "Display thumbnail previews of windows",
            type: .toggle,
            requiresRestart: false
        )
    ]

    static let defaults: [String: Any] = [
        "palette.activationKey": "Option",
        "palette.autoHideApps": false,
        "palette.showPreviews": false
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
class WindowListViewModel: ObservableObject {
    func focus(window: WindowInfo) {
        let config = CiderConfig.load()
        windowManager.focus(window: window, stageOthers: config.autoHideApps)
    }
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
CommandPaletteView()
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

> **Note:** No tests exist in the repo yet. The examples below show the recommended pattern using Swift Testing for when tests are added.

### Test Setting Persistence

```swift
import Testing

@Test("Settings persist across save/load")
func settingsPersist() throws {
    var config = CiderConfig.default
    config.autoHideApps = true
    config.save()

    let loaded = CiderConfig.load()
    #expect(loaded.autoHideApps == true)
}
```

### Test Backward Compatibility

```swift
@Test("Old config loads with defaults for missing fields")
func loadingOldConfig() throws {
    let oldConfigJSON = """
    {"textSize":"medium","paletteSize":"medium"}
    """
    UserDefaults.standard.set(oldConfigJSON.data(using: .utf8), forKey: "CiderConfig")

    let config = CiderConfig.load()

    #expect(config.autoHideApps == false)
    #expect(config.activationMode == .doubleTap)
    #expect(config.enableOptionTabCycling == true)
}
```

---

## Benefits

1. **Single source of truth**: All persisted settings in one Codable struct (except `launchAtLogin` via SMAppService; `hotkeyDoubleTapInterval` and `showOnScreen` are UI-only and not yet wired into CiderConfig)
2. **Type-safe**: Enums for constrained values
3. **Backward compatible**: Custom decoding handles missing fields
4. **Immediate save**: `synchronize()` ensures persistence
5. **Easy to test**: Pure data model, no dependencies

---

**This document is the source of truth for user preferences. When adding settings, update both the code and this documentation.**
