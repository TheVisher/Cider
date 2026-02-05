import SwiftUI
import AppKit

struct MouseTrackingView: NSViewRepresentable {
    var onMove: (CGPoint) -> Void
    var onEnter: () -> Void
    var onExit: () -> Void

    func makeNSView(context: Context) -> TrackingNSView {
        let view = TrackingNSView()
        view.onMove = onMove
        view.onEnter = onEnter
        view.onExit = onExit
        return view
    }

    func updateNSView(_ nsView: TrackingNSView, context: Context) {
        nsView.onMove = onMove
        nsView.onEnter = onEnter
        nsView.onExit = onExit
    }
}

final class TrackingNSView: NSView {
    var onMove: ((CGPoint) -> Void)?
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var exitWorkItem: DispatchWorkItem?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        // Ensure first click is not discarded on non-activating panels.
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onMove?(point)
    }

    override func mouseEntered(with event: NSEvent) {
        // Cancel any pending exit to prevent oscillation
        exitWorkItem?.cancel()
        exitWorkItem = nil
        onEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        // Debounce exit by 100ms to prevent spurious exits during tracking area updates
        exitWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.isMouseInsideView() { return }
            self.onExit?()
        }
        exitWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    private func isMouseInsideView() -> Bool {
        guard let window else { return false }
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let localPoint = convert(windowPoint, from: nil)
        return bounds.contains(localPoint)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Return nil to allow SwiftUI views beneath to receive clicks
        // But the panel itself should block events from going to apps behind
        // This is handled by the panel's ignoresMouseEvents = false
        return nil
    }
}
