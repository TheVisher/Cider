# Bookmark Web View Memory Policy Design

**Date:** 2026-04-22
**Status:** Approved design, pending implementation plan

## Summary

Design a bookmark-detail memory policy that reduces retained RAM after the Cider panel is hidden, without breaking the currently viewed bookmark page or interfering with background app services.

The chosen behavior is to preserve only the active live bookmark web view when the panel is dismissed, while discarding auxiliary bookmark web-view state that exists only to keep the UI warm. This behavior should be user-configurable in Settings under `General -> Panel`.

## Problem

Today, Cider intentionally keeps bookmark-detail web views alive for responsiveness. That makes detail transitions feel fast, but it also means memory can remain elevated after the user hides the panel.

This creates two product issues:

- users can feel like Cider "never gives RAM back"
- memory retained for warm UI state can be disproportionate to the value it provides after dismiss

At the same time, a naive reset would be a regression:

- users should not lose their place in the bookmark page they were actively viewing
- panel-hide memory trimming must not disturb reminders, notifications, Telegram polling, CLI/orchestrator behavior, or other background systems

## Goals

- Reduce retained bookmark-detail memory after panel dismiss.
- Preserve the currently viewed live bookmark page so reopening the panel does not refresh that page or lose scroll/session state.
- Remove bookmark-detail warm state that is not actively valuable after dismiss.
- Expose the policy as a simple user-facing setting.
- Keep the change scoped to bookmark-detail memory in this pass.

## Non-Goals

- No notes-editor memory policy changes in this pass.
- No broad settings reorganization in this pass.
- No attempt to build a generic memory manager for every subsystem in Cider.
- No changes to reminder, notification, Telegram, or CLI/orchestrator lifecycle management.

## Chosen Direction

### Preserve only the active live bookmark web view

On panel dismiss, Cider should preserve the active live bookmark `WKWebView` if a bookmark detail is currently open. This protects the exact user-visible page state that matters most.

At the same time, Cider should aggressively trim the rest of the bookmark-detail warm state:

- discard the reader web view
- cancel and discard background reader extraction web view work
- clear cached reader article content that only exists to warm reader mode
- clear other bookmark-detail warm state that does not affect the currently visible live page

If no bookmark detail is open when the panel is dismissed, Cider should fully reset the bookmark-detail web-view store.

### Why this direction

This is the best tradeoff between memory recovery and user trust:

- it avoids the frustrating "my page refreshed and lost my place" outcome
- it meaningfully lowers retained UI memory compared with keeping all bookmark-detail web views warm
- it is easier to reason about and test than a multi-entry web-view cache

## Settings

Add a new setting under `General -> Panel`.

Proposed label:

- `Bookmark web view memory`

Proposed options:

- `Conserve Memory`
- `Keep More Warm`

### Behavior by option

#### Conserve Memory

This is the recommended option.

On panel dismiss:

- keep only the active live bookmark web view if a bookmark detail is open
- discard bookmark reader/extraction warm state
- fully reset bookmark-detail web-view state if no bookmark detail is open

#### Keep More Warm

Preserve current bookmark-detail warm behavior across panel dismiss, prioritizing faster return over lower memory retention.

This option is explicitly for users who prefer responsiveness and have RAM to spare.

## Lifecycle Boundary

The memory policy must be implemented at the panel UI boundary, not the application-service boundary.

That means the change should be triggered by panel dismiss / hide behavior and should only affect bookmark-detail UI memory.

The following systems must remain untouched and continue running normally regardless of this setting:

- reminder reconciliation
- local notifications
- Telegram bridge
- AI agent tool registration
- CLI/orchestrator runtime behavior
- other app-level services started from `AppDelegate`

## Implementation Shape

### Detail web-view store

Extend the bookmark detail web-view store so it can trim itself in two modes:

- full reset
- preserve active live page while discarding auxiliary warm state

The preserve-active path should keep the main live bookmark web view and its loaded page/session state intact, while removing reader-specific and extraction-specific retained objects.

### Panel dismiss path

When the Cider panel is dismissed:

- consult the bookmark web-view memory preference
- if the preference is `Conserve Memory` and a bookmark detail is open, preserve only the active live page
- if the preference is `Conserve Memory` and no bookmark detail is open, perform a full reset
- if the preference is `Keep More Warm`, preserve existing behavior

### Settings plumbing

Add a persisted config value and surface it in the existing `General -> Panel` settings UI.

The initial default should be `Conserve Memory`.

## Testing

Add focused tests for the new policy behavior:

- config round-trip for the new bookmark web-view memory preference
- detail web-view store trimming behavior for `preserve active live page`
- panel dismiss behavior choosing the correct trim path based on setting and whether a bookmark detail is open

Manual verification should cover:

- hide panel while viewing a bookmark page, reopen, confirm page is still intact
- hide panel while not viewing bookmark detail, confirm bookmark-detail warm state is released
- switch setting to `Keep More Warm`, confirm existing warm behavior is preserved
- confirm reminders, notifications, Telegram, and AI assistant behavior are unchanged while panel is hidden

## Risks

- If the preserve-active path clears too much state, the active page could still refresh or lose session context.
- If the setting label is too technical, users may not understand the tradeoff.
- If the panel dismiss path trims more than bookmark-detail UI state, it could accidentally couple UI lifecycle to background services.

## Open Follow-Up

If this works well, a later pass can decide whether notes editor memory should get a similar user-facing policy. That follow-up is intentionally out of scope for this design.
