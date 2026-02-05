# Cider Tech Stack

> **Read this for tech stack context.** This document covers Swift 6.2, SwiftUI, GRDB, Combine/async-await, and framework-specific patterns for 2025/2026.

---

## Overview

Cider uses a modern, native macOS tech stack optimized for performance, safety, and maintainability:

| Layer | Technology | Version | Why |
|-------|-----------|---------|-----|
| Language | Swift | 6.2+ | Data-race safety, modern concurrency |
| UI Framework | SwiftUI | macOS 14+ | Declarative, performant, native |
| System Integration | AppKit | macOS 14+ | NSPanel, window management, system APIs |
| Concurrency | Swift Concurrency | 6.2+ | Async/await, actors, structured concurrency |
| Reactive | Combine | iOS 14+ | SwiftUI integration, @Published |
| Database | SQLite via GRDB | 7.9+ | Local-first, performant, protocol-oriented |
| State Management | Combine + @Observable | iOS 17+ | Native observation, minimal boilerplate |

---

## Swift 6.2 Language

### Language Mode

**Use Swift 6.2 language mode** with Approachable Concurrency enabled.

```swift
// Swift Settings in Xcode
SWIFT_VERSION = 6.2
SWIFT_STRICT_CONCURRENCY = complete
```

**Why Swift 6.2?**
- **Approachable Concurrency**: Defaults to main actor isolation (like UIKit apps)
- **Data-race safety**: Compile-time checking prevents data races
- **Typed throws**: Type-safe error handling
- **InlineArray**: 20-30% performance improvements for collections
- **Better ergonomics**: Reduced "async contamination" vs Swift 6.0

### Concurrency Model (Approachable Concurrency)

Swift 6.2 introduced `-default-isolation MainActor`, which means **most code runs on the main actor by default** unless you opt into concurrency.

#### Default Isolation Strategy

```swift
// ✅ Default: Runs on main actor
class ViewModel: ObservableObject {
    @Published var items: [Item] = []
    
    func loadData() {
        // Automatically on main actor
        self.items = fetchedItems
    }
}

// ✅ Opt into background execution when needed
class BackgroundWorker {
    nonisolated func heavyComputation() async -> Result {
        // Runs on background
        return performWork()
    }
}

// ✅ Explicit actor for shared state
actor DatabaseManager {
    private var cache: [String: Data] = [:]
    
    func get(_ key: String) -> Data? {
        cache[key]
    }
}
```

#### When to Use Each Pattern

| Pattern | When to Use |
|---------|-------------|
| **Main Actor** (default) | UI updates, ViewModels, most app code |
| **nonisolated** | CPU-intensive work, I/O operations |
| **Actor** | Shared mutable state accessed from multiple contexts |
| **@Sendable closures** | Crossing actor boundaries safely |

### Sendable and Thread Safety

```swift
// ✅ Value types are implicitly Sendable
struct LibraryItem: Sendable {
    let id: UUID
    let title: String
}

// ✅ Final classes with immutable properties
final class Configuration: Sendable {
    let apiKey: String
    let timeout: TimeInterval
    
    init(apiKey: String, timeout: TimeInterval) {
        self.apiKey = apiKey
        self.timeout = timeout
    }
}

// ✅ Classes with @unchecked Sendable (use carefully)
class ThreadSafeCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Any] = [:]
    
    func get(_ key: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }
}

// ❌ Mutable class without Sendable conformance
class UnsafeState { // Will cause warnings in Swift 6
    var items: [String] = []
}
```

### Typed Throws (New in Swift 6)

```swift
// ✅ Type-safe error handling
enum StorageError: Error {
    case databaseLocked
    case fileNotFound
    case permissionDenied
}

func saveNote(_ note: Note) throws(StorageError) {
    // Only StorageError can be thrown
}

// ✅ Caller knows exact error type
do {
    try saveNote(myNote)
} catch {
    // error is StorageError, not generic Error
    switch error {
    case .databaseLocked:
        // Handle specific error
    case .fileNotFound:
        // Handle specific error
    case .permissionDenied:
        // Handle specific error
    }
}
```

### Modern Patterns

```swift
// ✅ if/switch expressions (Swift 5.9+)
let color = if darkMode { .white } else { .black }

let status = switch response.statusCode {
    case 200..<300: "Success"
    case 400..<500: "Client Error"
    case 500..<600: "Server Error"
    default: "Unknown"
}

// ✅ Parameter packs (Swift 5.9+)
func print<each T>(_ value: repeat each T) {
    repeat (print(each value))
}

// ✅ Macro support (Swift 5.9+)
@Observable
class AppState {
    var isLoading = false
    var items: [Item] = []
}
```

---

## SwiftUI (2025/2026 Patterns)

### Current State (iOS 26.2+)

SwiftUI is **now production-ready** (community consensus shifted in 2025):
- 6x faster list loading
- 16x faster updates on macOS
- NSVisualEffectView integration for materials
- New SwiftUI Instrument for performance profiling

### Performance Fundamentals

**Core principle**: Keep view bodies lightweight and pure.

```swift
// ❌ Bad: Heavy computation in body
struct BookRow: View {
    let book: Book
    
    var body: some View {
        HStack {
            // Bad: Formatting every render
            Text(formatDate(book.publishDate))
            Text(calculateDiscount(book.price))
        }
    }
}

// ✅ Good: Precomputed data
struct BookRow: View {
    let book: Book
    let formattedDate: String
    let discountText: String
    
    var body: some View {
        HStack {
            Text(formattedDate)
            Text(discountText)
        }
    }
}
```

### State Management Patterns

```swift
// ✅ Use @Observable (iOS 17+) over @ObservableObject
@Observable
class LibraryViewModel {
    var items: [LibraryItem] = []
    var isLoading = false
    var searchQuery = ""
    
    func search() async {
        isLoading = true
        // Fetch items
        isLoading = false
    }
}

// ✅ Local state with @State
struct NoteEditor: View {
    @State private var title = ""
    @State private var content = ""
    
    var body: some View {
        // ...
    }
}

// ✅ Dependency injection for testability
struct LibraryView: View {
    @State private var viewModel: LibraryViewModel
    
    init(storage: StorageService = .shared) {
        _viewModel = State(initialValue: LibraryViewModel(storage: storage))
    }
}
```

### List Performance

```swift
// ✅ Always use List (virtual scrolling)
List(items) { item in
    ItemRow(item: item)
        .id(item.id) // Stable identity
}

// ✅ Use LazyVStack only when List doesn't fit
ScrollView {
    LazyVStack(spacing: Spacing.md) {
        ForEach(items) { item in
            CustomCard(item: item)
        }
    }
}

// ❌ Never use regular VStack for large lists
ScrollView {
    VStack { // Renders everything at once
        ForEach(items) { item in
            ItemRow(item: item)
        }
    }
}
```

### View Identity and Updates

```swift
// ✅ Stable view types prevent rebuilds
if isLoggedIn {
    Text(userName)
} else {
    Text("Guest")
}

// ❌ Type changes cause expensive rebuilds
if isLoggedIn {
    Text(userName)
} else {
    Image("guest-icon")
}

// ✅ Equatable views skip unnecessary renders
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

### Animation Best Practices

```swift
// ✅ Use spring animations for interactive elements
withAnimation(.spring(duration: 0.3, bounce: 0.05)) {
    isExpanded.toggle()
}

// ✅ Respect Reduce Motion
@Environment(\.accessibilityReduceMotion) var reduceMotion

withAnimation(reduceMotion ? .none : .spring()) {
    scale = 1.1
}

// ❌ Don't animate high-frequency updates
.onChange(of: scrollOffset) { _, newValue in
    // Don't animate on every scroll event
    position = newValue
}

// ❌ Avoid mixing animation and layout changes
withAnimation {
    // Don't do heavy layout changes here
    items.append(contentsOf: newItems)
}
```

### Preview-Driven Development

**Apple's 2025 guidance**: Previews should be central to development workflow.

```swift
struct NoteWindow: View {
    @State private var viewModel: NoteViewModel
    
    init(note: Note) {
        _viewModel = State(initialValue: NoteViewModel(note: note))
    }
    
    var body: some View {
        // ...
    }
}

#Preview("Empty Note") {
    NoteWindow(note: Note(title: "", content: ""))
}

#Preview("With Content") {
    NoteWindow(note: Note(
        title: "Meeting Notes",
        content: "Discussed Q4 strategy..."
    ))
}

#Preview("Dark Mode") {
    NoteWindow(note: Note.sample)
        .preferredColorScheme(.dark)
}
```

### SwiftUI Instrument (WWDC 2025)

**New tool for performance profiling**:
- Visualizes view update causes and effects
- Shows "Long View Body Updates" (orange/red warnings)
- Displays Cause & Effect Graph for data flow

```swift
// Debug view updates
struct ContentView: View {
    @State private var items: [Item] = []
    
    var body: some View {
        List(items) { item in
            ItemRow(item: item)
        }
        ._printChanges() // Shows what triggered re-render
    }
}
```

**Key takeaway**: Use Instruments → SwiftUI template to profile render count, memory, GPU cost.

---

## GRDB (SQLite Database)

### Version & Installation

**Current**: GRDB 7.9.0 (January 2026)
**Requirements**: Swift 6.1+, Xcode 16.3+

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.9.0")
]
```

### Core Principles

GRDB is **protocol-oriented** and **immutable-first**:
- Records are **not uniqued** (unlike Core Data)
- Records **don't auto-update** (you fetch fresh data)
- **Single source of truth**: The database
- **Fat controllers, not fat models**

### Database Setup

```swift
import GRDB

// DatabaseQueue for single-threaded access
let dbQueue = try DatabaseQueue(path: "/path/to/database.sqlite")

// DatabasePool for concurrent access (recommended)
let dbPool = try DatabasePool(path: "/path/to/database.sqlite")

// Migrations
var migrator = DatabaseMigrator()

migrator.registerMigration("v1") { db in
    try db.create(table: "library_item") { t in
        t.primaryKey("id", .text)
        t.column("type", .text).notNull()
        t.column("title", .text).notNull()
        t.column("content", .text)
        t.column("created_at", .datetime).notNull()
        t.column("updated_at", .datetime).notNull()
    }
    
    // Create indexes immediately
    try db.create(index: "idx_type", on: "library_item", columns: ["type"])
    try db.create(index: "idx_created", on: "library_item", columns: ["created_at"])
}

try migrator.migrate(dbQueue)
```

### Record Types (Recommended Pattern)

```swift
struct LibraryItem: Identifiable, Codable {
    var id: UUID
    var type: ContentType
    var title: String
    var content: String?
    var createdAt: Date
    var updatedAt: Date
    
    // Nested Columns enum for type-safe queries
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let type = Column(CodingKeys.type)
        static let title = Column(CodingKeys.title)
        static let content = Column(CodingKeys.content)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }
}

// FetchableRecord: Reading from database
extension LibraryItem: FetchableRecord {
    // Codable conformance provides default implementation
}

// PersistableRecord: Writing to database
extension LibraryItem: PersistableRecord {
    // Codable conformance provides default implementation
}
```

### Modern Query Syntax (GRDB 7.5+)

```swift
// ✅ New Swift 6.1+ syntax with key paths
let items = try dbQueue.read { db in
    try LibraryItem
        .filter { $0.type == "note" }
        .order(\.createdAt)
        .limit(50)
        .fetchAll(db)
}

// ✅ Type-safe column references
let count = try dbQueue.read { db in
    try LibraryItem
        .filter { $0.title.like("%search%") }
        .fetchCount(db)
}

// ❌ Old syntax (still works but verbose)
let items = try dbQueue.read { db in
    try LibraryItem
        .filter(Column("type") == "note")
        .order(Column("created_at"))
        .fetchAll(db)
}
```

### Concurrency Patterns

```swift
// ✅ Async database access (recommended)
actor LibraryDatabase {
    private let dbQueue: DatabaseQueue
    
    init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
    }
    
    func fetchItems(limit: Int) async throws -> [LibraryItem] {
        try await dbQueue.read { db in
            try LibraryItem
                .order(\.createdAt)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    func saveItem(_ item: LibraryItem) async throws {
        try await dbQueue.write { db in
            try item.save(db)
        }
    }
}

// ✅ Background queue for heavy queries
func search(query: String) async -> [LibraryItem] {
    await Task.detached(priority: .userInitiated) {
        try? await dbQueue.read { db in
            try LibraryItem
                .filter { $0.title.like("%\(query)%") }
                .fetchAll(db)
        }
    }.value ?? []
}
```

### Performance Best Practices

```swift
// ✅ Create indexes for common queries
try db.create(index: "idx_tags", on: "items", columns: ["tags"])
try db.create(index: "idx_type_date", on: "items", columns: ["type", "created_at"])

// ✅ Use statement caching
let statement = try db.cachedStatement(sql: "SELECT * FROM items WHERE type = ?")

// ✅ Batch inserts in a single transaction
try dbQueue.write { db in
    for item in largeArray {
        try item.insert(db)
    }
}

// ✅ Use DatabasePool for concurrent reads
let dbPool = try DatabasePool(path: "/path/to/db.sqlite")

// Multiple reads can happen simultaneously
Task {
    let items = try await dbPool.read { db in
        try Item.fetchAll(db)
    }
}
```

### Full-Text Search (FTS5)

```swift
// Create FTS5 table
try db.create(virtualTable: "items_fts", using: FTS5()) { t in
    t.column("title")
    t.column("content")
}

// Populate FTS5 from items table
try db.execute(sql: """
    INSERT INTO items_fts (rowid, title, content)
    SELECT id, title, content FROM items
    """)

// Search with FTS5
let results = try LibraryItem
    .matching(FTS5Pattern(matchingAllTokensIn: "swift database"))
    .fetchAll(db)
```

### ValueObservation (Reactive Queries)

```swift
// Observe database changes
let observation = ValueObservation.tracking { db in
    try LibraryItem
        .filter { $0.type == "note" }
        .fetchAll(db)
}

// Use with Combine
let publisher = observation.publisher(in: dbQueue)
    .receive(on: DispatchQueue.main)

publisher
    .sink { completion in
        // Handle completion
    } receiveValue: { items in
        self.items = items
    }
    .store(in: &cancellables)

// Use with async/await (Swift 6+)
for try await items in observation.values(in: dbQueue) {
    await MainActor.run {
        self.items = items
    }
}
```

---

## Combine vs Async/Await

### Current State (2025/2026)

- **Combine**: No major updates since 2020, but still fully supported
- **Swift Concurrency**: Apple's focus, built into the language
- **Recommendation**: Use async/await for one-shot operations, Combine for streams

### When to Use Each

| Use Case | Use This |
|----------|----------|
| Network request (single value) | async/await |
| Database query (single result) | async/await |
| SwiftUI @Published properties | Combine |
| Observing database changes | Combine (ValueObservation) |
| Stream of user inputs | Combine |
| Multiple concurrent operations | TaskGroup (async/await) |
| Debouncing/throttling | Combine operators |
| Timer-based updates | AsyncStream or Combine |

### Bridging Combine and Async/Await

```swift
// ✅ Convert Combine publisher to async
extension Publisher {
    func async() async throws -> Output where Failure == Error {
        try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            var finishedWithoutValue = true
            
            cancellable = first()
                .sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            if finishedWithoutValue {
                                continuation.resume(throwing: CancellationError())
                            }
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                        cancellable?.cancel()
                    },
                    receiveValue: { value in
                        finishedWithoutValue = false
                        continuation.resume(returning: value)
                    }
                )
        }
    }
}

// Usage
let result = try await somePublisher.async()

// ✅ Convert async function to publisher
extension Future where Failure == Error {
    convenience init(operation: @escaping () async throws -> Output) {
        self.init { promise in
            Task {
                do {
                    let output = try await operation()
                    promise(.success(output))
                } catch {
                    promise(.failure(error))
                }
            }
        }
    }
}

// Usage
func fetchDataPublisher() -> Future<Data, Error> {
    Future {
        try await URLSession.shared.data(from: url).0
    }
}
```

### Combining Approaches in ViewModels

```swift
@Observable
class LibraryViewModel {
    // ✅ @Published for SwiftUI bindings
    var items: [LibraryItem] = []
    var searchQuery = ""
    
    // ✅ Async methods for operations
    func loadItems() async {
        items = await database.fetchItems(limit: 50)
    }
    
    // ✅ Combine for reactive search
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Debounced search with Combine
        $searchQuery
            .debounce(for: 0.3, scheduler: DispatchQueue.main)
            .sink { [weak self] query in
                Task {
                    await self?.performSearch(query)
                }
            }
            .store(in: &cancellables)
    }
    
    private func performSearch(_ query: String) async {
        items = await database.search(query: query)
    }
}
```

---

## AppKit Integration

### NSPanel for Floating Windows

```swift
class CommandPalettePanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Critical: Float above everything without stealing focus
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        // Acrylic style: we draw our own background and shadow
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
    }

    // Allow text input but don't become main window
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
```

### NSHostingView for SwiftUI in AppKit

```swift
let panel = CommandPalettePanel()
let viewModel = CommandPaletteViewModel()
let hostingView = NSHostingView(rootView: CommandPaletteView(viewModel: viewModel))
panel.contentView = hostingView
```

### Window Management (AXUIElement)

```swift
import ApplicationServices

actor WindowManager {
    func getAllWindows() -> [WindowInfo] {
        // Get all running apps
        guard let apps = NSWorkspace.shared.runningApplications as [NSRunningApplication]? else {
            return []
        }
        
        var windows: [WindowInfo] = []
        
        for app in apps {
            guard let axApp = AXUIElementCreateApplication(app.processIdentifier) as AXUIElement? else {
                continue
            }
            
            var windowsRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(
                axApp,
                kAXWindowsAttribute as CFString,
                &windowsRef
            )
            
            guard result == .success,
                  let windowList = windowsRef as? [AXUIElement] else {
                continue
            }
            
            for window in windowList {
                if let info = extractWindowInfo(window, app: app) {
                    windows.append(info)
                }
            }
        }
        
        return windows
    }
    
    func focusWindow(_ window: WindowInfo) {
        guard let axApp = AXUIElementCreateApplication(window.processID) as AXUIElement? else {
            return
        }
        
        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
        
        guard let windowList = windowsRef as? [AXUIElement],
              let targetWindow = windowList.first(where: { /* match window */ }) else {
            return
        }
        
        AXUIElementSetAttributeValue(
            targetWindow,
            kAXMainAttribute as CFString,
            kCFBooleanTrue
        )
        
        NSRunningApplication(processIdentifier: window.processID)?.activate(options: [])
    }
}
```

---

## Testing Patterns

### Swift Testing (New Framework)

```swift
import Testing

@Test("Save note creates file")
func saveNoteCreatesFile() async throws {
    let storage = StorageService(rootPath: tempDirectory)
    let note = Note(title: "Test", content: "Hello")
    
    try await storage.saveNote(note)
    
    #expect(FileManager.default.fileExists(atPath: expectedPath))
}

@Test("Search returns filtered items")
func searchReturnsFilteredItems() async throws {
    let db = try await LibraryDatabase(path: ":memory:")
    
    try await db.saveItem(LibraryItem(title: "Swift Guide", ...))
    try await db.saveItem(LibraryItem(title: "Python Basics", ...))
    
    let results = try await db.search(query: "swift")
    
    #expect(results.count == 1)
    #expect(results[0].title == "Swift Guide")
}
```

### Async Testing

```swift
func testAsyncLoadItems() async throws {
    let viewModel = LibraryViewModel()
    
    await viewModel.loadItems()
    
    #expect(!viewModel.items.isEmpty)
}

// Test cancellation
func testCancellation() async throws {
    let task = Task {
        try await longRunningOperation()
    }
    
    task.cancel()
    
    do {
        _ = try await task.value
        #expect(false, "Should have been cancelled")
    } catch is CancellationError {
        // Expected
    }
}
```

---

## Framework-Specific Guidelines

### Combine

```swift
// ✅ Use @Published for SwiftUI state
@Observable
class ViewModel {
    @Published var items: [Item] = []
    @Published var isLoading = false
}

// ✅ Dispose subscriptions properly
class Service {
    private var cancellables = Set<AnyCancellable>()
    
    deinit {
        cancellables.removeAll()
    }
}

// ✅ Debounce user input
searchTextField.publisher(for: \.stringValue)
    .debounce(for: 0.3, scheduler: DispatchQueue.main)
    .sink { [weak self] query in
        self?.performSearch(query)
    }
    .store(in: &cancellables)

// ❌ Don't store high-frequency values in @Published
@Published var scrollOffset: CGFloat = 0 // Bad: Updates too often
```

### LinkPresentation (Thumbnails)

```swift
import LinkPresentation

func fetchMetadata(for url: URL) async throws -> LPLinkMetadata {
    let provider = LPMetadataProvider()
    return try await provider.startFetchingMetadata(for: url)
}

// Extract thumbnail
if let imageProvider = metadata.imageProvider {
    let image = try await imageProvider.loadObject(ofClass: NSImage.self)
}
```

### Vision (OCR)

```swift
import Vision

func extractText(from image: NSImage) async throws -> String {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw OCRError.invalidImage
    }
    
    return try await withCheckedThrowingContinuation { continuation in
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                continuation.resume(throwing: error)
                return
            }
            
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            continuation.resume(returning: text)
        }
        
        request.recognitionLevel = .accurate
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }
}
```

---

## Migration Paths

### From Combine to Async/Await

```swift
// Before (Combine)
func fetchData() -> AnyPublisher<Data, Error> {
    URLSession.shared.dataTaskPublisher(for: url)
        .map(\.data)
        .eraseToAnyPublisher()
}

// After (async/await)
func fetchData() async throws -> Data {
    let (data, _) = try await URLSession.shared.data(from: url)
    return data
}

// Keep Combine variant for backward compatibility
func fetchDataPublisher() -> AnyPublisher<Data, Error> {
    Future {
        try await self.fetchData()
    }
    .eraseToAnyPublisher()
}
```

### From Swift 5 to Swift 6

```swift
// Enable Swift 6 mode gradually
// 1. Keep Swift 5 mode, enable warnings
SWIFT_VERSION = 5
SWIFT_STRICT_CONCURRENCY = minimal

// 2. Fix warnings, then enable targeted
SWIFT_STRICT_CONCURRENCY = targeted

// 3. Finally, full Swift 6 mode
SWIFT_VERSION = 6
SWIFT_STRICT_CONCURRENCY = complete
```

---

## Performance Checklist

When implementing any feature, verify:

- [ ] Database queries use indexes for common filters
- [ ] SwiftUI Lists use stable `.id()` for items
- [ ] Heavy computations moved out of view bodies
- [ ] Async operations run on background queues
- [ ] @Published properties don't update too frequently
- [ ] Images load asynchronously with caching
- [ ] Animations respect Reduce Motion
- [ ] No force unwrapping in production code
- [ ] Memory leaks checked (weak self in closures)

---

## Resources

### Official Documentation
- [Swift.org - Swift 6 Language Guide](https://docs.swift.org/swift-book/)
- [Apple - SwiftUI Performance](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance)
- [GRDB Documentation](https://github.com/groue/GRDB.swift)

### WWDC Sessions
- WWDC 2025: Optimize SwiftUI performance with Instruments
- WWDC 2024: What's new in Swift 6
- WWDC 2023: Discover Observation in SwiftUI

### Community Resources
- [Swift Forums](https://forums.swift.org/)
- [Swift by Sundell](https://www.swiftbysundell.com/)
- [Hacking with Swift](https://www.hackingwithswift.com/)

---

**Last Updated**: February 2026

**This document reflects the latest Swift 6.2, SwiftUI iOS 26.2, and GRDB 7.9 best practices as of 2026.**
