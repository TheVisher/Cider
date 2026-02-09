import AppKit
import SwiftUI

final class NotesPanel: NSPanel {
    init() {
        let initialFrame = NSRect(x: 0, y: 0,
                                  width: NotesDesign.defaultWidth,
                                  height: NotesDesign.defaultHeight)

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
        hasShadow = false  // We draw custom shadow via PaletteBackgroundView

        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Show the panel near the mouse cursor, clamped to screen bounds.
    func showAtMouse() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen else { return }

        let screenFrame = screen.visibleFrame
        let panelSize = frame.size

        // Position: offset slightly from mouse
        var x = mouseLocation.x - panelSize.width / 2
        var y = mouseLocation.y - panelSize.height / 2

        // Clamp to screen bounds
        x = max(screenFrame.minX, min(x, screenFrame.maxX - panelSize.width))
        y = max(screenFrame.minY, min(y, screenFrame.maxY - panelSize.height))

        setFrameOrigin(NSPoint(x: x, y: y))
        makeKeyAndOrderFront(nil)
    }

    /// Toggle between floating (pinned) and normal (unpinned) level.
    func setPinned(_ pinned: Bool) {
        level = pinned ? .floating : .normal
    }
}

// MARK: - Hosting View

final class NotesPanelHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}
