# Next Sprint Plan (v0.2)

## Goal
Add window preview thumbnails, keyboard navigation, and polish the command palette experience.

## Work Items

### 1. Window Preview Thumbnails
- Request Screen Recording permission when user enables previews.
- Capture window thumbnails using ScreenCaptureKit or CGWindowListCreateImage.
- Display thumbnails in window list on hover.
- Cache thumbnails in memory with size limits.

### 2. Keyboard Navigation
- Arrow keys (↑↓) to navigate window list.
- Enter to focus selected window.
- Escape to close palette.
- Tab to cycle between sections (search, apps, windows).

### 3. Pinned Apps Improvements
- Drag to reorder pinned apps.
- App folders (group multiple apps).
- "Add to Pinned" from window context menu.

### 4. Search Enhancements
- Filter windows by title as you type.
- Filter pinned apps.
- Highlight matching text in results.

### 5. Visual Polish
- Smoother animations on hover.
- Loading states for thumbnails.
- Better empty states (no windows, no pinned apps).

## Definition of Done
- Previews show within 200ms of hover.
- Full keyboard navigation without mouse.
- All animations respect Reduce Motion.
- No crashes in 30 minutes of use.

## Dependencies
- Screen Recording permission for previews (optional feature).
