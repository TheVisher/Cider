# Cider Storage

Status: canonical core doc.

Cider is local-first. The user's local SQLite database is the canonical memory/query layer, and the vault holds durable user-visible artifacts.

## Sources Of Truth

- SQLite is the canonical metadata/query layer for Cider-managed entities.
- Vault files are durable user artifacts where the file itself matters: notes, `.webloc` bookmarks, `.ics` todos/events, `.vcf` contacts, and saved files.
- JSON indexes and sidecars are transitional, compatibility, cache, or export surfaces unless explicitly documented otherwise.
- Kanban board YAML files remain the canonical project/workflow store, but selected card detail is projected into SQLite for structured sections and search.

## File-Backed Domain Contracts

These contracts tell agents which file/YAML domains are intentional authorities, which are rebuildable projections, and which are legacy surfaces. Do not migrate a file-backed domain only for purity; migrate or hide it when it affects capture, routing, review, search, provenance, or agent explanation quality.

| Domain | Status | Authority contract | Next action |
| --- | --- | --- | --- |
| Kanban board YAML | Canonical file store | Board YAML in `~/CiderVault/.cider/boards/` owns project workflow, card notes, status, parent/child links, QA evidence, implementation history, and handoff context. | Keep YAML canonical; use supported board commands or structured YAML writes; refresh SQLite projection after edits when search/agent inspection needs it. |
| Kanban SQLite projection | Projection | `SecondBrainKanbanProjectionService` projects board/card sections into `item_sections` and `content_chunks` for search and agent inspection. | Treat as rebuildable read-model data; repair drift with `item backfill-kanban --board <board>`. |
| Spaces | Hybrid | Space metadata currently lives in `Spaces/<name>/.cider-space.yaml`, while native membership lives in `space_memberships`. Spaces should behave as product surfaces over shared SQLite/vault state rather than separate memory silos. | Cut over toward a SQLite `spaces` table; keep metadata files as export/projection compatibility and do not treat Space folders as semantic membership truth. |
| Media | Hybrid | MediaItem metadata remains YAML-backed under `Spaces/Media/.cider/media-items`, backed by bookmark/item links, `media_item` action provenance, and provider payload artifacts. | Keep file-backed media metadata for now; migrate only when media routing, provenance, or item graph explanation needs a SQLite-native contract. |
| Agent memory | Legacy | Durable memory Markdown/review files are review artifacts and compatibility memory, not canonical second-brain item truth. | Do not let legacy memory files override SQLite item graph, capture, or routing state; future chat/memory intake should feed canonical capture/provenance services. |
| Folder Kanban | Legacy | `.cider/folder-kanban/*.yaml` stores per-folder item columns tied to legacy folder organization. | Do not expand as second-brain truth; hide or retire when Spaces/item routing replaces folder-centered workflows. |
| Dashboard topics and cards | Hybrid | `DashboardStorage` stores local JSON dashboard topics/cards/runs; it is product state, not vault evidence or canonical item memory. | Keep as local UI state until schema compatibility is explicit; link to canonical items instead of duplicating item truth. |
| Vault folders | Hybrid | Folders are storage topology for durable artifacts and conservative routing, but not the meaning layer. | Preserve user topology and identity on moves; Spaces, routing decisions, and explicit project/board routes should carry meaning. |

## Second Brain Item Graph

Cider's durable second-brain foundation is SQLite-led. LLMs and Hermes reason over Cider; SQLite owns memory identity, structured state, retrieval hooks, routing records, and provenance.

Current second-brain foundation tables include:

- `item_sections`: typed visual/detail sections for an item or external owner such as a Kanban card.
- `content_chunks`: searchable chunks derived from sections, notes, captures, or imported content.
- `content_chunks_fts`: FTS5 exact-search index over chunk title/body.
- `routing_decisions`: durable record of where an item was routed, why, by whom, and with what confidence.
- `agent_actions`: durable record of agent/CLI/tool actions against an item or projected owner.
- `owner_relations`: typed graph edges between universal owners such as items, Kanban cards, projects, capture events, capture attachments, docs, and future owner types.
- `projects`: backend project graph rows used by project context, project-scoped artifacts, board/card relations, and agent-safe project inspection.
- `capture_events`: canonical capture provenance records with source surface/channel/message/sender context and produced-item relations.
- `capture_attachments`: per-attachment capture provenance with source filename, local/remote reference, MIME type, byte size when available, and owner relations to capture events/items.
- `enrichment_outputs`: structured AI/enrichment outputs such as entities, topics, dates, links, summaries, and review state.
- `similarity_candidates`: reviewable grouping/linking suggestions that can be accepted into typed owner relations.

Vectors and embeddings may augment retrieval later, but they are not the source of truth. Hybrid retrieval should layer structured filters, FTS5, links/graph expansion, optional embeddings, and reranking.

The storage model follows the product loop: capture source identity, enrich metadata/content, record routing/review state, and make resurfacing explainable.

## Accepted Backend Graph Contract

The accepted backend graph foundation is operational enough for documentation, dogfooding, and UX planning. It is not a promise that every table is always populated; readiness is explicit and inspectable.

- Universal owners use stable `{ownerType, ownerID}` refs. Current owners include library items, Kanban cards, Kanban boards, projects, docs/artifacts, `capture_event`, `capture_attachment`, and future external owners.
- `owner_relations` is the typed, queryable relationship layer. Relations should be idempotent where rebuildable, include source/provenance metadata when useful, and avoid replacing existing `item_links` behavior without a bridge.
- `capture_events` and `capture_attachments` are the canonical provenance path for capture surfaces. Source context should preserve surface/channel/message/sender/original text and attachment metadata where available, and item context should expose producing capture events through `captureProvenance`.
- `projects` and project graph services provide project context through backend relations, not folder-path inference. `item project-context <project> --json` is the preferred agent entry point for project graph context.
- `content_chunks` and `content_chunks_fts` are rebuildable retrieval projections for notes, cards, captures, imported content, docs/artifacts, and other item content.
- Typed item deletion cleans the deleted owner's second-brain footprint: owner projections, owner relations in either direction, routing decisions, agent actions, enrichment outputs, and similarity candidates. This keeps graph provenance from pointing at missing item owners after trash/delete flows.
- `enrichment_outputs` stores structured, reviewable enrichment data. Generated enrichment must not overwrite user-owned fields without explicit review/approval.
- `similarity_candidates` stores explainable suggestions. Accepting a candidate may create typed owner relations, but candidate generation itself must not silently reorganize user knowledge.
- `item graph-health --json` is the preferred readiness command before raw SQLite inspection. Empty/rebuild-needed components are findings for sync/rebuild/dogfood, not automatic acceptance failures.
- Graph-heavy commands should report counts, bounded samples where practical, and safe next commands so agents can continue without dumping unbounded context.

Durable docs should describe the contract; Kanban cards should hold implementation history, QA evidence, dogfood notes, and follow-up friction.

## Kanban Projection Lifecycle

Kanban YAML remains canonical for boards and card notes in this bridge phase. SQLite projections are rebuildable agent/read-model data.

- Card projection is created or refreshed when Cider writes card notes through `board add-card`, `board update-card`, `board section update`, or `board evidence add`.
- `item backfill-kanban [--board <name-or-id>]` rebuilds projections from canonical board YAML. Use it after branch changes, restores, manual YAML repair, or when an agent needs current search results before the app has naturally refreshed the board.
- Card or board deletion removes matching `item_sections` and `content_chunks` projections plus owner-scoped graph sidecars so old card text and stale Kanban owner provenance do not remain searchable/queryable.
- Board reload/restore should re-project cards when loaded by Cider services; agents can force the same result with `item backfill-kanban`.
- `item doctor` currently verifies schema/table health and SQLite integrity. Stale projection drift is not yet a first-class doctor finding; until that follow-up lands, repair suspected drift with backfill and verify with `item get card <id>` and `item search`.

The target future model is native structured sections rendered into dashboard/source/export views. The current Markdown-derived projection is an intentional migration bridge, not the final authority model.

## Safety Rules

- Never delete user data directly from feature code. Use trash/undo flows.
- Preserve stable identity across moves and renames.
- Treat external file changes carefully and reconcile into SQLite when supported.
- Avoid storage paths that let older sidecar/cache data overwrite newer SQLite state.
- Compare before writing watcher-managed files to avoid write loops.
- External file moves, folder moves, and URL rewrites must persist identity rather than adopting duplicate rows.
- Keep backups usable and test restore logic in isolated databases.

## Vault Shape

The vault stores user-readable artifacts in folders such as Inbox, Bookmarks, Notes, Todos, Date Cards, Contacts, and Files. Routing should be conservative when confidence is low.

Spaces are surfaces over shared SQLite/vault state. A Space may correspond to folders, dashboard panels, routing hints, or domain-specific UI, but it must not become a separate authority for item identity or memory.

Project work surfaces use vault folders for user-visible Markdown and reference material:

- `Projects/<Project>/Plans/` stores draft feature plans and implementation shaping notes until they are promoted into milestones/cards.
- `Projects/<Project>/QA/` stores project audit outputs and QA reports until actionable findings are promoted into cleanup milestones/cards.
- `Projects/<Project>/Assets/` stores project reference material such as screenshots, inspiration, app links, and local files.

These folders are Cider workspace artifacts, not repo docs. Project tabs should show artifacts deliberately placed in their matching project folder or represented by matching project artifact metadata; they must not silently mine the Library for fuzzy text matches. Moving a Library item into a project should preserve the item identity and backlinks while changing its placement. Completed plans and QA reports should be archived, marked extracted, or deleted after their durable decisions and active work have moved into core docs and Kanban cards.

Routing rules:

- Choose one obvious destination when confidence is high.
- Prefer Inbox over a wrong folder.
- Merge or link before creating duplicate entities.
- Preserve user folder topology; do not invent new domain folders casually.

## Bookmarks

Bookmark `.webloc` files are durable artifacts. SQLite stores canonical bookmark metadata used by Cider. Legacy sidecar metadata is migration/backfill material, not an ongoing authority.

## Notes

Notes are Markdown files with Cider metadata in SQLite. Rich editor details should round-trip to durable Markdown as safely as possible. The app should guard against overwriting externally modified notes.

## Todos And Dates

Todos and date cards use `.ics` files with VTODO or VEVENT content, mirrored into SQLite for fast loading and queries.

## Contacts

Contacts use `.vcf` files and SQLite-backed metadata. Relationship context should live in structured contact fields or notes, not vague agent memory.

## Backups And Migration

SQLite backup and restore are required safety rails. Migrations should be idempotent where possible and should not depend on debug-only state. Restore paths should be tested against isolated databases before real-vault use.

Second-brain migrations must be additive until backfill and export safety are proven. Kanban, Markdown, `.webloc`, `.ics`, `.vcf`, and saved files must remain usable during migration; projected SQLite rows can be rebuilt from canonical artifacts when applicable.

## Sync

Sync is secondary to local-first correctness. If sync metadata is incomplete or conflicting, local data safety wins.

Cider Web sync currently covers bookmarks, folders, and notes. It does not sync second-brain graph tables such as `owner_relations`, `capture_events`, `content_chunks`, `enrichment_outputs`, `similarity_candidates`, or file-backed MediaItem YAML unless a later bridge explicitly expands the contract.

Durable sync invariants:

- `ciderSyncId` values are case-insensitive and should be normalized consistently.
- Timestamps exchanged across clients should be unambiguous and comparable.
- Soft deletes/tombstones are safer than silent hard deletes.
- Conflict handling should prefer deterministic last-writer or explicit reconciliation over hidden merges.
- Desktop remains authoritative for local vault safety; Web/iOS clients must not force unsafe local mutations.

## Media Bridge

MediaItem metadata remains YAML-backed during the bridge phase. `media identify --apply` writes MediaItem YAML and records `media_item` action provenance through `agent_actions` when the second-brain store is available, but it does not yet project MediaItem content into `item_sections`/`content_chunks` or create full SQLite-native media owner relations.

Agents should inspect media through the media CLI, Media Space dashboard, and the YAML-backed storage contract rather than assuming full item graph parity.

## Native Spaces Cutover

The native cutover target is a SQLite `spaces` table with stable ID, name, preset/purpose, agent instructions, routing hints, default views, root storage path, pinned state, and timestamps. `space_memberships` already carries item-to-space meaning; follow-up graph work should mirror that membership into owner relations instead of inferring meaning from folders.

Path containment is storage topology, not semantic membership. `.cider-space.yaml` should become an export/projection compatibility surface for Finder visibility, sync/export, and rollback while SQLite owns Space identity and meaning.

`space_memberships` writes are mirrored into `owner_relations` as item-owner `belongs_to_space` edges targeting a `space` owner. This makes accepted Space membership discoverable through item context, backlinks, and related-owner graph inspection without treating folder containment as meaning.

## Dashboard Data

Dashboard data is local-first Cider state. Topics, cards, runs, soft-deletes, and provenance belong in Cider-managed storage. Web or remote clients may consume the model only after schema compatibility is explicit.
