import Foundation
import os
import WebKit

/// Headless WKWebView that renders a page (handling WAF challenges, JS-rendered meta tags)
/// and extracts og:image + title from the DOM. Used as a fallback when static HTML parsing
/// fails to find metadata (e.g. IMDB behind Amazon WAF, Booking.com with JS rendering).
@MainActor
final class WebViewMetadataExtractor: NSObject, WKNavigationDelegate {
    private static let logger = Logger(subsystem: "com.cider.app", category: "Enrichment")

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<(title: String?, imageURL: URL?), Never>?
    private var hasResumed = false
    private var extractionAttempts = 0
    private var timeoutTask: Task<Void, Never>?

    /// Extract metadata by rendering the page in a headless WebView.
    /// Handles WAF challenges (page reloads after JS token exchange).
    static func extract(from url: URL) async -> (title: String?, imageURL: URL?) {
        let extractor = WebViewMetadataExtractor()
        return await extractor.run(url: url)
    }

    private func run(url: URL) async -> (title: String?, imageURL: URL?) {
        return await withCheckedContinuation { continuation in
            self.continuation = continuation

            let config = WKWebViewConfiguration()
            config.suppressesIncrementalRendering = true
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 720), configuration: config)
            webView.navigationDelegate = self
            webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15"
            self.webView = webView
            webView.load(URLRequest(url: url))

            // Hard timeout — don't hang forever
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                self?.resumeIfNeeded(title: nil, imageURL: nil)
            }
        }
    }

    // MARK: - WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            self?.handleDidFinish(webView)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            Self.logger.warning("WebView navigation failed: \(error.localizedDescription, privacy: .public)")
            self?.resumeIfNeeded(title: nil, imageURL: nil)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            Self.logger.warning("WebView provisional navigation failed: \(error.localizedDescription, privacy: .public)")
            self?.resumeIfNeeded(title: nil, imageURL: nil)
        }
    }

    // MARK: - Extraction

    private func handleDidFinish(_ webView: WKWebView) {
        extractionAttempts += 1

        // Brief delay for post-load JS execution (WAF token exchange, meta tag injection)
        Task { [weak self, attempts = extractionAttempts] in
            try? await Task.sleep(for: .milliseconds(800))
            guard let self, self.extractionAttempts == attempts else { return }
            await self.extractMetadata(from: webView)
        }
    }

    private func extractMetadata(from webView: WKWebView) async {
        let js = """
        (function() {
            var og = document.querySelector('meta[property="og:image"]');
            var tw = document.querySelector('meta[name="twitter:image"]')
                  || document.querySelector('meta[name="twitter:image:src"]');
            var ogTitle = document.querySelector('meta[property="og:title"]');
            var title = ogTitle ? ogTitle.content : document.title;
            var image = og ? og.content : (tw ? tw.content : null);
            return JSON.stringify({title: title || null, image: image || null});
        })()
        """

        do {
            guard let result = try await webView.evaluateJavaScript(js) as? String,
                  let data = result.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                if extractionAttempts >= 3 {
                    resumeIfNeeded(title: nil, imageURL: nil)
                }
                return
            }

            let title = json["title"] as? String
            let imageString = json["image"] as? String
            let imageURL = imageString.flatMap { URL(string: $0) }

            if imageURL != nil || extractionAttempts >= 3 {
                // Found og:image, or exhausted retries (WAF challenge may have failed)
                resumeIfNeeded(title: title, imageURL: imageURL)
            }
            // else: probably a WAF challenge page — wait for the reload
        } catch {
            Self.logger.warning("WebView JS extraction error: \(error.localizedDescription, privacy: .public)")
            if extractionAttempts >= 3 {
                resumeIfNeeded(title: nil, imageURL: nil)
            }
        }
    }

    // MARK: - Cleanup

    private func resumeIfNeeded(title: String?, imageURL: URL?) {
        guard !hasResumed else { return }
        hasResumed = true
        timeoutTask?.cancel()
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
        continuation?.resume(returning: (title, imageURL))
    }
}
