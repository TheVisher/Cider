# Workspaces Vision: Folders, Projects, and Search

> This document captures the product vision for Cider's organizational system: universal folders, project workspaces, and search-to-tab flow.
>
> **Implementation Status:**
> - ✅ Phase 1 — Universal Folders (complete)
> - ✅ Phase 2 — Center Search Palette (complete)
> - ✅ Phase 3 — Custom Saved View Tabs (complete, `feature/custom-tabs-date-cards-stacks`)
> - 🔲 Phase 4 — Projects UI (ProjectStorage exists; full sidebar + tab UI future)
> - 🔲 Phase 5 — Tear-off windows, Kanban, archiving (future)

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

## Projects

**Purpose:** Active workspaces for ongoing efforts. Workbench for things you're building or researching.

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

## Search

**Purpose:** Find things across all of Cider, with results that can become persistent.

### Search Flow
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
- Can be **promoted to a project** if the search turns into ongoing work.

### Tab States

```
[Home] [Bookmarks] [Notes] [🔍 "react hooks" ×] [🔍 "standing desks" ×] [📌 Game Room ×]
 fixed   fixed      fixed     search tab            search tab           project tab
```

- **Fixed tabs** (Home, Bookmarks, Notes) — always present, not closeable.
- **Search tabs** — ephemeral, closeable, show search results.
- **Project tabs** — persistent (backed by sidebar project), closeable (project stays in sidebar).

---

## Cross-Cutting: Universal Sidebar

The folder sidebar is **universal** — visible across views, not scoped to bookmarks only.

### Design Principle: Sidebar = Organization, Tab Bar = Views

- **Tab bar** shows *what you're looking at* — Home (library), Bookmarks, Notes, future content types
- **Sidebar** shows *how you've organized it* — folders, projects
- "All Items" was removed from the sidebar because it's a view, not a folder
- Clicking a folder opens a standalone folder view (deselects tabs)
- Clicking any tab exits the folder view and returns to tab content

```
FOLDERS
  Restaurants          (3 bookmarks, 1 note)
  Design Resources     (12 bookmarks, 2 notes)
  Work
    └── Internal Tools (5 bookmarks)

PROJECTS
  Game Room            (8 items)
  New Website          (15 items)
  Trip to Japan        (22 items)
```

- Clicking a folder filters the current view to show its contents.
- Clicking a project opens it as a tab.
- Both folders and projects show item counts.
- Notes can be assigned to folders (new capability — notes currently have no folder system).

---

## Data Model Changes

### Current State
- `Bookmark` has `folderID: UUID?` pointing to `BookmarkFolder`.
- `BookmarkFolder` has `parentID: UUID?` for nesting.
- `Note` has no folder/project relationship.

### Required Changes

1. **Rename `BookmarkFolder` → `Folder`** — folders are universal, not bookmark-specific.
2. **Add `folderID: UUID?` to `Note`** — notes can belong to folders.
3. **New `Project` model:**
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
- Works across all tabs (Home, Bookmarks, Notes, Folders) and all display modes
- Mixed content: bookmarks and notes can be multi-dragged together (Home tab, folder views)

- Selection title bar replaces normal title bar: `[X] "N items selected" [Move to Folder ▾] [Delete]`
- Cards: accent border + `SelectionCheckmark` (top-left). List rows: `selectedFill` background + inline checkmark.
- State: `Set<String>` with type-prefixed IDs (`"bookmark-{uuid}"`, `"note-{uuid}"`) owned by CiderPanelView
- Clears on tab switch, folder switch, Escape, or X button
- Continue section (Home tab) excluded from selection
- Works in all display modes (list, grid, masonry) and all tabs (Home, Bookmarks, Notes, Folders)
- Escape key: hidden `Button` + `.keyboardShortcut(.escape)` — `.onExitCommand` doesn't work with `.nonactivatingPanel`
- Future: bulk tag, bulk export

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
- Fuzzy matching for typo tolerance
- Recent searches list

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
