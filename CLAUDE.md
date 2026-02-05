# Cider - Claude Context Guide

Cider is a native macOS **command palette** app that replaces Dock, Stage Manager, and Spotlight with a unified floating interface. Activated by double-tapping Option, it provides quick access to pinned apps, open windows, and more. Uses SwiftUI + AppKit, targets macOS 14+.

## Critical Rules (Always Follow)

- **Never steal focus** - All floating surfaces use `NSPanel` with `.nonactivatingPanel`
- **No hardcoded colors** - Use semantic system colors only
- **No magic numbers** - Use spacing/animation tokens from Constants.swift
- **Spring animations only** - No `.easeIn`, `.easeOut`, `.linear` for UI motion
- **Acrylic style** - Use `NSVisualEffectView` with `.underWindowBackground`, NOT `.glassEffect()`

## Primary Interface: Command Palette

The command palette is the main way users interact with Cider:
- **Activation:** Double-tap Option key
- **Opens on:** Screen where mouse is located
- **Style:** Raycast-inspired dark acrylic with custom shadows
- **Dismissal:** Escape key, click outside, or double-tap Option again

## Documentation Reference

### Before Writing ANY UI Code
**Read:** `Docs/DESIGN_SYSTEM.md`
- Color palette, typography, spacing tokens
- Animation springs and transitions
- Component specifications

### For Acrylic/Material Implementation
**Read:** `Docs/ACRYLIC_STYLE.md`
- NSVisualEffectView patterns
- Custom shadow technique (blurred shapes, not .shadow())
- Border and divider guidelines
- NSPanel configuration

### Before Writing ANY Swift Code
**Read:** `Docs/CONVENTIONS.md`
- Swift style, file organization
- SwiftUI patterns, state management
- Performance guidelines, threading

### For Architecture Decisions
**Read:** `Docs/ARCHITECTURE.md`
- Project structure
- NSPanel patterns
- Service layer design
- Storage model

### For Swift 6.2 / GRDB / Modern Patterns
**Read:** `Docs/TECH_STACK.md`
- Approachable Concurrency patterns
- GRDB query syntax
- Combine vs async/await guidance

### When Adding a New Feature
**Read:** `Docs/USER_PREFERENCES.md`
- Settings patterns
- CiderConfig for persistent settings

### To Understand the Product
**Read:** `Docs/VISION.md`
- What Cider is and isn't
- Design principles
- Command palette as primary interface

### For Full Feature Specs
**Read:** `Docs/product-spec.md`
- Command palette components
- Keyboard shortcuts
- Technical architecture

### For Current Work
**Read:** `Docs/NEXT_SPRINT.md` - Active sprint tasks
**Read:** `Docs/ROADMAP.md` - Milestone plan

### Before Release
**Read:** `Docs/RELEASE_CHECKLIST.md` - QA verification

## Quick Reference

### Spacing Tokens
```
xxs: 2pt | xs: 4pt | sm: 8pt | md: 12pt | lg: 16pt | xl: 20pt | xxl: 24pt | xxxl: 32pt
```

### Animation Presets
```swift
.smooth       // 0.5s, no bounce - default transitions
.snappy       // 0.35s, no bounce - menus, popovers
.bouncy       // 0.5s, 0.25 bounce - UI feedback
```

### Corner Radii (always .continuous)
```
xs: 4pt | sm: 6pt | md: 10pt | lg: 14pt | xl: 20pt
```

### Key Patterns
```swift
// NSPanel setup (command palette)
panel.styleMask = [.borderless, .nonactivatingPanel]
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
panel.backgroundColor = .clear
panel.hasShadow = false  // We draw custom shadows

// Acrylic background (NOT .glassEffect)
ZStack {
    VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
    Color.black.opacity(0.45)
    Color.white.opacity(0.03)
}

// Custom shadow as blurred shape
RoundedRectangle(cornerRadius: 14, style: .continuous)
    .fill(Color.black)
    .blur(radius: 18)
    .offset(y: 18)
    .opacity(0.7)

// Reduce Motion respect
@Environment(\.accessibilityReduceMotion) var reduceMotion
withAnimation(reduceMotion ? .none : .spring()) { }
```

## File Structure
```
Sources/
├── App/           # Entry point, AppDelegate, Panels
├── Views/
│   ├── CommandPalette/  # Main UI (palette, search, content)
│   ├── Settings/        # Settings window views
│   └── ...              # Other views
├── ViewModels/    # ObservableObject view models
├── Services/      # Business logic (WindowManager, etc.)
├── Models/        # Data models, CiderConfig
└── Utilities/     # Constants, extensions, helpers
```

## Command Palette Structure
```
CommandPaletteView
├── PaletteBackgroundView      # Acrylic + shadow
├── PaletteSearchBar           # Search input
├── PaletteAppsRow             # Pinned apps with running indicators
├── PaletteContentArea         # Tabs (Windows, Notes, Bookmarks)
│   └── PaletteWindowRow       # Individual window with actions
└── PaletteFooterBar           # Actions + settings button
```
