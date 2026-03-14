# Feature Parity

> What each app has, doesn't have, and what's planned. This is the go-to reference for deciding what to build next on any platform.
>
> **Last updated**: 2026-03-13

Legend: Yes = shipped, No = not built, Planned = on roadmap, N/A = not applicable to this platform

## Core Features

| Feature | Desktop | Web | iOS |
|---------|---------|-----|-----|
| Bookmark CRUD | Yes | Yes | Yes |
| Notes CRUD | Yes | Yes (plain text) | No |
| Bookmark sync (push/pull) | Yes | Yes (direct mutations) | Yes |
| Folder sync | Yes | Yes | No |
| Soft delete / trash | Yes | Yes | Yes (swipe-to-delete) |
| Trash view / restore | Yes | Yes | Planned (M8) |
| Permanent delete (purge) | Yes | Yes (30-day cron) | No |
| Search | Yes | Yes | Yes (local filter) |
| Tags | Yes | Yes | Yes (display only) |
| Share Extension | N/A | N/A | Yes |

## Organization

| Feature | Desktop | Web | iOS |
|---------|---------|-----|-----|
| Folders / collections | Yes | Yes | No |
| Nested folders (tree) | Yes | Yes | No |
| Folder icons | Yes (SF Symbols) | Yes (Lucide) | No |
| Move to folder | Yes | Planned | No |
| Tag management (rename/merge) | Yes | Planned | No |
| Tag filtering | Yes | Yes | Planned |
| Saved views / smart filters | Yes | Yes (tabs) | Planned (M16) |

## Display & Layout

| Feature | Desktop | Web | iOS |
|---------|---------|-----|-----|
| Grid view | Yes | Yes | No |
| List view | Yes | Yes | Yes (default) |
| Masonry view | Yes | Yes | No |
| Card size slider | Yes | Planned | No |
| Sidebar | Yes | Yes (collapsible) | No |
| Detail panel (slide-out) | Yes | Yes | No |
| Keyboard shortcuts | Yes | Partial (Cmd+K, Cmd+B) | No |

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
| Clipboard detection | Yes | No | Planned (M10) |

## Visual & Media

| Feature | Desktop | Web | iOS |
|---------|---------|-----|-----|
| Thumbnails | Yes (local + remote) | Yes (Convex storage + remote) | Yes (remote only) |
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
| AI summaries (display) | Yes | Yes | No |
| AI chat | Yes | No | No |
| Auto-enrichment pipeline | Yes | Partial (server action) | No |

## Sync & Auth

| Feature | Desktop | Web | iOS |
|---------|---------|-----|-----|
| Sync token auth | Yes | Yes (generates tokens) | Yes |
| Account-based auth | No | Yes (email/password) | No |
| OAuth (Google/GitHub/Apple) | No | Planned | No |
| Account-based sync (replace tokens) | Planned | Planned | Planned |
| Background sync | Yes (5s poll) | Yes (real-time subscriptions) | No (foreground only) |
| Dirty-only push | Yes | N/A | Yes |
| Failure handling / retry | Yes (pause after 3) | N/A (Convex retries) | Yes (user-facing errors) |
| Reconciliation (drift detection) | Yes | Yes (endpoint exists) | No |

## Polish & UX

| Feature | Desktop | Web | iOS |
|---------|---------|-----|-----|
| Undo delete | Yes | Yes (toast) | Planned (M9) |
| Pull to refresh | N/A | N/A | Yes |
| Context menus | Yes | Yes (right-click) | Yes (long-press) |
| Multi-select / bulk ops | Yes | Planned | Planned (M12) |
| Export (Netscape HTML) | Yes | Yes | Planned (M15) |
| Import (Netscape HTML) | Yes | Planned | No |
| Reader mode | Yes (Readability.js) | No | Planned (M11) |
| Accessibility (VoiceOver) | Partial | No | Yes |
| Reduce Motion | Yes | No | Yes |
| Dynamic Type | No | No | Partial |

## Notes System

| Feature | Desktop | Web | iOS |
|---------|---------|-----|-----|
| Standalone notes | Yes | No | No |
| Rich text editor (TipTap) | Yes | Planned | No |
| Notes on bookmarks | Yes | Yes (plain text) | No |
| Notes sync | Yes | Yes | No |
| Whiteboard (Excalidraw) | Yes | No | No |

## Deployment & Distribution

| Feature | Desktop | Web | iOS |
|---------|---------|-----|-----|
| Auto-updates | Yes (Sparkle) | Yes (Vercel auto-deploy) | TestFlight |
| Landing page | N/A | Planned | N/A |
| Security headers | N/A | Yes | N/A |
| App Store | No | N/A | Planned |
