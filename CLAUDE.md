# Cider

Native macOS floating panel app for bookmarks, notes, and projects. Double-tap Option to activate. SwiftUI + AppKit, macOS 14+.

## Critical Rules

- **Never steal focus** — `NSPanel` with `.nonactivatingPanel`
- **No hardcoded colors** — `CiderColors.*` from Constants.swift
- **No hardcoded fonts** — `CiderFont.*` from CiderFont.swift
- **No magic numbers** — spacing/animation tokens from Constants.swift
- **Spring animations only** — no `.easeIn`, `.easeOut`, `.linear`
- **Respect Reduce Motion** — `reduceMotion ? .none : .spring` on every animation
- **Acrylic style** — `NSVisualEffectView` with `.underWindowBackground`, NOT `.glassEffect()`
- **Use `os.Logger`** — not `print()` (invisible from Dock launch)
- **Delete via TrashStorage** — never direct file deletion, always TrashStorage + CiderUndoManager
- **Update Kanban boards** — when starting, completing, or adding work, update the YAML boards in `~/CiderVault/.cider/boards/`. Move cards between columns (backlog → in_progress → testing → done). The app watches these files and updates live.

## Kanban Boards

YAML files in `~/CiderVault/.cider/boards/`. Two active boards:
- `a1b2c3.yaml` — **Cider Roadmap** (features, backlog, in progress, done)
- `d4e5f6.yaml` — **Cider Bugs** (high/medium/low priority, fixed)

When you start work on a feature, move its card to `in_progress`. When done, move to `done` (or `testing` if it needs manual testing). When fixing a bug, move it to `fixed`. If you build something new that isn't on the board, add a card.

## Build

```
swift build -Xswiftc -warnings-as-errors
```

## Skills

Use `/code`, `/design`, `/review`, `/docs` for deep reference on conventions, UI tokens, code review checklists, and doc formatting. Invoke before writing code or docs in unfamiliar areas.

## Docs

**How to read docs:** Read ONLY the Table of Contents first, then jump to the relevant section by line number. Do not read entire docs unless explicitly asked.

**How to write docs:** Use `/docs` skill — it has the exact format rules. No guessing.

**Before debugging:** Read `Docs/LESSONS_LEARNED.md` TOC for the relevant feature area. Past bugs with root causes and fixes are documented there.

| Doc | Contents |
|-----|----------|
| `Docs/LESSONS_LEARNED.md` | Past bugs: symptom → root cause → fix, organized by feature |
| `Docs/Architecture/ARCHITECTURE.md` | Panel, floating panel, tech stack, SwiftUI + AppKit patterns |
| `Docs/Architecture/STORAGE.md` | Vault file storage, webloc lifecycle, sidecar system |
| `Docs/Design/DESIGN_SYSTEM.md` | Component catalog, spacing, color tokens, cross-tab patterns |
| `Docs/Conventions/CONVENTIONS.md` | Code conventions, naming, patterns |
| `Docs/Conventions/CODE_HEALTH.md` | Weekly health scans, large file tracking |
| `Docs/Conventions/TROUBLESHOOTING.md` | Performance patterns, known issues |
| `Docs/Features/AI.md` | AI architecture, tool calling, MLX, Apple Intelligence |
| `Docs/Features/TIPTAP_EDITOR.md` | TipTap/ProseMirror editor in WKWebView |
| `Docs/Product/PRODUCT_VISION.md` | Roadmap, per-tab visions, strategy |
| `Docs/QA/AUDIT_LOOPS.md` | All reusable audit procedures (design tokens, conventions, threading, storage, dead code) |
| `Shared/` | Cross-platform: sync protocol, data model, feature parity |
