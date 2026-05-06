# Cider Docs Information Architecture

**Purpose:** Keep Cider docs traceable, visual, and maintainable so ideas do not disappear into a sea of markdown.

This is the reusable structure Erik can apply across Cider and future apps.

---

## The Mental Model

Every doc should answer one question:

> **What shelf does this belong on, and what active source of truth should it update?**

Use this flow before creating or moving docs:

```text
New idea / code change / bug / agent output
        │
        ▼
Is it durable guidance or just work-in-progress?
        │
        ├─ Small/active work item
        │      ▼
        │   Cider Kanban card
        │      │
        │      └─ If it becomes durable, promote summary into Product / Architecture / Feature docs
        │
        ├─ Large work-in-progress implementation artifact
        │      ▼
        │   Docs/superpowers/plans/ or Docs/superpowers/specs/
        │      │
        │      └─ If it becomes durable, promote summary into Product / Architecture / Feature docs
        │
        └─ Durable knowledge
               ▼
        Is it app-wide, feature-specific, or process-specific?
               │
               ├─ Product direction       → Docs/Product/
               ├─ System design           → Docs/Architecture/
               ├─ Feature behavior        → Docs/Features/<Feature>/
               ├─ Vault/domain rules      → Docs/Vault/
               ├─ Quality/testing reports → Docs/QA/
               ├─ Team/agent conventions  → Docs/Conventions/
               └─ Old but worth keeping   → Docs/Archive/
```

---

## The Shelf System

### Docs vs. Kanban

Docs are the bookshelf: durable foundation records for product vision, architecture, data models, UX principles, agent operating rules, routing doctrine, and big feature designs.

Kanban is the workbench: active smaller tweaks, bugs, follow-up ideas, implementation tasks, testing tasks, code review findings, commit notes, and handoff history. A card can carry enough context for another agent to continue, but it is not the long-term source of truth for durable doctrine.

Backlink rule: cards that affect a feature should link back to the relevant canonical feature docs folder or section, e.g. `Docs/Features/Kanban/`. This gives agents a stable place to find current product/architecture/data-model/testing context before acting.

Promotion rule: when a Kanban item changes Cider's lasting behavior or principles, move the durable summary into the appropriate Product, Architecture, Feature, Vault, QA, or Conventions doc before treating the work as fully settled.

Large implementation plans/specs may live under `Docs/superpowers/`, but active tracking should still live on a Kanban card. Link the card to the plan/spec, and promote only durable outcomes into Product, Architecture, Feature, Vault, QA, or Conventions docs.

Use Kanban cards for task-local test evidence and handoff notes. Use `Docs/QA/` for reusable audit procedures, release/regression plans, and historical reports that should remain useful after the card is done. Future archived cards may be discoverable from their relevant feature area, but archived card history should not bloat the canonical docs.

### 1. Product shelf: `Docs/Product/`

Use for *why* and *what matters*.

Examples:
- product vision
- roadmap
- UX direction
- user value
- high-level decisions

**Default source of truth:** `Docs/Product/CIDER_ADAPTIVE_ROADMAP.md`

### 2. Architecture shelf: `Docs/Architecture/`

Use for *how the system is shaped*.

Examples:
- local-first architecture
- storage doctrine
- agent runtime
- sync/service boundaries
- major engineering tradeoffs

### 3. Feature shelf: `Docs/Features/<Feature>/`

Use for *how one feature works and evolves*.

Every major feature should eventually have this shape:

```text
Docs/Features/<Feature>/
├── README.md        # Start here: what it is, current status, code map
├── PRODUCT.md       # UX/product behavior and user stories
├── ARCHITECTURE.md  # implementation shape and important flows
├── DATA_MODEL.md    # persisted structures, schemas, JSON, tables
├── CLI.md           # commands and agent-facing usage
├── TESTING.md       # test commands, coverage, regression checklist
├── ROADMAP.md       # feature-specific next steps
└── DECISIONS.md     # dated decisions and why
```

Not every feature needs every file. But every feature needs at least `README.md` once it becomes important.

### 4. Plan/spec shelf: `Docs/superpowers/`

Use for agent-generated build artifacts.

These are allowed to be messy and timestamped because they are work products, not the bookshelf.

Rule:
- Plans/specs can contain ideas.
- Durable ideas must be promoted into Product / Architecture / Feature docs.
- The original plan/spec can remain as history.

### 5. QA shelf: `Docs/QA/`

Use for verification and confidence.

Examples:
- audit loops
- release checklist
- regression reports
- reusable bug verification notes

### 6. Conventions shelf: `Docs/Conventions/`

Use for reusable rules that apply across the repo or across apps.

Examples:
- docs IA
- coding conventions
- code health rules
- agent behavior rules

### 7. Archive shelf: `Docs/Archive/`

Use for docs that should be kept but are no longer active guidance.

Never archive silently. The Doc Control Agent should propose archive candidates first.

---

## Feature README Standard

Every `Docs/Features/<Feature>/README.md` should include these sections in this order:

```markdown
# <Feature Name>

**Status:** Proposed | Active | Shipping | Stable | Deprecated
**Owner surface:** Desktop | Web | CLI | Vault | Agent | Mobile
**Source of truth:** one sentence

## Visual Map

A simple flow or component map.

## What This Feature Does

Plain-English description.

## Current Code Map

- `Sources/...` — what lives here
- `Tests/...` — relevant tests
- `Docs/...` — related docs

## User Flows

1. User does X
2. System does Y
3. Data lands in Z

## Maintenance Rules

- When code changes here, update these docs.
- When tests change here, update testing notes.

## Related Docs

- links
```

---

## Doc Lifecycle

Use this lifecycle to prevent idea loss:

```text
Capture → Triage → Promote → Maintain → Archive
```

### Capture

Put rough ideas where they are easiest to capture:
- Telegram/Cider chat
- inbox notes
- agent plans/specs
- checkpoints

### Triage

Ask:
- Is this temporary or durable?
- Which feature or product area owns it?
- Does an existing doc need updating?

### Promote

Move the durable summary into the right source-of-truth doc.

Do not just move raw messy notes unless they are intentionally historical.

### Maintain

Doc Control Agent checks whether code, tests, roadmap, and docs have drifted.

### Archive

If a doc is no longer active guidance, propose moving it to `Docs/Archive/` with a replacement link.

---

## Naming Rules

Use consistent names:

- Feature folders: `PascalCase` or clear compound names, e.g. `MainBrain`, `AgentHost`, `SearchRecall`.
- Standard feature files: uppercase role names: `README.md`, `ARCHITECTURE.md`, `DATA_MODEL.md`, `CLI.md`, `TESTING.md`, `ROADMAP.md`, `DECISIONS.md`.
- Historical plans/specs: keep timestamp prefix.
- Checkpoints: keep date prefix.

---

## Maintenance Checklist for Agents

Before creating a new doc:

1. Read `Docs/README.md`.
2. Search for an existing feature folder.
3. Search Product and Architecture docs for an existing source of truth.
4. If creating a new doc, add it to the relevant README/index.
5. If promoting from a plan/spec, link back to the original artifact.
6. If uncertain above ~10%, ask Erik instead of guessing.

Before moving/archiving docs:

1. Produce a proposed move map.
2. Explain what becomes the new source of truth.
3. Preserve backlinks or replacement links.
4. Ask Erik for approval.

---

## Visual Aid

Open this visual map in a browser:

`Docs/Visuals/cider-docs-map.html`
