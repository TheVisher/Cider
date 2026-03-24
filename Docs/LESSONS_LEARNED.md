# Lessons Learned

Hard-won debugging knowledge from past issues. **Read the relevant section before investigating bugs in that area.** Each entry documents a real bug, the root cause, and the fix — so we never spend hours rediscovering the same thing.

---

## Table of Contents

- [Drag and Drop](#drag-and-drop)
- [Storage / Vault Files](#storage--vault-files)
- [Animations & SwiftUI](#animations--swiftui)
- [NSPanel / Window Management](#nspanel--window-management)
- [Keyboard Events](#keyboard-events)
- [Sync](#sync)
- [Performance & Caching](#performance--caching)
- [TipTap Editor](#tiptap-editor)
- [AI / LLM](#ai--llm)

---

## Drag and Drop

### Note cards can't be dragged to folders
**Symptom:** Bookmark cards drag fine, but note cards don't initiate drag at all.
**Root cause:** `registerFileRepresentation` on the NSItemProvider breaks SwiftUI's `.onDrop` — providers arrive with empty `registeredTypeIdentifiers`, so the sidebar drop handler silently fails. `registerDataRepresentation` for extra types (like markdown) can cause the same issue.
**Fix:** Only register the internal type ID (`com.cider.note-id`) and the text representation (NSString). Do NOT register any additional types — no `registerFileRepresentation`, no markdown UTI, no `public.file-url`. Finder drag-out is sacrificed for internal drag-to-folder.
**Commit:** `175b607` (2026-03-23)

### `.onDrop` doesn't match custom UTIs via conformance
**Symptom:** `.onDrop(of:)` accepts providers but `registeredTypeIdentifiers` appears empty.
**Root cause:** Custom UTIs like `com.cider.bookmark-id` aren't in the system conformance tree. `.onDrop` matches via the text fallback type, but adding file representations can break even that.
**Fix:** Use `registeredTypeIdentifiers.contains()` (string match), not `hasItemConformingToTypeIdentifier()` (conformance match) when checking for custom types in drop handlers.

---

## Storage / Vault Files

### "Reassigned X bookmarks" spam every 5 seconds
**Symptom:** Console floods with "Reassigned N bookmarks to match filesystem folders" on every adoption scan cycle.
**Root cause:** Duplicate `.webloc` files — same bookmark URL exists in both Inbox/Bookmarks AND a vault folder (or in two different vault folders). The adoption scan ping-pongs the `folderID` between them each cycle.
**Fix:** (1) Scan vault folders FIRST (authoritative), then Inbox. (2) Track seen URLs — if a URL was already claimed by a folder, delete the duplicate copy instead of reassigning. (3) Match scan order between `scanAllVaultFolders()` and `adoptOrphanedVaultFiles()`.
**Commit:** `175b607` (2026-03-23)

### Zombie bookmark re-adoption after deletion
**Symptom:** Deleting a bookmark causes it to reappear within seconds.
**Root cause:** The `.webloc` file still exists on disk (or a duplicate copy does). The adoption scan finds it and re-creates the bookmark.
**Fix:** (1) `recentlyDeletedURLs` set with TTL blocks re-adoption for 30 seconds after deletion. (2) `deleteWeblocFile()` removes the physical file immediately on delete.
**Commit:** `268e037` (2026-03-23)

### `updateURL` doesn't survive app restart
**Symptom:** Editing a bookmark's URL works in the session but reverts after relaunch.
**Root cause:** `updateURL()` updated the in-memory bookmark and sidecar, but NOT the `.webloc` plist file on disk. On next launch, the old URL was read back from the plist.
**Fix:** After updating `bookmarks[index].urlString`, rewrite the `.webloc` plist via `PropertyListSerialization`.
**Commit:** `ee9538d` (2026-03-23)

### Trash restore puts assets in wrong directory
**Symptom:** Restoring a trashed bookmark from a vault folder loses its thumbnail/image.
**Root cause:** `TrashStorage.restoreBookmark` hardcoded the legacy `StoragePaths.directoryURL(for: .bookmarks)` path instead of resolving the bookmark's actual folder via `VaultFolderService`.
**Fix:** Resolve the target directory from the bookmark's `folderID` at restore time.
**Commit:** `ee9538d` (2026-03-23)

### Double-delete clears sidecar data needed by trash
**Symptom:** Sidecar metadata lost after trashing a bookmark (affects restore fidelity).
**Root cause:** `remove()` called `TrashStorage.trashBookmark()` (moves assets to .trash/) then `deleteWeblocFile()` which calls `BookmarkFileService.delete()` (tries to delete assets again + removes sidecar entry).
**Fix:** Added `deleteWeblocFileOnly()` that removes just the `.webloc` file without touching sidecar or assets.
**Commit:** `ee9538d` (2026-03-23)

### Same-name folder trash collision
**Symptom:** Deleting two folders with the same name (e.g., `Work/Recipes` and `Personal/Recipes`) destroys the first one's trash contents.
**Root cause:** Trash destination used `folder.name` as the subdirectory. Two folders with the same name collide.
**Fix:** Use `folder.id.uuidString` as the trash subdirectory name.
**Commit:** `ee9538d` (2026-03-23)

---

## Animations & SwiftUI

### `withAnimation` without reduceMotion crashes accessibility
**Symptom:** Users with Reduce Motion enabled see jarring animations or VoiceOver issues.
**Root cause:** `withAnimation(.snappy)` without checking `reduceMotion`.
**Fix:** Always use `withAnimation(reduceMotion ? .none : .snappy)`. Add `@Environment(\.accessibilityReduceMotion) private var reduceMotion` to the view.

### `.hoverState()` handles reduceMotion internally
**Note:** Don't add a reduceMotion check around `.hoverState()` — it's built in. This is a known non-violation in audits.

---

## NSPanel / Window Management

### `makeKeyAndOrderFront` steals focus
**Symptom:** Cider's panel steals focus from the user's active app.
**Root cause:** `makeKeyAndOrderFront` activates the app. Cider uses `NSPanel` with `.nonactivatingPanel` specifically to avoid this.
**Fix:** Use `orderFront(nil)` + `makeKey()` (if keyboard input needed) instead of `makeKeyAndOrderFront`.

### AX `setWindowSize` ignored by Firefox/Zen
**Symptom:** Window resize works for most apps but Firefox ignores width changes.
**Root cause:** Firefox's accessibility implementation doesn't honor AX size changes.
**Fix:** Fall back to AppleScript `set size of window 1` for apps that ignore AX.

### Resize then position, not the reverse
**Symptom:** Window ends up in wrong position after resize+move.
**Root cause:** Resizing after positioning shifts the window because macOS anchors from different corners.
**Fix:** Always resize first, then set position.

### VisualEffectView blending mode matters
**Symptom:** Overlay views show desktop wallpaper bleeding through instead of blending with panel content.
**Root cause:** `.behindWindow` blending samples through the clear window background to the desktop wallpaper. It's meant for the window chrome itself, not for views layered on top of other panel content.
**Fix:** Use `.withinWindow` for views overlaying panel content. Reserve `.behindWindow` for the base window background layer only.

### GeometryReader in compact mode — measure the right thing
**Symptom:** Panel width oscillates infinitely between collapsed and expanded states.
**Root cause:** GeometryReader was measuring the content area width (which changes when the sidebar toggles), feeding back into layout, which triggers another toggle — infinite loop.
**Fix:** Measure the full panel width (the outer HStack), not the content area. The panel width is stable regardless of sidebar state.

### Sticky section headers need opaque backgrounds
**Symptom:** Scrolling content bleeds through sticky section headers in lists.
**Root cause:** `LazyVStack` with `pinnedViews: [.sectionHeaders]` pins headers but they have transparent backgrounds by default.
**Fix:** Add an explicit opaque background (e.g., `CiderColors.panelBackground`) to section header views.

### DatePicker crashes in non-activating panel popovers
**Symptom:** App crashes when opening a DatePicker inside a popover in a non-activating `NSPanel`.
**Root cause:** `DatePicker` with `.field` or `.compact` style tries to present its own popover, which conflicts with the non-activating panel's window level and event handling.
**Fix:** Don't use `DatePicker` in non-activating panel popovers. Use a plain `TextField` with manual date string parsing instead.

### Remote view service crashes from focus/animation in popovers
**Symptom:** Intermittent crashes in remote XPC view service when interacting with popovers.
**Root cause:** Two patterns crash the remote view service: (1) `@FocusState` combined with `async .task { focused = true }`, and (2) `withAnimation` on content that changes height. Both trigger XPC issues in the remote rendering process.
**Fix:** Remove `@FocusState` auto-focus hacks and avoid animating height-changing content inside popovers. Let the user tap to focus manually.

---

## Keyboard Events

### Terminal unusable — only letter keys work
**Symptom:** Enter, Space, Tab, arrows don't work in the embedded terminal.
**Root cause:** `CiderPanelView` has an app-wide `NSEvent.addLocalMonitorForEvents(.keyDown)` that intercepts these keys for card navigation.
**Fix:** Check if the event target is inside the terminal view first — return the event untouched if so.

---

## Sync

### Folders created on desktop don't appear on web/iOS
**Symptom:** New folders invisible on other platforms.
**Root cause:** SyncService was reading from legacy `BookmarksStorage.folders` instead of `VaultFolderService.shared.folders`.
**Fix:** Updated all SyncService folder reads/writes to use VaultFolderService. (Fixed 2026-03-23)

### Case-insensitive SyncId matching
**Symptom:** Duplicate records appear on the backend for the same bookmark/note.
**Root cause:** UUID strings can differ in casing (e.g., `A1B2...` vs `a1b2...`). Backend lookups were case-sensitive, treating them as different records.
**Fix:** All `ciderSyncId` lookups in the backend use `.toLowerCase()`. Prevents duplicate records from UUID casing differences.

### Preserve FolderId on sync lookup failure
**Symptom:** Bookmarks silently lose their folder assignment after a sync cycle.
**Root cause:** When `folderSyncId` lookup fails (because the folder hasn't synced yet), the code was clearing the bookmark's `folderId` instead of leaving it alone.
**Fix:** When folder lookup fails, preserve the existing `folderId` value instead of setting it to nil. The folder will sync eventually and the association will resolve.

---

## Performance & Caching

### NotesStorage filesystem watcher CPU loop
**Symptom:** App pegs 100% CPU doing nothing visible.
**Root cause:** The filesystem watcher monitors the notes directory. `scanNotes()` rebuilds and writes the index file, which lives in the same directory. The write triggers the watcher, which calls `scanNotes()` again — infinite loop.
**Fix:** Compare the rebuilt index to the previous one before writing. Only write if content actually changed. This pattern applies to ANY filesystem watcher that writes into its own watched directory.

### Card size slider minimum width pressure
**Symptom:** Panel can't shrink below a certain width even though the user is dragging it smaller.
**Root cause:** `MasonryLayout.resolvedLayoutWidth` floors the width at `minimumColumnWidth`, which creates back-pressure preventing the panel from shrinking.
**Fix:** Return `rawWidth` directly from `resolvedLayoutWidth` instead of flooring. Let the masonry layout adapt to whatever width it's given.

### CiderFont scale caching
**Symptom:** Changing font scale in config has no effect until app restart.
**Root cause:** `_cachedScale` is computed once at startup and never invalidated. New config-driven font properties read from the stale cache.
**Fix:** Call `invalidateScale()` in `handleConfigChanged()` so the cached scale is recomputed when config changes.

### StoragePaths vault URL caching
**Symptom:** Sluggish scrolling or hitches in card grid views.
**Root cause:** `StoragePaths` URLs were being resolved fresh on every access, including calling `CiderConfig.load()` from disk in view body render paths.
**Fix:** URLs are cached in `_cachedTypeURLs`. Use `cachedDirectoryURL(for:)` in render paths. Never call `CiderConfig.load()` in SwiftUI view bodies — it reads from disk.

---

## TipTap Editor

### Note images broken after vault migration
**Symptom:** Images in notes show as broken links in the editor.
**Root cause:** WKWebView can't load `file://` URLs from the vault due to sandbox restrictions.
**Fix:** Added `CiderVaultSchemeHandler` for `cider-vault://` scheme. `NotesMarkdownPathCodec` converts paths to `cider-vault://` for the editor and strips them on persistence.
**Commit:** `d2b0457` (2026-03-17)

---

## AI / LLM

### Apple Intelligence context window is tiny (~4K tokens)
**Symptom:** AI "forgets" conversation after a few exchanges, gives generic answers.
**Root cause:** Apple's on-device Foundation Models have ~4K context. Multi-turn history fills it quickly.
**Fix:** This is a platform limitation. The local MLX model (Qwen, 32K context) is the upgrade path. Model picker in AI panel lets users switch.

### MLX tool calling uses prompt-based parsing
**Symptom:** Local model tool calls sometimes fail or produce malformed JSON.
**Root cause:** Unlike Apple Intelligence (which has a native tool API), MLX uses `<tool_call>` blocks parsed from the response text.
**Fix:** `MLXToolExecutor` parses these blocks and executes them in a loop (up to 3 rounds). Individual tool results are truncated at 2,000 chars. Budget capped at 28K tokens.
