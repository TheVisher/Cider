# Feature Parity

> What each app has, doesn't have, and what's planned. This is the go-to reference for deciding what to build next on any platform.
>
> **Last updated**: 2026-03-16

Legend: Yes = shipped, No = not built, Planned = on roadmap, N/A = not applicable to this platform

## Core Features

| Feature | Desktop | Web | iOS |
|---------|---------|-----|-----|
| Bookmark CRUD | Yes | Yes | Yes |
| Notes CRUD | Yes | Yes (rich text) | Yes |
| Bookmark sync (push/pull) | Yes | Yes (direct mutations) | Yes |
| Folder sync | Yes | Yes | Yes |
| Soft delete / trash | Yes | Yes | Yes |
| Trash view / restore | Yes | Yes | Yes |
| Permanent delete (purge) | Yes | Yes (30-day cron) | No |
| Search | Yes | Yes | Yes (local filter) |
| Tags | Yes | Yes | Yes (display only) |
| Share Extension | N/A | N/A | Yes |

## Organization

| Feature | Desktop | Web | iOS |
|---------|---------|-----|-----|
| Folders / collections | Yes | Yes | Yes |
| Nested folders (tree) | Yes | Yes | Yes |
| Folder icons | Yes (SF Symbols) | Yes (Lucide) | Yes (SF Symbols + emoji) |
| Move to folder | Yes | Yes (context menu + drag-and-drop) | Yes (context menu + detail) |
| Tag management (rename/merge/delete) | Yes | Yes | No |
| Tag filtering | Yes | Yes (AND/OR toggle) | Yes (multi-tag filter panel) |
| Saved views / smart filters | Yes | Yes (tabs) | Planned (M16) |

## Display & Layout

| Feature | Desktop | Web | iOS |
|---------|---------|-----|-----|
| Grid view | Yes | Yes | Yes |
| List view (table) | Yes (unified table w/ columns) | Yes (table w/ configurable columns) | Yes (configurable columns) |
| Masonry view | Yes | Yes | Yes |
| Card size slider | Yes | Yes (per-view, debounced) | Yes (3 levels) |
| Sidebar | Yes | Yes (collapsible) | Yes (tab bar) |
| Detail panel (slide-out) | Yes | Yes | Yes (sheet) |
| Hide card details (hover reveal) | Yes | Yes | No |
| Keyboard shortcuts | Yes | Partial (Cmd+K search, Cmd+B sidebar) | No |

## Capture & Input

| Feature | Desktop | Web | iOS |
|---------|---------|-----|-----|
| Add bookmark (form) | Yes | Yes | Yes |
| Quick paste capture | Yes | Yes | Planned (M14) |
| URL metadata auto-fetch | Yes (full enrichment) | Yes (server action) | Yes (title only) |
| Share Extension | N/A | N/A | Yes |
| Bookmarklet | N/A | Yes | N/A |
| PWA share target | N/A | Yes | N/A |
| Browser extension | N/A | Planned | N/A |
| Clipboard detection | Yes | Yes (global paste-to-capture) | Planned (M10) |
| Browser session capture | Yes (Safari + Chromium) | Planned | N/A |
| Session restore (any browser) | Yes | Planned | N/A |
| Session tab → bookmark | Yes | Planned | N/A |

## Visual & Media

| Feature | Desktop | Web | iOS |
|---------|---------|-----|-----|
| Thumbnails | Yes (local + remote) | Yes (Convex storage + remote) | Yes (remote + disk cache) |
| Thumbnail upload to Convex | Planned | Endpoint exists | No |
| Favicon display | Yes | Yes | Yes |
| Gradient fallbacks | Yes | Yes | Yes |
| Dominant colors | Yes (extracted locally) | Yes (from Desktop) | Yes (from Desktop) |
| Dark mode | Yes (only) | Yes (default) | Yes (only) |
| Light mode | No | Yes | No |

## Intelligence & AI

| Feature | Desktop | Web | iOS |
|---------|---------|-----|-----|
| AI summaries (generate) | Yes (local) | Planned (needs API key) | No |
| AI summaries (display) | Yes | Yes | Yes |
| AI chat | Yes | No | No |
| Auto-enrichment pipeline | Yes | Partial (server action) | No |

## Sync & Auth

| Feature | Desktop | Web | iOS |
|---------|---------|-----|-----|
| Sync token auth | Yes | Yes (generates tokens) | Yes |
| Account-based auth | Yes (email/password) | Yes (email/password) | Yes (email/password) |
| Connected Devices (view/revoke) | Yes | Yes | Yes |
| OAuth (Google/GitHub/Apple) | No | Planned | No |
| Account-based sync (replace tokens) | Yes (login returns sync token) | Planned | Yes (login returns sync token) |
| Background sync | Yes (5s poll) | Yes (real-time subscriptions) | Yes (30s poll + offline queue) |
| Dirty-only push | Yes | N/A | Yes (offline queue + immediate push) |
| Failure handling / retry | Yes (pause after 3) | N/A (Convex retries) | Yes (user-facing errors) |
| Reconciliation (drift detection) | Yes | Yes (endpoint exists) | No |

## Polish & UX

| Feature | Desktop | Web | iOS |
|---------|---------|-----|-----|
| Undo delete | Yes | Yes (toast) | Yes (toast) |
| Pull to refresh | N/A | N/A | Yes |
| Context menus | Yes | Yes (right-click) | Yes (long-press) |
| Multi-select / bulk ops | Yes | Yes (Cmd+Click, Shift+Click, bulk delete/move) | Yes (filter panel multi-select) |
| Export (Netscape HTML) | Yes | Yes | Yes (JSON + HTML) |
| Import (Netscape HTML) | Yes | Planned | No |
| Reader mode | Yes (Readability.js) | Yes (Readability.js) | Yes (Readability.js) |
| Accessibility (VoiceOver) | Partial | No | Yes |
| Reduce Motion | Yes | No | Yes |
| Dynamic Type | No | No | Partial |

## Notes System

| Feature | Desktop | Web | iOS |
|---------|---------|-----|-----|
| Standalone notes | Yes | Yes | No |
| Rich text editor (TipTap) | Yes | Yes | No |
| Notes on bookmarks | Yes | Yes (rich text) | Yes |
| Notes sync | Yes | Yes | Yes |
| Whiteboard (Excalidraw) | Yes | No | No |

## Deployment & Distribution

| Feature | Desktop | Web | iOS |
|---------|---------|-----|-----|
| Auto-updates | Yes (Sparkle) | Yes (Vercel auto-deploy) | TestFlight |
| Landing page | N/A | Yes | N/A |
| Security headers | N/A | Yes | N/A |
| App Store | No | N/A | Planned |
