# Canvas Next Steps

> Implementation plan for the next phase of canvas development. Start here after the POC session.

## Current State (as of 2026-03-30)

Branch: `feature/canvas-poc` — all work is on this branch.

### What's shipped and working:
- React Flow canvas in WKWebView inside a standard NSWindow
- Custom node types: BookmarkCardNode, NoteCardNode, TodoCardNode, FolderGroupNode
- All vault items load onto canvas grouped by folder
- Folder groups with collapse/expand toggle
- Click any card → NSPanel opens with that item's detail view (bookmarks, notes, todos)
- Canvas persistence to `.cider/canvases/default.canvas.json` (save/restore with fallback hardening)
- Zoom level-of-detail (LOD) — hides thumbnails/tags when zoomed out for performance
- Sidebar folder navigation with animated pan-to-folder
- Base64 data transfer for UTF-8 safety
- Window behavior: regular app policy when open, accessory when closed

### Key files:
- `canvas-editor/` — React app (Vite/esbuild build)
  - `src/index.jsx` — Main React Flow app + canvasBridge API
  - `src/BookmarkCardNode.jsx`, `NoteCardNode.jsx`, `TodoCardNode.jsx`, `FolderGroupNode.jsx`
  - `src/styles.css` — All card + folder + LOD styles
- `Sources/Cider/ViewModels/CanvasViewModel.swift` — Swift side: WKWebView singleton, bridge, persistence
- `Sources/Cider/Views/Canvas/` — CanvasView, CanvasWindowContentView, CanvasSidebarView
- `Sources/Cider/App/CanvasWindow.swift` — NSWindow subclass
- `Sources/Cider/Resources/CanvasEditor/` — Built JS/CSS/HTML bundle

### Build process:
1. `cd canvas-editor && npm run build` — builds JS bundle to Resources/CanvasEditor/
2. `swift build` or Xcode Cmd+R — builds Swift
3. Must quit app before deleting canvas save, or auto-save recreates it

---

## Next Steps (prioritized)

### 1. CLI Canvas Commands
The AI's interface to the canvas. Enables iMessage/CLI workflows like "save this bookmark and put it in my Research canvas."

Commands to add to `CiderCLI.swift`:
- `cider-cli canvas list` — list all canvases (for now just "default")
- `cider-cli canvas show` — dump canvas JSON (node count, folder groups, positions)
- `cider-cli canvas place <item-id> --x 200 --y 400` — place an item at a position
- `cider-cli canvas move <item-id> --x 300 --y 500` — move an existing item
- `cider-cli canvas link <id1> <id2> --label "related"` — create an edge between items

Implementation: CLI reads/writes `.cider/canvases/default.canvas.json` directly. The canvas WebView picks up changes on next load.

### 2. Auto-Layout Modes Within Folders
Right now cards inside folders use fixed positions from the initial grid layout. Add layout modes:
- Grid (current default, but responsive to folder resize)
- List (vertical stack)
- Masonry (variable height cards)

Implementation: `layoutEngine.ts` module in canvas-editor. Each folder group node has a `layoutMode` in its data. Right-click context menu to switch modes.

### 3. Edges / Linking Between Items
Draw connections between related items. AI can create these via CLI.
- Visual arrows/lines between cards
- Optional labels on edges
- Click edge to see relationship context

Implementation: React Flow edges are already supported in the data model. Need UI for creating edges (drag from handle) and CLI for AI-created edges.

### 4. Hot Reload — Live Updates When Items Change
Currently new items only appear after restart. Watch the vault for changes and update the canvas live.

Implementation: Listen to `VaultBookmarkService` / `NotesStorage` / `TodoCardStorage` publishers. When items change, call `updateItemMetadata` or `placeItem` on the JS bridge.

### 5. Folder Polish
- Scrollable content within folders (overflow: auto)
- Click folder header title bar to collapse/expand
- Responsive card sizing based on folder width
- Frosted glass background on expanded folders (so they can overlap)

### 6. Drawing / Annotation Layer (Phase 5 from architecture doc)
- Rough.js canvas overlay for freehand drawing
- Or keep Excalidraw as separate whiteboard mode
- AI can read annotations spatially

---

## Known Issues to Fix
- Cards overlap when tags appear at different zoom levels (card height varies)
- Some ICO favicons fail to load in WKWebView (non-critical, shows fallback)
- Double `canvasReady` still fires (guarded, but root cause is WebView lifecycle)
- Note card emoji icons (📝) work after UTF-8 fix but haven't been tested on restore
