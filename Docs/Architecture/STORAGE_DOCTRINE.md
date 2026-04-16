# Storage Doctrine

**Status:** Active target architecture  
**Date:** 2026-04-15

## Purpose

This document defines the storage model Cider is moving toward.

The goal is simple:

- user content remains real files on disk
- SQLite becomes the canonical metadata and query layer
- agents and automation mutate storage through app services, not raw database writes
- sidecars are legacy migration artifacts and will be removed over time

This doctrine is the decision-maker when older docs, legacy services, or transitional code disagree.

## Core Model

### 1. Files are the user-owned artifacts

Every primary Cider item must exist as a real file on disk whenever the underlying format supports it.

- bookmarks: `.webloc`
- notes: `.md`
- todos: `.ics` (`VTODO`)
- date cards: `.ics` (`VEVENT`)
- contacts: `.vcf`

The file is what the user owns, sees in Finder, syncs, and can inspect outside Cider.

### 2. SQLite is the canonical metadata layer

SQLite is the authoritative store for app-managed metadata, indexing, query acceleration, relationships, and AI-facing retrieval.

Examples:

- stable item identity
- title overrides
- notes attached to bookmarks
- tags and labels
- summaries and enrichment output
- OCR text
- thumbnails and asset references
- UI state and app-specific flags
- cross-item links and graph data

In normal operation, rich Cider cards are assembled from:

- file content/artifact data
- SQLite metadata

### 3. Files remain recoverable; metadata is protected separately

If SQLite is lost:

- the file artifact should still survive
- Cider should recover as much as possible from disk
- metadata that only lived in SQLite may be partially lost unless it was backed up

This is an accepted tradeoff of the architecture.

Examples:

- a Markdown note still contains its full body if SQLite is lost
- a `.webloc` still contains the URL if SQLite is lost
- tags, labels, AI summaries, and similar app metadata may require SQLite backup restore

## Canonicality Rules

Use these rules when implementing or reviewing storage behavior.

### Files are canonical for:

- the underlying user content
- the interoperable artifact format
- externally visible presence in the vault

### SQLite is canonical for:

- item metadata
- app relationships
- labels and tags
- search and query indexing
- agent query access
- reminder scheduling state
- restore bookkeeping

### Sidecars are not canonical

Sidecars may exist temporarily during migration, but they are not the target storage model.

New product work should not introduce new sidecar dependencies unless there is a temporary migration need with a clear removal path.

## Write Rules

### All mutations go through app services

The UI, CLI, and agent runtime must all mutate data through validated storage services.

Examples:

- `NotesStorage`
- `VaultBookmarkService`
- `TodoCardStorage`
- `DateCardStorage`
- `ContactStorage`
- `TrashStorage`

They should not:

- write raw SQL for normal product mutations
- edit SQLite tables directly from agent code
- bypass file writes that the service is responsible for

### Write ordering

For file-backed items, a valid mutation path is:

1. update the file artifact if needed
2. update SQLite metadata in the same logical operation
3. publish in-memory state for the UI
4. emit any downstream effects such as search reindexing or reminder reconciliation

Atomicity matters. Multi-step writes should use transactions where possible.

## Recovery and Safety

Because SQLite is the canonical metadata layer, it must be treated as protected infrastructure.

Required safeguards:

- rolling SQLite backups
- snapshot before schema migrations
- integrity checks
- explicit restore path
- mutation audit trail for destructive operations
- rebuild/reconcile from filesystem on launch

The intended safety model is:

- files protect user content
- SQLite backups protect metadata
- service-layer writes protect consistency

## Sidecar Policy

### Allowed right now

Existing sidecars may remain during migration where they currently provide:

- identity recovery
- metadata backfill into SQLite
- compatibility with existing vaults

### Not allowed for new architecture

- new permanent sidecar dependencies
- UI features that only read sidecar metadata when SQLite should own it
- new agent flows that rely on sidecars as the primary metadata store

## Per-Type Direction

### Notes

- `.md` remains the content artifact
- SQLite stores note metadata and cached/query fields
- note sidecar identity and display metadata should be removed

### Bookmarks

- `.webloc` remains the artifact
- SQLite stores bookmark metadata and stable identity
- bookmark sidecar metadata should be migrated fully into SQLite

### Todos, Date Cards, Contacts

- standard file remains the artifact
- SQLite stores app metadata, fast lookup state, and graph/query state
- file-embedded IDs remain useful for reconciliation

### Labels

Labels are metadata, not user-authored content files.

SQLite is canonical, with backup/export support for recoverability.

The existing labels backup file is an acceptable safety exception because it is a vault-level backup artifact, not a per-item sidecar model.

## Definition of Done

The storage transition is complete when:

- every supported item type writes its metadata to SQLite
- sidecars are no longer required for normal reads
- rebuild/reconcile does not depend on sidecars
- UI metadata reads come from SQLite-backed models
- agent and CLI writes go through service-layer mutations
- backup and restore safeguards exist for SQLite
