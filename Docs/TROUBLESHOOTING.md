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

## General Layout Principles

1. **Content should never demand more width than proposed.** Layouts should accept whatever width they're given and adapt (fewer columns, smaller items). Never floor a layout width at a content-derived minimum.

2. **Thumbnail heights should be proportional to card width.** Fixed heights from a sizing struct only work when cards are at their ideal width. When the container is narrower, heights must scale proportionally.

3. **Masonry should use exact aspect ratios.** No min/max clamping — let each image's natural shape determine its card height. Clamping creates mismatches that cause padding (with `.fit`) or cropping (with `.fill`).

4. **Use `.fit` for masonry, `.fill` for grid.** Masonry shows full images at natural aspect ratios. Grid crops images to uniform height for a clean grid.

5. **Use `onTapGesture` instead of `Button` in popovers.** Button's press animation adds delay and visual noise inside dropdown menus. `onTapGesture` fires immediately.

6. **Guard against same-value ViewModel updates.** When a `didSet` handler posts a notification that triggers the same property to be set again, add `if self.value != newValue` guards to prevent double re-renders.
