# Kanban Board — Vision

## Concept

A file-backed Kanban board in Cider where both the user and AI agents can read and write to the same board. The visual lives in Cider, the data lives on disk as a YAML file in the vault.

Two surfaces, two purposes:
1. **Projects tab** — standalone Kanban boards with typed-in cards. For planning, project tracking, and agent workflows. Cards are their own thing — not bookmarks or notes.
2. **Folder Kanban view** (phase 2) — any folder can toggle to a Kanban view. Existing items in the folder (bookmarks, notes, todos, etc.) become the cards. For organizing existing content through stages.

## How it works

**User → Cider UI:**
- Drag a card from Todo → In Progress
- Cider writes that change to the YAML file on disk

**Agent → YAML file:**
- Agent reads the YAML, sees what's In Progress
- Builds the feature
- Moves the card to Testing
- Cider reflects it instantly

## Projects Tab (Phase 1)

Standalone boards that live in the Projects tab. Cards are simple — a title, optional notes, optional color/priority. You type in items, drag them between columns. No connection to bookmarks, notes, or todos.

**Use cases:**
- "Cider Roadmap" — plan features through backlog → in progress → done
- "Apartment Hunting" — track places through found → toured → applied → rejected/accepted
- "Recipe Ideas" — save ideas through want to try → tried → loved it / meh
- Agent task boards — agent picks up cards, moves them through stages

**Cards are NOT todos.** Todos are personal reminders that live as cards in the library. Kanban cards are project tracking items. They look similar but serve different purposes. A bridge between them (send todo to kanban, create todo from card) can be added later if needed — not designed upfront.

## Folder Kanban View (Phase 2)

Any folder can switch to Kanban view. The bookmarks, notes, todos, and other items already in the folder become the cards. You drag them between columns. The column assignment is stored as metadata on the item (or in the folder's YAML).

**Use cases:**
- Restaurant folder: bookmarks for places → columns: want to try, tried, loved, didn't like
- Reading list folder: bookmarks → to read, reading, finished
- Project research folder: notes + bookmarks → gathering, reviewing, referenced

## File format: YAML

YAML hits the sweet spot:
- Human readable — power users can edit directly
- Structured enough to render a proper visual Kanban
- AI can easily read and update — "move X to done" is trivial
- Git diffs are clean and meaningful
- Extends easily — add priority, tags, notes per card without breaking anything

Each board is one `.yaml` file in the vault under `.cider/boards/`.

## Data Model

```yaml
board: Cider Roadmap
created: 2026-03-20
columns:
  - name: Backlog
    id: backlog
    cards:
      - id: abc123
        title: Bulk Operations
        notes: Multi-select mode + bulk actions bar
        color: blue
        created: 2026-03-20

  - name: In Progress
    id: in_progress
    cards:
      - id: def456
        title: Search result highlighting
        notes: ""
        agent: web-agent
        created: 2026-03-18

  - name: Testing
    id: testing
    cards:
      - id: ghi789
        title: Share Extension fixes
        created: 2026-03-15

  - name: Done
    id: done
    cards:
      - id: jkl012
        title: Tag management
        completed: 2026-03-17
        created: 2026-03-10
```

### Card fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | String | Yes | Short unique ID (auto-generated) |
| title | String | Yes | Card title |
| notes | String | No | Freeform notes/description |
| color | String | No | Card color accent (blue, green, orange, red, purple) |
| agent | String | No | Assigned AI agent name |
| created | Date | Yes | When the card was created |
| completed | Date | No | When moved to a "done" column |
| priority | String | No | low, medium, high |
| tags | [String] | No | Optional tags for filtering |

### Column fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| name | String | Yes | Display name |
| id | String | Yes | Slug identifier (used in YAML keys) |
| cards | [Card] | Yes | Ordered list of cards in this column |

## Agent rules

Agents could have a rule: "before starting work, read kanban.yaml and only work on cards assigned to you in in_progress. When done, move your card to testing."

Combined with a daily briefing, the agent wakes up, reads the Kanban, knows exactly what to do, and documents its own progress.

## Why this matters

- No Jira, no Notion, no Linear — just a YAML file and Cider
- Self-updating project board that both user and agents read/write simultaneously
- Fits Cider's open file format philosophy perfectly
- Columns are fully customizable (user creates whatever columns they want)
- Syncs across devices via the vault (same as bookmarks/notes)

## Implementation Plan

### Phase 1: Projects Tab (standalone boards)
1. **Data model** — KanbanBoard, KanbanColumn, KanbanCard structs + YAML parsing
2. **Storage service** — read/write/watch YAML files in `.cider/boards/`
3. **ViewModel** — board state, card CRUD, drag-and-drop column moves
4. **Board list view** — shows all boards, create new, delete
5. **Board view** — horizontal scrolling columns with cards, drag-and-drop
6. **Card detail** — edit title, notes, color, priority inline or in popover

### Phase 2: Folder Kanban View
7. **Folder view mode toggle** — switch between list/grid/kanban
8. **Column assignment** — store which column each item belongs to
9. **Mixed item cards** — render bookmarks, notes, todos as kanban cards with type indicators

## Status

Planning complete. Ready for Phase 1 implementation.
