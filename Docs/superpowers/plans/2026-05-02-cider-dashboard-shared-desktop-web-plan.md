# Cider Shared Dashboard Implementation Plan

> Status: historical implementation context. The current Dashboard source of truth lives in `Docs/Features/Dashboard/`; active follow-up work should live in Kanban and durable outcomes should be promoted back into the Dashboard feature docs.

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.
>
> **Hard constraint from Erik:** Do **not** touch the Cider AI panels or AI chat work while implementing this plan. Avoid `Sources/Cider/Views/AIAssistant/**`, `Sources/Cider/ViewModels/AIAssistantViewModel.swift`, `Sources/Cider/Services/AI/**`, `Sources/Cider/App/AppDelegate+AIAssistantPanel.swift`, and any UI wiring whose only purpose is the current AI panel.

**Goal:** Build the Cider personal dashboard as a local-first, shared data feature that works in the current macOS app format first and can be cleanly consumed by Cider Web later.

**Architecture:** Add a first-class Dashboard domain model and storage layer to Cider Desktop, persist it in the vault using existing `.cider/<type>/_cider_*.json` conventions, and define the same schema in `Shared/` before wiring any UI. Desktop remains the local-first source of truth and the first real UI. The existing overview dashboard is preserved as the `Main` view inside a new dashboard shell; topic/card dashboard views sit beside it as peer buttons inside the same Dashboard saved-view tab. Cider Web becomes a Convex-backed consumer/editor of the same dashboard cards after the model has settled.

**Tech Stack:** Swift 6 / SwiftUI / AppKit on Desktop, local vault JSON storage under `~/CiderVault/.cider/`, Convex + React 19 + TanStack Router + Tailwind v4 on Web, shared Markdown specs in `Shared/`.

---

## Read This First

The dashboard is **not** an AI panel feature. It is a Cider data/product surface.

This plan should produce:

1. A shared cross-platform dashboard schema/spec.
2. A Desktop local storage model that matches Cider's existing vault conventions.
3. A Desktop MVP UI that displays and mutates dashboard cards without touching AI panel code.
4. A sync-ready shape that Cider Web can later render through Convex.
5. A Web adaptation path that does not make Web the separate source of truth.

The existing product direction lives in:

- `Docs/Product/PRODUCT_VISION.md`
  - Section: `### Personal Dashboard / Recommendation Loop Vision`
- `Shared/CORE_SPEC.md`
- `Shared/SYNC.md`
- `Shared/FEATURE_PARITY.md`
- Desktop architecture notes: `Docs/Architecture/ARCHITECTURE.md`
- Web repo context: `../Cider-Web/AGENTS.md`

Current relevant implementation facts:

- Desktop storage roots are modeled by `StorageType` and `StoragePaths` in `Sources/Cider/Utilities/StoragePaths.swift`.
- Existing app-internal JSON patterns include `SavedViewStorage`, which writes `_cider_saved_views.json` under `.cider/saved-views/`.
- Desktop Home UI currently has:
  - `Sources/Cider/Views/Home/HomeDashboardView.swift` for saved/library content.
  - `Sources/Cider/Views/Home/HomeOverviewDashboardView.swift` for the overview/daily brief style dashboard. This must remain intact and become the `Main` dashboard view.
  - `Sources/Cider/Views/Home/HomeOverviewModels.swift` and `HomeOverviewDataProvider.swift` for current overview snapshots.
- Sync currently covers bookmarks, folders, and notes only. `Docs/Architecture/ARCHITECTURE.md` explicitly says date cards, contacts, todos, vault files, sessions, and tags remain local-only.
- Web's canonical schema lives in `../Cider-Web/convex/schema.ts`. Per Web rules, do **not** change Convex schema without a deliberate schema-gate review.

---

## Product Definition

The new dashboard is a calm, browseable, multi-topic Cider surface for cards from:

- personalized news/interests,
- local life reminders,
- project roadmaps / kanban / bugs,
- recent repo/doc changes,
- saved items needing follow-up,
- external sources that may become Cider bookmarks, memories, events, todos, or reminders.

Telegram should remain a lightweight notification/query/action surface. Web should become a remote browse/action surface. Desktop/vault remains the durable source of truth.

The user-facing Desktop shape is:

- Sidebar/tab bar still has one `Dashboard` saved-view tab.
- Inside `Dashboard`, a small dashboard switcher shows `Main` plus topic buttons.
- `Main` renders the existing Home overview dashboard.
- Topic buttons render the new dashboard card board filtered to that topic.

---

## Non-Goals for This Worktree

Do not implement these in the first worktree unless Erik explicitly asks:

- Do not modify the AI assistant panel or AI chat UI.
- Do not build agent/news collection yet.
- Do not build Hermes cron jobs yet.
- Do not add LLM ranking/summarization code yet.
- Do not sync dashboard cards to Convex until the Desktop model and shared spec are reviewed.
- Do not create a web-only dashboard that stores different data from Desktop.
- Do not hard-delete dashboard data. Use soft delete fields and/or Cider trash semantics where applicable.

---

## Proposed Shared Model

### DashboardTopic

Represents user-configurable dashboard sections/tabs.

Fields:

```typescript
type DashboardTopic = {
  ciderSyncId: string;          // lowercase UUID, cross-platform identity
  title: string;                // e.g. "AI / Vibe Coding", "Mariners", "Cider Projects"
  icon?: string;                // SF Symbol on Desktop, Lucide or emoji on Web
  colorToken?: string;          // token name, not raw color
  position: number;
  isPinned?: boolean;
  isArchived?: boolean;
  createdAt: number;            // ms since epoch
  updatedAt: number;            // ms since epoch
  deleted?: boolean;
  deletedAt?: number;
};
```

### DashboardCard

Represents one dashboard item. A card may belong to multiple topics.

```typescript
type DashboardCard = {
  ciderSyncId: string;          // lowercase UUID
  topicSyncIds: string[];

  title: string;
  subtitle?: string;
  summary: string;
  whyItMatters?: string;

  sourceKind: "url" | "bookmark" | "note" | "todo" | "event" | "project" | "board" | "repo" | "manual";
  sourceURL?: string;
  sourceTitle?: string;
  relatedItemSyncId?: string;   // bookmark/note/todo/event/board card when available
  relatedItemType?: string;

  status: "new" | "seen" | "saved" | "dismissed" | "reminded" | "archived";
  priority: "low" | "normal" | "high" | "urgent";
  score?: number;               // 0...1 ranking score, not required for manual cards

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

### DashboardCardFeedback

```typescript
type DashboardCardFeedback = {
  rating?: number;              // 1...5
  moreLikeThis?: boolean;
  lessLikeThis?: boolean;
  notInterested?: boolean;
  note?: string;                // user-owned; do not auto-generate
  updatedAt: number;
};
```

### DashboardCardActionState

Tracks side effects created from the card.

```typescript
type DashboardCardActionState = {
  savedBookmarkSyncId?: string;
  savedMemorySyncId?: string;   // future Cider memory/note model; initially optional/unused
  createdTodoSyncId?: string;
  createdEventSyncId?: string;
  reminderSyncId?: string;
  lastActionAt?: number;
};
```

### DashboardRun

Batch provenance model for manual/import/agent/cron generations. Store it from the first snapshot so the schema does not need to be reopened when collectors arrive, but do not build a run-history UI yet.

```typescript
type DashboardRun = {
  ciderSyncId: string;
  source: "manual" | "agent" | "cron" | "import";
  startedAt: number;
  finishedAt?: number;
  topicSyncIds: string[];
  cardSyncIds: string[];
  status: "running" | "completed" | "failed";
  errorMessage?: string;
};
```

---

## Desktop Persistence Recommendation

Add a new `StorageType.dashboard = "Dashboard"` with `ciderSubpath` of `dashboard`.

Persist one snapshot file first:

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

Why one JSON snapshot first:

- matches `SavedViewStorage` style,
- easy to reason about in the first MVP,
- easy to migrate later to SQLite or per-card files,
- avoids premature Convex/schema complexity,
- keeps agent-generated cards clearly separated from user bookmarks/notes/todos.

If card volume grows, migrate later to per-card JSON files plus an index. Do not start there.

---

## Desktop UI Recommendation

Do **not** cram the new dashboard into the existing library feed implementation.

Recommended MVP:

- Add domain models under `Sources/Cider/Models/Dashboard/`.
- Add storage under `Sources/Cider/Services/Dashboard/`.
- Add reusable card/topic views under `Sources/Cider/Views/Dashboard/`.
- Add a new `DashboardHubView` wrapper that renders the existing `HomeOverviewDashboardView` as `Main` and the new `DashboardBoardView` for topic tabs.
- Modify the existing `.dashboard` saved-view route to render `DashboardHubView`; do not add a second saved-view kind yet.

Important: `HomeDashboardView.swift` is already large. Prefer new small files instead of adding hundreds of lines there.

Possible Desktop files:

```text
Sources/Cider/Models/Dashboard/DashboardTopic.swift
Sources/Cider/Models/Dashboard/DashboardCard.swift
Sources/Cider/Models/Dashboard/DashboardSnapshot.swift
Sources/Cider/Services/Dashboard/DashboardStorage.swift
Sources/Cider/Views/Dashboard/DashboardCardView.swift
Sources/Cider/Views/Dashboard/DashboardTopicPillView.swift
Sources/Cider/Views/Dashboard/DashboardBoardView.swift
Sources/Cider/Views/Dashboard/DashboardEmptyStateView.swift
Sources/Cider/Views/Dashboard/DashboardHubView.swift
Tests/CiderTests/DashboardStorageTests.swift
Tests/CiderTests/DashboardModelTests.swift
```

If the test target has a different name/path, inspect `Package.swift` and match current test conventions.

---

## Web Adaptation Recommendation

Web should later add Convex tables matching the shared schema after review:

```typescript
dashboardTopics
dashboardCards
dashboardRuns // schema-gated after Desktop model review
```

But this worktree should not blindly change `../Cider-Web/convex/schema.ts` unless Erik approves the schema gate.

The Web MVP after schema approval should:

- add an auth-gated `/dashboard` route,
- use Convex `useQuery` / `useMutation` hooks,
- render topics and cards using existing design tokens from `src/styles.css`,
- support read/seen/dismiss/rate actions first,
- defer card-to-bookmark/todo/event actions until the corresponding cross-platform mutation contract is explicit,
- never store a separate browser-only dashboard copy.

Possible Web files after schema gate:

```text
../Cider-Web/convex/dashboard.ts
../Cider-Web/src/routes/dashboard.tsx
../Cider-Web/src/components/dashboard/dashboard-board.tsx
../Cider-Web/src/components/dashboard/dashboard-card.tsx
../Cider-Web/src/components/dashboard/dashboard-topic-tabs.tsx
../Cider-Web/src/components/dashboard/dashboard-empty-state.tsx
```

---

## Implementation Phases

### Phase 0: Repo and Scope Verification

**Objective:** Confirm current repo state and protect Erik's active AI panel changes.

**Steps:**

1. Run in Desktop repo:

   ```bash
   cd /Users/minivish/Cider
   git status --short
   git branch --show-current
   swift build -Xswiftc -warnings-as-errors
   ```

2. Run in Web repo if touching Web docs/plans:

   ```bash
   cd /Users/minivish/Cider-Web
   git status --short
   git branch --show-current
   npm test -- --runInBand || npm test
   npm run build
   ```

3. Inspect `Package.swift` for test target names before adding tests.

4. Confirm no files under the AI panel paths are modified:

   ```bash
   git diff --name-only | grep -E 'Sources/Cider/(Views/AIAssistant|ViewModels/AIAssistantViewModel|Services/AI|App/AppDelegate\+AIAssistantPanel)' && exit 1 || true
   ```

**Acceptance criteria:**

- Worktree state is known.
- Any pre-existing dirty files are documented and avoided.
- No AI panel files are modified.

---

### Phase 1: Shared Spec First

**Objective:** Make the dashboard contract cross-platform before coding UI.

**Files:**

- Create: `Shared/DASHBOARD.md`
- Create: `Docs/superpowers/specs/2026-05-02-dashboard-tabs-shared-design.md`
- Modify: `Shared/CORE_SPEC.md`
- Modify: `Shared/FEATURE_PARITY.md`
- Modify only if needed: `Shared/SYNC.md`

**Steps:**

1. Create `Shared/DASHBOARD.md` with:
   - product intent,
   - Desktop/Web roles,
   - model definitions,
   - timestamp/UUID rules,
   - status and feedback semantics,
   - action semantics,
   - sync gate notes.

2. Add `Shared/DASHBOARD.md` to the shared docs table in `Shared/CORE_SPEC.md`.

3. Add a `Dashboard` section to `Shared/FEATURE_PARITY.md` with initial state:
   - Desktop: Planned / MVP in progress,
   - Web: Planned consumer,
   - iOS: Later / No.

4. If the plan touches sync docs, add only a short note to `Shared/SYNC.md` saying dashboard sync is future/schema-gated, not currently part of sync.

**Acceptance criteria:**

- Another Desktop or Web agent can read `Shared/DASHBOARD.md` and implement compatible models.
- The spec explicitly says Desktop/vault is source of truth for the first MVP.
- The spec explicitly says Web must not create a separate incompatible model.

---

### Phase 2: Desktop Models

**Objective:** Add Codable/Hashable Swift models for dashboard topics, cards, feedback, actions, and snapshot.

**Files:**

- Create: `Sources/Cider/Models/Dashboard/DashboardTopic.swift`
- Create: `Sources/Cider/Models/Dashboard/DashboardCard.swift`
- Create: `Sources/Cider/Models/Dashboard/DashboardSnapshot.swift`
- Create or update tests under the existing test target.

**Model requirements:**

- Use `UUID` for local IDs.
- Include a persisted `ciderSyncId: String` that defaults to `id.uuidString.lowercased()`.
- Store persisted dashboard timestamps as numeric milliseconds since epoch. Swift models may expose `Date` helpers if useful, but JSON should match `Shared/DASHBOARD.md`.
- Include `schemaVersion` on snapshot.
- Make status/source/priority enums `String, Codable, CaseIterable` where useful.
- Include `DashboardRun` model and snapshot `runs`, even though no run-history UI is required yet.
- Decode unknown enum values safely instead of crashing on future Web/agent values.
- Keep AI-generated fields distinct from user-owned fields. `summary` and `whyItMatters` can be machine-produced later, but `feedback.note` is user-owned.

**Acceptance criteria:**

- Models compile.
- JSON round-trip tests pass.
- Lowercase `ciderSyncId` behavior is tested.
- Unknown/future fields do not crash decoding if practical.

---

### Phase 3: Desktop Storage

**Objective:** Persist dashboard snapshot using Cider's current vault format.

**Files:**

- Modify: `Sources/Cider/Utilities/StoragePaths.swift`
- Create: `Sources/Cider/Services/Dashboard/DashboardStorage.swift`
- Tests: `DashboardStorageTests.swift`

**Implementation notes:**

1. Add `case dashboard = "Dashboard"` to `StorageType`.
2. Add `case .dashboard: return "dashboard"` to `ciderSubpath`.
3. Add `DashboardStorage` as `@MainActor final class DashboardStorage: ObservableObject` with:
   - `static let shared`,
   - `@Published private(set) var topics: [DashboardTopic]`,
   - `@Published private(set) var cards: [DashboardCard]`,
   - `reload()`,
   - `upsertTopic`, `archiveTopic`, `moveTopic`,
   - `upsertCard`, `markSeen`, `dismissCard`, `rateCard`,
   - `persist()` using `JSONEncoder`.
4. Use `StoragePaths.directoryURL(for: .dashboard)` and `StoragePaths.jsonFileURL(fileName: "_cider_dashboard.json", in: dir)`.
5. Use `os.Logger`, not `print()`.
6. Persist atomically if the codebase already has a helper; otherwise write to temp then replace.
7. Do not write into `.cider` indexes or unrelated generated files.

**Acceptance criteria:**

- Empty/missing snapshot loads as empty dashboard, not an error.
- Invalid JSON logs an error and keeps an empty safe state.
- Upsert/rate/dismiss persists and reloads correctly.
- Storage path is under `.cider/dashboard/_cider_dashboard.json`.

---

### Phase 4: Seed/Test Data Helper

**Objective:** Provide preview/test data without implementing collectors or AI.

**Files:**

- Modify: `DashboardStorage.swift`
- Optional create: `Sources/Cider/Services/Dashboard/DashboardSeedData.swift`

**Implementation notes:**

Add a debug/development-only seed helper that creates a few manual cards when no dashboard data exists. Keep it obviously non-production and behind an explicit method, e.g. `seedSampleDataIfEmpty()` called only from preview/test code unless Erik approves in-app seeding. Do not call the seed helper from `DashboardHubView.onAppear` or any normal runtime path.

Sample topics:

- `AI / Vibe Coding`
- `Cider Projects`
- `Entertainment`

Sample cards should be neutral placeholders, not fake claims about live news.

**Acceptance criteria:**

- Previews/tests can render realistic cards.
- No live-source or AI collection is implied.

---

### Phase 5: Desktop Dashboard UI MVP

**Objective:** Display topics and cards in Desktop without modifying AI panels.

**Files:**

- Create: `Sources/Cider/Views/Dashboard/DashboardBoardView.swift`
- Create: `Sources/Cider/Views/Dashboard/DashboardCardView.swift`
- Create: `Sources/Cider/Views/Dashboard/DashboardTopicTabsView.swift`
- Create: `Sources/Cider/Views/Dashboard/DashboardEmptyStateView.swift`
- Create: `Sources/Cider/Views/Dashboard/DashboardHubView.swift`
- Modify: `Sources/Cider/Views/CiderPanelView+ContentArea.swift` only at the existing `.dashboard` saved-view route.

**UI rules:**

- Use `CiderColors.*`, never hardcoded colors.
- Use `CiderFont.*`, never hardcoded fonts.
- Use `Spacing.*` and design constants, no magic numbers.
- Use spring animations only and respect Reduce Motion.
- Use `.cardContainer(isHovered:isSelected:isDropTargeted:)` if rendering cards in the existing card style.
- Keep files small. If a file passes roughly 300-400 lines, extract subviews.

**Minimum MVP interactions:**

- Select topic.
- View cards for topic.
- Switch back to Main and see the existing overview dashboard.
- Mark card seen.
- Dismiss card.
- Rate card or mark more/less like this.
- Open source URL if present.

**Deferred interactions:**

- Save as bookmark.
- Create todo/reminder.
- Create event.
- Ask AI.

Those require explicit cross-entity mutation decisions and should be separate tasks.

**Acceptance criteria:**

- Dashboard renders in Desktop with existing data or a useful empty state.
- Existing overview dashboard remains available as the `Main` dashboard view.
- Mark seen/dismiss/rating updates storage.
- Empty state is useful.
- No AI panel files changed.

---

### Phase 6: Desktop Actions, One at a Time

**Objective:** Wire card actions to existing Cider entities only after basic UI/storage works.

Implement in this order:

1. `open source URL`
2. `save existing URL as bookmark`
3. `create todo/reminder`
4. `create event/date card`
5. `save as lightweight memory/note`

Each action needs its own tiny PR/task because each crosses into existing storage and trash/undo semantics.

Rules:

- Use existing storage services; do not bypass them.
- If deleting/undoing anything, use existing `TrashStorage` and `CiderUndoManager` patterns.
- After action success, update `DashboardCardActionState` with the created/saved item sync ID where available.
- If an action cannot safely determine the correct folder/date/title with high confidence, prompt the user instead of guessing.

**Acceptance criteria:**

- Each action creates the target Cider item correctly.
- Dashboard card records the action result.
- Failed actions do not corrupt dashboard state.

---

### Phase 7: Sync Contract Review Gate

**Objective:** Decide how dashboard cards enter Convex/Web without breaking existing sync.

Do this before modifying `../Cider-Web/convex/schema.ts`.

Review questions:

- Should dashboard cards sync through existing `sync:push` / `sync:pull`, or should Web use direct Convex tables and Desktop add dashboard arrays to sync actions?
- Are cards user-private per `userId` only? Yes by default.
- Which fields are Desktop-write-only initially?
- Can Web create cards, or only mutate feedback/status? Recommendation: Web can mutate feedback/status first; Desktop/agents create cards.
- Should `DashboardRun` sync now or later? Recommendation: later.

Produce a short schema-gate note before implementation:

```text
Docs/superpowers/plans/YYYY-MM-DD-dashboard-sync-schema-gate.md
```

**Acceptance criteria:**

- Erik approves schema direction before Convex schema changes.
- Shared docs are updated if the chosen sync path differs from this plan.

---

### Phase 8: Web MVP After Schema Gate

**Objective:** Render the same cards in Cider Web once Convex schema/mutations are approved.

**Files:**

- Web create: `../Cider-Web/convex/dashboard.ts`
- Web modify: `../Cider-Web/convex/schema.ts` after approval only
- Web create: `../Cider-Web/src/routes/dashboard.tsx`
- Web create: `../Cider-Web/src/components/dashboard/*`
- Web modify: sidebar/nav only if needed

**Web rules:**

- Use Convex `useQuery`/`useMutation`; no separate local dashboard store.
- Auth-gate route like `/home`.
- Use CSS variables from `src/styles.css`; no hardcoded colors/fonts/magic spacing.
- Keep actions conservative: seen/dismiss/rate/open source first.
- Do not build Web-only card creation unless Desktop sync/write ownership is decided.

**Acceptance criteria:**

- `/dashboard` shows topics and cards from Convex.
- Dismiss/rating mutations update instantly through Convex subscriptions.
- Web UI matches Cider visual language closely enough for MVP.

---

## Testing and Verification Commands

Desktop:

```bash
cd /Users/minivish/Cider
swift build -Xswiftc -warnings-as-errors
swift test
```

Web, only if touched:

```bash
cd /Users/minivish/Cider-Web
npm test
npm run build
npx convex codegen
```

Diff safety check:

```bash
cd /Users/minivish/Cider
git diff --name-only | grep -E 'Sources/Cider/(Views/AIAssistant|ViewModels/AIAssistantViewModel|Services/AI|App/AppDelegate\+AIAssistantPanel)' && echo "ERROR: touched AI panel files" && exit 1 || echo "AI panel untouched"
```

Manual Desktop QA:

- Open Cider.
- Verify Home/dashboard still loads.
- Verify existing library feed still works.
- Verify topic selection does not reset unrelated Home state unexpectedly.
- Verify card seen/dismiss/rating persists after app restart.
- Verify no console/log spam.

Manual Web QA after Web phase:

- Sign in.
- Open `/dashboard`.
- Verify auth gate redirects logged-out users.
- Verify cards render on desktop and mobile widths.
- Verify rating/dismiss updates without refresh.
- Verify `/home` bookmark feed still works.

---

## Agent Handoff Prompt

Use this prompt when sending an implementation agent into a worktree:

```text
You are implementing Cider's shared personal dashboard MVP. Start by reading:
- /Users/minivish/Cider/Docs/superpowers/plans/2026-05-02-cider-dashboard-shared-desktop-web-plan.md
- /Users/minivish/Cider/Shared/CORE_SPEC.md
- /Users/minivish/Cider/Shared/SYNC.md
- /Users/minivish/Cider/Shared/FEATURE_PARITY.md
- /Users/minivish/Cider/Docs/Architecture/ARCHITECTURE.md section "Cider Web Sync"
- /Users/minivish/Cider/Docs/Product/PRODUCT_VISION.md section "Personal Dashboard / Recommendation Loop Vision"

Hard constraint: do not touch any AI assistant panel/chat files. Avoid:
- Sources/Cider/Views/AIAssistant/**
- Sources/Cider/ViewModels/AIAssistantViewModel.swift
- Sources/Cider/Services/AI/**
- Sources/Cider/App/AppDelegate+AIAssistantPanel.swift

Implement Phase 1 through Phase 5 only unless asked otherwise:
1. Shared dashboard spec.
2. Desktop dashboard models.
3. Desktop vault JSON storage under .cider/dashboard/_cider_dashboard.json.
4. Preview/test seed data helper.
5. Desktop dashboard UI MVP with topic tabs, cards, seen/dismiss/rating/open-source actions.

Do not change Convex schema yet. Do not implement Web yet. Do not implement AI/news collectors yet. Keep Desktop as source of truth and keep the model sync-ready for Web.

Before coding, inspect the current worktree and report any dirty files. After coding, run:
- swift build -Xswiftc -warnings-as-errors
- swift test if available
- git diff --name-only safety check for AI panel paths

Keep changes small and decomposed into new Dashboard model/service/view files instead of bloating HomeDashboardView.swift.
```

---

## Definition of Done for the First Worktree

The first implementation worktree is done when:

- `Shared/DASHBOARD.md` exists and describes the Desktop/Web-compatible contract.
- Desktop has dashboard models and storage that round-trip JSON.
- Dashboard snapshot persists under `.cider/dashboard/_cider_dashboard.json`.
- Desktop can display dashboard topics/cards in a small MVP surface.
- Seen/dismiss/rating/open-source interactions work.
- No AI panel files were touched.
- Desktop build passes with warnings as errors.
- Tests for model/storage pass or the agent documents exactly why the test target could not run.
- Web schema is untouched unless Erik explicitly approved the schema gate.

---

## Future Work After MVP

- Add card-to-bookmark action.
- Add card-to-todo/reminder action.
- Add card-to-event action.
- Add lightweight memory/note action.
- Add dashboard card generation from Cider project boards.
- Add dashboard card generation from repo status/cron jobs.
- Add curated source/news collection through Hermes/Cider agents.
- Add Convex dashboard tables and Web `/dashboard` after schema approval.
- Add Cider Web feedback/rating actions.
- Add dashboard notification policy for Telegram nudges only.
