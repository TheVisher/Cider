# Home Tab Vision

The Home tab is the library — the unified view of all Cider content. A sticky "Continue" section for recent items, then a scrollable mixed-content feed below with display mode switching.

---

## Current State (Implemented)

### Continue Section

- Sticky two-column list of the 8 most recent items (mixed bookmarks + notes), sorted by date
- Left column: items 0-3 (most recent), right column: items 4-7
- At compact width (content area &lt; 700pt), right column hides — only left column's 4 items shown
- Threshold set high enough that sidebar auto-hiding (\~200pt freed) doesn't cause column flicker
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
- `LibraryViewModel.recentItems` — pre-sorted top 8 by `updatedDate`, computed in `rebuildItems()` so Home body doesn't sort on every render
- `LibraryDisplayMode` enum conforming to `DisplayModeOption` — plugs into ViewOptionsDropdown
- `LibraryCardSizing` struct with 4-stop interpolation, produces `bookmarkSizing` and `noteSizing` for downstream components
- View state (display mode, card size, continue collapsed) persisted in CiderConfig
- Display mode and card size controlled by CiderPanelView via bindings, persisted on change

### Performance

- **Home kept alive across tab switches** — `HomeDashboardView` stays in the view tree via ZStack + opacity/allowsHitTesting, so thumbnails, card data, and scroll position persist when switching to other tabs. Other tabs (saved views, search) create/destroy on demand.
- **Async image loading** — All card thumbnails (bookmarks, notes, contacts) load via `Task.detached` + `CGImageSource` to prevent main-thread blocking during scroll.
- **No `CiderConfig.load()` in body** — `HomeDashboardView` uses `@State config` and `StoragePaths` cached paths instead of decoding UserDefaults on every render.

### Sidebar Changes

- "All Items" row removed from FolderSidebarView — sidebar is purely organizational (folders only)
- Home tab serves as "All Items" — want to see everything? Click Home.
- Folder selection on Home tab filters the library feed (not the Continue section)

### Mental Model

| Surface | Shows |
| --- | --- |
| **Home tab** | Everything, mixed. Your library. |
| **Saved view tab** | User-defined filter: any combination of types, labels, folders — replaces the old fixed Bookmarks and Notes tabs |
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
- **Note card click** → Opens inline note editor within the main panel (push/pop navigation — editor takes over the content area, title bar shows note title + back button)

  - Press Escape or click the back arrow to return to the previous view
  - Auto-save flushes on editor close
- **Rejected approach:** Tab-switching on click (loses scroll position, feels disruptive)
- **Previous approach (removed):** Standalone notes panel with modal click-outside-to-dismiss — replaced by inline editor in Feb 2026 panel consolidation

## Planned: Sorting Options

Sort controls in ViewOptionsDropdown for the Home library feed:

- Sort by: creation date, recently modified, title A-Z
- Ascending/descending toggle
- Persisted in CiderConfig as `homeSort` preference
- Currently the feed sorts by `createdDate` descending — this becomes configurable

---

## Implemented: Date Card Surfacing (F-05)

Date cards with approaching dates are visually surfaced so users don't miss important dates.

### Current State

- **`DateCardUrgency` enum** on `DateCard` model: `.approaching(daysUntil:)`, `.today`, `.overdue` — computed via `urgency(now:windowDays:)`
- **Visual indicators:** Date block (month + day) tints by urgency (red = overdue, yellow = today, accent = approaching). Urgency badge pill on cards and list rows ("Overdue", "Today", "In N days")
- **"Coming Up" section** on Home/Inbox tab: horizontal scroll of compact date card cards between Continue section and library feed. Sorted by `startAt` (most urgent first). Hidden when empty.
- **Configuration:** `CiderConfig.dateCardSurfacingDays: Int` (default 7). Set to 0 to disable.
- **All render sites:** Home/Inbox, Folder detail view, Saved View tabs — all pass urgency through.
- Completed date cards never show urgency indicators or appear in Coming Up.

### Future Enhancements (Post-Beta)

- **Per-view "Coming Up" toggle:** Let users show/hide the Coming Up section per saved view tab, not just globally. Some tabs (e.g., a "Bills" tab) might always want it; others (e.g., a "Notes" tab) never do.
- **Notification / sidebar surfacing settings:** Dedicated settings section for Coming Up behavior — configure surfacing window per entity type, enable/disable sidebar badge counts for approaching items, optional system notification for Today/Overdue items.
- **Per-card surfacing override:** `DateCard.rules: [SurfacingRule]` already stores `surfaceDaysBeforeDate(N)` — evaluate it to override the global default per card (e.g., birthdays surface 14 days ahead, bills 7 days).
- **Hybrid sort mode:** Library feed sort that promotes approaching date cards above the normal sort order, with non-promoted items following the user's chosen sort.
- **Continue section integration:** Optionally include surfaced date cards in the Continue section (top 8 recents) alongside recent items.

## Planned: Resurfacing & Rediscovery

Items you save shouldn't disappear into a void. Cider should proactively surface items you've forgotten about — not by age alone, but by actual engagement.

### The Problem with "Sort by Oldest"

Sorting by oldest doesn't surface forgotten items — it surfaces items you may have seen many times. A bookmark created a year ago that you've opened 10 times isn't forgotten. A bookmark created 9 months ago that you've never opened IS forgotten. The sort order can't distinguish these.

### Engagement-Based Resurfacing

Track lightweight engagement signals per item:
- **`lastOpenedAt: Date?`** — last time the user clicked/opened the item (nil = never opened)
- **`openCount: Int`** — total number of opens

The resurfacing algorithm prioritizes items with:
1. **Never opened** (`lastOpenedAt == nil`) — highest priority, sorted oldest first
2. **Not opened recently** (`lastOpenedAt` is far in the past) — weighted by staleness
3. **Low open count** — items opened once 6 months ago rank higher than items opened 10 times

**Scoring formula (conceptual):**
```
resurfaceScore = daysSinceLastOpen * (1 / (openCount + 1))
```
Items with high scores are good candidates for resurfacing. Never-opened items get `daysSinceLastOpen = daysSinceCreation` and `openCount = 0`, giving them the highest scores.

### Resurfacing as a Saved View

Resurfacing is not a built-in mode — it's a **saved view filter dimension** that users opt into:
- Add `sortMode: .resurfacing` to `LibrarySortMode` — sorts by resurface score descending
- Users create a saved view called "Rediscover" with this sort mode
- The view shows their most-forgotten items in the familiar card layout
- Optionally limit to items older than N days (skip very recent captures)

### Resurfacing in the Continue Section

Alternatively (or additionally), the Continue section on Home could mix in 1-2 resurfaced items alongside the 8 most recent. A subtle "You saved this 6 months ago" label distinguishes them from recents.

### AI-Enhanced Discovery

With Apple Intelligence (see `AI_VISION.md`):
- **Similar items** — when viewing a bookmark, Cider suggests related items via NaturalLanguage embedding similarity. "You might also want to revisit these."
- **Contextual resurfacing** — AI notices you're saving React articles and surfaces that React tutorial you bookmarked 8 months ago but never opened
- These suggestions could appear in the detail popover, as a sidebar section, or as cards in the Resurfacing saved view

### Model Changes Required
- Add `lastOpenedAt: Date?` and `openCount: Int` to `Bookmark` and `Note` models
- Increment on every open action (`BookmarksViewModel.open()`, `NotesViewModel` note open)
- Add `resurfacing` case to `LibrarySortMode`
- Add resurfacing score computation to `LibraryViewModel`

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