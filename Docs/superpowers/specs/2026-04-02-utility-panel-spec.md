# Cider Utility Panel — Architecture Spec

> The new lightweight NSPanel that replaces the current full-app panel. Built from scratch alongside the existing panel (no extraction). Cherry-picks working components. Old panel stays as fallback until this is proven.

---

## Mental Model

**Canvas = the drawer.** Everything lives there, organized spatially in folders. When you need something, you reach in (click a card, search) and pull it into the panel.

**Panel = the thing in your hand.** It holds what you pulled out. You use it — read it, edit it, share it, drag it to another app. You can hold up to 5 things. When you grab a new item, the oldest unpinned one gets replaced. The panel doesn't organize anything. It doesn't browse. It just holds what you gave it and lets you use it.

---

## Who This Is For

People who collect things (bookmarks, notes, todos, ideas, recipes, game guides) and need them at their fingertips while doing something else. The key word is **while** — view a note while gaming, search a bookmark while chatting, save a thought while it's still in your head.

## Success Criteria

You reach for it without thinking. You search with a half-remembered word and still find the thing. It feels like an extension of your memory — natural, fast, forgiving.

## What This Is NOT

Not Obsidian. Not Notion. Not a workspace you live in. Not a document editor with page hierarchies and databases. Rich content (kanban, markdown, todos) lives on the canvas. The panel holds items and gives them back quickly.

---

## Header Bar

```
[● ● ●]  [◀ ▶]  [○ ● ○ ○ ○]   Item Title              [📋] [🤖] [+]  [Copy] [Open]
traffic   nav    recent items    title                   tool        contextual
lights   btns   (5 dot max,     (changes per view)       buttons     actions
                 items only)                              (always     (per mode)
                                                          available)
```

### Traffic Lights (left)
Custom traffic lights matching the canvas sidebar style. Users need fullscreen (reader mode, split view comparisons), minimize, and close.

### Navigation Buttons (left, after traffic lights)
Back/forward buttons, browser-style. Navigate through the full history — items AND tool modes. Back always means "what I was just looking at." The history is linear: bookmark → clipboard → note → Back → clipboard.

### Recent Item Dots (center-left)
Dots represent **items only** (bookmarks, notes, todos, images). Tool modes (clipboard, AI, search results) are NOT stored in dots — they have dedicated header buttons.

- 5 dots maximum, circular buffer
- Color-coded by item type (blue=bookmark, yellow=note, green=todo, purple=image, etc.)
- Hover → thumbnail preview of the item (split view shows both items side by side)
- Click → jump to that item
- Oldest unpinned dot gets replaced when a new item is opened
- **Pinning:** Small pin icon on hover/click. Pinned dots are not evicted.
- **All 5 pinned or non-evictable:** Opening a 6th item shows a brief toast "Unpin or save an item to open a new one" — no silent data loss. Items with unsaved work (`canEvict = false`) are treated as pinned for eviction purposes.
- **Dedup:** Opening an item that already has a dot → focuses the existing dot, does not create a duplicate.
- Empty dots shown as dim/outline when fewer than 5 items are open
- Split view: two dots connected by a small bar, indicating they're linked. Consumes 2 dot slots. Opening a new item while in split view collapses the split first.

### Title (center)
Shows the current item title or tool name ("Clipboard", "Search Results", "AI Chat"). Changes dynamically per active view.

### Tool Buttons (right)
Always-available buttons for tool modes. These do NOT consume dot slots. They're "tools on your belt" — always one click away. Highlighted when active.
- Clipboard (📋)
- AI Chat (🤖)
- Room for future tools
- Clicking a tool button pushes onto the back/forward history (so Back works) but doesn't create a dot.

### Action Buttons (right, contextual)
Change per mode. For bookmark detail: Copy, Open in Browser. For notes: Share. For clipboard: Clear. Etc.

---

## Two Kinds of Views

### Item Views (stored in dots)
Bookmarks, notes, todos, images — things you pulled from the canvas drawer. Each occupies a dot. Max 5. Pinnable. Evictable (oldest unpinned). Color-coded.

### Tool Views (not in dots)
Utility surfaces that do NOT consume dot slots. Persist their state when you switch away and back (clipboard stays scrolled, AI chat keeps conversation, search keeps results).

**Header-button tools** (always one click away):
- Clipboard — dedicated header button
- AI Chat — dedicated header button

**Contextual tools** (entered via specific actions, no header button):
- Search Results — entered via "Open in Panel" from canvas palette
- Capture — entered via drag onto panel, or when panel has no active item

### Back/Forward History (includes everything)
The back/forward stack tracks ALL views in order — both items and tools. If you view a bookmark, open clipboard, view a note, Back goes: note → clipboard → bookmark. The history is "what did I look at, in order" regardless of type.

---

## PanelMode Protocol

Each view (item or tool) is a self-contained package conforming to a protocol. The panel shell renders whatever's active without knowing the internals. Adding a new mode = one new file.

```swift
protocol PanelMode: Identifiable {
    var id: String { get }
    var title: String { get }
    var modeType: PanelModeType { get }         // .item or .tool
    var headerActions: [PanelHeaderAction] { get }
    var contentView: AnyView { get }

    // Lifecycle
    func onActivate()
    func onDeactivate()

    // Eviction (items only)
    var canEvict: Bool { get }                  // false if unsaved work

    // Layout
    var preferredWidth: CGFloat? { get }        // nil = use default

    // Drag support
    var dragProviders: [NSItemProvider]? { get } // what can be dragged out

    // Keyboard
    var keyboardShortcuts: [PanelKeyboardShortcut]? { get }
}

enum PanelModeType {
    case item    // stored in dots, evictable
    case tool    // header button, always available, not in dots
}
```

This covers focus ownership (onActivate/onDeactivate), dirty state (canEvict), sizing (preferredWidth), drag support, and keyboard shortcuts. No mode-specific conditionals in the shell.

---

## Focus Contract

The panel is `.nonActivatingPanel` by default — it doesn't steal focus from other apps. But it needs typing support for notes, AI chat, search, and capture.

### Focus-follows-mouse (default)
When the mouse hovers over the panel, it becomes key window and accepts keyboard input. When the mouse leaves, it gives up key status. This makes the panel feel like a HUD — hover over it, start typing, move away and it's passive again.

**Editing exception:** The panel does NOT resign key window while a text field has active first responder, a mouse-down/drag is in progress, or IME composition is active. It only resigns on mouse-exit when in a passive state (viewing, scrolling, not editing). This prevents accidental focus loss mid-sentence.

### Click-to-focus (setting)
Optional setting for users who find hover-focus annoying. Panel only becomes key window when explicitly clicked.

### Escape behavior
Escape means "I'm done" — it closes the panel. Back/forward buttons handle history navigation.

- **If a text field is focused** (note editor, search, AI chat): first Escape unfocuses the text field / cancels editing. Second Escape closes the panel.
- **If no text field is focused**: Escape closes (hides) the panel immediately.
- Panel remembers its state when hidden. Double-tap Option reopens to where you left off.

---

## Modes

### Detail Mode (item view)
View/edit a single item. Cherry-picked from existing panel:
- Bookmark: hero image + BookmarkMetadataSidebar (source, folder, tags, keywords, notes, AI intelligence, colors, info, delete)
- Note: TipTap markdown editor (WKWebView)
- Todo: completion state, priority, checklist, details, due date
- Image: full preview with metadata

### Search Mode (tool view)
Only appears inside the panel when results are "opened in panel" from the canvas palette. Shows card-style results with thumbnails, tags, metadata. Click a result → pushes to detail mode. Back → returns to results. Results are draggable into other apps.

### Clipboard Mode (tool view)
Clipboard history. Direct-jump via header button. Items draggable into other apps. State persists when switching away and back.

### AI Chat Mode (tool view)
Local AI chat (Apple Intelligence / MLX). Direct-jump via header button. Ask AI to find items, summarize bookmarks, help write notes. Conversation persists when switching away and back.

### Capture Mode (tool view)
Empty/cleared panel state. Ready to receive:
- Drag in a URL → bookmark created
- Drag in an image → image card created
- Start typing → quick note
- Opt+V → clipboard contents

### Split View Mode (item view, 2 dots)
Two items side-by-side with draggable divider. Triggered by:
- Cmd+click two canvas cards
- Select multiple search results + "Open in Panel"
- Right-click context menu on a card → "Compare with..."
Consumes two dot slots. Connected visually by a linking bar between dots. Opening a new single item collapses the split first.

---

## Search Architecture

One search engine (`SearchService`), one search component (`SearchPaletteView`), two homes:

### Canvas Palette (lightweight, fast)
- Triggered by: Cmd+F, or clicking the sidebar search bar
- Appears as overlay on canvas (spatial context visible behind it)
- Text-based result list (compact, fast)
- Click a result → opens in NSPanel detail mode + canvas flies to card
- Select multiple → "Open in Panel" button or keybind → results transfer to panel search mode
- Palette closes when panel takes over, or on Escape/backdrop click

### Panel Search Mode (power search, tool view)
- Triggered by: "Open in Panel" from canvas palette
- Card-style results with thumbnails, tags, metadata
- Results are draggable into other apps
- Click result → pushes to detail mode within the panel
- Back → returns to card results

Same `SearchService` and `SearchPaletteView` underneath. Same query, same results. Different display density and host window.

---

## Canvas → Panel Flow

| Action | Result |
|--------|--------|
| Click canvas card | Panel opens in detail mode for that card. Canvas flies to card if not visible. |
| Cmd+F → search → click result | Panel opens in detail mode. Canvas flies to card. Palette closes. |
| Cmd+F → search → select multiple → "Open in Panel" | Panel opens in search mode with card results. Palette closes. |
| Double-tap Option | Panel toggles show/hide. Shows last viewed content. |
| Opt+V | Panel opens in clipboard mode. |
| Drag URL/image onto panel | Panel captures it (capture mode). |
| Click clipboard header button | Panel switches to clipboard mode (pushes to back/forward history). |
| Click AI header button | Panel switches to AI chat mode (pushes to back/forward history). |

---

## Panel Behavior

- **`.nonActivatingPanel`** with focus-follows-mouse (or click-to-focus via setting)
- **Saves position** across sessions (user decides where it lives)
- **Pre-loaded** on app launch — instant open, zero cold start
- **Floats above all apps** — read notes while gaming, drag items into Discord
- **Draggable, resizable** — min width matching current panel, max to fullscreen
- **Visual treatment** — acrylic background (`NSVisualEffectView`, `.underWindowBackground`, `.withinWindow`), `CiderColors.borderPanel` border, `CiderBorder.innerStrokeWidth`, matching canvas sidebar aesthetic
- **Animations** — spring only (`.snappy`, `.smooth`, `.bouncy`), respect `reduceMotion`
- **Fonts** — `CiderFont.*` tokens only
- **Colors** — `CiderColors.*` tokens only
- **Logging** — `os.Logger`, not `print()`
- **Hover previews** — in-window overlays only, NOT popovers (popovers crash in non-activating panels)
- **Window level** — `.floating` for above-all-apps behavior. Explicit `collectionBehavior` for Spaces/fullscreen.

---

## What Lives Where

| Feature | Canvas | Panel |
|---------|--------|-------|
| Spatial card layout | ✓ | |
| Folder organization | ✓ | |
| Kanban boards | ✓ | |
| Pan/zoom/navigation | ✓ | |
| Bulk operations | ✓ | |
| Item creation | ✓ | ✓ (capture mode) |
| Search (lightweight filter) | ✓ (sidebar) | |
| Search (full palette) | ✓ (overlay) | ✓ (card results, drag) |
| Item detail/editing | | ✓ |
| Note editor | | ✓ |
| Clipboard history | | ✓ |
| AI chat | | ✓ |
| Cross-app drag | | ✓ |
| Split view comparison | | ✓ |
| Settings | Separate window | |

---

## Dot State Model

```swift
struct DotSlot: Identifiable {
    let id: UUID
    let itemID: UUID                // vault item ID
    let itemType: ItemType          // for dot color
    let title: String
    let previewImage: NSImage?      // for hover thumbnail
    var isPinned: Bool
}

class DotBuffer: ObservableObject {
    @Published var slots: [DotSlot?] = Array(repeating: nil, count: 5)
    @Published var activeIndex: Int?

    func open(item: DotSlot) {
        // If item already has a dot, focus it
        if let existing = slots.firstIndex(where: { $0?.itemID == item.itemID }) {
            activeIndex = existing
            return
        }
        // Find first empty slot, or evict oldest unpinned
        // If all pinned, reject with toast
    }

    func pin(at index: Int) { ... }
    func unpin(at index: Int) { ... }
}
```

### Back/Forward History (separate from dots)

```swift
class PanelHistory: ObservableObject {
    @Published var stack: [PanelHistoryEntry] = []
    @Published var currentIndex: Int = -1

    struct PanelHistoryEntry {
        let id: UUID
        let type: PanelHistoryType
    }

    enum PanelHistoryType {
        case item(itemID: UUID)                         // single item
        case splitView(itemID1: UUID, itemID2: UUID)    // two items side by side
        case tool(ToolMode)                             // clipboard, AI, search, capture
    }

    func push(_ entry: PanelHistoryEntry) { ... }
    func back() -> PanelHistoryEntry? { ... }
    func forward() -> PanelHistoryEntry? { ... }
}
```

The history stack includes items, split views, and tools in chronological order. Dots are a separate visual representation of just the items.

**Key behaviors:**
- Back/forward walks the history stack. Clicking a dot pushes an item history entry.
- **Split view in history:** Back from split view returns to whatever preceded it. Forward restores the split. Split view is a first-class history entry with both item IDs.
- **Evicted items in history:** If Back lands on a history entry whose dot was evicted, the item is re-opened into a dot (evicting the oldest unpinned, same as opening a new item). The history stores the `itemID`, not a dot reference — the vault still has the data. Navigating back simply restores the item to a dot slot.
- **Tool transitions:** Tools don't consume dots but are tracked in history. Back from clipboard → returns to previous view (item or another tool).

---

## Canvas ↔ Panel Interface

Narrow, explicit contract. No reaching into each other's state.

```swift
// Canvas → Panel
protocol PanelController {
    func openItem(_ itemID: UUID)
    func openItems(_ itemIDs: [UUID])           // split view
    func openSearch(query: String, results: [SearchResult])
    func showClipboard()
    func showCapture()
}

// Panel → Canvas
protocol CanvasNavigator {
    func navigateToItem(_ itemID: UUID)         // fly-to animation
    func highlightItem(_ itemID: UUID)          // visual emphasis
}
```

---

## Phase Plan

### Phase 0: State Model Spike (before any UI)
Define and test the dot buffer, back/forward history, and mode switching logic in isolation. Write the transition table. This is the foundation everything hangs on.

Edge cases to validate:
- All 5 dots pinned → open 6th item → toast, rejected
- Unpinned dot with unsaved work (canEvict = false) → treated as pinned for eviction, skipped
- Split view open → open single item → split collapses, new item gets dot
- Split view encoded in history → Back restores split, Forward re-enters it
- Tool mode cycling (item → clipboard → AI → Back → Back → item)
- Dedup: open existing item → focus dot, push history entry
- Evicted dot in history: Back lands on evicted item → re-open into dot (evict oldest unpinned)
- Escape: unfocuses text field first, second Escape hides panel
- History doesn't grow unbounded — cap at reasonable limit (e.g. 50 entries)

### Phase 1: Panel Shell + Toggle
- New `CiderUtilityPanel` NSPanel subclass
- `.nonActivatingPanel`, position saving, resize, custom drag, focus-follows-mouse
- Header bar: traffic lights, back/forward, 5 dots (color, hover preview, pin), title, tool buttons
- `PanelMode` protocol (full version with lifecycle, eviction, drag, sizing)
- Wire dot buffer and history from Phase 0
- Acrylic/border visual treatment matching canvas sidebar
- **Old/new panel toggle** — setting or debug flag to choose which panel Opt activates. Available from day one.

### Phase 2: Detail Mode
- Cherry-pick BookmarkMetadataSidebar, hero rendering from old panel
- Cherry-pick note editor (TipTap WKWebView) from old panel
- Cherry-pick todo detail from old panel
- Wire canvas card click → opens new panel
- Validate focus/input model with note editing

### Phase 3: Search Integration
- "Open in Panel" bridge from canvas palette
- Card-style results view in panel
- Click result → detail mode (push to history + dot)
- Back → returns to results
- Drag results into other apps

### Phase 4: Clipboard
- Cherry-pick clipboard view from old panel
- Header button for clipboard tool mode
- Validate tool mode doesn't consume dots

### Phase 5: Capture + AI Chat
- Capture mode (empty panel as drag target, quick note)
- AI chat mode (local model integration)
- Header button for AI
- AI chat after detail/capture validates the input model

### Phase 6: Split View
- Split view (Cmd+click two items, draggable divider)
- Connected dot visualization (2 slots, linking bar)
- Collapse behavior when opening single item

### Phase 7: Canvas Self-Sufficiency (parallel track)
- Item creation on canvas (new bookmark/note/todo/folder)
- Drag-and-drop capture onto canvas
- Bulk operations (multi-select, move, delete)
- Folder/tag management

### Phase 8: Retire Old Panel
- Verify full feature coverage with new panel
- Switch default to new panel
- Comment out old CiderPanelView
- Delete old panel code after burn-in period
