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

Read the relevant doc BEFORE writing code in that area:

| When... | Read |
|---------|------|
| Cross-platform context | `Shared/ECOSYSTEM.md` |
| Sync work | `Shared/SYNC_PROTOCOL.md` |
| Schema / data model | `Shared/DATA_MODEL.md` |
| Cross-platform design | `Shared/DESIGN_LANGUAGE.md` |
| Feature parity check | `Shared/FEATURE_PARITY.md` |
| Any UI work | `Docs/DESIGN_SYSTEM.md` |
| Acrylic/materials | `Docs/ACRYLIC_STYLE.md` |
| Any Swift code | `Docs/CONVENTIONS.md` |
| Panel architecture | `Docs/FLOATING_PANEL.md` |
| Panel layout, display modes, search, settings internals | `Docs/ARCHITECTURE.md` |
| SwiftUI + NSPanel pitfalls | `Docs/SWIFTUI_GOTCHAS.md` |
| TipTap/notes editor | `Docs/TIPTAP_EDITOR.md` |
| Concurrency/storage patterns | `Docs/TECH_STACK.md` |
| Adding/modifying card storage | `Docs/STORAGE.md` |
| Adding settings | `Docs/USER_PREFERENCES.md` |
| Reusable components | `Docs/SHARED_COMPONENTS.md` |
| Detail views | `Docs/DETAIL_PANEL_SPEC.md` |
| AI features & chat | `Docs/AI.md` |
| Terminal / AI Chat panel | `Docs/TERMINAL.md` |
| Cider Web sync | `Shared/SYNC_PROTOCOL.md` |
| Display/perf bugs | `Docs/TROUBLESHOOTING.md` |
| Code health/debt | `Docs/CODE_HEALTH.md` |
| Pre-release QA | `Docs/RELEASE_CHECKLIST.md` |

Tab vision docs: `Docs/{TAB_NAME}_VISION.md` (HOME, BOOKMARKS, NOTES, WHITEBOARD, CLIPBOARD, LINKED_SOURCES)
Future tabs (Books, Todos, Documents): `Docs/FUTURE_TABS.md`
Long-term vault direction: `Docs/VAULT_VISION.md`

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
    Color.black.opacity(0.45)
    Color.white.opacity(0.03)
}

// Reduce Motion
@Environment(\.accessibilityReduceMotion) var reduceMotion
withAnimation(reduceMotion ? .none : .spring()) { }
```

## File Structure
```
Sources/Cider/
├── App/              # AppDelegate, Panels (CiderPanel, DetailPopover, Settings)
├── Models/           # Bookmark, Note, Folder, CiderConfig, TrashItem, CiderTab
├── Services/         # Storage, DoubleTapDetector, TrashStorage, CiderUndoManager, SyncService, AI/
├── Utilities/        # Constants, CiderFont, ButtonStyles, ContainerStyles, HoverState
├── ViewModels/       # BookmarksViewModel, NotesViewModel, SettingsViewModel
└── Views/
    ├── Bookmarks/    # Cards, list rows, thumbnails, details, reader
    ├── Home/         # Dashboard (Continue + Library feed)
    ├── Notes/        # TipTap editor, cards, list rows
    ├── Search/       # Search palette and tab
    ├── Settings/     # Settings views
    └── Shared/       # TabBar, Sidebar, FolderDetail, ViewOptions, Masonry
```
