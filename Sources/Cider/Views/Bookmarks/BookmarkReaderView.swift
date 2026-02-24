import SwiftUI
import WebKit

struct BookmarkReaderView: NSViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    /// When set, article text is forwarded to SummaryService after extraction.
    var bookmarkID: UUID?

    func makeCoordinator() -> Coordinator { Coordinator(isLoading: $isLoading) }

    func makeNSView(context: Context) -> WKWebView {
        let wv = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        wv.navigationDelegate = context.coordinator
        wv.setValue(false, forKey: "drawsBackground")
        context.coordinator.bookmarkID = bookmarkID
        context.coordinator.load(url: url, in: wv)
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        context.coordinator.bookmarkID = bookmarkID
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isLoading: Bool
        var bookmarkID: UUID?

        private enum Phase { case loadingRaw, extracting, displaying, error }
        private var phase: Phase = .loadingRaw
        private weak var webView: WKWebView?
        private var articleURL: URL?

        private static let readabilityJS: String? = {
            guard let url = Bundle.module.url(
                forResource: "Readability", withExtension: "js",
                subdirectory: "ReaderMode"
            ) else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        }()

        private static let readerCSS: String? = {
            guard let url = Bundle.module.url(
                forResource: "reader", withExtension: "css",
                subdirectory: "ReaderMode"
            ) else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        }()

        init(isLoading: Binding<Bool>) { _isLoading = isLoading }

        func load(url: URL, in wv: WKWebView) {
            webView = wv
            articleURL = url
            phase = .loadingRaw
            isLoading = true

            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
            URLSession.shared.dataTask(with: request) { [weak self, weak wv] data, _, _ in
                guard let self, let wv else { return }
                let html = data.flatMap {
                    String(data: $0, encoding: .utf8) ?? String(data: $0, encoding: .isoLatin1)
                }
                DispatchQueue.main.async {
                    if let html {
                        wv.loadHTMLString(html, baseURL: url)
                    } else {
                        self.showError(in: wv)
                    }
                }
            }.resume()
        }

        func webView(_ wv: WKWebView, didFinish _: WKNavigation!) {
            switch phase {
            case .loadingRaw:
                phase = .extracting
                extractArticle(from: wv)
            case .displaying:
                isLoading = false
            default:
                break
            }
        }

        func webView(_ wv: WKWebView, didFail _: WKNavigation!, withError _: Error) {
            if phase == .loadingRaw { showError(in: wv) }
        }

        func webView(_ wv: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) {
            if phase == .loadingRaw { showError(in: wv) }
        }

        func webView(
            _ wv: WKWebView,
            decidePolicyFor action: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = action.request.url else { return .cancel }
            if action.navigationType == .linkActivated {
                NSWorkspace.shared.open(url)
                return .cancel
            }
            return .allow
        }

        private func extractArticle(from wv: WKWebView) {
            guard let readabilityJS = Self.readabilityJS else { showError(in: wv); return }
            let script = """
            (function() {
                try {
                    \(readabilityJS)
                    var reader = new Readability(document);
                    var article = reader.parse();
                    if (!article) return null;
                    return JSON.stringify({
                        title: article.title || '',
                        content: article.content || '',
                        byline: article.byline || ''
                    });
                } catch (e) { return null; }
            })()
            """
            wv.evaluateJavaScript(script) { [weak self, weak wv] result, _ in
                guard let self, let wv else { return }
                guard let json = result as? String,
                      let data = json.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String]
                else { self.showError(in: wv); return }
                self.showReader(
                    title: obj["title"] ?? "",
                    byline: obj["byline"] ?? "",
                    content: obj["content"] ?? "",
                    in: wv
                )
            }
        }

        private func showReader(title: String, byline: String, content: String, in wv: WKWebView) {
            let css = Self.readerCSS ?? ""
            let bylineHTML = byline.isEmpty ? "" : "<p class='reader-byline'>\(byline)</p>"
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
                    <h1 class="reader-title">\(title)</h1>
                    \(bylineHTML)
                    <div class="reader-content">\(content)</div>
                </div>
            </body>
            </html>
            """
            phase = .displaying
            wv.loadHTMLString(html, baseURL: articleURL)

            // Trigger summary generation if Apple Intelligence is available
            // and this bookmark doesn't already have a summary.
            if let bid = bookmarkID,
               BookmarksStorage.shared.bookmarks.first(where: { $0.id == bid })?.aiSummary == nil {
                let plainText = "\(title). \(content)"
                    .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                Task { @MainActor in
                    if let summary = await SummaryService.shared.summarize(articleText: plainText) {
                        BookmarksStorage.shared.applyAISummary(summary, for: bid)
                    }
                }
            }
        }

        private func showError(in wv: WKWebView) {
            phase = .error
            isLoading = false
            let css = Self.readerCSS ?? ""
            wv.loadHTMLString("""
            <!DOCTYPE html><html>
            <head><meta charset="utf-8"><meta name="color-scheme" content="dark">
            <style>\(css)</style></head>
            <body><div class="reader-container">
                <div class="reader-error">Could not load article.</div>
            </div></body></html>
            """, baseURL: nil)
        }
    }
}
