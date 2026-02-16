# Cider Deep-Dive Code Review

Date: 2026-02-16
Reviewer: Codex
Scope: `Sources/Cider`, `tiptap-editor`, `Tests/CiderTests`, and relevant docs in `Docs/`

## Summary

- Total findings: 13
- Critical: 1
- High: 3
- Medium: 6
- Medium-Low: 2
- Low: 1

## Validation Notes

- `swift test` currently fails to compile due to missing symbols in `TileNodeTests` (`TileNode`, `SplitOrientation`).
- Review was static-analysis based plus targeted command-line validation for references and test status.
- No production code was changed as part of this review.

## Findings (Severity Ordered)

### CR-01 (Critical) WebView Bridge Exposure via HTML + Navigation Policy

- Category: Security
- Evidence:
`Sources/Cider/Views/Notes/TipTapEditorView.swift:12`
`Sources/Cider/Views/Notes/TipTapEditorView.swift:123`
`Sources/Cider/Views/Notes/TipTapEditorView.swift:133`
`tiptap-editor/src/editor.js:1912`
`tiptap-editor/src/editor.js:2031`
- Issue:
The notes editor enables HTML markdown parsing (`html: true`) and registers multiple `window.webkit.messageHandlers`. The navigation policy only blocks `.linkActivated`; non-link navigations are allowed, which increases risk that untrusted rendered content can navigate and still interact with native bridge handlers.
- Risk:
Potential script/native bridge abuse and elevated attack surface in editor context.
- Suggested remediation:
Restrict WebView navigation to trusted origins/schemes, remove or harden broad message-handler exposure, and disable/sanitize unsafe HTML in markdown ingestion.

### HI-01 (High) WKWebView Read Access Root Is `/`

- Category: Security
- Evidence:
`Sources/Cider/Views/Notes/TipTapEditorView.swift:35`
- Issue:
The editor WebView loads with `allowingReadAccessTo` set to filesystem root (`/`).
- Risk:
Overly broad local file access scope if WebView content is compromised.
- Suggested remediation:
Constrain read access to the smallest required directory scope (for example notes/attachments roots only).

### HI-02 (High) Test Suite Cannot Compile

- Category: Quality / Regression Safety
- Evidence:
`Tests/CiderTests/TileNodeTests.swift:34`
`Tests/CiderTests/TileNodeTests.swift:43`
- Issue:
`swift test` fails due to missing `TileNode` / `SplitOrientation` in the tested target.
- Risk:
No functioning CI-style regression guard for this package state.
- Suggested remediation:
Restore the missing types or remove/replace stale tests so the test target compiles and runs.

### HI-03 (High) Main-Thread Disk Reads in Search Paths

- Category: Performance
- Evidence:
`Sources/Cider/Views/Search/SearchTabContent.swift:12`
`Sources/Cider/Services/SearchService.swift:74`
`Sources/Cider/ViewModels/NotesViewModel.swift:64`
`Sources/Cider/ViewModels/NotesViewModel.swift:69`
- Issue:
Search recomputation repeatedly performs per-note content loads from disk on main actor paths.
- Risk:
Typing/scroll stutter and poor responsiveness with larger note sets.
- Suggested remediation:
Introduce cached note content/indexes and move expensive search prep off the main actor.

### ME-01 (Medium) Project Storage Path Does Not Track Directory Changes

- Category: Correctness
- Evidence:
`Sources/Cider/Services/ProjectStorage.swift:21`
`Sources/Cider/Services/ProjectStorage.swift:23`
`Sources/Cider/App/AppDelegate.swift:153`
- Issue:
`ProjectStorage` captures its file path at init and is not refreshed when bookmarks directory changes.
- Risk:
Projects persist to stale location, causing confusing state split and discoverability problems.
- Suggested remediation:
Add config-change handling to rebind `ProjectStorage` path similarly to notes/bookmarks storage updates.

### ME-02 (Medium) Main-Thread Blocking I/O in Storage Initialization

- Category: Performance
- Evidence:
`Sources/Cider/Services/NotesStorage.swift:79`
`Sources/Cider/Services/BookmarksStorage.swift:400`
`Sources/Cider/Services/BookmarksStorage.swift:462`
- Issue:
Large file reads/parsing happen synchronously in `@MainActor` storage flows.
- Risk:
Launch and directory-switch UI hangs on larger datasets.
- Suggested remediation:
Move read/decode work to background tasks and publish finalized state back on main actor.

### ME-03 (Medium) Attachment Cleanup Does Full Note Scans on Main Actor

- Category: Performance
- Evidence:
`Sources/Cider/Services/NotesStorage.swift:449`
`Sources/Cider/Services/NotesStorage.swift:454`
`Sources/Cider/Services/NotesStorage.swift:499`
`Sources/Cider/Services/NotesStorage.swift:510`
- Issue:
Attachment orphan cleanup performs O(n) content scans across notes after saves.
- Risk:
Post-save UI slowdowns as note count grows.
- Suggested remediation:
Perform cleanup/indexing off main actor and/or incrementally track attachment references.

### ME-04 (Medium) Floating Surface Rule Deviation (`.popover`)

- Category: Design / Architecture Compliance
- Evidence:
`AGENTS.md:6`
`AGENTS.md:34`
`Sources/Cider/Views/CiderPanelView.swift:145`
`Sources/Cider/Views/CiderPanelView.swift:167`
- Issue:
View options are implemented with SwiftUI popovers, while project rules require floating surfaces to be `NSPanel` with non-activating behavior.
- Risk:
Behavior/style inconsistency with the documented panel model.
- Suggested remediation:
Replace these popovers with panel-backed dropdown surfaces consistent with floating panel conventions.

### ME-05 (Medium) Non-Spring Panel Animation Curves

- Category: Motion / Design Compliance
- Evidence:
`AGENTS.md:9`
`Sources/Cider/App/CiderPanel.swift:242`
`Sources/Cider/App/NotesPanel.swift:174`
`Sources/Cider/App/BookmarksPanel.swift:158`
- Issue:
Panel frame transitions use `.easeInEaseOut` timing functions rather than spring-based motion.
- Risk:
Inconsistent interaction feel and divergence from motion guidelines.
- Suggested remediation:
Use spring animation presets and reduce-motion fallback behavior in panel transitions.

### ME-06 (Medium) FeatureSettings Requirement Not Fully Implemented

- Category: Architecture / Settings Governance
- Evidence:
`AGENTS.md:40`
`Sources/Cider/Models/FeatureSettings.swift:10`
`Sources/Cider/Models/FeatureSettings.swift:15`
- Issue:
Feature settings metadata exists only in partial form; no broad, enforced per-feature settings registry/pattern is wired.
- Risk:
Settings become inconsistent and harder to audit as features expand.
- Suggested remediation:
Implement and adopt a complete feature-settings contract across feature modules.

### ML-01 (Medium-Low) Acrylic Shadow Style Deviation

- Category: Design Compliance
- Evidence:
`Docs/ACRYLIC_STYLE.md:232`
`Sources/Cider/Views/Search/SearchPaletteView.swift:88`
- Issue:
Search palette container uses `.shadow(...)` directly, while acrylic guidance prefers shape-based shadow treatment.
- Risk:
Visual mismatch and potential clipping behavior differences.
- Suggested remediation:
Adopt the shared acrylic shadow pattern used by panel background components.

### ML-02 (Medium-Low) Persisted Settings Not Fully Exposed in Settings UI

- Category: UX / Settings Consistency
- Evidence:
`Sources/Cider/Models/CiderConfig.swift:119`
`Sources/Cider/Models/CiderConfig.swift:120`
`Sources/Cider/Models/CiderConfig.swift:121`
`Sources/Cider/ViewModels/NotesViewModel.swift:793`
`Sources/Cider/ViewModels/NotesViewModel.swift:803`
`Sources/Cider/Views/Settings/SettingsView.swift:111`
`Sources/Cider/ViewModels/SettingsViewModel.swift:26`
- Issue:
Some persisted display/card-size settings are not clearly surfaced in Settings UI.
- Risk:
Configuration is partially discoverable and inconsistent for users.
- Suggested remediation:
Expose these options in Settings and ensure parity between persisted fields and settings controls.

### LO-01 (Low) Doc Drift: Storage Model Description vs Implementation

- Category: Documentation / Architecture
- Evidence:
`AGENTS.md:37`
`Package.swift:10`
`Sources/Cider/Services/NotesStorage.swift:22`
`Sources/Cider/Services/BookmarksStorage.swift:24`
`Sources/Cider/Services/ProjectStorage.swift:16`
- Issue:
Docs mention SQLite metadata storage, while current implementation is file/JSON-based and package has no DB dependency.
- Risk:
Onboarding and planning confusion.
- Suggested remediation:
Update docs to match current architecture or implement the documented storage stack.

## Suggested Triage Order

1. CR-01, HI-01 (security boundary hardening)
2. HI-02 (restore working tests)
3. HI-03, ME-02, ME-03 (performance responsiveness)
4. ME-01 (storage correctness after config changes)
5. ME-04, ME-05, ML-01 (design-system compliance)
6. ME-06, ML-02, LO-01 (settings/doc consistency)
