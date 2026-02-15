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

    func showAdjacent(to parentPanel: NSPanel, content: some View) {
        let hostingView = NSHostingView(rootView: content)
        self.contentView = hostingView

        let parentFrame = parentPanel.frame
        let popoverWidth: CGFloat = 600
        let popoverHeight: CGFloat = parentFrame.height
        let padding = CiderPanelDesign.shadowPadding

        // Try to position to the right of the parent panel
        let rightX = parentFrame.maxX - padding
        let leftX = parentFrame.minX - popoverWidth + padding

        let screen = parentPanel.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visibleMaxX = screen?.visibleFrame.maxX ?? .infinity

        let x: CGFloat
        if rightX + popoverWidth <= visibleMaxX {
            x = rightX
        } else {
            x = leftX
        }

        let frame = NSRect(
            x: x,
            y: parentFrame.minY,
            width: popoverWidth,
            height: popoverHeight
        )

        setFrame(frame, display: true)
        orderFront(nil)
    }
}
