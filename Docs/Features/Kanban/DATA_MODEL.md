# Kanban Data Model

## Board File

Each board is stored as one YAML file:

```yaml
id: a1b2c3
board: Cider Roadmap
created: '2026-03-20'
columns:
  - id: backlog
    name: Backlog
    cards: []
```

Dates should be quoted as `YYYY-MM-DD` when edited manually.

## KanbanBoard

Implemented in `Sources/Cider/Models/KanbanBoard.swift`.

Fields:

- `id`
- `name`, encoded as `board`
- `created`
- `columns`

## KanbanColumn

Fields:

- `id`
- `name`
- `isDoneColumn`, encoded as `is_done_column`
- `cards`

Done columns control completion semantics. Moving a card into a done column sets `completed`; moving it out clears `completed`.

## KanbanCard

Fields:

- `id`
- `title`
- `notes`
- `color`
- `priority`
- `agent`
- `tags`
- `linkedEntities`
- `parentCardID`
- `created`
- `completed`

`notes` is the canonical long-form body for the card. It may contain product briefs, refactor notes, acceptance criteria, testing notes, and handoff context.

`parentCardID` links scoped implementation cards back to a larger parent card. Child cards may also have children, so the model can represent follow-up bugs or sub-slices discovered while implementing a scoped card. The board should keep visual nesting readable, while the detail panel shows the full card lineage.

## Draft

`KanbanCardDraft` is the editable detail-panel state for a card.

It owns:

- `title`
- `notes`
- `color`
- `priority`
- `agent`
- `tagsText`
- `linkedEntities`

Both the main editor and metadata rail bind to this draft so a save cannot overwrite another section with stale state.

## YAML Rules

- Every board and card must have a valid `created` date.
- Quote dates with single quotes when editing manually.
- Do not duplicate keys.
- Preserve indentation.
- Prefer CLI commands or structured YAML parsing when available.
- If manual edits are necessary, rewrite the whole board carefully instead of tiny indentation-sensitive patches.

