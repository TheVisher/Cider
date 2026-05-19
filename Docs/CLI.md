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

- Cider-owned capture, routing, review, and recall
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

- bookmarks: add, get, list/search, move, tag/update, enrich, duplicate-check, date-suggestions, date-suggestions approve
- notes: create, list, update
- todos/events/contacts/files: create, list, update where supported
- links: related/backlink operations where available
- dashboard: topic/card list and upsert with JSON
- item graph: inspect/search/routing/provenance, Kanban projection backfill, and doctor checks
- spaces: explain routing context and agent instructions
- boards: show, recent, testing-summary, card inspect, add-card, update-card, move-card, children, section update, evidence add, history add
- database: backup list and isolated restore verification

## Item Graph And Spaces

Agents should prefer `cider-cli item ...` and `cider-cli space ...` for second-brain memory work.

Core commands:

- `item search <query> --json`: FTS-backed search over projected chunks.
- `item get <type> <id-or-ref> --json`: unified item context for library item refs such as bookmark, note, todo, dateCard/event, contact, and vaultFile.
- `item owner-get <owner-type> <owner-id-or-ref> --json`: legacy owner-section inspection for projected owners such as Kanban cards; returns structured sections, routing decisions, agent actions, and owner resolution metadata.
- `item route <type> <id-or-ref> --target-type <space|folder|board> --reason <text> --json`: records a routing decision without silently moving files.
- `item backfill-kanban [--board <name-or-id>] --json`: rebuilds Kanban card projections from YAML into SQLite sections/chunks.
- `item doctor --json`: checks second-brain tables and SQLite integrity.
- `space explain <name-or-id> --json`: returns purpose, routing hints, default views, and agent instructions for a Space.

`item get` still accepts legacy non-library owner refs as a deprecated compatibility fallback and marks JSON with `command: item.get.legacy-owner-fallback`, `deprecated: true`, and a `deprecationMessage`. New callers should use `item owner-get` for owner projections and `item context`/`item get` for unified library items.

The second-brain command surface should support the product loop: capture -> enrich -> route -> review -> resurface/act. JSON output should make uncertainty, provenance, and next safe action visible.

Legacy bookmark creation is a compatibility surface over the unified capture backend. `bookmark add --json` preserves bookmark fields and includes `command: bookmark.add`, `backendCommand: capture.add`, and a nested `capture` result so agents can see the capture/routing/review contract without switching commands mid-workflow.

Legacy bookmark batch enrichment remains available as `bookmark enrich --all --confirm`, but agents should prefer `review enrich-batch --confirm` so enrichment work is review-backed and records batch history.

Kanban card details can be discovered with `board recent <board> --limit <count> --json`, which lists newest card activity with board, column, parent, priority, timestamps, recent edit/move/completion activity kind, and compact current-state/next-step context. `board workflow <board> --json` groups workflow lanes and exposes approval-aware `automationActions` with safe inspection, history, move, and review-routing commands; these actions are guidance, not an agent scheduler. Testing gates can be triaged with `board testing-summary <board> --json`, which groups cards in Testing/Ready to Test columns into `needsErik` and `agentCanVerify` queues. Parent plan status can be inspected with `board parent-summary <board> --card <id> --json`; `--refresh --dry-run` returns proposed Current State / Next Step text and stale-parent findings, while `--refresh --confirm` applies those sections explicitly. Exact cards can be inspected through `board card inspect <board> --card <id> --json`, which returns parsed dashboard lanes, sections, card metadata, hierarchy, roadmap `roadmapNextUp` sequence/groups, links, routing decisions, and agent actions. Card details can be edited through `board section update <board> --card <id> --section <name> --value <text>`, `board evidence add <board> --card <id> --text <text>`, and `board history add <board> --card <id> --type <implementation|failed-attempt|test|decision|handoff|commit> --text <text>`. `board add-card <board> --column <col> --title <title> --parent <card-id> --after <sibling-id>` inserts a roadmap child immediately after an existing sibling in the same column. These update the YAML card and refresh its SQLite projection.

Normal agent workflow for a Cider card:

1. If the active card ID is unknown, run `board recent <board> --limit 20 --json` before broad search or raw YAML inspection.
2. Run `board workflow <board> --json` when choosing the next agent-safe action or review route for Queued/In Progress/Testing/Needs Fix cards.
3. `board card inspect <board> --card <id> --json` to understand state without scraping YAML.
4. `board section update ... --section "Current State" --value "..." --json` before and after implementation when state changes.
5. `board history add ... --type implementation --text "..." --source "..." --json` for concise implementation or fix summaries.
6. `board history add ... --type failed-attempt --text "..." --source "..." --json` when an attempted path matters for future agents.
7. `board evidence add ... --text "..." --source "..." --json` after verification. `board history add ... --type test` writes the same durable test-evidence lane.
8. `board history add ... --type decision --text "..." --source "..." --json` when a durable product, architecture, storage, CLI, QA, or agent-behavior choice is made.
9. `board history add ... --type commit --text "<sha> <branch/files/tests summary>" --source "git" --json` when repo changes are available for regression traceability.
10. `board history add ... --type handoff --text "..." --source "..." --json` before stopping, or use `board section update ... --section "Agent Handoff" --value "..." --json` for a full replacement handoff.

Kanban projection lifecycle:

- Creation: `board add-card`, `board update-card`, `board section update`, `board evidence add`, and `board history add` refresh that card's SQLite projection after writing YAML.
- Refresh: `item backfill-kanban --board <board> --json` rebuilds all card projections for a board from canonical YAML; omit `--board` to refresh every board.
- Deletion: deleting a Kanban card or board removes its projected sections/chunks so `item search` stops finding stale card content.
- Restore/reload: restored or reloaded boards should be followed by `item backfill-kanban --board <board> --json` when an agent needs fresh search immediately.
- Doctor: `item doctor --json` checks schema and table health. Projection drift detection is a follow-up, so suspected stale card projections should currently be repaired with backfill and verified with `item owner-get card <id> --json` plus `item search <query> --json`.

## Agenda And Life-Assistant Reporting

Agent reports should reduce noise, not turn every dated item into an alarm. This belongs in Cider's shared CLI/API layer so Dashboard, agents, and scheduled jobs get the same relevance answer without prompt-specific workarounds.

- Add or maintain a canonical agenda/briefing query path that returns agent-ready items with resolved relevance/status, not just raw todo/event records.
- The daily brief should focus on items important/relevant today, plus reminders whose configured reminder rule says to surface today.
- Active todos come from non-completed `todo list --json` items only.
- If a completed todo matches a same-cycle date card or event, reports should not keep calling the dated item overdue. Example: completed `Pay rent` suppresses a same-title `Pay Rent` event for that cycle.
- Rent/monthly bills should only appear when the next due date is close, roughly within five days, or when the configured reminder rule says to surface today.
- Birthdays/anniversaries should not appear in every daily report merely because they are future dated. Cider should support reminder policies such as "one week before," "on the day," or "start-of-month birthday digest," and the agenda API should return `surfaceToday`, reason, reminder policy, and next surface date.
- The same reminder should not spam every daily report across its lead window unless explicitly configured as a repeating reminder.
## Current Hardening Cautions

Historical CLI and storage bug detail belongs on Kanban cards, not in this core doc. Durable cautions for agents:

- After CLI capture while Cider.app is running, verify the final item with duplicate/search/get commands instead of assuming a single row exists.
- Inbox can be virtual or type-scoped. Prefer item lists, snapshot/status JSON, or review queue commands over raw folder lookup when reporting Inbox health.
- Duplicate folder/note/bookmark regressions should be audited against the current second-brain backend before cleanup. Use the current roadmap/bug cards for exact evidence and acceptance criteria.
- CLI/date handling must preserve local-date semantics for all-day events, birthdays, due dates, and Kanban `created` dates.

## CLI Quality Bar

When fixing or adding CLI behavior:

- add focused tests where practical
- preserve existing human-readable output unless intentionally changing it
- verify JSON output with a parser
- keep command errors actionable
