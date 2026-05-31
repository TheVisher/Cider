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
- exact agent capture through `capture add`
- vault search and item lookup
- current vault totals and status checks
- Kanban card creation and movement
- board inspection
- database backup inspection
- focused regression checks

## Kanban

Kanban boards live in `~/CiderVault/.cider/boards/`.

Use supported `cider-cli board ...` commands for routine card creation, movement, milestone assignment, section updates, evidence, history, handoffs, and commit traceability. If a command lacks a needed routine operation, create a scoped follow-up to add the missing CLI command instead of normalizing direct YAML patching.

Raw board YAML edits are only for parser/storage debugging or emergency repair. Any direct board-file write must use structured parsing or a careful whole-file rewrite, then validate the board file and refresh projections when relevant.

Every card must include `created: 'YYYY-MM-DD'`.

## Second Brain v1 Agent CLI Surface

`cider-cli capture add` is the canonical agent capture API. Agents should use it for new notes, todos, bookmarks, files, events, and contacts, and should include `--json` for verification.

Core capture flags:

- `--kind note|todo|bookmark|file|event|contact` selects the item kind explicitly. Do not rely on inference when the kind is known.
- `--stdin` reads exact raw source text from standard input.
- `--text-file <path>` reads exact raw source text from a file.
- `--url <url>` is the explicit bookmark source.
- `--path <source-file-path>` is the explicit file source for `capture add`.
- `--folder <target-folder-path>` is the destination folder selector for `capture add`; examples include `Inbox/Notes`, `Inbox/Bookmarks`, and project or topic folders.
- `--json` is required for agent verification.

Folder/path rules:

- Source paths are local filesystem inputs. In `capture add`, `--path` always means source file, never destination.
- Target folders are vault-relative destination folders. Use `--folder "Inbox/Notes"` when capturing a note directly to the Notes inbox.
- Target paths in `item move`, `review correct`, and `route correct` are folder paths. `--path "Projects/Cider/Notes"` means move or route into that folder.
- Vault artifact paths include filenames such as `Inbox/Bookmarks/Example.webloc` or `Projects/Cider/Notes/Plan.md`. Do not pass artifact filenames to `item move --path`; pass the containing folder with `--folder Inbox/Bookmarks` or `--path Inbox/Bookmarks`.

Canonical examples:

```bash
printf '%s' "$RAW_NOTE" | cider-cli capture add --kind note --stdin --json
cider-cli capture add --kind note --folder "Inbox/Notes" "Quick note" --json
printf '%s' "$RAW_TODO" | cider-cli capture add --kind todo --stdin --json
cider-cli capture add --kind bookmark --url "https://example.com?a=1&b=two" --json
cider-cli capture add --kind file --path "/path/with spaces.txt" --json
printf '%s' "$RAW_EVENT_DETAILS" | cider-cli capture add --kind event --title "Passport appointment" --date 2026-05-20 --time "10:30 AM" --location "City Hall" --stdin --json
printf '%s' "$RAW_CONTACT_NOTES" | cider-cli capture add --kind contact --name "Avery Example" --email avery@example.com --phone "555-0100" --stdin --json
```

The capture JSON contract reports `command: capture.add`, source text/source metadata, item identity when available, routing/review state, provenance/indexing status, `nextSafeAction`, and `safeNextCommands`.

Hidden or removed legacy commands return `legacyRemoved: true` with a canonical replacement. Legacy type-specific commands such as `bookmark`, `note`, `todo`, `event`, `contact`, `file`, `folder`, `tag`, `label`, `dashboard`, `media`, `recall`, and top-level `search/query/recent/status/snapshot` are not part of the visible agent API.

`bookmark add`, `note create`, `todo create`, and `file import` are temporary compatibility wrappers. They should remain hidden from top-level help, call the capture backend, and return `compatibilityWrapper: true`, `backendCommand: capture.add`, and nested `capture.command: capture.add`.

`note daily append --kind journal|food-log [--date YYYY-MM-DD] [--time HH:mm] (--stdin|--text-file <path>|--content <text>) --json` is the blessed same-day append path for running journals and food logs. It must upsert one note per kind/day, preserve source context in JSON and mutation audit metadata, write through Cider storage, and return `safeNextCommands` for `item get` / `item context` verification.

After capture, agents should verify and continue through backend-backed item/review commands: `item get`, `item search`, `item context`, `item relations`, `item backlinks`, `item move`, `item route`, `item link`, `review list`, `review approve`, `review correct`, `review enrich`, and `storage audit`.

`bookmark enrich <id> [--timeout <seconds>|--no-wait] --json` is the explicit bookmark metadata refetch path. It is allowed for a single bookmark ID only; legacy batch enrichment remains removed in favor of `review enrich-batch --confirm --json`. JSON output must report `command: bookmark.enrich`, `status: completed|timed_out|scheduled`, before/after bookmark snapshots, changed metadata fields, wait timing when applicable, and safe follow-up commands. This lets agents tell the difference between a completed no-op, a still-pending WebView/native enrichment, and a blocked/partial metadata capture such as X/Twitter pages.

## Important Command Areas

Keep command details in CLI help and tests, not sprawling docs. The core command areas agents rely on are:

- capture: `capture add --kind ... --json` for all new user material
- item: get/search/query/recent/context/relations/backlinks/graph-health/project-context/doctor, plus backend-backed move/unfile/route/link
- review: list/summary/drilldown/approve/correct/defer/enrich/enrich-batch/jobs
- storage: audit/doctor-plan/doctor-apply/repair-schema
- route/routing: temporary routing aliases until consolidated
- migrate, doctor, and db integrity
- spaces: explain routing context and agent instructions
- boards: list, show, workflow, recent, testing-summary, parent-summary, children, card inspect, add-card, update-card, move-card, delete-card, section update, evidence add, history add
- database: backup list and isolated restore verification

## Item Graph And Spaces

Agents should prefer `cider-cli item ...` and `cider-cli space ...` for second-brain memory work.

Core commands:

- `item search <query> --json`: FTS-backed search over projected chunks.
- `item get <type> <id-or-ref> --json`: unified item context for library item refs such as bookmark, note, todo, dateCard/event, contact, and vaultFile, including `captureProvenance` when a capture event produced the item.
- `item owner-get <owner-type> <owner-id-or-ref> --json`: legacy owner-section inspection for projected owners such as Kanban cards; returns structured sections, routing decisions, agent actions, and owner resolution metadata.
- `item open <type> <id-or-ref> --json`: read-only UI bridge for surfacing a resolved library item, Kanban card, or board in the running Cider app. It posts `cider.externalOpenRequest` through `DistributedNotificationCenter`; JSON confirms the notification was posted, not that a human saw the target.
- `item graph-health --json`: read-only graph readiness across owner relations, projects, capture events/attachments, content chunks, enrichment outputs, similarity candidates, schema state, counts, findings, string `suggestedCommands`, and structured `suggestedActions` / per-component `safeNextActions` with `readOnly`, `requiresApproval`, and `mutationReason` metadata.
- `item project-context <project> --json`: project graph context with project owner, board/card/doc/artifact relations, backend project metadata, and safe follow-up commands. This is read-only; JSON reports `readOnly: true` and `changed: false`.
- `item sync-project <project> --json`: explicit project workspace sync/seed path for backend project metadata and Kanban owner relations. This can mutate state; JSON reports `readOnly: false`, `changed`, and `mutationReason`.
- `item route <type> <id-or-ref> --target-type <space|folder|board> --reason <text> --json`: records a routing decision without silently moving files.
- `item route ... --target-type space` records native Space membership and creates a `belongs_to_space` owner relation so item context and graph inspection can see the Space assignment.
- `item move <type> <id-or-ref> --path <target-folder-path> --json`: moves an item into a folder path. The path must be a folder, not a `.webloc`, `.md`, `.ics`, `.vcf`, or other artifact filename.
- `item backfill-kanban [--board <name-or-id>] --json`: rebuilds Kanban card projections from YAML into SQLite sections/chunks.
- `item dogfood-intelligence [--limit <n>] --json`: bounded mutation that rebuilds reviewable enrichment outputs and similarity candidates from existing content chunks. Generated rows remain `suggested`; accepting similarity candidates is a separate explicit command.
- `item doctor --json`: checks second-brain tables and SQLite integrity.
- `space explain <name-or-id> --json`: returns purpose, routing hints, default views, and agent instructions for a Space.
- `space list --json` and `space explain <name-or-id> --json` expose an `authority` object so agents can distinguish Space metadata, semantic membership, and storage fallback. `authority.pathContainmentIsSemantic: false` means root paths are not proof of membership.
- `media identify --dry-run --json`: read-only media identification preview. JSON reports `command: media.identify`, `readOnly: true`, `changed: false`, candidate counts, review items, and safe review actions.
- `media identify --apply --json`: mutating media identification apply path. JSON reports `command: media.identify`, `readOnly: false`, `changed`, `mutationReason`, write counts, and `actionRecords` for recorded media provenance.

Graph-heavy commands should expose counts and safe follow-up commands. Prefer bounded summaries or explicit full-detail flags when relation-heavy responses, such as project card lists, would otherwise flood agent context.

`item get` still accepts legacy non-library owner refs as a deprecated compatibility fallback and marks JSON with `command: item.get.legacy-owner-fallback`, `deprecated: true`, and a `deprecationMessage`. New callers should use `item owner-get` for owner projections and `item context`/`item get` for unified library items.

The second-brain command surface should support the product loop: capture -> enrich -> route -> review -> resurface/act. JSON output should make uncertainty, provenance, and next safe action visible.

Review queue JSON includes `reasonCodes` for trust-boundary states such as `routing_low_confidence`, `enrichment_failed`, `inbox_unrouted`, and duplicate-specific codes so agents do not need to parse prose reasons.

Media identification is a bridge command over file-backed MediaItem metadata. `media identify --dry-run --json` reports `readOnly: true` and `changed: false`; `media identify --apply --json` reports `readOnly: false` and must include a mutation reason when applying proposed YAML writes. `reviewLane.safeActions` must include only read-only commands; mutating follow-ups belong in `reviewLane.actions` with `readOnly: false` and `requiresApproval: true`.

Database admin commands with `--json` use explicit envelopes. `db integrity`, `db backups`, and `db audit` report `readOnly: true` and `changed: false`; `db backup` reports the created backup and verification details with `readOnly: false`. `db restore <selector> --dry-run --json` is the agent-safe inspection path and reports the selected backup, required `--yes` confirmation, active-app blockers, planned pre-restore snapshot, rollback guidance, and safe follow-up commands. Confirmed restore can still refuse with structured JSON when Cider.app is running.

Kanban read commands with `--json`, including `board list`, `board show`, `board workflow`, `board recent`, `board testing-summary`, `board parent-summary`, `board children`, and `board card inspect`, use a stable read envelope with `ok`, `command`, `readOnly: true`, `changed: false`, board/card identity where applicable, and `safeVerificationCommands`. Command-specific bodies remain nested, such as `boardDetail`, `workflow`, `testingSummary`, and `parentSummary`, so agents do not need raw YAML or prose scraping.

Kanban card details can be discovered with `board recent <board> --limit <count> --json`, which lists newest card activity with board, column, parent, priority, timestamps, recent edit/move/completion activity kind, and compact current-state/next-step context. `board workflow <board> --json` groups workflow lanes and exposes approval-aware `automationActions` with safe inspection, history, move, and review-routing commands; these actions are guidance, not an agent scheduler. Testing gates can be triaged with `board testing-summary <board> --json`, which groups cards in Testing/Ready to Test columns into `needsErik` and `agentCanVerify` queues. Parent plan status can be inspected with `board parent-summary <board> --card <id> --json`; `--refresh --dry-run` returns proposed Current State / Next Step text and stale-parent findings, while `--refresh --confirm` applies those sections explicitly. Milestones are card-backed project checkpoints managed through `board milestone create <board> --title <title> --description <text> --json`, `board milestone list <board> --json`, `board milestone inspect <board> --milestone <id> --json`, and `board milestone attach-card <board> --milestone <id> --card <id> --json`; attach validates the relationship and records the milestone move on the card. Exact cards can be inspected through `board card inspect <board> --card <id> --json`, which returns parsed dashboard lanes, sections, card metadata, hierarchy, roadmap `roadmapNextUp` sequence/groups, links, routing decisions, and agent actions. Card details can be edited through `board section update <board> --card <id> --section <name> --value <text>`, `board evidence add <board> --card <id> --text <text>`, and `board history add <board> --card <id> --type <implementation|failed-attempt|test|decision|handoff|commit> --text <text>`. `board add-card <board> --column <col> --title <title> --parent <card-id> --after <sibling-id>` inserts a roadmap child immediately after an existing sibling in the same column. These update the YAML card and refresh its SQLite projection.

Normal agent workflow for a Cider card:

1. If the active card ID is unknown, run `board recent <board> --limit 20 --json` before broad search or raw YAML inspection.
2. Run `board workflow <board> --json` when choosing the next agent-safe action or review route for Queued/In Progress/Testing/Needs Fix cards.
3. `board card inspect <board> --card <id> --json` to understand state without scraping YAML.
4. `board section update ... --section "Current State" --value "..." --json` before and after implementation when state changes.
5. `board history add ... --type implementation --text "..." --source "..." --json` for concise implementation or fix summaries.
6. `board history add ... --type failed-attempt --text "..." --source "..." --json` when an attempted path matters for future agents.
7. `board evidence add ... --text "..." --source "..." --json` after verification. `board history add ... --type test` writes the same durable test-evidence lane.
8. `board history add ... --type decision --text "..." --source "..." --json` when a durable product, architecture, storage, CLI, QA, or agent-behavior choice is made.
9. For implementation work with repo changes, commit the scoped changes before moving the card to Done unless the user explicitly says not to commit.
10. `board history add ... --type commit --text "<sha> <branch/files/tests summary>" --source "git" --json` after committing, so Done cards can be traced to landed code.
11. If work is verified but intentionally uncommitted, record that state on the card and keep it out of Done.
12. `board history add ... --type handoff --text "..." --source "..." --json` before stopping, or use `board section update ... --section "Agent Handoff" --value "..." --json` for a full replacement handoff.

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
- Active todos should come from backend-backed item/review/agenda queries, not legacy type-specific todo list output.
- If a completed todo matches a same-cycle date card or event, reports should not keep calling the dated item overdue. Example: completed `Pay rent` suppresses a same-title `Pay Rent` event for that cycle.
- Rent/monthly bills should only appear when the next due date is close, roughly within five days, or when the configured reminder rule says to surface today.
- Birthdays/anniversaries should not appear in every daily report merely because they are future dated. Cider should support reminder policies such as "one week before," "on the day," or "start-of-month birthday digest," and the agenda API should return `surfaceToday`, reason, reminder policy, and next surface date.
- The same reminder should not spam every daily report across its lead window unless explicitly configured as a repeating reminder.
## Current Hardening Cautions

Historical CLI and storage bug detail belongs on Kanban cards, not in this core doc. Durable cautions for agents:

- After CLI capture while Cider.app is running, verify the final item with duplicate/search/get commands instead of assuming a single row exists.
- Inbox can be virtual or type-scoped. Prefer item/review/storage JSON over raw folder lookup when reporting Inbox health.
- Duplicate folder/note/bookmark regressions should be audited against the current second-brain backend before cleanup. Use the current roadmap/bug cards for exact evidence and acceptance criteria.
- CLI/date handling must preserve local-date semantics for all-day events, birthdays, due dates, and Kanban `created` dates.

## CLI Quality Bar

When fixing or adding CLI behavior:

- add focused tests where practical
- preserve existing human-readable output unless intentionally changing it
- verify JSON output with a parser
- keep command errors actionable
