import AppKit
import SwiftUI

final class DetailPopoverPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
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

    func showAdjacent(to parentPanel: NSPanel, preferredWidth: CGFloat, content: some View) {
        let hostingView = NSHostingView(rootView: content)
        self.contentView = hostingView

        let parentFrame = parentPanel.frame
        let screen = parentPanel.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? parentFrame
        let minimumWidth: CGFloat = 480
        let minimumHeight: CGFloat = 420
        let desiredWidth = max(preferredWidth, minimumWidth)
        let maxAllowedWidth = max(minimumWidth, visibleFrame.width - CiderPanelDesign.shadowPadding * 2)
        let popoverWidth = min(desiredWidth, maxAllowedWidth)
        let maxAllowedHeight = max(minimumHeight, visibleFrame.height - CiderPanelDesign.shadowPadding * 2)
        hostingView.frame = NSRect(x: 0, y: 0, width: popoverWidth, height: maxAllowedHeight)
        hostingView.layoutSubtreeIfNeeded()
        let desiredHeight = max(hostingView.fittingSize.height, minimumHeight)
        let popoverHeight = min(desiredHeight, maxAllowedHeight)
        let padding = CiderPanelDesign.shadowPadding

        // Try to position to the right of the parent panel
        let rightX = parentFrame.maxX - padding
        let leftX = parentFrame.minX - popoverWidth + padding

        let visibleMinX = visibleFrame.minX
        let visibleMaxX = visibleFrame.maxX

        let x: CGFloat
        if rightX + popoverWidth <= visibleMaxX {
            x = rightX
        } else {
            x = min(max(leftX, visibleMinX), visibleMaxX - popoverWidth)
        }

        let preferredY = parentFrame.maxY - popoverHeight
        let y = min(
            max(preferredY, visibleFrame.minY),
            visibleFrame.maxY - popoverHeight
        )

        let frame = NSRect(
            x: x,
            y: y,
            width: popoverWidth,
            height: popoverHeight
        )

        setFrame(frame, display: true)
        orderFront(nil)
    }
}
