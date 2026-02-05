import AppKit
import SwiftUI

final class WindowCyclingPanel: NSPanel {
    init() {
        let initialFrame = NSRect(x: 0, y: 0, width: 600, height: 120)

        super.init(contentRect: initialFrame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false  // We draw our own shadow

        isMovable = false
        acceptsMouseMovedEvents = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func centerOnScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen else { return }

        let screenFrame = screen.visibleFrame
        let panelSize = frame.size

        let x = screenFrame.midX - panelSize.width / 2
        let y = screenFrame.midY - panelSize.height / 2

        setFrameOrigin(NSPoint(x: x, y: y))
    }

    func showCentered() {
        centerOnScreen()
        orderFrontRegardless()
    }
}

// MARK: - Hosting View

final class WindowCyclingHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}
