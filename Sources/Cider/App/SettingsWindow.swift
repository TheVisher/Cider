import AppKit
import SwiftUI

final class SettingsWindow: NSPanel {
    init() {
        let initialFrame = NSRect(x: 0, y: 0, width: SettingsDesign.width, height: SettingsDesign.height)

        super.init(contentRect: initialFrame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        // Make it float above normal windows but not aggressively
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true

        // Standard window behavior
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }

        let action: Selector? = switch event.charactersIgnoringModifiers {
        case "x": #selector(NSText.cut(_:))
        case "c": #selector(NSText.copy(_:))
        case "v": #selector(NSText.paste(_:))
        case "a": #selector(NSText.selectAll(_:))
        case "z" where event.modifierFlags.contains(.shift): #selector(UndoManager.redo)
        case "z": #selector(UndoManager.undo)
        default: nil
        }

        if let action, let responder = firstResponder, responder.responds(to: action) {
            responder.doCommand(by: action)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    func centerOnScreen() {
        // Use mouse location to find the screen (same as command palette)
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
    }

    func showCentered() {
        centerOnScreen()
        orderFront(nil)
    }
}

// MARK: - Hosting View

final class SettingsHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}
