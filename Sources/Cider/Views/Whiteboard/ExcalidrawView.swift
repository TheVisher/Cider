import SwiftUI
import WebKit

/// Thin NSViewRepresentable that borrows the singleton Excalidraw WKWebView
/// from `WhiteboardViewModel`. Mirrors the TipTapEditorView pattern exactly.
struct ExcalidrawView: NSViewRepresentable {
    @ObservedObject var viewModel: WhiteboardViewModel

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let webView = viewModel.ensureWebView()
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let webView = viewModel.ensureWebView()
        if webView.superview == nil {
            webView.frame = container.bounds
            webView.autoresizingMask = [.width, .height]
            container.addSubview(webView)
        }
    }
}
