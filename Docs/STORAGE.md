# Cider Storage

Status: canonical core doc.

Cider is local-first. The user's vault and local SQLite database are the durable foundation.

## Sources Of Truth

- SQLite is the canonical metadata/query layer for Cider-managed entities.
- Vault files are durable user artifacts where the file itself matters: notes, `.webloc` bookmarks, `.ics` todos/events, `.vcf` contacts, and saved files.
- JSON indexes and sidecars are transitional, compatibility, cache, or export surfaces unless explicitly documented otherwise.
- Kanban board YAML files are a separate project/workflow store, not part of the library graph.

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
