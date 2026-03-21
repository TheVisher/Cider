# Troubleshooting: Known Issues, Fixes, and Performance Best Practices

> Solutions to layout, sizing, and rendering issues encountered during development. Also includes performance patterns and memory management guidelines. Reference this when similar problems arise.
>
> For tracked code health issues (open and resolved), see [CODE_HEALTH.md](CODE_HEALTH.md).

---

## Card / Thumbnail Sizing Issues

### Problem: Large card sizes prevent panel from shrinking to minimum width

**Symptom:** When the card size slider is at max, the panel cannot be dragged narrower than the card's minimum width. The sidebar won't auto-hide and the window gets stuck at a wide minimum.

**Root cause:** Content minimum width propagates upward through the SwiftUI layout chain. Two sources of width pressure:

1. **Masonry layout's `resolvedLayoutWidth`** floored the layout width at `minimumColumnWidth`:
   ```swift
   // BAD — creates upward width pressure
   return max(minimumColumnWidth, rawWidth)
   ```

2. **NSHostingView's compression resistance** prevented the window from shrinking past the content's ideal width.

**Fix:**
1. In `MasonryLayout.resolvedLayoutWidth`, return `rawWidth` directly (no floor):
   ```swift
   // GOOD — layout accepts whatever width is proposed
   return rawWidth
   ```

2. In `CiderPanelHostingView.viewDidMoveToWindow`, disable sizing options and lower compression resistance:
   ```swift
   sizingOptions = []
   setContentCompressionResistancePriority(.fittingSizeCompression, for: .horizontal)
   setContentCompressionResistancePriority(.fittingSizeCompression, for: .vertical)
   ```

**Key insight:** The panel manages its own sizing via resize handles — the hosting view should never impose minimum size constraints from content.

---

### Problem: Cards don't shrink vertically when panel narrows

**Symptom:** When the panel is narrowed and cards get narrower, the thumbnail area keeps its full height. This creates excessive padding above and below the thumbnail.

**Root cause:** Thumbnail heights were computed from the slider's `CardSizing` values (e.g., `gridThumbnailHeight = 360`), which are fixed regardless of actual card width.

**Fix:** Make thumbnail heights proportional to the card's actual width:

```swift
// Grid mode: proportional to card width
let targetRatio = cardSizing.gridThumbnailHeight / max(cardSizing.cardMinWidth, 1)
return cardWidth * targetRatio

// Masonry mode: use exact image aspect ratio
return cardWidth * aspectRatio
```

**Key insight:** The card and thumbnail should resize as one unified unit. All height calculations should be relative to the actual card width, not the ideal/slider width.

---

### Problem: Masonry thumbnails show padding and sharp corners

**Symptom:** In masonry view, thumbnails have visible card background around them (sharp corners on the image, horizontal/vertical padding between image and card edges).

**Root cause:** Two interacting issues:

1. **`.fit` content mode with min/max clamping:** The masonry thumbnail height was clamped by `masonryThumbnailHeightMin` and `masonryThumbnailHeightMax`. When the clamped height didn't match the image's natural aspect ratio, `.fit` rendered the image smaller than the frame, leaving padding.

2. **Min height floor too aggressive:** The min height (e.g., 300pt at max slider) was taller than many images' natural height at narrow widths. This forced a tall frame that the image couldn't fill with `.fit`.

**Fix:** Remove min and max clamping for masonry. Use the image's exact natural aspect ratio:

```swift
// Before (BAD): clamping causes padding with .fit
let proposedHeight = cardWidth * aspectRatio
return min(max(proposedHeight, masonryMin), masonryMax)

// After (GOOD): exact aspect ratio, no clamping
return cardWidth * aspectRatio
```

**Key insight:** Masonry's purpose is variable-height cards that show full images. Any height clamping creates a mismatch between the frame and the image, causing padding with `.fit` or cropping with `.fill`. Use the pure aspect ratio.

---

### Problem: Portrait images in masonry all have the same height

**Symptom:** Two portrait-oriented cards (e.g., movie posters) appear at identical height even though their images have slightly different aspect ratios. One has horizontal padding.

**Root cause:** Both images hit the same `masonryThumbnailHeightMax` cap. With `.fit`, the wider image gets letterboxed (horizontal padding).

**Fix:** Same as above — remove the max cap. Let each image's aspect ratio determine its card height independently.

---

## View Switching Performance

### Problem: Clicking view mode icons in dropdown has noticeable delay

**Symptom:** Switching between List/Grid/Masonry views from the ViewOptionsDropdown popover feels sluggish with a visible "compression" animation on click.

**Root causes:**

1. **Button press animation:** SwiftUI `Button` inside popovers adds a press animation that delays the action. Use `onTapGesture` instead:
   ```swift
   // BAD — Button adds press chrome
   Button(action: { displayMode = mode }) { ... }

   // GOOD — immediate tap response
   Image(systemName: mode.icon)
       .onTapGesture { displayMode = mode }
   ```

2. **Double ViewModel update:** Setting `displayMode` fires `didSet` which saves config and posts `.ciderConfigChanged`. The notification handler sets `displayMode` again, causing two re-renders:
   ```swift
   // Fix: guard against same-value sets in notification handler
   if self.displayMode != newMode { self.displayMode = newMode }
   ```

3. **Unwanted animation propagation:** The display mode change triggers SwiftUI transition animations. Suppress with:
   ```swift
   var transaction = Transaction()
   transaction.disablesAnimations = true
   withTransaction(transaction) { displayMode = mode }
   ```

---

## Fluid Card Size Slider

### Architecture: CardSizing struct

The card size slider uses a continuous `Double` (0-3) instead of the discrete `BookmarkCardSize` enum. The `LibraryCardSizing` struct interpolates all dimensions:

```swift
struct LibraryCardSizing {
    let scale: Double  // 0 = compact, 1 = comfortable, 2 = large, 3 = extraLarge

    var cardMinWidth: CGFloat { interpolate(196, 240, 340, 520) }
    var gridThumbnailHeight: CGFloat { interpolate(124, 160, 220, 360) }
    // ... other dimensions

    private func interpolate(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
        // Linear interpolation between 4 stops
    }
}
```

**Integration points:**
- `BookmarksViewModel.cardSizeScale: Double` — the source of truth
- `CiderConfig.bookmarksCardSizeScale: Double?` — persistence (optional for migration)
- `ViewOptionsDropdown` — binds to `cardSizeScale` with `Slider(value:in: 0...3)`
- `HomeDashboardView`, `FolderDetailView`, `SavedViewTabContent` — compute `LibraryCardSizing(scale: cardSizeScale)` for card rendering
- `SettingsViewModel` — syncs `bookmarksCardSizeScale` when the discrete `BookmarkCardSize` picker changes

**Key insight:** The `BookmarkCardSize` enum is retained for settings UI (discrete S/M/L/XL picker) and initial migration. The continuous scale is the actual runtime value.

---

## Performance Issues

### Problem: NotesStorage filesystem watcher causes ~100% CPU at idle

**Symptom:** Cider uses ~100% CPU even when idle. Activity Monitor shows the main process pegged. The app becomes unresponsive and fans spin up.

**Root cause:** An infinite feedback loop between `scanNotes()` and the filesystem watcher (`DispatchSource.makeFileSystemObjectSource`).

The watcher monitors the notes directory for changes. When `scanNotes()` runs, it rebuilds the note index and calls `saveIndex()`, which writes `_cider_notes_index.json` into the watched directory. That write triggers the watcher, which calls `scanNotes()` again — infinite loop.

```
scanNotes() → saveIndex() → writes index file → watcher fires → scanNotes() → saveIndex() → ...
```

**Fix:** Make `NoteIndexEntry` conform to `Equatable`, then compare the rebuilt index against the previous snapshot before writing:

```swift
private struct NoteIndexEntry: Codable, Equatable, Sendable {
    var filename: String
    var folderID: UUID?
    var labelIDs: [UUID]?
    var createdAt: Date?
    var sourceURL: String?
    var sourceImageFilename: String?
    var isPinned: Bool?
}

// In scanNotes():
let previousIndex = index
let rebuiltIndex = Dictionary(uniqueKeysWithValues: scannedNotes.map {
    ($0.id, NoteIndexEntry(filename: $0.relativePath, folderID: $0.folderID, createdAt: $0.createdAt))
})
index = rebuiltIndex

if rebuiltIndex != previousIndex {
    saveIndex()
}
```

**Result:** CPU drops from ~100% to 2-5% at idle. The watcher still fires on legitimate external changes (user edits a file outside Cider), but no-op scans no longer trigger a rewrite.

**Key insight:** Any filesystem watcher that writes into its own watched directory must guard against feedback loops. The pattern is: **rebuild state → compare with previous → only write if changed.** This applies to any `DispatchSource` or `FSEvents` watcher that also persists metadata alongside the files it monitors.

**Related test fix:** `NotesStorageRegressionTests` was updated to handle the richer `NoteIndexEntry` object format (previously the index was a flat `[String: String]` dictionary). Uses `JSONSerialization` for flexible decoding instead of `JSONDecoder` with a fixed type.

---

### Watch For: Memory growth with large bookmark/note collections

**Status:** Major bookmark-thumbnail source has been addressed.

**Implemented fix (bookmarks):**
- Dual-asset storage:
  - Full-size image persisted in `.originals/`.
  - Downsampled runtime thumbnail persisted in `.thumbnails/` (PNG).
- Card/list rendering uses the downsampled thumbnail path.
- Existing bookmark images are retroactively normalized on load.

**Observed impact:** Local test run reduced app memory from ~550 MB to ~276 MB after first-run normalization.

**Remaining risk areas:**
1. **SwiftUI lazy container retention** — `LazyVGrid` and masonry layouts keep rendered views in memory longer than expected, especially with variable-height cards. Off-screen cards may not be deallocated promptly.
2. **WKWebView** — the TipTap editor WebView is always alive (singleton pattern). WebKit processes are inherently memory-heavy.

**Thumbnail max-dimension profiles (for future settings toggle):**
- `720px` (current default) — highest quality, higher memory than smaller profiles.
- `512px` — balanced quality/perf.
- `360px` — memory-first profile for very large libraries.

**Suggested future settings label set:**
- `High Quality (720)`
- `Balanced (512)`
- `Memory Saver (360)`

**Still useful mitigation strategies:**
- **`NSCache` for decoded thumbnails** — auto-evicts under memory pressure.
- **Limit prefetch distance** — only load thumbnails for cards within ~2 screens of current viewport.
- **Profile with Instruments** — use Allocations + Leaks to validate real hot spots before further optimization.

**Key insight:** Persisting small display assets separately from originals gives predictable memory behavior while preserving full-quality media for explicit user actions (open/export).

---

### Watch For: Bookmark enrichment spikes during rapid capture

**Status:** Not yet a problem, but relevant when batch-importing or rapid-firing captures.

**Risk:** Each bookmark capture fires network requests for title, favicon, and thumbnail. Rapid captures (e.g., 20 URLs pasted quickly, or a future bulk import) could spike CPU and network simultaneously with unbounded concurrent requests.

**Mitigation:** Use a `TaskGroup` with max concurrency (3-4 simultaneous enrichment tasks). Queue the rest. This smooths out CPU/network load without slowing down the perceived capture speed — the bookmark appears immediately, enrichment fills in progressively.

---

### Watch For: Image decoding on the main thread

**Status:** Resolved. All card types now decode images async on background threads:
- **Bookmarks:** `BookmarkThumbnailView` and `BookmarkDetailsHeroPreview` use `.task(id: fingerprint)` + `Task.detached` + `CGImageSourceCreateWithURL`. Fingerprint combines path + metadataUpdatedAt + remoteURLString.
- **Notes:** `NoteCardData.load()` on `Task.detached` with `CGImageSourceCreateThumbnailAtIndex` (240px max). `resolvedContent` called once, passed to `stripMarkup`/`countWords`/`imageURLs(from:)` to avoid repeated disk I/O.
- **Contacts:** `ContactCardCardView` and `ContactListRow` use `CGImageSourceCreateThumbnailAtIndex` with 120px max dimension inside `Task.detached`.

**Pattern for new image-loading views:**
```swift
.task(id: imageFingerprint) {
    let image = await Task.detached(priority: .userInitiated) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }.value
    guard !Task.isCancelled else { return }
    self.displayImage = image
}
```

---

### Watch For: Search performance at scale

**Status:** Fine at current collection size. Monitor past ~300-500 items.

**Risk:** If search filters by iterating the full in-memory array on every keystroke, it'll feel sluggish with large collections. Each character triggers a full scan, and SwiftUI re-renders the filtered results on every pass.

**Mitigation:**
- **Debounce search input** (200-300ms) so filtering only runs after the user pauses typing, not on every character.
- **Pre-build a lightweight search index** if debouncing alone isn't enough — a simple inverted index of title/domain words mapped to item IDs.
- **Cancel in-flight searches** when new input arrives (use `Task` cancellation).

---

### Watch For: Redundant SwiftUI re-renders from @Published properties

**Status:** Not a problem at current scale. Becomes relevant past ~200-300 visible cards.

**Risk:** With `@Published` on ViewModels, changing any property re-renders all subscribers. If a ViewModel has many published properties, an unrelated change (e.g., updating a loading flag) triggers card re-renders across the entire grid even though card data didn't change.

**Mitigation:**
- Add `Equatable` conformance to card data structs — SwiftUI can skip diffing unchanged cards.
- Use the existing `didSet` guard pattern (`if self.value != newValue`) to prevent redundant `@Published` updates, especially in notification handlers.
- Long-term: migrating to `@Observable` (Swift Observation framework) gives per-property tracking instead of whole-object invalidation. Not urgent.

---

## Performance Best Practices

> Moved from CONVENTIONS.md. These are patterns to follow when writing new code.

### SwiftUI Optimization

**List Virtualization:**
```swift
// GOOD: Use List (auto-virtualizes, only renders visible rows)
List(items) { item in
    ItemRow(item: item)
}

// BAD: ScrollView + ForEach (renders everything)
ScrollView {
    ForEach(items) { item in
        ItemRow(item: item)
    }
}
```

**View Identity:**
```swift
// GOOD: Use explicit .id() for reorderable items
List(items) { item in
    ItemRow(item: item)
        .id(item.id)
}
```

**Equatable Views:**
```swift
// GOOD: Implement Equatable for complex row content
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
// BAD: Don't @Published entire large arrays
class ViewModel: ObservableObject {
    @Published var allItems: [LibraryItem] = [] // Triggers full UI rebuild on any change
}

// GOOD: Use fine-grained updates
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
// GOOD: Show metadata only in list views
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
// GOOD: Async load thumbnails
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
// GOOD: 300ms delay on search input
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
// GOOD: Only UI updates on main thread
@MainActor
func updateUI() {
    self.items = newItems
}

// BAD: Never block main thread
func loadData() {
    let data = heavyComputation() // Freezes UI
    self.items = data
}
```

**Background Threads:**
```swift
// GOOD: All heavy work on background
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
// GOOD: Use .receive(on: DispatchQueue.main) for UI updates
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

### Memory Management

**Avoid Retain Cycles:**
```swift
// GOOD: Weak self in closures
somePublisher.sink { [weak self] value in
    self?.update(value)
}

// GOOD: Unowned for non-optional guaranteed references
Timer.scheduledTimer(withTimeInterval: 1.0) { [unowned self] _ in
    self.tick()
}

// BAD: Strong reference creates retain cycle
Timer.scheduledTimer(withTimeInterval: 1.0) { _ in
    self.tick() // Retains self
}
```

**NSCache for Caching:**
```swift
// GOOD: Use NSCache (auto-evicts under memory pressure)
private let thumbnailCache = NSCache<NSURL, NSImage>()

thumbnailCache.countLimit = 100
thumbnailCache.totalCostLimit = 50 * 1024 * 1024 // 50 MB

// BAD: Don't use Dictionary for caching
private var thumbnailCache: [URL: NSImage] = [:] // Never evicts
```

**Dispose of Observers:**
```swift
// GOOD: Cancel subscriptions in deinit
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

**Instruments Profiling:**

Use Instruments to catch:
- **Leaks**: Retain cycles, abandoned objects
- **Allocations**: Memory growth over time
- **Time Profiler**: CPU bottlenecks
- **SwiftUI**: View rendering performance

### App Launch & Assets

**Launch Optimization:**
```swift
// GOOD: Defer non-critical initialization
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

**Asset Optimization:**
```swift
// GOOD: Use SF Symbols when possible (0 bytes, perfect rendering)
Image(systemName: "bookmark")

// GOOD: Compress custom images with ImageOptim or similar
// Target: <50 KB per image

// GOOD: Use vector PDFs for icons (scale to any size without blur)
Image("custom-icon") // PDF in Assets.xcassets
    .resizable()
    .frame(width: 24, height: 24)
```

**Bundle Size:**
- Remove unused assets
- Use asset catalogs (auto-optimize for device)
- Enable app thinning
- Avoid bundling large frameworks unnecessarily

### Modern Concurrency

**Async/Await:**
```swift
// GOOD: Use async/await for async operations
func captureSnapshots(for windowIDs: [CGWindowID]) async {
    for windowID in windowIDs {
        if let image = captureWindowPrivate(windowID: windowID) {
            previews[windowID] = image
        }
    }
}

// GOOD: Call from view with .task
.task {
    await previewService.startCapturing(windowIDs: visibleWindowIDs)
}

// BAD: Old completion handler style (avoid)
func captureSnapshot(windowID: CGWindowID, completion: @escaping (NSImage?) -> Void) {
    // Don't use this pattern anymore
}
```

**Actor for Shared State:**

> **Note:** Cider doesn't currently use actors, but this is the recommended pattern for future thread-safe shared state.

```swift
// GOOD: Use actor for thread-safe state
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

**TaskGroup for Concurrent Operations:**
```swift
// GOOD: Load multiple window previews concurrently
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

## General Layout Principles

1. **Content should never demand more width than proposed.** Layouts should accept whatever width they're given and adapt (fewer columns, smaller items). Never floor a layout width at a content-derived minimum.

2. **Thumbnail heights should be proportional to card width.** Fixed heights from a sizing struct only work when cards are at their ideal width. When the container is narrower, heights must scale proportionally.

3. **Masonry should use exact aspect ratios.** No min/max clamping — let each image's natural shape determine its card height. Clamping creates mismatches that cause padding (with `.fit`) or cropping (with `.fill`).

4. **Use `.fit` for masonry, `.fill` for grid.** Masonry shows full images at natural aspect ratios. Grid crops images to uniform height for a clean grid.

5. **Use `onTapGesture` instead of `Button` in popovers.** Button's press animation adds delay and visual noise inside dropdown menus. `onTapGesture` fires immediately.

6. **Guard against same-value ViewModel updates.** When a `didSet` handler posts a notification that triggers the same property to be set again, add `if self.value != newValue` guards to prevent double re-renders.

7. **All images in scrollable views must load async.** Use `.task(id:)` with `Task.detached` and `CGImageSource` decoding on a background thread. Never call `NSImage(contentsOfFile:)` or `NSImage(data:)` on the main thread during scroll — it causes frame drops in masonry/grid views.

8. **Never call `CiderConfig.load()` in view body or computed properties.** Use cached paths (`StoragePaths.cachedVaultDirectoryURL`) or `@State config` instead. Each `CiderConfig.load()` does a UserDefaults read + JSONDecoder decode.
