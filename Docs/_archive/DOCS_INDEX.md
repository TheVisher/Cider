# Cider Docs Index

> **Start here.** This is the map of everything in `Docs/` and `Shared/`. Use it to find the right doc to read or update.
>
> When you make changes in a session — new features, decisions, gotchas, bugs — update the relevant doc(s) listed below.

---

## Shared Docs (`Shared/`)

Cross-platform docs read by agents working on any Cider app (Desktop, iOS, Web).

| Doc | What it's for |
| --- | --- |
| **ECOSYSTEM.md** | How the 3 apps relate, Convex backend, universal rules (UUIDs, timestamps, soft delete). |
| **SYNC_PROTOCOL.md** | REST endpoints, push/pull schemas, accepted/rejected fields, conflict resolution, historical bugs. |
| **DATA_MODEL.md** | Canonical Convex schema — bookmarks, folders, sync tokens tables with field-by-field docs. |
| **DESIGN_LANGUAGE.md** | Cross-platform design principles, shared token scales, surface/border hierarchy. |
| **FEATURE_PARITY.md** | 3-column matrix of what each app has. Updated by agents after shipping features + daily 4 AM scan. |

---

## Navigation & Status

| Doc | What it's for |
| --- | --- |
| **DOCS_INDEX.md** | This file. The map. |
| **1_0_ROADMAP.md** | **READ FIRST EVERY SESSION.** The active roadmap from beta to 1.0 release. |
| **USER_FEEDBACK.md** | Inbox for beta tester feedback. Periodically triaged into the 1.0 roadmap. |
| **QUICK_REFERENCE.md** | Slash commands, end-of-session workflow, how to use Claude effectively on this project. |
| **CODE_HEALTH.md** | Living bug/debt tracker. Known issues, code review findings. |

---

## Reference Docs (Read Before Writing Code)

| Doc | What it covers | Read before... |
| --- | --- | --- |
| **DESIGN_SYSTEM.md** | Color palette, typography, spacing tokens, animation specs, component specs | Any UI work |
| **ACRYLIC_STYLE.md** | NSVisualEffectView patterns, custom shadow technique, borders, NSPanel config | Panel/surface work |
| **CONVENTIONS.md** | Swift style, file organization, SwiftUI patterns, state management, threading | Any Swift code |
| **FLOATING_PANEL.md** | NSPanel architecture, positioning, resize handling, CiderPanel implementation | Panel architecture work |
| **DETAIL_PANEL_SPEC.md** | Detail view layout spec — slide-out/fullPanel/page geometry, alignment targets | Building/modifying detail views |
| **SHARED_COMPONENTS.md** | Inventory of reusable cross-tab components | Adding any new UI component |
| **TECH_STACK.md** | Swift 6.2, Combine, approachable concurrency, UserDefaults + Codable patterns | Concurrency or storage work |
| **USER_PREFERENCES.md** | CiderConfig structure, adding new settings, backward-compatible decoding | Adding any new setting |
| **ARCHITECTURE.md** | Panel structure, layout alignment rules, display modes, search, settings architecture | Panel layout, display modes, search, settings |
| **SWIFTUI_GOTCHAS.md** | Hard-won SwiftUI + NSPanel lessons | Debugging any SwiftUI issue |
| **TIPTAP_EDITOR.md** | TipTap/ProseMirror editor: singleton WebView, image serialization, CSS gotchas | Any notes editor work |
| **STORAGE.md** | Per-file storage standard + `.cider/` internal directory structure | Adding/modifying card storage |
| **AI.md** | AI philosophy, Apple frameworks, implementation status, AI Chat feature | Any AI or intelligence work |
| **TERMINAL.md** | Terminal/keyboard architecture doc | AI Chat keyboard work |
| **TROUBLESHOOTING.md** | Known layout/rendering issues and fixes | Debugging display/perf issues |
| **RELEASE_CHECKLIST.md** | Pre-release QA verification | Before shipping |
| **NOTES_EDITOR_SMOKE_CHECKLIST.md** | Notes editor-specific QA | Before shipping notes changes |

---

## Vision & Roadmap Docs

### Implemented Tabs

| Doc | What it covers | Status |
| --- | --- | --- |
| **HOME_VISION.md** | Home tab — library feed, Continue section, date cards, stacks, display modes | Implemented |
| **BOOKMARKS_VISION.md** | Bookmarks tab — capture flows, card display, dual-asset image storage, labels/stacks | Implemented |
| **NOTES_VISION.md** | Notes tab — card browsing, editor, display modes, storage | Phase 1 implemented |

### Organization & Integrations

| Doc | What it covers | Status |
| --- | --- | --- |
| **WORKSPACES_VISION.md** | Folders, saved views, search tabs, sidebar, multi-select, undo, trash | Phases 1-3 complete |
| **LINKED_SOURCES_VISION.md** | External filesystem folders surfaced in Cider | Implemented |
| **INTEGRATION_DESIGN.md** | Obsidian / knowledge-base sync architecture | Future |

### Other Implemented Features

| Doc | What it covers | Status |
| --- | --- | --- |
| **CLIPBOARD_VISION.md** | Standalone clipboard panel with history | Implemented |
| **WHITEBOARD_VISION.md** | Excalidraw-based canvas | Phase A shipped |
| **DATE_CARDS_VISION.md** | Calendar-linked events and reminders | Implemented |
| **VAULT_VISION.md** | Long-term direction: filesystem-as-truth, AI-powered, cross-platform | In progress |
| **BOOKMARK_FILE_MIGRATION.md** | Monolithic JSON → individual `.webloc` files | Phases 1-4 done |

### Future (Not Yet Started)

| Doc | Concept |
| --- | --- |
| **FUTURE_TABS.md** | Books tab, Todos tab, Documents tab — consolidated ideas for unbuilt tabs |

### Setup Guides

| Doc | What it covers |
| --- | --- |
| **SPARKLE_SETUP.md** | Sparkle auto-updater configuration |
| **RESURF_COMPETITIVE_ANALYSIS.md** | Competitive analysis vs Resurf app |

---

## Archive

Historical docs live in `Docs/_archive/`. Nothing is deleted — if you need context on an old decision, look there.

Notable archive contents:
- `BETA_ROADMAP.md` — old beta roadmap with window tiling concepts (superseded by 1_0_ROADMAP.md)
- `SYNC_COLLABORATION.md` — per-platform sync debugging notes (superseded by `Shared/SYNC_PROTOCOL.md`)
- `AI_VISION.md`, `AI_IMPLEMENTATION.md`, `AI_CHAT_VISION.md` — consolidated into `AI.md`
- `BOOKS_VISION.md`, `TODOS_VISION.md`, `DOCUMENTS_VISION.md` — consolidated into `FUTURE_TABS.md`
- `PER_FILE_STORAGE.md` (original), `VAULT_STORAGE.md` — consolidated into `STORAGE.md`
- `CODE_REVIEW_2026-02-16.md`, `CODE_REVIEW_2026-02-18.md` — superseded by `CODE_HEALTH.md`
- `PIVOT_STRATEGY.md` — rationale for pivot from window manager to capture/reference layer
- Various implementation plans and migration docs
