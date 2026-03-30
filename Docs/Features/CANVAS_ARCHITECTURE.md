# Canvas Architecture

> Design spec for Cider's canvas-first architecture: React Flow + Rough.js in a full app window, NSPanel as floating companion tool, every folder is a canvas.

## Table of Contents
- [Vision](#vision) — L15
- [Two-Window Model](#two-window-model) — L30
- [Canvas Window (React Flow + WKWebView)](#canvas-window-react-flow--wkwebview) — L45
- [NSPanel as Floating Tool](#nspanel-as-floating-tool) — L100
- [Storage Model](#storage-model) — L135
- [Panel-to-Canvas Drag-and-Drop](#panel-to-canvas-drag-and-drop) — L175
- [Folder-as-Canvas Model](#folder-as-canvas-model) — L210
- [Auto-Layout Within Regions](#auto-layout-within-regions) — L245
- [AI Integration](#ai-integration) — L280
- [Custom Node Types](#custom-node-types) — L315
- [Drawing and Annotation Layer](#drawing-and-annotation-layer) — L355
- [Swift-to-JS Bridge API](#swift-to-js-bridge-api) — L385
- [Migration Path](#migration-path) — L430
- [Open Questions](#open-questions) — L470

---

## Vision

Cider evolves from a panel-only app to a two-window architecture. The primary workspace becomes a spatial canvas where every folder is a canvas. Items (bookmarks, notes, todos) are cards with positions. The NSPanel stays as an instant-access floating tool for quick capture, inspection, and library browsing. Freehand drawing and annotation come later via Rough.js overlay or the existing Excalidraw integration.

Users who don't want spatial features see auto-laid-out cards in a grid — functionally identical to today's folder view. Users who want spatial organization drag items around and build research boards. Same underlying system, different levels of engagement.

The canvas is powered by React Flow (MIT, free) embedded in a WKWebView inside a standard app window. This follows the same integration pattern as the existing TipTap editor. Drawing/annotation is handled separately — either Rough.js on a canvas overlay or Excalidraw in a dedicated whiteboard mode (already shipped).

---

## Two-Window Model

| Window | Technology | Purpose | Activation |
|--------|-----------|---------|------------|
| Canvas window | React Flow in WKWebView, hosted in NSWindow | Primary workspace — spatial organization, folder navigation | Menu bar icon, Dock, or keyboard shortcut |
| NSPanel | Native SwiftUI (unchanged) | Quick capture, item inspection, library drag source | Double-tap Option (existing) |

The canvas window is a standard resizable `NSWindow`. It can go full screen. It persists between sessions (position/size saved). The NSPanel floats above it when both are open.

Both windows read from the same vault on disk. Changes in one appear in the other because the source of truth is the filesystem, not either window's state.

---

## Canvas Window (React Flow + WKWebView)

### Why React Flow

| Requirement | React Flow | tldraw | Excalidraw |
|-------------|-----------|--------|------------|
| Custom cards as React components (HTML/CSS) | Best — nodes ARE React | Good (shape system) | Bad — canvas-only, no HTML |
| Parent-child node grouping (folder frames) | Built-in | Built-in (frames) | Basic grouping only |
| Layout library integration (dagre, elkjs) | Excellent | None built-in | None |
| Viewport virtualization | Yes | Yes | Limited |
| Drawing/annotation tools | None (add separately) | Built-in | Best |
| License | MIT | Proprietary ($6K/yr) | MIT |
| Cost | Free | $6,000/year | Free |

React Flow gives us the most important thing — rich HTML/CSS cards that look exactly like Cider's existing bookmark/note/todo cards. Drawing comes later via Rough.js overlay (same engine Excalidraw uses for its hand-drawn aesthetic) or the existing Excalidraw whiteboard mode.

### WKWebView Setup

Follow the existing singleton pattern from `WhiteboardViewModel`:

1. Create a `CanvasWebView` subclass of `WKWebView` (prevent window dragging, handle drop targets)
2. Bundle the React Flow app as static HTML/JS/CSS in `Resources/CanvasEditor/`
3. Register script message handlers for Swift-JS communication
4. Load `index.html` with read access to the bundle directory

### React Flow App

A React app that:
- Initializes React Flow with custom node types (bookmark card, note card, todo card, folder group)
- Exposes `window.canvasBridge` API for Swift to call
- Posts messages to Swift via `window.webkit.messageHandlers`
- Serializes/deserializes canvas state as JSON
- Implements the auto-layout engine using dagre or elkjs for structured layouts

Build with Vite (same as existing tiptap-editor build). Output goes to `Sources/Cider/Resources/CanvasEditor/`.

### React Flow Key Concepts

- **Nodes** — each item card is a node with a custom React renderer. Full HTML/CSS — thumbnails, tag pills, favicons, everything.
- **Edges** — connections between nodes (arrows/lines). Used for AI-generated links between related items.
- **Parent nodes** — a node can be a parent (folder group). Child nodes move with the parent. Collapsing hides children.
- **Viewport** — built-in pan/zoom with `fitView()`, `setCenter()`, `fitBounds()` for navigation.
- **Minimap** — built-in minimap widget for orientation on large canvases.

---

## NSPanel as Floating Tool

The NSPanel keeps its current native SwiftUI implementation. No WKWebView. It stays fast.

### Three Modes

**Inspector mode:**
- Triggered when user clicks a card on the canvas
- Canvas sends item UUID to Swift via message handler
- Panel displays the item's full detail view (metadata, tags, notes, preview)
- Edit inline — changes write to disk, canvas picks up updates
- Closes on click-away or Escape

**Library mode:**
- User opens via panel toggle or keyboard shortcut
- Shows all items in scrollable list/grid/masonry (same as today's library view)
- Supports search and filter
- Items are draggable — drag off the panel and onto the canvas to place them

**Quick capture mode:**
- Double-tap Option from anywhere (existing behavior)
- Save a URL, jot a note, create a todo
- New item lands at the default inbox position on the active canvas
- Panel dismisses, user continues what they were doing

### Panel ↔ Canvas Communication

Both windows live in the same process. Communication through:
1. `NotificationCenter` posts (e.g., `.canvasItemSelected`, `.canvasItemPlaced`)
2. Shared `ViewModel` state (e.g., `CanvasViewModel.selectedItemID`)
3. Direct method calls on shared services (e.g., `VaultBookmarkService.shared`)

No IPC, no networking — just in-process Swift.

---

## Storage Model

### Principle: Items on disk are the source of truth. Canvas JSON is a layout overlay.

```
~/CiderVault/
├── Restaurants/
│   ├── .canvas.json              ← canvas layout for this folder
│   ├── some-restaurant.webloc    ← bookmark (unchanged)
│   ├── some-restaurant.sidecar.json
│   ├── Seattle/
│   │   ├── .canvas.json          ← sub-folder canvas layout
│   │   ├── pike-place.webloc
│   │   └── pike-place.sidecar.json
│   └── Portland/
│       ├── .canvas.json
│       └── ...
├── Research/
│   ├── .canvas.json
│   ├── ai-notes.md
│   └── ...
```

### .canvas.json Schema

```json
{
  "version": 1,
  "nodes": [
    {
      "id": "node-uuid-1",
      "itemID": "cider-bookmark-uuid",
      "itemType": "bookmark",
      "position": { "x": 200, "y": 400 },
      "size": { "width": 280, "height": 160 },
      "parentNode": null
    }
  ],
  "edges": [
    {
      "id": "edge-1",
      "source": "node-uuid-1",
      "target": "node-uuid-2",
      "label": "related"
    }
  ],
  "folderGroups": [
    {
      "id": "group-seattle",
      "folderName": "Seattle",
      "position": { "x": 0, "y": 0 },
      "size": { "width": 600, "height": 400 },
      "collapsed": false,
      "layoutMode": "grid"
    }
  ],
  "annotations": [],
  "viewport": { "x": 0, "y": 0, "zoom": 1 }
}
```

The `nodes` array maps directly to React Flow nodes. The `edges` array maps to React Flow edges. `folderGroups` are parent nodes. `annotations` stores drawing layer data (Phase 5). `viewport` saves the last camera position.

### Graceful Degradation

- Delete `.canvas.json` → items still exist on disk, folder view falls back to auto-layout grid
- Item deleted from disk → canvas detects missing UUID on next load, removes orphaned node
- Item added to folder without canvas position → placed at default inbox position (0,0 region)

---

## Panel-to-Canvas Drag-and-Drop

### How It Works

The NSPanel already renders native drag previews that follow the cursor off-panel (this works today for dragging bookmarks to the desktop). The native drag image stays visible as the cursor moves over the canvas window — no cross-renderer coordination needed.

1. **Drag starts in panel** — SwiftUI `.onDrag` creates `NSItemProvider` with `com.cider.bookmark-id` (existing `CiderDragPayload` system). Native drag preview follows cursor everywhere.
2. **Cursor enters canvas window** — `CanvasWebView` implements `NSDraggingDestination` on the hosting `NSView`.
3. **`draggingEntered`** — Returns `.copy` drag operation.
4. **`performDragOperation`** — Reads UUID from pasteboard (`com.cider.bookmark-id` or `com.cider.note-id`). Converts drop coordinates from AppKit to React Flow canvas coordinates. Calls `window.canvasBridge.placeItem(uuid, x, y)` via `evaluateJavaScript`.
5. **React Flow places the card** — Creates a custom node at the drop position. Canvas state auto-saves to `.canvas.json`.

### Coordinate Conversion

AppKit drop coordinates are window-relative, bottom-left origin. React Flow uses top-left origin with its own viewport transform (pan + zoom). The JS bridge converts:

```javascript
function screenToCanvas(windowX, windowY, viewportHeight) {
  const domY = viewportHeight - windowY; // flip Y axis
  const canvasPoint = reactFlowInstance.screenToFlowPosition({ x: windowX, y: domY });
  return canvasPoint;
}
```

### Multi-Item Drag

The existing `CiderMultiDrag` payload supports multiple item UUIDs. The canvas places them in a cluster near the drop point, offset so they don't stack.

---

## Folder-as-Canvas Model

Every folder in the vault has an optional `.canvas.json`. If present, the canvas view renders it. If absent, auto-layout generates a default grid.

### Navigation

- **Sidebar** shows the folder tree (same as today)
- **Click a folder** → canvas pans and zooms to that folder's group node
- **Breadcrumb bar** at top of canvas shows current path, click to navigate up
- **Double-click a sub-folder group** on the canvas → zooms into it (same as clicking in sidebar)

### Sub-Folder Groups on Canvas

A sub-folder is a React Flow parent node. Child nodes (items) belong to that parent. The group can be:
- **Expanded** — shows all cards inside, group is sized to fit
- **Collapsed** — compact node with folder name and item count, click to expand
- Dragging a card into a group moves it to that sub-folder on disk

### Default Inbox Position

New items (saved via CLI, iMessage, quick capture) land at position 0,0 of the target folder's canvas. This is the "inbox zone." User drags items from there to wherever they want, or the AI organizes them.

---

## Auto-Layout Within Regions

React Flow works well with layout libraries. A TypeScript layout engine runs inside the React Flow context.

### Layout Modes

| Mode | Behavior | Library |
|------|----------|---------|
| Grid | Cards in rows/columns within the group, wrapping at group width | Custom (simple grid math) |
| List | Cards stacked vertically, full group width | Custom (vertical stack) |
| Kanban | Named columns within the group, cards stack in each | Custom (column distribution) |
| Freeform | No auto-layout — items stay where placed (default) | None |
| Graph | Auto-arranged by relationships/edges | dagre or elkjs |

### How It Works

Each folder group node has a `layoutMode` property. When set to grid/list/kanban/graph:
- On group resize, child nodes are repositioned to fit the layout
- On node add/remove, layout recalculates
- User can switch modes via right-click context menu on the group
- Switching to freeform keeps items at their current positions (layout "freezes")
- Switching from freeform to grid rearranges all items

### Implementation

A `layoutEngine.ts` module that:
- Takes a group's bounds and child nodes
- Applies the layout algorithm (grid packing, vertical stack, column distribution, or dagre graph)
- Returns new positions for each child
- Called on group resize, child mutation, or explicit layout toggle

---

## AI Integration

### Machine-Readable Canvas Data

The `.canvas.json` is structured data. The AI can parse it to understand spatial relationships:

1. **Read node positions** — know where items are spatially relative to each other
2. **Read edges** — understand which items are linked and why (edge labels)
3. **Read group membership** — know which items are in which folder groups
4. **Read annotations** (Phase 5) — circles, text, arrows drawn by the user

### CLI Commands for Canvas

```
cider-cli canvas list                          # list all canvases
cider-cli canvas show <folder>                 # dump canvas JSON
cider-cli canvas place <item-id> --folder <f> --x 200 --y 400
cider-cli canvas move <item-id> --x 300 --y 500
cider-cli canvas link <id1> <id2> --label "related"
cider-cli canvas auto-layout <folder> --mode grid
cider-cli canvas query --annotation "research" # find annotated regions + enclosed items (Phase 5)
```

### AI Spatial Queries

The canvas query command reads the JSON and does coordinate math:
1. Find annotation shapes (circles, rectangles) with text labels
2. Identify item nodes whose positions fall inside each annotation's bounds
3. Return structured JSON: `{ annotation: "research this more", items: [...] }`

This enables workflows like:
- "Find the items I circled and research them further"
- "Link all the items in the 'Seattle' group that are about seafood"
- "Organize my inbox items into existing groups"

---

## Custom Node Types

React Flow nodes ARE React components — full HTML/CSS rendering. Each card type looks exactly like it does in Cider today.

### Bookmark Card Node

- Favicon + domain text
- Title (truncated)
- Thumbnail image if available
- Tag pills
- Visual indicator for AI summary

Props: `{ itemID: UUID, itemType: "bookmark", title, url, favicon, thumbnail, tags, hasAISummary }`

Click → posts message to Swift → NSPanel opens in inspector mode.

### Note Card Node

- Title
- First ~3 lines of markdown content (plain text preview)
- Word count or last-edited date

### Todo Card Node

- Title
- Priority indicator (color-coded border or badge)
- Completion checkbox (toggleable on canvas)
- Due date if set

### Folder Group Node

- Group header with folder name
- Collapse/expand toggle button
- Item count badge when collapsed
- Layout mode indicator (grid/list/kanban/freeform)
- Background fill to visually contain children

---

## Drawing and Annotation Layer

Drawing is **Phase 5** — not needed for the spatial card canvas to be useful. Two approaches, not mutually exclusive:

### Option A: Rough.js Canvas Overlay

A transparent HTML canvas element layered on top of the React Flow viewport. Rough.js renders freehand-style shapes (same engine Excalidraw uses internally).

- Circles, rectangles, arrows, freehand lines, text
- Hand-drawn aesthetic matching Excalidraw's look
- Annotations stored in the `annotations` array of `.canvas.json`
- Canvas overlay pans/zooms with React Flow's viewport transform
- Drawing mode toggle — switch between item interaction and drawing

### Option B: Keep Excalidraw for Whiteboards

The existing Excalidraw integration stays as a separate "whiteboard" mode. Users who want full freeform drawing open a whiteboard tab. The React Flow canvas handles spatial item arrangement only.

Two tools, both MIT, both already proven:
- **React Flow** — spatial PKM canvas (items, folders, navigation)
- **Excalidraw** — freeform whiteboard (drawing, brainstorming, research branching)

Can start with Option B (zero new work for drawing) and add Option A later if users want annotations directly on the item canvas.

---

## Swift-to-JS Bridge API

### Swift → JavaScript (via evaluateJavaScript)

```javascript
window.canvasBridge = {
  // Canvas state
  loadCanvas(jsonString),           // load .canvas.json
  getCanvas() → jsonString,         // serialize current state

  // Item management
  placeItem(uuid, type, x, y, metadata),  // add node at position
  removeItem(uuid),                        // remove node
  updateItemMetadata(uuid, metadata),      // refresh card content

  // Navigation
  panToGroup(groupId),              // zoom to a folder group
  panToItem(uuid),                  // center on a specific card
  fitAll(),                         // zoom to fit everything

  // Layout
  setGroupLayout(groupId, mode),    // grid/list/kanban/freeform/graph

  // Edges
  addEdge(sourceUuid, targetUuid, label),  // connect two items
  removeEdge(edgeId),

  // Theme
  setTheme(theme),                  // sync with system appearance
};
```

### JavaScript → Swift (via message handlers)

| Handler | Payload | Purpose |
|---------|---------|---------|
| `canvasReady` | — | React Flow initialized, safe to load canvas |
| `canvasChanged` | JSON string | Canvas state changed (debounced 1500ms) |
| `itemClicked` | `{ uuid, type }` | User clicked a card — open inspector panel |
| `itemDoubleClicked` | `{ uuid, type }` | User double-clicked — open item for editing |
| `itemDropped` | `{ uuid, x, y }` | External drop placed an item |
| `groupEntered` | `{ groupId, folderName }` | User navigated into a folder group |
| `itemMoved` | `{ uuid, x, y }` | User dragged a card to new position |
| `canvasError` | `{ message, stack }` | Error reporting |

### Coordinator Pattern

Follow the existing `ExcalidrawCoordinator` / `TipTapEditorCoordinator` pattern:

```swift
class CanvasCoordinator: NSObject, WKScriptMessageHandler {
    weak var viewModel: CanvasViewModel?

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        switch message.name {
        case "canvasReady":
            viewModel?.onCanvasReady()
        case "canvasChanged":
            guard let json = message.body as? String else { return }
            viewModel?.saveCanvasState(json)
        case "itemClicked":
            guard let dict = message.body as? [String: Any],
                  let uuid = dict["uuid"] as? String else { return }
            viewModel?.onItemClicked(uuid)
        // ...
        }
    }
}
```

---

## Migration Path

Each step is a shippable increment. Nothing breaks at any step.

### Phase 1: Canvas Window Foundation (Planned)

- Create `CanvasWindow` (standard `NSWindow`) with `CanvasWebView` (WKWebView)
- Bundle React Flow app with bookmark card node type
- Load/save `.canvas.json` per folder
- Sidebar navigation that pans canvas to folder groups
- No panel integration yet — canvas is standalone

### Phase 2: Panel as Inspector (Planned)

- Click card on canvas → `itemClicked` message → panel opens showing item detail
- Panel shows metadata, tags, notes (reuse existing detail views)
- Edit in panel → writes to disk → canvas refreshes card metadata

### Phase 3: Panel-to-Canvas Drag (Planned)

- `CanvasWebView` implements `NSDraggingDestination`
- Accepts `com.cider.bookmark-id` and `com.cider.note-id` from pasteboard
- Drop places card at cursor position on canvas
- Panel library mode: browse + drag items onto canvas

### Phase 4: Full Node Set + Layout (Planned)

- Note card, todo card, folder group node types
- Sub-folder collapse/expand
- Auto-layout engine (grid/list/kanban/graph modes via dagre/elkjs)
- Edge creation between related items

### Phase 5: Drawing and Annotation (Planned)

- Rough.js canvas overlay for freehand annotation on the item canvas
- OR keep Excalidraw as separate whiteboard mode (already shipped)
- CLI canvas query for spatial annotation parsing
- AI reads annotations and acts on them

---

## Open Questions

1. **React Flow Pro features** — The MIT core covers everything needed. Pro features (helpers, sub-flows) are paid but optional. Evaluate if any Pro features would save significant time.
2. **Performance at scale** — React Flow handles thousands of nodes well. Need to test with realistic Cider vaults (hundreds of items per folder with thumbnail images). Lazy thumbnail loading likely needed.
3. **Offline bundling** — React Flow is bundled in the app, no network needed. Verify all assets (fonts, icons) are self-contained in the Vite build.
4. **Canvas window lifecycle** — Does it persist in background? Reload React Flow on each open? Singleton like the Excalidraw view? Singleton is likely best for performance.
5. **Existing Excalidraw whiteboards** — Keep Excalidraw for standalone whiteboards. React Flow for folder canvases. Two separate features, no migration needed.
6. **Mobile/iPad** — React Flow supports touch. If Cider goes to iPad, the WKWebView canvas works there too.
7. **Rough.js vs Excalidraw for annotations** — Decide in Phase 5. Rough.js overlay is more integrated but more work. Excalidraw whiteboard mode is already shipping. Could offer both.
