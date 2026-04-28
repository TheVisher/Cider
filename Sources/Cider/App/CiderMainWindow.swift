import AppKit
import SwiftUI
import WebKit

final class CiderMainWindow: NSWindow {
    /// Updated by CiderPanelShell when sidebar visibility changes.
    var isSidebarCurrentlyVisible = true

    private var dragStartOrigin: NSPoint?
    private var dragStartMouse: NSPoint?
    private var isDragging = false

    init() {
        let initialFrame = NSRect(x: 0, y: 0, width: 1180, height: 760)

        super.init(
            contentRect: initialFrame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        title = "Cider"
        isReleasedWhenClosed = false
        minSize = NSSize(width: 920, height: 560)
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
    }

    func showCentered() {
        if frame.origin == .zero {
            center()
        }
        if isMiniaturized {
            deminiaturize(nil)
        }
        makeKeyAndOrderFront(nil)
    }

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
        guard let contentView else { return false }
        let bounds = contentView.bounds

        if isInResizeEdgeBand(locationInWindow, bounds: bounds) {
            return false
        }

        if let hitView = contentView.hitTest(locationInWindow) {
            var view: NSView? = hitView
            while let v = view, v !== contentView {
                if v is NSControl { return false }
                if v is WKWebView { return false }
                if v is PanelEdgeResizeNSView { return false }
                view = v.superview
            }
        }

        let titleBarMinY = bounds.height - CiderPanelDesign.titleBarHeight - (Spacing.sm - 1)
        if locationInWindow.y >= titleBarMinY {
            return true
        }

        if isSidebarCurrentlyVisible {
            let sidebarMaxX = BookmarksDesign.folderSidebarWidth + Spacing.md * 2 + Spacing.sm
            if locationInWindow.x <= sidebarMaxX {
                return true
            }
        }

        return false
    }

    private func isInResizeEdgeBand(_ locationInWindow: NSPoint, bounds: NSRect) -> Bool {
        let hPad = CiderPanelDesign.shadowPadding
        let topPad = CiderPanelDesign.topPadding
        let bottomPad = CiderPanelDesign.shadowPadding + CiderPanelDesign.bottomPadding
        let edgeInset = CiderPanelDesign.resizeEdgeThickness

        let contentMinX = hPad
        let contentMaxX = bounds.width - hPad
        let contentMinY = bottomPad
        let contentMaxY = bounds.height - topPad

        return locationInWindow.x < contentMinX + edgeInset
            || locationInWindow.x > contentMaxX - edgeInset
            || locationInWindow.y < contentMinY + edgeInset
            || locationInWindow.y > contentMaxY - edgeInset
    }
}

final class CiderMainWindowHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
