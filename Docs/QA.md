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

For startup/migration safety changes, use disposable physical SQLite files and fingerprint the database, WAL, SHM, and containing manifest before and after every refused preflight. Cover current and older healthy schemas, a real uncheckpointed WAL, corrupt header/pages/WAL, unreadable input, future schema, orphan sidecars, artifact capture/verification failure, migration rollback with retained artifact, physical close/reopen, and overlapping real processes. Deterministically force a database to appear while another startup waits on serialization, and force old, current, and corrupt sources to appear at the real VFS open boundary after fresh classification. Prove a path-race winner is reclassified through existing-source health/artifact policy, corrupt refusal preserves exact bytes and manifest, and the exclusive-create loser never opens the late source as fresh. Also force a same-inode/same-size external SQLite commit after artifact verification and prove it cannot be migrated from an artifact that lacks the commit. Production-order guards must inspect the real source root and known app/CLI/database owners rather than a copied fixture.

## Core Smoke Areas

- launch and floating panel activation
- focus behavior and resize behavior
- capture -> enrich -> route -> review flow when touched
- bookmark capture, enrichment, detail view, and trash/restore
- note create/edit/save/reopen
- search across saved items
- item get/search/context JSON for second-brain recall changes
- folder and tag navigation
- Spaces dashboard/routed capture surfacing when touched
- Review Queue list, approve, correct, and defer when touched
- Kanban board load, card edit, movement, and YAML validity
- todo/date/contact file watcher behavior
- database backup listing and isolated restore
- dashboard snapshot/card/topic load
- Main Brain identity, send, busy, slash command, and repair paths
- floating/detail pop-out surfaces, focus return, resizing, and pointer interactions
- screen capture and drag/drop routing when touched
- Journal voice Record/stop/cancel, provider permission timing, atomic day transcript plus native audio source-card playback, and temporary-file cleanup when touched

## Hang and Crash Capture

When chasing intermittent rainbow-spinner hangs or unexplained app freezes, launch Cider from the repo with:

```bash
./script/build_and_run.sh --telemetry
```

Keep that terminal running while using the app. It writes a timestamped session under `~/Library/Logs/Cider/` with:

- `unified.log`: macOS unified logs for the Cider process and `com.cider.app` subsystem.
- `performance.log`: `CIDER_PERF` context/frame samples, `CIDER_NAV` route changes, and `CIDER_HANG` suspected main-thread stalls.
- `stdout.log` and `stderr.log`: app process output.
- `process-stats.tsv`: periodic CPU, memory, process state, and elapsed-time samples.
- `samples/`: periodic `sample` stack captures for post-hang inspection.

If Cider hangs, leave the telemetry command running long enough for at least one more sample, then stop it with `Ctrl-C`. Put the log directory path, reproduction steps, visible UI state, nearest `CIDER_NAV` line, any `CIDER_HANG` line, and the nearest sample file on the relevant bug card.

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
- Docs-health audit: compare active docs against `Docs/PRODUCT.md`, core-doc policy, and the active roadmap card; convert active work to Kanban and leave legacy context in git history.

## Capture Quality Matrix

Use this matrix when capture, bookmark enrichment, provider metadata, review routing, or agent-visible capture JSON changes. A capture is not good just because an item row exists. Check lifecycle success and visible quality separately.

For each fixture, record:

- command or UI entry point used
- final canonical item ID
- title and `.webloc` relative path
- thumbnail/card source and local thumbnail presence
- enrichment status and provider/fallback reason
- route/review state
- app/CLI/API agreement after the capture settles

Reusable fixtures:

| Fixture | Example | Expected visible quality | Quality checks |
| --- | --- | --- | --- |
| GitHub repo, old-good comparison | `https://github.com/nodes-app/swift-markdown-engine` | Repository-shaped title, GitHub Open Graph or repo-specific card, thumbnail stored locally, no generic `Github.Com` card after settle. | Compare against an existing good capture; verify `item get`, `bookmark get`, SQLite, and Library card agree on title, thumbnail, and path. |
| GitHub repo, current regression | `https://github.com/AndrewPrifer/liquid-dom` | Same repo-card quality as the old-good fixture. A remote Open Graph URL without a local thumbnail is partial/degraded, not complete quality. | Verify title is rich, path is not host-only drift, thumbnail download/card source is present or a retryable provider failure is reported. |
| Social short link | TikTok short URLs such as `https://www.tiktok.com/t/...` | oEmbed/native title and author when available, real video thumbnail, canonical item updated instead of app-only rich state. | Check app, CLI, duplicate-check, and SQLite converge on the same item ID/title/thumbnail after bounded wait. |
| Store/media page | Steam store URLs such as `https://store.steampowered.com/app/...` | Store title, provider capsule/header image, media-route metadata where applicable. | Confirm provider image beats generic screenshot, thumbnail is local or failure is explicit, and route/review state is observable. |
| Product page | Vans/product URLs | Product title and hero image fill card area; icon/touch-icon fallbacks must not count as quality. | Check thumbnail dimensions/render mode, remote URL provenance, and no stale icon-overlay cache decision. |
| Local/restaurant page | Restaurant or local discovery pages | Human-meaningful place title and useful image when provider metadata exists. | Verify capture does not settle as high quality with only host title, missing thumbnail, and no route/review explanation. |

Pass/fail guidance:

- Lifecycle pass: item exists, duplicate state is correct, provenance/indexing/routing side effects are recorded or explicitly reported as partial.
- Metadata pass: title is not generic host-only unless no better metadata exists and the fallback is reported.
- Thumbnail/card pass: expected provider thumbnail/card is local and app-visible, or provider failure is retryable and marked degraded.
- Canonical parity pass: app, CLI JSON, duplicate-check, search/context, and SQLite refer to the same item ID and final metadata.
- Drift pass: title, filename/path, search chunks, and visible card state agree unless an explicit review/repair state explains the mismatch.

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

- capture/routing/review provenance and uncertainty handling
- drag/drop URL and image flows
- `.webloc` adoption, deduplication, rename, and URL rewrite behavior
- FSEvents watcher loops and external edit adoption
- sync folder IDs, tombstones, and missing `ciderSyncId`
- DatePicker/popover behavior in panel contexts
- masonry/card sizing after window resize
- note editor save/reopen/image serialization
- Space dashboards over shared item state

## Notes Editor Smoke

When note/editor code changes:

- create a note
- edit rich text and Markdown-like content
- paste/drop an image
- close and reopen
- verify external modification protection if relevant
- verify find/search still works

## Journal Voice Smoke

Use synthetic/disposable audio and a disposable database/vault for automated coverage. Never request microphone or Speech permission in tests. Verify idle does not prompt; explicit Record requests only the permissions required by the selected provider; stop yields one final normalized transcript, one canonical receipt, and one native audio source card on the selected day; exact retry reuses that receipt; changed bytes fail closed; and cancel, provider failure, atomic-writer failure, view loss, or app background yields no new Journal mutation and no working file. The remaining user-level gate is a signed-app visual check plus one explicit real-microphone Record/stop/save and one cancel, followed by native source-card playback.

## Reminder Smoke

When todo/date/reminder code changes:

- create todo and date card through UI or CLI
- verify `.ics` file and SQLite state
- verify watcher adoption without restart
- verify local notification scheduling when enabled
- verify recurring event behavior does not complete the whole series accidentally
