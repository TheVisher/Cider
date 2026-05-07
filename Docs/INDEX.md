# Cider Docs Index

Status: canonical core doc.

This folder should stay small. Cider uses Kanban for roadmap, QA evidence, active work, bugs, implementation notes, review findings, and completed plan history. Markdown docs exist only for durable development knowledge that should remain true after a card is done.

## Core Docs

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

## Existing Legacy Docs

The older docs tree is being audited. During the audit, each old Markdown file should be processed once:

1. Harvest durable facts into one of the core docs.
2. Convert active work, ideas, bugs, or QA evidence into Kanban if needed.
3. Delete the old doc after harvesting.

Do not create a permanent audit report doc. Audit state belongs on the Kanban card tracking the cleanup.
