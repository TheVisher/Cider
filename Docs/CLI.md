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

## CLI Quality Bar

When fixing or adding CLI behavior:

- add focused tests where practical
- preserve existing human-readable output unless intentionally changing it
- verify JSON output with a parser
- keep command errors actionable
