import AppKit
import SwiftUI

final class CiderFloatingPanel: NSPanel {
    let surface: CiderFloatableSurface

    init(
        surface: CiderFloatableSurface,
        contentSize: NSSize = NSSize(width: 420, height: 520)
    ) {
        self.surface = surface

        let rect = NSRect(origin: .zero, size: contentSize)
        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        title = surface.defaultTitle
        identifier = NSUserInterfaceItemIdentifier(surface.stableKey)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        hasShadow = true
        isMovable = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        minSize = NSSize(width: 320, height: 280)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func showNearMouse() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var frame = frame

        frame.origin = NSPoint(
            x: mouse.x + 18,
            y: mouse.y - frame.height - 18
        )

        if frame.maxX > visibleFrame.maxX {
            frame.origin.x = visibleFrame.maxX - frame.width - 16
        }
        if frame.minX < visibleFrame.minX {
            frame.origin.x = visibleFrame.minX + 16
        }
        if frame.minY < visibleFrame.minY {
            frame.origin.y = visibleFrame.minY + 16
        }
        if frame.maxY > visibleFrame.maxY {
            frame.origin.y = visibleFrame.maxY - frame.height - 16
        }

        setFrame(frame, display: true)
        orderFrontRegardless()
    }
}
