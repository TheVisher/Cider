# Linked Sources Vision

> Cider can watch external filesystem directories and surface their `.md` files alongside native content. The primary use case is dogfooding — pointing Cider at its own `Docs/` folder to browse and edit project docs live. The broader use case is making Cider a first-class `.md` editor/viewer for any folder on your system.

**Status:** 🔲 Not yet implemented

---

## Concept

A **Linked Source** is an external filesystem directory that Cider watches. Files inside it appear in Cider as if they were native content — in the library feed, in the sidebar, as a tab — but Cider doesn't own them. Edits save back to the original file in place. No copying, no importing, no syncing.

This is different from the primary notes directory:
- **Notes directory** — Cider owns these files. It creates, moves, and manages them.
- **Linked Source** — Cider watches and reads these files. The filesystem owns them.

---

## Three Surfaces

A Linked Source can appear in three places, independently toggled:

### 1. Sidebar — Permanent
A "Sources" section in the sidebar (below Projects) lists all pinned sources. Clicking a source opens a detail view of its `.md` files — same card layout as FolderDetailView. Right-click to configure, rename, or remove.

This is the permanent home. Even if the tab is closed, the source is still there.

```
FOLDERS
  Design Resources
  Work

PROJECTS
  New Website

SOURCES                       ← new section
  📂 Cider Docs
  📂 Personal Notes
```

### 2. Tab — Focused / Temporary
A source can be pinned as a tab in the tab bar (same `isTabPinned` pattern as SavedViews). This gives you a dedicated tab showing just that source's files. Close the tab, the source stays in the sidebar.

```
[Home] [Bookmarks] [Notes] [📂 Cider Docs ×]
```

### 3. Library — Ambient
When `showInLibrary` is enabled for a source, its files appear in the Home library feed alongside bookmarks, notes, date cards, and contacts. A small footer indicator shows which source the file belongs to (e.g., "Cider Docs"). A filter chip in the library lets you show/hide external files globally.

These three surfaces are not mutually exclusive — a source can be in all three at once.

---

## Data Model

### ExternalSource

```swift
struct ExternalSource: Codable, Identifiable {
    var id: UUID
    var path: String               // absolute filesystem path
    var displayName: String        // user-facing name (defaults to folder name)
    var showInSidebar: Bool        // appears in sidebar Sources section
    var isTabPinned: Bool          // appears as a tab in the tab bar
    var showInLibrary: Bool        // files appear in Home library feed
    var createdAt: Date
}
```

Persisted in `_cider_sources.json` in the bookmarks root (alongside other storage JSON files).

### ExternalFile

```swift
struct ExternalFile: Identifiable {
    var id: UUID                   // deterministic UUID derived from file path (stable, no storage needed)
    var title: String              // filename without extension
    var path: URL                  // absolute path to the .md file
    var sourceID: UUID             // which ExternalSource this belongs to
    var sourceName: String         // display name of the source (for footer indicator)
    var createdAt: Date            // from filesystem attributes
    var modifiedAt: Date           // from filesystem attributes
    // content is lazy-loaded from disk, same pattern as NotesStorage.loadContent(for:)
}
```

Identity is derived from the file path — no UUIDs stored anywhere. If a file moves, it's treated as a new item (same behavior as any file editor).

### LibraryItemV2

Add a new case:
```swift
case externalFile(ExternalFile)
```

`dateAnchor` → `modifiedAt` (for sorting in the library feed)
`isCompleted` → always `false`

---

## File Operations

| Action | Behavior |
|--------|----------|
| Open | Loads content from disk path in TipTap editor |
| Edit | Saves back to the original file path in place |
| Create new file | Creates a new `.md` file in the source directory |
| Delete | Moves to **system Trash** (not Cider's trash — we don't own the file) |
| Move to folder | Not applicable — external files stay in their source directory |

---

## Adding a Source

Three entry points:
1. **"Add Source" button** in the sidebar Sources section header → `NSOpenPanel` folder picker
2. **Drag a folder** onto the Cider sidebar or icon
3. **AppDelegate `application(_:open:)`** — when Cider is set as the default app for `.md` files and a folder is opened via Finder

macOS file type registration (`Info.plist`) allows setting Cider as the default opener for `.md` and optionally `.txt` files.

---

## Filesystem Watching

Each linked source gets a filesystem watcher (same `FSEventStream` / `DispatchSourceFileSystemObject` pattern as the existing notes watcher). On change:
1. Re-scan the directory
2. Diff against current file list
3. Update `LibraryViewModel` — new files appear, removed files disappear, modified files refresh

Supports live updates — edits by external tools (agents, editors) appear in Cider automatically.

**Supported file types (v1):** `.md` only. Hidden files and non-text files are ignored.

---

## UI Details

### Source Card in Library
Same card treatment as `NoteCardView` — content preview, title, date. Footer shows:
```
📂 Cider Docs  ·  Modified 2 hours ago
```

### Source Detail View (sidebar click)
Same layout as `FolderDetailView`:
- Header with source name, file count, path
- Card grid of all `.md` files in the directory
- Supports all display modes (list, grid, masonry)
- Sorted by modified date by default

### Library Filter
ViewOptionsDropdown gets an "External Files" toggle. When off, `LibraryViewModel` excludes `externalFile` items from the feed.

### Sidebar Source Row
```
📂 Cider Docs       12 files
```
Right-click context menu:
- Show in Library (toggle)
- Pin as Tab (toggle)
- Rename
- Open in Finder
- Remove Source

---

## Architecture

### New Files
- `Sources/Cider/Models/ExternalSource.swift`
- `Sources/Cider/Models/ExternalFile.swift`
- `Sources/Cider/Services/ExternalSourceStorage.swift` — CRUD + persistence for sources
- `Sources/Cider/Services/ExternalSourceScanner.swift` — scans directory, watches for changes, produces `[ExternalFile]`
- `Sources/Cider/Views/Sources/SourceDetailView.swift` — detail view for a source (like FolderDetailView)
- `Sources/Cider/Views/Sources/SourceCardView.swift` — card for external files in library

### Modified Files
- `Sources/Cider/Models/LibraryItemV2.swift` — add `.externalFile(ExternalFile)` case
- `Sources/Cider/ViewModels/LibraryViewModel.swift` — aggregate external files from all sources
- `Sources/Cider/Views/Shared/FolderSidebarView.swift` — add Sources section
- `Sources/Cider/Views/CiderPanelView.swift` — handle source tab content
- `Sources/Cider/Views/Shared/CiderTabBar.swift` — render source tabs
- `Sources/Cider/Views/Home/HomeDashboardView.swift` — filter chip for external files
- `Sources/Cider/App/AppDelegate.swift` — `application(_:open:)` handler
- `Sources/Cider/Models/CiderConfig.swift` — no new fields needed (sources stored in own JSON)
- `Info.plist` — register `.md` file type association

### Does NOT Touch
- `NotesStorage` — external files are a separate concern
- `NotesViewModel` — library aggregation happens in `LibraryViewModel`
- `TipTapEditorView` — already opens any file path, works as-is
- `TrashStorage` — external files use system Trash, not Cider trash

---

## Implementation Phases

### Phase 1 — Model + Storage
- `ExternalSource` model and `ExternalSourceStorage`
- `ExternalFile` model with path-derived identity
- `_cider_sources.json` persistence

### Phase 2 — File Scanning + Watching
- `ExternalSourceScanner` — directory scan, FSEventStream watching, produces `[ExternalFile]`
- Live update on file changes

### Phase 3 — Sidebar
- Sources section in `FolderSidebarView`
- `SourceDetailView` — browse a source's files
- Add Source via folder picker
- Context menu: configure, rename, remove

### Phase 4 — Library Integration
- `.externalFile` case in `LibraryItemV2`
- `LibraryViewModel` reads from all active sources
- Source footer indicator on cards
- Library filter toggle for external files

### Phase 5 — Tab Support
- Source tabs in `CiderTabBar`
- Source tab content in `CiderPanelView`
- `isTabPinned` toggled from sidebar context menu

### Phase 6 — File Open Handler
- `AppDelegate.application(_:open:)` — handle files and folders from Finder
- Drag folder onto sidebar or icon → add as source
- `Info.plist` `.md` file type registration
- "Open With Cider" from Finder context menu
