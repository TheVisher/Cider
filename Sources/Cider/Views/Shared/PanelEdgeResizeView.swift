import SwiftUI
import AppKit

struct PanelEdgeResizeView: NSViewRepresentable {
    func makeNSView(context: Context) -> PanelEdgeResizeNSView {
        PanelEdgeResizeNSView()
    }

    func updateNSView(_ nsView: PanelEdgeResizeNSView, context: Context) {}
}

final class PanelEdgeResizeNSView: NSView {
    private var trackingArea: NSTrackingArea?
    private var currentZone: ResizeZone = .none

    override var mouseDownCanMoveWindow: Bool { false }
    override var isFlipped: Bool { false }

    enum ResizeZone {
        case none
        case left, right, top, bottom
        case topLeft, topRight, bottomLeft, bottomRight
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let zone = resolveZone(at: point)
        if zone == .none {
            return nil
        }
        return self
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let zone = resolveZone(at: point)
        if zone != .none {
            updateCursor(for: zone)
        } else if currentZone != .none {
            // Was in a resize zone, now leaving — restore default
            NSCursor.arrow.set()
        }
        currentZone = zone
    }

    override func mouseEntered(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let zone = resolveZone(at: point)
        if zone != .none {
            updateCursor(for: zone)
        }
        currentZone = zone
    }

    override func mouseExited(with event: NSEvent) {
        if currentZone != .none {
            NSCursor.arrow.set()
        }
        currentZone = .none
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = self.window else { return }

        let point = convert(event.locationInWindow, from: nil)
        let zone = resolveZone(at: point)
        guard zone != .none else { return }

        let initialFrame = window.frame
        let initialMouse = NSEvent.mouseLocation

        var keepRunning = true
        while keepRunning {
            guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }

            switch next.type {
            case .leftMouseDragged:
                let mouse = NSEvent.mouseLocation
                let dx = mouse.x - initialMouse.x
                let dy = mouse.y - initialMouse.y

                var newFrame = initialFrame
                applyResize(zone: zone, dx: dx, dy: dy, initial: initialFrame, frame: &newFrame)
                window.setFrame(newFrame, display: true)

            case .leftMouseUp:
                keepRunning = false

            default:
                break
            }
        }
    }

    // MARK: - Zone Resolution

    private func resolveZone(at point: NSPoint) -> ResizeZone {
        let hPad = CiderPanelDesign.shadowPadding
        let topPad = CiderPanelDesign.topPadding
        let bottomPad = CiderPanelDesign.shadowPadding + CiderPanelDesign.bottomPadding
        let cornerSize = CiderPanelDesign.resizeCornerSize
        let edgeInset: CGFloat = 6  // extend this many pt into the content for easier grab

        // Content rect — the visible acrylic area (NSView: y=0 is bottom)
        let contentMinX = hPad
        let contentMaxX = bounds.width - hPad
        let contentMinY = bottomPad
        let contentMaxY = bounds.height - topPad

        // Extended zones (shadow + a few pt into content for easier grabbing)
        let inLeftExt   = point.x < contentMinX + edgeInset
        let inRightExt  = point.x > contentMaxX - edgeInset
        let inBottomExt = point.y < contentMinY + edgeInset
        let inTopExt    = point.y > contentMaxY - edgeInset

        // Must be in at least one extended zone
        guard inLeftExt || inRightExt || inBottomExt || inTopExt else { return .none }

        // Corners — use extended zones (shadow + edge inset) so corners
        // are reachable even where shadow padding is thin (e.g. top: 20pt)
        let nearLeft   = point.x < contentMinX + cornerSize
        let nearRight  = point.x > contentMaxX - cornerSize
        let nearBottom = point.y < contentMinY + cornerSize
        let nearTop    = point.y > contentMaxY - cornerSize

        if inTopExt    && nearLeft  || inLeftExt  && nearTop    { return .topLeft }
        if inTopExt    && nearRight || inRightExt && nearTop    { return .topRight }
        if inBottomExt && nearLeft  || inLeftExt  && nearBottom { return .bottomLeft }
        if inBottomExt && nearRight || inRightExt && nearBottom { return .bottomRight }

        // Edges — use extended zones for better grab area
        if inLeftExt   { return .left }
        if inRightExt  { return .right }
        if inTopExt    { return .top }
        if inBottomExt { return .bottom }

        return .none
    }

    // MARK: - Cursor

    private func updateCursor(for zone: ResizeZone) {
        switch zone {
        case .none:
            NSCursor.arrow.set()
        case .left:
            NSCursor.frameResize(position: .left, directions: [.inward, .outward]).set()
        case .right:
            NSCursor.frameResize(position: .right, directions: [.inward, .outward]).set()
        case .top:
            NSCursor.frameResize(position: .top, directions: [.inward, .outward]).set()
        case .bottom:
            NSCursor.frameResize(position: .bottom, directions: [.inward, .outward]).set()
        case .topLeft:
            NSCursor.frameResize(position: .topLeft, directions: [.inward, .outward]).set()
        case .topRight:
            NSCursor.frameResize(position: .topRight, directions: [.inward, .outward]).set()
        case .bottomLeft:
            NSCursor.frameResize(position: .bottomLeft, directions: [.inward, .outward]).set()
        case .bottomRight:
            NSCursor.frameResize(position: .bottomRight, directions: [.inward, .outward]).set()
        }
    }

    // MARK: - Resize Math

    private func applyResize(
        zone: ResizeZone,
        dx: CGFloat,
        dy: CGFloat,
        initial: NSRect,
        frame: inout NSRect
    ) {
        let minW = window?.minSize.width ?? CiderPanelDesign.panelMinWidth
        let minH = window?.minSize.height ?? CiderPanelDesign.panelMinHeight

        switch zone {
        case .none:
            break

        case .right:
            frame.size.width = max(minW, initial.width + dx)

        case .left:
            let newW = max(minW, initial.width - dx)
            frame.origin.x = initial.maxX - newW
            frame.size.width = newW

        case .bottom:
            // NSScreen: bottom is low Y. Dragging down = negative dy
            let newH = max(minH, initial.height - dy)
            frame.origin.y = initial.maxY - newH
            frame.size.height = newH

        case .top:
            frame.size.height = max(minH, initial.height + dy)

        case .bottomRight:
            frame.size.width = max(minW, initial.width + dx)
            let newH = max(minH, initial.height - dy)
            frame.origin.y = initial.maxY - newH
            frame.size.height = newH

        case .bottomLeft:
            let newW = max(minW, initial.width - dx)
            frame.origin.x = initial.maxX - newW
            frame.size.width = newW
            let newH = max(minH, initial.height - dy)
            frame.origin.y = initial.maxY - newH
            frame.size.height = newH

        case .topRight:
            frame.size.width = max(minW, initial.width + dx)
            frame.size.height = max(minH, initial.height + dy)

        case .topLeft:
            let newW = max(minW, initial.width - dx)
            frame.origin.x = initial.maxX - newW
            frame.size.width = newW
            frame.size.height = max(minH, initial.height + dy)
        }
    }
}
