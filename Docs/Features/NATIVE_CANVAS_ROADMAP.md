# Native Canvas Roadmap

> Implementation roadmap with test criteria and sign-off requirements for each milestone. Each milestone must be tested and approved before moving to the next.

## Status Key

- [x] **Complete** — implemented and tested
- [ ] **Next** — ready to implement
- [ ] **Planned** — designed but not started

---

## Milestone 1: Core Canvas Surface [COMPLETE]

**What shipped:** Pan, zoom, positioned cards, viewport culling, LOD, minimap, fit-all, persistence, hot reload.

**Test results:**
- [x] Cards render at full retina quality (BookmarkCard, NoteCardView, TodoCardCardView)
- [x] Trackpad pan (two-finger scroll) and zoom (pinch)
- [x] Mouse wheel zoom with cursor anchoring
- [x] Click-drag background to pan
- [x] Minimap shows all nodes and viewport rect
- [x] Cmd+0 fits all content
- [x] LOD tiers: colored rects → simplified cards → full detail
- [x] Viewport culling: offscreen cards not rendered
- [x] Positions persist across restarts
- [x] Hot reload: new bookmarks appear on canvas

---

## Milestone 2: Folder Groups & Polish [COMPLETE]

**What shipped:** Folder collapse/expand, auto-sizing, O(1) lookups, batched grid, zoom toolbar, keyboard shortcuts, selection ring, escape deselect, double-click open.

**Test results:**
- [x] Click folder header collapses/expands with animation
- [x] Collapsed folder shrinks to header-only
- [x] Folder sizes auto-calculated from children count
- [x] Zoom % shown in toolbar, click to reset to 100%
- [x] Cmd+/Cmd- zoom shortcuts
- [x] Selected card shows accent border
- [x] Escape clears selection
- [x] Double-click bookmark opens in browser
- [x] CLI: canvas collapse/expand/validate/reset

---

## Milestone 3: Drag-and-Drop Polish

**Goal:** Make card and folder dragging production-quality. Fix remaining drag issues, add multi-select, add drag between folders.

### Features

| Feature | Priority | Complexity |
|---------|----------|------------|
| Fix folder drag bounce on drop | High | Low |
| Drag card out of folder (unparent) | High | Medium |
| Drag card into folder (reparent) | High | Medium |
| Multi-select cards (Cmd+click) | Medium | Medium |
| Multi-drag selected cards | Medium | Medium |
| Drag from panel to canvas | Low | High |

### Test Criteria (must pass before sign-off)

- [ ] Drag folder: moves 1:1 with mouse, no bounce/snap on drop
- [ ] Drag card out of folder: card becomes top-level, positioned where dropped
- [ ] Drag card into folder: card becomes child of that folder group
- [ ] Cmd+click selects multiple cards (selection ring on each)
- [ ] Drag one selected card: all selected cards move together
- [ ] Escape clears multi-selection

### Buy-off
- Manual test all 6 criteria
- Drag at various zoom levels (0.5x, 1x, 1.5x) — 1:1 tracking at all levels
- Canvas validate passes after drag operations

---

## Milestone 4: Sidebar Overlay

**Goal:** Replace the two-window NSPanel docking hack with a native SwiftUI sidebar overlay on the canvas.

### Features

| Feature | Priority | Complexity |
|---------|----------|------------|
| Sidebar overlay with folder tree | High | Medium |
| Frosted glass background | High | Low |
| Click folder → canvas pans to it | High | Low |
| Toggle sidebar with animation | High | Low |
| Opt key undocks to floating NSPanel | Medium | Medium |
| Remove old docking code from AppDelegate | Medium | Low |

### Test Criteria

- [ ] Sidebar appears on left side of canvas with rounded corners
- [ ] Frosted glass: canvas content visible behind at corners
- [ ] Click folder in sidebar: canvas smoothly pans to that folder group
- [ ] Toggle button shows/hides sidebar with spring animation
- [ ] Opt key (or undock button) hides overlay, shows floating NSPanel
- [ ] No two-window lag or shadow issues
- [ ] Old docking code removed: `isPanelDockedToCanvas`, `dockPanelToCanvas()`, etc.

### Buy-off
- All 7 test criteria pass
- Sidebar works at all zoom levels
- Panel undock/redock cycle works 3x without bugs

---

## Milestone 5: Card Detail Overlay

**Goal:** Click a card on canvas to see its full details in a native overlay — replacing the need to open the panel.

### Features

| Feature | Priority | Complexity |
|---------|----------|------------|
| Frosted glass detail modal overlay | High | Medium |
| Reuse BookmarkMetadataSidebar content | High | Medium |
| Animated entrance from card position | Medium | Medium |
| Dismiss with Escape or click outside | High | Low |
| Inline tag editing | Low | Low |
| Inline note editing | Low | Medium |

### Test Criteria

- [ ] Click card → detail overlay appears with entrance animation
- [ ] Overlay shows: thumbnail, title, URL, folder, tags, notes, AI summary
- [ ] Tags display with correct colors
- [ ] Escape dismisses overlay
- [ ] Click outside overlay dismisses it
- [ ] Second card click while overlay open switches to new card

### Buy-off
- Test with bookmark, note, and todo cards
- Overlay renders correctly at various zoom levels
- No performance impact when overlay is dismissed

---

## Milestone 6: Edges & Lines

**Goal:** Visual connections between cards — AI-generated relationships, manual linking.

### Features

| Feature | Priority | Complexity |
|---------|----------|------------|
| Edge rendering (bezier curves) | High | Medium |
| Edges update when cards move | High | Low |
| Edge labels | Medium | Low |
| CLI `canvas link` creates visible edges | High | Low (already works) |
| Click edge to select/delete | Low | Medium |
| Edge color theming | Low | Low |

### Test Criteria

- [ ] CLI: `canvas link <id1> <id2> --label "related"` creates edge
- [ ] Edge renders as curved line between card centers
- [ ] Moving either card updates the edge position live
- [ ] Label appears on edge midpoint
- [ ] Edges respect zoom level (line width scales appropriately)
- [ ] Edges visible in minimap

### Buy-off
- Create 5+ edges via CLI, verify all render
- Drag connected cards, edges follow smoothly
- Zoom in/out — edges remain crisp and readable

---

## Milestone 7: Performance & LOD Tuning

**Goal:** Smooth 60fps with 200+ cards at all zoom levels.

### Features

| Feature | Priority | Complexity |
|---------|----------|------------|
| 4-tier LOD (plan spec thresholds) | High | Low |
| Viewport culling margin tuning | Medium | Low |
| Profile and fix frame drops | High | Medium |
| Lazy thumbnail loading | Medium | Medium |
| Card recycling / virtualization | Low | High |

### Test Criteria

- [ ] 200 cards on canvas: no frame drops during pan at 1x zoom
- [ ] 200 cards: smooth zoom from 0.1x to 2.0x
- [ ] LOD transitions: no visual pop/flash when crossing thresholds
- [ ] Memory usage stable (no growth during extended pan/zoom)
- [ ] Minimap responsive with 200+ nodes

### Buy-off
- Add 200 test bookmarks via CLI, measure FPS during pan/zoom
- Profile in Instruments: no >16ms frames during smooth pan
- Memory stable over 5 min of continuous interaction

---

## Milestone 8: Cleanup & Migration

**Goal:** Remove all WebView canvas code, finalize the native canvas as the default.

### Features

| Feature | Priority | Complexity |
|---------|----------|------------|
| Delete canvas-editor/ React app | High | Low |
| Delete CanvasEditor/ bundle resources | High | Low |
| Remove CiderVaultSchemeHandler (if unused elsewhere) | Medium | Low |
| Remove old canvas JS bridge code | High | Low |
| Update CLAUDE.md / docs | Medium | Low |
| Merge feature/native-canvas → main | High | Low |

### Test Criteria

- [ ] `canvas-editor/` directory deleted
- [ ] `Resources/CanvasEditor/` deleted
- [ ] Build succeeds with no dead code warnings from canvas
- [ ] All 76+ tests pass
- [ ] Canvas CLI validate passes
- [ ] Full manual smoke test: open canvas, pan, zoom, collapse folders, click cards, hot reload

### Buy-off
- Clean build with zero canvas-related warnings
- Full smoke test checklist
- PR review

---

## Implementation Order

```
M1 Core Surface ✓
  ↓
M2 Folders & Polish ✓
  ↓
M3 Drag Polish ← YOU ARE HERE
  ↓
M4 Sidebar Overlay
  ↓
M5 Detail Overlay
  ↓
M6 Edges & Lines
  ↓
M7 Performance Tuning
  ↓
M8 Cleanup & Merge
```

## Principles

1. **Ship each milestone independently.** Don't start M4 until M3 is signed off.
2. **Test at every zoom level.** Most canvas bugs only appear at non-1x zoom.
3. **CLI-testable where possible.** CLI commands let us verify data integrity without GUI.
4. **Commit before agents.** Never dispatch subagents on uncommitted work.
5. **One agent per file.** Never let two parallel agents touch the same source file.
