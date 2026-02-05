# Cider Agent Guide

This file consolidates the project rules and references from CLAUDE.md and Docs/ for day-to-day work.

**Critical Rules**
- Never steal focus. All floating surfaces must be NSPanel with .nonactivatingPanel.
- No arbitrary hex colors. Use semantic system colors, or the acrylic palette values defined in Docs/DESIGN_SYSTEM.md and Docs/ACRYLIC_STYLE.md.
- No magic numbers. Use spacing/animation tokens from Constants.swift or documented CommandPaletteDesign constants.
- Spring animations only for UI motion. Linear is only allowed for Reduce Motion (see `CiderAnimation.reduceMotion`).
- Acrylic goes on panels and chrome only. Never apply acrylic/glass materials directly to content rows or text.

**Design System Rules**
- System-first. Use SF Pro, SF Symbols, semantic colors, and native controls.
- Brand amber is for identity only, not interactive UI.
- Continuous corners only. Use RoundedRectangle(..., style: .continuous) or .containerConcentric.
- Respect accessibility settings: Reduce Motion, Reduce Transparency, Increase Contrast, Dynamic Type, VoiceOver.
- Minimum tap target: 28x28 pt. List item height: 36 pt minimum, 44 pt with subtitles.

**Acrylic Rules**
- Use NSVisualEffectView with `.underWindowBackground` + `.behindWindow` and acrylic overlays (see Docs/ACRYLIC_STYLE.md).
- Do not use `.glassEffect()` anywhere in Cider.
- Never stack acrylic layers; use a single VisualEffectView per panel.
- Acrylic shapes must be explicit for non-capsule surfaces.

**Swift and SwiftUI Conventions**
- Follow naming conventions in Docs/CONVENTIONS.md.
- Keep views small and composable. Do not put business logic in views.
- Use @State, @StateObject, @ObservedObject appropriately.
- Respect Reduce Motion by disabling spring animations when enabled.
- Use List for large collections; avoid ScrollView + ForEach for long lists.
- Avoid force unwraps in production code.

**Architecture Rules**
- NSPanel is mandatory for all floating surfaces.
- SwiftUI is hosted in NSPanel via NSHostingView.
- Services must be UI-independent.
- Storage model: SQLite for metadata, files for content.
- Target macOS 14+ with acrylic materials (NSVisualEffectView).

**Feature Settings Requirement**
- Every new feature must define settings using FeatureSettings (Docs/USER_PREFERENCES.md).
- Define defaults and configurable options up front.

**Quick Tokens (Reference)**
Spacing tokens:
```
xxs 2 | xs 4 | sm 8 | md 12 | lg 16 | xl 20 | xxl 24 | xxxl 32
```
Animation presets:
```
.smooth 0.5s | .snappy 0.35s | .bouncy 0.5s
```
Corner radii (continuous):
```
xs 4 | sm 6 | md 10 | lg 14 | xl 20
```

**Reference Docs (Read Before Work)**
- Docs/DESIGN_SYSTEM.md for any UI work.
- Docs/CONVENTIONS.md for any Swift code.
- Docs/ACRYLIC_STYLE.md for acrylic usage and fallbacks.
- Docs/ARCHITECTURE.md for structure and service patterns.
- Docs/TECH_STACK.md for Swift 6.2, concurrency, and GRDB guidance.
- Docs/USER_PREFERENCES.md for feature settings requirements.
- Docs/VISION.md for product intent.
- Docs/product-spec.md and Docs/cider-product-spec.docx for full spec context.
- Docs/NEXT_SPRINT.md for current priorities.
- Docs/ROADMAP.md for milestone planning.
- Docs/IDEAS.md for backlog.
- Docs/RELEASE_CHECKLIST.md for QA and release readiness.
- Docs/extension-api.md for extension design.
- Docs/cider-design-system.docx for design system reference.
