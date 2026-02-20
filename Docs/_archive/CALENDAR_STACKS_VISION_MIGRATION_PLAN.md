# Cider Migration Plan: Custom Tabs, Date Cards, Stacks

Date: 2026-02-18  
Owner: Product + Coding Agent execution plan  
Primary scope: Move from current Bookmarks/Notes/Home architecture to library-first temporal system with custom tabs, date cards, and stacks.

---

## 1) Goals

1. Preserve Cider’s current strength: unified library and fast capture.
2. Add temporal behavior without building a separate calendar app.
3. Make tabs user-defined (saved views), not hard-coded by content type.
4. Introduce stacks as first-class context objects (manual + rule-driven).
5. Ship incrementally with low migration risk and no data loss.

## 2) Non-goals (v1)

1. Full Google Calendar-style drag/resize time-grid editor.
2. Multi-provider calendar sync (Google/Proton/etc.) in first release.
3. CloudKit/iOS sync in same milestone as the desktop model refactor.
4. Replacing existing bookmark/note storage formats.

---

## 3) Current State Audit (Code + Docs)

### 3.1 What already aligns with the new direction

1. Unified library already exists in Home:
   - `Sources/Cider/Views/Home/HomeDashboardView.swift`
   - Uses mixed `LibraryItem` list (`bookmark`, `note`) and shared card rendering.
2. Dynamic tabs already exist for search/projects:
   - `Sources/Cider/Models/CiderTab.swift`
   - `Sources/Cider/Views/CiderPanelView.swift`
   - `Sources/Cider/Views/Shared/CiderTabBar.swift`
3. Folder + project organization already implemented:
   - `Sources/Cider/Views/Shared/FolderSidebarView.swift`
   - `Sources/Cider/Services/ProjectStorage.swift`
4. Search and “save as project” flow already implemented:
   - `Sources/Cider/Services/SearchService.swift`
   - `Sources/Cider/Views/Search/SearchPaletteView.swift`
   - `Sources/Cider/Views/Search/SearchTabContent.swift`
5. Existing docs already trend toward tab simplification:
   - `Docs/UX_TAB_SIMPLIFICATION.md`
   - `Docs/HOME_VISION.md`

### 3.2 Gaps vs new vision

1. No date-native card model (due date/time/recurrence) in current core entities.
2. No saved-view tab model (tabs are fixed + dynamic search/project only).
3. No stack model (manual or rule-based).
4. No labels system beyond bookmark tags; no cross-entity colored labels.
5. No rule/surfacing engine (pin until paid, surface 7 days before birthday, etc.).
6. No calendar projection view (week/month grid on date metadata).
7. No contact card model/backlinks.

### 3.3 Existing behavior conflicts to resolve

1. Fixed tabs are hard-coded (`home`, `bookmarks`, `notes`) in `CiderTab.fixedTabs`.
2. `CiderPanelView` passes `selectedFolderID: nil` to Bookmarks/Notes tab content, bypassing folder filtering in those tabs.
3. `LibraryItem` is currently only two-type (`bookmark`, `note`) and not extensible for date/contact/book cards.
4. Several docs still describe many fixed content tabs (Books/Whiteboard/Todos) which conflicts with “single library + saved views”.

---

## 4) Product Architecture Decisions (lock these first)

1. **Calendar as projection**: no separate calendar source-of-truth.
2. **Entity model stays composable**:
   - Keep existing `Bookmark`/`Note` storage.
   - Add new temporal/contact/stack entities in separate stores.
   - Introduce a shared “library projection” layer that merges all entities.
3. **Stacks are first-class objects**:
   - Have ids, filters, sort/surface rules, summary config.
   - Do not own cards; they resolve dynamically from rules.
4. **Tabs become user views**:
   - Keep one fixed `Home`.
   - Keep ephemeral Search/Project tabs.
   - Add persistent custom tabs from saved filters/views.
5. **Ghost day cells**: optional calendar rendering behavior, not domain objects.

---

## 5) Proposed Data Model Additions (v1)

Add under `Sources/Cider/Models/`:

1. `LibraryEntityRef.swift`
   - `enum LibraryEntityType { bookmark, note, dateCard, contact }`
   - `struct LibraryEntityRef { type, id }`
2. `DateCard.swift`
   - Core fields:
   - `id`, `title`, `details`, `startAt`, `endAt?`, `allDay`, `location`
   - `recurrenceRule?`, `isCompleted`, `completedAt?`
   - `labels: [UUID]`, `linkedEntities: [LibraryEntityRef]`
   - `createdAt`, `updatedAt`
3. `ContactCard.swift`
   - `id`, `displayName`, `birthday?`, `labels`, `notes`, `linkedEntities`
   - `createdAt`, `updatedAt`
4. `Label.swift`
   - `id`, `name`, `colorHex`, `kind` (`person`, `category`, `priority`, `custom`)
5. `Stack.swift`
   - `id`, `name`, `isPinned`, `primarySort` (`attention`, `time`)
   - `matchRules`, `surfaceRules`, `summaryModule?` (`none`, `bills`)
   - `createdAt`, `updatedAt`
6. `SavedView.swift`
   - `id`, `name`, `filterSpec`, `sortSpec`, `layoutSpec`
   - `isTabPinned`, `createdAt`, `updatedAt`
7. `Rule.swift` / `SurfacingRule.swift`
   - v1 rule types: `pinUntilDone`, `surfaceDaysBeforeDate(Int)`, `remindBeforeMinutes(Int)`.

Storage services (JSON-backed like current code, under `Sources/Cider/Services/`):

1. `DateCardStorage.swift`
2. `ContactStorage.swift`
3. `LabelStorage.swift`
4. `StackStorage.swift`
5. `SavedViewStorage.swift`

Persistence location strategy (v1 pragmatic):

1. Store new JSON snapshots in bookmarks root (same place as `_cider_projects.json`) for now:
   - `_cider_date_cards.json`
   - `_cider_contacts.json`
   - `_cider_labels.json`
   - `_cider_stacks.json`
   - `_cider_saved_views.json`
2. Keep existing note markdown/index untouched.

---

## 6) UI/State Architecture Additions

### 6.1 Library projection layer

Add `Sources/Cider/Models/LibraryItemV2.swift`:

1. Extend current `LibraryItem` union to include:
   - `.dateCard(DateCard)`
   - `.contact(ContactCard)`
2. Add derived metadata used by surfacing and calendar projection:
   - `eventDateRange`, `labels`, `entityRef`, `attentionScore`.

### 6.2 View model layer

Add `Sources/Cider/ViewModels/LibraryViewModel.swift`:

1. Reads from all storages.
2. Produces:
   - Feed items (attention-sorted or date-sorted).
   - Calendar projection buckets by day/week/month.
   - Stack resolutions.
   - Saved view results.
3. Applies filter specs (types, labels, date range, text query).

### 6.3 Tabs and custom views

Modify:

1. `Sources/Cider/Models/CiderTab.swift`
   - Add `.savedView(id: UUID, name: String)`.
   - Keep `home`, `search`, `project`.
   - Plan deprecation for fixed `bookmarks` and `notes`.
2. `Sources/Cider/Views/CiderPanelView.swift`
   - Source tab list from fixed + saved views + dynamic tabs.
3. `Sources/Cider/Views/Shared/CiderTabBar.swift`
   - Add support for custom tab icons and rename/delete actions.

### 6.4 Calendar projection UI

Add:

1. `Sources/Cider/Views/Calendar/CalendarProjectionView.swift`
2. `Sources/Cider/Views/Calendar/CalendarDayCell.swift`
3. `Sources/Cider/Views/Calendar/GhostDayCard.swift`

Behavior:

1. Month/week toggle.
2. Date cells show up to N cards (`N=3`).
3. Overflow shows `+X`.
4. Empty day: ghost cell (toggle-able in view options).
5. Click ghost cell: prefill create-date-card modal.

### 6.5 Stacks UI

Add:

1. `Sources/Cider/Views/Stacks/StackCardView.swift`
2. `Sources/Cider/Views/Stacks/StackModalView.swift`
3. `Sources/Cider/Views/Stacks/StackSummaryBillsView.swift`

Behavior:

1. Stack card surfaces in library when rules match.
2. Top card + count badge.
3. Modal sort toggle (`attention`, `time`).
4. “Hide for me” vs “Mark done” actions are distinct.

---

## 7) Phased Implementation Plan

## Phase 0: Spec and guardrails (1-2 days)

1. Finalize model shapes and JSON schema docs.
2. Add feature flags in config:
   - `enableDateCards`
   - `enableStacks`
   - `enableSavedViewTabs`
   - `enableCalendarProjection`
3. Decide whether to hide Bookmarks/Notes fixed tabs now or later.

Acceptance:

1. No runtime behavior changes yet.
2. All flags default off in production.

## Phase 1: Data foundation (2-4 days)

1. Add models/storages listed in sections 5.1-5.2.
2. Add unit tests for storage round-trip and schema evolution.
3. Add `LibraryEntityRef` and lightweight backlinks.

Acceptance:

1. `swift build` clean.
2. New storages persist/load with no impact to existing bookmark/note data.

## Phase 2: Library projection v2 (3-5 days)

1. Extend `LibraryItem` union and feed rendering paths to include `DateCard` and `ContactCard`.
2. Introduce `LibraryViewModel`.
3. Add filter chips for type + labels (internal first, simple UI).

Acceptance:

1. Home feed can render mixed bookmarks, notes, date cards, contacts.
2. Existing cards still render unchanged.

## Phase 3: Saved views as tabs (2-4 days)

1. Add `SavedView` model/storage and CRUD UI (save current filters as tab).
2. Add `.savedView` case to `CiderTab`.
3. Render saved view tabs in `CiderTabBar`.
4. Keep fixed `Bookmarks`/`Notes` temporarily behind compatibility toggle.

Acceptance:

1. User can create, rename, delete saved tabs.
2. Saved tab reproduces filter/layer settings exactly.

## Phase 4: Date cards + calendar projection (4-7 days)

1. Create DateCard CRUD modal (reusing existing modal style).
2. Add calendar projection screen (month/week).
3. Add ghost days and “create from ghost day” flow.
4. Add date-related sorting and time ordering in day cells.

Acceptance:

1. Calendar view is generated from DateCards, not separate event objects.
2. Exiting calendar returns to same library context.

## Phase 5: Labels + rules + reminders (4-6 days)

1. Add labels storage/UI and multi-label assignment.
2. Implement rule engine v1:
   - `pinUntilDone`
   - `surfaceDaysBeforeDate`
   - `remindBeforeMinutes`
3. Add reminders via `UserNotifications`.

Acceptance:

1. Bills and birthdays can be modeled with labels + rules.
2. Rule-driven surfacing appears in feed predictably.

## Phase 6: Stacks v1 (4-7 days)

1. Add Stack CRUD (manual + rule-based).
2. Stack card representation in feed.
3. Stack modal with top-card, expansion list, sort toggle.
4. Optional Bills summary module.

Acceptance:

1. User can create stack templates: Bills, Kids Sports, Dinner.
2. Stack surface behavior follows configured rules.

## Phase 7: Contact card integration (3-5 days)

1. Add contact cards and birthday field.
2. “Add birthday card” quick action from contact.
3. Backlink rendering in contact detail (gift ideas, linked notes/bookmarks/date cards).

Acceptance:

1. Birthday card auto-links to contact and can use birthday surfacing rules.

## Phase 8: Decommission redundant fixed tabs (1-2 days)

1. Remove or hide fixed `Bookmarks` and `Notes` tabs by default.
2. Keep migration fallback setting for legacy users.
3. Update docs and release checklist.

Acceptance:

1. Home + saved views + dynamic search/project tabs cover workflows.

---

## 8) Detailed Code Change Map

### 8.1 Modify existing files

1. `Sources/Cider/Models/CiderTab.swift`
2. `Sources/Cider/Views/CiderPanelView.swift`
3. `Sources/Cider/Views/Shared/CiderTabBar.swift`
4. `Sources/Cider/Models/LibraryDisplayMode.swift` (or split to new `LibraryItemV2.swift`)
5. `Sources/Cider/Views/Home/HomeDashboardView.swift`
6. `Sources/Cider/Models/CiderConfig.swift` (new feature flags + saved-view prefs)
7. `Sources/Cider/Views/Shared/ViewOptionsDropdown.swift` (calendar toggles, ghost-card toggle)

### 8.2 New files/directories

1. `Sources/Cider/Models/DateCard.swift`
2. `Sources/Cider/Models/ContactCard.swift`
3. `Sources/Cider/Models/Label.swift`
4. `Sources/Cider/Models/Stack.swift`
5. `Sources/Cider/Models/SavedView.swift`
6. `Sources/Cider/Models/Rule.swift`
7. `Sources/Cider/Models/LibraryEntityRef.swift`
8. `Sources/Cider/ViewModels/LibraryViewModel.swift`
9. `Sources/Cider/Services/DateCardStorage.swift`
10. `Sources/Cider/Services/ContactStorage.swift`
11. `Sources/Cider/Services/LabelStorage.swift`
12. `Sources/Cider/Services/StackStorage.swift`
13. `Sources/Cider/Services/SavedViewStorage.swift`
14. `Sources/Cider/Views/Calendar/CalendarProjectionView.swift`
15. `Sources/Cider/Views/Calendar/CalendarDayCell.swift`
16. `Sources/Cider/Views/Calendar/GhostDayCard.swift`
17. `Sources/Cider/Views/Stacks/StackCardView.swift`
18. `Sources/Cider/Views/Stacks/StackModalView.swift`
19. `Sources/Cider/Views/Stacks/StackSummaryBillsView.swift`
20. `Sources/Cider/Views/Contacts/ContactCardView.swift`

---

## 9) Migration and Compatibility

### 9.1 Data migration strategy

1. No destructive migration of bookmarks/notes.
2. New entities start empty on first launch.
3. Optional auto-conversion utility (later):
   - Convert bookmark tags into labels.
   - Convert project searches into saved views.

### 9.2 UX migration strategy

1. Introduce “Custom Tabs (Beta)” in settings first.
2. Keep Bookmarks/Notes fixed tabs visible until saved views are stable.
3. Add one-click “Create saved view from current Bookmarks tab filter”.

### 9.3 Rollback strategy

1. Feature flags allow disabling new surfaces without touching legacy data.
2. If rule engine fails, fallback to static date sorting.

---

## 10) Testing Plan

Add tests under `Tests/CiderTests/`:

1. `DateCardStorageTests.swift`
2. `StackStorageTests.swift`
3. `SavedViewStorageTests.swift`
4. `RuleEngineTests.swift`
5. `LibraryProjectionTests.swift`
6. `CalendarProjectionTests.swift`
7. `TabModelMigrationTests.swift`

Critical test cases:

1. Recurrence edge cases (month boundaries, leap day, DST).
2. Sorting determinism when multiple cards have same datetime.
3. Stack rule composition (AND/OR filters).
4. Saved view reproducibility after app relaunch.
5. Backlink integrity when linked entity is deleted.

Manual smoke:

1. Build and launch panel.
2. Create date card from ghost cell.
3. Save current filters as tab and relaunch.
4. Create bills stack and mark one card paid.
5. Open stack modal and verify order toggles.

---

## 11) Product/UX Decisions (locked)

1. Keep fixed `Bookmarks` and `Notes` tabs for now; remove later after migration confidence.
2. Calendar projection v1 ships with both Month and Week views.
3. Ghost day cells default to ON with a visible toggle to disable.
4. Stack surfacing can be triggered by rules and/or pinning.
5. Reminders v1 are passive only (no auto-expand card behavior yet).

---

## 12) Mapping New Ideas to Current Docs

### 12.1 Aligned docs (reuse)

1. `Docs/HOME_VISION.md` (library-first baseline).
2. `Docs/UX_TAB_SIMPLIFICATION.md` (supports reducing fixed tabs).
3. `Docs/WORKSPACES_VISION.md` (dynamic tabs and mixed-content model).

### 12.2 Docs now outdated or conflicting

1. `Docs/WHITEBOARD_VISION.md`, `Docs/BOOKS_VISION.md`, `Docs/TODOS_VISION.md`:
   - These assume many fixed feature tabs.
   - Need rewrite as library entity types + saved views.
2. `Docs/RELEASE_CHECKLIST.md`:
   - Still assumes fixed Home/Bookmarks/Notes as final architecture.

Action:

1. Add a single umbrella doc update pass after Phase 3.

---

## 13) Suggested Execution Order for a Coding Agent

1. Implement data models/storages and tests first (Phases 1-2).
2. Land saved view tabs before calendar/stack UI (Phase 3).
3. Ship date cards + calendar projection next (Phase 4).
4. Add rules and labels then stacks (Phases 5-6).
5. Integrate contacts and birthday backlinks (Phase 7).
6. Remove redundant fixed tabs only after usage confidence (Phase 8).

---

## 14) Known UI Consistency Follow-up

1. `BookmarkCard` still uses inline container styling while other card types use shared `.cardContainer(...)`.
2. To make visual treatment (including shadows/borders/edge behavior) truly universal, normalize `BookmarkCard` to shared container primitives in a dedicated polish pass.

Definition of done for overall initiative:

1. Users can work primarily from Home library + custom tabs.
2. Calendar view exists as a projection of date-tagged cards.
3. Stacks surface meaningful grouped contexts (bills, birthdays, schedules).
4. Rules drive surfacing without requiring separate app modes.
5. Existing bookmark/note workflows remain intact during migration.
