# Whiteboard Tab Vision

> **Status:** Not Yet Implemented

## Overview

The Whiteboard is a freeform canvas for dumping thoughts, images, links, and quotes. It's the "junk drawer of your brain" — a place to capture anything without structure, then optionally promote clusters of content into structured notes.

It will appear as a **saved view tab** in the tab bar — created by the user via the +New popover. There is no fixed Whiteboard tab; the user opts in by creating one.

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

## Clipboard Capture Flow

The Whiteboard doubles as Cider's **clipboard inbox**. Instead of building a separate clipboard manager, clipboard captures route through the existing toast system — the same one that already handles URL bookmarking.

### How It Works

Every time you copy something, Cider detects it and shows a toast:

**URLs** → "Save as bookmark?" toast (already exists, no change)

**Everything else** (text, images, quotes, code snippets) → "Save to Whiteboard?" toast

That's it. Two paths, both using the same toast pattern. Nothing is captured unless you confirm it.

### Accepting a Toast: Keyboard Shortcuts

When a toast is showing, Cider's existing hotkeys double as accept gestures:

- **Double-tap Option** → save to **Whiteboard** (default — sort it later)
- **Option+N** → save directly as a **Note** (skips Whiteboard, creates a new note)
- **Option+B** → save directly as a **Bookmark** (skips Whiteboard, adds to bookmarks)
- **Ignore / let it expire** → nothing is captured

When no toast is showing, these hotkeys work as normal (double-tap Option opens Cider, Option+N creates a new note, Option+B captures a bookmark from the active browser).

This means:
- No new hotkeys to learn — same gestures you already use for Cider
- **Casual flow:** copy, double-tap Option, sort later on the Whiteboard
- **Power-user flow:** copy, Option+N or Option+B to route directly — skip the Whiteboard entirely
- Ignoring a capture is zero effort — just don't do anything, the toast expires

### What Gets Created

Accepted clipboard content lands on the Whiteboard as a styled block, auto-detected by type:
- **Plain text** → sticky note block (random rotation, warm background)
- **Quoted text** (text in quotes, or with attribution patterns) → quote block (vertical accent bar, italic)
- **Image data** → image block (lifted corner, drop shadow)
- **URL** → routed to bookmarks, not the Whiteboard (existing flow)

### Why No Filtering Is Needed

You copied a 2FA code? Ignore the toast. A password? Ignore it. A Discord username? Ignore. Only the things you actively accept with double-tap Option make it to the Whiteboard. No blocklists, no pattern matching, no settings to configure.

### AI-Powered Sorting (Future)

With AI integration, the Whiteboard could:
- Auto-categorize captured blocks (research, quotes, tasks, references)
- Suggest connections between related blocks (detective-board strings between related items)
- Propose promotions ("These 4 blocks look like a note about X — create one?")
- Cluster nearby blocks by topic automatically

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
