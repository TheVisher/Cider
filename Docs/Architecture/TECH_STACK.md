# Cider Tech Stack

> **Read this for tech stack context.** This document covers Swift 6.2, SwiftUI, Combine, AppKit integration, and framework-specific patterns used in Cider.

---

## Overview

Cider uses a modern, native macOS tech stack with zero external dependencies:

| Layer | Technology | Version | Why |
|-------|-----------|---------|-----|
| Language | Swift | 6.2+ | Data-race safety, modern concurrency |
| UI Framework | SwiftUI | macOS 26+ | Declarative, performant, native |
| System Integration | AppKit | macOS 26+ | NSPanel, window management, system APIs |
| Concurrency | Swift Concurrency | 6.2+ | Async/await, actors, structured concurrency |
| Reactive State | Combine | macOS 26+ | @Published properties, reactive ViewModels |
| Storage | UserDefaults + JSON | macOS 26+ | Simple config persistence via Codable |
| Build System | Swift Package Manager | 6.2+ | No Xcode project, pure SPM |

**No external dependencies.** `Package.swift` has `dependencies: []`.

---

## Swift 6.2 Language

### Language Mode

Cider uses **Swift 6.2 language mode** with Swift Package Manager:

```swift
// Package.swift
// swift-tools-version: 6.2
let package = Package(
    name: "Cider",
    platforms: [.macOS(.v26)],
    dependencies: [],
    targets: [
        .executableTarget(name: "Cider", path: "Sources/Cider")
    ]
)
```

### Concurrency Model

Most code runs on the main actor by default. ViewModels and services use `@MainActor`:

```swift
// ✅ Standard ViewModel pattern used throughout Cider
@MainActor
final class CommandPaletteViewModel: ObservableObject {
    @Published var pinnedApps: [AppInfo] = []
    @Published var windowGroups: [WindowAppGroup] = []
    @Published var isVisible = false
    @Published var searchText: String = ""

    private var cancellables = Set<AnyCancellable>()
}

// ✅ Opt into background execution when needed
nonisolated func heavyComputation() async -> Result {
    return performWork()
}
```

#### When to Use Each Pattern

| Pattern | When to Use |
|---------|-------------|
| **@MainActor** (default) | UI updates, ViewModels, most app code |
| **nonisolated** | CPU-intensive work, I/O operations |
| **Actor** | Shared mutable state accessed from multiple contexts |
| **@Sendable closures** | Crossing actor boundaries safely |

### Sendable and Thread Safety

```swift
// ✅ Value types are implicitly Sendable
struct WindowInfo: Sendable {
    let id: CGWindowID
    let title: String
    let ownerPID: pid_t
}

// ✅ Final classes with immutable properties
final class Configuration: Sendable {
    let apiKey: String
    let timeout: TimeInterval
}

// ✅ Use OSAllocatedUnfairLock for lightweight thread safety
// (Used in DoubleTapDetector for suppressUntilNextOptionDown)
import os
let lock = OSAllocatedUnfairLock(initialState: false)
lock.withLock { state in
    state = true
}
```

### Typed Throws (New in Swift 6)

```swift
// ✅ Type-safe error handling
enum StorageError: Error {
    case encodingFailed
    case decodingFailed
    case permissionDenied
}

func saveConfig(_ config: CiderConfig) throws(StorageError) {
    guard let data = try? JSONEncoder().encode(config) else {
        throw .encodingFailed
    }
    UserDefaults.standard.set(data, forKey: CiderConfig.storageKey)
}
```

---

## State Management Patterns

### ObservableObject + @Published (Primary Pattern)

Cider uses `ObservableObject` with `@Published` properties for all ViewModels. **Not** `@Observable`.

```swift
// ✅ Standard ViewModel pattern used throughout Cider
@MainActor
final class WindowListViewModel: ObservableObject {
    @Published var groups: [WindowAppGroup] = []
    @Published var monitors: [MonitorInfo] = []

    let windowManager: WindowManager
    private var cancellable: AnyCancellable?
    private var monitorCancellable: AnyCancellable?

    init(windowManager: WindowManager = WindowManager()) {
        self.windowManager = windowManager

        // Subscribe to monitor changes via Combine
        monitorCancellable = MonitorManager.shared.$monitors
            .receive(on: DispatchQueue.main)
            .sink { [weak self] monitors in
                self?.monitors = monitors
                self?.refresh()
            }

        monitors = MonitorManager.shared.monitors
        refresh()
        startTimer()
    }

    private func startTimer() {
        cancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    func refresh() {
        let allWindows = windowManager.fetchWindows()
        // Group by app, sort alphabetically
        // ...
    }
}

// ✅ Local state with @State
struct PaletteSearchBar: View {
    @Binding var text: String
    @State private var isFocused = false

    var body: some View {
        // ...
    }
}

// ✅ Dependency injection
struct CommandPaletteView: View {
    @ObservedObject var viewModel: CommandPaletteViewModel

    var body: some View {
        // ...
    }
}
```

**Why not `@Observable`?** Cider was built with `ObservableObject` + `@Published`, which works well with Combine subscriptions for reactive data flow between ViewModels.

### Combine for Reactive State

Cider uses **Combine extensively** for reactive state management:

```swift
// Data flows from services → ViewModels → Views via Combine subscriptions
final class CommandPaletteViewModel: ObservableObject {
    @Published var windowGroups: [WindowAppGroup] = []
    private var cancellables = Set<AnyCancellable>()

    init(windowListViewModel: WindowListViewModel) {
        windowListViewModel.$groups
            .receive(on: DispatchQueue.main)
            .sink { [weak self] groups in
                self?.windowGroups = groups
            }
            .store(in: &cancellables)
    }
}
```

### When to Use Each

| Use Case | Pattern Used in Cider |
|----------|----------------------|
| ViewModel state | Combine (@Published) |
| View → ViewModel binding | Combine (@ObservedObject, @Published) |
| Service → ViewModel sync | Combine (.sink, .receive(on:)) |
| One-shot operations | async/await (Task, await) |
| Window management API calls | Synchronous (AXUIElement is sync) |
| Timer-based updates | Timer + @Published |
| Config change notifications | NotificationCenter + Combine |

---

## Storage and Persistence

Cider uses **UserDefaults + Codable** for all persistence. No database.

### CiderConfig Pattern

```swift
struct CiderConfig: Codable {
    var autoHideApps: Bool
    var showMenuBarIcon: Bool
    var textSize: TextSize
    var paletteSize: PaletteSize
    var activationMode: ActivationMode
    var enableOptionTabCycling: Bool
    var optionTabCycleAllScreens: Bool
    var rememberPaletteState: Bool

    static let storageKey = "CiderConfig"

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
            UserDefaults.standard.synchronize()
        }
    }

    // Custom decoding for backward compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoHideApps = try container.decodeIfPresent(Bool.self, forKey: .autoHideApps) ?? false
        showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        textSize = try container.decodeIfPresent(TextSize.self, forKey: .textSize) ?? .medium
        paletteSize = try container.decodeIfPresent(PaletteSize.self, forKey: .paletteSize) ?? .medium
        activationMode = try container.decodeIfPresent(ActivationMode.self, forKey: .activationMode) ?? .doubleTap
        enableOptionTabCycling = try container.decodeIfPresent(Bool.self, forKey: .enableOptionTabCycling) ?? true
        optionTabCycleAllScreens = try container.decodeIfPresent(Bool.self, forKey: .optionTabCycleAllScreens) ?? true
        rememberPaletteState = try container.decodeIfPresent(Bool.self, forKey: .rememberPaletteState) ?? false
    }
}
```

### Pinned Apps Storage

Pinned apps are stored as JSON in UserDefaults:
- Key: `"PinnedApps"`
- Format: Array of `AppInfo` (bundle ID, name, path)
- Loaded at app launch, saved on changes

### Folders Storage

App folders are stored as JSON in UserDefaults:
- Key: `"AppFolders"`
- Format: Array of folder objects (name, app bundle IDs)
- Managed by `CommandPaletteViewModel`

**Why not a database?**
- Simple data model (< 100 items)
- No complex queries needed
- Fast reads/writes with Codable
- Atomic updates with UserDefaults

---

## SwiftUI Patterns

### Performance Fundamentals

**Core principle**: Keep view bodies lightweight and pure.

```swift
// ❌ Bad: Heavy computation in body
struct WindowRow: View {
    let window: WindowInfo

    var body: some View {
        HStack {
            Text(formatTitle(window.title))  // Bad: every render
        }
    }
}

// ✅ Good: Precomputed data
struct WindowRow: View {
    let window: WindowInfo
    let formattedTitle: String

    var body: some View {
        HStack {
            Text(formattedTitle)
        }
    }
}
```

### List Performance

```swift
// ✅ Use LazyVStack for custom layouts (Cider's primary pattern)
ScrollView {
    LazyVStack(spacing: Spacing.md) {
        ForEach(items) { item in
            CustomCard(item: item)
        }
    }
}

// ✅ Use explicit .id() for reorderable items
ForEach(pinnedApps) { app in
    AppIcon(app: app)
        .id(app.bundleID)
}
```

### Animation Best Practices

```swift
// ✅ Use SwiftUI spring presets (aliased in CiderAnimation)
withAnimation(.snappy) {
    isExpanded.toggle()
}

// ✅ Custom springs from CiderAnimation
withAnimation(CiderAnimation.hoverMagnify) {
    scale = 1.08
}

// ✅ Respect Reduce Motion
@Environment(\.accessibilityReduceMotion) var reduceMotion
withAnimation(reduceMotion ? .none : .snappy) {
    isExpanded.toggle()
}
```

---

## AppKit Integration

### NSPanel for Floating Windows

```swift
final class CommandPalettePanel: NSPanel {
    init() {
        let initialFrame = NSRect(x: 0, y: 0, width: 600, height: 500)
        super.init(contentRect: initialFrame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false  // We draw our own shadow

        isMovable = false
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
```

### Window Management (AXUIElement)

```swift
import ApplicationServices

// WindowManager uses CGWindowListCopyWindowInfo for enumeration
// and AXUIElement for manipulation (focus, close, move, resize)

// Key patterns:
// - CGWindowList coordinates: bottom-left origin, Y up
// - AX coordinates: top-left origin, Y down
// - Use convertToAXPosition() to convert between them
// - When resizing + moving: resize first, then position
```

---

## Testing Patterns

### Swift Testing Framework

```swift
import Testing

@Test("Config loads with defaults for missing fields")
func configLoadsDefaults() throws {
    let oldJSON = """
    {"textSize":"medium","paletteSize":"medium"}
    """
    UserDefaults.standard.set(oldJSON.data(using: .utf8), forKey: "CiderConfig")

    let config = CiderConfig.load()

    #expect(config.autoHideApps == false)
    #expect(config.activationMode == .doubleTap)
    #expect(config.enableOptionTabCycling == true)
}
```

---

## Performance Checklist

When implementing any feature, verify:

- [ ] SwiftUI views use stable `.id()` for items
- [ ] Heavy computations moved out of view bodies
- [ ] @Published properties don't update too frequently
- [ ] Animations respect Reduce Motion
- [ ] No force unwrapping in production code
- [ ] Memory leaks checked (weak self in closures)
- [ ] Use spring animations, not linear/easeInOut

---

## Resources

### Official Documentation
- [Swift.org - Swift 6 Language Guide](https://docs.swift.org/swift-book/)
- [Apple - SwiftUI Performance](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance)

### WWDC Sessions
- WWDC 2025: Optimize SwiftUI performance with Instruments
- WWDC 2024: What's new in Swift 6

---

**Last Updated**: February 2026

**This document reflects the actual Cider tech stack: Swift 6.2, SwiftUI, AppKit, Combine, UserDefaults. No external dependencies.**
