# Cider Design System

> **Purpose:** This document defines every visual and interaction token for Cider.
> All agent sessions must read this before writing any UI code.

---

## 1. Design Philosophy

Cider is a native macOS command palette. It uses a **Raycast-inspired acrylic material** that provides a clean, dark, translucent appearance that works on any desktop background.

**Core principles:**

- **Content over chrome.** The UI exists to show windows and apps, not to decorate.
- **Dark acrylic aesthetic.** Dark translucent backgrounds with subtle borders and highlights.
- **Physics-based motion.** Every animation uses springs. No linear or ease-in-out curves.
- **Respect system settings.** Dark mode, accent color, Reduce Motion, Reduce Transparency.
- **Restraint.** Fewer effects done perfectly beats many effects done approximately.

**DO NOT use Apple's Liquid Glass** (`.glassEffect()`) — we intentionally chose the Raycast aesthetic for its cleaner, more predictable appearance.

---

## 2. Color Palette

### 2.1 Command Palette Colors

The acrylic palette uses a specific dark color palette:

| Element | Color | Usage |
|---------|-------|-------|
| Background tint | `Color.black.opacity(0.45)` | Over visual effect view |
| Highlight layer | `Color.white.opacity(0.03)` | Subtle surface highlight |
| Border | `Color.white.opacity(0.25)` | Panel border stroke |
| Dividers | `Color.white.opacity(0.2)` | Section separators |
| Hover states | `Color.white.opacity(0.08)` | List item hover |
| Selected states | `Color.white.opacity(0.1)` | Active selection |
| Button backgrounds | `Color.white.opacity(0.05)` | Secondary buttons |
| Footer background | `Color.white.opacity(0.03)` | Footer area tint |

### 2.2 CiderColors (Constants.swift)

Centralized color tokens used throughout the command palette:

| Token | Value | Usage |
|-------|-------|-------|
| `CiderColors.primary` | `Color.primary` | Primary labels, titles |
| `CiderColors.secondary` | `Color.secondary` | Subtitles, metadata |
| `CiderColors.tertiary` | `Color(.tertiaryLabelColor)` | Placeholder text, hints |
| `CiderColors.quaternary` | `Color(.quaternaryLabelColor)` | Disabled text |
| `CiderColors.separator` | `Color(.separatorColor)` | Dividers |
| `CiderColors.controlAccent` | `Color(.controlAccentColor)` | System accent |
| `CiderColors.label` | `Color(.labelColor)` | Standard label |
| `CiderColors.selectedContent` | `Color(.selectedContentBackgroundColor)` | Selection |
| `CiderColors.success` | `Color.green` | Confirmations |
| `CiderColors.destructive` | `Color(.systemRed)` | Destructive actions |
| `CiderColors.opaqueBackground` | `Color(.windowBackgroundColor)` | Reduce Transparency fallback |

These use system semantic colors that automatically adapt to dark/light mode and high contrast settings. Inside the acrylic palette (which has a dark translucent background), `.primary` renders as white and `.secondary` as white at 60% opacity.

### 2.3 Brand Color (Cider Amber)

| Token | Value | Usage |
|-------|-------|-------|
| `Cider.amber` | `#D97706` | App icon, marketing only |

The amber brand color never appears in the UI. All interactive elements use system accent color or white-based neutrals.

### 2.4 Status Colors

| Status | Color | Usage |
|--------|-------|-------|
| Running indicator | App's extracted accent color | Thin bar under running apps |
| Success | `Color.green` | Confirmations |
| Warning | `Color.orange` | Warnings |
| Error | `Color.red` | Errors |

---

## 3. Typography

### 3.1 System Font

Cider uses **SF Pro** (the macOS system font) exclusively.

### 3.2 Type Scale

| Style | Size | Weight | Usage |
|-------|------|--------|-------|
| Search bar | 18pt | Regular | Search field text |
| Section headers | 11pt | Medium | "Pinned", "Windows" labels |
| App names | 10pt | Regular | Under pinned app icons |
| Window titles | 12pt | Regular | Window list items |
| App group headers | 12pt | Medium | App name in window list |
| Footer text | 11pt | Regular | Footer bar hints |
| Metadata | 10pt | Regular | Window counts, secondary info |

### 3.3 Text Scaling

Cider supports user-configurable text scaling:

| Setting | Scale | Usage |
|---------|-------|-------|
| Small | 0.85 | Compact view |
| Medium | 1.0 | Default |
| Large | 1.18 | Accessibility |

All font sizes multiply by the `textScale` environment value.

---

## 4. Spacing Scale

| Token | Value | Usage |
|-------|-------|-------|
| `Spacing.xxs` | 2pt | Hairline gaps |
| `Spacing.xs` | 4pt | Tight internal padding |
| `Spacing.sm` | 8pt | Between elements, standard padding |
| `Spacing.md` | 12pt | Section padding |
| `Spacing.lg` | 16pt | Between sections |
| `Spacing.xl` | 20pt | Large separations |
| `Spacing.xxl` | 24pt | Major areas |
| `Spacing.xxxl` | 32pt | Page margins |

---

## 5. Corner Radii

| Token | Value | Usage |
|-------|-------|-------|
| `Radius.xs` | 4pt | Small badges, tags |
| `Radius.sm` | 6pt | Buttons, hover backgrounds |
| `Radius.md` | 10pt | App icons, cards |
| `Radius.lg` | 14pt | Inner panels |
| `Radius.xl` | 20pt | Main palette corners |

**Always use `.continuous` style** for RoundedRectangle.

---

## 6. Acrylic Material

### 6.1 Implementation

See `ACRYLIC_STYLE.md` for complete implementation details. Core pattern:

```swift
ZStack {
    // Visual effect layer
    VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)

    // Dark tint
    Color.black.opacity(0.45)

    // Subtle highlight
    Color.white.opacity(0.03)
}
.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
```

### 6.2 Shadow Technique

Draw shadows as **blurred shapes**, not using `.shadow()` modifier:

```swift
RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    .fill(Color.black)
    .blur(radius: 18)
    .offset(y: 18)
    .opacity(0.7)
```

### 6.3 Border Technique

Use `.stroke()` with inset, not `.strokeBorder()`:

```swift
RoundedRectangle(cornerRadius: cornerRadius - 0.75, style: .continuous)
    .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
    .padding(0.75)
```

---

## 7. Component Specifications

### 7.1 Command Palette

| Property | Value |
|----------|-------|
| Corner radius | 14pt |
| Border | 1.5px white @ 25% |
| Shadow | Blurred shape, 18px blur, 18px Y offset, 70% black |
| Width (Small) | 480pt |
| Width (Medium) | 600pt |
| Width (Large) | 760pt |
| Min Height (Small/Med/Large) | 320 / 400 / 480 |
| Max Height (Small/Med/Large) | 480 / 600 / 720 |

### 7.2 Pinned Apps Row

| Property | Value |
|----------|-------|
| Icon size | 48pt (× textScale) |
| Folder icon size | 48pt (× textScale) |
| Grid spacing | 12pt |
| Running indicator | 2pt tall colored bar, 50% icon width |
| Hover scale | 1.1× |

### 7.3 Window List Item

| Property | Value |
|----------|-------|
| Height | ~26–32pt (scales with text size) |
| Icon size | 16pt |
| Padding | 6pt vertical, 8pt horizontal |
| Hover background | white @ 8% |
| Corner radius | 6pt |

### 7.4 Settings Window

| Property | Value |
|----------|-------|
| Width | 750pt |
| Height | 580pt |
| Same acrylic style as command palette |

### 7.5 Floating Window Traffic Lights

Use the Notes traffic-light geometry for all floating panels/windows (Notes, Settings, and future surfaces) to keep controls visually consistent.

| Token | Value | Source |
|-------|-------|--------|
| Circle diameter | 12pt | `NotesDesign.trafficLightDiameter` |
| Center spacing | 4pt | `NotesDesign.trafficLightSpacing` |
| Tap target | 16pt × 16pt | `NotesDesign.trafficLightTapTarget` |
| Symbol size (hover glyphs) | 7pt | `NotesDesign.trafficLightSymbolSize` |

Do not introduce alternate traffic-light sizing/spacing constants per window.

---

## 8. Animation Tokens

### 8.1 Spring Presets

| Preset | SwiftUI API | Usage |
|--------|-------------|-------|
| Smooth | `.smooth` | Default transitions |
| Snappy | `.snappy` | Menus, hover states |
| Bouncy | `.bouncy` | Playful interactions |

### 8.2 Custom Springs

| Token | API | Usage |
|-------|-----|-------|
| `hoverMagnify` | `.spring(duration: 0.25, bounce: 0.05)` | Icon hover scale |
| `listReorder` | `.spring(duration: 0.3, bounce: 0.08)` | List shuffle |

### 8.3 Animation Rules

- Every interactive animation uses springs
- Dismiss is faster than appear
- **Reduce Motion:** Replace springs with 0.2s opacity crossfades

---

## 9. Interaction Patterns

### 9.1 Hover States

| Element | Effect | Animation |
|---------|--------|-----------|
| Pinned app icon | Scale to 1.1× | `.snappy` |
| Window list item | Background highlight @ 8% | `.snappy` |
| Action buttons | Opacity increase | `.snappy` |

### 9.2 Press States

| Element | Effect |
|---------|--------|
| Buttons | Scale to 0.95× |
| List items | Background @ 10% |

### 9.3 Context Menus

Use native `NSMenu` via SwiftUI's `.contextMenu { }` modifier.

---

## 10. Accessibility

### 10.1 Required Adaptations

| Setting | Cider Behavior |
|---------|----------------|
| Reduce Motion | 0.2s opacity crossfades, no scale |
| Reduce Transparency | Opaque `windowBackgroundColor` fallback |
| Dark Mode | Automatic via semantic colors |
| VoiceOver | Labels on all interactive elements |

### 10.2 Minimum Targets

- Click targets: 28pt × 28pt minimum
- Pinned apps: 44pt × 44pt
- Text contrast: Automatically met via high-contrast palette

---

## 11. Implementation Checklist

When building any new UI component:

- [ ] Uses acrylic pattern (not Liquid Glass)
- [ ] All spacing uses tokens (no magic numbers)
- [ ] All corners use `.continuous` style
- [ ] All animations use springs
- [ ] Hover and press states defined
- [ ] Reduce Motion respected
- [ ] Reduce Transparency respected
- [ ] VoiceOver labels present
- [ ] Works in light and dark mode

---

## Changelog

| Date | Change |
|------|--------|
| 2026-02-04 | Rewrote for command palette focus, replaced Liquid Glass with acrylic style |
| 2026-02-02 | Initial design system |
