# Dashboard

Cross-platform contract for Cider's personal dashboard. This feature is a Cider product surface, not an AI assistant panel.

## Product Shape

The existing Desktop `Dashboard` saved-view tab remains the entry point. Inside that tab, Cider shows a dashboard shell with multiple dashboard views:

- `Main`: the current Desktop overview/daily brief dashboard.
- Curated topic views such as `Tech News`, `Sports`, `Entertainment`, and `Cider Projects`.

Desktop is the first implementation and the local-first source of truth. Cider Web should later render and mutate the same dashboard data after a Convex schema review. Web must not create a separate browser-only dashboard model.

## Identity and Time

- `ciderSyncId` is always a lowercase UUID string.
- Swift models may keep a local `UUID` `id`, but the persisted `ciderSyncId` must be explicit and must default to `id.uuidString.lowercased()`.
- All persisted dashboard timestamps are milliseconds since epoch as numbers, matching the shared cross-platform rule in `CORE_SPEC.md`.
- Soft delete uses `deleted: true` and `deletedAt`. Dashboard code should not hard-delete cards, topics, or runs in the first implementation.

## DashboardTopic

Represents a curated dashboard view inside the Dashboard tab.

```typescript
type DashboardTopic = {
  ciderSyncId: string;
  title: string;
  icon?: string;
  colorToken?: string;
  position: number;
  isPinned?: boolean;
  isArchived?: boolean;
  createdAt: number;
  updatedAt: number;
  deleted?: boolean;
  deletedAt?: number;
};
```

## DashboardCard

Represents one dashboard item. A card may belong to multiple topics.

```typescript
type DashboardCard = {
  ciderSyncId: string;
  topicSyncIds: string[];

  title: string;
  subtitle?: string;
  summary: string;
  whyItMatters?: string;

  sourceKind: "url" | "bookmark" | "note" | "todo" | "event" | "project" | "board" | "repo" | "manual" | string;
  sourceURL?: string;
  sourceTitle?: string;
  relatedItemSyncId?: string;
  relatedItemType?: string;

  status: "new" | "seen" | "saved" | "dismissed" | "reminded" | "archived" | string;
  priority: "low" | "normal" | "high" | "urgent" | string;
  score?: number;

  feedback?: DashboardCardFeedback;
  actionState?: DashboardCardActionState;

  createdAt: number;
  updatedAt: number;
  lastSeenAt?: number;
  dismissedAt?: number;
  deleted?: boolean;
  deletedAt?: number;
};
```

`summary` and `whyItMatters` may be generated later. `feedback.note` is user-owned and must not be overwritten by generation.

## DashboardCardFeedback

```typescript
type DashboardCardFeedback = {
  rating?: number;
  moreLikeThis?: boolean;
  lessLikeThis?: boolean;
  notInterested?: boolean;
  note?: string;
  updatedAt: number;
};
```

Ratings are clamped to `1...5`. `moreLikeThis`, `lessLikeThis`, and `notInterested` are feedback signals, not destructive actions.

## DashboardCardActionState

Tracks side effects created from a dashboard card.

```typescript
type DashboardCardActionState = {
  savedBookmarkSyncId?: string;
  savedMemorySyncId?: string;
  createdTodoSyncId?: string;
  createdEventSyncId?: string;
  reminderSyncId?: string;
  lastActionAt?: number;
};
```

The first Desktop MVP only needs open-source, seen, dismiss, and rating actions. Cross-entity actions should update this object when implemented.

## DashboardRun

Represents one batch that produced or imported dashboard cards. It is useful even before automated collectors exist because it gives future agents, imports, and cron jobs a place to record provenance.

```typescript
type DashboardRun = {
  ciderSyncId: string;
  source: "manual" | "agent" | "cron" | "import" | string;
  startedAt: number;
  finishedAt?: number;
  topicSyncIds: string[];
  cardSyncIds: string[];
  status: "running" | "completed" | "failed" | string;
  errorMessage?: string;
};
```

The first implementation should store runs in the snapshot and include model tests, but it does not need to render run history in the UI.

## Desktop Persistence

Desktop stores one snapshot:

```text
~/CiderVault/.cider/dashboard/_cider_dashboard.json
```

Shape:

```json
{
  "schemaVersion": 1,
  "topics": [],
  "cards": [],
  "runs": [],
  "updatedAt": 1777708800000
}
```

Missing files load as an empty dashboard. Invalid JSON logs an error and keeps an empty safe state.

## Desktop UI

Desktop renders the dashboard as a tabbed shell:

- Main button: existing `HomeOverviewDashboardView`.
- Topic buttons: user-configurable `DashboardTopic` views rendered by `DashboardBoardView`.

The current overview dashboard must not be deleted or visually demoted. It is the first dashboard view.

## Web and Sync Gate

Dashboard sync is future work. Before changing `../Cider-Web/convex/schema.ts`, write and approve a schema-gate note that answers:

- whether dashboard data joins existing `sync:push` / `sync:pull`,
- whether Web can create cards or only mutate status/feedback,
- which fields are Desktop-write-only,
- whether `DashboardRun` syncs in the first Web pass.
