import AppKit
import SwiftUI

final class ClipboardPanel: NSPanel {
    // Window dragging state
    private var dragStartOrigin: NSPoint?
    private var dragStartMouse: NSPoint?
    private var isDragging = false

    init() {
        let initialFrame = NSRect(
            x: 0,
            y: 0,
            width: ClipboardPanelDesign.defaultWidth,
            height: ClipboardPanelDesign.defaultHeight
        )

        super.init(
            contentRect: initialFrame,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
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
            width: ClipboardPanelDesign.minWidth,
            height: ClipboardPanelDesign.minHeight
        )

        contentView?.wantsLayer = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        var rect = frameRect
        rect.size.width = max(ClipboardPanelDesign.minWidth, rect.size.width)
        rect.size.height = max(ClipboardPanelDesign.minHeight, rect.size.height)
        return rect
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var r = frameRect
        r.size.width = max(ClipboardPanelDesign.minWidth, r.size.width)
        super.setFrame(r, display: flag)
    }

    // MARK: - Window Dragging

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            if isInDraggableArea(event.locationInWindow) {
                dragStartOrigin = frame.origin
                dragStartMouse = NSEvent.mouseLocation
                isDragging = false
            }
            super.sendEvent(event)

        case .leftMouseDragged:
            if let startOrigin = dragStartOrigin,
               let startMouse = dragStartMouse {
                let currentMouse = NSEvent.mouseLocation
                let dx = currentMouse.x - startMouse.x
                let dy = currentMouse.y - startMouse.y

                if !isDragging && (abs(dx) > 3 || abs(dy) > 3) {
                    isDragging = true
                }

                if isDragging {
                    setFrameOrigin(NSPoint(
                        x: startOrigin.x + dx,
                        y: startOrigin.y + dy
                    ))
                    return
                }
            }
            super.sendEvent(event)

        case .leftMouseUp:
            dragStartOrigin = nil
            dragStartMouse = nil
            isDragging = false
            super.sendEvent(event)

        default:
            super.sendEvent(event)
        }
    }

    private func isInDraggableArea(_ locationInWindow: NSPoint) -> Bool {
        guard let contentView = contentView else { return false }
        let bounds = contentView.bounds

        // Check if the hit view is an interactive control or our resize view
        if let hitView = contentView.hitTest(locationInWindow) {
            var view: NSView? = hitView
            while let v = view, v !== contentView {
                if v is NSControl { return false }
                if v is PanelEdgeResizeNSView { return false }
                view = v.superview
            }
        }

        // Header region: top 48pt is draggable (covers the "Clipboard" title bar area)
        let headerMinY = bounds.height - 48
        return locationInWindow.y >= headerMinY
    }
}
