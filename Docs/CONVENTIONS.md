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
let defaultSidebarWidth: CGFloat = 280

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
func loadDatabase() throws -> Database

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
struct SidebarView: View {
    var body: some View {
        VStack {
            // 200 lines of header code
            // 300 lines of list code
            // 150 lines of footer code
        }
    }
}

// ✅ Composed from smaller views
struct SidebarView: View {
    var body: some View {
        VStack(spacing: 0) {
            SidebarHeader()
            SidebarContent()
            SidebarFooter()
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
// ✅ Use defined tokens
withAnimation(CiderAnimation.sidebarSlide) {
    // ...
}

// ❌ Magic numbers
withAnimation(.spring(duration: 0.35, bounce: 0.05)) {
    // ...
}
```

**Respect Reduce Motion:**

```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion

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

### Database

**Index Strategy:**
```swift
// Create indexes on frequently queried columns
CREATE INDEX idx_tags ON items(tags);
CREATE INDEX idx_created_at ON items(created_at);
CREATE INDEX idx_updated_at ON items(updated_at);
CREATE INDEX idx_type ON items(type);
CREATE INDEX idx_context ON items(context);

// Composite index for common filter combinations
CREATE INDEX idx_type_date ON items(type, created_at);
```

**Query Patterns:**
```swift
// ✅ Always use GRDB background queues for searches
func searchLibrary(query: String) async -> [LibraryItem] {
    await dbQueue.read { db in
        try LibraryItem
            .filter(Column("title").like("%\(query)%"))
            .limit(50)
            .fetchAll(db)
    }
}

// ✅ Paginate results
func loadMore(offset: Int, limit: Int = 50) async -> [LibraryItem] {
    await dbQueue.read { db in
        try LibraryItem
            .order(Column("created_at").desc)
            .limit(limit, offset: offset)
            .fetchAll(db)
    }
}

// ❌ Don't load everything at once
let allItems = try LibraryItem.fetchAll(db) // Bad for 10k+ items
```

**Full-Text Search:**
```swift
// Use SQLite FTS5 for content search
CREATE VIRTUAL TABLE items_fts USING fts5(title, content, tags);

// Index for metadata search (faster)
SELECT * FROM items WHERE title LIKE '%query%' LIMIT 50;

// FTS5 for full content search (slower but comprehensive)
SELECT * FROM items_fts WHERE items_fts MATCH 'query' LIMIT 50;
```

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
// ✅ Sidebar shows metadata only
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

## Thumbnail System

### Architecture

Beautiful, fast thumbnails are critical for bookmarks, notes with images, and files. The system must:
1. Generate high-quality thumbnails asynchronously
2. Cache aggressively (memory + disk)
3. Display placeholders instantly
4. Never block the UI

### Thumbnail Service

```swift
actor ThumbnailService {
    static let shared = ThumbnailService()
    
    private let memoryCache = NSCache<NSURL, NSImage>()
    private let diskCacheURL: URL
    private let maxThumbnailSize = CGSize(width: 400, height: 400)
    
    init() {
        diskCacheURL = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cider/Thumbnails")
        
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        
        // Configure memory cache
        memoryCache.countLimit = 100 // 100 thumbnails
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
    }
    
    func getThumbnail(for source: ThumbnailSource) async -> NSImage? {
        // 1. Check memory cache
        if let cached = await checkMemoryCache(source: source) {
            return cached
        }
        
        // 2. Check disk cache
        if let cached = await checkDiskCache(source: source) {
            await storeInMemoryCache(image: cached, source: source)
            return cached
        }
        
        // 3. Generate thumbnail
        guard let generated = await generate(source: source) else {
            return nil
        }
        
        // 4. Store in both caches
        await storeInMemoryCache(image: generated, source: source)
        await storeToDisk(image: generated, source: source)
        
        return generated
    }
    
    private func generate(source: ThumbnailSource) async -> NSImage? {
        switch source {
        case .url(let url):
            return await generateFromURL(url)
        case .file(let path):
            return await generateFromFile(path)
        case .webArchive(let path):
            return await generateFromWebArchive(path)
        }
    }
    
    private func generateFromURL(_ url: URL) async -> NSImage? {
        // Use LinkPresentation for rich Open Graph thumbnails
        let provider = LPMetadataProvider()
        
        do {
            let metadata = try await provider.startFetchingMetadata(for: url)
            
            // Extract image from metadata
            if let imageProvider = metadata.imageProvider {
                return await loadImage(from: imageProvider)
            }
            
            // Fallback: Render the page
            return await renderWebPage(url: url)
        } catch {
            Logger.thumbnails.error("Failed to fetch metadata: \(error)")
            return nil
        }
    }
    
    private func generateFromFile(_ path: URL) async -> NSImage? {
        // Use QLThumbnailGenerator for file thumbnails
        let request = QLThumbnailGenerator.Request(
            fileAt: path,
            size: maxThumbnailSize,
            scale: NSScreen.main?.backingScaleFactor ?? 2.0,
            representationTypes: .thumbnail
        )
        
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateRepresentations(for: request) { thumbnail, _, error in
                if let thumbnail = thumbnail {
                    continuation.resume(returning: thumbnail.nsImage)
                } else {
                    Logger.thumbnails.error("Failed to generate thumbnail: \(error?.localizedDescription ?? "unknown")")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func renderWebPage(url: URL) async -> NSImage? {
        // Last resort: render the page with WebKit
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1200, height: 800))
                webView.load(URLRequest(url: url))
                
                // Wait for load
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    webView.takeSnapshot(with: nil) { image, error in
                        continuation.resume(returning: image)
                    }
                }
            }
        }
    }
    
    private func checkMemoryCache(source: ThumbnailSource) async -> NSImage? {
        let key = source.cacheKey as NSURL
        return memoryCache.object(forKey: key)
    }
    
    private func storeInMemoryCache(image: NSImage, source: ThumbnailSource) async {
        let key = source.cacheKey as NSURL
        memoryCache.setObject(image, forKey: key)
    }
    
    private func checkDiskCache(source: ThumbnailSource) async -> NSImage? {
        let fileURL = diskCacheURL.appendingPathComponent(source.cacheKey + ".png")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return NSImage(contentsOf: fileURL)
    }
    
    private func storeToDisk(image: NSImage, source: ThumbnailSource) async {
        let fileURL = diskCacheURL.appendingPathComponent(source.cacheKey + ".png")
        
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return
        }
        
        try? pngData.write(to: fileURL)
    }
}

enum ThumbnailSource {
    case url(URL)
    case file(URL)
    case webArchive(URL)
    
    var cacheKey: String {
        switch self {
        case .url(let url):
            return url.absoluteString.sha256() // Hash for filename
        case .file(let url):
            return url.path.sha256()
        case .webArchive(let url):
            return url.path.sha256()
        }
    }
}
```

### SwiftUI Integration

```swift
struct ThumbnailView: View {
    let source: ThumbnailSource
    let size: CGSize
    
    @State private var image: NSImage?
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .cornerRadius(8)
            } else if isLoading {
                // Beautiful placeholder
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
                    .frame(width: size.width, height: size.height)
                    .overlay {
                        ProgressView()
                            .controlSize(.small)
                    }
            } else {
                // Fallback icon
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
                    .frame(width: size.width, height: size.height)
                    .overlay {
                        Image(systemName: iconForSource)
                            .font(.system(size: size.width * 0.4))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .task {
            image = await ThumbnailService.shared.getThumbnail(for: source)
            isLoading = false
        }
    }
    
    private var iconForSource: String {
        switch source {
        case .url: return "link"
        case .file: return "doc"
        case .webArchive: return "archivebox"
        }
    }
}
```

### Preloading Strategy

```swift
// Preload thumbnails for visible + next 10 items
class LibraryViewModel: ObservableObject {
    @Published var items: [LibraryItemMetadata] = []
    
    func preloadThumbnails(visibleRange: Range<Int>) {
        let preloadRange = visibleRange.lowerBound..<min(visibleRange.upperBound + 10, items.count)
        
        Task.detached(priority: .low) {
            for index in preloadRange {
                let item = items[index]
                if let thumbnailSource = item.thumbnailSource {
                    _ = await ThumbnailService.shared.getThumbnail(for: thumbnailSource)
                }
            }
        }
    }
}

// Usage in List
List(items) { item in
    ItemRow(item: item)
        .onAppear {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                viewModel.preloadThumbnails(visibleRange: index..<index+1)
            }
        }
}
```

### Thumbnail Quality Guidelines

```swift
struct ThumbnailConstants {
    // Sizes
    static let grid = CGSize(width: 240, height: 180)      // Grid view
    static let list = CGSize(width: 80, height: 60)        // List view
    static let detail = CGSize(width: 400, height: 300)    // Detail view
    
    // Quality
    static let jpegQuality: CGFloat = 0.85
    static let retinaScale: CGFloat = 2.0
    
    // Cache limits
    static let memoryCacheLimit = 100  // thumbnails
    static let diskCacheSizeLimit = 200 * 1024 * 1024  // 200 MB
}
```

### Thumbnail Performance Tips

1. **Always load async** - Never block the main thread
2. **Placeholders first** - Show something immediately
3. **Preload strategically** - Load visible + next 10
4. **Cache aggressively** - Memory + disk caching
5. **Downscale early** - Generate at display size, not full resolution
6. **Use QuickLook** - QLThumbnailGenerator for files (it's fast)
7. **Use LinkPresentation** - For URLs (fetches Open Graph images)
8. **Batch operations** - Load multiple thumbnails concurrently

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
enum StorageError: LocalizedError {
    case databaseLocked
    case fileNotFound(path: String)
    case permissionDenied
    case corruptedData
    
    var errorDescription: String? {
        switch self {
        case .databaseLocked:
            return "Database is locked by another process"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .permissionDenied:
            return "Permission denied"
        case .corruptedData:
            return "Data is corrupted or invalid"
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

```swift
import os.log

extension Logger {
    static let storage = Logger(subsystem: "com.cider", category: "storage")
    static let windowManager = Logger(subsystem: "com.cider", category: "windows")
    static let thumbnails = Logger(subsystem: "com.cider", category: "thumbnails")
    static let ui = Logger(subsystem: "com.cider", category: "ui")
}

// Usage
Logger.storage.info("Saving note: \(note.title)")
Logger.storage.error("Failed to save note: \(error.localizedDescription)")
Logger.windowManager.debug("Focusing window: \(window.title)")

// Never log sensitive data
// ❌ Logger.storage.info("User password: \(password)")
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

### ViewModels

```swift
// Make ViewModels testable by injecting dependencies
class WindowListViewModel: ObservableObject {
    private let windowManager: WindowManaging
    
    init(windowManager: WindowManaging = WindowManager.shared) {
        self.windowManager = windowManager
    }
    
    func refresh() {
        windows = windowManager.getAllWindows()
    }
}

// Protocol for mocking
protocol WindowManaging {
    func getAllWindows() -> [WindowInfo]
    func focusWindow(_ window: WindowInfo)
}

// Test
func testRefresh() {
    let mockManager = MockWindowManager()
    let viewModel = WindowListViewModel(windowManager: mockManager)
    
    viewModel.refresh()
    
    XCTAssertEqual(viewModel.windows.count, 2)
}
```

### Services

```swift
// Test with mock database
func testSaveNote() {
    let mockDB = MockDatabase()
    let service = StorageService(database: mockDB)
    
    let note = Note(title: "Test", content: "Content")
    let result = service.save(note)
    
    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(mockDB.savedNotes.count, 1)
}
```

### Async Testing

```swift
func testAsyncSearch() async throws {
    let viewModel = LibraryViewModel()
    
    await viewModel.search(query: "test")
    
    XCTAssertFalse(viewModel.searchResults.isEmpty)
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
        // Critical: Set up window, show UI immediately
        setupWindow()
        
        // Defer: Background tasks
        DispatchQueue.global(qos: .utility).async {
            self.setupDatabase()
            self.setupClipboardMonitoring()
            self.checkForUpdates()
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
func fetchBookmarkMetadata(url: URL) async throws -> BookmarkMetadata {
    let (data, _) = try await URLSession.shared.data(from: url)
    return try JSONDecoder().decode(BookmarkMetadata.self, from: data)
}

// ✅ Call from view
.task {
    do {
        metadata = try await fetchBookmarkMetadata(url: bookmark.url)
    } catch {
        Logger.ui.error("Failed to fetch metadata: \(error)")
    }
}

// ❌ Old completion handler style (avoid)
func fetchBookmarkMetadata(url: URL, completion: @escaping (Result<BookmarkMetadata, Error>) -> Void) {
    // Don't use this pattern anymore
}
```

### Actor for Shared State

```swift
// ✅ Use actor for thread-safe state
actor ClipboardHistory {
    private var items: [ClipboardItem] = []
    
    func add(_ item: ClipboardItem) {
        items.append(item)
    }
    
    func getRecent(count: Int) -> [ClipboardItem] {
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
// ✅ Load multiple thumbnails concurrently
func loadThumbnails(for items: [LibraryItem]) async -> [UUID: NSImage] {
    await withTaskGroup(of: (UUID, NSImage?).self) { group in
        for item in items {
            group.addTask {
                let thumbnail = await ThumbnailService.shared.getThumbnail(for: item.thumbnailSource)
                return (item.id, thumbnail)
            }
        }
        
        var results: [UUID: NSImage] = [:]
        for await (id, thumbnail) in group {
            if let thumbnail {
                results[id] = thumbnail
            }
        }
        return results
    }
}
```

---

## Adding a New Companion Window

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

### 5. Add to Sidebar

```swift
// Views/Sidebar/QuickCaptureSection.swift
Button(action: { openTimerWindow() }) {
    Label("Timer", systemImage: "timer")
}
```

---

## Constants & Tokens

All constants should be defined in a central location:

```swift
// Utilities/Constants.swift
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

enum CiderAnimation {
    static let sidebarSlide = Animation.spring(duration: 0.35, bounce: 0.05)
    static let hoverMagnify = Animation.spring(duration: 0.2, bounce: 0.1)
    static let listReorder = Animation.spring(duration: 0.4, bounce: 0.05)
}

enum Shadow {
    static let subtle = Shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    static let medium = Shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    static let strong = Shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
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
- [ ] Database queries on background thread
- [ ] Error handling with graceful fallbacks
- [ ] Memory leaks checked (weak self in closures)
- [ ] Logging added for errors
- [ ] Constants defined centrally

---

**This document is the source of truth for code quality. When in doubt, reference this file.**
