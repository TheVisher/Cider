import AppKit
import SwiftUI

/// Standard NSWindow for the canvas workspace.
/// Unlike the NSPanel, this is a regular app window — it appears in the Dock
/// and Window menu, can become main/key, and supports full screen.
final class CanvasWindow: NSWindow {
    /// Set by the SwiftUI overlay to enable sidebar-region dragging.
    var isSidebarVisible = true

    // Drag state
    private var dragStartOrigin: NSPoint?
    private var dragStartMouse: NSPoint?
    private var isDragging = false

    init() {
        let initialFrame = NSRect(x: 0, y: 0, width: 1200, height: 800)

        super.init(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        title = "Cider Canvas"
        isReleasedWhenClosed = false
        minSize = NSSize(width: 600, height: 400)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden

        // Remove any toolbar so the titlebar collapses to zero height
        toolbar = nil

        // Hide native traffic lights — custom ones live in the sidebar overlay
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

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

    override func becomeKey() {
        super.becomeKey()
        // Re-hide in case the system restored them during window lifecycle
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    // MARK: - Custom Window Dragging

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            if isInDraggableArea(event.locationInWindow) {
                dragStartOrigin = frame.origin
                dragStartMouse = NSEvent.mouseLocation
                isDragging = false
            }
            super.sendEvent(event)

        case .leftMouseDragged:
            if let startOrigin = dragStartOrigin,
               let startMouse = dragStartMouse {
                let currentMouse = NSEvent.mouseLocation
                let dx = currentMouse.x - startMouse.x
                let dy = currentMouse.y - startMouse.y

                if !isDragging && (abs(dx) > 3 || abs(dy) > 3) {
                    isDragging = true
                }

                if isDragging {
                    setFrameOrigin(NSPoint(
                        x: startOrigin.x + dx,
                        y: startOrigin.y + dy
                    ))
                    return
                }
            }
            super.sendEvent(event)

        case .leftMouseUp:
            dragStartOrigin = nil
            dragStartMouse = nil
            isDragging = false
            super.sendEvent(event)

        default:
            super.sendEvent(event)
        }
    }

    private func isInDraggableArea(_ locationInWindow: NSPoint) -> Bool {
        guard let contentView else { return false }
        let bounds = contentView.bounds

        // Skip if clicking on an interactive control
        if let hitView = contentView.hitTest(locationInWindow) {
            var view: NSView? = hitView
            while let v = view, v !== contentView {
                if v is NSControl { return false }
                view = v.superview
            }
        }

        // Top strip: thin titlebar area (top 40pt)
        let titleBarMinY = bounds.height - CiderPanelDesign.titleBarHeight
        if locationInWindow.y >= titleBarMinY {
            return true
        }

        // Sidebar region when visible
        // sidebar width (224pt) + leading padding (12pt) + container insets
        if isSidebarVisible {
            let sidebarMaxX = BookmarksDesign.folderSidebarWidth + Spacing.md * 2 + Spacing.sm
            if locationInWindow.x <= sidebarMaxX {
                return true
            }
        }

        // Collapsed pill region: top-left corner
        if !isSidebarVisible {
            let pillHeight: CGFloat = 36
            let pillWidth: CGFloat = 260
            let topY = bounds.height - Spacing.md - pillHeight
            if locationInWindow.y >= topY && locationInWindow.x <= Spacing.md + pillWidth {
                return true
            }
        }

        return false
    }

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
