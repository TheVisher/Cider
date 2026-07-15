# Cider Storage

Status: canonical core doc.

Cider is local-first. The user's local SQLite database is the canonical memory/query layer, and the vault holds durable user-visible artifacts.

## Sources Of Truth

- SQLite is the canonical metadata/query layer for Cider-managed entities.
- Vault files are durable user artifacts where the file itself matters: notes, `.webloc` bookmarks, `.ics` todos/events, `.vcf` contacts, and saved files.
- JSON indexes and sidecars are transitional, compatibility, cache, or export surfaces unless explicitly documented otherwise.
- Kanban board YAML files remain the canonical project/workflow store, but selected card detail is projected into SQLite for structured sections and search.
- Durable native Rooms history, including the reserved Cider Test Chat, lives in the canonical SQLite Conversation Core tables (`conversation_rooms`, runtime bindings, turns, and messages). The room UUID is stable product identity; Hermes session/run IDs are replaceable runtime bindings and source identities. Accepted user messages, partial assistant output, terminal turn outcomes, retry identity, and source-backed receipt metadata persist there without a JSONL, defaults, sidecar, or legacy-history fallback. Legacy/private previews remain ineligible for this live path unless ownership is independently canonical and explicit.
- Each Cider-owned canonical room may persist one validated provider-neutral acting-agent assignment snapshot in bounded room metadata. The snapshot owns the profile identity, display name, provider/runtime binding, capabilities, availability, and assignment time independently of replaceable runtime session IDs; sending remains ineligible when no assignment exists, the configured profile changed, or its selected provider/runtime is unavailable.
- Older valid canonical rooms without CID-827 metadata remain explicitly unassigned and unrostered when reopened; production composition never backfills an acting agent, participant roster, attachment, or speech state. Draft editing, attachment staging, participant invocation, speech drafting, and Send expose their own prerequisites, and blocked actions preserve the room draft and canonical history.
- A canonical room may also persist one bounded named participant roster above its acting-agent assignment. Explicit user-origin invocations write Cider-owned invocation/run/participant attribution and bounded display-safe activity into the same ordered Conversation Core turns and messages; runtime sessions remain replaceable provenance, unavailable or uncomposed participants fail before durable acceptance, and sequential zero-recursion routing prevents autonomous participant chatter.
- Validated attachment and generated-artifact terminal facts remain bounded metadata on their exact Conversation Core turn. They reference canonical Cider vault-file or project-artifact identity rather than storing paths or transport payloads; rejected facts persist only their rejected state. Native room export is a read-only projection of the canonical room UUID, ordered turns/messages, terminal truth, provenance, and structured receipt metadata into a new caller-selected `.cider-room` folder containing `conversation.md` and `manifest.json`. Runtime session IDs, private paths, credentials, and raw transport payloads are excluded, and export never overwrites an existing destination.
- Native room composer attachments use a Cider-owned draft-to-acceptance boundary. Picker/drop selection stages at most four UTF-8 text (`txt`, `md`, `csv`, `json`) or decodable image (`png`, `jpeg`, `gif`) files locally, with per-file and 12 MB aggregate limits; selection never creates a turn, message, vault file, upload, or transport call. Explicit Send revalidates availability, type, size, readability, non-alias/non-symlink identity, hash, duplicates, selected participant capability, and transport capability before copying into the existing canonical `Inbox/Files` or `Inbox/Images` vault-file store. The user row and exact-turn facts are then committed before transport. Facts contain stable Cider attachment/vault-file IDs, SHA-256, safe display name/type/size, picker/drop provenance, accepted lifecycle, and a Cider-native Open route, never an original path or file URL. Failure, cancellation, retry, close/reopen, receipt, and export reuse those facts without duplicating canonical user attachments; unsupported runtimes fail before durable acceptance with no fallback.
- Caller-supplied local files entering Chat, Capture, the Journal media adapter, or the Notes editor use `LocalFileIntakeValidator`; each surface keeps its own type, count, size, duration, submission, and retention policy. Validation preserves the original security-scoped access URL separately from standardized/resolved identity, hashes and revalidates reads under balanced access, and rejects non-regular, unreadable, alias, symlink, traversal, changed, and unsafe-destination inputs with bounded path-free failures. `VaultFileIngestionService` materializes Chat, Capture, and Journal originals with redirected-path rejection, stable identity, transactional persistence, and rollback. Chat retains its four-file/12 MB composer contract; Capture retains receipt/provenance/routing/indexing behavior. `JournalMediaIntakeService` applies a Journal-owned bounded generic-media policy, decodes photo payloads, stores immutable source-truth originals under `Journal/Audio`, `Journal/Photos`, or `Journal/Media`, and transcribes only through a disposable extension-compatible copy. Its batch seam validates every source before materialization and commits all originals plus caller-owned source cards in one transaction. `JournalAtomicCaptureWriter` is the blessed text-plus-media mutation for app/CLI/agent adapters: one canonical day note, one text source, distinct timestamped media source cards backed by `capture_attachments`, exact day/original relations, one durable receipt, exact-retry reuse, indexed note/files, and Markdown compensation on failure. After that source boundary commits, `JournalCaptureCandidateService` composes the existing Journal extractor and canonical enrichment/evidence/lifecycle stores in a separate transaction. Candidate rows retain the note owner for existing review queries while their source evidence owner is the exact `capture_event`; a completion marker on that event makes exact retry/reopen read-only and prevents duplicate candidates, evidence, lifecycle, or audit history. Failure rolls back only candidate enrichment and leaves the day Markdown, media, capture provenance, and source receipt intact. Friendly display titles stay in canonical item/source metadata while the raw filename remains provenance; Journal originals are hidden from the default Library feed and projected through Journal cards into the existing native vault-file preview route. Complete private source identity drives stable hashing; long provenance identities are persisted only as bounded kind-prefixed SHA-256 projections, so common-prefix identities stay distinct without exposing private suffixes in paths, logs, or read models. `NotesRelativeAssetIntakeService` uses the filesystem-only rooted materializer instead of creating `VaultFile` rows: editor imports land beside the owning note under `.attachments`, commit only after decode/editor/note-save finalization, and persist canonical `./.attachments/...` Markdown while `cider-vault://` remains presentation-only. The real `NotesViewModel` image transaction snapshots exact JS Markdown, disk truth, selection/external-change/autosave state, suppresses competing delayed saves, and uses a throwing `NotesStorage` boundary that replaces the file, persists the canonical row and searchable chunk in one SQLite transaction, then publishes memory/cache and schedules cleanup. Determinate failure restores exact prior bytes/existence and read-model state before the new asset is removed; indeterminate file compensation retains the asset and surfaces bounded recovery instead of manufacturing a broken reference. Success invokes the normal sync hook once. Stable retry/reopen reuses exact content and incompatible identity or destination redirects fail closed.
- Native room speech input composes Cider's shared provider-neutral transcription capability and the existing per-canonical-room draft store. Apple Speech is the explicit shared default for both live microphone and caller-supplied stored-audio inputs, with no silent network fallback. The optional local faster-whisper adapter consumes only caller-supplied stored files through a bounded offline subprocess and cached model; it reports live partials as unsupported and is not selected independently by Chat, Journal, or transport surfaces. Permission is requested only from an explicit surface action; denied, restricted, offline, unavailable, cancelled, timed-out, or failed sessions preserve the exact caller-owned state without a turn, message, transport call, or provider fallback. Bounded partial/final text is deterministically appended to only the originating room's editable draft, room changes cancel and invalidate late callbacks, and transcription completion never submits. Only the existing explicit Send path can create canonical history. Process-local Chat speech provenance records provider, source, locale, timing, bounded transcript, and finality; Chat does not retain raw microphone audio or persist speech-specific provenance by default. The shared stored-audio contract carries a stable caller-owned source identity and `preserveOriginal` retention requirement while treating its file URL as a read-only input handle; the adapter-only Journal backend fulfills that contract without exposing its canonical file to provider code and may edit only the derived transcript. Shared transcripts are not subject to Chat's 4,000-character composer bound; each surface applies its own explicit presentation or persistence limit.

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
- `action_receipts`: durable agent-safe command receipt ledger for representative read-only and mutation-style actions, including owner refs, source/evidence refs, safety semantics, verification/follow-up commands, and structured failures.
- `owner_relations`: typed graph edges between universal owners such as items, Kanban cards, projects, capture events, capture attachments, docs, and future owner types.
- `projects`: backend project graph rows used by project context, project-scoped artifacts, board/card relations, and agent-safe project inspection.
- `capture_events`: canonical capture provenance records with source surface/channel/message/sender context and produced-item relations.
- `capture_attachments`: per-attachment capture provenance with source filename, local/remote reference, MIME type, byte size when available, and owner relations to capture events/items.
- `enrichment_outputs`: structured AI/enrichment outputs such as entities, topics, dates, links, summaries, and review state.
- `source_evidence`: shared provenance/source-span records connecting source owners, quotes/spans, extraction runs, candidates, accepted facts, and recall citations.
- `review_lifecycle_events`: append-only lifecycle events for reviewable candidates and accepted truth records.
- `entity_resolution_candidates`: reviewable entity/alias/merge suggestions with explicit accept/reject/merge semantics.
- `fact_validity_candidates`: reviewable invalidation/supersession/expiration assertions for accepted facts and owner relations; accepted rows mark current vs stale/superseded truth without deleting provenance.
- `similarity_candidates`: reviewable grouping/linking suggestions that can be accepted into typed owner relations.
- `similarity_reconciliation_runs`: bounded live-seeding/repair job metadata for similarity/link candidates, including candidate families and stale/unseeded counts.
- `recall_access_events`: local retrieval/access audit rows for recall/context explanations; they store selector/query hashes and surfaced refs/reason kinds, not raw private query text.

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
- `enrichment_outputs(kind: graph_candidate)` is the universal reviewable object/relation candidate contract. The row owner is the raw source owner, `value` is the mention text, `evidence` is the source quote/snippet, `confidence` is optional, `review_state` is one of `suggested`, `needs_review`, `deferred`, `accepted`, or `rejected`, and `metadata` carries the candidate kind, object type guesses, relation guesses, safe actions, source owner ref, and accepted target/relation fields when promoted.
- `similarity_candidates` stores explainable suggestions. Accepting a candidate may create typed owner relations, but candidate generation itself must not silently reorganize user knowledge.
- `item graph-health --json` is the preferred readiness command before raw SQLite inspection. Empty/rebuild-needed components are findings for sync/rebuild/dogfood, not automatic acceptance failures.
- Graph-heavy commands should report counts, bounded samples where practical, and safe next commands so agents can continue without dumping unbounded context.

Durable docs should describe the contract; Kanban cards should hold implementation history, QA evidence, dogfood notes, and follow-up friction.

## Graph Candidate Contract

Graph candidates are source-backed suggestions, not graph truth. They let journals, bookmarks, notes, files, chats, contacts, media, places, reminders, and future sources speak one shared language before domain-specific extractors or UI surfaces exist.

Contract roles:

- Raw source item: the source owner recorded by the `enrichment_outputs` row owner fields, such as a note, bookmark, capture event, Kanban card, file, contact, or projected external owner.
- Object candidate: a reviewable possible object such as contact/person, place/restaurant, media/movie, recipe, food/drink, product, project, trip, reminder, event, note, file, URL, topic, or generic object.
- Relation candidate: a reviewable possible edge such as `mentions`, `represents`, `source_for`, `watched`, `visited`, `likes`, `likes_drink`, `likes_food`, `dislikes`, `includes`, `reminder_from`, `gifted`, `wants`, `owns`, `bought`, `cooked`, `ate`, `drank`, or `related_to`.
- Accepted object: an explicit object owner created or linked by a review/accept path. Candidate generation alone must not create permanent object truth.
- Accepted relation: an `owner_relations` edge created by a review/accept path. It must preserve source evidence with candidate/source metadata.

Required metadata keys for `graph_candidate` rows are defined in `SecondBrainGraphCandidateContract`. Core keys include `candidate_kind`, `source_owner_ref`, `source_quote`, `mention_text`, `object_type_guesses`, `relation_guesses`, `action_guesses`, and `safe_actions`. Accepted rows also carry `accepted_target_owner_type`, `accepted_target_owner_id`, and, for relation candidates, `accepted_relation_type`.

Examples:

- Journal quote "I gave Jami that pineapple coconut drink and she loved it." can produce an `object_relation` candidate with object type `drink`, relation `likes_drink`, subject "Jami", and the journal quote as evidence.
- Journal quote "I watched The Way Way Back last night." can produce an unresolved `object_relation` candidate with object types `movie`/`media` and relation `watched`.
- IMDb, restaurant, recipe, product, YouTube, and GitHub bookmarks can produce `object_relation` candidates with `represents` or `source_for` relation guesses.
- Ambiguous text such as "We went to Cactus" can produce a `needs_review` object candidate with possible object types such as `restaurant`, `place`, `topic`, or `object`.
- A journal-sourced reminder can produce a `reminder` object candidate and a `reminder_from` relation candidate back to the source entry.

## Kanban Projection Lifecycle

Kanban YAML remains canonical for boards and card notes in this bridge phase. SQLite projections are rebuildable agent/read-model data.

- Kanban completion/progress uses done-like column placement as the canonical done truth. A child card in a Done/Completed/archive-like column counts complete even if old YAML lacks a `completed` date. The `completed` field is supporting timestamp metadata; supported moves into done-like columns should set or repair it, and audits may flag done-like cards that are missing it.
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
- User-selected filesystem exports must use `CiderExportWritePolicy`. The default is create-new/no-replace; explicit confirmed replacement is limited to typed single-file intent, while directory/package export never overwrites. Staging, redirect/identity revalidation, cancellation cleanup, and bounded rollback apply only to the filesystem boundary and do not imply a cross-database transaction.
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

For ordinary app or agent edits, the blessed mutation path is `cider-cli item update note <id-or-ref> ... --json` or the equivalent `NotesStorage` service path. It updates the Markdown artifact, SQLite note/item rows, search chunks, and app-facing note read model together. When a note Markdown file is edited externally and Cider performs a note rescan, disk is the source of truth for that rescan and is reconciled back into SQLite and chunks.

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

MediaItem metadata remains YAML-backed during the bridge phase. `media identify --apply` writes MediaItem YAML and records `media_item` action provenance through `agent_actions` when the second-brain store is available. `media identify --apply` also projects bounded `media_item` owner sections and searchable chunks, plus source-bookmark owner relations, so agents can inspect the YAML bridge without treating Media as fully SQLite-native.

Agents should inspect media through the media CLI, `item owner-get media_item <id> --json`, item search, Media Space dashboard, and the YAML-backed storage contract rather than assuming full item graph parity.

## Native Spaces Cutover

The native cutover target is a SQLite `spaces` table with stable ID, name, preset/purpose, agent instructions, routing hints, default views, root storage path, pinned state, and timestamps. `space_memberships` already carries item-to-space meaning; follow-up graph work should mirror that membership into owner relations instead of inferring meaning from folders.

Path containment is storage topology, not semantic membership. `.cider-space.yaml` should become an export/projection compatibility surface for Finder visibility, sync/export, and rollback while SQLite owns Space identity and meaning.

`space_memberships` writes are mirrored into `owner_relations` as item-owner `belongs_to_space` edges targeting a `space` owner. This makes accepted Space membership discoverable through item context, backlinks, and related-owner graph inspection without treating folder containment as meaning.

## Dashboard Data

Dashboard data is local-first Cider state. Topics, cards, runs, soft-deletes, and provenance belong in Cider-managed storage. Web or remote clients may consume the model only after schema compatibility is explicit.
