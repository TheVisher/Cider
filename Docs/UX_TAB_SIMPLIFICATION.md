# UX Insight: Tab Simplification

> Captured during workspace implementation testing (Feb 2026)

## Observation

With the universal folder sidebar in place, the Bookmarks and Notes tabs become redundant. Here's why:

- **"All Items"** in the folder sidebar already shows everything (bookmarks + notes combined)
- **Clicking a folder** shows all content in that folder regardless of type
- **The Bookmarks tab** just filters to bookmarks — same as what a filter toggle could do
- **The Notes tab** just filters to notes — same thing

The tabs are essentially doing what a simple filter button could do inside the "All Items" view.

## Proposed Simplification

### Remove Bookmarks and Notes as fixed tabs

Keep only:
- **Home** — Dashboard with stats, quick actions, recent items
- **Dynamic tabs** — Projects, Search results (already closeable)

### Add type filter to the main content view

When viewing "All Items" or a folder, add a filter bar:
- `[All] [Bookmarks] [Notes]` — toggle buttons at the top of the content area
- Default to "All" showing both types mixed
- Remembers the last selection per session

### Benefits

1. **Cleaner tab bar** — Only Home + contextual tabs (projects, searches)
2. **Less confusion** — No weird interaction between folder selection and tab selection
3. **More space** — Tab bar isn't cluttered with fixed tabs that duplicate sidebar functionality
4. **Consistent model** — Sidebar = navigation, tab bar = workspaces

### Tab bar would look like:

```
[Home] [Project: Research] [Search: "swift"] [+]
```

Instead of current:

```
[Home] [Bookmarks 48] [Notes 12] [Project: Research] [Search: "swift"]
```

## Implementation Notes

- The folder sidebar already shows combined bookmark + note counts per folder
- `FolderContentView` already renders mixed bookmarks + notes for a folder
- Would need a `ContentFilterMode` enum: `.all`, `.bookmarks`, `.notes`
- Home dashboard stays as-is (already shows both types)
- The standalone BookmarksPanel and NotesPanel remain unchanged (independent floating panels)
