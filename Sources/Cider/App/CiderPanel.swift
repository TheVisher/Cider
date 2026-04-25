import AppKit
import SwiftUI
import QuartzCore
import WebKit

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

    /// Updated by CiderPanelShell when sidebar visibility changes.
    var isSidebarCurrentlyVisible = true

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

        isMovableByWindowBackground = false
        isReleasedWhenClosed = false

        self.minSize = NSSize(
            width: CiderPanelDesign.panelMinWidth,
            height: CiderPanelDesign.panelMinHeight
        )

        // Ensure the content view is layer-backed so the window server can
        // compute the shadow shape from the composited rounded content.
        contentView?.wantsLayer = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Non-activating borderless panels have no main menu, so standard Edit
    // key equivalents (Cmd+C/V/X/A/Z) never fire. Intercept them here and
    // route to the first responder manually.
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

    // Allow the panel to be dragged freely across all monitors (don't constrain
    // position to visibleFrame like the default implementation does), but still
    // enforce minimum width so the panel can't be shrunk to nothing.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        var rect = frameRect
        rect.size.width = max(CiderPanelDesign.panelMinWidth, rect.size.width)
        rect.size.height = max(CiderPanelDesign.panelMinHeight, rect.size.height)
        return rect
    }

    // Enforce minimum width for ALL setFrame calls (including those from the custom
    // edge-resize view, which calls setFrame directly and bypasses constrainFrameRect).
    // Height is intentionally not clamped here — collapse sets a much smaller height.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var r = frameRect
        r.size.width = max(CiderPanelDesign.panelMinWidth, r.size.width)
        super.setFrame(r, display: flag)
    }

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

        if isInResizeEdgeBand(locationInWindow, bounds: bounds) {
            return false
        }

        // Check if the hit view is an interactive control or our resize view
        if let hitView = contentView.hitTest(locationInWindow) {
            var view: NSView? = hitView
            while let v = view, v !== contentView {
                if v is NSControl { return false }
                if v is WKWebView { return false }
                if v is PanelEdgeResizeNSView { return false }
                view = v.superview
            }
        }

        // Title bar region: top strip across full width
        // Right column has Spacing.sm - 1 (7pt) top padding + titleBarHeight (40pt)
        let titleBarMinY = bounds.height - CiderPanelDesign.titleBarHeight - (Spacing.sm - 1)
        if locationInWindow.y >= titleBarMinY {
            return true
        }

        // Sidebar region: left column when visible
        // folderSidebarWidth (224pt) + leading padding (12pt) + vertical padding (12pt) + container insets
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
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.0, 0.0, 0.2, 1.0)
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
