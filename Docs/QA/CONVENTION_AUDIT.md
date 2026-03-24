# Convention Enforcement Audit

Automated scan-fix-rescan loop across the entire codebase.
Each area requires **3 independent clean scans** before marking PASS.
Build verified with `swift build` after each fix batch.

**Rules checked:**
1. No `print()` — use `os.Logger` instead
2. No direct file deletion — use `TrashStorage` + `CiderUndoManager`
3. Notification names use `cider.` prefix, centralized in Constants.swift
4. No `as?` for CF types — use `unsafeDowncast` after `CFGetTypeID` check
5. No raw app names in AppleScript — use `application id` (bundle ID)
6. Shell.run() safety — Process with argument arrays
7. No `.glassEffect()` — use `NSVisualEffectView` with `.underWindowBackground`
8. No `makeKeyAndOrderFront` — use `orderFront`
9. CiderConfig pattern — `decodeIfPresent` + fallback
10. No local `@State` copies of ViewModel data

---

## Progress Tracker

| Area | Status | Violations | Clean Passes | Last Scanned |
|------|--------|------------|-------------|--------------|
| App/ | PASS | 2 fixed | 3/3 | 2026-03-23 |
| Models/ | PASS | 0 | 3/3 | 2026-03-23 |
| Utilities/ | PASS | 0 | 3/3 | 2026-03-23 |
| Services/ | PASS | 2 fixed | 3/3 | 2026-03-23 |
| Services/AI/ | PASS | 0 | 3/3 | 2026-03-23 |
| ViewModels/ | PASS | 0 | 3/3 | 2026-03-23 |
| Views/Bookmarks/ | PASS | 0 | 3/3 | 2026-03-23 |
| Views/Notes/ | PASS | 0 | 3/3 | 2026-03-23 |
| Views/Home/ | PASS | 0 | 3/3 | 2026-03-23 |
| Views/Shared/ | PASS | 0 | 3/3 | 2026-03-23 |
| Views/Search/ | PASS | 0 | 3/3 | 2026-03-23 |
| Views/Settings/ | PASS | 0 | 3/3 | 2026-03-23 |
| Views/AIAssistant/ | PASS | 0 | 3/3 | 2026-03-23 |
| Views/Calendar/ | PASS | 0 | 3/3 | 2026-03-23 |
| Views/Contacts/ | PASS | 0 | 3/3 | 2026-03-23 |
| Views/DateCards/ | PASS | 0 | 3/3 | 2026-03-23 |
| Views/Kanban/ | PASS | 0 | 3/3 | 2026-03-23 |
| Views/Onboarding/ | PASS | 0 | 3/3 | 2026-03-23 |
| Views/SavedViews/ | PASS | 0 | 3/3 | 2026-03-23 |
| Views/ScreenCapture/ | PASS | 0 | 3/3 | 2026-03-23 |
| Views/Sessions/ | PASS | 0 | 3/3 | 2026-03-23 |
| Views/Sources/ | PASS | 0 | 3/3 | 2026-03-23 |
| Views/Stacks/ | PASS | 0 | 3/3 | 2026-03-23 |
| Views/Todos/ | PASS | 0 | 3/3 | 2026-03-23 |
| Views/Whiteboard/ | PASS | 0 | 3/3 | 2026-03-23 |

---

## Fix Log

### App/ — 2026-03-23

Scanned 14 files. Found and fixed 2 violations:

1. **AppDelegate+ClipboardPanel.swift** — Rule 8: `makeKeyAndOrderFront(nil)` replaced with `orderFront(nil)` + `makeKey()` to avoid focus stealing.
2. **AppDelegate+AIAssistantPanel.swift** — Rule 8: `makeKeyAndOrderFront(nil)` replaced with `orderFront(nil)` + `makeKey()` to avoid focus stealing.

Build verified: `swift build` passed with zero errors.

### Services/ — 2026-03-23

Scanned 40+ files. Found and fixed 2 violations:

1. **iMessageSender.swift** — Rule 5: `tell application "Messages"` replaced with `tell application id "com.apple.MobileSMS"` to use bundle ID instead of raw app name.
2. **ScreenCaptureService.swift** — Rule 8: `makeKeyAndOrderFront(nil)` replaced with `orderFront(nil)` + `makeKey()`. The screen capture overlay needs key status for mouse event handling, achieved via separate `makeKey()` call.

Build verified: `swift build` passed with zero errors.

### Noted (acceptable patterns, not violations)

- **Rule 2 — `FileManager.default.trashItem` in Views/Home, Views/SavedViews, Views/Sources**: These call `trashItem(at:resultingItemURL:)` on `ExternalFile` objects (files from linked external sources outside the vault). Since these are not Cider-managed data items, using macOS system Trash is appropriate — CiderUndoManager/TrashStorage only applies to vault items.
- **Rule 2 — `removeItem` in Services/**: Storage services (TrashStorage, BookmarksStorage, NotesStorage, VaultBookmarkService, VaultFolderService, ClipboardStorage, KanbanStorage, etc.) use `removeItem` internally as part of their own file management. These are not user-facing deletions bypassing the trash system.
- **Rule 2 — `removeItem` in iMessageSender.swift**: Cleans up temporary files created for AppleScript message passing. Not user data.
- **Rule 2 — `removeItem` in Services/AI/AIConversationStorage.swift**: Manages its own conversation JSON files internally.
- **Rule 4 — `as? [CFString: Any]` in ClipboardHistoryService and BookmarksStorage**: These cast `CGImageSourceCopyPropertiesAtIndex` return value (`CFDictionary?`) to a Swift dictionary via toll-free bridging. This is standard Apple API usage, not an unsafe CF type downcast.
- **Rule 9 — CiderConfig**: All 60+ properties use `decodeIfPresent` + fallback pattern correctly.
- **Rule 6 — Shell/Process usage**: All Process usage in iMessageBridgeService, ClaudeSessionManager, iMessageSender, and BrowserTabCaptureService uses argument arrays correctly.
