# Sync Protocol

> Last validated: 2026-03-18 (iOS now expects purge + tag management routes — see Planned Endpoints below)

> Canonical sync specification for all three Cider apps. Consolidates the per-app `SYNC_COLLABORATION.md` docs into one source of truth.
>
> **If you're working on anything sync-related, read this entire file first.**

## Overview

All three clients sync bookmarks and folders through Convex HTTP endpoints. Web also uses direct Convex mutations for its own saves (bypassing the REST layer), but exposes the REST API for Desktop and iOS.

```
Desktop (macOS)  ── REST ──>  Convex Backend  <── REST ──  iOS
                                    ^
                              Web (direct mutations + subscriptions)
```

**Auth**: All REST sync endpoints require `Authorization: Bearer <sync_token>`. Desktop and iOS obtain tokens automatically via the native auth endpoints (login/signup). Web uses `@convex-dev/auth` session cookies.

**Base URL**: `https://dashing-fennec-334.convex.site`

## Native Auth Endpoints (Desktop + iOS)

Desktop and iOS authenticate via email/password. On login or signup, the server auto-creates a sync token and returns it. The client stores the token in Keychain and uses it for all sync requests.

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/auth/login` | Sign in with email + password → returns sync token |
| POST | `/api/auth/signup` | Create account with email + password → returns sync token |
| POST | `/api/auth/account` | Get account info (requires Bearer token) |
| POST | `/api/auth/devices` | List connected devices (requires Bearer token) |
| POST | `/api/auth/devices/revoke` | Revoke a device's sync token (requires Bearer token) |

### Login Request

```json
{
  "email": "user@example.com",
  "password": "password123",
  "deviceName": "MacBook Pro"
}
```

### Login Response (200)

```json
{
  "token": "aBcDeFgH-iJkLmNoP-qRsTuVwX-yZaBcDeF",
  "userId": "convex_user_id",
  "email": "user@example.com"
}
```

### Error Response (401 login / 400 signup)

```json
{
  "error": "Invalid email or password"
}
```

### Auth Flow

1. User enters email + password in Settings
2. Client calls `/api/auth/login` (or `/api/auth/signup`)
3. Server verifies credentials against `@convex-dev/auth` password hashes
4. Server creates or reuses a sync token for this device
5. Client stores token in Keychain, sets `syncEnabled = true`
6. All subsequent sync calls use `Authorization: Bearer <token>`

### Device Name

Each device gets a named sync token (e.g., "MacBook Pro", "iPhone"). If the user logs in again from the same device name, the existing token is reused instead of creating a new one.

### Sign Out

Client clears the stored token and email, sets `syncEnabled = false`. The sync token remains valid on the server (can be revoked via Connected Devices).

### Connected Devices

All three apps display a Connected Devices view in Settings, showing every device that has a sync token. Users can revoke tokens to log out other devices.

#### List Devices (`/api/auth/devices`)

**Request**: POST with `Authorization: Bearer <token>`. No body required.

**Response (200)**:
```json
{
  "devices": [
    {
      "_id": "token_doc_id",
      "name": "MacBook Pro",
      "createdAt": 1709766000000,
      "lastUsedAt": 1709800000000,
      "revoked": false
    }
  ]
}
```

#### Revoke Device (`/api/auth/devices/revoke`)

**Request**:
```json
{
  "tokenId": "token_doc_id"
}
```

**Response (200)**:
```json
{
  "success": true
}
```

Revoking a device marks its sync token as `revoked: true`. The token will be rejected on subsequent sync requests. The server tracks `lastUsedAt` for each token, updated on every authenticated request.

## Sync Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/sync/push` | Push bookmarks + folders from client to server |
| POST | `/api/sync/pull` | Pull changes since a timestamp |
| POST | `/api/sync/reconcile` | Full manifest of all bookmark `ciderSyncId` + `updatedAt` pairs (drift detection) |
| POST | `/api/sync/upload-thumbnail` | Upload thumbnail image for a bookmark (multipart or raw binary) |
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

- **Desktop**: `SyncPushBookmark` / `SyncPushFolder` (Encodable structs in SyncService.swift)
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
| **Push trigger** | Every 5s poll (dirty-only) | On save/delete/edit | Direct Convex mutation (no REST push) |
| **Pull trigger** | Every 5s poll | Launch + foreground + pull-to-refresh | Convex real-time subscriptions |
| **Dirty tracking** | `lastSuccessfulPushAt` filter | Pushes only affected bookmark(s) | N/A |
| **Failure handling** | Consecutive failure counter, pauses after 3+ | Shows user-facing error | Convex handles retries |
| **Enrichment** | Runs enrichment pipeline locally, pushes `"complete"` | Pushes `"pending"` | Pushes `"pending"`, has server-side enrichment action |
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

### Remaining Desktop Issue

`updateFromSync()` uses `if let folderID` to set folder — when remote has no folder, this is a no-op and Desktop keeps the stale local `folderID`. Web's equal-timestamp defense handles this, but Desktop should unconditionally assign `folderID` (including nil) to match the server.

## Verification Checklist

After any sync changes, verify all of these across all three platforms:

- [ ] Edit a note on Web -> pull on iOS and Desktop -> all three show the note
- [ ] Edit a note on Desktop -> check Web and iOS see it
- [ ] Edit a note on iOS -> check Web and Desktop see it
- [ ] Delete a bookmark on any platform -> verify tombstone propagates to the other two
- [ ] Create a bookmark on iOS (with `enrichmentStatus: "pending"`) -> verify Desktop enriches it
- [ ] Move a bookmark into a folder on Web -> verify Desktop and iOS see the folder assignment
- [ ] Move a bookmark out of a folder on Web -> verify it's unassigned on Desktop and iOS
