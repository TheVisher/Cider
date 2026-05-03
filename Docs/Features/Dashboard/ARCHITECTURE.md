# Dashboard Architecture

**Status:** Durable architecture source of truth for the Dashboard feature.

---

## Current Shape

```text
Shared/DASHBOARD.md
        │
        ▼
Swift Dashboard Models
        │
        ▼
DashboardStorage
        │
        ▼
.cider/dashboard/_cider_dashboard.json
        │
        ▼
DashboardHubView
        ├── Main → HomeOverviewDashboardView
        └── Topic → DashboardBoardView → DashboardCardView
```

---

## Boundaries

Dashboard is a Cider product/data surface, **not** the AI assistant panel.

Avoid touching:

- `Sources/Cider/Views/AIAssistant/**`
- `Sources/Cider/ViewModels/AIAssistantViewModel.swift`
- `Sources/Cider/Services/AI/**`
- `Sources/Cider/App/AppDelegate+AIAssistantPanel.swift`

---

## Source of Truth

Desktop/vault is the source of truth for the MVP.

Persistence:

```text
~/CiderVault/.cider/dashboard/_cider_dashboard.json
```

The first MVP uses one JSON snapshot for simplicity and traceability. If card volume grows, a later migration can move to per-card files or SQLite.

---

## UI Composition

`DashboardHubView` is the shell.

It renders:

- `Main`: existing `HomeOverviewDashboardView`
- topic buttons from `DashboardTopic`
- `DashboardBoardView` for topic-filtered cards

The current overview dashboard must stay intact and remain the first view.

---

## Data Flow

```text
DashboardStorage.load()
        │
        ▼
DashboardSnapshot
        │
        ├─ topics → DashboardTopicTabsView
        └─ cards  → DashboardBoardView filter/sort
                         │
                         ▼
                   DashboardCardView actions
                         │
                         ▼
              DashboardStorage mutation + persist()
```

Visible cards exclude:

- `deleted == true`
- `status == dismissed`
- `status == archived`

Sorting favors:

1. new cards
2. higher priority
3. newer updates

---

## Agent / CLI Boundary

Agents should mutate dashboard data through CLI/storage flows, not by directly editing `_cider_dashboard.json`.

Agent-safe path:

```text
Agent/report → cider-cli dashboard ... → DashboardStorage-compatible JSON → vault snapshot
```

---

## Web / Sync Boundary

Web must not create a separate dashboard model.

Before Web work:

1. Write a dashboard sync schema-gate note.
2. Decide whether Web can create cards or only mutate status/feedback.
3. Decide whether dashboard joins existing sync or uses direct Convex tables.
4. Update `Shared/DASHBOARD.md` if the contract changes.

---

## Future Collectors

Collectors should follow this pipeline:

```text
collect signals → generate candidates → score/rank → explain why → write cards → learn from feedback
```

Early collectors should be report-only or reversible.
