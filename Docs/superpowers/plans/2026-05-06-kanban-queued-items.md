# Kanban Queued Items Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Complete the scoped cards currently queued on the Cider board and move them to Testing for manual QA.

**Architecture:** Keep the existing Kanban model and SwiftUI board surface, adding small focused helpers rather than broad view rewrites. Persistence changes go through `KanbanCard`, draft merging, and storage update paths; visual changes stay in `KanbanBoardLayout` and `KanbanBoardView`.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, YAML-backed Kanban board files, existing `SummaryService`/Foundation Models availability checks where generation is needed.

---

### Task 1: Generated Card Preview Summaries (`c2f4a1`)

**Files:**
- Modify: `Sources/Cider/Models/KanbanBoard.swift`
- Modify: `Sources/Cider/Views/Kanban/KanbanCardDraft.swift`
- Modify: `Sources/Cider/Services/KanbanStorage.swift`
- Modify: `Sources/Cider/Views/Kanban/KanbanBoardLayout.swift`
- Modify: `Sources/Cider/Views/Kanban/KanbanBoardView.swift`
- Test: `Tests/CiderTests/KanbanCardCodableTests.swift`
- Test: `Tests/CiderTests/KanbanCardDraftTests.swift`
- Test: `Tests/CiderTests/KanbanCardHierarchyTests.swift`

- [x] Add a stored optional card summary field, preserving legacy decode.
- [x] Add preview-text selection that prefers the stored summary and falls back to current notes excerpt.
- [x] Refresh generated summaries on card creation/update when AI is available; keep fallback useful when AI is unavailable.
- [x] Cap preview body text at 4-5 lines.
- [x] Verify codable, draft, preview fallback, and Kanban test slices.

### Task 2: Next Up Plan Indicator (`dd47ba`)

**Files:**
- Modify: `Sources/Cider/Views/Kanban/KanbanBoardLayout.swift`
- Modify: `Sources/Cider/Views/Kanban/KanbanBoardView.swift`
- Test: `Tests/CiderTests/KanbanCardHierarchyTests.swift`

- [x] Mark the first non-done child in each parent plan as next up.
- [x] Surface the cue in the existing step/context pill without making every card urgent.
- [x] Verify step order still shows absolute plan position.

### Task 3: Card Split Quality Checklist (`7d7a8b`)

**Files:**
- Modify: `AGENTS.md`
- Modify: `Docs/Features/Kanban/PRODUCT.md`
- Modify: `Docs/Features/Kanban/DECISIONS.md`

- [x] Add durable guidance for child/follow-up card quality.
- [x] Include required fields: problem, goal, MVP scope, non-goals, acceptance, parent/source, tags, priority.
- [x] Note that follow-up cards should be created sequentially unless board file locking is available.

### Task 4: Blue/Purple Accent Differentiation (`21b40d`)

**Files:**
- Modify: `Sources/Cider/Utilities/Constants.swift`
- Modify: `Sources/Cider/Views/Kanban/KanbanBoardView.swift`
- Test: `Tests/CiderTests/KanbanBoardLayoutTests.swift`

- [x] Add or adjust Kanban accent tokens so blue and purple are visually distinct.
- [x] Use those tokens for strips, connectors, parent badges, and plan dots.
- [x] Verify priority colors remain separate.

### Task 5: Column Header Quick-Add Popover (`1c26ce`)

**Files:**
- Modify: `Sources/Cider/Services/KanbanStorage.swift`
- Modify: `Sources/Cider/Views/Kanban/KanbanBoardView.swift`
- Test: `Tests/CiderTests/KanbanBoardFileLockingTests.swift`

- [x] Extend `addCard` to accept notes, priority, color, tags, and parent.
- [x] Add a plus button in each column header.
- [x] Build a compact popover with title, notes, priority, color, tags, and optional parent selection.
- [x] Preserve the existing bottom title-only Add card flow.
- [x] Verify metadata persists and parent children appear in hierarchy.

### Final Verification

- [x] Run `swift test --filter Kanban`.
- [x] Run `./script/build_and_run.sh --verify`.
- [x] Move completed scoped cards to Testing with implementation notes and test evidence.
