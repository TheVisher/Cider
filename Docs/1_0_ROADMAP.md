# Cider 1.0 Roadmap

> **This is the active roadmap from beta to 1.0 release.** The beta launch roadmap (`BETA_ROADMAP.md`) is complete and archived. Every agent session should check this doc first. If the user gets sidetracked with post-1.0 ideas, acknowledge and redirect.

**Created:** 2026-02-28
**Target:** Stable 1.0 release (out of beta)
**Guiding Principle:** Polish what exists, complete half-finished features, add new card types, nail distribution. No ambitious new systems until after 1.0.

---

## Process: How Features Ship

Same 5-gate process from the beta roadmap. Nothing is "done" until Gate 5.

```
Gate 1: IMPLEMENT     — Agent writes the code
Gate 2: CODE REVIEW   — Agent reviews for bugs, conventions, accessibility
Gate 3: USER TEST     — User (minivish) manually tests the feature, reports issues
Gate 4: FIX & POLISH  — Address any issues from testing and review
Gate 5: SIGN OFF      — User confirms it's good. Status -> Complete
```

### Status Legend
| Status | Meaning |
|--------|---------|
| `Not Started` | Work hasn't begun |
| `Implementing` | Agent is actively building |
| `In Review` | Code review in progress |
| `Testing` | User is manually testing |
| `Fixing` | Issues found, being addressed |
| `Complete` | User signed off. Done. |
| `Blocked` | Can't proceed — dependency or decision needed |

### Agent Rules

1. **Check this doc at the start of every session.**
2. **When the user asks "what should we work on next?"** — point to the next Not Started item in the current phase.
3. **When the user gets sidetracked** — acknowledge the idea, add it to the post-1.0 backlog at the bottom, and redirect.
4. **Never mark an item Complete** without user sign-off.
5. **After implementing**, do a code review (conventions, reduce motion, tokens, etc.).
6. **Update this doc** after each gate transition.
7. **Check `USER_FEEDBACK.md`** periodically for tester feedback that should be promoted to this roadmap.

---

## Phase 1: Infrastructure & Distribution

Must be solid before 1.0. Users need auto-updates and a proper install path.

### R-01: Sparkle Auto-Updater
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

### R-02: Mac App Store Listing
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

### R-03: Code Health Fixes ✅
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

### R-04: Vault Directory Migration ✅
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

## Phase 2: Complete & Polish Existing Features

Make everything that shipped in beta feel finished.

### R-05: Tag System Completion ✅
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

### R-06: Date Card Surfacing Completion
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

### R-07: AI Auto-Tag Quality ✅
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

### R-08: Keyboard Navigation ✅
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

### R-09: Notes Editor Polish ✅
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

### R-10: Custom Folder Icons ✅
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

### R-11: Drag Out to External Apps
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

### R-12: Clipboard Viewer ✅
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

### R-13: Advanced Search
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

### R-20: Screen Capture Polish
> Complete the screen capture flow — Date Card and Contact OCR routing is broken, and the feature needs general polish.

**Status:** `Testing`
**Priority:** Medium

**Scope:**
- ✅ **Fix Date Card OCR routing:** OCR detected dates + suggested title now passed through notification → NewItemPopover → EventCreationForm pre-fill
- ✅ **Fix Contact OCR routing:** OCR detected emails/phones + suggested title now passed through notification → NewItemPopover → ContactCreationForm pre-fill
- ✅ **Notes routing works:** Verified functional (OCR text → new note) — was already working
- ✅ **Image preview in capture toast:** Capture thumbnail shown in toast header (replaces camera icon)
- ✅ **Direct step navigation:** Screen capture toast buttons skip the item picker and go directly to the Event/Contact form
- **General UX polish:** Review the full capture flow end-to-end, fix any rough edges

---

### R-21: Keyboard Shortcuts Reference ✅
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

## Phase 3: Detail View & Media

Richer content display and media type support.

### R-14: Bookmark Detail View V2
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

### R-15: GIF, Video & Carousel Bookmarks
> Extended media type support beyond static images.

**Status:** `Testing` — GIF + carousel complete, video deferred to post-1.0
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

## Phase 4: New Card Types & Views

Expand Cider beyond bookmarks and notes.

### R-16: Books Card Type
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

### R-17: Todos Card Type
> Task cards that live in the library alongside everything else.

**Status:** `Not Started`
**Priority:** Medium

**Scope:**
- `TodoCard` model as new `LibraryItemV2` case
- Fields: title, checklist items (title + done), due date (optional), priority (optional)
- `TodoStorage` in vault (`~/CiderVault/Todos/`)
- Card view showing checklist with interactive checkboxes
- Quick-add from +New popover
- Shows in library feed, folders, search, tags
- Full todo system (daily lists, templates, recurring, views) deferred to post-1.0

---

### R-18: Documents Card Type
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

### R-19: Whiteboard Folder Theme
> Display a folder as a freeform canvas instead of list/grid/masonry.

**Status:** `Not Started`
**Priority:** Medium

**Scope:**
- New display mode on folders: Whiteboard (alongside list/grid/masonry)
- Infinite canvas with dot grid background
- Existing cards (bookmarks, notes, etc.) rendered as draggable blocks
- Drag to reposition, persist positions per item per folder
- Pan (scroll) and zoom (Cmd+scroll)
- Drag items from other folders/tabs onto the canvas
- Phase 2 (post-1.0): connections between blocks, lasso select, block rotation, export as image

---

## Stretch Goals

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

---

## Progress Dashboard

| ID | Feature | Phase | Status |
|----|---------|-------|--------|
| R-01 | Sparkle Auto-Updater | 1 | In Progress |
| R-02 | Mac App Store Listing | 1 | Not Started |
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
| R-15 | GIF/Video/Carousel Bookmarks | 3 | Testing |
| R-16 | Books Card Type | 4 | Not Started |
| R-17 | Todos Card Type | 4 | Not Started |
| R-18 | Documents Card Type | 4 | Not Started |
| R-19 | Whiteboard Folder Theme | 4 | Not Started |

**Completed:** 14/21

---

## Already Shipped (Beta)

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

---

## Post-1.0 Backlog

Everything here is tracked but not planned for 1.0. Ideas get promoted to the roadmap above based on user feedback and priorities.

### AI & Intelligence
| Item | Source | Notes |
|------|--------|-------|
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

### Notes
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

### Bookmarks
| Item | Source | Notes |
|------|--------|-------|
| Video bookmarks | R-15 | Drag-drop .mp4/.mov/.webm, thumbnail extraction via AVAssetImageGenerator |
| YouTube transcript sync | BOOKMARKS_VISION | Live captions, click-to-seek |
| PiP video player | BOOKMARKS_VISION | Mini-panel playback when panel closed |
| Richer import feedback | BOOKMARKS_VISION | Malformed file diagnostics |
| Thumbnail dimension settings | BOOKMARKS_VISION | User-facing 720/512/360px toggle |
| Bookmark sorting/filter chips | BOOKMARKS_VISION | Has thumbnail, no thumbnail, recent, tagged |
| Large-library performance pass | BOOKMARKS_VISION | Optimize for 1000+ bookmarks |

### Views & Organization
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

### Full Systems (card type expansions)
| Item | Source | Notes |
|------|--------|-------|
| Books: ISBN/barcode lookup | BOOKS_VISION | Goodreads/StoryGraph import |
| Books: progress tracking | BOOKS_VISION | Page tracking, reading dates |
| Books: highlight extraction | BOOKS_VISION | Kindle/Apple Books highlights |
| Books: statistics | BOOKS_VISION | Books/year, genre distribution |
| Books: shelf display mode | BOOKS_VISION | Books spine-out visual layout |
| Todos: daily lists | TODOS_VISION | Named lists, auto-archive, templates |
| Todos: recurring tasks | TODOS_VISION | Recurring structures |
| Todos: views (Today/Upcoming/All) | TODOS_VISION | Dedicated task views |
| Todos: note integration | TODOS_VISION | Pull checkboxes from notes into unified view |
| Todos: global hotkey capture | TODOS_VISION | Add todo without opening panel |
| Todos: natural language dates | TODOS_VISION | Parse "tomorrow", "next Friday" |
| Documents: filesystem watcher | DOCUMENTS_VISION | FSEvents directory monitoring |
| Documents: full-text search | DOCUMENTS_VISION | PDF text, image OCR |
| Documents: window-based capture | DOCUMENTS_VISION | Proxy icon drops, AX file path detection |
| Whiteboard: connections | WHITEBOARD_VISION | Draw lines between blocks |
| Whiteboard: lasso select | WHITEBOARD_VISION | Multi-select on canvas |
| Whiteboard: sketch/draw | WHITEBOARD_VISION | PencilKit blocks |
| Whiteboard: templates | WHITEBOARD_VISION | Brainstorming, planning layouts |
| Whiteboard: export as image | WHITEBOARD_VISION | PNG/PDF export of canvas |
| Whiteboard: clipboard capture flow | WHITEBOARD_VISION | Route text/images to whiteboard via toast |
| Whiteboard: Excalidraw engine | WHITEBOARD_VISION | Embed Excalidraw in WKWebView as drawing engine, .excalidraw JSON persistence |

### Drag & Drop
| Item | Source | Notes |
|------|--------|-------|
| Electron app drag-out (Discord, Slack) | R-11 | Rework internal drop detection so text payload can carry the URL instead of Cider ID |
| SavedViewTabContent drag providers | R-11 | Wire drag providers into saved view tab cards (needs selection state first) |

### Home & UX
| Item | Source | Notes |
|------|--------|-------|
| Today's activity summary | HOME_VISION | Dashboard widget |
| Streak / activity indicators | HOME_VISION | Visual usage feedback |
| Customizable widget layout | HOME_VISION | Choose which sections on Home |
| Pinned items section | HOME_VISION | Show pinned items at top |
| Search shortcut / recent searches | HOME_VISION | Persist recent queries |
| Continue section resurfacing | HOME_VISION | Mix 1-2 forgotten items into Continue alongside recents |

### Code Health & Refactoring
| Item | Source | Notes |
|------|--------|-------|
| Split BookmarksStorage (2,450 lines) | CODE_AUDIT 2026-03 | Extract BookmarkEnrichmentService (title/summary/favicon/color/image analysis) and BookmarkImageAssetManager (thumbnail/original/cover handling). Keep BookmarksStorage as persistence + CRUD facade. |
| Split CiderPanelView (2,450 lines) | CODE_AUDIT 2026-03 | Extract DetailPanelManager (detail state), EditorManager (note editing state), TabNavigationManager (tab/folder/source selection). Keep CiderPanelView as root layout + composition. |
| Split AppDelegate (1,400 lines) | CODE_AUDIT 2026-03 | Extract PanelManagerService (panels/positioning), HotkeyService (detector instances), ToastOrchestrationService (toast types + timers). Keep AppDelegate as lifecycle + init. |
| Monitor growing files | CODE_AUDIT 2026-03 | SettingsView (1,230), SavedViewTabContent (1,207), FolderSidebarView (1,080), NotesViewModel (1,057), FolderDetailView (1,007) — watch for crossing 1,500 lines |

### Infrastructure
| Item | Source | Notes |
|------|--------|-------|
| Collaboration | WHITEBOARD_VISION | Shared whiteboards |
| JSON full backup/restore | BETA_ROADMAP | Single-file export of everything |
| OPML format support | BETA_ROADMAP | RSS reader compatibility |
| Docs status audit | CODE_HEALTH | CH-D06: Multiple docs disagree on shipped status |

---

## Issues Log

Track issues found during review and testing. Reference the feature ID.

| Issue | Feature | Found During | Severity | Status | Notes |
|-------|---------|-------------|----------|--------|-------|
| | | | | | |
