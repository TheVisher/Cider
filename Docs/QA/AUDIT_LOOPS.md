# Audit Loops

Reusable automated audit loops for enforcing code quality across the Cider codebase. Each loop is a self-contained checklist that Claude can run on command.

## Table of Contents

- [Code Audit Loop](#code-audit-loop)
- [Convention Enforcement Loop](#convention-enforcement-loop)
- [Dead Code Detection Loop](#dead-code-detection-loop)
- [Documentation Health Loop](#documentation-health-loop)
- [Storage Integrity Loop](#storage-integrity-loop)
- [Threading Safety Loop](#threading-safety-loop)

---

## Code Audit Loop

Reusable automated audit for enforcing design token consistency across the Cider codebase.

### When to run
- After major feature work
- Before releases
- Quarterly health check
- Any time you want to validate codebase consistency

### How to run

Tell Claude: **"Run the code audit loop"** — it will read this doc and know what to do.

### Setup

1. Create a branch: `git checkout -b audit-fixes`
2. Start the loop: `/loop 15m Run the code audit loop per Docs/QA/AUDIT_LOOPS.md`
3. Let it run — it cycles through each area, fixes violations, verifies with `swift build`
4. Review the diff when done, merge if clean

### Rules checked

1. No `.easeIn`, `.easeOut`, `.linear` — spring animations only
2. Every `withAnimation` must have `reduceMotion` check (`.hoverState` handles internally)
3. No hardcoded colors — use `CiderColors.*`
4. No hardcoded font sizes — use `CiderFont.*`
5. No magic numbers for spacing/radius — use `Spacing.*`, `Radius.*`, or named `*Design` constants

### Token mappings

#### CiderFont (by base size)
| Size | Tokens |
|------|--------|
| 8 | badge, badgeSemibold |
| 9 | micro, microMedium, microBold |
| 10 | caption, captionMedium, captionSemibold, captionBold |
| 11 | body, bodyMedium, bodySemibold, monospacedBody |
| 12 | label, labelMedium, labelSemibold |
| 13 | subheading, subheadingMedium, subheadingSemibold |
| 14 | heading, headingMedium, headingSemibold, headingBold |
| 16 | title, titleMedium |
| 20 | display, displaySemibold, displayBold |
| 28 | heroFallback, settingsEmptyIcon |

#### CiderColors (common replacements)
| Hardcoded | Token |
|-----------|-------|
| `.green` / `.foregroundColor(.green)` | `CiderColors.success` |
| `.orange` / `.foregroundColor(.orange)` | `CiderColors.warning` |
| `Color.black.opacity(0.28)` | `CiderColors.backdrop` |
| `Color.black.opacity(0.38)` | `CiderColors.acrylicOverlayTint` |
| `Color.black.opacity(0.45)` | `CiderColors.acrylicTint` |
| `Color.black.opacity(0.55)` | `CiderColors.trafficLightSymbol` |
| `Color.black.opacity(0.72)` | `CiderColors.overlayDark` |
| `Color.black.opacity(0.4)` | `CiderColors.shadowHeavy` |
| `Color.white.opacity(0.03)` | `CiderColors.surfaceHighlight` |
| `Color.white.opacity(0.04)` | `CiderColors.surfaceSubtle` |
| `Color.white.opacity(0.06)` | `CiderColors.surfaceElevated` |
| `Color.white.opacity(0.08)` | `CiderColors.surfaceInput` |
| `Color.white.opacity(0.1)` | `CiderColors.surfaceHover` |
| `Color.white.opacity(0.12)` | `CiderColors.borderDefault` |
| `Color.white.opacity(0.2)` | `CiderColors.borderStrong` |
| `Color.white.opacity(0.25)` | `CiderColors.borderPanel` |
| `Color(.windowBackgroundColor)` | `CiderColors.opaqueBackground` |
| `CiderColors.success.opacity(0.08)` | `CiderColors.successSubtle` |

#### Spacing tokens
`hairline:1 | xxs:2 | xs:4 | sm:8 | md:12 | lg:16 | xl:20 | xxl:24 | xxxl:32`

#### Radius tokens
`xs:4 | sm:6 | md:10 | lg:14 | xl:20` (always `.continuous`)

### Known non-violations (skip these)
- `Color.clear` — structural transparency
- `Color(hex:)` from model data — data-driven colors
- `.opacity(condition ? 1 : 0)` — binary visibility toggles
- `spacing: 0` — explicit zero-gap layout
- `.hoverState()` — handles reduceMotion internally
- Token definitions inside Constants.swift / CiderFont.swift — source of truth
- `NSColor.white.cgColor` in CoreGraphics rendering contexts
- `.font(.system(size: computedParam))` — computed parameter, not raw literal
- Time constants (86400), notification intervals, grammar checks (`count == 1`)
- `.scale(0.95)` in transitions

### 3-pass verification

Each area requires 3 independent clean scans before PASS. If any scan finds a new violation, fix it and reset to 1/3. This ensures thoroughness — single passes consistently miss edge cases.

### Areas (scan order)
App/ -> Models/ -> Utilities/ -> Services/ -> Services/AI/ -> ViewModels/ -> Views/Bookmarks/ -> Views/Notes/ -> Views/Home/ -> Views/Shared/ -> Views/Search/ -> Views/Settings/ -> Views/AIAssistant/

### Progress tracking
Results are logged in `Docs/QA/AUDIT_REPORTS.md`.

---

## Convention Enforcement Loop

Automated audit for enforcing CLAUDE.md coding conventions across the Cider codebase.

### When to run
- After major feature work
- Before releases
- When onboarding new patterns
- Any time you want to validate convention compliance

### How to run

Tell Claude: **"Run the convention enforcement loop"** — it will read this doc and know what to do.

### Setup

1. Create a branch: `git checkout -b convention-fixes`
2. Start the loop: `/loop 15m Run the convention enforcement loop per Docs/QA/AUDIT_LOOPS.md`
3. Let it run — cycles through each area, fixes violations, verifies with `swift build`
4. Review the diff when done, merge if clean

### Rules checked

1. **No `print()` statements** — use `os.Logger` instead (print is invisible when launched from Dock)
2. **No direct file deletion** — always use `TrashStorage` + `CiderUndoManager`
3. **Notification names** — must use `cider.` prefix, centralized in Constants.swift
4. **No `as?` for CF types** — use `unsafeDowncast` after `CFGetTypeID` check
5. **No raw app names in AppleScript** — use `application id` (bundle ID)
6. **Shell.run() safety** — must use Process with argument arrays, no shell interpretation
7. **No `.glassEffect()`** — use `NSVisualEffectView` with `.underWindowBackground`
8. **No `makeKeyAndOrderFront`** — use `orderFront` to avoid stealing focus
9. **CiderConfig pattern** — new properties must use `decodeIfPresent` + fallback in `init(from:)`
10. **No local `@State` copies of ViewModel data** — render directly from ViewModel to avoid sync bugs

### 3-pass verification

Each area requires 3 independent clean scans before PASS. If any scan finds a new violation, fix it and reset to 1/3. This ensures thoroughness.

### Areas (scan order)
App/ -> Models/ -> Utilities/ -> Services/ -> Services/AI/ -> ViewModels/ -> Views/Bookmarks/ -> Views/Notes/ -> Views/Home/ -> Views/Shared/ -> Views/Search/ -> Views/Settings/ -> Views/AIAssistant/

### Progress tracking

Results are logged in `Docs/QA/AUDIT_REPORTS.md`.

### Known non-violations (skip these)
- `print()` inside `#Preview` blocks
- `print()` in test targets
- `os.Logger` definition lines themselves
- TrashStorage definition/implementation files
- Notification name definitions in Constants.swift (source of truth)

---

## Dead Code Detection Loop

Automated audit for finding unused functions, variables, types, and imports across the Cider codebase.

### When to run
- After major refactors
- Before releases (reduce binary size)
- Quarterly cleanup
- When the codebase feels bloated

### How to run

Tell Claude: **"Run the dead code detection loop"** — it will read this doc and know what to do.

### Setup

1. Create a branch: `git checkout -b dead-code-cleanup`
2. Start the loop: `/loop 15m Run the dead code detection loop per Docs/QA/AUDIT_LOOPS.md`
3. Let it run — cycles through each area, removes dead code, verifies with `swift build`
4. Review the diff when done, merge if clean

### What to check

1. **Unused private functions** — `private func` or `private static func` that nothing calls within the file
2. **Unused private variables** — `private var` or `private let` that nothing reads
3. **Unused parameters** — function parameters that are never referenced in the body (use `_` prefix)
4. **Unused imports** — `import` statements for frameworks not used in the file
5. **Commented-out code blocks** — large blocks of `//` commented code that should be deleted (git has history)
6. **Empty extension blocks** — `extension Foo { }` with no members
7. **Unused type definitions** — `struct`, `enum`, `class` that nothing references outside their file (if private) or across the codebase (if internal)
8. **Unused protocol conformances** — protocols declared but never used as a type constraint

### How to verify

For each candidate:
1. Search the ENTIRE codebase for references (not just the current file)
2. Check if it's used via protocol conformance, KVO, or Objective-C selectors (@objc)
3. Check if it's referenced in JS bridge code (TipTap message handlers)
4. Only remove if truly unreferenced

After removal: `swift build` must pass. If build fails, the code wasn't actually dead — revert immediately.

### 3-pass verification

Each area requires 3 independent clean scans before PASS. If any scan finds new dead code, remove it and reset to 1/3.

### Areas (scan order)
App/ -> Models/ -> Utilities/ -> Services/ -> Services/AI/ -> ViewModels/ -> Views/Bookmarks/ -> Views/Notes/ -> Views/Home/ -> Views/Shared/ -> Views/Search/ -> Views/Settings/ -> Views/AIAssistant/

### Progress tracking

Results are logged in `Docs/QA/AUDIT_REPORTS.md`.

### Known non-violations (skip these)
- `@objc` functions — may be called via selectors from AppKit/NotificationCenter
- Functions referenced in `#selector()` — runtime dispatch
- Protocol requirement stubs — required even if body is empty
- `CodingKeys` enums — used by Codable even if not explicitly referenced
- Public/internal API that may be used by future code — only remove `private` dead code with certainty
- JS message handler names in ViewModels — called from TipTap WebView
- `@IBAction` / `@IBOutlet` — Interface Builder references

---

## Documentation Health Loop

Automated audit for keeping docs accurate, consolidated, and in sync with the actual codebase. This loop should support both deep cleanup sessions and a lightweight recurring `Docs Health` dashboard/digest so stale project documentation does not silently pile up.

### When to run
- After major feature work or refactors
- Weekly as a report-only recurring health check
- Quarterly maintenance
- When docs feel stale or contradictory
- Before onboarding someone new to the project

### How to run

Tell Claude: **"Run the docs health loop"** — it will read this doc and know what to do.

For recurring unattended runs, default to report-only mode: inspect, rank, and summarize issues, but do not edit or delete docs without explicit user approval.

### Setup

1. Create a branch: `git checkout -b docs-cleanup`
2. Start the loop: `/loop 15m Run the docs health loop per Docs/QA/AUDIT_LOOPS.md`
3. Let it run — cycles through each docs folder, validates against code, fixes/consolidates
4. Review the diff when done, merge if clean

### What to check

#### 1. Accuracy — does the doc match the code?
- File paths mentioned in docs — do they still exist?
- Code patterns/examples — do they match current implementation?
- API/function names — have they been renamed or removed?
- Architecture descriptions — does the code still work this way?
- Feature descriptions — is the feature still implemented as described?

#### 2. Staleness — is the doc still relevant?
- Does the doc describe something that was removed or replaced?
- Are there TODO/FIXME items that were already completed?
- Are there "planned" features that were already shipped or abandoned?
- Are dates/timelines outdated?

#### 3. Duplication — is the same info in multiple places?
- Same pattern described in two docs — consolidate into one, reference from the other
- CLAUDE.md duplicating what's in a doc — remove from CLAUDE.md, keep the reference
- Overlapping docs that could be merged

#### 4. Completeness — is anything missing?
- New features with no doc coverage
- Patterns used across the codebase but undocumented
- Known gotchas discovered during development but not written down

#### 5. Organization — is it in the right folder?
- Doc content doesn't match its folder (e.g., architecture doc in Product/)
- Doc could be split into multiple focused docs
- Doc is too long and should be broken up

### How to fix

- **Stale info**: Update to match current code, or delete if no longer relevant
- **Duplicates**: Pick the better version, consolidate, add a reference from the other location
- **Wrong folder**: `git mv` to the correct folder
- **Missing docs**: Create a stub noting what should be documented (don't write full docs without user input on scope)
- **Dead references**: Fix paths, or remove references to deleted features

After changes: verify any code examples still compile conceptually (no need to `swift build` for pure doc changes).

### 3-pass verification

Each docs folder requires 3 independent clean scans before PASS. If any scan finds issues, fix them and reset to 1/3.

### Folders (scan order)
Architecture/ -> Design/ -> Conventions/ -> Features/ -> Product/ -> QA/ -> Shared/ -> CLAUDE.md

### Progress tracking

Results are logged in `Docs/QA/AUDIT_REPORTS.md`.

### Known non-issues (skip these)
- `_archive/` folder — intentionally outdated, don't audit
- Vision docs describing future plans — these are aspirational, not meant to match current code
- CLAUDE.md being brief — that's by design, it references docs instead of duplicating them

---

## Storage Integrity Loop

Automated audit for file-based storage layer correctness across the Cider vault system.

### When to run
- After any changes to VaultBookmarkService, NotesStorage, TrashStorage, VaultFolderService
- After adding new item types or storage paths
- Before releases
- Weekly health check

### How to run

Tell Claude: **"Run the storage integrity loop"** — it will read this doc and know what to do.

### Setup

1. Create a branch: `git checkout -b storage-fixes`
2. Start the loop: `/loop 15m Run the storage integrity loop per Docs/QA/AUDIT_LOOPS.md`
3. Let it run — cycles through each area, fixes violations, verifies with `swift build`
4. Review the diff when done, merge if clean

### Rules checked

#### 1. File / Memory consistency
- Every in-memory mutation (folderID, URL, title, labels) must be persisted to disk (index, sidecar, or file)
- After `persist()` / `saveIndex()`, the next load from disk must produce identical state
- No property updates without corresponding file writes (the `updateURL` bug pattern)

#### 2. Webloc file integrity
- `.webloc` plist must contain the same URL as the in-memory bookmark
- Moving a bookmark between folders must delete the source `.webloc` (no duplicates)
- Deleting a bookmark must remove the `.webloc` from disk
- Adoption scan must not re-adopt recently deleted URLs (TTL guard)

#### 3. Sidecar consistency
- Every `.webloc` file with metadata must have a matching sidecar entry (keyed by filename)
- Renaming/moving a file must update the sidecar key in both source and destination
- Empty sidecars (no entries) must be cleaned up (deleted from disk)
- `persistSidecar` must use `BookmarkFileService.updateSidecar` — no manual encode/write

#### 4. Trash round-trip integrity
- `trash()` -> `restore()` must produce identical item state (URL, title, folderID, assets)
- Trash must use UUID-based paths (not name-based) to avoid collisions
- Restoring a bookmark must put assets in the correct per-folder directory
- `remove()` must not double-delete assets that `TrashStorage` already moved
- `recentlyDeletedURLs` must have TTL expiry (not grow forever)

#### 5. Index/cache / disk agreement
- `VaultBookmarkService` index cache must match what `BookmarkFileService.readAll()` produces
- `NotesStorage` index (`_cider_notes_index.json`) must have entries for all `.md` files on disk
- Orphaned index entries (file deleted from disk) must be cleaned up
- Orphaned files (not in index) must be adopted or flagged

#### 6. Folder assignment integrity
- Bookmark/note `folderID` must match the vault folder where its file lives on disk
- Scan order must be consistent: vault folders first, then Inbox (both in load and adoption)
- Cross-folder duplicates (same URL in two folders) must be detected and cleaned up
- Moving an item to a folder must physically move the file AND update folderID + relativePath

#### 7. Migration safety
- `VaultMigrationService` must use `uniqueFilename` to avoid collision on same-title bookmarks
- Migration must be idempotent — running twice must not duplicate or corrupt data
- Legacy `BookmarksStorage` references must not exist outside migration code

#### 8. No stale references
- No consumer code should reference `BookmarksStorage.shared` (use `VaultBookmarkService.shared`)
- No hardcoded paths to `.cider/bookmarks/` — use `StoragePaths` helpers
- No assumptions about Inbox-only storage — items can live in any vault folder

### Files to scan

#### Primary (storage layer)
- `Services/VaultBookmarkService.swift`
- `Services/BookmarkFileService.swift`
- `Services/VaultFolderService.swift`
- `Services/VaultMigrationService.swift`
- `Services/VaultStructureMigration.swift`
- `Services/NotesStorage.swift`
- `Services/TrashStorage.swift`
- `Services/ContactStorage.swift`
- `Services/DateCardStorage.swift`
- `Services/TodoCardStorage.swift`
- `Utilities/StoragePaths.swift`

#### Consumers (correct delegation)
- `ViewModels/BookmarksViewModel.swift`
- `ViewModels/NotesViewModel.swift`
- `Views/CiderPanelView+Sidebar.swift`
- `Views/Shared/FolderSidebarView.swift`
- `Views/Shared/FolderDetailView.swift`
- `Views/Home/HomeDashboardView.swift`

### 3-pass verification

Each rule area requires 3 independent clean scans before PASS. If any scan finds a new violation, fix it and reset to 1/3.

### Known non-violations (skip these)
- `BookmarksStorage.shared` in `VaultMigrationService` — intentional legacy source for one-time migration
- `try?` on `FileManager.removeItem` in cleanup paths — harmless no-ops for missing files
- In-memory content cache misses (`contentCache`) — lazy loading, not data loss
- `relativePath` containing folder names with special characters — handled by URL encoding

### Live Vault Verification

In addition to static code analysis, each loop cycle should inspect the live vault at `~/CiderVault/` to catch drift between what the code thinks and what's actually on disk.

#### 9. Vault filesystem health checks

Run these checks against the live vault directory:

**Orphan detection:**
- Find all `.webloc` files on disk -> compare against `_cider_bookmarks.json` index -> flag any not in index
- Find all index entries -> check each has a corresponding `.webloc` file on disk -> flag missing files
- Find all `.md` files in `Inbox/Notes/` and vault folders -> compare against `_cider_notes_index.json` -> flag orphans

**Duplicate detection:**
- Find `.webloc` files with the same URL in multiple folders (read the plist, extract URL)
- Find `.webloc` files in Inbox that also exist in a vault folder (same filename or same URL)
- Flag any duplicates found — these cause the "Reassigned N bookmarks" spam

**Sidecar health:**
- For each folder with `.webloc` files, check `_cider_sidecar.json` exists and has entries for each file
- Check for stale sidecar entries (filename in sidecar but no matching `.webloc` on disk)
- Check for empty sidecars (`{"items":{}}`) that should be deleted

**Trash health:**
- Check `.cider/bookmarks/.trash/` for items older than 30 days (should be auto-purged)
- Check `Inbox/Notes/.trash/` for the same
- Check `.cider/folders/.trash/` for UUID-named subdirectories (not name-based — name-based = old bug)
- Verify trash manifest entries match actual files in trash directories

**Folder structure:**
- For each vault folder, verify it exists on disk at the path `VaultFolderService` expects
- Check for folders on disk not tracked by `.cider/folders/index.json`
- Check for `index.json` entries pointing to non-existent directories

#### 10. Cross-item consistency

**Bookmarks in folders:**
- For each bookmark with a `folderID`, verify the `.webloc` file is physically inside that folder's directory
- If the file is in a different directory, flag as folderID/path mismatch

**Notes in folders:**
- For each note with a `folderID`, verify the `.md` file is physically inside that folder's directory
- Check `relativePath` in the notes index matches the actual file location

**Item counts:**
- Compare bookmark count in index vs `.webloc` files on disk
- Compare note count in index vs `.md` files on disk (excluding index files)
- Large discrepancies indicate adoption or cleanup bugs

#### Reporting format for live checks

For each check, report:
```
CHECK: [description]
STATUS: PASS | FAIL | WARN
DETAILS: [specifics if not PASS]
```

Warnings are for non-critical drift (e.g., empty sidecar file). Failures are for data integrity issues (orphaned files, missing files, duplicates).

### Integration Tests (Exercise the Storage)

These tests actually create, move, and delete items to verify the full round-trip works. All operations use a dedicated test folder (`_StorageAuditTest`) that is created at the start and cleaned up at the end. **No real user data is touched.**

#### Setup & teardown
- Create vault folder `_StorageAuditTest` via `VaultFolderService` at start
- Delete it (and all contents) at the end
- If the folder already exists from a previous failed run, delete it first

#### Test 1: Bookmark create -> verify on disk
1. Create a `.webloc` file in `~/CiderVault/_StorageAuditTest/` with a test URL (e.g., `https://example.com/storage-audit-test`)
2. Wait for adoption scan (or trigger manually)
3. Verify: `.webloc` exists on disk, sidecar has an entry, index has the bookmark
4. **PASS** if all three agree. **FAIL** if any missing.

#### Test 2: Bookmark move -> verify file moved
1. Using the bookmark from Test 1, move it to `Inbox/Bookmarks/` (set folderID to nil)
2. Verify: `.webloc` is now in `Inbox/Bookmarks/`, NOT in `_StorageAuditTest/`
3. Verify: sidecar entry removed from source, added to destination
4. Verify: bookmark's `relativePath` and `folderID` updated in index
5. **PASS** if old location clean and new location correct. **FAIL** if duplicate or stale.

#### Test 3: Bookmark move back -> verify no duplicates
1. Move the bookmark back to `_StorageAuditTest/`
2. Verify: `.webloc` only exists in `_StorageAuditTest/`, not in Inbox
3. Verify: no "Reassigned" log spam on next adoption scan
4. **PASS** if single copy in correct location. **FAIL** if duplicates.

#### Test 4: Bookmark delete -> verify trash
1. Delete the bookmark via `VaultBookmarkService.remove()`
2. Verify: `.webloc` removed from `_StorageAuditTest/`
3. Verify: trash manifest has the bookmark entry
4. Verify: bookmark no longer in index or `bookmarks` array
5. Verify: adoption scan does NOT re-adopt the URL (TTL guard)
6. **PASS** if cleanly trashed. **FAIL** if orphaned or zombie re-adopted.

#### Test 5: Bookmark restore -> verify round-trip
1. Restore the trashed bookmark
2. Verify: `.webloc` reappears on disk at correct location
3. Verify: bookmark back in index with correct folderID, title, URL
4. Verify: sidecar entry restored
5. **PASS** if state matches pre-delete. **FAIL** if data lost.

#### Test 6: Note create -> verify on disk
1. Create a note via `NotesStorage.shared.createNew(initialContent: "Storage audit test")`
2. Verify: `.md` file exists in `Inbox/Notes/`
3. Verify: notes index has entry with correct filename
4. **PASS** if file and index agree. **FAIL** if missing.

#### Test 7: Note move to folder -> verify file moved
1. Move the note to `_StorageAuditTest/` via `NotesStorage.shared.assignNote()`
2. Verify: `.md` file is in `~/CiderVault/_StorageAuditTest/`, NOT in `Inbox/Notes/`
3. Verify: note's `folderID` and `relativePath` updated in index
4. **PASS** if single copy in correct location. **FAIL** if duplicate or stale.

#### Test 8: Note delete -> verify trash
1. Delete the note
2. Verify: `.md` removed from `_StorageAuditTest/`
3. Verify: trash manifest has the note entry
4. **PASS** if cleanly trashed. **FAIL** if orphaned.

#### Test 9: Note restore -> verify round-trip
1. Restore the trashed note
2. Verify: `.md` reappears at correct location with correct content
3. Verify: note back in index with correct folderID
4. **PASS** if content and metadata match pre-delete. **FAIL** if data lost.

#### Test 10: URL update -> verify webloc rewrite
1. Create a new test bookmark in `_StorageAuditTest/`
2. Update its URL via `VaultBookmarkService.shared.updateURL()`
3. Read the `.webloc` plist directly from disk
4. Verify: plist contains the NEW URL, not the old one
5. **PASS** if plist matches in-memory URL. **FAIL** if stale.

#### Test 11: Duplicate URL detection
1. Create a `.webloc` file manually in `Inbox/Bookmarks/` with the same URL as the Test 10 bookmark
2. Trigger adoption scan
3. Verify: the duplicate is detected and cleaned up (Inbox copy deleted)
4. Verify: bookmark remains in `_StorageAuditTest/` with correct folderID
5. **PASS** if single copy survives. **FAIL** if both kept or wrong one deleted.

#### Cleanup
- Delete all test bookmarks and notes created during the run
- Delete the `_StorageAuditTest` folder via `VaultFolderService`
- Verify: no leftover files, index entries, or sidecar entries from the test

#### Reporting format
```
TEST 1: Bookmark create -> verify on disk ........... PASS
TEST 2: Bookmark move -> verify file moved .......... PASS
TEST 3: Bookmark move back -> verify no duplicates .. PASS
TEST 4: Bookmark delete -> verify trash ............. PASS
TEST 5: Bookmark restore -> verify round-trip ....... PASS
TEST 6: Note create -> verify on disk ............... PASS
TEST 7: Note move to folder -> verify file moved .... PASS
TEST 8: Note delete -> verify trash ................. PASS
TEST 9: Note restore -> verify round-trip ........... PASS
TEST 10: URL update -> verify webloc rewrite ........ PASS
TEST 11: Duplicate URL detection ................... PASS
CLEANUP: Test folder removed ....................... PASS
```

Any FAIL stops the run and reports the mismatch details. The test folder is always cleaned up, even on failure.

### Progress tracking

Results are logged in `Docs/QA/AUDIT_REPORTS.md`.

---

## Threading Safety Loop

Automated audit for threading and concurrency safety across the Cider codebase.

### When to run
- After adding new async/await code
- After modifying ViewModels or Services
- Before releases
- When investigating crashes or race conditions

### How to run

Tell Claude: **"Run the threading safety loop"** — it will read this doc and know what to do.

### Setup

1. Create a branch: `git checkout -b threading-fixes`
2. Start the loop: `/loop 15m Run the threading safety loop per Docs/QA/AUDIT_LOOPS.md`
3. Let it run — cycles through each area, fixes violations, verifies with `swift build`
4. Review the diff when done, merge if clean

### Rules checked

1. **@MainActor on UI-touching code** — any code that updates `@Published` properties observed by SwiftUI must be `@MainActor`
2. **No bare DispatchQueue.main.async without guard** — prefer `@MainActor` or `MainActor.run`; if using DispatchQueue, guard against stale state (e.g., check `panel.isVisible` before updating UI)
3. **No force unwraps in async callbacks** — objects may be deallocated; use `[weak self]` and guard
4. **OSAllocatedUnfairLock for shared mutable state** — not `DispatchQueue` or `NSLock` for simple flag protection
5. **No synchronous file I/O on main thread** — `Data(contentsOf:)`, `FileManager` operations should be on background
6. **Task cancellation handling** — long-running Tasks should check `Task.isCancelled`
7. **No data races in KVO/NotificationCenter callbacks** — async callbacks may fire after object is invalid; guard with `[weak self]` and state checks
8. **Sendable compliance** — types shared across concurrency boundaries should conform to `Sendable` or use `@unchecked Sendable` with documented justification

### 3-pass verification

Each area requires 3 independent clean scans before PASS. If any scan finds a new violation, fix it and reset to 1/3.

### Areas (scan order)
App/ -> Services/ -> Services/AI/ -> ViewModels/ -> Views/Shared/ -> Views/Bookmarks/ -> Views/Notes/ -> Views/Home/ -> Views/Search/ -> Views/Settings/ -> Views/AIAssistant/

Note: Models/ and Utilities/ are excluded — they are pure data types and static tokens with no concurrency concerns.

### Progress tracking

Results are logged in `Docs/QA/AUDIT_REPORTS.md`.

### Known non-violations (skip these)
- `DispatchQueue.main.async` in AppKit lifecycle code (applicationDidFinishLaunching, etc.) — AppKit convention
- `@unchecked Sendable` with a comment explaining why — intentional
- Synchronous reads of small config files at startup — acceptable tradeoff
- `nonisolated(unsafe)` on logger instances — Swift concurrency convention
