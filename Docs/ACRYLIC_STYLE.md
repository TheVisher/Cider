# Cider Acrylic Style Guide

Cider uses a **Raycast-inspired acrylic material** for its floating panels. This creates a modern, dark aesthetic with subtle transparency that blends with any desktop background.

## Core Approach

We use `NSVisualEffectView` with `.underWindowBackground` material and `.behindWindow` blending, combined with color overlays to achieve a dark, translucent look.

**DO NOT** use Apple's Liquid Glass (`.glassEffect()`) - we intentionally chose the Raycast aesthetic for its cleaner, more predictable appearance.

---

## Implementation Pattern

### Background View (SwiftUI)

```swift
struct PaletteBackgroundView: View {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            opaqueBackground
        } else {
            acrylicBackground
        }
    }

    @ViewBuilder
    private var acrylicBackground: some View {
        ZStack {
            // Shadow layer - drawn as blurred shape (not .shadow() modifier)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black)
                .blur(radius: 18)
                .offset(y: 18)
                .opacity(0.7)

            // Main acrylic content
            ZStack {
                VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                Color.black.opacity(0.45)  // Dark tint
                Color.white.opacity(0.03)  // Subtle highlight
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                // Border stroke - use .stroke() not .strokeBorder() for proper alignment
                RoundedRectangle(cornerRadius: cornerRadius - 0.75, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                    .padding(0.75)
            )
        }
    }

    @ViewBuilder
    private var opaqueBackground: some View {
        // Fallback for Reduce Transparency accessibility setting
        Color(nsColor: NSColor.windowBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius - 0.75, style: .continuous)
                    .stroke(CiderColors.separator.opacity(0.5), lineWidth: 1.5)
                    .padding(0.75)
            )
    }
}
```

### NSVisualEffectView Wrapper

```swift
import SwiftUI
import AppKit

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
```

---

## NSPanel Configuration

All floating panels must be configured correctly:

```swift
final class CommandPalettePanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false  // We draw our own shadow

        isMovable = false
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
```

**Key points:**
- `.borderless` - No system chrome, we draw everything
- `.nonactivatingPanel` - Doesn't steal focus from other apps
- `hasShadow = false` - We draw custom shadows as blurred shapes
- `backgroundColor = .clear` - Transparent window for our custom background

---

## Shadow Technique

We draw shadows as **blurred shapes** rather than using SwiftUI's `.shadow()` modifier. This prevents clipping issues when the shadow extends beyond the content bounds.

```swift
// Shadow as blurred shape
RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    .fill(Color.black)
    .blur(radius: 18)
    .offset(y: 18)  // Push shadow down
    .opacity(0.7)
```

**Window padding:** The panel must be larger than the visible content to give shadows room to render:

```swift
let shadowPadding: CGFloat = 45
let paletteView = CommandPaletteView(viewModel: viewModel)
    .padding(.horizontal, shadowPadding)
    .padding(.top, 20)
    .padding(.bottom, shadowPadding + 15)

let width = paletteSize.width + shadowPadding * 2
let height = paletteSize.maxHeight + 20 + shadowPadding + 15
panel.setContentSize(NSSize(width: width, height: height))
```

---

## Border & Divider Guidelines

### Border Stroke
- Width: `1.5px`
- Color: `Color.white.opacity(0.25)`
- Use `.stroke()` with inset, not `.strokeBorder()` to avoid corner artifacts

### Internal Dividers
- Width: `1px`
- Color: `Color.white.opacity(0.2)`
- Horizontal padding: Match border width (1.5px) to avoid overlap at edges

```swift
// Divider that doesn't overlap with border
Divider()
    .padding(.horizontal, 1.5)
    .opacity(0.3)

// Or as Rectangle for more control
Rectangle()
    .fill(Color.white.opacity(0.2))
    .frame(height: 1)
    .padding(.horizontal, 1.5)
```

---

## Color Palette

The acrylic style uses a limited, dark color palette:

| Element | Color |
|---------|-------|
| Background tint | `Color.black.opacity(0.45)` |
| Highlight layer | `Color.white.opacity(0.03)` |
| Border | `Color.white.opacity(0.25)` |
| Dividers | `Color.white.opacity(0.2)` |
| Hover states | `Color.white.opacity(0.08)` |
| Selected states | `Color.white.opacity(0.1)` |
| Button backgrounds | `Color.white.opacity(0.05)` |
| Footer background | `Color.white.opacity(0.03)` |

---

## Accessibility

Always respect `accessibilityReduceTransparency`:

```swift
@Environment(\.accessibilityReduceTransparency) private var reduceTransparency

var body: some View {
    if reduceTransparency {
        // Solid opaque background
        Color(nsColor: NSColor.windowBackgroundColor)
    } else {
        // Acrylic effect
        acrylicBackground
    }
}
```

---

## Common Mistakes

### DON'T use .shadow() modifier
```swift
// BAD - shadow gets clipped by window bounds
.shadow(color: .black.opacity(0.5), radius: 20)
```

### DON'T use .glassEffect()
```swift
// BAD - we don't use Liquid Glass
.glassEffect(.regular, in: RoundedRectangle(...))
```

### DON'T use .strokeBorder() for borders
```swift
// BAD - causes corner artifacts with thick borders
.strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5)
```

### DO draw shadows as shapes
```swift
// GOOD
RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    .fill(Color.black)
    .blur(radius: 18)
    .offset(y: 18)
    .opacity(0.7)
```

### DO use .stroke() with padding for borders
```swift
// GOOD
RoundedRectangle(cornerRadius: cornerRadius - 0.75, style: .continuous)
    .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
    .padding(0.75)
```

---

## File References

- `PaletteBackgroundView.swift` - Command palette background
- `SettingsBackgroundView` - Settings window background (in SettingsView.swift)
- `CommandPalettePanel.swift` - NSPanel configuration
- `SettingsWindow.swift` - Settings NSWindow configuration
