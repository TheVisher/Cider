import SwiftUI
import AppKit

struct PanelEdgeResizeView: NSViewRepresentable {
    var horizontalResizeEnabled: Bool = true
    var minWidth: CGFloat = CiderPanelDesign.panelMinWidth
    var minHeight: CGFloat = CiderPanelDesign.panelMinHeight
    var shadowPadding: CGFloat = CiderPanelDesign.shadowPadding
    var topPadding: CGFloat = CiderPanelDesign.topPadding
    var bottomPadding: CGFloat = CiderPanelDesign.shadowPadding + CiderPanelDesign.bottomPadding
    var resizeCornerSize: CGFloat = CiderPanelDesign.resizeCornerSize
    var resizeEdgeThickness: CGFloat = CiderPanelDesign.resizeEdgeThickness

    func makeNSView(context: Context) -> PanelEdgeResizeNSView {
        let view = PanelEdgeResizeNSView()
        view.horizontalResizeEnabled = horizontalResizeEnabled
        applyConfig(to: view)
        return view
    }

    func updateNSView(_ nsView: PanelEdgeResizeNSView, context: Context) {
        nsView.horizontalResizeEnabled = horizontalResizeEnabled
        applyConfig(to: nsView)
    }

    private func applyConfig(to view: PanelEdgeResizeNSView) {
        view.minW = minWidth
        view.minH = minHeight
        view.hPad = shadowPadding
        view.topPad = topPadding
        view.bottomPad = bottomPadding
        view.cornerSize = resizeCornerSize
        view.edgeInset = resizeEdgeThickness
    }
}

final class PanelEdgeResizeNSView: NSView {
    var horizontalResizeEnabled: Bool = true
    var minW: CGFloat = CiderPanelDesign.panelMinWidth
    var minH: CGFloat = CiderPanelDesign.panelMinHeight
    var hPad: CGFloat = CiderPanelDesign.shadowPadding
    var topPad: CGFloat = CiderPanelDesign.topPadding
    var bottomPad: CGFloat = CiderPanelDesign.shadowPadding + CiderPanelDesign.bottomPadding
    var cornerSize: CGFloat = CiderPanelDesign.resizeCornerSize
    var edgeInset: CGFloat = CiderPanelDesign.resizeEdgeThickness
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

        let maxW = window.maxSize.width

        var keepRunning = true
        while keepRunning {
            guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }

            switch next.type {
            case .leftMouseDragged:
                let mouse = NSEvent.mouseLocation
                let dx = mouse.x - initialMouse.x
                let dy = mouse.y - initialMouse.y

                var newFrame = initialFrame
                applyResize(zone: zone, dx: dx, dy: dy, initial: initialFrame, frame: &newFrame,
                            minW: minW, minH: minH, maxW: maxW)

                if newFrame != window.frame {
                    window.setFrame(newFrame, display: true)
                }

            case .leftMouseUp:
                keepRunning = false

            default:
                break
            }
        }
    }

    // MARK: - Zone Resolution

    private func resolveZone(at point: NSPoint) -> ResizeZone {
        let rawZone = resolveRawZone(at: point)

        // Suppress horizontal resize zones when horizontal resize is disabled
        if !horizontalResizeEnabled {
            switch rawZone {
            case .left, .right: return .none
            case .topLeft, .topRight: return .top
            case .bottomLeft, .bottomRight: return .bottom
            default: return rawZone
            }
        }

        return rawZone
    }

    private func resolveRawZone(at point: NSPoint) -> ResizeZone {
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
        frame: inout NSRect,
        minW: CGFloat,
        minH: CGFloat,
        maxW: CGFloat
    ) {

        // Helper: resize width from the right edge (origin stays fixed)
        func resizeRight() {
            frame.size.width = min(maxW, max(minW, initial.width + dx))
        }

        // Helper: resize width from the left edge (right edge stays fixed)
        func resizeLeft() {
            let newW = min(maxW, max(minW, initial.width - dx))
            // Only move origin by exactly how much the width changed
            frame.origin.x = initial.origin.x + (initial.width - newW)
            frame.size.width = newW
        }

        // Helper: resize height from the top edge (bottom stays fixed)
        func resizeTop() {
            frame.size.height = max(minH, initial.height + dy)
        }

        // Helper: resize height from the bottom edge (top edge stays fixed)
        func resizeBottom() {
            let newH = max(minH, initial.height - dy)
            // Only move origin by exactly how much the height changed
            frame.origin.y = initial.origin.y - (newH - initial.height)
            frame.size.height = newH
        }

        switch zone {
        case .none:       break
        case .right:      resizeRight()
        case .left:       resizeLeft()
        case .top:        resizeTop()
        case .bottom:     resizeBottom()
        case .topRight:   resizeRight(); resizeTop()
        case .topLeft:    resizeLeft(); resizeTop()
        case .bottomRight: resizeRight(); resizeBottom()
        case .bottomLeft: resizeLeft(); resizeBottom()
        }
    }
}
