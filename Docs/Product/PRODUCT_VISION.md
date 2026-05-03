# Cider Product Vision

> Consolidated product vision document. Each section below was originally a standalone doc.

---

## Table of Contents

1. [1.0 Roadmap](#10-roadmap)
2. [Bookmarks Vision](#bookmarks-vision)
3. [Home Vision](#home-vision)
4. [Kanban Vision](#kanban-vision)
5. [Linked Sources Vision](#linked-sources-vision)
6. [Notes Vision](#notes-vision)
7. [Vault Vision](#vault-vision)
8. [Whiteboard Vision](#whiteboard-vision)
9. [Workspaces Vision](#workspaces-vision)
10. [AI Strategy](#ai-strategy)
11. [Resurf Competitive Analysis](#resurf-competitive-analysis)

---


## 1.0 Roadmap


> **This is the active roadmap from beta to 1.0 release.** The beta launch roadmap (`Docs/_archive/BETA_ROADMAP.md`) is complete and archived.

### Agent Rules

- For adjustable feature direction beyond the strict 1.0 release list, check `Docs/Product/CIDER_ADAPTIVE_ROADMAP.md` first.
- Check this doc when asked "what should we work on?" for 1.0 release gating — point to next `Not Started` item
- Also check `Shared/FEATURE_PARITY.md` to see if iOS or Web are missing something Desktop already has
- Redirect post-1.0 ideas to the adaptive roadmap/backlog instead of scattering them across new docs
- Never mark features Complete — only the user does that after testing
- Run code review after implementing any feature
- Update this doc after gate transitions
- After user confirms a feature is complete, update `Shared/FEATURE_PARITY.md` to reflect the change

**Created:** 2026-02-28
**Target:** Stable 1.0 release (out of beta)
**Guiding Principle:** Polish what exists, complete half-finished features, add new card types, nail distribution. No ambitious new systems until after 1.0.

---

### Process: How Features Ship

Same 5-gate process from the beta roadmap. Nothing is "done" until Gate 5.

```
Gate 1: IMPLEMENT     — Agent writes the code
Gate 2: CODE REVIEW   — Agent reviews for bugs, conventions, accessibility
Gate 3: USER TEST     — User (minivish) manually tests the feature, reports issues
Gate 4: FIX & POLISH  — Address any issues from testing and review
Gate 5: SIGN OFF      — User confirms it's good. Status -> Complete
```

#### Status Legend
| Status | Meaning |
|--------|---------|
| `Not Started` | Work hasn't begun |
| `Implementing` | Agent is actively building |
| `In Review` | Code review in progress |
| `Testing` | User is manually testing |
| `Fixing` | Issues found, being addressed |
| `Complete` | User signed off. Done. |
| `Blocked` | Can't proceed — dependency or decision needed |

#### Agent Rules

1. **Check this doc at the start of every session.**
2. **When the user asks "what should we work on next?"** — point to the next Not Started item in the current phase.
3. **When the user gets sidetracked** — acknowledge the idea, add it to the post-1.0 backlog at the bottom, and redirect.
4. **Never mark an item Complete** without user sign-off.
5. **After implementing**, do a code review (conventions, reduce motion, tokens, etc.).
6. **Update this doc** after each gate transition.
7. **Watch for user feedback** (GitHub Issues, direct messages, testing sessions) that should be promoted to this roadmap.

---

### Phase 1: Infrastructure & Distribution

Must be solid before 1.0. Users need auto-updates and a proper install path.

#### R-01: Sparkle Auto-Updater
> Integrate Sparkle framework for automatic update checks so users don't manually re-download .dmg files.

**Status:** `In Progress` — code complete, needs Xcode project + signing setup
**Priority:** Critical

**Scope:**
- ✅ SPM dependency on Sparkle 2.9.0
- ✅ `SparkleUpdaterService` singleton with `start()` and `checkForUpdates()`
- ✅ "Check for Updates" button in Settings > About
- ✅ Auto-update toggle in Settings > General > Startup
- ✅ "Check for Updates Now" with last-check timestamp
- ✅ AppDelegate calls `SparkleUpdaterService.shared.start()` at launch

**Remaining (manual setup required):**
- ✅ Add `SUFeedURL` to Info.plist (appcast URL: `https://thevisher.github.io/Cider/appcast.xml`)
- ✅ Generate Ed25519 signing keys
- ✅ Add `SUPublicEDKey` to Info.plist with the generated public key
- ✅ Set up appcast XML hosting (GitHub Pages on `gh-pages` branch)
- ✅ Release script generates appcast via `generate_appcast` and publishes to gh-pages
- [ ] Add Sparkle framework to Xcode project (File > Add Package Dependencies > search "sparkle-project/Sparkle")
- [ ] Test update flow with a real update (ship 0.1.0-beta.3, verify Sparkle prompts)

---

#### R-02: Mac App Store Listing
> Distribute Cider through the Mac App Store for discoverability and trust.

**Status:** `Not Started`
**Priority:** High

**Scope:**
- App Store Connect setup (screenshots, description, categories)
- Sandboxing audit (identify what needs entitlements)
- App Store review guidelines compliance
- Pricing decision (free with IAP? paid? free beta period?)
- Dual distribution: direct download (GitHub) + MAS

---

#### R-03: Code Health Fixes ✅
> Resolve high and medium severity issues from CODE_HEALTH.md.

**Status:** `Complete` (2026-02-28)
**Priority:** High

**Scope (all resolved):**
- ✅ CH-S03: SSRF validation in bookmark enrichment
- ✅ CH-S04: Symlink traversal blocking in ExternalSourceScanner
- ✅ CH-C05: Orphan attachment cleanup race condition (added creationDate check)
- ✅ CH-C06: Short UUID collision risk (use full UUID)
- ✅ CH-C07: NetscapeBookmarksCodec unit tests (10 tests)
- ✅ CH-C11: NotesStorage async directory update (synchronous clear before async scan)
- ✅ CH-C12: Already correct (verified, original report inaccurate)
- ✅ CH-D06: Docs status drift fixed (DOCS_INDEX, QUICK_REFERENCE)
- ✅ CH-L04: SPM resource warnings fixed (Package.swift excludes)

---

#### R-04: Vault Directory Migration ✅
> When the user changes the vault location in Settings, offer to move existing files automatically.

**Status:** `Complete` (2026-02-28)
**Priority:** Medium

**Scope (all resolved):**
- ✅ "Move existing data?" confirmation dialog (Move / Don't Move / Cancel)
- ✅ Vault root migration: moves all type subdirectories + .ai embeddings
- ✅ Per-type override migration: moves single type directory contents
- ✅ Cancel button aborts the directory change entirely
- ✅ Skips files that already exist at destination (no overwrites)
- ✅ Works for both vault root changes and per-type override changes
- Note: Progress indicator deferred — file moves are fast for typical vaults

---

### Phase 2: Complete & Polish Existing Features

Make everything that shipped in beta feel finished.

#### R-05: Tag System Completion ✅
> Merge tags and saved view tag filter — the two deferred tag features.

**Status:** `Complete` (2026-03-01)
**Priority:** High

**Scope (all resolved):**
- ✅ Tag merge UI in tag manager ("Merge Into..." context menu + target popover)
- ✅ Tag hygiene with similarity detection (edit distance, stemming, punctuation) + unused tag cleanup
- ✅ Saved view tag filter UI in ViewOptionsDropdown with tag chips
- ✅ Tag search in sidebar (filters tag pills) and Cmd+K (creates filtered saved view tab)
- ✅ Bulk tag from selection title bar "Tag" button
- ✅ Context menu tag actions apply to all selected items when multi-selected
- ✅ Sidebar live search matches items by tag name

---

#### R-06: Date Card Surfacing Completion
> Notifications, per-view toggle, per-card override, and recurring event support.

**Status:** `Complete`
**Priority:** High

**Scope:**
- **Recurring event surfacing:** `nextOccurrence(after:)` and `effectiveDate(now:)` on DateCard — recurring events surface before their next occurrence, not just the original date
- **Per-card surfacing override:** `SurfacingRule` model activated — custom reminder window (days) and notification lead time (minutes) per card, editable in DateCardEditorSheet
- **Per-view toggle:** `showComingUpSection` on `SavedViewLayoutSpec` — "Show Coming Up" toggle in ViewOptionsDropdown, gates HomeDashboardView section
- **Home tab badge count:** CiderTabBar shows count of urgent date cards on the Home tab
- **System notifications:** `DateCardNotificationService` using `UNUserNotificationCenter` — per-card or default notification time, category with "Open" and "Mark Complete" actions, Settings UI under Data → Notifications

---

#### R-07: AI Auto-Tag Quality ✅
> Improve semantic category matching and threshold tuning for auto-generated tags.

**Status:** `Complete` (2026-03-01)
**Priority:** Medium

**Scope (all resolved):**
- ✅ Expanded taxonomy from 31 → 40 categories (cooking, travel, photography, sports, entertainment, business, real-estate, government, cryptocurrency)
- ✅ Host keyword matching stage — checks hostname against taxonomy keywords (allrecipes.com → cooking, mlb.com → sports, imdb.com → entertainment)
- ✅ Expanded taxonomy keywords with domain-specific terms (booking, airbnb, espn, netflix, etc.)
- ✅ Tag limit increased from 3 → 4
- ✅ 3-char ALL CAPS acronyms allowed through entity filtering (API, AWS, GCP)
- ✅ Dismissed label tracking — removed AI labels won't be re-assigned on re-enrichment
- ✅ "Re-run Auto-Tagging" button in Settings → Intelligence with throttled scheduling
- ✅ Extended entity and URL path stopword lists

---

#### R-08: Keyboard Navigation ✅
> Arrow keys, Enter, Delete — standard keyboard interaction for grid and masonry views.

**Status:** `Complete` (2026-03-02)
**Priority:** High

**Scope (all resolved):**
- ✅ Arrow keys move focus ring in grid/masonry (spatial, column-aware) and list (linear)
- ✅ Enter opens focused item (bookmark detail, note editor, date card, contact)
- ✅ Delete/Backspace trashes focused or selected items with undo
- ✅ Tab/Shift+Tab for sequential linear navigation
- ✅ Shift+Arrow for range selection
- ✅ Space to toggle selection on focused item
- ✅ Focus ring visual indicator (separate from selection highlight)
- ✅ Auto-scroll to keep focused item visible (ScrollViewReader)
- ✅ Arrow keys escape sidebar search field at text boundaries
- ✅ NSEvent local monitor with text field safety (skips when typing in search/editor)

---

#### R-09: Notes Editor Polish ✅
> Compact Apple Notes-style formatting toolbar and note pinning.

**Status:** `Complete` (2026-03-03)
**Priority:** Medium

**Scope (all resolved):**
- ✅ **Compact toolbar:** Undo/Redo, Aa popover, Table, Link — in title bar, no title label (title comes from content)
- ✅ **Aa text style popover:** Inline styles (B/I/U/S/highlight), alignment, paragraph styles (Title/Heading/Subheading/Body/Monostyled), lists, block elements — all with active state indicators
- ✅ **New formatting:** Strikethrough, highlight, block quote, horizontal rule, heading levels, code block — via Aa popover
- ✅ **TipTap highlight extension:** `@tiptap/extension-highlight` installed and wired
- ✅ **Format state reporting:** JS→Swift bridge reports active marks/nodes on every selection change
- ✅ **Note pinning:** Pin/unpin via context menu, pinned notes sort to top, persisted in index
- ✅ **Old toolbar removed:** Flat scrollable toolbar strip replaced by compact title bar icons
- ✅ **Floating toolbar removed:** Redundant JS floating toolbar replaced by table popover with 5×5 grid picker + contextual table operations
- ✅ **Save protection:** flushSave guards against incomplete editor round-trips (isLoadingNote/isLoadingExternalFile)

---

#### R-10: Custom Folder Icons ✅
> Let users pick SF Symbols or emoji for folder icons.

**Status:** `Complete` (2026-03-06)
**Priority:** Low

**Scope:**
- ✅ `icon: String?` on Folder model (SF Symbol name or emoji, auto-detects type)
- ✅ Icon picker via right-click context menu → Icon submenu (Symbol + Emoji submenus)
- ✅ 22 SF Symbol presets + 16 emoji presets, with checkmark on current selection
- ✅ "Remove Icon" option when icon is set
- ✅ Display in sidebar (root + sub-folder rows) and FolderDetailView header
- ✅ Default folder/folder.fill icon when none set (unchanged behavior)
- ✅ `BookmarksStorage.setFolderIcon()` for persistence
- ✅ Backward compatible — existing folders deserialize with `icon: nil`

---

#### R-11: Drag Out to External Apps
> Drag bookmarks and notes out of Cider into other apps.

**Status:** `Complete` (2026-03-04)
**Priority:** High

**Scope:**
- ✅ Bookmarks: register `public.url` drag provider (URL opens in browser)
- ✅ Notes: register `public.file-url` drag provider (.md file)
- ✅ Bookmarks with images: Option+drag exports image via `NSItemProvider(contentsOf:)`
- ✅ Multi-drag: primary item's external types registered for external app targets
- ✅ Works from Home tab, Folder detail view, Continue section, all display modes
- ✅ Option+drag mode switching with drag preview hint ("⌥ for image")
- ✅ showDragModeHints setting toggle
- ✅ Bulk multi-drag undo (single undo action for all moved items)
- ✅ Panel drag area restricted to title bar + sidebar (no accidental panel moves)
- ✅ Tested: Finder, iMessage, Facebook, Discord desktop app — all working
- ✅ Image drag uses file URL provider (no text leakage into text fields)

**Known limitation:** Discord web app doesn't accept native file drags (browser sandbox limitation, not fixable from our side).

---

#### R-12: Clipboard Viewer ✅
> Show recent clipboard items with action buttons.

**Status:** `Complete` (2026-03-05)
**Priority:** Medium

**Scope (all resolved):**
- ✅ Standalone `ClipboardPanel` — dedicated NSPanel, opens/closes via Opt+V
- ✅ `ClipboardHistoryService` monitors pasteboard changes, routes to `ClipboardStorage`
- ✅ Clipboard items: URLs, images, text, rich text — with source app detection
- ✅ Action buttons per item: Copy, Save as Bookmark/Note, Dismiss
- ✅ Date-grouped sections (Today, Yesterday, weekdays, weeks, months) with collapse/expand
- ✅ Current item section (most recent copy highlighted)
- ✅ Two-width mode toggle (single column / 2-column grid)
- ✅ Saved state tracking — items marked when saved as bookmark/note, reconciled on deletion
- ✅ Purge saved items, clear all, per-section delete
- ✅ Image retention and storage cap settings
- ✅ Favicon + domain display for URL cards (multi-source: DuckDuckGo, Google, direct)
- ✅ Configurable retention (text and image separately), auto-purge on launch

---

#### R-13: Advanced Search
> Scope modifiers for power users.

**Status:** `✅ Complete`
**Priority:** Medium

**Scope:**
- `@bookmarks`, `@notes`, `@events`, `@contacts` type filters with prefix matching (`@b` works)
- `@folder:Name` scope to specific folder (multi-word, prefix match, multiple folders)
- `@folder:` (bare) shows all folder items grouped by folder with headers
- `@tag:Name` scope to specific tag (prefix match)
- Scope pills shown below search field when active
- Works in Cmd+K palette, sidebar search, and search tabs

---

#### R-20: Screen Capture Polish
> Complete the screen capture flow — Date Card and Contact OCR routing is broken, and the feature needs general polish.

**Status:** `Testing`
**Priority:** Medium

**Scope:**
- ✅ **Fix Date Card OCR routing:** Screen capture → full DateCardEditorSheet with pre-filled title, date/time, location, OCR text in details
- ✅ **Fix Contact OCR routing:** Screen capture → full ContactEditorSheet with pre-filled name, email, phone in correct fields
- ✅ **Notes routing works:** Verified functional (OCR text → new note) — was already working
- ✅ **Image preview in capture toast:** Capture thumbnail shown in toast header (replaces camera icon)
- ✅ **Direct editor routing:** Screen capture buttons bypass +New popover, open full editor sheets directly
- ✅ **OCR time merging:** When NSDataDetector defaults to 12PM, scan text for explicit time patterns and merge
- ✅ **OCR noise filtering:** Skip PROMOTED, SPONSORED, tickets, etc. when extracting title
- ✅ **OCR location extraction:** Detect venue names from lines after the title
- **Known limitation:** OCR quality depends on screenshot clarity; garbled text produces garbled titles

---

#### R-21: Keyboard Shortcuts Reference ✅
> A discoverable place showing all keybinds — currently no way for users to find them.

**Status:** `Complete` (2026-03-06)
**Priority:** Medium

**Scope (all resolved):**
- ✅ Settings → General → Shortcuts subcategory
- ✅ Four sections: Panel, Capture, Navigation, Editing
- ✅ Monospaced key labels + descriptions for all current keybinds
- ✅ Documents: Option double-tap, Opt+B/N/V, Opt+Cmd+2, Cmd+K, arrow keys, Shift+Arrow, Tab, Return, Space, Cmd+A/C/V/X/Z, Delete, Escape chain
- Future: user-configurable keybinds (post-1.0)

---

### Phase 3: Detail View & Media

Richer content display and media type support.

#### R-14: Bookmark Detail View V2
> Redesigned detail view with multiple view modes and rich metadata.

**Status:** `Complete`
**Priority:** High

**Scope:**
- ✅ Three view modes: Slide-out panel, Full panel, Page view — with persistent config + switcher popover
- ✅ Metadata panel with 8 collapsible sections (Title, Source, Folder, Tags, Keywords, Notes, Intelligence, Info)
- ✅ Content tabs: Preview (thumbnail) / Reader (Readability.js) / Web (live WKWebView)
- ✅ Eager preload: web page + reader extraction start on card open, content ready instantly
- ✅ Reader extraction in background — no raw HTML flash, cached article displayed directly
- ✅ Reader unavailability persisted per bookmark — button pre-disabled, no click needed to discover
- ✅ Per-bookmark hero mode persistence — each card remembers its last view across sessions
- ✅ Persistent WKWebView across mode switches — videos keep playing through transitions
- ✅ Autoplay prevention on preloaded web views
- ✅ Toolbar spinners while loading, greyed icons when unavailable
- ✅ Replaces current detail popover

---

#### R-15: GIF, Video & Carousel Bookmarks
> Extended media type support beyond static images.

**Status:** `Complete` (2026-03-09) — GIF + carousel complete, video deferred to vault roadmap
**Priority:** Medium

**Scope:**
- **GIF support (done):**
  - `BookmarkMediaType` enum (`.image`, `.gif`, `.video`) on Bookmark model
  - GIF detection via magic bytes (`GIF87a`/`GIF89a`) and CGImageSource frame count for animated WebP/APNG
  - Direct image URL enrichment bypass (skip HTML parsing, download image directly)
  - `.webp` → `.gif` URL variant fallback for Giphy/Tenor/Imgur
  - Clipboard `com.compuserve.gif` detection (preserves animation over PNG fallback)
  - `AnimatedGIFView` (NSViewRepresentable) with custom aspect-fill layout via `AnimatedGIFWrapper`
  - Hover-to-animate on bookmark cards, always-animate in detail view
  - "GIF" badge overlay on animated thumbnails
  - **Known limitation:** Drag-drop GIF from browser provides static TIFF — animation lost. URL-based GIF bookmarks work fully.
- **Video bookmarks (deferred to post-1.0):** Accept .mp4/.mov/.webm drag-drop, thumbnail extraction via AVAssetImageGenerator
- **Multi-image/carousel (done):** Multiple images per bookmark, horizontal paging on cards with arrows/scroll wheel/keyboard, page dots, count badge, images section in metadata sidebar with delete/open in Preview

---

### Phase 4: New Card Types & Views

Expand Cider beyond bookmarks and notes.

#### R-16: Books Card Type
> Track books as library items alongside bookmarks and notes.

**Status:** `Not Started`
**Priority:** Medium

**Scope:**
- `Book` model as new `LibraryItemV2` case
- Fields: title, author, cover image, reading status (want/reading/finished/abandoned), rating, notes
- `BookStorage` in vault (`~/CiderVault/Books/`)
- Card view (cover-forward) and list row
- Manual entry (title + author minimum)
- Shows in library feed, folders, search, tags — like every other card type
- Full book system (ISBN lookup, Goodreads import, progress tracking) deferred to post-1.0

---

#### R-17: Todos Card Type
> Task cards that live in the library alongside everything else, with rich checklist items, due date surfacing, and recurring support.

**Status:** `Complete` (2026-03-09)
**Priority:** Medium

**Scope:**

**Phase A — Core infrastructure (done):**
- ✅ `TodoCard` model with `TodoChecklistItem` + `TodoSubtask` three-level hierarchy — title, details, notes, checklist items, due date, priority, completion state, labels, folders, linked entities
- ✅ `TodoChecklistItem` sub-model — individual checklist items with completion tracking, subtasks
- ✅ `TodoPriority` enum — low/medium/high with display names and icons
- ✅ `TodoCardStorage` — JSON snapshot persistence, CRUD, completion toggle, checklist item toggle, subtask toggle, folder assignment, label management
- ✅ `LibraryItemV2.todo` case — integrated into all computed properties (id, title, dates, folderID, labelIDs, dateAnchor, isCompleted)
- ✅ `LibraryEntityType.todo` — registered for saved views, entity filters, scope modifiers
- ✅ `StorageType.todos` — vault directory at `~/CiderVault/Todos/`
- ✅ Trash integration — `TodoCardTrashPayload`, trash/restore/permanent-delete in TrashStorage
- ✅ LibraryViewModel binding — auto-rebuilds on todo changes, text search across title/details/checklist
- ✅ +New popover — "Todo" type card with Single Todo / Todo List choice
- ✅ Search — `@todos` / `@tasks` scope modifier, subtask title search via `SearchService.searchTodos`
- ✅ Cmd+K "New Todo" quick action
- ✅ Label cascade — delete/merge labels propagates to todos
- ✅ All exhaustive switches updated across all view files
- ✅ Notes field on TodoCard with auto-logging of completions

**Phase B — Card views & integration (done):**
- ✅ `TodoCardCardView` — card with completion toggle, title, priority indicator, checklist preview (first 4 items), due date badge (Overdue/Today/date), progress counter, tag pills
- ✅ `TodoListRow` — compact list row with completion toggle, title, checklist count, priority, due date badge
- ✅ `TodoEditorSheet` — full editor with checklist management, subtasks, reorder controls
- ✅ `TodoDetailView` — slide-out detail panel with clickable URLs, tappable checkboxes, summary bar
- ✅ `todoCardContextMenu` — Open, Mark Complete/Incomplete, Tags, Move to Folder, Delete
- ✅ Wired into HomeDashboardView (library view), Coming Up section, FolderDetailView, SavedViewTabContent with full callbacks (selection, hover, focus, undo, trash)
- ✅ Click-to-open across search results, stacks, saved views, folders

**Phase C — Enriched checklist items & bills tracking (done):**
- ✅ Enrich `TodoChecklistItem` with optional `dueDate`, `amount`, `urlString` fields
- ✅ Summary bar (Total / Paid / Remaining / Progress) for lists with amounts
- ✅ Due date badges (Overdue / Today capsules) in detail view
- ✅ Completion timestamps ("Done Mar 8") on checked items

**Phase D — Recurring & kanban (post-1.0):**
- [ ] Recurring schedule on TodoCard (daily/weekly/monthly/yearly)
- [ ] On completion: auto-reset checklist items and un-complete for next cycle (or spawn fresh copy)
- [ ] Kanban display mode in dedicated Todos tab (columns by status/priority/label)

---

#### R-18: Documents Card Type
> Upload and organize files (PDFs, images, documents).

**Status:** `Not Started`
**Priority:** Medium

**Scope:**
- `Document` model as new `LibraryItemV2` case
- Fields: title, file path/URL, file type, size, thumbnail
- `DocumentStorage` in vault (`~/CiderVault/Documents/`)
- Drag-drop file ingestion (copy to vault)
- Card view with file type icon and/or thumbnail preview
- Open in default app, reveal in Finder
- Shows in library feed, folders, search, tags
- Full document system (filesystem watcher, OCR, full-text search) deferred to post-1.0

---

#### R-19: Excalidraw Whiteboard Tab
> Full Excalidraw-powered whiteboard as a tab type, with Cider library integration.

**Status:** `Complete` (2026-03-09) — Phase A done, Phases B & C deferred to vault roadmap
**Priority:** Medium

**Phase A — Foundation (Complete):**
- `SavedViewKind` enum (`.library` / `.whiteboard(canvasID)`) with backward-compat decoding
- `WhiteboardCanvas` model + `WhiteboardStorage` service (vault persistence in `~/CiderVault/Whiteboards/`)
- `StorageType.whiteboards`, trash/restore/undo manager support
- Excalidraw JS bundle (React + esbuild, bundled in `Resources/ExcalidrawEditor/`)
- `WhiteboardViewModel` with singleton WKWebView, debounced scene saves (1.5s)
- `ExcalidrawView` (NSViewRepresentable) + `WhiteboardTabView`
- "Create Whiteboard" in NewItemPopover and Cmd+K palette
- Tab system routing: whiteboard SavedViews render Excalidraw canvas
- Flush-save on tab switch, transparent canvas background
- Xcode project wiring (`ExcalidrawEditor` folder reference in Resources build phase)

**Phase B — Cider Library Integration (Not Started):**
- Drag bookmarks from sidebar/library → drops as linked card on canvas
- Drag images from Cider library → inserts as Excalidraw image element via JS bridge
- Right-click any card → "Send to Whiteboard" → pick target whiteboard
- `cider-library-item` custom element type with `libraryItemID` in Excalidraw `customData`
- Swift bridge resolves IDs to current card data (title, thumbnail, URL)

**Phase C — Polish (Not Started):**
- Canvas rename via tab context menu
- Canvas delete with undo toast
- Theme sync (dark/light appearance changes)
- Whiteboard tab icon ("scribble") in tab bar
- Keyboard shortcut conflict prevention (Excalidraw vs panel shortcuts)
- Export whiteboard as PNG/PDF

---

#### R-22: Browser Session Cards
> Capture, view, and restore browser tab sessions as full library cards.

**Status:** `Complete` (2026-03-14)
**Priority:** Medium

**Scope:**
- ✅ `BrowserSession` as full `LibraryItemV2` case with `LibraryEntityType.session`
- ✅ `folderID`, `labelIDs` on BrowserSession with backward-compat decoding
- ✅ `SessionCardCardView` (grid/masonry card with tab preview) + `SessionListRow` (list mode)
- ✅ `SessionDetailView` slide-out with editable name, scrollable tab list, Restore All Tabs
- ✅ Save individual tabs as bookmarks from detail view
- ✅ Browser picker dropdown with persistent default (CiderConfig)
- ✅ +New popover "Session" capture form with loading state
- ✅ Search: `@sessions` scope modifier, tab title text search
- ✅ Folders, tags, trash, undo — all standard library card operations
- ✅ Bulk operations: select-all, bulk delete, bulk move, bulk tag
- ✅ Keyboard navigation: arrow keys, Enter to open, Delete to trash
- ✅ Table list view, entity filter chip, stacks support

---

### Stretch Goals

If time allows before 1.0. Otherwise, first post-1.0 priorities.

| Item | Notes |
|------|-------|
| Resurfacing system | Track `lastOpenedAt` / `openCount`, surface forgotten items |
| Smart folder suggestions | AI: "You saved 12 React articles — create a folder?" |
| AI page summaries | Summarize bookmarked pages via Foundation Models |
| Similar items discovery | Cosine similarity suggestions in detail view |
| Group-by | Group items by date, type, domain, tags with collapsible headers |
| Web archival | .webarchive snapshots for offline access |
| Related links per bookmark | Multiple URLs for one entity (App Store + GitHub + docs) |
| Quick-capture inline text field | Type and hit Enter to create note/bookmark from Home |
| ~~Browser session sync~~ | ✅ Shipped as R-22. Sessions are full library cards with capture, restore, search, folders, tags, trash. |
| Quick Note scratchpad | Alt+N opens a small standalone panel with just a note editor. Fast capture without opening the full panel. |

---

### Progress Dashboard

| ID | Feature | Phase | Status |
|----|---------|-------|--------|
| R-01 | Sparkle Auto-Updater | 1 | Deferred → Vault Roadmap |
| R-02 | Mac App Store Listing | 1 | Deferred → Vault Roadmap |
| R-03 | Code Health Fixes | 1 | ✅ Complete |
| R-04 | Vault Directory Migration | 1 | ✅ Complete |
| R-05 | Tag System Completion | 2 | ✅ Complete |
| R-06 | Date Card Surfacing Completion | 2 | ✅ Complete |
| R-07 | AI Auto-Tag Quality | 2 | ✅ Complete |
| R-08 | Keyboard Navigation | 2 | ✅ Complete |
| R-09 | Notes Editor Polish | 2 | ✅ Complete |
| R-10 | Custom Folder Icons | 2 | ✅ Complete |
| R-11 | Drag Out to External Apps | 2 | ✅ Complete |
| R-12 | Clipboard Viewer | 2 | ✅ Complete |
| R-13 | Advanced Search | 2 | ✅ Complete |
| R-20 | Screen Capture Polish | 2 | Testing |
| R-21 | Keyboard Shortcuts Reference | 2 | ✅ Complete |
| R-14 | Bookmark Detail View V2 | 3 | ✅ Complete |
| R-15 | GIF/Video/Carousel Bookmarks | 3 | ✅ Complete |
| R-16 | Books Card Type | 4 | Deferred → Vault Roadmap |
| R-17 | Todos Card Type | 4 | ✅ Complete |
| R-18 | Documents Card Type | 4 | Deferred → Vault Roadmap |
| R-19 | Excalidraw Whiteboard Tab | 4 | ✅ Complete |
| R-22 | Browser Session Cards | 4 | ✅ Complete |

**Completed:** 18/22 (3 deferred to Vault Roadmap, 1 in testing)

---

### Already Shipped (Beta)

These shipped in the beta launch and are maintained, not re-implemented:

- Import/Export (Netscape HTML bookmark import and export)
- Floating panel (NSPanel, double-tap Option, all-edge resize, compact mode)
- Bookmark capture (browser, clipboard, drag-drop, Opt+B hotkey)
- Notes editor (TipTap/ProseMirror, inline editing, formatting toolbar)
- Folders (hierarchical, universal, cover images, sticky headers)
- Tab system (saved views, drag-to-reorder, rename, close, +New)
- Full tag system (create, assign, filter, color, sidebar multi-select)
- Display modes (list/grid/masonry + continuous card size slider)
- Multi-select + drag-drop + fanned preview
- Trash & undo (30-day retention, 5-second toast, configurable)
- AI enrichment (auto-tagging, embeddings, OCR, color extraction, page summaries)
- Reader mode (Readability.js + Foundation Models)
- Linked sources (external directory watching)
- Screen capture with OCR routing
- Stacks (query objects, surfacing rules, built-in templates)
- Calendar projection (month view, ghost cells)
- Date card surfacing (Coming Up section, urgency badges)
- Cmd+K quick actions
- Search (token-based, cross-entity, snippets)
- Sound effects (configurable)
- Settings (7 categories)
- Spotlight indexing
- First-run onboarding
- Distribution pipeline (code signing, notarization confirmed 2026-03-02, .dmg, GitHub Releases)
- Standard Edit key equivalents (Cmd+C/V/X/A/Z routed in non-activating panels)
- Per-display panel position memory (each screen remembers its own position/size)
- Open on active display setting (panel follows mouse cursor to current screen)
- Note title in all detail view modes (slide-out, full panel, page) with double-click rename

---

### Post-1.0 Backlog

Everything here is tracked but not planned for 1.0. Ideas get promoted to the roadmap above based on user feedback and priorities.

#### AI & Intelligence
| Item | Source | Notes |
|------|--------|-------|
| AI Chat polish | AI_CHAT_VISION | Popout window broken, streaming markdown rendering, custom agent support, tool use visualization |
| Conversational AI assistant | AI_VISION | Chat overlay, natural language queries, structured output |
| BYOAI (bring your own API key) | BETA_ROADMAP | For users without Apple Intelligence |
| Voice note capture | AI_VISION | Dictate notes via speech-to-text |
| Audio bookmark annotation | AI_VISION | Record voice memo about a bookmark |
| Screenshot-to-text (Vision OCR) | AI_VISION | Alternative to Chrome extension |
| Image search indexing | AI_VISION | Extract text from thumbnails, make searchable |
| GIF finder | AI_VISION, HOME_VISION | Screenshot conversation -> OCR -> AI -> search GIFs |
| Content classification | AI_VISION | Categorize items (tutorial vs news vs recipe) |
| Semantic search via embeddings | AI_VISION | Beyond keyword matching |
| Auto-generate bookmark titles | AI_VISION | From page content via Foundation Models |
| Auto-generate note titles | AI_VISION | From content |
| Generate transcript summaries | AI_VISION | Bullet-point summarization |
| Search via App Intents / Shortcuts | AI_VISION | Siri and Shortcuts integration |
| Hybrid summary validation | AI_VISION | Cross-check FM summary against author's meta description |
| Smart organization nudges | AI_VISION | "You saved 12 React articles — create a folder?" (beyond stretch goal) |

#### Notes
| Item | Source | Notes |
|------|--------|-------|
| Split view (browser + editor) | NOTES_VISION | Resizable divider at wider panel widths |
| Multi-folder membership | NOTES_VISION | `folderIDs: [UUID]` instead of `folderID: UUID?` |
| Drag reorder for manual sort | NOTES_VISION | Manual sort order |
| Advanced image treatment | NOTES_VISION | Fanned/angled image stacks with click-to-cycle |
| Interactive checkboxes on cards | NOTES_VISION | Toggle checkboxes without opening the editor |
| Per-folder sort persistence | NOTES_VISION | Each folder remembers its own sort order/view mode |
| Inline title (first H1 = display title) | R-09 | Apple Notes-style: first H1 in content becomes card title, filename stays decoupled (renameable via context menu) |
| Plain text note format (.txt) | NOTES_VISION | `.txt` alongside `.md`, plain text editor, default format setting, +New picker |
| Quick Note scratchpad (Alt+N) | USER_IDEA 2026-03 | Alt+N opens a small/narrow standalone NSPanel with just a note editor — no sidebar, no tabs. Fast scratchpad for jotting things down. Could use TipTap or plain text. Saves to vault like normal notes. May ship before or after 1.0. |
| Universal floatability contract | USER_IDEA 2026-04 | Future detail surfaces should be authored so they can run embedded in the main app or floated in an `NSPanel` without duplicating business logic. Notes, bookmark metadata, contacts, todos, date cards, and future surfaces should share the same data/view-model boundary and only swap the window shell. |

#### Bookmarks
| Item | Source | Notes |
|------|--------|-------|
| Video bookmarks | R-15 | Drag-drop .mp4/.mov/.webm, thumbnail extraction via AVAssetImageGenerator |
| YouTube transcript sync | BOOKMARKS_VISION | Live captions, click-to-seek |
| PiP video player | BOOKMARKS_VISION | Mini-panel playback when panel closed |
| Richer import feedback | BOOKMARKS_VISION | Malformed file diagnostics |
| Thumbnail dimension settings | BOOKMARKS_VISION | User-facing 720/512/360px toggle |
| Bookmark sorting/filter chips | BOOKMARKS_VISION | Has thumbnail, no thumbnail, recent, tagged |
| Large-library performance pass | BOOKMARKS_VISION | Optimize for 1000+ bookmarks |

#### Views & Organization
| Item | Source | Notes |
|------|--------|-------|
| Kanban display mode | WORKSPACES_VISION | Columns by attribute, drag between columns |
| Themed folders: Media Hub | WORKSPACES_VISION | Netflix-style, TMDB/OMDB enrichment, episode tracking |
| Themed folders: Recipe | WORKSPACES_VISION | Schema.org extraction, cooking mode, meal planning |
| Themed folders: other | WORKSPACES_VISION | Reading List, Music, Travel, Shopping, Learning |
| Card customization sliders | WORKSPACES_VISION | Padding and spacing controls |
| Manual item refs on saved views | WORKSPACES_VISION | "Send to view" context action |
| Sidebar folder drag reorder & nesting | WORKSPACES_VISION | Drag to reorder siblings, nest under other folders |
| Folder breadcrumb path | WORKSPACES_VISION | "Work > Internal Tools > APIs" in folder header |
| Folder inline rename | WORKSPACES_VISION | Right-click context menu + inline editing in sidebar |
| Private/locked folders | USER_IDEA 2026-03 | Folders marked as private are hidden from the library feed, search, and Continue section. Items only visible when you open the folder directly. Optional password/biometric lock — folder contents are completely inaccessible until unlocked. Could use `isPrivate: Bool` + `lockPassword: String?` on Folder model. Private folders excluded from sync push (stay local-only) or encrypted before sync. |

#### Full Systems (card type expansions)
| Item | Source | Notes |
|------|--------|-------|
| Books: ISBN/barcode lookup | BOOKS_VISION | Goodreads/StoryGraph import |
| Books: progress tracking | BOOKS_VISION | Page tracking, reading dates |
| Books: highlight extraction | BOOKS_VISION | Kindle/Apple Books highlights |
| Books: statistics | BOOKS_VISION | Books/year, genre distribution |
| Books: shelf display mode | BOOKS_VISION | Books spine-out visual layout |
| Todos: recurring tasks | R-17 Phase D | Auto-reset or clone on completion, daily/weekly/monthly/yearly |
| Todos: kanban display mode | R-17 Phase D | Columns by status/priority/label in dedicated Todos tab |
| Todos: daily lists | TODOS_VISION | Named lists, auto-archive, templates |
| Todos: views (Today/Upcoming/All) | TODOS_VISION | Dedicated task views |
| Todos: note integration | TODOS_VISION | Pull checkboxes from notes into unified view |
| Todos: global hotkey capture | TODOS_VISION | Add todo without opening panel |
| Todos: natural language dates | TODOS_VISION | Parse "tomorrow", "next Friday" |
| Documents: filesystem watcher | DOCUMENTS_VISION | FSEvents directory monitoring |
| Documents: full-text search | DOCUMENTS_VISION | PDF text, image OCR |
| Documents: window-based capture | DOCUMENTS_VISION | Proxy icon drops, AX file path detection |
| Whiteboard: drag library items onto canvas | R-19 Phase B | Drag bookmarks/notes/images from sidebar → Excalidraw canvas via JS bridge |
| Whiteboard: "Send to Whiteboard" action | R-19 Phase B | Right-click any card → pick target whiteboard → insert as element |
| Whiteboard: cider-library-item elements | R-19 Phase B | Custom Excalidraw element type with libraryItemID, resolved to live card data |
| Whiteboard: export as PNG/PDF | R-19 Phase C | Export canvas via Excalidraw's export API |
| Whiteboard: clipboard capture flow | WHITEBOARD_VISION | Route text/images to whiteboard via toast |
| Whiteboard: templates | WHITEBOARD_VISION | Brainstorming, planning layouts |
| Whiteboard: "Create Note" from selection | WHITEBOARD_VISION | Select blocks → promote to structured note in Notes tab |

#### Books Tab — Full Spec (from FUTURE_TABS.md)

A dedicated reading tracker. Separate from bookmarks (web links) and notes (written content).

**Core features:**
- Library views: cover grid, list view, shelf view
- Book entry: manual add, ISBN/barcode lookup, import from Goodreads/StoryGraph
- Reading status: Want to Read / Currently Reading / Finished / Abandoned
- Progress tracking (page number or percentage), start/finish dates, rating
- Per-book notes, highlights, quotes. Link to Notes tab.
- Shelves/collections, tags, search, reading statistics

**Data model sketch:**
```swift
struct Book: Identifiable, Codable {
    let id: UUID
    var title: String
    var author: String
    var coverImagePath: String?
    var isbn: String?
    var status: ReadingStatus       // .wantToRead, .reading, .finished, .abandoned
    var progress: Double?           // 0-1
    var currentPage: Int?
    var totalPages: Int?
    var startDate: Date?
    var finishDate: Date?
    var rating: Int?                // 1-5
    var notes: String?
    var tags: [String]
    var shelfID: UUID?
    var createdAt: Date
    var updatedAt: Date
}
```

**Storage:** Follow per-file standard (see `STORAGE.md`). Books would likely use a JSON-based format since no standard file format exists for reading metadata.

#### Documents Tab — Full Spec (from FUTURE_TABS.md)

A dedicated surface for non-URL assets (PDFs, images, files). Keeps bookmarks URL-first and avoids mixed-content complexity.

**Phases:**
1. MVP: drag-and-drop ingestion, list/grid browsing, open/reveal/delete
2. Preview & metadata: PDF first page, image thumbnails, details panel
3. Organization: collections/folders/tags, multi-select, bulk actions
4. Interop: import bundles, sync/export, "Attach to Bookmark" linking, `.webarchive` viewing
5. Filesystem watcher: watch `~/Pictures`, `~/Documents`, `~/Downloads` via FSEvents, reference files in-place (like Spotlight), full-text search via PDFKit + Vision OCR

**Window-based file capture (concept):**
- Accept proxy icon drags from document apps (already works via `NSItemProvider`)
- Frontmost window detection via Accessibility API (`kAXDocumentAttribute`) → one-tap "Capture [filename]" suggestion
- "Shake to grab" (detect rapid window movement → surface capture HUD)

**Supported file classes (MVP):** PDF, PNG/JPG/WEBP/GIF/HEIC, TXT/MD (DOCX optional)

**Storage:** Under `~/CiderVault/.cider/documents/` for metadata, with files referenced in-place for watched directories or copied into user folders for manually captured files.

#### Todos Tab — Historical Spec (Shipped as R-17)

> The Todos card type shipped in R-17 (2026-03-09). The original spec from FUTURE_TABS.md is preserved here for reference. See R-17 above for the implemented scope.

Original vision: A lightweight personal planner. Quick-add tasks, organize by day or project, check things off. Not a full PM tool — the digital equivalent of a to-do list on your desk.

**Original core features (many now shipped):**
- Quick-add (type and enter), checkboxes, due dates, priority, subtasks, drag reorder
- Views: Today, Upcoming, All, Completed
- Daily lists with auto-archive and template support
- Integration with Notes tab (pull checkbox items, expand todo → note)
- Quick capture: global hotkey, clipboard, natural language date parsing

**Original data model sketch:**
```swift
struct TodoItem: Identifiable, Codable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var dueDate: Date?
    var priority: TodoPriority?     // .low, .medium, .high
    var notes: String?
    var parentID: UUID?             // subtasks
    var sortOrder: Int
    var listID: UUID?
    var tags: [String]
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date
}
```

**Original storage plan:** `.ics` files (RFC 5545 VTODO). Already defined in the per-file storage standard — `~/CiderVault/Inbox/Todos/`.

---

#### Drag & Drop
| Item | Source | Notes |
|------|--------|-------|
| Electron app drag-out (Discord, Slack) | R-11 | Rework internal drop detection so text payload can carry the URL instead of Cider ID |
| SavedViewTabContent drag providers | R-11 | Wire drag providers into saved view tab cards (needs selection state first) |
| Drag/drop zone panel | USER_IDEA 2026-04 | Dragging files, links, text, or images near the desktop could reveal a floating save-to-Cider drop zone. This builds on the manual Drop Zone surface and should feel like a fast inbox target, not a modal import flow. |

#### Desktop Stickies
| Item | Source | Notes |
|------|--------|-------|
| Desktop sticky notes | USER_IDEA 2026-03 | Pin any card (bookmark, note, todo, event, contact) to the desktop as a small persistent window. Each sticky is a thin NSWindow wrapper around existing card views. ~2-3MB per sticky, zero CPU when idle. Reuses existing card views + vault data. Natural extension of drag-out — if you can drag a card to another app, you should be able to drop it on your desktop too. |
| Sticky window level picker | USER_IDEA 2026-03 | User-configurable window level per sticky: Desktop (behind all windows, stuck to wallpaper), Normal (with other windows), or Floating (always on top, PiP-style). Enables niche use cases like a quick note overlay while gaming, reading instructions over a full-screen app, or a todo list pinned above your workspace. Maps to `NSWindow.Level`: `.desktop`, `.normal`, `.floating`. |
| Sticky desktop widgets | USER_IDEA 2026-04 | Any todo, note, contact, bookmark card, or detail surface can be floated either above all apps or pinned to the desktop as a widget-like panel. This is the product version of universal floatability: small, persistent, glanceable, and directly backed by vault data. |
| Drag-to-desktop sticky creation | USER_IDEA 2026-03 | Drag a card out of Cider onto the desktop → creates a desktop sticky for that card. Inverse of the current drag-out behavior (which exports URLs/files to other apps). |
| Sticky position persistence | USER_IDEA 2026-03 | Remember per-card desktop position across restarts + handle multi-monitor. Track which cards are "pinned to desktop" in CiderConfig or a separate index. |
| Sticky lifecycle management | USER_IDEA 2026-03 | Clean up sticky windows when cards are deleted/trashed. Update live when card data changes (shared storage observer, not per-sticky timers). |

#### Home & UX
| Item | Source | Notes |
|------|--------|-------|
| Today's activity summary | HOME_VISION | Dashboard widget |
| Streak / activity indicators | HOME_VISION | Visual usage feedback |
| Customizable widget layout | HOME_VISION | Choose which sections on Home |
| Pinned items section | HOME_VISION | Show pinned items at top |
| Search shortcut / recent searches | HOME_VISION | Persist recent queries |
| Continue section resurfacing | HOME_VISION | Mix 1-2 forgotten items into Continue alongside recents |
| Rediscovery / auto-surface forgotten items | USER_IDEA | View option or tab section that surfaces cards not opened in X days. Could also pair with auto-purge setting to clean stale content after a threshold. |
| Clipboard as inbox | USER_IDEA 2026-04 | Copied text, images, and URLs become recoverable ingestion candidates for Cider. Clipboard history should act like an inbox queue with save/dismiss state, not just a viewer of transient pasteboard events. |

#### Browser Integration
| Item | Source | Notes |
|------|--------|-------|
| ~~Browser tab capture & restore~~ | ✅ Shipped as R-22 |
| ~~Portable browser sessions~~ | ✅ Shipped as R-22. Cross-device sync planned via Cider Web session sync. |

#### Code Health & Refactoring
| Item | Source | Notes |
|------|--------|-------|
| Split BookmarksStorage (2,450 lines) | CODE_AUDIT 2026-03 | Extract BookmarkEnrichmentService (title/summary/favicon/color/image analysis) and BookmarkImageAssetManager (thumbnail/original/cover handling). Keep BookmarksStorage as persistence + CRUD facade. |
| Split CiderPanelView (2,450 lines) | CODE_AUDIT 2026-03 | Extract DetailPanelManager (detail state), EditorManager (note editing state), TabNavigationManager (tab/folder/source selection). Keep CiderPanelView as root layout + composition. |
| Split AppDelegate (1,400 lines) | CODE_AUDIT 2026-03 | Extract PanelManagerService (panels/positioning), HotkeyService (detector instances), ToastOrchestrationService (toast types + timers). Keep AppDelegate as lifecycle + init. |
| Monitor growing files | CODE_AUDIT 2026-03 | SettingsView (1,230), SavedViewTabContent (1,207), FolderSidebarView (1,080), NotesViewModel (1,057), FolderDetailView (1,007) — watch for crossing 1,500 lines |

#### Infrastructure
| Item | Source | Notes |
|------|--------|-------|
| Collaboration | WHITEBOARD_VISION | Shared whiteboards |
| JSON full backup/restore | BETA_ROADMAP | Single-file export of everything |
| OPML format support | BETA_ROADMAP | RSS reader compatibility |
| Docs status audit | CODE_HEALTH | CH-D06: Multiple docs disagree on shipped status |
| Sync: lightweight inventory endpoint | SYNC_OPT 2026-03 | New `sync:inventory` Convex function returning only `[{syncId, updatedAt}]` for reconciliation — avoids pulling full content (titles, notes, HTML) every hour |
| Sync: thumbnail cleanup on delete | SYNC_OPT 2026-03 | Cider Web delete/trash logic should call `ctx.storage.delete(thumbnailStorageId)` — currently orphans files in Convex file storage |
| Sync: thumbnail compression cap | SYNC_OPT 2026-03 | Enrichment downloads og:image at full size (seen 3.29MB). Resize/compress to ~200KB max before `ctx.storage.store()` |

---

### Issues Log

Track issues found during review and testing. Reference the feature ID.

| Issue | Feature | Found During | Severity | Status | Notes |
|-------|---------|-------------|----------|--------|-------|
| Note editor blank — WKWebView sandbox | R-09 | R-22 testing | Critical | ✅ Fixed | S10 security fix (a0b9f23) restricted readAccessRoot to vault dir, breaking TipTap bundle loading |
| +New note content not in editor | R-09 | R-22 testing | High | ✅ Fixed | save(note:) after rename wrote to wrong path; fixed by adding initialContent to createNew() |

---


## BOOKMARKS Vision


### Goal
Build a fast, low-friction bookmarking system in Cider with strong capture flows, high-quality metadata, and a polished visual browsing experience (List/Grid/Masonry).

### Current Status (Implemented)
- Command Palette tab and standalone Bookmarks window.
- List, Grid, and true Masonry layouts.
- Cross-browser capture flow (capture button + hotkey + clipboard + drag/drop URL).
- Browser coverage working for Chrome, Dia, Zen, and Comet capture path.
- Metadata/title enrichment and thumbnail fetching with fallback behavior.
- Shimmer placeholder while enrichment/thumbnail loads.
- Manual thumbnail assignment by dropping image/image URL/file onto a bookmark card. **This feature is self-contained in `BookmarkCard` — it calls `BookmarksStorage.shared` directly and posts the toast notification itself. No per-view wiring needed. Any view that renders `BookmarkCard` gets drag-and-drop automatically. Do not add `onAssignThumbnailFrom*` callbacks back.**
- Dual-image asset storage for bookmarks:
  - Full-size originals stored in `.originals/` for later access/export.
  - Runtime thumbnails stored in `.thumbnails/` as downsampled PNGs (currently max 720px).
  - Existing bookmarks are normalized retroactively on load (legacy large thumbnails are rewritten to the new format).
- Clipboard review toast flow (save/discard), plus capture success/error toasts.
- Window behavior parity improvements (resizing, tiling shortcuts, snap padding consistency).
- Context menus on cards/rows with Open in Browser, Show Details, Move to Folder, Delete (shared CardContextMenu component).
- **Reader Mode** — Three-mode hero area in the detail panel: thumbnail preview, Readability.js reader view, and live WKWebView. Toolbar buttons (`photo`, `doc.richtext`, `globe`) switch between modes. State resets on bookmark change; each mode is lazy-activated and kept alive on first use.
- **Dominant Color Extraction** — k-means palette extracted from bookmark thumbnails via `ColorExtractionService`. Stored as `dominantColors: [String]?` (hex). Displayed as color swatches in the detail panel's Intelligence section.
- **AI Enrichment Pipeline (Phase 1)** — On capture: NaturalLanguage keyword extraction for auto-tagging (in `BookmarkAIEnrichment`), NLEmbedding vector computation (`EmbeddingStore`), Vision OCR text extraction (`OCRService`), color palette extraction (`ColorExtractionService`). All on-device, all background.
- **Intelligence section in detail panel** — Shows `aiSummary` text, dominant color swatches, and related items (`RelatedItemsView`, up to 3 by vector similarity). Visible for all URL bookmarks.
- **Foundation Models summary integration** — `SummaryService` (Foundation Models on macOS 26+) generates summaries from Reader Mode article text. Triggered on first reader open if no existing `aiSummary`. Stored on the Bookmark model.

### Label and Stack Integration

Bookmarks participate in the cross-entity label and stack system alongside date cards and contacts.

- The `CardLabel` system is cross-entity — labels can be assigned to bookmarks, date cards, and contacts
- Bookmarks can be included in stacks via **manual refs** (explicitly added) or **rule matches** (e.g., stack filtering for a specific label)
- Filter chips in saved views allow label-based filtering across all entity types simultaneously
- Example use cases:
  - Tag a bookmark with a "Gift Idea" label → it surfaces in a partner's birthday stack
  - Tag concert/event bookmarks with a "Tickets" label → a stack filters for upcoming events
  - Color-code bookmarks by project or person for quick visual scanning in mixed-content views

### Future: Related Links Per Bookmark (Single Product, Multiple Sources)

For product-like saves (apps, tools, services), Cider should support one bookmark with multiple source links instead of forcing users into multiple separate bookmarks.

- Keep the one-item mental model:
  - A single bookmark remains the canonical item.
  - One `primary URL` (first captured link) plus `related links` in metadata.
- Keep stacks focused on grouping multiple items:
  - Stacks remain cross-item organization.
  - Related links are per-item enrichment, not a stack substitute.

#### Metadata Actions (Planned)

- `Add Related Link` (manual entry)
- `Suggest Related Content` (AI-assisted scan)

#### Suggested Flow (Planned)

1. User opens bookmark detail panel.
2. User clicks `Suggest Related Content`.
3. Cider extracts canonical entity signals (name, publisher, source domain).
4. High-confidence pass searches for official site / app store / GitHub / docs.
5. If confidence is low, run broader semantic/fuzzy pass.
6. Show candidate links with type, confidence, and short reason.
7. User explicitly selects links to attach (never auto-attach silently).

#### Suggested Related Link Types (Planned)

- `official_site`
- `app_store`
- `play_store`
- `github_repo`
- `github_org`
- `docs`
- `support`
- `pricing`
- `changelog`
- `community`

#### Data Shape (Planned)

Add per-bookmark related links metadata:

```swift
struct RelatedLink: Codable, Identifiable {
    var id: UUID
    var urlCanonical: String
    var type: String
    var title: String?
    var confidence: Int?          // 0...100 for AI suggestions
    var reason: String?           // why this was suggested
    var source: String            // manual | ai_suggested | accepted_ai
    var createdAt: Date
}
```

#### Ranking Guardrails (Planned)

- Score exact entity/publisher/domain matches highest.
- Prefer trusted platforms (`apps.apple.com`, `github.com`, official domain).
- Canonicalize/dedupe URLs before display.
- Penalize likely collisions (same name, different publisher/category).
- Hide low-confidence results behind an explicit "show low confidence" action.
- Require user confirmation before attach.

<!-- Removed: Standalone panel resize handle bug fix — standalone BookmarksPanel was removed in Feb 2026 panel consolidation. Bookmarks are now browsed exclusively in the main panel. -->

---

### Phase 1: Capture Quality and Reliability (Next)
1. Harden metadata extraction quality.
2. Improve source-specific handling for Reddit/X edge cases.
3. Add lightweight diagnostics for failed enrichment/capture attempts.

#### Acceptance Criteria
- Capture success/failure messaging is always accurate (no false positives).
- Metadata title quality is improved on major sites.
- Thumbnail fallback coverage improves without regressions in speed.

### Phase 2: Bookmark Details Surface ✅ (V1)
1. ✅ Add bookmark details panel (on thumbnail click / info action).
2. ✅ Show/edit metadata:
- ✅ canonical URL
- ✅ title
- ✅ tags
- ✅ notes
- thumbnail source/local status (partial — hero preview, no separate indicator)
3. ✅ Add actions:
- replace/remove thumbnail (drag-and-drop on card)
- set thumbnail from Reader/Browser view (right-click image → "Set as Bookmark Thumbnail")
- ✅ copy URL
- ✅ open in browser
- ✅ open original image (if local original exists, else remote fallback)

#### Acceptance Criteria
- ✅ Details panel opens reliably from cards in all layouts (BookmarksTabContent, HomeDashboardView, FolderDetailView).
- ✅ Edits persist and reflect immediately in card/list views.
- ✅ Keyboard navigation and accessibility behavior match existing panel standards.

### Detail View V2 — Resurf-Inspired Redesign

Complete redesign of the detail surface, inspired by Resurf's modal system. The current V1 is a basic two-column sheet (hero preview + metadata sidebar). V2 transforms it into a flexible, content-aware detail experience with multiple view modes and richer metadata.

#### Three View Modes

The detail view supports three sizes, switchable via toolbar buttons + a drag handle for manual resizing:

**1. Slide-out panel (default)**
- Slides in from the right edge of the content area (replaces the current detached popover)
- Content behind it stays visible (not blurred) — the panel overlays part of the card grid
- Toggleable: clicking a card opens it, clicking the same card or pressing Escape closes it
- Metadata sidebar is toggleable — when hidden, just the content preview fills the panel
- Metadata toggle state persists (if you prefer metadata always visible, it stays that way)
- Drag handle on the left edge to manually widen/narrow

**2. Full panel**
- Takes over the entire content area (sidebar stays, tab bar stays)
- Great for images you want to see larger, or for reading bookmark content
- Toolbar button to switch between slide-out and full panel

**3. Page view**
- Self-contained view — takes over everything including the tab bar area
- Essentially a dedicated screen for that item
- Back button or Escape to return
- Best for notes in reader mode, long articles, or when you want to focus entirely on one item

#### Metadata Panel Layout

The metadata panel lives on the right side of the detail view. All sections are collapsible (disclosure triangles, state persisted per section). Order top to bottom:

**Title** — Large editable text at the top of the metadata panel (not buried under "Metadata" heading like V1)

**Folders** — Current folder assignment with picker (same as V1 but moved up in priority)

**Tags** — Tag chips with inline "Add tag..." field. Tap a tag to filter by it. (Currently comma-separated text — upgrade to chip UI)

**Notes** — Expandable text area for free-form notes about the bookmark. "Add note" button when empty.

**Source** — URL display with open/copy actions. For image bookmarks, shows "Saved from clipboard" or the source app.

**Colors** — Dominant color palette extracted from the thumbnail/image. Shows 5-7 color swatches as filled circles or rounded rectangles. "Extract Colors" button if not yet computed. Color values copyable (hex, RGB). Technical approach: `CGImage` → `CIFilter` (CIAreaAverage for regions) or k-means clustering on downsampled pixel data. Store extracted colors on the Bookmark model as `[String]?` (hex values). See "Dominant Color Extraction" below.

**Properties** (bottom) — Read-only metadata grid:
- Created: date
- Updated: date
- Type: Bookmark / Image / (future: Video, GIF)
- Size: file size for images, or "Web page" for URL bookmarks

#### Content-Specific Tabs (URL Bookmarks)

URL bookmarks get hero mode buttons in the detail panel toolbar (implemented as icon toggles, not traditional tabs):

**Preview** (`photo` icon) ✅ — Shows the thumbnail image. Default mode.

**Reader** (`doc.richtext` icon) ✅ — Clean Readability.js article view, styled to match Cider's dark aesthetic. Triggers Foundation Models summary on first open. Links open in system browser.

**Web** (`globe` icon) ✅ — Embedded WKWebView showing the live page. Loaded on demand; stays alive once activated so toggling back is instant.

#### Dominant Color Extraction

✅ Implemented: dominant color palette extracted on capture from bookmark thumbnails.

**Technical approach:**
- Load the thumbnail (not original — already downsampled, fast to process)
- ✅ k-means clustering on downsampled pixel buffer (resize to ~50x50, run k-means with k=6) — implemented in `ColorExtractionService`

**Storage:** `dominantColors: [String]?` on the Bookmark model — array of hex strings (e.g., `["#FC3434", "#1A1A2E", "#E94560"]`). Extracted lazily (on first detail view open) or eagerly (on capture, in background).

**Display:** Row of filled circles or rounded-rect swatches. Tap to copy hex value. Could also be used for:
- Tinting the card border/background subtly in grid view
- Filtering bookmarks by color ("show me all blue-dominant images")
- Color-based sorting or grouping

#### Shared Pattern

This detail view pattern is shared across all content types — not just bookmarks. Notes, date cards, contacts, and future types (documents, whiteboard items) should all use the same three-mode detail surface with content-specific tabs and a consistent metadata panel. The metadata sections vary by type (notes don't have URL/Colors, date cards have date/time/location, etc.) but the shell is identical.

Update `DESIGN_SYSTEM.md` (section 18, Component Catalog) when implementing to document the shared detail view container.

### Phase 3: Library Management
1. **Multi-select** ✓ — Shift-click range, Cmd-click toggle, Cmd+A select all. Bulk move/delete implemented. Multi-drag with fanned preview implemented. Bulk tag future. See `WORKSPACES_VISION.md`.
2. **Sorting controls** — newest, oldest, title A-Z, domain. Per-tab persistence.
3. **Trash integration** ✓ — Delete sends to trash (30-day retention), not permanent delete. See `WORKSPACES_VISION.md` for trash system spec.
4. **Undo** ✓ — Transient toast with "Undo" button for destructive/organizational actions.
5. Filter chips (has thumbnail, no thumbnail, recent, tagged).
6. Duplicate management improvements.

#### Acceptance Criteria
- Bulk actions perform safely with undo support.
- Deleted items go to trash, not permanent deletion.
- Sorting/filtering is stable across List/Grid/Masonry and search.

### Phase 4: Portability and Interop
1. Finalize storage layout under `~/Documents/Cider/bookmarks` (with migration support).
2. Continue Netscape HTML import/export compatibility.
3. Add richer import feedback for malformed/partial bookmark files.
4. **Drag-out to external apps** — register `public.url` on bookmark drag providers so dragging a bookmark onto a browser opens the URL, onto Finder creates a `.webloc`, etc. See `WORKSPACES_VISION.md` → "Drag Out to External Apps" for full spec.

#### Acceptance Criteria
- Existing users migrate safely.
- Imports/exports round-trip with mainstream browser bookmark files.
- Dragging a bookmark out of Cider onto a browser/Finder works as expected.

### Phase 5: Polish and Performance
1. ✅ Async thumbnail loading via `.task(id: fingerprint)` + `Task.detached` + `CGImageSourceCreateWithURL` — no main-thread image decoding during scroll.
2. ✅ `Bookmark.thumbnailFileURL` / `originalImageFileURL` use `StoragePaths.cachedCiderDataDirectoryURL` instead of per-access `CiderConfig.load()`.
3. Smarter thumbnail invalidation/retry policy.
4. Large-library performance pass (scrolling, filtering, search latency).

#### Acceptance Criteria
- ✅ Smooth interaction at high bookmark counts — async loading prevents scroll jank in masonry/grid.
- ✅ No layout jank in masonry during enrichment updates — `.task(id: fingerprint)` auto-cancels and re-fires on enrichment changes.
- Thumbnail memory/perf can be tuned without code changes (future settings toggle target).

#### Thumbnail Dimension Options (Documented for Future Settings)
These are intentionally documented as operational profiles for a future user-facing settings toggle:

- `720px` max dimension (current default): best visual quality, moderate memory use.
- `512px` max dimension: balanced quality/performance profile.
- `360px` max dimension: aggressive memory savings for very large libraries.

Potential settings UX:
- `High Quality (720)`
- `Balanced (512)`
- `Memory Saver (360)`

---

### Browser Companion Features

These features lean into Cider's unique position as a floating panel open alongside your browser. Rather than replacing the browser, Cider augments it — providing surfaces the browser doesn't have.

#### Live YouTube Transcript Sync

**Concept:** When a YouTube video is playing — either in Chrome or in Cider's built-in web view — Cider shows a live-scrolling transcript. Words/sentences highlight in real-time as the video plays.

**Two modes:**

*Chrome companion mode (future):*
- Detect YouTube tab in Chrome via the existing browser extension pattern
- Extension reads `video.currentTime` and sends playback state to Cider via local IPC
- Cider fetches captions and renders them in the panel alongside the browser

*In-app mode (closer, more feasible):*
- User opens a YouTube bookmark in the Web view tab of the detail panel
- Cider injects a `WKScriptMessageHandler` into the WKWebView
- JS polls `video.currentTime` every ~500ms and posts it back to Swift
- Cider fetches the caption track from YouTube's timedtext endpoint, extracts the URL from `ytInitialPlayerResponse.captions.playerCaptionsTracklistRenderer.captionTracks[*].baseUrl`
- Current line is highlighted in a transcript panel below or alongside the video
- Click any line → inject JS to seek: `document.querySelector('video').currentTime = timestamp`
- Transcript stored as a bookmark artifact on save

**Core experience (both modes):**
- Transcript scrolls automatically, highlighting the current sentence/word
- Click any line in the transcript → seeks the video to that timestamp
- Search within the transcript while the video plays
- Copy/highlight passages directly into Cider notes
- Transcript persists as a bookmark artifact — even after closing the video, you have the full text

**Open questions:**
- Should transcript auto-appear for YouTube bookmarks in web view, or require a manual "Show Transcript" button?
- Should transcripts be saved automatically with the bookmark, or only on explicit save?
- Support for other video platforms (Vimeo, Twitch VODs) — same pattern, different caption APIs?
- Could we generate transcripts via local Whisper for videos without captions?

---

#### Picture-in-Picture Video Player

**Concept:** When the bookmark detail panel is closed while a YouTube video is playing in the web view, instead of killing the audio, pop out the video into a small floating mini-player — like browsers' PiP mode. Put it back in the panel when you return to that bookmark.

**Core experience:**
- Video playing in web view → user closes the detail panel → Cider detects active video playback
- Small floating panel appears with the video still playing (no reload, no audio gap)
- User can dismiss the mini-player to stop the video entirely
- User opens the same YouTube bookmark → web view resumes from the mini-player seamlessly
- Timestamp is preserved throughout — the video state is never interrupted

**Why this fits:**
- Cider is already a floating panel app — a second floating mini-player is a natural extension
- Users already have the video in Cider's web view; PiP is a logical "continue watching while you do something else" action
- Much better UX than the current behavior (audio orphaned with no controls)

**Technical approach:**
- `BookmarkWebViewManager` singleton — owns `WKWebView` instances keyed by URL (same pattern as `NotesViewModel` owning the TipTap `WKWebView`)
- On panel close: detect `!video.paused` via JS injection. If playing, reparent the `WKWebView` (`NSView` subclass) into a new floating `NSPanel` instead of discarding it
- `NSView.addSubview()` reparents cleanly — the video process continues uninterrupted
- On panel reopen for the same bookmark: reparent the WKWebView back into the detail panel hero area
- Mini-player panel: borderless, floating level, resizable, shows only the video — no Cider chrome
- Dismiss button: calls `video.pause()` JS and closes the panel

**Timestamp persistence (prerequisite):**
- Before any navigation or close, inject JS to capture `video.currentTime`
- Store as `lastWatchedTimestamp: TimeInterval?` on the `Bookmark` model
- On reopen: use the YouTube `&t=Ns` URL parameter (more reliable than JS-seeking a React-managed player)
- Show a small "Resume from X:XX" indicator in the web view toolbar when a saved timestamp exists
- Minimum viable first version: timestamp persistence alone (no reparented mini-player) — close kills audio, but reopening resumes from where you left off

**Open questions:**
- Should PiP be automatic (always pop out when closing with video playing) or optional (ask once, configurable)?
- Should the mini-player appear adjacent to the main Cider panel, or freely positioned?

---

#### AI Page Summaries

**Concept:** Click "Summarize" in Cider and get an AI-generated summary of the page you're currently browsing. The summary lives in the panel alongside the page. Optionally save it as a bookmark annotation.

**Core experience:**
- User is browsing any webpage → clicks Summarize in Cider (or hotkey)
- Cider extracts the page content (via Chrome extension reading the DOM / Readability)
- Sends to AI for summarization → displays result in a summary card in the panel
- "Save" button captures the URL as a bookmark with the summary attached
- Summaries persist with bookmarks — when you revisit a saved bookmark, the summary is already there

**Why this fits Cider:**
- Cider already captures URLs and metadata — summaries are a natural enrichment layer
- The floating panel is the perfect surface for "glanceable info about the current page"
- Summaries become part of your bookmark library — searchable, browsable, organized in folders
- Doesn't require switching context — you stay on the page, summary appears alongside

**Variations:**
- **On-demand:** Click to summarize the current page (primary flow)
- **Auto-summary on bookmark:** When you capture a URL, optionally auto-generate a summary as metadata
- **Saved summary library:** Browse all your summaries in the bookmarks tab — effectively a personal knowledge base of everything you've read
- **Key points mode:** Bullet-point extraction instead of prose summary
- **Custom prompts:** "Summarize for a 5-year-old" / "Extract action items" / "What are the counterarguments?"

**Tiered approach — ship without AI, enhance with it:**

*Tier 0: Metadata extraction (no AI, ship first)*
- Pull `<meta name="description">`, Open Graph `og:description`, Twitter card description
- Extract `<h1>`–`<h3>` headings as a structural outline
- Grab the first paragraph of Readability-parsed article text
- This is already useful — most well-structured pages have human-written summaries in their metadata
- Costs nothing, runs instantly, works offline

*Tier 1: Extractive summarization (no AI, local algorithms)*
- TextRank — graph-based sentence ranking (like PageRank for sentences). Scores sentences by similarity to other sentences, picks top N. Works well on long articles, poorly on short/conversational pages.
- TF-IDF sentence scoring — rank by keyword density relative to the document. Picks sentences with the most "distinctive" terms.
- Apple NaturalLanguage framework — on-device tokenization, NER, sentence segmentation. Combine with TextRank for a fully local pipeline.
- Output: real sentences from the page (never "wrong"), but selection quality is mediocre and summaries feel choppy since they can't synthesize.

*Tier 2: AI summarization (optional, user-configured)*
- Apple Foundation Models framework (macOS 26+) — on-device LLM, no cloud dependency, no API costs, private by default. Best of both worlds.
- Cloud APIs (OpenAI, Anthropic, etc.) — higher quality for complex pages, but requires API key and sends content off-device.
- Local LLM (Ollama, llama.cpp) — power-user option, runs locally but needs model download.
- User chooses their provider in settings. Tier 0/1 is always available as fallback.

**Technical approach:**
- Chrome extension extracts page content (innerText or Readability-parsed article text)
- Sends to Cider via same IPC bridge as transcript sync
- Cider runs Tier 0 instantly, Tier 1 locally, Tier 2 on request
- Summary stored as a field on the Bookmark model (or as a linked Note)
- Summary card shows which tier generated it (metadata vs extractive vs AI)

**Open questions:**
- Should summaries be stored on the Bookmark model directly, or as linked Notes?
- Privacy: some users won't want page content sent to cloud APIs — local-first tiers solve this
- Could summaries update when a page changes (re-summarize stale bookmarks)?
- Should Tier 0 metadata extraction happen automatically on every bookmark capture?

---

#### Reader Mode

✅ **Implemented:** Clean distraction-free reading view inside the detail panel's hero area. Accessed via the `doc.richtext` toolbar button.

**Core experience:**
- Click `doc.richtext` in the detail panel toolbar
- Cider fetches the page content and runs it through a Readability parser (strip ads, nav, sidebars → extract article body)
- Clean article renders in the hero area — title, byline, body text, images
- Typography and spacing match Cider's design system
- Reader view can be scrolled; links open in system browser
- After article extraction, Foundation Models summary is triggered and saved to the bookmark (if no existing summary)

**Why this fits Cider:**
- Cider is already a reading companion — it saves links. Reader mode makes it a reading *tool*, not just a link repository.
- The floating panel is the perfect surface for focused reading alongside your browser
- Reader content can be saved as a permanent offline copy (see Web Archival below)
- Future integration with the Books tab — reader mode is the core reading experience for both web articles and longer-form content

**Technical approach:**
- ✅ `BookmarkReaderView.swift`: Swift fetches raw HTML via URLSession → `loadHTMLString` into WKWebView → Readability.js evaluated after `didFinish` → parsed JSON → styled HTML loaded in second pass
- Phase state machine (`loadingRaw` → `extracting` → `displaying` / `error`) prevents re-entrant extraction
- CSS in `Resources/ReaderMode/reader.css` — dark mode, `color-scheme: dark`, matches panel aesthetic

**Open questions / future:**
- Should reader content be cached locally for offline access?
- Support for multi-page articles (auto-pagination)?

---

#### Web Archival

**Concept:** Save a full snapshot of a web page locally so it survives if the original goes offline. The archived version is viewable inside Cider forever.

**Core experience:**
- Right-click a bookmark → "Archive Page" (or auto-archive on capture, configurable)
- Cider saves a complete snapshot of the page (HTML, CSS, images)
- Badge on the card indicates "Archived" — the bookmark is now immune to link rot
- Click to view the archived version inside Cider, even if the live URL is dead

**Technical approach:**
- `WKWebView.createWebArchiveData()` — macOS native API that saves a `.webarchive` bundle (HTML + all assets)
- Store alongside bookmark data in the Cider data directory (`.archives/{bookmark-id}.webarchive`)
- View archived pages in a WKWebView inside the detail popover or a dedicated viewer
- Storage could be significant — make archival opt-in per bookmark or per folder, with a storage indicator in Settings → Data

**Tiered approach:**
- *Tier 0:* Reader-mode text only (Readability-parsed article body saved as HTML/markdown — tiny, fast)
- *Tier 1:* Full `.webarchive` snapshot (complete page with styles and images — larger but faithful)
- *Tier 2:* Screenshot fallback (PNG of the rendered page — works for any page, even SPAs)

**Relationship to Documents tab:**
- Archived web pages could appear in the Documents tab as a "Web Archive" file type
- Or they stay attached to the bookmark as metadata — viewable via the bookmark's detail view

---

### Rich Media Capture

Extending image bookmarks beyond static images to support richer media types. Three tiers of increasing complexity:

#### GIF Support (Low Effort)

GIF bookmarks are nearly supported already — most of the pipeline handles them:

- Add `public.gif` to `BookmarksClipboardMonitor.imageTypes` array
- GIF stored as original in `.originals/{id}.gif`, thumbnail is first-frame PNG extracted via `CGImageSourceCreateThumbnailAtIndex` (already works with GIF sources)
- `normalizedImageFileExtension` already handles `.gif` → no storage path changes needed
- Also add GIF support to `CiderServicesProvider.sendImageToCider` for macOS Services integration
- Card display: static first-frame thumbnail (no animation in grid/masonry — animation would be distracting and memory-heavy)
- Optional future: play GIF on hover in detail popover or reader view

#### Video Bookmarks (Medium Effort, Clipboard Limitation)

Short video clips from Reddit, Instagram, TikTok, etc.:

- **Clipboard limitation:** Browsers don't put video data on the clipboard — only URLs. So clipboard capture can't grab video content directly.
- **Drag-drop of local files** is more feasible: accept `.mp4`/`.mov`/`.webm` drops onto bookmark cards (same pattern as image drops)
- Store short clips in `.originals/` with video thumbnail extraction via `AVAssetImageGenerator` (first frame or mid-point frame)
- **Card display:** Static thumbnail with play icon overlay — no inline video playback in grid/masonry
- **Playback:** Click to play in DetailPopoverPanel using `AVPlayerView` or embedded `WKWebView`
- **Storage implications:** Videos are orders of magnitude larger than images — needs size limits (e.g., 50MB max) or explicit opt-in
- **URL-based video bookmarks:** For Reddit/Instagram/TikTok URLs, could use yt-dlp or similar to download the video on capture — but this adds external dependencies and raises storage concerns

#### Multi-Image Bookmarks / Carousels (Larger Effort)

Instagram posts, product comparisons, design inspiration boards — content that's naturally multi-image:

- **Model change:** `thumbnailRelativePaths: [String]?` and `originalImageRelativePaths: [String]?` (arrays alongside existing single-image fields for backward compat)
- **Storage naming:** `{bookmarkID}_0.png`, `{bookmarkID}_1.png`, etc. in both `.thumbnails/` and `.originals/`
- **Card UI:** Carousel with dot indicators or horizontal swipe gesture. Cover image (first by default, user-selectable) shown in grid/masonry.
- **Drag-drop:** Accept multiple images in a single drop (currently stops after first image). Could also support dropping a folder of images.
- **Use cases:** Instagram posts, product comparison screenshots, design inspiration boards, step-by-step tutorials, before/after pairs
- **Migration:** Existing single-image bookmarks continue to work unchanged — array fields are optional and nil by default

---

### Clipboard Integration

The clipboard is a core capture flow for bookmarks, images, and text. Cider's clipboard system is a dedicated panel (Opt+V) that serves as both a capture gateway and a history viewer.

#### Current State

Standalone `ClipboardPanel` — a dedicated NSPanel that opens/closes independently via Opt+V. The Cider panel is never touched. Clipboard history is managed by `ClipboardHistoryService` and stored in `ClipboardStorage`.

#### Clipboard Viewer

Since Cider relies heavily on the clipboard for capturing bookmarks, images, and text, a dedicated clipboard viewer gives users a safety net — a way to see what's there and act on it when auto-capture misses something.

**V1 — Basic viewer:**

- Shows current clipboard contents in a scrollable feed: URLs, images, GIFs, text snippets, rich text, file references
- Single-column layout at default panel width; expands to multi-column when the panel is wider (same responsive pattern as masonry/grid)
- Each clipboard item has action buttons: "Save as Bookmark", "Save as Note", etc. — one click to route content to the right place
- Drag-and-drop from clipboard items to the library feed, folders in the sidebar, or specific tabs — same drag patterns as existing cards
- Clipboard history: show the last N items (macOS `NSPasteboard` tracks change count but not history natively — would need our own ring buffer, capturing snapshots on each `changeCount` increment)
- Accessible from the capture button area (popover or inline section) or as a dedicated tab

**Future — Privacy & safety:**

- App exclusion list: skip capturing clipboard changes from specific apps (password managers, banking apps, 1Password, etc.)
- Sensitive content detection: auto-redact or skip items that look like passwords, API keys, credit card numbers
- Configurable in Settings — off by default so the basic version ships without complexity
- Could also auto-expire clipboard history items after a configurable duration

#### Future Enhancements

##### Full Page Thumbnails

Rich preview cards for URLs with page screenshot, title, and description. Currently URL cards show favicon + domain name (fetched from Google's favicon API, cached to disk). The next step is full page thumbnails — requires hidden WKWebView rendering or an external screenshot API. Post-1.0 enhancement.

##### Toast-to-Clipboard Morphing

When something is copied, the capture toast shows a preview of the item. Hovering the toast expands/transitions it into the full clipboard panel with that item at the top. The toast becomes a gateway into clipboard history rather than just a notification.

**Flow:**
1. User copies something → small toast appears with item preview
2. Toast auto-dismisses after timeout (normal behavior)
3. If user hovers the toast → toast morphs/expands into the full clipboard panel
4. The copied item is highlighted at the top of the clipboard history
5. User can interact with clipboard history, copy other items, save to bookmarks/notes

**Design considerations:**
- Toast position should align with where the clipboard panel will appear
- Morphing animation: toast grows in place, content cross-fades from toast preview to full clipboard UI
- If clipboard panel is already open, toast should just flash the new item at the top instead of morphing

---

### Future Ideas

---

### Open Questions
- Should clipboard auto-capture default to review mode or instant-save mode?
- Should there be per-site metadata adapters for high-value domains?
- What is the preferred UX for failed/blocked thumbnail fetches (badge vs details warning)?

### Known Issues — Content Capture
- ~~**Opt+B hotkey only works in Chrome**~~ — Resolved. `ActiveBrowserCaptureService` now supports Chrome, Arc, Safari, Dia, Zen, Comet, Firefox, and other browsers via per-browser AppleScript/JXA paths.
- **Reader view right-click thumbnail** — Allow right-clicking an image in the reader/browser view and setting it as the bookmark's thumbnail (noted above in detail panel actions).
- **Reddit image CDN** — `external-preview.redd.it` returns HTTP 403 on direct download (hotlink protection). No known workaround — users can drag replacement thumbnails from the browser.
- **Instagram oEmbed deprecated** — Meta deprecated `api.instagram.com/oembed` (2025). Falls through to WebView/screenshot, which captures login wall. Would need Graph API credentials for real support.

---


## HOME Vision


The Home tab is the library — the unified view of all Cider content. A sticky "Continue" section for recent items, then a scrollable mixed-content feed below with display mode switching.

---

### Current State (Implemented)

#### Continue Section

- Sticky two-column list of the 8 most recent items (mixed bookmarks + notes), sorted by date
- Left column: items 0-3 (most recent), right column: items 4-7
- At compact width (content area &lt; 700pt), right column hides — only left column's 4 items shown
- Threshold set high enough that sidebar auto-hiding (\~200pt freed) doesn't cause column flicker
- Collapse toggle lives in the title bar (right-aligned, away from tabs) — no wasted vertical space when collapsed
- Collapsed state persisted in CiderConfig
- Hideable via `showContinueSection` setting
- Always shows global recents regardless of folder selection
- Rows are draggable (single-item drag to folders) with hover highlight
- No divider between Continue and library feed — the visual shift from compact rows to cards is sufficient separation

#### Library Feed

- Scrollable mixed-content feed of all library items (bookmarks, notes, date cards, contacts), sorted by date
- Filters by folder when one is selected in the sidebar (folder filtering applies to bookmarks + notes; date cards and contacts are global)
- Display mode switching: list / grid / masonry (same ViewOptionsDropdown as Bookmarks/Notes)
- Continuous card size slider (0-3 scale) via LibraryCardSizing
- List mode is the default — mixed content reads better as a uniform list
- Reuses existing card components: BookmarkCard, BookmarkListRow, NoteCardView, NoteListRow, DateCardCardView, ContactCardCardView
- Scrollbars hidden — consistent with the rest of the app (no visible scroll indicators anywhere)
- Surfaced stacks appear in the feed when their rules trigger (see Stacks section below)

#### Architecture

- `LibraryItemV2` discriminated union: `.bookmark(Bookmark)` / `.note(Note)` / `.dateCard(DateCard)` / `.contact(ContactCard)` / `.todo(TodoCard)` / `.externalFile(ExternalFile)` / `.vaultFile(VaultFile)` / `.session(BrowserSession)` — all entity types flow through a single unified feed
- `LibraryItemV2.dateAnchor: Date?` — the key property for calendar projection; dateCards use `startAt`, contacts use `birthday`, todos use `earliestApproachingDate`, others have nil
- `LibraryItemV2.isCompleted: Bool` — meaningful for dateCards and todos; used by surfacing rules like `pinUntilDone`
- `LibraryViewModel` — unified query engine reading from all storages; produces filtered feeds, calendar buckets, and stack resolutions; rebuilds on any storage change
- `LibraryViewModel.recentItems` — pre-sorted top 8 by `updatedDate`, computed in `rebuildItems()` so Home body doesn't sort on every render
- `LibraryDisplayMode` enum conforming to `DisplayModeOption` — plugs into ViewOptionsDropdown
- `LibraryCardSizing` struct with 4-stop interpolation, produces `bookmarkSizing` and `noteSizing` for downstream components
- View state (display mode, card size, continue collapsed) persisted in CiderConfig
- Display mode and card size controlled by CiderPanelView via bindings, persisted on change

#### Performance

- **Home kept alive across tab switches** — `HomeDashboardView` stays in the view tree via ZStack + opacity/allowsHitTesting, so thumbnails, card data, and scroll position persist when switching to other tabs. Other tabs (saved views, search) create/destroy on demand.
- **Async image loading** — All card thumbnails (bookmarks, notes, contacts) load via `Task.detached` + `CGImageSource` to prevent main-thread blocking during scroll.
- **No `CiderConfig.load()` in body** — `HomeDashboardView` uses `@State config` and `StoragePaths` cached paths instead of decoding UserDefaults on every render.

#### Sidebar Changes

- "All Items" row removed from FolderSidebarView — sidebar is purely organizational (folders only)
- Home tab serves as "All Items" — want to see everything? Click Home.
- Folder selection on Home tab filters the library feed (not the Continue section)

#### Mental Model

| Surface | Shows |
| --- | --- |
| **Home tab** | Everything, mixed. Your library. |
| **Saved view tab** | User-defined filter: any combination of types, labels, folders — replaces the old fixed Bookmarks and Notes tabs |
| **Custom saved-view tab** | User-defined filter: any combination of types, labels, folders |
| **Sidebar folders** | Standalone mixed-content card view (independent of tabs) |

#### Stacks

Stacks are first-class query objects that surface in the library feed when their rules trigger. They are **not containers** — they reference items dynamically by rules (label match, entity type, date range) and/or manual refs.

- A stack shows as a single stacked card in the feed with a count badge and top-card preview
- Click → modal showing all matched items, sorted by attention score or time (user-toggleable)
- Surfacing is rule-driven: `pinUntilDone`, `surfaceDaysBeforeDate(N)`, `remindBeforeMinutes(N)`
- A stack surfaces when: `isPinned` OR any enabled surface rule is triggered
- Built-in templates: **Bills** (pin until paid, surface 7 days before due), **Birthdays** (surface 14 days before), **Schedule** (remind 30min before)
- "Hide for me" (session-local dismiss) and "Mark done" (completion) are distinct actions — never conflate them
- Max 5 pinned stacks is a good practical limit; optional, not enforced in code
- Bills stack modal shows a summary panel: total amount, paid amount, remaining, next due date

#### Saved Views / Custom Tabs

Saved views let users define their own tabs: a named filter + sort + layout configuration that pins to the tab bar. The calendar is a **view mode within a saved view**, not a separate tab.

- Saved views store: filter spec (entity types, labels, folder, completed status, text query), sort spec, layout spec (list/grid/masonry + calendar projection toggle)
- `isTabPinned: Bool` controls whether the saved view appears in the tab bar
- Creating a saved view: build a filter in the feed → "Save as Tab" → names the tab
- Calendar projection is a toggle on any saved view — it groups the filtered items by `dateAnchor` into a month/week grid
- Ghost day cells (empty days rendered as dashed placeholders) are toggleable; clicking one pre-fills the DateCard editor with that date
- Example flows: "Bills" tab = date cards filtered by Bills label + calendar; "Kids Sports" tab = schedule stack + calendar; "My Girlfriend's Events" tab = her person label + time sort

#### Product Philosophy

**"Time is metadata. Importance is the UI."**

Traditional calendars make time the primary axis — every day gets equal visual weight regardless of whether anything is happening. Cider's approach: time is just metadata on a card. The feed surfaces cards by *relevance* (rules, pins, surfacing logic), not purely by chronology. Ghost day cells in the calendar view reinforce this — you immediately see how many days actually matter vs. how many are empty.

**"Calendar without calendar anxiety"** — the grid exists, but it's calm. Density is controlled. Empty days are visually lightweight. Filters apply everywhere. The calendar isn't a separate mode; it's a lens on your library.

#### Click Behavior

- **Bookmark card click** → Opens bookmark detail modal within the Home view (not tab switch)
- **Note card click** → Opens inline note editor within the main panel (push/pop navigation — editor takes over the content area, title bar shows note title + back button)

  - Press Escape or click the back arrow to return to the previous view
  - Auto-save flushes on editor close
- **Rejected approach:** Tab-switching on click (loses scroll position, feels disruptive)
- **Previous approach (removed):** Standalone notes panel with modal click-outside-to-dismiss — replaced by inline editor in Feb 2026 panel consolidation

### Planned: Sorting Options

Sort controls in ViewOptionsDropdown for the Home library feed:

- Sort by: creation date, recently modified, title A-Z
- Ascending/descending toggle
- Persisted in CiderConfig as `homeSort` preference
- Currently the feed sorts by `createdDate` descending — this becomes configurable

---

### Implemented: Date Card Surfacing (F-05)

Date cards with approaching dates are visually surfaced so users don't miss important dates.

#### Current State

- **`DateCardUrgency` enum** on `DateCard` model: `.approaching(daysUntil:)`, `.today`, `.overdue` — computed via `urgency(now:windowDays:)`
- **Visual indicators:** Date block (month + day) tints by urgency (red = overdue, yellow = today, accent = approaching). Urgency badge pill on cards and list rows ("Overdue", "Today", "In N days")
- **"Coming Up" section** on Home/Inbox tab: horizontal scroll of compact date card cards between Continue section and library feed. Sorted by `startAt` (most urgent first). Hidden when empty.
- **Configuration:** `CiderConfig.dateCardSurfacingDays: Int` (default 7). Set to 0 to disable.
- **All render sites:** Home/Inbox, Folder detail view, Saved View tabs — all pass urgency through.
- Completed date cards never show urgency indicators or appear in Coming Up.

#### Future Enhancements (Post-Beta)

- **Per-view "Coming Up" toggle:** Let users show/hide the Coming Up section per saved view tab, not just globally. Some tabs (e.g., a "Bills" tab) might always want it; others (e.g., a "Notes" tab) never do.
- **Notification / sidebar surfacing settings:** Dedicated settings section for Coming Up behavior — configure surfacing window per entity type, enable/disable sidebar badge counts for approaching items, optional system notification for Today/Overdue items.
- **Per-card surfacing override:** `DateCard.rules: [SurfacingRule]` already stores `surfaceDaysBeforeDate(N)` — evaluate it to override the global default per card (e.g., birthdays surface 14 days ahead, bills 7 days).
- **Recurring event surfacing:** Evaluate `DateCardRecurrenceRule` to compute the next occurrence date from today, and use that for urgency instead of the raw `startAt`. Birthdays, bills, and other recurring events would automatically resurface in Coming Up each cycle.
- **Hybrid sort mode:** Library feed sort that promotes approaching date cards above the normal sort order, with non-promoted items following the user's chosen sort.
- **Continue section integration:** Optionally include surfaced date cards in the Continue section (top 8 recents) alongside recent items.

### Date Card Lifecycle & Event Visibility

Date cards are calendar-linked items — events, reminders, deadlines, and recurring dates. They bridge the gap between a full calendar app and simple task management by treating dates as cards in your library.

#### Storage

Date cards are stored as standard `.ics` files (iCalendar VEVENT, RFC 5545). See `Docs/Architecture/STORAGE.md` for the full spec.

#### Problem: Library Clutter from Past Events

One-off events like "Dentist" become dead weight after they pass. In a card-based library, past events clutter the feed and push active content down. Recurring events don't have this problem — they always have a next occurrence.

#### Solution: Smart Visibility Rules

**Default library behavior:**
- Hide events that are **completed AND non-recurring** from the Home/library feed
- Overdue uncompleted events stay visible (they're actionable — user forgot or hasn't dealt with them)
- Recurring events always visible (next occurrence is relevant)

**Event-specific views:**
- A saved view filtered to date cards shows ALL events — past, completed, everything
- This is an intentional "show me my events" action, so no filtering

**Per-event auto-expiration (optional):**
- Individual events can opt into auto-trash: "Delete X days after event date"
- Perfect for throwaway events (dentist, package delivery, one-time reminders)
- User explicitly enables this per card — nothing disappears without consent

#### Key Principle

Overdue events should NAG, not hide. Auto-completing past events would mask things the user forgot about. The user must manually mark an event complete to dismiss it from the feed.

#### Calendar View (Future)

A calendar view built around the user's events, with "ghost cards" filling in days without items. Not a full-blown calendar app — just a date-oriented way to browse your cards.

- Events are shown in context of their date (past events aren't clutter here, they're historical)
- Overdue uncompleted events get prominent visual treatment (red badge, overdue indicator)
- Ghost cards on empty days keep the visual rhythm and invite the user to add events
- Ties into the existing `DateCard.urgency()` system for surfacing approaching dates

#### Date Card Ideas / Backlog

- Drag `.ics` files into Cider to import events from other calendar apps
- Export/share events as `.ics` (already possible — just share the file from Finder)
- Calendar widget in the Home tab showing upcoming events
- Integration with system Calendar.app via EventKit (read-only sync)

---

### Planned: Resurfacing & Rediscovery

Items you save shouldn't disappear into a void. Cider should proactively surface items you've forgotten about — not by age alone, but by actual engagement.

#### The Problem with "Sort by Oldest"

Sorting by oldest doesn't surface forgotten items — it surfaces items you may have seen many times. A bookmark created a year ago that you've opened 10 times isn't forgotten. A bookmark created 9 months ago that you've never opened IS forgotten. The sort order can't distinguish these.

#### Engagement-Based Resurfacing

Track lightweight engagement signals per item:
- **`lastOpenedAt: Date?`** — last time the user clicked/opened the item (nil = never opened)
- **`openCount: Int`** — total number of opens

The resurfacing algorithm prioritizes items with:
1. **Never opened** (`lastOpenedAt == nil`) — highest priority, sorted oldest first
2. **Not opened recently** (`lastOpenedAt` is far in the past) — weighted by staleness
3. **Low open count** — items opened once 6 months ago rank higher than items opened 10 times

**Scoring formula (conceptual):**
```
resurfaceScore = daysSinceLastOpen * (1 / (openCount + 1))
```
Items with high scores are good candidates for resurfacing. Never-opened items get `daysSinceLastOpen = daysSinceCreation` and `openCount = 0`, giving them the highest scores.

#### Resurfacing as a Saved View

Resurfacing is not a built-in mode — it's a **saved view filter dimension** that users opt into:
- Add `sortMode: .resurfacing` to `LibrarySortMode` — sorts by resurface score descending
- Users create a saved view called "Rediscover" with this sort mode
- The view shows their most-forgotten items in the familiar card layout
- Optionally limit to items older than N days (skip very recent captures)

#### Resurfacing in the Continue Section

Alternatively (or additionally), the Continue section on Home could mix in 1-2 resurfaced items alongside the 8 most recent. A subtle "You saved this 6 months ago" label distinguishes them from recents.

#### AI-Enhanced Discovery

With Apple Intelligence (see `Docs/Features/AI.md`):
- **Similar items** — when viewing a bookmark, Cider suggests related items via NaturalLanguage embedding similarity. "You might also want to revisit these."
- **Contextual resurfacing** — AI notices you're saving React articles and surfaces that React tutorial you bookmarked 8 months ago but never opened
- These suggestions could appear in the detail popover, as a sidebar section, or as cards in the Resurfacing saved view

#### Model Changes Required
- Add `lastOpenedAt: Date?` and `openCount: Int` to `Bookmark` and `Note` models
- Increment on every open action (`BookmarksViewModel.open()`, `NotesViewModel` note open)
- Add `resurfacing` case to `LibrarySortMode`
- Add resurfacing score computation to `LibraryViewModel`

---

### Future Ideas (Not Yet Prioritized)

- Pinned items section (show pinned notes/bookmarks at the top)
- Today's activity summary
- Folder quick-nav (jump to frequently used folders)
- Search shortcut / recent searches
- Customizable widget layout (choose which sections appear)
- Streak / activity indicators
- Quick-capture inline text field (type and hit enter to create a note or bookmark)

#### AI GIF Finder (Requires AI + OCR)

A contextual GIF search tool powered by AI. Instead of guessing keywords in Discord/iMessage/Slack's built-in GIF search, screenshot any conversation and let AI find the perfect reaction GIF.

**Flow:** Screenshot a conversation (using Cider's planned OCR/capture features) → AI reads the context and tone → generates smart search queries → hits GIPHY/Tenor APIs → returns ranked results in a panel → click to copy, paste into any chat app.

**Why it fits Cider:** Cider is already a floating panel open while browsing, and OCR/screenshot capture is planned. This makes it app-agnostic — works with any chat platform since it reads from screenshots, not platform APIs. Results could also be saved to the Whiteboard as image blocks.

**The value is in tone detection:** AI understands that "sure, that's fine" is passive-aggressive and returns the right GIF, not a literal thumbs up. Built-in GIF search can't do this because it's keyword-only.

Full concept doc: `~/Documents/GifGenius-App-Concept.md`

#### Recipe Capture (Requires AI + OCR + Bookmark Pipeline)

Automatically extract structured recipe data from saved content — TikTok links, Instagram posts, screenshots of recipe cards, photos of cookbooks, or any URL. Turns unstructured "I saved this for later" into a clean, searchable recipe with ingredients and steps.

**Capture flows:**

- **URL capture (TikTok, Instagram, YouTube, blogs):** Save a link as a bookmark → AI enrichment pipeline detects recipe content → extracts title, ingredients list, and step-by-step instructions from the page/video description. For video-only recipes (TikTok/Reels with no written recipe), use captions/transcript if available.
- **OCR capture (screenshots, photos):** Screenshot a recipe from any app, or photograph a cookbook page → existing OCR pipeline (`OCRService`) extracts text → AI parses the raw text into structured recipe fields (title, servings, ingredients, steps, cook time).
- **Manual entry:** Quick-capture a recipe inline with a structured template (title, ingredients, steps) for recipes dictated by a friend or remembered from memory.

**Structured recipe data model:**

- `title: String` — recipe name
- `servings: String?` — yield (e.g., "4 servings", "12 cookies")
- `prepTime: String?` / `cookTime: String?`
- `ingredients: [String]` — ingredient list, preserving order
- `steps: [String]` — numbered instructions
- `sourceURL: URL?` — original link if captured from a URL
- `sourceImage: Data?` — original screenshot/photo if captured via OCR
- `tags: [String]` — auto-generated from AI (cuisine type, dietary info, meal type)

**Why it fits Cider:** Recipes are one of the most common "save for later" items that get lost in bookmarks, screenshots, and saved posts. Cider already has the capture pipeline (bookmarks + OCR), AI enrichment (NLP + embeddings), and card-based browsing. A recipe is just a bookmark with structured metadata extracted by AI. Recipes would surface naturally in the library feed, be taggable with labels, and work with stacks (e.g., a "Meal Planning" stack, a "Quick Weeknight Dinners" saved view).

**Integration with existing systems:**

- Stored as a bookmark with a `recipeData` metadata extension — not a new entity type
- Reader Mode could render a clean recipe view (ingredients sidebar + steps) instead of the raw article
- Dominant color extraction from food photos for visual browsing in grid/masonry
- NLEmbedding vectors enable "similar recipes" suggestions
- Stacks and labels work out of the box (label recipes by cuisine, meal type, or occasion)

**Stretch goals:**

- Grocery list generation from selected recipes (aggregate ingredients, deduplicate)
- Serving size scaling (multiply/divide ingredient quantities)
- Cooking mode: step-by-step view with large text, optimized for kitchen use (keep-awake, tap to advance)
- Import/export as standard recipe formats (e.g., Recipe JSON-LD, Paprika `.paprikarecipes`)
---


## KANBAN Vision

> Status: historical product/roadmap context. The current Kanban source of truth lives in `Docs/Features/Kanban/` and the active board YAML files under `/Users/minivish/CiderVault/.cider/boards/`.

### Concept

A file-backed Kanban board in Cider where both the user and AI agents can read and write to the same board. The visual lives in Cider, the data lives on disk as a YAML file in the vault.

Two surfaces, two purposes:
1. **Projects tab** — standalone Kanban boards with typed-in cards. For planning, project tracking, and agent workflows. Cards are their own thing — not bookmarks or notes.
2. **Folder Kanban view** (phase 2) — any folder can toggle to a Kanban view. Existing items in the folder (bookmarks, notes, todos, etc.) become the cards. For organizing existing content through stages.

### How it works

**User → Cider UI:**
- Drag a card from Todo → In Progress
- Cider writes that change to the YAML file on disk

**Agent → YAML file:**
- Agent reads the YAML, sees what's In Progress
- Builds the feature
- Moves the card to Testing
- Cider reflects it instantly

### Projects Tab (Phase 1)

Standalone boards that live in the Projects tab. Cards are simple — a title, optional notes, optional color/priority. You type in items, drag them between columns. No connection to bookmarks, notes, or todos.

**Use cases:**
- "Cider Roadmap" — plan features through backlog → in progress → done
- "Apartment Hunting" — track places through found → toured → applied → rejected/accepted
- "Recipe Ideas" — save ideas through want to try → tried → loved it / meh
- Agent task boards — agent picks up cards, moves them through stages

**Cards are NOT todos.** Todos are personal reminders that live as cards in the library. Kanban cards are project tracking items. They look similar but serve different purposes. A bridge between them (send todo to kanban, create todo from card) can be added later if needed — not designed upfront.

### Folder Kanban View (Phase 2)

Any folder can switch to Kanban view. The bookmarks, notes, todos, and other items already in the folder become the cards. You drag them between columns. The column assignment is stored as metadata on the item (or in the folder's YAML).

**Use cases:**
- Restaurant folder: bookmarks for places → columns: want to try, tried, loved, didn't like
- Reading list folder: bookmarks → to read, reading, finished
- Project research folder: notes + bookmarks → gathering, reviewing, referenced

### File format: YAML

YAML hits the sweet spot:
- Human readable — power users can edit directly
- Structured enough to render a proper visual Kanban
- AI can easily read and update — "move X to done" is trivial
- Git diffs are clean and meaningful
- Extends easily — add priority, tags, notes per card without breaking anything

Each board is one `.yaml` file in the vault under `.cider/boards/`.

### Data Model

```yaml
board: Cider Roadmap
created: 2026-03-20
columns:
  - name: Backlog
    id: backlog
    cards:
      - id: abc123
        title: Bulk Operations
        notes: Multi-select mode + bulk actions bar
        color: blue
        created: 2026-03-20

  - name: In Progress
    id: in_progress
    cards:
      - id: def456
        title: Search result highlighting
        notes: ""
        agent: web-agent
        created: 2026-03-18

  - name: Testing
    id: testing
    cards:
      - id: ghi789
        title: Share Extension fixes
        created: 2026-03-15

  - name: Done
    id: done
    cards:
      - id: jkl012
        title: Tag management
        completed: 2026-03-17
        created: 2026-03-10
```

#### Card fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | String | Yes | Short unique ID (auto-generated) |
| title | String | Yes | Card title |
| notes | String | No | Freeform notes/description |
| color | String | No | Card color accent (blue, green, orange, red, purple) |
| agent | String | No | Assigned AI agent name |
| created | Date | Yes | When the card was created |
| completed | Date | No | When moved to a "done" column |
| priority | String | No | low, medium, high |
| tags | [String] | No | Optional tags for filtering |

#### Column fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| name | String | Yes | Display name |
| id | String | Yes | Slug identifier (used in YAML keys) |
| cards | [Card] | Yes | Ordered list of cards in this column |

### Agent rules

Agents could have a rule: "before starting work, read kanban.yaml and only work on cards assigned to you in in_progress. When done, move your card to testing."

Combined with a daily briefing, the agent wakes up, reads the Kanban, knows exactly what to do, and documents its own progress.

### Why this matters

- No Jira, no Notion, no Linear — just a YAML file and Cider
- Self-updating project board that both user and agents read/write simultaneously
- Fits Cider's open file format philosophy perfectly
- Columns are fully customizable (user creates whatever columns they want)
- Syncs across devices via the vault (same as bookmarks/notes)

### Implementation Plan

#### Phase 1: Projects Tab (standalone boards)
1. **Data model** — KanbanBoard, KanbanColumn, KanbanCard structs + YAML parsing
2. **Storage service** — read/write/watch YAML files in `.cider/boards/`
3. **ViewModel** — board state, card CRUD, drag-and-drop column moves
4. **Board list view** — shows all boards, create new, delete
5. **Board view** — horizontal scrolling columns with cards, drag-and-drop
6. **Card detail** — edit title, notes, color, priority inline or in popover

#### Phase 2: Folder Kanban View
7. **Folder view mode toggle** — switch between list/grid/kanban
8. **Column assignment** — store which column each item belongs to
9. **Mixed item cards** — render bookmarks, notes, todos as kanban cards with type indicators

### Status

Phase 1 (Projects Tab) is implemented. Kanban boards, cards, columns, drag-and-drop, board picker, card filtering, and compact view are shipped. Phase 2 (Folder Kanban View) is implemented — `FolderKanbanView` is wired into `FolderDetailView` as a `.kanban` display mode, backed by `FolderKanbanStorage`.

---


## LINKED SOURCES Vision


> Cider can watch external filesystem directories and surface their `.md` files alongside native content. The primary use case is dogfooding — pointing Cider at its own `Docs/` folder to browse and edit project docs live. The broader use case is making Cider a first-class `.md` editor/viewer for any folder on your system.
>
> **Confirmed use case (Feb 2026):** Link your project's `Docs/` folder to monitor agent activity at a glance — whichever file an agent last touched floats to the top of the list automatically.

**Status:** ✅ Implemented (Feb 2026)

---

### Concept

A **Linked Source** is an external filesystem directory that Cider watches. Files inside it appear in Cider as if they were native content — in the library feed, in the sidebar, as a tab — but Cider doesn't own them. Edits save back to the original file in place. No copying, no importing, no syncing.

This is different from the primary notes directory:

- **Notes directory** — Cider owns these files. It creates, moves, and manages them.
- **Linked Source** — Cider watches and reads these files. The filesystem owns them.

---

### Three Surfaces

A Linked Source can appear in three places, independently toggled:

#### 1\. Sidebar — Permanent

A "Sources" section in the sidebar (below Projects) lists all pinned sources. Clicking a source opens a detail view of its `.md` files — same card layout as FolderDetailView. Right-click to configure, rename, or remove.

This is the permanent home. Even if the tab is closed, the source is still there.

```
FOLDERS
  Design Resources
  Work
```

`PROJECTS
New Website`

`SOURCES                       ← new section
📂 Cider Docs
📂 Personal Notes`

#### 2\. Tab — Focused / Temporary

A source can be pinned as a tab in the tab bar (same `isTabPinned` pattern as SavedViews). This gives you a dedicated tab showing just that source's files. Close the tab, the source stays in the sidebar.

```
[Home] [📂 Cider Docs ×]
```

#### 3\. Library — Ambient

When `showInLibrary` is enabled for a source, its files appear in the Home library feed alongside bookmarks, notes, date cards, and contacts. A small footer indicator shows which source the file belongs to (e.g., "Cider Docs"). A filter chip in the library lets you show/hide external files globally.

These three surfaces are not mutually exclusive — a source can be in all three at once.

---

### Data Model

#### ExternalSource

```swift
struct ExternalSource: Codable, Identifiable {
var id: UUID
var path: String               // absolute filesystem path
var displayName: String        // user-facing name (defaults to folder name)
var showInSidebar: Bool        // appears in sidebar Sources section
var isTabPinned: Bool          // appears as a tab in the tab bar
var showInLibrary: Bool        // files appear in Home library feed
var createdAt: Date
}
```

Persisted in `cider_sources.json` *in the bookmarks root (alongside other storage JSON files).*

#### *ExternalFile*

```
struct ExternalFile: Identifiable {
var id: UUID                   // deterministic UUID derived from file path (stable, no storage needed)
var title: String              // filename without extension
var path: URL                  // absolute path to the .md file
var sourceID: UUID             // which ExternalSource this belongs to
var sourceName: String         // display name of the source (for footer indicator)
var createdAt: Date            // from filesystem attributes
var modifiedAt: Date           // from filesystem attributes
// content is lazy-loaded from disk, same pattern as NotesStorage.loadContent(for:)
}
```

*Identity is derived from the file path — no UUIDs stored anywhere. If a file moves, it's treated as a new item (same behavior as any file editor).*

#### *LibraryItemV2*

*Add a new case:*

```
case externalFile(ExternalFile)
```

`dateAnchor` *→* `modifiedAt` *(for sorting in the library feed)*`isCompleted` *→ always* `false`

---

### *File Operations*

| Action | Behavior |
| --- | --- |
| Open | Opens in the same TipTap editor as native notes (via `NotesViewModel.openExternalFile`). Right-click → "Open in Default App" to launch in an external editor instead. |
| Edit | Saves back to the original file path in place |
| Create new file | Creates a new `.md` file in the source directory |
| Delete | Moves to **system Trash** (not Cider's trash — we don't own the file) |
| Move to folder | Not applicable — external files stay in their source directory |

---

### *Adding a Source*

*Three entry points:*

1. ***"Add Source" button*** *in the sidebar Sources section header →* `NSOpenPanel` *folder picker*
2. ***Drag a folder*** *onto the Cider sidebar or icon*
3. ***AppDelegate*** `application(:open:)` — when Cider is set as the default app for `.md` files and a folder is opened via Finder

macOS file type registration (`Info.plist`) allows setting Cider as the default opener for `.md` and optionally `.txt` files.

---

### Filesystem Watching

Each linked source gets a filesystem watcher (same `FSEventStream` / `DispatchSourceFileSystemObject` pattern as the existing notes watcher). On change:

1. Re-scan the directory
2. Diff against current file list
3. Update `LibraryViewModel` — new files appear, removed files disappear, modified files refresh

Supports live updates — edits by external tools (agents, editors) appear in Cider automatically.

**Supported file types (v1):** `.md` only. Hidden files and non-text files are ignored.

---

### UI Details

#### Source Card in Library

Same card treatment as `NoteCardView` — content preview, title, date. Footer shows:

```
📂 Cider Docs  ·  Modified 2 hours ago
```

#### Source Detail View (sidebar click)

Same layout as `FolderDetailView`:

- Header with source name, file count, path
- Card grid of all `.md` files in the directory
- Supports all display modes (list, grid, masonry)
- Sorted by modified date by default
- Sort reflects **external** modification only — opening a file in Cider does not bump its mtime

#### Library Filter

ViewOptionsDropdown gets an "External Files" toggle. When off, `LibraryViewModel` excludes `externalFile` items from the feed.

#### Sidebar Source Row

```
📂 Cider Docs       12 files
```

Right-click context menu:

- Show in Library (toggle)
- Pin as Tab (toggle)
- Rename
- Open in Finder
- Remove Source

---

### Architecture

#### New Files

- `Sources/Cider/Models/ExternalSource.swift`
- `Sources/Cider/Models/ExternalFile.swift`
- `Sources/Cider/Services/ExternalSourceStorage.swift` — CRUD + persistence for sources
- `Sources/Cider/Services/ExternalSourceScanner.swift` — scans directory, watches for changes, produces `[ExternalFile]`
- `Sources/Cider/Views/Sources/SourceDetailView.swift` — detail view for a source (like FolderDetailView)
- `Sources/Cider/Views/Sources/SourceCardView.swift` — card for external files in library

#### Modified Files

- `Sources/Cider/Models/LibraryItemV2.swift` — add `.externalFile(ExternalFile)` case
- `Sources/Cider/ViewModels/LibraryViewModel.swift` — aggregate external files from all sources
- `Sources/Cider/Views/Shared/FolderSidebarView.swift` — add Sources section
- `Sources/Cider/Views/CiderPanelView.swift` — handle source tab content
- `Sources/Cider/Views/Shared/CiderTabBar.swift` — render source tabs
- `Sources/Cider/Views/Home/HomeDashboardView.swift` — filter chip for external files
- `Sources/Cider/App/AppDelegate.swift` — `application(_:open:)` handler
- `Sources/Cider/Models/CiderConfig.swift` — no new fields needed (sources stored in own JSON)
- `Info.plist` — register `.md` file type association

#### Does NOT Touch

- `NotesStorage` — external files are a separate concern
- `TipTapEditorView` — already opens any file path, works as-is
- `TrashStorage` — external files use system Trash, not Cider trash

> **Note:** `NotesViewModel` IS touched — it owns `activeExternalFile` and `openExternalFile()`. External files open in the same TipTap editor as native notes, branching at save time to write back to the source path instead of NotesStorage.

---

### Implementation Phases

#### Phase 1 — Model + Storage

- `ExternalSource` model and `ExternalSourceStorage`
- `ExternalFile` model with path-derived identity
- `cider_sources.json` *persistence*

#### *Phase 2 — File Scanning + Watching*

- `ExternalSourceScanner` *— directory scan, FSEventStream watching, produces* `[ExternalFile]`
- *Live update on file changes*

#### *Phase 3 — Sidebar*

- *Sources section in* `FolderSidebarView`
- `SourceDetailView` *— browse a source's files*
- *Add Source via folder picker*
- *Context menu: configure, rename, remove*

#### *Phase 4 — Library Integration*

- `.externalFile` *case in* `LibraryItemV2`
- `LibraryViewModel` *reads from all active sources*
- *Source footer indicator on cards*
- *Library filter toggle for external files*

#### *Phase 5 — Tab Support*

- *Source tabs in* `CiderTabBar`
- *Source tab content in* `CiderPanelView`
- `isTabPinned` *toggled from sidebar context menu*

#### *Phase 6 — File Open Handler*

- `AppDelegate.application(:open:)` — handle files and folders from Finder
- Drag folder onto sidebar or icon → add as source
- `Info.plist` `.md` file type registration
- "Open With Cider" from Finder context menu

---

### Future Ideas

#### Sidebar Header Navigation Targets

Clicking the section text in sidebar headers (e.g. "Sources", "Folders") could navigate to dedicated overview views:

- **"All Sources" overview** — all linked sources as cards, each showing name, path, file count, last modified date, and a preview of recent files.
- **"All Folders" overview** — all folders as a grid with cover images, item counts, and last updated dates.

Neither exists yet because the sidebar already serves as navigation. These become valuable if users accumulate many sources/folders and want a visual overview in the main content area rather than scrolling the sidebar. Low priority — add when a real use case emerges.

#### Source View Options (Display Modes)

Source detail views currently don't respond well to view option changes (grid, masonry, list). Source cards need the same display mode treatment as bookmarks and notes — especially list view, which needs standardization across all card types. This is part of a broader list view overhaul (see below).

#### List View Standardization

List view needs significant work across ALL card types (bookmarks, notes, contacts, todos, date cards, sources). Each type currently has inconsistent list row layouts. Need a shared `ListRowContainer` pattern with consistent column alignment, hover states, and density. This is a cross-cutting UI task, not source-specific.

#### Diff View — Changes Since Last Opened

Show what changed in a file since you last viewed it in Cider. Effort: **\~1.5 days**.

**How it would work:**

1. **Snapshot storage** — when a file is closed, save its content (keyed by `ExternalFile.stableID`) to a small JSON store in Cider's data directory. No size limit concern; these are `.md` files.
2. **Diff on open** — on next open, load the snapshot and compute a line-level diff using Swift's `CollectionDifference`. Produces a list of added/unchanged/removed lines.
3. **TipTap rendering** — a custom TipTap extension that decorates paragraphs with `data-diff="added"` / `data-diff="removed"` background marks. Added lines get a subtle green tint, removed lines shown as struck-through or in a ghost color. A "Dismiss diff" button in the toolbar clears the marks.

**The hard part** is the TipTap JS integration — the decoration API is straightforward but requires care to not interfere with normal editing. A simpler v1 could skip TipTap integration entirely and show a read-only diff panel *before* opening the editor (like a "what changed?" preview card).

**Good trigger:** show automatically only if more than N lines changed since last open, to avoid noise on trivial edits.
---


## NOTES Vision


This document captures the full vision for the Notes tab, broken into phases. Phase 1 is the current focus. Later phases are documented here for future context.

---

### Phase 1: Note Cards & View Modes (Current)

Bring the Notes tab up to parity with Bookmarks in terms of browse experience. Notes get their own card design that's visually distinct from bookmark cards — text-forward with side images instead of top images.

#### Card Layout

Each note card displays:
- **Title** (bold header)
- **Sub-header line** — folder name for now, tags later (see Phase 3)
- **Preview text** — first few lines of plain text, stripped of markdown/HTML formatting
- **Images** — extracted from note content, alternating left/right layout, max 3
- **Footer** — modified date (relative) + word count
- **Empty state** — notes with no content show italic "Empty note" placeholder

#### Context Menu

Right-click any card or list row for:
- **Open** — opens the note in the editor
- **Rename** — inline rename directly on the card (title swaps to a focused text field, Enter to save, Escape to cancel)
- **Move to Folder** — submenu listing all folders + "No Folder" option
- **Delete** — sends the note to Trash (recoverable via Settings → Storage)

Design decision: Rename edits inline on the card rather than opening the editor. This matches user expectations for a "Rename" action.

#### Image Extraction & Display

Notes embed images via `![alt](./.attachments/filename.png)` in markdown. Cards parse these references and resolve them to file URLs for display.

**Image placement rules (grid & masonry):**
- **1 image:** Always on the right side of the card, text fills the left (~65/35 split)
- **2 images:** First image on the right. Second row: image on the left, text on the right (alternating sides)
- **3 images (max):** Alternating continues — right, left, right
- **0 images:** Text preview fills the full card width

Image area is roughly 30-35% of card width. Images are displayed with aspect-fit, rounded corners matching the design system.

#### View Modes

Same three modes as Bookmarks, adapted for text-forward cards:

**List mode:**
- Compact horizontal row
- Small square thumbnail on the left (first image from note, if any)
- Title, date, and preview text to the right
- Notes without images skip the thumbnail column

**Grid mode:**
- Fixed-height cards in adaptive columns
- Title + sub-header at top
- Text preview on the left, first image on the right
- Footer with date + word count at bottom
- Text truncated to fit standardized card height

**Masonry mode:**
- Variable-height cards based on content
- Full alternating image layout (up to 3 images)
- More preview text visible alongside images
- Card height grows with image count but capped at 3 images
- Notes without images are shorter, text-only cards — creates visual variety

#### Card Size Slider

Reuse the same `CardSizing` infrastructure and `ViewOptionsDropdown` from Bookmarks. The slider scales:
- Card width (column count adjusts)
- Preview text area size
- Image dimensions
- Typography sizes

#### Title Bar Integration

Add the same view options button to the Notes tab title bar area:
- Card size slider
- View mode toggle (list / grid / masonry icons)
- Same `ViewOptionsDropdown` component, configured for notes

---

<!-- Removed: Standalone panel resize handle bug fix — standalone NotesPanel was removed in Feb 2026 panel consolidation. Notes editor now opens inline within the main panel (push/pop navigation). -->

---

### Phase 2: Interactive Checkboxes & Pinning

#### Interactive Checkboxes on Cards

Notes containing TODO items (markdown checkboxes `- [ ]` / `- [x]`) display them directly on the card. Users can check/uncheck items without opening the note.

**Implementation considerations:**
- Parse markdown for checkbox patterns
- Render as native SwiftUI toggles on the card
- On toggle: update the specific checkbox line in the note's markdown content
- Save the modified content back to disk
- Limit display to first N checkboxes to avoid overwhelming the card

#### Note Pinning

- Pin notes to the top of the list/grid/masonry view
- Pinned notes always appear first, regardless of sort order
- Visual indicator (pin icon) on pinned cards
- Toggle via right-click context menu (add "Pin" / "Unpin" to existing context menu)

#### Drag Reorder

- Drag notes to manually reorder within the view
- Pinned notes can be reordered among themselves
- Persist custom sort order

#### Drag to Folder

- ✅ Drag note cards onto folders in the sidebar to assign them, matching the bookmark drag-and-drop pattern
- Primary method for folder organization — context menu "Move to Folder" is the secondary option
- ✅ Reuses shared `CiderDragPayload` infrastructure (`NoteDragPayload` + `ciderDraggable` modifier)
- Works across all tabs: Notes tab, Home tab, and FolderDetailView
- Note cards use `Button(action:)` wrapper (not `.onTapGesture`) to prevent NSPanel window-dragging

---

### Phase 3: Tags & Metadata

#### Multi-Folder Membership

Notes should support belonging to multiple folders simultaneously. This requires changing `folderID: UUID?` to `folderIDs: [UUID]` on the Note model.

**Card display options (needs design decision):**
- **Compact row with overflow:** Show first 2-3 folder pills inline, then a "+N" badge for remaining folders
- **Tags-style row at bottom:** Move folders to the card footer area, displayed as pills in a wrapping row — similar to how tags would appear
- **Open question:** If both folders and tags are shown on cards, how do they coexist? Separate rows? Mixed pills with different styling? Folders may need a folder icon prefix to distinguish from tags.

**Clickable folder pills:** Clicking a folder name on a card should navigate to that folder in the sidebar (select the folder, scroll sidebar to it). Provides quick navigation without right-click menus.

#### Tags on Notes

Add a `tags: [String]` field to the Note model. Tags appear as the sub-header line on cards (replacing folder name as the sole sub-header content).

**Tag features:**
- Assign tags when editing a note
- Filter notes by tag in the sidebar or via search
- Tag pills displayed on cards with subtle color coding
- Auto-suggest existing tags when adding new ones

**Relationship with folders on cards:** Both folders and tags are metadata shown on cards. Design needs to decide whether they share the same visual row (mixed pills) or have distinct locations (folders in sub-header, tags in footer — or vice versa). Consider that folders are structural (where the note lives) while tags are descriptive (what the note is about).

---

### Phase 4: Split View & Advanced Layout

#### Split View (Panel Width Dependent)

Once the Whiteboard tab is implemented as its own dedicated tab, the Notes tab focuses purely on structured note browsing and editing. The split view becomes the primary layout at wide widths.

**Layout:**
- **Left side:** Card browser (list/grid/masonry)
- **Right side:** Inline note editor for the selected note

Click a note in the browser to open it in the adjacent editor without leaving the panel. This provides a browse-and-edit workflow similar to Apple Notes / Bear / Obsidian.

**Width behavior:**
- **Narrow panel (< ~500pt):** Card browser only. Click opens note in inline editor (push/pop navigation)
- **Wide panel (> ~500pt):** Split view with resizable divider

**Empty state (no note selected):**
- Clean placeholder: "Select a note or create one" with a + button
- No scratchpad or capture area — that's what the Whiteboard tab is for
- The Notes tab stays focused on structured reading and writing

<!-- Previous: "This is distinct from the Opt+B dedicated notes panel" — standalone panel removed in Feb 2026 consolidation. Opt+B now captures a bookmark from the active browser. -->

#### What Differentiates Notes Cards from Bookmark Cards

Notes and Bookmarks share card infrastructure but should feel visually distinct:
- **Bookmark cards:** Image-heavy, portrait-oriented, thumbnail dominates the card
- **Note cards:** Text-heavy, wider/landscape-oriented, body preview dominates
- **Color coding:** Subtle background tinting of note cards by folder, tag, or user-picked color (inspired by Google Keep). Helps visual scanning without adding UI clutter.
- Notes without images should feel like the natural default, not a missing-thumbnail state

#### Advanced Image Treatment

- **Fanned/angled image stacks:** When a card has 2-3 images, the additional images fan out at slight angles behind the primary image, creating a layered stack effect
- **Click-to-cycle:** Clicking the image stack cycles through images in the fan
- **Image zoom preview:** Hover or long-press on card images for a larger preview

---

### Compact Formatting Toolbar (Upcoming)

Replace the current flat icon strip (15+ icons in a scrollable row) with a compact grouped toolbar inspired by Apple Notes. 5-6 icon buttons in the title bar area, each opening a dropdown/popover with related actions.

#### Toolbar Layout (left to right)

1. **Undo / Redo** — two small buttons, always visible (no dropdown)
2. **Aa (Text Style)** — dropdown showing:
   - Top row: **B** / *I* / U / ~~S~~ / highlight marker / text color dot
   - Below: Title, Heading, Subheading, Body, Monostyled (checkmark on the active style)
   - Below: Bulleted List, Dashed List, Numbered List
   - Below: Block Quote
   - **Active state indicator:** When text is selected, the dropdown shows which styles are currently applied (checkmark next to "Title" if it's an H1, bold icon highlighted if bold is active, etc.)
3. **Lists** — task list, bullet list, numbered list (or fold into Aa dropdown)
4. **Table** — insert table (with row/column controls in a sub-menu or inline after insertion)
5. **Attach** — insert image from file picker, attach files
6. **Link** — add/remove link (or fold into Aa dropdown)

#### Key Feature: Active Formatting State

The Aa dropdown must reflect the current selection's formatting. When the user selects text and opens the dropdown:
- Checkmark appears next to the active paragraph style (Title / Heading / Body)
- Inline style icons (B, I, U, S) show highlighted/active state
- This helps users understand what formatting is applied, especially distinguishing heading levels

#### Missing Formatting (add alongside toolbar)

- **Block quotes** — the TipTap extension and CSS exist but no toolbar button currently
- **Strikethrough** — standard text decoration, missing from toolbar
- **Highlight** — background color on selected text
- **Horizontal rule / divider** — useful for section breaks

#### Relationship to Pinned Toolbar

The current "pin toolbar" toggle becomes unnecessary — the compact toolbar is always visible in the title bar since it's only 5-6 icons wide. The old scrollable strip is removed entirely.

---

<!-- Standalone Panel Sidebar section — standalone NotesPanel was removed in Feb 2026 panel consolidation.
The inline editor now lives inside the main panel, which already has the full sidebar.
Keeping the sidebar vision below for reference in case a future dedicated editor surface is added.

### Standalone Panel Sidebar (Archived — panel removed)

**Prerequisite:** Redesign the main app's sidebar first, then reuse the same component in the standalone notes panel.

Replace the dropdown note-switcher menu in the standalone panel with a proper collapsible sidebar, matching the main app's sidebar pattern.

#### Sidebar Layout

- **Toggle:** Show/hide button in the title bar (same pattern as main panel)
- **Search bar** at top — searches within the open note first (incremental/in-note find), but also shows contextual results from other notes that match the query (with preview snippets showing matching text in context)
- **Notes list** — all notes, sorted by modified date (or user preference)
- **Selected state** — current note highlighted in the sidebar
- **Create new** — button or keyboard shortcut to create a note

#### Tree Structure (future enhancement)

Notes expand in a tree to show:
- **Attachments** — images and files embedded in that note, listed as children
- **Backlinks** — other notes that reference this note (e.g., contain a `[[Note Title]]` link), shown as linked children

This makes the sidebar a quick-reference navigation tool, not just a flat list.

#### Search Behavior

The search bar in the standalone sidebar has two modes:
1. **In-note search** (primary) — highlights matches within the currently open note, with next/previous navigation
2. **Cross-note search** — below the in-note results, shows other notes containing the query with context snippets (the matching line with surrounding text). Clicking a result switches to that note and scrolls to the match.

This is sometimes called "universal search" or "omnisearch" (Obsidian's pattern).
End of archived standalone panel sidebar section. -->

---

### Future Ideas (Not Yet Prioritized)

#### Plain Text Note Format (.txt)

Support `.txt` files alongside `.md`. Some users prefer plain text — no formatting, universal, lightweight.

**Design (planned):**
- `NoteFormat` enum (`.markdown`, `.plainText`) derived from file extension — no new stored field
- `NotesStorage` scans both `.md` and `.txt` files; `createNew(format:)` uses correct extension
- Plain text editor: `NSTextView` wrapper (no TipTap) — no formatting toolbar, no image embeds
- `InlineNoteEditorView` switches between TipTap and plain text editor based on `note.format`
- `CiderConfig.notesDefaultFormat` setting with picker in Settings → Notes → Behavior
- +New popover: segmented picker (Markdown / Plain Text), defaults from config
- `strippedContent` skips markdown regex for plain text; `imageURLs` returns `[]`
- Screen captures always create `.md` (embed `<img>` tags)
- Rename preserves existing extension
- Full plan was in `.claude/plans/encapsulated-splashing-harbor.md` (since deleted)

#### Drag Out to External Apps
✅ **Implemented (R-11).** Drag a note card out of Cider onto Finder, a text editor, or a CLI and it drops the actual `.md` file via `public.file-url`. Full spec in `WORKSPACES_VISION.md` → "Drag Out to External Apps".

#### UX Ideas from Note App Research

Patterns worth stealing from other note apps:
- **Bear's search tokens** — typing `@todo`, `@today`, `@images` in the search bar instantly filters notes by type. Zero UI footprint, very power-user friendly.
- **Ulysses auto-titling** — first line of the note automatically becomes the title. Reduces friction when creating notes quickly.
- **Per-folder sort persistence** (Evernote, UpNote) — each folder remembers its own preferred sort order and view mode independently.
- **Agenda's "flagged" concept** — a single-bit flag that creates a cross-folder "active now" virtual list. Could be a "Starred" or "Flagged" filter in the sidebar.

#### Relationship to Whiteboard Tab

The Notes and Whiteboard tabs serve different mental modes:

| Aspect | Notes | Whiteboard |
|--------|-------|------------|
| Structure | Linear documents with titles | Freeform spatial canvas |
| Creation | Deliberate — create, title, write | Impulsive — click and dump |
| Organization | Folders and tags | Spatial positioning |
| Content | Long-form text, rich formatting | Fragments: short text, images, links, quotes |
| Output | Finished thoughts | Raw material that becomes notes |

The promotion flow: **Whiteboard blocks → select → "Create Note" → Notes tab**

#### Screen Capture → Note

Screen capture (Opt+Cmd+2) is a first-class note creation path. When the routing toast's "Create Note" action fires:
- Title: first meaningful OCR line (≤ 60 chars), fallback "Screen Capture"
- Body: full OCR text from Vision framework
- Screenshot saved as `{notesDir}/Attachments/{uuid}.png` and embedded in the note

This means any visible text on screen — a chat message, a document, a code snippet — can become a searchable, editable note in one gesture.

#### Todos / Planner Tab

Now has its own vision doc: `Docs/_archive/TODOS_VISION.md`. The core idea remains: separate actionable items (todos) from captured thoughts (notes) and freeform brainstorming (whiteboard).

---

### Model Changes Required

#### Phase 1
- Add computed properties to `Note` for image extraction (parse markdown for image references)
- Add `NoteDisplayMode` enum (`.list`, `.grid`, `.masonry`)
- Add note-specific card sizing to `CiderConfig` persistence
- Word count computed property on `Note`

#### Phase 2
- Add `isPinned: Bool` to `Note` model
- Add `sortOrder: Int?` to `Note` model for manual ordering
- Checkbox parsing utilities for markdown content

#### Phase 3
- Add `tags: [String]` to `Note` model
- Tag storage and indexing in `NotesStorage`

---

### Post-1.0 Editor Features

#### Toggle List (Collapsible Sections)
- TipTap `Details` extension (`<details>/<summary>` HTML)
- Toolbar button to insert a collapsible block
- Useful for long notes with sections you want to collapse

#### Block Drag Handles
- Notion-style drag handles on paragraph/block hover
- Allows reordering blocks (paragraphs, headings, lists, code blocks) by dragging
- "Paragraph" insert button creates a new block at cursor position

#### Comments / Annotations
- Select text → add comment → text highlighted with distinct comment color
- Comments listed in the info/metadata sidebar panel
- Click a comment in sidebar → scrolls to highlighted text in editor
- TipTap custom `Comment` mark with comment ID attribute
- Comment storage: array of `{id, text, author, createdAt}` persisted with note metadata
- Serialization: `<mark data-comment="id">text</mark>` in HTML

#### Editor Background Themes
- Preset background colors for the editor in page view: dark (default), cream/sepia, paper white, soft gray
- Applied as a CSS class on the TipTap editor body element
- Persisted in CiderConfig (`noteEditorBackground: String`)
- Toggle in the note toolbar or view options dropdown

#### Per-Type Detail View Mode
- Each content type remembers its own preferred detail view mode (slideOut, fullPanel, page)
- `CiderConfig.bookmarkDetailViewMode`, `noteDetailViewMode`, `dateCardDetailViewMode`, etc.
- CiderPanelView reads the appropriate mode based on what's being opened
- Mode picker updates only the relevant type's setting
- Users who prefer notes full-page but bookmarks in slideout get exactly that

#### Columns Layout
- Multi-column content layout within a note
- Would need a custom TipTap node extension
- Low priority — uncertain value in a notes app

---


## VAULT Vision


> **Status:** Vision / exploratory — not on the 1.0 roadmap. This document captures the long-term direction for Cider's architecture and philosophy.

---

### The Problem

People have files scattered everywhere — photos on their phone, bank statements in Downloads, contractor quotes in email, kids' event flyers as screenshots, grocery receipts, cell phone bills. Organizing all of this manually is tedious. Everyone is already paying for AI tools (Claude, ChatGPT, etc.) that can do this work.

### The Vision

**Cider becomes a beautiful presentation layer over a raw filesystem vault.** The vault is a single folder where users dump everything. External AI tools (CLI or desktop) do the heavy lifting — sorting, tagging, summarizing, categorizing. Cider watches the vault and renders it as a polished dashboard.

Cider remains a fast, simple, double-tap-Option floating panel. The vault doesn't change what Cider is — it changes the backend. Instead of proprietary storage, Cider reads from a folder of standard files. Same speed, same simplicity, better foundation.

#### Key Principles

1. **Dump everything, organize later.** The vault accepts any file type — photos, PDFs, documents, screenshots, notes, bookmarks. No friction on capture.
2. **Filesystem is the source of truth.** Folders in the vault = folders in Cider. No proprietary metadata databases. Move a file in Finder, it moves in Cider.
3. **Bring your own AI.** Users point Claude Code, ChatGPT desktop, or any CLI tool at the vault. Tell it "organize my inbox" or "tag everything from this month."
4. **"Cider is the stage, not the stagehand."** This is the product truth. Cider's job is to present information beautifully — cards, grids, dashboards, search. The AI does the categorization, tagging, and summarization. Cider doesn't need its own intelligence. It needs to be the best place to *see* the results of intelligence. This line should guide every feature decision: if it's stagehand work, let the user's AI tools handle it. If it's stage work — making things visible, beautiful, searchable, browsable — that's Cider.
5. **No lock-in.** Users own their files in standard formats. Cider adds value through presentation, not proprietary storage. If you leave Cider, you still have a well-structured vault with all your files in normal formats.
6. **View, don't edit (for complex types).** Cider can view any file type — images, PDFs, video, audio, spreadsheets. For notes and bookmarks, Cider is the editor. For complex types (image editing, spreadsheet editing), users open their preferred external editor. Cider is a viewer + launcher, not a replacement for specialized tools.

### How It Works

#### Capture Flow

```
User's life (photos, docs, bills, screenshots, memes, etc.)
    │
    ▼
Cider Vault (single folder on disk)
    │
    ├── Inbox/          ← raw dumps land here (mobile sync, drag-drop, etc.)
    ├── Photos/         ← AI-sorted by person, location, type
    ├── Finance/        ← bank statements, bills, receipts
    ├── Kids/           ← school events, activities
    ├── Projects/       ← contractor quotes, home improvement
    ├── Notes/          ← markdown files
    ├── Bookmarks/      ← .webloc files or URL lists
    └── ...             ← any folder structure the AI or user creates
```

#### Organization Flow

```
1. User dumps files into vault (or Inbox/ subfolder)
2. User opens their CLI AI tool, cd's into the vault
3. "Organize everything in my inbox"
4. AI moves files into folders, writes sidecar metadata, tags content
5. User opens Cider — everything appears organized
```

#### What AI Tools Can Do

- Sort photos by face, location, scene type, date
- Categorize documents (bills → Finance/, quotes → Projects/)
- Extract dates from event flyers → surface in Coming Up section
- Summarize PDFs and long documents
- Tag files with semantic labels
- Create folder structures based on content patterns
- Write sidecar `.cider-meta.json` files with extracted metadata

#### Cider's Role

- **Render cards** based on file type (image → photo card, .md → note card, .pdf → document card, .webloc → bookmark card)
- **View any file type** — images, PDFs, video, audio via native macOS frameworks (PDFKit, AVKit, QuickLook). No custom editors needed for viewing.
- **Read sidecar metadata** for tags, summaries, extracted dates
- **Watch filesystem** via FSEvents for instant updates when AI tools make changes
- **Provide saved views, search, stacks** — all reading from the filesystem
- **"Open in..." button** for complex file types — launches the user's preferred external editor

#### Viewing File Types

Cider leverages macOS/iOS built-in frameworks for viewing — no custom renderers needed for most types:

| File Type | Framework | Effort |
|-----------|-----------|--------|
| Images (JPEG, PNG, etc.) | SwiftUI `Image` / `NSImage` | Trivial |
| PDFs | `PDFKit` | Trivial |
| Video/Audio | `AVKit` / `AVPlayer` | Trivial |
| Spreadsheets, Office docs | `QLPreviewPanel` (Quick Look) | Trivial |
| Everything else | Quick Look fallback → icon + metadata card | Trivial |

For files Quick Look can't preview, Cider shows a file icon, name, size, date, and tags from sidecar metadata, with an "Open in..." button.

### Cross-Platform Architecture

#### The Core Model

Convex is the shared cloud database. The vault is a desktop-specific local mirror of real files.

```
Web App (full functionality)     iOS App (full functionality)
    │                                │
    ▼                                ▼
                  Convex
        (shared cloud database)
                    │
                    ▼
            Desktop App
                    │
                    ▼
              CiderVault/
        (real files on disk)
                    │
                    ▼
           AI tools (Claude Code,
           ChatGPT, Codex, etc.)
```

- **Convex** = shared cloud database, all platforms read/write here
- **CiderVault/** = desktop-only local mirror as real files (for AI tools, Finder access, offline use, no lock-in)
- **Web app** = full Cider experience, talks directly to Convex
- **iOS app** = full Cider experience, talks to Convex, has local vault in app sandbox
- **Desktop app** = full Cider experience, talks to Convex AND syncs to/from vault on disk

#### Two-Way Sync

Edits can happen on any platform:

```
Web/iOS edits → saved to Convex → desktop pulls down to vault files
Desktop edits (vault files) → pushed to Convex → web/iOS see updates
AI tool edits (vault files) → desktop detects via FSEvents → pushed to Convex
```

#### Web App — Full Functionality

The web app is NOT capture-only. It's a full Cider experience for scenarios like:
- Using a locked-down work computer where you can't install apps
- Accessing your vault from any browser, anywhere
- Creating/editing notes, saving bookmarks, tagging items, organizing folders

The web app reads/writes Convex directly. It doesn't need the vault — that's a desktop concept.

#### iOS App — Local Vault + Sync

The iOS app maintains a local vault in its sandboxed Documents directory:
```
App Sandbox/Documents/CiderVault/
├── Inbox/
├── Notes/        ← .md files
├── Bookmarks/    ← .webloc or bookmark JSON
├── Photos/       ← actual JPEGs
└── ...
```

- Same file formats as desktop (JPEG, markdown, PDF, etc.)
- Exposed via `FileProvider` so users can browse in iOS Files app
- Syncs to/from Convex for cross-device access

#### iOS Photo Capture

**Share Sheet extension** (primary method):
- User takes a photo → taps Share → taps Cider
- Photo saved as JPEG to local vault's `Inbox/`
- Syncs to Convex → downloads to Mac vault
- Opt-in per photo, no surprise data usage

**Camera roll import** (optional):
- User grants photo library access
- Cider imports selected photos when app is open
- Apple restricts true 24/7 background sync — import happens when user opens the app

**Data optimization:**
- Sync **thumbnails** through Convex (small, fast, cheap)
- Full-resolution files sync on-demand or via iCloud Drive
- Browsing vault on other devices is fast, pulling full 4K photos only happens on tap

### Sync Provider Architecture

#### Abstracted Sync Layer

Users choose their sync backend. Convex is the default. Others are optional.

```swift
protocol SyncProvider {
    func push(item: VaultItem) async throws
    func pull() async throws -> [VaultItem]
    func observe(onChange: @escaping ([VaultItem]) -> Void)
}

class ConvexSyncProvider: SyncProvider { ... }  // Default
class CloudKitSyncProvider: SyncProvider { ... } // iCloud option
// Future: DropboxSyncProvider, GoogleDriveSyncProvider, FilenSyncProvider, etc.
```

The rest of the app doesn't care which provider is active. Swap backends in settings.

#### Sync Provider Options

| | Convex (default) | iCloud / CloudKit | Dropbox / Google Drive / Filen |
|---|---|---|---|
| **Setup** | Cider account | Apple ID | Existing account |
| **Cost** | Free tier / paid | User's iCloud storage | User's existing plan |
| **Web app** | Email/password auth | Apple ID via CloudKit JS | OAuth |
| **Shared vaults** | Easy (multi-user DB) | Limited (CKShare) | Shared folders |
| **Non-Apple devices** | Works everywhere | Apple ecosystem + web | Works everywhere |
| **Speed** | Very fast (WebSocket) | Good (Apple-controlled) | Varies |

#### iCloud / CloudKit Details

- **Desktop + iOS:** Native CloudKit frameworks, straightforward
- **Web app:** Apple provides CloudKit JS — user authenticates with Apple ID via OAuth, web app reads/writes CloudKit data
- CloudKit JS is functional but less polished than Convex — slightly slower queries, clunkier auth flow

#### Adding Future Providers

Any cloud storage service that has an API can become a SyncProvider:
- **Dropbox:** REST API + webhooks for change notifications
- **Google Drive:** REST API + push notifications
- **Filen:** API for encrypted storage
- **Self-hosted:** Syncthing, WebDAV, etc.

Each just conforms to the same `SyncProvider` protocol. The vault on disk works identically regardless of which provider syncs the data.

### Shared Vaults / Family Sharing

#### How It Works

Since Convex is a multi-user database, shared vaults are straightforward:

```
Your girlfriend (iOS only)     You (Desktop + iOS + Web)
    │                              │
    ▼                              ▼
        Convex (shared collection)
                  │
                  ▼
           Your CiderVault/
            ├── Your stuff/
            └── Shared/    ← her photos/notes land here
```

- Each user has their own Cider account
- Users can link accounts and create shared collections
- Shared items sync to both users' vaults
- Scoped sharing — share photos but not notes, or everything
- Phone-only users (like a partner who doesn't use a computer) get the full experience through the iOS app backed by Convex — they never need a desktop vault

#### With iCloud

Shared vaults are harder with CloudKit (`CKShare` is more record-level than workspace-level). This is one reason Convex is the recommended default.

### AI Chat Panel

#### Current Implementation: Native AI Assistant

> **Note:** The original plan was a styled SwiftTerm terminal (Option A below). The actual implementation went directly to a native chat UI with MLX local models.

A slide-out companion panel (`AIAssistantPanelView`) that opens alongside the main Cider panel:

- **Floating NSPanel** — separate panel with acrylic background, positioned next to the main panel
- **Chat bubble UI** — `AIAssistantBubbleView` renders conversation as user/assistant message bubbles
- **MLX local models** — `MLXModelManager` manages on-device model loading; `AIAssistantViewModel` handles streaming inference
- **Tool calling** — `MLXToolExecutor` + `AIAssistantTools` let the AI interact with vault content (search, read, organize)
- **Conversation persistence** — `AIConversationStorage` saves chat history across sessions
- **Model picker** — select between available MLX models

#### Original Plan: Option A — Styled Terminal (Not Implemented)

The original concept was a PTY-backed terminal (SwiftTerm) styled to feel like a chat window, with model selector pills that auto-launch CLI tools. This approach was replaced by the native chat UI above, which provides a better user experience and doesn't require users to have CLI tools installed.

#### Future: Option B — Chat UI with Hidden Terminal (Archived)

> **Status:** Archived. The native AI assistant approach superseded both Option A and Option B.

The ambitious evolution: build a proper chat bubble UI that completely hides the terminal:

**How it would work:**
- SwiftTerm still runs underneath as the engine (invisible)
- A custom SwiftUI chat view captures terminal stdout and renders it as "assistant" message bubbles
- A text input field at the bottom sends keystrokes to the hidden terminal
- ANSI escape codes are stripped/parsed from output before display
- Clean conversation flow with user messages on the right, AI responses on the left

**Technical challenges:**
- **Streaming output parsing** — CLI tools use progress spinners, partial lines, markdown formatting, cursor movement. Reliably parsing this into clean "messages" is hard.
- **Message boundary detection** — Knowing when the AI is "done" responding vs. still streaming. No universal signal across different CLI tools.
- **Rich content** — Some CLI tools output tables, code blocks, file trees. Need a markdown renderer for assistant bubbles.
- **Interactive prompts** — Some tools ask yes/no questions mid-stream. The chat UI needs to handle these gracefully.
- **Tool-specific adapters** — Each CLI tool (Claude, ChatGPT, Codex) has different output patterns. May need per-tool parsing logic.

**Suggested approach:**
1. Start with Claude CLI (most structured output, most popular)
2. Build an output parser that detects message boundaries using prompt patterns (`❯`, `$`, etc.)
3. Render assistant messages as markdown bubbles
4. Add adapters for other tools as needed
5. Keep a "raw terminal" toggle for power users who want the real terminal

**Why wait:** Option A gets 80% of the chat feel with 20% of the complexity. Option B is worth pursuing only if users consistently ask "why does this look like a terminal?" — meaning the styling alone isn't enough.

### Metadata Strategy

#### Sidecar Files

Instead of a proprietary database, metadata lives alongside files as `.cider-meta.json`:

```
Photos/
├── vacation-2026-hawaii/
│   ├── IMG_001.jpg
│   ├── IMG_002.jpg
│   └── .cider-meta.json     ← tags, descriptions, face IDs, location
├── memes/
│   ├── funny-cat.png
│   └── .cider-meta.json
```

A `.cider-meta.json` sidecar file per directory (or per file for rich items):

```json
{
  "items": {
    "IMG_001.jpg": {
      "tags": ["hawaii", "beach", "family"],
      "people": ["Dad", "Mom", "Kids"],
      "date": "2026-07-15",
      "summary": "Family at Waikiki Beach at sunset"
    }
  }
}
```

#### Why Sidecar Files

- **Human-readable** — it's JSON, anyone can open it
- **AI-writable** — any CLI tool can create/update it
- **Cider-readable** — the app knows how to parse it
- **Non-destructive** — removing Cider doesn't touch your files
- **Interoperable** — Cider UI writes the same format as AI tools

#### How Sidecar Works

"Sidecar" = a small metadata file that rides alongside the real files (like a sidecar on a motorcycle). When you tag a photo in Cider's UI, it writes to the `.cider-meta.json` in that folder. When an AI tool tags files, it writes to the same file. Both read the same format.

### Vault Roadmap

This is an evolution, not a rewrite. The roadmap is split into **core milestones** (the ship path) and a **backlog** (everything else, to be prioritized after core is proven).

---

#### Core Milestones

##### Milestone 1: The Magical Loop
> *Prove the concept. Drop file → organize → Cider reflects it.*

- [x] Real vault folder on disk (`~/CiderVault/` or user-configured path)
- [x] Cider mirrors vault folder structure (folders = real directories on disk)
- [x] FSEvents watching — external changes reflect instantly in Cider UI
- [x] Vault index (`.cider-index.json`) for fast item lookup without scanning
- [x] Notes physically move to vault folders when assigned
- [x] Unsorted/ directory for unfiled items (hidden from Cider sidebar)
- [x] Sidecar `.cider-meta.json` reading (tags, summaries, dates rendered in UI)
- [x] Sidecar writing from Cider UI (tag/edit metadata → writes to sidecar file)
- [x] Search includes sidecar metadata tags in matching

##### Milestone 2: Universal Viewing
> *Cider can display any file type dropped into the vault.*

- [x] Card type inference from file extension
- [x] Image viewer (SwiftUI `Image` / `NSImage`)
- [x] PDF viewer (`PDFKit`)
- [x] Video/audio player (`AVKit` / `AVPlayer`)
- [x] Quick Look fallback for everything else
- [x] "Open in..." button for external editing
- [x] File icon + metadata card for unknown types
- [ ] Vault file detail panel polish — match the look/feel of bookmark/note detail panels for all file types (image, PDF, video, audio). Toolbar actions, metadata sidebar, consistent layout, proper sizing.

##### Milestone 3: AI Workspace
> *AI workspace inside Cider for interacting with vault content.*

- [x] AI Assistant panel — `AIAssistantPanelView` as a separate floating NSPanel with acrylic background, chat bubble UI, MLX local model integration (`AIAssistantViewModel` + `MLXModelManager`)
- [x] Conversation persistence — `AIConversationStorage` for chat history
- [x] Model picker — select between available MLX models
- [x] Tool calling — `MLXToolExecutor` + `AIAssistantTools` for vault-aware AI actions
- ~~SwiftTerm-based terminal~~ — original terminal approach was replaced by the native AI chat panel above
- [ ] Additional polish — custom model configuration in settings, keyboard shortcut for toggle

##### Milestone 4: Data Migration (Personal)
> *Move existing Cider data into the vault format. Not a user-facing migration tool — just personal data preservation.*

- [x] Export bookmarks from current JSON → vault files (.webloc)
- [x] Export notes → `.md` files in vault (already native format)
- [x] Export folders → vault directories (legacy → VaultFolder)
- [x] Export tags/metadata → sidecar files (.cider-meta.json)
- [x] Settings UI trigger (Data → Import/Export → "Export to Vault" button)

##### Milestone 5: Convex Sync
> *Default sync provider. Desktop syncs vault ↔ Convex. Web and iOS consume synced data.*

Internally treated as sub-phases:

- [ ] **5A:** `SyncProvider` protocol abstraction + Convex provider (desktop vault ↔ Convex two-way sync)
- [ ] **5B:** Web app reads synced vault data from Convex
- [ ] **5C:** Web app writes to Convex (full read/write — notes, bookmarks, tags, folders)
- [ ] **5D:** iOS app reads/captures via Convex sync (browse + capture to Inbox)

##### Milestone 6: iOS Capture
> *iOS becomes a real capture point. Browse + capture via Convex, no local vault complexity yet.*

- [ ] Share Sheet extension for photo/file capture → Inbox
- [ ] Thumbnail sync through Convex (small/fast/cheap), full-res on demand
- [ ] Browse vault contents on iOS via Convex
- [ ] Create/edit notes and bookmarks on iOS

---

#### Backlog (Post-Core)

> Everything below is captured so nothing gets lost. To be prioritized and scheduled after core milestones are proven and shipped. New ideas get added here.

##### Alternative Sync Providers
- [ ] iCloud/CloudKit provider (desktop + iOS native CloudKit frameworks)
- [ ] CloudKit JS integration for web app (Apple ID OAuth)
- [ ] Dropbox provider (REST API + webhooks)
- [ ] Google Drive provider (REST API + push notifications)
- [ ] Filen provider (encrypted storage API)
- [ ] Self-hosted options (Syncthing, WebDAV)

##### Shared Vaults / Family Sharing
- [ ] Account linking between Cider users
- [ ] Shared collections in Convex
- [ ] Scoped sharing (by folder, by type, or everything)
- [ ] Phone-only users get full experience via iOS app + Convex
- [ ] Shared vault permission model (granular vs. all-or-nothing)

##### iOS Local Vault
- [ ] Local vault in iOS app sandbox (same file formats as desktop)
- [ ] `FileProvider` integration (vault visible in iOS Files app)
- [ ] Local/remote reconciliation for offline edits

##### Photo Intelligence
- [ ] Face grouping / recognition
- [ ] Scene/location inference
- [ ] Photo deduplication
- [ ] Camera roll import (bulk import selected photos when app is open)

##### Advanced Vault Features
- [ ] SQLite cache for fast search/filtering across large vaults (10k+ files)
- [ ] Background auto-organize agent (watches Inbox, auto-sorts via AI)
- [ ] Default "organize" prompt/script shipped with Cider for users to run with any AI tool
- [ ] Smart folders / saved searches (virtual folders based on tags, dates, types)
- [ ] Vault statistics dashboard (storage usage, file counts by type, organization score)

##### Drop Built-In AI (Optional)
- [ ] Remove built-in auto-tagging/summarization if "bring your own AI" proves sufficient
- [ ] Or keep built-in AI as convenience layer for users without CLI tools
- [ ] Evaluate based on user feedback after AI Workspace ships

##### Distribution & Updates (Deferred from 1.0)
- [ ] Sparkle Auto-Updater — add Sparkle package to Xcode, test real update flow (code is written, needs Xcode wiring + signing test)
- [ ] Mac App Store listing — App Store Connect setup, sandboxing audit, pricing decision, dual distribution (direct + MAS)

##### New Card Types (Deferred from 1.0)
- [ ] Books card type — `Book` model, fields (title, author, cover, reading status, rating, notes), `BookStorage`, card/list views, manual entry. Full book system (ISBN lookup, Goodreads import, progress tracking, highlights, statistics, shelf display) is further backlog.
- [ ] Documents card type — `Document` model, fields (title, file path, file type, size, thumbnail), `DocumentStorage`, drag-drop ingestion, card views, open in default app / reveal in Finder. Full document system (filesystem watcher, OCR, full-text search, window-based capture) is further backlog.

##### Screen Capture (Deferred from 1.0)
- [ ] Screen capture polish — Date Card and Contact OCR routing improvements, image preview in toast, OCR noise filtering. Core functionality works, needs edge case polish.

##### Whiteboard Expansion (Deferred from 1.0)
- [ ] Drag library items onto Excalidraw canvas (bookmarks, notes, images via JS bridge)
- [ ] "Send to Whiteboard" context menu action on any card
- [ ] `cider-library-item` custom Excalidraw element type with live card data
- [ ] Canvas rename, delete with undo, theme sync, export as PNG/PDF
- [ ] Keyboard shortcut conflict prevention (Excalidraw vs panel shortcuts)

##### Video Bookmarks (Deferred from 1.0)
- [ ] Accept .mp4/.mov/.webm drag-drop as bookmark type
- [ ] Thumbnail extraction via AVAssetImageGenerator
- [ ] Video player in detail view

### FSEvents — How Filesystem Watching Works

FSEvents is the macOS API for watching a folder for changes. Like how Finder instantly shows a new file after you download something. Cider uses FSEvents to watch the vault folder, so when an AI tool (or the user in Finder) moves files, creates folders, or edits sidecar metadata, Cider updates instantly without manual refresh.

Key considerations:
- Debouncing — batch rapid changes (AI tool moving 50 files) into a single UI update
- Incremental diffing — only process what changed, not the whole vault
- Lightweight SQLite cache — read from filesystem, cache for fast search/filtering
- Scales to 10k+ files (apps like DEVONthink prove this works)

### Why This Direction

1. **Everyone's paying for AI already.** Don't rebuild what Claude Code and ChatGPT desktop already do.
2. **No lock-in.** Standard files in standard folders. If you leave Cider, you keep everything.
3. **Future-proof.** As AI tools get better, Cider automatically benefits.
4. **User owns everything.** No export needed — your files are already normal files.
5. **Simpler app architecture.** Cider reads the filesystem instead of managing complex storage layers.
6. **Cross-platform without compromise.** Full experience on web and iOS, with the vault as a desktop superpower.
7. **Flexible sync.** Users choose their cloud provider — Convex, iCloud, Dropbox, or anything else.

### Open Questions

- How to handle bookmarks (URLs aren't files)? `.webloc` files? A `bookmarks.json` index?
- Should Cider ship a default "organize" prompt/script that users can run with any AI tool?
- How to handle the transition for existing users with proprietary vault data?
- Thumbnail generation strategy for Convex sync (pre-generate on capture? on-demand?)
- Thumbnail size cap — enrichment downloads og:image at full size with no limit (seen 3.29MB for a single product photo). Should resize/compress to ~200KB max before storing in Convex file storage to keep bandwidth and storage costs down at scale.
- SQLite cache schema for fast search across large vaults
- `FileProvider` implementation details for iOS Files app integration
- Shared vault permission model — granular sharing (by folder? by type?) vs. all-or-nothing

---

**This document is a north star, not a spec.** The 1.0 roadmap focuses on shipping what's built. This vision guides post-1.0 decisions — every architectural choice should move toward this direction, not away from it.

---


## WHITEBOARD Vision


> **Status:** Phase A Shipped (Excalidraw canvas tab), Phase B (library integration) Not Started

### Overview

The Whiteboard is a freeform canvas for dumping thoughts, images, links, and quotes. It's the "junk drawer of your brain" — a place to capture anything without structure, then optionally promote clusters of content into structured notes.

It will appear as a **saved view tab** in the tab bar — created by the user via the +New popover. There is no fixed Whiteboard tab; the user opts in by creating one.

Notes is for deliberate structured writing, Whiteboard is for impulsive brain-dumping. Different mental modes, different tabs.

### Core Concept

An infinite canvas where clicking anywhere creates a block. No grid, no alignment, no structure. Content lands wherever you put it. The aesthetic is intentionally loose — sticky notes at slight angles, images with lifted corners, handwritten-feeling text. Think detective evidence board meets personal scratchpad.

### Interaction Model

#### Creating Blocks

**Text block:**
- Click anywhere on the canvas → text input cursor appears at that position
- Start typing → text appears inline on the canvas
- Click away or press Escape → input finalizes into a styled sticky note block
- The sticky note gets a subtle random rotation (-3 to +3 degrees), a warm background tint, and a slight drop shadow

**Quote block:**
- Paste text that's wrapped in quotes, or paste from a clipboard that has a quote format
- Auto-detected and formatted as a quote block: vertical accent bar on the left, italic text, slightly different card style than a regular text block
- Could also detect "said" or attribution patterns and style accordingly

**Image block:**
- Drag an image file onto the canvas, or paste from clipboard
- Image renders at a reasonable default size with:
  - One corner slightly lifted (3-5 degree rotation on the corner)
  - Soft drop shadow underneath
  - Optional: a small "pin" or "tape" visual at the top
- Resizable by dragging edges

**URL/Link block:**
- Paste a URL onto the canvas
- Auto-generates a thumbnail preview card (reuse bookmark thumbnail infrastructure)
- Shows: favicon, page title, domain, thumbnail image
- Clicking it opens the URL
- Visually distinct from text blocks — more structured, card-like

**Sketch block (future):**
- Draw directly on the canvas with Apple Pencil or mouse
- Freeform strokes stored as vector paths
- Could use PencilKit on supported devices

#### Manipulating Blocks

- **Drag** any block to reposition it on the canvas
- **Resize** blocks by dragging edges/corners
- **Rotate** blocks by grabbing a rotation handle (or two-finger gesture)
- **Delete** via backspace when selected, or right-click > Delete
- **Duplicate** via Cmd+D or right-click > Duplicate
- **Color** — right-click > Change Color to tint the block background

#### Multi-Select & Promote

- **Lasso select** — click and drag on empty canvas to draw a selection rectangle
- **Cmd+click** to add/remove blocks from selection
- Selected blocks get a highlight border
- **"Create Note" button** appears when blocks are selected — promotes the selected blocks into a structured note in the Notes tab
  - Text blocks become paragraphs
  - Quote blocks become blockquotes
  - Images become inline images
  - URLs become links
  - The note is created in the user's current folder (or inbox)
- Promoted blocks can optionally remain on the whiteboard (as references) or be removed

#### Canvas Navigation

- **Pan** — scroll or two-finger drag to move around the canvas
- **Zoom** — pinch or Cmd+scroll to zoom in/out
- **Minimap** (optional) — small overview in the corner showing block positions at a glance
- **Reset view** — double-click empty space or button to snap back to center/fit-all

### Visual Design

#### Block Styles

```
Text Block (Sticky Note):
┌─────────────────┐
│ Random thought   │  ← warm background (cream, light yellow, light pink, light blue)
│ about something  │  ← slight rotation (-3 to +3 deg)
│ I need to        │  ← soft drop shadow
│ remember...      │
└─────────────────┘

Quote Block:
┌──┬──────────────┐
│▐ │ "Design is    │  ← vertical accent bar on left
│▐ │  not just     │  ← italic text
│▐ │  what it      │  ← muted background
│▐ │  looks like"  │
│  │   — Steve Jobs │
└──┴──────────────┘

Image Block:
  ┌──────────────┐╲
  │              │ │  ← one corner slightly lifted
  │   [image]    │ │  ← soft drop shadow
  │              │ │  ← optional pin/tape at top
  └──────────────┘─┘

URL Block:
┌──────────────────┐
│ ┌──────┐         │
│ │thumb │ Page Title│  ← reuse bookmark card style
│ └──────┘ domain.com│  ← favicon + domain
└──────────────────┘
```

#### Canvas Background

- Subtle dot grid or graph paper pattern (very low opacity, ~5%)
- Dark background matching Cider's acrylic aesthetic
- Dots/grid help give spatial orientation when panning

#### Color Palette for Sticky Notes

Muted, warm tones that work on dark backgrounds:
- Cream/warm white (default)
- Soft yellow
- Light coral/pink
- Light blue
- Light green
- Light purple
- User can change per block via right-click

Colors should be semi-transparent so they blend with the dark canvas rather than looking like Post-its on a white board.

### Connections (v2)

After the basic canvas works:

- **Draw connections** between blocks by dragging from one block's edge to another
- Connection renders as a curved line (bezier) or straight line
- Optional label on the connection (small text along the line)
- Connections are purely visual — they don't create data relationships (yet)
- Style: thin line, slightly transparent, with a subtle arrow at the target end

### Data Model

```swift
struct WhiteboardCanvas: Identifiable, Codable {
    let id: UUID
    var name: String
    var blocks: [WhiteboardBlock]
    var connections: [WhiteboardConnection]
    var viewportCenter: CGPoint  // last camera position
    var viewportZoom: CGFloat    // last zoom level
    var createdAt: Date
    var updatedAt: Date
}

struct WhiteboardBlock: Identifiable, Codable {
    let id: UUID
    var position: CGPoint       // center point on canvas
    var size: CGSize             // width x height
    var rotation: Double         // degrees, -180 to 180
    var content: BlockContent    // what's inside
    var style: BlockStyle        // visual customization
    var zIndex: Int              // layering order
    var createdAt: Date
    var updatedAt: Date
}

enum BlockContent: Codable {
    case text(String)
    case quote(text: String, attribution: String?)
    case image(imageData: Data, originalFilename: String?)
    case url(urlString: String, title: String?, domain: String?, thumbnailData: Data?)
    case sketch(pathData: Data)  // future
}

struct BlockStyle: Codable {
    var backgroundColor: String?  // color name or hex
    var opacity: Double           // 0-1, default 1.0
    var borderVisible: Bool       // default false
    var pinned: Bool              // pinned blocks don't move with canvas gestures
}

struct WhiteboardConnection: Identifiable, Codable {
    let id: UUID
    var fromBlockId: UUID
    var toBlockId: UUID
    var label: String?
    var style: ConnectionStyle    // line type, color, thickness
}

enum ConnectionStyle: Codable {
    case straight
    case curved
    case dashed
}
```

### Relationship to Notes Tab

The Whiteboard and Notes tabs serve different purposes:

| Aspect | Notes | Whiteboard |
|--------|-------|------------|
| Structure | Linear documents with titles | Freeform spatial canvas |
| Creation | Deliberate — create, title, write | Impulsive — click and dump |
| Organization | Folders and tags | Spatial positioning |
| Content | Long-form text, rich formatting | Fragments: short text, images, links, quotes |
| Output | Finished thoughts | Raw material that becomes notes |

The promotion flow: **Whiteboard blocks → select → "Create Note" → Notes tab**

### Clipboard Capture Flow

The Whiteboard doubles as Cider's **clipboard inbox**. Instead of building a separate clipboard manager, clipboard captures route through the existing toast system — the same one that already handles URL bookmarking.

#### How It Works

Every time you copy something, Cider detects it and shows a toast:

**URLs** → "Save as bookmark?" toast (already exists, no change)

**Everything else** (text, images, quotes, code snippets) → "Save to Whiteboard?" toast

That's it. Two paths, both using the same toast pattern. Nothing is captured unless you confirm it.

#### Accepting a Toast: Keyboard Shortcuts

When a toast is showing, Cider's existing hotkeys double as accept gestures:

- **Double-tap Option** → save to **Whiteboard** (default — sort it later)
- **Option+N** → save directly as a **Note** (skips Whiteboard, creates a new note)
- **Option+B** → save directly as a **Bookmark** (skips Whiteboard, adds to bookmarks)
- **Ignore / let it expire** → nothing is captured

When no toast is showing, these hotkeys work as normal (double-tap Option opens Cider, Option+N creates a new note, Option+B captures a bookmark from the active browser).

This means:
- No new hotkeys to learn — same gestures you already use for Cider
- **Casual flow:** copy, double-tap Option, sort later on the Whiteboard
- **Power-user flow:** copy, Option+N or Option+B to route directly — skip the Whiteboard entirely
- Ignoring a capture is zero effort — just don't do anything, the toast expires

#### What Gets Created

Accepted clipboard content lands on the Whiteboard as a styled block, auto-detected by type:
- **Plain text** → sticky note block (random rotation, warm background)
- **Quoted text** (text in quotes, or with attribution patterns) → quote block (vertical accent bar, italic)
- **Image data** → image block (lifted corner, drop shadow)
- **URL** → routed to bookmarks, not the Whiteboard (existing flow)

#### Why No Filtering Is Needed

You copied a 2FA code? Ignore the toast. A password? Ignore it. A Discord username? Ignore. Only the things you actively accept with double-tap Option make it to the Whiteboard. No blocklists, no pattern matching, no settings to configure.

#### AI-Powered Sorting (Future)

With AI integration, the Whiteboard could:
- Auto-categorize captured blocks (research, quotes, tasks, references)
- Suggest connections between related blocks (detective-board strings between related items)
- Propose promotions ("These 4 blocks look like a note about X — create one?")
- Cluster nearby blocks by topic automatically

### Implementation Phases

#### Phase 1: Basic Canvas (MVP)

The MVP is a "dumb" version that's still useful and charming. The key interaction: **click anywhere on the canvas and start typing.** That's it. No toolbars, no mode switching.

**Core interactions:**
- Click anywhere on empty canvas → text cursor appears at that position → start typing
- Click away or press Escape → text finalizes into a styled sticky note block
- Each block gets a subtle random rotation (-3 to +3 degrees) and warm background tint
- Drag any block to reposition it

**Content auto-detection on paste:**
- Paste plain text → becomes a sticky note block at the cursor position
- Paste a quote (text in quotes or from a recognized quote format) → auto-formats as a quote block with vertical accent bar and italic text
- Paste/drag an image → image block with a slight corner lift and drop shadow
- Paste a URL → generates a thumbnail card (reuse bookmark thumbnail infrastructure) with favicon, title, domain

**Canvas basics:**
- Infinite scrollable/zoomable canvas with subtle dot grid background (~5% opacity)
- Pan via scroll or drag on empty space
- Zoom via Cmd+scroll or pinch
- Persist blocks to local storage (JSON/SQLite)
- Block deletion via backspace/delete when selected

#### Phase 2: Polish & Block Types
- Quote block auto-detection and styling
- URL thumbnail generation (reuse bookmark infrastructure)
- Block rotation (random on creation, manual adjustment)
- Block color picker
- Multi-select with lasso
- "Create Note" from selected blocks
- Block resize handles
- Right-click context menu

#### Phase 3: Connections & Advanced
- Draw connections between blocks (curved lines)
- Connection labels
- Minimap for canvas overview
- Multiple whiteboards (create new canvases, switch between them)
- Keyboard shortcuts (Delete, Cmd+D duplicate, Cmd+A select all)
- Export whiteboard as image

#### Phase 4: Future Ideas
- Sketch/draw blocks (PencilKit or custom)
- Collaboration (shared whiteboards)
- Templates (pre-arranged block layouts for brainstorming, planning, etc.)
- Smart grouping (auto-cluster nearby blocks)
- Linking whiteboard blocks to notes bidirectionally
- Audio block (record a voice memo, drops as a block)

### Tab Architecture

The Whiteboard tab fits into Cider's tab hierarchy as a distinct stage of thought:

| Tab | Purpose | Mental Mode |
|-----|---------|-------------|
| Home | Dashboard / overview | Orienting |
| Bookmarks | Things collected from the web | Collecting |
| Notes | Things written deliberately | Writing |
| **Whiteboard** | **Things dumped without thinking** | **Brainstorming** |
| Books | Long-form reading tracker | Reading |
| Todos | Actionable items and planning | Doing |

Content flows between tabs:
- **Whiteboard → Notes**: Select blocks, promote to structured note
- **Whiteboard → Bookmarks**: URL blocks could be saved as bookmarks
- **Notes → Whiteboard**: Could "send to whiteboard" to break a note apart for rethinking
- **Todos → Whiteboard**: Brain-dump tasks onto the board before organizing them

### Excalidraw as the Canvas Engine

> **Key decision:** Excalidraw IS the whiteboard surface — not a separate drawing tool. All whiteboard interaction (blocks, connections, drawing, zoom/pan) happens on the Excalidraw canvas. This replaces the custom canvas/block rendering described in the sections above.

Embed [Excalidraw](https://github.com/excalidraw/excalidraw) (MIT, React-based) in a WKWebView, same architecture as TipTap for the notes editor.

**Why this replaces a custom canvas:**
- Infinite canvas with zoom/pan — free
- Shapes, arrows, text, freehand drawing — free
- Connections between elements — free (Excalidraw's native connector tool)
- Hit testing, selection, drag, resize, lasso — free
- Hand-drawn aesthetic fits Cider's "brain dump" vibe perfectly
- JSON-based `.excalidraw` file format — easy to persist in vault

**Cider library items on the canvas:**
- Drag a bookmark/note/date card from the library onto the whiteboard → creates a custom Excalidraw element rendering the card
- Draw arrows between items, circle groups, annotate with freehand
- Custom Excalidraw element type: `cider-library-item` with `libraryItemID` in metadata
- On render, Swift bridge resolves the ID to current card data (title, thumbnail, etc.)

**Integration approach:**
- Bundle Excalidraw as a built JS app in `Resources/Excalidraw/` (like TipTap in `Resources/TipTapEditor/`)
- Load in WKWebView with `allowingReadAccessTo: NSHomeDirectory()`
- JS→Swift bridge: `sceneChanged` (JSON scene data), `itemDropped`, `exportRequested`
- Swift→JS: `loadScene(json)`, `exportAsPNG()`, `setTheme(dark)`, `addLibraryItem(id, position, cardData)`
- Store as `.excalidraw` JSON files in `~/CiderVault/Whiteboards/`
- Card preview: render thumbnail via `exportAsPNG()` on save

**What the custom data model above becomes:**
- `WhiteboardCanvas` simplifies to: `id`, `name`, `excalidrawJSON: Data`, `createdAt`, `updatedAt`
- `WhiteboardBlock`, `BlockContent`, `BlockStyle`, `WhiteboardConnection`, `ConnectionStyle` — all replaced by Excalidraw's native scene format
- Only custom extension: `cider-library-item` elements with `libraryItemID` in Excalidraw's `customData` field

**Bundle size:** ~2-3MB minified (acceptable for desktop app)

**Open questions:**
- Should each whiteboard folder get one canvas, or can users create multiple canvases?
- Excalidraw's toolbar vs Cider's toolbar — hide Excalidraw's and build a Cider-native one, or style Excalidraw's to match?
- Live card updates — when a bookmark title changes, does it auto-update on all whiteboards containing it?

### What's Shipped (Phase A)

As of R-19 Phase A, the following is implemented:

- **Excalidraw embedded in WKWebView** — full drawing/shapes/text/freehand canvas
- **Whiteboard as a tab type** — `SavedViewKind.whiteboard(canvasID)` on `SavedView`
- **Create from + button or Cmd+K** — "New Whiteboard" option in both flows
- **Auto-save** — debounced 1.5s scene saves to `~/CiderVault/Whiteboards/{id}.excalidraw`
- **Flush-save on tab switch** — no data loss when switching between tabs
- **Transparent canvas** — Cider's acrylic shows through
- **Trash/restore** — delete via TrashStorage with undo support
- **Singleton WKWebView** — shared across whiteboard tabs (same pattern as TipTap)

#### What's NOT Shipped Yet

- **No drag-and-drop from Cider library** — can't drag bookmarks/notes/images from sidebar onto canvas
- **No "Send to Whiteboard" action** — no right-click menu option on cards
- **No `cider-library-item` custom elements** — no linked card rendering on canvas
- **No theme sync** — always dark theme regardless of system appearance
- **No export** — can't export canvas as PNG/PDF
- **No clipboard capture flow** — copying text doesn't offer "Save to Whiteboard" toast

### Inspiration

- **Miro / FigJam** — infinite canvas with sticky notes and connections (but way heavier)
- **Apple Freeform** — Apple's own freeform canvas app
- **Milanote** — visual mood board / brainstorming tool
- **Kinopio** — spatial thinking tool with cards and connections
- **Excalidraw** — open-source virtual whiteboard with hand-drawn aesthetic
- **Real cork boards** — the analog version: pushpins, string, photos at angles

Cider's version is deliberately simpler and more personal. It's not a collaboration tool. It's your brain's overflow area, living inside the same floating panel as your bookmarks and notes.

---


## WORKSPACES Vision


> This document captures the product vision for Cider's organizational system: universal folders, saved view tabs, and search-to-tab flow.
>
> **Implementation Status:**
> - ✅ Phase 1 — Universal Folders (complete)
> - ✅ Phase 2 — Center Search Palette (complete)
> - ✅ Phase 3 — Custom Saved View Tabs (complete)
> - ~~🔲 Phase 4 — Projects UI~~ — **Removed.** Projects removed from UI and codebase. See decision below.
> - ✅ "New Tab" in +New popover (complete, Feb 2026)
> - 🔲 Phase 4 (new) — Saved View expansion: manual item refs + "Send to view" context action
> - 🔲 Phase 5 — Kanban display mode on Saved Views

---

### Design Decision: Projects Removed (Feb 2026)

Projects were removed from the UI because:

1. **Too much overlap with Saved Views.** Both produce a tab showing a curated list of items. The distinction wasn't meaningful enough at Cider's current scope.
2. **Scope creep risk.** The "project workspace" concept (Kanban, timelines, team collaboration) belongs to heavier tools like Linear or Notion — not what Cider is.
3. **Saved Views can absorb the use case.** Everything Projects was trying to do can be done via Saved Views with future enhancements (see roadmap below).

`ProjectStorage`, `Project` model, and `ProjectItem` model have been removed from the codebase. If the concept is revisited, the models would need to be recreated.

---

### Core Concept

Cider's organization has three layers, each serving a different intent:

| Layer | Intent | Persistence | Example |
|-------|--------|-------------|---------|
| **Folders** | "Where things belong" | Permanent | Restaurants, Design Resources, Work |
| **Projects** | "What I'm working on" | Persistent until archived | Game Room, New Website, Trip to Japan |
| **Search Tabs** | "What I'm looking for right now" | Ephemeral | "react hooks", "standing desks" |

#### The Lifecycle

```
Search → Tab → Project → Folder/Archive
```

1. **Search** spawns a temporary tab showing results.
2. You keep the tab open, maybe add items manually.
3. **Promote to Project** — saves it to the sidebar, now it's persistent.
4. Work on the project over days/weeks, adding bookmarks, notes, images.
5. When done, **archive** or **convert to folder** for long-term storage.

---

### Folders

**Purpose:** Long-term categorical organization. Filing cabinet for your digital life.

#### Key Properties
- **Universal** — hold both bookmarks AND notes (not bookmarks-only).
- **Hierarchical** — nested folder tree (already supported via `parentID`).
- **Permanent** — folders persist until you delete them.
- **Passive** — you file things away; folders don't imply active work.

#### Sidebar Location
Folders live in the sidebar under a "Folders" section, visible across all views.

#### Folder View (Implemented)
- Selecting a folder shows a **standalone FolderDetailView** — same rich card components as Home tab (BookmarkCard, NoteCardView, etc.)
- **Tab-independent** — the same folder view shows regardless of which tab was active
- **Tabs deselect** when viewing a folder — clicking any tab exits the folder view
- **Layout:** `ScrollView` with `LazyVStack(pinnedViews: [.sectionHeaders])` — cover image scrolls away, header (title + counts + FOLDERS toggle + sub-folder cards when expanded) sticks at top
- **Root folders** show cover image (if set), sticky header with sub-folder cards, then mixed items below
- **Leaf folders** show cover image (if set), sticky header, then mixed items
- **Empty folders** show header + empty state (no scroll needed)
- Supports all display modes (list, grid, masonry) — shares Home tab's display mode setting
- Drag-and-drop works: items can be dragged onto sub-folder cards or sidebar folders
- Bookmark detail modals open within the folder view; notes open as modal notes panel

#### Example Use Cases
- **Restaurants** folder with saved restaurant bookmarks + a note listing ones you've tried.
- **Design Resources** folder with inspiration links, color palette notes, tool bookmarks.
- **Work** folder with project docs, internal tool links, meeting notes.

#### Future: Folder Views
Folders could support different view modes beyond a flat list:
- **Kanban** — columns for status (Want to Try / Tried / Loved / Nah).
- **Grid** — visual card layout for browsing.
- **List** — compact sortable list.

---

### Projects (Removed — Feb 2026)

> Projects have been removed from the UI. The section below is retained for historical context and to inform any future revisit. See the design decision at the top of this doc.

**Original purpose:** Active workspaces for ongoing efforts. Workbench for things you're building or researching.

#### Key Properties
- **Persistent** — live in the sidebar under a "Projects" section. Closing a tab doesn't delete the project.
- **Active** — implies ongoing work. You're adding to them regularly.
- **Mixed content** — hold bookmarks, notes, images, quotes, links.
- **Openable as tabs** — click a project in sidebar to open it as a tab. Close the tab, project stays.
- **Tearable** — can be torn out as an independent floating window for focused research sessions.

#### Sidebar Location
Projects live in the sidebar under a "Projects" section, below Folders.

```
FOLDERS
  Restaurants
  Design Resources
  Work
    └── Internal Tools

PROJECTS
  Game Room
  New Website
  Trip to Japan
```

#### How Projects Differ from Folders
- **Folders** = categorical, where things *live* permanently. Static.
- **Projects** = goal-oriented, what you're *working on*. Dynamic, growing.
- A bookmark can be in a "Furniture" folder AND in a "Game Room" project.
- Projects are for collecting resources *for a purpose* — when the purpose is done, archive or convert.

#### Example Use Cases
- **Game Room** project — furniture bookmarks, inspiration images, budget note, store links. Tear it out when shopping online.
- **New Website** project — design references, framework docs, competitor sites, implementation notes.
- **Trip to Japan** project — flight bookmarks, hotel options, restaurant recs, itinerary note, packing list note.

#### Project Lifecycle
1. Created explicitly ("New Project") or promoted from a search tab.
2. Lives in sidebar Projects section.
3. Opened as a tab when you want to work on it.
4. Closed tab — project persists in sidebar.
5. When done: archive (hide from sidebar) or convert to folder (permanent storage).

---

### Saved Views — Future Roadmap

Saved Views are currently filter-only (dynamic). The roadmap expands them to absorb everything Projects was meant to do.

#### Phase 4 — Manual Item Refs ("Send to View")

Add `manualItemRefs: [LibraryEntityRef]` to `SavedView`. A saved view can then be:
- **Filter-driven** — content auto-populates from filter rules (current)
- **Manually curated** — items pinned explicitly by the user
- **Both** — filter provides the base set; manual refs add specific items on top

**"Send to view" context action** — right-click any item anywhere in the library → "Add to [View Name]" → pins it to that saved view's `manualItemRefs`. This is how users build curated collections without a separate "Projects" concept. A saved view with no filter spec and only manual refs is effectively a "collection tab."

This mirrors how Stacks already work (`matchRules` + `manualItemRefs`) — apply the same pattern to SavedView.

#### Phase 5 — Kanban Display Mode

Add `kanban` as a display mode option on Saved Views (alongside list, grid, masonry). Columns map to a user-chosen attribute — label, folder, status field, or a custom column set. Dragging a card between columns reassigns that attribute on the item.

Any saved view can become a Kanban — you don't need a separate "board" or "project" concept. A "Game Room renovation" Kanban is just a saved view in Kanban mode.

#### Create Tab from +New Popover ✅ Implemented (Feb 2026)

The "Tab" card fills the slot left by the removed "Project" card. The +New picker is now a full 3×2 grid: Bookmark, Note, Event, Contact, Folder, Tab.

**Flow:**
1. Click +New → popover opens
2. Click "Tab" card (icon: `rectangle.badge.plus`)
3. Name field — user types tab name (Create Tab button disabled until non-empty)
4. Content pills — four toggleable pills: **Bookmarks**, **Notes**, **Events**, **Contacts** (all selected by default = "Everything"; last one can't be deselected)
5. "Create Tab" — `SavedView` created with `isTabPinned: true` and selected `entityTypes` as `filterSpec`. Panel navigates immediately to the new tab.

**Two entry points for the same result:**
- **+New → Tab** — for users who know what they want upfront (name it, pick content type)
- **Search → Save as tab** — for users who discover a useful query mid-session

**Future refinements (not yet implemented):**
- "By label" and "By folder" filter pills in the creation form
- Folder picker integration so users can scope a tab to a specific folder at creation time
- "Unfiled items only" toggle — `requireUnfiled: Bool` on `SavedViewFilterSpec`, filters to items where `folderID == nil`

#### Inbox as a User-Created View

An "Inbox" is not a built-in concept — it's a saved view the user creates with the "Unfiled" filter enabled. This keeps the architecture simple: the inbox is just a filter, not a special mode.

**How to create one:**
1. +New → Tab → name it "Inbox"
2. Enable "Unfiled only" filter (once the `requireUnfiled` chip is implemented)
3. The tab now shows every item that hasn't been organized into a folder yet

**Workflow:** Capture freely without thinking about organization. Items land in the library with no folder. When you're ready to triage, open your Inbox tab and drag items into folders. As items get organized, they disappear from the Inbox view automatically.

This is the same approach as Resurf's inbox-first workflow, but opt-in and user-configured rather than forced.

---

### Search

**Purpose:** Find things across all of Cider, with results that can become persistent.

#### Live Search (Planned — Replaces Command Palette for Item Search)

The current search palette (Cmd+K overlay) shows results in a separate floating list. A better model: **search filters the current view in-place**.

**How it works:**
- Double-tap Option → panel opens → search field in title bar is auto-focused
- User starts typing immediately — no extra shortcut needed
- The current tab's content filters live as you type (same masonry/grid/list layout, just fewer items)
- Search "YouTube" on the Home tab → all YouTube bookmarks appear in the familiar card layout, scrollable and browsable
- Clear the search → full view returns instantly

**Why this is better:**
- Results stay in context — you see cards with thumbnails, not a flat list of titles
- You can browse filtered results (scroll, right-click, open details) just like normal
- No mode switch — search IS the view, not a separate overlay
- Double-tap Option + type = instant access to anything in your library

**Implementation:**
- `SavedViewFilterSpec.textQuery` already supports live text filtering in saved view tabs
- Extend this to the Home tab's library feed (bind a search field to `LibraryViewModel` filtering)
- Auto-focus the search field on panel open (with the existing 150ms delay for `@FocusState` in NSPanel)

**Command palette repurposed:**
- Cmd+K becomes an **action palette** — create note, open settings, switch tab, run shortcuts
- Item search moves entirely to the inline search field
- The action palette is a command runner (like Raycast), not a content finder

#### Search Flow (Current)
1. **Trigger** — Click search field in title bar, press Cmd+K, or type `/`.
2. **Center palette opens** — Zen-style overlay, blurs background content.
3. **Live results** — Split by type: bookmarks, notes, date cards, contacts. Debounced 100ms.
4. **Actions on results:**
   - Click → opens the item.
   - Enter → spawns a search tab showing all results for that query.

#### Result Display
- **Title match** → subtitle shows host URL (bookmark), first 80 chars of content (note), formatted date (date card), or relationship label (contact).
- **Body-only match** → snippet shown instead of subtitle: `…prefix **match** suffix…` where the matched portion renders in primary color and surrounding context in tertiary. Implemented via `SearchSnippet` struct + inline `AttributedString` in result rows.
- Fields searched per type:
  - **Bookmark:** title, URL, host, tags, notes field
  - **Note:** title, stripped HTML body
  - **DateCard:** title, details, location
  - **Contact:** displayName, relationshipLabel, notes

#### Search Tabs (Ephemeral)
- A search spawns a temporary tab in the tab bar.
- Shows mixed results across all content types (bookmarks, notes, date cards, contacts).
- Close anytime — nothing is lost, it's just a search view.
- Can be **saved as a Saved View** if the search turns into ongoing work.

#### Tab States

```
[Home] [📌 Design Inspo ×] [📌 Work ×] [🔍 "react hooks" ×] [📂 Cider Docs ×]
 fixed    saved view          saved view    search tab          external source
```

- **Home** — only fixed tab, always present, not closeable.
- **Saved View tabs** — user-created, persistent, closeable.
- **Search tabs** — ephemeral, closeable, show mixed search results.
- **External Source tabs** — linked filesystem directories, closeable.

---

### Cross-Cutting: Universal Sidebar

The folder sidebar is **universal** — visible across views, not scoped to bookmarks only.

#### Design Principle: Sidebar = Organization, Tab Bar = Views

- **Tab bar** shows *what you're looking at* — Home (your full library), plus saved views and search tabs the user creates
- **Sidebar** shows *how you've organized it* — folders and linked sources
- "All Items" was removed from the sidebar because it's a view, not a folder
- Clicking a folder opens a standalone folder view (deselects tabs)
- Clicking any tab exits the folder view and returns to tab content

```
FOLDERS
  Restaurants          (3 bookmarks, 1 note)
  Design Resources     (12 bookmarks, 2 notes)
  Work
    └── Internal Tools (5 bookmarks)

SOURCES
  📂 Cider Docs        (12 files)
```

- Clicking a folder opens a standalone folder view (deselects the current tab).
- Clicking any tab exits the folder view.
- Folders show item counts.
- Notes can be assigned to folders.

---

### Data Model Changes

#### Current State
- `Bookmark` has `folderID: UUID?` pointing to `Folder`.
- `Folder` has `parentID: UUID?` for nesting (renamed from `BookmarkFolder`).
- `Note` has `folderID: UUID?` — notes belong to folders.

#### Completed Changes

1. ✅ **Renamed `BookmarkFolder` → `Folder`** — folders are universal, not bookmark-specific.
2. ✅ **Added `folderID: UUID?` to `Note`** — notes can belong to folders.

#### Historical (Projects — Removed)

3. **`Project` model (dormant):**
   ```
   Project {
     id: UUID
     name: String
     createdAt: Date
     updatedAt: Date
     isPinned: Bool        // pinned = visible in sidebar always
     isArchived: Bool      // archived = hidden from sidebar
     searchQuery: String?  // if promoted from search, the original query
   }
   ```
4. **New `ProjectItem` model (join table):**
   ```
   ProjectItem {
     id: UUID
     projectID: UUID
     bookmarkID: UUID?     // one of these is set
     noteID: UUID?         // one of these is set
     addedAt: Date
     sortOrder: Int
   }
   ```
5. A bookmark/note can be in ONE folder but MULTIPLE projects.

---

### Folder Refinements (Planned)

#### Folder Rename
Right-click context menu on folders in the sidebar should include "Rename." Uses inline editing pattern — folder name swaps to a focused text field, Enter to save, Escape to cancel. Same pattern as card inline rename.

#### Folder Header with Title + Breadcrumb
FolderDetailView should have a header area showing:
- **Folder title** in heading font
- **Breadcrumb path** in smaller text below (e.g., "Work > Internal Tools > APIs")
- Breadcrumb is most useful when the sidebar is collapsed — provides context about where you are
- Each breadcrumb segment is clickable to navigate up

#### Folder Header Image
**Status: Implemented.**
Folders have optional cover images displayed at the top of FolderDetailView (Notion-style).
- 160pt banner, drag-to-reposition vertically (normalized 0.0–1.0 offset, persisted)
- Set/change/remove via right-click context menu on header or cover image
- Cover scrolls away when scrolling; header sticks via `LazyVStack(pinnedViews: [.sectionHeaders])`
- `CoverRepositionOverlay` NSViewRepresentable blocks `isMovableByWindowBackground` window drag
- Uses AppKit event loop (`window.nextEvent`) pattern (same as PanelEdgeResizeView)
- Image downsampled to 800px via `CGImageSourceCreateThumbnailAtIndex`
- Stored in `.folder-covers/` directory; `Folder.coverImagePath` + `coverImageOffsetY` on model
- NSOpenPanel for image picker requires `NSApp.activate(ignoringOtherApps: true)` before `runModal()` — non-activating panel doesn't give the file picker proper focus otherwise

#### Sub-Folders Section in Folder View
**Status: Implemented.**
- "FOLDERS >" toggle on the same line as the folder title (right-aligned, `SectionCollapseToggle`)
- Sub-folder cards are part of the sticky Section header — they pin while scrolling
- Collapsible with `.snappy` animation; state persisted
- Shows sub-folder cards in a compact grid (clickable to navigate deeper)
- Below the sticky header: the folder's own items (bookmarks + notes)

#### Sticky Header Readability (Unsolved)
The pinned folder header (title, counts, FOLDERS toggle, sub-folder cards) currently has no background.
Content scrolls visibly through/behind the header text, making it unreadable when cards overlap.

**Rejected approaches (avoid revisiting):**
- **Full-width acrylic background** (VisualEffectView + tint) — looks like an ugly solid dark bar, especially when nothing is scrolled under it
- **Scroll-triggered dark overlay** — same ugly bar, just delayed. Jarring when it appears.
- **Gradient fade below header** — doesn't help because content passes *through* the header text, not under the gradient
- **Frosted rail always-on** (blur + subtle tint + border) — ugly dark strip when no content underneath
- **Per-element backplates** (small dark pills behind each text element, overlap-triggered) — rejected, felt cluttered

**Still exploring:** Need a solution that provides readability without adding any visible surface when content isn't behind the header. Text shadow/glow on the header text is one untried option.

#### Folder Sorting Options
Folders need their own sort controls in the view options dropdown:
- Sort by: creation date, recently modified, title A-Z/Z-A
- Ascending/descending toggle
- Per-folder sort persistence (each folder remembers its preferred sort)

#### Custom Folder Icons
Allow users to change the folder icon in the sidebar:
- Right-click > "Change Icon" on any folder row
- Pick from SF Symbols or emoji
- Store as `iconName: String?` in `Folder` model
- Default to "folder.fill" for roots, "folder" for sub-folders

#### Sidebar Folder Drag Reorder & Nesting
Drag folders in the sidebar to:
- **Reorder** — change the display order of sibling folders
- **Nest** — drag a root folder onto another root folder to make it a child/sub-folder
- Drop indicators (line between items for reorder, highlight on folder for nesting)
- Hover-to-expand: hovering a collapsed folder during drag auto-expands it after a short delay

---

### Cross-Cutting Features

#### Multi-Select ✓
Implemented. Cmd-click toggles, Shift-click range-selects, Cmd+A selects all visible, Escape clears.

##### Drag & Drop ✓
When dragging a selected item, all selected items travel together and drop as a group.
Dragging an unselected item while others are selected drags only that single item.

**Fanned preview** (Finder-style):
- 1 item: normal single-card preview
- 2 items: 2-card fan
- 3+ items: 3-card fan + count badge (capsule, accent bg, white text) when total > 3
- Fan geometry: 6° rotation, 16pt X offset, 8pt Y offset per successive card
- Works across all tabs (Home, saved views, folders) and all display modes
- Mixed content: bookmarks and notes can be multi-dragged together (Home tab, folder views)

- Selection title bar replaces normal title bar: `[X] "N items selected" [Move to Folder ▾] [Delete]`
- Cards: accent border + `SelectionCheckmark` (top-left). List rows: `selectedFill` background + inline checkmark.
- State: `Set<String>` with type-prefixed IDs (`"bookmark-{uuid}"`, `"note-{uuid}"`) owned by CiderPanelView
- Clears on tab switch, folder switch, Escape, or X button
- Continue section (Home tab) excluded from selection
- Works in all display modes (list, grid, masonry) and all tabs (Home, saved views, folders)
- Escape key: hidden `Button` + `.keyboardShortcut(.escape)` — `.onExitCommand` doesn't work with `.nonactivatingPanel`
- Future: bulk tag, bulk export

##### Drag Out to External Apps

Currently drag providers only register internal Cider type identifiers (`com.cider.bookmark-id`, `com.cider.note-id`). External apps can't consume these. To enable drag-out, register standard UTTypes alongside the internal ones on the same `NSItemProvider`:

| Item type | Register | External behavior |
|---|---|---|
| Bookmark | `public.url` with the bookmark's URL | Browsers open the URL; Finder creates `.webloc` |
| Note | `public.file-url` with the `.md` file path | Editors, CLIs, Finder receive the actual file |
| Bookmark thumbnail | `public.file-url` with local thumbnail path | Image editors receive the image file |

Implementation notes:
- Add `provider.register(NSString(string: bookmark.urlString) as NSURL)` (or equivalent `public.url` registration) to each `bookmarkDragProvider` function
- Add `provider.register(note.fileURL as NSURL)` (or equivalent `public.file-url` registration) to each `noteDragProvider` function
- Internal Cider types stay registered so Cider-to-Cider drag (folder shelf, reorder) still works
- Multi-drag: register standard types on the primary item's provider; secondary items are internal-only
- Drag providers exist in 3 places: `BookmarksBrowserView`, `HomeDashboardView`, `FolderDetailView` — all must be updated

Use cases:
- Drag a bookmark onto a browser tab bar → opens the URL
- Drag a note onto Claude Code CLI → CLI reads the `.md` file path
- Drag a bookmark card onto Finder → creates a `.webloc` shortcut
- Drag a note onto a text editor → editor opens the markdown file

#### Undo System ✓
Reversible actions should support undo via a transient toast:
- Toast appears for ~5 seconds after destructive/organizational actions with an "Undo" button
- Actions that support undo: delete, move to folder, move to trash, bulk operations
- Single-level undo (undo the most recent action)
- Toast dismisses on timeout or manual dismiss; clicking "Undo" reverses the action immediately

**Implemented.** `CiderUndoManager` singleton tracks one pending `UndoAction`. Timer-driven 5-second progress bar with hover-to-pause matches the clipboard review toast pattern. Delete actions show an additional "Trash" button to open Settings → Storage. Toast position is user-configurable per toast type (capture toast and undo toast have separate position settings).

#### Trash System ✓
Deleted items go to a Trash instead of being permanently removed:
- **30-day retention** — items auto-purge after 30 days in trash
- Trash is accessible from **Settings → Storage** (not the sidebar)
- Trash view shows items with their deletion date and days remaining
- Actions in trash: Restore (moves back to original folder), Delete Permanently
- "Empty Trash" option for manual purge
- Items in trash don't appear in search results, Home feed, or folder views
- Affects both bookmarks and notes

**Implemented.** `TrashStorage` manages `.trash/` subdirectories inside each storage directory with JSON manifests. Bookmarks move image assets to `.trash/thumbnails|originals/`. Notes move `.md` files to `.trash/`. Retention is configurable (7/30/90 days or Never) in Settings → Storage. Auto-purge runs on launch.

#### Keyboard Navigation
Power-user keyboard shortcuts for the floating panel:
- **Arrow keys** to move between cards in grid/masonry (left/right/up/down)
- **Enter** to open the selected item
- **Delete/Backspace** to trash the selected item
- **Cmd+Shift+N** to create a new note
- **/** to focus the search field
- **Escape** to deselect or dismiss
- Visual focus ring on the currently selected card

#### Sorting Options
Global sort controls in ViewOptionsDropdown, available on all tabs:
- Sort by: creation date, recently modified, title A-Z
- Ascending/descending toggle
- Sort preference persisted per-tab in CiderConfig

#### Group By (Future)
Group items into visual sections within a view:
- Group by: date (Today, Yesterday, This Week, This Month, Older), type (bookmarks vs notes), domain (for bookmarks), tags (when implemented)
- Collapsible group headers
- Works alongside sorting (sort within each group)

#### Search Refinement (Future)
Enhance the search palette with:
- Type filter chips (Bookmarks, Notes, or both)
- Folder filter (search within a specific folder)
- Date range filter
- ✅ Token matching — query split into words, each must match independently. "nuts nerdy" finds "Nerdy Nuts". Uses `localizedStandardContains` for diacritic/case-insensitive matching ("cafe" → "Café").
- True fuzzy matching (Sublime Text / fzf style) — characters appear in order but not adjacently ("nrdnts" → "Nerdy Nuts"). Needs scoring to rank results by match quality. Useful for power users but produces noisier results than token matching. Consider as opt-in or for the command palette only.
- Recent searches list

#### Search Scope Modifiers (Future)

Currently the sidebar live search is scoped to whatever view is active — Home tab searches the full library, a folder view searches within that folder, a saved view tab searches within its filtered results. This is the right default. But power users may want to reach outside the current view without navigating away.

**`@`-prefix modifiers** in the search field change the scope on the fly:

| Modifier | Scope | Example |
|---|---|---|
| *(none)* | Current view (default) | `react hooks` — searches whatever is on screen |
| `@all` | Entire library | `@all react hooks` — searches everything regardless of current view |
| `@folder-name` | Named folder | `@Design Resources color palette` — searches within that folder |
| `@bookmarks` | All bookmarks | `@bookmarks typescript` — bookmarks only, any folder |
| `@notes` | All notes | `@notes meeting agenda` — notes only, any folder |

**Behavior:**
- Typing `@` shows an autocomplete dropdown of available scopes (folder names, type filters)
- The modifier is parsed and stripped before the text query runs — the rest of the string is the search term
- Modifier chip appears as a removable pill left of the search text (visual confirmation of active scope)
- Clearing the modifier (backspace through it or click the pill's ×) returns to default current-view scope
- Folder name matching is case-insensitive and supports partial matches (`@des` → suggests "Design Resources")

**Why this fits:**
- Keeps the single search field as the only entry point — no separate "search everywhere" UI
- Discoverable but not required — users who never type `@` get the same scoped search they already have
- Consistent with how other tools use prefix modifiers (Slack's `in:#channel`, Raycast's file filters)
- Composable with future modifiers: `@bookmarks @Design Resources` could mean "bookmarks in Design Resources folder"

**Not for immediate implementation** — this builds on top of the planned Live Search (above) and should come after that is solid.

**Gap: Linked Sources** — The sidebar live search currently does not filter linked source views (`SourceDetailView`). Source files are not wired to `sidebarSearchText`. This should be addressed alongside scope modifiers or as a standalone follow-up — add a `searchText` param to `SourceDetailView` and filter its file listing by title/content match.

#### macOS Services Integration

Register Cider as a macOS Services provider so users can right-click selected content in any app and send it to Cider.

**How it works:**
- Select text, a URL, or an image in any app → right-click → Services → "Send to Cider"
- Cider routes by content type:
  - **URL detected** → captured as a bookmark (triggers enrichment pipeline)
  - **Plain text** → created as a new note
  - **Image** → saved as a document/image (future Documents tab) or attached to a new note
- Capture toast confirms the action (reuses existing toast system)

**Implementation:**
- Register service in `Info.plist` with `NSServices` array (send types: `NSStringPboardType`, `NSURLPboardType`, `NSPasteboardTypePNG/TIFF`)
- Handle `NSPerformService` in AppDelegate — inspect pasteboard, route to `BookmarksStorage.capture()` or `NotesStorage.create()` based on content type
- URL detection reuses the existing `normalizedURL()` logic from `BookmarksStorage`
- No UI needed beyond the existing capture toast

**Complements existing capture flows:**
- Hotkeys (Opt+B, Opt+N) — fastest, muscle memory
- Clipboard monitoring — automatic, passive
- Drag & drop — visual, intentional
- **Services** — contextual, from any app's right-click menu

#### Card Customization Sliders (Future)
Additional sliders in ViewOptionsDropdown alongside the existing card size slider:
- **Padding slider** — adjust internal card padding (content density)
- **Spacing slider** — adjust gap between cards in grid/masonry (breathing room)
- These compound with the card size slider for fine-grained visual tuning

---

### Themed Folders

**Concept:** Folders can have a **theme** that transforms their entire visual presentation, card layout, and organizational features based on content type. A themed folder isn't just a collection of bookmarks — it becomes a specialized micro-app with an aesthetic and UX tailored to that content.

Default folders use the standard Cider card layout (BookmarkCard, NoteCardView). Themed folders replace this with a completely different visual system while keeping the same underlying data (bookmarks + notes + metadata).

#### Media Hub Theme

Transform a folder into a Netflix/Apple TV-style media browser. For saving movies, TV shows, documentaries, and anything you want to watch or have watched.

**Visual aesthetic:**
- Large poster-art cards (portrait orientation, like streaming service tiles)
- Hero banner at top — featured/pinned item with backdrop image, title overlay, genre tags
- Horizontal scrolling rows by category (Watching, Watchlist, Completed, Dropped)
- Card hover: subtle scale + metadata overlay (year, rating, runtime)
- Dark, cinematic feel — leans into the acrylic panel aesthetic

**Card enrichment:**
When you save an IMDB, Letterboxd, TMDB, or similar URL, Cider enriches the bookmark with:
- Poster artwork (high-res, portrait crop for the card)
- Backdrop image (for hero banner or detail view)
- Rotten Tomatoes / IMDB score
- Runtime, release date, genres, director, cast
- For TV shows: season/episode count, air status (ongoing/ended)
- Sources: TMDB API (free, comprehensive), OMDB API, or scrape from the bookmarked page

**TV show episode tracking:**
- Expand a TV show card to see seasons and episodes
- Mark episodes as watched/unwatched individually
- Track progress: "Season 2, Episode 4 of 10"
- Integration with **Trakt.tv** — sync watch status bidirectionally so marking something watched in Cider updates Trakt, and watching something on your TV updates Cider
- Episode cards show: title, thumbnail, air date, runtime, brief synopsis

**Smart organization:**
- Auto-categorize into sections: Watching, Watchlist, Completed, Dropped, Favorites
- Status is per-item (set via right-click or swipe gesture on cards)
- Sub-folders or smart sections by genre, year, rating
- "Up Next" section — shows with unwatched episodes, sorted by air date

**AI-powered features** (see AI_VISION.md):
- Similar show/movie suggestions based on what's in the folder ("You liked these 5 sci-fi shows, you might like...")
- Auto-genre classification from page content if metadata API misses it
- Natural language filter: "show me comedies from the 2010s I haven't watched"

**Data flow:**
```
User saves IMDB/TMDB URL → Cider captures bookmark
  → Detect media URL (domain or page structure)
  → Fetch metadata from TMDB API (poster, backdrop, scores, cast, episodes)
  → Store enriched metadata on bookmark model (extended fields)
  → Render with Media Hub card layout instead of standard BookmarkCard
  → Trakt.tv sync (if connected): push/pull watch status
```

#### Recipe Theme

Transform a folder into a visual recipe collection. For saving recipes from cooking sites, food blogs, YouTube cooking videos.

**Visual aesthetic:**
- Large food photography thumbnails (landscape, hero-style)
- Card overlay: recipe title, cook time, servings, difficulty
- Warm, appetizing color accents
- Cards feel like physical recipe cards — clean typography, ingredients visible

**Card enrichment:**
Most recipe sites use **Schema.org Recipe markup** (`application/ld+json`), which means structured data is already on the page:
- Recipe name, description, author
- Cook time, prep time, total time
- Servings / yield
- Ingredients list
- Step-by-step instructions
- Nutrition info (calories, macros)
- High-quality food photography
- Cider extracts this on capture — no API needed, it's in the page source

**Card layout variations:**
- **Photo card:** Full-bleed food image, title + time overlay at bottom (default)
- **Recipe card:** Split layout — image on left, ingredients list on right (for planning)
- **Compact list:** Title + time + thumbnail (for searching/browsing quickly)

**Useful features:**
- Ingredient aggregation — select multiple recipes, see combined ingredient list (meal planning / grocery list)
- Cooking mode — open a recipe full-panel with large text, step-by-step, screen stays on
- Tag by cuisine, meal type, dietary restrictions (AI auto-tag or manual)
- "Tried it" / "Want to make" status tracking
- Notes field per recipe for personal tweaks ("used less salt", "double the garlic")

#### Other Potential Themes (Future Exploration)

- **Reading List** — book covers, Goodreads integration, read/unread/reading status, page progress
- **Music** — album art grid, Spotify/Apple Music integration, playlist building
- **Travel** — map view with pinned locations, trip grouping, photos, itinerary timeline
- **Shopping** — price tracking, product images, purchase status, wishlists
- **Learning** — course cards, progress tracking, certificate display, learning paths

#### Architecture Implications

**Folder model changes:**
- `Folder.theme: FolderTheme?` — enum: `.default`, `.mediaHub`, `.recipe`, `.readingList`, etc.
- Theme is set via folder context menu ("Set Theme → Media Hub") or auto-suggested based on content

**Pluggable renderers:**
- `FolderDetailView` checks `folder.theme` and delegates to the appropriate renderer
- Each theme has its own card component, layout logic, and section organization
- Standard folder uses existing `BookmarkCard` / `NoteCardView`
- Media Hub uses `MediaCard`, `EpisodeRow`, `HeroCarousel`
- Recipe uses `RecipeCard`, `IngredientsList`, `CookingModeView`

**Extended metadata:**
- Bookmark model gets a flexible `metadata: [String: AnyCodable]?` field for theme-specific data
- Media Hub stores: poster URL, backdrop URL, scores, cast, episodes, watch status
- Recipe stores: ingredients, steps, cook time, servings, nutrition
- Metadata fetched on capture via theme-appropriate enrichment (TMDB API, Schema.org extraction, etc.)

**Third-party integrations:**
- Trakt.tv: OAuth flow in settings, background sync service
- Future: Goodreads, Spotify, etc. — same pattern (OAuth + sync service per integration)

---

### Implementation Priority

1. **Phase 1: Universal Folders** — Rename BookmarkFolder to Folder, add folderID to Notes, universal sidebar.
2. **Phase 2: Center Search Palette** — Cmd+K overlay with live cross-type results.
3. **Phase 3: Search Tabs** — Search results spawn tabs, tab management in tab bar.
4. **Phase 4: Projects** — Project model, sidebar section, promote-from-search, project tabs.
5. **Phase 5: Tear-off & Advanced** — Tear out project tabs as windows, kanban folder views, archiving.

#### Refinement Priority (Current Focus)

1. **Folder rename** — right-click context menu + inline editing in sidebar
2. **Multi-select** — shift/cmd-click selection with bulk operations
3. **Undo system** ✓ — transient toast with "Undo" button
4. **Trash system** ✓ — 30-day retention, restore/permanent delete
5. **Sorting options** — per-tab sort controls
6. **Folder header + breadcrumb** — title and navigation in FolderDetailView
7. **Sub-folders section** — collapsible sub-folder cards at top of folder view
8. **Sidebar drag reorder/nesting** — reorder and nest folders via drag
9. **Keyboard navigation** — arrow keys, enter, delete shortcuts
10. **Card customization sliders** — padding and spacing controls

---


## AI STRATEGY

AI Strategy & Architecture
Internal Product Document  ·  March 2026

Overview
Cider's AI strategy is built around a simple principle: give users the right level of AI for their comfort and needs, without forcing anyone into a subscription or cloud dependency. Every AI feature in Cider is opt-in, privacy-respecting, and additive — users can go deeper as they want, or ignore AI entirely.
This document captures the three-tier AI model, local model recommendations, fine-tuning strategy, and the competitive moat that open file formats create.

The Three-Tier AI Model
Cider supports three distinct AI tiers. Each tier serves a different type of user and requires zero compromise from the others.

Tier 1 — Apple Intelligence
Zero setup · Always available · Limited capability
Apple Intelligence is available to all users immediately with no configuration. It handles basic tasks like simple summarization, autocomplete, and light text processing. It's not powerful enough for smart tagging or meaningful content analysis, but it's a solid baseline for users who just want things to work.
Best for: Non-technical users who want basic AI assistance without any setup.

Tier 2 — Local Bundled Model
Opt-in download · ~1–2GB · On-device · No subscription
Users can opt in to download a small, capable language model that runs entirely on their Mac. Once downloaded, this unlocks real AI features inside Cider:
	•	Auto-tagging saved bookmarks and notes
	•	Summarizing long-form content on save
	•	In-app chat to ask questions about your vault
	•	Semantic search across saved content
	•	Smart sorting and filtering of captures
Everything runs on-device. No data leaves the machine. This is the privacy-first power tier for users who want real AI without any cloud dependency or ongoing cost.
Best for: Privacy-conscious users and people who want strong AI features without a subscription.

Tier 3 — CLI Power Users
No setup required · Bring your own LLM · Unlimited capability
Power users can skip the in-app AI entirely and interact with their Cider vault directly through the terminal using any LLM they choose — Claude, Gemini, Codex, or any other CLI-accessible model.
This works out of the box because Cider stores everything as real files on disk:
	•	Bookmarks → .webloc files
	•	Notes → .md files
	•	Images → .jpeg / .png
	•	Folders in the sidebar → actual folders in Finder
Any AI that can read files can work with a Cider vault. Users can tell their LLM to organize bookmarks, summarize notes, tag captures, or restructure their entire vault — and every change reflects instantly in Cider.
Best for: Developers, researchers, and power users who are already using AI tooling in the terminal.

Local Model Recommendations
For Tier 2, Cider needs a model that is small enough to be a reasonable download, fast enough to feel snappy on Apple Silicon, capable enough to handle summarization and tagging well, and permissively licensed for commercial bundling.

Recommended: Phi-4 Mini (Microsoft)
Phi-4 Mini is the current top recommendation for bundling with Cider. It punches significantly above its weight on structured tasks like classification, tagging, and summarization. Microsoft's license is permissive for commercial use, and it runs fast on Apple Silicon via MLX.
	•	Size: ~2GB
	•	License: MIT
	•	Strengths: Structured tasks, summarization, classification
	•	Runtime: MLX (Apple Silicon optimized)

Alternative: Qwen3 4B (Alibaba)
Qwen3 is a strong alternative with good multilingual support and solid reasoning for its size. Already proven on-device on iPhone 15 Pro Max, so Apple Silicon Macs will handle it easily. Good for summarization and chat.
	•	Size: ~2.3GB
	•	License: Apache 2.0 (commercial friendly)
	•	Strengths: Chat, multilingual, reasoning
	•	Runtime: llama.cpp or MLX

Alternative: Gemma 3 4B (Google)
Google's Gemma 3 is well-rounded and benefits from strong instruction-following. Apache 2.0 licensed, solid all-rounder for Cider's use cases.
	•	Size: ~2.5GB
	•	License: Gemma Terms of Use (commercial friendly)
	•	Strengths: Instruction following, general tasks

Runtime: MLX vs Ollama
For bundling with Cider, MLX is the recommended runtime. It's Apple's own framework, optimized specifically for Apple Silicon, and consistently faster than llama.cpp on M-series chips. It's also the most native-feeling integration for a macOS app.
Ollama is a viable alternative for users who already have it installed — Cider could detect an active Ollama instance and use it as a free upgrade path, falling back gracefully to the bundled model or Apple Intelligence if not present.

Training the Model for Cider
Full fine-tuning a model for Cider is overkill — the tasks are focused and well-defined enough that tight system prompts and few-shot examples get 90% of the way there. The strategy is prompt engineering first, fine-tuning only if needed.

Prompting Strategy by Task
Auto-Tagging
Provide the model with Cider's tag taxonomy as context, then ask it to classify. A system prompt like 'You are a personal knowledge management assistant. Given the following content, suggest 2-5 tags from this list: [tags]. Return only the tags as a comma-separated list.' works reliably with Phi-4 Mini and Qwen3.
Summarization
Few-shot examples work well here. Show the model 2-3 examples of a bookmark URL + page content + ideal Cider-style summary (1-2 sentences, no fluff). The model quickly learns the desired tone and length.
Smart Sorting
Ask the model to return structured JSON with a category, priority score, and suggested folder. Structured output prompting (asking for JSON explicitly) is well-supported by all recommended models.
In-App Chat
System prompt establishes the vault context: 'You are an assistant helping the user manage their personal knowledge vault. The vault contains the following items: [list]. Answer questions about their saved content and help them organize it.' Pass relevant file contents as context per query.

When Fine-Tuning Makes Sense
Fine-tuning becomes worth exploring if Cider develops a sufficiently large user base and collects (with consent) examples of good tagging and sorting decisions. A LoRA fine-tune on Phi-4 Mini with ~1,000 Cider-specific examples would likely produce noticeably better results for tagging and categorization than prompt engineering alone. This is a v2+ consideration.

The Competitive Moat: Open Files
Cider's most defensible advantage isn't the UI or the AI features — it's the file format philosophy. Everything in Cider is a real file in a real folder on the user's Mac. This creates a moat that locked-garden competitors cannot replicate without rebuilding from scratch.

Why This Matters
Most PKM tools trap user data in proprietary formats or cloud databases. Leaving Notion means export pain. Leaving Roam means wrestling with JSON. Leaving Craft means losing formatting. Cider users never face this problem — their vault is just a folder. They could delete Cider tomorrow and lose nothing.
Paradoxically, this is what makes users trust Cider enough to commit to it.

The AI Amplifier
Open file formats don't just create trust — they create a compounding AI advantage. Because the vault is plain files, any AI can interact with it without special integration:
	•	Claude Code agents can read and reorganize the vault
	•	Power users can prompt any LLM to restructure their notes
	•	Future AI tools Cider hasn't built yet will work automatically
	•	The vault is indexable, searchable, and portable across any tool
No competitor offering a closed format can claim this. A user's Cider vault gets more useful as AI tooling improves industrywide, with zero effort from the Cider team.

The Marketing Angle
This story is simple and resonant across all three user tiers:
	•	To the non-technical user: "Your data is yours. Always."
	•	To the privacy-conscious user: "Nothing leaves your Mac. Ever."
	•	To the power user: "Your vault is a folder. Your AI already knows how to use it."
One product, three clear value propositions, zero overlap. This is the kind of positioning that earns word-of-mouth in developer and privacy communities — exactly the audiences most likely to become Cider's early evangelists.

Summary
Cider's AI architecture is a tiered opt-in system that serves every type of user without compromise. The open file format philosophy is both the technical foundation and the competitive moat. Local AI — specifically MLX + Phi-4 Mini or Qwen3 — gives users real capability without cloud dependency. And power users don't need any of it, because their LLM already speaks the language of files.
The strategy is: start with what Apple gives you for free, go deeper when users want it, and never lock anyone in.

### Personal Dashboard / Recommendation Loop Vision

This is a Cider product direction, not a separate standalone app. The idea is strong enough to stand alone, but it fits Cider's second-brain mission best: Cider should become the user's personal dashboard for curated discovery, memory, projects, actions, and reminders.

Cider's long-term life-assistant surface should move beyond a single dense feed or Telegram digest. The preferred model is a calm, browseable, multi-tab dashboard that the user can check daily, every few days, or weekly. This dashboard should work in Cider Desktop and also be a strong fit for the Cider web app: desktop/local agents collect and sync dashboard cards, while the web app lets the user browse from anywhere.

Potential dashboard tabs:

- Tech / AI / vibe-coding tools
- Electronics and devices
- Sports
- Entertainment and media
- Comedy and live events
- Local events and places
- Cider / Chost / personal project ideas
- Projects / roadmaps / kanban / bugs

Each dashboard item should be a card with enough structure for both browsing and learning:

- title, source, URL, date, and topic
- short summary
- why Cider thinks it may matter to the user
- status: new, seen, saved, dismissed, reminded
- user feedback: rating, more like this, less like this, not interested
- actions: save article to Cider, save as lightweight memory, create event, create todo/reminder, open source, ask AI about it

Dashboard topics should be user-configurable rather than hardcoded. The user should be able to add, remove, reorder, hide, pin, or rename topic tabs as their interests change. A card may belong to multiple topics, and topics should be able to start broad (Tech, Sports, Entertainment) then become more specific (COSMIC DE, Mariners, AI app builders, comedy shows) as Cider learns.

Telegram should remain a lightweight command/notification surface. Examples:

- “What’s my tech dashboard news today?”
- “Anything new on COSMIC DE?”
- “Any Mariners news worth knowing?”
- “Save this to memory, not bookmarks.”
- “Create an event if Shane Gillis tickets go on sale near Seattle.”

The core product loop:

1. Cider/Hermes monitors trusted sources for user-interest topics.
2. Cider creates ranked dashboard cards instead of overwhelming Telegram with long digests.
3. The user rates, saves, dismisses, or turns cards into events/todos.
4. Saved items become permanent vault knowledge.
5. Events like local comedy shows, ticket-sale dates, sports games, or release dates can become Cider events/reminders.
6. User feedback tunes future recommendations and source weighting.

Project dashboards should use the same pattern for the user's own work. Cider can show per-project roadmaps, kanban boards, bug lists, open questions, recent commits, build/test status, stale tasks, and next suggested actions. Background/cron agents can periodically inspect project repos for code changes, docs changes, failing tests, new TODOs, or uncommitted work, then update project dashboard cards without spamming Telegram. If a project has not been touched, the dashboard can cheaply confirm that no code or docs changed since the last scan and keep the project status current without inventing work. This makes Cider not just a second brain for external information, but a living command center for the user's active projects.

Cider should also help prevent project documentation rot. Many active app projects accumulate large numbers of Markdown files: old plans, outdated specs, stale implementation notes, abandoned ideas, and docs that no longer match the code. Project dashboard agents should be able to audit Markdown-heavy projects, compare docs against recent code/git activity, flag likely-outdated or low-value files, suggest consolidation/archive candidates, and surface docs that need refresh. The goal is not automatic destructive cleanup; it is keeping project knowledge trustworthy and keeping the project moving.

For stale bugs or maintenance cards, Cider can support an escalation policy. If a bug has remained unfixed past a user-defined age or priority threshold, an agent can propose a fix plan, open a branch, run the relevant tests, and optionally implement the bug fix autonomously when the project policy allows it. Riskier changes should still require approval, but low-risk stale bugs can become agent-owned maintenance work instead of lingering forever.

Example project dashboard cards:

- “Cider: 3 files changed since yesterday; dashboard vision docs updated; no build run yet.”
- “Chost: continuation-session fix committed; consider adding a regression test around Hermes compaction.”
- “Cider Bugs board: 2 high-priority cards stale for 7+ days.”
- “Roadmap: next Not Started 1.0 item is X; ask before moving work into Implementing.”

Example target behavior: if a Shane Gillis show in Seattle or a ticket-sale announcement appears, Cider surfaces it as a dashboard card with actions to save the article, create an event, and set a reminder for ticket sales or show date. Telegram should only provide lightweight nudges such as “Dashboard updated: 3 high-signal items,” not the whole feed.


---


## RESURF COMPETITIVE ANALYSIS


> **Purpose:** Deep reference doc for comparing Cider and Resurf feature-by-feature. Use this when evaluating whether to adopt, adapt, or ignore patterns Resurf has solved. Updated Feb 2026 based on direct inspection of the Resurf app bundle (`/Applications/Resurf.app`).
>
> **Resurf version analyzed:** 1.107.1-beta.1
> **Resurf repo name internally:** `captureai` (the internal project name is CaptureAI)

---

### 1. Tech Stack

| | Cider | Resurf |
|---|---|---|
| **Framework** | SwiftUI + AppKit | Electron (Chromium + Node.js) |
| **Language** | Swift 6.2 | TypeScript + React |
| **Editor** | TipTap v3 (WKWebView) | TipTap v3 (Chromium WebView) |
| **Note storage** | Markdown files on disk | ProseMirror JSON blobs (proprietary vault) |
| **Data format** | Open (`.md`, Netscape HTML, JSON) | Opaque (custom vault, not human-readable) |
| **Panel behavior** | Native NSPanel, `.nonactivatingPanel` | Electron `BrowserWindow` (full focus steal) |
| **Animations** | Native SwiftUI springs | CSS transitions |
| **Acrylic/blur** | `NSVisualEffectView` | CSS `backdrop-filter` (low fidelity) |
| **Native bridge** | Pure Swift/AppKit | Thin Obj-C++ NAPI module for macOS Services |
| **Auto-update** | (not confirmed) | Squirrel |
| **Error tracking** | (not confirmed) | Sentry |
| **Analytics** | (not confirmed) | Custom telemetry + session tracking |

**Key takeaway:** Resurf's "native Mac feel" is CSS work inside Chromium. Cider's non-activating panel, spring physics, `NSVisualEffectView` acrylic, and zero-focus-steal behavior are impossible to replicate in Electron. This is a durable technical advantage.

---

### 2. Capture System

#### Activation

| | Cider | Resurf |
|---|---|---|
| **Primary shortcut** | Double-tap Option | `Cmd+Shift+C` (configurable) |
| **Spotlight/search** | (planned) | `Cmd+Shift+Space` (separate window) |
| **Screenshot capture** | (planned via OCR) | `Cmd+Shift+S` (native area selection) |
| **Per-type shortcuts** | Opt+B (bookmark), Opt+N (note) | Configurable per type (note, link, media, voice) |
| **Menu bar** | No | Yes — persistent menu bar icon |
| **macOS Services** | Yes (`CiderServicesProvider`) | Yes (Obj-C++ bridge, right-click "Send to Resurf") |

#### Capture Widget Flow

**Cider:** Single floating panel stays open persistently. Capture is contextual — you're already in the panel, you drop a URL or drag content in. No separate "capture mode."

**Resurf:** Dedicated capture widget that appears as a step-based flow:

```
select (300×225, centered)
    ├── note  (400×250, stays in place)
    ├── link  (400×188, stays in place)
    ├── voice (200×36, stays in place)
    └── attachment (350×433, stays in place)
→ success (260×50, centered, auto-dismisses)
```

Each step is a different Electron window size — the window physically resizes between steps. The `select` step is a type-picker; once you choose a type, the window morphs into that type's input form.

**Assessment:** Resurf's step-based capture widget is optimized for quick "get in, get out" capture without opening the full library. Cider's approach keeps everything in one persistent surface — good for power users, but there's a case for a lighter quick-capture mode that dismisses itself after saving (like Resurf's `success` step). **Worth considering for Cider:** a minimal "quick capture" mode that auto-dismisses after a successful save, distinct from the full panel.

#### What Can Be Captured

| Content Type | Cider | Resurf |
|---|---|---|
| **URLs / bookmarks** | ✅ Full (metadata, thumbnail, OG data) | ✅ (OG data, screenshot, article text) |
| **Plain text / notes** | ✅ | ✅ |
| **Images** | ✅ (drag-drop, clipboard) | ✅ |
| **PDFs** | 🔲 (Documents tab, future) | ✅ (native PDF viewer) |
| **Video files** | 🔲 (vision doc only) | ✅ (attachment type) |
| **Audio files** | ❌ | ✅ |
| **Voice recording** | ❌ | ✅ (dedicated capture step) |
| **Screen area capture** | 🔲 (OCR vision doc) | ✅ (`captureAreaWithNativeTool`) |
| **Tweet embedding** | ❌ | ✅ (`react-tweet`, renders tweets natively) |
| **YouTube** | 🔲 (transcript sync vision) | ✅ (content type exists) |
| **GIFs** | 🔲 (vision doc, low effort) | ✅ |
| **Todos / tasks** | ✅ (checkboxes in notes) | ✅ (dedicated `todo` content type) |
| **Files (generic)** | 🔲 (Documents tab) | ✅ |
| **macOS Services (right-click)** | ✅ | ✅ |

#### Link Processing Pipeline

**Cider:**
1. Fetch OG metadata (title, description, image)
2. Download and store thumbnail (`.thumbnails/`, `.originals/`)
3. Fallback chain if thumbnail unavailable

**Resurf:**
1. Fetch OG metadata
2. Take a **full screenshot of the rendered page** (not just OG image)
3. Extract article text via `@mozilla/readability`
4. Convert article HTML → Markdown via `turndown`
5. Run async AI pipeline: generate TLDR + compute vector embedding (if AI enabled)
6. Store all of it with the capture

**Key difference:** Resurf captures a rendered screenshot of the page, not just the OG image. This means every link capture has a visual snapshot of what the page actually looked like — immune to sites that don't set OG images. They also extract the full article body at capture time, so Reader Mode works even if the page goes offline later.

**Cider gap:** No page screenshot on capture. No article body stored at capture time. Reader Mode (planned) would need to re-fetch live. **High-value steal:** capture a page screenshot at bookmark time (using `WKWebView` screenshot API) and store the article body via Readability at capture — this makes both Reader Mode and web archival essentially free.

---

### 3. Data Model & Storage

#### The Core Data Unit

**Cider:** Two separate models — `Bookmark` and `Note`. Different storage backends, different features. Unified view via `LibraryItemV2` discriminated union in the Home feed.

**Resurf:** One unified `Capture` model for everything:

```typescript
type Capture = {
  id: string           // ULID
  type: "note" | "attachment" | "link"
  contentType: "note" | "tweet" | "link" | "youtube" | "image" |
               "video" | "audio" | "recording" | "todo" | "pdf"
  title?: string
  tags: string[]
  spaceKeys: string[]
  isPinned: boolean
  isHidden: boolean
  triageStatus: "inbox" | "later" | "archive"
  snoozeUntil?: number        // timestamp — defer to resurface later
  colorPalette: ColorInfo[]   // extracted dominant colors
  tldr?: string               // AI-generated summary
  embedding?: number[]        // vector embedding for semantic search
  processingStatus: "processing" | "completed" | "failed"
  content: NoteData | LinkPreviewData | AttachmentData
}
```

**Assessment:** Resurf's unified model is cleaner for filtering and mixed-content views. Cider's split model made sense early but creates friction in the Home feed (the `LibraryItemV2` union is the workaround). Worth considering a migration toward a unified model in a future major version.

**Notable fields Cider doesn't have:**
- `triageStatus` — explicit inbox/later/archive state machine (see section 7)
- `snoozeUntil` — defer a capture to resurface at a specific time
- `processingStatus` — async enrichment pipeline with failure tracking
- `isHidden` — soft-hide without deleting

**Fields Cider now has equivalents for:**
- `colorPalette` — ✅ `dominantColors` on Bookmark, extracted by `ColorExtractionService`
- `embedding` — ✅ NLEmbedding vectors stored via `EmbeddingStore`, used for related items

#### Storage Format

| | Cider | Resurf |
|---|---|---|
| **Notes** | `.md` files (human-readable) | ProseMirror JSON (opaque) |
| **Bookmarks** | Netscape HTML + JSON sidecar | Same vault (opaque) |
| **Vault** | Standard filesystem (no special format) | Custom "vault" directory with schema versioning |
| **iCloud sync** | ❌ | ✅ (`useICloud` flag, migration tooling built in) |
| **Obsidian compatible** | ✅ (primary integration) | ❌ |
| **Human-readable** | ✅ (any text editor can read it) | ❌ (app-dependent) |
| **Backup/export** | ❌ (planned) | ✅ (vault export, auto-backup, configurable frequency) |
| **Schema migration** | ❌ | ✅ (`_version` field, reindex pipeline) |
| **Data portability** | ✅ (open formats) | ❌ (proprietary) |

**Cider advantage:** Open formats are a genuine differentiator. Resurf's data is trapped in their app. Cider's notes are `.md` files that Obsidian, VS Code, or any editor can open. This is the correct long-term strategy — lean into it in marketing.

**Resurf advantage:** iCloud sync is built in. Cider has no sync story yet. This is a real gap for users with multiple Macs.

---

### 4. Organization System

#### Hierarchy

**Cider:**
```
Folders (hierarchical, user-defined)
  └── Items (bookmarks, notes, date cards, contacts)
Tags (flat, cross-folder)
Saved views (filter + layout configs, optionally pinned as tabs)
Stacks (dynamic query objects that surface in the feed)
```

**Resurf:**
```
Areas (groups of spaces — top-level organizer)
  └── Spaces (named collections, with icon + 20 color options, pinnable)
        └── Captures (items)
Tags (flat, cross-space)
Triage status (inbox / later / archive — orthogonal to spaces)
```

**Assessment:** Resurf's Area → Space hierarchy is roughly equivalent to Cider's folder hierarchy. The difference: Resurf's Spaces have first-class color + icon assignment (20 preset colors). Cider's folders don't have colors yet — this is low-hanging fruit for visual organization.

**Resurf's triage system** is worth a deeper look (see section 7).

#### Filters

| | Cider | Resurf |
|---|---|---|
| **By type** | ✅ (saved views can filter by entity type) | ✅ |
| **By tag** | ✅ | ✅ |
| **By folder/space** | ✅ | ✅ |
| **By date range** | 🔲 (planned in saved views) | ✅ |
| **By pinned** | ✅ | ✅ |
| **By triage status** | ❌ | ✅ |
| **Sort: random** | ❌ | ✅ (good for rediscovery) |
| **Sort: relevance** | ❌ | ✅ (AI-powered) |
| **Hidden items** | ❌ | ✅ (`isHidden` filter) |
| **Inbox only** | ❌ | ✅ |
| **Space item counts** | ❌ | ✅ (per-type counts per space) |

---

### 5. Triage System

This is one of Resurf's most thoughtful design decisions and deserves its own section.

**Resurf's model:** Every capture has a `triageStatus`:
- `inbox` — newly captured, needs attention
- `later` — acknowledged but deferred
- `archive` — processed, out of the way

Combined with `snoozeUntil` (a timestamp), captures can be deferred to resurface at a specific time — like email snooze applied to anything you save.

**Cider's current model:** No triage. Items land in the library and stay there. The Home tab's "Continue" section (8 most recent items) approximates an inbox but isn't explicit.

**Assessment:** The inbox/later/archive model is simple but powerful — it gives every capture an explicit lifecycle state. Combined with snooze, it turns Resurf into a "capture now, process later" system. This maps directly to Cider's planned `HOME_VISION.md` resurfacing concepts (engagement-based resurfacing, date card surfacing) but Resurf's approach is simpler and more explicit.

**Steal candidate:** Add `triageStatus` to both `Bookmark` and `Note` models. Create a dedicated "Inbox" sidebar entry that filters to `triageStatus == .inbox`. Make new captures default to inbox. "Archive" action moves to `.archive`. This solves the "library grows forever and becomes noise" problem without requiring AI.

---

### 6. In-App Viewing

This is the area where Resurf has the most to teach Cider.

#### Web Viewer

**Cider:** ✅ Embedded WKWebView in the bookmark detail panel's "Web" tab (shipped in R-14, Detail V2). Live page rendering inside the panel without leaving Cider.

**Resurf:** Full embedded web viewer — an Electron `BrowserView`/`WebContentsView` that renders live pages inside the app. You can browse the web without leaving Resurf.

**Assessment:** Both apps now have in-app web viewing. Cider's WKWebView approach is more memory-efficient than Resurf's Chromium WebView.

#### Reader Mode

| | Cider | Resurf |
|---|---|---|
| **Status** | ✅ Shipped (R-14, Detail V2) | ✅ Beta feature |
| **Parser** | Readability.js (`BookmarkReaderView`) | `@mozilla/readability` |
| **Rendering** | WKWebView | Chromium WebView |
| **Stored at capture** | ❌ (re-fetches on open) | ✅ (`articleContent` + `articleHtml` stored) |
| **Offline capable** | ❌ | ✅ (content stored at capture time) |

**Key difference:** Resurf stores the Readability-parsed article body at capture time. Cider's Reader Mode re-fetches and re-parses the live URL on each open. **High-value steal:** store `articleContent` and `articleHtml` at bookmark capture time (add to the enrichment pipeline). No extra work at reading time.

#### PDF Viewer

| | Cider | Resurf |
|---|---|---|
| **Status** | 🔲 Planned (Documents tab) | ✅ Beta feature (native PDF viewer) |
| **Implementation** | `PDFKit` (Apple native, planned) | Chromium's built-in PDF renderer |

**Assessment:** Cider's PDFKit path will produce a higher-quality native viewer. Chromium's PDF renderer is functional but it's not a native PDF experience. Cider has the advantage here once it ships.

#### Screenshot / Screen Capture

**Cider:** ✅ Implemented. `ScreenCaptureService` provides area-select capture (Opt+Cmd+2), `OCRService` runs `VNRecognizeTextRequest` for text extraction. OCR text routes to note/date card/contact creation via capture toast. R-20 (Screen Capture Polish) is in testing.

**Resurf:**
```typescript
captureAreaWithNativeTool: () => Promise<string | null>
captureNativeScreenshot: () => Promise<string | null>
hasScreenPermission: () => Promise<boolean>
```

They have a working native area-select screenshot capture that saves the image as an attachment. Requires Screen Recording permission.

**Assessment:** Near parity. Both apps ship screenshot capture with OCR. Cider's implementation routes captured text to typed cards (notes, date cards, contacts) via OCR — a more structured approach than Resurf's generic attachment.

#### Tweet Embedding

**Resurf:** Uses `react-tweet` to render tweets as styled embeds inside the app — not just a URL card but the actual tweet layout with avatar, text, metrics. Content type `tweet` is first-class in their schema.

**Cider:** Treats Twitter/X URLs as standard bookmarks with OG metadata.

**Assessment:** Tweet embedding is a niche feature but signals that Resurf thinks carefully about content-type-specific rendering. Cider's vision for content-aware rendering (the Detail V2 tabs: Preview, Reader, Web) can handle this implicitly via the Web tab — no need to special-case tweets.

---

### 7. Detail / Metadata Panel

#### Resurf's Approach
Based on their schema and window system, captures open in a dedicated detail view within the main app window. The metadata panel shows: title (editable), spaces, tags, notes field, source URL, color palette, TLDR (AI), creation/update dates. All sections are likely togglable or collapsible given the schema breadth.

#### Cider's Current Approach (V1)
`DetailPopoverPanel` — a secondary floating NSPanel that appears to the right of the main panel. Two-column: hero preview on left, metadata fields on right. Expands the main panel if needed (`expandCiderPanelForDetailModal`).

#### Cider's Planned Approach (V2, `BOOKMARKS_VISION.md`)
Three modes:
1. **Slide-out panel** — slides in from the right edge, content stays visible behind it
2. **Full panel** — takes over the entire content area
3. **Page view** — takes over everything including the tab bar

This is more sophisticated than anything Resurf shows. The V2 spec is already well-designed — it just needs to be built.

#### Side-by-Side Metadata Panel

| Metadata Field | Cider V1 | Cider V2 (planned) | Resurf |
|---|---|---|---|
| Title (editable) | ✅ | ✅ | ✅ |
| Folders/Spaces | ✅ | ✅ | ✅ |
| Tags | ✅ (comma text) | ✅ (chip UI) | ✅ (chip UI) |
| Notes/annotation | ✅ | ✅ | ✅ |
| Source URL | ✅ | ✅ | ✅ |
| Dominant colors | ✅ | ✅ | ✅ |
| TLDR / AI summary | ✅ (Foundation Models) | ✅ | ✅ (AI-generated) |
| Triage status | ❌ | ❌ | ✅ |
| Snooze | ❌ | ❌ | ✅ |
| Pin | ✅ | ✅ | ✅ |
| Hidden toggle | ❌ | ❌ | ✅ |
| Created / Updated | ✅ | ✅ | ✅ |
| Content tabs (Preview/Reader/Web) | ✅ | ✅ | ✅ (web viewer) |
| Reprocess / refresh | ❌ | ❌ | ✅ |

---

### 8. Editor

Both apps use TipTap v3. The architecture is nearly identical — a WKWebView/Chromium WebView running a TipTap instance with a JS↔native bridge.

| | Cider | Resurf |
|---|---|---|
| **Editor** | TipTap v3 | TipTap v3 |
| **Storage format** | Markdown (`.md` files) | ProseMirror JSON |
| **Serialization** | Custom markdown↔HTML round-trip | `@tiptap/markdown` |
| **Extensions** | Custom (hardbreak, link, highlight, tasks, underline, etc.) | Same set via `@captureai/shared` |
| **Image handling** | `<img>` tags in HTML paragraphs (avoids CommonMark HTML block edge case) | Not confirmed |
| **Singleton WebView** | ✅ (one WebView shared, moved between containers) | Not confirmed |
| **Formatting toolbar** | ✅ (flat strip, compact version planned) | Not confirmed |

**Notable:** Resurf stores notes as ProseMirror JSON, not markdown. This means their notes are not portable — you can't open them in Obsidian or any text editor. Cider's markdown-on-disk approach is strictly better for users who care about data ownership.

---

### 9. AI Features

| | Cider | Resurf |
|---|---|---|
| **AI model** | Apple Foundation Models (on-device, macOS 26+) + tiered fallback | OpenAI via Vercel AI SDK (BYOK only) |
| **Privacy model** | On-device first, cloud optional | Always off-device (BYOK, their servers aren't involved but OpenAI is) |
| **TLDR/summaries** | ✅ (Foundation Models on macOS 26+) | ✅ |
| **Vector embeddings** | ✅ (`EmbeddingStore`, NLEmbedding) | ✅ (stored per capture, enables semantic search) |
| **Auto-tagging** | ✅ (NLP keyword extraction in `BookmarkAIEnrichment`) | ❌ |
| **Semantic search** | ❌ | ✅ (via embeddings, sort by relevance) |
| **AI key required** | No (on-device works without) | Yes (BYOK, feature is off without a key) |
| **Space instructions** | N/A | ✅ (`instruction` field on Space — AI can use this as context) |

**Notable:** Resurf's `Space.instruction` field lets users give each space an AI instruction (e.g., "This space is for work research — always tag with project names"). This is a clever way to make AI behavior configurable without building a full prompt editor.

**Notable:** Resurf stores vector embeddings per capture (`embedding: number[]`). This enables semantic search (find things by meaning, not keywords) and similarity features ("related items"). These embeddings are computed at capture time in the background — no latency at search time.

**Cider advantage:** Cider's tiered AI approach (no-AI → Apple on-device → cloud API) is a better long-term strategy. Apple Foundation Models (macOS 26+) will provide AI features to all users without any API key or cost. Resurf's BYOK model means AI is only available to users willing to pay for OpenAI. This is a major adoption barrier.

---

### 10. Search

| | Cider | Resurf |
|---|---|---|
| **Keyword search** | ✅ (token-based, `localizedStandardContains`) | ✅ |
| **Semantic search** | ❌ | ✅ (via vector embeddings) |
| **Full content search** | ✅ (notes: full file content; bookmarks: title + URL + tags) | ✅ |
| **Filter by type** | ✅ | ✅ |
| **Filter by tag** | ✅ | ✅ |
| **Filter by date** | 🔲 | ✅ |
| **Sort by relevance** | ❌ | ✅ (AI-powered) |
| **Sort by random** | ❌ | ✅ (rediscovery use case) |
| **Spotlight integration** | ✅ (`SpotlightIndexer`, dormant in dev builds) | Not confirmed |
| **Search palette** | ✅ (`SearchService` + search tab) | ✅ (separate Spotlight window, `Cmd+Shift+Space`) |
| **Search snippets** | ✅ (`SearchSnippet` with prefix/match/suffix) | Not confirmed |

**Notable:** Resurf's "sort by random" is a simple but clever resurfacing tool. No AI required — just shuffle the library and surface things you've forgotten. Cider's `HOME_VISION.md` has a more sophisticated engagement-based resurfacing plan, but random sort could be added as a zero-effort first step.

---

### 11. Business Model

| | Cider | Resurf |
|---|---|---|
| **Current status** | Private, in development | Beta, publicly available |
| **Pricing** | TBD | License key (one-time or subscription, tiers confirmed in code) |
| **Free tier limits** | N/A | Yes — `FreeTierLimits: { captures: number, spaces: number }` |
| **Distribution** | TBD | Direct download (resurf.so), not yet on App Store |
| **Auto-update** | TBD | Squirrel (built in) |

**Notable:** Resurf has a license validation system with a cache token and failure count — suggesting they've dealt with offline validation edge cases. They also have `licenseValidationFailureCount` — after N failures the app presumably degrades gracefully rather than hard-locking.

---

### 12. Canvas / Whiteboard

**Resurf:** Canvas feature exists in the schema (with nodes, connections, annotations — text, rectangle, circle, arrow) but is behind a feature flag (`canvas: false` by default). Not shipped to users yet.

```typescript
type Canvas = {
  id: string
  name: string
  nodes: CanvasNode[]           // captures placed on a 2D canvas
  connections: CanvasConnection[] // links between nodes with labels
  annotations: CanvasAnnotation[] // text, shapes, arrows
}
```

**Cider:** Whiteboard tab is in the vision doc (`WHITEBOARD_VISION.md`), also not shipped.

**Assessment:** Both apps have whiteboard/canvas as a future feature. Neither has shipped it. Resurf's Canvas model shows captures as nodes (their unified model makes this natural — any capture can be placed on a canvas). Cider's Whiteboard will likely be freeform fragments (blocks of text, images, links) that can be promoted to notes.

---

### 13. What Resurf Does That Cider Should Steal

Ranked by implementation value vs. effort:

#### High Value, Low Effort

1. **Screenshot capture at capture time** — Store a page screenshot when bookmarking a URL. Makes thumbnails work for every site regardless of OG image. Immediate value, one WKWebView call. See `captureAreaWithNativeTool` pattern.

2. **Article body stored at capture time** — Run Readability at bookmark capture and store `articleContent` + `articleHtml`. Reader Mode becomes instant and offline-capable. Cider is already planning Readability — the only change is running it eagerly at capture vs. lazily at read time.

3. **Sort by random** — One line of code. Surfaces forgotten items without any AI. Fits directly into the `LibrarySortMode` enum.

4. **Capture triage: inbox/later/archive** — Add `triageStatus` to Bookmark and Note models. Default new captures to `.inbox`. Add an "Inbox" entry to the sidebar. This gives the library an explicit lifecycle that prevents it becoming a graveyard. Resurf's app name literally means "resurface" — this is their core product loop.

5. **Snooze on any item** — `snoozeUntil: Date?` on any item. Items with a future snooze date are hidden from the main feed until that time. Surfaces automatically when the time arrives. Powerful for "I'll deal with this on Monday" workflows.

6. **Space/folder color + icon** — Resurf has 20 color options per space with an icon picker. Cider's folders are uncolored. Color-coded folders are an immediate visual improvement for library navigation.

#### High Value, Medium Effort

7. ~~**In-app web viewer**~~ — ✅ Shipped (R-14 Detail V2, Web tab). Bookmarks open in embedded WKWebView inside the detail panel.

8. **Area screenshot capture (Cmd+Shift+S equivalent)** — Select an area of the screen and capture it as an image capture. Requires Screen Recording permission. Uses `SCScreenshotManager` or `CGWindowListCreateImage`. Resurf ships this, Cider doesn't.

9. **Processing status on captures** — `processingStatus: "processing" | "completed" | "failed"` gives users feedback that enrichment is happening. Currently Cider shows a shimmer but has no explicit "failed" state — failed enrichments are silently incomplete.

10. **Backup + auto-backup** — `autoBackup: true`, `backupFrequencyDays: 7`, `maxBackupCount: 1`. A periodic vault export to a zip file. Low complexity, high user trust. Resurf has this built in.

#### Lower Priority / Different Direction

11. **Voice recording capture** — Resurf has voice as a first-class capture type (dedicated widget step, 200×36 mini window). This is a meaningful differentiator but would require significant work (audio recording, transcription, playback). Worth tracking but not stealing immediately.

12. ~~**Vector embeddings**~~ — ✅ Shipped. `EmbeddingStore` uses NLEmbedding for on-device vector storage. `RelatedItemsView` shows similar items by cosine similarity.

13. **Space AI instructions** — `Space.instruction` field that gives AI context about what the space is for. Only relevant once AI is working. Low effort to add the field now, high value once AI is live.

14. **`isHidden` flag** — Soft-hide captures without deleting them. Different from archiving. Useful for suppressing items you don't want to see but don't want to lose.

---

### 14. What Cider Has That Resurf Doesn't

These are genuine Cider advantages — not features to copy but reasons why users should choose Cider:

1. **Open data format** — Notes are `.md` files, bookmarks are Netscape HTML. Readable in any editor, importable/exportable to anything. Resurf's data is locked in a proprietary vault.

2. **Obsidian integration** — Bidirectional vault sync, wikilinks, frontmatter preservation. Resurf has no Obsidian integration and cannot have one without a significant architecture change (their data model doesn't produce Obsidian-compatible files).

3. **Non-activating panel** — Cider never steals focus. The panel floats over your work without interrupting it. Electron apps always steal focus on window activation — this is a physical limitation of the platform, not a design choice.

4. **True native animations** — Spring physics, `NSVisualEffectView` acrylic, Core Animation. Not achievable in Electron.

5. **Spotlight indexing** — `SpotlightIndexer` integrates Cider's content with macOS Spotlight, Raycast, and Alfred. Resurf doesn't confirm this.

6. **Mixed content model** — Cider's `LibraryItemV2` handles bookmarks, notes, date cards, contacts, and stacks in a unified feed with calendar projection. Resurf is captures-only (no calendar, contacts, or structured date items).

7. **Stacks / smart surfacing** — Cider's stacks (dynamic query objects with surfacing rules, pin-until-done, remind-before) have no equivalent in Resurf. Resurf has `snoozeUntil` on individual items but no concept of a smart collection with surfacing logic.

8. **Bookmark-first identity** — Cider has deep bookmark features (masonry, thumbnails, Netscape HTML export, DataCards Obsidian export) that Resurf doesn't match. Resurf treats links as just another capture type — no special treatment for bookmark-specific workflows.

9. **Reader Mode + Web Archival planned as native** — When built, Cider's Reader Mode will use native `WKWebView` + Swift APIs. Web archival uses `WKWebView.createWebArchiveData()`. These will outperform Resurf's Chromium-based equivalents in memory and battery usage.

10. **Apple on-device AI (roadmap)** — Foundation Models will provide free, private, on-device AI to all Cider users on macOS 26+. Resurf's AI requires a paid OpenAI key and sends content off-device.

---

### 15. Summary Table

| Feature Area | Cider | Resurf | Notes |
|---|---|---|---|
| Panel behavior | ✅ Native, non-activating | ⚠️ Electron, focus-stealing | Durable Cider advantage |
| Animations/feel | ✅ Native springs + acrylic | ⚠️ CSS | Durable Cider advantage |
| Data portability | ✅ Open formats | ❌ Proprietary vault | Durable Cider advantage |
| Obsidian integration | ✅ | ❌ | Durable Cider advantage |
| Mixed content (notes + bookmarks + calendar) | ✅ | ⚠️ Captures only | Cider advantage |
| Screenshot at capture | ❌ | ✅ | Steal this |
| Article body at capture | ❌ | ✅ | Steal this |
| In-app web viewer | ✅ (Detail V2 Web tab) | ✅ | Parity |
| Area screenshot capture | ✅ Testing (R-20) | ✅ | Near parity |
| Reader Mode | ✅ (Detail V2 Reader tab) | ✅ Beta | Parity |
| PDF viewer | 🔲 Planned | ✅ Beta | Planned path is better (PDFKit) |
| Voice recording | ❌ | ✅ | Different direction |
| Triage (inbox/later/archive) | ❌ | ✅ | Steal this |
| Snooze | ❌ | ✅ | Steal this |
| Folder/space colors | ❌ | ✅ | Low effort, steal |
| Color extraction from images | ✅ (`ColorExtractionService`) | ✅ | Parity |
| Tweet embedding | ❌ | ✅ | Skip (Web tab covers it) |
| iCloud sync | ❌ | ✅ | Major gap, different problem |
| Auto-backup | ❌ | ✅ | Low effort, high trust signal |
| AI summaries | ✅ (Foundation Models, on-device) | ✅ BYOK | Cider's approach is better |
| Semantic/vector search | ✅ (NLEmbedding, on-device) | ✅ | Parity (different approach) |
| Sort by random | ❌ | ✅ | One-line steal |
| Processing status feedback | ⚠️ Shimmer only | ✅ Explicit states | Improve feedback |
| Canvas / Whiteboard | 🔲 Planned | 🔲 Behind flag | Both future |
| Stacks / smart surfacing | ✅ | ❌ | Cider advantage |
| Calendar / date cards | ✅ | ❌ | Cider advantage |
| Spotlight integration | ✅ (dormant) | Not confirmed | Cider advantage |
| macOS 14+ | ✅ | ✅ | Parity |
| Menu bar icon | ❌ | ✅ | Different philosophy |

---
