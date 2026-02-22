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

## Planned: Date Card Surfacing

Date cards should behave like calendar events — they surface near the top of the library feed when their scheduled date approaches, not just when they were created.

### Behavior

- A date card created in January for a June birthday should sit in the library at its creation position, then **resurface near the top** as the date approaches
- Surfacing window is configurable: "Show N days before" (default: 7 days)
- Once surfaced, the card stays promoted until the event passes or is marked completed
- Completed date cards stop surfacing regardless of date proximity

### Sort Integration

The library feed sort should support a **hybrid mode** (likely the default) that:
1. Evaluates each date card's `startAt` against the current date + surfacing window
2. Promotes matching date cards above the normal sort order
3. Among promoted cards, sorts by nearest `startAt` first (most urgent on top)
4. Non-promoted items follow the user's chosen sort (created, modified, title, etc.)

### Configuration

- **Global default**: `CiderConfig.dateCardSurfaceDaysBefore: Int` (default 7) — applies to all date cards without per-card rules
- **Per-card override**: `DateCard.rules: [SurfacingRule]` already exists (stored but not evaluated) — `surfaceDaysBeforeDate(N)` should override the global default when present
- **Settings UI**: slider or stepper in Settings → General or a dedicated "Surfacing" section

### Implementation Notes

- `DateCard.rules` field is already persisted in JSON — just needs evaluation in `LibraryViewModel`
- `LibraryItemV2.dateAnchor` already extracts `startAt` — the surfacing check is: `dateAnchor >= now && dateAnchor <= now + N days`
- Stack surfacing logic (`isSurfaceRuleTriggered`) already implements `surfaceDaysBeforeDate(N)` — the same logic applies to individual date cards
- The Continue section (top 8 recents) could optionally include surfaced date cards, or surfacing could be limited to the library feed only

### Examples

| Scenario | Surfacing window | Behavior |
| --- | --- | --- |
| Birthday on June 15, created Jan 10 | 14 days | Appears at creation position until June 1, then surfaces to top |
| Bill due March 1, created Feb 20 | 7 days | Surfaces Feb 22 (7 days before) |
| Meeting tomorrow, created today | 1 day | Surfaces immediately (within window) |
| Past event (Feb 10), today is Feb 21 | any | Does not surface (date has passed) |
| Completed event | any | Does not surface |

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