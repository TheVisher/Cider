# Cider Code Health

> **Living document.** Do not replace or rewrite — update it in place.
> Items are checked off when fixed, never deleted. New findings are appended under the appropriate section.

---

## Agent Instructions

**Before starting a code review:**

- Read this file first. Do not re-report findings that are already listed here (open or resolved).
- Identify the highest-severity open items and call them out in your review.

**When you fix something on this list:**

- Check the item's checkbox and add the date: `✅ Fixed YYYY-MM-DD`

**When a code review surfaces a new finding:**

- Add it under the correct section using the next available ID (e.g., `CH-C05`).
- Include severity, a short description, and file refs.
- Leave it unchecked.

**Severity guide:** `Critical` → `High` → `Medium` → `Low`

---

## Security

### CH-S01 — WKWebView root filesystem access (High)

The notes editor WebView loads with `allowingReadAccessTo: URL(fileURLWithPath: "/")` — a skeleton key to the entire disk. Cider only needs access to the user's home directory (notes, attachments, dragged images).

- [ ]

- [ ]

- Remediation: Change to `URL(fileURLWithPath: NSHomeDirectory())`

- File refs: `Sources/Cider/ViewModels/NotesViewModel.swift:199–200`

- First reported: 2026-02-16

- [ ] Fixed

### CH-S02 — WebView bridge exposure via HTML + navigation policy (Critical)

The editor enables HTML markdown parsing (`html: true`) and registers multiple `window.webkit.messageHandlers`. The navigation policy only blocks `.linkActivated`, leaving non-link navigations able to interact with native bridge handlers.

> **Note:** CLAUDE.md documents this as an accepted risk — the editor JS is bundled and trusted, and the navigation delegate filters external URLs. Flag for hardening if the editor ever accepts arbitrary external content.

- [ ]

- [ ]

- Remediation: Restrict navigation to trusted origins/schemes; consider sanitizing unsafe HTML on ingest.

- File refs: `Sources/Cider/Views/Notes/TipTapEditorView.swift:12, 123, 133`

- First reported: 2026-02-16

- [ ] Fixed

---

## Correctness / Data

### ~~CH-C01 — Storage path split on directory change~~ ✅ Fixed 2026-02-21

`fileURL` in ContactStorage, ProjectStorage, DateCardStorage, CardStackStorage, CardLabelStorage, SavedViewStorage, and ExternalSourceStorage changed from stored properties (set at `init()`) to computed properties that call `StoragePaths.ciderDataDirectoryURL()` at runtime. Each storage gained a public `reload()` method. `AppDelegate.handleConfigChanged()` calls `reload()` on all 6 after updating the BookmarksStorage directory. Also: `CiderConfig.bookmarksDirectory` renamed to `ciderDataDirectory`; CodingKeys alias keeps JSON key `"bookmarksDirectory"` for backward compat.

### ~~CH-C02 — Note restore orphan risk in TrashStorage~~ ✅ Fixed 2026-02-21

Move is now `try fm.moveItem` inside a `do/catch`; on failure, function returns early leaving the manifest intact. `restoreFromTrash` and `removeFromManifest` only called on success. If the trash file is already gone (manual deletion), manifest is cleaned but index is not updated.

### ~~CH-C03 — Note search false negatives from 120-char cap~~ ✅ Fixed 2026-02-21

`notePreview` renamed `noteStrippedContent` and returns the full stripped string. `searchNotes` matches against the full content; `prefix(120)` applied only to the `subtitle` field in the returned `SearchResult`.

### CH-C04 — Select All skips date cards and contacts on Home tab (High)

`selectAll()` in `CiderPanelView` iterates `bookmarksViewModel.bookmarks` and `notesViewModel.notes` only. Date cards and contacts visible in the Home feed are not selected.

> **Note:** Only address once bulk-delete/move actions support all entity types. Until then, add a `// TODO: CH-C04` comment at the call site so it's findable.

- [ ]

- [ ]

- File refs: `Sources/Cider/Views/CiderPanelView.swift:826–829`

- First reported: 2026-02-20

- [ ] Fixed

---

## Performance

### CH-P01 — Main-thread disk I/O in search (Medium)

`SearchService.searchNotes` calls `NotesStorage.shared.loadContent(for:)` per note on the main actor. With large note sets this causes typing and scroll stutter.

- [ ]

- [ ]

- Remediation: Make search async; move content loads off the main actor.

- File refs: `Sources/Cider/Services/SearchService.swift:74`, `Sources/Cider/ViewModels/NotesViewModel.swift:71`, `Sources/Cider/ViewModels/LibraryViewModel.swift:139`

- First reported: 2026-02-16 (HI-03), confirmed 2026-02-18, 2026-02-20

- [ ] Fixed

### CH-P02 — Main-thread I/O at startup and directory-switch (Medium)

Large note/bookmark scans and JSON parsing happen synchronously on `@MainActor` during launch and when the storage directory changes in Settings.

- [ ]

- [ ]

- Remediation: Move read/decode work to background tasks; publish finalized state back on main actor.

- File refs: `Sources/Cider/Services/NotesStorage.swift:40`, `Sources/Cider/Services/BookmarksStorage.swift:467`

- First reported: 2026-02-16 (ME-02)

- [ ] Fixed

### CH-P03 — Attachment orphan cleanup scans all notes on main actor (Medium)

After every note save, orphan cleanup reads all note files and the attachment directory on `@MainActor`. Cost is O(n notes) and blocks the UI.

- [ ]

- [ ]

- Remediation: Move cleanup to a `Task.detached`; fence mutations back to `@MainActor`.

- File refs: `Sources/Cider/Services/NotesStorage.swift:470, 483, 528`

- First reported: 2026-02-16 (ME-03), confirmed 2026-02-20

- [ ] Fixed

### CH-P04 — Config save thrashing on slider changes (Medium)

Every slider tick (e.g., card size) triggers `config.save()` immediately. Slow drags produce dozens of disk writes per second. `save()` also logs on every call, adding noise.

- [ ]

- [ ]

- Remediation: Debounce writes with a \~300ms delay. Lower the log call to `.debug` or remove it.

- File refs: `Sources/Cider/Views/CiderPanelView.swift:86, 115`, `Sources/Cider/Models/CiderConfig.swift:215, 218`, `Sources/Cider/ViewModels/SettingsViewModel.swift:15, 132`

- First reported: 2026-02-20

- [ ] Fixed

### ~~CH-P05 — CiderFont decodes config on every render access~~ ✅ Fixed 2026-02-21

`_cachedScale` (`nonisolated(unsafe) static var`) is set once at startup. `invalidateScale()` re-reads config and updates the cache; called at the top of `AppDelegate.handleConfigChanged()`. Font tokens now read the cached value with no UserDefaults decode per access.

---

## Design & Architecture

### CH-D01 — Carbon fallback hotkeys consume keys when disabled (Medium)

In Carbon fallback mode (no Accessibility permission), disabled hotkeys still report "handled," causing `Opt+N` / `Opt+B` to be swallowed even when the feature is turned off.

- [ ]

- [ ]

- Remediation: Check the enabled state inside the Carbon event handler; return `eventNotHandledErr` if disabled.

- File refs: `Sources/Cider/Services/NotesHotkeyDetector.swift:166`, `Sources/Cider/Services/BookmarksHotkeyDetector.swift:190`

- First reported: 2026-02-18

- [ ] Fixed

### CH-D02 — Undo-toast hover resets timer instead of pausing (Medium)

Hovering over the undo toast resets the countdown timer and progress to full rather than simply pausing it in place. This makes the undo window effectively unbounded while the user hovers.

- [ ]

- [ ]

- Remediation: Pause the timer on hover-enter (save remaining time); resume from saved point on hover-exit. Do not reset.

- File refs: `Sources/Cider/App/AppDelegate.swift:586`

- First reported: 2026-02-18

- [ ] Fixed

### CH-D03 — Non-spring animation curves in panel transitions (Low)

Panel frame transitions use `.easeInEaseOut` rather than spring-based motion, diverging from the project's animation guidelines.

- [ ]

- [ ]

- Remediation: Replace with spring presets from `CiderAnimation`; add reduce-motion fallback.

- File refs: `Sources/Cider/App/CiderPanel.swift:242`, `Sources/Cider/App/NotesPanel.swift:174`, `Sources/Cider/App/BookmarksPanel.swift:158`

- First reported: 2026-02-16 (ME-05)

- [ ] Fixed

### CH-D04 — Search palette uses `.shadow()` instead of shape-based shadow (Low)

The search palette container applies `.shadow(...)` directly, while acrylic guidelines require a blurred-shape shadow to avoid clipping artifacts.

- [ ]

- [ ]

- Remediation: Replace with the shared acrylic shadow pattern (`RoundedRectangle.fill(.black).blur(...)`).

- File refs: `Sources/Cider/Views/Search/SearchPaletteView.swift:88`

- First reported: 2026-02-16 (ML-01)

- [ ] Fixed

### CH-D05 — Some UI elements ignore global text-size preference (Low)

A few fixed-size icon/font paths remain unscaled after the global `CiderFont` scale was introduced.

- [ ]

- [ ]

- File refs: `Sources/Cider/Utilities/CiderFont.swift:93`, `Sources/Cider/Views/Notes/NotesPanelView.swift:511`

- First reported: 2026-02-18

- [ ] Fixed

---

## Dead Code & Cleanup

### CH-L01 — Stale feature flags with no runtime gating (Low)

`enableDateCards`, `enableStacks`, `enableSavedViewTabs`, `enableCalendarProjection` exist in `CiderConfig` but nothing in the app checks them to gate behavior. They add migration surface area for no benefit.

- [ ]

- [ ]

- Remediation: Either wire them to actually gate their features, or delete them from `CiderConfig` (update `default`, memberwise `init`, and `init(from:)`).

- File refs: `Sources/Cider/Models/CiderConfig.swift:128–131`

- First reported: 2026-02-20

- [ ] Fixed

### CH-L02 — Dead code artifacts (Low)

Three files exist in the codebase and are never referenced.

- [ ]

- [ ]

- Remediation: Delete all three.

- File refs: `Sources/Cider/Services/SystemStatus.swift`, `Sources/Cider/Models/FeatureSettings.swift`, `Sources/Cider/Views/Projects/ProjectTabContent.swift:16` (unused import)

- First reported: 2026-02-20

- [ ] Fixed

---

## Resolved

### ✅ HI-02 — Test suite failed to compile (TileNode / SplitOrientation)

Stale tests from the window-manager era referenced removed types. Resolved when the window management pivot cleaned out these modules.

- Fixed: 2026-02

### ✅ LO-01 — SQLite doc drift

Docs previously described SQLite metadata storage; implementation is file/JSON-based. Documentation updated to reflect actual architecture.

- Fixed: 2026-02