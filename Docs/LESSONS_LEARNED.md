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
