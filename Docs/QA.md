# Cider QA

Status: canonical core doc.

This doc holds reusable QA procedures. Task-specific test evidence belongs on Kanban cards.

## Default Verification

Choose the narrowest meaningful verification:

- model/service change: focused `swift test --filter ...`
- UI policy change: focused unit tests plus manual app check when needed
- CLI change: command run plus JSON parsing when applicable
- storage change: isolated backup/migration/reconcile tests
- release change: build, signing, notarization, and install checks
- web/editor asset change: run the relevant npm tests for the embedded editor/package

## Core Smoke Areas

- launch and floating panel activation
- focus behavior and resize behavior
- bookmark capture, enrichment, detail view, and trash/restore
- note create/edit/save/reopen
- search across saved items
- folder and tag navigation
- Kanban board load, card edit, movement, and YAML validity
- todo/date/contact file watcher behavior
- database backup listing and isolated restore
- dashboard snapshot/card/topic load
- Main Brain identity, send, busy, slash command, and repair paths
- floating/detail pop-out surfaces, focus return, resizing, and pointer interactions
- screen capture and drag/drop routing when touched

## Release Gate

Before a user-facing build:

- run `swift build -Xswiftc -warnings-as-errors`
- run the relevant Swift test suite or focused filters
- run embedded editor tests when TipTap assets changed
- verify signing/notarization for release artifacts
- install or launch the exported app
- verify Sparkle update flow when update delivery is in scope
- explicitly mark experimental/deferred channels such as Telegram before promising them

## Audit Procedures

Reusable audits belong here; task evidence belongs on cards.

- Design-token audit: scan for hardcoded colors, fonts, spacing, radii, shadows, animation curves, and Reduce Motion gaps.
- Storage-integrity audit: verify SQLite authority, vault artifacts, cache-only files, trash/restore, backups, and watcher behavior.
- Threading/runtime audit: check UI work on main actor, background services off the click path, and clear logging.
- Dead-code/code-health audit: identify oversized files, force unwraps, debug logs, stale feature paths, and unsafe direct file mutation.
- Docs-health audit: compare active docs against core-doc policy, convert active work to Kanban, and delete harvested legacy docs.

## Release Scope

Before external users, clearly decide what is included, experimental, or deferred. Do not let old docs promise features that are not currently supported.

## Evidence Rules

- Put task-local evidence on the Kanban card.
- Put reusable procedures here.
- Delete old historical QA reports once any durable procedure or unresolved issue has been harvested.
- Bugs go on the bugs board, not in a QA report doc.

## Regression Rules

When fixing a regression:

1. Find the relevant old card or create a new bug card.
2. Record the failure, root cause, and test evidence on the card.
3. Promote only reusable procedure changes into this doc.
4. Delete temporary investigation docs after harvesting.

Regression areas worth checking after related changes:

- drag/drop URL and image flows
- `.webloc` adoption, deduplication, rename, and URL rewrite behavior
- FSEvents watcher loops and external edit adoption
- sync folder IDs, tombstones, and missing `ciderSyncId`
- DatePicker/popover behavior in panel contexts
- masonry/card sizing after window resize
- note editor save/reopen/image serialization

## Notes Editor Smoke

When note/editor code changes:

- create a note
- edit rich text and Markdown-like content
- paste/drop an image
- close and reopen
- verify external modification protection if relevant
- verify find/search still works

## Reminder Smoke

When todo/date/reminder code changes:

- create todo and date card through UI or CLI
- verify `.ics` file and SQLite state
- verify watcher adoption without restart
- verify local notification scheduling when enabled
- verify recurring event behavior does not complete the whole series accidentally
