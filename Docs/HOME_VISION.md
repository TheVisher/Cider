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
- Rows are draggable (single-item drag to folders) with hover highlight
- No divider between Continue and library feed — the visual shift from compact rows to cards is sufficient separation

### Library Feed
- Scrollable mixed-content feed of all library items (bookmarks, notes, date cards, contacts), sorted by date
- Filters by folder when one is selected in the sidebar (folder filtering applies to bookmarks + notes; date cards and contacts are global)
- Display mode switching: list / grid / masonry (same ViewOptionsDropdown as Bookmarks/Notes)
- Continuous card size slider (0-3 scale) via LibraryCardSizing
- List mode is the default — mixed content reads better as a uniform list
- Reuses existing card components: BookmarkCard, BookmarkListRow, NoteCardView, NoteListRow, DateCardCardView, ContactCardCardView
- Scrollbars hidden — consistent with the rest of the app (no visible scroll indicators anywhere)
- Surfaced stacks appear in the feed when their rules trigger (see Stacks section below)

### Architecture
- `LibraryItemV2` discriminated union: `.bookmark(Bookmark)` / `.note(Note)` / `.dateCard(DateCard)` / `.contact(ContactCard)` — all entity types flow through a single unified feed
- `LibraryItemV2.dateAnchor: Date?` — the key property for calendar projection; dateCards use `startAt`, contacts use `birthday`, bookmarks and notes have nil
- `LibraryItemV2.isCompleted: Bool` — only meaningful for dateCards; used by surfacing rules like `pinUntilDone`
- `LibraryViewModel` — unified query engine reading from all four storages; produces filtered feeds, calendar buckets, and stack resolutions; rebuilds on any storage change
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
| **Bookmarks tab** | Just bookmarks (to be replaced by saved views over time) |
| **Notes tab** | Just notes (to be replaced by saved views over time) |
| **Custom saved-view tab** | User-defined filter: any combination of types, labels, folders |
| **Sidebar folders** | Standalone mixed-content card view (independent of tabs) |

### Stacks

Stacks are first-class query objects that surface in the library feed when their rules trigger. They are **not containers** — they reference items dynamically by rules (label match, entity type, date range) and/or manual refs.

- A stack shows as a single stacked card in the feed with a count badge and top-card preview
- Click → modal showing all matched items, sorted by attention score or time (user-toggleable)
- Surfacing is rule-driven: `pinUntilDone`, `surfaceDaysBeforeDate(N)`, `remindBeforeMinutes(N)`
- A stack surfaces when: `isPinned` OR any enabled surface rule is triggered
- Built-in templates: **Bills** (pin until paid, surface 7 days before due), **Birthdays** (surface 14 days before), **Schedule** (remind 30min before)
- "Hide for me" (session-local dismiss) and "Mark done" (completion) are distinct actions — never conflate them
- Max 5 pinned stacks is a good practical limit; optional, not enforced in code
- Bills stack modal shows a summary panel: total amount, paid amount, remaining, next due date

### Saved Views / Custom Tabs

Saved views let users define their own tabs: a named filter + sort + layout configuration that pins to the tab bar. The calendar is a **view mode within a saved view**, not a separate tab.

- Saved views store: filter spec (entity types, labels, folder, completed status, text query), sort spec, layout spec (list/grid/masonry + calendar projection toggle)
- `isTabPinned: Bool` controls whether the saved view appears in the tab bar
- Creating a saved view: build a filter in the feed → "Save as Tab" → names the tab
- Calendar projection is a toggle on any saved view — it groups the filtered items by `dateAnchor` into a month/week grid
- Ghost day cells (empty days rendered as dashed placeholders) are toggleable; clicking one pre-fills the DateCard editor with that date
- Example flows: "Bills" tab = date cards filtered by Bills label + calendar; "Kids Sports" tab = schedule stack + calendar; "My Girlfriend's Events" tab = her person label + time sort

### Product Philosophy

**"Time is metadata. Importance is the UI."**

Traditional calendars make time the primary axis — every day gets equal visual weight regardless of whether anything is happening. Cider's approach: time is just metadata on a card. The feed surfaces cards by *relevance* (rules, pins, surfacing logic), not purely by chronology. Ghost day cells in the calendar view reinforce this — you immediately see how many days actually matter vs. how many are empty.

**"Calendar without calendar anxiety"** — the grid exists, but it's calm. Density is controlled. Empty days are visually lightweight. Filters apply everywhere. The calendar isn't a separate mode; it's a lens on your library.

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
