import AppKit
import SwiftUI
import os
import WebKit

private let logger = Logger(subsystem: "com.cider.app", category: "CiderUtilityPanel")

final class CiderUtilityPanel: NSPanel {

    // Navigation callback for mouse back/forward buttons
    var onNavigateBack: (() -> Void)?
    var onNavigateForward: (() -> Void)?

    // Window dragging state
    private var dragStartOrigin: NSPoint?
    private var dragStartMouse: NSPoint?
    private var isDragging = false

    // Focus-follows-mouse tracking
    private var mouseTrackingArea: NSTrackingArea?

    init() {
        let initialFrame = NSRect(
            x: 0,
            y: 0,
            width: UtilityPanelDesign.panelContentWidth,
            height: UtilityPanelDesign.panelContentHeight
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
            width: UtilityPanelDesign.panelMinWidth,
            height: UtilityPanelDesign.panelMinHeight
        )

        contentView?.wantsLayer = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Key Equivalents

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }

        let action: Selector? = switch event.charactersIgnoringModifiers {
        case "x": #selector(NSText.cut(_:))
        case "c": #selector(NSText.copy(_:))
        case "v": #selector(NSText.paste(_:))
        case "a": #selector(NSText.selectAll(_:))
        case "z" where event.modifierFlags.contains(.shift): #selector(UndoManager.redo)
        case "z": #selector(UndoManager.undo)
        default: nil
        }

        if let action, let responder = firstResponder, responder.responds(to: action) {
            responder.doCommand(by: action)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Frame Constraints

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        var rect = frameRect
        rect.size.width = max(UtilityPanelDesign.panelMinWidth, rect.size.width)
        rect.size.height = max(UtilityPanelDesign.panelMinHeight, rect.size.height)
        return rect
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var r = frameRect
        r.size.width = max(UtilityPanelDesign.panelMinWidth, r.size.width)
        super.setFrame(r, display: flag)
    }

    // MARK: - Window Dragging via Header Bar

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            // Let resize handles take priority over header bar dragging
            if isInResizeZone(event.locationInWindow) {
                super.sendEvent(event)
                return
            }
            if isInHeaderBar(event.locationInWindow) {
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

        case .otherMouseUp:
            // Mouse button 3 = back, button 4 = forward
            if event.buttonNumber == 3 {
                onNavigateBack?()
                return
            } else if event.buttonNumber == 4 {
                onNavigateForward?()
                return
            }
            super.sendEvent(event)

        default:
            super.sendEvent(event)
        }
    }

    private func isInResizeZone(_ locationInWindow: NSPoint) -> Bool {
        guard let contentView else { return false }
        let hitView = contentView.hitTest(locationInWindow)
        return hitView is PanelEdgeResizeNSView
    }

    private func isInHeaderBar(_ locationInWindow: NSPoint) -> Bool {
        guard let contentView else { return false }
        let bounds = contentView.bounds

        // Check for interactive controls — don't drag when clicking buttons
        if let hitView = contentView.hitTest(locationInWindow) {
            var view: NSView? = hitView
            while let v = view, v !== contentView {
                if v is NSControl { return false }
                view = v.superview
            }
        }

        // Header bar region: top strip
        let headerMinY = bounds.height - UtilityPanelDesign.headerBarHeight
        return locationInWindow.y >= headerMinY
    }

    // MARK: - Focus-Follows-Mouse

    func installMouseTracking() {
        guard let contentView else { return }
        if let existing = mouseTrackingArea {
            contentView.removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: contentView.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        contentView.addTrackingArea(area)
        mouseTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        if !isKeyWindow {
            makeKey()
        }
    }

    override func mouseExited(with event: NSEvent) {
        // Only resign key when no text field is actively editing
        guard isKeyWindow else { return }
        if let responder = firstResponder,
           responder is NSTextView || responder is NSTextField {
            // Active text editing — don't resign
            return
        }
        resignKey()
    }

    // MARK: - Show / Hide

    func show(frame preferredFrame: NSRect) {
        guard let screen = preferredScreen(for: preferredFrame) else { return }
        let clamped = clampedFrame(for: preferredFrame, in: screen)
        setFrame(clamped, display: true)
        orderFront(nil)
    }

    func showAtMouse() {
        let mouseLocation = NSEvent.mouseLocation
        let panelSize = frame.size
        let preferredOrigin = NSPoint(
            x: mouseLocation.x - panelSize.width / 2,
            y: mouseLocation.y - panelSize.height / 2
        )
        show(frame: NSRect(origin: preferredOrigin, size: panelSize))
    }

    // MARK: - Screen Utilities

    private func preferredScreen(for preferredFrame: NSRect) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        if let containing = screens.first(where: { $0.visibleFrame.contains(preferredFrame.origin) }) {
            return containing
        }

        let targetCenter = NSPoint(x: preferredFrame.midX, y: preferredFrame.midY)
        return screens.min {
            distanceSquared(from: $0.visibleFrame, to: targetCenter)
                < distanceSquared(from: $1.visibleFrame, to: targetCenter)
        } ?? NSScreen.main
    }

    private func clampedFrame(for preferredFrame: NSRect, in screen: NSScreen) -> NSRect {
        let visibleFrame = screen.visibleFrame
        let width = max(UtilityPanelDesign.panelMinWidth, min(preferredFrame.width, visibleFrame.width))
        let height = max(UtilityPanelDesign.panelMinHeight, min(preferredFrame.height, visibleFrame.height))
        let x = max(visibleFrame.minX, min(preferredFrame.minX, visibleFrame.maxX - width))
        let y = max(visibleFrame.minY, min(preferredFrame.minY, visibleFrame.maxY - height))
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func distanceSquared(from rect: NSRect, to point: NSPoint) -> CGFloat {
        let cx = rect.midX - point.x
        let cy = rect.midY - point.y
        return cx * cx + cy * cy
    }
}
