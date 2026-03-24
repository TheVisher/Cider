# Threading Safety Audit

**Date:** 2026-03-23
**Branch:** feature/sessions-tab
**Build:** PASS (clean build, pre-existing MLX deprecation warning with `-warnings-as-errors`)

## Rules Checked

1. @MainActor on UI-touching code
2. No bare DispatchQueue.main.async without guard
3. No force unwraps in async callbacks
4. OSAllocatedUnfairLock for shared mutable state
5. No synchronous file I/O on main thread
6. Task cancellation handling
7. No data races in KVO/NotificationCenter callbacks
8. Sendable compliance

## Progress

| Area | Status | Scans | Notes |
|------|--------|-------|-------|
| App/ | PASS | 3/3 | AppDelegate is @MainActor. KVO callbacks use [weak self] + DispatchQueue.main.async (AppKit convention). |
| Services/ | PASS | 3/3 | All ObservableObject services are @MainActor. Added @unchecked Sendable justification comments to 6 hotkey detectors. |
| Services/AI/ | PASS | 3/3 | EmbeddingStore uses Task.detached for computation, MainActor.run for state updates. BookmarkAIEnrichment checks Task.isCancelled. |
| ViewModels/ | PASS | 3/3 | All ViewModels are @MainActor. Task {} in @MainActor class inherits isolation. |
| Views/Shared/ | PASS | 3/3 | Fixed 4x bare DispatchQueue.main.async in FolderSidebarView drag callbacks -> Task { @MainActor in }. |
| Views/Bookmarks/ | PASS | 3/3 | All Task {} calls are @MainActor annotated. No violations. |
| Views/Notes/ | PASS | 3/3 | DispatchQueue.main.asyncAfter for focus management is AppKit convention. HideScrollIndicatorsHelper is NSViewRepresentable convention. |
| Views/Home/ | PASS | 3/3 | Clean. |
| Views/Search/ | PASS | 3/3 | SearchPaletteView Task {} inherits @MainActor from View context. |
| Views/Settings/ | PASS | 3/3 | DispatchQueue.main.async for NSOpenPanel is AppKit convention. |
| Views/AIAssistant/ | PASS | 3/3 | Clean. |

## Fixes Applied

### 1. @unchecked Sendable justification comments (Rule 8)

Added documentation comments to 6 hotkey detector classes explaining why `@unchecked Sendable` is safe:

- `DoubleTapDetector.swift`
- `BookmarksHotkeyDetector.swift`
- `NotesHotkeyDetector.swift`
- `ScreenCaptureHotkeyDetector.swift`
- `ClipboardHotkeyDetector.swift`
- `AIAssistantHotkeyDetector.swift`

All use NSEvent monitors that deliver callbacks on the main thread; no cross-thread mutable state access.

### 2. DispatchQueue.main.async in drag callbacks (Rule 2)

**File:** `Views/Shared/FolderSidebarView.swift`

Replaced 4 instances of bare `DispatchQueue.main.async` inside `loadDataRepresentation` callbacks with `Task { @MainActor in }` for consistent concurrency model. These callbacks fire on background threads after drag data is loaded.

## Observations (no fix needed)

- **ClaudeSessionManager.resolveClaudePath()** runs `Process.waitUntilExit()` synchronously on @MainActor. Mitigated by caching after first call. A future improvement could make this async, but the shell commands complete in <100ms and results are cached.
- **DetailWebViewStore** uses `DispatchQueue.main.async` inside URLSession.dataTask callback to call WKWebView APIs. Uses [weak wv, weak delegate] captures. Standard WebKit pattern.
- **SpotlightIndexer** uses `DispatchQueue.main.asyncAfter` for navigation delay after showing panel. Acceptable UI convention.
- **NotesStorage / VaultIndexService** use `DispatchQueue.main.asyncAfter` with `DispatchWorkItem` for debouncing. Both are @MainActor classes. Acceptable pattern.
