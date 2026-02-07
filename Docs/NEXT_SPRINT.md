# Next Sprint Plan (v0.3)

## Goal
Add window tiling from the command palette, window preview thumbnails, and organizational features.

## Completed in v0.2
- [x] Keyboard navigation (↑↓←→, Tab, Enter, Escape)
- [x] Search filtering (apps, windows, folders — real-time)
- [x] Drag to reorder pinned apps and folders
- [x] App folders (drag-to-create, rename, expand/collapse)
- [x] Drag windows between monitors
- [x] Option+Tab window cycling
- [x] Highlighted text in search results

## Work Items

### 1. Window Preview Thumbnails (carried from v0.2)
- WindowPreviewService exists but is not integrated into UI.
- Display thumbnails in window rows (on hover or inline).
- Request Screen Recording permission when user enables previews.
- Add settings toggle for preview feature.
- Cache thumbnails with size limits.

### 2. Window Tiling
- Context menu tiling: Left Half, Right Half, Top Half, Bottom Half, Quarters.
- Maximize, Center, and Restore options.
- Implementation via AXUIElement position/size setting (WindowManager already has this).
- Multi-monitor aware tiling.

### 3. Window Grouping
- Manual window groups (drag windows onto each other).
- Named groups.
- Groups persist across app restarts.

## Definition of Done
- Tiling works reliably across major apps.
- Previews load without blocking UI.
- All animations respect Reduce Motion.
- No crashes in 30 minutes of use.

## Dependencies
- Screen Recording permission for previews (optional feature).
