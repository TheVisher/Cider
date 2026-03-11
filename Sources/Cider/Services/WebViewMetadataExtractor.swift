import AppKit
import Foundation
import os
import WebKit

/// Result of a WebView metadata extraction — includes an optional page screenshot
/// as a fallback thumbnail when the og:image URL can't be downloaded.
struct WebViewExtractionResult {
    let title: String?
    let imageURL: URL?
    let screenshotData: Data?
}

/// Headless WKWebView that renders a page (handling WAF challenges, JS-rendered meta tags)
/// and extracts og:image + title from the DOM. Also captures a page screenshot as a fallback
/// thumbnail. Used when static HTML parsing fails to find metadata.
@MainActor
final class WebViewMetadataExtractor: NSObject, WKNavigationDelegate {
    private static let logger = Logger(subsystem: "com.cider.app", category: "Enrichment")

    // Process pool removed — WKProcessPool was deprecated in macOS 12.0
    // and no longer has any effect.

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<WebViewExtractionResult, Never>?
    private var hasResumed = false
    private var extractionAttempts = 0
    private var timeoutTask: Task<Void, Never>?

    /// Extract metadata by rendering the page in a headless WebView.
    /// Handles WAF challenges (page reloads after JS token exchange).
    static func extract(from url: URL) async -> WebViewExtractionResult {
        let extractor = WebViewMetadataExtractor()
        return await extractor.run(url: url)
    }

    private func run(url: URL) async -> WebViewExtractionResult {
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
                await self?.resolveWithScreenshot(title: nil, imageURL: nil)
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
            self?.resumeIfNeeded(title: nil, imageURL: nil, screenshotData: nil)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            Self.logger.warning("WebView provisional navigation failed: \(error.localizedDescription, privacy: .public)")
            self?.resumeIfNeeded(title: nil, imageURL: nil, screenshotData: nil)
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

    // swiftlint:disable function_body_length
    private func extractMetadata(from webView: WKWebView) async {
        // Enhanced JS: og:image, twitter:image, itemprop, link image_src,
        // JSON-LD image, largest visible <img>. Resolves relative URLs.
        let js = """
        (function() {
            function resolve(url) {
                if (!url) return null;
                try { return new URL(url, window.location.href).href; } catch(e) { return url; }
            }

            var og = document.querySelector('meta[property="og:image"]');
            var tw = document.querySelector('meta[name="twitter:image"]')
                  || document.querySelector('meta[name="twitter:image:src"]');
            var ip = document.querySelector('meta[itemprop="image"]');
            var li = document.querySelector('link[rel="image_src"]');

            // JSON-LD image
            var jsonld = null;
            var scripts = document.querySelectorAll('script[type="application/ld+json"]');
            for (var i = 0; i < scripts.length; i++) {
                try {
                    var data = JSON.parse(scripts[i].textContent);
                    var items = Array.isArray(data) ? data : (data['@graph'] || [data]);
                    for (var j = 0; j < items.length; j++) {
                        var item = items[j];
                        if (!item || !item.image) continue;
                        var img = item.image;
                        if (typeof img === 'string') { jsonld = img; break; }
                        if (Array.isArray(img)) img = img[0];
                        if (typeof img === 'string') { jsonld = img; break; }
                        if (img && (img.url || img.contentUrl)) { jsonld = img.url || img.contentUrl; break; }
                    }
                    if (jsonld) break;
                } catch(e) {}
            }

            // Largest visible image on page (min 200x150 to skip icons/avatars)
            var largestImg = null;
            var largestArea = 0;
            var imgs = document.querySelectorAll('img[src]');
            for (var i = 0; i < imgs.length; i++) {
                var el = imgs[i];
                var w = el.naturalWidth || el.width;
                var h = el.naturalHeight || el.height;
                var area = w * h;
                if (area > largestArea && w >= 200 && h >= 150) {
                    largestArea = area;
                    largestImg = el.src;
                }
            }

            var ogTitle = document.querySelector('meta[property="og:title"]');
            var title = ogTitle ? ogTitle.content : document.title;

            var image = resolve(og ? og.content : null)
                     || resolve(tw ? tw.content : null)
                     || resolve(ip ? ip.content : null)
                     || resolve(li ? li.href : null)
                     || resolve(jsonld)
                     || largestImg;

            return JSON.stringify({title: title || null, image: image || null});
        })()
        """

        do {
            guard let result = try await webView.evaluateJavaScript(js) as? String,
                  let data = result.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                if extractionAttempts >= 3 {
                    await resolveWithScreenshot(title: nil, imageURL: nil)
                }
                return
            }

            let title = json["title"] as? String
            let imageString = json["image"] as? String
            let imageURL = imageString.flatMap { URL(string: $0) }

            Self.logger.info("WebView DOM extraction attempt \(self.extractionAttempts): title=\(title ?? "nil", privacy: .public) image=\(imageURL?.absoluteString ?? "nil", privacy: .public)")

            if imageURL != nil || extractionAttempts >= 3 {
                await resolveWithScreenshot(title: title, imageURL: imageURL)
            }
            // else: probably a WAF challenge page — wait for the reload
        } catch {
            Self.logger.warning("WebView JS extraction error: \(error.localizedDescription, privacy: .public)")
            if extractionAttempts >= 3 {
                await resolveWithScreenshot(title: nil, imageURL: nil)
            }
        }
    }
    // swiftlint:enable function_body_length

    // MARK: - Screenshot

    /// Capture a page screenshot before resuming — serves as a fallback thumbnail
    /// when the og:image URL can't be downloaded (CDN auth, hotlink protection, etc.).
    private func resolveWithScreenshot(title: String?, imageURL: URL?) async {
        guard !hasResumed else { return }
        var screenshotData: Data?
        if let webView {
            screenshotData = await captureScreenshot(from: webView)
        }
        resumeIfNeeded(title: title, imageURL: imageURL, screenshotData: screenshotData)
    }

    private func captureScreenshot(from webView: WKWebView) async -> Data? {
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: 1280, height: 720)
        do {
            let image = try await webView.takeSnapshot(configuration: config)
            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
            return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        } catch {
            Self.logger.warning("WebView screenshot failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Cleanup

    private func resumeIfNeeded(title: String?, imageURL: URL?, screenshotData: Data?) {
        guard !hasResumed else { return }
        hasResumed = true
        timeoutTask?.cancel()
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
        continuation?.resume(returning: WebViewExtractionResult(
            title: title,
            imageURL: imageURL,
            screenshotData: screenshotData
        ))
    }
}
