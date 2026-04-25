# Pre-User Knockout Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` when implementing items from this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clear the smallest release-readiness issues first, then move through progressively harder reliability, QA, and distribution work until Cider is safe to push to early users.

**Architecture:** This is a difficulty-ordered working list, not a product roadmap. Each item should be fixed, verified, and checked off before moving on unless it is explicitly deferred or hidden from users.

**Tech Stack:** Swift 6.2, SwiftUI/AppKit, Swift Package Manager, XCTest/Swift Testing, TipTap editor Node tests, Sparkle, Cidervault YAML boards.

## Current Handoff Status

Last updated: `2026-04-24` on branch `codex/batch-1-knockouts`, immediately before merging to `main`.

Completed in this batch: Items 1-10, 13, and 14 are checked off. Item 11 has local Sparkle wiring/tool-path cleanup done, but the signed appcast/update install flow remains open. Item 12 confirms SQLite is the canonical bookmark metadata layer and `.webloc` files are durable user artifacts; the roadmap card should only move out of `in_progress` after a broader signed/manual storage pass. Item 17 has the everyday data safety workflows marked covered by prior manual testing; the explicit rolling SQLite backup and restore-from-backup checks remain open.

Important recovery note: during Item 14, a test-only `VaultBookmarkService(database:)` instance exposed a bug where test services could still write the real vault bookmark index cache. The real vault files were not deleted, but `_cider_bookmarks_index.json` was temporarily collapsed to test data. Recovery rebuilt the cache from SQLite/files, removed the two test rows from the real DB, and added a `writesVaultCaches` guard so injected test services cannot write real vault caches or trigger sync. Recovery snapshots are under `~/CiderVault/.cider/recovery-20260424-1932/`.

Next useful work:
- Finish Item 15 by either hiding/marking Telegram as experimental for first users, or fixing reminders, image attachments, runtime status, and regression prompts.
- Finish Item 16 with a full release packaging dry run.
- Finish the remaining Item 17 backup existence and restore-from-backup checks.
- Finish Item 11 only when a signed archive/appcast/update-install flow is ready to test.

---

## How To Use This

- Work top to bottom.
- After each fix, run the item-specific verification.
- After a batch of easy fixes, run the batch gate:

```bash
swift build
swift test
cd tiptap-editor && npm test
```

- Before any beta/user push, run the final gate:

```bash
swift build -Xswiftc -warnings-as-errors
swift test
cd tiptap-editor && npm test
```

---

## Easy

### 1. Update Stale QuickAction Tests

**Why:** `swift test` currently fails only because the tests expect the old quick-action count.

**Files:**
- Modify: `Tests/CiderTests/QuickActionTests.swift`
- Reference: `Sources/Cider/Views/Search/SearchPaletteView.swift`

- [x] Confirm current `QuickAction.allCases` includes 10 actions.
- [x] Update `testAllCasesCount()` from `8` to `10`.
- [x] Update creation-action expectations from `7` to `9`.
- [x] Run:

```bash
swift test --filter QuickActionTests
```

- [x] Expected: all `QuickActionTests` pass.
- [x] Run:

```bash
swift test
```

- [x] Expected: full Swift test suite passes.

### 2. Refresh The Release Checklist Open-Issue Section

**Why:** `Docs/QA/RELEASE_CHECKLIST.md` still lists old open issues that the live bug board says were fixed, which makes the ship state muddy.

**Files:**
- Modify: `Docs/QA/RELEASE_CHECKLIST.md`
- Reference: `/Users/minivish/CiderVault/.cider/boards/d4e5f6.yaml`

- [x] Replace the stale post-QA open-items table with the live bug-board state.
- [x] Mark old fixed items as fixed or remove them from the open pre-release list.
- [x] Keep only currently open bugs:
  - Drag-drop URL no drop zone.
  - Carousel arrows blocked by hover overlay.
  - Telegram reminder did not fire.
  - Telegram agent does not receive image attachments.
  - Low-priority quick tab drag / doubled extension visual test / Cmd+K tab filter, if still intentionally tracked.
- [x] Add a note that the checklist was reconciled against the Cidervault bug board on `2026-04-24`.

### 3. Decide What To Hide Or Defer For The First User Push

**Why:** Some advanced surfaces are not release blockers if they are not part of the first-user promise.

**Files:**
- Modify: this file
- Optionally modify: `Docs/Product/PRODUCT_VISION.md`
- Optionally modify: `Docs/QA/RELEASE_CHECKLIST.md`

- [x] Decide whether Telegram/reminders are included in the first push.
- [x] Decide whether whiteboard/session features are included or treated as experimental.
- [x] Decide whether Convex/iOS sync is included, hidden, or clearly labeled as not part of desktop beta.
- [x] Write the decision under "First Push Scope" at the bottom of this document.

---

## Easy-Medium

### 4. Fix Warnings-As-Errors In Drag Payload Registration

**Why:** Normal `swift build` passes, but the documented release gate fails because `NSItemProvider.registerDataRepresentation` completion calls produce actor-isolation warnings.

**Files:**
- Modify: `Sources/Cider/Utilities/CiderDragPayload.swift`

- [x] Fix completion-handler isolation warnings at the URL, image, note file URL, and multi-drag data registrations.
- [x] Keep drag-out behavior intact for bookmarks, images, notes, and multi-select.
- [x] Run:

```bash
swift build -Xswiftc -warnings-as-errors
```

- [x] Expected: build passes with no Cider warnings-as-errors failure.
- [x] Manually tested on `2026-04-24`:
  - Drag bookmark to Finder.
  - Option-drag bookmark image to Finder.
  - Drag note to Finder and confirm it exports as `.md`.
  - Drag note into a Cider folder.
  - Multi-select drag still works inside Cider.

### 5. Reconcile macOS Minimum Version

**Why:** README says macOS 14+, while `Package.swift` and Xcode target macOS 26.0. Users need an honest compatibility promise.

**Files:**
- Modify: `README.md`
- Modify: `Package.swift`
- Modify: `Cider.xcodeproj/project.pbxproj`
- Check: `Sources/Cider/Resources/Info.plist`

- [x] Decide the real minimum supported macOS version.
- [x] If Cider now requires macOS 26, update README requirements and download copy.
- [x] If Cider should support macOS 14, identify and gate/remove macOS 26-only dependencies and APIs.
- [x] Run:

```bash
swift build
swift test
```

- [x] Expected: build and tests pass after the target/version decision.

Decision captured on `2026-04-24`: first-user builds target macOS 26.0 or later. `Package.swift`, `Cider.xcodeproj`, `Info.plist`, and architecture docs already used macOS 26.0 as the effective deployment target; the stale README/Appcast docs were corrected rather than back-porting this batch to macOS 14.

### 6. Update Build Status

**Why:** `Docs/BUILD_STATUS.md` is stale and still says Swift was skipped in sandbox. We now have current local results.

**Files:**
- Modify: `Docs/BUILD_STATUS.md`

- [x] Add a `2026-04-24` row with:
  - `swift build`: pass, with Convex linker deployment-target warnings.
  - `swift build -Xswiftc -warnings-as-errors`: fail until item 4 is fixed.
  - `swift test`: pass after item 1 is fixed.
  - TipTap `npm test`: pass.
- [x] After item 4 is fixed, update the row to reflect the final green warnings-as-errors state.

---

## Medium

### 7. Fresh Manual QA Pass For Core Desktop

**Why:** The old checklist has useful coverage, but the current app has moved. Do one current pass focused only on what first users will touch.

**Files:**
- Modify: `Docs/QA/RELEASE_CHECKLIST.md`

- [x] Test launch, onboarding, permissions, and settings.
- [x] Test panel activation, focus behavior, resize, and multi-monitor behavior.
- [x] Test bookmark capture, enrichment, detail view, reader/web tabs, drag-out, trash/restore.
- [x] Test notes create/edit/autosave, formatting smoke, image attachments, drag-out, trash/restore.
- [x] Test folders, tags, saved views, search, import/export.
- [x] Test clipboard and screen capture if included in first push.
- [x] Record pass/fail directly in the release checklist.

Fresh QA pass recorded on `2026-04-24` in `Docs/QA/RELEASE_CHECKLIST.md`. Computer Use covered visible launch state, settings panes, panel navigation, folder/tag views, search, existing bookmark detail modes, existing note open/autosave state, and clipboard panel. User confirmed activation/dismiss, resize, focus behavior, multi-monitor activation, trash/restore, import, and deeper note editing/image attachment flows are acceptable based on recent or prior manual testing. A stale debug instance briefly failed horizontal resize; restarting from Xcode resized correctly, and `CiderPanel` now defensively excludes resize edge bands from panel-drag hit testing. Remaining known gap is the visible URL drop area, tracked separately as Item 8.

### 8. Fix Drag-Drop URL Drop Zone

**Why:** Dragging a URL into Cider is a basic capture affordance; the bug board says there is no visible drop target.

**Files To Inspect:**
- `Sources/Cider/Views/CiderPanelView.swift`
- `Sources/Cider/Views/CiderPanelView+ContentArea.swift`
- `Sources/Cider/Views/Bookmarks/BookmarkCard.swift`
- `Sources/Cider/Services/VaultBookmarkService.swift`

- [x] Add a visible drop overlay when a URL is dragged over the panel.
- [x] Accept URL drops and create a bookmark through the same service path as other captures.
- [x] Verify enrichment starts after drop.
- [x] Manual test:
  - Drag URL from browser address bar into Cider.
  - Confirm bookmark appears in the expected folder/inbox.
  - Confirm no focus-stealing regression.

Code update on `2026-04-24`: `CiderPanelView` now has a panel-level URL drop target with a visible overlay, and dropped URLs call `VaultBookmarkService.add(urlString:title:folderID:)`. New bookmarks are written to the selected folder when one is active, otherwise Inbox, and the existing add path still calls `startEnrichmentIfNeeded`.

Manual test on `2026-04-24`: user confirmed dragging a browser URL over empty panel space shows a clear drop indicator and works acceptably for this pass.

Follow-up manual test on `2026-04-24`: user confirmed internal Cider bookmark drags no longer trigger the panel URL drop zone after adding an internal-drag guard. Browser URL drops still need to be treated as the external target path.

### 9. Fix Carousel Arrows Under Hover Overlay

**Why:** This is a polished-user-experience bug on visual bookmark cards.

**Files To Inspect:**
- `Sources/Cider/Views/Bookmarks/BookmarkCard.swift`
- `Sources/Cider/Views/Bookmarks/BookmarkThumbnailView.swift`
- `Sources/Cider/Views/Bookmarks/BookmarkVisualStyle.swift`

- [x] Ensure carousel navigation controls render above the hover/details overlay.
- [x] Preserve hide-details-on-hover behavior.
- [x] Manual test:
  - Enable hide card details / show on hover.
  - Open a multi-image bookmark card.
  - Click carousel arrows.
  - Confirm arrows remain clickable and visually legible.

Code/manual update on `2026-04-24`: the hover-details footer is visual-only for hit testing, and carousel arrows now sit vertically centered in the thumbnail so they are no longer covered by the hover footer. User accepted the result as good enough for this pass.

### 10. Visual Test Doubled Extension Fix

**Why:** The bug board says the doubled extension fix exists in code but still needs visual testing.

**Files To Inspect:**
- `Sources/Cider/Utilities/CiderDragPayload.swift`
- `Sources/Cider/Views/Bookmarks/BookmarkCard.swift`
- `Sources/Cider/Views/Bookmarks/BookmarkThumbnailView.swift`

- [x] Option-drag a bookmark image to Finder.
- [x] Confirm filename does not become `title.jpg.jpeg` or similar.
- [x] If still broken, fix filename extension normalization.
- [x] Retest after rebuild: `jpg` titles backed by `.jpeg` files should export as one extension, not `jpg.jpeg`.

---

## Medium-Hard

### 11. Finish Sparkle Auto-Updater Setup And Test Flow

**Why:** If users get a direct-download beta, updates are a trust feature and reduce support pain.

**Files:**
- Modify/check: `Cider.xcodeproj/project.pbxproj`
- Modify/check: `Sources/Cider/Resources/Info.plist`
- Modify/check: `Docs/Architecture/SPARKLE_SETUP.md`
- Possibly add: appcast hosting files

- [x] Confirm Sparkle package is linked in the Xcode app target.
- [ ] Build a signed app archive.
- [ ] Generate or update appcast XML.
- [ ] Host appcast at `https://thevisher.github.io/Cider/appcast.xml` or update `SUFeedURL`.
- [ ] Create a test older build and a newer build.
- [ ] Use "Check for Updates Now" and verify Sparkle offers and installs the newer build.
- [ ] Document exact release/update steps.

Local update on `2026-04-24`: the Xcode debug app embeds `Contents/Frameworks/Sparkle.framework`, `Cider.debug.dylib` links Sparkle 2.9.0, and the built app plist contains `SUFeedURL`, `SUPublicEDKey`, and `LSMinimumSystemVersion` `26.0`. `scripts/release.sh` now finds Sparkle tools in `.build/xcode/SourcePackages/artifacts/sparkle/Sparkle/bin` and the generated GitHub release notes no longer claim macOS 14 support. Remaining unchecked steps require signed/notarized release artifacts and live appcast/install testing.

### 12. Verify Storage Rework Is Not Mid-Flight

**Why:** `VaultBookmarkService (Storage Rework)` is still in progress on the roadmap board. Shipping while storage source-of-truth work is half-finished risks data loss or confusing migration behavior.

**Files To Inspect:**
- `Sources/Cider/Services/VaultBookmarkService.swift`
- `Sources/Cider/Services/BookmarksStorage.swift`
- `Docs/Architecture/STORAGE.md`
- `Docs/Architecture/STORAGE_DOCTRINE.md`
- `/Users/minivish/CiderVault/.cider/boards/a1b2c3.yaml`

- [x] Confirm which bookmark storage path is authoritative.
- [x] Confirm legacy JSON/sidecar paths are transition-only and cannot overwrite newer SQLite state.
- [x] Confirm import/export still works.
- [x] Confirm external `.webloc` changes reconcile correctly or are clearly unsupported for first push.
- [ ] Move the board card out of `in_progress` only after the storage story is safe.

Storage review on `2026-04-24`: `VaultBookmarkService` is the active bookmark runtime path; current UI, settings import/export, AI tools, sync, labels, trash, and clipboard call `VaultBookmarkService.shared`, while `BookmarksStorage.shared` is only referenced by `VaultMigrationService` for legacy migration reads. Bookmark `.webloc` files are durable user artifacts and SQLite is the canonical metadata/query layer per `Docs/Architecture/STORAGE_DOCTRINE.md`; `_cider_bookmarks_index.json` remains a cache/external edit bridge. Legacy bookmark sidecars are now one-time migration/backfill inputs and normal file scans pass `includeLegacySidecarMetadata: false`. Import/export uses `VaultBookmarkService.importNetscapeHTML` / `exportNetscapeHTML`. Local hardening added in this pass: externally edited tracked `.webloc` files with the same relative path but a changed URL now update the existing bookmark in place instead of adopting a duplicate. The roadmap card remains in progress until a broader signed/manual storage test pass is done.

### 13. Verify File Watchers For Todos, Events, And Contacts

**Why:** This is in testing as high priority. If agents/CLI/external edits create files, Cider should reflect them without restart.

**Files To Inspect:**
- `Sources/Cider/Services/TodoCardStorage.swift`
- `Sources/Cider/Services/DateCardStorage.swift`
- `Sources/Cider/Services/ContactStorage.swift`
- `Sources/Cider/Utilities/FSEventsWatcher.swift`
- `/Users/minivish/CiderVault/.cider/boards/a1b2c3.yaml`

- [x] Create a todo `.ics` externally or through `cider-cli`.
- [x] Confirm it appears in Cider without restart.
- [x] Create an event/date-card `.ics` externally or through `cider-cli`.
- [x] Confirm it appears in Cider without restart.
- [x] Create a contact `.vcf` externally or through `cider-cli`.
- [x] Confirm it appears in Cider without restart.
- [x] Document any unsupported paths.

CLI/file verification on `2026-04-24`: while debug Cider PID `84710` was running, `cider-cli` created `QA Watcher Todo 20260424-175217` (`E4F91F28`), `QA Watcher Event 20260424-175217` (`94D42951`), and `QA Watcher Contact 20260424-175217` (`48F14E27`). Matching files appeared under `Inbox/Todos`, `Inbox/Date Cards`, and `Inbox/Contacts`, and `cider-cli list` showed all three.

Manual visual confirmation on `2026-04-24`: user confirmed the same QA watcher event, contact, and todo appeared in the running Cider app without restart. No unsupported watcher paths were found in this pass.

### 14. Run Focused Enrichment Regression

**Why:** Visual enrichment is a big part of Cider feeling magical. The board has oEmbed/enrichment still in testing.

**Files To Inspect:**
- `Sources/Cider/Services/AI/BookmarkAIEnrichment.swift`
- `Sources/Cider/Services/AI/OEmbedService.swift`
- `Sources/Cider/Services/BookmarkMetadataParser.swift`
- `Sources/Cider/Services/WebViewMetadataExtractor.swift`

- [x] Save a TikTok URL and verify descriptive title/notes/thumbnail.
- [x] Save a YouTube URL and verify video metadata/thumbnail.
- [x] Save an Amazon URL and verify product-ish metadata or graceful fallback.
- [x] Save a Reddit gallery and verify carousel images populate.
- [x] Refetch metadata for a manually renamed bookmark and verify the title is not overwritten.

Automated regression on `2026-04-24`: `BookmarkSQLiteTests` now covers oEmbed and AI enrichment result application for bookmarks with `titleManuallySet == true`. Both paths preserve the curated title while still applying safe enrichment fields such as notes, tags, OCR text, and colors. Code inspection confirms forced refetch routes title writes through the same manual-title guard.

Manual live confirmation on `2026-04-24`: user confirmed TikTok, YouTube, Amazon, and Reddit gallery links pull titles, notes, thumbnails, and the Intelligence section populates for each.

---

## Hard

### 15. Decide And Harden Telegram/Reminder Scope

**Why:** The live bug board has two medium Telegram bugs. This can be deferred only if Telegram is not part of first-user scope.

**Files To Inspect:**
- `Sources/Cider/Services/Channels/Telegram/TelegramBridge.swift`
- `Sources/Cider/Services/ReminderReconciler.swift`
- `Sources/Cider/Services/ReminderOutbox.swift`
- `Sources/Cider/Services/Agent/CodexProcessRuntime.swift`
- `Docs/Architecture/CODEX_TELEGRAM_HANDOFF_2026-04-14.md`
- `Docs/Architecture/TELEGRAM_AGENT_REGRESSION_SET.md`

- [ ] Rotate the Telegram bot token before any external testing.
- [ ] If Telegram is included, fix scheduled Telegram reminder delivery.
- [ ] If Telegram is included, fix image attachment ingestion or clearly disable attachment promises.
- [ ] Run the Telegram regression prompt set.
- [ ] Add `/runtime` or visible runtime status if Telegram remains enabled.
- [ ] If Telegram is deferred, hide the feature or mark it experimental in settings/docs.

### 16. Full Release Packaging Dry Run

**Why:** A passing debug build is not the same as a user-installable app.

**Files:**
- `scripts/release.sh`
- `scripts/ExportOptions.plist`
- `Cider.xcodeproj/project.pbxproj`

- [ ] Run release script with a test version and `--skip-github` if needed.
- [ ] Verify archive/export succeeds.
- [ ] Verify code signing.
- [ ] Verify notarization or document manual beta exception.
- [ ] Install from the generated DMG on a clean-ish user account or machine.
- [ ] Launch and complete the core smoke test.

### 17. First-Run Data Safety Drill

**Why:** Cider owns a personal vault. Before users, prove backup/restore and trash behavior under realistic mistakes.

**Files To Inspect:**
- `Sources/Cider/Services/DatabaseSafetyService.swift`
- `Sources/Cider/Services/TrashStorage.swift`
- `Sources/Cider/Database/VaultReconciler.swift`
- `Docs/Architecture/STORAGE_DOCTRINE.md`

- [x] Create a disposable test vault with bookmarks, notes, todos, events, contacts, and files.
- [x] Delete one of each type and restore it.
- [x] Move folders and verify items keep identity.
- [x] Simulate app restart after mutations.
- [ ] Verify rolling SQLite backup exists.
- [ ] Verify restore-from-backup path works.

Manual coverage note on `2026-04-24`: user confirmed delete/restore from trash has been tested repeatedly across app development and works. User also confirmed the broader data safety drill has been tested before; backup existence and restore-from-backup are left open for a later explicit recheck.

---

## First Push Scope

Use this section to make the release promise explicit before inviting users.

- [x] **Included:** Core floating panel, bookmarks, notes, folders/tags, search, trash/restore.
- [x] **Included:** Clipboard capture, because it is part of the README first-user promise.
- [x] **Included:** Screen capture, because it is part of the README first-user promise; verify in the fresh core QA pass.
- [x] **Experimental/deferred:** Whiteboard. Do not promise it to first users unless a dedicated QA pass signs it off.
- [x] **Deferred:** Browser sessions. Session entities are currently legacy/back-compat surfaces in the app.
- [x] **Deferred:** Telegram remote agent and Telegram reminders. The bug board still tracks reminder and attachment issues.
- [x] **Deferred:** Convex/iOS sync. Desktop can ship as a local-first beta before promising cross-device sync.
- [x] **Deferred for first external push:** Sparkle auto-updates. Direct-download beta can proceed, but broader beta/1.0 should complete the Sparkle test flow.

Decision captured on `2026-04-24`: the first user push is a local-first macOS desktop beta centered on capture, notes, bookmarks, organization, search, and trash/restore. Remote agents, sync, whiteboard, browser sessions, and auto-update promises stay out of first-user copy until their specific QA gates pass.

---

## Current Verification Snapshot

Captured during inspection on `2026-04-24`:

- `tiptap-editor`: `npm test` passed, 10/10.
- `swift build`: passed, with Convex linker deployment-target warnings.
- `swift build -Xswiftc -warnings-as-errors`: now passes after fixing `CiderDragPayload.swift`; Convex linker deployment-target warnings remain.
- `swift test`: now passes after updating stale `QuickActionTests` expectations and drag payload regression tests.
- Manual drag/export retest: note drag-out exports `.md`, option-drag image exports one `.jpeg` extension, and normal note drag into Cider folders works.
- Live bug board: no open high-priority bugs; four open medium-priority bugs.
