# Cider Architecture

Status: canonical core doc.

Cider is a SwiftUI + AppKit macOS app with local-first storage, a floating panel shell, SQLite-backed models, vault files, CLI access, and agent integrations.

## App Boundaries

- `Sources/Cider/App/` owns app launch, panel lifecycle, hotkeys, and app-level coordination.
- `Sources/Cider/Views/` owns SwiftUI surfaces.
- `Sources/Cider/ViewModels/` owns view state and user workflows.
- `Sources/Cider/Services/` owns persistence, indexing, integrations, enrichment, agents, and utilities.
- `Sources/Cider/Models/` owns data models.
- `Sources/CiderCLI/` exposes agent and shell-friendly operations.
- `Tests/CiderTests/` covers model, storage, service, CLI, and policy behavior.

## UI Architecture

The primary UI combines AppKit window/panel behavior with SwiftUI content. Cider should preserve non-stealing focus behavior where expected and use explicit drag/resize exclusion zones where interactive controls need reliable clicks.

Shared views should be extracted when behavior is reused across features, but avoid large abstractions that hide simple feature-specific flows.

UI rules worth keeping:

- Avoid putting complex AppKit popovers around controls known to crash under non-activating panels; use safer sheets/custom panels where needed.
- Masonry and card grids should measure from the parent viewport and item/card width, not from speculative child geometry.
- Expensive detail preloading should not sit on the click path.
- WKWebView-backed editors should use a narrow coordinator boundary, a custom vault URL scheme, and deny-by-default navigation.
- Detail panels, metadata rails, and floatable surfaces should share shell behavior while preserving each item type's primary workflow.

## Service Architecture

Storage services should expose clear operations for their feature area and keep direct file/database details out of views.

Agent and AI services should route through narrow seams so runtime providers can change without rewriting UI workflows.

`ItemLinkService` owns explicit related-item/backlink behavior. `DashboardStorage` owns local dashboard snapshot persistence. Feature views should consume these services instead of reconstructing relationships or snapshot logic themselves.

## Agent Boundary

Cider owns the native UI, vault data, stable logical chat identity, local state, commands, mirrored display history, and user-facing approval surfaces. Hermes or another runtime owns long-running agent execution, tool semantics, runtime session truth, and external session continuity.

Raw runtime session IDs are rotating pointers, not product identity. Direct assumptions about one runtime should stay isolated in agent transport/client files. Prefer Runs/SSE-style APIs when available, with CLI/export fallback as a compatibility path.

Future Agent Host work should coordinate multi-client rooms, ordering, approvals, event fanout, and relay behavior without letting clients write directly to Hermes internals.

## CLI Boundary

`cider-cli` is an agent-facing and user-facing interface to Cider data. It should prefer strict JSON when `--json` is passed and human-readable output otherwise.

Agents should use CLI/services for vault facts and mutations. They should not read raw caches or count filesystem files when a CLI command can answer.

## Testing Boundary

Use focused Swift tests for models, storage, service policies, CLI serialization, and regression behavior. Manual QA evidence belongs on the relevant Kanban card unless it becomes a reusable procedure, in which case it belongs in `Docs/QA.md`.
