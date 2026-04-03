# Phase 2: Utility Panel Detail Mode — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire real item detail views (bookmark, note, todo) into the utility panel so canvas card clicks open items with working dot navigation and back/forward history.

**Architecture:** A new `UtilityPanelCoordinator` (ObservableObject) owns the `DotBuffer` and `PanelHistory` and exposes an `openItem` method. It resolves UUIDs to actual models via existing storage services and manages the active content view. The coordinator replaces the placeholder in `UtilityPanelRootView` with type-switched detail views that directly reuse existing components (`BookmarkMetadataSidebar`, `InlineNoteEditorView`, `TodoDetailView`). Canvas clicks are routed through AppDelegate based on the `useNewPanel` config flag.

**Tech Stack:** SwiftUI, AppKit (NSPanel), existing Cider storage services (VaultBookmarkService, NotesStorage, TodoCardStorage), existing ViewModels (BookmarksViewModel, NotesViewModel)

---

## File Map

### New Files
| File | Responsibility |
|------|---------------|
| `Sources/Cider/ViewModels/UtilityPanelCoordinator.swift` | Owns DotBuffer + PanelHistory, resolves item IDs, manages active view state, coordinates open/close/navigate |
| `Sources/Cider/Views/UtilityPanel/UtilityPanelContentView.swift` | Switches on coordinator state to render bookmark/note/todo detail or placeholder |
| `Sources/Cider/Views/UtilityPanel/UtilityPanelBookmarkDetail.swift` | Wraps `BookmarkMetadataSidebar` with draft state management for the utility panel |
| `Sources/Cider/Views/UtilityPanel/UtilityPanelNoteDetail.swift` | Wraps `InlineNoteEditorView` for the utility panel |
| `Sources/Cider/Views/UtilityPanel/UtilityPanelTodoDetail.swift` | Wraps `TodoDetailView` for the utility panel |
| `Tests/CiderTests/UtilityPanelCoordinatorTests.swift` | Tests for coordinator open/navigate/evict logic |

### Modified Files
| File | Change |
|------|--------|
| `Sources/Cider/Views/UtilityPanel/UtilityPanelRootView.swift` | Replace placeholder with coordinator-driven content |
| `Sources/Cider/Views/UtilityPanel/UtilityPanelHeaderBar.swift` | Wire nav buttons through coordinator instead of raw history |
| `Sources/Cider/App/AppDelegate+UtilityPanel.swift` | Create coordinator, pass ViewModels, observe `.canvasItemSelected` |
| `Sources/Cider/App/AppDelegate.swift` | Add coordinator property, pass bookmarksViewModel/notesViewModel to utility panel setup |
| `Sources/Cider/Models/UtilityPanel/DotBuffer.swift` | Add `activeIndex` public setter (currently private(set), coordinator needs to set it) |

### Existing Files Referenced (read-only, not modified)
| File | What we reuse |
|------|--------------|
| `Sources/Cider/Views/Bookmarks/BookmarkDetailsDraft.swift` | `BookmarkMetadataSidebar`, `BookmarkDetailsDraft` |
| `Sources/Cider/Views/Notes/InlineNoteEditorView.swift` | `InlineNoteEditorView` |
| `Sources/Cider/Views/Todos/TodoDetailView.swift` | `TodoDetailView` |
| `Sources/Cider/ViewModels/BookmarksViewModel.swift` | `bookmarks` array, `saveBookmarkDetails()` |
| `Sources/Cider/ViewModels/NotesViewModel.swift` | `selectNote()`, `flushSave()` |
| `Sources/Cider/Services/TodoCardStorage.swift` | `todoCards` array, `todoCard(for:)` |

---

## Task 1: UtilityPanelCoordinator — State Model

**Files:**
- Create: `Sources/Cider/ViewModels/UtilityPanelCoordinator.swift`
- Modify: `Sources/Cider/Models/UtilityPanel/DotBuffer.swift` (make `activeIndex` settable)

- [ ] **Step 1: Make DotBuffer.activeIndex publicly settable**

In `Sources/Cider/Models/UtilityPanel/DotBuffer.swift`, change:

```swift
@Published private(set) var slots: [DotSlot?] = Array(repeating: nil, count: capacity)
@Published var activeIndex: Int?
```

Remove `private(set)` from `activeIndex` only — it's already `@Published`, but currently the `UtilityPanelDotView` sets it directly via `buffer.activeIndex = index`. Actually, re-check: `activeIndex` is already `var` without `private(set)`. Confirm by reading the file — if it already has a public setter, skip this step.

- [ ] **Step 2: Create UtilityPanelCoordinator**

Create `Sources/Cider/ViewModels/UtilityPanelCoordinator.swift`:

```swift
import Foundation
import SwiftUI
import os

private let logger = Logger(subsystem: "com.cider.app", category: "UtilityPanelCoordinator")

// MARK: - Active Item

enum UtilityPanelActiveItem: Equatable {
    case bookmark(UUID)
    case note(UUID)
    case todo(UUID)

    var itemID: UUID {
        switch self {
        case .bookmark(let id), .note(let id), .todo(let id): return id
        }
    }

    var panelItemType: PanelItemType {
        switch self {
        case .bookmark: return .bookmark
        case .note: return .note
        case .todo: return .todo
        }
    }

    var historyType: PanelHistoryType {
        .item(itemID: itemID)
    }
}

// MARK: - Coordinator

@MainActor
final class UtilityPanelCoordinator: ObservableObject {
    let buffer = DotBuffer()
    let history = PanelHistory()

    /// The currently displayed item (nil = placeholder/tool mode)
    @Published private(set) var activeItem: UtilityPanelActiveItem?

    /// Map from dot slot itemID → UtilityPanelActiveItem (to recover type info from history)
    private var itemTypeMap: [UUID: UtilityPanelActiveItem] = [:]

    // MARK: - Open Item

    func openItem(_ item: UtilityPanelActiveItem, title: String) {
        let slot = DotSlot(
            itemID: item.itemID,
            itemType: item.panelItemType,
            title: title
        )

        let result = buffer.open(item: slot)

        switch result {
        case .opened, .focused:
            itemTypeMap[item.itemID] = item
            activeItem = item
            history.push(PanelHistoryEntry(type: item.historyType))
            logger.debug("Opened \(title) in utility panel")

        case .rejected:
            logger.info("Utility panel full — item rejected: \(title)")
            // TODO: Phase 1 spec says show toast — wire this in later
        }
    }

    // MARK: - Navigation

    func goBack() {
        guard let entry = history.back() else { return }
        navigateToEntry(entry)
    }

    func goForward() {
        guard let entry = history.forward() else { return }
        navigateToEntry(entry)
    }

    // MARK: - Close Active

    func closeActive() {
        guard let activeItem else { return }
        if let index = buffer.index(of: activeItem.itemID) {
            buffer.clear(at: index)
        }
        itemTypeMap.removeValue(forKey: activeItem.itemID)
        self.activeItem = nil
    }

    // MARK: - Dot Tap

    /// Called when user clicks a dot directly.
    func activateDot(at index: Int) {
        guard let slot = buffer.slots[index] else { return }
        buffer.activeIndex = index
        if let item = itemTypeMap[slot.itemID] {
            activeItem = item
            history.push(PanelHistoryEntry(type: item.historyType))
        }
    }

    // MARK: - Private

    private func navigateToEntry(_ entry: PanelHistoryEntry) {
        switch entry.type {
        case .item(let itemID):
            // Re-open into dot if evicted
            if let item = itemTypeMap[itemID] {
                let title = buffer.slots.compactMap({ $0 }).first(where: { $0.itemID == itemID })?.title
                    ?? "Item"
                let slot = DotSlot(
                    itemID: itemID,
                    itemType: item.panelItemType,
                    title: title
                )
                let result = buffer.open(item: slot)
                if case .rejected = result {
                    // Can't re-open — all slots pinned/non-evictable
                    logger.info("Cannot restore evicted item — all slots full")
                    return
                }
                activeItem = item
            }

        case .splitView:
            // Phase 6 — not implemented yet
            break

        case .tool:
            // Phase 4/5 — not implemented yet
            activeItem = nil
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Cider/ViewModels/UtilityPanelCoordinator.swift Sources/Cider/Models/UtilityPanel/DotBuffer.swift
git commit -m "feat(utility-panel): add UtilityPanelCoordinator state manager"
```

---

## Task 2: Coordinator Tests

**Files:**
- Create: `Tests/CiderTests/UtilityPanelCoordinatorTests.swift`

- [ ] **Step 1: Write coordinator tests**

```swift
import XCTest
@testable import Cider

@MainActor
final class UtilityPanelCoordinatorTests: XCTestCase {

    // MARK: - Open Item

    func testOpenItemCreatesSlotAndSetsActive() {
        let coord = UtilityPanelCoordinator()
        let id = UUID()
        coord.openItem(.bookmark(id), title: "Test Bookmark")

        XCTAssertEqual(coord.activeItem, .bookmark(id))
        XCTAssertEqual(coord.buffer.filledCount, 1)
        XCTAssertEqual(coord.buffer.activeIndex, 0)
        XCTAssertEqual(coord.history.stack.count, 1)
    }

    func testOpenDuplicateFocusesExisting() {
        let coord = UtilityPanelCoordinator()
        let id = UUID()
        coord.openItem(.bookmark(id), title: "Bookmark")
        coord.openItem(.note(UUID()), title: "Note")

        XCTAssertEqual(coord.buffer.filledCount, 2)
        XCTAssertEqual(coord.buffer.activeIndex, 1)

        // Re-open same bookmark
        coord.openItem(.bookmark(id), title: "Bookmark")

        XCTAssertEqual(coord.buffer.filledCount, 2) // no duplicate
        XCTAssertEqual(coord.buffer.activeIndex, 0) // focused back
        XCTAssertEqual(coord.activeItem, .bookmark(id))
        XCTAssertEqual(coord.history.stack.count, 3) // 3 pushes
    }

    func testOpenRejectedWhenAllPinned() {
        let coord = UtilityPanelCoordinator()
        for i in 0..<5 {
            coord.openItem(.bookmark(UUID()), title: "Item \(i)")
            coord.buffer.pin(at: i)
        }

        let rejectedID = UUID()
        coord.openItem(.todo(rejectedID), title: "Rejected")

        XCTAssertNotEqual(coord.activeItem, .todo(rejectedID))
        XCTAssertEqual(coord.buffer.filledCount, 5)
    }

    // MARK: - Navigation

    func testBackAndForward() {
        let coord = UtilityPanelCoordinator()
        let id1 = UUID()
        let id2 = UUID()
        coord.openItem(.bookmark(id1), title: "First")
        coord.openItem(.note(id2), title: "Second")

        XCTAssertEqual(coord.activeItem, .note(id2))

        coord.goBack()
        XCTAssertEqual(coord.activeItem, .bookmark(id1))

        coord.goForward()
        XCTAssertEqual(coord.activeItem, .note(id2))
    }

    func testBackToEvictedItemReopensIt() {
        let coord = UtilityPanelCoordinator()
        var ids: [UUID] = []

        // Fill 5 slots
        for i in 0..<5 {
            let id = UUID()
            ids.append(id)
            coord.openItem(.bookmark(id), title: "Item \(i)")
        }

        // Open 6th — evicts slot 0 (ids[0])
        let sixthID = UUID()
        coord.openItem(.bookmark(sixthID), title: "Sixth")
        XCTAssertNil(coord.buffer.index(of: ids[0]))

        // Navigate back through history to ids[0]
        // History: ids[0..4], sixthID — we're at index 5
        for _ in 0..<5 {
            coord.goBack()
        }

        // ids[0] should be re-opened into a dot
        XCTAssertEqual(coord.activeItem, .bookmark(ids[0]))
        XCTAssertNotNil(coord.buffer.index(of: ids[0]))
    }

    // MARK: - Dot Tap

    func testActivateDotSwitchesActiveItem() {
        let coord = UtilityPanelCoordinator()
        let id1 = UUID()
        let id2 = UUID()
        coord.openItem(.bookmark(id1), title: "First")
        coord.openItem(.note(id2), title: "Second")

        coord.activateDot(at: 0)

        XCTAssertEqual(coord.activeItem, .bookmark(id1))
        XCTAssertEqual(coord.buffer.activeIndex, 0)
    }

    // MARK: - Close Active

    func testCloseActiveClearsSlot() {
        let coord = UtilityPanelCoordinator()
        let id = UUID()
        coord.openItem(.bookmark(id), title: "Test")

        coord.closeActive()

        XCTAssertNil(coord.activeItem)
        XCTAssertEqual(coord.buffer.filledCount, 0)
    }

    // MARK: - Item Types

    func testDifferentItemTypesGetCorrectDotColors() {
        let coord = UtilityPanelCoordinator()
        coord.openItem(.bookmark(UUID()), title: "Bookmark")
        coord.openItem(.note(UUID()), title: "Note")
        coord.openItem(.todo(UUID()), title: "Todo")

        XCTAssertEqual(coord.buffer.slots[0]?.itemType, .bookmark)
        XCTAssertEqual(coord.buffer.slots[1]?.itemType, .note)
        XCTAssertEqual(coord.buffer.slots[2]?.itemType, .todo)
    }
}
```

- [ ] **Step 2: Run tests**

Run: `swift test --filter UtilityPanelCoordinatorTests`
Expected: All pass

- [ ] **Step 3: Commit**

```bash
git add Tests/CiderTests/UtilityPanelCoordinatorTests.swift
git commit -m "test(utility-panel): add UtilityPanelCoordinator tests"
```

---

## Task 3: Detail Wrapper Views

**Files:**
- Create: `Sources/Cider/Views/UtilityPanel/UtilityPanelBookmarkDetail.swift`
- Create: `Sources/Cider/Views/UtilityPanel/UtilityPanelNoteDetail.swift`
- Create: `Sources/Cider/Views/UtilityPanel/UtilityPanelTodoDetail.swift`

These are thin wrappers that adapt the existing detail components to work inside the utility panel (no slide-out chrome, no view mode picker — just the content).

- [ ] **Step 1: Create bookmark detail wrapper**

Create `Sources/Cider/Views/UtilityPanel/UtilityPanelBookmarkDetail.swift`:

```swift
import SwiftUI

struct UtilityPanelBookmarkDetail: View {
    let bookmarkID: UUID
    @ObservedObject var bookmarksViewModel: BookmarksViewModel
    @StateObject private var webViewStore = DetailWebViewStore()
    @State private var draft: BookmarkDetailsDraft?
    @State private var errorMessage: String?
    @State private var heroMode: BookmarkHeroMode = .thumbnail

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var bookmark: Bookmark? {
        bookmarksViewModel.bookmarks.first(where: { $0.id == bookmarkID })
    }

    var body: some View {
        if let bookmark, let draft = Binding($draft) {
            ScrollView {
                BookmarkMetadataSidebar(
                    draft: draft,
                    bookmark: bookmark,
                    errorMessage: errorMessage,
                    folders: bookmarksViewModel.folders,
                    width: .infinity,
                    showBackground: false,
                    onDelete: nil,
                    onFolderChanged: { folderID in
                        self.draft?.folderID = folderID
                        saveDetails()
                    },
                    onOpenURL: {
                        if let url = bookmark.url {
                            NSWorkspace.shared.open(url)
                        }
                    },
                    onCopyURL: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(bookmark.urlString, forType: .string)
                    },
                    onSave: { saveDetails() },
                    onCancel: { loadDraft() }
                )
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }
            .onAppear { loadDraft() }
            .onChange(of: bookmarkID) { _, _ in loadDraft() }
        } else {
            PlaceholderMode().contentView
        }
    }

    private func loadDraft() {
        guard let bookmark else { return }
        draft = BookmarkDetailsDraft(bookmark: bookmark)
        let isReaderUnavailable = bookmark.readerUnavailable == true
        let restored = bookmark.preferredHeroMode.flatMap(BookmarkHeroMode.init(rawValue:)) ?? .thumbnail
        heroMode = (restored == .reader && isReaderUnavailable) ? .thumbnail : restored
        if bookmark.hasURL, let url = bookmark.url {
            webViewStore.preload(url: url, bookmarkID: bookmark.id)
        }
    }

    private func saveDetails() {
        guard let draft, let bookmark else { return }
        bookmarksViewModel.saveBookmarkFromDraft(draft, original: bookmark)
    }
}
```

Note: `saveBookmarkFromDraft` may not exist yet — check if `BookmarksViewModel` has it. If not, the save logic in `CiderPanelView+DetailManagement.swift` (`saveBookmarkDetails()`) reads from its local state. For the utility panel, we'll call the underlying service directly. Verify during implementation and adapt the save call.

- [ ] **Step 2: Create note detail wrapper**

Create `Sources/Cider/Views/UtilityPanel/UtilityPanelNoteDetail.swift`:

```swift
import SwiftUI

struct UtilityPanelNoteDetail: View {
    let noteID: UUID
    @ObservedObject var notesViewModel: NotesViewModel

    var body: some View {
        InlineNoteEditorView(viewModel: notesViewModel)
            .onAppear {
                if let note = NotesStorage.shared.notes.first(where: { $0.id == noteID }) {
                    if notesViewModel.selectedNote?.id != noteID {
                        notesViewModel.selectNote(note)
                    }
                }
            }
            .onChange(of: noteID) { _, newID in
                if let note = NotesStorage.shared.notes.first(where: { $0.id == newID }) {
                    notesViewModel.selectNote(note)
                }
            }
    }
}
```

- [ ] **Step 3: Create todo detail wrapper**

Create `Sources/Cider/Views/UtilityPanel/UtilityPanelTodoDetail.swift`:

```swift
import SwiftUI

struct UtilityPanelTodoDetail: View {
    let todoID: UUID

    private var todoCard: TodoCard? {
        TodoCardStorage.shared.todoCard(for: todoID)
    }

    var body: some View {
        if let todoCard {
            ScrollView {
                TodoDetailView(todoCard: todoCard)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
            }
        } else {
            PlaceholderMode().contentView
        }
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add Sources/Cider/Views/UtilityPanel/UtilityPanelBookmarkDetail.swift \
        Sources/Cider/Views/UtilityPanel/UtilityPanelNoteDetail.swift \
        Sources/Cider/Views/UtilityPanel/UtilityPanelTodoDetail.swift
git commit -m "feat(utility-panel): add detail wrapper views for bookmark, note, todo"
```

---

## Task 4: Content View + Root View Wiring

**Files:**
- Create: `Sources/Cider/Views/UtilityPanel/UtilityPanelContentView.swift`
- Modify: `Sources/Cider/Views/UtilityPanel/UtilityPanelRootView.swift`
- Modify: `Sources/Cider/Views/UtilityPanel/UtilityPanelHeaderBar.swift`

- [ ] **Step 1: Create UtilityPanelContentView**

Create `Sources/Cider/Views/UtilityPanel/UtilityPanelContentView.swift`:

```swift
import SwiftUI

struct UtilityPanelContentView: View {
    @ObservedObject var coordinator: UtilityPanelCoordinator
    @ObservedObject var bookmarksViewModel: BookmarksViewModel
    @ObservedObject var notesViewModel: NotesViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch coordinator.activeItem {
            case .bookmark(let id):
                UtilityPanelBookmarkDetail(
                    bookmarkID: id,
                    bookmarksViewModel: bookmarksViewModel
                )
            case .note(let id):
                UtilityPanelNoteDetail(
                    noteID: id,
                    notesViewModel: notesViewModel
                )
            case .todo(let id):
                UtilityPanelTodoDetail(todoID: id)
            case nil:
                PlaceholderMode().contentView
            }
        }
        .animation(reduceMotion ? .none : .snappy, value: coordinator.activeItem)
    }
}
```

- [ ] **Step 2: Update UtilityPanelRootView to use coordinator**

Replace the contents of `Sources/Cider/Views/UtilityPanel/UtilityPanelRootView.swift`:

```swift
import SwiftUI

struct UtilityPanelRootView: View {
    @ObservedObject var coordinator: UtilityPanelCoordinator
    @ObservedObject var bookmarksViewModel: BookmarksViewModel
    @ObservedObject var notesViewModel: NotesViewModel
    let onClose: () -> Void
    let onMaximize: () -> Void

    var body: some View {
        UtilityPanelShell(
            buffer: coordinator.buffer,
            history: coordinator.history,
            onClose: onClose,
            onMaximize: onMaximize
        ) {
            UtilityPanelContentView(
                coordinator: coordinator,
                bookmarksViewModel: bookmarksViewModel,
                notesViewModel: notesViewModel
            )
        }
    }
}
```

- [ ] **Step 3: Update UtilityPanelHeaderBar to use coordinator for nav + dot taps**

In `Sources/Cider/Views/UtilityPanel/UtilityPanelHeaderBar.swift`, add a coordinator parameter and wire the nav buttons and title through it:

Add `@ObservedObject var coordinator: UtilityPanelCoordinator` parameter.

Change nav button actions:
- Back: `coordinator.goBack()` instead of `history.back()`
- Forward: `coordinator.goForward()` instead of `history.forward()`

Change title computation:
```swift
private var currentTitle: String {
    if let activeIndex = coordinator.buffer.activeIndex,
       let slot = coordinator.buffer.slots[activeIndex] {
        return slot.title
    }
    return "Cider"
}
```

Update `UtilityPanelShell` to pass coordinator through to the header bar.

- [ ] **Step 4: Update UtilityPanelDotView to use coordinator for dot taps**

In `Sources/Cider/Views/UtilityPanel/UtilityPanelDotView.swift`, the `onTapGesture` on dots should call `coordinator.activateDot(at: index)` instead of directly setting `buffer.activeIndex`. Add a coordinator parameter or use a callback closure.

Simplest approach: add an `onTap: (Int) -> Void` closure to `UtilityPanelDotView` and `UtilityPanelDotRow`, wired from the header bar.

- [ ] **Step 5: Commit**

```bash
git add Sources/Cider/Views/UtilityPanel/
git commit -m "feat(utility-panel): wire coordinator into root view and header bar"
```

---

## Task 5: AppDelegate Wiring + Canvas Bridge

**Files:**
- Modify: `Sources/Cider/App/AppDelegate.swift`
- Modify: `Sources/Cider/App/AppDelegate+UtilityPanel.swift`

- [ ] **Step 1: Replace standalone DotBuffer/PanelHistory with coordinator in AppDelegate**

In `Sources/Cider/App/AppDelegate.swift`, replace:
```swift
let utilityPanelDotBuffer = DotBuffer()
let utilityPanelHistory = PanelHistory()
```
with:
```swift
let utilityPanelCoordinator = UtilityPanelCoordinator()
```

- [ ] **Step 2: Update configureUtilityPanel() to use coordinator and pass ViewModels**

In `Sources/Cider/App/AppDelegate+UtilityPanel.swift`, update `configureUtilityPanel()`:

```swift
func configureUtilityPanel() {
    guard let bookmarksViewModel, let notesViewModel else { return }

    let panel = CiderUtilityPanel()
    self.ciderUtilityPanel = panel

    let shadowPanel = CiderShadowPanel()
    self.utilityPanelShadowPanel = shadowPanel

    utilityPanelFrameObservation = panel.observe(\.frame, options: [.new]) { [weak self] _, change in
        guard let frame = change.newValue else { return }
        DispatchQueue.main.async { [weak self] in
            self?.utilityPanelShadowPanel?.updateFrame(for: frame)
        }
    }

    let rootView = UtilityPanelRootView(
        coordinator: utilityPanelCoordinator,
        bookmarksViewModel: bookmarksViewModel,
        notesViewModel: notesViewModel,
        onClose: { [weak self] in self?.hideUtilityPanel() },
        onMaximize: { [weak self] in self?.maximizeUtilityPanel() }
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)

    let hostingView = CiderPanelHostingView(rootView: rootView)
    panel.contentView = hostingView
    panel.installMouseTracking()

    panel.setContentSize(NSSize(
        width: UtilityPanelDesign.panelContentWidth,
        height: UtilityPanelDesign.panelContentHeight
    ))
}
```

- [ ] **Step 3: Add canvas item observer for utility panel**

In `Sources/Cider/App/AppDelegate+UtilityPanel.swift`, add to `observeUtilityPanelNotifications()`:

```swift
NotificationCenter.default.publisher(for: .canvasItemSelected)
    .receive(on: DispatchQueue.main)
    .sink { [weak self] notification in
        guard let self else { return }
        guard CiderConfig.load().useNewPanel else { return }
        guard let itemID = notification.userInfo?["bookmarkID"] as? UUID,
              let type = notification.userInfo?["type"] as? String else { return }

        // Don't pop when canvas is active window
        if self.canvasWindow?.isKeyWindow == true { return }

        switch type {
        case "note":
            let title = NotesStorage.shared.notes.first(where: { $0.id == itemID })?.title ?? "Note"
            self.utilityPanelCoordinator.openItem(.note(itemID), title: title)
        case "todo":
            let title = TodoCardStorage.shared.todoCard(for: itemID)?.title ?? "Todo"
            self.utilityPanelCoordinator.openItem(.todo(itemID), title: title)
        default:
            let title = VaultBookmarkService.shared.bookmarks.first(where: { $0.id == itemID })?.title ?? "Bookmark"
            self.utilityPanelCoordinator.openItem(.bookmark(itemID), title: title)
        }

        self.showUtilityPanel()
    }
    .store(in: &cancellables)
```

- [ ] **Step 4: Also handle direct `.openBookmarkDetails` / `.openNoteDetails` / `.openTodoDetails` for utility panel**

Add receivers for the existing detail notifications (these are posted by non-canvas code paths too):

```swift
NotificationCenter.default.publisher(for: .openBookmarkDetails)
    .receive(on: DispatchQueue.main)
    .sink { [weak self] notification in
        guard let self, CiderConfig.load().useNewPanel else { return }
        guard let id = notification.userInfo?["bookmarkID"] as? UUID else { return }
        let title = VaultBookmarkService.shared.bookmarks.first(where: { $0.id == id })?.title ?? "Bookmark"
        self.utilityPanelCoordinator.openItem(.bookmark(id), title: title)
        self.showUtilityPanel()
    }
    .store(in: &cancellables)

NotificationCenter.default.publisher(for: .openNoteDetails)
    .receive(on: DispatchQueue.main)
    .sink { [weak self] notification in
        guard let self, CiderConfig.load().useNewPanel else { return }
        guard let id = notification.userInfo?["noteID"] as? UUID else { return }
        let title = NotesStorage.shared.notes.first(where: { $0.id == id })?.title ?? "Note"
        self.utilityPanelCoordinator.openItem(.note(id), title: title)
        self.showUtilityPanel()
    }
    .store(in: &cancellables)

NotificationCenter.default.publisher(for: .openTodoDetails)
    .receive(on: DispatchQueue.main)
    .sink { [weak self] notification in
        guard let self, CiderConfig.load().useNewPanel else { return }
        guard let id = notification.userInfo?["todoID"] as? UUID else { return }
        let title = TodoCardStorage.shared.todoCard(for: id)?.title ?? "Todo"
        self.utilityPanelCoordinator.openItem(.todo(id), title: title)
        self.showUtilityPanel()
    }
    .store(in: &cancellables)
```

- [ ] **Step 5: Commit**

```bash
git add Sources/Cider/App/AppDelegate.swift Sources/Cider/App/AppDelegate+UtilityPanel.swift
git commit -m "feat(utility-panel): wire canvas clicks and detail notifications to coordinator"
```

---

## Task 6: Build Verification + Manual Test

- [ ] **Step 1: Build**

Run: `swift build -Xswiftc -warnings-as-errors 2>&1 | grep error: | grep -v MLXModelManager | grep -v CiderDragPayload`
Expected: No errors from new/modified files

- [ ] **Step 2: Run all utility panel tests**

Run: `swift test --filter "DotBufferTests|PanelHistoryTests|UtilityPanelCoordinatorTests"`
Expected: All pass

- [ ] **Step 3: Manual test checklist**

Build and run from Xcode with `useNewPanel: true`:

1. Click a bookmark card on canvas → utility panel opens, dot fills with accent color, bookmark metadata shows
2. Click a note card → second dot fills orange, note editor shows
3. Click a todo card → third dot fills green, todo detail shows
4. Click dot 1 → switches back to bookmark, back button enables
5. Click back → returns to previous item
6. Click forward → returns to next item
7. Open 6th item with none pinned → oldest dot gets evicted, new item shows
8. Pin all 5 dots, open 6th → rejected (no crash, item doesn't appear)
9. Close panel, reopen → panel shows last viewed item (state preserved)

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat(utility-panel): Phase 2 complete — detail mode with dot navigation"
```

---

## Notes for Implementation

1. **BookmarkMetadataSidebar `onDelete` / `onSave`**: Check the exact save mechanism. The old panel uses `saveBookmarkDetails()` in `CiderPanelView+DetailManagement.swift` which reads from local `@State`. The utility panel wrapper manages its own `@State draft` and needs to call `VaultBookmarkService.shared` directly or use a `BookmarksViewModel` method. Verify `bookmarksViewModel.saveBookmarkFromDraft()` exists — if not, extract the save logic from the old panel's method.

2. **NotesViewModel shared state**: `InlineNoteEditorView` reads `viewModel.selectedNote` to decide what to render. When the utility panel opens a note, it calls `notesViewModel.selectNote(note)`. If the old panel is also connected to the same `NotesViewModel`, opening a note in the utility panel will change the old panel's state too. This is acceptable since only one panel is active at a time (gated by `useNewPanel`).

3. **Focus/input with notes**: The TipTap editor needs the panel to be key window for typing. The utility panel's focus-follows-mouse should handle this — mouse enters panel → becomes key → editor accepts input. Verify this works during manual testing.

4. **`VaultBookmarkService.shared.bookmarks`** — confirm this is the correct property name by grepping. The exploration showed `bookmarksViewModel.bookmarks` delegates to `VaultBookmarkService.shared.bookmarks`.
