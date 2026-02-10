import AppKit

/// A small NSPanel that displays a single tile drag handle.
final class TileHandlePanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 20, height: 20),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The AppKit view drawn inside a TileHandlePanel.
/// Hidden by default — reveals on hover over the panel's area, providing
/// a discoverable drag handle along tile split gaps.
final class TileHandleView: NSView {
    /// Whether this handle can be dragged horizontally (horizontal split).
    var isHorizontal: Bool = false
    /// Whether this handle can be dragged vertically (vertical split).
    var isVertical: Bool = false

    var onDragStart: (() -> Void)?
    var onDrag: ((NSPoint) -> Void)?
    var onDragEnd: (() -> Void)?

    private var isDragging = false
    private var isHovered = false
    private var isRevealed = false
    private var trackingArea: NSTrackingArea?

    // Visual sizes
    private let idleSize: CGFloat = 12
    private let hoverSize: CGFloat = 16
    private let clickRadius: CGFloat = 14

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        alphaValue = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    // MARK: - Hit Testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only accept clicks when revealed and near the circle
        guard isRevealed else { return nil }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let dx = point.x - center.x
        let dy = point.y - center.y
        if dx * dx + dy * dy <= clickRadius * clickRadius {
            return self
        }
        return nil
    }

    // MARK: - Tracking Area

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let size = isHovered || isDragging ? hoverSize : idleSize
        let circleRect = NSRect(
            x: (bounds.width - size) / 2,
            y: (bounds.height - size) / 2,
            width: size,
            height: size
        )
        let path = NSBezierPath(ovalIn: circleRect)

        let fillOpacity: CGFloat
        if isDragging {
            fillOpacity = 0.35
        } else if isHovered {
            fillOpacity = 0.25
        } else {
            fillOpacity = 0.15
        }
        NSColor.white.withAlphaComponent(fillOpacity).setFill()
        path.fill()

        NSColor.white.withAlphaComponent(0.3).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    // MARK: - Mouse Events

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        isRevealed = true
        updateCursor()
        needsDisplay = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            self.animator().alphaValue = 1
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSCursor.arrow.set()
        needsDisplay = true
        if !isDragging {
            isRevealed = false
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                self.animator().alphaValue = 0
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        needsDisplay = true
        onDragStart?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let windowFrame = window?.frame else { return }
        let locationInWindow = event.locationInWindow
        let screenPoint = NSPoint(
            x: windowFrame.origin.x + locationInWindow.x,
            y: windowFrame.origin.y + locationInWindow.y
        )
        onDrag?(screenPoint)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        needsDisplay = true
        onDragEnd?()
        if !isHovered {
            isRevealed = false
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                self.animator().alphaValue = 0
            }
        }
    }

    private func updateCursor() {
        if isHorizontal && isVertical {
            NSCursor.crosshair.set()
        } else if isHorizontal {
            NSCursor.resizeLeftRight.set()
        } else if isVertical {
            NSCursor.resizeUpDown.set()
        }
    }
}
