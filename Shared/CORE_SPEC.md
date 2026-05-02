# Cider Core Specification

Cross-platform specification covering the data model, design language, and ecosystem architecture shared by all three Cider apps.

## Table of Contents

- [Ecosystem](#ecosystem)
- [Data Model](#data-model)
- [Design Language](#design-language)

---

## Ecosystem

> **Every agent working on any Cider app must read this file first.**
> This is the single source of truth for how the three Cider apps relate to each other and to the shared backend.
>
> **Last updated**: 2026-03-21

### Architecture

```
Desktop (Cider macOS)  -- SDK (WebSocket) -->  Convex Backend  <-- REST (HTTP) --  iOS (Cider iOS)
      native Swift/SwiftUI                           ^                              native Swift/SwiftUI
                                                Cider Web
                                          React + Convex client
                                       (direct mutations + subscriptions)
```

All three clients share one Convex deployment. Desktop uses the Convex Swift SDK (`ConvexMobile`) over WebSocket to call Convex actions directly. iOS uses REST HTTP endpoints. Web uses Convex's real-time client directly (subscriptions for reads, mutations for writes) and hosts the REST endpoints that iOS calls.

### The Three Apps

| | Cider (Desktop) | Cider Web | Cider iOS |
|---|---|---|---|
| **Path** | `../Cider/` (this repo) | `../Cider-Web/` | `../Cider-iOS/` |
| **Tech** | Swift 6, SwiftUI, AppKit (NSPanel) | React 19, Convex, TanStack Router, Tailwind v4 | Swift 6, SwiftUI (iOS 17+) |
| **Role** | Primary app. Local-first with cloud sync. Bookmarks, notes, projects, AI enrichment. | Web companion + Convex backend host. Bookmark capture, browse, organize. | Mobile capture companion. Bookmarks + Share Extension. |
| **Storage** | Local files in `~/CiderVault/` + Convex sync | Convex (server-side only) | SwiftData local persistence + offline queue + disk image cache (App Group shared) |
| **Sync method** | Convex Swift SDK (`ConvexMobile`) over WebSocket — event-driven push (2s debounce on local change) + reactive pull via `changeSignal` subscription (3s debounce) | Direct Convex mutations + subscriptions | REST push/pull (`/api/sync/push`, `/api/sync/pull`) + offline queue (QueueDrainer) |
| **Deploy** | Direct (macOS app, Sparkle updates) | Vercel (auto-deploy from main) at cider.so | Xcode / TestFlight |

### Convex Backend

- **Dev deployment** (currently live): `dashing-fennec-334`
- **HTTP base URL**: `https://dashing-fennec-334.convex.site`
- **Prod deployment** (unused): `spotted-sockeye-736`
- **Auth model**: Email/password accounts via `@convex-dev/auth`. Desktop and iOS authenticate via `/api/auth/login` (returns sync token automatically). Web uses Convex session cookies for its direct client. Connected Devices management available on all platforms via `/api/auth/devices`. See the [Sync](#sync) doc for full auth details.
- **Schema lives in**: `Cider-Web/convex/schema.ts`
- **Sync API lives in**: `Cider-Web/convex/sync.ts` + `Cider-Web/convex/http.ts`

### Universal Rules (All Platforms)

These conventions must be identical across all three apps:

- **`ciderSyncId`**: Always `UUID` lowercased. Swift: `UUID().uuidString.lowercased()`. JS: `crypto.randomUUID()`.
- **Timestamps**: Milliseconds since epoch. Swift: `Date().timeIntervalSince1970 * 1000`. JS: `Date.now()`.
- **Soft delete**: Set `deleted: true` + `deletedAt` timestamp. Never hard-delete bookmarks.
- **Enrichment status**: Desktop pushes `"complete"` (already enriched locally). iOS and Web push `"pending"` (Desktop will enrich on next pull).
- **Conflict resolution**: Last-write-wins on `updatedAt`. Server only updates if `incoming.updatedAt > existing.updatedAt`.

### Shared Docs (This Folder)

| Doc | What it covers |
|-----|----------------|
| `CORE_SPEC.md` | You're reading it. Ecosystem, data model, design language. |
| `SYNC.md` | Sync protocol (REST + Convex SDK), auth, request/response schemas, conflict resolution. |
| `FEATURE_PARITY.md` | What features each app has. Updated regularly. |
| `DASHBOARD.md` | Shared personal dashboard model, Desktop/Web roles, and schema-gated sync rules. |
| `CLOUDFLARE_ENRICHMENT.md` | Backend enrichment service, referenced by web repo. |

### Cross-References

Each app also has its own docs for platform-specific concerns:

- **Desktop**: `Cider/Docs/` — design system, architecture, floating panel, SwiftUI gotchas, TipTap editor, etc.
- **iOS**: `Cider-iOS/docs/` + `DESIGN_SYSTEM.md`, `AGENT_BRIEF.md`, `ROADMAP.md`
- **Web**: `Cider-Web/docs/` + `ROADMAP.md`

**Rule**: If information applies to more than one app, it belongs in `Shared/`. If it's platform-specific, it stays in that app's docs.

---

## Data Model

> Canonical Convex schema reference. The actual schema lives in `Cider-Web/convex/schema.ts` — this doc mirrors it with annotations for all three platforms.
>
> **If the schema changes, update this doc. If this doc and the schema disagree, the schema wins.**
>
> **Last updated**: 2026-03-21

### Bookmarks Table

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

#### Bookmark Field Notes

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
| Everything else | YES | — | See SYNC.md for the exact push schema. |

### Folders Table

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

#### Icon Mapping

Desktop uses SF Symbols, Web uses Lucide icons. A mapping exists in the Web codebase for the 22 most common icons. When a folder is created on one platform and synced to the other, the icon name is translated.

### Sync Tokens Table

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

### Notes Table

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

#### Notes Field Notes

| Field | Notes |
|-------|-------|
| `folderId` | Stored as string (not Convex ID) for safer sync + folder deletion handling. |
| `folderSyncId` | Used by Desktop to resolve folder references during sync. |
| `content` | Markdown format. Desktop and Web use TipTap for rich text editing. |

### Tabs Table (Saved Views)

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
  hideCardFooters: v.optional(v.boolean()),         // Hide card footer text (title/host)
  showDetailsOnHover: v.optional(v.boolean()),      // Reveal details on hover instead

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

#### Cleanup Note

Tabs are hard-deleted immediately by the cleanup cron when `deleted: true` — no 30-day purge cycle like bookmarks, notes, and folders.

### Note Attachments Table

> **TODO**: This table exists in `schema.ts` but has not been documented here yet. It stores metadata for note image attachments uploaded via `/api/sync/upload-note-attachment`. Check `Cider-Web/convex/schema.ts` for the current schema definition.

### Auth Tables

Convex auth tables (`users`, `authAccounts`, `authSessions`, etc.) are managed by `@convex-dev/auth`. See Convex docs for their schema — don't modify them directly.

### Timestamp Convention

All timestamps across all tables and all platforms are **milliseconds since epoch**.

- **Swift**: `Date().timeIntervalSince1970 * 1000`
- **JavaScript**: `Date.now()`
- **Convex queries**: Compare directly as numbers

### UUID Convention

All `ciderSyncId` values (bookmarks and folders) are **lowercase UUIDs**.

- **Swift**: `UUID().uuidString.lowercased()`
- **JavaScript**: `crypto.randomUUID()` (already lowercase)

This matters because Swift's `UUID().uuidString` is uppercase by default. Forgetting `.lowercased()` will create duplicate records on sync.

---

## Design Language

> Cross-platform design principles shared by all three Cider apps. Platform-specific tokens and implementation details live in each app's own design system docs.

### Philosophy

Cider's visual identity is consistent across Desktop, Web, and iOS. The apps should feel like they belong to the same family, even though each respects its platform's native conventions.

#### Core Principles

1. **Dark-first, monochromatic with accent** — white-based surfaces on dark backgrounds, system accent for interactive elements.
2. **Content over chrome** — minimize decoration, let content breathe.
3. **Semantic opacity scale** — consistent progression for surfaces (subtle -> elevated -> input -> hover) and borders (subtle -> default -> hover -> strong).
4. **Continuous corners** — always continuous/squircle, never circular. Swift: `.continuous` RoundedRectangle. CSS: not natively supported but approximated.
5. **Physics-based motion** — springs, not easing curves. Desktop: SwiftUI `.spring()`. Web: CSS `transition` with spring-like timing.
6. **Respect system settings** — Reduce Motion, Dynamic Type, Reduce Transparency, accent color.
7. **Restraint** — fewer effects done perfectly beats many effects done approximately.

### Shared Token Scale

These values are identical across all three platforms:

#### Spacing (4pt base grid)

| Token | Value |
|-------|-------|
| xs | 4pt |
| sm | 8pt |
| md | 12pt |
| lg | 16pt |
| xl | 20pt |
| xxl | 24pt |
| xxxl | 32pt |

Desktop also has `hairline` (1pt) and `xxs` (2pt) for fine-grained layout.

#### Corner Radii

| Token | Value | Usage |
|-------|-------|-------|
| xs | 4pt | Badges, tags |
| sm | 6pt | Buttons, pills, search fields |
| md | 10pt | Cards, containers |
| lg | 14pt | Panels, major surfaces |
| xl | 20pt | Reserved |

#### Surface Hierarchy (white-based opacity)

| Level | Opacity | Usage |
|-------|---------|-------|
| Highlight | 0.03 | Shimmer, subtle shine |
| Subtle | 0.04 | Empty states, faint backgrounds |
| Elevated | 0.06 | Cards, containers, sidebar |
| Input | 0.07 | Text fields, form elements |
| Hover | 0.08-0.10 | Hover states |

#### Border Hierarchy (white-based opacity)

| Level | Opacity | Usage |
|-------|---------|-------|
| Subtle | 0.08 | Default card borders |
| Default | 0.12 | Visible borders |
| Hover | 0.18-0.20 | Hover state borders |
| Strong | 0.25 | Active/selected borders |

### Platform-Specific Tokens

Each platform adapts the shared language to its native conventions:

#### Desktop (macOS)
- **Token files**: `Sources/Cider/Utilities/Constants.swift`, `CiderFont.swift`
- **Colors**: `CiderColors.*` — includes acrylic material palette (NSVisualEffectView)
- **Typography**: macOS system font sizes (10pt caption through 20pt display)
- **Animations**: SwiftUI `.spring()` variants (smooth, snappy, bouncy)
- **Full spec**: `Cider/Docs/Design/DESIGN_SYSTEM.md`

#### iOS
- **Token files**: `Shared/CiderColors.swift`, `Shared/CiderFont.swift`, `Shared/CiderSpacing.swift`
- **Colors**: Same opacity scale as Desktop, adapted for iOS rendering
- **Typography**: Scaled up from Desktop for mobile reading distance (12pt caption through 24pt display)
- **Animations**: SwiftUI `.spring()`, respects `accessibilityReduceMotion`
- **Full spec**: `Cider-iOS/DESIGN_SYSTEM.md`

#### Web
- **Token files**: `src/styles.css` (CSS custom properties `--cider-*`)
- **Colors**: Same opacity scale as CSS vars. Accent color is **amber** (not system blue)
- **Typography**: CSS rem-based scale matching the Desktop proportions
- **Animations**: `transition-all duration-200` for most interactions
- **Full spec**: Inline in `Cider-Web/CLAUDE.md`

### Visual Consistency Rules

- **Thumbnail fallbacks**: All three apps use a gradient fallback when no thumbnail exists — URL-hash-based color pair with the domain's first letter. The gradient algorithm should produce the same colors for the same URL across platforms.
- **Favicon display**: Show favicon next to the host/domain text when available.
- **Tag pills**: Small rounded badges, capped display (show 3 + "+N" overflow).
- **Relative timestamps**: "2 days ago" format, not raw dates.
- **Dark mode**: All apps are dark-first. Desktop is dark-only. Web and iOS support light mode as secondary.
