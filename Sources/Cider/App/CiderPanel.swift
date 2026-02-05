import AppKit
import SwiftUI

final class CiderPanel: NSPanel {
    init(contentRect: NSRect) {
        // Borderless panel for clean Raycast-style appearance
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false  // We draw our own shadow

        isMovable = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Container view that ensures arrow cursor is shown over the panel
final class CiderPanelContentView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Ensure cursor rects are updated when view changes
        window?.invalidateCursorRects(for: self)
    }
}

/// Custom NSHostingView that accepts first mouse clicks in non-key windows
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    // Ensure we capture all clicks within our bounds
    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        // If super returns nil but point is in bounds, return self to capture the click
        if result == nil && bounds.contains(point) {
            return self
        }
        return result
    }
}
