import AppKit

enum CiderMainWindowPlacement {
    static let screenPadding: CGFloat = 16

    static func restoredFrame(
        _ savedFrame: NSRect,
        savedScreenVisibleFrame: NSRect,
        targetVisibleFrame: NSRect,
        minimumSize: NSSize
    ) -> NSRect {
        guard savedScreenVisibleFrame.width > 0, savedScreenVisibleFrame.height > 0 else {
            return clampedFrame(savedFrame, in: targetVisibleFrame, minimumSize: minimumSize)
        }

        let size = clampedSize(savedFrame.size, in: targetVisibleFrame, minimumSize: minimumSize)
        let xRatio = (savedFrame.minX - savedScreenVisibleFrame.minX) / savedScreenVisibleFrame.width
        let topRatio = (savedScreenVisibleFrame.maxY - savedFrame.maxY) / savedScreenVisibleFrame.height
        let x = targetVisibleFrame.minX + targetVisibleFrame.width * xRatio
        let y = targetVisibleFrame.maxY - targetVisibleFrame.height * topRatio - size.height

        return clampedFrame(
            NSRect(x: x, y: y, width: size.width, height: size.height),
            in: targetVisibleFrame,
            minimumSize: minimumSize
        )
    }

    static func clampedFrame(
        _ frame: NSRect,
        in visibleFrame: NSRect,
        minimumSize: NSSize
    ) -> NSRect {
        var clamped = frame
        clamped.size = clampedSize(frame.size, in: visibleFrame, minimumSize: minimumSize)

        let minX = visibleFrame.minX + screenPadding
        let minY = visibleFrame.minY + screenPadding
        let maxX = visibleFrame.maxX - clamped.width - screenPadding
        let maxY = visibleFrame.maxY - clamped.height - screenPadding

        clamped.origin.x = max(minX, min(clamped.minX, maxX))
        clamped.origin.y = max(minY, min(clamped.minY, maxY))
        return clamped
    }

    private static func clampedSize(
        _ size: NSSize,
        in visibleFrame: NSRect,
        minimumSize: NSSize
    ) -> NSSize {
        let availableWidth = max(1, visibleFrame.width - screenPadding * 2)
        let availableHeight = max(1, visibleFrame.height - screenPadding * 2)
        return NSSize(
            width: min(max(minimumSize.width, size.width), availableWidth),
            height: min(max(minimumSize.height, size.height), availableHeight)
        )
    }
}
