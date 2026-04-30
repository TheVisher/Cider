import AppKit

enum CiderFloatingPanelPlacement {
    static let screenPadding: CGFloat = 16

    static func mouseScreen(
        mouseLocation: NSPoint = NSEvent.mouseLocation,
        screens: [NSScreen] = NSScreen.screens
    ) -> NSScreen? {
        screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main ?? screens.first
    }

    static func preferredScreen(
        for frame: NSRect,
        screens: [NSScreen] = NSScreen.screens
    ) -> NSScreen? {
        guard !screens.isEmpty else { return nil }
        let center = frame.center

        if let containing = screens.first(where: { NSMouseInRect(center, $0.frame, false) }) {
            return containing
        }

        return screens.min {
            $0.visibleFrame.distanceSquared(to: center)
                < $1.visibleFrame.distanceSquared(to: center)
        } ?? NSScreen.main
    }

    static func frameNearMouse(
        currentFrame: NSRect,
        mouseLocation: NSPoint = NSEvent.mouseLocation,
        screen: NSScreen? = nil
    ) -> NSRect {
        let targetScreen = screen ?? mouseScreen(mouseLocation: mouseLocation)
        let visibleFrame = targetScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? currentFrame
        var frame = currentFrame

        frame.origin = NSPoint(
            x: mouseLocation.x + 18,
            y: mouseLocation.y - frame.height - 18
        )

        return clampedFrame(frame, in: visibleFrame)
    }

    static func translatedFrame(
        _ frame: NSRect,
        from sourceVisibleFrame: NSRect,
        to targetVisibleFrame: NSRect
    ) -> NSRect {
        guard sourceVisibleFrame.width > 0, sourceVisibleFrame.height > 0 else {
            return clampedFrame(frame, in: targetVisibleFrame)
        }

        let xRatio = (frame.minX - sourceVisibleFrame.minX) / sourceVisibleFrame.width
        let topOffset = sourceVisibleFrame.maxY - frame.maxY
        let topRatio = topOffset / sourceVisibleFrame.height

        let x = targetVisibleFrame.minX + targetVisibleFrame.width * xRatio
        let y = targetVisibleFrame.maxY - targetVisibleFrame.height * topRatio - frame.height

        return clampedFrame(
            NSRect(x: x, y: y, width: frame.width, height: frame.height),
            in: targetVisibleFrame
        )
    }

    static func clampedFrame(_ frame: NSRect, in visibleFrame: NSRect) -> NSRect {
        var clamped = frame
        clamped.size.width = min(clamped.width, visibleFrame.width - screenPadding * 2)
        clamped.size.height = min(clamped.height, visibleFrame.height - screenPadding * 2)
        clamped.origin.x = max(visibleFrame.minX + screenPadding, min(clamped.minX, visibleFrame.maxX - clamped.width - screenPadding))
        clamped.origin.y = max(visibleFrame.minY + screenPadding, min(clamped.minY, visibleFrame.maxY - clamped.height - screenPadding))
        return clamped
    }
}

private extension NSRect {
    var center: NSPoint {
        NSPoint(x: midX, y: midY)
    }

    func distanceSquared(to point: NSPoint) -> CGFloat {
        let dx = midX - point.x
        let dy = midY - point.y
        return dx * dx + dy * dy
    }
}
