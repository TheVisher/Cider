# Native Canvas Implementation Plan

> Rebuild the canvas from React Flow/WKWebView to native SwiftUI. Same features, native quality.

## Why

- Blurry thumbnails at retina (WebKit renders at web resolution)
- Two-window docking hack (child window coordination) is fragile
- Can't reuse existing SwiftUI card components directly
- JS bridge adds latency and complexity
- WebView spawns separate process (memory overhead)
- Drawing/annotation layer requires yet another web layer

## Architecture

### Single-Window Native Canvas

```
┌──────────────────────────────────────────┐
│ Canvas Window (single NSWindow)          │
├─────────────┬────────────────────────────┤
│             │                            │
│  Sidebar    │   NativeCanvasView         │
│  (SwiftUI)  │   (ZStack + gestures)      │
│             │                            │
│  Overlay,   │   Cards positioned via     │
│  rounded    │   .position(x:, y:)        │
│  corners,   │                            │
│  frosted    │   Edges drawn via          │
│  glass      │   Canvas underlay          │
│             │                            │
├─────────────┴────────────────────────────┤
```

- Sidebar is a SwiftUI overlay within the same window (not a separate NSPanel)
- When "undocked" via opt, sidebar content moves to the floating NSPanel
- Canvas is a ZStack with `scaleEffect(zoom)` and `offset(pan)`
- Cards are existing SwiftUI components positioned absolutely
- Edge lines drawn via SwiftUI `Canvas` (draw-only) underlay

### Data Layer (keep from current implementation)

- `CanvasViewModel` — persistence, hot reload, metadata builders
- `default.canvas.json` — same schema, same storage path
- Combine publishers on vault services for hot reload
- Remove all JS bridge code (evaluateJavaScript, WKScriptMessageHandler, etc.)

## Build Phases

### Phase 1: Core Canvas Surface

**Goal:** Pannable, zoomable surface with positioned cards. No sidebar, no edges.

**Files to create:**
- `Sources/Cider/Views/Canvas/NativeCanvasView.swift` — The main canvas view
  - ZStack containing all card views
  - `@State var zoom: CGFloat = 1.0`
  - `@State var panOffset: CGPoint = .zero`
  - `MagnifyGesture` for zoom (0.1 to 2.0 range)
  - `DragGesture` on background for pan
  - Apply `.scaleEffect(zoom)` and `.offset(x: panOffset.x, y: panOffset.y)` to content
  - Dot grid background (20px spacing)

- `Sources/Cider/Views/Canvas/CanvasCardView.swift` — Wrapper that positions a card
  - Takes a `CanvasNode` (position, size, type, metadata)
  - Renders the appropriate card type (`BookmarkCard`, `NoteCardView`, `TodoCardCardView`)
  - `DragGesture` for repositioning (divide translation by zoom for coordinate transform)
  - LOD: at low zoom, swap for simplified view

**ViewModel changes:**
- `CanvasViewModel` — remove all WKWebView/JS bridge code
- Keep: persistence (load/save JSON), hot reload, metadata builders
- Add: `@Published var nodes: [CanvasNode]` — SwiftUI-observable node array
- Add: `@Published var edges: [CanvasEdge]` — SwiftUI-observable edge array
- Add: `@Published var viewport: CanvasViewport` — zoom + pan offset
- Add: `func moveNode(id:, to:)`, `func addNode(...)`, `func removeNode(id:)`

**Data models to create:**
- `Sources/Cider/Models/CanvasNode.swift`
  ```swift
  struct CanvasNode: Identifiable, Codable {
      let id: String
      var itemID: String?
      var itemType: String // "bookmark", "note", "todo", "folderGroup"
      var position: CGPoint
      var size: CGSize
      var parentNodeID: String?
      var layoutMode: String? // "grid", "list", "masonry"
      var collapsed: Bool
  }
  ```
- `Sources/Cider/Models/CanvasEdge.swift`
  ```swift
  struct CanvasEdge: Identifiable, Codable {
      let id: String
      var sourceID: String
      var targetID: String
      var label: String?
  }
  ```
- `Sources/Cider/Models/CanvasViewport.swift`
  ```swift
  struct CanvasViewport: Codable {
      var offset: CGPoint
      var zoom: CGFloat
  }
  ```

**Update `CanvasWindowContentView`:**
- Replace `CanvasView(viewModel:)` (WKWebView) with `NativeCanvasView(viewModel:)`

**Test criteria:**
- Cards render at full retina quality
- Trackpad pan and zoom work smoothly
- Cards can be dragged to new positions
- Positions persist across app restarts
- Hot reload works (add a bookmark, it appears on canvas)

### Phase 2: Folder Groups

**Goal:** Folder containers with collapsible headers, layout modes.

**Implementation:**
- `Sources/Cider/Views/Canvas/CanvasFolderGroupView.swift`
  - Rounded rect background with frosted glass
  - Header bar: folder icon, name, item count, layout picker, collapse toggle
  - Child cards positioned relative to folder origin
  - Three layout modes using existing `MasonryLayout` or manual grid/list positioning
  - Collapse: hide children, shrink to header-only

**Folder group sizing:**
- Folder calculates its size based on children positions + padding
- When layout mode changes, reposition children within the folder
- Use `GeometryReader` or `.onGeometryChange` for masonry height measurement

**Test criteria:**
- Folders render with frosted glass background
- Click header to collapse/expand
- Layout mode picker works (grid/list/masonry)
- Masonry cards don't overlap
- Child cards stay within folder bounds when dragged

### Phase 3: Native Sidebar Overlay

**Goal:** Replace the two-window NSPanel docking with a native SwiftUI sidebar overlay.

**Implementation:**
- `Sources/Cider/Views/Canvas/CanvasSidebarOverlay.swift`
  - Reuse existing `FolderSidebarView` content (folder tree, search)
  - Frosted glass background, rounded corners
  - Overlays the canvas on the left side
  - Toggle visibility with animation
  - Click folder → canvas pans to that folder

- **Undock to NSPanel:**
  - When user hits opt (or undock button), hide the overlay sidebar
  - Show the existing NSPanel in floating mode
  - NSPanel has full functionality (tabs, detail views, everything)

- **Dock from NSPanel:**
  - When canvas is focused and user triggers dock, hide NSPanel
  - Show the overlay sidebar

**Remove from AppDelegate:**
- `isPanelDockedToCanvas`, `frameBeforeDock`, `canvasFrameObservation`
- `dockPanelToCanvas()`, `undockPanelFromCanvas()`, `updateDockedPanelPosition()`
- Child window coordination code

**Test criteria:**
- Sidebar overlays canvas with rounded corners and frosted glass
- Cards visible behind sidebar at rounded corners
- Toggle sidebar with animation
- Folder click pans canvas
- Opt undocks to floating NSPanel
- No two-window lag or shadow issues

### Phase 4: Card Detail Overlay

**Goal:** Click a card on canvas, see its details in a native overlay.

**Implementation:**
- `Sources/Cider/Views/Canvas/CanvasDetailOverlay.swift`
  - Frosted glass modal overlay on the canvas
  - Reuses existing `BookmarkMetadataSidebar` content
  - Shows: thumbnail, title, source, folder, tags, notes, intelligence, info
  - Dismiss with Escape or click outside
  - Animated entrance (scale up from card position)

**Test criteria:**
- Click card → detail overlay appears
- All metadata fields display correctly
- Notes editable inline
- Tags display with colors
- Escape dismisses
- Click outside dismisses

### Phase 5: Edges & Lines

**Goal:** Visual connections between cards.

**Implementation:**
- SwiftUI `Canvas` (draw-only) underlay beneath all card views
- Reads `edges` from ViewModel
- Draws bezier curves between card centers (or connection points)
- Optional labels on edges
- Edge styling: thin line, optional arrow, themed colors

**Test criteria:**
- Edges render between connected cards
- Edges update when cards move
- CLI `canvas link` command creates visible edges

### Phase 6: LOD & Performance

**Goal:** Smooth performance at all zoom levels with 200+ cards.

**Implementation:**
- LOD tiers based on zoom:
  - `zoom >= 0.8` → full card detail
  - `0.5–0.8` → hide tags, AI badge, previews
  - `0.25–0.5` → hide thumbnails, show title + colored rect only
  - `< 0.25` → colored rectangles only (40px)
- Viewport culling: only render cards within visible rect + margin
- Use `.drawingGroup()` on cards at low zoom for GPU-accelerated compositing

**Test criteria:**
- Smooth zoom from 0.1x to 2.0x
- No frame drops with 200 cards visible
- Cards gracefully simplify at low zoom

## Existing Components to Reuse (confirmed standalone)

| Component | File | Canvas Use |
|-----------|------|------------|
| `BookmarkCard` | `Views/Bookmarks/BookmarkCard.swift` | Bookmark canvas cards |
| `BookmarkThumbnailView` | `Views/Bookmarks/BookmarkThumbnailView.swift` | Thumbnail rendering |
| `NoteCardView` | `Views/Notes/NoteCardView.swift` | Note canvas cards |
| `TodoCardCardView` | `Views/Todos/TodoCardCardView.swift` | Todo canvas cards |
| `DateCardCardView` | `Views/DateCards/DateCardCardView.swift` | Event canvas cards |
| `VaultFileCardView` | `Views/Shared/VaultFileCardView.swift` | File canvas cards |
| `ContactCardCardView` | `Views/Contacts/ContactCardCardView.swift` | Contact canvas cards |
| `cardContainer` modifier | `Utilities/ContainerStyles.swift` | Card visual shell |
| `MasonryLayout` | `Views/Shared/MasonryLayout.swift` | Folder group layout |
| `CardSizing` | `Models/Bookmark.swift:180` | Card dimension tokens |
| `TagPillRow` | `Views/Shared/TagPillView.swift` | Tag display |
| `FolderSidebarView` | `Views/Shared/FolderSidebarView.swift` | Sidebar folder tree |

## Migration Notes

- The `canvas-editor/` React app and `Sources/Cider/Resources/CanvasEditor/` bundle become unused
- `CiderVaultSchemeHandler` is no longer needed (native views load images directly from disk)
- The `CanvasWebView` class and `CanvasCoordinator` are removed
- `CiderCLI` canvas commands should still work — they read/write `default.canvas.json` directly
- The canvas JSON schema stays compatible (same nodes/edges/viewport structure)

## Risk: Pure SwiftUI Zoom

`scaleEffect` is a render transform, not a layout transform. This means:
- Hit testing may be off at non-1.0 zoom levels
- Gesture coordinates need manual transform (`/ zoom`)
- If this becomes unworkable, migrate the outer container to `NSScrollView` with `allowsMagnification` (Approach 1 from research) while keeping SwiftUI cards via `NSHostingView`

## Success Criteria

The native canvas is ready to replace the WebView canvas when:
1. All existing card types render at full retina quality
2. Pan/zoom feels native (trackpad, scroll wheel)
3. Cards drag to reposition with correct coordinate transforms
4. Folder groups with layout modes work
5. Sidebar overlay replaces two-window docking hack
6. Canvas state persists and hot-reloads
7. Performance is smooth with 150+ cards
