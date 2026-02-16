# Whiteboard Tab Vision

> **Status:** Not Yet Implemented

## Overview

The Whiteboard is a freeform canvas for dumping thoughts, images, links, and quotes. It's the "junk drawer of your brain" — a place to capture anything without structure, then optionally promote clusters of content into structured notes.

It will be a **dedicated tab** in the title bar. The planned full lineup: **Home | Bookmarks | Notes | Whiteboard | Documents | Books | Todos**

Notes is for deliberate structured writing, Whiteboard is for impulsive brain-dumping. Different mental modes, different tabs.

## Core Concept

An infinite canvas where clicking anywhere creates a block. No grid, no alignment, no structure. Content lands wherever you put it. The aesthetic is intentionally loose — sticky notes at slight angles, images with lifted corners, handwritten-feeling text. Think detective evidence board meets personal scratchpad.

## Interaction Model

### Creating Blocks

**Text block:**
- Click anywhere on the canvas → text input cursor appears at that position
- Start typing → text appears inline on the canvas
- Click away or press Escape → input finalizes into a styled sticky note block
- The sticky note gets a subtle random rotation (-3 to +3 degrees), a warm background tint, and a slight drop shadow

**Quote block:**
- Paste text that's wrapped in quotes, or paste from a clipboard that has a quote format
- Auto-detected and formatted as a quote block: vertical accent bar on the left, italic text, slightly different card style than a regular text block
- Could also detect "said" or attribution patterns and style accordingly

**Image block:**
- Drag an image file onto the canvas, or paste from clipboard
- Image renders at a reasonable default size with:
  - One corner slightly lifted (3-5 degree rotation on the corner)
  - Soft drop shadow underneath
  - Optional: a small "pin" or "tape" visual at the top
- Resizable by dragging edges

**URL/Link block:**
- Paste a URL onto the canvas
- Auto-generates a thumbnail preview card (reuse bookmark thumbnail infrastructure)
- Shows: favicon, page title, domain, thumbnail image
- Clicking it opens the URL
- Visually distinct from text blocks — more structured, card-like

**Sketch block (future):**
- Draw directly on the canvas with Apple Pencil or mouse
- Freeform strokes stored as vector paths
- Could use PencilKit on supported devices

### Manipulating Blocks

- **Drag** any block to reposition it on the canvas
- **Resize** blocks by dragging edges/corners
- **Rotate** blocks by grabbing a rotation handle (or two-finger gesture)
- **Delete** via backspace when selected, or right-click > Delete
- **Duplicate** via Cmd+D or right-click > Duplicate
- **Color** — right-click > Change Color to tint the block background

### Multi-Select & Promote

- **Lasso select** — click and drag on empty canvas to draw a selection rectangle
- **Cmd+click** to add/remove blocks from selection
- Selected blocks get a highlight border
- **"Create Note" button** appears when blocks are selected — promotes the selected blocks into a structured note in the Notes tab
  - Text blocks become paragraphs
  - Quote blocks become blockquotes
  - Images become inline images
  - URLs become links
  - The note is created in the user's current folder (or inbox)
- Promoted blocks can optionally remain on the whiteboard (as references) or be removed

### Canvas Navigation

- **Pan** — scroll or two-finger drag to move around the canvas
- **Zoom** — pinch or Cmd+scroll to zoom in/out
- **Minimap** (optional) — small overview in the corner showing block positions at a glance
- **Reset view** — double-click empty space or button to snap back to center/fit-all

## Visual Design

### Block Styles

```
Text Block (Sticky Note):
┌─────────────────┐
│ Random thought   │  ← warm background (cream, light yellow, light pink, light blue)
│ about something  │  ← slight rotation (-3 to +3 deg)
│ I need to        │  ← soft drop shadow
│ remember...      │
└─────────────────┘

Quote Block:
┌──┬──────────────┐
│▐ │ "Design is    │  ← vertical accent bar on left
│▐ │  not just     │  ← italic text
│▐ │  what it      │  ← muted background
│▐ │  looks like"  │
│  │   — Steve Jobs │
└──┴──────────────┘

Image Block:
  ┌──────────────┐╲
  │              │ │  ← one corner slightly lifted
  │   [image]    │ │  ← soft drop shadow
  │              │ │  ← optional pin/tape at top
  └──────────────┘─┘

URL Block:
┌──────────────────┐
│ ┌──────┐         │
│ │thumb │ Page Title│  ← reuse bookmark card style
│ └──────┘ domain.com│  ← favicon + domain
└──────────────────┘
```

### Canvas Background

- Subtle dot grid or graph paper pattern (very low opacity, ~5%)
- Dark background matching Cider's acrylic aesthetic
- Dots/grid help give spatial orientation when panning

### Color Palette for Sticky Notes

Muted, warm tones that work on dark backgrounds:
- Cream/warm white (default)
- Soft yellow
- Light coral/pink
- Light blue
- Light green
- Light purple
- User can change per block via right-click

Colors should be semi-transparent so they blend with the dark canvas rather than looking like Post-its on a white board.

## Connections (v2)

After the basic canvas works:

- **Draw connections** between blocks by dragging from one block's edge to another
- Connection renders as a curved line (bezier) or straight line
- Optional label on the connection (small text along the line)
- Connections are purely visual — they don't create data relationships (yet)
- Style: thin line, slightly transparent, with a subtle arrow at the target end

## Data Model

```swift
struct WhiteboardCanvas: Identifiable, Codable {
    let id: UUID
    var name: String
    var blocks: [WhiteboardBlock]
    var connections: [WhiteboardConnection]
    var viewportCenter: CGPoint  // last camera position
    var viewportZoom: CGFloat    // last zoom level
    var createdAt: Date
    var updatedAt: Date
}

struct WhiteboardBlock: Identifiable, Codable {
    let id: UUID
    var position: CGPoint       // center point on canvas
    var size: CGSize             // width x height
    var rotation: Double         // degrees, -180 to 180
    var content: BlockContent    // what's inside
    var style: BlockStyle        // visual customization
    var zIndex: Int              // layering order
    var createdAt: Date
    var updatedAt: Date
}

enum BlockContent: Codable {
    case text(String)
    case quote(text: String, attribution: String?)
    case image(imageData: Data, originalFilename: String?)
    case url(urlString: String, title: String?, domain: String?, thumbnailData: Data?)
    case sketch(pathData: Data)  // future
}

struct BlockStyle: Codable {
    var backgroundColor: String?  // color name or hex
    var opacity: Double           // 0-1, default 1.0
    var borderVisible: Bool       // default false
    var pinned: Bool              // pinned blocks don't move with canvas gestures
}

struct WhiteboardConnection: Identifiable, Codable {
    let id: UUID
    var fromBlockId: UUID
    var toBlockId: UUID
    var label: String?
    var style: ConnectionStyle    // line type, color, thickness
}

enum ConnectionStyle: Codable {
    case straight
    case curved
    case dashed
}
```

## Relationship to Notes Tab

The Whiteboard and Notes tabs serve different purposes:

| Aspect | Notes | Whiteboard |
|--------|-------|------------|
| Structure | Linear documents with titles | Freeform spatial canvas |
| Creation | Deliberate — create, title, write | Impulsive — click and dump |
| Organization | Folders and tags | Spatial positioning |
| Content | Long-form text, rich formatting | Fragments: short text, images, links, quotes |
| Output | Finished thoughts | Raw material that becomes notes |

The promotion flow: **Whiteboard blocks → select → "Create Note" → Notes tab**

## Implementation Phases

### Phase 1: Basic Canvas (MVP)

The MVP is a "dumb" version that's still useful and charming. The key interaction: **click anywhere on the canvas and start typing.** That's it. No toolbars, no mode switching.

**Core interactions:**
- Click anywhere on empty canvas → text cursor appears at that position → start typing
- Click away or press Escape → text finalizes into a styled sticky note block
- Each block gets a subtle random rotation (-3 to +3 degrees) and warm background tint
- Drag any block to reposition it

**Content auto-detection on paste:**
- Paste plain text → becomes a sticky note block at the cursor position
- Paste a quote (text in quotes or from a recognized quote format) → auto-formats as a quote block with vertical accent bar and italic text
- Paste/drag an image → image block with a slight corner lift and drop shadow
- Paste a URL → generates a thumbnail card (reuse bookmark thumbnail infrastructure) with favicon, title, domain

**Canvas basics:**
- Infinite scrollable/zoomable canvas with subtle dot grid background (~5% opacity)
- Pan via scroll or drag on empty space
- Zoom via Cmd+scroll or pinch
- Persist blocks to local storage (JSON/SQLite)
- Block deletion via backspace/delete when selected

### Phase 2: Polish & Block Types
- Quote block auto-detection and styling
- URL thumbnail generation (reuse bookmark infrastructure)
- Block rotation (random on creation, manual adjustment)
- Block color picker
- Multi-select with lasso
- "Create Note" from selected blocks
- Block resize handles
- Right-click context menu

### Phase 3: Connections & Advanced
- Draw connections between blocks (curved lines)
- Connection labels
- Minimap for canvas overview
- Multiple whiteboards (create new canvases, switch between them)
- Keyboard shortcuts (Delete, Cmd+D duplicate, Cmd+A select all)
- Export whiteboard as image

### Phase 4: Future Ideas
- Sketch/draw blocks (PencilKit or custom)
- Collaboration (shared whiteboards)
- Templates (pre-arranged block layouts for brainstorming, planning, etc.)
- Smart grouping (auto-cluster nearby blocks)
- Linking whiteboard blocks to notes bidirectionally
- Audio block (record a voice memo, drops as a block)

## Tab Architecture

The Whiteboard tab fits into Cider's tab hierarchy as a distinct stage of thought:

| Tab | Purpose | Mental Mode |
|-----|---------|-------------|
| Home | Dashboard / overview | Orienting |
| Bookmarks | Things collected from the web | Collecting |
| Notes | Things written deliberately | Writing |
| **Whiteboard** | **Things dumped without thinking** | **Brainstorming** |
| Books | Long-form reading tracker | Reading |
| Todos | Actionable items and planning | Doing |

Content flows between tabs:
- **Whiteboard → Notes**: Select blocks, promote to structured note
- **Whiteboard → Bookmarks**: URL blocks could be saved as bookmarks
- **Notes → Whiteboard**: Could "send to whiteboard" to break a note apart for rethinking
- **Todos → Whiteboard**: Brain-dump tasks onto the board before organizing them

## Inspiration

- **Miro / FigJam** — infinite canvas with sticky notes and connections (but way heavier)
- **Apple Freeform** — Apple's own freeform canvas app
- **Milanote** — visual mood board / brainstorming tool
- **Kinopio** — spatial thinking tool with cards and connections
- **Real cork boards** — the analog version: pushpins, string, photos at angles

Cider's version is deliberately simpler and more personal. It's not a collaboration tool. It's your brain's overflow area, living inside the same floating panel as your bookmarks and notes.
