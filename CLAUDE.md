# Cider

Native macOS floating panel app for bookmarks, notes, and projects. Double-tap Option to activate. SwiftUI + AppKit, macOS 14+.

## Critical Rules

- **Never steal focus** — `NSPanel` with `.nonactivatingPanel`
- **No hardcoded colors** — `CiderColors.*` from Constants.swift
- **No hardcoded fonts** — `CiderFont.*` from CiderFont.swift
- **No magic numbers** — spacing/animation tokens from Constants.swift
- **Spring animations only** — no `.easeIn`, `.easeOut`, `.linear`
- **Respect Reduce Motion** — `reduceMotion ? .none : .spring` on every animation
- **Acrylic style** — `NSVisualEffectView` with `.underWindowBackground`, NOT `.glassEffect()`
- **Use `os.Logger`** — not `print()` (invisible from Dock launch)
- **Delete via TrashStorage** — never direct file deletion, always TrashStorage + CiderUndoManager
- **Update Kanban boards** — Kanban is first-class for Cider development. For read-only audits or quick inspections, do not move or create cards unless the user asks. For substantial implementation, bug fixing, or agreed follow-up work, update the YAML boards in `~/CiderVault/.cider/boards/`. Move cards between columns (backlog/planned → in_progress → testing/ready to test → done). The app watches these files and updates live.
- **Keep docs lean** — active docs are the core docs listed in `Docs/INDEX.md`. Roadmap, bugs, QA evidence, implementation notes, review findings, failed attempts, and completed plan history belong in Kanban.
- **Delete completed docs** — plans/specs are temporary. When work is done, harvest durable facts into core docs, put work history on the card, then delete the completed plan/spec. Git history is the archive.
- **YAML board rules** — every card MUST have a `created` field (e.g. `created: '2026-03-29'`). Always quote dates with single quotes. Never duplicate keys on the same card. Prefer supported CLI commands or structured YAML parsing when available. If editing manually, rewrite the whole board file and preserve indentation; avoid tiny indentation-sensitive edits.

## Kanban Boards

YAML files in `~/CiderVault/.cider/boards/`. Active boards include:
- `2afee0.yaml` — **Cider** (default dedicated Cider product/project board)
- `08c899.yaml` — **Cider Web**
- `2d3f69.yaml` — **Cider iOS**
- `a1b2c3.yaml` — **Cider Roadmap** (legacy/general roadmap)
- `d4e5f6.yaml` — **Cider Bugs**
- `p1l2m3.yaml` — **Implementation Plans**
- `e7f8a9.yaml` — **Kanban Implementation**
- `f0d730.yaml` — **Vault Agent Work**

Docs and Kanban have different jobs:

- **Docs are the minimal durable foundation** — product principles, feature summaries, architecture, storage, agent rules, CLI contracts, reusable QA procedures, design rules, and conventions.
- **Kanban is the active work surface** — roadmap, bugs, active ideas, implementation tasks, testing tasks, QA evidence, code review findings, failed attempts, completed plan history, and handoff records.
- If a Kanban item produces a lasting product/architecture/UX/data-model/agent/CLI/storage decision, promote that outcome into the relevant core doc before or when the card moves to done.
- Do not create one-off Markdown docs for tasks. Use Kanban cards for specs, implementation plans, QA evidence, and handoff context unless the user explicitly asks for a standalone doc.
- Completed plans/specs should be harvested into core docs and Kanban cards, then deleted.

When you start work on a feature, move its card to `in_progress`. When done, move to `done` (or `testing` if it needs manual testing). When fixing a bug, move it to `fixed`. If you build something new that isn't on the board, add a card.

Use cards as working handoff records. Add implementation notes, test evidence, blockers, failed attempts, and follow-up context to the card so Hermes, Codex, Claude, or another agent can pick up the thread without creating stray Markdown files for every task.

Use `Docs/QA.md` for reusable audit procedures and release/regression plans. Historical reports should be harvested and deleted.

## Build

```
swift build -Xswiftc -warnings-as-errors
```

## Skills

Use `/code`, `/design`, `/review`, `/docs` for deep reference on conventions, UI tokens, code review checklists, and doc formatting. Invoke before writing code or docs in unfamiliar areas.

## Docs

**How to read docs:** Start with `Docs/INDEX.md`, then read only the relevant core doc.

**How to write docs:** Update an existing core doc whenever possible. Do not create standalone docs for temporary work.

**Before debugging:** Search Kanban cards and git history for prior failures. Old one-off Markdown reports are being removed during the docs diet.

| Doc | Contents |
|-----|----------|
| `Docs/INDEX.md` | Canonical docs entrypoint and active core-doc list |
| `Docs/PRODUCT.md` | Product principles and current direction |
| `Docs/FEATURES.md` | Concise inventory of app features |
| `Docs/ARCHITECTURE.md` | App structure, services, boundaries |
| `Docs/STORAGE.md` | SQLite, vault files, backups, sync, migration |
| `Docs/AGENT.md` | Agent workflow, docs hygiene, Kanban rules |
| `Docs/CLI.md` | cider-cli usage and agent command patterns |
| `Docs/QA.md` | Reusable verification and release procedures |
| `Docs/DESIGN.md` | Durable design and interaction rules |
| `Docs/CONVENTIONS.md` | Code, docs, Kanban, and git conventions |
