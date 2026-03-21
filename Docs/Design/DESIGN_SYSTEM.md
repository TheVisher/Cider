# Cider Design System

> **This document is the single source of truth for Cider's visual design.**
> Every surface, window, and component must conform to these specifications.
> If your code deviates from this document, **your code is wrong** — fix it.
> Do not introduce new spacing values, shadow styles, or layout patterns
> without explicit user approval.
>
> **Read this document before writing ANY UI code.**

---

## 1. Compliance Rules

1. **No deviations.** Every padding, font, radius, and opacity in this doc is intentional. Do not "improve" or "clean up" values.
2. **Compare your work.** After writing UI code, compare your padding/layout against the relevant section of this doc. Fix mismatches immediately.
3. **No magic numbers.** Every spacing value must use a `Spacing.*` token. Every radius must use a `Radius.*` token.
4. **No hardcoded colors.** Use `CiderColors.*` tokens or the acrylic palette values listed below.
5. **Standalone windows must match.** The standalone Bookmarks and Notes windows must conform to the same structural patterns as the main panel (acrylic background, shadow technique, traffic lights, drag handles, title bar layout). If they don't match, fix them.
6. **When in doubt, match the main panel.** The main `CiderPanelView` is the reference implementation. All other surfaces derive from it.

---

## 2. Design Philosophy

Cider is a native macOS floating panel app. It uses a **Raycast-inspired acrylic material** — a dark, translucent aesthetic that works on any desktop background.

**Core principles:**
- **Content over chrome.** Minimize decoration. Let content breathe.
- **Dark acrylic aesthetic.** Dark translucent backgrounds with subtle borders and highlights.
- **Physics-based motion.** Every animation uses springs. No `.easeIn`, `.easeOut`, `.linear`.
- **Respect system settings.** Reduce Motion, Reduce Transparency, accent color.
- **Restraint.** Fewer effects done perfectly beats many effects done approximately.

**DO NOT use Apple's Liquid Glass** (`.glassEffect()`) — we intentionally chose the Raycast aesthetic.

**Theming note:** "Cider" is potentially a placeholder name. The entire color palette lives in `CiderColors` (Constants.swift) as semantic tokens. When the brand identity is finalized, changing the theme means editing one file — not hunting through views. All UI code must use `CiderColors.*` tokens, never raw `Color.white.opacity(...)` or similar.

---

## 3. Foundation Tokens

All tokens are defined in `Sources/Cider/Utilities/Constants.swift`.

### 3.1 Spacing

| Token | Value | Usage |
|-------|-------|-------|
| `Spacing.hairline` | 1pt | Sub-pixel vertical padding for badges and tags |
| `Spacing.xxs` | 2pt | Tight vertical padding, BrowserView inner padding |
| `Spacing.xs` | 4pt | Tight internal padding, traffic light spacing |
| `Spacing.sm` | 8pt | Standard element spacing, sidebar internal padding |
| `Spacing.md` | 12pt | Section padding, tab content wrapper padding |
| `Spacing.lg` | 16pt | Traffic light tap target size |
| `Spacing.xl` | 20pt | Large separations |
| `Spacing.xxl` | 24pt | Major areas |
| `Spacing.xxxl` | 32pt | Page margins |

### 3.2 Corner Radii

| Token | Value | Usage |
|-------|-------|-------|
| `Radius.xs` | 4pt | Small badges, tags |
| `Radius.sm` | 6pt | Buttons, hover backgrounds, tab pills, search field |
| `Radius.md` | 10pt | Cards, sidebar background, compact overlay corners |
| `Radius.lg` | 14pt | Main panel corners (`CiderPanelDesign.cornerRadius`) |
| `Radius.xl` | 20pt | Reserved (not currently used) |

**Always use `.continuous` style** for `RoundedRectangle`.

### 3.3 Border

| Token | Value |
|-------|-------|
| `CiderBorder.innerStrokeWidth` | 1.5pt |
| `CiderBorder.innerStrokeInset` | 0.75pt |

Usage: `.stroke(color, lineWidth: CiderBorder.innerStrokeWidth)` with `.padding(CiderBorder.innerStrokeInset)`.

### 3.4 Colors

#### Semantic Tokens (`CiderColors.*`)

| Token | Value | Usage |
|-------|-------|-------|
| `.primary` | `Color.primary` | Primary labels, titles (renders white in acrylic) |
| `.secondary` | `Color.secondary` | Section headers, sidebar icons, toolbar icons |
| `.tertiary` | `Color(.tertiaryLabelColor)` | Placeholder text, search hints, item counts |
| `.quaternary` | `Color(.quaternaryLabelColor)` | Disabled text, decorative icons |
| `.separator` | `Color(.separatorColor)` | Dividers |
| `.controlAccent` | `Color(.controlAccentColor)` | System accent for selection, active states |
| `.success` | `Color.green` | Confirmations |
| `.destructive` | `Color(.systemRed)` | Destructive actions |
| `.opaqueBackground` | `Color(.windowBackgroundColor)` | Reduce Transparency fallback |

#### Surfaces (white-based fills — `CiderColors.*`)

| Token | Value | Usage |
|-------|-------|-------|
| `.surfaceHighlight` | white 3% | Acrylic shimmer layer |
| `.surfaceSubtle` | white 4% | Empty states, faint section backgrounds |
| `.surfaceElevated` | white 6% | Cards, sidebar rows, raised surfaces |
| `.surfaceInput` | white 8% | Buttons, pills, input fields, list row hover |
| `.surfaceHover` | white 10% | Hover state for elevated surfaces |

#### Borders (white-based strokes — `CiderColors.*`)

| Token | Value | Usage |
|-------|-------|-------|
| `.borderSubtle` | white 8% | Faint borders (note card default) |
| `.borderDefault` | white 12% | Standard element borders |
| `.borderSelected` | white 14% | Settings selected-row border, progress track |
| `.borderHover` | white 18% | Border on hover |
| `.borderStrong` | white 20% | Emphasized borders (detail sheets) |
| `.borderPanel` | white 25% | Outer panel stroke |

#### Backdrops & Overlays (black-based — `CiderColors.*`)

| Token | Value | Usage |
|-------|-------|-------|
| `.backdropSubtle` | black 14% | In-panel detail overlays |
| `.backdrop` | black 28% | Compact sidebar dim, search palette dim |
| `.stageGradientEnd` | black 22% | Hero preview gradient (light end) |
| `.stageGradientStart` | black 34% | Hero preview gradient (dark end) |
| `.acrylicOverlayTint` | black 38% | Palette/overlay acrylic tint |
| `.acrylicTint` | black 45% | Main panel acrylic tint |
| `.trafficLightSymbol` | black 65% | Traffic light hover icon |
| `.overlayDark` | black 72% | Drag preview / dark thumbnail overlay |

#### Shadows (black-based — `CiderColors.*`)

| Token | Value | Usage |
|-------|-------|-------|
| `.shadowLight` | black 20% | Subtle icon/element shadows |
| `.shadowMedium` | black 28% | Standard card/sheet `.shadow()` |
| `.shadowHeavy` | black 40% | Deep floating palette/modal `.shadow()` |

#### Text on Color (`CiderColors.*`)

| Token | Value | Usage |
|-------|-------|-------|
| `.textOnColor` | white 90% | Bright text on gradient/colored backgrounds |
| `.shimmerPeak` | white 22% | Peak brightness of shimmer animation band |

#### Selection & Drop Targets (accent-based — `CiderColors.*`)

| Token | Value | Usage |
|-------|-------|-------|
| `.selectedFill` | accent 14% | Selected row/card fill |
| `.selectedBorder` | accent 48% | Selected row/card border |
| `.dropTargetFill` | accent 20% | Drag-over highlight fill |
| `.dropTargetBorder` | accent 72% | Drag-over stroke |
| `.dropTargetBorderStrong` | accent 65% | Strong drop target indicator |

#### Accent Tints (accent-based — `CiderColors.*`)

| Token | Value | Usage |
|-------|-------|-------|
| `.accentSubtle` | accent 8% | Barely-tinted backgrounds, button rest state |
| `.accentLight` | accent 12% | Pressed states, subtle selection, folder pills |
| `.accentSelected` | accent 18% | Selected interactive element (view toggle) |
| `.accentMedium` | accent 20% | Avatar circles, medium fills |
| `.accentBorder` | accent 30% | Accent-colored borders |
| `.accentText` | accent 80% | Accent-colored text and labels |
| `.accentSolid` | accent 88% | Progress bar fill, near-solid accent |

#### Separator-based Fills (neutral gray scale — `CiderColors.*`)

| Token | Value | Usage |
|-------|-------|-------|
| `.separatorSubtle` | separator 20% | Faint neutral fill (home sections, button rest) |
| `.separatorLight` | separator 25% | Tab badge bg, search bar, light fills |
| `.separatorMedium` | separator 30% | Selected list row, tab border |
| `.separatorFirm` | separator 40% | Selected tab badge, hover buttons |
| `.separatorStrong` | separator 50% | Panel inner stroke (opaque fallback), settings borders |
| `.separatorSolid` | separator 70% | Toolbar divider, active indicator |

#### Destructive Fills (`CiderColors.*`)

| Token | Value | Usage |
|-------|-------|-------|
| `.destructiveSubtle` | destructive 8% | Destructive button rest state |
| `.destructiveLight` | destructive 14% | Destructive button hover/fill |

#### Status Fills (`CiderColors.*`)

| Token | Value | Usage |
|-------|-------|-------|
| `.successMuted` | success 70% | Saved indicator icon |

#### CGFloat Constants (`CiderColors.*`)

| Token | Value | Usage |
|-------|-------|-------|
| `.gradientTint` | 0.8 | Palette/thumbnail gradient tint opacity |
| `.dividerPrimaryOpacity` | 0.28 | Primary settings divider dim |
| `.dividerSecondaryOpacity` | 0.22 | Secondary settings divider dim |
| `.disabledOpacity` | 0.55 | Disabled element view opacity |

### 3.5 Typography

Cider uses **SF Pro** (macOS system font) exclusively. All font declarations use **`CiderFont`** tokens (`Utilities/CiderFont.swift`). Never write `.font(.system(size:weight:))` directly — use a `CiderFont.*` token instead.

**Theming note:** Like `CiderColors`, all font definitions live in one file. When the brand identity is finalized, changing typography means editing `CiderFont.swift` — not hunting through views.

#### Fixed Tokens

| Token | Size | Weight | Usage |
|-------|------|--------|-------|
| `.badge` | 8pt | Bold | Tab bar badge count |
| `.badgeSemibold` | 8pt | Semibold | Badge variant |
| `.micro` | 9pt | Semibold | Small sidebar chevrons |
| `.microMedium` | 9pt | Medium | Resize icon, decorative labels |
| `.microBold` | 9pt | Bold | Sidebar confirm/cancel icons |
| `.caption` | 10pt | Regular | Metadata, timestamps, word counts |
| `.captionMedium` | 10pt | Medium | Secondary labels, sidebar counts, tab badges |
| `.captionSemibold` | 10pt | Semibold | Small emphasized labels, footer pill icon |
| `.captionBold` | 10pt | Bold | Folder item badges |
| `.body` | 11pt | Regular | Body text, descriptions, metadata |
| `.bodyMedium` | 11pt | Medium | Emphasized body, item labels, sidebar rows |
| `.bodySemibold` | 11pt | Semibold | Section headers, folder names, icon labels |
| `.bodyItalic` | 11pt | Regular Italic | Empty note placeholder |
| `.toolbarIcon` | 11pt | Medium | Toolbar icon sizing |
| `.monospacedBody` | 11pt | Medium Mono | Monospaced body text |
| `.label` | 12pt | Regular | Form text, editor content, search fields |
| `.labelMedium` | 12pt | Medium | Form labels, action labels |
| `.labelSemibold` | 12pt | Semibold | Root folder headers, emphasized section headers |
| `.subheading` | 13pt | Regular | Search palette text |
| `.subheadingMedium` | 13pt | Medium | Card titles, note titles |
| `.subheadingSemibold` | 13pt | Semibold | Bold card titles, view icons |
| `.heading` | 14pt | Regular | Heading base |
| `.headingMedium` | 14pt | Medium | Dashboard section headers, search categories |
| `.headingSemibold` | 14pt | Semibold | Settings section title |
| `.headingBold` | 14pt | Bold | Bold heading variant |
| `.navTitle` | 15pt | Semibold | Settings navigation title |
| `.title` | 16pt | Regular | Search palette input, about version |
| `.titleMedium` | 16pt | Medium | Panel headers, dashboard section titles |
| `.display` | 20pt | Regular | Folder overview icon, settings icon |
| `.displaySemibold` | 20pt | Semibold | Settings panel title, dashboard heading |
| `.displayBold` | 20pt | Bold | Home dashboard title |
| `.heroFallback` | 28pt | Bold | Bookmark hero fallback letter |
| `.settingsEmptyIcon` | 28pt | Regular | Settings empty state icon |
| `.dragPreviewIcon` | 32pt | Medium | Drag preview icon |
| `.vaultCardIcon` | 32pt | Light | Vault card decorative icon |
| `.fileIconLarge` | 32pt | Regular | Large file type icon |
| `.emptyStateIcon` | 36pt × scale | Regular | Empty state icon (scales with global text size) |
| `.vaultDetailIcon` | 48pt | Light | Vault detail decorative icon |
| `.appIcon` | 64pt | Regular | About screen app icon (fixed — decorative) |

#### NSFont Tokens

| Token | Size | Weight | Usage |
|-------|------|--------|-------|
| `.captureLabel` | 11pt | Medium Mono Digit | Screen capture label (NSFont) |

#### Responsive Tokens (textScale-based)

For views with a continuous card size slider (BookmarksBrowserView), use the `(scale:)` function variants:

```swift
.font(CiderFont.body(scale: textScale))
.font(CiderFont.captionMedium(scale: textScale))
```

Available: `body`, `bodyMedium`, `bodySemibold`, `caption`, `captionMedium`, `captionSemibold`, `micro`, `label`, `labelMedium`, `labelSemibold`, `subheadingMedium`, `heroTitle`, `heroDisplay`.

#### Exceptions (intentionally not tokenized)

- **Design constants:** `CiderPanelDesign.trafficLightSymbolSize`, `NotesDesign.toolbarIconSize` — sizes tied to specific component dimensions
- **Dynamic weights:** `CiderTabBar` uses `isSelected ? .semibold : .regular` — weight toggles at runtime
- **Settings dynamic preview:** Settings views use `CiderFont` tokens throughout (dynamic preview sizing excepted)

### 3.6 Animations

**Spring presets only.** Never use `.easeIn`, `.easeOut`, `.linear` for UI motion.

| Preset | SwiftUI API | Usage |
|--------|-------------|-------|
| Smooth | `.smooth` | Default transitions, chevron reveal |
| Snappy | `.snappy` | Sidebar toggle, tab selection, hover states, folder expand |
| Bouncy | `.bouncy` | Sidebar toggle button appearance |

**Reduce Motion:** Check `@Environment(\.accessibilityReduceMotion)`. Replace springs with `.none` (instant) or `.linear(duration: 0.2)` opacity crossfade.

**AppKit exception:** `NSAnimationContext` window-frame animations use `CAMediaTimingFunction(controlPoints:)` — AppKit has no spring timing API. This applies to panel collapse/expand in `CiderPanel`. Check `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` for these (not `@Environment`).

---

## 4. Acrylic Material

All floating surfaces use `AcrylicPanelBackground` — a three-layer stack of blurred shadow shape, `NSVisualEffectView` with dark tint/shimmer, and an inset border stroke. Canonical example:

```swift
ZStack {
    // Layer 1: Shadow (blurred shape — NOT .shadow() modifier)
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(Color.black)
        .blur(radius: 18)
        .offset(y: 18)
        .opacity(0.7)

    // Layer 2: Acrylic content
    ZStack {
        VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
        CiderColors.acrylicTint       // dark tint
        CiderColors.surfaceHighlight  // highlight shimmer
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

    // Layer 3: Border stroke
    .overlay(
        RoundedRectangle(cornerRadius: cornerRadius - CiderBorder.innerStrokeInset, style: .continuous)
            .stroke(CiderColors.borderPanel, lineWidth: CiderBorder.innerStrokeWidth)
            .padding(CiderBorder.innerStrokeInset)
    )
}
```

**Key rules:**
- **Never use SwiftUI `.shadow()` modifier** — it clips at window bounds. Draw shadows as blurred shapes.
- **Never use `.glassEffect()`** — we use the Raycast acrylic aesthetic.
- **Reduce Transparency fallback:** Replace acrylic stack with `Color(nsColor: NSColor.windowBackgroundColor)`.

| Shadow Style | Blur | Y Offset | Opacity | Usage |
|-------|------|----------|---------|-------|
| Full | 18pt | 18pt | 0.7 | Expanded panel |
| Compact | 10pt | 8pt | 0.52 | Collapsed panel |

> **Full implementation guide:** `Docs/Design/ACRYLIC_IMPLEMENTATION.md` — NSPanel configuration, `VisualEffectView` wrapper, border/divider guidelines, color palette, common mistakes.

---

## 5. Main Panel Layout

The main panel (`CiderPanelView`) is the reference implementation. All measurements below are exact.

### 5.1 Panel Dimensions

| Property | Token | Value |
|----------|-------|-------|
| Default width | `CiderPanelDesign.defaultWidth` | 780pt |
| Default height | `CiderPanelDesign.defaultHeight` | 640pt |
| Min width | `CiderPanelDesign.minWidth` | 400pt |
| Min height | `CiderPanelDesign.minHeight` | 440pt |
| Corner radius | `CiderPanelDesign.cornerRadius` | 14pt (`Radius.lg`) |

### 5.2 Window Padding (Shadow Space)

All shadow padding values are now `0`. The NSWindow frame matches the visible panel exactly — no extra padding for shadow rendering.

| Edge | Token | Value |
|------|-------|-------|
| Shadow padding | `CiderPanelDesign.shadowPadding` | 0pt |
| Top | `CiderPanelDesign.topPadding` | 0pt |
| Bottom | `CiderPanelDesign.bottomPadding` | 0pt |
| Bottom (collapsed) | `CiderPanelDesign.collapsedBottomPadding` | 0pt (equals `topPadding`) |

### 5.3 Panel Structure Diagram

```
NSWindow frame (equals visible panel — no shadow padding)
┌─────────────────────────────────────────────────────────────┐
│  Visible acrylic panel (14pt corners)                        │
│  ┌───────────────────────────────────────────────────────┐   │
│  │   HStack(spacing: 0)                                  │   │
│  │   ┌──────────┬────────────────────────┐               │   │
│  │   │ Sidebar  │  Right Column           │               │   │
│  │   │ Column   │  (VStack, spacing: 0)   │               │   │
│  │   │          │  ┌────────────────────┐ │               │   │
│  │   │          │  │ Title Bar (40pt h)  │ │               │   │
│  │   │          │  ├────────────────────┤ │               │   │
│  │   │          │  │ Divider (14pt inset)│ │               │   │
│  │   │          │  ├────────────────────┤ │               │   │
│  │   │          │  │ Content Area        │ │               │   │
│  │   │          │  │ (tab content)       │ │               │   │
│  │   │          │  │                     │ │               │   │
│  │   │          │  └────────────────────┘ │               │   │
│  │   └──────────┴────────────────────────┘               │   │
│  └───────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 5.4 Content Clipping

The `HStack` containing sidebar + right column must be clipped to the panel's rounded rect:
```swift
.clipShape(RoundedRectangle(cornerRadius: CiderPanelDesign.cornerRadius, style: .continuous))
```
This prevents slide transitions (sidebar toggle) from overflowing into the shadow area.

---

## 6. Right Column

The right column contains the title bar, divider, and tab content.

```
Right Column (VStack, spacing: 0)
├── .padding(.top, 7pt)  ← Spacing.sm - 1, aligns title bar center with traffic lights
│
├── Title Bar ─────────────────────────────────────
│   HStack(spacing: 8pt = Spacing.sm)
│   ├── [Sidebar toggle] (24×24, only when sidebar hidden)
│   ├── CiderTabBar (.frame(maxWidth: .infinity))
│   ├── [Capture button] (28×28, only on Bookmarks tab)
│   └── [Continue toggle] (28pt tall, only on Home when `showContinueSection`)
│   .padding(.horizontal, 12pt = Spacing.md)
│   .frame(height: 40pt = titleBarHeight)
│
├── Divider ───────────────────────────────────────
│   .padding(.horizontal, 14pt = Spacing.md + Spacing.xxs)
│
└── Content Area ──────────────────────────────────
    (switches by selectedTab)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
```

### 6.1 Title Bar

| Property | Value |
|----------|-------|
| Height | 40pt (`CiderPanelDesign.titleBarHeight`) |
| Internal spacing | 8pt (`Spacing.sm`) |
| Horizontal padding | 12pt (`Spacing.md`) |
| Sidebar toggle icon | 11pt semibold, 24×24 frame |
| Capture button icon | 11pt semibold, 28×28 frame |
| Continue toggle | Text: 10pt semibold uppercase (`CiderFont.captionSemibold`) + chevron: 9pt semibold (`CiderFont.micro`), container height 28pt |

The sidebar toggle appears with `.bouncy` animation after a 150ms delay when the sidebar closes. It disappears immediately with `.snappy` when the sidebar opens.

### 6.1.1 Tab-Specific Trailing Controls

- **Bookmarks tab:** shows capture button (`safari`) in the title bar trailing slot.
- **Home tab:** when `showContinueSection` is enabled in config, shows the `Continue` collapse toggle in the trailing slot.
- **Other tabs:** no trailing title-bar control; tab bar remains right-aligned with spacer behavior unchanged.

### 6.1.2 Selection Title Bar

When `selectedItemIDs` is non-empty, the title bar swaps to selection mode:

| Element | Spec |
|---------|------|
| X button | Clears selection, 24×24 frame |
| Count label | "N items selected", `CiderFont.bodySemibold` |
| Move to Folder | `Menu` with folder list, `CiderFont.bodySemibold` |
| Delete | Destructive button, `CiderFont.bodySemibold` |

Transition: `.snappy` spring between normal and selection title bar.

### 6.2 Divider

| Property | Value |
|----------|-------|
| Horizontal inset | 14pt (`Spacing.md + Spacing.xxs`) |
| Color | `CiderColors.separator` |

The 14pt inset aligns the divider endpoints with the card content edges in the tab below.

### 6.3 Top Padding Alignment

The right column has `7pt` top padding (`Spacing.sm - 1`). This is calculated so the vertical center of the title bar aligns with the vertical center of the traffic light circles in the sidebar header. **Do not change this value.**

### 6.4 Asymmetric Title Bar Spacing

There is intentionally more space above the title bar (7pt + panel chrome) than between the title bar and divider (0pt — they are adjacent in the VStack). The divider feels anchored to the header. **Do not equalize.**

---

## 7. Tab Bar

The tab bar (`CiderTabBar`) is a horizontal scroll view inside the title bar.

```
CiderTabBar
└── ScrollView(.horizontal)
    └── HStack(spacing: 2pt = tabSpacing)
        ├── Tab Button: [icon] [label] [badge?]
        ├── Tab Button: ...
        └── ...
    .padding(.horizontal, 4pt = tabHorizontalPadding)
.frame(height: 34pt = tabBarHeight)
```

### 7.1 Tab Button

| Property | Value |
|----------|-------|
| Internal spacing | 4pt (`Spacing.xs`) |
| Horizontal padding | 8pt (`Spacing.sm`) |
| Vertical padding | 4pt (`Spacing.xs`) |
| Background radius | 6pt (`Radius.sm`) |
| Selected background | `CiderColors.separator.opacity(0.3)` |
| Inactive background | Transparent |
| Icon size | 11pt medium |
| Label (selected) | 12pt semibold |
| Label (inactive) | 12pt regular |
| Badge | 10pt medium, capsule background |
| Tab-to-tab gap | 2pt (`CiderPanelDesign.tabSpacing`) |

---

## 8. Sidebar Column

The sidebar is a full-height floating column on the left side of the panel.

The sidebar is a **reusable container pattern** — the same structural shell (column, background, header, footer, compact mode) must be used by all windows that have a sidebar. The **content** inside the sidebar varies per window (folders/projects in main panel, notes list in standalone Notes, etc.), but the container dimensions, padding, background, header, and footer are identical everywhere.

```
Sidebar Column (VStack, spacing: 0)
├── sidebarHeader (traffic lights + collapse toggle)
├── [sidebar content] (scrollable, fills available space)
└── sidebarFooter (optional per window)
│
├── Background: RoundedRectangle(10pt = Radius.md), white 6%
├── Border: stroke white 12%, width 1.5pt
├── .padding(.leading, 12pt = Spacing.md)
└── .padding(.vertical, 12pt = Spacing.md)
```

**The sidebar is the layout source of truth.** When aligning elements between sidebar and right column, adjust the right column to match the sidebar — never the other way around.

### 8.1 Sidebar Dimensions

| Property | Value |
|----------|-------|
| Width | 224pt (`BookmarksDesign.folderSidebarWidth`) |
| Background radius | 10pt (`Radius.md`) |
| Background fill | `CiderColors.surfaceElevated` |
| Border stroke | `CiderColors.borderDefault`, 1.5pt |
| Leading padding (from panel edge) | 12pt (`Spacing.md`) |
| Vertical padding (from panel edge) | 12pt (`Spacing.md`) |
| Compact mode threshold | 680pt panel width |

### 8.2 Sidebar Header

```
sidebarHeader
HStack(alignment: .top, spacing: 4pt = trafficLightSpacing)
├── Traffic Light (red/close)      12pt circle, 16×16 tap target
├── Traffic Light (yellow/collapse) 12pt circle, 16×16 tap target
├── Traffic Light (green/maximize)  12pt circle, 16×16 tap target
├── Spacer
└── Collapse Toggle                11pt icon, 28w × 16h frame
│
.frame(height: 28pt = buttonTapTarget, alignment: .top)
.padding(.horizontal, 8pt = Spacing.sm)
.padding(.top, 8pt = Spacing.sm)
.frame(maxWidth: 224pt)
```

#### Traffic Lights

| Property | Token | Value |
|----------|-------|-------|
| Circle diameter | `trafficLightDiameter` | 12pt |
| Tap target | `trafficLightTapTarget` | 16pt × 16pt |
| Spacing between circles | `trafficLightSpacing` | 4pt |
| Hover symbol size | `trafficLightSymbolSize` | 7pt semibold |
| Hover symbol color | — | `CiderColors.trafficLightSymbol` |

Traffic lights use `HStack(alignment: .top)` and `frame(alignment: .top)` to stay pinned to the top regardless of conditional content.

#### Collapse Toggle

| Property | Value |
|----------|-------|
| Icon | `sidebar.left`, 11pt semibold |
| Frame | width: 28pt, height: 16pt (`trafficLightTapTarget`) |
| Color | `CiderColors.secondary` |

The collapse toggle height matches `trafficLightTapTarget` (16pt), not `buttonTapTarget` (28pt), to center-align with the traffic light circles.

### 8.3 Sidebar Content (FolderSidebarView)

```
FolderSidebarView (VStack, alignment: .leading, spacing: 8pt = Spacing.sm)
├── Search trigger button (rounded rect, Radius.sm)
│   ├── .padding(.horizontal, 8pt), .padding(.vertical, 4pt)
│   └── Background: separator @ 25%, Radius.sm
│
│   ↕ 8pt (VStack spacing)
│   ↕ 4pt (Folders label .padding(.top, Spacing.xs))
│   = 12pt total gap
│
├── "Folders" label (11pt semibold, CiderColors.secondary)
│   └── .padding(.top, 4pt = Spacing.xs)  ← breathing room from search
│
│   ↕ 8pt (VStack spacing)
│
├── All Items row (30pt min height)
│   ├── Background: white 6%, Radius.sm
│   └── Border: white 12% / accent 48% when selected
│
│   ↕ 8pt (VStack spacing)
│
├── ScrollView (folder tree)
│   └── LazyVStack(spacing: 8pt = Spacing.sm)
│       └── Root folder groups (30pt+2pt min height each)
│
│   ↕ 8pt (VStack spacing)
│
├── Projects Section (if projects exist)
│   └── VStack(spacing: 8pt = Spacing.sm)
│       ├── Divider
│       │   └── .padding(.vertical, 4pt = Spacing.xs)
│       ├── "Projects" label (11pt semibold)
│       └── Project rows (30pt min height each)
│
└── Spacer
│
.padding(.horizontal, 8pt = Spacing.sm)
.frame(width: 224pt)
```

#### Key Sidebar Spacing Rules

| Gap | Value | How |
|-----|-------|-----|
| Search → "Folders" header | 12pt | 8pt VStack spacing + 4pt `.padding(.top)` on label |
| "Folders" → All Items | 8pt | VStack spacing |
| All Items → folder tree | 8pt | VStack spacing |
| Last folder → Projects divider | 8pt | VStack spacing |
| Divider vertical padding | 4pt each side | `.padding(.vertical, Spacing.xs)` |
| "Projects" → project rows | 8pt | Projects VStack spacing (`Spacing.sm`) |
| Between project rows | 8pt | Projects VStack spacing |

#### Sidebar Rows

| Property | Value |
|----------|-------|
| Min height | 30pt (`BookmarksDesign.folderSidebarRowMinHeight`) |
| Root folder row height | 32pt (30pt + 2pt extra) |
| Horizontal padding | 8pt (`Spacing.sm`) |
| Background radius | 6pt (`Radius.sm`) |
| Default fill | `CiderColors.surfaceElevated` |
| Hover fill | `CiderColors.surfaceHover` |
| Selected fill | `CiderColors.selectedFill` |
| Default border | `CiderColors.borderDefault` |
| Selected border | `CiderColors.selectedBorder` |
| Icon color (default) | `CiderColors.secondary` |
| Icon color (selected) | `CiderColors.controlAccent` |
| Row text | 11pt medium (sub-folders), 12pt semibold (root folders) |

**No top padding on FolderSidebarView itself** — the search bar's top edge aligns with the divider line in the right column.

### 8.4 Sidebar Footer

```
sidebarFooter (VStack, spacing: 8pt = Spacing.sm)
├── Divider
│   └── .padding(.bottom, 4pt = Spacing.xs)
├── HStack(spacing: 8pt = Spacing.sm)
│   ├── Gear icon (16×16 frame)
│   ├── Spacer
│   ├── "+ New" pill menu
│   │   ├── HStack(spacing: 4pt): [+] [New]
│   │   ├── .padding(.horizontal, 8pt)
│   │   ├── .frame(height: 16pt = trafficLightTapTarget)
│   │   └── Capsule background: white 8%
│   ├── Spacer
│   └── View options icon (16×16 frame)
│
.padding(.top, 8pt = Spacing.sm)
.padding(.horizontal, 8pt = Spacing.sm)
.padding(.bottom, 8pt = Spacing.sm)
.frame(width: 224pt)
```

Footer icon frames use `trafficLightTapTarget` (16pt) height, not `buttonTapTarget` (28pt).

---

## 9. Tab Content Padding

Every tab content area uses the same two-layer padding pattern to produce a consistent 14pt inset from the divider/edges to the content.

### 9.1 Standard Pattern

```
Tab Content Area
├── TabContent wrapper (BookmarksTabContent / NotesTabContent)
│   └── .padding(.horizontal, 12pt = Spacing.md)
│       .padding(.vertical, 12pt = Spacing.md)
│
└── BrowserView (BookmarksBrowserView / NotesBrowserView)
    └── .padding(2pt = Spacing.xxs)  ← all sides
```

| Layer | Token | Value |
|-------|-------|-------|
| TabContent | `Spacing.md` (horizontal + vertical) | 12pt |
| BrowserView | `Spacing.xxs` (all sides) | 2pt |
| **Total inset** | | **14pt** |

### 9.2 Home Dashboard

```
HomeDashboardView
├── .padding(2pt = Spacing.xxs)         ← inner
├── .padding(.horizontal, 12pt = Spacing.md)  ← outer
└── .padding(.vertical, 12pt = Spacing.md)    ← outer
Total: 14pt
```

### 9.3 Critical Rules

- Padding is applied **outside** the ScrollView. Content inside the ScrollView starts at (0,0).
- The 14pt total inset must match the divider's horizontal inset (also 14pt) so card edges align with divider endpoints.
- Do not add extra padding inside the ScrollView or on individual cards that would break this alignment.

---

## 10. Resize Handles

The panel supports all-edge resizing via `PanelEdgeResizeView`, an `NSViewRepresentable` overlay.

### 10.1 Hit Zones

| Property | Token | Value |
|----------|-------|-------|
| Edge grab thickness | `resizeEdgeThickness` | 6pt into content |
| Corner grab size | `resizeCornerSize` | 20pt |

Resize zones extend through the shadow padding area AND 6pt into the visible content area for easier grabbing. Corners are resolved where two edge zones overlap.

### 10.2 Cursors

Each zone shows the appropriate `NSCursor.frameResize(position:directions:)` cursor. The resize icon in the bottom-right corner (`CiderPanelResizeIcon`) is decorative only — 9pt medium, `CiderColors.quaternary`, `allowsHitTesting(false)`.

### 10.3 Resize Constraints

| Constraint | Token | Value |
|------------|-------|-------|
| Min width | `panelMinWidth` | 400pt (= `minWidth` + 0 shadow) |
| Min height | `panelMinHeight` | 440pt (= `minHeight` + 0 padding) |

---

## 11. Compact Mode

When the panel width drops below `680pt` (`sidebarCompactThreshold`), the sidebar switches from inline column to overlay mode.

### 11.1 Behavior

- **Auto-collapse:** If sidebar is visible when width crosses below threshold, it auto-hides and `sidebarAutoCollapsed` is set.
- **Auto-restore:** When width crosses back above threshold, sidebar restores if it was auto-collapsed.
- **Manual toggle:** User can still toggle sidebar in compact mode; it slides over content as an overlay.

### 11.2 Compact Overlay Sidebar

```
ZStack(alignment: .leading)
├── Dimming backdrop: CiderColors.backdrop, tap to dismiss
└── VStack (same sidebarHeader + folderSidebar + sidebarFooter)
    └── Background: VisualEffectView(.underWindowBackground, .withinWindow)
        + .sectionContainer() (surfaceElevated fill + border)
        Background clip: RoundedRectangle(Radius.md)
        Outer clip: panel corner radius (14pt)
```

**Critical:** The overlay must use `.withinWindow` blending, not `.behindWindow`. Since our window background is transparent (for custom shadows), `.behindWindow` samples the desktop wallpaper instead of the panel's acrylic. `.withinWindow` samples the panel's own rendered content — the dark acrylic — giving the correct appearance.

The entire overlay is clipped to the panel's rounded rect to prevent overflow.

---

<!-- Section 12: Standalone Windows — REMOVED in Feb 2026 panel consolidation.
Standalone BookmarksPanel and NotesPanel were removed. All content now lives in the
main CiderPanel. The notes editor opens inline via push/pop navigation. Bookmarks are
browsed exclusively in the main panel's saved view tabs or Home feed.

If standalone windows are re-introduced in the future, refer to this archived spec
for the required structure (must match main panel: same acrylic, shadow, sidebar,
traffic lights, resize handles, compact mode, etc. — see sections 4-11 above).

Previous section covered:
- 12.1 Required Structure (NSPanel + CiderPanelShell two-column layout)
- 12.2 What Must Be Identical (acrylic, shadow, border, sidebar, resize handles, compact mode)
- 12.3 What Varies Per Window (sidebar content + title bar content)
- 12.4 Current Status (needed updating — now moot)
-->

---

## 13. Search Palette

The search palette is an overlay inside the main panel.

| Property | Token | Value |
|----------|-------|-------|
| Width | `SearchPaletteDesign.paletteWidth` | 560pt |
| Results max height | `SearchPaletteDesign.resultsMaxHeight` | 400pt |
| Search field height | `SearchPaletteDesign.searchFieldHeight` | 52pt |
| Shadow color | `SearchPaletteDesign.shadowColor` | `.black` |
| Shadow blur radius | `SearchPaletteDesign.shadowBlurRadius` | 24pt |
| Shadow Y offset | `SearchPaletteDesign.shadowYOffset` | 12pt |
| Shadow opacity | `SearchPaletteDesign.shadowOpacity` | 0.7 |
| Top offset factor | `SearchPaletteDesign.topOffsetFactor` | 0.22 (fraction of container height) |

---

## 14. Accessibility

### 14.1 Required Adaptations

| Setting | Behavior |
|---------|----------|
| Reduce Motion | All springs → `.none` (instant). No scale animations. |
| Reduce Transparency | Opaque `windowBackgroundColor` replaces acrylic stack |
| Dark Mode | Automatic via semantic `CiderColors.*` tokens |
| VoiceOver | `.help()` labels on all interactive elements |

### 14.2 Minimum Tap Targets

| Element | Size |
|---------|------|
| Traffic lights | 16pt × 16pt (visual 12pt circle) |
| Buttons | 28pt × 28pt minimum |
| Sidebar rows | Full width × 30pt min height |
| Tab buttons | Full pill area (8pt padding each side) |

---

## 15. Button Styles

Three shared `ButtonStyle` implementations in `Utilities/ButtonStyles.swift`. Use these for pill-shaped action buttons — **not** for icon-only toolbar buttons (use `.buttonStyle(.plain)` for those).

| Style | Text Color | Rest Fill | Press Fill | Use For |
|-------|-----------|-----------|------------|---------|
| `CiderAccentButtonStyle` | `controlAccent` | `accentSubtle` | `accentLight` | Primary actions (Save, Create, Sign In) |
| `CiderDestructiveButtonStyle` | `destructive` | `destructiveSubtle` | `destructiveLight` | Dangerous actions (Delete, Reset) |
| `CiderSecondaryButtonStyle` | `secondary` | `surfaceInput` | `surfaceHover` | Cancel/dismiss alongside a primary button |

**Shared properties:** `.font(.body)` · `.padding(.horizontal: Spacing.md, .vertical: Spacing.sm)` · `RoundedRectangle(Radius.sm, .continuous)` background

```swift
// Primary action
Button("Save", action: save)
    .buttonStyle(CiderAccentButtonStyle())

// Destructive action
Button("Delete", action: delete)
    .buttonStyle(CiderDestructiveButtonStyle())

// Cancel/dismiss
Button("Cancel", action: cancel)
    .buttonStyle(CiderSecondaryButtonStyle())
```

---

## 16. Card Consistency Contract

Cider has multiple card types (`BookmarkCard`, `NoteCardView`, `DateCardCardView`, `ContactCardCardView`). These are intentionally **separate files** — the content of each is different enough to justify it. The contract that ensures visual consistency is **shared primitives**, not a shared file.

Every card view MUST use:
- `.cardContainer(isHovered: isHovered)` — provides background fill, border, clipShape, and contentShape
- `.hoverState($isHovered, animation: .snappy)` — hover tracking
- `CiderColors.*` — no hardcoded colors
- `CiderFont.*` — no `.font(.body)` etc.
- `Spacing.*` — no magic number padding values
- `Radius.*` — no hardcoded corner radii

**Do not** build a new card by inlining `RoundedRectangle + .fill + .overlay(stroke)`. That is what `.cardContainer()` is for. Any visual change to the card shell (border width, hover color, corner radius) flows through the modifier and updates every card type automatically.

### `cardContainer()` Parameters

```swift
func cardContainer(
    isHovered: Bool,
    isSelected: Bool = false,       // selected border (selectedBorder + innerStrokeWidth)
    isFocused: Bool = false,        // focus ring (controlAccent stroke)
    isDropTargeted: Bool = false,   // drop highlight (dropTargetBorderStrong + innerStrokeWidth); overrides hover, overridden by isSelected
    cornerRadius: CGFloat = BookmarksDesign.cardCornerRadius
) -> some View
```

Border priority (highest wins): `isSelected` → `isDropTargeted` → `isHovered` → default.

### Drag-and-Drop Thumbnail (BookmarkCard)

`BookmarkCard` owns its thumbnail drop handling entirely — it calls `BookmarksStorage.shared` directly and posts `.showBookmarkCaptureToast`. There are **no** `onAssignThumbnailFrom*` callbacks on `BookmarkCard` or `BookmarksBrowserView`. Do not add them back. Any view that renders `BookmarkCard` gets working drag-and-drop with zero call-site wiring.

---

## 16b. Table List View Contract

When `displayMode == .list`, all item types render through the unified **LibraryTableView** instead of per-type list rows. This replaces `BookmarkListRow`, `NoteListRow`, `TodoListRow`, `DateCardListRow`, `ContactListRow`, and `VaultFileListRow` in list mode.

**Key files:**
- `Views/Shared/LibraryTableHeader.swift` — column headers + resize handles + column picker
- `Views/Shared/LibraryTableRow.swift` — unified row for any `LibraryItemV2`
- `Views/Shared/LibraryTableView.swift` — `LibraryTableView` (self-contained) + `LibraryTableRows` (embeddable)
- `Models/TableColumn.swift` — `TableColumnID` enum + `TableColumnConfig` (persisted widths/visibility)

**Row styling:**
- Row height: 40pt
- Checkbox (40pt) appears on hover/selection
- Background: `selectedFill` when selected, `surfaceInput` on hover, `clear` default
- Focus ring: `controlAccent` stroke (1.5pt)
- All fonts use `CiderFont.*` tokens, all colors use `CiderColors.*`
- Name column icon: 20×20 (favicon for bookmarks, SF Symbol for other types)
- Tag pills: compact inline capsules with colored dot

**Integration pattern:**
- `HomeDashboardView`: uses `LibraryTableView` (owns its own scroll)
- `FolderDetailView`: uses `LibraryTableHeader` + `LibraryTableRows` (inside existing scroll)
- `SavedViewTabContent`: same as FolderDetailView

---

## 17. Implementation Checklist

When building or modifying any UI component, verify:

- [ ] Uses acrylic background pattern (not `.glassEffect()`)
- [ ] All spacing uses `Spacing.*` tokens (no magic numbers)
- [ ] All corners use `Radius.*` tokens with `.continuous` style
- [ ] All animations use spring presets (no ease/linear)
- [ ] Reduce Motion checked with `@Environment(\.accessibilityReduceMotion)`
- [ ] Reduce Transparency checked with `@Environment(\.accessibilityReduceTransparency)`
- [ ] Colors use `CiderColors.*` tokens (no hardcoded colors)
- [ ] Fonts use `CiderFont.*` tokens (no hardcoded `.font(.system(size:weight:))`)
- [ ] Borders use `CiderBorder.innerStrokeWidth` / `.innerStrokeInset`
- [ ] Tab content padding matches the 12pt + 2pt = 14pt pattern
- [ ] Shadows drawn as blurred shapes (not `.shadow()`)
- [ ] `.help()` labels on interactive elements
- [ ] Card views use `.cardContainer()` + `.hoverState()` — no inline RoundedRectangle container code
- [ ] Compared against this document — no deviations

---

## 18. Component Catalog

When building a new feature, check this section first. If a component already exists, reuse it. If a new feature creates something reusable, add it here.

### 18.1 Shared Views (`Views/Shared/`)

#### MasonryLayout
- **File:** `Views/Shared/MasonryLayout.swift`
- **Used by:** Bookmarks, Notes
- **What:** Custom SwiftUI `Layout` that arranges items in a variable-height masonry grid with shortest-column placement
- **Config:** `minimumColumnWidth` and `itemSpacing` — column count auto-calculates from available width

#### ViewOptionsDropdown
- **File:** `Views/Shared/ViewOptionsDropdown.swift`
- **Used by:** Bookmarks, Notes (sidebar header popover in CiderPanelView)
- **What:** Generic dropdown for display mode toggle (list/grid/masonry icons) + continuous card size slider
- **Pattern:** Generic over `DisplayModeOption` protocol — any tab with display modes can use it by conforming its enum

#### FolderSidebarView
- **File:** `Views/Shared/FolderSidebarView.swift`
- **Used by:** All tabs (universal sidebar in CiderPanelView)
- **What:** Hierarchical folder tree + projects list + search trigger + quick action buttons
- **Params:** `showBackground: Bool = true` — set `false` when a wrapper provides the background (e.g., CiderPanelView's sidebar column)
- **Note:** Folders are shared across bookmarks and notes — both content types can be assigned to any folder

#### BookmarkCard
- **File:** `Views/Bookmarks/BookmarkCard.swift`
- **Used by:** Bookmarks (grid/masonry), Home (library feed grid/masonry)
- **What:** Visual card for bookmarks with thumbnail, title, domain, timestamp. Supports `.grid` and `.masonry` modes.
- **Note:** Extracted from BookmarksBrowserView to enable reuse from Home tab's mixed-content library feed

#### BookmarkListRow (legacy — superseded by LibraryTableRow in list mode)
- **File:** `Views/Bookmarks/BookmarkListRow.swift`
- **Used by:** Bookmarks (list mode — legacy, may still be referenced in BookmarksTabContent)
- **What:** Compact list row for bookmarks with optional thumbnail, title, domain, timestamp, hover delete
- **Note:** Superseded by the unified table list view. Grid/masonry modes still use per-type card views.

#### LibraryTableView / LibraryTableRows
- **Files:** `Views/Shared/LibraryTableView.swift`, `Views/Shared/LibraryTableRow.swift`, `Views/Shared/LibraryTableHeader.swift`, `Models/TableColumn.swift`
- **Used by:** HomeDashboardView, FolderDetailView, SavedViewTabContent (all in list mode)
- **What:** Unified table list view — all item types (bookmarks, notes, todos, events, contacts, files) render in the same row with column headers. 9 columns: Name (flexible), Type, Tags, Folder, Created, Modified, URL, Words, Priority. Resizable column dividers, column visibility toggling via `+` button. Config persisted in `CiderConfig.tableColumnConfig`.
- **Note:** `LibraryTableView` owns its own scroll (used by HomeDashboardView). `LibraryTableRows` is embeddable inside existing ScrollViews (used by FolderDetailView, SavedViewTabContent).

#### FolderDetailView
- **File:** `Views/Shared/FolderDetailView.swift`
- **Used by:** CiderPanelView (when a folder is selected in sidebar)
- **What:** Mixed-content view showing bookmarks + notes within a folder

#### AcrylicPanelBackground
- **File:** `Views/Shared/AcrylicPanelBackground.swift`
- **Used by:** All panels
- **What:** Standard dark acrylic background with optional custom shadows, respects accessibility transparency

#### CiderTabBar
- **File:** `Views/Shared/CiderTabBar.swift`
- **Used by:** CiderPanelView
- **What:** Horizontal scrollable tab bar with badge counts

#### CiderPanelShell
- **File:** `Views/Shared/CiderPanelShell.swift`
- **Used by:** CiderPanelView
- **What:** Generic structural shell for all panel windows — encapsulates two-column layout, sidebar container, traffic lights, title bar, divider, compact mode logic, resize handles, and shadow padding
- **Generic params:** `SidebarContent`, `SidebarFooter`, `TitleBarContent`, `Content`, `PanelOverlay`
- **Init params:** `isCollapsed`, `onClose`, `onCollapse`, `onMaximize`, plus `@ViewBuilder` closures for each generic slot
- **Handles:** Sidebar show/hide animation, compact mode auto-collapse at `CiderPanelDesign.sidebarCompactThreshold` (680pt), title bar toggle appearance, panel edge resize, acrylic background + shadow

#### PanelEdgeResizeView
- **File:** `Views/Shared/PanelEdgeResizeView.swift`
- **Used by:** CiderPanelView
- **What:** All-edge resize handles with cursor tracking

#### EmptyStateView
- **File:** `Views/Shared/EmptyStateView.swift`
- **Used by:** FolderDetailView, CiderPanelView+ContentArea, SearchTabContent, InlineNoteEditorView, StackDetailSheet, StackManagerSheet
- **What:** Vertically centered empty state with icon (36pt), title, optional subtitle, optional action button
- **Params:** `icon: String`, `title: String`, `subtitle: String?`, `actionLabel: String?`, `action: (() -> Void)?`
- **Note:** BookmarksBrowserView has its own inline empty state that scales with `textScale` — don't use this shared component there

### 18.2 Shared Utilities (`Utilities/`)

#### HighlightedText
- **File:** `Utilities/HighlightedText.swift`
- **Used by:** Notes cards/rows (titles and previews)
- **What:** SwiftUI `Text` view with search match highlighting — preserves all Text modifiers (font, color, lineLimit)
- **Note:** Search palette and search tab result rows use inline `AttributedString` snippet rendering instead (see `SearchService.SearchSnippet` + `snippetAttributedString()` in both search views) — `HighlightedText` is for card titles/previews in context, not search result rows

#### CiderFont
- **File:** `Utilities/CiderFont.swift`
- **Used by:** All views with text
- **What:** Semantic typography tokens replacing all `.font(.system(size:weight:))` declarations. 29 fixed tokens + 13 responsive `(scale:)` function variants for textScale views.
- **Pattern:** `CiderFont.body`, `CiderFont.captionMedium`, `CiderFont.subheadingSemibold`, etc.
- **Responsive:** `CiderFont.body(scale: textScale)` for views with continuous card size slider
- **When NOT to use:** Design constants (`CiderPanelDesign.trafficLightSymbolSize`), dynamic weights (`isSelected ? .semibold : .regular`), Apple semantic styles in Settings views

#### Constants (Spacing, Radius, Animation)
- **File:** `Utilities/Constants.swift`
- **What:** All design tokens — `Spacing.*`, `Radius.*`, animation presets, notification names, border constants

#### VisualEffectView
- **File:** `Utilities/VisualEffectView.swift`
- **What:** NSViewRepresentable for `NSVisualEffectView` — use instead of `.glassEffect()`

### 18.3 Search System (`Services/` + `Views/Search/`)

#### SearchService
- **File:** `Services/SearchService.swift`
- **What:** `@MainActor` enum with static search methods across all content types
- **Types searched:** Bookmarks, Notes, DateCards, Contacts (reads from storage singletons internally)
- **`SearchResult`:** `id`, `type` (`SearchResultType`), `title`, `subtitle: String?`, `snippet: SearchSnippet?`, `date`, plus optional typed payload (`bookmark`, `note`, `dateCard`, `contact`)
- **`SearchSnippet`:** `prefix`, `match`, `suffix` — 60-char context window around the query hit, with `...` truncation markers. `match` preserves original casing.
- **Rule:** `subtitle` is set when the match is in a short metadata field (host, date, tag, relationship label). `snippet` is set when the match is in a long body field (note content, bookmark notes, date card details/location, contact notes). Exactly one is non-nil.
- **`extractSnippet(query:from:windowSize:)`** — finds first case-insensitive match, returns +/-60 chars of context.

#### SearchPaletteView
- **File:** `Views/Search/SearchPaletteView.swift`
- **What:** Center-screen overlay palette (Cmd+K). Debounces search 100ms via `@State searchTask: Task`. Shows four result sections (Bookmarks, Notes, Date Cards, Contacts). Recent section shows 3 bookmarks + 2 notes + 2 date cards + 2 contacts when query is empty.
- **Snippet rendering:** `snippetAttributedString(_:)` -> `AttributedString` with `.swiftUI.foregroundColor` per range (tertiary/primary/tertiary).

#### SearchTabContent
- **File:** `Views/Search/SearchTabContent.swift`
- **What:** Full-height tab content for search tabs spawned from the palette. Same four-section layout + snippet rendering as the palette. Query is a fixed prop (no debounce needed — tab is created once per query).

---

## 19. Cross-Tab Patterns

These aren't single components but established patterns that should be followed consistently across tabs.

### 19.1 Display Modes (list / grid / masonry)
- **Used by:** Bookmarks (`BookmarkDisplayMode`), Notes (`NoteDisplayMode`), Home (`LibraryDisplayMode`)
- **Pattern:** Enum conforming to `DisplayModeOption` protocol -> plugs into `ViewOptionsDropdown`
- **Card sizing:** Continuous 0-3 slider via a sizing struct (e.g., `CardSizing`, `NoteCardSizing`, `LibraryCardSizing`) that interpolates between stops
- **Cross-type sizing:** `LibraryCardSizing` delegates to `CardSizing` and `NoteCardSizing` — mixed-content views use it to size both bookmark and note cards consistently
- **When adding a new tab with cards:** Create a `<Tab>DisplayMode` enum conforming to `DisplayModeOption` + a `<Tab>CardSizing` struct

### 19.2 Card Data Loading
- **Used by:** Notes (`NoteCardData`)
- **Pattern:** Pre-compute display data off the main thread, cache in `@State`
- **Key rule:** Use `.task(id: item.modifiedAt)` not `.task(id: item.id)` so cards refresh after edits
- **Never:** Put disk I/O or regex in SwiftUI view body — always use `.task` + `@State` cache

### 19.3 CardContextMenu (NSMenu-based)
- **File:** `Utilities/CardContextMenu.swift`
- **Used by:** Notes (NoteCardView, NoteListRow), Bookmarks (BookmarkCard, BookmarkListRow)
- **What:** Native `NSMenu` context menu that builds fresh on every right-click, replacing SwiftUI's `.contextMenu` which caches content and goes stale when data changes
- **Architecture:** `CardMenuItem` enum (.action, .submenu, .separator, .destructive) -> `CardContextMenuModifier` -> invisible `RightClickView` overlay with `hitTest` pass-through for non-right-click events
- **Convenience extensions:** `.noteContextMenu()` (Open, Rename, Move to Folder, Delete) and `.bookmarkContextMenu()` (Open in Browser, Show Details, Move to Folder, Delete)
- **Adding a new context menu:** Create a new View extension that returns `CardContextMenuModifier` with the desired `CardMenuItem` list
- **Key detail:** `RightClickView.hitTest()` returns nil for non-right-click events so left clicks, hovers, and drags pass through to SwiftUI content underneath
- **Why not `.contextMenu`:** SwiftUI caches `.contextMenu` content inside lazy containers (`LazyVStack`, `LazyVGrid`). After any data change (moving items to folders, creating folders), the menu shows stale content. No workaround (`.id()`, removing conditionals) reliably fixes it.

### 19.4 Container Style Modifiers
- **File:** `Utilities/ContainerStyles.swift`
- **Used by:** CiderPanelShell, BookmarksBrowserView, RootFolderOverviewView, NoteCardView
- **What:** Two `ViewModifier`s for common container background + border patterns
- **Modifiers:**
  - `.sectionContainer(cornerRadius:)` — static elevated container: `surfaceElevated` fill + `borderDefault` stroke + `innerStrokeWidth`. Default radius: `Radius.md`. For sidebar columns, panel sections, folder cards.
  - `.cardContainer(isHovered:, isSelected:, isFocused:, isDropTargeted:, cornerRadius:)` — hover-aware card: `surfaceElevated`/`surfaceHover` fill + `borderSubtle`/`borderHover` stroke + clipShape + contentShape. Default radius: `BookmarksDesign.cardCornerRadius`. For masonry/grid cards.
- **When NOT to use:** Containers with conditional backgrounds (FolderSidebarView's `showBackground` flag) or cards with custom stroke logic (BookmarksBrowserView's drop-target border)

### 19.5 Button Styles
- **File:** `Utilities/ButtonStyles.swift`
- **Used by:** Settings views (currently), any view needing pill-shaped action buttons
- **What:** Three shared `ButtonStyle` variants for pill-shaped action buttons with rounded backgrounds and press states
- **Styles:**
  - `CiderAccentButtonStyle` — primary action (accent text on `accentSubtle` bg, `accentLight` on press)
  - `CiderDestructiveButtonStyle` — destructive action (red text on `destructiveSubtle` bg, `destructiveLight` on press)
  - `CiderSecondaryButtonStyle` — cancel/dismiss (secondary text on `surfaceInput` bg, `surfaceHover` on press)
- **All three share:** `.font(CiderFont.body)` + `.padding(.horizontal: Spacing.md, .vertical: Spacing.sm)` + `RoundedRectangle(Radius.sm)` background
- **When NOT to use:** Icon-only toolbar buttons (use `.buttonStyle(.plain)`) or buttons that need `textScale` multipliers (style inline)

### 19.6 Hover State Modifier
- **File:** `Utilities/HoverState.swift`
- **Used by:** All interactive views with hover effects
- **What:** `.hoverState($isHovered)` — binds hover to a `@State` Bool. Optional `animation:` parameter wraps state change in `withAnimation` with automatic Reduce Motion respect.
- **Usage:**
  - `.hoverState($isHovered)` — plain binding (use when view has `.animation(_, value: isHovered)`)
  - `.hoverState($isHovered, animation: .snappy)` — animated (use when no `.animation()` on view)
- **Remaining `.onHover`:** `BookmarksBrowserView` list row (custom hover callback) and `BookmarkCaptureToastPanel` (toast dismiss logic) — both have custom `onHoverChanged` callbacks, can't use shared modifier

### 19.7 Inline Rename
- **Used by:** Notes (NoteCardView, NoteListRow)
- **Pattern:** Local `@State isRenaming` + `@State renamingTitle` + `@FocusState` per card
- **Flow:** Context menu "Rename" -> title swaps to TextField -> Enter saves, Escape cancels
- **Focus:** Use `.task { try? await Task.sleep(for: .milliseconds(150)); focused = true }` — NSPanel needs delay for `@FocusState`
- **Reuse opportunity:** Bookmark cards, folder rename in sidebar

### 19.8 Folder Assignment
- **Used by:** Notes (via context menu), Bookmarks (via drag-and-drop and context menu)
- **Pattern:** Folders stored in `BookmarksStorage.shared.folders`, shared across all content types
- **Future:** Notes will support drag-to-folder (matching bookmarks) and multi-folder membership (`folderIDs: [UUID]` instead of `folderID: UUID?`)

---

## 20. File Reference

| File | Contains |
|------|----------|
| `Utilities/Constants.swift` | All tokens: Spacing, Radius, CiderBorder, CiderColors, *Design enums, CiderAnimation |
| `Utilities/CiderFont.swift` | All typography tokens: CiderFont.body, .caption, .label, .subheading, .heading, .title, .display, .micro, .badge + responsive `(scale:)` variants |
| `Utilities/ButtonStyles.swift` | Shared button styles: CiderAccentButtonStyle, CiderDestructiveButtonStyle, CiderSecondaryButtonStyle |
| `Utilities/ContainerStyles.swift` | Container modifiers: `.sectionContainer()`, `.cardContainer(isHovered:)` |
| `Utilities/HoverState.swift` | Shared hover state modifier: `.hoverState($isHovered)` with Reduce Motion respect |
| `Utilities/HighlightedText.swift` | Search match highlighting for Text views |
| `Utilities/CardContextMenu.swift` | NSMenu-based context menus replacing SwiftUI `.contextMenu` |
| `Views/Shared/AcrylicPanelBackground.swift` | Acrylic background + shadow implementation |
| `Views/Shared/PanelEdgeResizeView.swift` | All-edge resize handle NSView |
| `Views/Shared/CiderTabBar.swift` | Tab bar component |
| `Views/Shared/CiderPanelShell.swift` | Shared panel shell: sidebar container, traffic lights, title bar, compact mode, resize handles, shadow padding |
| `Views/Shared/FolderSidebarView.swift` | Sidebar content (folders, projects) |
| `Views/Shared/EmptyStateView.swift` | Shared empty state: icon + title + optional subtitle/action button |
| `Views/Shared/MasonryLayout.swift` | Variable-height masonry grid layout |
| `Views/Shared/ViewOptionsDropdown.swift` | Display mode toggle + card size slider |
| `Views/Shared/LibraryTableView.swift` | Unified table list view (self-contained + embeddable) |
| `Views/Shared/FolderDetailView.swift` | Mixed-content folder view |
| `Views/CiderPanelView.swift` | Main panel (uses CiderPanelShell, provides tab/folder/search logic) |
| `Docs/Design/ACRYLIC_IMPLEMENTATION.md` | Detailed acrylic/shadow implementation guide |
| `Docs/Features/DETAIL_PANEL_SPEC.md` | Detail view layout specification |
| `Docs/Features/INTEGRATION_DESIGN.md` | Obsidian/knowledge-base integration design |

---

## Changelog

| Date | Change |
|------|--------|
| 2026-03-18 | Absorbed SHARED_COMPONENTS.md: added component catalog (§18), cross-tab patterns (§19). Trimmed acrylic section to overview + cross-ref to ACRYLIC_IMPLEMENTATION.md. Expanded file reference (§20). |
| 2026-02-16 | Added CiderFont typography tokens (§3.5), button styles (§15), container modifiers, hover state. Complete rewrite as binding specification. Documented exact panel layout, sidebar structure, padding chain, resize handles, compact mode. Replaced outdated component specs. |
| 2026-02-04 | Rewrote for command palette focus, replaced Liquid Glass with acrylic style |
| 2026-02-02 | Initial design system |
