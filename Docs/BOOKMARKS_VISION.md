# Bookmarks Tab Vision

## Goal
Build a fast, low-friction bookmarking system in Cider with strong capture flows, high-quality metadata, and a polished visual browsing experience (List/Grid/Masonry + standalone panel).

## Current Status (Implemented)
- Command Palette tab and standalone Bookmarks window.
- List, Grid, and true Masonry layouts.
- Cross-browser capture flow (capture button + hotkey + clipboard + drag/drop URL).
- Browser coverage working for Chrome, Dia, Zen, and Comet capture path.
- Metadata/title enrichment and thumbnail fetching with fallback behavior.
- Shimmer placeholder while enrichment/thumbnail loads.
- Manual thumbnail assignment by dropping image/image URL/file onto a bookmark card.
- Clipboard review toast flow (save/discard), plus capture success/error toasts.
- Window behavior parity improvements (resizing, tiling shortcuts, snap padding consistency).
- Context menus on cards/rows with Open in Browser, Show Details, Move to Folder, Delete (shared CardContextMenu component).

## Bug Fix: Standalone Panel Resize Handles

The standalone bookmarks panel (`BookmarksPanelView`) uses a single-corner resize handle (`BookmarksResizeHandle`). Needs to be updated to use all-edge resize handles matching the main panel's `PanelEdgeResizeView` pattern.

---

## Phase 1: Capture Quality and Reliability (Next)
1. Harden metadata extraction quality.
2. Improve source-specific handling for Reddit/X edge cases.
3. Add lightweight diagnostics for failed enrichment/capture attempts.

### Acceptance Criteria
- Capture success/failure messaging is always accurate (no false positives).
- Metadata title quality is improved on major sites.
- Thumbnail fallback coverage improves without regressions in speed.

## Phase 2: Bookmark Details Surface
1. Add bookmark details panel (on thumbnail click / info action).
2. Show/edit metadata:
- canonical URL
- title
- tags
- notes
- thumbnail source/local status
3. Add actions:
- replace/remove thumbnail
- copy URL
- open in browser

### Acceptance Criteria
- Details panel opens reliably from cards in all layouts.
- Edits persist and reflect immediately in card/list views.
- Keyboard navigation and accessibility behavior match existing panel standards.

## Phase 3: Library Management
1. **Multi-select** — Shift-click range, Cmd-click toggle, Cmd+A select all. Bulk move to folder, bulk delete (to trash), bulk tag. See `WORKSPACES_VISION.md` for cross-cutting multi-select spec.
2. **Sorting controls** — newest, oldest, title A-Z, domain. Per-tab persistence.
3. **Trash integration** — Delete sends to trash (30-day retention), not permanent delete. See `WORKSPACES_VISION.md` for trash system spec.
4. **Undo** — Transient toast with "Undo" button for destructive/organizational actions.
5. Filter chips (has thumbnail, no thumbnail, recent, tagged).
6. Duplicate management improvements.

### Acceptance Criteria
- Bulk actions perform safely with undo support.
- Deleted items go to trash, not permanent deletion.
- Sorting/filtering is stable across List/Grid/Masonry and search.

## Phase 4: Portability and Interop
1. Finalize storage layout under `~/Documents/Cider/bookmarks` (with migration support).
2. Continue Netscape HTML import/export compatibility.
3. Add richer import feedback for malformed/partial bookmark files.

### Acceptance Criteria
- Existing users migrate safely.
- Imports/exports round-trip with mainstream browser bookmark files.

## Phase 5: Polish and Performance
1. Progressive image loading refinements.
2. Smarter thumbnail invalidation/retry policy.
3. Large-library performance pass (scrolling, filtering, search latency).

### Acceptance Criteria
- Smooth interaction at high bookmark counts.
- No layout jank in masonry during enrichment updates.

## Open Questions
- Should clipboard auto-capture default to review mode or instant-save mode?
- Should there be per-site metadata adapters for high-value domains?
- What is the preferred UX for failed/blocked thumbnail fetches (badge vs details warning)?
