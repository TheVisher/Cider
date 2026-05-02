# Cider Adaptive Roadmap

> Living roadmap for the Cider features Erik and Hermes keep discussing. This is intentionally adjustable: items can be added, reordered, split, paused, or promoted as the product direction changes.

**Created:** 2026-05-01
**Owner:** Erik + Hermes
**Status:** Active planning source

---

## Why this doc exists

Cider already has many product docs, plans, specs, and kanban cards. The problem is not lack of ideas — it is keeping direction clear while the product evolves.

This roadmap is the high-level steering layer:

- what we are focused on now
- what comes next
- what is intentionally later
- what should be revisited or reordered
- which docs/plans support each feature stream

This is not a rigid release contract. It is a living queue.

---

## Operating rules

0. **Agents check this first for product direction.** When Erik asks what to work on next, where a new Cider idea fits, or how to order feature work, start here before scattered specs/plans.
1. **Current focus stays visible.** Keep one primary focus and one secondary focus at the top.
2. **Reorder freely.** If Erik changes priorities, move the feature stream instead of creating another scattered doc.
3. **Do not mark complete without user testing/sign-off.** Agents can mark implementation/review/testing states, but Erik signs off on complete.
4. **Prefer report-only agents for maintenance.** Scheduled audits should suggest actions before mutating docs, vault data, email, calendar, or project state.
5. **Capture product lessons here, then split implementation plans out.** This doc decides priority; detailed builds belong in `Docs/superpowers/plans/` or dedicated specs.
6. **Keep Cider local-first and dashboard-first.** Cider should become the user's visual command center and second brain, with Telegram/CLI as lightweight remote surfaces.
7. **When docs drift, update or link them.** If a roadmap item contradicts another doc, note the conflict instead of letting both silently rot.

---

## Status legend

| Status | Meaning |
|---|---|
| `Now` | Active focus; should guide current work |
| `Next` | High-confidence next candidates |
| `Soon` | Important, but not after the current focus unless pulled up |
| `Later` | Valuable, but depends on foundation work or clearer shape |
| `Parked` | Keep the idea, but do not spend implementation time yet |
| `Shipped / Needs Sign-off` | Built or mostly built; needs Erik testing/sign-off |
| `Done` | Erik confirmed it is good |

---

## Current focus

### 1. Perfect the Cider / Hermes chat UI

**Status:** `Now`

**Why it matters:** This is the surface Erik is using right now to talk to Hermes. If this feels confusing, leaky, unreliable, or hard to resume, every other agent-powered feature feels worse.

**Direction:** Cider should become a clean vault-aware client over Hermes/agent sessions, not just a raw transcript viewer.

**Key outcomes:**

- clean user-facing chat output with minimal internal tool chatter
- stable session identity and resume behavior
- clear distinction between visible Cider chat and underlying Hermes session lineage
- good handling of compaction/new-session weirdness
- approvals/status/tool progress presented in a way normal users understand
- eventual `Cider Main Brain` chat as the default life/vault assistant thread

**Supporting docs:**

- `Docs/superpowers/plans/2026-04-29-main-panel-deprecation-smart-recall.md`
- `Docs/Architecture/TELEGRAM_REMOTE_AGENT_PLAN.md`
- `Docs/Architecture/AGENT_SERVICE.md`
- Cider-vault-agent skill references: `cider-main-brain-chat.md`, `telegram-checkpoint-protocol.md`

---

### 2. Establish this adaptive roadmap as the steering layer

**Status:** `Now`

**Why it matters:** Cider has many good ideas spread across docs, memories, kanban cards, and chat sessions. We need one adjustable map so the next feature choice is not lost in scattered notes.

**Key outcomes:**

- one place to add/reorder feature streams
- lightweight status and priority tracking
- links to detailed specs/plans instead of duplicating everything
- periodic review cadence: ask “what should move up/down?”
- future dashboard card that can show roadmap/project direction inside Cider

**Supporting docs:**

- `Docs/Product/PRODUCT_VISION.md`
- `Docs/superpowers/specs/2026-04-19-dashboard-design.md`
- `Docs/QA/AUDIT_LOOPS.md`

---

## Next candidates

### 3. Agent session continuity / Main Brain foundation

**Status:** `Next`

**Goal:** Make Cider's AI experience feel like one durable personal brain, even when Hermes sessions compact, fork, resume, or move across Telegram/CLI/Cider.

**Feature shape:**

- stable logical chat ID such as `cider.main`
- mapping from Cider chat to current Hermes session ID and continuation lineage
- read-only awareness of Hermes session history/lineage
- safe message serialization so multiple clients do not race
- clear UI when a session was resumed, compacted, or started fresh

**Why before bigger AI features:** If session continuity is shaky, doc audits, reminders, project agents, and life-assistant workflows will feel fragmented.

---

### 4. Dashboard command center v1

**Status:** `Next`

**Goal:** Turn Home/Dashboard into a high-signal command center instead of only a mixed-content feed.

**Panels/signals to include over time:**

- Vault Pulse
- Overview
- Needs Attention
- Recent Activity
- Today + Upcoming
- Resurface
- Pinned Projects
- Docs Health
- Inbox/Triage health
- Agent job summaries

**Near-term rule:** Start with a polished curated dashboard before building full customization.

**Supporting doc:** `Docs/superpowers/specs/2026-04-19-dashboard-design.md`

---

### 5. Report-only maintenance agents

**Status:** `Next`

**Goal:** Let Hermes/Cider periodically inspect things Erik forgets to maintain, without silently changing data.

**Streams:**

- Inbox triage suggestions
- Docs Health / doc-rot audit
- memory hygiene
- stale bugs / stale tasks
- project command center summaries
- weekly vault digest

**Current scheduled examples:**

- Daily Cider morning brief
- Daily inbox triage suggestions
- Weekly docs health digest
- Weekly Hermes memory hygiene audit

**Product direction:** These start as Hermes reports, then become dashboard cards inside Cider.

---

## Soon

### 6. Capture and import rails

**Status:** `Soon`

**Goal:** Make it easy for Erik and agents to get anything into Cider with the least possible friction.

**Likely pieces:**

- `cider ingest <url-or-text>`
- `cider import <path> --infer`
- file/image/GIF import rail
- quick note / scratchpad
- better short-link/social-link metadata handling
- canonical title cleanup and routing suggestions

**Why it matters:** Cider only works as a second brain if capture is fast and reliable.

---

### 7. Cider-owned reminders, todos, and resurfacing

**Status:** `Soon`

**Goal:** Cider should own contextual reminders and resurfacing instead of defaulting to Apple Reminders or another app.

**Likely pieces:**

- reminder/todo model polish
- natural-language reminder capture
- resurfacing rules
- forgotten item surfacing
- follow-up reminders from media, bookmarks, notes, and projects
- dashboard + notification surface

**Supporting docs:**

- `Docs/superpowers/plans/2026-04-12-reminder-engine.md`
- `Docs/superpowers/plans/2026-04-26-update-reminder-plan.md`
- `Docs/superpowers/specs/2026-04-26-update-reminder-design.md`

---

### 8. Project command centers

**Status:** `Soon`

**Goal:** Let Cider show project direction, bugs, docs health, agent runs, plans, and stale work as a visual dashboard.

**Initial target:** Cider itself.

**Feature shape:**

- project overview page/card
- active roadmap stream
- bugs / stale bugs
- docs health
- recent code/doc changes
- agent job summaries
- next recommended action

**Why it matters:** This solves the current pain: too many docs/plans/ideas, not enough direction.

---

## Later

### 9. Media memory and taste library

**Status:** `Later`

**Goal:** Turn the Markdown media-library pilot into a first-class Cider media/taste surface.

**Streams:**

- Games
- TV Shows
- Movies
- Books later
- recommendations and follow-up reminders
- ratings/reactions as taste signals

**Current pilot files:**

- `/Users/minivish/CiderVault/Media/Games/Games Library.md`
- `/Users/minivish/CiderVault/Media/TV Shows/TV Shows Library.md`
- `/Users/minivish/CiderVault/Media/Movies/Movies Library.md`

---

### 10. Knowledge graph / related items

**Status:** `Later`

**Goal:** Make Cider connect related bookmarks, notes, contacts, files, todos, and projects.

**Supporting docs:**

- `Docs/superpowers/plans/2026-04-30-related-items-linking.md`
- `Docs/superpowers/specs/2026-04-30-related-items-linking-design.md`

---

### 11. Universal metadata inspector

**Status:** `Later`

**Goal:** Let Erik inspect and understand all metadata Cider has for a thing, including agent-owned metadata, without exposing confusing internals by default.

**Supporting docs:**

- `Docs/superpowers/plans/2026-04-30-universal-metadata-inspector.md`
- `Docs/superpowers/specs/2026-04-30-universal-metadata-inspector-design.md`

---

### 12. Contact profile surface

**Status:** `Later`

**Goal:** Make people/contact entities useful as part of the second brain.

**Supporting docs:**

- `Docs/superpowers/plans/2026-04-30-contact-profile-surface.md`
- `Docs/superpowers/specs/2026-04-30-contact-profile-surface-design.md`

---

## Parked / revisit later

These are valuable but should not distract from chat, roadmap, dashboard, and capture foundations.

- Whiteboard / research canvas integration
- advanced web archival
- full customization dashboard engine
- public/social/community features
- fully standalone agent chat app outside Cider
- heavy project-management suite features that duplicate Linear/Notion

---

## Adjustment log

Use this section to capture major reorder decisions.

| Date | Change | Reason |
|---|---|---|
| 2026-05-01 | Created adaptive roadmap with chat UI, roadmap steering, Main Brain, dashboard, maintenance agents, capture rails, reminders/resurfacing, and project command centers as the first major streams. | Erik asked for a constantly adjustable roadmap for the features discussed with Hermes. |

---

## Next review prompt

When revisiting this roadmap, ask:

1. Is the Cider/Hermes chat UI good enough to stop being the primary focus?
2. What is the single next feature stream that would make Cider feel more useful this week?
3. Are any scheduled agent reports noisy, missing, or ready to become dashboard cards?
4. Which docs are stale enough that they should be merged, archived, or rewritten?
5. Should any `Later` item move to `Soon`, or any `Soon` item move down?
