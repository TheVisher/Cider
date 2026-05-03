# Cider Doc Control Agent

**Created:** 2026-05-02  
**Owner:** Erik + Hermes  
**Status:** Product / operating model proposal

---

## Problem

Cider has many useful docs, specs, plans, checkpoints, and handoffs, but the docs are becoming hard to trust because they are spread across broad folders and older ideas can silently drift from the code.

The goal is not “more docs.” The goal is a system where Cider documentation stays useful for both Erik and agents:

- agents can quickly find the right source of truth
- new docs land in predictable locations
- feature docs are grouped by component/feature area
- stale docs are detected instead of silently rotting
- code structure and docs structure are periodically compared
- drift is reported before agents rewrite or reorganize anything

---

## Proposed Docs Shape

Use `Docs/` as the top-level documentation hub, with a small table of contents/router at the root and feature/component folders underneath.

```text
Docs/
├── README.md                         # Table of contents + routing rules for agents
├── Product/                          # Product vision, adaptive roadmap, high-level strategy
├── Architecture/                     # Cross-cutting architecture and system doctrine
├── Features/                         # Feature/component docs, grouped by area
│   ├── Dashboard/
│   ├── MainBrain/
│   ├── AgentHost/
│   ├── Bookmarks/
│   ├── Notes/
│   ├── TodosReminders/
│   ├── CalendarEvents/
│   ├── Contacts/
│   ├── Files/
│   ├── SearchRecall/
│   ├── CLI/
│   └── Vault/
├── Plans/                            # Active implementation plans, if promoted out of superpowers
├── Specs/                            # Durable design specs, if promoted out of superpowers
├── QA/                               # Audit reports, release checks, regression sets
├── Conventions/                      # Coding/doc conventions and troubleshooting
├── Design/                           # Visual/product design system
└── Archive/                          # Superseded docs retained for context
```

The current `Docs/superpowers/plans/` and `Docs/superpowers/specs/` can remain as agent-generated implementation artifacts, but durable feature knowledge should eventually be summarized or promoted into the relevant `Docs/Features/<Feature>/` folder.

---

## Docs Root README / Router

`Docs/README.md` should tell agents:

1. where to look first
2. where to place new docs
3. which docs are source-of-truth vs historical
4. how to decide when to update, merge, archive, or create a doc
5. which feature folder maps to which source-code paths

The root README should not become a giant manual. It should be a routing layer.

---

## Feature Folder Contract

Each major feature/component folder should eventually contain a small set of predictable files:

```text
Docs/Features/Dashboard/
├── README.md             # Feature overview and source-of-truth index
├── PRODUCT.md            # User-facing product intent and use cases
├── DATA_MODEL.md         # Data structures, storage files, schema notes
├── ARCHITECTURE.md       # Services, views, dependencies, boundaries
├── CLI.md                # CLI commands that affect this feature
├── TESTING.md            # Important tests and verification commands
├── ROADMAP.md            # Feature-specific next steps
└── DECISIONS.md          # Major decisions and reversals
```

Not every feature needs every file on day one. Start with `README.md`, then split when a file gets too large or mixed.

---

## Code ↔ Docs Mapping

The doc control system should maintain a mapping between code areas and doc areas.

Example:

```text
Sources/Cider/Models/Dashboard/       -> Docs/Features/Dashboard/DATA_MODEL.md
Sources/Cider/Services/Dashboard/     -> Docs/Features/Dashboard/ARCHITECTURE.md
Sources/Cider/Views/Dashboard/        -> Docs/Features/Dashboard/README.md or PRODUCT.md
Sources/CiderCLI/*Dashboard*          -> Docs/Features/Dashboard/CLI.md
Tests/CiderTests/Dashboard*           -> Docs/Features/Dashboard/TESTING.md
```

This mapping lets an agent ask:

- “Code changed here. Which docs probably need review?”
- “This doc claims X. Does the current code still do X?”
- “This feature has code but no docs.”
- “This doc exists, but the referenced files moved or disappeared.”

---

## Persistent Doc Control Agent

A persistent agent is a good fit, as long as it starts in **report-only mode**.

This should not be a one-off delegated subagent. It should behave like a recurring Cider maintenance agent whose single job is documentation control.

### Responsibilities

The Doc Control Agent should periodically:

1. scan doc structure
2. scan source-code structure
3. compare feature folders against source folders
4. detect orphan docs, stale docs, missing docs, and duplicated/contradictory docs
5. inspect recent git diffs for code changes that should update docs
6. write a report showing what changed and what docs likely need action
7. optionally create dashboard cards for high-priority doc drift
8. ask for approval before moving, merging, archiving, or rewriting docs

### Non-goals at first

The agent should not initially:

- auto-delete docs
- auto-move large numbers of files
- rewrite product direction without Erik approval
- mark roadmap items complete without Erik testing/sign-off
- treat old docs as wrong just because they are old

### Report shape

A recurring report should include:

```text
Doc Control Report
- Summary
- New code areas with no docs
- Docs that reference missing/renamed files
- Recently changed code with likely stale docs
- Duplicate/conflicting docs
- Suggested moves/merges/archives
- Suggested roadmap updates
- Proposed dashboard cards
- Approval checklist
```

---

## Implementation Options

### Option A: Hermes cron job

Use a scheduled Hermes job to run weekly or daily in report-only mode.

Best near-term option because it already exists.

### Option B: Cider dashboard collector

Create a Cider-side collector that emits Docs Health cards into the dashboard.

Good once dashboard runs/cards are first-class.

### Option C: Dedicated local service / Agent Host worker

Long-term ideal: the Agent Host owns recurring project maintenance jobs, including docs health, and broadcasts results to Cider, Telegram, or mobile.

---

## Recommended MVP

1. Create `Docs/README.md` as the docs router.
2. Create the first feature folder: `Docs/Features/Dashboard/`.
3. Move or summarize durable dashboard docs into that folder, without deleting historical plans/specs.
4. Add `Docs/Features/MainBrain/` and `Docs/Features/AgentHost/` next.
5. Create a report-only weekly Doc Control Agent.
6. Have the report produce suggested actions and dashboard cards, not direct mutations.
7. Once stable, let the agent perform approved moves/patches one item at a time.

---

## Why this matters for Cider

Cider itself is becoming a second brain. If Cider’s own docs are messy, agents will make worse decisions and Erik will keep losing the thread.

A Doc Control Agent turns Cider into its own first serious customer:

- Cider uses a dashboard to surface project/doc drift
- Cider uses agents to maintain its own knowledge base
- Cider uses local-first storage and approval flows
- Cider learns from the same organization problems it is designed to solve for Erik
