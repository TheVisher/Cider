# Workspaces Vision: Folders, Projects, and Search

> This document captures the product vision for Cider's organizational system: universal folders, project workspaces, and search-to-tab flow.
>
> **Status:** Phase 1 (Universal Folders) — Complete. Phases 2-4 (Search, Projects) — Future work.

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
3. **Live results** — Split by type: bookmarks, notes, (future: projects, folders).
4. **Actions on results:**
   - Click → opens the item.
   - Enter → spawns a search tab showing all results for that query.

### Search Tabs (Ephemeral)
- A search spawns a temporary tab in the tab bar.
- Shows mixed results (bookmarks + notes matching the query).
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
- Clicking a folder filters the current tab's content to that folder
- Deselecting all folders returns to the full unfiltered tab view

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

## Implementation Priority

1. **Phase 1: Universal Folders** — Rename BookmarkFolder to Folder, add folderID to Notes, universal sidebar.
2. **Phase 2: Center Search Palette** — Cmd+K overlay with live cross-type results.
3. **Phase 3: Search Tabs** — Search results spawn tabs, tab management in tab bar.
4. **Phase 4: Projects** — Project model, sidebar section, promote-from-search, project tabs.
5. **Phase 5: Tear-off & Advanced** — Tear out project tabs as windows, kanban folder views, archiving.
