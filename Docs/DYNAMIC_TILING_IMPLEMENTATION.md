# Dynamic Tiling Implementation Research (Cider)

Last updated: 2026-02-08

## Why this doc exists

This is a practical implementation playbook for robust dynamic tiling in Cider:

- Drag a window from the command palette onto another app.
- Show clear split zones while dragging.
- Create/extend a tile group (2+ windows).
- Keep all windows in the group synchronized when one is resized.
- Keep behavior stable across multi-display setups and real-world app quirks.

This document is based on:

- The current Cider codebase state.
- Open-source window manager implementations (AeroSpace, Rectangle, Amethyst, yabai, Loop).
- Apple platform APIs used by macOS tilers.

## Current Cider state (what exists now)

Cider already has the first pass of dynamic tiling:

- Drag tracking and split overlays:
  - `Sources/Cider/App/AppDelegate.swift`
  - `Sources/Cider/App/TileZoneOverlayPanel.swift`
  - `Sources/Cider/App/SplitZoneOverlayPanel.swift`
  - `Sources/Cider/Views/CommandPalette/TileZoneOverlayView.swift`
  - `Sources/Cider/Views/CommandPalette/SplitZoneOverlayView.swift`
- Tree model + group manager:
  - `Sources/Cider/Models/TileNode.swift`
  - `Sources/Cider/Models/TileGroup.swift`
  - `Sources/Cider/Services/DynamicTileManager.swift`
- Drag payload tracking:
  - `Sources/Cider/ViewModels/CommandPaletteViewModel.swift`
  - `Sources/Cider/Views/CommandPalette/CommandPaletteView.swift`
- Settings toggles:
  - `Sources/Cider/Models/CiderConfig.swift`
  - `Sources/Cider/ViewModels/SettingsViewModel.swift`
  - `Sources/Cider/Views/Settings/GeneralSettingsView.swift`

## Root causes for instability in current implementation

### 1) Coordinate conversion is still primary-screen based

The current implementation repeatedly converts between NS/CG/AX coordinates by using only the first screen height:

- `Sources/Cider/App/AppDelegate.swift:539` and `Sources/Cider/App/AppDelegate.swift:616`
- `Sources/Cider/Utilities/AccessibilityHelpers.swift:177`
- `Sources/Cider/Services/MonitorManager.swift:60`
- `Sources/Cider/Services/WindowManager.swift:1085`

This is fragile in multi-monitor layouts and causes incorrect target detection and frame math.

### 2) Ratio update logic is ambiguous for nested splits

`TileGroup.updateRatio` infers left/right or top/bottom by comparing resized frame midpoint against global group center:

- `Sources/Cider/Models/TileGroup.swift:71`

That heuristic breaks with nested trees, causing wrong split ratio updates.

### 3) AX lifecycle coverage is incomplete for group membership health

Dynamic observers currently register move/resize notifications, but group cleanup is mostly tied to explicit remove/terminate flows:

- `Sources/Cider/Services/DynamicTileManager.swift:206`

Destroyed/minimized transitions should also prune or suspend group membership to avoid stale nodes.

### 4) Drag/drop completion has race-prone branching

`AppDelegate` has multiple cleanup paths around mouse-up, tile completion notifications, split-zone fallback, and delayed teardown:

- `Sources/Cider/App/AppDelegate.swift:386`
- `Sources/Cider/App/AppDelegate.swift:448`

This can leave stale drag state or duplicate completion handling.

### 5) No edge/fence-based resize mapping

When users resize one tiled window, good tilers adjust the nearest controlling split(s), not arbitrary ancestors. Cider currently updates a single parent split by heuristic.

## What high-quality tilers do (research synthesis)

### AeroSpace (tree-normalized tiler)

Key patterns:

- Uses size -> position -> size AX apply ordering:
  - `MacApp.swift` `setFrame(...)` (`#L379-L387`)
- Temporarily disables `AXEnhancedUserInterface` during frame changes:
  - `MacApp.swift` `disableAnimations(...)` (`#L392-L404`)
- Subscribes to destroyed/minimized/deminiaturized notifications:
  - `MacApp.swift` (`#L351-L355`)
- Updates tile weights from actual mouse-driven resize deltas:
  - `resizeWithMouse.swift` (`#L50-L75`)
- Normalizes trees (flatten single-child containers, normalize orientation):
  - `normalizeContainers.swift` (`#L11-L31`)
  - docs `guide.adoc` (`#L286-L338`)

Takeaway for Cider:

- Keep a normalized tree and explicit split ownership.
- Use lifecycle-safe observers and robust AX apply semantics.
- Resize logic should be delta/fence driven, not center heuristic driven.

### Rectangle (drag snapping UX quality)

Key patterns:

- Explicit drag state machine with edge margins and live preview:
  - `SnappingManager.swift` (`#L192-L313`, `#L395-L469`)
- Uses prior snap area to stabilize area selection (hysteresis-like behavior):
  - `ThirdsCompoundCalculation.swift` (`#L13-L37`)
- Uses size -> position -> size, and toggles enhanced UI:
  - `AccessibilityElement.swift` (`#L127-L152`)

Takeaway for Cider:

- Keep zone selection stable while cursor jitters.
- Decouple preview rendering from final drop action.

### Amethyst (layout reacts to manual mouse resize)

Key patterns:

- On resize notification, computes implied ratio from old assigned frame and commits layout ratio:
  - `WindowManager.swift` (`#L630-L667`)
  - `ReflowOperation.swift` `impliedMainPaneRatio` (`#L196-L201`)
- Uses race-tolerant drag/resize state handling:
  - `WindowManager.swift` (`#L653-L673`)

Takeaway for Cider:

- Manual resize should feed back into the tiling model deterministically.

### yabai (deep BSP robustness)

Key patterns:

- Ratio clamping:
  - `view.c` (`#L151-L154`, `#L312-L316`)
- Edge/fence traversal to find which ancestor split to update during resize:
  - `view.c` `window_node_fence` (`#L509-L523`)
- Insertion point controls and auto-balance:
  - `view.c` (`#L751-L803`)
- Batched tree updates followed by a single flush:
  - `event_loop.c` (`#L202-L239`, `#L289-L332`)
- Debounces no-op moved/resized events against current frame:
  - `event_loop.c` (`#L656-L660`, `#L706-L710`)

Takeaway for Cider:

- Resize sync quality comes from ancestor-edge mapping and ratio constraints.
- Batch updates to reduce jitter and feedback loops.

## Recommended Cider architecture (Dynamic Tiling v2)

### 1) Unify geometry in a single service

Add a dedicated service, e.g. `WindowCoordinateSpace.swift`, with per-display conversions:

- Never use `NSScreen.screens.first` for coordinate transforms.
- Resolve display by point/frame overlap.
- Convert NS <-> AX/CG using the matched display's bounds.

Recommended approach:

- Store layout and split math in one coordinate space only (prefer NS global for UI math, convert at AX I/O boundaries).
- Convert once at the edges, not repeatedly through the stack.

### 2) Separate drag orchestration from AppDelegate

Create `DragTilingCoordinator` service and move drag state machine out of `AppDelegate`.

State machine:

- `idle`
- `dragging(windowID, pid)`
- `hovering(targetWindowID, side, screenID)`
- `dropping`
- `cleanup`

Benefits:

- One completion path.
- Easier to test.
- Fewer race conditions.

### 3) Upgrade tree model with path-aware split ownership

Extend `TileNode`/`TileGroup`:

- Add path lookup for a leaf to its ancestors.
- Cache last computed frame per node/leaf during layout.
- Implement edge-based split resolver:
  - Find nearest ancestor split controlling the moved edge(s), similar to yabai fence logic.

Then manual resize updates:

- Detect changed edges against expected frame.
- Update only controlling split ratio(s).
- Clamp ratio to safe bounds (`0.1...0.9` or configurable).

### 4) Observer model: full lifecycle coverage

In `DynamicTileManager` observer registration:

- Keep move/resize notifications.
- Add destroyed + miniaturized + deminiaturized handling.
- On destroyed/minimized:
  - remove or suspend leaf from group.
  - normalize tree.
  - reflow remaining leaves.

### 5) Frame application pipeline

Keep and formalize:

- Batch frame computation.
- Mark windows as "currently tiling" for suppression.
- Apply size -> position -> size.
- Read back actual AX frame after apply.
- Store expected frame with tolerance.

Add:

- Per-batch transaction ID.
- Timeout cleanup to avoid stuck suppression.

### 6) Overlay and target UX

Split-zone UX improvements:

- Add hysteresis deadband around zone boundaries.
- Keep previous zone until cursor crosses a minimum threshold.
- Render preview frame from the same geometry service used by tiler math.

This prevents flicker and side flipping near center diagonals.

### 7) Group semantics

Define behavior explicitly:

- A drop onto a grouped target inserts by splitting that target leaf.
- Dropping third/fourth windows keeps tree normalized.
- Optional setting for auto-balance after insertion/removal.

## Concrete implementation plan (file-by-file)

### Phase 0: Instrumentation and safety

- Add debug categories (`drag`, `target`, `layout`, `ax-apply`, `observer`).
- Keep logs bounded and toggleable.

Targets:

- `Sources/Cider/App/AppDelegate.swift`
- `Sources/Cider/Services/DynamicTileManager.swift`

### Phase 1: Coordinate-space refactor (highest priority)

Create:

- `Sources/Cider/Services/WindowCoordinateSpace.swift`

Update all callsites:

- `Sources/Cider/App/AppDelegate.swift`
- `Sources/Cider/Utilities/AccessibilityHelpers.swift`
- `Sources/Cider/Services/MonitorManager.swift`
- `Sources/Cider/Services/WindowManager.swift`

Exit criteria:

- Correct targeting and overlay on any display arrangement.

### Phase 2: Drag coordinator and cleanup unification

Create:

- `Sources/Cider/Services/DragTilingCoordinator.swift`

Refactor:

- `Sources/Cider/App/AppDelegate.swift`
- `Sources/Cider/ViewModels/CommandPaletteViewModel.swift`

Exit criteria:

- Exactly one completion/cleanup path per drag.

### Phase 3: Tree math and resize propagation

Refactor:

- `Sources/Cider/Models/TileNode.swift`
- `Sources/Cider/Models/TileGroup.swift`
- `Sources/Cider/Services/DynamicTileManager.swift`

Add:

- path/fence-style ancestor resolution
- edge-aware ratio update
- optional auto-balance

Exit criteria:

- Resizing one tiled window updates siblings correctly for 2+ windows.

### Phase 4: Observer lifecycle hardening

Refactor:

- `Sources/Cider/Services/DynamicTileManager.swift`

Add handling:

- destroyed/minimized/deminiaturized
- safe group normalization after removals

Exit criteria:

- No stale groups when windows close/minimize/restore.

### Phase 5: Overlay UX polish

Refactor:

- `Sources/Cider/Views/CommandPalette/SplitZoneOverlayView.swift`
- `Sources/Cider/App/AppDelegate.swift`

Add:

- hysteresis
- stable side selection
- shared geometry source

Note: replace magic numbers (`inset: 4`, line width `2`, edge fractions) with design tokens/constants.

## Testing strategy

### Unit tests

- `TileNode` invariants:
  - split replacement
  - removal normalization
  - ratio clamping
  - frame partition correctness
- new coordinate service:
  - NS <-> AX conversion for single and multi-display fixtures
  - target-window monitor resolution

### Integration tests

- Simulated drag sequence:
  - 2-window split creation
  - third-window insertion
  - drop cancel path
- Resize sync:
  - left/right/top/bottom edge drags
  - nested split updates

### Manual QA scenarios

- Monitors left/right/above/below primary.
- Different scale factors (Retina/non-Retina mix).
- Windows with minimum size constraints.
- Minimize, close, app quit while grouped.
- Reduce Motion enabled.

## Suggested settings to expose

Keep existing toggles and add:

- `dynamicTilingAutoBalance` (Bool, default false)
- `dynamicTilingResizeDebounceMs` (Int, default ~50)
- `dynamicTilingFeedbackTolerancePx` (Int, default ~2)
- `dynamicTilingZoneHysteresisPx` (Int, default ~10)

These should follow `Docs/USER_PREFERENCES.md` checklist and map into `CiderConfig`.

## Acceptance criteria

Dynamic tiling is "good enough" when all are true:

1. Dragging from palette reliably identifies target window and split side on any display.
2. Dropping creates predictable 2-window splits.
3. Adding third/fourth windows maintains a stable tree and expected layout.
4. Manual resize of any tiled window updates adjacent windows with no oscillation.
5. Closing/minimizing grouped windows does not leave stale state.
6. No focus stealing from overlays (`NSPanel` + `.nonactivatingPanel` retained).

## Inferences made from sources

- The biggest stability gains come from three combined changes: coordinate unification, fence-based ratio updates, and lifecycle-complete observers.
- Existing Cider behavior is close to working for simple 2-window cases but fails under nested/multi-display/race-heavy paths because those three layers are not yet unified.

## External references

### Apple APIs

- [NSWindow.StyleMask.nonactivatingPanel](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel)
- [NSPanel](https://developer.apple.com/documentation/appkit/nspanel)
- [CGWindowListCopyWindowInfo](https://developer.apple.com/documentation/coregraphics/1455137-cgwindowlistcopywindowinfo)
- [AXUIElementSetAttributeValue](https://developer.apple.com/documentation/applicationservices/1462091-axuielementsetattributevalue)
- [AXObserverAddNotification](https://developer.apple.com/documentation/applicationservices/1459139-axobserveraddnotification)
- [AXUIElementCopyAttributeValue](https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue)

### AeroSpace

- [AeroSpace repo](https://github.com/nikitabobko/AeroSpace)
- [setFrame + AXEnhancedUI workaround](https://github.com/nikitabobko/AeroSpace/blob/18545c2/Sources/AppBundle/tree/MacApp.swift#L379-L404)
- [AX window lifecycle subscriptions](https://github.com/nikitabobko/AeroSpace/blob/18545c2/Sources/AppBundle/tree/MacApp.swift#L351-L357)
- [mouse resize weight updates](https://github.com/nikitabobko/AeroSpace/blob/18545c2/Sources/AppBundle/mouse/resizeWithMouse.swift#L50-L75)
- [container normalization implementation](https://github.com/nikitabobko/AeroSpace/blob/18545c2/Sources/AppBundle/tree/normalizeContainers.swift#L11-L31)
- [tree + normalization docs](https://github.com/nikitabobko/AeroSpace/blob/18545c2/docs/guide.adoc#tree)

### Rectangle

- [Rectangle repo](https://github.com/rxhanson/Rectangle)
- [drag snap manager](https://github.com/rxhanson/Rectangle/blob/1eaa6dc/Rectangle/Snapping/SnappingManager.swift#L192-L469)
- [compound snap hysteresis behavior](https://github.com/rxhanson/Rectangle/blob/1eaa6dc/Rectangle/Snapping/CompoundSnapArea/ThirdsCompoundCalculation.swift#L13-L37)
- [setFrame ordering + AXEnhancedUI handling](https://github.com/rxhanson/Rectangle/blob/1eaa6dc/Rectangle/AccessibilityElement.swift#L127-L152)

### Amethyst

- [Amethyst repo](https://github.com/ianyh/Amethyst)
- [BSP tree structure and insertion/removal](https://github.com/ianyh/Amethyst/blob/d34119c/Amethyst/Layout/Layouts/BinarySpacePartitioningLayout.swift#L11-L158)
- [mouse resize -> pane ratio recommendation](https://github.com/ianyh/Amethyst/blob/d34119c/Amethyst/Managers/WindowManager.swift#L630-L667)
- [implied ratio math](https://github.com/ianyh/Amethyst/blob/d34119c/Amethyst/Layout/ReflowOperation.swift#L196-L201)
- [config flag for mouse-resizes-windows](https://github.com/ianyh/Amethyst/blob/d34119c/docs/configuration-files.md#configuration-keys)

### yabai

- [yabai repo](https://github.com/koekeishiya/yabai)
- [split ratio clamp + area split math](https://github.com/koekeishiya/yabai/blob/5bde933/src/view.c#L151-L193)
- [fence ancestor selection for resize](https://github.com/koekeishiya/yabai/blob/5bde933/src/view.c#L509-L523)
- [insertion point + auto-balance](https://github.com/koekeishiya/yabai/blob/5bde933/src/view.c#L751-L803)
- [debounced move/resize event handling](https://github.com/koekeishiya/yabai/blob/5bde933/src/event_loop.c#L640-L792)
- [AX batching/flush notes](https://github.com/koekeishiya/yabai/blob/5bde933/src/event_loop.c#L202-L239)
