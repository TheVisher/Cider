# Workspaces Implementation Plan

> Step-by-step plan for implementing universal folders, center search palette, search tabs, and projects.
> See `WORKSPACES_VISION.md` for the full product vision.

---

## Phase 1: Universal Folders

**Goal:** Folders hold both bookmarks AND notes. Sidebar is universal across views.

### Step 1.1: Rename BookmarkFolder to Folder

**Files to modify:**
- `Sources/Cider/Models/BookmarkFolder.swift` → rename file to `Folder.swift`, rename struct to `Folder`
- `Sources/Cider/Services/BookmarksStorage.swift` — update all `BookmarkFolder` references to `Folder`
- `Sources/Cider/ViewModels/BookmarksViewModel.swift` — update type references
- `Sources/Cider/Views/Bookmarks/BookmarksBrowserView.swift` — update type references (BookmarkFolderSidebarRow → FolderSidebarRow, etc.)
- `Sources/Cider/Views/Bookmarks/BookmarksTabContent.swift` — update any folder type references
- Any other files referencing `BookmarkFolder` (grep for all occurrences)

**Changes:**
- Pure rename, no behavior change
- `BookmarksMetadataSnapshot` keeps `folders: [Folder]` (same JSON key, type changes)

### Step 1.2: Add folderID to Note

**Files to modify:**
- `Sources/Cider/Models/Note.swift` — add `var folderID: UUID?`
- `Sources/Cider/Services/NotesStorage.swift` — persist folderID in note metadata
- `Sources/Cider/ViewModels/NotesViewModel.swift` — add folder assignment methods

**Changes:**
- Note gains `folderID: UUID?` field
- NotesStorage saves/loads folderID
- NotesViewModel exposes `assign(_ note: Note, toFolder folderID: UUID?)` method

### Step 1.3: Centralize folder storage

Currently folders are stored inside `BookmarksStorage` as part of `BookmarksMetadataSnapshot`. They need to become independent since they're now shared between bookmarks and notes.

**New file:**
- `Sources/Cider/Services/FolderStorage.swift` — singleton managing folder CRUD, persistence

**Files to modify:**
- `Sources/Cider/Services/BookmarksStorage.swift` — remove folder storage, delegate to FolderStorage
- `Sources/Cider/ViewModels/BookmarksViewModel.swift` — get folders from FolderStorage

**Changes:**
- `FolderStorage.shared` owns `@Published folders: [Folder]`
- `FolderStorage` handles create, delete, rename, subtree operations
- `BookmarksStorage` still persists bookmarks but delegates folder ops to `FolderStorage`
- Migration: on first launch, reads folders from `_cider_bookmarks_metadata.json` and moves them to `_cider_folders.json`

### Step 1.4: Extract universal folder sidebar

Currently the folder sidebar is embedded in `BookmarksBrowserView` (~200 lines). Extract it into a standalone component that can be used in CiderPanelView across all tabs.

**New file:**
- `Sources/Cider/Views/Shared/FolderSidebarView.swift` — extracted folder sidebar

**Files to modify:**
- `Sources/Cider/Views/Bookmarks/BookmarksBrowserView.swift` — remove inline folder sidebar, use shared component
- `Sources/Cider/Views/CiderPanelView.swift` — add folder sidebar to the left of tab content

**Changes:**
- `FolderSidebarView` takes:
  - `folders: [Folder]`
  - `selectedFolderID: Binding<UUID?>`
  - `expandedFolderIDs: Binding<Set<UUID>>`
  - Callbacks for create, rename, delete, drop
- Sidebar visible on left side of CiderPanelView, persistent across tab switches
- BookmarksBrowserView removes its internal sidebar code, receives `selectedFolderID` from parent

### Step 1.5: Filter notes by folder

**Files to modify:**
- `Sources/Cider/Views/Notes/NotesTabContent.swift` — filter by selectedFolderID
- `Sources/Cider/Views/CiderPanelView.swift` — pass selectedFolderID to NotesTabContent

**Changes:**
- NotesTabContent accepts `selectedFolderID: UUID?` and filters displayed notes
- When a folder is selected, both bookmarks tab and notes tab filter to that folder's contents
- Home tab shows unfiltered dashboard (ignores folder selection)

### Step 1.6: Build and verify

- `swift build` succeeds
- Folder sidebar appears in CiderPanel, persists across tab switches
- Creating a folder works
- Assigning bookmarks to folders works (existing behavior preserved)
- Notes can be assigned to folders (new)
- Selecting a folder filters both bookmarks and notes tabs

---

## Phase 2: Center Search Palette

**Goal:** Cmd+K / clicking search triggers a Zen-style center palette with live cross-type results.

### Step 2.1: Search palette overlay view

**New files:**
- `Sources/Cider/Views/Search/SearchPaletteView.swift` — center overlay with search field + categorized results

**Changes:**
- Full-screen overlay within CiderPanelView (like the bookmark details overlay pattern)
- Blurred backdrop, centered search field, live-updating results below
- Results split into sections: Bookmarks, Notes, (future: Folders, Projects)
- Each result row shows type icon, title, and metadata preview
- Click result → opens it (bookmark opens URL, note opens editor)
- Enter with text → spawns a search tab (Phase 3)
- Escape → dismisses palette

### Step 2.2: Cross-type search service

**New file:**
- `Sources/Cider/Services/SearchService.swift` — unified search across bookmarks and notes

**Changes:**
- `SearchService` queries both `BookmarksStorage` and `NotesStorage`
- Returns `[SearchResult]` with type discrimination (bookmark vs note)
- Fuzzy/substring matching on title, URL (bookmarks), content preview (notes), tags
- Debounced (100ms) to avoid excessive filtering

### Step 2.3: Wire up triggers

**Files to modify:**
- `Sources/Cider/Views/CiderPanelView.swift` — show search palette on Cmd+K or search field click
- `Sources/Cider/Utilities/Constants.swift` — add search palette notification names if needed

**Changes:**
- Clicking the search field in title bar opens the search palette (instead of inline filtering)
- Cmd+K keyboard shortcut opens search palette
- Search palette state managed as `@State private var isSearchPaletteVisible = false`

### Step 2.4: Build and verify

- `swift build` succeeds
- Cmd+K opens center search palette
- Typing shows live results from both bookmarks and notes
- Clicking a result opens it
- Escape dismisses

---

## Phase 3: Search Tabs

**Goal:** Search results can spawn persistent tabs in the tab bar.

### Step 3.1: Dynamic tab model

**Files to modify:**
- `Sources/Cider/Models/CiderTab.swift` — support dynamic tabs (search tabs, project tabs)

**Changes:**
- `CiderTab` becomes an enum with associated values or a struct-based approach:
  ```
  .home, .bookmarks, .notes — fixed tabs
  .search(id: UUID, query: String) — ephemeral search tabs
  .project(id: UUID) — project tabs (Phase 4)
  ```
- Tab bar supports dynamic tab list with closeable tabs
- Fixed tabs are always present and not closeable

### Step 3.2: Search tab content view

**New file:**
- `Sources/Cider/Views/Search/SearchTabContent.swift` — shows search results as tab content

**Changes:**
- Displays mixed results (bookmarks + notes) for a search query
- Same layout as search palette results but as full tab content
- Search query shown at top, results below in sections

### Step 3.3: Tab bar updates

**Files to modify:**
- `Sources/Cider/Views/Shared/CiderTabBar.swift` — render dynamic tabs with close buttons
- `Sources/Cider/Views/CiderPanelView.swift` — manage dynamic tab state, switch content

**Changes:**
- Tab bar renders fixed tabs + dynamic tabs
- Dynamic tabs have close (x) button
- CiderPanelView manages `@State private var dynamicTabs: [DynamicTab]`
- Pressing Enter in search palette creates a search tab and switches to it

### Step 3.4: Build and verify

- `swift build` succeeds
- Enter in search palette spawns a search tab
- Search tab shows results
- Close button on search tab removes it
- Fixed tabs remain always visible

---

## Phase 4: Projects

**Goal:** Persistent project workspaces that live in the sidebar and open as tabs.

### Step 4.1: Project data model

**New files:**
- `Sources/Cider/Models/Project.swift` — Project struct
- `Sources/Cider/Models/ProjectItem.swift` — join model linking projects to bookmarks/notes
- `Sources/Cider/Services/ProjectStorage.swift` — persistence for projects and project items

**Changes:**
- `Project { id, name, createdAt, updatedAt, isArchived, searchQuery? }`
- `ProjectItem { id, projectID, bookmarkID?, noteID?, addedAt, sortOrder }`
- `ProjectStorage.shared` manages CRUD and persistence to `_cider_projects.json`

### Step 4.2: Projects sidebar section

**Files to modify:**
- `Sources/Cider/Views/Shared/FolderSidebarView.swift` — add Projects section below Folders

**Changes:**
- Sidebar gains "Projects" header with "New Project" button
- Lists all non-archived projects with item counts
- Click → opens project as a tab
- Right-click → rename, archive, delete

### Step 4.3: Project tab content

**New file:**
- `Sources/Cider/Views/Projects/ProjectTabContent.swift` — project workspace view

**Changes:**
- Shows all items in a project (bookmarks + notes, mixed)
- Supports adding items (bookmark URL, new note, drag-drop from other views)
- Supports removing items from project
- Supports reordering items

### Step 4.4: Promote search to project

**Files to modify:**
- `Sources/Cider/Views/Search/SearchTabContent.swift` — add "Save as Project" action
- `Sources/Cider/Views/Shared/CiderTabBar.swift` — visual distinction for project tabs (pin icon)

**Changes:**
- Search tab gains "Save as Project" button
- Clicking saves all current search results as project items
- Tab converts from search tab to project tab
- Project appears in sidebar

### Step 4.5: Build and verify

- `swift build` succeeds
- Can create projects from sidebar
- Projects open as tabs
- Can add bookmarks/notes to projects
- Search tabs can be promoted to projects
- Closing a project tab keeps the project in sidebar

---

## Phase 5: Tear-off and Advanced Features (Future)

### Step 5.1: Tab tear-off
- Drag a project tab out of the tab bar → opens as independent floating window
- Uses existing NSPanel pattern (like BookmarksPanel)
- Closing the floating window returns the tab to the main panel

### Step 5.2: Kanban folder views
- Optional kanban view mode for folders
- Columns defined by tags or custom statuses
- Drag items between columns

### Step 5.3: Project archiving
- Archive completed projects (hide from sidebar)
- View archived projects list
- Unarchive or convert to folder

---

## Implementation Order

We build Phase 1 first (universal folders), then Phase 2 (search palette), then Phase 3 (search tabs), then Phase 4 (projects). Each phase builds and runs independently.

Start with **Phase 1, Step 1.1** (rename BookmarkFolder to Folder).
