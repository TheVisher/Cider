# Kanban Docs Governance Audit - 2026-05-03

## Summary

This audit put Cider's docs and Kanban boards under the agreed operating model:

- Docs are durable foundation records.
- Kanban is the active work and handoff surface.
- Durable Kanban outcomes should be promoted into docs.
- Board YAML has one coordinator/writer during multi-agent work.

## Agent Guidance

Normalized guidance in repo and vault-facing agent docs:

- `AGENTS.md`
- `CLAUDE.md`
- `Docs/README.md`
- `Docs/Conventions/DOCS_INFORMATION_ARCHITECTURE.md`
- `/Users/minivish/CiderVault/AGENTS.md`
- `/Users/minivish/CiderVault/CLAUDE.md`
- `/Users/minivish/CiderVault/.cider/memory/agent.md`

Hermes skill and memory were inspected. Hermes skill already contained the governance guardrails, and Hermes memory was not direct-edited.

## New Source-Of-Truth Docs

Created:

- `Docs/Features/Kanban/`
- `Docs/Features/TodosReminders/`

These give Kanban and Todos/Reminders durable feature homes instead of relying on old product vision sections, implementation plans, or active cards as the only reference.

## Historical Labels

Marked older Dashboard, MainBrain/Hermes, Storage/SQLite, and Kanban docs as historical, transitional, or source-context where they were no longer the current source of truth.

Major current homes:

- Dashboard: `Docs/Features/Dashboard/`
- Main Brain/Hermes: `Docs/Features/MainBrain/`
- Future Agent Host boundary: `Docs/Features/AgentHost/README.md`
- Storage doctrine: `Docs/Architecture/STORAGE_DOCTRINE.md`
- Kanban: `Docs/Features/Kanban/`
- Todos/Reminders: `Docs/Features/TodosReminders/`

## Board Cleanup

Roadmap Testing was reduced from 10 cards to 4 cards.

Moved to Done as verified duplicate/stale QA cards:

- `t001` Image Cards
- `t002` oEmbed & Enrichment
- `t004` Image Drop on Bookmark
- `t005` Note Pinning & Tags
- `t006` Card UI Polish
- `t007` Kanban Escape Key

Kept in Testing because they still need clearer manual verification or product decision:

- `v1b001` VaultBookmarkService Storage Rework
- `b1c011` Screen Capture Polish
- `f1a001` Folder Kanban View
- `t008` File Watchers for Todos/Events/Contacts

Vault Agent Work Ready to test was reduced from 18 cards to 10 cards.

Moved to Done as covered by the reusable Telegram regression set:

- `31a6f7`
- `63e960`
- `bb135a`
- `c9c40c`
- `a9f277`
- `f0fe61`
- `fac0e9`
- `5fb490`

Kept in Ready to test because they still need behavior or logging verification:

- durable memory behavior cards
- runtime logging cards
- recent-thread handoff restore

## Verification

Commands run:

```bash
/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli board list --json
/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli board show "Cider Roadmap" --json
/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli board show "Vault Agent Work" --json
find Docs -name '*.md' | wc -l
rg -n 'TBD|TODO|implement later|fill in details|Similar to Task' Docs/Features/Kanban Docs/Features/TodosReminders Docs/Features/Dashboard/DECISIONS.md Docs/README.md
```

Results:

- All 5 boards load.
- `Cider Roadmap` loads after YAML edits.
- `Vault Agent Work` loads after YAML edits.
- Docs count is 114 Markdown files.
- New feature docs have no placeholder markers.

## Remaining Work

- Review the four remaining `Cider Roadmap` Testing cards manually.
- Decide whether old fixed bug history should be archived by release boundary.
- Decide whether the fully completed `Kanban Implementation` board should remain visible or become historical/archive-only.
- Continue trimming Vault Agent Work Ready to test after real runtime/logging verification.

