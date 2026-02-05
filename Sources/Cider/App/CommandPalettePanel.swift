import AppKit
import SwiftUI

final class CommandPalettePanel: NSPanel {
    init() {
        // Start with a reasonable size, will be centered later
        let initialFrame = NSRect(x: 0, y: 0, width: 600, height: 500)

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
        acceptsMouseMovedEvents = true

        // Allow the panel to become key so the search field can receive input
        // But use nonactivatingPanel so it doesn't steal focus from other apps
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func centerOnScreen() {
        // Find the screen where the mouse currently is
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen else { return }

        let screenFrame = screen.visibleFrame
        let panelSize = frame.size

        let x = screenFrame.midX - panelSize.width / 2
        let y = screenFrame.midY - panelSize.height / 2 + 100  // Slightly above center

        setFrameOrigin(NSPoint(x: x, y: y))
    }

    func showCentered() {
        centerOnScreen()
        makeKeyAndOrderFront(nil)
    }
}

// MARK: - Hosting View for Command Palette

final class CommandPaletteHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}
