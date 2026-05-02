# Sync & Authentication

Cross-platform sync protocol and authentication specification for all three Cider apps.

## Table of Contents

- [Authentication](#authentication)
  - [Overview](#overview)
  - [Auth Flow (Desktop + iOS)](#auth-flow-desktop--ios)
  - [Auth Flow (Web)](#auth-flow-web)
  - [Auth Endpoints](#auth-endpoints)
  - [Device Naming](#device-naming)
  - [Token Storage](#token-storage)
  - [Sign Out](#sign-out)
  - [Password Hashing](#password-hashing)
  - [Backend Files](#backend-files)
  - [Client Files](#client-files)
  - [Connected Devices](#connected-devices)
  - [Security Notes](#security-notes)
  - [Future Considerations](#future-considerations)
- [Sync Protocol](#sync-protocol)
  - [Sync Overview](#sync-overview)
  - [Sync Endpoints](#sync-endpoints)
  - [Push](#push-apisyncpush)
  - [Pull](#pull-apisyncpull)
  - [Conflict Resolution](#conflict-resolution)
  - [Sync Behavior by Platform](#sync-behavior-by-platform)
  - [Historical Bugs](#historical-bugs-all-fixed)
  - [Verification Checklist](#verification-checklist)

---

## Authentication

> Cross-platform auth specification for all three Cider apps. Read this before working on auth, login, sync credentials, or account management.
>
> **Last updated**: 2026-03-19

### Overview

Users create an account with email + password. All three apps authenticate against the same Convex backend. Desktop and iOS use REST endpoints to sign in and receive a sync token. Web uses `@convex-dev/auth` session cookies directly.

```
Desktop (macOS)  -- /api/auth/login -->  Convex Backend  <-- /api/auth/login --  iOS
                         |                     ^                    |
                    sync token             session cookie       sync token
                    (Keychain)          (@convex-dev/auth)     (Keychain)
                         |                     |                    |
                    /api/sync/*           direct mutations     /api/sync/*
                                              |
                                         Cider Web
```

### Auth Flow (Desktop + iOS)

1. User opens Settings -> Account -> enters email + password
2. App calls `POST /api/auth/login` (or `/api/auth/signup`)
3. Server verifies credentials (Scrypt password hash via Lucia)
4. Server creates or reuses a device-named sync token
5. App stores token in Keychain, stores email in UserDefaults
6. App sets `syncEnabled = true` and starts sync
7. All sync requests include `Authorization: Bearer <token>`

### Auth Flow (Web)

Web uses `@convex-dev/auth` Password provider with React hooks (`useAuthActions().signIn()`). Session management is handled automatically via Convex session cookies. Web never uses sync tokens — it talks to Convex directly via subscriptions and mutations.

### Auth Endpoints

| Method | Path | Purpose | Auth Required |
|--------|------|---------|---------------|
| POST | `/api/auth/login` | Sign in -> returns sync token | No (credentials in body) |
| POST | `/api/auth/signup` | Create account -> returns sync token | No (credentials in body) |
| POST | `/api/auth/account` | Get account info (email) | Bearer token |
| POST | `/api/auth/devices` | List connected devices | Bearer token |
| POST | `/api/auth/devices/revoke` | Remove a device | Bearer token |

#### Login / Signup Request

```json
{
  "email": "user@example.com",
  "password": "password123",
  "deviceName": "MacBook Pro"
}
```

#### Login / Signup Response (200)

```json
{
  "token": "aBcDeFgH-iJkLmNoP-qRsTuVwX-yZaBcDeF",
  "userId": "convex_user_id",
  "email": "user@example.com"
}
```

#### Error Response

```json
{
  "error": "Invalid email or password"
}
```

### Device Naming

Each sync token is associated with a device name. When a device logs in:
- If a non-revoked token with the same device name exists, it's reused
- Otherwise, a new token is created

Device names come from:
- **macOS**: `Host.current().localizedName` (e.g., "VishMac")
- **iOS**: `UIDevice.current.name` (e.g., "iPhone")

### Token Storage

| Platform | Token Storage | Email Storage |
|----------|--------------|---------------|
| Desktop | Keychain (`SyncService.saveSyncToken`) | UserDefaults (`CiderAccountEmail`) |
| iOS | Keychain (`KeychainHelper`) | UserDefaults App Group (`cider_account_email`) |
| Web | N/A (session cookies) | N/A (Convex auth) |

### Sign Out

Desktop/iOS:
1. Clear token from Keychain
2. Clear email from UserDefaults
3. Set `syncEnabled = false`
4. Stop sync service
5. Token remains valid on server (can be revoked via Connected Devices)

Web:
1. Call `signOut()` from `@convex-dev/auth`

### Password Hashing

All platforms use the same password hash format (Lucia Scrypt):

```
<salt_hex>:<key_hex>
```

- Salt: 16 random bytes, hex-encoded (32 chars)
- Key: scrypt with `N=16384, r=16, p=1, dkLen=64`
- Salt is passed to scrypt as TEXT STRING (hex chars as UTF-8 bytes)
- Password is NFKC-normalized before hashing

Password verification runs in a `"use node"` Convex action (`nativeAuthNode.ts`) because it needs Node.js `crypto.scryptSync`.

### Backend Files

| File | Purpose |
|------|---------|
| `convex/auth.ts` | `@convex-dev/auth` config (Password provider, session settings) |
| `convex/auth.config.ts` | OIDC provider config |
| `convex/nativeAuth.ts` | DB helpers: findAuthAccount, createTokenForUser, createUserAndToken, listDevices, revokeDevice |
| `convex/nativeAuthNode.ts` | `"use node"` actions: verifyCredentials, createAccount (Scrypt crypto) |
| `convex/http.ts` | HTTP routes: /api/auth/* |
| `convex/syncTokens.ts` | Legacy token CRUD (used by web settings page — to be replaced with Connected Devices) |

### Client Files

| Platform | Auth Service | Settings UI |
|----------|-------------|-------------|
| Desktop | `Services/AuthService.swift` | `Views/Settings/SettingsComponents.swift` (SettingsAccountOverviewView) |
| iOS | `CiderApp/Services/AuthService.swift` | `CiderApp/Views/SettingsView.swift` |
| Web | `@convex-dev/auth` hooks | `src/pages/login-form.tsx`, `src/pages/signup-form.tsx` |

### Connected Devices

The "Connected Devices" view shows all devices with active sync tokens. Users can remove devices (revokes their token — that device will need to sign in again).

- Desktop: `Views/Settings/ConnectedDevicesView.swift`
- Web: `src/components/settings/connected-devices.tsx` (uses `syncTokens.list` query + `syncTokens.revoke` mutation)
- iOS: `CiderApp/Views/DevicesView.swift` (DevicesSection in Settings)

### Security Notes

- Sync tokens are random 32-character strings (4 segments of 8 alphanumeric chars)
- Tokens are stored in Keychain on native clients (not UserDefaults)
- Token lookup uses an indexed query (`by_token`) — O(1) at any scale
- Passwords are never stored on the client
- HTTPS enforced for all auth endpoints (Desktop and iOS both validate URL scheme before sending credentials)
- Revoking a device immediately invalidates its token — next sync request will fail with 401

### Future Considerations

- OAuth providers (Google, Apple Sign In) — would go through `@convex-dev/auth` on web, need equivalent native flows
- Password reset flow — currently manual ("contact support"), needs self-service email reset
- Email verification — `@convex-dev/auth` supports it, not currently enforced
- JWT migration — could replace sync tokens with JWTs for a more standard approach, but sync tokens work fine at scale (indexed lookup, same pattern as Stripe/GitHub API keys)

---

## Sync Protocol

> Last validated: 2026-03-24 (Web backend: case-insensitive syncId matching, scoped parentSyncId resolution, preserve folderId on lookup failure)

> Canonical sync specification for all three Cider apps. Consolidates the per-app `SYNC_COLLABORATION.md` docs into one source of truth.
>
> **If you're working on anything sync-related, read this entire file first.**

### Sync Overview

All three clients sync bookmarks, folders, and notes through Convex. Desktop uses the **Convex Swift SDK** (`ConvexMobile`) over WebSocket, calling Convex actions (`sync:push`, `sync:pull`, etc.) directly. iOS uses the **REST HTTP endpoints** in `http.ts`. Web uses direct Convex mutations and real-time subscriptions (bypassing the REST/action layer entirely).

Dashboard topics, cards, feedback, action state, and runs are not part of sync yet. Desktop persists the first dashboard MVP locally under `.cider/dashboard/_cider_dashboard.json`. Web dashboard work must go through a schema-gate review before changing Convex schema or sync payloads.

```
Desktop (macOS)  -- Convex SDK (WebSocket) -->  Convex Backend  <-- REST (HTTP) --  iOS
                                                       ^
                                                 Web (direct mutations + subscriptions)
```

**Auth**: REST sync endpoints require `Authorization: Bearer <sync_token>`. Convex SDK actions use `sync:authenticate` to validate the token. Desktop and iOS obtain tokens automatically via the native auth endpoints (login/signup). Web uses `@convex-dev/auth` session cookies.

**Base URL**: `https://dashing-fennec-334.convex.site`

### Sync Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/sync/push` | Push bookmarks + folders from client to server |
| POST | `/api/sync/pull` | Pull changes since a timestamp |
| POST | `/api/sync/reconcile` | Full manifest of all bookmark `ciderSyncId` + `updatedAt` pairs (drift detection) |
| POST | `/api/sync/upload-thumbnail` | Upload thumbnail image for a bookmark (multipart or raw binary) |
| POST | `/api/sync/upload-note-attachment` | Upload note image attachment (Desktop) |
| POST | `/api/sync/note-attachments-check` | Batch check which note attachments already exist on server |
| POST | `/api/capture` | Quick-capture a URL (creates bookmark with `enrichmentStatus: "pending"`) |

#### Planned Endpoints (not yet in `http.ts` — iOS client fully wired as of 2026-03-23)

| Method | Path | Purpose | iOS client code |
|--------|------|---------|-----------------|
| POST | `/api/sync/purge` | Permanently delete one item: `{ type: "bookmark"\|"note", ciderSyncId }` | `SyncClient.purgeBookmark/purgeNote` — called from `DataStore.permanentlyDeleteBookmark/Note` |
| POST | `/api/sync/empty-trash` | Purge all soft-deleted items for the user -> `{ purgedBookmarks, purgedNotes, serverTime }` | `SyncClient.emptyTrash` — called from `DataStore.emptyTrash` |
| POST | `/api/tags/rename` | Rename a tag: `{ oldName, newName }` -> `{ count }` | `SyncClient.renameTag` — called from `TagManagementView` |
| POST | `/api/tags/delete` | Delete a tag: `{ name }` -> `{ count }` | `SyncClient.deleteTag` — called from `TagManagementView` |
| POST | `/api/tags/merge` | Merge tags: `{ sourceName, targetName }` -> `{ count }` | `SyncClient.mergeTag` — called from `TagManagementView` |

Backend mutations for purge already exist (`bookmarks.ts`, `notes.ts`), but the HTTP routes in `http.ts` need to be added. Tag management mutations need to be created. All routes should use the existing `authenticateSync` Bearer token pattern.

iOS also handles purge on pull: `DataStore.applyPullResponse` now checks `isPurged` on incoming bookmarks and notes and removes local copies of purged items from SwiftData.

All requests: `POST`, `Content-Type: application/json`, `Authorization: Bearer <sync_token>`.

### Push (`/api/sync/push`)

#### Request

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
  "notes": [
    {
      "ciderSyncId": "uuid-string-lowercase",
      "title": "Note Title",
      "content": "Note body text",
      "tags": ["tag1"],
      "isPinned": false,
      "folderSyncId": "folder-uuid-lowercase",
      "createdAt": 1709766000000,
      "updatedAt": 1709766000000,
      "deleted": false,
      "deletedAt": null
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

#### Accepted Bookmark Fields (STRICT)

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

#### Rejected Bookmark Fields (will cause validation failure)

Do NOT send: `_id`, `host`, `favicon`, `thumbnailUrl`, `thumbnailStorageId`, `userId`, `folderId`, `purged`, `purgedAt`, or any unlisted field.

#### Accepted Note Fields (STRICT)

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `ciderSyncId` | string | yes | Lowercase UUID |
| `title` | string | yes | |
| `content` | string | yes | |
| `tags` | string[] | no | |
| `isPinned` | boolean | no | |
| `folderSyncId` | string | no | References folder's `ciderSyncId` |
| `createdAt` | number | yes | ms since epoch |
| `updatedAt` | number | yes | ms since epoch |
| `deleted` | boolean | no | |
| `deletedAt` | number | no | ms since epoch |

#### Accepted Folder Fields (STRICT)

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

#### Response

```json
{
  "created": 2,
  "updated": 1,
  "serverTime": 1709766000000
}
```

#### Deletion Tombstones

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

#### Push-Safe Struct Pattern

Both Desktop and iOS use a dedicated push-only type to prevent accidental extra fields:

- **Desktop**: `bookmarkPayload()` / `folderPayload()` / `notePayload()` (static functions in SyncService.swift returning `[String: ConvexEncodable?]` dictionaries)
- **iOS**: `PushBookmark` (Codable struct in Shared/Bookmark.swift)

**Any new client must follow this pattern.** Never serialize a full model object directly into a push payload.

### Pull (`/api/sync/pull`)

#### Request

```json
{
  "since": 1709766000000
}
```

Use `0` to pull everything.

#### Response

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
      "purged": false,
      "purgedAt": null,
      "folderSyncId": "resolved-from-folderId"
    }
  ],
  "folders": [ ... ],
  "notes": [
    {
      "_id": "convex_doc_id",
      "ciderSyncId": "uuid-string",
      "title": "Note Title",
      "content": "Note body text",
      "tags": ["tag1"],
      "isPinned": false,
      "folderSyncId": "resolved-from-folderId",
      "createdAt": 1709766000000,
      "updatedAt": 1709766000000,
      "deleted": false,
      "deletedAt": null,
      "purged": false,
      "purgedAt": null,
      "attachments": [{ "filename": "image.png", "url": "https://convex-storage-url/..." }]
    }
  ],
  "serverTime": 1709766000000
}
```

Pull returns additional server-computed fields not accepted by push: `_id`, `host`, `favicon`, `thumbnailUrl` (resolved from `thumbnailStorageId`), `folderSyncId` (resolved from `folderId`), `purged`, `purgedAt`. Notes pull also includes `attachments` (array of `{ filename, url }` with Convex storage URLs for note image attachments).

### Conflict Resolution

**Primary rule**: Last-write-wins on `updatedAt`. Server only updates a record if `incoming.updatedAt > existing.updatedAt`.

#### Case-Insensitive SyncId Matching

All `ciderSyncId` and `folderSyncId` lookups in `syncInternal.ts` are **case-insensitive** (`.toLowerCase()` on both sides). This applies to folder parent resolution (`pushFolders`), note folder resolution (`pushNotes`), and bookmark folder resolution (`pushBookmarks`). This prevents duplicate records when clients send UUIDs with different casing.

#### Scoped Parent Resolution (Folders)

When `pushFolders` resolves `parentSyncId` -> `parentId`, it only updates folders that were **part of the current push batch** — not all of the user's folders. This prevents unrelated folders from having their parent references touched during a partial push.

#### Preserve FolderId on Lookup Failure

When `pushNotes` or `pushBookmarks` processes an incoming item with a `folderSyncId`, and the lookup fails (the referenced folder doesn't exist on the server yet), the backend **preserves the existing `folderId`** rather than clearing it to `undefined`. This prevents items from being silently unassigned when folders haven't synced yet. If `folderSyncId` is explicitly empty/null, `folderId` is still cleared (allowing "move out of folder" to propagate).

#### Conditional Patch (newer timestamp)

When the incoming push has a strictly newer `updatedAt`, core fields always overwrite. But three fields have special handling:

| Field | Condition | Why |
|-------|-----------|-----|
| `folderId` | Set if `incoming.folderSyncId` is truthy; cleared if falsy | Allows both "move into folder" and "move out of folder" to propagate |
| `aiSummary` | Only overwrite if `incoming.aiSummary !== undefined` | Prevents clients without AI data from wiping enrichment |
| `dominantColors` | Only overwrite if `incoming.dominantColors !== undefined` | Same as above |

#### Equal Timestamp Rule

When timestamps are equal, the **server is canonical** for folder assignment. Only enrichment fields (`aiSummary`, `dominantColors`) can be added if the server is missing them. This prevents bounce-back when Desktop pulls a bookmark that was moved out of a folder — Desktop preserves the server's `updatedAt` but may have a stale local `folderID`.

**Key principle**: Folder assignment changes require a strictly newer `updatedAt`. At equal timestamps, server wins.

### Sync Behavior by Platform

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

### Historical Bugs (All Fixed)

These caused a "bounce-back" cycle. Documented here so no one reintroduces them.

#### Desktop Bugs (Fixed)

| Bug | Fix | File |
|-----|-----|------|
| `updateFromSync()` used `Date()` instead of server timestamp | Now accepts and uses `remoteUpdatedAt` parameter | BookmarksStorage.swift |
| `updateFolderFromSync()` same issue | Same fix | BookmarksStorage.swift |
| Pushed ALL bookmarks every 5s | Dirty-only push via `lastSuccessfulPushAt` filter | SyncService.swift |
| Push failures were silent | Consecutive failure counter, pauses after 3+ failures | SyncService.swift |
| `updateFromSync()` used `if let folderID` — when remote had no folder, Desktop kept stale local folderID | Now explicitly handles nil `remoteFolderSyncId` by setting `syncFolderID = nil` | SyncService.swift (lines 565-572) |

### Verification Checklist

After any sync changes, verify all of these across all three platforms:

- [ ] Edit a note on Web -> pull on iOS and Desktop -> all three show the note
- [ ] Edit a note on Desktop -> check Web and iOS see it
- [ ] Edit a note on iOS -> check Web and Desktop see it
- [ ] Delete a bookmark on any platform -> verify tombstone propagates to the other two
- [ ] Create a bookmark on iOS (with `enrichmentStatus: "pending"`) -> verify Desktop enriches it
- [ ] Move a bookmark into a folder on Web -> verify Desktop and iOS see the folder assignment
- [ ] Move a bookmark out of a folder on Web -> verify it's unassigned on Desktop and iOS
