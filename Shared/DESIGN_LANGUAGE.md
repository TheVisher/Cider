# Design Language

> Cross-platform design principles shared by all three Cider apps. Platform-specific tokens and implementation details live in each app's own design system docs.

## Philosophy

Cider's visual identity is consistent across Desktop, Web, and iOS. The apps should feel like they belong to the same family, even though each respects its platform's native conventions.

### Core Principles

1. **Dark-first, monochromatic with accent** — white-based surfaces on dark backgrounds, system accent for interactive elements.
2. **Content over chrome** — minimize decoration, let content breathe.
3. **Semantic opacity scale** — consistent progression for surfaces (subtle → elevated → input → hover) and borders (subtle → default → hover → strong).
4. **Continuous corners** — always continuous/squircle, never circular. Swift: `.continuous` RoundedRectangle. CSS: not natively supported but approximated.
5. **Physics-based motion** — springs, not easing curves. Desktop: SwiftUI `.spring()`. Web: CSS `transition` with spring-like timing.
6. **Respect system settings** — Reduce Motion, Dynamic Type, Reduce Transparency, accent color.
7. **Restraint** — fewer effects done perfectly beats many effects done approximately.

## Shared Token Scale

These values are identical across all three platforms:

### Spacing (4pt base grid)

| Token | Value |
|-------|-------|
| xs | 4pt |
| sm | 8pt |
| md | 12pt |
| lg | 16pt |
| xl | 20pt |
| xxl | 24pt |
| xxxl | 32pt |

Desktop also has `hairline` (1pt) and `xxs` (2pt) for fine-grained layout.

### Corner Radii

| Token | Value | Usage |
|-------|-------|-------|
| xs | 4pt | Badges, tags |
| sm | 6pt | Buttons, pills, search fields |
| md | 10pt | Cards, containers |
| lg | 14pt | Panels, major surfaces |
| xl | 20pt | Reserved |

### Surface Hierarchy (white-based opacity)

| Level | Opacity | Usage |
|-------|---------|-------|
| Highlight | 0.03 | Shimmer, subtle shine |
| Subtle | 0.04 | Empty states, faint backgrounds |
| Elevated | 0.06 | Cards, containers, sidebar |
| Input | 0.07 | Text fields, form elements |
| Hover | 0.08-0.10 | Hover states |

### Border Hierarchy (white-based opacity)

| Level | Opacity | Usage |
|-------|---------|-------|
| Subtle | 0.08 | Default card borders |
| Default | 0.12 | Visible borders |
| Hover | 0.18-0.20 | Hover state borders |
| Strong | 0.25 | Active/selected borders |

## Platform-Specific Tokens

Each platform adapts the shared language to its native conventions:

### Desktop (macOS)
- **Token files**: `Sources/Cider/Utilities/Constants.swift`, `CiderFont.swift`
- **Colors**: `CiderColors.*` — includes acrylic material palette (NSVisualEffectView)
- **Typography**: macOS system font sizes (10pt caption through 20pt display)
- **Animations**: SwiftUI `.spring()` variants (smooth, snappy, bouncy)
- **Full spec**: `Cider/Docs/DESIGN_SYSTEM.md`

### iOS
- **Token files**: `CiderApp/Design/CiderColors.swift`, `CiderFont.swift`, `CiderSpacing.swift`
- **Colors**: Same opacity scale as Desktop, adapted for iOS rendering
- **Typography**: Scaled up from Desktop for mobile reading distance (12pt caption through 24pt display)
- **Animations**: SwiftUI `.spring()`, respects `accessibilityReduceMotion`
- **Full spec**: `Cider-iOS/DESIGN_SYSTEM.md`

### Web
- **Token files**: `src/styles.css` (CSS custom properties `--cider-*`)
- **Colors**: Same opacity scale as CSS vars. Accent color is **amber** (not system blue)
- **Typography**: CSS rem-based scale matching the Desktop proportions
- **Animations**: `transition-all duration-200` for most interactions
- **Full spec**: Inline in `Cider-Web/CLAUDE.md`

## Visual Consistency Rules

- **Thumbnail fallbacks**: All three apps use a gradient fallback when no thumbnail exists — URL-hash-based color pair with the domain's first letter. The gradient algorithm should produce the same colors for the same URL across platforms.
- **Favicon display**: Show favicon next to the host/domain text when available.
- **Tag pills**: Small rounded badges, capped display (show 3 + "+N" overflow).
- **Relative timestamps**: "2 days ago" format, not raw dates.
- **Dark mode**: All apps are dark-first. Desktop is dark-only. Web and iOS support light mode as secondary.
