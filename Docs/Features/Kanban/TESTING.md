# Kanban Testing

## Automated Coverage

Focused tests:

- `KanbanCardDraftTests` - shared draft preservation and normalization.
- `KanbanCardMarkdownExporterTests` - Markdown export uses card/draft content and safe filenames.
- `KanbanCardCodableTests` - card YAML/JSON compatibility and linked entity decoding.
- `CiderDetailNavigationPolicyTests` - Kanban participates in the one-detail-at-a-time panel policy.

Run:

```bash
swift test --filter KanbanCardDraftTests
swift test --filter KanbanCardMarkdownExporterTests
swift test --filter KanbanCardCodableTests
swift test --filter CiderDetailNavigationPolicyTests
```

## Board Validation

After touching board YAML, run:

```bash
/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli board list --json
/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli board show "Cider Roadmap" --json
```

Use `board show` for every board changed during the audit.

## Manual Regression Areas

- Card click opens the slide-out detail panel.
- Long notes remain editable and readable without creating a separate Markdown note.
- Main notes/title edits and metadata edits share one draft.
- Priority/color/agent/tags changes do not overwrite title or notes.
- Status moves preserve notes and apply completed-date behavior.
- Export Markdown includes current unsaved draft text.
- Delete clears selected Kanban detail state.
- Linked items persist on the card.
- Escape closes the detail panel without losing saved work.
- Board YAML edits reload in the app without restart.

