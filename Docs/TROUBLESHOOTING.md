# Troubleshooting: Known Issues and Fixes

> Solutions to layout, sizing, and rendering issues encountered during development. Reference this when similar problems arise.

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
1. In `BookmarkMasonryLayout.resolvedLayoutWidth`, return `rawWidth` directly (no floor):
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

The card size slider uses a continuous `Double` (0-3) instead of the discrete `BookmarkCardSize` enum. The `CardSizing` struct interpolates all dimensions:

```swift
struct CardSizing {
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
- `BookmarksBrowserView` — computes `CardSizing(scale: cardSizeScale)` for all card rendering
- `SettingsViewModel` — syncs `bookmarksCardSizeScale` when the discrete `BookmarkCardSize` picker changes

**Key insight:** The `BookmarkCardSize` enum is retained for settings UI (discrete S/M/L/XL picker) and initial migration. The continuous scale is the actual runtime value.

---

## Performance

### Problem: NotesStorage filesystem watcher causes ~100% CPU at idle

**Symptom:** Cider uses ~100% CPU even when idle. Activity Monitor shows the main process pegged. The app becomes unresponsive and fans spin up.

**Root cause:** An infinite feedback loop between `scanNotes()` and the filesystem watcher (`DispatchSource.makeFileSystemObjectSource`).

The watcher monitors the notes directory for changes. When `scanNotes()` runs, it rebuilds the note index and calls `saveIndex()`, which writes `_cider_notes_index.json` into the watched directory. That write triggers the watcher, which calls `scanNotes()` again — infinite loop.

```
scanNotes() → saveIndex() → writes index file → watcher fires → scanNotes() → saveIndex() → ...
```

**Fix:** Make `NoteIndexEntry` conform to `Equatable`, then compare the rebuilt index against the previous snapshot before writing:

```swift
private struct NoteIndexEntry: Codable, Equatable {
    let filename: String
    let folderID: UUID?
    let createdAt: Date
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

**Status:** Not yet a problem, but worth monitoring as collections grow.

**Current baseline:** ~270 MB with a small collection. Comparable to Messages (~249 MB), higher than typical utility apps (~140-175 MB). The WKWebView singleton for TipTap accounts for a chunk of this.

**Known risk areas:**

1. **Bookmark thumbnails** — if held at full resolution in memory, a large collection will balloon quickly. Notes already downsample to 240px via `CGImageSource` — bookmarks should follow the same pattern.
2. **SwiftUI lazy container retention** — `LazyVGrid` and masonry layouts keep rendered views in memory longer than expected, especially with variable-height cards. Off-screen cards may not be deallocated promptly.
3. **WKWebView** — the TipTap editor WebView is always alive (singleton pattern). WebKit processes are inherently memory-heavy.

**Mitigation strategies when this becomes an issue:**

- **`NSCache` for thumbnails** — auto-evicts under system memory pressure. Reload from disk on cache miss. This is the single biggest win.
- **Downsample bookmark thumbnails on save** — store a 240-360px version on disk, never load the full-resolution image into the card grid.
- **Limit prefetch distance** — only load thumbnails for cards within ~2 screens of the current scroll position.
- **Profile with Instruments** — use the Allocations and Leaks instruments to identify the actual top consumers before optimizing. Don't guess.

**Key insight:** Native Swift has the tools (`NSCache`, `CGImageSource` downsampling, `autoreleasepool` for batch operations) — the framework handles memory pressure gracefully as long as you use these patterns. The app should scale to hundreds of bookmarks without issue if thumbnails are properly managed.

---

### Watch For: Bookmark enrichment spikes during rapid capture

**Status:** Not yet a problem, but relevant when batch-importing or rapid-firing captures.

**Risk:** Each bookmark capture fires network requests for title, favicon, and thumbnail. Rapid captures (e.g., 20 URLs pasted quickly, or a future bulk import) could spike CPU and network simultaneously with unbounded concurrent requests.

**Mitigation:** Use a `TaskGroup` with max concurrency (3-4 simultaneous enrichment tasks). Queue the rest. This smooths out CPU/network load without slowing down the perceived capture speed — the bookmark appears immediately, enrichment fills in progressively.

---

### Watch For: Image decoding on the main thread

**Status:** Notes handle this correctly via async `NoteCardData.load()`. Bookmarks should follow the same pattern.

**Risk:** If bookmark thumbnails are decoded on the main thread during scroll, frame drops will appear in masonry/grid views — especially with large images or fast scrolling. The symptom is visible jank or stuttering when scrolling through cards.

**Mitigation:**
- Decode and downsample via `CGImageSource` on a background queue.
- Dispatch the final downsampled `NSImage`/`CGImage` back to main for display.
- Notes already do this — bookmarks should follow the same `async` loading pattern.

**Priority:** High. This is the single most likely source of scroll jank as the collection grows. Fix this before other optimizations.

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

## General Layout Principles

1. **Content should never demand more width than proposed.** Layouts should accept whatever width they're given and adapt (fewer columns, smaller items). Never floor a layout width at a content-derived minimum.

2. **Thumbnail heights should be proportional to card width.** Fixed heights from a sizing struct only work when cards are at their ideal width. When the container is narrower, heights must scale proportionally.

3. **Masonry should use exact aspect ratios.** No min/max clamping — let each image's natural shape determine its card height. Clamping creates mismatches that cause padding (with `.fit`) or cropping (with `.fill`).

4. **Use `.fit` for masonry, `.fill` for grid.** Masonry shows full images at natural aspect ratios. Grid crops images to uniform height for a clean grid.

5. **Use `onTapGesture` instead of `Button` in popovers.** Button's press animation adds delay and visual noise inside dropdown menus. `onTapGesture` fires immediately.

6. **Guard against same-value ViewModel updates.** When a `didSet` handler posts a notification that triggers the same property to be set again, add `if self.value != newValue` guards to prevent double re-renders.
