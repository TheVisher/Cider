# Canvas Detail Modal Design

> Replaces the current right-pinned `CanvasDetailOverlay` with a centered floating modal matching the NSPanel's `DetailSlideOutView` split layout and the canvas sidebar's visual treatment.

---

## Goals

1. Click a canvas card, see a centered floating modal with hero content (left) and metadata (right)
2. Match the NSPanel detail view's look and layout using the same design tokens
3. Architect for future additions (web/reader views, drag-resize, pin) without rewriting

## Non-Goals (Future Work)

- Web view / reader view hero modes (stub the slot, don't wire)
- Drag-to-resize width
- Pin-to-canvas (keep modal open while browsing)
- Card-lift animation (card zooms from canvas position into modal)

---

## Layout

```
+---------------------------------------------------------------+
| [x Close]           Title + Domain            [Copy] [Open]   |  <- Toolbar
+--------------------------+------------------------------------+
|                          |                                    |
|   Hero Thumbnail         |   Metadata Sidebar (scrollable)   |
|   (aspect-fit,           |   - Folder                        |
|    rounded corners,      |   - Tags                          |
|    shadow)               |   - AI Summary                    |
|                          |   - Notes                         |
|                          |   - Created date                  |
|                          |   - Open in Browser button        |
|                          |                                    |
+--------------------------+------------------------------------+
```

For notes: left column shows content preview. For todos: left column shows completion state, priority, checklist.

### Dimensions

| Property | Value | Notes |
|----------|-------|-------|
| Modal width | 800pt | Stored as constant, easy to make dynamic. Room for future hero modes. |
| Min width | `BookmarksDesign.detailsSlideOutMinWidth` (600pt) | For future drag-resize |
| Min height | 400pt | Prevents collapsed layout on small windows |
| Modal height | 80% of canvas geometry height, clamped to min | Centered vertically |
| Max height | Canvas height - `2 * Spacing.xxl` | Breathing room at edges |
| Metadata sidebar width | `BookmarksDesign.detailsSidebarFixedWidth` (300pt) | Matches NSPanel |
| Hero column width | Remaining (modal width - sidebar width) | Flexible |

### Positioning

- Centered horizontally and vertically within the canvas `GeometryReader`
- Backdrop overlay covers entire canvas (click to dismiss)

---

## Visual Treatment

### Background (same stack as DetailSlideOutView)

```swift
ZStack {
    VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
    CiderColors.acrylicOverlayTint
    CiderColors.surfaceSubtle
}
.clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
```

### Border

```swift
RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
    .stroke(CiderColors.borderPanel, lineWidth: CiderBorder.innerStrokeWidth)
```

Using `borderPanel` and `innerStrokeWidth` to match the NSPanel's `DetailSlideOutView` border treatment.

### Shadow

```swift
.shadow(color: CiderColors.shadowHeavy, radius: Spacing.xl, y: Spacing.sm)
```

### Backdrop

```swift
Color.black.opacity(0.3)
    .ignoresSafeArea()
    .onTapGesture { dismiss }
```

---

## Toolbar

Top bar inside the modal, above the divider.

**Left:** Close button (xmark icon, same style as current `closeHeader`)

**Center-ish:** Item type icon + title (truncated, 1 line) + domain subtitle for bookmarks

**Right:** Action buttons
- Copy URL (`doc.on.doc`)
- Open in Browser (`safari`)
- (Future slots: view mode toggle, pin, delete)

Toolbar padding matches `DetailSlideOutView`: horizontal `Spacing.md`, top `Spacing.xxs`, bottom `Spacing.xs + 1`.

Divider below toolbar with same inset: `.padding(.leading, Spacing.md + Spacing.xxs)`.

---

## Content Areas

### Hero Column (Left)

**Bookmarks:** `AsyncImage` of thumbnail, aspect-fit, rounded corners (`Radius.sm`), floating shadow (`detailsFloatingLiftBlur` / `detailsFloatingLiftYOffset`). Falls back to letter icon if no thumbnail. The hero area is a `@ViewBuilder` slot so web/reader views can be added as enum cases later.

**Notes:** Content preview text, scrollable, using `CiderFont.body`.

**Todos:** Completion state icon + priority badge at top, then checklist items, then details text.

### Metadata Sidebar (Right)

Fixed width (300pt). Scrollable vertically. Sections:

1. **Folder** — icon + folder name (if assigned)
2. **Tags** — `TagFlowLayout` with colored pills (reuse existing `labelPills`)
3. **AI Summary** — if available
4. **Notes** — if non-empty (bookmarks only)
5. **Date** — created/modified with calendar icon
6. **Open in Browser** — full-width button (bookmarks only)

Same metadata row style as current overlay (`metadataRow(icon:label:value:)`).

**Sidebar visual treatment:** `CiderColors.surfaceInput` background fill on the metadata column, with a leading vertical separator strip (matching `DetailSlideOutView`'s metadata column treatment). Not a plain `Divider()`.

### Stale / Deleted Items

If `selectedItemID` resolves to no backing item in any lookup, show the existing "Item not found" placeholder (question mark icon + message) centered in the modal. Same pattern as current `unknownItemPlaceholder`.

### Per-Item-Type Toolbar Variations

- **Bookmarks:** Copy URL + Open in Browser buttons shown
- **Notes:** No URL actions; toolbar right side is empty (future: export, share)
- **Todos:** No URL actions; toolbar right side is empty (future: toggle completion)

---

## Interaction

| Action | Behavior |
|--------|----------|
| Click card on canvas | `viewModel.selectedItemID` set, modal appears |
| Click backdrop | `viewModel.deselectAll()`, modal dismisses |
| Press Escape | Same as backdrop click (already wired in `CanvasWindowContentView`) |
| Click Close button | Same as backdrop click |
| Click Copy URL | Copy to pasteboard |
| Click Open in Browser | `NSWorkspace.shared.open(url)` |

### Transitions

- **Appear:** `.opacity.combined(with: .scale(scale: 0.95))` with `.snappy(duration: 0.25)` (or `.none` if reduceMotion)
- **Dismiss:** Reverse of appear

---

## Architecture

### File Changes

| File | Change |
|------|--------|
| `CanvasDetailOverlay.swift` | Full rewrite — centered modal with split layout |
| `CanvasWindowContentView.swift` | Update overlay usage — add backdrop, center modal |

### No New Files

Everything stays in `CanvasDetailOverlay.swift`. The metadata sections, toolbar, and hero area are private subviews within the same file. If the file grows past ~500 lines, the metadata sidebar can be extracted later.

### Growth Points

1. **Hero mode enum:** Add a `CanvasDetailHeroMode` enum (`.thumbnail` for now). When web/reader views are ready, add `.web` / `.reader` cases and switch in the hero `@ViewBuilder`.
2. **Toolbar actions array:** Toolbar buttons are individual views now, but structured so adding more is just adding another button to the `HStack`.
3. **Width property:** `modalWidth` is a stored constant. To add drag-resize: make it `@State`, add a drag gesture on the modal edges, clamp between min/max.
4. **Metadata sidebar reuse:** The sidebar sections (folder, tags, summary, notes, date) follow the same pattern as the NSPanel version. When full parity is needed, these can be extracted into a shared `ItemMetadataSidebar` view.

---

## Tokens Reference

All values from existing constants — no new tokens needed.

| Usage | Token |
|-------|-------|
| Modal corner radius | `Radius.md` |
| Border color | `CiderColors.borderPanel` |
| Border width | `CiderBorder.innerStrokeWidth` |
| Acrylic material | `.underWindowBackground` / `.withinWindow` |
| Toolbar padding | `Spacing.md`, `Spacing.xxs`, `Spacing.xs` |
| Content padding | `Spacing.lg` |
| Metadata sidebar width | `BookmarksDesign.detailsSidebarFixedWidth` |
| Shadow | `CiderColors.shadowHeavy` |
| Thumbnail corners | `Radius.sm` |
| Thumbnail shadow | `BookmarksDesign.detailsFloatingLiftBlur` / `detailsFloatingLiftYOffset` |
