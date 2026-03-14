import SwiftUI
import WebKit

/// Displays pre-extracted Readability article content from the DetailWebViewStore cache.
/// Never loads raw page HTML — only receives styled reader HTML, eliminating flash.
struct BookmarkReaderView: NSViewRepresentable {
    let url: URL
    var bookmarkID: UUID?
    var store: DetailWebViewStore

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let wrapper = WebViewWrapper()
        let wv = store.getReaderWebView(for: url, delegate: context.coordinator)
        wrapper.attach(wv)
        // If article is already cached, load it immediately
        if let article = store.cachedArticle {
            loadStyledArticle(article, into: wv, bookmarkID: bookmarkID)
        }
        return wrapper
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let wrapper = nsView as? WebViewWrapper else { return }
        let wv = store.getReaderWebView(for: url, delegate: context.coordinator)
        wrapper.attach(wv)
        // Load article when it becomes available (store.readerReady published change)
        if let article = store.cachedArticle, !context.coordinator.hasLoadedArticle {
            loadStyledArticle(article, into: wv, bookmarkID: bookmarkID)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        guard let wrapper = nsView as? WebViewWrapper else { return }
        wrapper.detach()
    }

    private func loadStyledArticle(_ article: DetailWebViewStore.ReaderArticle, into wv: WKWebView, bookmarkID: UUID?) {
        let css = Self.readerCSS ?? ""
        // Escape title and byline to prevent XSS from malicious page metadata.
        // Content is already sanitized HTML from Readability.js and must render as-is.
        let escapedTitle = Self.htmlEscape(article.title)
        let escapedByline = article.byline.isEmpty ? "" : "<p class='reader-byline'>\(Self.htmlEscape(article.byline))</p>"
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="color-scheme" content="dark">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>\(css)</style>
        </head>
        <body>
            <div class="reader-container">
                <h1 class="reader-title">\(escapedTitle)</h1>
                \(escapedByline)
                <div class="reader-content">\(article.content)</div>
            </div>
        </body>
        </html>
        """
        wv.loadHTMLString(html, baseURL: url)

        // Trigger summary generation if needed
        if let bid = bookmarkID,
           CiderConfig.load().enablePageSummaries,
           BookmarksStorage.shared.bookmarks.first(where: { $0.id == bid })?.aiSummary == nil {
            let plainText = "\(article.title). \(article.content)"
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            Task { @MainActor in
                if let summary = await SummaryService.shared.summarize(articleText: plainText) {
                    BookmarksStorage.shared.applyAISummary(summary, for: bid)
                }
            }
        }
    }

    private static func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#x27;")
    }

    private static let readerCSS: String? = {
        guard let url = Bundle.main.url(
            forResource: "reader", withExtension: "css",
            subdirectory: "ReaderMode"
        ) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    final class Coordinator: NSObject, WKNavigationDelegate {
        var hasLoadedArticle = false

        func webView(_ wv: WKWebView, didFinish _: WKNavigation!) {
            hasLoadedArticle = true
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
