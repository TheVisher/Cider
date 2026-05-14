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
- item graph: inspect/search/routing/provenance, Kanban projection backfill, and doctor checks
- spaces: explain routing context and agent instructions
- boards: show, recent, card inspect, add-card, update-card, move-card, children, section update, evidence add, history add
- database: backup list and isolated restore verification

## Item Graph And Spaces

Agents should prefer `cider-cli item ...` and `cider-cli space ...` for second-brain memory work.

Core commands:

- `item search <query> --json`: FTS-backed search over projected chunks.
- `item get <type> <id-or-ref> --json`: structured sections, routing decisions, agent actions, and owner resolution metadata for an owner.
- `item route <type> <id-or-ref> --target-type <space|folder|board> --reason <text> --json`: records a routing decision without silently moving files.
- `item backfill-kanban [--board <name-or-id>] --json`: rebuilds Kanban card projections from YAML into SQLite sections/chunks.
- `item doctor --json`: checks second-brain tables and SQLite integrity.
- `space explain <name-or-id> --json`: returns purpose, routing hints, default views, and agent instructions for a Space.

Kanban card details can be discovered with `board recent <board> --limit <count> --json`, which lists newest card activity with board, column, parent, priority, timestamps, recent edit/move/completion activity kind, and compact current-state/next-step context. Exact cards can be inspected through `board card inspect <board> --card <id> --json`, which returns parsed dashboard lanes, sections, card metadata, hierarchy, links, routing decisions, and agent actions. Card details can be edited through `board section update <board> --card <id> --section <name> --value <text>`, `board evidence add <board> --card <id> --text <text>`, and `board history add <board> --card <id> --type <implementation|failed-attempt|test|decision|handoff> --text <text>`. These update the YAML card and refresh its SQLite projection.

Normal agent workflow for a Cider card:

1. If the active card ID is unknown, run `board recent <board> --limit 20 --json` before broad search or raw YAML inspection.
2. `board card inspect <board> --card <id> --json` to understand state without scraping YAML.
3. `board section update ... --section "Current State" --value "..." --json` before and after implementation when state changes.
4. `board history add ... --type implementation --text "..." --source "..." --json` for concise implementation or fix summaries.
5. `board history add ... --type failed-attempt --text "..." --source "..." --json` when an attempted path matters for future agents.
6. `board evidence add ... --text "..." --source "..." --json` after verification. `board history add ... --type test` writes the same durable test-evidence lane.
7. `board history add ... --type decision --text "..." --source "..." --json` when a durable product, architecture, storage, CLI, QA, or agent-behavior choice is made.
8. `board history add ... --type handoff --text "..." --source "..." --json` before stopping, or use `board section update ... --section "Agent Handoff" --value "..." --json` for a full replacement handoff.

Kanban projection lifecycle:

- Creation: `board add-card`, `board update-card`, `board section update`, `board evidence add`, and `board history add` refresh that card's SQLite projection after writing YAML.
- Refresh: `item backfill-kanban --board <board> --json` rebuilds all card projections for a board from canonical YAML; omit `--board` to refresh every board.
- Deletion: deleting a Kanban card or board removes its projected sections/chunks so `item search` stops finding stale card content.
- Restore/reload: restored or reloaded boards should be followed by `item backfill-kanban --board <board> --json` when an agent needs fresh search immediately.
- Doctor: `item doctor --json` checks schema and table health. Projection drift detection is a follow-up, so suspected stale card projections should currently be repaired with backfill and verified with `item get card <id> --json` plus `item search <query> --json`.

## Scheduled Briefing / Life-Assistant Reporting

Daily agent reports should reduce noise, not turn every dated item into an alarm. This should be solved in Cider's shared CLI/API layer so any agent, dashboard, or scheduled job gets the same answer without prompt-specific workarounds.

- Add or maintain a canonical agenda/briefing query path that returns agent-ready items with resolved relevance/status, not just raw todo/event records.
- The daily brief should focus on items important/relevant today, plus reminders whose configured reminder rule says to surface today.
- Active todos come from non-completed `todo list --json` items only.
- If a completed todo matches a same-cycle date card or event, reports should not keep calling the dated item overdue. Example: completed `Pay rent` suppresses a same-title `Pay Rent` event for that cycle.
- Rent/monthly bills should only appear when the next due date is close, roughly within five days, or when the configured reminder rule says to surface today.
- Birthdays/anniversaries should not appear in every daily report merely because they are future dated. Cider should support reminder policies such as "one week before," "on the day," or "start-of-month birthday digest," and the agenda API should return `surfaceToday`, reason, reminder policy, and next surface date.
- The same reminder should not spam every daily report across its lead window unless explicitly configured as a repeating reminder.
- CLI/date handling should make local-date semantics obvious. Agents observed `event update <id> --date 2026-06-01` producing a `startAt` of `2026-06-02T00:00:00Z`; this needs a regression test or clearer timezone/date normalization.

## Known Agent/CLI Hardening Findings

- 2026-05-09: Running the Cider app while Hermes uses `cider-cli` to capture/route bookmarks can create duplicate bookmarks. Repro observed with Steam/TikTok captures: CLI created and moved the bookmark, then the already-running app adopted the moved `.webloc` as an orphan because its in-memory bookmark list had not reloaded the CLI-created URL/ID. Result: same URL appears twice, often with `(... 2).webloc`, and later UI enrichment/labels apply to the duplicate. Fix direction: cross-process storage invalidation/reload or a URL/relative-path duplicate guard in app-side orphan adoption/sync before minting a new bookmark ID. Agent workaround until fixed: after CLI bookmark capture while Cider.app is running, run duplicate-check/search/get and report/cleanup duplicates rather than assuming one row.
- 2026-05-11: `folder get "Inbox"` is not a reliable Inbox count source. Inbox is a reserved/virtual storage area for item-type subfolders, and current folder lookup may return `No folder found matching 'Inbox'` even while `snapshot --json` reports an Inbox folder count and item lists show `relativePath` values under `Inbox/...`. Agent/scheduled-brief workaround: use `snapshot --json` `folderCounts[name == "Inbox"]` for count, and use item lists filtered by `folder == "Inbox"` or `relativePath` beginning with `Inbox/` for actionable examples. Do not report Inbox as unavailable solely because folder lookup fails.
- 2026-05-11: A dogfood audit found bulk duplicate top-level folders and exact-content duplicated Markdown notes after a Cider app launch around 2026-05-10 10:18 PDT. `status --json` rose from 63 folders to 189; SQLite shows 126 folder rows created in the same short window; examples include `Games`/`Games 2`, `Movies`/`Movies 2`, `TV Shows`/`TV Shows 2`, and duplicated files such as `Games Library 2.md`/`Games Library 3.md`. `folder doctor --json` currently reports no findings, so add doctor coverage for duplicate folder/note drift and investigate folder/sidebar/domain adoption paths before any cleanup. Tracking card: Cider board `d165bc`.
- 2026-05-13 regression: After a prior cleanup/stabilization pass claimed zero active duplicates, the live vault regressed while Cider.app was running. `status --json` showed folders=190, notes=21, bookmarks=248, trash=504; `folder doctor --json` showed 105 warnings; filesystem scan found 37 top-level numeric-suffix dirs and 6 active exact-content Markdown duplicate groups, including `Media/Games/Games Library.md` vs `Media 2/Games/Games Library 2.md` vs `Games/Games Library 2 2.md`, plus the matching Movies/TV Shows library groups. Active duplicate bookmark URL groups also reappeared (7 groups), including Stonewards Steam where one copy had a Steam/page screenshot style thumbnail/title and another had the real game metadata. Treat this as an active recurrence, not stale solved cleanup debt. Update cards `d165bc` and `3281a2`; fix source before or alongside cleanup, then verify with status, doctor, numeric-suffix folder scan, exact-note hash scan, and duplicate URL scan after app launch/sync.

## CLI Quality Bar

When fixing or adding CLI behavior:

- add focused tests where practical
- preserve existing human-readable output unless intentionally changing it
- verify JSON output with a parser
- keep command errors actionable
