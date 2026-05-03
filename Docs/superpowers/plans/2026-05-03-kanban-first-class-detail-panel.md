# Kanban First-Class Detail Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Kanban cards open in Cider's shared slide-out detail panel, support long-form product/refactor notes directly on the card, and export a card to Markdown on demand without creating extra vault notes by default.

**Architecture:** Kanban joins the existing centralized detail-selection system in `CiderPanelView`, using `GenericItemDetailPanel` as the shared shell. The Kanban card editor becomes panel content with a large notes/spec editor, while a Kanban-specific metadata rail owns board, status, priority, color, tags, agent, dates, delete, and Markdown export. Long-form preservation and Markdown export are covered by pure Swift tests.

**Tech Stack:** Swift, SwiftUI, Swift Testing, existing YAML-backed `KanbanStorage`, existing `CiderFileExporter`/`NSSavePanel` export utilities.

---

## File Structure

- Create `Sources/Cider/Views/Kanban/KanbanCardDraft.swift`
  - Holds editable Kanban card state, normalizes title/notes/agent/tags, and produces updated `KanbanCard`.
- Create `Sources/Cider/Views/Kanban/KanbanCardMarkdownExporter.swift`
  - Builds Markdown text and safe default filenames for a card export.
- Modify `Sources/Cider/Views/Kanban/KanbanCardDetailView.swift`
  - Convert from modal chrome to reusable slide-out content with a large long-form editor.
- Create `Sources/Cider/Views/Kanban/KanbanCardMetadataInspectorView.swift`
  - Kanban-specific metadata rail for board/status/priority/color/tags/agent/dates/delete/export.
- Modify `Sources/Cider/Views/Kanban/KanbanBoardView.swift`
  - Remove modal overlay state; accept `onOpenCard` and invoke it on card click.
- Modify `Sources/Cider/Views/CiderPanelView.swift`
  - Add selected Kanban board/card state and include Kanban slide-out overlay in existing shell.
- Modify `Sources/Cider/Views/CiderPanelView+ContentArea.swift`
  - Pass `openKanbanCardDetail(boardID:cardID:)` into `KanbanBoardView`.
- Modify `Sources/Cider/Views/CiderPanelView+DetailManagement.swift`
  - Add Kanban to detail navigation policy and open/close/delete/export helpers.
- Modify `Sources/Cider/Views/CiderPanelView+DetailViews.swift`
  - Render Kanban cards in `GenericItemDetailPanel` with content plus metadata.
- Modify `Tests/CiderTests/CiderDetailNavigationPolicyTests.swift`
  - Assert Kanban participates in the one-detail-at-a-time policy.
- Create `Tests/CiderTests/KanbanCardDraftTests.swift`
  - Test long notes are preserved and normalization is conservative.
- Create `Tests/CiderTests/KanbanCardMarkdownExporterTests.swift`
  - Test Markdown export contains title, board/status metadata, tags, agent, and full long-form body.

## Product Decisions

- Kanban card notes are the source of truth for product/refactor briefs. Do not create a `Note` or `.md` file when editing or saving a Kanban card.
- The board card remains compact: title, short notes preview, priority/color/tags.
- The slide-out main area prioritizes writing: title plus one large multiline notes/spec editor that can comfortably hold a long chat summary.
- Markdown export is explicit and one-way: user chooses "Export Markdown", Cider writes a `.md` file via save panel, and the Kanban card remains the canonical object.
- Checklist and acceptance criteria can be added later as structured fields. For this pass, acceptance criteria can live inside notes as Markdown text.

---

### Task 1: Add Pure Draft and Markdown Export Tests

**Files:**
- Create: `Tests/CiderTests/KanbanCardDraftTests.swift`
- Create: `Tests/CiderTests/KanbanCardMarkdownExporterTests.swift`
- Create in Task 2: `Sources/Cider/Views/Kanban/KanbanCardDraft.swift`
- Create in Task 2: `Sources/Cider/Views/Kanban/KanbanCardMarkdownExporter.swift`

- [ ] **Step 1: Write failing draft tests**

Create `Tests/CiderTests/KanbanCardDraftTests.swift`:

```swift
import Foundation
import Testing
@testable import Cider

struct KanbanCardDraftTests {
    @Test("draft preserves very long product refinement notes")
    func draftPreservesVeryLongProductRefinementNotes() {
        let longNotes = (1...300)
            .map { "Refactor note \($0): preserve this paragraph exactly enough for product refinement." }
            .joined(separator: "\n\n")
        let card = KanbanCard(
            id: "card-1",
            title: "Refactor capture pipeline",
            notes: longNotes,
            color: .blue,
            priority: .high,
            agent: "Codex",
            tags: ["refactor", "capture"],
            created: Date(timeIntervalSince1970: 100),
            completed: nil
        )

        let draft = KanbanCardDraft(card: card)
        let updated = draft.updatedCard(from: card)

        #expect(updated.notes == longNotes)
        #expect(updated.title == "Refactor capture pipeline")
        #expect(updated.tags == ["refactor", "capture"])
    }

    @Test("draft normalizes empty title, blank notes, blank agent, and comma tags")
    func draftNormalizesEditableFields() {
        var draft = KanbanCardDraft(card: KanbanCard(id: "card-2", title: "Original"))
        draft.title = "   "
        draft.notes = "   \n  "
        draft.agent = "   "
        draft.tagsText = " roadmap,  refinement, roadmap ,  "

        let updated = draft.updatedCard(from: KanbanCard(id: "card-2", title: "Original"))

        #expect(updated.title == "Untitled Card")
        #expect(updated.notes == nil)
        #expect(updated.agent == nil)
        #expect(updated.tags == ["roadmap", "refinement", "roadmap"])
    }
}
```

- [ ] **Step 2: Write failing Markdown exporter tests**

Create `Tests/CiderTests/KanbanCardMarkdownExporterTests.swift`:

```swift
import Foundation
import Testing
@testable import Cider

struct KanbanCardMarkdownExporterTests {
    @Test("markdown export includes metadata and full notes")
    func markdownExportIncludesMetadataAndFullNotes() {
        let notes = """
        ## Context

        We discussed making Kanban a first-class planning surface.

        ## Acceptance Criteria

        - Card opens in slide-out
        - Long notes stay on the card
        - Export is explicit
        """

        let card = KanbanCard(
            id: "abc123",
            title: "Kanban detail panel",
            notes: notes,
            color: .green,
            priority: .high,
            agent: "Hermes",
            tags: ["kanban", "product"],
            created: Date(timeIntervalSince1970: 0),
            completed: nil
        )

        let markdown = KanbanCardMarkdownExporter.markdown(
            for: card,
            boardName: "Cider Roadmap",
            columnName: "In Progress"
        )

        #expect(markdown.contains("# Kanban detail panel"))
        #expect(markdown.contains("- Board: Cider Roadmap"))
        #expect(markdown.contains("- Status: In Progress"))
        #expect(markdown.contains("- Priority: high"))
        #expect(markdown.contains("- Color: green"))
        #expect(markdown.contains("- Agent: Hermes"))
        #expect(markdown.contains("- Tags: kanban, product"))
        #expect(markdown.contains(notes))
    }

    @Test("markdown filename is safe and ends in md")
    func markdownFilenameIsSafe() {
        let card = KanbanCard(id: "abc123", title: "Refactor: capture / save pipeline?")

        #expect(KanbanCardMarkdownExporter.suggestedFileName(for: card) == "Refactor capture save pipeline.md")
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run:

```bash
swift test --filter KanbanCardDraftTests
swift test --filter KanbanCardMarkdownExporterTests
```

Expected: both fail because `KanbanCardDraft` and `KanbanCardMarkdownExporter` do not exist.

---

### Task 2: Implement Draft and Markdown Export Helpers

**Files:**
- Create: `Sources/Cider/Views/Kanban/KanbanCardDraft.swift`
- Create: `Sources/Cider/Views/Kanban/KanbanCardMarkdownExporter.swift`
- Test: `Tests/CiderTests/KanbanCardDraftTests.swift`
- Test: `Tests/CiderTests/KanbanCardMarkdownExporterTests.swift`

- [ ] **Step 1: Add `KanbanCardDraft`**

Create `Sources/Cider/Views/Kanban/KanbanCardDraft.swift`:

```swift
import Foundation

struct KanbanCardDraft: Equatable {
    var title: String
    var notes: String
    var color: KanbanCardColor?
    var priority: KanbanPriority?
    var agent: String
    var tagsText: String

    init(card: KanbanCard) {
        title = card.title
        notes = card.notes ?? ""
        color = card.color
        priority = card.priority
        agent = card.agent ?? ""
        tagsText = card.tags.joined(separator: ", ")
    }

    func updatedCard(from original: KanbanCard) -> KanbanCard {
        var updated = original

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.title = trimmedTitle.isEmpty ? "Untitled Card" : trimmedTitle

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.notes = trimmedNotes.isEmpty ? nil : notes

        let trimmedAgent = agent.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.agent = trimmedAgent.isEmpty ? nil : trimmedAgent

        updated.color = color
        updated.priority = priority
        updated.tags = tagsText
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return updated
    }
}
```

- [ ] **Step 2: Add `KanbanCardMarkdownExporter`**

Create `Sources/Cider/Views/Kanban/KanbanCardMarkdownExporter.swift`:

```swift
import Foundation

enum KanbanCardMarkdownExporter {
    static func markdown(for card: KanbanCard, boardName: String, columnName: String) -> String {
        var lines: [String] = []
        lines.append("# \(card.title)")
        lines.append("")
        lines.append("- Board: \(boardName)")
        lines.append("- Status: \(columnName)")
        if let priority = card.priority {
            lines.append("- Priority: \(priority.rawValue)")
        }
        if let color = card.color {
            lines.append("- Color: \(color.rawValue)")
        }
        if let agent = card.agent, !agent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("- Agent: \(agent)")
        }
        if !card.tags.isEmpty {
            lines.append("- Tags: \(card.tags.joined(separator: ", "))")
        }
        lines.append("- Created: \(formattedDate(card.created))")
        if let completed = card.completed {
            lines.append("- Completed: \(formattedDate(completed))")
        }
        lines.append("")
        lines.append("## Notes")
        lines.append("")
        lines.append(card.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? card.notes! : "_No notes yet._")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    static func suggestedFileName(for card: KanbanCard) -> String {
        let cleaned = card.title
            .components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:"))
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\((cleaned.isEmpty ? "Kanban Card" : cleaned)).md"
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
```

- [ ] **Step 3: Run helper tests**

Run:

```bash
swift test --filter KanbanCardDraftTests
swift test --filter KanbanCardMarkdownExporterTests
```

Expected: both pass.

- [ ] **Step 4: Commit helper work**

```bash
git add Sources/Cider/Views/Kanban/KanbanCardDraft.swift Sources/Cider/Views/Kanban/KanbanCardMarkdownExporter.swift Tests/CiderTests/KanbanCardDraftTests.swift Tests/CiderTests/KanbanCardMarkdownExporterTests.swift
git commit -m "feat: add kanban card draft and markdown export helpers"
```

---

### Task 3: Add Kanban to Central Detail Navigation

**Files:**
- Modify: `Sources/Cider/Views/CiderPanelView+DetailManagement.swift`
- Modify: `Sources/Cider/Views/CiderPanelView.swift`
- Modify: `Tests/CiderTests/CiderDetailNavigationPolicyTests.swift`

- [ ] **Step 1: Write failing navigation test**

Append this test to `Tests/CiderTests/CiderDetailNavigationPolicyTests.swift`:

```swift
    @Test("opening kanban clears other detail surfaces")
    func openingKanbanClearsOtherDetailSurfaces() {
        let cleared = CiderDetailNavigationPolicy.surfacesToClear(whenOpening: .kanban)

        #expect(cleared.contains(.bookmark))
        #expect(cleared.contains(.note))
        #expect(cleared.contains(.todo))
        #expect(!cleared.contains(.kanban))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter CiderDetailNavigationPolicyTests
```

Expected: fail because `.kanban` is not a `CiderDetailSurfaceKind` case.

- [ ] **Step 3: Add Kanban detail state**

In `Sources/Cider/Views/CiderPanelView+DetailManagement.swift`, add `.kanban`:

```swift
enum CiderDetailSurfaceKind: CaseIterable, Hashable {
    case bookmark
    case note
    case dateCard
    case contact
    case todo
    case vaultFile
    case kanban
}
```

In `Sources/Cider/Views/CiderPanelView.swift`, add state next to the other selected detail states:

```swift
@State var selectedKanbanBoardID: String?
@State var selectedKanbanCardID: String?
@State var kanbanMetadataVisible: Bool = true
```

- [ ] **Step 4: Clear Kanban when other details open**

In `clearDetailSelectionState(except:)`, add:

```swift
if surfacesToClear.contains(.kanban) {
    selectedKanbanBoardID = nil
    selectedKanbanCardID = nil
}
```

In `closeGenericDetail()` and `closeAllDetails()`, clear the Kanban state too:

```swift
selectedKanbanBoardID = nil
selectedKanbanCardID = nil
```

Update `isAnyDetailOpen` to include Kanban once Task 5 adds `isKanbanDetailOpen`.

- [ ] **Step 5: Run navigation tests**

Run:

```bash
swift test --filter CiderDetailNavigationPolicyTests
```

Expected: pass.

- [ ] **Step 6: Commit navigation state**

```bash
git add Sources/Cider/Views/CiderPanelView.swift Sources/Cider/Views/CiderPanelView+DetailManagement.swift Tests/CiderTests/CiderDetailNavigationPolicyTests.swift
git commit -m "feat: add kanban to detail navigation policy"
```

---

### Task 4: Route Board Card Clicks to the Shared Detail System

**Files:**
- Modify: `Sources/Cider/Views/Kanban/KanbanBoardView.swift`
- Modify: `Sources/Cider/Views/CiderPanelView+ContentArea.swift`
- Modify: `Sources/Cider/Views/CiderPanelView+DetailManagement.swift`

- [ ] **Step 1: Remove modal state from `KanbanBoardView`**

In `KanbanBoardView`, replace:

```swift
@State private var editingCard: KanbanCard?
```

with:

```swift
var onOpenCard: (String, String) -> Void = { _, _ in }
```

Remove the `ZStack` modal overlay in `body`. The board body should become:

```swift
var body: some View {
    if let board {
        VStack(spacing: 0) {
            boardHeader(board)
            Divider().background(CiderColors.separator)
            columnsArea(board)
        }
    } else {
        emptyState
    }
}
```

- [ ] **Step 2: Open the selected card by ID**

In the card tap gesture, replace:

```swift
editingCard = card
```

with:

```swift
onOpenCard(boardID, card.id)
```

Remove the `.animation(..., value: editingCard != nil)` modifier because modal presentation has moved to `CiderPanelView`.

- [ ] **Step 3: Add open helper**

In `Sources/Cider/Views/CiderPanelView+DetailManagement.swift`, add:

```swift
func openKanbanCardDetail(boardID: String, cardID: String) {
    if isSearchPaletteVisible { isSearchPaletteVisible = false }
    if isNoteDetailOpen { notesViewModel.flushSave() }
    if isDetailOpen { saveBookmarkDetails() }

    guard KanbanStorage.shared.findCard(id: cardID)?.board.id == boardID else { return }

    let wasExpanded = isAnyDetailOpen
    clearDetailSelectionState(except: .kanban)
    kanbanMetadataVisible = true
    selectedKanbanBoardID = boardID
    selectedKanbanCardID = cardID

    if !wasExpanded {
        NotificationCenter.default.post(
            name: .expandCiderPanelForSlideOut,
            object: nil,
            userInfo: ["minimumWidth": BookmarksDesign.detailsSlideOutExpandedPanelMinWidth]
        )
    }

    if let found = KanbanStorage.shared.findCard(id: cardID) {
        AIAssistantViewModel.shared.updateContext(
            todo: (title: found.card.title, status: found.column.name)
        )
    }
}
```

- [ ] **Step 4: Pass callback into Kanban tab**

In `Sources/Cider/Views/CiderPanelView+ContentArea.swift`, replace:

```swift
KanbanBoardView(boardID: boardID)
```

with:

```swift
KanbanBoardView(boardID: boardID, onOpenCard: openKanbanCardDetail)
```

- [ ] **Step 5: Build**

Run:

```bash
swift build
```

Expected: build succeeds. If it fails because `isKanbanDetailOpen` is not present yet, add Task 5's computed properties before retrying.

---

### Task 5: Render Kanban in `GenericItemDetailPanel`

**Files:**
- Modify: `Sources/Cider/Views/CiderPanelView+DetailManagement.swift`
- Modify: `Sources/Cider/Views/CiderPanelView+DetailViews.swift`
- Modify: `Sources/Cider/Views/CiderPanelView.swift`
- Modify: `Sources/Cider/Views/Kanban/KanbanCardDetailView.swift`

- [ ] **Step 1: Add computed properties and close helper**

In `Sources/Cider/Views/CiderPanelView+DetailManagement.swift`, add:

```swift
var selectedKanbanDetail: (board: KanbanBoard, column: KanbanColumn, card: KanbanCard)? {
    guard let selectedKanbanBoardID, let selectedKanbanCardID else { return nil }
    guard let found = KanbanStorage.shared.findCard(id: selectedKanbanCardID) else { return nil }
    guard found.board.id == selectedKanbanBoardID else { return nil }
    return found
}

var isKanbanDetailOpen: Bool {
    selectedKanbanDetail != nil
}

var isKanbanDetailSlideOut: Bool {
    isKanbanDetailOpen
}

func closeKanbanDetail() {
    guard isKanbanDetailOpen else { return }
    selectedKanbanBoardID = nil
    selectedKanbanCardID = nil
    AIAssistantViewModel.shared.clearContext()
    NotificationCenter.default.post(name: .restoreCiderPanelAfterSlideOut, object: nil)
}
```

Update `isAnyDetailOpen`:

```swift
var isAnyDetailOpen: Bool {
    isDetailOpen || isGenericDetailOpen || isNoteDetailOpen || isKanbanDetailOpen
}
```

- [ ] **Step 2: Add overlay in `CiderPanelView`**

In `Sources/Cider/Views/CiderPanelView.swift`, include Kanban in shell blur:

```swift
blurRightColumn: isDetailSlideOut || isGenericDetailSlideOut || isNoteDetailSlideOut || isKanbanDetailSlideOut,
```

Add overlay near the other slide-out overlays:

```swift
if isKanbanDetailSlideOut {
    Color.clear
        .contentShape(Rectangle())
        .onTapGesture { closeKanbanDetail() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

    kanbanDetailSlideOutContainer
        .frame(width: min(detailSlideOutWidth, maxSlideOutWidth))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .padding(BookmarksDesign.detailsSlideOutFloatInset)
        .transition(.move(edge: .trailing).combined(with: .opacity))
}
```

Add animation:

```swift
.animation(reduceMotion ? .none : .snappy, value: isKanbanDetailSlideOut)
```

- [ ] **Step 3: Convert `KanbanCardDetailView` to content-only editor**

Replace the modal chrome in `Sources/Cider/Views/Kanban/KanbanCardDetailView.swift` with this shape:

```swift
import SwiftUI

struct KanbanCardDetailView: View {
    let card: KanbanCard
    let boardID: String
    var onSave: (KanbanCard) -> Void

    @State private var draft: KanbanCardDraft
    @FocusState private var notesFocused: Bool

    init(card: KanbanCard, boardID: String, onSave: @escaping (KanbanCard) -> Void) {
        self.card = card
        self.boardID = boardID
        self.onSave = onSave
        _draft = State(initialValue: KanbanCardDraft(card: card))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            TextField("Card title", text: $draft.title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(CiderFont.subheadingSemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(1...4)
                .onSubmit { save() }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Notes")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)

                TextEditor(text: $draft.notes)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.primary)
                    .scrollContentBackground(.hidden)
                    .focused($notesFocused)
                    .frame(minHeight: 420)
                    .padding(Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .stroke(CiderColors.borderSubtle, lineWidth: CiderBorder.hairlineStrokeWidth)
                    )
            }

            HStack {
                Text("Use this as the source of truth for product/refactor context. Export Markdown only when you need a portable copy.")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(CiderAccentButtonStyle())
            }
        }
        .onChange(of: card.id) { _, _ in
            draft = KanbanCardDraft(card: card)
        }
    }

    private func save() {
        onSave(draft.updatedCard(from: card))
    }
}
```

- [ ] **Step 4: Add Kanban slide-out container**

In `Sources/Cider/Views/CiderPanelView+DetailViews.swift`, add:

```swift
@ViewBuilder
var kanbanDetailSlideOutContainer: some View {
    if let detail = selectedKanbanDetail {
        GenericItemDetailPanel(
            title: detail.card.title,
            detailViewMode: .slideOut,
            width: min(detailSlideOutWidth, maxSlideOutWidth),
            maxWidth: maxSlideOutWidth,
            metadataVisible: $kanbanMetadataVisible,
            onResize: { newWidth in
                detailSlideOutWidth = min(max(BookmarksDesign.detailsSlideOutMinWidth, newWidth), maxSlideOutWidth)
            },
            onFloat: nil,
            onClose: closeKanbanDetail,
            onModeChange: { _ in },
            trailingExtra: { EmptyView() },
            metadata: {
                KanbanCardMetadataInspectorView(
                    board: detail.board,
                    column: detail.column,
                    card: detail.card,
                    onSave: { updated in
                        KanbanStorage.shared.updateCard(boardID: detail.board.id, card: updated)
                    },
                    onMove: { columnID in
                        KanbanStorage.shared.moveCard(
                            boardID: detail.board.id,
                            cardID: detail.card.id,
                            toColumnID: columnID,
                            toIndex: detail.board.columns.first(where: { $0.id == columnID })?.cards.count ?? 0
                        )
                    },
                    onDelete: {
                        KanbanStorage.shared.deleteCard(boardID: detail.board.id, cardID: detail.card.id)
                        closeKanbanDetail()
                    },
                    onExportMarkdown: {
                        exportKanbanCardMarkdown(board: detail.board, column: detail.column, card: detail.card)
                    }
                )
            }
        ) {
            KanbanCardDetailView(
                card: detail.card,
                boardID: detail.board.id,
                onSave: { updated in
                    KanbanStorage.shared.updateCard(boardID: detail.board.id, card: updated)
                    selectedKanbanCardID = updated.id
                }
            )
        }
    }
}
```

- [ ] **Step 5: Build**

Run:

```bash
swift build
```

Expected: build succeeds except for missing `KanbanCardMetadataInspectorView` and `exportKanbanCardMarkdown`, which Task 6 adds.

---

### Task 6: Add Kanban Metadata Rail and Markdown Export Action

**Files:**
- Create: `Sources/Cider/Views/Kanban/KanbanCardMetadataInspectorView.swift`
- Modify: `Sources/Cider/Views/CiderPanelView+DetailManagement.swift`

- [ ] **Step 1: Create metadata inspector**

Create `Sources/Cider/Views/Kanban/KanbanCardMetadataInspectorView.swift`:

```swift
import SwiftUI

struct KanbanCardMetadataInspectorView: View {
    let board: KanbanBoard
    let column: KanbanColumn
    let card: KanbanCard
    var onSave: (KanbanCard) -> Void
    var onMove: (String) -> Void
    var onDelete: () -> Void
    var onExportMarkdown: () -> Void

    @State private var draft: KanbanCardDraft
    @State private var isBoardExpanded = true
    @State private var isPlanningExpanded = true
    @State private var isDatesExpanded = true

    init(
        board: KanbanBoard,
        column: KanbanColumn,
        card: KanbanCard,
        onSave: @escaping (KanbanCard) -> Void,
        onMove: @escaping (String) -> Void,
        onDelete: @escaping () -> Void,
        onExportMarkdown: @escaping () -> Void
    ) {
        self.board = board
        self.column = column
        self.card = card
        self.onSave = onSave
        self.onMove = onMove
        self.onDelete = onDelete
        self.onExportMarkdown = onExportMarkdown
        _draft = State(initialValue: KanbanCardDraft(card: card))
    }

    var body: some View {
        ItemMetadataPanel {
            Text(card.title)
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(3)
                .padding(.bottom, Spacing.md)

            ItemMetadataDivider()

            ItemMetadataSectionView(title: "Board", isExpanded: $isBoardExpanded) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    metadataLine("Board", board.name)
                    Picker("Status", selection: Binding(
                        get: { column.id },
                        set: { onMove($0) }
                    )) {
                        ForEach(board.columns) { column in
                            Text(column.name).tag(column.id)
                        }
                    }
                    .labelsHidden()
                }
            }

            ItemMetadataDivider()

            ItemMetadataSectionView(title: "Planning", isExpanded: $isPlanningExpanded) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Picker("Priority", selection: $draft.priority) {
                        Text("None").tag(KanbanPriority?.none)
                        ForEach(KanbanPriority.allCases, id: \.self) { priority in
                            Text(priority.rawValue.capitalized).tag(Optional(priority))
                        }
                    }
                    .onChange(of: draft.priority) { _, _ in saveDraft() }

                    Picker("Color", selection: $draft.color) {
                        Text("None").tag(KanbanCardColor?.none)
                        ForEach(KanbanCardColor.allCases, id: \.self) { color in
                            Text(color.rawValue.capitalized).tag(Optional(color))
                        }
                    }
                    .onChange(of: draft.color) { _, _ in saveDraft() }

                    TextField("Agent", text: $draft.agent)
                        .textFieldStyle(.plain)
                        .onSubmit { saveDraft() }

                    TextField("Tags, comma-separated", text: $draft.tagsText)
                        .textFieldStyle(.plain)
                        .onSubmit { saveDraft() }
                }
            }

            ItemMetadataDivider()

            ItemMetadataSectionView(title: "Dates", isExpanded: $isDatesExpanded) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    metadataLine("Created", card.created.formatted(date: .abbreviated, time: .omitted))
                    if let completed = card.completed {
                        metadataLine("Completed", completed.formatted(date: .abbreviated, time: .omitted))
                    }
                }
            }
        } footer: {
            VStack(spacing: Spacing.sm) {
                Button {
                    onExportMarkdown()
                } label: {
                    Label("Export Markdown", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(CiderSecondaryButtonStyle())

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete Card", systemImage: "trash")
                }
                .buttonStyle(.plain)
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.destructive)
            }
            .padding(Spacing.md)
        }
        .onChange(of: card.id) { _, _ in
            draft = KanbanCardDraft(card: card)
        }
    }

    private func saveDraft() {
        onSave(draft.updatedCard(from: card))
    }

    private func metadataLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
            Spacer()
            Text(value)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.secondary)
                .lineLimit(2)
        }
    }
}
```

- [ ] **Step 2: Add export helper**

In `Sources/Cider/Views/CiderPanelView+DetailManagement.swift`, add:

```swift
func exportKanbanCardMarkdown(board: KanbanBoard, column: KanbanColumn, card: KanbanCard) {
    let markdown = KanbanCardMarkdownExporter.markdown(
        for: card,
        boardName: board.name,
        columnName: column.name
    )
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("md")

    do {
        try markdown.write(to: tempURL, atomically: true, encoding: .utf8)
        CiderFileExporter.exportFile(
            sourceURL: tempURL,
            suggestedFileName: KanbanCardMarkdownExporter.suggestedFileName(for: card),
            helpText: "Export this Kanban card as a Markdown file."
        )
    } catch {
        print("Kanban Markdown export failed: \(error.localizedDescription)")
    }
}
```

- [ ] **Step 3: Build and focused tests**

Run:

```bash
swift test --filter KanbanCardMarkdownExporterTests
swift build
```

Expected: tests and build pass.

- [ ] **Step 4: Commit UI rail and export action**

```bash
git add Sources/Cider/Views/Kanban/KanbanCardMetadataInspectorView.swift Sources/Cider/Views/CiderPanelView+DetailManagement.swift Sources/Cider/Views/CiderPanelView+DetailViews.swift Sources/Cider/Views/Kanban/KanbanCardDetailView.swift Sources/Cider/Views/CiderPanelView.swift
git commit -m "feat: render kanban cards in shared detail panel"
```

---

### Task 7: Polish Board Card Behavior and Stale Selection

**Files:**
- Modify: `Sources/Cider/Views/Kanban/KanbanBoardView.swift`
- Modify: `Sources/Cider/Views/CiderPanelView.swift`
- Modify: `Sources/Cider/Views/CiderPanelView+DetailManagement.swift`

- [ ] **Step 1: Close detail when selected card disappears**

In `Sources/Cider/Views/CiderPanelView.swift`, add an `onChange` for board/card changes:

```swift
.onChange(of: KanbanStorage.shared.boards) { _, _ in
    guard let selectedKanbanCardID else { return }
    if KanbanStorage.shared.findCard(id: selectedKanbanCardID) == nil {
        closeKanbanDetail()
    }
}
```

If `KanbanBoard` array observation causes compile issues, move this to a `.onReceive(NotificationCenter.default.publisher(for: .kanbanBoardsChanged))` block:

```swift
.onReceive(NotificationCenter.default.publisher(for: .kanbanBoardsChanged)) { _ in
    guard let selectedKanbanCardID else { return }
    if KanbanStorage.shared.findCard(id: selectedKanbanCardID) == nil {
        closeKanbanDetail()
    }
}
```

- [ ] **Step 2: Keep board cards compact**

In `cardView`, keep current preview behavior but make the notes preview clearly bounded:

```swift
if let notes = card.notes, !notes.isEmpty {
    Text(notes)
        .font(CiderFont.caption)
        .foregroundColor(CiderColors.tertiary)
        .lineLimit(3)
}
```

Do not render the full notes on the board.

- [ ] **Step 3: Build**

Run:

```bash
swift build
```

Expected: build passes.

---

### Task 8: Verification

**Files:**
- No new files unless fixing failures.

- [ ] **Step 1: Run focused test suite**

Run:

```bash
swift test --filter KanbanCardDraftTests
swift test --filter KanbanCardMarkdownExporterTests
swift test --filter CiderDetailNavigationPolicyTests
```

Expected: all pass.

- [ ] **Step 2: Run full tests**

Run:

```bash
swift test
```

Expected: pass. If unrelated pre-existing failures appear, record exact failures and confirm the focused Kanban tests pass.

- [ ] **Step 3: Build app**

Run:

```bash
swift build
```

Expected: pass.

- [ ] **Step 4: Manual smoke test**

Launch Cider, open a Kanban saved view, and verify:

- Clicking a Kanban card opens the right-side slide-out, not a centered modal.
- Long notes can be pasted into the notes editor, saved, closed, reopened, and preserved.
- Board card still shows only a compact preview.
- Metadata rail changes priority, color, tags, agent, and column/status.
- Moving into a done column still sets `completed`; moving out clears it.
- Export Markdown opens a save panel and writes a `.md` with metadata and the complete notes body.
- No new Cider note or vault `.md` appears merely from editing/saving the Kanban card.

- [ ] **Step 5: Final commit**

```bash
git add Sources/Cider/Views/Kanban Sources/Cider/Views/CiderPanelView.swift Sources/Cider/Views/CiderPanelView+ContentArea.swift Sources/Cider/Views/CiderPanelView+DetailManagement.swift Sources/Cider/Views/CiderPanelView+DetailViews.swift Tests/CiderTests/KanbanCardDraftTests.swift Tests/CiderTests/KanbanCardMarkdownExporterTests.swift Tests/CiderTests/CiderDetailNavigationPolicyTests.swift
git commit -m "feat: make kanban cards first-class detail items"
```

---

## Self-Review

- Spec coverage: The plan covers shared slide-out routing, long-form notes as the source of truth, compact board cards, metadata rail, explicit Markdown export, stale-selection cleanup, and verification.
- Placeholder scan: No incomplete placeholders remain. Checklist support is explicitly out of scope for this pass.
- Type consistency: `KanbanCardDraft`, `KanbanCardMarkdownExporter`, `openKanbanCardDetail`, `closeKanbanDetail`, and `kanbanDetailSlideOutContainer` are introduced before use or in the same task that requires them.
- Scope check: This is one cohesive subsystem. Hermes-to-Kanban card creation and Codex task pickup are intentionally not included; this plan prepares the card surface those workflows will use.
