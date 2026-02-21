import AppKit
import SwiftUI

/// An invisible NSView that captures its NSView reference for use as an NSPopover anchor.
/// Place in a `.background {}` modifier on the button you want to anchor a popover to.
struct PopoverAnchorView: NSViewRepresentable {
    let onCapture: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onCapture(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
