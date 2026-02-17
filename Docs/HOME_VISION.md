# Home Tab Vision

The Home tab is the library — the unified view of all Cider content. A sticky "Continue" section for recent items, then a scrollable mixed-content feed below with display mode switching.

---

## Current State (Implemented)

### Continue Section
- Sticky two-column list of the 8 most recent items (mixed bookmarks + notes), sorted by date
- Left column: items 0-3 (most recent), right column: items 4-7
- At compact width (content area < 700pt), right column hides — only left column's 4 items shown
- Threshold set high enough that sidebar auto-hiding (~200pt freed) doesn't cause column flicker
- Collapse toggle lives in the title bar (right-aligned, away from tabs) — no wasted vertical space when collapsed
- Collapsed state persisted in CiderConfig
- Hideable via `showContinueSection` setting
- Always shows global recents regardless of folder selection
- No divider between Continue and library feed — the visual shift from compact rows to cards is sufficient separation

### Library Feed
- Scrollable mixed-content feed of all bookmarks + notes, sorted by date
- Filters by folder when one is selected in the sidebar
- Display mode switching: list / grid / masonry (same ViewOptionsDropdown as Bookmarks/Notes)
- Continuous card size slider (0-3 scale) via LibraryCardSizing
- List mode is the default — mixed content reads better as a uniform list
- Reuses existing card components: BookmarkCard, BookmarkListRow, NoteCardView, NoteListRow
- Scrollbars hidden — consistent with the rest of the app (no visible scroll indicators anywhere)

### Architecture
- `LibraryItem` discriminated union: `.bookmark(Bookmark)` / `.note(Note)` with shared `id`, `date`, `title`, `folderID`
- `LibraryDisplayMode` enum conforming to `DisplayModeOption` — plugs into ViewOptionsDropdown
- `LibraryCardSizing` struct with 4-stop interpolation, produces `bookmarkSizing` and `noteSizing` for downstream components
- View state (display mode, card size, continue collapsed) persisted in CiderConfig
- Display mode and card size controlled by CiderPanelView via bindings, persisted on change

### Sidebar Changes
- "All Items" row removed from FolderSidebarView — sidebar is purely organizational (folders only)
- Home tab serves as "All Items" — want to see everything? Click Home.
- Folder selection on Home tab filters the library feed (not the Continue section)

### Mental Model

| Surface | Shows |
|---------|-------|
| **Home tab** | Everything, mixed. Your library. |
| **Bookmarks tab** | Just bookmarks |
| **Notes tab** | Just notes |
| **Sidebar folders** | Standalone mixed-content card view (independent of tabs) |

### Click Behavior
- **Bookmark card click** → Opens bookmark detail modal within the Home view (not tab switch)
- **Note card click** → Opens standalone notes panel on top, with click-outside-to-dismiss modal behavior
  - First click outside the notes panel → dismisses it (event is swallowed so underlying cards don't activate)
  - First click inside the notes panel → removes the monitor, panel becomes a normal sticky panel
- **Rejected approach:** Tab-switching on click (loses scroll position, feels disruptive)

## Planned: Sorting Options

Sort controls in ViewOptionsDropdown for the Home library feed:
- Sort by: creation date, recently modified, title A-Z
- Ascending/descending toggle
- Persisted in CiderConfig as `homeSort` preference
- Currently the feed sorts by `createdDate` descending — this becomes configurable

---

## Future Ideas (Not Yet Prioritized)

- Pinned items section (show pinned notes/bookmarks at the top)
- Today's activity summary
- Folder quick-nav (jump to frequently used folders)
- Search shortcut / recent searches
- Customizable widget layout (choose which sections appear)
- Streak / activity indicators
- Quick-capture inline text field (type and hit enter to create a note or bookmark)

### AI GIF Finder (Requires AI + OCR)

A contextual GIF search tool powered by AI. Instead of guessing keywords in Discord/iMessage/Slack's built-in GIF search, screenshot any conversation and let AI find the perfect reaction GIF.

**Flow:** Screenshot a conversation (using Cider's planned OCR/capture features) → AI reads the context and tone → generates smart search queries → hits GIPHY/Tenor APIs → returns ranked results in a panel → click to copy, paste into any chat app.

**Why it fits Cider:** Cider is already a floating panel open while browsing, and OCR/screenshot capture is planned. This makes it app-agnostic — works with any chat platform since it reads from screenshots, not platform APIs. Results could also be saved to the Whiteboard as image blocks.

**The value is in tone detection:** AI understands that "sure, that's fine" is passive-aggressive and returns the right GIF, not a literal thumbs up. Built-in GIF search can't do this because it's keyword-only.

Full concept doc: `~/Documents/GifGenius-App-Concept.md`
