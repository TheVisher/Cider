# Cider Tech Stack

> **Read this for tech stack context.** This document covers Swift 6.2, SwiftUI, Combine, AppKit integration, and framework-specific patterns used in Cider.

---

## Overview

Cider uses a modern, native macOS tech stack:

| Layer | Technology | Version | Why |
|-------|-----------|---------|-----|
| Language | Swift | 6.2+ | Data-race safety, modern concurrency |
| UI Framework | SwiftUI | macOS 26+ | Declarative, performant, native |
| System Integration | AppKit | macOS 26+ | NSPanel, window management, system APIs |
| Concurrency | Swift Concurrency | 6.2+ | Async/await, actors, structured concurrency |
| Reactive State | Combine | macOS 26+ | @Published properties, reactive ViewModels |
| Storage | UserDefaults + JSON | macOS 26+ | Simple config persistence via Codable |
| Build System | Swift Package Manager | 6.2+ | SPM for dependencies + compilation; Xcode project wraps SPM for code signing |
| Auto-Updates | Sparkle | 2.6+ | macOS update framework |
| Sync | convex-swift | 0.8+ | Convex backend client |
| Local AI | mlx-swift-lm | 2.29.x | Apple MLX inference (Qwen 2.5) |
| YAML Parsing | Yams | 5.1+ | Kanban board YAML serialization |

Four external dependencies via SPM. All are well-maintained, permissively licensed libraries.

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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(url: "https://github.com/get-convex/convex-swift", from: "0.8.1"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm/", .upToNextMinor(from: "2.29.1")),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.3"),
    ],
    targets: [
        .target(
            name: "Cider",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "ConvexMobile", package: "convex-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Sources/Cider"
        )
    ]
)
```

### Concurrency Model

Most code runs on the main actor by default. ViewModels and services use `@MainActor`:

```swift
// ✅ Standard ViewModel pattern used throughout Cider
@MainActor
final class BookmarksViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var displayMode: BookmarkDisplayMode
    @Published var isVisible = false

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
struct Bookmark: Sendable, Identifiable {
    let id: UUID
    var title: String
    var urlString: String
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
final class LibraryViewModel: ObservableObject {
    @Published private(set) var items: [LibraryItemV2] = []
    @Published private(set) var recentItems: [LibraryItemV2] = []

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Subscribe to storage changes via Combine
        BookmarksStorage.shared.$bookmarks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildItems() }
            .store(in: &cancellables)

        NotesStorage.shared.$notes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildItems() }
            .store(in: &cancellables)

        rebuildItems()
    }

    func rebuildItems() {
        // Merge all storage types into unified feed
        // Pre-compute recentItems (top 8 by updatedDate)
        // ...
    }
}

// ✅ Dependency injection
struct CiderPanelView: View {
    @ObservedObject var bookmarksViewModel: BookmarksViewModel
    @ObservedObject var libraryViewModel: LibraryViewModel

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
@MainActor
final class BookmarksViewModel: ObservableObject {
    @Published var searchText: String = ""
    private var cancellables = Set<AnyCancellable>()

    init() {
        BookmarksStorage.shared.$bookmarks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
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
| Browser capture (AXUIElement) | Synchronous (AX APIs are sync) |
| Timer-based updates | Timer + @Published |
| Config change notifications | NotificationCenter + Combine |

---

## Storage and Persistence

Cider uses **UserDefaults + Codable** for all persistence. No database.

### CiderConfig Pattern

```swift
struct CiderConfig: Codable {
    var showMenuBarIcon: Bool
    var textSize: TextSize
    var activationMode: ActivationMode
    var activationSpeed: Double
    var vaultDirectory: String
    var rememberPanelPosition: Bool
    var bookmarksDefaultViewMode: BookmarkDisplayMode
    // ... 40+ properties (see Models/CiderConfig.swift)

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
        }
    }

    // Custom decoding — every property uses decodeIfPresent + fallback
    // for backward compatibility when new fields are added
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        textSize = try container.decodeIfPresent(TextSize.self, forKey: .textSize) ?? .medium
        activationMode = try container.decodeIfPresent(ActivationMode.self, forKey: .activationMode) ?? .doubleTap
        // ... all properties follow this pattern
    }
}
```

### Content Storage

All user content is stored as standard files in `~/CiderVault/` (see `Docs/Architecture/STORAGE.md` for full details):
- Bookmarks: `.webloc` files + per-folder `.cider-meta.json` sidecar
- Notes: `.md` files
- Contacts: `.vcf` files
- Date Cards / Todos: `.ics` files
- App metadata: JSON indexes in `~/CiderVault/.cider/{type}/`
- App config: `CiderConfig` struct in UserDefaults (key: `"CiderConfig"`)

**Why not a database?**
- Files are the source of truth — users can browse in Finder
- Standard formats (`.webloc`, `.md`, `.vcf`, `.ics`) open in native apps
- Simple read/write with Codable indexes for fast startup
- Atomic updates with `.atomic` write options

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

// ✅ Spring presets from CiderAnimation
withAnimation(CiderAnimation.snappy) {
    isExpanded.toggle()
}

// ✅ Respect Reduce Motion
@Environment(\.accessibilityReduceMotion) var reduceMotion
withAnimation(reduceMotion ? .none : .snappy) {
    isExpanded.toggle()
}
```

---

## AppKit Integration

> NSPanel setup patterns are documented in `Docs/Architecture/FLOATING_PANEL.md`.

### NSPanel Integration

NSPanel setup patterns (borderless, non-activating, custom shadow, resize handles) are documented in `Docs/Architecture/FLOATING_PANEL.md`. Key types:
- `CiderPanel` — main resizable panel (`App/CiderPanel.swift`)
- `CiderPanelShell` — SwiftUI shell with sidebar, resize, compact mode (`Views/Shared/CiderPanelShell.swift`)
- `AcrylicPanelBackground` — acrylic + shadow + corners (`Views/Shared/AcrylicPanelBackground.swift`)
- `PanelEdgeResizeView` — all-edge AppKit resize handles (`Views/Shared/PanelEdgeResizeView.swift`)

---

## Testing Patterns

### Swift Testing Framework

```swift
import Testing

@Test("Config loads with defaults for missing fields")
func configLoadsDefaults() throws {
    let oldJSON = """
    {"textSize":"medium"}
    """
    UserDefaults.standard.set(oldJSON.data(using: .utf8), forKey: "CiderConfig")

    let config = CiderConfig.load()

    #expect(config.showMenuBarIcon == true)
    #expect(config.activationMode == .doubleTap)
    #expect(config.textSize == .medium)
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

**Last Updated**: March 2026

**This document reflects the actual Cider tech stack: Swift 6.2, SwiftUI, AppKit, Combine, UserDefaults, plus four SPM dependencies (Sparkle, convex-swift, mlx-swift-lm, Yams).**
