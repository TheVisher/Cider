import AppKit
import SwiftUI
import QuartzCore

final class CiderPanel: NSPanel {
    private(set) var isCollapsed = false
    var isMaximized = false
    private var expandedFrameBeforeCollapse: NSRect?
    var frameBeforeMaximize: NSRect?
    private var lastCollapseToggleDate: Date = .distantPast

    // Window dragging state
    private var dragStartOrigin: NSPoint?
    private var dragStartMouse: NSPoint?
    private var isDragging = false

    init() {
        let initialFrame = NSRect(
            x: 0,
            y: 0,
            width: CiderPanelDesign.panelContentWidth,
            height: CiderPanelDesign.panelContentHeight
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

        isMovableByWindowBackground = true
        isReleasedWhenClosed = false

        self.minSize = NSSize(
            width: CiderPanelDesign.panelMinWidth,
            height: CiderPanelDesign.panelMinHeight
        )
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Window Dragging via Title Bar

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

        // Allow dragging from anywhere within the visible content area
        let hPad = CiderPanelDesign.shadowPadding
        let topPad = CiderPanelDesign.topPadding
        let bottomPad = CiderPanelDesign.shadowPadding + CiderPanelDesign.bottomPadding

        guard locationInWindow.x >= hPad && locationInWindow.x <= bounds.width - hPad else {
            return false
        }
        guard locationInWindow.y >= bottomPad && locationInWindow.y <= bounds.height - topPad else {
            return false
        }

        // Check if the hit view is an interactive control or our resize view
        if let hitView = contentView.hitTest(locationInWindow) {
            var view: NSView? = hitView
            while let v = view, v !== contentView {
                if v is NSControl { return false }
                if v is PanelEdgeResizeNSView { return false }
                view = v.superview
            }
        }

        return true
    }

    var persistableFrame: NSRect {
        guard isCollapsed else { return frame }

        var expanded = expandedFrameBeforeCollapse ?? frame
        expanded.origin.x = frame.minX
        expanded.origin.y = frame.maxY - expanded.height
        return expanded
    }

    func show(frame preferredFrame: NSRect) {
        guard let screen = preferredScreen(for: preferredFrame) else { return }
        let clamped = clampedFrame(for: preferredFrame, in: screen)
        setFrame(clamped, display: true)
        expandedFrameBeforeCollapse = clamped
        isCollapsed = false
        makeKeyAndOrderFront(nil)
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

    func setCollapsed(_ collapsed: Bool, animated: Bool = true) {
        guard collapsed != isCollapsed else { return }
        let now = Date()
        let isRapidToggle = now.timeIntervalSince(lastCollapseToggleDate) < CiderPanelDesign.collapseToggleAnimationDuration
        let shouldAnimate = animated && !isRapidToggle
        lastCollapseToggleDate = now

        if collapsed {
            if !isRapidToggle || expandedFrameBeforeCollapse == nil {
                expandedFrameBeforeCollapse = frame
            }

            let collapsedHeight = CiderPanelDesign.panelCollapsedHeight
            let target = NSRect(
                x: frame.minX,
                y: frame.maxY - collapsedHeight,
                width: frame.width,
                height: collapsedHeight
            )
            guard let screen = preferredScreen(for: target) else { return }
            let clamped = clampedFrame(
                for: target,
                in: screen,
                minimumHeight: CiderPanelDesign.panelCollapsedHeight
            )
            applyFrame(clamped, animated: shouldAnimate)
            isCollapsed = true
            return
        }

        let currentTopY = frame.maxY
        var expanded = expandedFrameBeforeCollapse
            ?? NSRect(
                x: frame.minX,
                y: frame.minY,
                width: frame.width,
                height: CiderPanelDesign.panelContentHeight
            )
        expanded.origin.x = frame.minX
        expanded.origin.y = currentTopY - expanded.height

        guard let screen = preferredScreen(for: expanded) else { return }
        let clamped = clampedFrame(for: expanded, in: screen)
        applyFrame(clamped, animated: shouldAnimate)
        expandedFrameBeforeCollapse = clamped
        isCollapsed = false
    }

    func toggleCollapsed(animated: Bool = true) {
        setCollapsed(!isCollapsed, animated: animated)
    }

    private func preferredScreen(for preferredFrame: NSRect) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        if let containing = screens.first(where: { $0.visibleFrame.contains(preferredFrame.origin) }) {
            return containing
        }

        let targetCenter = preferredFrame.center
        return screens.min {
            $0.visibleFrame.distanceSquared(to: targetCenter)
                < $1.visibleFrame.distanceSquared(to: targetCenter)
        } ?? NSScreen.main
    }

    private func clampedFrame(
        for preferredFrame: NSRect,
        in screen: NSScreen,
        minimumHeight: CGFloat = CiderPanelDesign.panelMinHeight
    ) -> NSRect {
        let visibleFrame = screen.visibleFrame
        let width = max(CiderPanelDesign.panelMinWidth, min(preferredFrame.width, visibleFrame.width))
        let height = max(minimumHeight, min(preferredFrame.height, visibleFrame.height))
        let x = max(visibleFrame.minX, min(preferredFrame.minX, visibleFrame.maxX - width))
        let y = max(visibleFrame.minY, min(preferredFrame.minY, visibleFrame.maxY - height))
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func applyFrame(_ frame: NSRect, animated: Bool) {
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            setFrame(frame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = CiderPanelDesign.collapseToggleAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(frame, display: true)
        }
    }
}

private extension NSRect {
    var center: NSPoint {
        NSPoint(x: midX, y: midY)
    }

    func distanceSquared(to point: NSPoint) -> CGFloat {
        let dx = center.x - point.x
        let dy = center.y - point.y
        return dx * dx + dy * dy
    }
}

final class CiderPanelHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Prevent NSHostingView from influencing window sizing at all.
        // Our borderless panel manages its own min/max via the resize handle.
        // .intrinsicContentSize was causing Auto Layout compression resistance
        // that prevented the window from shrinking past the content's ideal width,
        // blocking the compact-mode sidebar auto-hide on content-heavy tabs.
        sizingOptions = []
        setContentCompressionResistancePriority(.fittingSizeCompression, for: .horizontal)
        setContentCompressionResistancePriority(.fittingSizeCompression, for: .vertical)
    }
}
