# Detail Panel Layout Specification

> Reference for building detail view surfaces (slide-out, full panel, page). These values ensure visual alignment with the main CiderPanel's sidebar and title bar. Apply consistently across all content types (bookmarks, notes, date cards, contacts, documents).
>
> **Token reference:** All spacing, radius, and border values are defined in `Docs/Design/DESIGN_SYSTEM.md` (sections 3.1-3.3). Use `Spacing.*`, `Radius.*`, and `CiderBorder.*` tokens — never hardcoded numbers.

---

## View Modes

The detail view supports three modes, switchable via toolbar icons:

| Mode | Icon | Behavior |
| --- | --- | --- |
| **Slide-out** (default) | `sidebar.trailing` | Floats over the right column as an overlay. Drag handle on left edge to resize. |
| **Full panel** | `rectangle` | Covers the entire panel content area (modal overlay). |
| **Page** | `rectangle.fill` | Replaces the content area entirely (push navigation). |

---

## Slide-Out Panel Layout

The slide-out is positioned in the `panelOverlay` slot of `CiderPanelShell`, aligned trailing with uniform padding. The main panel's right column (title bar + divider + content) is blurred when the slide-out is visible (`blurRightColumn: true`).

### Alignment Targets

These are the positions from the **panel clip edge** (the inner edge of the panel's rounded rect, not the window edge):

| Element | From panel clip edge | Notes |
| --- | --- | --- |
| Traffic light circle center | **28pt** | `Spacing.md` sidebar padding + `Spacing.sm` header padding + half of traffic light tap target |
| Sidebar collapse button center | **28pt** | Same HStack as traffic lights |
| Main panel divider | **47pt** | Right column top padding (7pt) + `CiderPanelDesign.titleBarHeight` |
| Sidebar search bar top | **48pt** | `Spacing.md` + `Spacing.sm` + sidebar header height |

### Slide-Out Geometry

```
Panel clip edge
|
+- Spacing.md  <- overlay inset (detailsSlideOutFloatInset)
|
|  Slide-out top edge
|  +- Spacing.xxs  <- toolbar top padding
|  +- 28pt         <- toolbar content height (buttons are 28x28)
|  |                -> button center at Spacing.md + Spacing.xxs + 14 = 28pt from panel edge
|  +- Spacing.xs+1 <- toolbar bottom padding
|  |                -> divider at Spacing.md + Spacing.xxs + 28 + Spacing.xs+1 = 47pt from panel edge
|  +- divider line
|  +- content area (hero + title | metadata sidebar)
```

### Key Values

| Property | Value | Token / Derivation |
| --- | --- | --- |
| Overlay inset (all sides) | `Spacing.md` | `BookmarksDesign.detailsSlideOutFloatInset` |
| Corner radius | `Radius.md` | Matches sidebar `sectionContainer` |
| Border | `stroke` (not `strokeBorder`) | `CiderColors.borderPanel`, `CiderBorder.innerStrokeWidth` |
| Toolbar top padding | `Spacing.xxs` | Aligns button centers with traffic lights |
| Toolbar bottom padding | `Spacing.xs` + 1pt | Pushes divider to 47pt from panel edge |
| Toolbar horizontal padding | `Spacing.md` | |
| Divider horizontal inset | `Spacing.md` + `Spacing.xxs` | Matches main panel divider |
| Drag handle width | `SlideOutDesign.dragHandleWidth` | |
| Min width | `BookmarksDesign.detailsSlideOutMinWidth` | 600pt |
| Max width | `contentAreaWidth - 2 x inset` | Ensures uniform gap between sidebar and slide-out |
| Metadata sidebar width | `BookmarksDesign.detailsSidebarFixedWidth` | 300pt |

### Background

Single acrylic container — no nested panels:

```swift
.background(
    ZStack {
        VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
        CiderColors.acrylicOverlayTint
        CiderColors.surfaceSubtle
    }
    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
)
.overlay {
    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        .stroke(CiderColors.borderPanel, lineWidth: CiderBorder.innerStrokeWidth)
        .allowsHitTesting(false)
}
```

**Important:** Clip the background ZStack, NOT the outer view. Use `.stroke()` (not `.strokeBorder()`) for the border overlay. This avoids the double-line corner artifact that occurs when `.clipShape()` + `.strokeBorder()` are combined on the same view. Matches the sidebar's `sectionContainer` pattern.

### Toolbar

```
[X close]  ...spacer...  [i info toggle]  [= slideOut] [box fullPanel] [fill page]
```

- Close button: `xmark`, 28x28, `CiderFont.bodySemibold`
- Info toggle: `info.circle` / `info.circle.fill`, 24x24, toggles metadata sidebar
- Mode icons: 24x24, active mode highlighted with `CiderColors.controlAccent`
- No divider between toolbar and drag handle area

### Content Layout

```
HStack(alignment: .top, spacing: 0)
+- Left column (ScrollView, maxWidth: .infinity)
|   +- Hero image (BookmarkDetailsHeroPreview)
|   +- Title (heroTitle)
|   +- Subtitle (host . relative date)
|   +- padding: Spacing.lg around content
|
+- Right column (conditional, animated)
    +- BookmarkMetadataSidebar
        +- surfaceInput background + borderStrong stroke + shadow
        +- Toggle: @State isMetadataVisible (default true, resets on open)
        +- Transition: .move(edge: .trailing).combined(with: .opacity), .snappy
```

### CiderPanelShell Integration

The slide-out is passed via the `overlay` closure, not inside the `content` slot:

```swift
CiderPanelShell(
    blurRightColumn: isDetailSlideOut,  // blurs title bar + divider + content
    ...
) {
    ...
} overlay: {
    if isDetailSlideOut, let _ = detailsDraft {
        detailSlideOutContainer
            .frame(width: min(detailSlideOutWidth, maxSlideOutWidth))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(BookmarksDesign.detailsSlideOutFloatInset)
            .transition(.move(edge: .trailing).combined(with: .opacity))
    }
}
```

---

## Shared Components

### BookmarkMetadataSidebar

Extracted struct in `BookmarkDetailsDraft.swift`. Used by both the slide-out panel and fullPanel/page modes. Contains: URL field, action buttons (Open/Copy/Open Image), Title, Tags, Notes, Folder picker, timestamps, Delete/Cancel/Save buttons. Has its own `surfaceInput` background + `borderStrong` border + shadow.

### BookmarkDetailsHeroPreview

Hero image display with gradient background. Falls back to a large letter when no thumbnail exists. Uses `CGImageSourceCreateThumbnailAtIndex` for async loading.

---

## Applying to Other Content Types

When building detail views for notes, date cards, contacts, or documents:

1. **Use the same shell** — slide-out geometry, corner radius, padding, divider alignment, toolbar layout
2. **Swap the content** — left column shows type-specific hero/preview, right column shows type-specific metadata sidebar
3. **Reuse toolbar pattern** — close + info toggle + mode switcher, same sizes and positions
4. **Metadata sidebar** — create a type-specific `XxxMetadataSidebar` struct following `BookmarkMetadataSidebar`'s pattern (same background/border/shadow treatment)
5. **Share the `DetailSlideOutView` if possible** — parameterize the content via generics or closures rather than duplicating the shell
