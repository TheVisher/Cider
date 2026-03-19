import AppKit
import SwiftUI

final class AIChatPanel: NSPanel {
    // Window dragging state
    private var dragStartOrigin: NSPoint?
    private var dragStartMouse: NSPoint?
    private var isDragging = false

    init() {
        let initialFrame = NSRect(
            x: 0,
            y: 0,
            width: AIChatPanelDesign.defaultWidth,
            height: AIChatPanelDesign.defaultHeight
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
            width: AIChatPanelDesign.minWidth,
            height: AIChatPanelDesign.minHeight
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

    // MARK: - Window Dragging

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            makeKey()

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

        if let hitView = contentView.hitTest(locationInWindow) {
            var view: NSView? = hitView
            while let v = view, v !== contentView {
                if v is NSControl { return false }
                if v is PanelEdgeResizeNSView { return false }
                view = v.superview
            }
        }

        let headerMinY = contentView.bounds.height - AIChatPanelDesign.draggableHeaderHeight
        return locationInWindow.y >= headerMinY
    }
}
