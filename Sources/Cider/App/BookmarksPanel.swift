import AppKit
import SwiftUI
import QuartzCore

final class BookmarksPanel: NSPanel {
    private(set) var isCollapsed = false
    private var expandedFrameBeforeCollapse: NSRect?
    private var lastCollapseToggleDate: Date = .distantPast

    init() {
        let initialFrame = NSRect(
            x: 0,
            y: 0,
            width: BookmarksDesign.panelContentWidth,
            height: BookmarksDesign.panelContentHeight
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
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

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
        let isRapidToggle = now.timeIntervalSince(lastCollapseToggleDate) < BookmarksDesign.collapseToggleAnimationDuration
        let shouldAnimate = animated && !isRapidToggle
        lastCollapseToggleDate = now

        if collapsed {
            if !isRapidToggle || expandedFrameBeforeCollapse == nil {
                expandedFrameBeforeCollapse = frame
            }

            let collapsedHeight = BookmarksDesign.panelCollapsedHeight
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
                minimumHeight: BookmarksDesign.panelCollapsedHeight
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
                height: BookmarksDesign.panelContentHeight
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

        return screens.min { lhs, rhs in
            lhs.visibleFrame.distanceSquared(to: preferredFrame.center)
                < rhs.visibleFrame.distanceSquared(to: preferredFrame.center)
        } ?? NSScreen.main
    }

    private func clampedFrame(
        for preferredFrame: NSRect,
        in screen: NSScreen,
        minimumHeight: CGFloat = BookmarksDesign.panelMinHeight
    ) -> NSRect {
        let visibleFrame = screen.visibleFrame
        let width = max(BookmarksDesign.panelMinWidth, min(preferredFrame.width, visibleFrame.width))
        let height = max(minimumHeight, min(preferredFrame.height, visibleFrame.height))
        let x = max(visibleFrame.minX, min(preferredFrame.minX, visibleFrame.maxX - width))
        let y = max(visibleFrame.minY, min(preferredFrame.minY, visibleFrame.maxY - height))
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func applyFrame(_ frame: NSRect, animated: Bool) {
        guard animated else {
            setFrame(frame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = BookmarksDesign.collapseToggleAnimationDuration
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

final class BookmarksPanelHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
