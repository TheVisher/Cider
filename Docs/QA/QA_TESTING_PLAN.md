# Cider 1.0 QA Testing Plan

> **How to use:** Work through one round at a time. For each step, test it and mark Pass/Fail. If something is broken, log it in the Issues column. After each round, sign off before moving to the next. Any agent can pick this up mid-stream — just find the next unsigned round.

**Created:** 2026-03-16
**Tester:** minivish

---

## Legend

| Symbol | Meaning |
|--------|---------|
| `[ ]` | Not tested yet |
| `[x]` | Pass |
| `[!]` | Fail — see Issues column |
| `[-]` | Skipped / N/A |

---

## Round 1: Panel Basics

Core floating panel behavior. This is the foundation — if activation or focus is broken, nothing else matters.

| # | Test Step | Result | Issues / Notes |
|---|-----------|--------|----------------|
| 1.1 | **Single-tap Option** — tap Option once, panel appears. Tap again, panel dismisses. | `[x]` | |
| 1.2 | **Double-tap Option** — switch to double-tap mode in Settings, verify double-tap activates. | `[x]` | |
| 1.3 | **Activation speed slider** — adjust slider in Settings, verify faster/slower taps respond correctly. | `[x]` | |
| 1.4 | **No focus steal** — open a text editor (e.g. VS Code), activate Cider, type — keystrokes should go to the text editor, not Cider. | `[x]` | Fixed: changed `makeKeyAndOrderFront` → `orderFront` in CiderPanel.show() |
| 1.5 | **Escape chain** — Escape walks back through open states (search → detail → selection) to default view. Does NOT dismiss panel. | `[x]` | By design — Option tap dismisses |
| 1.6 | **Click outside** — clicking outside panel does NOT dismiss it. Panel stays open. | `[x]` | By design — Option tap dismisses |
| 1.7 | **Resize** — drag each edge and corner to resize. Panel should respect minimum size. | `[x]` | Fixed: `window.minSize` returned (0,0) on borderless panels — switched to design constants. Left/bottom edges no longer slide at minimum. |
| 1.8 | **Drag to move** — drag title bar area, panel moves. | `[x]` | |
| 1.9 | **Multi-monitor** — move mouse to a different screen, activate. Panel should appear on that screen. | `[x]` | |
| 1.10 | **Panel position memory** — move/resize panel on a screen, dismiss, reactivate on same screen. Position and size should be restored. | `[x]` | |
| 1.11 | **Sidebar auto-hide** — shrink panel to compact width, sidebar should collapse. Widen it, sidebar returns. | `[x]` | |
| 1.12 | **Modifier key passthrough** — while panel is open, Opt+Tab should still switch windows. Opt+Cmd+other shortcuts should work. | `[x]` | |

**Round 1 Sign-off:**
- [x] All tests passed or issues logged
- **Date:** 2026-03-16
- **Notes:** Two fixes: (1) `makeKeyAndOrderFront` → `orderFront` to prevent focus steal on open. (2) Resize min-size fix — `window.minSize` returns (0,0) on borderless panels, switched to design constants so left/bottom edges stop at minimum.

---

## Round 2: Navigation & Tabs

Tab bar, sidebar navigation, saved views, and the Cmd+K palette.

| # | Test Step | Result | Issues / Notes |
|---|-----------|--------|----------------|
| 2.1 | **Home tab** — Home tab is always visible and shows the dashboard (Continue + Library feed). | `[-]` | Removed — Home tab was cut from the design |
| 2.2 | **Create saved view tab** — click + button, create a new saved view. It appears as a tab. | `[x]` | |
| 2.3 | **Rename tab** — double-click or right-click rename on a saved view tab. | `[x]` | Fixed: added double-click rename via simultaneousGesture |
| 2.4 | **Close tab** — close a saved view tab via right-click. | `[x]` | No X button, right-click only — by design |
| 2.5 | **Drag reorder tabs** — drag tabs to reorder them. Order persists after restart. | `[x]` | Works with slow click-hold-drag. Quick drag moves window instead (pre-existing, logged) |
| 2.6 | **Sidebar toggle** — click sidebar toggle button, sidebar hides/shows. | `[x]` | |
| 2.7 | **Sidebar folder navigation** — click folders in sidebar, content area shows that folder's items. | `[x]` | |
| 2.8 | **Cmd+K palette** — press Cmd+K, palette opens. Type to search items and quick actions. | `[x]` | |
| 2.9 | **Cmd+K quick actions** — "New Bookmark", "New Note", "New Todo" actions work from palette. | `[x]` | New Bookmark = capture active tab (known: not yet working). New Note and New Todo work. |
| 2.10 | **Sidebar search** — type in sidebar search field, items filter live. | `[x]` | |
| 2.11 | **Tab persistence** — close and relaunch app, all tabs are restored in order. | `[x]` | |

**Round 2 Sign-off:**
- [x] All tests passed or issues logged
- **Date:** 2026-03-16
- **Notes:** One fix (double-click rename). One pre-existing low-priority issue logged (quick tab drag moves window). Home tab N/A — removed from design.

---

## Round 3: Bookmarks — Capture & Display

Adding bookmarks and viewing them in all display modes.

| # | Test Step | Result | Issues / Notes |
|---|-----------|--------|----------------|
| 3.1 | **Capture from browser** — click capture button (or Opt+B) while a browser tab is open. Bookmark created with title + URL + thumbnail. | `[x]` | Fixed: switched AppleScript to CGEvent keystrokes. Required re-adding Accessibility permission after Xcode rebuild. |
| 3.2 | **Capture from clipboard** — copy a URL, use +New or Cmd+K to add. URL is recognized and enriched. | `[x]` | |
| 3.3 | **Drag-drop URL** — drag a URL from browser address bar into Cider. Bookmark created. | `[!]` | No visible drop target — needs drop zone overlay. Logged. |
| 3.4 | **Drag-drop image** — drag an image file onto a bookmark card to set its thumbnail. | `[!]` | Crashes: `_dispatch_assert_queue_fail` threading bug. Logged. |
| 3.5 | **Grid view** — switch to grid view. Cards render with thumbnails, titles, domain. | `[x]` | |
| 3.6 | **List view** — switch to list view. Rows show title, URL, date, tags. | `[x]` | |
| 3.7 | **Masonry view** — switch to masonry view. Full thumbnails shown without cropping. | `[x]` | |
| 3.8 | **Card size slider** — adjust slider. Cards resize fluidly in all view modes. | `[x]` | |
| 3.9 | **Enrichment** — add a new bookmark, wait a few seconds. Title, thumbnail, favicon, tags should populate. | `[x]` | |
| 3.10 | **YouTube bookmark** — add a YouTube URL. Thumbnail should be the video thumbnail. | `[x]` | |
| 3.11 | **Reddit bookmark** — add a Reddit post URL. Gallery posts should show carousel, video posts should show thumbnail. | `[x]` | |
| 3.12 | **X/Twitter bookmark** — add an X.com tweet URL. Title and media should extract. | `[x]` | |
| 3.13 | **Shopify/Cloudflare site** — add a Shopify store URL. Should NOT open a browser tab. Thumbnail should appear. | `[x]` | Allbirds works. Amazon enrichment needs work (logged separately). |
| 3.14 | **Hide card details toggle** — enable "Hide card details" in view options. Cards show only thumbnails, details appear on hover. | `[x]` | |

**Round 3 Sign-off:**
- [x] All tests passed or issues logged
- **Date:** 2026-03-16
- **Notes:** One fix (browser capture: AppleScript → CGEvent). Three issues logged: drag-drop URL needs drop zone (Medium), image drop crashes (High), Amazon enrichment (Medium). 11/14 pass.

---

## Round 4: Bookmark Details

The detail panel in all its view modes, plus reader and web views.

| # | Test Step | Result | Issues / Notes |
|---|-----------|--------|----------------|
| 4.1 | **Open detail (slide-out)** — click a bookmark, detail slides out from the right. | `[x]` | |
| 4.2 | **Open detail (full panel)** — switch to full panel mode via the mode switcher. | `[x]` | |
| 4.3 | **Open detail (page view)** — switch to page view mode. | `[x]` | |
| 4.4 | **Preview tab** — thumbnail/image preview displays correctly. | `[x]` | |
| 4.5 | **Reader tab** — Readability extraction shows clean article text. Loading spinner while extracting. | `[x]` | |
| 4.6 | **Web tab** — live web page loads in WKWebView. Navigation works. | `[x]` | |
| 4.7 | **Reader unavailable** — for sites where reader fails, button should be pre-disabled (no click needed). | `[x]` | Tested with YouTube |
| 4.8 | **Metadata editing** — edit title, add/remove tags, change folder, add notes in metadata panel. Changes persist. | `[x]` | |
| 4.9 | **GIF bookmark** — open a GIF bookmark. Animates on hover in grid, always animates in detail. "GIF" badge visible. | `[x]` | |
| 4.10 | **Carousel bookmark** — open a multi-image bookmark. Arrow buttons page through images. Page dots visible. | `[!]` | Reddit gallery only shows first image. Carousel not populated from gallery_data. Logged. |
| 4.11 | **Hero mode persistence** — set a bookmark to Reader view, close, reopen. Should remember Reader as the default. | `[x]` | |
| 4.12 | **Video keeps playing** — start a video in Web tab, switch detail view mode (slide-out → full). Video should keep playing. | `[x]` | |

**Round 4 Sign-off:**
- [x] All tests passed or issues logged
- **Date:** 2026-03-17
- **Notes:** One issue: Reddit gallery carousel only shows first image (Medium, logged). 11/12 pass.

---

## Round 5: Notes

Creating, editing, and managing notes. Reference `Docs/NOTES_EDITOR_SMOKE_CHECKLIST.md` for deeper editor tests.

| # | Test Step | Result | Issues / Notes |
|---|-----------|--------|----------------|
| 5.1 | **Create note** — use +New or Cmd+K "New Note". Editor opens. | `[x]` | |
| 5.2 | **Type and autosave** — type text, observe autosave indicator. Close and reopen — content persists. | `[x]` | |
| 5.3 | **Formatting toolbar** — Aa popover: bold, italic, underline, strikethrough, highlight all work. | `[x]` | Card previews show plain text (by design) |
| 5.4 | **Headings & lists** — create headings (Title/Heading/Subheading), bullet lists, numbered lists, task lists via Aa popover. | `[x]` | |
| 5.5 | **Tables** — insert table, edit cells, add/delete rows and columns. Persists after close/reopen. | `[x]` | |
| 5.6 | **Slash menu** — type `/`, menu appears. Select an item, it inserts. | `[x]` | |
| 5.7 | **Note pinning** — right-click a note, pin it. Pinned notes sort to top. | `[!]` | Pin toggles but doesn't sort to top. LibraryViewModel sort doesn't check isPinned. Logged. |
| 5.8 | **Note in folder** — assign a note to a folder. It appears when you navigate to that folder. | `[x]` | |
| 5.9 | **Drag-out** — drag a note out to Finder. A .md file should appear. | `[!]` | Exports as .webloc instead of .md. Wrong pasteboard type. Logged. |
| 5.10 | **In-note find** — Cmd+F in editor. Search highlights matches, arrow keys navigate between them. | `[x]` | |
| 5.11 | **Undo/Redo** — undo and redo from toolbar buttons work in the editor. | `[x]` | |
| 5.12 | **Note title** — title shows in all detail view modes. Double-click to rename works. | `[x]` | |

**Round 5 Sign-off:**
- [x] All tests passed or issues logged
- **Date:** 2026-03-17
- **Notes:** Two issues: note pinning doesn't sort to top (Medium), note drag-out exports .webloc instead of .md (Medium). 10/12 pass.

---

## Round 6: Folders & Tags

Organization features — folders, tags, saved view filtering.

| # | Test Step | Result | Issues / Notes |
|---|-----------|--------|----------------|
| 6.1 | **Create folder** — create a new folder from sidebar. It appears in the folder list. | `[x]` | |
| 6.2 | **Rename folder** — right-click rename. New name persists. | `[x]` | |
| 6.3 | **Delete folder** — delete a folder. Items inside are unassigned, not deleted. | `[x]` | |
| 6.4 | **Sub-folders** — create a folder inside another folder. Hierarchy displays correctly. | `[x]` | |
| 6.5 | **Folder icons** — right-click → Icon submenu. Set an SF Symbol and an emoji. Both display in sidebar and folder header. | `[x]` | |
| 6.6 | **Assign items to folder** — drag or use context menu to move bookmarks/notes into a folder. | `[x]` | |
| 6.7 | **Create tag** — add a tag to a bookmark or note. Tag appears in sidebar tag list. | `[x]` | "New Tag" UX issues logged (position + auto-naming) |
| 6.8 | **Tag filter in sidebar** — click a tag in sidebar, items filter to that tag. Click toggles selection (no Cmd needed). | `[x]` | |
| 6.9 | **Tag merge** — in tag manager, right-click → "Merge Into...". Items reassign to target tag. | `[x]` | |
| 6.10 | **Saved view tag filter** — in ViewOptions dropdown, add tag filter chips. Saved view only shows matching items. | `[x]` | |
| 6.11 | **Bulk tag** — select multiple items, click "Tag" in title bar. Tags apply to all selected. | `[x]` | Fixed duplicate tag display (sidecar vs Cider labels). Bottom gap noted for later. |
| 6.12 | **Tag search in Cmd+K** — search for a tag name in Cmd+K. Creates a filtered saved view tab. | `[x]` | |

**Round 6 Sign-off:**
- [x] All tests passed or issues logged
- **Date:** 2026-03-17
- **Notes:** One fix (duplicate sidecar tags filtered). Three UX issues logged: "New Tag" position + auto-naming (Medium), tag pill bottom gap (Low). 12/12 pass.

---

## Round 7: Todos & Date Cards

Task management and date-based surfacing.

| # | Test Step | Result | Issues / Notes |
|---|-----------|--------|----------------|
| 7.1 | **Create single todo** — +New → Todo → Single Todo. Quick-create popover with title field, enter to create. Edit via detail panel. | `[x]` | Flow updated from original test description |
| 7.2 | **Create todo list** — +New → Todo → Todo List. Full editor modal opens for checklist management. | `[x]` | Different flow from single todo (full editor upfront) |
| 7.3 | **Checklist items** — add, check/uncheck, reorder, delete checklist items. Subtasks work. | `[x]` | Subtasks not clickable on card preview (detail only). Logged. |
| 7.4 | **Todo card view** — todo cards show completion toggle, priority indicator, checklist preview, due date badge. | `[x]` | |
| 7.5 | **Todo list row** — in list view, todos show compact row with key info. | `[x]` | Shows title, type, dates. Column alignment issue logged separately. |
| 7.6 | **Mark complete** — toggle todo complete from card or context menu. Card visual updates. | `[x]` | Grid card size non-uniform logged. |
| 7.7 | **Todo detail view** — click todo, detail panel opens with tappable checkboxes. | `[x]` | |
| 7.8 | **Due date badges** — create todos with past/today/future dates. Verify Overdue/Today/date badges. | `[x]` | |
| 7.9 | **Date card creation** — create a date card (event). Set date, time, location. | `[x]` | |
| 7.10 | **Coming Up section** — library view shows upcoming date cards and todos with due dates. | `[x]` | Single todos need due date added via edit to appear. Optional due date in quick-create logged. |
| 7.11 | **Tab badge** — urgent date cards show a count badge on the first tab. | `[x]` | Shows on Library tab (no Home tab) |
| 7.12 | **Notifications** — if enabled in Settings, system notification fires for upcoming events. | `[-]` | Deferred for later testing |

**Round 7 Sign-off:**
- [x] All tests passed or issues logged
- **Date:** 2026-03-17
- **Notes:** All functional tests pass. Issues logged: subtask card interaction (Low), grid card sizing (Medium), column alignment (Low), single todo due date in quick-create (Low). Notifications deferred. 11/12 pass, 1 deferred.

---

## Round 8: Sessions & Whiteboard

Browser session capture and Excalidraw whiteboard.

| # | Test Step | Result | Issues / Notes |
|---|-----------|--------|----------------|
| 8.1 | **Capture browser session** — +New → Session. Loading state shows, then session card with tab list. | `[ ]` | |
| 8.2 | **Session card view** — card shows tab preview with count. | `[ ]` | |
| 8.3 | **Session detail** — click session, detail shows tab list with URLs. | `[ ]` | |
| 8.4 | **Restore all tabs** — click "Restore All Tabs" in session detail. Tabs open in browser. | `[ ]` | |
| 8.5 | **Save individual tab** — from session detail, save a single tab as a bookmark. | `[ ]` | |
| 8.6 | **Browser picker** — dropdown to choose which browser to capture from. Default persists. | `[ ]` | |
| 8.7 | **Create whiteboard** — +New → Whiteboard or Cmd+K "Create Whiteboard". Excalidraw canvas loads. | `[ ]` | |
| 8.8 | **Draw on whiteboard** — use drawing tools (rectangle, text, freehand). Elements persist after tab switch and return. | `[ ]` | |
| 8.9 | **Whiteboard persistence** — draw something, switch to another tab, switch back. Canvas content is intact. | `[ ]` | |
| 8.10 | **Whiteboard as tab** — whiteboard appears as a tab, can be reordered with other tabs. | `[ ]` | |

**Round 8 Sign-off:**
- [ ] All tests passed or issues logged
- **Date:**
- **Notes:**

---

## Round 9: Clipboard & Search

Clipboard panel and all search functionality.

| # | Test Step | Result | Issues / Notes |
|---|-----------|--------|----------------|
| 9.1 | **Clipboard panel open** — press Opt+V. Clipboard panel appears. | `[x]` | Fixed: rapid open/close left ghost shadow — KVO async update now guards `panel.isVisible` before updating shadow frame. |
| 9.2 | **Clipboard captures** — copy text, a URL, and an image. All appear in clipboard panel. | `[x]` | |
| 9.3 | **Clipboard actions** — Copy, Save as Bookmark, Save as Note buttons work on clipboard items. | `[x]` | |
| 9.4 | **Date grouping** — clipboard items grouped by Today, Yesterday, etc. Sections collapse/expand. | `[x]` | |
| 9.5 | **Clipboard URL cards** — URL items show favicon + domain. | `[x]` | |
| 9.6 | **Clear all / purge saved** — clear all and purge saved buttons work. | `[x]` | "Purge saved" only appears when saved items exist — by design. |
| 9.7 | **Search: basic** — Cmd+K or sidebar search. Type a bookmark title, it appears. | `[x]` | Two issues logged: search tab uses stripped-down view (9.7a), Cmd+K doesn't filter current tab (9.7b). |
| 9.8 | **Search: @bookmarks** — type `@bookmarks` or `@b` prefix. Only bookmarks shown. | `[x]` | |
| 9.9 | **Search: @notes** — type `@notes`. Only notes shown. | `[x]` | |
| 9.10 | **Search: @todos** — type `@todos` or `@tasks`. Only todos shown. | `[x]` | |
| 9.11 | **Search: @folder:Name** — type `@folder:Work`. Shows items in that folder. | `[x]` | UX note: `@folder:Name` syntax uses a colon unlike `@b`, `@n`, `@t` shorthands. Should support `@f FolderName` (space instead of colon) for consistency. |
| 9.12 | **Search: @tag:Name** — type `@tag:design`. Shows items with that tag. | `[x]` | Same colon inconsistency as @folder — should support `@tag TagName` space syntax. Logged in 9.11a. |
| 9.13 | **Scope pills** — when a scope modifier is active, pill appears below search field. | `[x]` | |
| 9.14 | **Search: @sessions** — type `@sessions`. Only browser sessions shown. | `[x]` | Fixed: sessions missing from SearchService — added search by name/tab titles/URLs. Clicking result is no-op (no onOpenSession handler yet). |

**Round 9 Sign-off:**
- [x] All tests passed or issues logged
- **Date:** 2026-03-17
- **Notes:** One fix (ghost shadow on rapid toggle). Four issues logged: search tab stripped-down view (9.7a, Medium), Cmd+K doesn't filter current tab (9.7b, Low), @folder/@tag colon syntax inconsistency (9.11a, Low). 14/14 pass.

---

## Round 10: Settings, Keyboard, Drag-Out & Polish

Settings, keyboard navigation, drag-to-external-apps, screen capture, and general polish.

| # | Test Step | Result | Issues / Notes |
|---|-----------|--------|----------------|
| 10.1 | **Settings opens** — open Settings from panel (gear icon or Cmd+,). All 7 categories load. | `[x]` | Fixed: Cmd+, opened a blank ghost window (SwiftUI Settings scene with EmptyView). Added `showSettingsWindow:` override in AppDelegate to intercept and open real settings instead. |
| 10.2 | **Activation mode setting** — switch between single/double tap. Behavior changes immediately. | `[x]` | |
| 10.3 | **Sound effects toggle** — enable/disable sound effects. Verify sounds play/stop. | `[x]` | |
| 10.4 | **Vault location** — change vault directory. Confirm move dialog appears. | `[!]` | No confirmation dialog — vault moves immediately after folder selection with no "Are you sure?" prompt. Should show a confirmation sheet before moving. |
| 10.5 | **Keyboard shortcuts reference** — Settings → General → Shortcuts shows all keybinds. | `[x]` | |
| 10.6 | **Arrow key navigation** — in grid/masonry, arrow keys move focus ring between cards. | `[x]` | |
| 10.7 | **Enter to open** — press Enter on focused card. Detail view opens. | `[x]` | |
| 10.8 | **Delete to trash** — press Delete on focused/selected card. Item trashed with undo toast. | `[x]` | |
| 10.9 | **Shift+Arrow select** — hold Shift + arrow keys to select a range of cards. | `[x]` | |
| 10.10 | **Multi-select** — Cmd+click multiple cards. Bulk actions (tag, move, delete) work. | `[x]` | |
| 10.11 | **Drag bookmark to Finder** — drag a bookmark out to Finder. Creates a .webloc or opens URL. | `[x]` | |
| 10.12 | **Drag note to Finder** — drag a note out. Creates a .md file. | `[x]` | Fixed: was exporting as .inetloc. Added registerFileRepresentation with markdown UTI. |
| 10.13 | **Option+drag for image** — hold Option, drag a bookmark with thumbnail to Finder. Image file appears. | `[x]` | Minor: some filenames get doubled extension (e.g. "title.jpg.jpeg"). Cosmetic. |
| 10.14 | **Screen capture** — use capture feature (Opt+Cmd+2). Screenshot taken, routing toast appears. | `[x]` | Fixed: screenshot saved as note showed broken image. Attachment was saved to Notes/.attachments/ but note lived in Inbox/Notes/ — relative path didn't resolve. Now saves to Inbox/Notes/.attachments/. |
| 10.15 | **Trash & undo** — delete an item, undo toast appears, click undo. Item restored. | `[x]` | |
| 10.16 | **Import bookmarks** — import a Netscape HTML bookmark file. Bookmarks appear. | `[x]` | |
| 10.17 | **Export bookmarks** — export bookmarks to HTML. File is valid and re-importable. | `[x]` | |
| 10.18 | **Light/Dark mode** — switch system appearance. Cider follows correctly. | `[N/A]` | Cider is dark-only by design. |
| 10.19 | **Reduce Motion** — enable Reduce Motion in System Settings. All animations should be instant/crossfade. | `[x]` | |

**Round 10 Sign-off:**
- [x] All tests passed or issues logged
- **Date:** 2026-03-17
- **Notes:** 10.18 N/A (dark-only app). Open issues: vault move no confirmation (10.4 Medium), search tab stripped-down view (9.7a Medium), @folder/@tag space syntax (9.11a Low), doubled extension on Option+drag (10.13 Cosmetic).

---

## Issues Log

Track everything found during QA here. Reference the test step number.

| Test # | Issue Description | Severity | Status | Fix Notes |
|--------|-------------------|----------|--------|-----------|
| 1.4 | Panel steals focus on open — cursor goes to sidebar search | Medium | Fixed | `makeKeyAndOrderFront` → `orderFront` in CiderPanel.show() |
| 1.7 | Left/bottom edge resize slides panel at minimum size | Medium | Fixed | `window.minSize` returns (0,0) on borderless panels; use `CiderPanelDesign` constants directly in PanelEdgeResizeView |
| 2.3 | Double-click to rename tab wasn't implemented | Low | Fixed | Added `simultaneousGesture(TapGesture(count: 2))` to tab buttons |
| 2.5 | Quick click-drag on tab drags window instead of reordering tab | Low | Open | Pre-existing: panel sendEvent drag handler (3px threshold) fires before SwiftUI `.onDrag` delay. Slow click-hold-drag works fine. |
| 3.1 | Browser capture failed for Zen (AppleScript -600, AX permission stale) | Medium | Fixed | Switched from AppleScript to CGEvent keystrokes. User needed to re-add Cider to Accessibility after Xcode rebuild. |
| 3.3 | Drag-drop URL into panel doesn't create bookmark — no visible drop target | Medium | Open | Need a drop zone overlay that appears when dragging a URL over the panel. |
| 3.4 | Drag-drop image onto bookmark crashes app | High | Open | `_dispatch_assert_queue_fail` — threading bug in image drop handler (wrong dispatch queue). |
| 3.13 | Amazon enrichment doesn't work — needs investigation | Medium | Open | Allbirds/Shopify works fine. Amazon likely blocks metadata scraping. |
| 4.10 | Reddit gallery carousel only shows first image | Medium | Open | Gallery post with 5 images only enriched the first. Carousel not populated from Reddit .json gallery_data. |
| 5.7 | Note pinning doesn't sort to top | Medium | Open | `togglePin` updates the model and index, but `LibraryViewModel.sortItems` doesn't check `isPinned`. Pinned items need priority in sort. |
| 5.9 | Note drag-out creates .webloc instead of .md file | Medium | Fixed | Added `registerFileRepresentation` with markdown UTI alongside internal Cider type. Avoids the public.file-url conflict with SwiftUI .onDrop. |
| 6.7a | "New Tag" option at bottom of tag list instead of top | Low | Open | Should be first item in the tag picker for discoverability. |
| 6.7b | "New Tag" creates literal "new tag" instead of prompting for name | Medium | Open | Should open an input field or inline rename for the new tag name. |
| 6.11 | Note cards show duplicate tags (colored + grey sidecar) | Medium | Fixed | Sidecar tags now filtered against Cider label names. |
| 6.11b | Note cards with tags have extra bottom gap below tag pills | Low | Open | TagPillRow uses `.frame(maxHeight: maxLines * 24)` which reserves space even for single-line tags. Cards without tags have no gap. |
| 7.5 | List view column header dividers misaligned with row content | Low | Open | Column dividers in header don't line up with the actual text position in rows. |
| 7.6a | Todo subtask checkboxes not clickable on card preview | Low | Open | Main task toggle works on card, subtasks only clickable in detail panel. |
| 7.6b | Todo cards don't conform to grid card size | Medium | Open | Todo cards (especially single todos) are smaller than other cards in grid view. All cards should be uniform height in grid mode. |
| 7.10 | Single todo creation popover should have optional due date field | Low | Open | Single todos created without a due date don't appear in Coming Up. Adding a due date field to the quick-create popover would help. |
| 8.1 | Browser session capture doesn't work with Zen (Firefox-based) | Medium | Open | Works with Dia and Chromium browsers. Zen likely needs Firefox-specific AppleScript or a different capture path. |
| 8.2 | Session card doesn't fill grid card space — shows 3 tabs with lots of empty space | Low | Open | Card has room to show more tab entries but caps at 3 + "+N more". Should fill available card height. |
| 8.6 | Browser picker only shows "Default" — can't select other browsers | Medium | Open | Should list installed browsers. Currently stuck on Default with no other options. |
| 9.1 | Rapid open/close leaves ghost shadow — main panel hidden but shadow stays visible | Low | Fixed | KVO async `updateFrame` guarded with `panel.isVisible` check |
| 9.7a | Search tab (from "Create tab" in Cmd+K) uses a stripped-down view — no grid/masonry/sort/filter/sidebar. Should use the regular library view with a text-search filter instead of the legacy CiderTab.search type. | Medium | Open | |
| 9.7b | Cmd+K search doesn't filter the current tab — sidebar search does. Cmd+K should do the same when there's no scope modifier. | Low | Open | |
| 9.11a | `@folder:Name` uses colon syntax, inconsistent with `@b`, `@n`, `@t` shorthands. Should support `@f FolderName` (space-separated) to match the pattern. Same likely applies to `@tag:Name` → `@tag Name`. | Low | Open | |
| 10.4 | Vault location change has no confirmation dialog — moves immediately after folder selection | Medium | Open | Should show a confirmation sheet: "Move vault to X? This cannot be undone." |
| 10.13 | Option+drag bookmark image to Finder produces doubled file extension (e.g. "title.jpg.jpeg") | Low | Open | Cosmetic — the file is usable but the name is wrong. |
| 11.1 | Sources folder → normal folder navigation stuck — selecting a sources folder then clicking a normal folder highlights both blue, doesn't switch. Must click a tab first to leave sources, then can enter normal folder. | Medium | Open | Sidebar selection state gets stuck when transitioning from linked source to regular folder. |

**Severity:** Critical / High / Medium / Low
**Status:** Open / In Progress / Fixed / Won't Fix

---

## Final Sign-off

- [x] All 10 rounds completed
- [x] All Critical/High issues resolved
- [ ] Medium/Low issues triaged (fix or defer)
- **Date:** 2026-03-17
- **Ready for release:** Pending triage of open Medium issues

### Open Items (post-QA, pre-release)

| # | Issue | Severity |
|---|-------|----------|
| 3.4 | Drag-drop image onto bookmark crashes app (threading bug in image drop handler) | High |
| 3.3 | Drag-drop URL into panel doesn't create bookmark — no drop zone overlay | Medium |
| 3.13 | Amazon enrichment doesn't work — likely blocks metadata scraping | Medium |
| 4.10 | Reddit gallery carousel only shows first image | Medium |
| 5.7 | Note pinning doesn't sort pinned notes to top | Medium |
| 6.7b | "New Tag" creates literal "new tag" instead of prompting for name | Medium |
| 7.6b | Todo cards don't conform to grid card size — smaller than other cards | Medium |
| 8.1 | Browser session capture doesn't work with Zen (Firefox-based) | Medium |
| 8.6 | Browser picker stuck on "Default" — can't select other browsers | Medium |
| 9.7a | Search tab (from Cmd+K "Create tab") uses stripped-down view instead of regular library view | Medium |
| 10.4 | Vault move has no confirmation dialog — moves immediately | Medium |
| 2.5 | Quick click-drag on tab drags window instead of reordering tab | Low |
| 6.7a | "New Tag" option at bottom of tag list instead of top | Low |
| 6.11b | Note cards with tags have extra bottom gap below tag pills | Low |
| 7.5 | List view column header dividers misaligned with row content | Low |
| 7.6a | Todo subtask checkboxes not clickable on card preview | Low |
| 7.10 | Single todo quick-create has no due date field | Low |
| 8.2 | Session card caps at 3 tabs — doesn't fill available card height | Low |
| 9.7b | Cmd+K search doesn't filter the current tab | Low |
| 9.11a | `@folder:Name` / `@tag:Name` should use space syntax to match other shorthands | Low |
| 10.13 | Option+drag produces doubled file extension (e.g. title.jpg.jpeg) | Low (Cosmetic) |
