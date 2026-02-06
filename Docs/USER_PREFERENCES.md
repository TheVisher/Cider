# User Preferences & Settings Management

> **For Cider**: Systematic approach to settings so features don't ship without corresponding preferences.

---

## Current Settings Model

Cider uses `CiderConfig`, a Codable struct stored in UserDefaults as JSON:

```swift
struct CiderConfig: Codable {
    // Behavior
    var autoHideApps: Bool = false

    // System
    var showMenuBarIcon: Bool = true

    // Appearance
    var textSize: TextSize = .medium
    var paletteSize: PaletteSize = .medium
}
```

**Not stored in CiderConfig:**  
`launchAtLogin` is managed via `SMAppService`. The hotkey toggle and double-tap interval are currently UI-only (not yet wired to `DoubleTapDetector`).

### Enums

```swift
enum TextSize: String, Codable, CaseIterable {
    case small, medium, large

    var scale: CGFloat {
        switch self {
        case .small: return 0.85
        case .medium: return 1.0
        case .large: return 1.18
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
}
```

This ensures old configs without new fields still load correctly.

---

## Loading and Saving

```swift
extension CiderConfig {
    static func load() -> CiderConfig {
        guard let data = UserDefaults.standard.data(forKey: "CiderConfig"),
              let config = try? JSONDecoder().decode(CiderConfig.self, from: data) else {
            return CiderConfig()
        }
        return config
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "CiderConfig")
            UserDefaults.standard.synchronize()  // Force immediate save
        }
    }
}
```

---

## Settings UI Structure

### General Tab

| Setting | Type | Default |
|---------|------|---------|
| Launch at login | Toggle | Off |
| Double-tap Option to open | Toggle | On |
| Double-tap speed | Slider | 0.3s (UI-only, not yet wired) |

### Appearance Tab

| Setting | Type | Default |
|---------|------|---------|
| Text size | Picker | Medium |
| Palette size | Picker | Medium |
| Show menu bar icon | Toggle | On |

### Advanced Tab

| Setting | Type | Default |
|---------|------|---------|
| Auto-hide apps | Toggle | Off |
| Reset to defaults | Button | — |

---

## Settings Management Pattern

### The Problem

Features ship without corresponding settings because:
1. No systematic place to track what needs settings
2. Settings are added ad-hoc after the fact
3. No checklist for "what settings does this feature need?"

### The Solution: Feature Settings Protocol

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

### Test Setting Persistence

```swift
func testSettingsPersist() throws {
    var config = CiderConfig()
    config.autoHideApps = true
    config.save()

    let loaded = CiderConfig.load()
    XCTAssertTrue(loaded.autoHideApps)
}
```

### Test Backward Compatibility

```swift
func testLoadingOldConfig() throws {
    // Simulate old config without new fields
    let oldConfigJSON = """
    {"textSize":"medium","paletteSize":"medium"}
    """
    UserDefaults.standard.set(oldConfigJSON.data(using: .utf8), forKey: "CiderConfig")

    let config = CiderConfig.load()

    // New fields should have defaults
    XCTAssertEqual(config.autoHideApps, false)
    XCTAssertEqual(config.activationKey, .option)
}
```

---

## Benefits

1. **Single source of truth**: All settings in one Codable struct
2. **Type-safe**: Enums for constrained values
3. **Backward compatible**: Custom decoding handles missing fields
4. **Immediate save**: `synchronize()` ensures persistence
5. **Easy to test**: Pure data model, no dependencies

---

**This document is the source of truth for user preferences. When adding settings, update both the code and this documentation.**
