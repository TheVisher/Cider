# Dashboard

**Status:** Active / MVP in progress  
**Owner surface:** Desktop first; Web/mobile later after sync/schema gates  
**Source of truth:** This feature folder is the durable source of truth for Dashboard behavior. Historical product docs and plans remain linked below.

---

## Visual Map

Open the browser visual:

`Docs/Features/Dashboard/VISUAL_MAP.html`

Quick text version:

```text
Erik / Agent / Collector
        │
        ▼
Dashboard Card Candidate
        │
        ▼
Personal relevance check
        │
        ├─ generic / no reason → do not show
        │
        └─ timely / personal / actionable / resurfacing / discovery / maintenance
                │
                ▼
        DashboardSnapshot JSON
        .cider/dashboard/_cider_dashboard.json
                │
                ▼
        DashboardHubView
        ├─ Main → existing HomeOverviewDashboardView
        └─ Topic tabs → DashboardBoardView
                │
                ▼
        User actions
        seen / dismiss / rate / more-like-this / less-like-this / open source
                │
                ▼
        Future: save as bookmark / note / todo / event / reminder / memory
```

---

## What This Feature Does

Dashboard is Cider's personalized second-brain feed and command center.

It should help Erik:

- curate the vault
- remember things he would otherwise forget
- resurface timely items from bookmarks, notes, projects, todos, events, media, and conversations
- expand on topics he already cares about
- discover similar items based on vault contents and taste signals
- see focused updates on teams, games, movies, shows, products, projects, and interests
- route cards into Cider objects or actions

The dashboard is **not generic news**. It is:

```text
personal context resurfacing + curated discovery + action routing
```

---

## Current Code Map

### Models

- `Sources/Cider/Models/Dashboard/DashboardSnapshot.swift` — top-level persisted snapshot
- `Sources/Cider/Models/Dashboard/DashboardTopic.swift` — user-facing dashboard lanes/tabs
- `Sources/Cider/Models/Dashboard/DashboardCard.swift` — individual cards plus feedback/action state
- `Sources/Cider/Models/Dashboard/DashboardRun.swift` — provenance for manual/import/agent/cron batches
- `Sources/Cider/Models/Dashboard/DashboardEnums.swift` — status/source/priority/run enums

### Storage

- `Sources/Cider/Services/Dashboard/DashboardStorage.swift` — local-first JSON load/save and mutations
- `Sources/Cider/Services/Dashboard/DashboardSeedData.swift` — explicit preview/test seed data helper
- Vault file: `.cider/dashboard/_cider_dashboard.json`

### Desktop UI

- `Sources/Cider/Views/Dashboard/DashboardHubView.swift` — dashboard shell; Main + topic tabs
- `Sources/Cider/Views/Dashboard/DashboardTopicTabsView.swift` — topic switcher
- `Sources/Cider/Views/Dashboard/DashboardBoardView.swift` — topic board
- `Sources/Cider/Views/Dashboard/DashboardCardView.swift` — card UI/actions
- `Sources/Cider/Views/Dashboard/DashboardEmptyStateView.swift` — empty state
- `Sources/Cider/Views/Home/HomeOverviewDashboardView.swift` — current Main overview dashboard

### CLI / Agents

- `Sources/CiderCLI/DashboardCLIModels.swift` — dashboard card upsert payloads
- `Sources/CiderCLI/CiderCLI.swift` — `dashboard` / `dash` command routing
- `Sources/CiderCLI/JSONOutput.swift` — JSON output helpers

### Tests

- `Tests/CiderTests/DashboardModelTests.swift`
- `Tests/CiderTests/DashboardStorageTests.swift`
- `Tests/CiderTests/DashboardSavedViewKindTests.swift`

### Shared Contract

- `Shared/DASHBOARD.md` — cross-platform dashboard contract

---

## User Flows

### Main dashboard orientation

1. Erik opens the Dashboard saved-view tab.
2. Cider renders `DashboardHubView`.
3. The `Main` tab shows the existing `HomeOverviewDashboardView`.
4. Erik gets a vault overview without switching into topic cards.

### Topic card review

1. Erik opens Dashboard.
2. Erik selects a topic such as Sports, Cider Projects, Entertainment, Games, or Tech News.
3. `DashboardBoardView` filters cards by `topicSyncIds`.
4. Cards are sorted by newness, priority, and update time.
5. Erik can mark seen, dismiss, rate, choose more/less like this, or open the source URL.

### Agent-generated maintenance card, future

1. A report-only agent finds stale docs, broken references, or an unfinished project.
2. The agent proposes or writes a dashboard card only through approved CLI/storage flows.
3. The card explains why it matters and points to exact paths.
4. Erik reviews it from Dashboard and chooses the next action.

---

## Card Quality Rules

A dashboard card should be shown only when at least one of these is true:

1. **Timely:** something is happening now or soon.
2. **Personal:** it matches a known interest, team, project, media taste, bookmark, note, or conversation signal.
3. **Actionable:** Erik can save, watch, play, read, reply, plan, triage, or dismiss it.
4. **Resurfacing:** it brings back something useful from the vault at the right time.
5. **Discovery:** it is similar to something Erik likes or saved, with a clear reason.
6. **Maintenance:** it highlights stale, broken, messy, or unfinished Cider/vault/project work.

Avoid cards that are:

- generic trending news
- generic AI/productivity slop
- low-context headlines
- unsourced rumors
- repeated cards with no new information
- content that cannot explain why it matched Erik

---

## Maintenance Rules

- When Dashboard persisted fields change, update `DATA_MODEL.md` and `Shared/DASHBOARD.md`.
- When Desktop view composition changes, update `ARCHITECTURE.md` and this README.
- When CLI commands change, update `CLI.md`.
- When tests change, update `TESTING.md`.
- When product behavior changes, update `PRODUCT.md`.
- When a key product/technical decision is made, append `DECISIONS.md`.
- Keep historical plans/specs linked; do not bulk-move or archive them without Erik approval.

---

## Related Docs

Durable docs:

- `Docs/Features/Dashboard/PRODUCT.md`
- `Docs/Features/Dashboard/ARCHITECTURE.md`
- `Docs/Features/Dashboard/DATA_MODEL.md`
- `Docs/Features/Dashboard/CLI.md`
- `Docs/Features/Dashboard/TESTING.md`
- `Docs/Features/Dashboard/ROADMAP.md`
- `Docs/Features/Dashboard/DECISIONS.md`
- `Shared/DASHBOARD.md`

Historical/source docs:

- `Docs/Product/CIDER_DASHBOARD_SECOND_BRAIN_FEED.md`
- `Docs/superpowers/specs/2026-04-19-dashboard-design.md`
- `Docs/superpowers/specs/2026-05-02-dashboard-tabs-shared-design.md`
- `Docs/superpowers/plans/2026-05-02-cider-dashboard-shared-desktop-web-plan.md`
