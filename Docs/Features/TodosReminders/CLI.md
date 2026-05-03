# Todos And Reminders CLI

Use the repo-built CLI:

```bash
/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli
```

## Todos

Common commands:

```bash
cider-cli todo create "Fix the bug" --due 2026-05-04 --priority high
cider-cli todo list --json
cider-cli todo update <id> --title "New title" --details "More context"
cider-cli todo complete <id>
cider-cli todo checklist list <todo-id>
cider-cli todo checklist add <todo-id> --title "Step"
cider-cli todo checklist toggle <todo-id> --item <item-id>
```

## Events / Date Cards

Common commands:

```bash
cider-cli event create "Dentist" --date 2026-05-04
cider-cli event update <id> --title "Updated Event" --date 2026-05-05 --location "123 Main St"
cider-cli event export <id> --to /tmp/event.ics
```

## Agent Rule

Prefer CLI commands for creating or updating todos/events. Do not write raw vault files when the CLI can perform the mutation through Cider's storage layer.

