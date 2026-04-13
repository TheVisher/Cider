# Lazy Masonry Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the eager `MasonryLayout` (a SwiftUI `Layout` conformance that instantiates and measures every item upfront) with a lazy `LazyMasonryView` that only creates visible cells, eliminating the O(N) instantiation burst, the per-card 3-phase feedback loop, and the N full-recompute cascade from async aspect ratio delivery.

**Architecture:** HStack of N LazyVStack columns. Items are pre-assigned to columns using cached height estimates. A shared `MasonryHeightCache` provides deterministic heights before cards render. `BookmarkThumbnailCache` is extended to store aspect ratios alongside images. The GeometryReader in `BookmarkCard` is removed for masonry mode — column width comes from the container.

**Tech Stack:** Swift, SwiftUI, AppKit (NSCache)

**Important codebase rules:**
- No hardcoded colors — use `CiderColors.*` from Constants.swift
- No hardcoded fonts — use `CiderFont.*` from CiderFont.swift
- Spring animations only — no `.easeIn`, `.easeOut`, `.linear`
- Respect Reduce Motion — `reduceMotion ? .none : .spring` on every animation
- Use `os.Logger` — not `print()`
- Build command: `swift build -Xswiftc -warnings-as-errors`
- Masonry is the user's favorite view — visual correctness is non-negotiable

**Risk areas:**
- Column reassignment causing visible card jumps when estimates refine
- Scroll position stability when heights update
- Mixed-item feeds (bookmarks, notes, contacts, todos, vault files, date cards) all need height estimates
- Multi-column span support (`MasonryColumnSpan`) must be preserved

---

## Current Architecture (What We're Replacing)

`MasonryLayout` (`Sources/Cider/Views/Shared/MasonryLayout.swift`) is a `Layout` protocol conformance. SwiftUI's `Layout` requires all subviews upfront — it is fundamentally eager.

**The cascade on first render with N items:**
1. All N cards instantiated immediately (views + @State + .task modifiers)
2. `sizeThatFits` calls `computeFrames` — loops all N subviews, calls `sizeThatFits` on each
3. Each bookmark card renders at fallback height (aspect ratio unknown)
4. GeometryReader fires per card → updates `cardWidth` state → invalidates card → masonry recomputes all N
5. Thumbnail loads complete per card → delivers aspect ratio → invalidates card → masonry recomputes all N
6. Result: up to 2N full O(N) recomputes after initial render

**Call sites using MasonryLayout:**
- `HomeDashboardView.swift` line 194
- `FolderDetailView.swift` line 578
- `SavedViewTabContent.swift` line 573

**Grid comparison:** All three use `LazyVGrid` for grid mode — same data, lazy instantiation.

---

## File Map

| File | Action | Task | Purpose |
|------|--------|------|---------|
| `Sources/Cider/Services/BookmarkThumbnailCache.swift` | **Modify** | 1 | Store aspect ratio + icon metadata alongside NSImage |
| `Sources/Cider/Views/Bookmarks/BookmarkThumbnailView.swift` | **Modify** | 1 | Populate aspect ratio in cache on decode |
| `Sources/Cider/Services/MasonryHeightCache.swift` | **Create** | 2 | Shared height estimates keyed by itemID + columnWidth |
| `Sources/Cider/Views/Shared/LazyMasonryView.swift` | **Create** | 3 | HStack of LazyVStack columns with pre-assigned items |
| `Sources/Cider/Views/Bookmarks/BookmarkCard.swift` | **Modify** | 4 | Accept column width as parameter, remove GeometryReader for masonry |
| `Sources/Cider/Views/Home/HomeDashboardView.swift` | **Modify** | 5 | Swap MasonryLayout for LazyMasonryView |
| `Sources/Cider/Views/Shared/FolderDetailView.swift` | **Modify** | 5 | Swap MasonryLayout for LazyMasonryView |
| `Sources/Cider/Views/SavedViews/SavedViewTabContent.swift` | **Modify** | 5 | Swap MasonryLayout for LazyMasonryView |
| `Sources/Cider/Views/Shared/MasonryLayout.swift` | **Keep** | — | Keep for now as fallback; delete after validation |

---

## Task 1: Extend BookmarkThumbnailCache to store aspect ratios

The thumbnail cache currently stores only `NSImage`. Extend it to store aspect ratio and icon-overlay metadata so masonry can know card height before the card renders.

**Files:**
- Modify: `Sources/Cider/Services/BookmarkThumbnailCache.swift`
- Modify: `Sources/Cider/Views/Bookmarks/BookmarkThumbnailView.swift`

- [ ] **Step 1: Create a CachedThumbnail struct that holds image + metadata**

In `BookmarkThumbnailCache.swift`, replace the raw `NSImage` storage with a struct:

```swift
import AppKit

@MainActor
final class BookmarkThumbnailCache {
    static let shared = BookmarkThumbnailCache()

    struct CachedThumbnail {
        let image: NSImage
        /// height / width — nil if the image should render as an icon overlay
        let aspectRatio: CGFloat?
        let isIconOverlay: Bool
    }

    private let cache = NSCache<NSString, CacheEntry>()

    init() { cache.countLimit = 300 }

    func get(_ filePath: String, modifiedAt: TimeInterval) -> CachedThumbnail? {
        let key = "\(filePath):\(modifiedAt)" as NSString
        return cache.object(forKey: key)?.value
    }

    func set(_ thumbnail: CachedThumbnail, for filePath: String, modifiedAt: TimeInterval) {
        let key = "\(filePath):\(modifiedAt)" as NSString
        cache.setObject(CacheEntry(value: thumbnail), forKey: key)
    }

    /// Quick aspect ratio lookup without needing the full image.
    /// Returns nil if not cached or if the image is an icon overlay.
    func aspectRatio(for filePath: String, modifiedAt: TimeInterval) -> CGFloat? {
        get(filePath, modifiedAt: modifiedAt)?.aspectRatio
    }
}

/// NSCache requires reference-type values.
private final class CacheEntry {
    let value: BookmarkThumbnailCache.CachedThumbnail
    init(value: BookmarkThumbnailCache.CachedThumbnail) { self.value = value }
}
```

- [ ] **Step 2: Update all cache call sites to use CachedThumbnail**

Update `BookmarkThumbnailView.loadThumbnailAsync()`, `CarouselPageImage.loadImage()`, `BookmarkDetailsHeroPreview.loadThumbnailAsync()`, and `BookmarkTableIcon.loadFavicon()` to construct `CachedThumbnail` with the aspect ratio and icon metadata they already compute.

The main `BookmarkThumbnailView` path already computes `isIconOverlay` and `aspectRatio` — just wrap them into the struct on cache store and unpack on cache hit.

For `CarouselPageImage` and `BookmarkTableIcon`, aspect ratio can be computed from the decoded image dimensions. `isIconOverlay` is false for carousel and true-ish for favicon (use a flag or just store nil aspect ratio).

- [ ] **Step 3: Build and verify**

Run: `swift build -Xswiftc -warnings-as-errors 2>&1 | tail -5`
Expected: Build Succeeded

- [ ] **Step 4: Commit**

```bash
git add Sources/Cider/Services/BookmarkThumbnailCache.swift Sources/Cider/Views/Bookmarks/BookmarkThumbnailView.swift Sources/Cider/Views/Bookmarks/BookmarkDetailsDraft.swift Sources/Cider/Views/Shared/LibraryTableRow.swift
git commit -m "feat: extend BookmarkThumbnailCache to store aspect ratio + icon metadata"
```

---

## Task 2: Create MasonryHeightCache

A shared model that provides deterministic height estimates for any `LibraryItemV2` at a given column width, so the lazy masonry can assign items to columns without rendering them.

**Files:**
- Create: `Sources/Cider/Services/MasonryHeightCache.swift`

- [ ] **Step 1: Create the height cache**

```swift
import SwiftUI

/// Provides deterministic height estimates for library items in masonry layout.
/// Used by LazyMasonryView to assign items to columns before any card renders.
@MainActor
final class MasonryHeightCache: ObservableObject {
    static let shared = MasonryHeightCache()

    /// Actual measured heights reported by rendered cards.
    /// Key: "\(itemID):\(columnWidth rounded to nearest int)"
    private var measuredHeights: [String: CGFloat] = [:]

    /// Debounce timer for column reassignment after height updates.
    private var reassignmentTask: Task<Void, Never>?

    func estimatedHeight(for item: LibraryItemV2, columnWidth: CGFloat, cardSizing: CardSizing) -> CGFloat {
        let key = cacheKey(itemID: item.id, columnWidth: columnWidth)

        // Return measured height if available
        if let measured = measuredHeights[key] {
            return measured
        }

        // Otherwise compute a deterministic estimate
        return defaultEstimate(for: item, columnWidth: columnWidth, cardSizing: cardSizing)
    }

    func reportMeasuredHeight(_ height: CGFloat, for itemID: String, columnWidth: CGFloat) {
        let key = cacheKey(itemID: itemID, columnWidth: columnWidth)
        let existing = measuredHeights[key]
        // Only update if meaningfully different (>2pt) to avoid churn
        guard existing == nil || abs((existing ?? 0) - height) > 2 else { return }
        measuredHeights[key] = height
    }

    /// Clear cached heights when column width changes significantly
    /// (e.g., panel resize). Heights at old widths are stale.
    func invalidate() {
        measuredHeights.removeAll()
    }

    private func cacheKey(itemID: String, columnWidth: CGFloat) -> String {
        "\(itemID):\(Int(columnWidth))"
    }

    private func defaultEstimate(for item: LibraryItemV2, columnWidth: CGFloat, cardSizing: CardSizing) -> CGFloat {
        switch item {
        case .bookmark(let bookmark):
            return bookmarkEstimate(bookmark, columnWidth: columnWidth, cardSizing: cardSizing)
        case .note:
            // Notes: thumbnail area + title + preview text. Roughly 1.4x column width.
            return columnWidth * 1.4
        case .dateCard, .contact, .todo:
            // Fixed-content cards: consistent height regardless of content.
            return columnWidth * 0.6
        case .vaultFile:
            // Vault files: thumbnail + filename. Similar to bookmarks with square aspect.
            return columnWidth * 1.0
        }
    }

    private func bookmarkEstimate(_ bookmark: Bookmark, columnWidth: CGFloat, cardSizing: CardSizing) -> CGFloat {
        // Check if we have a cached aspect ratio from thumbnail cache
        if let fileURL = bookmark.thumbnailFileURL {
            let modifiedAt = bookmark.metadataUpdatedAt?.timeIntervalSince1970 ?? -1
            if let aspectRatio = BookmarkThumbnailCache.shared.aspectRatio(for: fileURL.path, modifiedAt: modifiedAt) {
                // aspectRatio is height/width
                let thumbnailHeight = columnWidth * aspectRatio
                let clamped = min(max(thumbnailHeight, cardSizing.masonryThumbnailHeightMin),
                                  cardSizing.masonryThumbnailHeightMax)
                // Add footer estimate (~60pt for title + tags + padding)
                return clamped + 60
            }
        }

        // Fallback: use the existing fallback height + footer
        let widthScale = columnWidth / max(cardSizing.cardMinWidth, 1)
        return cardSizing.masonryThumbnailHeightFallback * widthScale + 60
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `swift build -Xswiftc -warnings-as-errors 2>&1 | tail -5`
Expected: Build Succeeded

- [ ] **Step 3: Commit**

```bash
git add Sources/Cider/Services/MasonryHeightCache.swift
git commit -m "feat: add MasonryHeightCache for deterministic card height estimates"
```

---

## Task 3: Create LazyMasonryView

The core replacement. An HStack of N `LazyVStack` columns, where items are pre-assigned to columns using height estimates from `MasonryHeightCache`.

**Files:**
- Create: `Sources/Cider/Views/Shared/LazyMasonryView.swift`

- [ ] **Step 1: Implement LazyMasonryView**

The approach:
1. Compute column count and width from available space (same math as current `MasonryLayout`)
2. Assign items to columns greedily using estimated heights (shortest-column-first, same algorithm)
3. Render each column as a `LazyVStack` — only visible items are instantiated
4. Each rendered card reports its actual height back to `MasonryHeightCache`
5. Column assignments are recomputed with debounce when height estimates change significantly

```swift
import SwiftUI

struct LazyMasonryView<Item: Identifiable & Hashable, Content: View>: View {
    let items: [Item]
    let minimumColumnWidth: CGFloat
    let itemSpacing: CGFloat
    let heightEstimate: (Item, CGFloat) -> CGFloat
    @ViewBuilder let content: (Item, CGFloat) -> Content

    @State private var containerWidth: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let columnCount = Self.columnCount(for: width, minimumColumnWidth: minimumColumnWidth, spacing: itemSpacing)
            let columnWidth = Self.columnWidth(for: width, columnCount: columnCount, spacing: itemSpacing)
            let columns = Self.assignColumns(
                items: items,
                columnCount: columnCount,
                columnWidth: columnWidth,
                spacing: itemSpacing,
                heightEstimate: heightEstimate
            )

            HStack(alignment: .top, spacing: itemSpacing) {
                ForEach(0..<columnCount, id: \.self) { columnIndex in
                    LazyVStack(spacing: itemSpacing) {
                        ForEach(columns[columnIndex], id: \.id) { item in
                            content(item, columnWidth)
                                .frame(width: columnWidth)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Column Math (matches MasonryLayout exactly)

    static func columnCount(for width: CGFloat, minimumColumnWidth: CGFloat, spacing: CGFloat) -> Int {
        guard width.isFinite, width > minimumColumnWidth else { return 1 }
        let denominator = minimumColumnWidth + spacing
        guard denominator.isFinite, denominator > 0 else { return 1 }
        let rawCount = ((width + spacing) / denominator).rounded(.down)
        guard rawCount.isFinite, rawCount > 0 else { return 1 }
        return max(1, Int(rawCount))
    }

    static func columnWidth(for width: CGFloat, columnCount: Int, spacing: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0 else { return minimumColumnWidth }
        guard columnCount > 1 else { return width }
        let totalSpacing = spacing * CGFloat(columnCount - 1)
        let computed = (width - totalSpacing) / CGFloat(columnCount)
        guard computed.isFinite, computed > 0 else { return minimumColumnWidth }
        return max(1, computed)
    }

    // MARK: - Greedy Column Assignment

    static func assignColumns(
        items: [Item],
        columnCount: Int,
        columnWidth: CGFloat,
        spacing: CGFloat,
        heightEstimate: (Item, CGFloat) -> CGFloat
    ) -> [[Item]] {
        var columns = Array(repeating: [Item](), count: columnCount)
        var columnHeights = Array(repeating: CGFloat(0), count: columnCount)

        for item in items {
            // Find shortest column
            let shortest = columnHeights.enumerated().min(by: { $0.element < $1.element })!.offset
            columns[shortest].append(item)
            columnHeights[shortest] += heightEstimate(item, columnWidth) + spacing
        }

        return columns
    }
}
```

**Note on multi-column span:** The current `MasonryLayout` supports `MasonryColumnSpan` for items that span multiple columns. The initial lazy implementation should handle single-column items only. If any items use `masonryColumnSpan(2)`, check how common this is — it may be unused or could be handled with a full-width row above/between columns. Document this as a known limitation in the code.

- [ ] **Step 2: Build and verify**

Run: `swift build -Xswiftc -warnings-as-errors 2>&1 | tail -5`
Expected: Build Succeeded

- [ ] **Step 3: Commit**

```bash
git add Sources/Cider/Views/Shared/LazyMasonryView.swift
git commit -m "feat: add LazyMasonryView — lazy HStack+LazyVStack masonry replacement"
```

---

## Task 4: Update BookmarkCard for masonry — accept column width, remove GeometryReader

In masonry mode, the card doesn't need to discover its own width — the column width is known by `LazyMasonryView`. Pass it in, and skip the GeometryReader when in masonry mode.

**Files:**
- Modify: `Sources/Cider/Views/Bookmarks/BookmarkCard.swift`

- [ ] **Step 1: Add a `knownWidth` parameter**

Add an optional `knownWidth: CGFloat?` parameter to `BookmarkCard`. When provided, use it instead of the GeometryReader-measured `cardWidth`.

```swift
/// When provided (e.g., from lazy masonry), skip the GeometryReader and use this width directly.
var knownWidth: CGFloat? = nil
```

Update `resolvedThumbnailHeight` and any other code that uses `cardWidth` to prefer `knownWidth` when available.

- [ ] **Step 2: Skip GeometryReader when knownWidth is provided**

In the `.background(GeometryReader { ... })` block (line 159), wrap it in a condition:

```swift
// Only measure width dynamically when not provided by the container
if knownWidth == nil {
    // existing GeometryReader background
}
```

And initialize `cardWidth` from `knownWidth` if available:

```swift
@State private var cardWidth: CGFloat

init(/* existing params */, knownWidth: CGFloat? = nil) {
    // ... existing init logic ...
    self._cardWidth = State(initialValue: knownWidth ?? 220)
    self.knownWidth = knownWidth
}
```

- [ ] **Step 3: Have card report measured height back to MasonryHeightCache**

Add a GeometryReader-based height reporter that writes the actual card height to the cache after render:

```swift
.background(
    GeometryReader { proxy in
        Color.clear.onAppear {
            MasonryHeightCache.shared.reportMeasuredHeight(
                proxy.size.height,
                for: "bookmark-\(bookmark.id.uuidString)",
                columnWidth: knownWidth ?? cardWidth
            )
        }
    }
)
```

This is lightweight (no state update, just a cache write) and only fires once on appear.

- [ ] **Step 4: Build and verify**

Run: `swift build -Xswiftc -warnings-as-errors 2>&1 | tail -5`
Expected: Build Succeeded

- [ ] **Step 5: Commit**

```bash
git add Sources/Cider/Views/Bookmarks/BookmarkCard.swift
git commit -m "feat: BookmarkCard accepts knownWidth, skips GeometryReader for masonry"
```

---

## Task 5: Swap call sites from MasonryLayout to LazyMasonryView

Replace the 3 masonry call sites with `LazyMasonryView`.

**Files:**
- Modify: `Sources/Cider/Views/Home/HomeDashboardView.swift` (line 194)
- Modify: `Sources/Cider/Views/Shared/FolderDetailView.swift` (line 578)
- Modify: `Sources/Cider/Views/SavedViews/SavedViewTabContent.swift` (line 573)

- [ ] **Step 1: Replace masonry case in HomeDashboardView**

Replace lines 194-205 with:

```swift
        case .masonry:
            LazyMasonryView(
                items: libraryItems,
                minimumColumnWidth: cardSizing.cardMinWidth,
                itemSpacing: Spacing.md,
                heightEstimate: { item, columnWidth in
                    MasonryHeightCache.shared.estimatedHeight(for: item, columnWidth: columnWidth, cardSizing: cardSizing)
                }
            ) { item, columnWidth in
                libraryCard(item, mode: .masonry, columnWidth: columnWidth)
                    .id(item.id)
            }
            .padding(.bottom, Spacing.xs)
```

This requires updating `libraryCard` to accept and pass through `columnWidth`. Add a `columnWidth: CGFloat? = nil` parameter to `libraryCard` and pass it as `knownWidth` to `BookmarkCard`.

- [ ] **Step 2: Apply same pattern to FolderDetailView**

Replace lines 578-589 with the same `LazyMasonryView` pattern, using `folderItems` instead of `libraryItems`.

- [ ] **Step 3: Apply same pattern to SavedViewTabContent**

Replace lines 573-584 with the same `LazyMasonryView` pattern, using `filteredItems`.

- [ ] **Step 4: Update libraryCard / itemCard helpers to pass columnWidth**

Each view has a helper function (`libraryCard`, `itemCard`) that creates the appropriate card for each `LibraryItemV2` case. Add `columnWidth: CGFloat? = nil` parameter and pass it through to `BookmarkCard(knownWidth:)`. Other card types (NoteCard, ContactCard, etc.) don't need it yet.

- [ ] **Step 5: Build and verify**

Run: `swift build -Xswiftc -warnings-as-errors 2>&1 | tail -5`
Expected: Build Succeeded

- [ ] **Step 6: Commit**

```bash
git add Sources/Cider/Views/Home/HomeDashboardView.swift Sources/Cider/Views/Shared/FolderDetailView.swift Sources/Cider/Views/SavedViews/SavedViewTabContent.swift
git commit -m "feat: swap masonry call sites to LazyMasonryView"
```

---

## Task 6: Visual validation and cleanup

**This task requires manual testing in Xcode (Cmd+R).**

- [ ] **Step 1: Visual comparison checklist**

Test each scenario and compare with the old masonry (keep `MasonryLayout.swift` as reference):

| Scenario | What to check |
|----------|--------------|
| Library → masonry view | Cards render, no blank gaps, columns balanced |
| Scroll down | New cards lazy-load as you scroll |
| Scroll back up | Previously rendered cards still correct |
| Resize panel | Columns recompute, cards reflow |
| Card sizing slider | Small/medium/large/XL all work |
| Folder → masonry | Same behavior as library |
| Saved view → masonry | Same behavior as library |
| Mixed content | Bookmarks, notes, contacts, todos all render correctly |
| Switch grid → masonry | No delay on switch (the main symptom we're fixing) |
| Switch masonry → grid | Clean transition, no lingering state |

- [ ] **Step 2: Verify scroll performance**

Open library with 145+ items in masonry. Scroll rapidly up and down. Cards should appear smoothly without stuttering. RAM usage should stay lower than the old masonry (since only visible cards exist).

- [ ] **Step 3: Check height settling**

Cards with thumbnail aspect ratios should start at a reasonable height and settle to the correct height after thumbnail loads. The settling should not cause visible card jumps or column rebalancing flicker.

- [ ] **Step 4: Delete MasonryLayout.swift (only after validation)**

Once satisfied the new implementation is correct:

```bash
git rm Sources/Cider/Views/Shared/MasonryLayout.swift
git commit -m "chore: remove old eager MasonryLayout (replaced by LazyMasonryView)"
```

If any issues are found, keep both files and iterate.

---

## Known Limitations (Document, Don't Fix Yet)

1. **Multi-column span:** `MasonryColumnSpan` is not supported in the initial `LazyMasonryView`. If any items use `.masonryColumnSpan(2)`, they'll render as single-column. Check usage — may be unused.

2. **Height estimate accuracy for non-bookmark items:** Notes, contacts, todos use rough multipliers. These could be refined with type-specific caches if they look visually unbalanced.

3. **Column reassignment on scroll:** If a card reports a height very different from its estimate, column assignments won't update (by design — avoids jumps). This means columns may be slightly unbalanced until the user navigates away and back.
