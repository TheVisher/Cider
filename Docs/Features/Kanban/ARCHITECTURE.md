# Kanban Architecture

## Storage

Kanban boards are YAML files under:

```text
/Users/minivish/CiderVault/.cider/boards/
```

`KanbanStorage` loads all `.yaml` files, decodes them with Yams, publishes boards to SwiftUI, saves mutations atomically, and watches the board directory for external changes. The app and agents share this same surface.

## App Integration

`KanbanStorage.syncTabsWithBoards()` creates SavedView tab entries for boards that do not yet have tabs. This lets Kanban participate in the main Cider workspace rather than living in a separate manager.

`KanbanBoardView` renders the board and calls into the shared detail-navigation layer when a card is selected.

`CiderPanelView` owns selected Kanban board/card state:

- `selectedKanbanBoardID`
- `selectedKanbanCardID`
- `kanbanCardDraft`

The selected card is rendered inside `GenericItemDetailPanel`, matching the shared slide-out pattern used by other Cider cards.

## Detail Draft Flow

Kanban detail editing uses one shared `KanbanCardDraft` owned by the slide-out/detail container.

- The main title/notes editor binds to the draft.
- The metadata inspector binds to the same draft.
- Save writes the draft back through `KanbanStorage.updateCard`.
- Status moves save the current draft before moving the card.
- Delete clears selected Kanban state after removal.
- Markdown export uses the current draft, not stale storage.

This avoids stale overwrites between title/notes and metadata edits.

## Agent Coordination

Kanban board YAML is shared state. During multi-agent work:

- read-only agents may inspect boards and propose dispositions;
- only one coordinator should mutate `/Users/minivish/CiderVault/.cider/boards/*.yaml`;
- touched boards should be verified with `cider-cli board show <board> --json`, not only `board list`;
- overlap with done/fixed cards is a review signal, not automatic closure proof.

On project boards, agents should treat `Queued` as the selected work stack. A durable automation loop can safely work through queued cards by moving one item at a time into `In Progress`, writing implementation notes and test evidence, moving the card to `Testing`, and then returning to `Queued` for the next item. Parent cards may summarize the plan while child cards carry scoped implementation work.

## CLI

Agents should prefer CLI commands when available:

```bash
/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli board list --json
/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli board show "Cider Roadmap" --json
/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli board add-card "Cider Roadmap" --column Backlog --title "Idea"
/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli board update-card "Cider Roadmap" --card abc123 --notes "..."
/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli board move-card "Cider Roadmap" --card abc123 --to Done
```
