import SwiftUI
import WebKit

/// Thin NSViewRepresentable that borrows the singleton canvas WKWebView
/// from `CanvasViewModel`. Mirrors the ExcalidrawView pattern exactly.
struct CanvasView: NSViewRepresentable {
    @ObservedObject var viewModel: CanvasViewModel

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
        if webView.superview !== container {
            webView.removeFromSuperview()
            webView.frame = container.bounds
            webView.autoresizingMask = [.width, .height]
            container.addSubview(webView)
        }
    }
}
