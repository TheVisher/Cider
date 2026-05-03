# Kanban Docs Governance Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring Cider's Kanban boards and docs under the new operating model: docs are durable foundation records, Kanban is the active work surface, and important Kanban outcomes are promoted into docs.

**Architecture:** Treat the cleanup as a governance pass with explicit inventories, reversible board movements, historical labels instead of deletion, and one durable Kanban feature doc. Use parallel read-only agents for independent board/doc clusters, then have one coordinator apply changes and commits in reviewed batches.

**Tech Stack:** Markdown docs, YAML Kanban boards in `/Users/minivish/CiderVault/.cider/boards/`, `cider-cli board list --json`, `cider-cli board show <board> --json`, Swift/Yams-aware caution for board edits, existing Cider docs IA.

---

## Working Rules

- Do not delete docs or cards in the first pass.
- Prefer "mark historical", "move to done", "merge into one card", or "link to source-of-truth doc" over removal.
- Use Kanban cards for task-local notes and test evidence.
- Use docs for durable product, architecture, UX, data-model, routing, QA, and agent-behavior decisions.
- When a card becomes durable doctrine, promote the durable summary into docs and leave the card as implementation/history.
- For YAML board edits, prefer supported CLI or structured parsing when available. If editing manually, rewrite the whole board file and preserve indentation.
- Only the coordinator mutates `/Users/minivish/CiderVault/.cider/boards/*.yaml`.
- Parallel agents produce findings, proposed diffs, file lists, risks, and open questions. They do not commit directly and do not move cards.
- Treat duplicate or overlapping Kanban cards as review candidates, not automatic closure proof. Before moving a card, verify the feature exists, the newer/fixed card truly covers the same behavior, and no manual QA requirement remains.
- Do not direct-edit Hermes memory files unless the agent has the proper Hermes memory tool or Erik explicitly approves direct edits.
- Preserve unrelated dirty repo changes:
  - `Sources/Cider/Views/AIAssistant/AIAssistantBubbleView.swift`
  - `Sources/Cider/Views/AIAssistant/AIAssistantPanelView.swift`
  - `Tests/CiderTests/RenderingConsistencyTests.swift`

## Current State

- Branch: `main`
- Local `main` is ahead of `origin/main`; push/merge status should be handled separately from this audit.
- Existing active audit card: `/Users/minivish/CiderVault/.cider/boards/a1b2c3.yaml`, card `2a41ec`, "Audit Kanban and docs foundation model".
- Boards:
  - `a1b2c3.yaml` - Cider Roadmap
  - `d4e5f6.yaml` - Cider Bugs
  - `p1l2m3.yaml` - Implementation Plans
  - `e7f8a9.yaml` - Kanban Implementation
  - `f0d730.yaml` - Vault Agent Work
- Docs inventory: 100 Markdown docs under `Docs/`, including 27 under `Docs/superpowers/`.

## Parallel Agent Strategy

Dispatch read-only explorers first, then let the coordinator apply reviewed changes.

- Agent A: Kanban board status audit.
  - Scope: `/Users/minivish/CiderVault/.cider/boards/*.yaml`
  - Output: card dispositions only; no edits.
- Agent B: Docs source-of-truth cluster audit.
  - Scope: `Docs/Features`, `Docs/Product`, `Docs/Architecture`, `Docs/Vault`, `Docs/superpowers`.
  - Output: canonical/historical/duplicate map; no edits.
- Agent C: Agent guidance consistency audit.
  - Scope: `AGENTS.md`, `CLAUDE.md`, `Docs/README.md`, `Docs/Conventions/DOCS_INFORMATION_ARCHITECTURE.md`, vault agent docs, Hermes skill references.
  - Output: contradictions and wording gaps; no edits.
- Coordinator:
  - Applies small, reviewed patches.
  - Is the only board YAML writer.
  - Is the only committer.
  - Updates the audit card after each batch.
  - Runs doc/board validation commands, including `board list` and `board show` for each touched board.

---

### Task 1: Normalize Agent Guidance Wording

**Files:**
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Modify: `Docs/README.md`
- Modify: `Docs/Conventions/DOCS_INFORMATION_ARCHITECTURE.md`
- Modify: `/Users/minivish/CiderVault/AGENTS.md`
- Modify: `/Users/minivish/CiderVault/.cider/memory/agent.md`
- Modify if present/relevant: `/Users/minivish/CiderVault/CLAUDE.md`
- Inspect, and update only if needed: `/Users/minivish/.hermes/skills/productivity/cider-vault-agent/SKILL.md`
- Inspect/report only unless proper Hermes memory tooling is available or Erik explicitly approves direct edits: `/Users/minivish/.hermes/memories/MEMORY.md`
- Inspect/report only unless proper Hermes memory tooling is available or Erik explicitly approves direct edits: `/Users/minivish/.hermes/memories/USER.md`

- [ ] **Step 1: Review current wording**

Run:

```bash
rg -n "Docs vs\\. Kanban|Kanban is first-class|Update Kanban boards|YAML board|Write tool|active work surface|durable foundation" \
  AGENTS.md CLAUDE.md Docs/README.md Docs/Conventions/DOCS_INFORMATION_ARCHITECTURE.md \
  /Users/minivish/CiderVault/AGENTS.md /Users/minivish/CiderVault/.cider/memory/agent.md \
  /Users/minivish/CiderVault/CLAUDE.md \
  /Users/minivish/.hermes/skills/productivity/cider-vault-agent/SKILL.md \
  /Users/minivish/.hermes/memories/MEMORY.md \
  /Users/minivish/.hermes/memories/USER.md
```

Expected: the model is present in most files, with minor wording conflicts around manual YAML edits, read-only audits, plans/specs, and QA evidence. Task 1 is a normalization/diff check, not a rewrite; keep existing good wording and patch only contradictions or gaps.

- [ ] **Step 2: Apply consistent wording**

Use this exact policy text, adapted to the local section:

```md
For read-only audits or quick inspections, do not move or create Kanban cards unless the user asks. For substantial implementation, bug fixing, or agreed follow-up work, use the relevant Kanban board.

Docs are Cider's durable foundation records: product vision, architecture, data models, UX principles, agent operating rules, routing doctrine, QA procedures, and big feature designs.

Kanban is Cider's active work surface: bugs, polish, ideas, implementation tasks, testing tasks, review findings, and handoff context.

Large implementation plans/specs may live under `Docs/superpowers/`, but active tracking should still live on a Kanban card. Link the card to the plan/spec, and promote only durable outcomes into Product, Architecture, Feature, Vault, QA, or Conventions docs.

Use Kanban cards for task-local test evidence and handoff notes. Use `Docs/QA/` for reusable audit procedures, release/regression plans, and historical reports that should remain useful after the card is done.

For YAML board edits, prefer supported CLI or structured YAML parsing when available. If editing manually, rewrite the whole board file and preserve indentation; avoid tiny indentation-sensitive patches.
```

- [ ] **Step 3: Verify no contradictions remain**

Run:

```bash
rg -n "Always use the Write tool|every start|every completion|create a Markdown doc for every|testing evidence" \
  AGENTS.md CLAUDE.md Docs/README.md Docs/Conventions/DOCS_INFORMATION_ARCHITECTURE.md \
  /Users/minivish/CiderVault/AGENTS.md /Users/minivish/CiderVault/.cider/memory/agent.md \
  /Users/minivish/CiderVault/CLAUDE.md
```

Expected: either no matches, or matches have nearby wording that clarifies scope.

- [ ] **Step 4: Commit repo docs only**

Coordinator only. Commit only repo files. Do not try to commit CiderVault or Hermes files because they may not be in this repo.

```bash
git add AGENTS.md CLAUDE.md Docs/README.md Docs/Conventions/DOCS_INFORMATION_ARCHITECTURE.md
git commit -m "docs: clarify kanban and docs governance"
```

---

### Task 2: Create the Kanban Foundation Feature Doc

**Files:**
- Create: `Docs/Features/Kanban/README.md`
- Create: `Docs/Features/Kanban/PRODUCT.md`
- Create: `Docs/Features/Kanban/ARCHITECTURE.md`
- Create: `Docs/Features/Kanban/DATA_MODEL.md`
- Create: `Docs/Features/Kanban/TESTING.md`
- Modify: `Docs/README.md`
- Modify: `Docs/Product/PRODUCT_VISION.md`
- Reference: `Docs/superpowers/plans/2026-05-03-kanban-first-class-detail-panel.md`
- Reference: `/Users/minivish/CiderVault/.cider/boards/e7f8a9.yaml`

- [ ] **Step 1: Create `Docs/Features/Kanban/README.md`**

Use:

```md
# Kanban

Kanban is both a Cider app feature and a Cider development workflow.

As an app feature, Kanban boards are views over actionable Cider work items. Cards can hold long-form briefs, implementation context, linked related items, metadata, and explicit Markdown exports.

As a development workflow, Kanban is the active coordination layer for Cider agents and humans. Docs hold durable truth; Kanban cards hold active work, status, and handoff context.

## Source Files

- `Docs/Features/Kanban/PRODUCT.md`
- `Docs/Features/Kanban/ARCHITECTURE.md`
- `Docs/Features/Kanban/DATA_MODEL.md`
- `Docs/Features/Kanban/TESTING.md`

## Active Boards

- `/Users/minivish/CiderVault/.cider/boards/a1b2c3.yaml` - Cider Roadmap
- `/Users/minivish/CiderVault/.cider/boards/d4e5f6.yaml` - Cider Bugs
- `/Users/minivish/CiderVault/.cider/boards/p1l2m3.yaml` - Implementation Plans
- `/Users/minivish/CiderVault/.cider/boards/e7f8a9.yaml` - Kanban Implementation
- `/Users/minivish/CiderVault/.cider/boards/f0d730.yaml` - Vault Agent Work
```

- [ ] **Step 2: Create `PRODUCT.md`**

Include these sections:

```md
# Kanban Product Model

## Purpose

Kanban gives Cider a lightweight work surface for ideas, bugs, implementation tasks, testing tasks, and agent handoffs.

## Product Principles

- Cards are active work records, not permanent product doctrine.
- Cards can hold deep notes so Cider does not create extra Markdown files for every working thought.
- Durable outcomes graduate into docs.
- Boards are one lens over Cider work, not a separate mini-app.
- Card detail uses the same slide-out detail pattern as other first-class Cider items.

## User Workflows

- Capture an idea from Hermes or chat.
- Refine the idea into a Kanban card.
- Add linked specs, notes, files, or related Cider items.
- Hand the card to Codex, Hermes, Claude, or manual work.
- Move it through active, testing, and done states.
- Export Markdown only when a portable copy is useful.
```

- [ ] **Step 3: Create `ARCHITECTURE.md`**

Include:

```md
# Kanban Architecture

## Storage

Kanban boards are YAML files in `/Users/minivish/CiderVault/.cider/boards/`. `KanbanStorage` owns board loading, mutation, and file watching.

## UI

`KanbanBoardView` renders board columns and compact cards. Selecting a card opens the shared slide-out detail shell through `CiderPanelView`.

## Detail Panel

Kanban detail uses `GenericItemDetailPanel`. The main area is long-form `Spec / Notes`; the metadata rail owns title, board/status, priority, color, agent, tags, linked items, actions, dates, and delete.

## Agent Workflow

Agents should update boards for substantial Cider work, but read-only audits should not mutate cards unless asked.
```

- [ ] **Step 4: Create `DATA_MODEL.md`**

Include:

```md
# Kanban Data Model

## Board

- `id`
- `board`
- `created`
- `columns`

## Column

- `id`
- `name`
- `is_done_column`
- `cards`

## Card

- `id`
- `title`
- `notes`
- `color`
- `priority`
- `agent`
- `tags`
- `linkedEntities`
- `created`
- `completed`

## YAML Rules

- Every card must have `created: 'YYYY-MM-DD'`.
- Quote dates with single quotes.
- Do not duplicate keys.
- Preserve indentation.
- Use structured parsing or whole-file rewrites for manual edits.

## Completion Semantics

Moving a card into a done column sets `completed`; moving it out clears or preserves completion according to `KanbanStorage` behavior and tests.
```

- [ ] **Step 5: Create `TESTING.md`**

Include:

```md
# Kanban Testing

## Regression Areas

- Board YAML loads after agent edits.
- Card click opens slide-out detail.
- Notes and metadata share one draft.
- Metadata changes do not overwrite notes.
- Status moves preserve notes and completion behavior.
- Markdown export includes current draft text.
- Delete clears selected detail state.
- Linked items persist on the card.
- Escape closes the detail panel without losing saved work.

## Commands

Run:

- `swift test --filter KanbanCardDraftTests`
- `swift test --filter KanbanCardMarkdownExporterTests`
- `swift test --filter KanbanCardCodableTests`
- `swift test --filter CiderDetailNavigationPolicyTests`
- `swift build`
```

- [ ] **Step 6: Link the feature folder from `Docs/README.md`**

Add Kanban to the feature docs list.

- [ ] **Step 7: Mark old Kanban sections as historical**

In `Docs/Product/PRODUCT_VISION.md`, add a short note above old Kanban content:

```md
> Status: historical product/roadmap context. The current Kanban source of truth lives in `Docs/Features/Kanban/` and the active board YAML files.
```

- [ ] **Step 8: Coordinator commit**

```bash
git add Docs/Features/Kanban Docs/README.md Docs/Product/PRODUCT_VISION.md
git commit -m "docs: add kanban feature foundation"
```

---

### Task 3: Roadmap Testing Column Cleanup

**Files:**
- Modify: `/Users/minivish/CiderVault/.cider/boards/a1b2c3.yaml`
- Reference: `Docs/Features/Kanban/TESTING.md`
- Reference: `Docs/Architecture/STORAGE.md`
- Reference: `Docs/Architecture/STORAGE_DOCTRINE.md`

- [ ] **Step 1: Classify Testing cards**

Review these cards:

- `t001` Image Cards
- `t002` oEmbed & Enrichment
- `t004` Image Drop on Bookmark
- `t005` Note Pinning & Tags
- `t006` Card UI Polish
- `t007` Kanban Escape Key
- `t008` File Watchers for Todos/Events/Contacts
- `v1b001` VaultBookmarkService Storage Rework
- `b1c011` Screen Capture Polish
- `f1a001` Folder Kanban View

Disposition:

- Close verified duplicates as done with a `completed: 'YYYY-MM-DD'` and a short note.
- Keep uncertain manual QA cards in Testing with sharper notes.
- Move vague polish cards back to Backlog if not currently actionable.

- [ ] **Step 2: Validate duplicate closures**

Use the existing evidence:

- `t001` overlaps done `bdf1a5`.
- `t002` overlaps done `bdf1a6` and fixed bugs `bug004`, `bug005`, `bug021`.
- `t004` overlaps fixed `bug001`.
- `t005` overlaps fixed `bug006`, `bug007`, `bug008`.
- `t006` overlaps fixed `bug009`, `bug010`, `bug014`, `bug017`, `bug019`.
- `t007` should be folded into Kanban regression coverage.

Overlap is a review signal, not closure proof. For each card, verify:

- the feature is actually present;
- the testing card is only asking for verification;
- the newer/fixed card covers the same behavior;
- no manual QA requirement remains.

- [ ] **Step 3: Apply YAML changes**

Use structured YAML parsing if available. If not, rewrite the whole board carefully. Preserve card IDs and add notes like:

```yaml
notes: 'Closed during Kanban/docs governance cleanup. Covered by shipped/fixed card <id> and current regression docs.'
completed: '2026-05-03'
```

- [ ] **Step 4: Validate board loads**

Run:

```bash
/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli board list --json
/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli board show 'Cider Roadmap' --json
```

Expected: board list prints all 5 boards without YAML parse errors, and `Cider Roadmap` renders the modified card structure as JSON.

- [ ] **Step 5: Commit only repo changes if any**

Board files are in CiderVault, not this repo. If no repo files changed, do not commit. Update the audit card notes instead.

---

### Task 4: Vault Agent Work Ready-to-Test Cleanup

**Files:**
- Modify: `/Users/minivish/CiderVault/.cider/boards/f0d730.yaml`
- Reference: `Docs/Architecture/TELEGRAM_AGENT_REGRESSION_SET.md`
- Reference: `Docs/Architecture/VAULT_AGENT_VISION.md`
- Reference: `Docs/Vault/CLAUDE-vault.md`
- Reference: `/Users/minivish/CiderVault/.cider/memory/agent.md`

- [ ] **Step 1: Group Ready-to-test cards**

Groups:

- Regression-set covered cards: `63e960`, `bb135a`, `c9c40c`, `a9f277`, `f0fe61`, `fac0e9`, `5fb490`
- Durable memory doctrine cards: `c8127f`, `573669`, `31f0fc`, `44a49f`, `60c106`
- Runtime logging cards: `8dbe66`, `bd73f6`, `1193d5`, `4250ad`
- Process card: `31a6f7`

- [ ] **Step 2: Promote durable process/doctrine**

Before moving cards, verify docs contain:

- regression cadence
- memory restraint and consolidation rules
- logging inspection workflow
- routing/query expected paths

Patch docs if the durable rule is missing.

- [ ] **Step 3: Move verified cards out of active Ready-to-test**

Move cards whose notes already say "Covered By" to Done if the referenced doc exists and still contains the coverage.

- [ ] **Step 4: Replace process card with doc/checklist**

Move `31a6f7` out of active flow after adding the regression cadence to `Docs/Architecture/TELEGRAM_AGENT_REGRESSION_SET.md` or `Docs/QA/AUDIT_LOOPS.md`.

- [ ] **Step 5: Validate board loads**

Run:

```bash
/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli board list --json
/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli board show 'Vault Agent Work' --json
```

Expected: all boards load, and `Vault Agent Work` renders the modified card structure as JSON.

---

### Task 5: Dashboard Docs Source-of-Truth Pass

**Files:**
- Canonical folder: `Docs/Features/Dashboard/`
- Mark historical: `Docs/Product/CIDER_DASHBOARD_SECOND_BRAIN_FEED.md`
- Mark historical: `Docs/superpowers/specs/2026-04-19-dashboard-design.md`
- Mark historical if implemented/superseded: `Docs/superpowers/specs/2026-05-02-dashboard-tabs-shared-design.md`
- Mark historical if implemented/superseded: `Docs/superpowers/plans/2026-05-02-cider-dashboard-shared-desktop-web-plan.md`

- [ ] **Step 1: Confirm canonical Dashboard folder is complete**

Run:

```bash
ls Docs/Features/Dashboard
```

Expected: `README.md`, `PRODUCT.md`, `ARCHITECTURE.md`, `DATA_MODEL.md`, `CLI.md`, `TESTING.md`, `DECISIONS.md`, `ROADMAP.md`.

- [ ] **Step 2: Add historical notes to superseded docs**

At the top of each superseded doc, add:

```md
> Status: historical design/implementation context. The current Dashboard source of truth lives in `Docs/Features/Dashboard/`.
```

- [ ] **Step 3: Promote any missing durable decision**

If a historical doc contains a durable decision not in `Docs/Features/Dashboard/DECISIONS.md`, add a concise bullet there.

- [ ] **Step 4: Coordinator commit**

```bash
git add Docs/Features/Dashboard Docs/Product/CIDER_DASHBOARD_SECOND_BRAIN_FEED.md Docs/superpowers/specs/2026-04-19-dashboard-design.md Docs/superpowers/specs/2026-05-02-dashboard-tabs-shared-design.md Docs/superpowers/plans/2026-05-02-cider-dashboard-shared-desktop-web-plan.md
git commit -m "docs: clarify dashboard source of truth"
```

---

### Task 6: MainBrain, AgentHost, and Hermes Docs Pass

**Files:**
- Canonical: `Docs/Features/MainBrain/`
- Canonical/future boundary: `Docs/Features/AgentHost/README.md`
- Review: `Docs/Architecture/AGENT_SERVICE.md`
- Review: `Docs/Architecture/MANAGED_AGENT_RUNTIME.md`
- Mark historical where superseded:
  - `Docs/Architecture/TELEGRAM_REMOTE_AGENT_PLAN.md`
  - `Docs/Architecture/TERMINAL_AGENT_HANDOFF_2026-04-13.md`
  - `Docs/Architecture/CODEX_HANDOFF_2026-04-14.md`
  - `Docs/Architecture/CODEX_TELEGRAM_HANDOFF_2026-04-14.md`
  - `Docs/Vault/Checkpoints/2026-05-02-cider-hermes-session-lineage-sync.md`
  - `Docs/superpowers/plans/2026-05-01-cider-main-brain-ai-surface.md`
  - `Docs/superpowers/plans/2026-05-02-cider-hermes-bridge-hardening.md`

- [ ] **Step 1: Identify current doctrine**

Canonical rule:

```md
Current direction: Cider should be a strong local-first client and context surface for Hermes/Codex-style agents, not a replacement runtime for every agent.
```

- [ ] **Step 2: Promote lineage/session durable model**

Ensure `Docs/Features/MainBrain/DATA_MODEL.md` or `ARCHITECTURE.md` contains:

- logical chat ID
- current Hermes session ID
- session lineage
- last synced cursor
- checkpoints

- [ ] **Step 3: Mark old handoffs/checkpoints historical**

Add:

```md
> Status: historical handoff/checkpoint. Current durable Main Brain and Hermes integration guidance lives in `Docs/Features/MainBrain/`.
```

- [ ] **Step 4: Coordinator commit**

```bash
git add Docs/Features/MainBrain Docs/Features/AgentHost/README.md Docs/Architecture/AGENT_SERVICE.md Docs/Architecture/MANAGED_AGENT_RUNTIME.md Docs/Architecture/TELEGRAM_REMOTE_AGENT_PLAN.md Docs/Architecture/TERMINAL_AGENT_HANDOFF_2026-04-13.md Docs/Architecture/CODEX_HANDOFF_2026-04-14.md Docs/Architecture/CODEX_TELEGRAM_HANDOFF_2026-04-14.md Docs/Vault/Checkpoints/2026-05-02-cider-hermes-session-lineage-sync.md Docs/superpowers/plans/2026-05-01-cider-main-brain-ai-surface.md Docs/superpowers/plans/2026-05-02-cider-hermes-bridge-hardening.md
git commit -m "docs: clarify main brain and agent source of truth"
```

---

### Task 7: Reminder and Life Assistant Source-of-Truth Pass

**Files:**
- Create: `Docs/Features/TodosReminders/README.md`
- Create: `Docs/Features/TodosReminders/ARCHITECTURE.md`
- Create: `Docs/Features/TodosReminders/DATA_MODEL.md`
- Create: `Docs/Features/TodosReminders/TESTING.md`
- Reference: `Docs/Product/CIDER_LIFE_ASSISTANT_VISION.md`
- Reference: `Docs/Product/CIDER_ADAPTIVE_ROADMAP.md`
- Reference: `Docs/superpowers/plans/2026-04-12-reminder-engine.md`
- Reference: `Docs/superpowers/specs/2026-04-26-update-reminder-design.md`
- Reference: `Docs/superpowers/plans/2026-04-26-update-reminder-plan.md`
- Board: `/Users/minivish/CiderVault/.cider/boards/p1l2m3.yaml`, card `plan004`
- Bug: `/Users/minivish/CiderVault/.cider/boards/d4e5f6.yaml`, card `0085e7`

- [ ] **Step 1: Create the feature folder**

Minimum durable model:

```md
# Todos and Reminders

Cider reminders are Cider-owned DateCard/Todo-driven workflows first. Apple Reminders or other external systems are bridges/fallbacks, not the source of truth.
```

- [ ] **Step 2: Promote durable decisions**

Include:

- DateCard/Todo as source of truth
- wake/reconciliation behavior
- notification/delivery expectations
- agent outbox/Telegram delivery limits
- manual testing requirements
- known gap: April 15, 2026 8:00 AM Telegram reminder did not fire

- [ ] **Step 3: Consolidate board tracking**

Keep one active reminder validation card. Link `plan004`, `0085e7`, and any Vault Agent reminder card in its notes.

- [ ] **Step 4: Coordinator commit**

```bash
git add Docs/Features/TodosReminders Docs/README.md Docs/Product/CIDER_LIFE_ASSISTANT_VISION.md Docs/Product/CIDER_ADAPTIVE_ROADMAP.md Docs/superpowers/plans/2026-04-12-reminder-engine.md Docs/superpowers/specs/2026-04-26-update-reminder-design.md Docs/superpowers/plans/2026-04-26-update-reminder-plan.md
git commit -m "docs: add reminders source of truth"
```

---

### Task 8: Storage and SQLite Docs Pass

**Files:**
- Canonical: `Docs/Architecture/STORAGE_DOCTRINE.md`
- Active cleanup plan: `Docs/Architecture/SIDECAR_RETIREMENT_PLAN.md`
- Review/section: `Docs/Architecture/STORAGE.md`
- Mark historical: `Docs/superpowers/specs/2026-04-09-sqlite-migration-design.md`
- Mark historical: `Docs/superpowers/plans/2026-04-09-sqlite-migration-plan.md`

- [ ] **Step 1: Make `STORAGE_DOCTRINE.md` clearly canonical**

Ensure it states:

- SQLite is canonical for structured metadata.
- Durable user-facing artifacts remain in the vault when appropriate.
- Indexes/sidecars are legacy/transitional unless explicitly listed.

- [ ] **Step 2: Section `STORAGE.md`**

Add a status note:

```md
> Status: mixed current and legacy storage reference. Current durable storage doctrine lives in `Docs/Architecture/STORAGE_DOCTRINE.md`; sidecar cleanup status lives in `Docs/Architecture/SIDECAR_RETIREMENT_PLAN.md`.
```

- [ ] **Step 3: Mark migration plans historical**

Add:

```md
> Status: historical migration plan. Current storage doctrine lives in `Docs/Architecture/STORAGE_DOCTRINE.md`.
```

- [ ] **Step 4: Coordinator commit**

```bash
git add Docs/Architecture/STORAGE_DOCTRINE.md Docs/Architecture/SIDECAR_RETIREMENT_PLAN.md Docs/Architecture/STORAGE.md Docs/superpowers/specs/2026-04-09-sqlite-migration-design.md Docs/superpowers/plans/2026-04-09-sqlite-migration-plan.md
git commit -m "docs: clarify storage doctrine"
```

---

### Task 9: Archive or Compress Completed Implementation Boards

**Files:**
- Modify: `/Users/minivish/CiderVault/.cider/boards/e7f8a9.yaml`
- Modify: `/Users/minivish/CiderVault/.cider/boards/d4e5f6.yaml`
- Reference: `Docs/Features/Kanban/`
- Reference: `Docs/QA/AUDIT_REPORTS.md` or release notes if used

- [ ] **Step 1: Decide archive policy**

Use one of these approaches:

- Conservative: keep cards in Done/Fixed but add top-level board notes if board schema supports it.
- Moderate: move old completed boards into `.trash` or an archive board only after user approval.
- Preferred first pass: keep history but reduce active noise by ensuring no old done/fixed cards appear in active columns.

- [ ] **Step 2: Compress Kanban Implementation board**

After `Docs/Features/Kanban/` exists, decide whether `e7f8a9.yaml` remains as historical implementation board or gets archived.

- [ ] **Step 3: Compress fixed bugs**

Do not delete fixed bugs. If they clutter active views, archive by release boundary after user approval.

- [ ] **Step 4: Validate board loads**

Run:

```bash
/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli board list --json
/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli board show 'Cider Roadmap' --json
/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli board show 'Kanban Implementation' --json
/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli board show 'Cider Bugs' --json
```

Expected: all boards load.

---

### Task 10: Final Audit Report and Board Update

**Files:**
- Create: `Docs/QA/KANBAN_DOCS_GOVERNANCE_AUDIT_2026-05-03.md`
- Modify: `/Users/minivish/CiderVault/.cider/boards/a1b2c3.yaml`, card `2a41ec`

- [ ] **Step 1: Write final audit report**

Include:

```md
# Kanban Docs Governance Audit - 2026-05-03

## Summary

## Boards Reviewed

## Cards Moved or Closed

## Docs Created

## Docs Marked Historical

## Durable Decisions Promoted

## Remaining Open Questions

## Follow-up Kanban Cards
```

- [ ] **Step 2: Update audit card**

Add concise final notes to card `2a41ec`:

```yaml
notes: 'Audit completed. See Docs/QA/KANBAN_DOCS_GOVERNANCE_AUDIT_2026-05-03.md. Major outcomes: Kanban feature docs created, stale testing cards cleaned up, docs clusters labeled canonical/historical, agent guidance normalized.'
completed: '2026-05-03'
```

- [ ] **Step 3: Validate docs and board**

Run:

```bash
find Docs -name '*.md' | wc -l
/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli board list --json
/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli board show 'Cider Roadmap' --json
/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli board show 'Vault Agent Work' --json
/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli board show 'Cider Bugs' --json
git status --short --branch
```

Expected:

- Markdown count is understandable and not inflated by stray one-off docs.
- Boards load.
- Repo status only contains intentional changes and the known unrelated AI/rendering dirty files if still present.

- [ ] **Step 4: Coordinator final commit**

```bash
git add Docs/QA/KANBAN_DOCS_GOVERNANCE_AUDIT_2026-05-03.md
git commit -m "docs: record kanban docs governance audit"
```

---

## Execution Order

Recommended order:

1. Task 1 - normalize guidance wording.
2. Task 2 - create Kanban feature foundation docs.
3. Task 3 - clean Roadmap Testing column.
4. Task 4 - clean Vault Agent Ready-to-test pile.
5. Task 8 - storage docs, because they affect `v1b001`.
6. Task 5 - Dashboard docs.
7. Task 6 - MainBrain/Agent/Hermes docs.
8. Task 7 - Reminder/Life Assistant docs.
9. Task 9 - archive/compress old implementation-history boards.
10. Task 10 - final report and audit card closure.

Parallelization:

- Agents can analyze Tasks 5, 6, 7, and 8 in parallel after Task 1 is complete, because they touch mostly disjoint doc clusters.
- Parallel agents should return proposed diffs, files touched, summaries, risks, and open questions. They should not commit directly.
- The coordinator applies doc-cluster patches sequentially, resolves wording consistency, and creates commits.
- One coordinator owns Tasks 3, 4, 9, and 10 because board YAML edits are shared state.
- Only the coordinator mutates `/Users/minivish/CiderVault/.cider/boards/*.yaml`.
- One coordinator reviews all doc cluster output for consistent historical labels and source-of-truth language.

## Acceptance Criteria

- Active Kanban columns contain current work, not stale duplicate history.
- `Docs/Features/Kanban/` exists and is linked from `Docs/README.md`.
- Dashboard, MainBrain/Agent, Reminders, Storage, and Kanban docs each have a clear source-of-truth location.
- Historical plans/specs/checkpoints are labeled as historical where superseded.
- Agent guidance consistently distinguishes docs from Kanban without tool-specific contradictions.
- Audit card `2a41ec` has final notes and is moved out of active work.
- `cider-cli board list --json` loads all boards.
- `cider-cli board show <touched board> --json` loads every board changed during the audit.
- Repo commits are grouped by logical doc/board governance batch.
- No parallel agent commits directly, and no unrelated dirty files are staged.
