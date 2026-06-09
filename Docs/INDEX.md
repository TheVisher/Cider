# Cider Docs Index

Status: canonical core doc.

This folder is Cider's durable documentation layer for the second-brain product line. It should stay small.

Cider uses Kanban for roadmap, specs, QA evidence, active work, bugs, implementation notes, review findings, failed attempts, completed plan history, and handoff records. Markdown docs exist only for durable development knowledge that should remain true after a card is done.

`main` is now the second-brain Cider line. The pre-second-brain product line is preserved for reference on `legacy/pre-second-brain-cider`; it is not active direction.

## Core Docs

- `Docs/NORTH_STAR.md` - guiding second-brain/life-assistant direction for broad work, audits, and future-agent prompts.
- `Docs/PRODUCT.md` - product direction, principles, and current focus.
- `Docs/FEATURES.md` - compact inventory of app features and what each one does.
- `Docs/ARCHITECTURE.md` - app structure, major services, and boundaries.
- `Docs/STORAGE.md` - SQLite, vault files, backups, sync, and migration rules.
- `Docs/AGENT.md` - agent operating rules for Cider development and docs hygiene.
- `Docs/CLI.md` - `cider-cli` usage and agent-facing command patterns.
- `Docs/QA.md` - reusable verification and release procedures.
- `Docs/DESIGN.md` - durable visual and interaction principles.
- `Docs/CONVENTIONS.md` - code, docs, and workflow conventions.

## What Does Not Belong In Docs

- Roadmap ideas belong on Kanban cards.
- Bugs belong on the bugs board.
- QA evidence for a task belongs on the card that needed testing.
- Implementation notes belong on the implementation card.
- Completed plans and specs should be harvested, then deleted.
- Historical handoffs should be harvested into a core doc or card, then deleted.

Git history is the archive for deleted Markdown. Do not keep stale docs alive just because they might be interesting later.

## Legacy Reference

The old Cider product/docs state is available through git, especially `legacy/pre-second-brain-cider`. Treat it as historical reference, not product instruction.

When old Markdown or legacy branch content is consulted:

1. Promote only still-current durable facts into a core doc.
2. Convert active work, ideas, bugs, or QA evidence into Kanban if needed.
3. Leave historical context in git history or on the relevant Kanban card.

Do not create a permanent audit report doc. Audit state belongs on the Kanban card tracking the cleanup.
