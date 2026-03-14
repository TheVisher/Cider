import SwiftUI
import WebKit

struct BookmarkWebView: NSViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    /// When false, all media in the web view is paused (e.g. heroMode switched away from .web).
    var isActive: Bool = true
    var store: DetailWebViewStore

    func makeCoordinator() -> Coordinator { Coordinator(isLoading: $isLoading) }

    func makeNSView(context: Context) -> NSView {
        // Use a wrapper view so the WKWebView can be reattached from the store
        // without SwiftUI dismantling it.
        let wrapper = WebViewWrapper()
        let wv = store.getWebView(for: url, delegate: context.coordinator)
        wrapper.attach(wv)
        return wrapper
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let wrapper = nsView as? WebViewWrapper else { return }
        let wv = store.getWebView(for: url, delegate: context.coordinator)
        wrapper.attach(wv)
        if !isActive {
            wv.evaluateJavaScript(
                "document.querySelectorAll('video,audio').forEach(function(m){try{m.pause();}catch(e){}})"
            )
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        // Don't pause or destroy — the store keeps the WKWebView alive
        // so it can be reattached when the view mode changes.
        guard let wrapper = nsView as? WebViewWrapper else { return }
        wrapper.detach()
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
                openURLSafely(url)
                return .cancel
            }
            return .allow
        }
    }
}

// MARK: - Wrapper NSView

/// A plain NSView container that holds a WKWebView as a subview.
/// This lets us detach/reattach the WKWebView without destroying it
/// when SwiftUI dismantles the NSViewRepresentable.
final class WebViewWrapper: NSView {
    private weak var current: WKWebView?

    func attach(_ wv: WKWebView) {
        guard wv !== current else { return }
        current?.removeFromSuperview()
        wv.removeFromSuperview()
        wv.frame = bounds
        wv.autoresizingMask = [.width, .height]
        addSubview(wv)
        current = wv
    }

    func detach() {
        // Only remove if the WKWebView is still parented to this wrapper.
        // If it's already been reattached to a new wrapper (mode switch),
        // don't pull it out.
        if current?.superview === self {
            current?.removeFromSuperview()
        }
        current = nil
    }
}
