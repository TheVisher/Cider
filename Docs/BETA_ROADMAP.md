# Cider Beta Roadmap

> **This is the single source of truth for what ships in beta.** Every agent session should check this doc first. If the user gets sidetracked, point them back here. If an item isn't on this list, it's post-beta.

**Created:** 2026-02-25
**Target:** Public beta via GitHub Releases (.dmg, notarized)
**Audience:** Anyone who saves things on a Mac

---

## Process: How Features Ship

Every feature goes through 5 gates. Agents MUST follow this process. Nothing is "done" until Gate 5.

```
Gate 1: IMPLEMENT     — Agent writes the code
Gate 2: CODE REVIEW   — Agent (or second agent) reviews for bugs, conventions, accessibility
Gate 3: USER TEST     — User (minivish) manually tests the feature, reports issues
Gate 4: FIX & POLISH  — Address any issues from testing and review
Gate 5: SIGN OFF      — User confirms it's good. Status → ✅ Complete
```

### Status Legend
| Status | Meaning |
|--------|---------|
| `⬜ Not Started` | Work hasn't begun |
| `🔨 Implementing` | Agent is actively building |
| `🔍 In Review` | Code review in progress |
| `🧪 Testing` | User is manually testing |
| `🔧 Fixing` | Issues found, being addressed |
| `✅ Complete` | User signed off. Done. |
| `⏸️ Blocked` | Can't proceed — dependency or decision needed |

### Agent Rules

1. **Check this doc at the start of every session.** Know what's in progress, what's next, what's done.
2. **When the user asks "what should we work on next?"** — point them to the highest-priority `⬜ Not Started` item in the current phase.
3. **When the user gets sidetracked** with new feature ideas or unrelated polish — acknowledge the idea, suggest adding it to the post-beta backlog, and redirect: *"That's a good idea for post-beta. Right now we're on [current item]. Want to finish that first?"*
4. **Never mark an item ✅ Complete** without user sign-off. Only the user moves items to ✅.
5. **After implementing**, immediately do a self code review (or request a `/review` agent). Check: conventions compliance, reduce motion, CiderColors/CiderFont tokens, no hardcoded values, no `.contextMenu` in lazy containers, spring animations only.
6. **Update this doc** after each gate transition. Add dates and notes.
7. **If an issue is found during review or testing**, document it in the Issues Log (bottom of this doc) with a reference to the feature.

---

## Phase 0: Foundation

These are structural changes that define how users interact with Cider. Must ship before any user touches the app.

### F-01: Cider Vault Storage
> Consolidate all storage into a single "Cider Vault" root directory with per-type subdirectories, each individually overridable.

**Status:** `✅ Complete`
**Priority:** Critical — must be first (all other features build on this)

**Scope:**
- Default root: `~/CiderVault/`
- Subdirectories: `Notes/`, `Bookmarks/` (thumbnails + originals inside), `Contacts/`, `DateCards/`, `Stacks/`, `Labels/`, `SavedViews/`, `Sources/`, `Tags/`
- Each subdirectory path individually overridable in CiderConfig (e.g., point Notes → Obsidian vault)
- StoragePaths refactor: per-type directory resolution with override support
- Settings UI: "Vault Location" main picker + expandable per-type override pickers
- All existing storages use the new paths
- CiderConfig migration: old `ciderDataDirectory` / `notesDirectoryPath` → new vault structure

**Testing checklist:**
- [x] Fresh launch creates vault structure at default location
- [x] Per-type override works (e.g., point Notes elsewhere)
- [x] All storages read/write from correct locations
- [x] Settings UI shows correct paths and overrides
- [x] Trash: delete + undo for each item type
- [ ] Vault relocation via Settings (deferred — confident it works given override testing)

**Gate log:**
| Gate | Date | Agent/User | Notes |
|------|------|------------|-------|
| Gate 1: Implement | 2026-02-26 | Claude | StoragePaths enum, CiderConfig vault props, all 8 storages, TrashStorage, Settings UI |
| Gate 2: Code Review | 2026-02-26 | Claude | Thread-safe cache (NSLock fix for EXC_BAD_ACCESS), cached paths in view closures |
| Gate 3: User Test | 2026-02-26 | minivish | Bookmarks + notes migrated, override tested, data migration noted as post-beta |
| Gate 5: Sign Off | 2026-02-26 | minivish | Signed off. Vault relocation deferred to post-beta. |

---

### F-02: Tab System Overhaul
> Replace fixed Home tab with a fully flexible tab system. All tabs are saved views — draggable, sortable, renameable, closeable.

**Status:** `✅ Complete`
**Priority:** Critical — defines core navigation
**Depends on:** F-01 (SavedViews stored in vault)

**Scope:**
- Remove fixed `.home` tab from CiderTab enum — everything is `.savedView`
- Default first-launch tabs: **Inbox** (leftmost, filter: `onlyUnassigned`) + **Library** (everything, no filter)
- CiderTabBar: drag-to-reorder, right-click to rename/close, `+` button at right end
- Tab order persisted in SavedViewStorage (tabOrder: [UUID])
- `+` button creates blank tab with welcome page and onboarding hints
- Per-tab entity filter, sort mode, and unassigned toggle (stored on SavedView)
- Deleting all tabs shows an empty state with prompt to create one
- Inbox is just a saved view — users can rename to "Unsorted", "Triage", whatever they want
- "Unassigned Only" toggle in ViewOptionsDropdown for recreating Inbox-style tabs

**Testing checklist:**
- [x] First launch shows Inbox + Library tabs
- [x] Inbox shows only items with no folder assigned
- [x] Library shows all items
- [x] Tabs can be dragged to reorder
- [x] Right-click tab to rename works (auto-focuses text field)
- [x] Right-click → Close Tab removes tab
- [x] `+` button creates blank tab with welcome page
- [x] Tab order persists across launches
- [x] Renaming persists across launches
- [x] Capture from browser → item appears in Inbox
- [x] Assign item to folder → item disappears from Inbox
- [x] Per-tab view options (sort, filter, unassigned) independent per tab

**Gate log:**
| Gate | Date | Agent/User | Notes |
|------|------|------------|-------|
| Gate 1: Implement | 2026-02-26 | Claude | Remove .home, add tabOrder, per-tab state, blank tab welcome, drag/rename/close |
| Gate 3: User Test | 2026-02-26 | minivish | Multiple rounds: fixed routing through HomeDashboardView, gesture conflicts, per-tab bindings, blank tab UX |
| Gate 4: Fix & Polish | 2026-02-26 | Claude | Right-click rename via .contextMenu, removed hover X, per-tab filter/sort bindings, blank tab empty entity types |
| Gate 5: Sign Off | 2026-02-26 | minivish | All tests pass. Signed off. |

---

## Phase 1: Core Features

These make the beta feel complete. Without them, users would say "this is missing something obvious."

### F-03: Full Tag System
> Tags as a first-class organizational primitive. View, filter, create, manage, and auto-generate via AI.

**Status:** `✅ Complete`
**Priority:** High — core organization alongside folders
**Depends on:** F-01 (TagStorage in vault)

**Scope:**
- **Model:** Tag (id: UUID, name: String, color: String?, createdAt: Date)
- **Storage:** TagStorage.swift (JSON in vault `/Tags/` dir)
- **Entity integration:** Add `tagIDs: [UUID]` to Bookmark, Note, DateCard, ContactCard models. Migrate existing Bookmark `tags: [String]` (AI-generated) to Tag references.
- **Card UI:** Tag pills on BookmarkCard, NoteCardView, DateCardCardView, ContactCardCardView. Tappable to filter.
- **Sidebar:** "Tags" section below Folders. List of tags with color dots. Click to filter library. Multi-select for combining.
- **Manual tagging:** Context menu → "Add Tag" / "Remove Tag" on any card. Tag picker in detail views.
- **Tag management:** Dedicated sheet/view: rename, delete, set color, merge duplicates.
- **Saved views:** Tag-based filter support (filter by tag = instant smart folder).
- **AI integration:** Existing NL auto-tagging creates Tag objects (not raw strings). Suggest tags on capture.

**Testing checklist:**
- [x] Create tag from sidebar
- [x] Assign tag to bookmark, note, date card, contact
- [x] Tag pills visible on all card types
- [x] Click tag in sidebar filters library (multi-select, clear all, show more/less)
- [x] Remove tag from item via context menu
- [x] Rename tag — all references update
- [x] Delete tag — removed from all items
- [x] Set tag color — pills reflect color
- [ ] Merge two tags — items consolidated *(deferred to post-beta)*
- [x] AI auto-tag on bookmark capture creates Tag objects *(works but needs tuning — deferred)*
- [ ] Create saved view filtered by tag *(deferred to post-beta)*
- [x] Tags persist across launches

**Gate log:**
| Gate | Date | Agent/User | Notes |
|------|------|------------|-------|
| Gate 1: Implement | 2026-02-27 | Claude | CardLabel model, CardLabelStorage, tag pills, sidebar tags, tag manager tab, context menu tagging, detail view tagging, AI NLPipeline rewrite |
| Gate 3: User Test | 2026-02-27 | minivish | Core tag CRUD all passes. Requested multi-select sidebar filtering, clear all, show more. AI tagging needs tuning (deferred). |
| Gate 4: Fix & Polish | 2026-02-27 | Claude | Multi-select tag filtering (Set<UUID>), Clear button, Show More/Less pill with threshold, tag creation form in +New popover and tag manager |
| Gate 5: Sign Off | 2026-02-27 | minivish | Signed off. Merge tags and saved view tag filter deferred to post-beta. AI tag quality deferred. |

---

### F-04: Cmd+K Quick Actions
> Enhance the search palette with quick action commands alongside search results.

**Status:** `⬜ Not Started`
**Priority:** Medium
**Depends on:** F-06 (CH-C08 fix for clickable search results)

**Scope:**
- Actions section above search results in SearchPaletteView
- Built-in actions: New Bookmark, New Note, New Date Card, New Contact, New Folder, New Tag, Open Settings
- Actions filter by query text (type "new" → show all "New X" actions; type "set" → show Settings)
- Execute on Enter/click: perform action (create item, open sheet, navigate)
- Keyboard navigation: arrow keys move through actions then results seamlessly

**Testing checklist:**
- [ ] Cmd+K opens palette
- [ ] Empty query shows action suggestions
- [ ] Typing "new" filters to creation actions
- [ ] Selecting "New Bookmark" triggers capture flow
- [ ] Selecting "New Note" creates and opens note
- [ ] Selecting "Open Settings" navigates to settings
- [ ] Arrow keys navigate actions → results seamlessly
- [ ] Escape closes palette

**Gate log:**
| Gate | Date | Agent/User | Notes |
|------|------|------------|-------|
| | | | |

---

### F-05: Date Card Surfacing
> Date cards with approaching dates are visually surfaced in the library feed so users don't miss important dates.

**Status:** `⬜ Not Started`
**Priority:** High — the core value of date cards

**Scope:**
- LibraryViewModel: compute `isApproaching` flag for date cards where `startAt` is within N days (default 7, configurable)
- Visual indicator on DateCardCardView: accent border or "Coming Up" badge
- Library feed: approaching date cards float toward top (or pinned section)
- Optional: "Coming Up" section in Library tab (like Continue section) showing approaching dates
- Configurable: `dateCardSurfacingDays` in CiderConfig (default 7)
- Overdue date cards (past date, not completed) get a different indicator ("Overdue")

**Testing checklist:**
- [ ] Date card with date in 3 days shows "Coming Up" indicator
- [ ] Date card with past date shows "Overdue" indicator
- [ ] Approaching date cards appear near top of library feed
- [ ] Completed date cards don't surface
- [ ] Configuring surfacing window changes behavior
- [ ] Date cards beyond the window show normally (no badge)

**Gate log:**
| Gate | Date | Agent/User | Notes |
|------|------|------------|-------|
| | | | |

---

## Phase 2: Bug Fixes

Known issues that would frustrate beta users.

### F-06: Fix CH-C08 — Search Results for Date Cards/Contacts
> Clicking a date card or contact in search results should open their detail/edit view.

**Status:** `⬜ Not Started`
**Priority:** High

**Scope:**
- SearchPaletteView: selection handler for `.dateCard` and `.contact` results opens detail sheet or navigates to detail view
- SearchTabContent: same — selection opens detail flow
- Reuse existing DateCardDetailView and ContactDetailView

**Testing checklist:**
- [ ] Search for a date card → click result → detail view opens
- [ ] Search for a contact → click result → detail view opens
- [ ] Works in both palette (Cmd+K) and search tab

**Gate log:**
| Gate | Date | Agent/User | Notes |
|------|------|------------|-------|
| | | | |

---

### F-07: Fix CH-C04 — Select All Includes All Entity Types
> Cmd+A should select date cards and contacts alongside bookmarks and notes.

**Status:** `⬜ Not Started`
**Priority:** Medium

**Scope:**
- `selectAll()` in CiderPanelView: iterate visible LibraryItemV2 items (all 4 types)
- Bulk operations (move, delete) must handle all entity types

**Testing checklist:**
- [ ] Cmd+A in Library selects bookmarks, notes, date cards, contacts
- [ ] Bulk delete works for mixed selection
- [ ] Bulk move-to-folder works for mixed selection (bookmarks + notes only — date cards/contacts don't have folders)

**Gate log:**
| Gate | Date | Agent/User | Notes |
|------|------|------------|-------|
| | | | |

---

## Phase 3: Ship Prep

### F-08: First-Run Experience
> New users need to know how to activate and use Cider.

**Status:** `⬜ Not Started`
**Priority:** High — without this, users won't know double-tap Option exists

**Scope:**
- Detect first launch (flag in CiderConfig)
- 2-3 screen onboarding overlay:
  1. "Double-tap Option to open Cider anytime" (with animation showing the gesture)
  2. "Capture from your browser" (show capture button / hotkey)
  3. "Organize with folders and tags" (show sidebar)
- Dismissable, skip button, never shows again
- Optional: re-trigger from Settings → About → "Show Onboarding"

**Testing checklist:**
- [ ] First launch shows onboarding
- [ ] Each screen is clear and informative
- [ ] Dismissing marks it as seen (doesn't reappear)
- [ ] Can re-trigger from Settings
- [ ] Doesn't interfere with panel functionality

**Gate log:**
| Gate | Date | Agent/User | Notes |
|------|------|------------|-------|
| | | | |

---

### F-09: Distribution Pipeline
> Code signing, notarization, .dmg packaging, GitHub Releases.

**Status:** `⬜ Not Started`
**Priority:** Critical — can't ship without this

**Scope:**
- Xcode project: release build configuration, proper Info.plist versioning
- Code signing with Apple Developer certificate
- Notarization via `notarytool`
- .dmg creation (drag app to Applications)
- GitHub Release with .dmg attached
- Automate with script or Makefile for repeatable releases
- Version numbering: 0.1.0-beta.1

**Testing checklist:**
- [ ] Release build compiles without warnings
- [ ] App is properly code signed
- [ ] App is notarized (passes Gatekeeper)
- [ ] .dmg opens cleanly with drag-to-Applications
- [ ] App launches from Applications folder
- [ ] GitHub Release page shows correct version and .dmg download

**Gate log:**
| Gate | Date | Agent/User | Notes |
|------|------|------------|-------|
| | | | |

---

### F-10: Landing Page & README
> What users see when they find Cider. Clear value prop, screenshot, download link.

**Status:** `⬜ Not Started`
**Priority:** Medium

**Scope:**
- GitHub README.md: one-liner, key features, screenshot/GIF, download link, "Beta" badge
- Optional: simple landing page (GitHub Pages or standalone)
- In-app: "Send Feedback" link in Settings → About → opens GitHub Issues
- GitHub Issues templates: Bug Report, Feature Request

**Testing checklist:**
- [ ] README is clear and compelling
- [ ] Screenshot/GIF shows the panel in action
- [ ] Download link points to latest release
- [ ] "Send Feedback" in app opens browser to GitHub Issues

**Gate log:**
| Gate | Date | Agent/User | Notes |
|------|------|------------|-------|
| | | | |

---

## Progress Dashboard

> Quick glance at where we are. Update this as items move through gates.

| ID | Feature | Phase | Status | Current Gate |
|----|---------|-------|--------|-------------|
| F-01 | Cider Vault Storage | 0 | ✅ Complete | Gate 5 |
| F-02 | Tab System Overhaul | 0 | ✅ Complete | Gate 5 |
| F-03 | Full Tag System | 1 | ✅ Complete | Gate 5 |
| F-04 | Cmd+K Quick Actions | 1 | ⬜ Not Started | — |
| F-05 | Date Card Surfacing | 1 | ⬜ Not Started | — |
| F-06 | Fix CH-C08 (Search Results) | 2 | ⬜ Not Started | — |
| F-07 | Fix CH-C04 (Select All) | 2 | ⬜ Not Started | — |
| F-08 | First-Run Experience | 3 | ⬜ Not Started | — |
| F-09 | Distribution Pipeline | 3 | ⬜ Not Started | — |
| F-10 | Landing Page & README | 3 | ⬜ Not Started | — |

**Completed:** 3/10
**In Progress:** 0/10

---

## Already Shipping (No Work Needed)

These are built, tested through development, and ship as-is:

- Floating panel (NSPanel, double-tap Option, all-edge resize, compact mode)
- Bookmark capture (browser, clipboard, drag-drop, Opt+B hotkey)
- Notes editor (TipTap/ProseMirror, inline editing, formatting toolbar)
- Folders (hierarchical, universal, cover images, sticky headers)
- Display modes (list/grid/masonry + continuous card size slider)
- Multi-select + drag-drop + fanned preview
- Trash & undo (30-day retention, 5-second toast, configurable)
- AI enrichment (auto-tagging, embeddings, OCR, color extraction, page summaries)
- Reader mode (Readability.js + Foundation Models)
- Linked sources (external directory watching)
- Screen capture with OCR routing
- Stacks (query objects, surfacing rules, built-in templates)
- Calendar projection (month view, ghost cells)
- Saved views (filter + sort + layout config)
- Search (token-based, cross-entity, snippets)
- Sound effects (configurable)
- Settings (7 categories)
- Spotlight indexing (activates in .app bundle)

---

## Post-Beta Backlog

Items explicitly deferred. Add new ideas here instead of scope-creeping the beta.

| Item | Priority | Notes |
|------|----------|-------|
| Mac App Store listing | Tier 1 | Revenue. Do after beta stabilizes. |
| Import/Export (Netscape HTML, OPML) | Tier 1 | Onboarding for users with existing bookmarks |
| Notes Phase 2 (checkboxes, pinning, drag reorder) | Tier 1 | Based on beta feedback |
| BYOAI (bring your own API key) | Tier 2 | For non-Apple Intelligence users |
| Drag out to external apps | Tier 2 | public.url, public.file-url |
| Advanced search (scope modifiers) | Tier 2 | @bookmarks, @notes, @folder:name |
| Whiteboard tab | Tier 3 | Freeform canvas |
| Documents tab | Tier 3 | PDFs, images, local files |
| Todos tab | Tier 3 | Task management |
| Books tab | Tier 3 | Reading tracker |
| Merge tags | Tier 2 | Consolidate two tags into one, reassign all items |
| Saved view tag filter | Tier 2 | Filter saved views by specific tags (smart folders) |
| AI auto-tag quality tuning | Tier 2 | Improve semantic category matching, threshold tuning |
| Themed folders (Media Hub, Recipe) | Tier 3 | Domain-specific views |
| YouTube transcript sync | Tier 3 | Live captions, click-to-seek |
| Clipboard viewer | Tier 3 | Recent items, action buttons |
| Vault directory migration prompt | Tier 2 | When vault root or override changes, offer "Move existing data to new location?" button — explicit, user-initiated, with confirmation. Currently users must move files manually in Finder. |
| Web archival | Tier 3 | .webarchive snapshots |
| GIF/video/carousel bookmarks | Tier 3 | Extended media types |

---

## Issues Log

Track issues found during review and testing. Reference the feature ID.

| Issue | Feature | Found During | Severity | Status | Notes |
|-------|---------|-------------|----------|--------|-------|
| | | | | | |

---

## Marketing Plan

### Pre-Launch (While Building)
- [ ] Make GitHub repo public
- [ ] Post 1-2 screen recording GIFs per week (#buildinpublic, #indiedev, #macdev)
- [ ] Brief dev log posts with screenshots

### Beta Launch
- [ ] r/macapps post
- [ ] Hacker News "Show HN" post
- [ ] GitHub Discussions enabled for community
- [ ] Simple landing page live

### Post-Beta
- [ ] Collect testimonials from beta testers
- [ ] Product Hunt launch (when polished)
- [ ] Mac App Store submission
- [ ] Monthly "what's new" updates
