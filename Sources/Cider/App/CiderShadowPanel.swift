import AppKit
import SwiftUI

/// A transparent NSPanel that renders a custom drop shadow behind CiderPanel.
///
/// The main panel keeps `hasShadow = false` and zero frame padding so window
/// snapping works correctly. This panel sits behind it at the same z-level and
/// draws whatever shadow shape we want without affecting the main panel's frame.
final class CiderShadowPanel: NSPanel {
    /// How many points this panel extends beyond the main panel on each side.
    static let padding: CGFloat = 80
    /// Blur radius for the shadow shape.
    static let blurRadius: CGFloat = 28

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        contentView = NSHostingView(rootView: CiderShadowView(
            cornerRadius: CiderPanelDesign.cornerRadius,
            padding: Self.padding,
            blurRadius: Self.blurRadius
        ))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// Repositions and resizes this panel to surround `panelFrame`.
    func updateFrame(for panelFrame: NSRect) {
        let p = Self.padding
        setFrame(NSRect(
            x: panelFrame.minX - p,
            y: panelFrame.minY - p,
            width: panelFrame.width + p * 2,
            height: panelFrame.height + p * 2
        ), display: true)
    }
}

private struct CiderShadowView: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    let blurRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.black.opacity(0.6))
            .padding(padding)
            .blur(radius: blurRadius)
    }
}
