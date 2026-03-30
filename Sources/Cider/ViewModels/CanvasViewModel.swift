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

    /// Latest canvas JSON from JS — used for flush-saves without JS round-trip.
    private var latestCanvasJSON: String?
    private var saveTask: Task<Void, Never>?
    private var terminationObserver: NSObjectProtocol?

    init() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.flushSave() }
        }
    }

    // MARK: - Storage

    private var canvasesDirectory: URL {
        StoragePaths.vaultDirectoryURL()
            .appendingPathComponent(StoragePaths.ciderInternalDir)
            .appendingPathComponent("canvases", isDirectory: true)
    }

    private var defaultCanvasFileURL: URL {
        canvasesDirectory.appendingPathComponent("default.canvas.json")
    }

    private func ensureCanvasesDirectory() {
        try? FileManager.default.createDirectory(
            at: canvasesDirectory,
            withIntermediateDirectories: true
        )
    }

    private func loadSavedCanvas() -> String? {
        guard FileManager.default.fileExists(atPath: defaultCanvasFileURL.path) else {
            return nil
        }
        return try? String(contentsOf: defaultCanvasFileURL, encoding: .utf8)
    }

    private func saveCanvasJSON(_ json: String) {
        ensureCanvasesDirectory()
        try? json.write(to: defaultCanvasFileURL, atomically: true, encoding: .utf8)
        Self.logger.debug("Saved canvas state (\(json.count) chars)")
    }

    func flushSave() {
        saveTask?.cancel()
        saveTask = nil

        guard let json = latestCanvasJSON else { return }
        saveCanvasJSON(json)
        latestCanvasJSON = nil
    }

    private func scheduleDebouncedSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.flushSave()
        }
    }

    // MARK: - WebView Setup

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

    // MARK: - Canvas Loading

    /// Called when JS signals ready. Loads saved canvas or generates initial layout.
    func onCanvasReady() {
        isReady = true
        Self.logger.info("Canvas editor ready")

        if let savedJSON = loadSavedCanvas() {
            // Restore saved canvas — but refresh metadata (thumbnails, tags may have changed)
            loadCanvasWithFreshMetadata(savedJSON)
        } else {
            // No saved canvas — generate initial layout from all bookmarks
            loadAllBookmarks()
        }
    }

    /// Load a saved canvas JSON, but refresh each item's metadata from the vault.
    private func loadCanvasWithFreshMetadata(_ savedJSON: String) {
        guard let webView = canvasWebView else { return }

        // Parse the saved JSON to get the node list
        guard let data = savedJSON.data(using: .utf8),
              let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nodes = saved["nodes"] as? [[String: Any]] else {
            // Corrupt save — fall back to initial layout
            loadAllBookmarks()
            return
        }

        let bookmarkService = VaultBookmarkService.shared

        // Build a set of item IDs already on the canvas
        let canvasItemIDs = Set(nodes.compactMap { $0["itemID"] as? String })

        // Rebuild nodes with fresh metadata
        var refreshedNodes: [[String: Any]] = []
        for node in nodes {
            guard let itemID = node["itemID"] as? String,
                  let uuid = UUID(uuidString: itemID),
                  let bookmark = bookmarkService.bookmarks.first(where: { $0.id == uuid }) else {
                continue // Skip orphaned nodes (item deleted from vault)
            }

            var refreshed = node
            var meta = bookmarkMetadata(for: bookmark)
            meta["itemID"] = itemID
            meta["itemType"] = node["itemType"] as? String ?? "bookmark"
            refreshed["metadata"] = meta
            refreshedNodes.append(refreshed)
        }

        // Find bookmarks NOT yet on the canvas — add them at inbox position
        let inboxX: CGFloat = 0
        var inboxY: CGFloat = 0
        for bookmark in bookmarkService.bookmarks {
            let idString = bookmark.id.uuidString
            guard !canvasItemIDs.contains(idString) else { continue }

            var meta = bookmarkMetadata(for: bookmark)
            meta["itemID"] = idString
            meta["itemType"] = "bookmark"

            let node: [String: Any] = [
                "id": "node-\(idString)",
                "itemID": idString,
                "itemType": "bookmark",
                "position": ["x": inboxX, "y": inboxY],
                "nodeType": "bookmarkCard",
                "metadata": meta,
            ]
            refreshedNodes.append(node)
            inboxY += 260
        }

        // Rebuild the canvas JSON with refreshed nodes
        var rebuilt = saved
        rebuilt["nodes"] = refreshedNodes

        if let rebuiltData = try? JSONSerialization.data(withJSONObject: rebuilt),
           let rebuiltJSON = String(data: rebuiltData, encoding: .utf8) {
            let escaped = escapeForJS(rebuiltJSON)
            webView.evaluateJavaScript("window.canvasBridge?.loadCanvas('\(escaped)')") { _, error in
                if let error {
                    Self.logger.error("loadCanvas JS error: \(error)")
                }
            }
        }
    }

    /// Generate initial canvas layout from all bookmarks in the vault.
    func loadAllBookmarks() {
        let bookmarkService = VaultBookmarkService.shared
        let bookmarks = bookmarkService.bookmarks

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

    // MARK: - Bridge: Swift → JS

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

    func handleCanvasChanged(_ jsonString: String) {
        latestCanvasJSON = jsonString
        scheduleDebouncedSave()
    }

    func handleItemClicked(uuid: String, type: String) {
        Self.logger.info("Item clicked: \(uuid) (\(type))")
        selectedItemID = uuid
        NotificationCenter.default.post(
            name: .canvasItemSelected,
            object: nil,
            userInfo: ["uuid": uuid, "type": type]
        )
    }

    func handleItemDoubleClicked(uuid: String, type: String) {
        Self.logger.info("Item double-clicked: \(uuid) (\(type))")
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
                viewModel.onCanvasReady()

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
