import SwiftUI
import WebKit

struct BookmarkWebView: NSViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    /// When false, all media in the web view is paused (e.g. heroMode switched away from .web).
    var isActive: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator(isLoading: $isLoading) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.setValue(false, forKey: "drawsBackground")
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        if !isActive {
            wv.evaluateJavaScript(
                "document.querySelectorAll('video,audio').forEach(function(m){try{m.pause();}catch(e){}})"
            )
        }
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        // Fired when the view is removed from the hierarchy (panel close, bookmark change).
        nsView.evaluateJavaScript(
            "document.querySelectorAll('video,audio').forEach(function(m){try{m.pause();}catch(e){}})"
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isLoading: Bool
        init(isLoading: Binding<Bool>) { _isLoading = isLoading }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
            isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError _: Error) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) {
            isLoading = false
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor action: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = action.request.url else { return .cancel }
            if action.navigationType == .linkActivated {
                NSWorkspace.shared.open(url)
                return .cancel
            }
            return .allow
        }
    }
}
