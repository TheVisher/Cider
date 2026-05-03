# Dashboard Data Model

**Status:** Durable schema/source-of-truth companion to `Shared/DASHBOARD.md`.

---

## Persisted Snapshot

Dashboard state is stored as a local-first snapshot:

```text
DashboardSnapshot
├── schemaVersion
├── topics: [DashboardTopic]
├── cards: [DashboardCard]
├── runs: [DashboardRun]
└── updatedAt
```

Current file:

```text
~/CiderVault/.cider/dashboard/_cider_dashboard.json
```

---

## Identity and Time Rules

- `ciderSyncId` is explicit and lowercased.
- Persisted timestamps are numeric milliseconds since epoch.
- Soft delete uses `deleted` and `deletedAt`.
- Unknown/future enum values should decode safely where practical.

---

## DashboardTopic

A topic is a user-facing lane/tab.

Fields:

- `ciderSyncId`
- `title`
- `icon`
- `colorToken`
- `position`
- `isPinned`
- `isArchived`
- `createdAt`
- `updatedAt`
- `deleted`
- `deletedAt`

Examples:

- Tech News
- Sports
- Cider Projects
- Entertainment
- Games

---

## DashboardCard

A card is a surfaced item. A card may belong to multiple topics.

Key fields:

- content: `title`, `subtitle`, `summary`, `whyItMatters`
- source: `sourceKind`, `sourceTitle`, `sourceURL`
- routing: `topicSyncIds`
- ranking: `priority`, `score`
- lifecycle: `status`, `createdAt`, `updatedAt`, `lastSeenAt`, `dismissedAt`
- feedback: `moreLikeThis`, `lessLikeThis`, `notInterested`, `rating`, `updatedAt`
- action state: saved/created object IDs and `lastActionAt`

---

## DashboardRun

A run records provenance for card batches.

Sources can include:

- manual
- agent
- cron
- import

Runs are useful before a run-history UI exists because they preserve traceability.

---

## Current Swift Code Areas

- `Sources/Cider/Models/Dashboard/DashboardSnapshot.swift`
- `Sources/Cider/Models/Dashboard/DashboardTopic.swift`
- `Sources/Cider/Models/Dashboard/DashboardCard.swift`
- `Sources/Cider/Models/Dashboard/DashboardRun.swift`
- `Sources/Cider/Models/Dashboard/DashboardEnums.swift`
- `Sources/Cider/Services/Dashboard/DashboardStorage.swift`

---

## Future Fields to Consider

### First-class sources

Add when collectors become real:

```text
DashboardSource
- ciderSyncId
- kind
- title
- url
- enabled
- reliability
- lastFetchedAt
- lastSuccessfulFetchAt
- fetchCadence
- failureState
```

### Personalization debug signals

Add machine-facing match explanations:

```text
matchedSignals[]
- type
- label
- sourceItemId
- confidence
```

### Freshness / expiration

Add when time-sensitive cards become common:

```text
publishedAt
relevantAt
eventDate
expiresAt
staleAfter
snoozedUntil
```

### Tags / facets

Keep facets separate from topics:

```text
sports
seahawks
mariners
game-update
movie-sequel
watchlist
vault-resurface
needs-action
local
high-confidence
```

---

## Product Rule

`whyItMatters` is what separates Cider from a generic feed. Keep it central.
