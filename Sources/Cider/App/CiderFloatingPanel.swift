import AppKit
import SwiftUI
import WebKit

final class CiderFloatingPanel: NSPanel {
    let surface: CiderFloatableSurface

    private var dragStartOrigin: NSPoint?
    private var dragStartMouse: NSPoint?
    private var isDragging = false

    init(
        surface: CiderFloatableSurface,
        contentSize: NSSize = NSSize(width: 420, height: 520)
    ) {
        self.surface = surface

        let rect = NSRect(origin: .zero, size: contentSize)
        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        title = surface.defaultTitle
        identifier = NSUserInterfaceItemIdentifier(surface.stableKey)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        hasShadow = true
        isMovable = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        minSize = NSSize(width: 320, height: 280)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

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

    func showNearMouse() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var frame = frame

        frame.origin = NSPoint(
            x: mouse.x + 18,
            y: mouse.y - frame.height - 18
        )

        if frame.maxX > visibleFrame.maxX {
            frame.origin.x = visibleFrame.maxX - frame.width - 16
        }
        if frame.minX < visibleFrame.minX {
            frame.origin.x = visibleFrame.minX + 16
        }
        if frame.minY < visibleFrame.minY {
            frame.origin.y = visibleFrame.minY + 16
        }
        if frame.maxY > visibleFrame.maxY {
            frame.origin.y = visibleFrame.maxY - frame.height - 16
        }

        setFrame(frame, display: true)
        orderFrontRegardless()
    }

    private func isInDraggableArea(_ locationInWindow: NSPoint) -> Bool {
        guard let contentView else { return false }

        if isInResizeEdgeBand(locationInWindow, bounds: contentView.bounds) {
            return false
        }

        if let hitView = contentView.hitTest(locationInWindow) {
            var view: NSView? = hitView
            while let v = view, v !== contentView {
                if v is NSControl { return false }
                if v is NSTextView { return false }
                if v is WKWebView { return false }
                if v is PanelEdgeResizeNSView { return false }
                view = v.superview
            }
        }

        let topDragHeight = CiderPanelDesign.titleBarHeight + Spacing.md
        return locationInWindow.y >= contentView.bounds.height - topDragHeight
    }

    private func isInResizeEdgeBand(_ locationInWindow: NSPoint, bounds: NSRect) -> Bool {
        let edgeInset = CiderPanelDesign.resizeEdgeThickness

        return locationInWindow.x < edgeInset
            || locationInWindow.x > bounds.width - edgeInset
            || locationInWindow.y < edgeInset
            || locationInWindow.y > bounds.height - edgeInset
    }
}
