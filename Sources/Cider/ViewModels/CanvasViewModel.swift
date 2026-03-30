import Combine
import Foundation
import os
import WebKit

/// Custom WKWebView subclass that prevents window dragging.
final class CanvasWebView: WKWebView {
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
final class CanvasViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.cider", category: "CanvasViewModel")

    private(set) var canvasWebView: WKWebView?
    private var coordinator: CanvasCoordinator?

    @Published private(set) var isReady = false
    @Published var selectedItemID: String?

    init() {}

    @discardableResult
    func ensureWebView() -> WKWebView {
        if let existing = canvasWebView {
            return existing
        }

        let coord = CanvasCoordinator(viewModel: self)
        coordinator = coord

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(CiderVaultSchemeHandler(), forURLScheme: "cider-vault")
        let contentController = config.userContentController
        contentController.add(coord, name: "canvasReady")
        contentController.add(coord, name: "canvasChanged")
        contentController.add(coord, name: "itemClicked")
        contentController.add(coord, name: "itemDoubleClicked")
        contentController.add(coord, name: "canvasError")

        let webView = CanvasWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coord
        webView.setValue(false, forKey: "drawsBackground")

        if let resourceURL = Bundle.main.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "CanvasEditor"
        ) {
            let readAccessRoot = resourceURL.deletingLastPathComponent()
            webView.loadFileURL(resourceURL, allowingReadAccessTo: readAccessRoot)
        } else {
            Self.logger.error("CanvasEditor/index.html not found in bundle")
        }

        canvasWebView = webView
        return webView
    }

    // MARK: - Bridge: Swift → JS

    /// Load demo bookmark items onto the canvas for POC testing.
    func loadDemoItems() {
        let bookmarkService = VaultBookmarkService.shared
        let bookmarks = Array(bookmarkService.bookmarks.prefix(12))

        guard !bookmarks.isEmpty else {
            Self.logger.warning("No bookmarks available to load onto canvas")
            return
        }

        // Arrange in a grid: 4 columns, 320px spacing
        let columns = 4
        let spacingX: CGFloat = 320
        let spacingY: CGFloat = 260

        for (index, bookmark) in bookmarks.enumerated() {
            let col = index % columns
            let row = index / columns
            let x = CGFloat(col) * spacingX + 50
            let y = CGFloat(row) * spacingY + 50

            let metadata = bookmarkMetadata(for: bookmark)
            placeItem(uuid: bookmark.id.uuidString, type: "bookmark", x: x, y: y, metadata: metadata)
        }
    }

    /// Place a single item on the canvas.
    func placeItem(uuid: String, type: String, x: CGFloat, y: CGFloat, metadata: [String: Any]) {
        guard let webView = canvasWebView else { return }

        let metadataJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: metadata),
           let str = String(data: data, encoding: .utf8) {
            metadataJSON = str
        } else {
            metadataJSON = "{}"
        }

        let escaped = escapeForJS(metadataJSON)
        let js = "window.canvasBridge?.placeItem('\(uuid)', '\(type)', \(x), \(y), '\(escaped)')"
        webView.evaluateJavaScript(js) { _, error in
            if let error {
                Self.logger.error("placeItem JS error: \(error)")
            }
        }
    }

    /// Update an item's metadata on the canvas.
    func updateItemMetadata(uuid: String, metadata: [String: Any]) {
        guard let webView = canvasWebView else { return }

        let metadataJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: metadata),
           let str = String(data: data, encoding: .utf8) {
            metadataJSON = str
        } else {
            metadataJSON = "{}"
        }

        let escaped = escapeForJS(metadataJSON)
        let js = "window.canvasBridge?.updateItemMetadata('\(uuid)', '\(escaped)')"
        webView.evaluateJavaScript(js) { _, _ in }
    }

    /// Zoom to fit all items.
    func fitAll() {
        guard let webView = canvasWebView else { return }
        webView.evaluateJavaScript("window.canvasBridge?.fitAll()") { _, _ in }
    }

    func setTheme(_ theme: String) {
        guard let webView = canvasWebView else { return }
        let safeTheme = theme == "light" ? "light" : "dark"
        webView.evaluateJavaScript("window.canvasBridge?.setTheme('\(safeTheme)')") { _, _ in }
    }

    // MARK: - Bridge: JS → Swift (called by coordinator)

    func markReady() {
        isReady = true
        Self.logger.info("Canvas editor ready")
    }

    func handleCanvasChanged(_ jsonString: String) {
        // POC: just log that we received changes. Persistence comes later.
        Self.logger.debug("Canvas state changed (\(jsonString.count) chars)")
    }

    func handleItemClicked(uuid: String, type: String) {
        Self.logger.info("Item clicked: \(uuid) (\(type))")
        selectedItemID = uuid
        // In the future this opens the NSPanel in inspector mode
        NotificationCenter.default.post(
            name: .canvasItemSelected,
            object: nil,
            userInfo: ["uuid": uuid, "type": type]
        )
    }

    func handleItemDoubleClicked(uuid: String, type: String) {
        Self.logger.info("Item double-clicked: \(uuid) (\(type))")
        // In the future this opens the item for editing
    }

    // MARK: - Helpers

    private func bookmarkMetadata(for bookmark: Bookmark) -> [String: Any] {
        var meta: [String: Any] = [
            "title": bookmark.title,
            "url": bookmark.urlString,
            "domain": bookmark.hostDisplay,
        ]

        // Favicon from ClipboardStorage cache — use cider-vault:// scheme for WKWebView access
        let domain = bookmark.hostDisplay
        let faviconURL = ClipboardStorage.shared.faviconFileURL(for: domain)
        if FileManager.default.fileExists(atPath: faviconURL.path) {
            meta["favicon"] = "cider-vault:///" + faviconURL.path
        }

        // Thumbnail from bookmark's cached file
        if let thumbnailURL = bookmark.thumbnailFileURL,
           FileManager.default.fileExists(atPath: thumbnailURL.path) {
            meta["thumbnail"] = "cider-vault:///" + thumbnailURL.path
        }

        // Relative time display
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        meta["timeAgo"] = formatter.localizedString(for: bookmark.createdAt, relativeTo: Date())

        // Tag labels with colors
        if !bookmark.labelIDs.isEmpty {
            let labels = bookmark.labelIDs.compactMap { id in
                CardLabelStorage.shared.labels.first { $0.id == id }
            }
            meta["tags"] = labels.map { label in
                ["name": label.name, "color": label.colorHex]
            }
        }

        meta["hasAISummary"] = bookmark.aiSummary != nil

        return meta
    }

    private func escapeForJS(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}

// MARK: - Coordinator

final class CanvasCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private static let logger = Logger(subsystem: "com.cider", category: "CanvasCoordinator")
    private weak var viewModel: CanvasViewModel?

    init(viewModel: CanvasViewModel) {
        self.viewModel = viewModel
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        Task { @MainActor [weak self] in
            guard let self, let viewModel = self.viewModel else { return }

            switch message.name {
            case "canvasReady":
                viewModel.markReady()
                // Auto-load demo items for POC
                viewModel.loadDemoItems()

            case "canvasChanged":
                if let jsonString = message.body as? String {
                    viewModel.handleCanvasChanged(jsonString)
                }

            case "itemClicked":
                if let jsonString = message.body as? String,
                   let data = jsonString.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let uuid = dict["uuid"] as? String {
                    let type = dict["type"] as? String ?? "bookmark"
                    viewModel.handleItemClicked(uuid: uuid, type: type)
                }

            case "itemDoubleClicked":
                if let jsonString = message.body as? String,
                   let data = jsonString.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let uuid = dict["uuid"] as? String {
                    let type = dict["type"] as? String ?? "bookmark"
                    viewModel.handleItemDoubleClicked(uuid: uuid, type: type)
                }

            case "canvasError":
                if let jsonString = message.body as? String {
                    Self.logger.error("Canvas error: \(jsonString)")
                }

            default:
                break
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        let scheme = url.scheme ?? ""
        if scheme == "file" || scheme == "about" || scheme == "blob" {
            decisionHandler(.allow)
            return
        }

        if scheme == "http" || scheme == "https" {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }
}
