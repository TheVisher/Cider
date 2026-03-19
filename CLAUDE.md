# Cider - Claude Context Guide

> **Start here**: Read `Shared/ECOSYSTEM.md` for cross-platform context (sync protocol, data model, feature parity). This CLAUDE.md covers Desktop-specific concerns only.

Cider is a native macOS floating panel app for bookmarks, notes, and projects. Double-tap Option to activate. SwiftUI + AppKit, macOS 14+.

## 1.0 Roadmap

**Read:** `Docs/1_0_ROADMAP.md` every session. Also check `Docs/USER_FEEDBACK.md`.

- Point to next `Not Started` item when asked "what should we work on?" — also check `Shared/FEATURE_PARITY.md` to see if iOS or Web are missing something Desktop already has.
- Redirect post-1.0 ideas to roadmap backlog
- Never mark features Complete — only the user does that after testing
- Run code review after implementing any feature
- Update roadmap doc after gate transitions
- After user confirms a feature is complete, update `Shared/FEATURE_PARITY.md` to reflect the change

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

## Docs Reference

Read the relevant doc BEFORE writing code in that area. Docs are organized by folder:

| Folder | Contents |
|--------|----------|
| `Docs/Architecture/` | Panel architecture, floating panel, storage, tech stack, SwiftUI gotchas |
| `Docs/Design/` | Design system, acrylic style, shared components, detail panel spec |
| `Docs/Conventions/` | Code conventions, code health, user preferences, troubleshooting |
| `Docs/Features/` | TipTap editor, AI/chat, terminal |
| `Docs/Product/` | 1.0 roadmap, tab vision docs, future tabs, vault vision, user feedback |
| `Docs/QA/` | QA testing plan, code audit loop, release checklist, build status |
| `Shared/` | Cross-platform: ecosystem, sync protocol, data model, design language, feature parity |

## Quick Reference

### Design Token Files
```
CiderColors     → Utilities/Constants.swift
CiderFont       → Utilities/CiderFont.swift
Spacing/Radius  → Utilities/Constants.swift
ButtonStyles    → Utilities/ButtonStyles.swift
ContainerStyles → Utilities/ContainerStyles.swift
HoverState      → Utilities/HoverState.swift
```

### Build
```
swift build -Xswiftc -warnings-as-errors
```

### Tokens
```
Spacing:  hairline:1 | xxs:2 | xs:4 | sm:8 | md:12 | lg:16 | xl:20 | xxl:24 | xxxl:32
Radii:    xs:4 | sm:6 | md:10 | lg:14 | xl:20  (always .continuous)
Springs:  .smooth(0.5,0) | .snappy(0.35,0) | .bouncy(0.5,0.25) | .hoverMagnify(0.25,0.05) | .listReorder(0.3,0.08)
```

### Key Patterns
```swift
// NSPanel setup
panel.styleMask = [.borderless, .nonactivatingPanel]
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
panel.backgroundColor = .clear
panel.hasShadow = false  // Custom shadows

// Acrylic background
ZStack {
    VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
    CiderColors.acrylicTint
    CiderColors.surfaceHighlight
}

// Reduce Motion
@Environment(\.accessibilityReduceMotion) var reduceMotion
withAnimation(reduceMotion ? .none : .spring()) { }
```

## File Structure
```
Sources/Cider/
├── App/              # AppDelegate, Panels (CiderPanel, DetailPopover, Settings)
├── Models/           # Bookmark, Note, Folder, CiderConfig, TrashItem, CiderTab, TableColumn
├── Services/         # Storage, DoubleTapDetector, TrashStorage, CiderUndoManager, SyncService, AI/
├── Utilities/        # Constants, CiderFont, ButtonStyles, ContainerStyles, HoverState
├── ViewModels/       # BookmarksViewModel, NotesViewModel, SettingsViewModel
└── Views/
    ├── Bookmarks/    # Cards, list rows, thumbnails, details, reader
    ├── Home/         # Dashboard (Continue + Library feed)
    ├── Notes/        # TipTap editor, cards, list rows
    ├── Search/       # Search palette and tab
    ├── Settings/     # Settings views
    └── Shared/       # TabBar, Sidebar, FolderDetail, ViewOptions, Masonry, LibraryTable*
```
