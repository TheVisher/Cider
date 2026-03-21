# Workspaces Vision: Folders, Saved Views, and Search

> This document captures the product vision for Cider's organizational system: universal folders, saved view tabs, and search-to-tab flow.
>
> **Implementation Status:**
> - ✅ Phase 1 — Universal Folders (complete)
> - ✅ Phase 2 — Center Search Palette (complete)
> - ✅ Phase 3 — Custom Saved View Tabs (complete)
> - ~~🔲 Phase 4 — Projects UI~~ — **Removed.** Projects removed from UI and codebase. See decision below.
> - ✅ "New Tab" in +New popover (complete, Feb 2026)
> - 🔲 Phase 4 (new) — Saved View expansion: manual item refs + "Send to view" context action
> - 🔲 Phase 5 — Kanban display mode on Saved Views

---

## Design Decision: Projects Removed (Feb 2026)

Projects were removed from the UI because:

1. **Too much overlap with Saved Views.** Both produce a tab showing a curated list of items. The distinction wasn't meaningful enough at Cider's current scope.
2. **Scope creep risk.** The "project workspace" concept (Kanban, timelines, team collaboration) belongs to heavier tools like Linear or Notion — not what Cider is.
3. **Saved Views can absorb the use case.** Everything Projects was trying to do can be done via Saved Views with future enhancements (see roadmap below).

`ProjectStorage`, `Project` model, and `ProjectItem` model have been removed from the codebase. If the concept is revisited, the models would need to be recreated.

---

## Core Concept

Cider's organization has three layers, each serving a different intent:

| Layer | Intent | Persistence | Example |
|-------|--------|-------------|---------|
| **Folders** | "Where things belong" | Permanent | Restaurants, Design Resources, Work |
| **Projects** | "What I'm working on" | Persistent until archived | Game Room, New Website, Trip to Japan |
| **Search Tabs** | "What I'm looking for right now" | Ephemeral | "react hooks", "standing desks" |

### The Lifecycle

```
Search → Tab → Project → Folder/Archive
```

1. **Search** spawns a temporary tab showing results.
2. You keep the tab open, maybe add items manually.
3. **Promote to Project** — saves it to the sidebar, now it's persistent.
4. Work on the project over days/weeks, adding bookmarks, notes, images.
5. When done, **archive** or **convert to folder** for long-term storage.

---

## Folders

**Purpose:** Long-term categorical organization. Filing cabinet for your digital life.

### Key Properties
- **Universal** — hold both bookmarks AND notes (not bookmarks-only).
- **Hierarchical** — nested folder tree (already supported via `parentID`).
- **Permanent** — folders persist until you delete them.
- **Passive** — you file things away; folders don't imply active work.

### Sidebar Location
Folders live in the sidebar under a "Folders" section, visible across all views.

### Folder View (Implemented)
- Selecting a folder shows a **standalone FolderDetailView** — same rich card components as Home tab (BookmarkCard, NoteCardView, etc.)
- **Tab-independent** — the same folder view shows regardless of which tab was active
- **Tabs deselect** when viewing a folder — clicking any tab exits the folder view
- **Layout:** `ScrollView` with `LazyVStack(pinnedViews: [.sectionHeaders])` — cover image scrolls away, header (title + counts + FOLDERS toggle + sub-folder cards when expanded) sticks at top
- **Root folders** show cover image (if set), sticky header with sub-folder cards, then mixed items below
- **Leaf folders** show cover image (if set), sticky header, then mixed items
- **Empty folders** show header + empty state (no scroll needed)
- Supports all display modes (list, grid, masonry) — shares Home tab's display mode setting
- Drag-and-drop works: items can be dragged onto sub-folder cards or sidebar folders
- Bookmark detail modals open within the folder view; notes open as modal notes panel

### Example Use Cases
- **Restaurants** folder with saved restaurant bookmarks + a note listing ones you've tried.
- **Design Resources** folder with inspiration links, color palette notes, tool bookmarks.
- **Work** folder with project docs, internal tool links, meeting notes.

### Future: Folder Views
Folders could support different view modes beyond a flat list:
- **Kanban** — columns for status (Want to Try / Tried / Loved / Nah).
- **Grid** — visual card layout for browsing.
- **List** — compact sortable list.

---

## Projects (Removed — Feb 2026)

> Projects have been removed from the UI. The section below is retained for historical context and to inform any future revisit. See the design decision at the top of this doc.

**Original purpose:** Active workspaces for ongoing efforts. Workbench for things you're building or researching.

### Key Properties
- **Persistent** — live in the sidebar under a "Projects" section. Closing a tab doesn't delete the project.
- **Active** — implies ongoing work. You're adding to them regularly.
- **Mixed content** — hold bookmarks, notes, images, quotes, links.
- **Openable as tabs** — click a project in sidebar to open it as a tab. Close the tab, project stays.
- **Tearable** — can be torn out as an independent floating window for focused research sessions.

### Sidebar Location
Projects live in the sidebar under a "Projects" section, below Folders.

```
FOLDERS
  Restaurants
  Design Resources
  Work
    └── Internal Tools

PROJECTS
  Game Room
  New Website
  Trip to Japan
```

### How Projects Differ from Folders
- **Folders** = categorical, where things *live* permanently. Static.
- **Projects** = goal-oriented, what you're *working on*. Dynamic, growing.
- A bookmark can be in a "Furniture" folder AND in a "Game Room" project.
- Projects are for collecting resources *for a purpose* — when the purpose is done, archive or convert.

### Example Use Cases
- **Game Room** project — furniture bookmarks, inspiration images, budget note, store links. Tear it out when shopping online.
- **New Website** project — design references, framework docs, competitor sites, implementation notes.
- **Trip to Japan** project — flight bookmarks, hotel options, restaurant recs, itinerary note, packing list note.

### Project Lifecycle
1. Created explicitly ("New Project") or promoted from a search tab.
2. Lives in sidebar Projects section.
3. Opened as a tab when you want to work on it.
4. Closed tab — project persists in sidebar.
5. When done: archive (hide from sidebar) or convert to folder (permanent storage).

---

## Saved Views — Future Roadmap

Saved Views are currently filter-only (dynamic). The roadmap expands them to absorb everything Projects was meant to do.

### Phase 4 — Manual Item Refs ("Send to View")

Add `manualItemRefs: [LibraryEntityRef]` to `SavedView`. A saved view can then be:
- **Filter-driven** — content auto-populates from filter rules (current)
- **Manually curated** — items pinned explicitly by the user
- **Both** — filter provides the base set; manual refs add specific items on top

**"Send to view" context action** — right-click any item anywhere in the library → "Add to [View Name]" → pins it to that saved view's `manualItemRefs`. This is how users build curated collections without a separate "Projects" concept. A saved view with no filter spec and only manual refs is effectively a "collection tab."

This mirrors how Stacks already work (`matchRules` + `manualItemRefs`) — apply the same pattern to SavedView.

### Phase 5 — Kanban Display Mode

Add `kanban` as a display mode option on Saved Views (alongside list, grid, masonry). Columns map to a user-chosen attribute — label, folder, status field, or a custom column set. Dragging a card between columns reassigns that attribute on the item.

Any saved view can become a Kanban — you don't need a separate "board" or "project" concept. A "Game Room renovation" Kanban is just a saved view in Kanban mode.

### Create Tab from +New Popover ✅ Implemented (Feb 2026)

The "Tab" card fills the slot left by the removed "Project" card. The +New picker is now a full 3×2 grid: Bookmark, Note, Event, Contact, Folder, Tab.

**Flow:**
1. Click +New → popover opens
2. Click "Tab" card (icon: `rectangle.badge.plus`)
3. Name field — user types tab name (Create Tab button disabled until non-empty)
4. Content pills — four toggleable pills: **Bookmarks**, **Notes**, **Events**, **Contacts** (all selected by default = "Everything"; last one can't be deselected)
5. "Create Tab" — `SavedView` created with `isTabPinned: true` and selected `entityTypes` as `filterSpec`. Panel navigates immediately to the new tab.

**Two entry points for the same result:**
- **+New → Tab** — for users who know what they want upfront (name it, pick content type)
- **Search → Save as tab** — for users who discover a useful query mid-session

**Future refinements (not yet implemented):**
- "By label" and "By folder" filter pills in the creation form
- Folder picker integration so users can scope a tab to a specific folder at creation time
- "Unfiled items only" toggle — `requireUnfiled: Bool` on `SavedViewFilterSpec`, filters to items where `folderID == nil`

### Inbox as a User-Created View

An "Inbox" is not a built-in concept — it's a saved view the user creates with the "Unfiled" filter enabled. This keeps the architecture simple: the inbox is just a filter, not a special mode.

**How to create one:**
1. +New → Tab → name it "Inbox"
2. Enable "Unfiled only" filter (once the `requireUnfiled` chip is implemented)
3. The tab now shows every item that hasn't been organized into a folder yet

**Workflow:** Capture freely without thinking about organization. Items land in the library with no folder. When you're ready to triage, open your Inbox tab and drag items into folders. As items get organized, they disappear from the Inbox view automatically.

This is the same approach as Resurf's inbox-first workflow, but opt-in and user-configured rather than forced.

---

## Search

**Purpose:** Find things across all of Cider, with results that can become persistent.

### Live Search (Planned — Replaces Command Palette for Item Search)

The current search palette (Cmd+K overlay) shows results in a separate floating list. A better model: **search filters the current view in-place**.

**How it works:**
- Double-tap Option → panel opens → search field in title bar is auto-focused
- User starts typing immediately — no extra shortcut needed
- The current tab's content filters live as you type (same masonry/grid/list layout, just fewer items)
- Search "YouTube" on the Home tab → all YouTube bookmarks appear in the familiar card layout, scrollable and browsable
- Clear the search → full view returns instantly

**Why this is better:**
- Results stay in context — you see cards with thumbnails, not a flat list of titles
- You can browse filtered results (scroll, right-click, open details) just like normal
- No mode switch — search IS the view, not a separate overlay
- Double-tap Option + type = instant access to anything in your library

**Implementation:**
- `SavedViewFilterSpec.textQuery` already supports live text filtering in saved view tabs
- Extend this to the Home tab's library feed (bind a search field to `LibraryViewModel` filtering)
- Auto-focus the search field on panel open (with the existing 150ms delay for `@FocusState` in NSPanel)

**Command palette repurposed:**
- Cmd+K becomes an **action palette** — create note, open settings, switch tab, run shortcuts
- Item search moves entirely to the inline search field
- The action palette is a command runner (like Raycast), not a content finder

### Search Flow (Current)
1. **Trigger** — Click search field in title bar, press Cmd+K, or type `/`.
2. **Center palette opens** — Zen-style overlay, blurs background content.
3. **Live results** — Split by type: bookmarks, notes, date cards, contacts. Debounced 100ms.
4. **Actions on results:**
   - Click → opens the item.
   - Enter → spawns a search tab showing all results for that query.

### Result Display
- **Title match** → subtitle shows host URL (bookmark), first 80 chars of content (note), formatted date (date card), or relationship label (contact).
- **Body-only match** → snippet shown instead of subtitle: `…prefix **match** suffix…` where the matched portion renders in primary color and surrounding context in tertiary. Implemented via `SearchSnippet` struct + inline `AttributedString` in result rows.
- Fields searched per type:
  - **Bookmark:** title, URL, host, tags, notes field
  - **Note:** title, stripped HTML body
  - **DateCard:** title, details, location
  - **Contact:** displayName, relationshipLabel, notes

### Search Tabs (Ephemeral)
- A search spawns a temporary tab in the tab bar.
- Shows mixed results across all content types (bookmarks, notes, date cards, contacts).
- Close anytime — nothing is lost, it's just a search view.
- Can be **saved as a Saved View** if the search turns into ongoing work.

### Tab States

```
[Home] [📌 Design Inspo ×] [📌 Work ×] [🔍 "react hooks" ×] [📂 Cider Docs ×]
 fixed    saved view          saved view    search tab          external source
```

- **Home** — only fixed tab, always present, not closeable.
- **Saved View tabs** — user-created, persistent, closeable.
- **Search tabs** — ephemeral, closeable, show mixed search results.
- **External Source tabs** — linked filesystem directories, closeable.

---

## Cross-Cutting: Universal Sidebar

The folder sidebar is **universal** — visible across views, not scoped to bookmarks only.

### Design Principle: Sidebar = Organization, Tab Bar = Views

- **Tab bar** shows *what you're looking at* — Home (your full library), plus saved views and search tabs the user creates
- **Sidebar** shows *how you've organized it* — folders and linked sources
- "All Items" was removed from the sidebar because it's a view, not a folder
- Clicking a folder opens a standalone folder view (deselects tabs)
- Clicking any tab exits the folder view and returns to tab content

```
FOLDERS
  Restaurants          (3 bookmarks, 1 note)
  Design Resources     (12 bookmarks, 2 notes)
  Work
    └── Internal Tools (5 bookmarks)

SOURCES
  📂 Cider Docs        (12 files)
```

- Clicking a folder opens a standalone folder view (deselects the current tab).
- Clicking any tab exits the folder view.
- Folders show item counts.
- Notes can be assigned to folders.

---

## Data Model Changes

### Current State
- `Bookmark` has `folderID: UUID?` pointing to `Folder`.
- `Folder` has `parentID: UUID?` for nesting (renamed from `BookmarkFolder`).
- `Note` has `folderID: UUID?` — notes belong to folders.

### Completed Changes

1. ✅ **Renamed `BookmarkFolder` → `Folder`** — folders are universal, not bookmark-specific.
2. ✅ **Added `folderID: UUID?` to `Note`** — notes can belong to folders.

### Historical (Projects — Removed)

3. **`Project` model (dormant):**
   ```
   Project {
     id: UUID
     name: String
     createdAt: Date
     updatedAt: Date
     isPinned: Bool        // pinned = visible in sidebar always
     isArchived: Bool      // archived = hidden from sidebar
     searchQuery: String?  // if promoted from search, the original query
   }
   ```
4. **New `ProjectItem` model (join table):**
   ```
   ProjectItem {
     id: UUID
     projectID: UUID
     bookmarkID: UUID?     // one of these is set
     noteID: UUID?         // one of these is set
     addedAt: Date
     sortOrder: Int
   }
   ```
5. A bookmark/note can be in ONE folder but MULTIPLE projects.

---

## Folder Refinements (Planned)

### Folder Rename
Right-click context menu on folders in the sidebar should include "Rename." Uses inline editing pattern — folder name swaps to a focused text field, Enter to save, Escape to cancel. Same pattern as card inline rename.

### Folder Header with Title + Breadcrumb
FolderDetailView should have a header area showing:
- **Folder title** in heading font
- **Breadcrumb path** in smaller text below (e.g., "Work > Internal Tools > APIs")
- Breadcrumb is most useful when the sidebar is collapsed — provides context about where you are
- Each breadcrumb segment is clickable to navigate up

### Folder Header Image
**Status: Implemented.**
Folders have optional cover images displayed at the top of FolderDetailView (Notion-style).
- 160pt banner, drag-to-reposition vertically (normalized 0.0–1.0 offset, persisted)
- Set/change/remove via right-click context menu on header or cover image
- Cover scrolls away when scrolling; header sticks via `LazyVStack(pinnedViews: [.sectionHeaders])`
- `CoverRepositionOverlay` NSViewRepresentable blocks `isMovableByWindowBackground` window drag
- Uses AppKit event loop (`window.nextEvent`) pattern (same as PanelEdgeResizeView)
- Image downsampled to 800px via `CGImageSourceCreateThumbnailAtIndex`
- Stored in `.folder-covers/` directory; `Folder.coverImagePath` + `coverImageOffsetY` on model
- NSOpenPanel for image picker requires `NSApp.activate(ignoringOtherApps: true)` before `runModal()` — non-activating panel doesn't give the file picker proper focus otherwise

### Sub-Folders Section in Folder View
**Status: Implemented.**
- "FOLDERS >" toggle on the same line as the folder title (right-aligned, `SectionCollapseToggle`)
- Sub-folder cards are part of the sticky Section header — they pin while scrolling
- Collapsible with `.snappy` animation; state persisted
- Shows sub-folder cards in a compact grid (clickable to navigate deeper)
- Below the sticky header: the folder's own items (bookmarks + notes)

### Sticky Header Readability (Unsolved)
The pinned folder header (title, counts, FOLDERS toggle, sub-folder cards) currently has no background.
Content scrolls visibly through/behind the header text, making it unreadable when cards overlap.

**Rejected approaches (avoid revisiting):**
- **Full-width acrylic background** (VisualEffectView + tint) — looks like an ugly solid dark bar, especially when nothing is scrolled under it
- **Scroll-triggered dark overlay** — same ugly bar, just delayed. Jarring when it appears.
- **Gradient fade below header** — doesn't help because content passes *through* the header text, not under the gradient
- **Frosted rail always-on** (blur + subtle tint + border) — ugly dark strip when no content underneath
- **Per-element backplates** (small dark pills behind each text element, overlap-triggered) — rejected, felt cluttered

**Still exploring:** Need a solution that provides readability without adding any visible surface when content isn't behind the header. Text shadow/glow on the header text is one untried option.

### Folder Sorting Options
Folders need their own sort controls in the view options dropdown:
- Sort by: creation date, recently modified, title A-Z/Z-A
- Ascending/descending toggle
- Per-folder sort persistence (each folder remembers its preferred sort)

### Custom Folder Icons
Allow users to change the folder icon in the sidebar:
- Right-click > "Change Icon" on any folder row
- Pick from SF Symbols or emoji
- Store as `iconName: String?` in `Folder` model
- Default to "folder.fill" for roots, "folder" for sub-folders

### Sidebar Folder Drag Reorder & Nesting
Drag folders in the sidebar to:
- **Reorder** — change the display order of sibling folders
- **Nest** — drag a root folder onto another root folder to make it a child/sub-folder
- Drop indicators (line between items for reorder, highlight on folder for nesting)
- Hover-to-expand: hovering a collapsed folder during drag auto-expands it after a short delay

---

## Cross-Cutting Features

### Multi-Select ✓
Implemented. Cmd-click toggles, Shift-click range-selects, Cmd+A selects all visible, Escape clears.

#### Drag & Drop ✓
When dragging a selected item, all selected items travel together and drop as a group.
Dragging an unselected item while others are selected drags only that single item.

**Fanned preview** (Finder-style):
- 1 item: normal single-card preview
- 2 items: 2-card fan
- 3+ items: 3-card fan + count badge (capsule, accent bg, white text) when total > 3
- Fan geometry: 6° rotation, 16pt X offset, 8pt Y offset per successive card
- Works across all tabs (Home, saved views, folders) and all display modes
- Mixed content: bookmarks and notes can be multi-dragged together (Home tab, folder views)

- Selection title bar replaces normal title bar: `[X] "N items selected" [Move to Folder ▾] [Delete]`
- Cards: accent border + `SelectionCheckmark` (top-left). List rows: `selectedFill` background + inline checkmark.
- State: `Set<String>` with type-prefixed IDs (`"bookmark-{uuid}"`, `"note-{uuid}"`) owned by CiderPanelView
- Clears on tab switch, folder switch, Escape, or X button
- Continue section (Home tab) excluded from selection
- Works in all display modes (list, grid, masonry) and all tabs (Home, saved views, folders)
- Escape key: hidden `Button` + `.keyboardShortcut(.escape)` — `.onExitCommand` doesn't work with `.nonactivatingPanel`
- Future: bulk tag, bulk export

#### Drag Out to External Apps

Currently drag providers only register internal Cider type identifiers (`com.cider.bookmark-id`, `com.cider.note-id`). External apps can't consume these. To enable drag-out, register standard UTTypes alongside the internal ones on the same `NSItemProvider`:

| Item type | Register | External behavior |
|---|---|---|
| Bookmark | `public.url` with the bookmark's URL | Browsers open the URL; Finder creates `.webloc` |
| Note | `public.file-url` with the `.md` file path | Editors, CLIs, Finder receive the actual file |
| Bookmark thumbnail | `public.file-url` with local thumbnail path | Image editors receive the image file |

Implementation notes:
- Add `provider.register(NSString(string: bookmark.urlString) as NSURL)` (or equivalent `public.url` registration) to each `bookmarkDragProvider` function
- Add `provider.register(note.fileURL as NSURL)` (or equivalent `public.file-url` registration) to each `noteDragProvider` function
- Internal Cider types stay registered so Cider-to-Cider drag (folder shelf, reorder) still works
- Multi-drag: register standard types on the primary item's provider; secondary items are internal-only
- Drag providers exist in 3 places: `BookmarksBrowserView`, `HomeDashboardView`, `FolderDetailView` — all must be updated

Use cases:
- Drag a bookmark onto a browser tab bar → opens the URL
- Drag a note onto Claude Code CLI → CLI reads the `.md` file path
- Drag a bookmark card onto Finder → creates a `.webloc` shortcut
- Drag a note onto a text editor → editor opens the markdown file

### Undo System ✓
Reversible actions should support undo via a transient toast:
- Toast appears for ~5 seconds after destructive/organizational actions with an "Undo" button
- Actions that support undo: delete, move to folder, move to trash, bulk operations
- Single-level undo (undo the most recent action)
- Toast dismisses on timeout or manual dismiss; clicking "Undo" reverses the action immediately

**Implemented.** `CiderUndoManager` singleton tracks one pending `UndoAction`. Timer-driven 5-second progress bar with hover-to-pause matches the clipboard review toast pattern. Delete actions show an additional "Trash" button to open Settings → Storage. Toast position is user-configurable per toast type (capture toast and undo toast have separate position settings).

### Trash System ✓
Deleted items go to a Trash instead of being permanently removed:
- **30-day retention** — items auto-purge after 30 days in trash
- Trash is accessible from **Settings → Storage** (not the sidebar)
- Trash view shows items with their deletion date and days remaining
- Actions in trash: Restore (moves back to original folder), Delete Permanently
- "Empty Trash" option for manual purge
- Items in trash don't appear in search results, Home feed, or folder views
- Affects both bookmarks and notes

**Implemented.** `TrashStorage` manages `.trash/` subdirectories inside each storage directory with JSON manifests. Bookmarks move image assets to `.trash/thumbnails|originals/`. Notes move `.md` files to `.trash/`. Retention is configurable (7/30/90 days or Never) in Settings → Storage. Auto-purge runs on launch.

### Keyboard Navigation
Power-user keyboard shortcuts for the floating panel:
- **Arrow keys** to move between cards in grid/masonry (left/right/up/down)
- **Enter** to open the selected item
- **Delete/Backspace** to trash the selected item
- **Cmd+Shift+N** to create a new note
- **/** to focus the search field
- **Escape** to deselect or dismiss
- Visual focus ring on the currently selected card

### Sorting Options
Global sort controls in ViewOptionsDropdown, available on all tabs:
- Sort by: creation date, recently modified, title A-Z
- Ascending/descending toggle
- Sort preference persisted per-tab in CiderConfig

### Group By (Future)
Group items into visual sections within a view:
- Group by: date (Today, Yesterday, This Week, This Month, Older), type (bookmarks vs notes), domain (for bookmarks), tags (when implemented)
- Collapsible group headers
- Works alongside sorting (sort within each group)

### Search Refinement (Future)
Enhance the search palette with:
- Type filter chips (Bookmarks, Notes, or both)
- Folder filter (search within a specific folder)
- Date range filter
- ✅ Token matching — query split into words, each must match independently. "nuts nerdy" finds "Nerdy Nuts". Uses `localizedStandardContains` for diacritic/case-insensitive matching ("cafe" → "Café").
- True fuzzy matching (Sublime Text / fzf style) — characters appear in order but not adjacently ("nrdnts" → "Nerdy Nuts"). Needs scoring to rank results by match quality. Useful for power users but produces noisier results than token matching. Consider as opt-in or for the command palette only.
- Recent searches list

### Search Scope Modifiers (Future)

Currently the sidebar live search is scoped to whatever view is active — Home tab searches the full library, a folder view searches within that folder, a saved view tab searches within its filtered results. This is the right default. But power users may want to reach outside the current view without navigating away.

**`@`-prefix modifiers** in the search field change the scope on the fly:

| Modifier | Scope | Example |
|---|---|---|
| *(none)* | Current view (default) | `react hooks` — searches whatever is on screen |
| `@all` | Entire library | `@all react hooks` — searches everything regardless of current view |
| `@folder-name` | Named folder | `@Design Resources color palette` — searches within that folder |
| `@bookmarks` | All bookmarks | `@bookmarks typescript` — bookmarks only, any folder |
| `@notes` | All notes | `@notes meeting agenda` — notes only, any folder |

**Behavior:**
- Typing `@` shows an autocomplete dropdown of available scopes (folder names, type filters)
- The modifier is parsed and stripped before the text query runs — the rest of the string is the search term
- Modifier chip appears as a removable pill left of the search text (visual confirmation of active scope)
- Clearing the modifier (backspace through it or click the pill's ×) returns to default current-view scope
- Folder name matching is case-insensitive and supports partial matches (`@des` → suggests "Design Resources")

**Why this fits:**
- Keeps the single search field as the only entry point — no separate "search everywhere" UI
- Discoverable but not required — users who never type `@` get the same scoped search they already have
- Consistent with how other tools use prefix modifiers (Slack's `in:#channel`, Raycast's file filters)
- Composable with future modifiers: `@bookmarks @Design Resources` could mean "bookmarks in Design Resources folder"

**Not for immediate implementation** — this builds on top of the planned Live Search (above) and should come after that is solid.

**Gap: Linked Sources** — The sidebar live search currently does not filter linked source views (`SourceDetailView`). Source files are not wired to `sidebarSearchText`. This should be addressed alongside scope modifiers or as a standalone follow-up — add a `searchText` param to `SourceDetailView` and filter its file listing by title/content match.

### macOS Services Integration

Register Cider as a macOS Services provider so users can right-click selected content in any app and send it to Cider.

**How it works:**
- Select text, a URL, or an image in any app → right-click → Services → "Send to Cider"
- Cider routes by content type:
  - **URL detected** → captured as a bookmark (triggers enrichment pipeline)
  - **Plain text** → created as a new note
  - **Image** → saved as a document/image (future Documents tab) or attached to a new note
- Capture toast confirms the action (reuses existing toast system)

**Implementation:**
- Register service in `Info.plist` with `NSServices` array (send types: `NSStringPboardType`, `NSURLPboardType`, `NSPasteboardTypePNG/TIFF`)
- Handle `NSPerformService` in AppDelegate — inspect pasteboard, route to `BookmarksStorage.capture()` or `NotesStorage.create()` based on content type
- URL detection reuses the existing `normalizedURL()` logic from `BookmarksStorage`
- No UI needed beyond the existing capture toast

**Complements existing capture flows:**
- Hotkeys (Opt+B, Opt+N) — fastest, muscle memory
- Clipboard monitoring — automatic, passive
- Drag & drop — visual, intentional
- **Services** — contextual, from any app's right-click menu

### Card Customization Sliders (Future)
Additional sliders in ViewOptionsDropdown alongside the existing card size slider:
- **Padding slider** — adjust internal card padding (content density)
- **Spacing slider** — adjust gap between cards in grid/masonry (breathing room)
- These compound with the card size slider for fine-grained visual tuning

---

## Themed Folders

**Concept:** Folders can have a **theme** that transforms their entire visual presentation, card layout, and organizational features based on content type. A themed folder isn't just a collection of bookmarks — it becomes a specialized micro-app with an aesthetic and UX tailored to that content.

Default folders use the standard Cider card layout (BookmarkCard, NoteCardView). Themed folders replace this with a completely different visual system while keeping the same underlying data (bookmarks + notes + metadata).

### Media Hub Theme

Transform a folder into a Netflix/Apple TV-style media browser. For saving movies, TV shows, documentaries, and anything you want to watch or have watched.

**Visual aesthetic:**
- Large poster-art cards (portrait orientation, like streaming service tiles)
- Hero banner at top — featured/pinned item with backdrop image, title overlay, genre tags
- Horizontal scrolling rows by category (Watching, Watchlist, Completed, Dropped)
- Card hover: subtle scale + metadata overlay (year, rating, runtime)
- Dark, cinematic feel — leans into the acrylic panel aesthetic

**Card enrichment:**
When you save an IMDB, Letterboxd, TMDB, or similar URL, Cider enriches the bookmark with:
- Poster artwork (high-res, portrait crop for the card)
- Backdrop image (for hero banner or detail view)
- Rotten Tomatoes / IMDB score
- Runtime, release date, genres, director, cast
- For TV shows: season/episode count, air status (ongoing/ended)
- Sources: TMDB API (free, comprehensive), OMDB API, or scrape from the bookmarked page

**TV show episode tracking:**
- Expand a TV show card to see seasons and episodes
- Mark episodes as watched/unwatched individually
- Track progress: "Season 2, Episode 4 of 10"
- Integration with **Trakt.tv** — sync watch status bidirectionally so marking something watched in Cider updates Trakt, and watching something on your TV updates Cider
- Episode cards show: title, thumbnail, air date, runtime, brief synopsis

**Smart organization:**
- Auto-categorize into sections: Watching, Watchlist, Completed, Dropped, Favorites
- Status is per-item (set via right-click or swipe gesture on cards)
- Sub-folders or smart sections by genre, year, rating
- "Up Next" section — shows with unwatched episodes, sorted by air date

**AI-powered features** (see AI_VISION.md):
- Similar show/movie suggestions based on what's in the folder ("You liked these 5 sci-fi shows, you might like...")
- Auto-genre classification from page content if metadata API misses it
- Natural language filter: "show me comedies from the 2010s I haven't watched"

**Data flow:**
```
User saves IMDB/TMDB URL → Cider captures bookmark
  → Detect media URL (domain or page structure)
  → Fetch metadata from TMDB API (poster, backdrop, scores, cast, episodes)
  → Store enriched metadata on bookmark model (extended fields)
  → Render with Media Hub card layout instead of standard BookmarkCard
  → Trakt.tv sync (if connected): push/pull watch status
```

### Recipe Theme

Transform a folder into a visual recipe collection. For saving recipes from cooking sites, food blogs, YouTube cooking videos.

**Visual aesthetic:**
- Large food photography thumbnails (landscape, hero-style)
- Card overlay: recipe title, cook time, servings, difficulty
- Warm, appetizing color accents
- Cards feel like physical recipe cards — clean typography, ingredients visible

**Card enrichment:**
Most recipe sites use **Schema.org Recipe markup** (`application/ld+json`), which means structured data is already on the page:
- Recipe name, description, author
- Cook time, prep time, total time
- Servings / yield
- Ingredients list
- Step-by-step instructions
- Nutrition info (calories, macros)
- High-quality food photography
- Cider extracts this on capture — no API needed, it's in the page source

**Card layout variations:**
- **Photo card:** Full-bleed food image, title + time overlay at bottom (default)
- **Recipe card:** Split layout — image on left, ingredients list on right (for planning)
- **Compact list:** Title + time + thumbnail (for searching/browsing quickly)

**Useful features:**
- Ingredient aggregation — select multiple recipes, see combined ingredient list (meal planning / grocery list)
- Cooking mode — open a recipe full-panel with large text, step-by-step, screen stays on
- Tag by cuisine, meal type, dietary restrictions (AI auto-tag or manual)
- "Tried it" / "Want to make" status tracking
- Notes field per recipe for personal tweaks ("used less salt", "double the garlic")

### Other Potential Themes (Future Exploration)

- **Reading List** — book covers, Goodreads integration, read/unread/reading status, page progress
- **Music** — album art grid, Spotify/Apple Music integration, playlist building
- **Travel** — map view with pinned locations, trip grouping, photos, itinerary timeline
- **Shopping** — price tracking, product images, purchase status, wishlists
- **Learning** — course cards, progress tracking, certificate display, learning paths

### Architecture Implications

**Folder model changes:**
- `Folder.theme: FolderTheme?` — enum: `.default`, `.mediaHub`, `.recipe`, `.readingList`, etc.
- Theme is set via folder context menu ("Set Theme → Media Hub") or auto-suggested based on content

**Pluggable renderers:**
- `FolderDetailView` checks `folder.theme` and delegates to the appropriate renderer
- Each theme has its own card component, layout logic, and section organization
- Standard folder uses existing `BookmarkCard` / `NoteCardView`
- Media Hub uses `MediaCard`, `EpisodeRow`, `HeroCarousel`
- Recipe uses `RecipeCard`, `IngredientsList`, `CookingModeView`

**Extended metadata:**
- Bookmark model gets a flexible `metadata: [String: AnyCodable]?` field for theme-specific data
- Media Hub stores: poster URL, backdrop URL, scores, cast, episodes, watch status
- Recipe stores: ingredients, steps, cook time, servings, nutrition
- Metadata fetched on capture via theme-appropriate enrichment (TMDB API, Schema.org extraction, etc.)

**Third-party integrations:**
- Trakt.tv: OAuth flow in settings, background sync service
- Future: Goodreads, Spotify, etc. — same pattern (OAuth + sync service per integration)

---

## Implementation Priority

1. **Phase 1: Universal Folders** — Rename BookmarkFolder to Folder, add folderID to Notes, universal sidebar.
2. **Phase 2: Center Search Palette** — Cmd+K overlay with live cross-type results.
3. **Phase 3: Search Tabs** — Search results spawn tabs, tab management in tab bar.
4. **Phase 4: Projects** — Project model, sidebar section, promote-from-search, project tabs.
5. **Phase 5: Tear-off & Advanced** — Tear out project tabs as windows, kanban folder views, archiving.

### Refinement Priority (Current Focus)

1. **Folder rename** — right-click context menu + inline editing in sidebar
2. **Multi-select** — shift/cmd-click selection with bulk operations
3. **Undo system** ✓ — transient toast with "Undo" button
4. **Trash system** ✓ — 30-day retention, restore/permanent delete
5. **Sorting options** — per-tab sort controls
6. **Folder header + breadcrumb** — title and navigation in FolderDetailView
7. **Sub-folders section** — collapsible sub-folder cards at top of folder view
8. **Sidebar drag reorder/nesting** — reorder and nest folders via drag
9. **Keyboard navigation** — arrow keys, enter, delete shortcuts
10. **Card customization sliders** — padding and spacing controls
