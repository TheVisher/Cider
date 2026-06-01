# Cider Agent Rules

Status: canonical core doc.

This doc tells agents how to work on Cider without growing a second project-management system in Markdown.

## Current Product Line

`main` is the second-brain Cider line. Treat Cider as a local-first Mac second brain and life command center, with the product direction summarized in `Docs/PRODUCT.md`.

The pre-second-brain app is preserved on `legacy/pre-second-brain-cider` for reference only. Do not use legacy docs or old branch behavior as active instruction unless the durable fact has been promoted into the current core docs or a current Kanban card.

The active roadmap source is the Second-Brain Roadmap v1 board, `~/CiderVault/.cider/boards/3d45ca.yaml`.

## The Model

Cider itself is the roadmap, QA, and handoff system.

- Kanban is the active work surface.
- Core docs are the durable development reference.
- Git history is the archive for deleted docs.

Agents should not preserve stale Markdown out of caution. If the useful information has been harvested into a core doc or a Kanban card, delete the old doc.

## Active Docs Policy

The active docs are the core docs listed in `Docs/INDEX.md`.

Do not create new standalone Markdown docs by default. New docs require a clear reason that the information is durable, broadly useful, and does not fit in an existing core doc.

Use Kanban for:

- roadmap ideas
- feature requests
- bugs
- QA evidence
- implementation notes
- review findings
- failed attempts
- handoff context
- completed plan history

Use core docs for:

- product principles
- architecture boundaries
- storage and vault rules
- agent behavior
- CLI contracts
- reusable QA procedures
- durable design rules
- coding conventions
- concise feature summaries

## Agent Behavior

Agents should be conservative operators over real Cider data:

- Use `cider-cli` or Cider services for current facts whenever possible.
- New agent capture must use `cider-cli capture add --kind ... --json`.
- Journal, voice-derived, and driving reflection intake must use `cider-cli capture add --kind journal --date today --stdin --json`; do not edit daily journal Markdown directly.
- Do not call hidden type-specific legacy commands such as `bookmark`, `note`, `todo`, `event`, `contact`, `file`, `folder`, `tag`, `label`, or `dashboard` as alternate APIs.
- Do not treat memory as more current than the Cider store, CLI, vault, or active Kanban card.
- Do not write AI-generated text into user-owned fields such as bookmark notes.
- Use AI-owned enrichment fields for generated summaries.
- Prefer capture, retrieval, and safe organization over broad autonomous cleanup.
- When asked to organize or delete, present a small plan unless the user clearly asked for immediate mutation.
- Do not make Spaces independent silos; they are surfaces over shared item, routing, review, saved-view, dashboard, and relevance state.
- Treat the file-backed domain contracts in `Docs/STORAGE.md` as authority: legacy memory files and folder-kanban YAML are not first-class second-brain truth unless rebuilt through canonical item, routing, and provenance services.
- Do not build clever auto-filing that hides uncertainty from the user. Low-confidence decisions belong in review.

## Plans And Specs

Plans and specs are temporary work products. Repo docs are not a scratchpad.

Project-scoped feature plans may live as Markdown artifacts inside the Cider vault while they are being shaped:

- `~/CiderVault/Projects/<Project>/Plans/`

Project-scoped QA and audit reports may live as Markdown artifacts inside the Cider vault while they are being triaged:

- `~/CiderVault/Projects/<Project>/QA/`

These vault artifacts are visual Cider work surfaces, not permanent repo docs. Use them to turn discussions, references, and audits into a clear milestone plus scoped Kanban cards. Link generated cards back to the source plan or QA artifact when possible.

For audits, QA passes, feature plans, and larger implementation planning:

1. Write the findings, evidence, open questions, and proposed direction in the appropriate Project artifact first: `Projects/<Project>/Plans/` for plans/specs, or `Projects/<Project>/QA/` for audits and QA reports.
2. Refine that artifact until it is solid enough to drive work. Do not skip straight from a broad audit or brainstorm into a pile of unrelated cards.
3. Create a milestone from the accepted artifact. The milestone is the overarching goal and should link back to the source plan or QA artifact.
4. Extract small, agent-ready Kanban cards under that milestone. Cards should be bite-sized fixes or verification tasks, not massive codebase-wide changes.
5. Work the cards one by one through `Queued`, `In Progress`, `Testing`, and `Done`, recording implementation history, failed attempts, verification evidence, and commits on each card.

If a proposed card cannot be implemented, tested, and committed as a reasonably scoped unit, split it before work begins. The project artifact and milestone hold the big picture; cards hold the execution trail.

When a feature or fix is complete:

1. Promote durable product, architecture, storage, agent, CLI, QA, design, or convention changes into the relevant core doc.
2. Put implementation notes, test evidence, failures, and handoff details on the Kanban card.
3. Archive, mark extracted, or delete the completed vault plan/QA artifact after its milestone/cards carry the work.

Do not keep completed plan/spec files in the docs tree just in case. If old repo context is ever needed, use git history.

## Docs Diet Audit Workflow

When auditing old docs, process one file at a time:

1. Read the file for durable facts.
2. Move still-current durable facts into the correct core doc.
3. Create or update Kanban cards for active work, bugs, ideas, or QA evidence.
4. Delete the old file once harvested.
5. Add a short note to the cleanup Kanban card with the file path and outcome.

Allowed outcomes:

- `harvested-to-core`
- `converted-to-card`
- `already-covered`
- `obsolete`
- `deleted`

Do not create a permanent Markdown audit log. The cleanup card is the audit log.

## Cider Kanban Rules

Board files live in `~/CiderVault/.cider/boards/`.

- Check the relevant board before substantial work.
- For read-only inspections, do not move or create cards unless the user asks.
- Use `cider-cli board ...` commands for routine Kanban mutations: card creation, card movement, section updates, implementation history, evidence, handoffs, and commit traceability.
- If work already has a card, move it to the active column before implementation with `cider-cli board move-card`.
- If work does not have a card, create an agent-ready card with `cider-cli board add-card`; the card must include `created: 'YYYY-MM-DD'`.
- Put test evidence and implementation notes on the card with `cider-cli board evidence add` and `cider-cli board history add`.
- Move fixed bugs to the bugs board `Fixed` column with `cider-cli board move-card`.
- Move implementation work through `Queued`, `In Progress`, `Testing`, and `Done` as reality changes with `cider-cli board move-card`.
- For implementation cards with repo changes, do not move to `Done` until the changes are committed and the card has commit traceability. If the user explicitly asks not to commit, keep the card out of `Done` or mark the card state as verified but unlanded.
- Do not leave cards in Testing when an agent can verify the result with CLI/tests/builds that produce the same evidence Erik would read. Run the verification, record evidence, and move the card forward.
- Testing handoffs to Erik must be ID-readable from chat: group cards by `Needs Erik` vs `Agent can verify`, include the card title/status, and use IDs only as secondary references.
- Do not patch board YAML by hand for normal card work. Raw board YAML edits are allowed only for parser/storage debugging or emergency repair, and must be followed by a full board parse validation and projection refresh when relevant.
- If a needed Kanban mutation is not supported by `cider-cli board ...`, create or update a scoped follow-up card to add the missing CLI command instead of normalizing manual YAML patching.
- For emergency direct edits only: preserve YAML structure, quote dates with single quotes, validate the board file, and record why the CLI path could not be used.

## Second-Brain Card Workflow

For Cider development work with a Kanban card, agents should use the structured card contract before reading raw board YAML:

1. If the active card ID is unknown, run `cider-cli board recent <board> --limit 20 --json`.
2. For workflow pickup or review routing, run `cider-cli board workflow <board> --json` and follow `automationActions` as approval-aware guidance, not as silent automation.
3. For Testing queue triage, run `cider-cli board testing-summary <board> --json` and use its `needsErik` / `agentCanVerify` grouping.
4. Inspect the active card with `cider-cli board card inspect <board> --card <id> --json`.
5. Read `dashboard.currentState`, `dashboard.nextStep`, `dashboard.openLoops`, `dashboard.evidenceEntries`, and `dashboard.agentContext`.
6. Move or create cards through `cider-cli board ...` commands, not direct YAML edits.
7. Update active status with `cider-cli board section update <board> --card <id> --section "Current State" --value "..." --json`.
8. Add implementation summaries with `cider-cli board history add <board> --card <id> --type implementation --text "..." --source "..." --json`.
9. Add failed-attempt notes with `cider-cli board history add <board> --card <id> --type failed-attempt --text "..." --source "..." --json` when they would save a future agent time.
10. Add verification through `cider-cli board evidence add <board> --card <id> --text "..." --source "..." --json`.
11. Record durable product, architecture, storage, CLI, QA, or agent-behavior choices with `cider-cli board history add <board> --card <id> --type decision --text "..." --source "..." --json` before promoting them into core docs.
12. For repo changes, commit the scoped work before `Done` unless the user explicitly says not to commit.
13. After committing, add commit traceability with `cider-cli board history add <board> --card <id> --type commit --text "<sha> <branch/files/tests summary>" --source "git" --json`.
14. Move the card to `Done` only after verification and commit traceability are recorded, or explicitly record that the work is verified but unlanded and keep it out of `Done`.
15. Before stopping, refresh `Agent Handoff` with the current status, exact commands the next agent should run, known gaps, and merge/push constraints.

Use `cider-cli item get card <id> --json` when an agent only needs projected sections/provenance, and `cider-cli item search <query> --json` when it needs retrieval across projected chunks. Raw Markdown or YAML inspection is for parser/storage debugging, not normal handoff.

## Accepted Graph Workflow

The accepted second-brain graph backend is the agent-facing memory foundation. Agents should use graph commands before falling back to raw SQLite, prose inference, or folder-path guesses.

- Run `cider-cli item graph-health --json` before raw SQLite inspection when checking graph readiness. Treat `needs_rebuild`, `needs_sync`, and `needs_review` as actionable state, not as permission to mutate silently.
- Use `cider-cli item project-context <project> --json` for project graph context. Prefer the returned owner refs, relations, counts, and safe commands over reading project folders or scraping Kanban YAML.
- Use item/project/owner context commands to understand relationships, backlinks, `captureProvenance`, routing, enrichment, and similarity state before making organization changes.
- Capture new source material through canonical capture commands/services so `capture_events`, `capture_attachments`, owner relations, routing, review, and agent-visible result JSON stay connected.
- Generated enrichment, similarity candidates, and grouping suggestions are reviewable outputs. Do not silently promote them into user organization unless the command explicitly records an approved mutation.
- Record friction as scoped Kanban follow-up cards instead of reopening broad architecture plans. Good follow-ups include bounded output, missing relation visibility, stale projection repair, or dogfood findings.
- Promote only durable product, storage, CLI, QA, or agent-behavior contracts into core docs after the card evidence proves them.

## Development Rules

- Use existing Cider patterns before adding abstractions.
- Keep edits scoped to the card.
- Use `os.Logger` for runtime logging.
- Use Cider design tokens for colors, fonts, spacing, radii, shadows, and animations.
- Delete user data through Cider trash/undo flows, not direct file deletion.
- Prefer structured parsing for YAML and persisted data.
- Verify changes with the narrowest meaningful build or test command.

## Bookmark Capture Rule

When the user sends a bare URL, use the full capture loop:

1. Capture through `cider-cli capture add --kind bookmark --url "<url>" --json`.
2. Inspect the capture JSON for duplicate, routing, review, provenance, indexing, `nextSafeAction`, and `safeNextCommands`.
3. Re-read through `cider-cli item get bookmark <id> --json` when an item ID is available.
4. Route or review only through backend-backed `item`/`review` commands.
5. Report the verified final title, routing/review state, and caveat.

## Agent Save Routing

When an agent saves a bookmark, note, contact, todo, date card, journal entry, or file:

- Use `cider-cli capture add --kind ... --json`; use `--stdin` or `--text-file` for exact raw text, `--url` for bookmarks, and `--path` for files.
- For journal-style memory intake, use `cider-cli capture add --kind journal --date today --stdin --json`; this appends to the daily journal and returns normal capture JSON.
- Successful journal captures should be verified through `safeNextCommands` such as `item get` or `item context`, not sent through folder-route review chores.
- Route obvious items before creation when the destination is clear.
- Use Inbox when classification is uncertain.
- Do not create in Inbox and move later unless routing is genuinely unclear.
- Inspect capture duplicate state and use backend-backed item search before creating a likely duplicate.
- Report the verified final destination after mutation.

## Checkpoints And Handoffs

For long-running Cider work, checkpoint into Kanban:

- what changed
- what was tested
- what failed or was deferred
- what another agent should read next

Do not create checkpoint Markdown files unless the user explicitly asks.
