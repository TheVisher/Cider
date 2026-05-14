# Cider Storage

Status: canonical core doc.

Cider is local-first. The user's vault and local SQLite database are the durable foundation.

## Sources Of Truth

- SQLite is the canonical metadata/query layer for Cider-managed entities.
- Vault files are durable user artifacts where the file itself matters: notes, `.webloc` bookmarks, `.ics` todos/events, `.vcf` contacts, and saved files.
- JSON indexes and sidecars are transitional, compatibility, cache, or export surfaces unless explicitly documented otherwise.
- Kanban board YAML files remain the canonical project/workflow store, but selected card detail is projected into SQLite for structured sections and search.

## Second Brain Item Graph

Cider's durable second-brain foundation is SQLite-led. LLMs and Hermes reason over Cider; SQLite owns memory identity, structured state, retrieval hooks, routing records, and provenance.

Schema v9 adds additive foundation tables:

- `item_sections`: typed visual/detail sections for an item or external owner such as a Kanban card.
- `content_chunks`: searchable chunks derived from sections, notes, captures, or imported content.
- `content_chunks_fts`: FTS5 exact-search index over chunk title/body.
- `routing_decisions`: durable record of where an item was routed, why, by whom, and with what confidence.
- `agent_actions`: durable record of agent/CLI/tool actions against an item or projected owner.

Vectors and embeddings may augment retrieval later, but they are not the source of truth. Hybrid retrieval should layer structured filters, FTS5, links/graph expansion, optional embeddings, and reranking.

## Kanban Projection Lifecycle

Kanban YAML remains canonical for boards and card notes in this bridge phase. SQLite projections are rebuildable agent/read-model data.

- Card projection is created or refreshed when Cider writes card notes through `board add-card`, `board update-card`, `board section update`, or `board evidence add`.
- `item backfill-kanban [--board <name-or-id>]` rebuilds projections from canonical board YAML. Use it after branch changes, restores, manual YAML repair, or when an agent needs current search results before the app has naturally refreshed the board.
- Card or board deletion removes matching `item_sections` and `content_chunks` projections so old card text does not remain searchable.
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

Durable sync invariants:

- `ciderSyncId` values are case-insensitive and should be normalized consistently.
- Timestamps exchanged across clients should be unambiguous and comparable.
- Soft deletes/tombstones are safer than silent hard deletes.
- Conflict handling should prefer deterministic last-writer or explicit reconciliation over hidden merges.
- Desktop remains authoritative for local vault safety; Web/iOS clients must not force unsafe local mutations.

## Dashboard Data

Dashboard data is local-first Cider state. Topics, cards, runs, soft-deletes, and provenance belong in Cider-managed storage. Web or remote clients may consume the model only after schema compatibility is explicit.
