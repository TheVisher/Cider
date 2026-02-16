# Home Tab Vision

The Home tab is the library — the unified view of all Cider content. Stats and quick actions at the top, then all items (bookmarks, notes, etc.) in a scrollable mixed-content feed below.

---

## Current State (Implemented)

- **Stats row** — bookmark count and note count in styled cards
- **Quick actions** — Capture Tab, New Note, Paste URL buttons
- **Recent Bookmarks** — last 6 bookmarks (title, host, relative date), click to open in browser
- **Recent Notes** — last 6 notes (title, relative date), click to open in notes panel

## Next: Home as Library (Planned)

Remove "All Items" from the sidebar. Home becomes the unified content view:

1. **Stats/widgets header** — counts, activity, quick actions (existing)
2. **All content feed** — scrollable mixed view of every bookmark, note, and future content type
3. **Scrolling behavior** — stats header scrolls away as you browse content
4. **View options** — same card size slider and display mode toggle as Bookmarks/Notes (sidebar header button always visible since every tab now has cards)

### Mental Model

| Surface | Shows |
|---------|-------|
| **Home tab** | Everything, mixed. Your library. |
| **Bookmarks tab** | Just bookmarks |
| **Notes tab** | Just notes |
| **Sidebar folders** | Filtered slice of whatever tab you're on |

### Why Remove "All Items" from Sidebar

- "All Items" is a *view*, not a *folder* — it belongs in the tab bar, not the sidebar
- The sidebar is for organization (folders, projects) — not view switching
- The count badge (65) is misleading when the active tab only shows one content type
- "All Items" stays blue/selected regardless of which tab you're on — confusing
- Home-as-library solves this naturally: want to see everything? Click Home.

### Sidebar View Options Always Visible

With Home showing cards too, the view options button in the sidebar header is always relevant — no more conditional show/hide based on selected tab.

## Future Ideas (Not Yet Prioritized)

- Pinned items section (show pinned notes/bookmarks at the top)
- Today's activity summary
- Folder quick-nav (jump to frequently used folders)
- Search shortcut / recent searches
- Customizable widget layout (choose which sections appear)
- Streak / activity indicators
- Quick-capture inline text field (type and hit enter to create a note or bookmark)
