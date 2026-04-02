# Canvas Search Palette Design

> Command palette for the canvas that reuses the NSPanel's `SearchPaletteView` with a push-aside detail behavior unique to the canvas.

---

## Goals

1. Press `Cmd+F` or click sidebar search bar on canvas → centered command palette appears
2. Type to search — results show as a scrollable list (same as NSPanel palette)
3. Click a result → palette slides left, detail modal appears on the right, canvas flies to that card in the background
4. Architecture supports future modes (create note, commands) via the existing `QuickAction` system

## Non-Goals (Future Work)

- Slide-out panel variant (persistent search panel on the right, non-modal)
- Settings for result-click behavior (always push-aside for now)
- Canvas card dimming/highlighting for non-selected results

---

## Existing Infrastructure

Already built and reusable:

| Component | File | What it does |
|-----------|------|-------------|
| `SearchPaletteView` | `Views/Search/SearchPaletteView.swift` | Full palette UI: search field, scope pills, quick actions, results list, keyboard nav |
| `SearchService` | `Services/SearchService.swift` | Async search across bookmarks, notes, todos, events, contacts. Scope parsing (`@bookmarks`, `@folder:Name`) |
| `SearchResult` | `Services/SearchService.swift` | Result model with type, title, subtitle, snippet, and typed item references |
| `QuickAction` | `Views/Search/SearchPaletteView.swift` | Command enum (new bookmark, new note, etc.) with keyword matching |
| `SearchPaletteDesign` | `Utilities/Constants.swift` | Layout tokens (width: 560pt, search field height: 52pt, etc.) |
| `CanvasDetailOverlay` | `Views/Canvas/CanvasDetailOverlay.swift` | Centered detail modal with full `BookmarkMetadataSidebar` |
| `CanvasViewModel.panToFolder` | `ViewModels/CanvasViewModel.swift` | Fly-to animation for canvas navigation |

---

## Layout

### Phase 1: Search (centered)

```
+----------------------------------------------------------+
|  [magnifying glass]  Search everything...        [esc]   |
+----------------------------------------------------------+
|  @bookmarks  @notes  (scope pills if active)             |
+----------------------------------------------------------+
|                                                          |
|   Quick Actions (New Bookmark, New Note, etc.)           |
|   --- or ---                                             |
|   Search Results (grouped by type, scrollable)           |
|                                                          |
+----------------------------------------------------------+
```

This is the existing `SearchPaletteView` — no changes to its internals.

### Phase 2: Result selected (push-aside)

```
+-------------------------+  +-----------------------------+
|  Search palette         |  |  Detail modal               |
|  (slides left,          |  |  (hero left, metadata right)|
|   narrower)             |  |  Same as CanvasDetailOverlay |
|                         |  |  but sized to fit           |
|  * Selected result      |  |                             |
|    highlighted          |  |                             |
|                         |  |                             |
+-------------------------+  +-----------------------------+
```

Behind both panels, the canvas flies to the selected card (dimmed by backdrop).

### Dimensions

| Property | Value | Notes |
|----------|-------|-------|
| Palette width (centered) | `SearchPaletteDesign.paletteWidth` (560pt) | Matches NSPanel palette |
| Palette width (pushed aside) | 360pt | Narrower to make room for detail |
| Detail width (pushed aside) | Remaining available width minus palette minus gap | Flexible |
| Gap between palette and detail | `Spacing.md` | Visual separation |
| Max results height | `SearchPaletteDesign.resultsMaxHeight` (400pt) | Scrollable beyond this |
| Vertical position | Top-biased — `proxy.size.height * topOffsetFactor` | Same as NSPanel palette |
| Horizontal centering | Respects sidebar (same `availableWidth` / `modalOffsetX` as detail modal) | |

### Backdrop

Same as detail modal: `Color.black.opacity(0.3)`, click to dismiss everything.

---

## Interaction Flow

| Action | Behavior |
|--------|----------|
| `Cmd+F` or click sidebar search | Open palette, auto-focus search field |
| Type query | Live filter results via `SearchService` (100ms debounce) |
| Arrow keys | Navigate results (existing keyboard nav in `SearchPaletteView`) |
| Click result / press Enter | Palette slides left, detail modal appears right, canvas flies to card |
| Click different result | Detail swaps to new item (spring animation), canvas flies to new card |
| Click result's detail close | Detail dismisses, palette slides back to center |
| Escape | Dismiss everything |
| Click backdrop | Dismiss everything |
| Quick action (e.g. "New Bookmark") | Execute action and dismiss (existing behavior) |

### Canvas Navigation

When a result is selected, call a new `CanvasViewModel` method to fly to a specific item:
- `viewModel.panToItem(_ itemID: String)` — finds the card's position and animates the viewport to center on it
- This reuses the same fly-to animation as `panToFolder` but targets a single card

---

## Architecture

### New Files

| File | Responsibility |
|------|---------------|
| `Views/Canvas/CanvasSearchOverlay.swift` | Container: backdrop, palette positioning, push-aside layout, detail embedding |

### Modified Files

| File | Change |
|------|--------|
| `Views/Canvas/CanvasWindowContentView.swift` | Add `Cmd+F` trigger, `@State isSearchVisible`, overlay the search palette |
| `ViewModels/CanvasViewModel.swift` | Add `panToItem(_ itemID: String)` method |
| `Views/Canvas/CanvasDetailOverlay.swift` | Extract modal content into an embeddable subview so it can be used both standalone and inside the search push-aside layout |

### No Changes To

- `SearchPaletteView.swift` — used as-is via its existing callback interface
- `SearchService.swift` — already supports all search functionality needed
- `SearchPaletteDesign` constants — reused directly

### Data Flow

```
CanvasSearchOverlay
├── SearchPaletteView (existing, callbacks wired)
│   ├── onOpenBookmark → set selectedResult + panToItem
│   ├── onOpenNote → set selectedResult + panToItem
│   ├── onOpenTodo → set selectedResult + panToItem
│   ├── onAction → execute QuickAction + dismiss
│   └── onDismiss → dismiss overlay
│
├── CanvasDetailContent (extracted from CanvasDetailOverlay)
│   └── Shows when selectedResult is set
│   └── Uses BookmarkMetadataSidebar for bookmarks (same as current)
│
└── Backdrop (click to dismiss)
```

### Push-Aside Animation

When `selectedResult` transitions from nil → some:
- Palette: `withAnimation(.snappy) { palettePosition = .leading }`
- Detail: appears with `.transition(.move(edge: .trailing).combined(with: .opacity))`

When `selectedResult` transitions from some → nil (detail closed):
- Palette: `withAnimation(.snappy) { palettePosition = .center }`
- Detail: dismissed with reverse transition

---

## Visual Treatment

Same as detail modal and NSPanel palette — all three use the identical acrylic stack:

```swift
ZStack {
    VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
    CiderColors.acrylicOverlayTint
    CiderColors.surfaceSubtle
}
```

Border: `CiderColors.borderPanel`, `CiderBorder.innerStrokeWidth`

The palette and detail are separate containers (not one big panel) — they float side by side with a gap.

---

## Tokens Reference

All values from existing constants — no new tokens needed.

| Usage | Token |
|-------|-------|
| Palette width | `SearchPaletteDesign.paletteWidth` |
| Palette pushed width | 360pt (new constant in `SearchPaletteDesign`) |
| Results max height | `SearchPaletteDesign.resultsMaxHeight` |
| Search field height | `SearchPaletteDesign.searchFieldHeight` |
| Gap between palette and detail | `Spacing.md` |
| Acrylic stack | Same as detail modal |
| Border | `CiderColors.borderPanel` / `CiderBorder.innerStrokeWidth` |
| Backdrop | `Color.black.opacity(0.3)` |
| Corner radius | `Radius.lg` (palette, matching NSPanel) / `Radius.md` (detail) |
