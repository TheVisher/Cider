# Kanban Decisions

**Purpose:** Durable Kanban product, architecture, data-model, testing, and agent-workflow decisions. Keep task-local implementation history on Kanban cards; promote only the stable outcome here.

---

## 2026-05-04 — Docs vs. Kanban split

**Decision:** Use docs for durable Kanban truth and Kanban cards for active work/history.

- Durable truth belongs in `Docs/Features/Kanban/`: product behavior, architecture, data model, testing rules, decisions, and agent operating doctrine.
- Active/history context belongs on Kanban cards: bugs, ideas, implementation notes, review findings, test evidence, commit notes, failed attempts, and iterations.
- Important card outcomes should be promoted into the relevant docs before being treated as settled.

**Reason:** This keeps docs small and trustworthy while preserving the detailed operational history agents need for future bug-fixing and regression analysis.

## 2026-05-04 — Kanban docs are the docs-governance pilot

**Decision:** Use `Docs/Features/Kanban/` as the first test case for the broader Cider docs cleanup model.

- Do not reorganize all Cider docs at once.
- First make the Kanban docs reliable and canonical.
- Use the Kanban pilot to prove the pattern before applying it to other feature folders.

**Reason:** The full docs set is overwhelming. A focused pilot gives Erik and agents a concrete structure to validate without bulk moves or deletions.

## 2026-05-04 — Cards backlink to canonical docs

**Decision:** Kanban-related cards should backlink to `Docs/Features/Kanban/` or a more specific section when available.

**Agent rule:** Before implementing or reviewing a Kanban card, inspect the linked docs folder for current durable context, then keep task-local findings on the card.

**Reason:** Backlinks give agents a stable path from active work to durable context and prevent card notes from becoming the only place product/architecture truth lives.

## 2026-05-04 — Core layout before automation/archive

**Decision:** Nail the core Kanban project-board/swimlane layout before building deeper automation, commit-history workflows, or archive/history layers.

Suggested sequence:

1. Project-board/wide-board/swimlane layout.
2. Board layout templates and consistent process guidance.
3. Card history + commit/repo traceability.
4. Automated agent loops and review routing.
5. Archive/history once the layout and workflow model are clear.

**Reason:** Archive and automation depend on the board structure. Building them before rows/swimlanes and process templates risks encoding the wrong model.

## 2026-05-04 — Archive is a push-over column reveal, not a permanent active row

**Decision:** Project boards should expose archive/history through a toggle or button that slides archive columns in from the right and pushes the active columns left, instead of rendering Archive as a third always-visible row.

Behavior notes:

- The active board stays focused on current work rows, such as `Workflow` and `QA`.
- When Archive is collapsed, users see the normal active columns.
- When Archive is expanded, archive columns slide in from the right and replace/push over one visible column-width of the active board.
- The rightmost active columns should remain visible enough to support dragging completed/verified cards into archive.
- Archive columns should preserve source-lane context, e.g. `Workflow Archive` for cards from `Workflow/Done` and `QA Archive` for cards from `QA/Verified`.
- This is a spatial continuation of the left-to-right lifecycle: active work flows toward the right, and archive lives just beyond the active board.

**Reason:** This keeps archive close to the work without cluttering the main cockpit. It lets Erik see the relevant right-side active columns while archiving, supports drag-and-drop, and matches the natural left-to-right reading/workflow model.

## 2026-05-05 — Parent/child cards are the roadmap/history unit for large work

**Decision:** Large ideas, bugs, or implementation themes should become parent cards with ordered, scoped child cards instead of one huge card/note moving across the board.

Behavior notes:

- The parent represents the overarching idea, issue, or feature direction.
- Children represent implementation slices, discovered bugs, QA follow-ups, or fix attempts.
- Child cards can have their own children when a scoped slice reveals smaller bugs or follow-up work.
- Work should proceed in an intentional child order, while preserving manual top-to-bottom board order as an attention/implementation cue.
- Each card should remain bite-sized and useful as local history: problem, attempted fix, final fix, test evidence, and handoff context.
- Visual hierarchy is part of the feature, not polish: indent children, collapse/expand parent groups, show parent progress summaries, and color-match related cards across columns.
- Avoid cross-column connector lines; use shared accent color and parent badges for children in other columns.

**Reason:** This gives Erik an ADHD-friendly visual roadmap and gives LLM agents traceable, scoped history without forcing everyone to read thousand-line Markdown files or massive forever-card notes.

## 2026-05-05 — Project boards use Queued as the selected work stack

**Decision:** Project-style boards should use `Backlog -> Queued -> In Progress -> Testing -> Done` for their Workflow lane.

Behavior notes:

- `Backlog` is for ideas, concepts, rough future work, and unscheduled possibilities.
- `Queued` is for selected/upcoming work that is intended to be drained soon.
- `In Progress` should stay narrow and represent the card actively being implemented.
- `Testing` holds completed implementation that needs manual/agent verification.
- `Done` means accepted.
- Parent cards can move to `Queued` to stage a larger plan, while child cards move individually through `In Progress`, `Testing`, and `Done`.
- Future agent automation should read `Queued`, choose a safe order, move one card into `In Progress`, implement it, move it to `Testing`, then return to `Queued` for the next card.

**Reason:** This gives Erik and agents a clean middle state between idea backlog and active implementation. It also creates the foundation for unattended or semi-automated agent work without letting `In Progress` become a dumping ground.
