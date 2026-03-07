# Sync Collaboration: Desktop Agent

> Cross-platform sync collaboration doc. All three Cider platforms (iOS, Desktop, Web) share a Convex backend. This doc was created by the iOS agent to coordinate sync fixes across platforms.

## How Sync Works

```
Desktop (macOS)  <-->  Convex Backend  <-->  iOS
                        ^
                   Web (browser)
```

- **Backend**: Convex deployment at `https://dashing-fennec-334.convex.site`
- **Auth**: Bearer token (sync tokens generated in Cider Web settings)
- **Endpoints**: `POST /api/sync/push` and `POST /api/sync/pull`
- **Conflict resolution**: Last-write-wins on `updatedAt` (milliseconds since epoch)
- **Push flow**: Client sends bookmarks array -> `pushBookmarks` mutation upserts each one
- **Pull flow**: Client sends `{ since: timestamp }` -> gets bookmarks updated after that time
- **Schema validation**: Convex uses `v.object()` strict validation — extra fields in the push payload cause the **entire mutation to fail**

## What the Convex `pushBookmarks` Mutation Accepts

These are the **only** fields accepted (from `Cider-Web/convex/sync.ts` line 241):

```typescript
v.object({
    ciderSyncId: v.string(),
    title: v.string(),
    urlString: v.string(),
    notes: v.optional(v.string()),
    tags: v.array(v.string()),
    thumbnailRemoteUrl: v.optional(v.string()),
    aiSummary: v.optional(v.string()),
    dominantColors: v.optional(v.array(v.string())),
    createdAt: v.number(),
    updatedAt: v.number(),
    deleted: v.optional(v.boolean()),
    deletedAt: v.optional(v.number()),
    enrichmentStatus: v.optional(v.string()),
    folderSyncId: v.optional(v.string()),
})
```

**Fields that will cause rejection if included**: `_id`, `host`, `favicon`, `thumbnailUrl`, `thumbnailStorageId`, `userId`, `folderId`, `purged`, `purgedAt`, or any other field not listed above.

## What iOS Is Doing

iOS uses a `PushBookmark` struct (in `Shared/Bookmark.swift`) that maps from the full `Bookmark` model to only the fields the push mutation accepts. This ensures Convex strict validation passes.

## What Web Has Done

Web has implemented **conditional patching** as a server-side defense against the Desktop timestamp inflation bug. In `pushBookmarks`, three fields now only overwrite when the incoming push explicitly provides them:

| Field | Condition | Why |
|-------|-----------|-----|
| `folderId` | Only if `incoming.folderSyncId` is truthy | Desktop doesn't know about web folder assignments |
| `aiSummary` | Only if `incoming.aiSummary !== undefined` | Prevents Desktop from wiping web enrichment |
| `dominantColors` | Only if `incoming.dominantColors !== undefined` | Same as above |

## Desktop Fixes (Completed)

All four bugs identified below have been fixed. Desktop sync now plays nicely with iOS and Web.

### Bug 1: Timestamp preservation — FIXED

**Problem**: `updateFromSync()` and `updateFolderFromSync()` in `BookmarksStorage.swift` set `updatedAt = Date()` instead of preserving the remote timestamp. This inflated the timestamp, causing pulled bookmarks to be re-pushed on the next cycle.

**Fix**: Both methods now accept a `remoteUpdatedAt: Date` parameter and use it directly. The caller in `SyncService.pull()` passes the already-computed remote timestamp through.

### Bug 2: Push sent ALL bookmarks every cycle — FIXED

**Problem**: Desktop pushed every bookmark to the server every 5 seconds, wasting bandwidth and risking one bad bookmark killing the entire push.

**Fix**: Added `lastSuccessfulPushAt: Double` to `CiderConfig` (persisted). `push()` now filters to only bookmarks/folders where `updatedAt > lastSuccessfulPushAt`. After a successful push, `lastSuccessfulPushAt` is updated. Combined with Bug 1 fix, pulled-but-unchanged bookmarks won't have a newer `updatedAt` and won't be re-pushed.

### Bug 3: Push payload included unsafe fields — FIXED

**Problem**: Push used `JSONSerialization` dictionaries built manually. Risk of accidentally including fields that Convex rejects.

**Fix**: Created `SyncPushBookmark`, `SyncPushFolder`, and `SyncPushBody` as `Encodable` structs (like iOS's `PushBookmark`). Only declared properties are serialized via `JSONEncoder` — no accidental extra fields. Tombstone initializers handle deletion payloads.

### Bug 4: Push failures were silent — FIXED

**Problem**: If `push()` threw, the error was caught and logged generically. The same failing payload was retried every 5 seconds forever.

**Fix**:
- `consecutiveFailures` counter tracks repeated errors
- After 3+ consecutive failures, sync pauses (stops retrying)
- 401 → stops sync entirely, logs auth error
- 400 → new `SyncError.validationError` captures response body for debugging
- 5xx → logs status code and failure count
- `startIfEnabled()` and successful syncs reset the failure counter
