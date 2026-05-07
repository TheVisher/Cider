# Cider Agent Notes

## Cider Development Kanban

Kanban is a first-class development workflow for Cider, not just an app feature.

Docs and Kanban have different jobs:

- Docs are Cider's minimal durable foundation: product principles, feature summaries, architecture, storage, agent rules, CLI contracts, reusable QA procedures, design rules, and conventions.
- Kanban is Cider's active work surface: roadmap ideas, bugs, follow-up ideas, implementation tasks, testing tasks, QA evidence, code review findings, failed attempts, completed plan history, and handoff records.
- Active docs should stay limited to the core docs listed in `Docs/INDEX.md`.
- Promote important Kanban outcomes into core docs only when they become lasting product, architecture, UX, data-model, routing, QA, CLI, storage, or agent-behavior decisions.
- Do not create stray Markdown docs for tasks. Use Kanban cards for specs, plans, notes, QA evidence, and handoffs unless the user explicitly asks for a standalone doc.
- Plans/specs are temporary. When work is complete, harvest durable facts into the core docs, put implementation/test history on the Kanban card, then delete the plan/spec doc. Git history is the archive.
- During the docs diet migration, process old Markdown files one by one: harvest durable facts into core docs, convert active work into Kanban cards if needed, then delete the old doc.
- `Docs/AGENT.md` is the canonical detailed agent workflow for docs hygiene and Cider development.

For Cider development work, agents should use the boards in `~/CiderVault/.cider/boards/` as the shared source of truth:

- For read-only audits or quick inspections, do not move or create Kanban cards unless the user asks.
- Check the relevant board before starting substantial work.
- If the work already has a card, move it to the active work column before implementing.
- If the work does not have a card, add one with a concise title, useful notes/spec context, and `created: 'YYYY-MM-DD'`.
- Move work through the board as reality changes: backlog/planned -> queued -> in_progress -> testing/ready to test -> done.
- On project boards, use `Queued` as the selected work stack between `Backlog` and `In Progress`. Pull chosen cards or parent groups into `Queued`, then move one scoped card at a time into `In Progress`, finish it, move it to `Testing`, and return to `Queued` for the next item.
- For bugs, use the bugs board and move fixed items to `fixed`.
- Put implementation notes, test evidence, blockers, failed attempts, and follow-up context on the card instead of scattering one-off Markdown files.
- When auditing old Roadmap/Bugs cards, move relevant Cider work into the dedicated project boards instead of deleting it; preserve old cards until their value is clear.
- Use `Docs/QA.md` for reusable audit procedures and release/regression plans. Historical QA reports should be harvested into cards or `Docs/QA.md`, then deleted.
- When a Kanban card grows into multiple deliverables, create child cards linked to the parent instead of expanding one forever-card. Parent cards should summarize direction; child cards should carry scoped implementation notes, test evidence, commits, and status.
- When splitting a parent/done card into child or follow-up cards, make each new card agent-ready instead of title-only. Include: Problem, Goal, MVP scope, non-goals/deferred scope, acceptance criteria, parent/source card or docs backlink, tags, priority, and a `created: 'YYYY-MM-DD'` field.
- Create follow-up cards sequentially unless you are using a workflow with board file locking; avoid parallel YAML writes to the same board.
- Keep card text useful for future handoff to Hermes, Codex, or another agent.

## Bookmark Capture Workflow

When the user sends a bare URL, do not stop after creating the bookmark. Use the full capture loop before reporting success:

1. Run `duplicate-check <url> --json`.
2. Save new bookmarks to a conservative staging path such as `Inbox/Bookmarks` unless the target folder is already obvious.
3. Run `bookmark enrich <id>` or otherwise let Cider fetch metadata.
4. Re-read with `bookmark get <id> --json`.
5. Route based on the enriched title/content and current vault topology; if routing confidence is below about 90%, leave it in `Inbox/Bookmarks` and ask.
6. Re-read again and report the verified final title, folder, relative path, and any caveat.

Active board files:

- `~/CiderVault/.cider/boards/2afee0.yaml` — Cider (default dedicated Cider product/project board; move newly audited Cider work here instead of deleting old cards)
- `~/CiderVault/.cider/boards/08c899.yaml` — Cider Web
- `~/CiderVault/.cider/boards/2d3f69.yaml` — Cider iOS
- `~/CiderVault/.cider/boards/a1b2c3.yaml` — Cider Roadmap (legacy/general roadmap; audit old cards and move relevant work into dedicated project boards)
- `~/CiderVault/.cider/boards/d4e5f6.yaml` — Cider Bugs
- `~/CiderVault/.cider/boards/p1l2m3.yaml` — Implementation Plans
- `~/CiderVault/.cider/boards/e7f8a9.yaml` — Kanban Implementation
- `~/CiderVault/.cider/boards/f0d730.yaml` — Vault Agent Work

YAML rules:

- Preserve board YAML structure and indentation.
- Every card must have a `created` field.
- Quote dates with single quotes, for example `created: '2026-05-03'`.
- Do not duplicate keys on a card.
- Prefer structured parsing or a whole-file rewrite over small indentation-sensitive YAML edits.

## Social Voice

For Cider social posts, write like a useful product made by a real person.

- Professional, but not corporate.
- Clear about what Cider does.
- Lightly humorous or mildly snarky when it fits.
- Specific examples beat vague productivity language.
- Avoid obvious AI phrasing, launch hype, and em dashes.
- Default vibe: helpful Mac app, tiny bit opinionated, never uptight.
