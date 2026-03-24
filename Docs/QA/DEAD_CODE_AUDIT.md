# Dead Code Detection Audit

Automated scan-fix-rescan loop for unused code across the codebase.
Each area requires **3 independent clean scans** before marking PASS.
Build verified with `swift build` after each removal.

**Checks:**
1. Unused private functions/variables
2. Unused imports
3. Commented-out code blocks
4. Empty extension blocks
5. Unused type definitions
6. Unused parameters

---

## Progress Tracker

| Area | Status | Removals | Clean Passes | Last Scanned |
|------|--------|----------|-------------|--------------|
| App/ | PASS | 0 | 3/3 | 2026-03-23 |
| Models/ | PASS | 1 removed | 3/3 | 2026-03-23 |
| Utilities/ | PASS | 0 | 3/3 | 2026-03-23 |
| Services/ | PASS | 5 removed | 3/3 | 2026-03-23 |
| Services/AI/ | PASS | 1 removed | 3/3 | 2026-03-23 |
| ViewModels/ | PASS | 1 removed | 3/3 | 2026-03-23 |
| Views/Bookmarks/ | PASS | 0 | 3/3 | 2026-03-23 |
| Views/Notes/ | PASS | 0 | 3/3 | 2026-03-23 |
| Views/Home/ | PASS | 2 removed | 3/3 | 2026-03-23 |
| Views/Shared/ | PASS | 2 removed | 3/3 | 2026-03-23 |
| Views/Search/ | PASS | 0 | 3/3 | 2026-03-23 |
| Views/Settings/ | PASS | 3 removed | 3/3 | 2026-03-23 |
| Views/AIAssistant/ | PASS | 0 | 3/3 | 2026-03-23 |
| Views/SavedViews/ | PASS | 4 removed | 3/3 | 2026-03-23 |

---

## Fix Log

### 2026-03-23 — Full Codebase Scan (Claude Opus 4.6)

**Pass 1 — 19 dead code items found and removed:**

#### Unused Imports (10)

1. `Models/VaultFile.swift` — removed `import UniformTypeIdentifiers` (UTType never used; file type inference is string-based)
2. `Models/ClipboardItem.swift` — removed `import AppKit` (only uses CGSize, provided by Foundation/CoreGraphics)
3. `Views/CiderPanelView.swift` — removed `import WebKit` (no WK types used)
4. `Views/Shared/DetailSlideOutView.swift` — removed `import WebKit` (no WK types used)
5. `Views/Settings/SettingsView.swift` — removed `import UniformTypeIdentifiers`
6. `Views/Settings/StorageSettingsView.swift` — removed `import AppKit` (no NS/CG types used)
7. `Views/Settings/GeneralSettingsView.swift` — removed `import AppKit` (no NS/CG types used)
8. `Views/Home/HomeDashboardView.swift` — removed `import UniformTypeIdentifiers`
9. `Views/Contacts/ContactEditorSheet.swift` — removed `import UniformTypeIdentifiers`
10. `Views/Shared/FolderDetailView.swift` — removed `import UniformTypeIdentifiers`

#### Unused Private Functions (7)

11. `ViewModels/NotesViewModel.swift` — removed `syncExternalContentFromEditor(fileURL:)` (23 lines) — identical to `syncContentFromEditor(noteID:)` but for external files; never called
12. `Views/Home/HomeDashboardView.swift` — removed `libraryListRow(_:)` (175 lines) — large dead switch statement for list row rendering; list mode uses `LibraryTableRows` instead
13. `Views/Shared/FolderDetailView.swift` — removed `libraryListRow(_:)` (160 lines) — same pattern as HomeDashboardView; list mode uses `LibraryTableRows`
14. `Views/SavedViews/SavedViewTabContent.swift` — removed `itemRow(_:)` (131 lines) — dead list row builder, plus cascading dead helpers `genericRow(_:)` (32 lines), `icon(for:)` (19 lines), `subtitle(for:)` (21 lines)
15. `Services/BookmarksStorage.swift` — removed `removeBookmarkImageAssetsIfPresent(for:)` (9 lines) — helper that was never called
16. `Services/ExternalSourceScanner.swift` — removed `stopWatcher()` (5 lines) — deinit handles cleanup directly
17. `Services/iMessageBridgeService.swift` — removed `sendReply(_:to:)` (3 lines) and `buildShellEnvironment()` (14 lines) — unused helper wrappers

#### Unused Private Variables (1)

18. `Services/ClipboardHistoryService.swift` — removed unused `logger` (Logger instance) + cascading unused `import os`

#### Unused Helper Functions (cascading from itemRow removal)

19. `Views/SavedViews/SavedViewTabContent.swift` — removed `genericRow(_:)`, `icon(for:)`, `subtitle(for:)` (only called from removed `itemRow`)

**Pass 2 — Clean.** No new dead code found.
**Pass 3 — Clean.** Confirmed.

**Build verified:** `swift build -Xswiftc -warnings-as-errors` passes clean.

**Total lines removed:** ~600+ lines of dead code.

### 2026-03-20 — Views/AIAssistant/ + Services/AI/ (Claude Opus 4.6)

**Pass 1 — 3 dead code items found and removed:**

1. `AIAssistantBubbleView.swift` — `@State private var isHovered` + `.onHover` handler: variable was written to by hover tracking but never read in any conditional. Removed both.

2. `MLXProvider.swift` — `private var conversationHistory`: maintained (appended, trimmed) but never read for prompt building. `buildConversationPrompt()` uses the `messages` parameter from the ViewModel instead. Likely a leftover from an earlier iteration. Removed property, removed append/trim logic in `streamResponse`, updated `resetSession()`.

3. `ColorExtractionService.swift` — Tested removing `import AppKit` (only CG types used visibly), but `CGImageSourceCreateWithURL` resolves through AppKit on macOS. Import is required — reverted.

**Pass 2 — Clean.** No new dead code found.
**Pass 3 — Clean.** Confirmed.

**No old CLI wrapper remnants found** — searched for CLIProvider, TerminalProvider, ShellProvider, OllamaProvider, LlamaProvider, Process(), and general CLI/terminal/shell references. All clean.
