# Cider Docs Index

> **Start here.** This is the map of everything in `Docs/`. Use it to find the right doc to read or update.
>
> When you make changes in a session — new features, decisions, gotchas, bugs — update the relevant doc(s) listed below. Each entry tells you exactly what belongs there.

---

## For You (Navigation & Status)

| Doc | What it's for |
| --- | --- |
| **DOCS_INDEX.md** | This file. The map. |
| **QUICK_REFERENCE.md** | Slash commands, end-of-session workflow, how to use Claude effectively on this project. |
| **CODE_HEALTH.md** | Living bug/debt tracker. Known issues, open findings from code reviews, items to fix. Check off when fixed, add new ones when found. |

---

## Reference Docs (Agents Read These Before Writing Code)

These are active standards. Agents are directed to read specific ones from CLAUDE.md before working on relevant areas.

| Doc | What it covers | Read before... |
| --- | --- | --- |
| **DESIGN_SYSTEM.md** | Color palette, typography, spacing tokens, animation specs, component specs | Any UI work |
| **ACRYLIC_STYLE.md** | NSVisualEffectView patterns, custom shadow technique, borders, NSPanel config | Panel/surface work |
| **CONVENTIONS.md** | Swift style, file organization, SwiftUI patterns, state management, threading | Any Swift code |
| **FLOATING_PANEL.md** | NSPanel architecture, positioning, resize handling, CiderPanel implementation | Panel architecture work |
| **SHARED_COMPONENTS.md** | Inventory of reusable cross-tab components — check here before building something new | Adding any new UI component |
| **TECH_STACK.md** | Swift 6.2, Combine, approachable concurrency, UserDefaults + Codable patterns | Concurrency or storage work |
| **USER_PREFERENCES.md** | CiderConfig structure, adding new settings, backward-compatible decoding | Adding any new setting |
| **TROUBLESHOOTING.md** | Known layout/rendering issues and their fixes (masonry, width pressure, thumbnails, CPU) | Debugging display or performance issues |
| **RELEASE_CHECKLIST.md** | Pre-release QA verification | Before shipping |
| **NOTES_EDITOR_SMOKE_CHECKLIST.md** | Notes editor-specific QA (formatting, tables, slash menu, drops) | Before shipping notes changes |

---

## Vision & Roadmap Docs

Each tab and major feature area has its own doc. These capture what's been built, what's planned, and design decisions that should survive across sessions. **When you add or change a feature, update the relevant vision doc.**

### Implemented Tabs

| Doc | What it covers | Status |
| --- | --- | --- |
| **HOME_VISION.md** | Home tab — library feed, Continue section, date cards, contacts, stacks, display modes | ✅ Implemented |
| **BOOKMARKS_VISION.md** | Bookmarks tab — capture flows, card display, dual-asset image storage, label/stack integration | ✅ Implemented |
| **NOTES_VISION.md** | Notes tab — card browsing, editor, display modes, storage architecture | ✅ Phase 1 implemented; Phases 2-4 future |

### Organization System

| Doc | What it covers | Status |
| --- | --- | --- |
| **WORKSPACES_VISION.md** | Folders, projects, search tabs, saved views, sidebar design, themed folders, multi-select, undo/trash | ✅ Phases 1-3 complete; Phase 4-5 (Projects UI, tear-off) future |

### Future Integrations & AI

| Doc | What it covers | Status |
| --- | --- | --- |
| **LINKED_SOURCES_VISION.md** | External filesystem folders surfaced in Cider — sidebar, tabs, library feed. Makes Cider a default `.md` editor/viewer. | 🔲 Not started |
| **AI_VISION.md** | On-device ML, smart tagging, semantic search, Apple Intelligence integration, tiered AI strategy | 🔲 Future |
| **INTEGRATION_DESIGN.md** | Obsidian / knowledge-base sync architecture and design | 🔲 Future (Phase 2+) |

### Future Tabs (Not Yet Started)

These exist to preserve ideas and design thinking for when these tabs get built. Add ideas here, not in general docs.

| Doc | Concept |
| --- | --- |
| **TODOS_VISION.md** | Task management tab |
| **WHITEBOARD_VISION.md** | Freeform canvas for brain-dumping |
| **BOOKS_VISION.md** | Reading tracker |
| **DOCUMENTS_VISION.md** | PDFs, images, local files |

---

## Archive

Historical docs that are no longer actively referenced live in `Docs/_archive/`. Nothing is deleted — if you need context on an old decision or past feature plan, look there.

Notable archive contents:

- `CODE_REVIEW_2026-02-16.md`, `CODE_REVIEW_2026-02-18.md` — superseded by `CODE_HEALTH.md`
- `CALENDAR_STACKS_VISION_MIGRATION_PLAN.md` — the plan for the custom tabs / date cards / stacks feature (now shipped)
- `WORKSPACES_IMPLEMENTATION_PLAN.md` — step-by-step plan for phases 1-3 (now complete)
- `PIVOT_STRATEGY.md` — rationale for the pivot from window manager to capture/reference layer
- `UX_TAB_SIMPLIFICATION.md` — original proposal for simplifying fixed tabs (now implemented via saved views)
- `UX_FOLDER_DESIGN.md` — early folder sidebar design decisions (now in `WORKSPACES_VISION.md`)
- `ANYBOX_COMPARISON.md` — competitive positioning vs Anybox