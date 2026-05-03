# Kanban

**Status:** Active / first-class Cider feature and development workflow  
**Owner surface:** Cider Desktop, CiderVault board YAML, and agent workflows  
**Source of truth:** This folder documents durable Kanban product, architecture, data model, and testing rules. The active work state lives in `/Users/minivish/CiderVault/.cider/boards/*.yaml`.

## What This Feature Does

Kanban gives Cider a visual active-work surface. Boards track product ideas, bugs, implementation plans, review findings, testing queues, and handoff context for Hermes, Codex, Claude, or manual work.

Kanban cards are first-class Cider detail items. A compact card lives on the board, while the shared slide-out detail panel owns long-form notes/spec text, metadata, linked items, and Markdown export.

## Source-Of-Truth Rules

- Board/card status lives in YAML board files under `/Users/minivish/CiderVault/.cider/boards/`.
- Durable product, architecture, UX, data-model, QA, and agent-behavior decisions belong in docs.
- A card may contain long notes and enough context for another agent to continue work.
- Markdown export is explicit and one-way; exporting does not make the `.md` file canonical.
- Important Kanban outcomes should be promoted into the relevant durable doc before the work is considered fully settled.

## Code Map

- `Sources/Cider/Models/KanbanBoard.swift` - board, column, card, priority, color, date encoding, and ID model.
- `Sources/Cider/Services/KanbanStorage.swift` - YAML-backed board persistence, live reload, CRUD, moves, done-column completion behavior, and SavedView tab sync.
- `Sources/Cider/Views/Kanban/KanbanBoardView.swift` - board UI, columns, cards, drag/drop, filters, and card opening.
- `Sources/Cider/Views/Kanban/KanbanCardDetailView.swift` - main slide-out title and long-form notes editor.
- `Sources/Cider/Views/Kanban/KanbanCardMetadataInspectorView.swift` - board/status, planning metadata, linked items, actions, dates, and delete.
- `Sources/Cider/Views/Kanban/KanbanCardDraft.swift` - shared editable draft for title, notes, metadata, tags, and linked entities.
- `Sources/Cider/Views/Kanban/KanbanCardMarkdownExporter.swift` - explicit Markdown export.
- `Sources/CiderCLI/CiderCLI.swift` - `cider-cli board ...` commands for agents and terminal workflows.

## Related Docs

- `Docs/Features/Kanban/PRODUCT.md`
- `Docs/Features/Kanban/ARCHITECTURE.md`
- `Docs/Features/Kanban/DATA_MODEL.md`
- `Docs/Features/Kanban/TESTING.md`
- `Docs/Conventions/DOCS_INFORMATION_ARCHITECTURE.md`
- `Docs/superpowers/plans/2026-05-03-kanban-first-class-detail-panel.md`

