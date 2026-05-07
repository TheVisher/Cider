# Cider CLI

Status: canonical core doc.

`cider-cli` is the shell and agent interface for Cider. It should be scriptable, conservative, and clear.

## Principles

- `--json` means strict JSON on stdout with no human-readable framing.
- Human-readable output is for non-JSON mode.
- Commands that mutate user data should report what changed.
- Agents should prefer CLI or app services over direct filesystem mutation.
- Destructive operations should use Cider safety flows.

## Common Agent Workflows

Use CLI commands for:

- duplicate checks before bookmark capture
- bookmark creation and enrichment
- vault search and item lookup
- current vault totals and status checks
- Kanban card creation and movement
- board inspection
- database backup inspection
- focused regression checks

## Kanban

Kanban boards live in `~/CiderVault/.cider/boards/`.

Prefer supported `cider-cli board ...` commands where available. If a command lacks a needed operation, use structured YAML parsing or a careful whole-file rewrite.

Every card must include `created: 'YYYY-MM-DD'`.

## Bookmark Capture

The expected capture loop is:

1. Duplicate check.
2. Save to an obvious folder or conservative Inbox staging folder.
3. Enrich metadata.
4. Re-read.
5. Route if confidence is high.
6. Re-read and report verified final state.

## Important Command Areas

Keep command details in CLI help and tests, not sprawling docs. The core command areas agents rely on are:

- bookmarks: add, get, list/search, move, tag/update, enrich, duplicate-check
- notes: create, list, update
- todos/events/contacts/files: create, list, update where supported
- links: related/backlink operations where available
- dashboard: topic/card list and upsert with JSON
- boards: show, add-card, update-card, move-card, children
- database: backup list and isolated restore verification

## CLI Quality Bar

When fixing or adding CLI behavior:

- add focused tests where practical
- preserve existing human-readable output unless intentionally changing it
- verify JSON output with a parser
- keep command errors actionable
