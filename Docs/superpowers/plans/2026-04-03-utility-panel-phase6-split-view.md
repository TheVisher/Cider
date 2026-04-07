# Phase 6: Split View — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two items side-by-side in the utility panel with a draggable divider, consuming 2 linked dot slots, with back/forward history support.

**Architecture:** The coordinator gains a `splitItems` published property alongside `activeItem`/`activeTool`. DotBuffer gets a `linkedPair` that tracks which two slots form the split. Content view branches on `splitItems` to show a `SplitContentView` with a draggable divider. Opening a single item collapses the split first. Entry point: right-click dot → "Compare with..." context menu.

**Tech Stack:** SwiftUI, AppKit (NSPanel), existing coordinator/buffer/history infrastructure.

---

## File Map

### New Files
| File | Responsibility |
|------|---------------|
| `Sources/Cider/Views/UtilityPanel/SplitContentView.swift` | Side-by-side container with draggable divider |

### Modified Files
| File | Change |
|------|--------|
| `Sources/Cider/Models/UtilityPanel/DotBuffer.swift` | Add `linkedPair`, `link()`, `unlink()`, `isLinked()`, `linkedPartner()` |
| `Sources/Cider/ViewModels/UtilityPanelCoordinator.swift` | Add `splitItems`, `openSplitView()`, `collapseSplit()`, `itemForSlot()`, implement `.splitView` history |
| `Sources/Cider/Views/UtilityPanel/UtilityPanelContentView.swift` | Branch on `splitItems` to show SplitContentView |
| `Sources/Cider/Views/UtilityPanel/UtilityPanelDotView.swift` | Linking bar overlay, "Compare with..." context menu |
| `Sources/Cider/Views/UtilityPanel/UtilityPanelBookmarkDetail.swift` | Add `compact` mode (metadata-only, no hero) |
| `Sources/Cider/Views/UtilityPanel/UtilityPanelHeaderBar.swift` | "A vs B" title in split mode, pass onCompare callback |
| `Sources/Cider/Utilities/Constants.swift` | Split view design constants |
| `Tests/CiderTests/DotBufferTests.swift` | Linking tests |
| `Tests/CiderTests/UtilityPanelCoordinatorTests.swift` | Split view tests |

---

## Task 1: DotBuffer Linking

**Files:**
- Modify: `Sources/Cider/Models/UtilityPanel/DotBuffer.swift`
- Modify: `Tests/CiderTests/DotBufferTests.swift`

- [ ] **Step 1: Add linkedPair property and methods**

In `DotBuffer.swift`, add:
```swift
@Published private(set) var linkedPair: (Int, Int)?

func link(_ index1: Int, _ index2: Int) {
    guard index1 != index2,
          (0..<Self.capacity).contains(index1),
          (0..<Self.capacity).contains(index2),
          slots[index1] != nil, slots[index2] != nil else { return }
    linkedPair = (min(index1, index2), max(index1, index2))
}

func unlink() {
    linkedPair = nil
}

func isLinked(_ index: Int) -> Bool {
    guard let pair = linkedPair else { return false }
    return pair.0 == index || pair.1 == index
}

func linkedPartner(of index: Int) -> Int? {
    guard let pair = linkedPair else { return nil }
    if pair.0 == index { return pair.1 }
    if pair.1 == index { return pair.0 }
    return nil
}
```

Modify `clear(at:)` to unlink if clearing a linked slot:
```swift
// At the top of clear(at:)
if isLinked(index) { unlink() }
```

- [ ] **Step 2: Write linking tests**

In `DotBufferTests.swift`, add:
```swift
func testLinkSetsLinkedPair() {
    let buffer = DotBuffer()
    buffer.open(item: makeSlot(title: "A"))
    buffer.open(item: makeSlot(title: "B"))
    buffer.link(0, 1)
    XCTAssertEqual(buffer.linkedPair?.0, 0)
    XCTAssertEqual(buffer.linkedPair?.1, 1)
    XCTAssertTrue(buffer.isLinked(0))
    XCTAssertTrue(buffer.isLinked(1))
    XCTAssertFalse(buffer.isLinked(2))
    XCTAssertEqual(buffer.linkedPartner(of: 0), 1)
}

func testUnlinkClearsLinkedPair() {
    let buffer = DotBuffer()
    buffer.open(item: makeSlot(title: "A"))
    buffer.open(item: makeSlot(title: "B"))
    buffer.link(0, 1)
    buffer.unlink()
    XCTAssertNil(buffer.linkedPair)
    XCTAssertFalse(buffer.isLinked(0))
}

func testLinkEmptySlotIsNoOp() {
    let buffer = DotBuffer()
    buffer.open(item: makeSlot(title: "A"))
    buffer.link(0, 1) // slot 1 is empty
    XCTAssertNil(buffer.linkedPair)
}

func testClearLinkedSlotUnlinks() {
    let buffer = DotBuffer()
    buffer.open(item: makeSlot(title: "A"))
    buffer.open(item: makeSlot(title: "B"))
    buffer.link(0, 1)
    buffer.clear(at: 0)
    XCTAssertNil(buffer.linkedPair)
}
```

- [ ] **Step 3: Run tests**

Run: `swift test --filter DotBufferTests`
Expected: All pass

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(utility-panel): add linked pair support to DotBuffer for split view"
```

---

## Task 2: Design Constants

**Files:**
- Modify: `Sources/Cider/Utilities/Constants.swift`

- [ ] **Step 1: Add split view constants**

In `enum UtilityPanelDesign`, add:
```swift
static let splitDefaultWidth: CGFloat = 880
static let splitMinPaneWidth: CGFloat = 200
static let splitDividerWidth: CGFloat = Spacing.xxs
static let splitDividerGrabWidth: CGFloat = Spacing.sm
static let dotLinkBarHeight: CGFloat = 2
```

- [ ] **Step 2: Commit**

```bash
git commit -m "feat(utility-panel): add split view design constants"
```

---

## Task 3: Coordinator Split View State

**Files:**
- Modify: `Sources/Cider/ViewModels/UtilityPanelCoordinator.swift`
- Modify: `Tests/CiderTests/UtilityPanelCoordinatorTests.swift`

- [ ] **Step 1: Add split state and methods**

Add to coordinator:
```swift
/// The two items shown side-by-side in split view (nil = not in split mode)
@Published private(set) var splitItems: (UtilityPanelActiveItem, UtilityPanelActiveItem)?

func openSplitView(item1: UtilityPanelActiveItem, item2: UtilityPanelActiveItem) {
    collapseSplit()
    activeTool = nil
    activeItem = nil

    // Ensure both items have dot slots
    let title1 = titleMap[item1.itemID] ?? "Item"
    let title2 = titleMap[item2.itemID] ?? "Item"
    let slot1 = DotSlot(itemID: item1.itemID, itemType: item1.panelItemType, title: title1)
    let slot2 = DotSlot(itemID: item2.itemID, itemType: item2.panelItemType, title: title2)

    let r1 = buffer.open(item: slot1)
    if case .rejected = r1 {
        logger.info("Split view rejected — cannot open first item")
        return
    }
    let r2 = buffer.open(item: slot2)
    if case .rejected = r2 {
        logger.info("Split view rejected — cannot open second item")
        return
    }

    guard let i1 = buffer.index(of: item1.itemID),
          let i2 = buffer.index(of: item2.itemID) else { return }

    buffer.link(i1, i2)
    itemTypeMap[item1.itemID] = item1
    itemTypeMap[item2.itemID] = item2
    splitItems = (item1, item2)
    history.push(PanelHistoryEntry(type: .splitView(itemID1: item1.itemID, itemID2: item2.itemID)))
    logger.debug("Opened split view: \(title1) vs \(title2)")
}

/// Look up the UtilityPanelActiveItem for a dot slot (for context menu wiring)
func itemForSlot(_ slot: DotSlot) -> UtilityPanelActiveItem? {
    itemTypeMap[slot.itemID]
}

private func collapseSplit() {
    guard splitItems != nil else { return }
    buffer.unlink()
    splitItems = nil
}
```

- [ ] **Step 2: Modify existing methods**

In `openItem(_:title:)`, add at the top:
```swift
collapseSplit()
```

In `openTool(_:)`, add at the top:
```swift
collapseSplit()
```

In `activateDot(at:)`, add before setting `activeItem`:
```swift
// If tapping a dot that's not part of the current split, collapse split
if splitItems != nil && !buffer.isLinked(index) {
    collapseSplit()
}
// If tapping a dot that IS part of the split, do nothing (split is already showing)
if splitItems != nil && buffer.isLinked(index) { return }
```

In `closeActive()`, update the split handling:
```swift
func closeActive() {
    if activeTool != nil {
        // ... existing tool close logic
        return
    }
    if splitItems != nil {
        // Close split: clear both dots
        if let pair = buffer.linkedPair {
            buffer.clear(at: pair.0)
            buffer.clear(at: pair.1)
        }
        splitItems = nil
        return
    }
    // ... existing item close logic
}
```

Implement `.splitView` in `navigateToEntry(_:)`:
```swift
case .splitView(let itemID1, let itemID2):
    activeTool = nil
    collapseSplit()
    guard let item1 = itemTypeMap[itemID1],
          let item2 = itemTypeMap[itemID2] else {
        logger.info("Cannot restore split — item type info missing")
        return
    }
    let title1 = titleMap[itemID1] ?? "Item"
    let title2 = titleMap[itemID2] ?? "Item"
    let slot1 = DotSlot(itemID: itemID1, itemType: item1.panelItemType, title: title1)
    let slot2 = DotSlot(itemID: itemID2, itemType: item2.panelItemType, title: title2)
    let r1 = buffer.open(item: slot1)
    if case .rejected = r1 { return }
    let r2 = buffer.open(item: slot2)
    if case .rejected = r2 { return }
    if let i1 = buffer.index(of: itemID1), let i2 = buffer.index(of: itemID2) {
        buffer.link(i1, i2)
        activeItem = nil
        splitItems = (item1, item2)
    }
```

Update `preferredWidth`:
```swift
var preferredWidth: CGFloat? {
    if splitItems != nil { return UtilityPanelDesign.splitDefaultWidth }
    guard let tool = activeTool else { return nil }
    // ... existing tool width logic
}
```

- [ ] **Step 3: Write coordinator tests**

```swift
func testOpenSplitViewSetsSplitItems() {
    let coord = UtilityPanelCoordinator()
    let id1 = UUID(), id2 = UUID()
    coord.openItem(.bookmark(id1), title: "First")
    coord.openItem(.note(id2), title: "Second")
    coord.openSplitView(item1: .bookmark(id1), item2: .note(id2))

    XCTAssertNotNil(coord.splitItems)
    XCTAssertNil(coord.activeItem)
    XCTAssertNotNil(coord.buffer.linkedPair)
}

func testOpenItemCollapsesSplit() {
    let coord = UtilityPanelCoordinator()
    let id1 = UUID(), id2 = UUID()
    coord.openItem(.bookmark(id1), title: "First")
    coord.openItem(.note(id2), title: "Second")
    coord.openSplitView(item1: .bookmark(id1), item2: .note(id2))

    let id3 = UUID()
    coord.openItem(.todo(id3), title: "Third")

    XCTAssertNil(coord.splitItems)
    XCTAssertNil(coord.buffer.linkedPair)
    XCTAssertEqual(coord.activeItem, .todo(id3))
}

func testSplitViewInHistory() {
    let coord = UtilityPanelCoordinator()
    let id1 = UUID(), id2 = UUID()
    coord.openItem(.bookmark(id1), title: "First")
    coord.openItem(.note(id2), title: "Second")
    coord.openSplitView(item1: .bookmark(id1), item2: .note(id2))

    // Open single item (collapses split)
    let id3 = UUID()
    coord.openItem(.todo(id3), title: "Third")
    XCTAssertNil(coord.splitItems)

    // Go back to split
    coord.goBack()
    XCTAssertNotNil(coord.splitItems)
    XCTAssertNil(coord.activeItem)
    XCTAssertNotNil(coord.buffer.linkedPair)
}

func testCloseSplitClearsBothDots() {
    let coord = UtilityPanelCoordinator()
    let id1 = UUID(), id2 = UUID()
    coord.openItem(.bookmark(id1), title: "First")
    coord.openItem(.note(id2), title: "Second")
    coord.openSplitView(item1: .bookmark(id1), item2: .note(id2))

    coord.closeActive()
    XCTAssertNil(coord.splitItems)
    XCTAssertEqual(coord.buffer.filledCount, 0)
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter "DotBufferTests|UtilityPanelCoordinatorTests"`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(utility-panel): add split view state and history to coordinator"
```

---

## Task 4: SplitContentView + Bookmark Compact Mode

**Files:**
- Create: `Sources/Cider/Views/UtilityPanel/SplitContentView.swift`
- Modify: `Sources/Cider/Views/UtilityPanel/UtilityPanelBookmarkDetail.swift`

- [ ] **Step 1: Add compact mode to UtilityPanelBookmarkDetail**

Add `var compact: Bool = false` parameter. When `compact`, show metadata-only vertical layout (no hero image, no fixed sidebar width):

```swift
if compact {
    // Metadata-only vertical layout for split view panes
    ScrollView {
        if let bookmark, let draft = Binding($draft) {
            BookmarkMetadataSidebar(
                draft: draft,
                bookmark: bookmark,
                errorMessage: errorMessage,
                folders: bookmarksViewModel.folders,
                width: .infinity,
                showBackground: false,
                // ... same callbacks as existing
            )
            .padding(Spacing.md)
        } else {
            PlaceholderMode().contentView
        }
    }
    .onAppear { loadDraft() }
    .onChange(of: bookmarkID) { _, _ in loadDraft() }
} else {
    // Existing HStack layout
    // ...
}
```

- [ ] **Step 2: Create SplitContentView**

Create `Sources/Cider/Views/UtilityPanel/SplitContentView.swift`:

```swift
import SwiftUI

struct SplitContentView: View {
    let item1: UtilityPanelActiveItem
    let item2: UtilityPanelActiveItem
    @ObservedObject var bookmarksViewModel: BookmarksViewModel
    @ObservedObject var notesViewModel: NotesViewModel

    @State private var leftFraction: CGFloat = 0.5
    @State private var dragStartFraction: CGFloat = 0.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let dividerW = UtilityPanelDesign.splitDividerWidth
            let usable = totalWidth - dividerW
            let leftWidth = max(UtilityPanelDesign.splitMinPaneWidth, usable * leftFraction)
            let rightWidth = max(UtilityPanelDesign.splitMinPaneWidth, usable - leftWidth)

            HStack(spacing: 0) {
                paneView(for: item1)
                    .frame(width: leftWidth)
                    .clipped()

                divider(totalWidth: totalWidth)

                paneView(for: item2)
                    .frame(width: rightWidth)
                    .clipped()
            }
        }
    }

    @ViewBuilder
    private func paneView(for item: UtilityPanelActiveItem) -> some View {
        switch item {
        case .bookmark(let id):
            UtilityPanelBookmarkDetail(
                bookmarkID: id,
                bookmarksViewModel: bookmarksViewModel,
                compact: true
            )
        case .note(let id):
            UtilityPanelNoteDetail(noteID: id, notesViewModel: notesViewModel)
        case .todo(let id):
            UtilityPanelTodoDetail(todoID: id)
        }
    }

    private func divider(totalWidth: CGFloat) -> some View {
        Rectangle()
            .fill(CiderColors.borderSubtle)
            .frame(width: UtilityPanelDesign.splitDividerWidth)
            .contentShape(Rectangle().size(
                width: UtilityPanelDesign.splitDividerGrabWidth,
                height: .infinity
            ))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragStartFraction == leftFraction && value.translation.width != 0 {
                            dragStartFraction = leftFraction
                        }
                        let delta = value.translation.width / totalWidth
                        let newFraction = dragStartFraction + delta
                        let minFrac = UtilityPanelDesign.splitMinPaneWidth / totalWidth
                        leftFraction = min(max(newFraction, minFrac), 1.0 - minFrac)
                    }
                    .onEnded { _ in
                        dragStartFraction = leftFraction
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(utility-panel): add SplitContentView and bookmark compact mode"
```

---

## Task 5: Dot Linking Bar + Compare Context Menu

**Files:**
- Modify: `Sources/Cider/Views/UtilityPanel/UtilityPanelDotView.swift`
- Modify: `Sources/Cider/Views/UtilityPanel/UtilityPanelHeaderBar.swift`

- [ ] **Step 1: Add onCompare callback to DotView and DotRow**

Add `var onCompare: ((Int, Int) -> Void)?` to both `UtilityPanelDotView` and `UtilityPanelDotRow`. Pass through from row to each dot.

- [ ] **Step 2: Add "Compare with..." context menu**

In `UtilityPanelDotView`, add to the context menu:
```swift
if !buffer.isLinked(index), let onCompare {
    Menu("Compare with...") {
        ForEach(0..<DotBuffer.capacity, id: \.self) { otherIndex in
            if otherIndex != index, let otherSlot = buffer.slots[otherIndex] {
                Button(otherSlot.title) {
                    onCompare(index, otherIndex)
                }
            }
        }
    }
}
```

- [ ] **Step 3: Add linking bar overlay to DotRow**

In `UtilityPanelDotRow`, add an overlay after the HStack that draws a bar between linked dots:
```swift
.overlay {
    if let pair = buffer.linkedPair {
        let totalDots = CGFloat(DotBuffer.capacity)
        let dotSize = UtilityPanelDesign.dotTapTarget
        let spacing = UtilityPanelDesign.dotSpacing
        let rowWidth = totalDots * dotSize + (totalDots - 1) * spacing
        let dotCenter1 = CGFloat(pair.0) * (dotSize + spacing) + dotSize / 2
        let dotCenter2 = CGFloat(pair.1) * (dotSize + spacing) + dotSize / 2
        let barX = dotCenter1
        let barWidth = dotCenter2 - dotCenter1

        RoundedRectangle(cornerRadius: 1)
            .fill(CiderColors.controlAccent)
            .frame(width: barWidth, height: UtilityPanelDesign.dotLinkBarHeight)
            .offset(
                x: barX + barWidth / 2 - rowWidth / 2,
                y: UtilityPanelDesign.dotDiameter / 2 + Spacing.xxs
            )
    }
}
```

- [ ] **Step 4: Wire onCompare in HeaderBar**

In `UtilityPanelHeaderBar`, pass `onCompare` to `UtilityPanelDotRow`:
```swift
UtilityPanelDotRow(buffer: coordinator.buffer, onDotTap: { index in
    coordinator.activateDot(at: index)
}, onCompare: { index1, index2 in
    guard let slot1 = coordinator.buffer.slots[index1],
          let slot2 = coordinator.buffer.slots[index2],
          let item1 = coordinator.itemForSlot(slot1),
          let item2 = coordinator.itemForSlot(slot2) else { return }
    coordinator.openSplitView(item1: item1, item2: item2)
})
```

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(utility-panel): add dot linking bar and Compare with context menu"
```

---

## Task 6: Wire Content View + Header Title

**Files:**
- Modify: `Sources/Cider/Views/UtilityPanel/UtilityPanelContentView.swift`
- Modify: `Sources/Cider/Views/UtilityPanel/UtilityPanelHeaderBar.swift`

- [ ] **Step 1: Add split branch to ContentView**

In `UtilityPanelContentView`, update body:
```swift
if let tool = coordinator.activeTool {
    toolView(for: tool)
} else if let split = coordinator.splitItems {
    SplitContentView(
        item1: split.0,
        item2: split.1,
        bookmarksViewModel: bookmarksViewModel,
        notesViewModel: notesViewModel
    )
} else {
    itemView
}
```

- [ ] **Step 2: Update header title for split mode**

In `UtilityPanelHeaderBar`, update `currentTitle`:
```swift
if coordinator.splitItems != nil {
    if let pair = coordinator.buffer.linkedPair,
       let t1 = coordinator.buffer.slots[pair.0]?.title,
       let t2 = coordinator.buffer.slots[pair.1]?.title {
        return "\(t1) vs \(t2)"
    }
    return "Compare"
}
```

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(utility-panel): wire split content view and header title"
```

---

## Task 7: Build Verification + Test

- [ ] **Step 1: Build**

Run: `swift build`
Expected: No new errors

- [ ] **Step 2: Run all utility panel tests**

Run: `swift test --filter "DotBufferTests|PanelHistoryTests|UtilityPanelCoordinatorTests"`
Expected: All pass (including new split view tests)

- [ ] **Step 3: Manual test checklist**

1. Open 2 bookmarks → right-click dot 1 → "Compare with..." → select dot 2 → side-by-side view appears
2. Drag divider left/right → panes resize, minimum width respected
3. Bookmark in split → metadata-only layout (no hero image)
4. Note in split → editor fills pane
5. Open new single item → split collapses, new item shown
6. Press Back → split restored. Press Forward → single item.
7. Linking bar visible between paired dots, disappears on collapse
8. Close while in split → both dots cleared
9. Panel widens to ~880pt for split, narrows back for single items

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(utility-panel): Phase 6 complete — split view with draggable divider"
```
