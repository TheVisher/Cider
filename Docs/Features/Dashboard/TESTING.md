# Dashboard Testing

**Status:** Durable testing reference for the Dashboard feature.

---

## Test Files

- `Tests/CiderTests/DashboardModelTests.swift`
- `Tests/CiderTests/DashboardStorageTests.swift`
- `Tests/CiderTests/DashboardSavedViewKindTests.swift`

---

## Quick Verification

```bash
swift test --filter Dashboard
```

---

## What Tests Should Cover

### Model tests

- snapshot encode/decode compatibility
- topic/card/run round-tripping
- lowercase `ciderSyncId` behavior
- persisted timestamps as numeric milliseconds
- unknown enum/future-value tolerance where practical
- feedback rating clamped to 1...5

### Storage tests

- missing snapshot loads as empty dashboard
- invalid JSON fails safe
- upsert topic/card persists and reloads
- seen/dismiss/archive/delete transitions persist
- feedback transitions persist
- user-owned feedback notes are not overwritten by generated/upserted content

### UI/manual tests

- Dashboard tab opens the `Main` overview first
- topic tabs render active topics
- cards filter by topic
- dismissed/archived/deleted cards disappear from the active board
- card actions update storage
- source URL opens when present

---

## Manual Desktop QA

```text
Open Cider
  → Dashboard saved-view tab loads
  → Main shows existing overview dashboard
  → Topic tabs are visible
  → Selecting a topic shows cards or useful empty state
  → Seen/dismiss/rating feedback persists after restart
```

---

## Safety Check

Dashboard work should not touch AI panel files.

```bash
git diff --name-only | grep -E 'Sources/Cider/(Views/AIAssistant|ViewModels/AIAssistantViewModel|Services/AI|App/AppDelegate\+AIAssistantPanel)' && echo "ERROR: touched AI panel files" && exit 1 || echo "AI panel untouched"
```
