# Dashboard Tabs Shared Design

> Status: historical implemented design context. The current Dashboard source of truth lives in `Docs/Features/Dashboard/`.

## Intent

Keep the current Cider Desktop Dashboard and extend it into a dashboard shell with multiple internal views. The current overview/daily brief becomes the `Main` view. New personal-dashboard topics such as tech news, sports, entertainment, and Cider projects become peer views inside the same Dashboard saved-view tab.

This preserves the dashboard Erik likes while adding a shared Desktop/Web-ready dashboard data model.

## Approach

Desktop remains the local-first source of truth. The first implementation adds dashboard models, vault JSON storage, sample data, and a Desktop MVP UI. Web remains schema-gated and must later consume the same model instead of creating a separate dashboard store.

The dashboard shell should be implemented as a new wrapper view rather than rewriting `HomeOverviewDashboardView`. That wrapper renders:

- `Main`: existing `HomeOverviewDashboardView`.
- one button per `DashboardTopic`: `DashboardBoardView` filtered to that topic.

## Data Contract

The canonical feature contract is `Shared/DASHBOARD.md`.

Key rules:

- persisted timestamps are numeric milliseconds since epoch,
- `ciderSyncId` is explicit and lowercased,
- topics, cards, feedback, action state, and runs are persisted,
- `DashboardRun` records provenance for manual/import/agent/cron batches, even though run history is not an MVP UI surface,
- soft delete fields exist from day one.

## Non-Goals

Do not touch the AI assistant panel, AI chat UI, or AI services. Do not add collectors, Hermes cron jobs, Convex dashboard schema, or Web dashboard UI in this worktree.

## Testing

Add model round-trip tests, storage persistence tests, and integration/build verification. The UI should be small and rely on the existing dashboard overview for the Main tab.
