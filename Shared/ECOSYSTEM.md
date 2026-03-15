# Cider Ecosystem

> **Every agent working on any Cider app must read this file first.**
> This is the single source of truth for how the three Cider apps relate to each other and to the shared backend.
>
> **Last updated**: 2026-03-14

## Architecture

```
Desktop (Cider macOS)  <-->  Convex Backend  <-->  iOS (Cider iOS)
      native Swift/SwiftUI         ^                 native Swift/SwiftUI
                              Cider Web
                          React + Convex client
```

All three clients share one Convex deployment. Desktop and iOS talk to it via REST endpoints. Web uses Convex's real-time client directly (subscriptions for reads, mutations for writes) and only uses the REST layer for the sync API that Desktop/iOS call.

## The Three Apps

| | Cider (Desktop) | Cider Web | Cider iOS |
|---|---|---|---|
| **Path** | `../Cider/` (this repo) | `../Cider-Web/` | `../Cider-iOS/` |
| **Tech** | Swift 6, SwiftUI, AppKit (NSPanel) | React 19, Convex, TanStack Router, Tailwind v4 | Swift 6, SwiftUI (iOS 17+) |
| **Role** | Primary app. Local-first with cloud sync. Bookmarks, notes, projects, AI enrichment. | Web companion + Convex backend host. Bookmark capture, browse, organize. | Mobile capture companion. Bookmarks + Share Extension. |
| **Storage** | Local files in `~/CiderVault/` + Convex sync | Convex (server-side only) | SwiftData local persistence + offline queue + disk image cache (App Group shared) |
| **Sync method** | REST polling every 5s (`/api/sync/push`, `/api/sync/pull`) | Direct Convex mutations + subscriptions | REST push/pull (same endpoints as Desktop) + offline queue (QueueDrainer) |
| **Deploy** | Direct (macOS app, Sparkle updates) | Vercel (auto-deploy from main) at cider.so | Xcode / TestFlight |

## Convex Backend

- **Dev deployment** (currently live): `dashing-fennec-334`
- **HTTP base URL**: `https://dashing-fennec-334.convex.site`
- **Prod deployment** (unused): `spotted-sockeye-736`
- **Auth model**: Email/password accounts via `@convex-dev/auth`. Desktop and iOS authenticate via `/api/auth/login` (returns sync token automatically). Web uses Convex session cookies. Legacy sync tokens still work for backward compatibility.
- **Schema lives in**: `Cider-Web/convex/schema.ts`
- **Sync API lives in**: `Cider-Web/convex/sync.ts` + `Cider-Web/convex/http.ts`

## Universal Rules (All Platforms)

These conventions must be identical across all three apps:

- **`ciderSyncId`**: Always `UUID` lowercased. Swift: `UUID().uuidString.lowercased()`. JS: `crypto.randomUUID()`.
- **Timestamps**: Milliseconds since epoch. Swift: `Date().timeIntervalSince1970 * 1000`. JS: `Date.now()`.
- **Soft delete**: Set `deleted: true` + `deletedAt` timestamp. Never hard-delete bookmarks.
- **Enrichment status**: Desktop pushes `"complete"` (already enriched locally). iOS and Web push `"pending"` (Desktop will enrich on next pull).
- **Conflict resolution**: Last-write-wins on `updatedAt`. Server only updates if `incoming.updatedAt > existing.updatedAt`.

## Shared Docs (This Folder)

| Doc | What it covers |
|-----|----------------|
| `ECOSYSTEM.md` | You're reading it. How the apps relate, universal rules. |
| `SYNC_PROTOCOL.md` | REST endpoints, request/response schemas, push/pull contract, conflict resolution details, known edge cases. |
| `DATA_MODEL.md` | Canonical Convex schema — every table, every field, every index. |
| `DESIGN_LANGUAGE.md` | Cross-platform design principles shared by all three apps. |
| `FEATURE_PARITY.md` | What features each app has. Updated regularly. |

## Cross-References

Each app also has its own docs for platform-specific concerns:

- **Desktop**: `Cider/Docs/` — design system, architecture, floating panel, SwiftUI gotchas, TipTap editor, etc.
- **iOS**: `Cider-iOS/docs/` + `DESIGN_SYSTEM.md`, `AGENT_BRIEF.md`, `ROADMAP.md`
- **Web**: `Cider-Web/docs/` + `ROADMAP.md`

**Rule**: If information applies to more than one app, it belongs in `Shared/`. If it's platform-specific, it stays in that app's docs.
