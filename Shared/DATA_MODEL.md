# Data Model

> Canonical Convex schema reference. The actual schema lives in `Cider-Web/convex/schema.ts` — this doc mirrors it with annotations for all three platforms.
>
> **If the schema changes, update this doc. If this doc and the schema disagree, the schema wins.**
>
> **Last updated**: 2026-03-15

## Bookmarks Table

```typescript
bookmarks: defineTable({
  // Identity
  userId: v.id("users"),                           // Set by server from auth token
  ciderSyncId: v.optional(v.string()),              // Lowercase UUID from client. Primary sync key.

  // Core content
  title: v.string(),
  urlString: v.string(),
  host: v.optional(v.string()),                     // Extracted from URL server-side
  notes: v.optional(v.string()),
  tags: v.array(v.string()),

  // Media
  thumbnailStorageId: v.optional(v.id("_storage")), // Convex storage ref (from upload-thumbnail)
  originalImageStorageId: v.optional(v.id("_storage")),
  thumbnailRemoteUrl: v.optional(v.string()),       // External thumbnail URL
  favicon: v.optional(v.string()),                  // Favicon URL

  // Intelligence (from Desktop enrichment or server-side action)
  aiSummary: v.optional(v.string()),
  dominantColors: v.optional(v.array(v.string())),  // Hex color strings
  enrichmentStatus: v.optional(v.string()),         // "pending" | "complete"

  // Organization
  folderId: v.optional(v.id("folders")),            // Server-side folder reference

  // Timestamps (milliseconds since epoch)
  createdAt: v.number(),
  updatedAt: v.number(),

  // Soft delete
  deleted: v.optional(v.boolean()),
  deletedAt: v.optional(v.number()),

  // Sync metadata
  lastSyncedAt: v.optional(v.number()),

  // Permanent delete (for trash cleanup)
  purged: v.optional(v.boolean()),
  purgedAt: v.optional(v.number()),
})
  .index("by_user", ["userId"])
  .index("by_user_deleted", ["userId", "deleted"])
  .index("by_user_created", ["userId", "createdAt"])
  .index("by_sync_id", ["userId", "ciderSyncId"])
  .searchIndex("search_title", { searchField: "title", filterFields: ["userId", "deleted"] })
```

### Field Notes

| Field | Push-safe? | Pull-only? | Notes |
|-------|-----------|------------|-------|
| `userId` | NO | Server-set | Derived from auth token. Never send in push. |
| `ciderSyncId` | YES | — | The cross-platform identity key. Always lowercase. |
| `host` | NO | YES | Server extracts from `urlString`. |
| `favicon` | NO | YES | Server-fetched. |
| `thumbnailStorageId` | NO | YES | Internal Convex storage ref. |
| `thumbnailUrl` | NO | YES | Resolved URL from `thumbnailStorageId`. Computed at pull time. |
| `folderId` | NO | — | Server-side ref. Use `folderSyncId` in push payloads instead. |
| `purged` / `purgedAt` | NO | YES | For permanent delete propagation. Desktop should remove purged items locally. |
| Everything else | YES | — | See SYNC_PROTOCOL.md for the exact push schema. |

## Folders Table

```typescript
folders: defineTable({
  userId: v.id("users"),
  name: v.string(),
  icon: v.optional(v.string()),                     // Icon name (SF Symbol on Desktop, Lucide on Web)
  parentId: v.optional(v.id("folders")),            // Nested folders
  parentSyncId: v.optional(v.string()),             // For sync — references parent folder's ciderSyncId
  ciderSyncId: v.optional(v.string()),              // Lowercase UUID
  createdAt: v.number(),
  updatedAt: v.number(),
  deleted: v.optional(v.boolean()),
  deletedAt: v.optional(v.number()),

  // Permanent delete (for trash cleanup — same as bookmarks)
  purged: v.optional(v.boolean()),
  purgedAt: v.optional(v.number()),
})
  .index("by_user", ["userId"])
  .index("by_sync_id", ["userId", "ciderSyncId"])
```

### Icon Mapping

Desktop uses SF Symbols, Web uses Lucide icons. A mapping exists in the Web codebase for the 22 most common icons. When a folder is created on one platform and synced to the other, the icon name is translated.

## Sync Tokens Table

```typescript
syncTokens: defineTable({
  userId: v.id("users"),
  name: v.string(),
  token: v.string(),                                // The bearer token string
  createdAt: v.number(),
  lastUsedAt: v.optional(v.number()),               // Updated on each authenticated request
  revoked: v.optional(v.boolean()),                  // True if device has been revoked
})
  .index("by_user", ["userId"])
  .index("by_token", ["token"])
```

## Notes Table

```typescript
notes: defineTable({
  userId: v.id("users"),

  // Core
  title: v.string(),
  content: v.string(),                              // Markdown

  // Organization
  folderId: v.optional(v.string()),                 // String (not v.id) — safer for sync
  folderSyncId: v.optional(v.string()),             // Desktop sync resolution
  tags: v.optional(v.array(v.string())),
  isPinned: v.optional(v.boolean()),

  // Sync
  ciderSyncId: v.optional(v.string()),              // Desktop UUID (lowercase)

  // Timestamps (ms since epoch)
  createdAt: v.number(),
  updatedAt: v.number(),

  // Soft delete
  deleted: v.optional(v.boolean()),
  deletedAt: v.optional(v.number()),

  // Permanent delete
  purged: v.optional(v.boolean()),
  purgedAt: v.optional(v.number()),
})
  .index("by_user", ["userId"])
  .index("by_user_deleted", ["userId", "deleted"])
  .index("by_sync_id", ["userId", "ciderSyncId"])
  .searchIndex("search_title", { searchField: "title", filterFields: ["userId", "deleted"] })
```

### Field Notes

| Field | Notes |
|-------|-------|
| `folderId` | Stored as string (not Convex ID) for safer sync + folder deletion handling. |
| `folderSyncId` | Used by Desktop to resolve folder references during sync. |
| `content` | Markdown format. Desktop and Web use TipTap for rich text editing. |

## Tabs Table (Saved Views)

```typescript
tabs: defineTable({
  userId: v.id("users"),
  label: v.string(),
  type: v.union(v.literal("tag"), v.literal("folder"), v.literal("search"), v.literal("savedView")),

  // Filter payload (one set per type)
  tagName: v.optional(v.string()),
  folderId: v.optional(v.string()),                 // String, not v.id — safer for sync
  folderSyncId: v.optional(v.string()),
  searchQuery: v.optional(v.string()),

  // SavedView configuration
  isBlank: v.optional(v.boolean()),                 // true = "New Tab" welcome page
  contentTypes: v.optional(v.array(v.string())),    // e.g. ["bookmark", "note"]
  filterTags: v.optional(v.array(v.string())),
  onlyUnassigned: v.optional(v.boolean()),
  showComingUp: v.optional(v.boolean()),

  // Sort spec
  sortMode: v.optional(v.string()),                 // "createdDesc" | "createdAsc" | "updatedDesc" | etc.

  // Layout spec
  displayMode: v.optional(v.string()),              // "grid" | "list" | "masonry"
  cardSizeScale: v.optional(v.number()),            // 0-3

  // Ordering
  position: v.number(),

  // Sync
  ciderSyncId: v.string(),                          // Required (not optional like other tables)

  // Timestamps
  createdAt: v.number(),
  updatedAt: v.number(),

  // Soft delete
  deleted: v.optional(v.boolean()),
  deletedAt: v.optional(v.number()),
})
  .index("by_user", ["userId"])
  .index("by_sync_id", ["userId", "ciderSyncId"])
```

### Cleanup Note

Tabs are hard-deleted immediately by the cleanup cron when `deleted: true` — no 30-day purge cycle like bookmarks, notes, and folders.

## Auth Tables

Convex auth tables (`users`, `authAccounts`, `authSessions`, etc.) are managed by `@convex-dev/auth`. See Convex docs for their schema — don't modify them directly.

## Timestamp Convention

All timestamps across all tables and all platforms are **milliseconds since epoch**.

- **Swift**: `Date().timeIntervalSince1970 * 1000`
- **JavaScript**: `Date.now()`
- **Convex queries**: Compare directly as numbers

## UUID Convention

All `ciderSyncId` values (bookmarks and folders) are **lowercase UUIDs**.

- **Swift**: `UUID().uuidString.lowercased()`
- **JavaScript**: `crypto.randomUUID()` (already lowercase)

This matters because Swift's `UUID().uuidString` is uppercase by default. Forgetting `.lowercased()` will create duplicate records on sync.
