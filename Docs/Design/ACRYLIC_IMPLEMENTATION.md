# Cider Acrylic Style Guide

Cider uses a **Raycast-inspired acrylic material** for its floating panels. This creates a modern, dark aesthetic with subtle transparency that blends with any desktop background.

## Core Approach

We use `NSVisualEffectView` with `.underWindowBackground` material and `.behindWindow` blending, combined with color overlays to achieve a dark, translucent look.

**DO NOT** use Apple's Liquid Glass (`.glassEffect()`) - we intentionally chose the Raycast aesthetic for its cleaner, more predictable appearance.

---

## Implementation Pattern

### Background View (SwiftUI)

```swift
struct AcrylicPanelBackground: View {
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
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
            CiderColors.acrylicTint
            CiderColors.surfaceHighlight
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius - CiderBorder.innerStrokeInset, style: .continuous)
                .stroke(CiderColors.borderPanel, lineWidth: CiderBorder.innerStrokeWidth)
                .padding(CiderBorder.innerStrokeInset)
        )
    }

    @ViewBuilder
    private var opaqueBackground: some View {
        // Fallback for Reduce Transparency accessibility setting
        Color(nsColor: NSColor.windowBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius - CiderBorder.innerStrokeInset, style: .continuous)
                    .stroke(CiderColors.separatorStrong, lineWidth: CiderBorder.innerStrokeWidth)
                    .padding(CiderBorder.innerStrokeInset)
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
    let state: NSVisualEffectView.State

    init(material: NSVisualEffectView.Material,
         blendingMode: NSVisualEffectView.BlendingMode,
         state: NSVisualEffectView.State = .active) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = PassthroughVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

private final class PassthroughVisualEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Allow clicks to pass through to SwiftUI content.
        return nil
    }
}
```

---

## NSPanel Configuration

All floating panels must be configured correctly:

```swift
final class CiderPanel: NSPanel {
    init() {
        let initialFrame = NSRect(
            x: 0,
            y: 0,
            width: CiderPanelDesign.panelContentWidth,
            height: CiderPanelDesign.panelContentHeight
        )

        super.init(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        isMovableByWindowBackground = false
        isReleasedWhenClosed = false

        self.minSize = NSSize(
            width: CiderPanelDesign.panelMinWidth,
            height: CiderPanelDesign.panelMinHeight
        )

        contentView?.wantsLayer = true
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

**Window padding:** Shadow padding is now `0` everywhere (`CiderPanelDesign.shadowPadding = 0`). The NSWindow frame matches the visible panel exactly — no extra padding is needed for shadow rendering. The panel content width and height are computed directly from the design tokens:

```swift
// CiderPanelDesign (Constants.swift)
static let shadowPadding: CGFloat = 0
static let topPadding: CGFloat = 0
static let bottomPadding: CGFloat = 0

static var panelContentWidth: CGFloat {
    defaultWidth + shadowPadding * 2   // 780pt
}
static var panelContentHeight: CGFloat {
    defaultHeight + topPadding + shadowPadding + bottomPadding  // 640pt
}
```

---

## Border & Divider Guidelines

### Border Stroke
- Width: `CiderBorder.innerStrokeWidth` (1.5px)
- Color: `CiderColors.borderPanel`
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

| Element | Token | Raw Value |
|---------|-------|-----------|
| Background tint | `CiderColors.acrylicTint` | `Color.black.opacity(0.45)` |
| Highlight layer | `CiderColors.surfaceHighlight` | `Color.white.opacity(0.03)` |
| Border | `CiderColors.borderPanel` | `Color.white.opacity(0.25)` |
| Dividers | `CiderColors.separator` | semantic |
| Hover states | `CiderColors.surfaceInput` | `Color.white.opacity(0.08)` |
| Selected states | `CiderColors.surfaceHover` | `Color.white.opacity(0.1)` |
| Footer background | `CiderColors.surfaceHighlight` | `Color.white.opacity(0.03)` |

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

- `AcrylicPanelBackground.swift` - Panel acrylic background (`Views/Shared/`)
- `SettingsBackgroundView` - Settings window background (in `SettingsComponents.swift`)
- `CiderPanel.swift` - NSPanel configuration (`App/`)
- `SettingsWindow.swift` - Settings NSWindow configuration
