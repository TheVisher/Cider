# Cider Sync Validation Report

**Date**: 2026-03-20 (automated daily run)
**Specs validated against**: SYNC_PROTOCOL.md (last validated 2026-03-19), DATA_MODEL.md (last updated 2026-03-17)

---

## Summary

**4 issues found, 3 informational notes.**

| Severity | Count | Description |
|----------|-------|-------------|
| 🔴 High | 1 | 5 planned HTTP endpoints missing — iOS client already calls them |
| 🟡 Medium | 2 | Desktop missing `enrichmentStatus` and `tags` in push payloads |
| 🟢 Low | 1 | `noteAttachments` table and 2 HTTP routes not documented in specs |
| ℹ️ Info | 3 | Spec outdated in 3 areas (see below) |

---

## 🔴 High: Missing HTTP Endpoints (iOS Calling Non-Existent Routes)

**Files**: `Cider-Web/convex/http.ts` (missing routes), `Cider-iOS/Shared/SyncClient.swift` (client calling them)

The SYNC_PROTOCOL.md documents these as "Planned Endpoints" and the iOS client already implements calls to all five, but **none exist in http.ts**:

| Endpoint | iOS Method | http.ts status |
|----------|-----------|----------------|
| `POST /api/sync/purge` | `SyncClient.purgeBookmark()` (line 92), `purgeNote()` (line 99) | ❌ Not implemented |
| `POST /api/sync/empty-trash` | `SyncClient.emptyTrash()` (line 106) | ❌ Not implemented |
| `POST /api/tags/rename` | `SyncClient.renameTag()` (line 159) | ❌ Not implemented |
| `POST /api/tags/delete` | `SyncClient.deleteTag()` (line 170) | ❌ Not implemented |
| `POST /api/tags/merge` | `SyncClient.mergeTag()` (line 181) | ❌ Not implemented |

**Impact**: Any iOS user triggering purge, empty-trash, or tag management will get server errors. These are runtime failures.

---

## 🟡 Medium: Desktop Not Pushing `enrichmentStatus`

**File**: `Cider/Sources/Cider/Services/SyncService.swift`, `bookmarkPayload()` (line 838)

The spec's behavior table states Desktop "Runs enrichment pipeline locally, pushes `'complete'`", but `bookmarkPayload()` never includes the `enrichmentStatus` field. The payload includes `aiSummary` and `dominantColors` (the enrichment results), but omits the status marker.

**Impact**: Server-side enrichmentStatus for Desktop-enriched bookmarks remains `"pending"` even after enrichment is done. This could cause the server-side enrichment action to re-process bookmarks that Desktop already enriched, or cause iOS/Web to display incorrect enrichment state.

---

## 🟡 Medium: Desktop Not Pushing Note `tags`

**File**: `Cider/Sources/Cider/Services/SyncService.swift`, `notePayload()` (line 895)

The note push payload includes `ciderSyncId`, `title`, `content`, `createdAt`, `updatedAt`, `deleted`, `isPinned`, and `folderSyncId` — but **never includes `tags`**. The Convex note validator accepts `tags: v.optional(v.array(v.string()))`, so this won't cause validation failures, but note tags will never sync from Desktop to server.

By comparison, iOS's `PushNote` struct (line 248 of `Cider-iOS/Shared/Bookmark.swift`) correctly includes `tags`.

---

## 🟢 Low: Undocumented Endpoints and Table

**Endpoints in http.ts not listed in SYNC_PROTOCOL.md:**

- `POST /api/sync/upload-note-attachment` (http.ts line 310) — Used by Desktop for note image uploads
- `POST /api/sync/note-attachments-check` (http.ts line 345) — Batch check for existing attachments

**Table in schema.ts not listed in DATA_MODEL.md:**

- `noteAttachments` table (schema.ts line 154) — Stores note image attachment metadata

These all work correctly but should be documented in the specs for completeness.

---

## ℹ️ Informational: Spec Outdated in 3 Areas

### 1. "Remaining Desktop Issue" appears fixed

SYNC_PROTOCOL.md (line 349) states: *"`updateFromSync()` uses `if let folderID` to set folder — when remote has no folder, this is a no-op and Desktop keeps the stale local folderID."*

SyncService.swift (lines 565-572) now explicitly handles this:
```swift
if remoteFolderSyncId == nil {
    syncFolderID = nil  // remote explicitly has no folder
} else if let resolvedFolderID {
    syncFolderID = resolvedFolderID
} else {
    syncFolderID = local.folderID  // can't resolve — preserve local
}
```
The spec's "Remaining Desktop Issue" section can be moved to "Historical Bugs (All Fixed)".

### 2. Desktop uses Convex SDK, not REST

The spec overview diagram shows `Desktop (macOS) ── REST ──> Convex Backend`, but Desktop actually uses the Convex Swift SDK (`ConvexMobile`) with WebSocket subscriptions and calls `sync:push`/`sync:pull` Convex actions directly — not the HTTP/REST endpoints in http.ts. This is functionally equivalent (the actions call the same internal mutations) but the spec should reflect the actual transport.

### 3. Push response shape differs between REST and SDK paths

The spec documents the push response as `{ created, updated, serverTime }`. The HTTP endpoint (http.ts line 234) returns additional fields: `foldersCreated`, `foldersUpdated`, `notesCreated`, `notesUpdated`. The Convex SDK action (sync.ts line 171) returns `bookmarksCreated`, `bookmarksUpdated` instead of `created`, `updated`. Both are backward-compatible but inconsistent with each other and the spec.

---

## ✅ Passing Checks

- **Bookmark push fields**: All three platforms send only spec-approved fields (no rejected fields like `_id`, `host`, `purged`, etc.)
- **Folder push fields**: All three platforms match the spec's accepted folder fields
- **Timestamp format**: All platforms use milliseconds since epoch consistently
- **UUID convention**: All platforms use `.lowercased()` UUIDs
- **Conflict resolution**: Desktop and server both use last-write-wins on `updatedAt`
- **Deletion tombstones**: Desktop and iOS both produce spec-compliant tombstones
- **Auth flow**: Bearer token pattern consistent across all endpoints
- **schema.ts ↔ DATA_MODEL.md**: All documented tables match (bookmarks, folders, syncTokens, notes, tabs)
- **Pull response handling**: Desktop and iOS correctly decode all pull fields including server-computed ones
- **Push-safe struct pattern**: Both Desktop (`bookmarkPayload()`) and iOS (`PushBookmark`) use dedicated push types to avoid extra fields
