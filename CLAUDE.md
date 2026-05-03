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
- **YAML board rules** — every card MUST have a `created` field (e.g. `created: '2026-03-29'`). Always quote dates with single quotes. Never duplicate keys on the same card. Prefer supported CLI commands or structured YAML parsing when available. If editing manually, rewrite the whole board file and preserve indentation; avoid tiny indentation-sensitive edits.

## Kanban Boards

YAML files in `~/CiderVault/.cider/boards/`. Active boards include:
- `a1b2c3.yaml` — **Cider Roadmap** (features, backlog, in progress, done)
- `d4e5f6.yaml` — **Cider Bugs** (high/medium/low priority, fixed)
- `p1l2m3.yaml` — **Implementation Plans** (implementation handoff/tracking)
- `e7f8a9.yaml` — **Kanban Implementation** (board mechanics)
- `f0d730.yaml` — **Vault Agent Work** (vault/agent workflow)

Docs and Kanban have different jobs:

- **Docs are the durable foundation** — product vision, architecture, data model, UX principles, agent operating rules, routing doctrine, and big feature designs that should remain true after individual tasks are done.
- **Kanban is the active work surface** — small tweaks, bugs, follow-up ideas, implementation tasks, testing tasks, code review findings, and short handoff records.
- If a Kanban item produces a lasting product/architecture/UX/data-model/agent-behavior decision, promote that outcome into the relevant docs before or when the card moves to done.
- Large implementation plans/specs may live under `Docs/superpowers/`, but active tracking should still live on a Kanban card. Link the card to the plan/spec, and promote only durable outcomes into Product, Architecture, Feature, Vault, QA, or Conventions docs.
- Do not create one-off Markdown docs for every task. Create a full Markdown spec/doc only when the work genuinely needs a durable standalone foundation record or large design.

When you start work on a feature, move its card to `in_progress`. When done, move to `done` (or `testing` if it needs manual testing). When fixing a bug, move it to `fixed`. If you build something new that isn't on the board, add a card.

Use cards as working handoff records. Add implementation notes, test evidence, blockers, and follow-up context to the card so Hermes, Codex, Claude, or another agent can pick up the thread without creating stray Markdown files for every task. Create a full Markdown spec only when the work genuinely needs a durable standalone document.

Use `Docs/QA/` for reusable audit procedures, release/regression plans, and historical reports that should remain useful after the card is done.

## Build

```
swift build -Xswiftc -warnings-as-errors
```

## Skills

Use `/code`, `/design`, `/review`, `/docs` for deep reference on conventions, UI tokens, code review checklists, and doc formatting. Invoke before writing code or docs in unfamiliar areas.

## Docs

**How to read docs:** Read ONLY the Table of Contents first, then jump to the relevant section by line number. Do not read entire docs unless explicitly asked.

**How to write docs:** Use `/docs` skill — it has the exact format rules. No guessing.

**Before debugging:** Read `Docs/LESSONS_LEARNED.md` TOC for the relevant feature area. Past bugs with root causes and fixes are documented there.

| Doc | Contents |
|-----|----------|
| `Docs/LESSONS_LEARNED.md` | Past bugs: symptom → root cause → fix, organized by feature |
| `Docs/Architecture/ARCHITECTURE.md` | Panel, floating panel, tech stack, SwiftUI + AppKit patterns |
| `Docs/Architecture/STORAGE.md` | Vault file storage, webloc lifecycle, sidecar system |
| `Docs/Design/DESIGN_SYSTEM.md` | Component catalog, spacing, color tokens, cross-tab patterns |
| `Docs/Conventions/CONVENTIONS.md` | Code conventions, naming, patterns |
| `Docs/Conventions/CODE_HEALTH.md` | Weekly health scans, large file tracking |
| `Docs/Conventions/TROUBLESHOOTING.md` | Performance patterns, known issues |
| `Docs/Features/AI.md` | AI architecture, tool calling, MLX, Apple Intelligence, oEmbed |
| `Docs/Features/TIPTAP_EDITOR.md` | TipTap/ProseMirror editor in WKWebView |
| `Docs/Features/SYSTEM_DESIGN.md` | Detail panel spec, integration design patterns |
| `Docs/Product/PRODUCT_VISION.md` | Roadmap, per-tab visions, strategy |
| `Docs/QA/AUDIT_LOOPS.md` | All reusable audit procedures (design tokens, conventions, threading, storage, dead code) |
| `Docs/QA/AUDIT_REPORTS.md` | Historical audit findings and fixes |
| `Docs/BUILD_STATUS.md` | Current build health and warnings |
| `Shared/` | Cross-platform: sync protocol, data model, feature parity |
