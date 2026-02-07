# Cider Conventions

> **Read this before writing code.** This document defines Swift style, SwiftUI patterns, performance guidelines, and how to add new features consistently.

---

## Swift Style

### Naming

```swift
// Types: UpperCamelCase
struct WindowInfo { }
class StorageService { }
protocol Focusable { }
enum ContentType { }

// Properties, methods, variables: lowerCamelCase
let windowTitle: String
func focusWindow(_ window: WindowInfo) { }
var isExpanded = false

// Constants: lowerCamelCase (not SCREAMING_CASE)
let defaultPaletteWidth: CGFloat = 600

// Boolean properties: use is/has/should/can prefix
var isRunning: Bool
var hasUnsavedChanges: Bool
var shouldAutoSave: Bool
var canBecomeKey: Bool
```

### File Organization

```swift
// MARK: - imports at top, alphabetized
import AppKit
import Combine
import SwiftUI

// MARK: - Type definition
struct NoteWindow: View {
    // MARK: - Properties (in this order)
    // 1. Environment
    @Environment(\.dismiss) private var dismiss
    
    // 2. State/Binding
    @State private var title = ""
    @StateObject private var viewModel: NoteViewModel
    
    // 3. Constants
    private let cornerRadius: CGFloat = 14
    
    // MARK: - Body
    var body: some View {
        // ...
    }
    
    // MARK: - Subviews (extracted as computed properties)
    private var headerView: some View {
        // ...
    }
    
    // MARK: - Methods
    private func save() {
        // ...
    }
}

// MARK: - Preview
#Preview {
    NoteWindow()
}
```

### Error Handling

```swift
// Use Result type for service methods that can fail
func saveNote(_ note: Note) -> Result<Note, StorageError>

// Use throws for synchronous operations
func loadConfig() throws -> CiderConfig

// Use async/await for async operations
func fetchThumbnail(for url: URL) async throws -> NSImage

// Never force unwrap in production code
// ❌ let window = windows.first!
// ✅ guard let window = windows.first else { return }
```

---

## SwiftUI Patterns

### View Composition

Keep views small. Extract subviews when:
- A section has its own state
- Code exceeds ~50 lines
- The same pattern repeats

```swift
// ❌ One giant view
struct CommandPaletteView: View {
    var body: some View {
        VStack {
            // 200 lines of search code
            // 300 lines of list code
            // 150 lines of footer code
        }
    }
}

// ✅ Composed from smaller views
struct CommandPaletteView: View {
    var body: some View {
        VStack(spacing: 0) {
            PaletteSearchBar()
            PaletteContentArea()
            PaletteFooterBar()
        }
    }
}
```

### State Management

```swift
// Local UI state: @State
@State private var isExpanded = false

// Shared state across views: @StateObject (owner) + @ObservedObject (consumer)
@StateObject private var viewModel = WindowListViewModel()

// App-wide state: Environment or singleton service
@Environment(\.colorScheme) var colorScheme

// Never put business logic in views
// ❌ Bad
Button("Save") {
    let data = try? JSONEncoder().encode(note)
    FileManager.default.createFile(at: path, contents: data)
}

// ✅ Good
Button("Save") {
    viewModel.save()
}
```

### Animations

**Always use spring animations for interactive elements:**

```swift
// ✅ Spring animation
withAnimation(.spring(duration: 0.3, bounce: 0.05)) {
    isExpanded.toggle()
}

// ❌ Linear or easeInOut for UI motion
withAnimation(.easeInOut) { // Don't do this
    isExpanded.toggle()
}
```

**Use animation tokens from Constants.swift:**

```swift
// ✅ Use SwiftUI animation presets (aliased in CiderAnimation)
withAnimation(.snappy) {
    // ...
}

// ✅ Or use custom springs from CiderAnimation
withAnimation(CiderAnimation.hoverMagnify) {
    scale = 1.08
}

// ❌ Don't create ad-hoc springs
withAnimation(.spring(duration: 0.35, bounce: 0.05)) {
    // ...
}
```

**Respect Reduce Motion:**

```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion

// ✅ Standard pattern — disable animation entirely
withAnimation(reduceMotion ? .none : .snappy) {
    isExpanded.toggle()
}

// ✅ Alternative — use linear fade if some motion is needed
withAnimation(reduceMotion ? CiderAnimation.reduceMotion : CiderAnimation.hoverMagnify) {
    scale = 1.08
}
```

### Colors

**For command palette, use the acrylic color palette:**

```swift
// ✅ Acrylic palette colors (command palette)
Text("Title")
    .foregroundStyle(CiderColors.primary)  // or .white

Rectangle()
    .fill(Color.white.opacity(0.2))  // Dividers

// ✅ Semantic colors (settings, standard views)
Text("Title")
    .foregroundStyle(.primary)

// ❌ Hardcoded hex colors
Rectangle()
    .fill(Color(hex: "#333333"))
```

### Spacing

**Use spacing tokens, never magic numbers:**

```swift
// ✅ Tokens
VStack(spacing: Spacing.md) {
    // ...
}
.padding(Spacing.lg)

// ❌ Magic numbers
VStack(spacing: 12) {
    // ...
}
.padding(16)
```

---

## Performance Guidelines

### SwiftUI Optimization

**List Virtualization:**
```swift
// ✅ Use List (auto-virtualizes, only renders visible rows)
List(items) { item in
    ItemRow(item: item)
}

// ❌ ScrollView + ForEach (renders everything)
ScrollView {
    ForEach(items) { item in
        ItemRow(item: item)
    }
}
```

**View Identity:**
```swift
// ✅ Use explicit .id() for reorderable items
List(items) { item in
    ItemRow(item: item)
        .id(item.id)
}
```

**Equatable Views:**
```swift
// ✅ Implement Equatable for complex row content
struct BookmarkRow: View, Equatable {
    let bookmark: Bookmark
    
    static func == (lhs: BookmarkRow, rhs: BookmarkRow) -> Bool {
        lhs.bookmark.id == rhs.bookmark.id &&
        lhs.bookmark.updatedAt == rhs.bookmark.updatedAt
    }
    
    var body: some View {
        // Complex layout
    }
}

// Usage
List(bookmarks) { bookmark in
    BookmarkRow(bookmark: bookmark)
        .equatable()
}
```

**@Published Gotcha:**
```swift
// ❌ Don't @Published entire large arrays
class ViewModel: ObservableObject {
    @Published var allItems: [LibraryItem] = [] // Triggers full UI rebuild on any change
}

// ✅ Use fine-grained updates
class ViewModel: ObservableObject {
    @Published var displayedItems: [LibraryItem] = []
    
    func loadMore() {
        // Append incrementally
        displayedItems.append(contentsOf: nextBatch)
    }
}
```

**LazyVStack/LazyHStack:**
```swift
// Only use when List doesn't fit the design
LazyVStack(spacing: Spacing.md) {
    ForEach(items) { item in
        ItemCard(item: item)
    }
}
```

### Content Loading

**Lazy Loading Pattern:**
```swift
// ✅ Show metadata only in list views
struct LibraryItemMetadata {
    let id: UUID
    let title: String
    let type: ContentType
    let createdAt: Date
    let thumbnailURL: URL? // URL, not loaded image
    let preview: String? // Short text preview
}

// Load full content only when opened
func openItem(_ metadata: LibraryItemMetadata) async {
    let fullContent = await loadFullContent(id: metadata.id)
    // Display full content
}
```

**Image Handling:**
```swift
// ✅ Async load thumbnails
struct ThumbnailView: View {
    let url: URL?
    @State private var image: NSImage?
    
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ProgressView()
            }
        }
        .task {
            image = await ThumbnailCache.shared.load(url: url)
        }
    }
}
```

**Debouncing:**
```swift
// ✅ 300ms delay on search input
@State private var searchText = ""
@State private var debouncedSearchText = ""

var body: some View {
    TextField("Search", text: $searchText)
        .onChange(of: searchText) { _, newValue in
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                if searchText == newValue { // Still the same query
                    debouncedSearchText = newValue
                }
            }
        }
}
```

### Threading

**Main Thread:**
```swift
// ✅ Only UI updates on main thread
@MainActor
func updateUI() {
    self.items = newItems
}

// ❌ Never block main thread
func loadData() {
    let data = heavyComputation() // Freezes UI
    self.items = data
}
```

**Background Threads:**
```swift
// ✅ All heavy work on background
func searchLibrary(query: String) async {
    let results = await Task.detached(priority: .userInitiated) {
        // Heavy database query on background
        return performSearch(query)
    }.value
    
    await MainActor.run {
        self.searchResults = results
    }
}
```

**Combine Pattern:**
```swift
// ✅ Use .receive(on: DispatchQueue.main) for UI updates
searchPublisher
    .debounce(for: 0.3, scheduler: DispatchQueue.main)
    .sink { [weak self] query in
        Task {
            let results = await self?.search(query)
            await MainActor.run {
                self?.searchResults = results ?? []
            }
        }
    }
    .store(in: &cancellables)
```

---

## Window Preview Thumbnails

Cider uses `WindowPreviewService` for window thumbnail capture via private CoreGraphics API `CGSHWCaptureWindowList`. This avoids the Screen Recording permission prompt that `CGWindowListCreateImage` triggers.

```swift
// Actual pattern: private Window Server API (WindowPreviewService.swift)
@_silgen_name("CGSHWCaptureWindowList")
private func CGSHWCaptureWindowList(
    _ cid: CGSConnectionID,
    _ windowIDs: UnsafeMutablePointer<CGWindowID>,
    _ windowCount: UInt32,
    _ options: UInt32
) -> CFArray?

// Capture returns a CFArray of CGImage
guard let imageArray = CGSHWCaptureWindowList(connectionID, &wid, 1, kCGSCaptureIgnoreGlobalClipShape) else {
    return nil
}
```

**Guidelines for window thumbnails:**
- `WindowPreviewService` is a singleton (`WindowPreviewService.shared`) with `startCapturing`/`stopAllStreams` lifecycle
- Captures run on a 0.1s interval loop (10fps) while active
- Black-frame detection rejects mostly-black captures (minimized/hidden windows)
- Freeze/unfreeze API prevents re-capturing windows mid-animation
- Show a placeholder (app icon or SF Symbol) when thumbnail is unavailable

---

## Memory Management

### Avoid Retain Cycles

```swift
// ✅ Weak self in closures
somePublisher.sink { [weak self] value in
    self?.update(value)
}

// ✅ Unowned for non-optional guaranteed references
Timer.scheduledTimer(withTimeInterval: 1.0) { [unowned self] _ in
    self.tick()
}

// ❌ Strong reference creates retain cycle
Timer.scheduledTimer(withTimeInterval: 1.0) { _ in
    self.tick() // Retains self
}
```

### NSCache for Caching

```swift
// ✅ Use NSCache (auto-evicts under memory pressure)
private let thumbnailCache = NSCache<NSURL, NSImage>()

thumbnailCache.countLimit = 100
thumbnailCache.totalCostLimit = 50 * 1024 * 1024 // 50 MB

// ❌ Don't use Dictionary for caching
private var thumbnailCache: [URL: NSImage] = [:] // Never evicts
```

### Dispose of Observers

```swift
// ✅ Cancel subscriptions in deinit
class ViewModel: ObservableObject {
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupPublishers()
    }
    
    deinit {
        cancellables.removeAll()
    }
}
```

### Instruments Profiling

Use Instruments to catch:
- **Leaks**: Retain cycles, abandoned objects
- **Allocations**: Memory growth over time
- **Time Profiler**: CPU bottlenecks
- **SwiftUI**: View rendering performance

---

## Error Handling & Logging

### Service Layer Errors

```swift
enum ConfigError: LocalizedError {
    case decodingFailed
    case fileNotFound(path: String)
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .decodingFailed:
            return "Failed to decode configuration"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .permissionDenied:
            return "Permission denied"
        }
    }
}
```

### Graceful Degradation

```swift
// ✅ Fail gracefully with fallback
func loadThumbnail() -> NSImage {
    guard let image = try? NSImage(contentsOf: url) else {
        return NSImage(systemSymbolName: "doc", accessibilityDescription: nil)!
    }
    return image
}

// ❌ Don't crash on failure
func loadThumbnail() -> NSImage {
    return try! NSImage(contentsOf: url) // Crashes if file missing
}
```

### Logging

Cider currently uses `NSLog` for logging (prefixed with `[Cider]`):

```swift
// ✅ Current pattern
NSLog("[Cider] Config decode error: \(error). Resetting to defaults.")
NSLog("[Cider] Focusing window: \(window.title)")

// ⚠️ print() output is lost when launching with &>/dev/null &
// For debugging, use file-based logging (FileHandle) instead of print()

// Never log sensitive data
// ❌ NSLog("[Cider] User password: \(password)")
```

---

## Accessibility

### VoiceOver Labels

```swift
// ✅ Every interactive element needs a label
Button(action: close) {
    Image(systemName: "xmark")
}
.accessibilityLabel("Close window")

// ✅ Describe complex views
HStack {
    Image(systemName: "bookmark")
    Text(bookmark.title)
}
.accessibilityElement(children: .combine)
.accessibilityLabel("Bookmark: \(bookmark.title)")

// ✅ Add hints for non-obvious actions
Button("Save") { save() }
    .accessibilityLabel("Save note")
    .accessibilityHint("Saves your note to the library")
```

### Keyboard Navigation

```swift
// ✅ Support tab navigation
List(items) { item in
    ItemRow(item)
        .focusable()
}

// ✅ Keyboard shortcuts with VoiceOver announcements
Button("New Note") { createNote() }
    .keyboardShortcut("n", modifiers: .command)
    .accessibilityLabel("New note, Command N")

// ✅ Focus management
@FocusState private var focusedField: Field?

TextField("Title", text: $title)
    .focused($focusedField, equals: .title)
    .onAppear {
        focusedField = .title // Auto-focus
    }
```

### Reduce Motion

```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion

// ✅ Disable animations when reduce motion is on
withAnimation(reduceMotion ? .none : .spring()) {
    isExpanded.toggle()
}

// ✅ Replace parallax with crossfade
if reduceMotion {
    // Static view
} else {
    // Animated view with parallax
}
```

### Color Contrast

```swift
// ✅ Always meet minimum contrast ratios
// Normal text: 4.5:1
// Large text (18pt+): 3:1

// Use system colors (they auto-adjust for high contrast)
Text("Title")
    .foregroundStyle(.primary) // Adapts to high contrast mode

// Test with Xcode Accessibility Inspector
```

### Dynamic Type

```swift
// ✅ Support Dynamic Type
Text("Title")
    .font(.headline) // Scales with user preference

// ✅ Layouts that adapt to size changes
VStack(alignment: .leading, spacing: Spacing.sm) {
    Text("Title")
        .font(.headline)
    Text("Description")
        .font(.body)
}
.fixedSize(horizontal: false, vertical: true) // Allows vertical growth
```

---

## Testing Patterns

> **Note:** No tests exist in the repo yet. When adding tests, use the **Swift Testing** framework (not XCTest):

### ViewModels

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

### Dependency Injection for Testability

```swift
// Make ViewModels testable by injecting dependencies
class WindowListViewModel: ObservableObject {
    private let windowManager: WindowManager

    init(windowManager: WindowManager = WindowManager()) {
        self.windowManager = windowManager
    }

    func refresh() {
        windows = windowManager.fetchWindows()
    }
}

// For mocking, extract a protocol:
protocol WindowManaging {
    func fetchWindows() -> [WindowInfo]
    func focus(window: WindowInfo, stageOthers: Bool)
}
```

---

## App Performance

### Launch Optimization

```swift
// ✅ Defer non-critical initialization
@main
struct CiderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Critical: Set up panels, start detectors immediately
        configureCommandPalette()
        startDoubleTapDetection()

        // Defer: Non-critical setup
        DispatchQueue.global(qos: .utility).async {
            self.setupStatusItem()
        }
    }
}
```

### Asset Optimization

```swift
// ✅ Use SF Symbols when possible (0 bytes, perfect rendering)
Image(systemName: "bookmark")

// ✅ Compress custom images with ImageOptim or similar
// Target: <50 KB per image

// ✅ Use vector PDFs for icons (scale to any size without blur)
Image("custom-icon") // PDF in Assets.xcassets
    .resizable()
    .frame(width: 24, height: 24)
```

### Bundle Size

- Remove unused assets
- Use asset catalogs (auto-optimize for device)
- Enable app thinning
- Avoid bundling large frameworks unnecessarily

---

## Modern Concurrency

### Async/Await

```swift
// ✅ Use async/await for async operations
func captureSnapshots(for windowIDs: [CGWindowID]) async {
    for windowID in windowIDs {
        if let image = captureWindowPrivate(windowID: windowID) {
            previews[windowID] = image
        }
    }
}

// ✅ Call from view with .task
.task {
    await previewService.startCapturing(windowIDs: visibleWindowIDs)
}

// ❌ Old completion handler style (avoid)
func captureSnapshot(windowID: CGWindowID, completion: @escaping (NSImage?) -> Void) {
    // Don't use this pattern anymore
}
```

### Actor for Shared State

> **Note:** Cider doesn't currently use actors, but this is the recommended pattern for future thread-safe shared state.

```swift
// ✅ Use actor for thread-safe state
actor ClipboardHistory {
    private var items: [String] = []

    func add(_ item: String) {
        items.append(item)
    }

    func getRecent(count: Int) -> [String] {
        Array(items.suffix(count))
    }

    func clear() {
        items.removeAll()
    }
}

// Usage (automatically safe)
let history = ClipboardHistory()
await history.add(newItem)
let recent = await history.getRecent(count: 10)
```

### TaskGroup for Concurrent Operations

```swift
// ✅ Load multiple window previews concurrently
func captureAll(windowIDs: [CGWindowID]) async -> [CGWindowID: NSImage] {
    await withTaskGroup(of: (CGWindowID, NSImage?).self) { group in
        for wid in windowIDs {
            group.addTask {
                let image = await WindowPreviewService.shared.captureWindowPrivate(windowID: wid)
                return (wid, image)
            }
        }

        var results: [CGWindowID: NSImage] = [:]
        for await (wid, image) in group {
            if let image {
                results[wid] = image
            }
        }
        return results
    }
}
```

---

## Adding a New Companion Window (Future)

> **Note:** Companion windows are not yet implemented. This section describes the planned pattern for when they are added.

Follow this checklist when adding a new companion window type (e.g., Timer, Checklist):

### 1. Create the Model

```swift
// Models/Timer.swift
struct Timer: Identifiable, Codable {
    let id: UUID
    var duration: TimeInterval
    var remaining: TimeInterval
    var isRunning: Bool
}
```

### 2. Create the ViewModel

```swift
// ViewModels/TimerViewModel.swift
class TimerViewModel: ObservableObject {
    @Published var timer: Timer
    
    init(timer: Timer = Timer(id: UUID(), duration: 300, remaining: 300, isRunning: false)) {
        self.timer = timer
    }
    
    func start() { /* ... */ }
    func pause() { /* ... */ }
    func reset() { /* ... */ }
}
```

### 3. Create the View

```swift
// Views/Companion/TimerWindow.swift
struct TimerWindow: View {
    @StateObject var viewModel: TimerViewModel

    var body: some View {
        VStack(spacing: Spacing.md) {
            headerView
            timerDisplay
            controls
        }
        .frame(width: 200, height: 150)
        .background(PaletteBackgroundView(cornerRadius: Radius.xl))
    }

    private var headerView: some View {
        HStack {
            Image(systemName: "timer")
            Text("Timer")
            Spacer()
            Button(action: { /* close */ }) {
                Image(systemName: "xmark")
            }
        }
        .padding(Spacing.md)
    }
}
```

### 4. Add NSPanel Configuration

```swift
// App/Panels/CompanionPanel.swift
extension CompanionPanel {
    static func timerWindow(timer: Timer) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 150),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false  // We draw our own shadow

        let viewModel = TimerViewModel(timer: timer)
        let hostingView = NSHostingView(rootView: TimerWindow(viewModel: viewModel))

        panel.contentView = hostingView

        return panel
    }
}
```

---

## Constants & Tokens

All constants should be defined in a central location:

```swift
// Utilities/Constants.swift
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}

enum CiderAnimation {
    static let smooth: Animation = .smooth
    static let snappy: Animation = .snappy
    static let bouncy: Animation = .bouncy

    // Reduce Motion: 0.2s opacity crossfade
    static let reduceMotion: Animation = .linear(duration: 0.2)

    // Custom springs
    static let hoverMagnify = Animation.spring(duration: 0.25, bounce: 0.05)
    static let listReorder = Animation.spring(duration: 0.3, bounce: 0.08)
}
```

---

## Code Review Checklist

Before submitting code, verify:

- [ ] No force unwraps (`!`)
- [ ] No hardcoded colors (use semantic colors)
- [ ] No magic numbers (use spacing/sizing tokens)
- [ ] No business logic in views
- [ ] All images load asynchronously
- [ ] Accessibility labels on interactive elements
- [ ] Reduce Motion respected for animations

- [ ] Error handling with graceful fallbacks
- [ ] Memory leaks checked (weak self in closures)
- [ ] Logging added for errors
- [ ] Constants defined centrally

---

**This document is the source of truth for code quality. When in doubt, reference this file.**
