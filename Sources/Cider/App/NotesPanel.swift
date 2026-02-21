import AppKit
import SwiftUI
import Foundation
import QuartzCore

final class NotesPanel: NSPanel {
    private(set) var isCollapsed = false
    private var expandedFrameBeforeCollapse: NSRect?
    private var lastCollapseToggleDate: Date = .distantPast

    var persistableFrame: NSRect {
        guard isCollapsed else { return frame }

        var expanded = expandedFrameBeforeCollapse ?? frame
        expanded.origin.x = frame.minX
        expanded.origin.y = frame.maxY - expanded.height
        return expanded
    }

    init() {
        let initialFrame = NSRect(x: 0, y: 0,
                                  width: NotesDesign.panelDefaultWidth,
                                  height: NotesDesign.panelDefaultHeight)

        super.init(contentRect: initialFrame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        // Persist across spaces (no .transient)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false  // We draw custom shadow via AcrylicPanelBackground

        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Show the panel using a preferred frame, clamped to visible screen bounds.
    func show(frame preferredFrame: NSRect) {
        guard let screen = preferredScreen(for: preferredFrame) else { return }
        let clamped = clampedFrame(for: preferredFrame, in: screen)
        setFrame(clamped, display: true)
        expandedFrameBeforeCollapse = clamped
        isCollapsed = false
        makeKeyAndOrderFront(nil)
    }

    /// Show the panel at a preferred origin, clamped to the nearest visible screen bounds.
    func show(at preferredOrigin: NSPoint) {
        show(frame: NSRect(origin: preferredOrigin, size: frame.size))
    }

    /// Show the panel near the mouse cursor, clamped to screen bounds.
    func showAtMouse() {
        let mouseLocation = NSEvent.mouseLocation
        let panelSize = frame.size

        // Position: offset slightly from mouse
        let preferredOrigin = NSPoint(
            x: mouseLocation.x - panelSize.width / 2,
            y: mouseLocation.y - panelSize.height / 2
        )
        show(at: preferredOrigin)
    }

    func setCollapsed(_ collapsed: Bool, animated: Bool = true) {
        guard collapsed != isCollapsed else { return }
        let now = Date()
        let isRapidToggle = now.timeIntervalSince(lastCollapseToggleDate) < NotesDesign.collapseToggleAnimationDuration
        let shouldAnimate = animated && !isRapidToggle
        lastCollapseToggleDate = now

        if collapsed {
            if !isRapidToggle || expandedFrameBeforeCollapse == nil {
                expandedFrameBeforeCollapse = frame
            }
            let collapsedHeight = NotesDesign.panelCollapsedHeight
            let target = NSRect(
                x: frame.minX,
                y: frame.maxY - collapsedHeight,
                width: frame.width,
                height: collapsedHeight
            )

            guard let screen = preferredScreen(for: target) else { return }
            let clamped = clampedFrame(for: target, in: screen, minimumHeight: NotesDesign.panelCollapsedHeight)
            applyFrame(clamped, animated: shouldAnimate)
            isCollapsed = true
            return
        }

        let currentTopY = frame.maxY
        var expanded = expandedFrameBeforeCollapse
            ?? NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: NotesDesign.panelDefaultHeight)
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

        // Fast path: origin is clearly inside one visible screen.
        if let containing = screens.first(where: { $0.visibleFrame.contains(preferredFrame.origin) }) {
            return containing
        }

        // Choose the screen with the largest overlap; tie-break by nearest center.
        let targetCenter = preferredFrame.center
        let overlapWinner = screens
            .map { screen in
                (screen: screen, overlapArea: screen.visibleFrame.intersectionArea(with: preferredFrame))
            }
            .max { lhs, rhs in
                if lhs.overlapArea == rhs.overlapArea {
                    return lhs.screen.visibleFrame.distanceSquared(to: targetCenter)
                        > rhs.screen.visibleFrame.distanceSquared(to: targetCenter)
                }
                return lhs.overlapArea < rhs.overlapArea
            }

        if let overlapWinner, overlapWinner.overlapArea > 0 {
            return overlapWinner.screen
        }

        // Fallback: nearest screen center.
        return screens.min {
            $0.visibleFrame.distanceSquared(to: targetCenter)
                < $1.visibleFrame.distanceSquared(to: targetCenter)
        } ?? NSScreen.main
    }

    private func clampedFrame(
        for preferredFrame: NSRect,
        in screen: NSScreen,
        minimumHeight: CGFloat = NotesDesign.panelMinHeight
    ) -> NSRect {
        let screenFrame = screen.visibleFrame
        let clampedWidth = max(NotesDesign.panelMinWidth, min(preferredFrame.size.width, screenFrame.width))
        let clampedHeight = max(minimumHeight, min(preferredFrame.size.height, screenFrame.height))
        let clampedX = max(screenFrame.minX, min(preferredFrame.origin.x, screenFrame.maxX - clampedWidth))
        let clampedY = max(screenFrame.minY, min(preferredFrame.origin.y, screenFrame.maxY - clampedHeight))

        return NSRect(x: clampedX, y: clampedY, width: clampedWidth, height: clampedHeight)
    }

    private func applyFrame(_ frame: NSRect, animated: Bool) {
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            setFrame(frame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = NotesDesign.collapseToggleAnimationDuration
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

    func intersectionArea(with other: NSRect) -> CGFloat {
        let intersection = self.intersection(other)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }
}

// MARK: - Hosting View

final class NotesPanelHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        sizingOptions = [.intrinsicContentSize]
    }
}
