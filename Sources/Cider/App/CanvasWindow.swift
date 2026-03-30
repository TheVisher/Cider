import AppKit
import SwiftUI

/// Standard NSWindow for the canvas workspace.
/// Unlike the NSPanel, this is a regular app window — it appears in the Dock
/// and Window menu, can become main/key, and supports full screen.
final class CanvasWindow: NSWindow {
    init() {
        let initialFrame = NSRect(x: 0, y: 0, width: 1200, height: 800)

        super.init(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        title = "Cider Canvas"
        isReleasedWhenClosed = false
        minSize = NSSize(width: 600, height: 400)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden

        // Dark vibrancy for the title bar area
        if let contentView {
            let visualEffect = NSVisualEffectView()
            visualEffect.material = .underWindowBackground
            visualEffect.state = .active
            visualEffect.blendingMode = .behindWindow
            visualEffect.frame = contentView.bounds
            visualEffect.autoresizingMask = [.width, .height]
            contentView.addSubview(visualEffect, positioned: .below, relativeTo: nil)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func showCentered() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen else { return }

        let screenFrame = screen.visibleFrame
        let windowSize = frame.size

        let x = screenFrame.midX - windowSize.width / 2
        let y = screenFrame.midY - windowSize.height / 2

        setFrameOrigin(NSPoint(x: x, y: y))
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
