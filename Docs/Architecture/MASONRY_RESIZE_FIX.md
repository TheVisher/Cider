# Masonry Resize Fix

Date: 2026-04-28

Context: after the NSPanelChange work, the regular `CiderMainWindow` could resize normally in Dashboard and grid views, but Library masonry resisted horizontal shrink. In some attempts, masonry content also drifted under the sidebar or off the right edge of the window.

Root cause: `LazyMasonryView` inferred its width from its own measured content. When the Library viewport became narrower, masonry could keep using a stale wider width as layout input. SwiftUI/AppKit then treated that wider content as part of the window's sizing pressure, which blocked horizontal shrink or left cards clipped outside the visible content area.

Fix:
- `HomeDashboardView` measures the real Library viewport with a parent `GeometryReader`.
- The Library feed is framed to that measured width before rendering grid or masonry content.
- `LazyMasonryView` now accepts an optional explicit `viewportWidth`.
- When `viewportWidth` is present, masonry uses it as the source of truth and skips its internal width-measurement fallback.
- `LazyMasonryColumnPlanner.layout` allows a one-column masonry layout to shrink below the preferred card width, so the viewport wins and cards adapt instead of forcing the window wider.

Avoided approaches:
- Do not override `CiderMainWindow.setFrame` to clamp or fight SwiftUI sizing. That path triggered AppKit/SwiftUI layout-cycle crashes.
- Do not key the feed with a per-pixel `.id(...)` based on exact width. It fixes stale layout by destroying/recreating the feed during resize, but performance is poor with image-heavy masonry.

Regression coverage:
- `LazyMasonryViewTests.plannerAllowsViewportBelowPreferredCardWidth`
- `LazyMasonryViewTests.plannerUsesExplicitViewportWidth`
- `LazyMasonryViewTests.homeDashboardFeedWidthUsesViewportWidth`

