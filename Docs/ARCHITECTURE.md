# Cider Architecture

Status: canonical core doc.

Cider is a SwiftUI + AppKit macOS app with local-first storage, a floating panel shell, SQLite-backed second-brain state, vault artifacts, CLI access, and agent integrations.

The durable architecture supports the product loop: capture -> enrich -> route -> review -> resurface/act. Features should plug into that loop instead of building isolated storage and routing behavior.

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

`ItemLinkService` owns explicit related-item/backlink behavior. `DashboardStorage` owns local dashboard snapshot persistence. A shared agenda/briefing policy service should own relevance decisions for today's dashboard, reminders, and agent reports. Feature views, `cider-cli` JSON, and agent integrations should consume that service instead of reconstructing reminder/date relevance independently.

The second-brain foundation lives in SQLite services, not in Markdown conventions or LLM memory. `SecondBrainStore` owns item sections, content chunks, FTS search, routing decisions, and agent action provenance. Feature-specific projectors, such as Kanban card projection, translate canonical feature storage into that shared graph without rewriting the feature's storage all at once.

Every capture client must converge on this shared foundation. A native bookmark save, drag/drop, clipboard URL/image prompt, OS screenshot/snipping tool routed through a local clipboard client, CLI/agent capture, Discord voice-derived Journal entry, and future client capture must produce compatible canonical item identity, source provenance, indexing, action receipts, review state, and agent-readable context. No client may create a private class of items that Main Brain cannot retrieve as reliably as another client's captures. The cloud agent cannot observe a local OS clipboard by itself; Windows screenshot prompts require an equivalent local Windows capture client/worker.

Cross-time relationship discovery should be incremental and reviewable. A bounded reconciliation service may compare recent/new Journal spans and newly captured objects, emit source-backed `graph_candidate` rows, and support daily/weekly agent runs. It must avoid duplicate candidates, preserve both source refs, and require explicit acceptance for ambiguous relations before creating accepted `owner_relations`.

Spaces are entity-aware product lenses under Library over shared state. They may add domain-specific facets, states, and workflows—such as watched/unwatched, liked/disliked, ratings, and recommendations for media—but they should not become independent data silos or parallel memory systems.

Graph-native second-brain work should use the shared `graph_candidate` contract before creating feature-specific models. Extractors write reviewable `enrichment_outputs(kind: graph_candidate)` rows with source quotes and typed guesses. Review, CLI, and UI surfaces inspect those candidates. Only explicit accept paths create accepted object owners or `owner_relations`; reject/defer/correct paths should change review state or metadata without creating graph truth.

## Agent Boundary

Cider owns the native UI, local memory state, vault artifacts, stable logical chat identity, commands, mirrored display history, and user-facing approval surfaces. Hermes is the sole supported current runtime and owns long-running agent execution, tool semantics, runtime session truth, and external session continuity. Keep the Hermes transport boundary narrow, but do not retain unused alternate-provider/runtime implementations merely for hypothetical flexibility; audit dependencies and delete safely unused code.

Normal Main Brain UI exposes only simple connection and active-model status. Provider selection, channel management, runtime switching, and restart administration belong to Hermes operations rather than the Cider product surface.

Raw runtime session IDs are rotating pointers, not product identity. Direct assumptions about one runtime should stay isolated in agent transport/client files. Prefer Runs/SSE-style APIs when available, with CLI/export fallback as a compatibility path.

Rooms Test Chat uses the canonical Conversation Core room, runtime-binding, turn, and message tables for durable continuity. Only fully synchronized, source-backed completed Hermes Runs API turns may advance that room; startup reload must reject partial, failed, cancelled, corrupt, mismatched-authority, and legacy-authoritative shapes rather than falling back to a private transcript store.

Future Agent Host work should coordinate multi-client rooms, ordering, approvals, event fanout, and relay behavior without letting clients write directly to Hermes internals.

## CLI Boundary

`cider-cli` is an agent-facing and user-facing interface to Cider data. It should prefer strict JSON when `--json` is passed and human-readable output otherwise.

Agents should use CLI/services for vault facts and mutations. They should not read raw caches or count filesystem files when a CLI command can answer.

Hermes and other agents should query Cider through stable commands such as `item get`, `item search`, `item route`, `item backfill-kanban`, `item doctor`, `space explain`, `board card inspect`, `board section update`, and `board evidence add`. Agents should not infer Cider state by scanning random Markdown files, folder names, sidecars, or UI-only summaries when a structured command exists.

## Testing Boundary

Use focused Swift tests for models, storage, service policies, CLI serialization, and regression behavior. Manual QA evidence belongs on the relevant Kanban card unless it becomes a reusable procedure, in which case it belongs in `Docs/QA.md`.
