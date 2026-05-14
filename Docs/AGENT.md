# Cider Agent Rules

Status: canonical core doc.

This doc tells agents how to work on Cider without growing a second project-management system in Markdown.

## The Model

Cider itself is the roadmap and QA system.

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
- Do not treat memory as more current than the vault.
- Do not write AI-generated text into user-owned fields such as bookmark notes.
- Use AI-owned enrichment fields for generated summaries.
- Prefer capture, retrieval, and safe organization over broad autonomous cleanup.
- When asked to organize or delete, present a small plan unless the user clearly asked for immediate mutation.

## Plans And Specs

Plans and specs are temporary work products.

When a feature or fix is complete:

1. Promote durable product, architecture, storage, agent, CLI, QA, design, or convention changes into the relevant core doc.
2. Put implementation notes, test evidence, failures, and handoff details on the Kanban card.
3. Delete the completed plan/spec doc.

Do not keep completed plan/spec files in the docs tree just in case. If old context is ever needed, use git history.

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
- If work already has a card, move it to the active column before implementation.
- If work does not have a card, create an agent-ready card with `created: 'YYYY-MM-DD'`.
- Put test evidence and implementation notes on the card.
- Move fixed bugs to the bugs board `Fixed` column.
- Move implementation work through `Queued`, `In Progress`, `Testing`, and `Done` as reality changes.
- Preserve YAML structure and quote dates with single quotes.

## Second-Brain Card Workflow

For Cider development work with a Kanban card, agents should use the structured card contract before reading raw board YAML:

1. Inspect the active card with `cider-cli board card inspect <board> --card <id> --json`.
2. Read `dashboard.currentState`, `dashboard.nextStep`, `dashboard.openLoops`, `dashboard.evidenceEntries`, and `dashboard.agentContext`.
3. Move or create cards through `cider-cli board ...` commands, not direct YAML edits.
4. Update active status with `cider-cli board section update <board> --card <id> --section "Current State" --value "..." --json`.
5. Add verification through `cider-cli board evidence add <board> --card <id> --text "..." --source "..." --json`.
6. Record durable product, architecture, storage, CLI, QA, or agent-behavior choices in a `Decisions` section before promoting them into core docs.
7. Before stopping, refresh `Agent Handoff` with the current status, exact commands the next agent should run, known gaps, and merge/push constraints.

Use `cider-cli item get card <id> --json` when an agent only needs projected sections/provenance, and `cider-cli item search <query> --json` when it needs retrieval across projected chunks. Raw Markdown or YAML inspection is for parser/storage debugging, not normal handoff.

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

1. Run duplicate check.
2. Save to a conservative staging path unless the destination is obvious.
3. Enrich metadata.
4. Re-read the bookmark.
5. Route only when confidence is high.
6. Re-read and report final title, folder, path, and caveat.

## Agent Save Routing

When an agent saves a bookmark, note, contact, todo, date card, or file:

- Route obvious items before creation when the destination is clear.
- Use Inbox when classification is uncertain.
- Do not create in Inbox and move later unless routing is genuinely unclear.
- Search/duplicate-check before creating a likely duplicate.
- Report the verified final destination after mutation.

## Checkpoints And Handoffs

For long-running Cider work, checkpoint into Kanban:

- what changed
- what was tested
- what failed or was deferred
- what another agent should read next

Do not create checkpoint Markdown files unless the user explicitly asks.
