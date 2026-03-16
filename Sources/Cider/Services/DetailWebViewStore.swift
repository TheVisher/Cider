import SwiftUI
import WebKit
import os

/// Holds persistent WKWebView instances so they survive SwiftUI view hierarchy
/// changes (e.g. switching between slide-out, full panel, and page detail modes).
/// Also eagerly preloads web and reader content when a bookmark detail opens.
@MainActor
final class DetailWebViewStore: ObservableObject {
    private static let logger = Logger(subsystem: "com.cider.app", category: "DetailWebViewStore")

    // MARK: - Live Web View

    private(set) var webView: WKWebView?
    private var loadedURL: URL?
    @Published var webViewReady: Bool = false

    // MARK: - Reader

    private(set) var readerWebView: WKWebView?
    private var readerLoadedURL: URL?
    @Published var readerReady: Bool = false
    @Published var readerFailed: Bool = false

    /// Cached reader article — extracted in background, loaded into visible WKWebView on demand.
    struct ReaderArticle {
        let title: String
        let byline: String
        let content: String
    }
    private(set) var cachedArticle: ReaderArticle?

    // Background extraction state
    private var extractionWebView: WKWebView?
    private var extractionDelegate: ReaderExtractionDelegate?
    private var currentBookmarkID: UUID?

    // MARK: - Eager Preload

    /// Call when a bookmark detail opens. Eagerly starts loading both the live
    /// web page and reader extraction so content is ready when the user switches.
    func preload(url: URL, bookmarkID: UUID) {
        currentBookmarkID = bookmarkID

        // Check persisted reader availability
        if let bm = BookmarksStorage.shared.bookmarks.first(where: { $0.id == bookmarkID }),
           bm.readerUnavailable == true {
            readerFailed = true
            // Skip reader extraction, still preload web view
        } else {
            // Start background reader extraction
            startReaderExtraction(url: url, bookmarkID: bookmarkID)
        }

        // Start preloading the live web view
        startWebViewPreload(url: url)
    }

    // MARK: - Web View Preload

    private func startWebViewPreload(url: URL) {
        guard webView == nil || loadedURL != url else {
            webViewReady = true
            return
        }
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = .all
        let wv = WKWebView(frame: .zero, configuration: config)
        let delegate = WebLoadDelegate { [weak self] in
            self?.webViewReady = true
        }
        wv.navigationDelegate = delegate
        wv.uiDelegate = Self.suppressingUIDelegate
        wv.setValue(false, forKey: "drawsBackground")
        wv.load(URLRequest(url: url))
        webView = wv
        loadedURL = url
        // Store the delegate so it stays alive
        objc_setAssociatedObject(wv, &AssociatedKeys.webDelegate, delegate, .OBJC_ASSOCIATION_RETAIN)
    }

    /// Returns the preloaded WKWebView, reassigning its delegate for interactive use.
    func getWebView(for url: URL, delegate: WKNavigationDelegate) -> WKWebView {
        if let existing = webView, loadedURL == url {
            existing.navigationDelegate = delegate
            return existing
        }
        // Fallback — shouldn't happen if preload was called
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = .all
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = delegate
        wv.setValue(false, forKey: "drawsBackground")
        wv.load(URLRequest(url: url))
        webView = wv
        loadedURL = url
        return wv
    }

    // MARK: - Reader Extraction (Background)

    private static let readabilityJS: String? = {
        guard let url = Bundle.main.url(
            forResource: "Readability", withExtension: "js",
            subdirectory: "ReaderMode"
        ) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    private func startReaderExtraction(url: URL, bookmarkID: UUID) {
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: WKWebViewConfiguration())
        wv.setValue(false, forKey: "drawsBackground")
        let delegate = ReaderExtractionDelegate(bookmarkID: bookmarkID) { [weak self] result in
            guard let self, self.currentBookmarkID == bookmarkID else { return }
            switch result {
            case .success(let article):
                self.cachedArticle = article
                self.readerReady = true
                BookmarksStorage.shared.setReaderUnavailable(false, for: bookmarkID)
                Self.logger.debug("Reader content extracted for \(bookmarkID)")
            case .failure:
                self.readerFailed = true
                BookmarksStorage.shared.setReaderUnavailable(true, for: bookmarkID)
                Self.logger.debug("Reader extraction failed for \(bookmarkID)")
            }
            self.extractionWebView = nil
            self.extractionDelegate = nil
        }
        wv.navigationDelegate = delegate
        extractionWebView = wv
        extractionDelegate = delegate

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        URLSession.shared.dataTask(with: request) { [weak wv, weak delegate] data, _, _ in
            guard let wv, let delegate else { return }
            let html = data.flatMap {
                String(data: $0, encoding: .utf8) ?? String(data: $0, encoding: .isoLatin1)
            }
            DispatchQueue.main.async {
                if let html {
                    // Strip <script> tags from the page HTML before loading to prevent
                    // untrusted page JavaScript from executing. Our Readability.js is
                    // injected separately via evaluateJavaScript after load.
                    let sanitized = html.replacingOccurrences(
                        of: #"(?is)<script\b[^>]*>.*?</script>"#,
                        with: "",
                        options: .regularExpression
                    )
                    delegate.phase = .loadedHTML
                    wv.loadHTMLString(sanitized, baseURL: url)
                } else {
                    delegate.reportFailure()
                }
            }
        }.resume()
    }

    // MARK: - Reader View (Visible)

    /// Returns a WKWebView for displaying cached reader content.
    /// The reader HTML is loaded directly from the cache — no raw page content ever touches this view.
    func getReaderWebView(for url: URL, delegate: WKNavigationDelegate) -> WKWebView {
        if let existing = readerWebView, readerLoadedURL == url {
            existing.navigationDelegate = delegate
            return existing
        }
        let wv = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        wv.navigationDelegate = delegate
        wv.setValue(false, forKey: "drawsBackground")
        readerWebView = wv
        readerLoadedURL = url
        return wv
    }

    // MARK: - Lifecycle

    func reset() {
        pauseMedia(in: webView)
        pauseMedia(in: readerWebView)
        webView = nil
        readerWebView = nil
        loadedURL = nil
        readerLoadedURL = nil
        extractionWebView = nil
        extractionDelegate = nil
        cachedArticle = nil
        currentBookmarkID = nil
        webViewReady = false
        readerReady = false
        readerFailed = false
    }

    func pauseAllMedia() {
        pauseMedia(in: webView)
        pauseMedia(in: readerWebView)
    }

    private func pauseMedia(in wv: WKWebView?) {
        wv?.evaluateJavaScript(
            "document.querySelectorAll('video,audio').forEach(function(m){try{m.pause();}catch(e){}})"
        )
    }

    /// Shared UI delegate that suppresses window.open() during preload.
    /// Without this, JS-heavy sites (Shopify) fire window.open() calls that
    /// leak to the system browser on macOS, opening dozens of tabs.
    private static let suppressingUIDelegate = SuppressingUIDelegate()
}

// MARK: - Suppressing UI Delegate (blocks window.open during preload)

private final class SuppressingUIDelegate: NSObject, WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // Return nil to block new window creation (window.open calls).
        // During preload, no user interaction is happening so these are
        // all JS-initiated and should be suppressed.
        return nil
    }
}

// MARK: - Associated Object Key

private enum AssociatedKeys {
    nonisolated(unsafe) static var webDelegate = 0
}

// MARK: - Web Load Delegate (preload completion tracking)

private final class WebLoadDelegate: NSObject, WKNavigationDelegate {
    private let onReady: () -> Void
    private var reported = false

    init(onReady: @escaping () -> Void) {
        self.onReady = onReady
    }

    func webView(_ wv: WKWebView, didFinish _: WKNavigation!) {
        guard !reported else { return }
        reported = true
        onReady()
    }

    func webView(_ wv: WKWebView, didFail _: WKNavigation!, withError _: Error) {
        guard !reported else { return }
        reported = true
        onReady() // Still "ready" — the web view shows an error page
    }

    func webView(_ wv: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) {
        guard !reported else { return }
        reported = true
        onReady()
    }

    // No decidePolicyFor here — this delegate is for preload only.
    // Opening URLs externally during preload causes JS-heavy sites
    // (e.g., Shopify) to spawn dozens of browser tabs. Link-opening
    // is handled by BookmarkWebView.Coordinator when the user
    // interacts with the visible web view.
}

// MARK: - Reader Extraction Delegate (background extraction)

private final class ReaderExtractionDelegate: NSObject, WKNavigationDelegate {
    enum Phase { case initial, loadedHTML, extracting }
    var phase: Phase = .initial
    private let bookmarkID: UUID
    private let completion: (Result<DetailWebViewStore.ReaderArticle, Error>) -> Void
    private var reported = false

    private static let readabilityJS: String? = {
        guard let url = Bundle.main.url(
            forResource: "Readability", withExtension: "js",
            subdirectory: "ReaderMode"
        ) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    init(bookmarkID: UUID, completion: @escaping (Result<DetailWebViewStore.ReaderArticle, Error>) -> Void) {
        self.bookmarkID = bookmarkID
        self.completion = completion
    }

    func reportFailure() {
        guard !reported else { return }
        reported = true
        completion(.failure(NSError(domain: "ReaderExtraction", code: -1)))
    }

    func webView(_ wv: WKWebView, didFinish _: WKNavigation!) {
        guard phase == .loadedHTML else { return }
        phase = .extracting
        guard let readabilityJS = Self.readabilityJS else {
            reportFailure()
            return
        }
        let script = """
        (function() {
            try {
                \(readabilityJS)
                var reader = new Readability(document);
                var article = reader.parse();
                if (!article || !article.content || article.content.length < 100) return null;
                return JSON.stringify({
                    title: article.title || '',
                    content: article.content || '',
                    byline: article.byline || ''
                });
            } catch (e) { return null; }
        })()
        """
        wv.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self, !self.reported else { return }
            self.reported = true
            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String]
            else {
                self.completion(.failure(NSError(domain: "ReaderExtraction", code: -2)))
                return
            }
            let article = DetailWebViewStore.ReaderArticle(
                title: obj["title"] ?? "",
                byline: obj["byline"] ?? "",
                content: obj["content"] ?? ""
            )
            self.completion(.success(article))
        }
    }

    func webView(_ wv: WKWebView, didFail _: WKNavigation!, withError _: Error) {
        reportFailure()
    }

    func webView(_ wv: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) {
        reportFailure()
    }
}
