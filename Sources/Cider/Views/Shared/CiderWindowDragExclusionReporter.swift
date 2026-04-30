import AppKit
import SwiftUI

struct CiderWindowDragExclusionReporter: NSViewRepresentable {
    let id: String

    func makeNSView(context: Context) -> CiderWindowDragExclusionNSView {
        let view = CiderWindowDragExclusionNSView()
        view.exclusionID = id
        return view
    }

    func updateNSView(_ nsView: CiderWindowDragExclusionNSView, context: Context) {
        nsView.exclusionID = id
        nsView.updateWindowRegistration()
    }
}

final class CiderWindowDragExclusionNSView: NSView {
    var exclusionID = "" {
        didSet {
            guard exclusionID != oldValue else { return }
            registeredWindow?.removeDragExclusionRect(for: oldValue)
            registeredID = nil
            updateWindowRegistration()
        }
    }

    private weak var registeredWindow: CiderMainWindow?
    private var registeredID: String?

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateWindowRegistration()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window {
            unregister()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        updateWindowRegistration()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateWindowRegistration()
    }

    override func layout() {
        super.layout()
        updateWindowRegistration()
    }

    func updateWindowRegistration() {
        guard !exclusionID.isEmpty else { return }

        guard let ciderWindow = window as? CiderMainWindow,
              !bounds.isEmpty else {
            unregister()
            return
        }

        let rectInWindow = convert(bounds, to: nil)
        if registeredWindow !== ciderWindow || registeredID != exclusionID {
            unregister()
        }

        ciderWindow.setDragExclusionRect(rectInWindow, for: exclusionID)
        registeredWindow = ciderWindow
        registeredID = exclusionID
    }

    private func unregister() {
        if let registeredID {
            registeredWindow?.removeDragExclusionRect(for: registeredID)
        }
        registeredWindow = nil
        registeredID = nil
    }
}
