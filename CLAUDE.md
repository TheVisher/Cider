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

## Docs

Read the relevant doc BEFORE writing code in that area:

| Folder | Contents |
|--------|----------|
| `Docs/Architecture/` | Panel architecture, floating panel, storage, tech stack, SwiftUI gotchas |
| `Docs/Design/` | Design system (incl. component catalog, cross-tab patterns), acrylic implementation |
| `Docs/Conventions/` | Code conventions, code health, troubleshooting + performance best practices |
| `Docs/Features/` | TipTap editor, AI/chat, terminal, detail panel spec, integration design, user preferences |
| `Docs/Product/` | 1.0 roadmap, tab vision docs, future tabs, vault vision, user feedback |
| `Docs/QA/` | QA testing, audit loops, release checklist, build status |
| `Shared/` | Cross-platform: ecosystem, sync protocol, data model, design language, feature parity |
