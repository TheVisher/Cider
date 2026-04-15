# Cider Performance Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the visible performance issues — slow thumbnail loading, laggy detail slideout, and animation jank — by adding a shared image cache, deferring expensive web preloads, and reducing competing animation work.

**Architecture:** Six tasks in two phases. **Phase 1** (Tasks 1-4) targets the three most visible symptoms: blank thumbnails, slideout click lag, competing window/panel animations, and blur cost. **Phase 2** (Tasks 5-6) is conditional — only proceed after measuring Phase 1 results. A backlog item (note search main-thread I/O) is documented but not scheduled.

**Execution order:** 1 → 2 → 3 → 4 → **re-measure** → conditionally 5 and/or 6

**Tech Stack:** Swift, SwiftUI, AppKit (NSImage, NSCache), CoreGraphics

**Important codebase rules:**
- No hardcoded colors — use `CiderColors.*` from Constants.swift
- No hardcoded fonts — use `CiderFont.*` from CiderFont.swift
- Spring animations only — no `.easeIn`, `.easeOut`, `.linear`
- Respect Reduce Motion — `reduceMotion ? .none : .spring` on every animation
- Use `os.Logger` — not `print()`
- Build command: `swift build -Xswiftc -warnings-as-errors`

---

## Execution Phases

### Phase 1 — Core fixes (implement all four)

| Task | What | Why |
|------|------|-----|
| 1 | Create `BookmarkThumbnailCache` singleton | Foundation for Task 2 |
| 2 | Wire cache into all 4 thumbnail decode sites | Fixes blank-card flicker on library load |
| 3 | Defer web/reader preload 350ms after slideout | Fixes click-to-slideout lag |
| 4 | Remove animated window resize on slideout open | Eliminates competing AppKit + SwiftUI animations |

### Phase 2 — Conditional (measure first)

| Task | What | Conditions |
|------|------|------------|
| 5 | Add `.compositingGroup()` before blur | Only if slideout blur still feels heavy after Phase 1. Measure first — `compositingGroup()` trades CPU layout cost for an offscreen render pass and higher memory bandwidth, so it's not a guaranteed win. |
| 6 | Remove GeometryReader from BookmarkCard | Only if grid/masonry rendering is still noticeably slow after Phase 1. High regression risk — changes how card width flows through the view hierarchy, can break masonry/grid thumbnail height calculations. |

### Backlog (not in this plan)

- **Note search main-thread I/O:** `LibraryViewModel.matchesTextQuery()` calls `NotesStorage.loadContent()` synchronously on the main actor for note items. There's a content cache that mitigates repeat hits, but first-search-after-vault-change with many notes still does proportional synchronous file I/O on the main thread. This becomes another source of perceived lag once thumbnail/slideout fixes land. Track separately.
- **Consolidate `.animation()` modifiers on CiderPanelView.body:** 7 separate `.animation()` modifiers (lines 174-180) all using `.snappy`. Could collapse to 2, but unlikely to move the performance needle compared to caching and preload deferral. Low priority cleanup.

---

## File Map

| File | Action | Task | Purpose |
|------|--------|------|---------|
| `Sources/Cider/Services/BookmarkThumbnailCache.swift` | **Create** | 1 | Shared NSCache singleton for bookmark thumbnails |
| `Sources/Cider/Views/Bookmarks/BookmarkThumbnailView.swift` | **Modify** | 2 | Use shared cache in `loadThumbnailAsync()` and `CarouselPageImage` |
| `Sources/Cider/Views/Bookmarks/BookmarkDetailsDraft.swift` | **Modify** | 2 | Use shared cache in `BookmarkDetailsHeroPreview.loadThumbnailAsync()` |
| `Sources/Cider/Views/Shared/LibraryTableRow.swift` | **Modify** | 2 | Use shared cache in `BookmarkTableIcon.loadFavicon()` |
| `Sources/Cider/Views/CiderPanelView+DetailManagement.swift` | **Modify** | 3 | Remove eager `detailWebViewStore.preload()` from click path |
| `Sources/Cider/Views/Shared/DetailSlideOutView.swift` | **Modify** | 3 | Remove redundant `onAppear` preload, defer `onChange` preload |
| `Sources/Cider/App/AppDelegate+CiderPanel.swift` | **Modify** | 4 | Instant window expand, no animated resize |
| `Sources/Cider/Views/Shared/CiderPanelShell.swift` | **Modify** | 5 | Add `compositingGroup()` before blur (conditional) |
| `Sources/Cider/Views/Bookmarks/BookmarkCard.swift` | **Modify** | 6 | Remove GeometryReader, pass width from parent (conditional) |

---

## Phase 1 Tasks

### Task 1: Create BookmarkThumbnailCache

A shared `NSCache`-backed singleton for bookmark thumbnail images, modeled after the existing `VaultFileThumbnailCache` in `VaultFileCardView.swift:6-25`.

**Files:**
- Create: `Sources/Cider/Services/BookmarkThumbnailCache.swift`

- [ ] **Step 1: Create the cache singleton**

```swift
import AppKit

/// Shared in-process cache for bookmark thumbnail images.
/// Prevents re-decoding the same JPEG/PNG from disk every time a card,
/// table row, detail hero, or carousel page appears.
@MainActor
final class BookmarkThumbnailCache {
    static let shared = BookmarkThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()

    init() { cache.countLimit = 300 }

    /// Cache key combines the file path and modification timestamp so stale
    /// entries auto-invalidate when the thumbnail file changes on disk.
    func get(_ filePath: String, modifiedAt: TimeInterval) -> NSImage? {
        let key = "\(filePath):\(modifiedAt)" as NSString
        return cache.object(forKey: key)
    }

    func set(_ image: NSImage, for filePath: String, modifiedAt: TimeInterval) {
        let key = "\(filePath):\(modifiedAt)" as NSString
        cache.setObject(image, forKey: key)
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build -Xswiftc -warnings-as-errors 2>&1 | tail -5`
Expected: Build Succeeded (or existing unrelated warnings)

- [ ] **Step 3: Commit**

```bash
git add Sources/Cider/Services/BookmarkThumbnailCache.swift
git commit -m "feat: add shared BookmarkThumbnailCache singleton"
```

---

### Task 2: Wire the cache into all bookmark thumbnail decode sites

There are 4 independent decode paths that each read from disk every time a view appears. Wire them all through `BookmarkThumbnailCache.shared`.

**Files:**
- Modify: `Sources/Cider/Views/Bookmarks/BookmarkThumbnailView.swift:182-224` (main thumbnail)
- Modify: `Sources/Cider/Views/Bookmarks/BookmarkThumbnailView.swift:358-393` (CarouselPageImage)
- Modify: `Sources/Cider/Views/Bookmarks/BookmarkDetailsDraft.swift:895-909` (hero preview)
- Modify: `Sources/Cider/Views/Shared/LibraryTableRow.swift:286-296` (table favicon)

- [ ] **Step 1: Update BookmarkThumbnailView.loadThumbnailAsync()**

In `BookmarkThumbnailView.swift`, modify `loadThumbnailAsync()` (line 182) to check the cache before decoding and store results after decoding. The cache key uses `thumbnailFileURL.path` and `metadataUpdatedAt`.

Replace the current `loadThumbnailAsync` method (lines 182-225) with:

```swift
private func loadThumbnailAsync() async {
    guard let fileURL = bookmark.thumbnailFileURL else {
        thumbnailImage = nil
        rendersAsIconOverlay = false
        onAspectRatioResolved?(nil)
        return
    }

    let remoteURLString = bookmark.thumbnailRemoteURLString
    let cacheKey = fileURL.path
    let modifiedAt = bookmark.metadataUpdatedAt?.timeIntervalSince1970 ?? -1

    // Check shared cache first
    if let cached = BookmarkThumbnailCache.shared.get(cacheKey, modifiedAt: modifiedAt) {
        let width = cached.size.width
        let height = cached.size.height
        let isIcon = Self.shouldRenderAsIconOverlay(
            width: width, height: height, remoteURLString: remoteURLString
        )
        thumbnailImage = cached
        rendersAsIconOverlay = isIcon
        onAspectRatioResolved?(isIcon ? nil : height / width)
        return
    }

    let result: (NSImage, Bool, CGFloat?)? = await Task.detached(priority: .userInitiated) {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width > 0, height > 0 else { return nil }

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))

        let isIconOverlay = BookmarkThumbnailView.shouldRenderAsIconOverlay(
            width: width, height: height, remoteURLString: remoteURLString
        )
        let aspectRatio: CGFloat? = isIconOverlay ? nil : height / width

        return (nsImage, isIconOverlay, aspectRatio)
    }.value

    guard !Task.isCancelled else { return }

    if let (image, isIcon, aspectRatio) = result, !shouldSuppressDownloadedThumbnail {
        BookmarkThumbnailCache.shared.set(image, for: cacheKey, modifiedAt: modifiedAt)
        thumbnailImage = image
        rendersAsIconOverlay = isIcon
        onAspectRatioResolved?(aspectRatio)
    } else {
        thumbnailImage = nil
        rendersAsIconOverlay = false
        onAspectRatioResolved?(nil)
    }
}
```

- [ ] **Step 2: Update CarouselPageImage.loadImage()**

In `BookmarkThumbnailView.swift`, modify the `CarouselPageImage` struct's `loadImage()` method (line 380) to use the cache. The carousel uses a URL as its key.

Replace `loadImage()` (lines 380-393) with:

```swift
private func loadImage() async -> NSImage? {
    let cacheKey = url.path
    let modifiedAt = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0

    if let cached = BookmarkThumbnailCache.shared.get(cacheKey, modifiedAt: modifiedAt) {
        return cached
    }

    let result: NSImage? = await Task.detached(priority: .userInitiated) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        guard w > 0, h > 0 else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: w, height: h))
    }.value

    if let image = result {
        BookmarkThumbnailCache.shared.set(image, for: cacheKey, modifiedAt: modifiedAt)
    }
    return result
}
```

- [ ] **Step 3: Update BookmarkDetailsHeroPreview.loadThumbnailAsync()**

In `BookmarkDetailsDraft.swift`, modify `loadThumbnailAsync()` (line 895) to check and populate the cache.

Replace lines 895-909 with:

```swift
private func loadThumbnailAsync() async {
    guard let fileURL = bookmark?.thumbnailFileURL else {
        thumbnailImage = nil
        return
    }

    let cacheKey = fileURL.path
    let modifiedAt = bookmark?.metadataUpdatedAt?.timeIntervalSince1970 ?? -1

    if let cached = BookmarkThumbnailCache.shared.get(cacheKey, modifiedAt: modifiedAt) {
        thumbnailImage = cached
        return
    }

    let image: NSImage? = await Task.detached(priority: .userInitiated) {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }.value

    guard !Task.isCancelled else { return }

    if let image {
        BookmarkThumbnailCache.shared.set(image, for: cacheKey, modifiedAt: modifiedAt)
        thumbnailImage = image
    } else {
        thumbnailImage = nil
    }
}
```

- [ ] **Step 4: Update BookmarkTableIcon.loadFavicon()**

In `LibraryTableRow.swift`, modify `loadFavicon()` (line 286) to check and populate the cache. Note: the table icon uses `kCGImageSourceThumbnailMaxPixelSize: 40` for a smaller decode — use a separate cache key suffix to avoid serving a 40px image to a full-size card.

Replace lines 286-296 with:

```swift
private func loadFavicon() async -> NSImage? {
    guard let url = bookmark.thumbnailFileURL else { return nil }

    let cacheKey = url.path + ":favicon"
    let modifiedAt = bookmark.metadataUpdatedAt?.timeIntervalSince1970 ?? -1

    if let cached = BookmarkThumbnailCache.shared.get(cacheKey, modifiedAt: modifiedAt) {
        return cached
    }

    let result: NSImage? = await Task.detached(priority: .utility) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 40,
              ] as CFDictionary) else { return nil as NSImage? }
        return NSImage(cgImage: cgImage, size: NSSize(width: 20, height: 20))
    }.value

    if let image = result {
        BookmarkThumbnailCache.shared.set(image, for: cacheKey, modifiedAt: modifiedAt)
    }
    return result
}
```

- [ ] **Step 5: Build and verify**

Run: `swift build -Xswiftc -warnings-as-errors 2>&1 | tail -5`
Expected: Build Succeeded

- [ ] **Step 6: Commit**

```bash
git add Sources/Cider/Views/Bookmarks/BookmarkThumbnailView.swift Sources/Cider/Views/Bookmarks/BookmarkDetailsDraft.swift Sources/Cider/Views/Shared/LibraryTableRow.swift
git commit -m "perf: wire all bookmark thumbnail decodes through shared cache"
```

---

### Task 3: Defer web/reader preload until after slideout animation

The current flow calls `detailWebViewStore.preload()` synchronously inside `openBookmarkDetails()`, which creates 2 WKWebViews + fires a URLSession request on the click path. Then `DetailSlideOutView.onChange(of: bookmark?.id)` resets and preloads again, and `onAppear` preloads a third time. Fix: remove the eager preload from `openBookmarkDetails()`, remove the redundant `onAppear` preload, and add a small delay in `onChange` so the animation settles first.

**Files:**
- Modify: `Sources/Cider/Views/CiderPanelView+DetailManagement.swift:65-81`
- Modify: `Sources/Cider/Views/Shared/DetailSlideOutView.swift:178-202`

- [ ] **Step 1: Remove eager preload from openBookmarkDetails()**

In `CiderPanelView+DetailManagement.swift`, remove the `detailWebViewStore.reset()` call and the preload block from `openBookmarkDetails()`. The detail view's `onChange` will handle it.

Replace lines 77-81 (from `detailWebViewStore.reset()` through the closing brace of the preload block):

```swift
        // Don't preload here — DetailSlideOutView.onChange handles it after animation settles
```

Keep everything else in the function exactly as-is (the `isSearchPaletteVisible`, `isNoteDetailOpen`, `detailBookmarkID`, `detailsDraft`, `detailsErrorMessage`, `bookmarkHeroMode`, notification post, and AI context update lines all stay).

- [ ] **Step 2: Remove redundant onAppear preload from DetailSlideOutView**

In `DetailSlideOutView.swift`, remove the preload from the `onAppear` block (lines 194-198). Keep the `sidebarTransitionEnabled` logic.

Replace lines 194-202 with:

```swift
        .onAppear {
            // Enable the sidebar's own transition only after the first render,
            // so it doesn't compound with the parent panel's slide-in animation.
            DispatchQueue.main.async { sidebarTransitionEnabled = true }
        }
```

- [ ] **Step 3: Add delay to onChange preload so animation settles first**

In `DetailSlideOutView.swift`, modify the `onChange(of: bookmark?.id)` block (lines 178-193) to delay the preload by 0.35 seconds (matching the slideout animation duration).

Replace lines 178-193 with:

```swift
        .onChange(of: bookmark?.id) { _, newID in
            webViewIsLoading = false
            webViewStore.reset()
            // Restore per-bookmark hero mode and reader availability
            if let bm = newID.flatMap({ id in VaultBookmarkService.shared.bookmarks.first { $0.id == id } }) {
                let isReaderUnavailable = bm.readerUnavailable == true
                let restored = bm.preferredHeroMode.flatMap(BookmarkHeroMode.init(rawValue:)) ?? .thumbnail
                heroMode = (restored == .reader && isReaderUnavailable) ? .thumbnail : restored
                // Defer preload until after slideout animation settles
                if bm.hasURL, let url = bm.url {
                    let bookmarkID = bm.id
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        guard !Task.isCancelled else { return }
                        webViewStore.preload(url: url, bookmarkID: bookmarkID)
                    }
                }
            } else {
                heroMode = .thumbnail
            }
        }
```

- [ ] **Step 4: Build and verify**

Run: `swift build -Xswiftc -warnings-as-errors 2>&1 | tail -5`
Expected: Build Succeeded

- [ ] **Step 5: Commit**

```bash
git add Sources/Cider/Views/CiderPanelView+DetailManagement.swift Sources/Cider/Views/Shared/DetailSlideOutView.swift
git commit -m "perf: defer web/reader preload until after slideout animation settles"
```

---

### Task 4: Remove animated window resize on slideout open

Currently `expandCiderPanelForSlideOut` animates the window width with `NSAnimationContext` (0.3s) at the same time the SwiftUI slideout transition runs. This causes two competing animations. Fix: expand the window instantly, let the slideout transition be the only animated element.

**Scope:** This change only affects `expandCiderPanelForSlideOut`. Other window animations (maximize, restore after slideout close, etc.) are left alone.

**Files:**
- Modify: `Sources/Cider/App/AppDelegate+CiderPanel.swift:239-273`

- [ ] **Step 1: Remove the NSAnimationContext animation from expandCiderPanelForSlideOut**

Replace the animation block at lines 265-273 with an instant resize:

```swift
        // Expand instantly — the slideout's SwiftUI transition provides the animation.
        // Running both simultaneously caused competing animations and visual jank.
        panel.setFrame(newFrame, display: true)
```

This replaces the `guard !reduceMotion` + `NSAnimationContext.runAnimationGroup` block (lines 265-273). The reduce-motion guard is no longer needed since `setFrame` is already instant.

- [ ] **Step 2: Build and verify**

Run: `swift build -Xswiftc -warnings-as-errors 2>&1 | tail -5`
Expected: Build Succeeded

- [ ] **Step 3: Commit**

```bash
git add Sources/Cider/App/AppDelegate+CiderPanel.swift
git commit -m "perf: instant window expand on slideout open (no competing animation)"
```

---

## Measurement Checkpoint

After completing Tasks 1-4, test the following in Xcode (Cmd+R) and evaluate whether Phase 2 is needed:

1. **Library load** — Open the app, switch to Library tab. Cards should show thumbnails immediately (no blank-then-fill flicker). Second visit should be instant from cache.
2. **Card click → slideout** — Click a bookmark card. The slideout should animate smoothly without lag. The web/reader content should start loading ~350ms after the animation finishes.
3. **Blur appearance** — When slideout opens, the library behind it should blur. Note whether it feels smooth or still heavy.
4. **Switch between cards** — With slideout open, click different cards. Each should load quickly (thumbnails from cache, web deferred).
5. **Window resize** — The window should expand instantly when the slideout needs more room, not animate simultaneously. Check whether the instant expand feels abrupt or natural.
6. **Grid/masonry/table views** — All three bookmark display modes should render thumbnails correctly.

**Decision points:**
- If blur still feels heavy during slideout transition → proceed with Task 5
- If grid/masonry card rendering is still noticeably slow → proceed with Task 6
- If both feel fine → skip Phase 2

---

## Phase 2 Tasks (Conditional)

### Task 5: Add compositingGroup() before blur (conditional — only if blur is still heavy)

**Caveat:** `compositingGroup()` trades per-frame SwiftUI re-layout cost for an offscreen render pass with higher memory bandwidth. It often helps before `.blur()`, but it's not a guaranteed win. Measure before and after.

**Files:**
- Modify: `Sources/Cider/Views/Shared/CiderPanelShell.swift:96-98`

- [ ] **Step 1: Add compositingGroup before the blur modifier**

In `CiderPanelShell.swift`, add `.compositingGroup()` before the existing `.blur()` modifier (line 96). This tells SwiftUI to flatten the entire right-column subtree into an offscreen buffer first, then apply the blur to that single composited texture — instead of blurring each subview individually.

Replace lines 96-98 with:

```swift
                .compositingGroup()
                .blur(radius: blurRightColumn ? BookmarksDesign.detailsContentBlurRadius : 0)
                .allowsHitTesting(!blurRightColumn)
                .animation(reduceMotion ? .none : .snappy, value: blurRightColumn)
```

**Why not `.drawingGroup()`:** `.drawingGroup()` forces Metal rendering for the entire subtree, which can break AppKit-hosted views (like `NSVisualEffectView`). `.compositingGroup()` is safer — it composites without changing the rendering backend.

- [ ] **Step 2: Build, run, and measure**

Run: `swift build -Xswiftc -warnings-as-errors 2>&1 | tail -5`
Expected: Build Succeeded

Then test in Xcode: open a slideout, watch the blur transition. If it's smoother, keep. If it looks the same or worse (higher memory, visual artifacts), revert.

- [ ] **Step 3: Commit (only if keeping)**

```bash
git add Sources/Cider/Views/Shared/CiderPanelShell.swift
git commit -m "perf: add compositingGroup before blur to reduce per-frame layout cost"
```

---

### Task 6: Remove GeometryReader from BookmarkCard (conditional — only if grid is still slow)

Each `BookmarkCard` uses a `GeometryReader` in `.background` (line 159) to measure its own width, causing a 3-phase render cycle: initial → width from GeometryReader → aspect ratio from thumbnail decode. Pass the card width from the parent layout instead.

**Risk:** This changes how thumbnail height is calculated. Can easily break masonry/grid layouts. Test thoroughly.

**Files:**
- Modify: `Sources/Cider/Views/Bookmarks/BookmarkCard.swift:159-168` (remove GeometryReader)
- Modify: `Sources/Cider/Views/Bookmarks/BookmarkCard.swift` (add `cardWidth` parameter)
- Modify: All `BookmarkCard(` call sites (pass width from parent)

- [ ] **Step 1: Find all BookmarkCard call sites**

Run: `grep -rn "BookmarkCard(" Sources/Cider/ | head -20`

Examine each call site to determine if a column width is already available from the parent layout (LazyVGrid, masonry, etc.).

- [ ] **Step 2: Add cardWidth as an init parameter with a default**

Find the `@State private var cardWidth` declaration and replace with:

```swift
var cardWidth: CGFloat = 0
```

Add a computed fallback:

```swift
private var effectiveCardWidth: CGFloat {
    cardWidth > 0 ? cardWidth : cardSizing.cardMinWidth
}
```

Update `resolvedThumbnailHeight` (line 203) to use `effectiveCardWidth` instead of `cardWidth`.

- [ ] **Step 3: Remove the GeometryReader background**

Remove lines 159-168 (the `.background(GeometryReader { ... })` block) and the `updateCardWidth` method (lines 219-223).

- [ ] **Step 4: Update call sites to pass cardWidth**

At each call site, pass the known column width. If the parent doesn't have a pre-computed width, keep the default (0) and let `effectiveCardWidth` use the fallback.

- [ ] **Step 5: Build and verify**

Run: `swift build -Xswiftc -warnings-as-errors 2>&1 | tail -5`
Expected: Build Succeeded

- [ ] **Step 6: Manual testing (critical)**

Test in Xcode (Cmd+R):
- Grid view: cards render with correct thumbnail heights (no collapsed or oversized thumbnails)
- Masonry view: aspect-ratio thumbnails still work correctly
- Resizing the panel: card thumbnails adapt to new widths
- Different card sizing presets: small, medium, large cards all look right

- [ ] **Step 7: Commit (only if layout is correct)**

```bash
git add Sources/Cider/Views/Bookmarks/BookmarkCard.swift
git commit -m "perf: remove GeometryReader from BookmarkCard, pass width from parent"
```

---

## Backlog (not scheduled)

### Note search synchronous I/O on main actor

`LibraryViewModel.matchesTextQuery()` (line 163) calls `NotesStorage.loadContent(for:)` (line 815) synchronously on the `@MainActor`. There is a content cache at `NotesStorage.loadContent` line 816 that mitigates repeat searches, but first-search-after-vault-change with many notes still does proportional synchronous file I/O on the main thread.

**Impact:** Typing/filtering stutter in the library when the note content cache is cold.

**Fix approach:** Move `matchesTextQuery` to a background task, or pre-warm the note content cache asynchronously when the vault changes.

**When to schedule:** After Phase 1 results are measured, if search/filter stutter is still noticeable.
