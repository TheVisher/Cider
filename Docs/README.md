# Cider Docs Index and Routing Guide

**Purpose:** Help Erik and agents find the right Cider docs quickly, place new docs consistently, and detect when documentation should be updated instead of duplicated.

---

## Start Here

If you feel lost, use these in order:

1. **Visual map:** `Docs/Visuals/cider-docs-map.html`
2. **Reusable docs structure:** `Docs/Conventions/DOCS_INFORMATION_ARCHITECTURE.md`
3. **Feature README template:** `Docs/Templates/FEATURE_README_TEMPLATE.md`
4. Product direction / priorities: `Docs/Product/CIDER_ADAPTIVE_ROADMAP.md`
5. Overall product vision: `Docs/Product/PRODUCT_VISION.md`
6. Cider life-assistant vision: `Docs/Product/CIDER_LIFE_ASSISTANT_VISION.md`
7. Dashboard second-brain feed: `Docs/Product/CIDER_DASHBOARD_SECOND_BRAIN_FEED.md`
8. Kanban boards and development workflow: `Docs/Features/Kanban/README.md`
9. Todos, reminders, and resurfacing: `Docs/Features/TodosReminders/README.md`
10. Doc control agent concept: `Docs/Product/CIDER_DOC_CONTROL_AGENT.md`
11. Storage doctrine: `Docs/Architecture/STORAGE_DOCTRINE.md`
12. Transitional storage details: `Docs/Architecture/STORAGE.md`
13. Vault agent behavior: `Docs/Architecture/VAULT_AGENT_VISION.md`
14. Agent service / Hermes integration: `Docs/Architecture/AGENT_SERVICE.md`
15. Vault routing rules: `Docs/Vault/02-routing-rules-v1.md`
16. Agent CLI hardening notes: `Docs/Vault/05-agent-cli-hardening-notes.md`

---

## Routing Rules for New Docs

When creating or updating docs, prefer updating an existing source-of-truth doc before adding another standalone file.

### Docs vs. Kanban

Docs are Cider's durable foundation. Use docs for product vision, architecture, data models, UX principles, agent operating rules, routing doctrine, QA procedures, and big feature designs that should remain true after implementation work is complete.

Kanban is Cider's active work surface. Use Kanban cards for smaller tweaks, bugs, follow-up ideas, implementation tasks, testing tasks, code review findings, and handoff context for Hermes, Codex, Claude, or another agent.

If a Kanban card produces a lasting product, architecture, UX, data-model, routing, or agent-behavior decision, promote the durable outcome into the relevant doc. Do not create a new Markdown doc for every card; create full docs only when the work needs a durable standalone foundation record or large spec.

Large implementation plans/specs may live under `Docs/superpowers/`, but active tracking should still live on a Kanban card. Link the card to the plan/spec, and promote only durable outcomes into Product, Architecture, Feature, Vault, QA, or Conventions docs.

Use Kanban cards for task-local test evidence and handoff notes. Use `Docs/QA/` for reusable audit procedures, release/regression plans, and historical reports that should remain useful after the card is done.

### Product docs

Use `Docs/Product/` for:

- product vision
- adaptive roadmap
- feature prioritization
- user-experience direction
- major product decisions

### Architecture docs

Use `Docs/Architecture/` for:

- system boundaries
- storage and sync architecture
- agent host/runtime architecture
- integration patterns
- engineering doctrine

### Feature docs

Use `Docs/Features/<Feature>/` for durable docs about a specific feature or component.

Target structure:

```text
Docs/Features/<Feature>/
├── README.md
├── PRODUCT.md
├── DATA_MODEL.md
├── ARCHITECTURE.md
├── CLI.md
├── TESTING.md
├── ROADMAP.md
└── DECISIONS.md
```

Not every feature needs every file. Start small.

### Plans and specs

Use `Docs/superpowers/plans/` and `Docs/superpowers/specs/` for agent-generated implementation artifacts.

If a plan/spec contains durable product or architecture knowledge, summarize or promote the durable parts into `Docs/Product/`, `Docs/Architecture/`, or `Docs/Features/<Feature>/`.

### QA docs

Use `Docs/QA/` for:

- reusable audit procedures
- release/regression plans
- historical audit reports
- release checklists
- bug verification notes that should remain useful after the card is done

### Conventions docs

Use `Docs/Conventions/` for:

- coding conventions
- troubleshooting
- code-health rules
- doc style conventions

### Archive docs

Use `Docs/Archive/` for superseded docs that should be kept for history but not treated as active guidance.

---

## Feature Folder Candidates

Initial feature/component folders to create over time:

- `Docs/Features/Dashboard/`
- `Docs/Features/MainBrain/`
- `Docs/Features/AgentHost/`
- `Docs/Features/Kanban/`
- `Docs/Features/Bookmarks/`
- `Docs/Features/Notes/`
- `Docs/Features/TodosReminders/`
- `Docs/Features/CalendarEvents/`
- `Docs/Features/Contacts/`
- `Docs/Features/Files/`
- `Docs/Features/SearchRecall/`
- `Docs/Features/CLI/`
- `Docs/Features/Vault/`

---

## Code ↔ Docs Mapping Seed

Use this as the starting point for doc-control audits.

```text
Sources/Cider/Models/Dashboard/       -> Docs/Features/Dashboard/DATA_MODEL.md
Sources/Cider/Services/Dashboard/     -> Docs/Features/Dashboard/ARCHITECTURE.md
Sources/Cider/Views/Dashboard/        -> Docs/Features/Dashboard/README.md
Sources/CiderCLI/*Dashboard*          -> Docs/Features/Dashboard/CLI.md
Tests/CiderTests/Dashboard*           -> Docs/Features/Dashboard/TESTING.md

Sources/Cider/Services/Agent/         -> Docs/Features/MainBrain/ARCHITECTURE.md
Sources/Cider/Views/*AI*              -> Docs/Features/MainBrain/README.md
Docs/Architecture/AGENT_SERVICE.md    -> Docs/Features/AgentHost/README.md or Architecture source

Sources/Cider/Models/KanbanBoard.swift          -> Docs/Features/Kanban/DATA_MODEL.md
Sources/Cider/Services/KanbanStorage.swift      -> Docs/Features/Kanban/ARCHITECTURE.md
Sources/Cider/Views/Kanban/                     -> Docs/Features/Kanban/README.md
Sources/CiderCLI/CiderCLI.swift board commands  -> Docs/Features/Kanban/ARCHITECTURE.md
Tests/CiderTests/Kanban*                        -> Docs/Features/Kanban/TESTING.md

Sources/Cider/Models/TodoCard.swift                    -> Docs/Features/TodosReminders/DATA_MODEL.md
Sources/Cider/Models/DateCard.swift                    -> Docs/Features/TodosReminders/DATA_MODEL.md
Sources/Cider/Models/SurfacingRule.swift               -> Docs/Features/TodosReminders/DATA_MODEL.md
Sources/Cider/Services/ReminderReconciler.swift        -> Docs/Features/TodosReminders/ARCHITECTURE.md
Sources/Cider/Services/DateCardNotificationService.swift -> Docs/Features/TodosReminders/ARCHITECTURE.md
Sources/Cider/Services/ReminderOutbox.swift            -> Docs/Features/TodosReminders/ARCHITECTURE.md
Sources/Cider/Services/DailyVaultReminderService.swift -> Docs/Features/TodosReminders/ARCHITECTURE.md
Tests/CiderTests/*Todo* Tests/CiderTests/*Reminder* Tests/CiderTests/*Event* -> Docs/Features/TodosReminders/TESTING.md

Sources/CiderCLI/                     -> Docs/Features/CLI/README.md
Docs/Vault/*                          -> Docs/Features/Vault/README.md or vault-specific docs
```

---

## Agent Rules

1. Check this README before creating a new Cider doc.
2. Check `Docs/Product/CIDER_ADAPTIVE_ROADMAP.md` before changing product priority.
3. Prefer updating a source-of-truth doc over creating another scattered note.
4. If a new doc is necessary, place it in the smallest appropriate folder.
5. If a doc is probably stale, label it as stale or propose an archive; do not silently delete it.
6. If code and docs conflict, report the conflict and cite paths/lines.
7. For bulk doc moves/rewrites, produce a report and ask Erik before mutating.

---

## Doc Control Agent

The intended recurring maintenance agent is described in:

`Docs/Product/CIDER_DOC_CONTROL_AGENT.md`

It should begin as report-only and produce suggested doc updates, moves, merges, and dashboard cards before making changes.
