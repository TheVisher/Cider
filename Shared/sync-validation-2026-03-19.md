# Cider Sync Validation Report

**Date**: 2026-03-19 (automated run)
**Specs validated against**: SYNC_PROTOCOL.md (last validated 2026-03-18), DATA_MODEL.md (last updated 2026-03-17)

---

## Summary

Found **2 critical**, **3 medium**, and **2 low-severity** issues across the three platforms.

| Severity | Count | Platforms affected |
|----------|-------|--------------------|
| CRITICAL | 2     | Web (backend), iOS |
| MEDIUM   | 3     | Desktop, iOS       |
| LOW      | 2     | All / Spec         |

---

## CRITICAL Issues

### 1. Missing HTTP routes for iOS endpoints

**Affected files**: `Cider-Web/convex/http.ts`, `Cider-iOS/Shared/SyncClient.swift`

iOS `SyncClient.swift` implements methods that call 5 endpoints which do **not exist** in `http.ts`. These calls will return 404 errors at runtime.

| iOS Method | Endpoint Called | Status in http.ts |
|------------|----------------|-------------------|
| `purgeBookmark()` / `purgeNote()` | `POST /api/sync/purge` | **MISSING** |
| `emptyTrash()` | `POST /api/sync/empty-trash` | **MISSING** |
| `renameTag()` | `POST /api/tags/rename` | **MISSING** |
| `deleteTag()` | `POST /api/tags/delete` | **MISSING** |
| `mergeTag()` | `POST /api/tags/merge` | **MISSING** |

The spec (`SYNC_PROTOCOL.md` lines 131-141) documents these as "Planned Endpoints" and notes that backend mutations for purge already exist in `bookmarks.ts`/`notes.ts`, but the HTTP routes and tag management mutations still need to be added.

**Impact**: Any iOS user attempting to permanently delete items, empty trash, or manage tags via sync will hit errors.

### 2. iOS never pushes folders independently

**Affected files**: `Cider-iOS/CiderApp/SyncService.swift` (lines 176-192)

iOS `SyncService` has `pushBookmarks(_:)` and `pushNotes(_:)` but **no `pushFolders` method**. Both existing push methods call `SyncClient.push()` without passing folders:

- `pushBookmarks` → `client.push(bookmarks: bookmarks)` — folders defaults to `[]`
- `pushNotes` → `client.push(bookmarks: [], notes: notes)` — folders defaults to `[]`

Meanwhile, `Folder.create()` in `Bookmark.swift` (line 24) generates folders with `ciderSyncId` locally, but these are never synced to the server.

**Impact**: Folders created on iOS will not appear on Desktop or Web. Bookmarks assigned to iOS-only folders will have unresolvable `folderSyncId` references on other platforms.

---

## MEDIUM Issues

### 3. Desktop does not push `enrichmentStatus`

**Affected file**: `Cider/Sources/Cider/Services/SyncService.swift`, `bookmarkPayload()` (lines 833-851)

The spec's sync behavior table states Desktop "Runs enrichment pipeline locally, pushes `'complete'`", but `bookmarkPayload()` never includes the `enrichmentStatus` field. After Desktop enriches a bookmark (adding `aiSummary`, `dominantColors`), the status flag is not propagated.

The server-side validator (`sync.ts` line 102) accepts `enrichmentStatus: v.optional(v.string())`, so there's no technical barrier to sending it.

**Impact**: The server and other clients cannot distinguish between bookmarks that have been fully enriched vs. those that happen to have partial AI data. Other clients with server-side enrichment (Web) may redundantly re-enrich bookmarks that Desktop already completed.

### 4. Desktop does not push note `tags`

**Affected file**: `Cider/Sources/Cider/Services/SyncService.swift`, `notePayload()` (lines 890-902)

The `notePayload()` builder omits the `tags` field entirely. The server-side note validator (`sync.ts` line 123) accepts `tags: v.optional(v.array(v.string()))`.

**Impact**: Tags assigned to notes on Desktop will not sync to the server. Existing note tags on the server won't be overwritten (since the field is absent, not empty), but any new tag assignments on Desktop are lost.

### 5. Desktop `bookmarkPayload()` sends `deleted: false` unconditionally

**Affected file**: `Cider/Sources/Cider/Services/SyncService.swift`, `bookmarkPayload()` (line 843)

The bookmark push payload hardcodes `"deleted": false` for all dirty bookmarks. While this is technically correct (deleted items go through the tombstone path), it means Desktop always sends this optional field. The spec lists `deleted` as optional (`no` for required). This is functionally harmless but unnecessarily verbose — the server treats absent `deleted` the same as `false`.

---

## LOW Issues

### 6. Spec architecture diagram is outdated

**Affected file**: `Cider/Shared/SYNC_PROTOCOL.md` (lines 9-17)

The spec states: "All three clients sync bookmarks and folders through Convex HTTP endpoints" and shows Desktop using REST. In reality, Desktop uses the **Convex Swift SDK** (WebSocket-based actions via `ConvexClient`), calling `sync:push`, `sync:pull`, `sync:authenticate`, and `sync:changeSignal` directly — not the HTTP REST endpoints in `http.ts`.

The HTTP REST endpoints (`/api/sync/push`, `/api/sync/pull`) are used only by iOS. Web uses direct Convex mutations/subscriptions.

### 7. Push response format divergence between HTTP and SDK paths

**Affected files**: `Cider-Web/convex/http.ts` (line 234), `Cider-Web/convex/sync.ts` (line 171)

The two push paths return different response shapes:

| Field | HTTP endpoint (`http.ts`) | SDK action (`sync.ts`) |
|-------|--------------------------|----------------------|
| Bookmark counts | `created`, `updated` | `bookmarksCreated`, `bookmarksUpdated` |
| Folder counts | `foldersCreated`, `foldersUpdated` | Same |
| Note counts | `notesCreated`, `notesUpdated` | Same |

This doesn't cause runtime errors because:
- Desktop (SDK path) only decodes `serverTime` from `SyncPushResponse`
- iOS (HTTP path) decodes `created`, `updated`, `serverTime` from `PushResponse`

But it's a maintenance risk — if either client starts reading the other fields, they'll get different shapes depending on the transport.

---

## Passing Checks (No Issues Found)

- **Schema alignment**: `schema.ts` matches `DATA_MODEL.md` for all tables (bookmarks, folders, notes, syncTokens, tabs)
- **Timestamp convention**: All three platforms use milliseconds since epoch consistently
- **UUID convention**: Desktop uses `.lowercased()`, iOS uses `.lowercased()`, Web uses `crypto.randomUUID()` (already lowercase)
- **Push-safe struct pattern**: Both Desktop (`bookmarkPayload`/`folderPayload`/`notePayload`) and iOS (`PushBookmark`/`PushFolder`/`PushNote`) use dedicated push-only types, never serializing full model objects
- **Bookmark push validators**: `sync.ts` `bookmarkValidator` matches the spec's accepted fields exactly
- **Folder push validators**: `sync.ts` `folderValidator` matches spec
- **Note push validators**: `sync.ts` `noteValidator` matches spec
- **Conflict resolution**: Both Desktop and iOS use strict `>` comparison on `updatedAt` for last-write-wins, matching the spec
- **Deletion tombstones**: Desktop and iOS both produce tombstones matching the spec format
- **Pull response handling**: Desktop and iOS correctly process pulled bookmarks, folders, and notes, including soft-delete propagation
- **Auth endpoints**: All 5 native auth routes (`login`, `signup`, `account`, `devices`, `devices/revoke`) exist in `http.ts` and match the spec
- **Sync endpoints**: Core sync routes (`push`, `pull`, `reconcile`, `upload-thumbnail`, `capture`) exist in `http.ts`
- **Bearer token auth**: `authenticateSync()` in `http.ts` correctly parses `Authorization: Bearer <token>` headers
- **Desktop folder assignment on pull**: `SyncService.swift` (lines 560-567) now explicitly handles nil `remoteFolderSyncId` by setting `syncFolderID = nil`, which addresses the "Remaining Desktop Issue" noted in the spec (though `BookmarksStorage.updateFromSync` implementation was not checked)

---

*Next scheduled run: 2026-03-20*
