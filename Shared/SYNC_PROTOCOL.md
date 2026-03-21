# Sync Protocol

> Last validated: 2026-03-21 (auth section deduplicated to AUTH.md; Desktop transport corrected to Convex SDK; remaining Desktop folder issue moved to fixed; note attachment endpoints documented; Desktop push/pull triggers corrected from "5s poll" to event-driven)

> Canonical sync specification for all three Cider apps. Consolidates the per-app `SYNC_COLLABORATION.md` docs into one source of truth.
>
> **If you're working on anything sync-related, read this entire file first.**

## Overview

All three clients sync bookmarks, folders, and notes through Convex. Desktop uses the **Convex Swift SDK** (`ConvexMobile`) over WebSocket, calling Convex actions (`sync:push`, `sync:pull`, etc.) directly. iOS uses the **REST HTTP endpoints** in `http.ts`. Web uses direct Convex mutations and real-time subscriptions (bypassing the REST/action layer entirely).

```
Desktop (macOS)  ── Convex SDK (WebSocket) ──>  Convex Backend  <── REST (HTTP) ──  iOS
                                                       ^
                                                 Web (direct mutations + subscriptions)
```

**Auth**: REST sync endpoints require `Authorization: Bearer <sync_token>`. Convex SDK actions use `sync:authenticate` to validate the token. Desktop and iOS obtain tokens automatically via the native auth endpoints (login/signup). Web uses `@convex-dev/auth` session cookies.

**Base URL**: `https://dashing-fennec-334.convex.site`

## Auth

See **AUTH.md** for the full auth specification: login/signup flow, token management, password hashing, connected devices, and per-platform details.

**Quick reference**: Desktop and iOS authenticate via email/password (`/api/auth/login` or `/api/auth/signup`), which returns a sync token stored in Keychain. All sync requests include `Authorization: Bearer <token>`. Web uses `@convex-dev/auth` session cookies.

## Sync Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/sync/push` | Push bookmarks + folders from client to server |
| POST | `/api/sync/pull` | Pull changes since a timestamp |
| POST | `/api/sync/reconcile` | Full manifest of all bookmark `ciderSyncId` + `updatedAt` pairs (drift detection) |
| POST | `/api/sync/upload-thumbnail` | Upload thumbnail image for a bookmark (multipart or raw binary) |
| POST | `/api/sync/upload-note-attachment` | Upload note image attachment (Desktop) |
| POST | `/api/sync/note-attachments-check` | Batch check which note attachments already exist on server |
| POST | `/api/capture` | Quick-capture a URL (creates bookmark with `enrichmentStatus: "pending"`) |

### Planned Endpoints (not yet in `http.ts` — iOS client code calls these as of 2026-03-18)

| Method | Path | Purpose | iOS client code |
|--------|------|---------|-----------------|
| POST | `/api/sync/purge` | Permanently delete one item: `{ type: "bookmark"\|"note", ciderSyncId }` | `SyncClient.purgeBookmark/purgeNote` |
| POST | `/api/sync/empty-trash` | Purge all soft-deleted items for the user | `SyncClient.emptyTrash` |
| POST | `/api/tags/rename` | Rename a tag: `{ oldName, newName }` → `{ count }` | `SyncClient.renameTag` |
| POST | `/api/tags/delete` | Delete a tag: `{ name }` → `{ count }` | `SyncClient.deleteTag` |
| POST | `/api/tags/merge` | Merge tags: `{ sourceName, targetName }` → `{ count }` | `SyncClient.mergeTag` |

Backend mutations for purge already exist (`bookmarks.ts`, `notes.ts`), but the HTTP routes in `http.ts` need to be added. Tag management mutations need to be created. All routes should use the existing `authenticateSync` Bearer token pattern.

All requests: `POST`, `Content-Type: application/json`, `Authorization: Bearer <sync_token>`.

## Push (`/api/sync/push`)

### Request

```json
{
  "bookmarks": [
    {
      "ciderSyncId": "uuid-string-lowercase",
      "title": "Page Title",
      "urlString": "https://example.com",
      "notes": "optional notes",
      "tags": ["tag1", "tag2"],
      "thumbnailRemoteUrl": "https://...",
      "aiSummary": "optional",
      "dominantColors": ["#hex1", "#hex2"],
      "createdAt": 1709766000000,
      "updatedAt": 1709766000000,
      "deleted": false,
      "deletedAt": null,
      "enrichmentStatus": "pending",
      "folderSyncId": "folder-uuid-lowercase"
    }
  ],
  "folders": [
    {
      "ciderSyncId": "folder-uuid-lowercase",
      "name": "Folder Name",
      "icon": "optional-icon-name",
      "parentSyncId": "parent-folder-uuid-or-null",
      "createdAt": 1709766000000,
      "updatedAt": 1709766000000,
      "deleted": false,
      "deletedAt": null
    }
  ]
}
```

### Accepted Bookmark Fields (STRICT)

Convex uses `v.object()` strict validation. **Extra fields cause the ENTIRE push batch to fail.**

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `ciderSyncId` | string | yes | Lowercase UUID |
| `title` | string | yes | |
| `urlString` | string | yes | |
| `notes` | string | no | |
| `tags` | string[] | yes | Empty array if none |
| `thumbnailRemoteUrl` | string | no | |
| `aiSummary` | string | no | |
| `dominantColors` | string[] | no | |
| `createdAt` | number | yes | ms since epoch |
| `updatedAt` | number | yes | ms since epoch |
| `deleted` | boolean | no | |
| `deletedAt` | number | no | ms since epoch |
| `enrichmentStatus` | string | no | `"pending"` or `"complete"` |
| `folderSyncId` | string | no | References folder's `ciderSyncId` |

### Rejected Bookmark Fields (will cause validation failure)

Do NOT send: `_id`, `host`, `favicon`, `thumbnailUrl`, `thumbnailStorageId`, `userId`, `folderId`, `purged`, `purgedAt`, or any unlisted field.

### Accepted Folder Fields (STRICT)

| Field | Type | Required |
|-------|------|----------|
| `ciderSyncId` | string | yes |
| `name` | string | yes |
| `icon` | string | no |
| `parentSyncId` | string | no |
| `createdAt` | number | yes |
| `updatedAt` | number | yes |
| `deleted` | boolean | no |
| `deletedAt` | number | no |

### Response

```json
{
  "created": 2,
  "updated": 1,
  "serverTime": 1709766000000
}
```

### Deletion Tombstones

To delete a bookmark, push a tombstone:

```json
{
  "ciderSyncId": "uuid-of-deleted-item",
  "title": "",
  "urlString": "",
  "tags": [],
  "createdAt": 1709766000000,
  "updatedAt": 1709766000000,
  "deleted": true,
  "deletedAt": 1709766000000
}
```

### Push-Safe Struct Pattern

Both Desktop and iOS use a dedicated push-only type to prevent accidental extra fields:

- **Desktop**: `bookmarkPayload()` / `folderPayload()` / `notePayload()` (static functions in SyncService.swift returning `[String: ConvexEncodable?]` dictionaries)
- **iOS**: `PushBookmark` (Codable struct in Shared/Bookmark.swift)

**Any new client must follow this pattern.** Never serialize a full model object directly into a push payload.

## Pull (`/api/sync/pull`)

### Request

```json
{
  "since": 1709766000000
}
```

Use `0` to pull everything.

### Response

```json
{
  "bookmarks": [
    {
      "_id": "convex_doc_id",
      "ciderSyncId": "uuid-or-null",
      "title": "Page Title",
      "urlString": "https://example.com",
      "host": "example.com",
      "notes": "optional",
      "tags": ["tag1"],
      "favicon": "https://...",
      "thumbnailRemoteUrl": "https://...",
      "thumbnailUrl": "https://convex-storage-url/...",
      "aiSummary": "optional",
      "dominantColors": ["#hex1"],
      "createdAt": 1709766000000,
      "updatedAt": 1709766000000,
      "deleted": false,
      "deletedAt": null,
      "folderSyncId": "resolved-from-folderId"
    }
  ],
  "folders": [ ... ],
  "serverTime": 1709766000000
}
```

Pull returns additional server-computed fields not accepted by push: `_id`, `host`, `favicon`, `thumbnailUrl` (resolved from `thumbnailStorageId`), `folderSyncId` (resolved from `folderId`).

## Conflict Resolution

**Primary rule**: Last-write-wins on `updatedAt`. Server only updates a record if `incoming.updatedAt > existing.updatedAt`.

### Conditional Patch (newer timestamp)

When the incoming push has a strictly newer `updatedAt`, core fields always overwrite. But three fields have special handling:

| Field | Condition | Why |
|-------|-----------|-----|
| `folderId` | Set if `incoming.folderSyncId` is truthy; cleared if falsy | Allows both "move into folder" and "move out of folder" to propagate |
| `aiSummary` | Only overwrite if `incoming.aiSummary !== undefined` | Prevents clients without AI data from wiping enrichment |
| `dominantColors` | Only overwrite if `incoming.dominantColors !== undefined` | Same as above |

### Equal Timestamp Rule

When timestamps are equal, the **server is canonical** for folder assignment. Only enrichment fields (`aiSummary`, `dominantColors`) can be added if the server is missing them. This prevents bounce-back when Desktop pulls a bookmark that was moved out of a folder — Desktop preserves the server's `updatedAt` but may have a stale local `folderID`.

**Key principle**: Folder assignment changes require a strictly newer `updatedAt`. At equal timestamps, server wins.

## Sync Behavior by Platform

| Behavior | Desktop | iOS | Web |
|----------|---------|-----|-----|
| **Transport** | Convex Swift SDK (WebSocket actions) | REST HTTP endpoints | Direct Convex mutations + subscriptions |
| **Push trigger** | Event-driven via `pushAfterLocalChange()` (2s debounce, dirty-only) + 30s timer for notes | On save/delete/edit | Direct Convex mutation (no REST push) |
| **Pull trigger** | Reactive via WebSocket `changeSignal` subscription (3s debounce) | Launch + foreground + pull-to-refresh | Convex real-time subscriptions |
| **Dirty tracking** | `lastSuccessfulPushAt` filter | Pushes only affected bookmark(s) | N/A |
| **Failure handling** | Consecutive failure counter, pauses after 3+ | Shows user-facing error | Convex handles retries |
| **Stale-pull guard** | N/A | Generation counter — stop/restart increments gen; results from stale gen are discarded (prevents sign-out race) | N/A |
| **Enrichment** | Runs enrichment pipeline locally, pushes AI data but does NOT yet push `enrichmentStatus: "complete"` (known gap) | Pushes `"pending"` | Pushes `"pending"`, has server-side enrichment action |
| **Thumbnail upload** | Not yet (planned) | Not yet | Endpoint exists (`/api/sync/upload-thumbnail`) |

## Historical Bugs (All Fixed)

These caused a "bounce-back" cycle. Documented here so no one reintroduces them.

### Desktop Bugs (Fixed)

| Bug | Fix | File |
|-----|-----|------|
| `updateFromSync()` used `Date()` instead of server timestamp | Now accepts and uses `remoteUpdatedAt` parameter | BookmarksStorage.swift |
| `updateFolderFromSync()` same issue | Same fix | BookmarksStorage.swift |
| Pushed ALL bookmarks every 5s | Dirty-only push via `lastSuccessfulPushAt` filter | SyncService.swift |
| Push failures were silent | Consecutive failure counter, pauses after 3+ failures | SyncService.swift |

### Desktop Bugs (Fixed, cont.)

| Bug | Fix | File |
|-----|-----|------|
| `updateFromSync()` used `if let folderID` — when remote had no folder, Desktop kept stale local folderID | Now explicitly handles nil `remoteFolderSyncId` by setting `syncFolderID = nil` | SyncService.swift (lines 565-572) |

## Verification Checklist

After any sync changes, verify all of these across all three platforms:

- [ ] Edit a note on Web -> pull on iOS and Desktop -> all three show the note
- [ ] Edit a note on Desktop -> check Web and iOS see it
- [ ] Edit a note on iOS -> check Web and Desktop see it
- [ ] Delete a bookmark on any platform -> verify tombstone propagates to the other two
- [ ] Create a bookmark on iOS (with `enrichmentStatus: "pending"`) -> verify Desktop enriches it
- [ ] Move a bookmark into a folder on Web -> verify Desktop and iOS see the folder assignment
- [ ] Move a bookmark out of a folder on Web -> verify it's unassigned on Desktop and iOS
