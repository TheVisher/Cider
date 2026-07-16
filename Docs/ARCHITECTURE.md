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

Private runtime values cross outward boundaries only through `CiderPrivacyProjectionPolicy`. Canonical stored values remain complete; system logs use content-free event/category projections, and user-facing diagnostics retain stable classifications and non-sensitive facts rather than raw URLs, paths, source text, sender identities, or process output. Ordinary CLI capture-provenance JSON uses the `cli_default` projection and portable item/folder exports use `portable_export`: both expose deterministic evidence-presence booleans, categories, counts, allowlisted metadata-key categories, timestamps, and relation/owner identity while omitting raw source URL/file/text, sender and transport identifiers, relation source/actor/evidence, and metadata values or unrecognized key names. Direct local CLI commands may select `trusted_local` only through the explicit `--include-private-provenance` flag; that projection restores exact provenance and declares `containsPrivateData=true`. Unknown or unrelated projection contexts fail closed. Intentionally exported item or conversation bodies remain complete, and projection never rewrites canonical evidence. Child processes receive an explicit purpose-built environment instead of ambient inheritance; required launcher/runtime variables are allowlisted and feature-specific additions must be intentional.

External opens cross `CiderOpenPolicy` with an explicit destination type: untrusted web, local file, Finder reveal, allowlisted local application, or allowlisted system destination. Untrusted web accepts only HTTP(S); local and system behavior must not weaken that guard. Filesystem exporters cross `CiderExportWritePolicy`: create-new is the default and commits without replacement, while an existing single file may be replaced only with explicit typed intent derived from user confirmation. Directory/package export remains non-overwriting. Writes stage beside the destination, revalidate parent/destination identity, reject symlink redirects, clean partial staging, and use bounded failures; this filesystem policy does not claim transactionality with SQLite or other external side effects.

Speech-to-text routes through the neutral shared Cider transcription capability in `Models/TranscriptionModels.swift` and `Services/Transcription/`. Live microphone and stored-audio inputs share provider selection, normalization, locale/timing/segment/source provenance, readiness, typed failures, and machine-readable provider capabilities. Surface policy remains separate: Chat keeps only an editable derived draft and does not retain microphone audio. Journal push-to-talk composes a surface-neutral main-actor session with the shared microphone/provider authorization boundaries, one bounded native recorder, and `JournalStoredVoiceCaptureCoordinator`; it creates audio only after Record, targets the selected canonical day with an opaque source/retry identity, and cancels on view loss or app background. `JournalMediaIntakeService` validates caller-supplied media, retains immutable canonical originals under `Journal/`, and gives transcription providers only bounded disposable working copies. `JournalStoredVoiceCaptureCoordinator` is the neutral local-file-to-Journal seam: it validates and transcribes a disposable copy through one explicit central provider resolution, then delegates the only canonical write to `JournalAtomicCaptureWriter`. The transaction policy is atomic after successful transcription because current Journal receipts represent completed captures: unavailable, unauthorized, unsupported, offline, timed-out, malformed, non-final, mismatched-provenance, or failed transcription creates no canonical audio, Journal text, source card, capture event, candidate source, or receipt. The atomic writer composes its batch seam with the canonical day note, capture event/attachments, owner relations, and content indexes; SQLite coordinates the commit and exact Markdown bytes are compensated on determinate failure. The committed source card stores the exact derived transcript, provider/adapter/model/execution, locale, timing/segments, source audio identity/SHA-256, `preserveOriginal` retention, and completed status, while the VaultFile remains the immutable native audio target. Exact retry checks path-free request/provider/source metadata and freshly validated audio bytes before provider work; unchanged input reuses the verified durable receipt and changed bytes fail closed. Complete caller source identity is reduced to a bounded kind-prefixed SHA-256 provenance value when it is too long or path-shaped, preserving retry/reopen identity and long-prefix collision resistance without persisting private path or suffix text. Journal type, size, duration, source-card, and retention policy stays above the shared provider. Apple Speech is the explicit shared default because it supports both live partials and stored files on device with no silent network fallback. The local faster-whisper adapter is an explicit offline, bounded-process, stored-file-only alternative over a caller-supplied cached model and executable; it cannot become the universal default or be selected by one surface while it lacks truthful live-partial support. Provider changes must occur at the shared selection point and fail closed.

`ItemLinkService` owns explicit related-item/backlink behavior. `DashboardStorage` owns local dashboard snapshot persistence. A shared agenda/briefing policy service should own relevance decisions for today's dashboard, reminders, and agent reports. Feature views, `cider-cli` JSON, and agent integrations should consume that service instead of reconstructing reminder/date relevance independently.

The second-brain foundation lives in SQLite services, not in Markdown conventions or LLM memory. `SecondBrainStore` owns item sections, content chunks, FTS search, routing decisions, and agent action provenance. Feature-specific projectors, such as Kanban card projection, translate canonical feature storage into that shared graph without rewriting the feature's storage all at once.

Every capture client must converge on this shared foundation. A native bookmark save, drag/drop, clipboard URL/image prompt, OS screenshot/snipping tool routed through a local clipboard client, CLI/agent capture, Discord voice-derived Journal entry, and future client capture must produce compatible canonical item identity, source provenance, indexing, action receipts, review state, and agent-readable context. No client may create a private class of items that Main Brain cannot retrieve as reliably as another client's captures. The cloud agent cannot observe a local OS clipboard by itself; Windows screenshot prompts require an equivalent local Windows capture client/worker.

Cross-time relationship discovery is incremental and reviewable. New Journal capture composes the canonical Journal extractor and enrichment-output/evidence/lifecycle services only after the atomic source commit, anchoring deterministic candidate identity to the exact capture event, text source, and evidence span. Safe HTTP(S), place, person, and project references stay candidate truth: canonical reconciliation may return bounded likely matches, but ambiguous identities are never selected and no entity or accepted relation is created without the shared review authority. Exact retries/reopens reuse the completed capture-scoped candidate receipt; candidate failure cannot roll back or rewrite the already committed Journal source and is reported as partial enrichment. Daily/weekly reconciliation must remain bounded, avoid duplicate candidates, preserve both source refs, and require explicit acceptance before creating accepted `owner_relations`.

Spaces are entity-aware product lenses under Library over shared state. They may add domain-specific facets, states, and workflows—such as watched/unwatched, liked/disliked, ratings, and recommendations for media—but they should not become independent data silos or parallel memory systems.

Graph-native second-brain work should use the shared `graph_candidate` contract before creating feature-specific models. Extractors write reviewable `enrichment_outputs(kind: graph_candidate)` rows with source quotes and typed guesses. Review, CLI, and UI surfaces inspect those candidates. Only explicit accept paths create accepted object owners or `owner_relations`; reject/defer/correct paths should change review state or metadata without creating graph truth.

## Agent Boundary

Cider owns the native UI, local memory state, vault artifacts, stable room and participant identity, canonical room history, message routing and visibility preferences, commands, and user-facing approval surfaces. Each room has one Cider-owned head-agent assignment for ordinary unaddressed turns and may have explicit bounded participants. Hermes is the sole supported current runtime and owns long-running agent execution, tool semantics, runtime session truth, and external session continuity. Runtime sessions remain replaceable bindings rather than room or participant identity. Keep the Hermes transport boundary narrow, but do not retain unused alternate-provider/runtime implementations merely for hypothetical flexibility; audit dependencies and delete safely unused code.

Normal Chat UI may choose a room's head agent, explicitly invoke participants, and independently filter participant output without exposing provider credentials, raw runtime switching, channel management, or restart administration. A participant invocation owns a linked run/work stream; full activity stays available there, while final outcomes normally notify the head agent for a concise main-room summary. All main-room messages, summaries, run links, failures, and approvals remain ordered against the same canonical Cider room.

Raw runtime session IDs are rotating pointers, not product identity. Direct assumptions about one runtime should stay isolated in agent transport/client files. Prefer Runs/SSE-style APIs when available, with CLI/export fallback as a compatibility path.

Rooms Test Chat uses the canonical Conversation Core room, runtime-binding, turn, and message tables for durable continuity. Only fully synchronized, source-backed completed Hermes Runs API turns may advance that room; startup reload must reject partial, failed, cancelled, corrupt, mismatched-authority, and legacy-authoritative shapes rather than falling back to a private transcript store.

Future Agent Host work should coordinate multi-client rooms, ordering, approvals, event fanout, and relay behavior without letting clients write directly to Hermes internals.

## CLI Boundary

`cider-cli` is an agent-facing and user-facing interface to Cider data. It should prefer strict JSON when `--json` is passed and human-readable output otherwise.

Agents should use CLI/services for vault facts and mutations. They should not read raw caches or count filesystem files when a CLI command can answer.

Hermes and other agents should query Cider through stable commands such as `item get`, `item search`, `item route`, `item backfill-kanban`, `item doctor`, `space explain`, `board card inspect`, `board section update`, and `board evidence add`. Agents should not infer Cider state by scanning random Markdown files, folder names, sidecars, or UI-only summaries when a structured command exists.

## Testing Boundary

Use focused Swift tests for models, storage, service policies, CLI serialization, and regression behavior. Manual QA evidence belongs on the relevant Kanban card unless it becomes a reusable procedure, in which case it belongs in `Docs/QA.md`.
