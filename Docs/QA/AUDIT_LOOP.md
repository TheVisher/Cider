# Code Audit Loop

Reusable automated audit for enforcing design token consistency across the Cider codebase.

## When to run
- After major feature work
- Before releases
- Quarterly health check
- Any time you want to validate codebase consistency

## How to run

Tell Claude: **"Run the code audit loop"** — it will read this doc and know what to do.

## Setup

1. Create a branch: `git checkout -b audit-fixes`
2. Start the loop: `/loop 15m Run the code audit loop per Docs/QA/AUDIT_LOOP.md`
3. Let it run — it cycles through each area, fixes violations, verifies with `swift build`
4. Review the diff when done, merge if clean

## Rules checked

1. No `.easeIn`, `.easeOut`, `.linear` — spring animations only
2. Every `withAnimation` must have `reduceMotion` check (`.hoverState` handles internally)
3. No hardcoded colors — use `CiderColors.*`
4. No hardcoded font sizes — use `CiderFont.*`
5. No magic numbers for spacing/radius — use `Spacing.*`, `Radius.*`, or named `*Design` constants

## Token mappings

### CiderFont (by base size)
| Size | Tokens |
|------|--------|
| 8 | badge, badgeSemibold |
| 9 | micro, microMedium, microBold |
| 10 | caption, captionMedium, captionSemibold, captionBold |
| 11 | body, bodyMedium, bodySemibold, monospacedBody |
| 12 | label, labelMedium, labelSemibold |
| 13 | subheading, subheadingMedium, subheadingSemibold |
| 14 | heading, headingMedium, headingSemibold, headingBold |
| 16 | title, titleMedium |
| 20 | display, displaySemibold, displayBold |
| 28 | heroFallback, settingsEmptyIcon |

### CiderColors (common replacements)
| Hardcoded | Token |
|-----------|-------|
| `.green` / `.foregroundColor(.green)` | `CiderColors.success` |
| `.orange` / `.foregroundColor(.orange)` | `CiderColors.warning` |
| `Color.black.opacity(0.28)` | `CiderColors.backdrop` |
| `Color.black.opacity(0.38)` | `CiderColors.acrylicOverlayTint` |
| `Color.black.opacity(0.45)` | `CiderColors.acrylicTint` |
| `Color.black.opacity(0.55)` | `CiderColors.trafficLightSymbol` |
| `Color.black.opacity(0.72)` | `CiderColors.overlayDark` |
| `Color.black.opacity(0.4)` | `CiderColors.shadowHeavy` |
| `Color.white.opacity(0.03)` | `CiderColors.surfaceHighlight` |
| `Color.white.opacity(0.04)` | `CiderColors.surfaceSubtle` |
| `Color.white.opacity(0.06)` | `CiderColors.surfaceElevated` |
| `Color.white.opacity(0.08)` | `CiderColors.surfaceInput` |
| `Color.white.opacity(0.1)` | `CiderColors.surfaceHover` |
| `Color.white.opacity(0.12)` | `CiderColors.borderDefault` |
| `Color.white.opacity(0.2)` | `CiderColors.borderStrong` |
| `Color.white.opacity(0.25)` | `CiderColors.borderPanel` |
| `Color(.windowBackgroundColor)` | `CiderColors.opaqueBackground` |
| `CiderColors.success.opacity(0.08)` | `CiderColors.successSubtle` |

### Spacing tokens
`hairline:1 | xxs:2 | xs:4 | sm:8 | md:12 | lg:16 | xl:20 | xxl:24 | xxxl:32`

### Radius tokens
`xs:4 | sm:6 | md:10 | lg:14 | xl:20` (always `.continuous`)

## Known non-violations (skip these)
- `Color.clear` — structural transparency
- `Color(hex:)` from model data — data-driven colors
- `.opacity(condition ? 1 : 0)` — binary visibility toggles
- `spacing: 0` — explicit zero-gap layout
- `.hoverState()` — handles reduceMotion internally
- Token definitions inside Constants.swift / CiderFont.swift — source of truth
- `NSColor.white.cgColor` in CoreGraphics rendering contexts
- `.font(.system(size: computedParam))` — computed parameter, not raw literal
- Time constants (86400), notification intervals, grammar checks (`count == 1`)
- `.scale(0.95)` in transitions

## 3-pass verification

Each area requires 3 independent clean scans before PASS. If any scan finds a new violation, fix it and reset to 1/3. This ensures thoroughness — single passes consistently miss edge cases.

## Areas (scan order)
App/ → Models/ → Utilities/ → Services/ → Services/AI/ → ViewModels/ → Views/Bookmarks/ → Views/Notes/ → Views/Home/ → Views/Shared/ → Views/Search/ → Views/Settings/ → Views/AIAssistant/

## Progress tracking
Results are logged in `Docs/QA/CODE_AUDIT.md` with a progress tracker table and detailed fix log.
