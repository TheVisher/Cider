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
        contentController.add(coord, name: "folderToggleCollapse")

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
            loadAllItems()
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
            loadAllItems()
            return
        }

        let bookmarks = VaultBookmarkService.shared.bookmarks
        let notes = NotesStorage.shared.notes
        let todos = TodoCardStorage.shared.todoCards

        // Build a set of item IDs already on the canvas
        let canvasItemIDs = Set(nodes.compactMap { $0["itemID"] as? String })

        // Rebuild nodes with fresh metadata
        var refreshedNodes: [[String: Any]] = []
        for node in nodes {
            guard let itemID = node["itemID"] as? String,
                  let uuid = UUID(uuidString: itemID) else { continue }

            let itemType = node["itemType"] as? String ?? "bookmark"
            var refreshed = node

            if itemType == "note", let note = notes.first(where: { $0.id == uuid }) {
                var meta = noteMetadata(for: note)
                meta["itemID"] = itemID
                meta["itemType"] = "note"
                refreshed["metadata"] = meta
                refreshed["nodeType"] = "noteCard"
                refreshedNodes.append(refreshed)
            } else if itemType == "todo", let todo = todos.first(where: { $0.id == uuid }) {
                var meta = todoMetadata(for: todo)
                meta["itemID"] = itemID
                meta["itemType"] = "todo"
                refreshed["metadata"] = meta
                refreshed["nodeType"] = "todoCard"
                refreshedNodes.append(refreshed)
            } else if let bookmark = bookmarks.first(where: { $0.id == uuid }) {
                var meta = bookmarkMetadata(for: bookmark)
                meta["itemID"] = itemID
                meta["itemType"] = "bookmark"
                refreshed["metadata"] = meta
                refreshed["nodeType"] = "bookmarkCard"
                refreshedNodes.append(refreshed)
            }
            // Skip if item not found in any storage (deleted)
        }

        // Find items NOT yet on the canvas — add them below existing items
        // Calculate the lowest Y position of existing nodes so new items don't overlap
        var maxY: CGFloat = 0
        for node in refreshedNodes {
            if let pos = node["position"] as? [String: Any],
               let y = pos["y"] as? CGFloat {
                maxY = max(maxY, y)
            }
        }
        let inboxX: CGFloat = 50
        var inboxY: CGFloat = maxY + 300 // Start below existing items
        let inboxColumns = 4
        let inboxSpacingX: CGFloat = 320
        let inboxSpacingY: CGFloat = 260
        var newItemIndex = 0

        func inboxPosition() -> (CGFloat, CGFloat) {
            let col = newItemIndex % inboxColumns
            let row = newItemIndex / inboxColumns
            let x = inboxX + CGFloat(col) * inboxSpacingX
            let y = inboxY + CGFloat(row) * inboxSpacingY
            newItemIndex += 1
            return (x, y)
        }

        for bookmark in bookmarks where !canvasItemIDs.contains(bookmark.id.uuidString) {
            var meta = bookmarkMetadata(for: bookmark)
            let idString = bookmark.id.uuidString
            meta["itemID"] = idString
            meta["itemType"] = "bookmark"
            let (x, y) = inboxPosition()
            refreshedNodes.append([
                "id": "node-\(idString)", "itemID": idString, "itemType": "bookmark",
                "position": ["x": x, "y": y], "nodeType": "bookmarkCard", "metadata": meta,
            ])
        }

        for note in notes where !canvasItemIDs.contains(note.id.uuidString) {
            var meta = noteMetadata(for: note)
            let idString = note.id.uuidString
            meta["itemID"] = idString
            meta["itemType"] = "note"
            let (x, y) = inboxPosition()
            refreshedNodes.append([
                "id": "node-\(idString)", "itemID": idString, "itemType": "note",
                "position": ["x": x, "y": y], "nodeType": "noteCard", "metadata": meta,
            ])
        }

        for todo in todos where !canvasItemIDs.contains(todo.id.uuidString) {
            var meta = todoMetadata(for: todo)
            let idString = todo.id.uuidString
            meta["itemID"] = idString
            meta["itemType"] = "todo"
            let (x, y) = inboxPosition()
            refreshedNodes.append([
                "id": "node-\(idString)", "itemID": idString, "itemType": "todo",
                "position": ["x": x, "y": y], "nodeType": "todoCard", "metadata": meta,
            ])
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

    /// Generate initial canvas layout from all items in the vault, grouped by folder.
    func loadAllItems() {
        let bookmarks = VaultBookmarkService.shared.bookmarks
        let notes = NotesStorage.shared.notes
        let todos = TodoCardStorage.shared.todoCards
        let folders = VaultFolderService.shared.folders

        // Collect all items by folder
        struct CanvasItem {
            let uuid: String
            let type: String   // "bookmark", "note", "todo"
            let nodeType: String // "bookmarkCard", "noteCard", "todoCard"
            let metadata: [String: Any]
        }

        var folderItems: [UUID: [CanvasItem]] = [:]
        var unfiledItems: [CanvasItem] = []

        for bookmark in bookmarks {
            let item = CanvasItem(
                uuid: bookmark.id.uuidString, type: "bookmark",
                nodeType: "bookmarkCard", metadata: bookmarkMetadata(for: bookmark)
            )
            if let fid = bookmark.folderID {
                folderItems[fid, default: []].append(item)
            } else {
                unfiledItems.append(item)
            }
        }

        for note in notes {
            let item = CanvasItem(
                uuid: note.id.uuidString, type: "note",
                nodeType: "noteCard", metadata: noteMetadata(for: note)
            )
            if let fid = note.folderID {
                folderItems[fid, default: []].append(item)
            } else {
                unfiledItems.append(item)
            }
        }

        for todo in todos {
            let item = CanvasItem(
                uuid: todo.id.uuidString, type: "todo",
                nodeType: "todoCard", metadata: todoMetadata(for: todo)
            )
            if let fid = todo.folderID {
                folderItems[fid, default: []].append(item)
            } else {
                unfiledItems.append(item)
            }
        }

        // Layout constants
        let columns = 4
        let cardWidth: CGFloat = 280
        let cardGapX: CGFloat = 20
        let cardSpacingX: CGFloat = cardWidth + cardGapX
        let cardHeight: CGFloat = 260   // card height including tags + meta
        let cardGapY: CGFloat = 20
        let cardSpacingY: CGFloat = cardHeight + cardGapY
        let folderPadding: CGFloat = 60 // top padding for header
        let folderGap: CGFloat = 80     // gap between folders
        let folderInset: CGFloat = 20   // padding inside folder edges
        var currentY: CGFloat = 50

        // Build all nodes at once, then send as a single loadCanvas call
        // (individual placeItem calls have timing issues with parent-child setup)
        var allNodes: [[String: Any]] = []

        // Folder groups first (parents must come before children in the array)
        for folder in folders {
            let items = folderItems[folder.id] ?? []
            guard !items.isEmpty else { continue }
            let groupId = "folder-\(folder.id.uuidString)"
            let actualColumns = min(columns, max(1, items.count))
            let rows = max(1, (items.count + columns - 1) / columns)
            let groupWidth = CGFloat(actualColumns) * cardSpacingX + folderInset * 2
            let groupHeight = folderPadding + CGFloat(rows) * cardSpacingY + folderInset + 20

            let folderNode: [String: Any] = [
                "id": groupId,
                "nodeType": "folderGroup",
                "position": ["x": 50, "y": currentY],
                "style": ["width": groupWidth, "height": groupHeight],
                "metadata": [
                    "folderName": folder.name,
                    "icon": folder.icon ?? "📁",
                    "itemCount": items.count,
                    "collapsed": false,
                ] as [String: Any],
            ]
            allNodes.append(folderNode)

            // Child items inside the folder
            for (i, item) in items.enumerated() {
                let col = i % columns
                let row = i / columns
                let x = CGFloat(col) * cardSpacingX + 20
                let y = folderPadding + CGFloat(row) * cardSpacingY

                var meta = item.metadata
                meta["itemID"] = item.uuid
                meta["itemType"] = item.type

                let childNode: [String: Any] = [
                    "id": "node-\(item.uuid)",
                    "itemID": item.uuid,
                    "itemType": item.type,
                    "nodeType": item.nodeType,
                    "position": ["x": x, "y": y],
                    "parentNode": groupId,
                    "metadata": meta,
                ]
                allNodes.append(childNode)
            }

            currentY += groupHeight + folderGap
        }

        // Unfiled items below all folders
        if !unfiledItems.isEmpty {
            currentY += 40
            for (i, item) in unfiledItems.enumerated() {
                let col = i % columns
                let row = i / columns
                let x = CGFloat(col) * cardSpacingX + 50
                let y = currentY + CGFloat(row) * cardSpacingY

                var meta = item.metadata
                meta["itemID"] = item.uuid
                meta["itemType"] = item.type

                let node: [String: Any] = [
                    "id": "node-\(item.uuid)",
                    "itemID": item.uuid,
                    "itemType": item.type,
                    "nodeType": item.nodeType,
                    "position": ["x": x, "y": y],
                    "metadata": meta,
                ]
                allNodes.append(node)
            }
        }

        // Send everything at once via loadCanvas
        let canvasData: [String: Any] = [
            "version": 1,
            "nodes": allNodes,
            "edges": [] as [[String: Any]],
        ]

        if let data = try? JSONSerialization.data(withJSONObject: canvasData),
           let json = String(data: data, encoding: .utf8) {
            let escaped = escapeForJS(json)
            canvasWebView?.evaluateJavaScript("window.canvasBridge?.loadCanvas('\(escaped)')") { _, error in
                if let error {
                    Self.logger.error("loadCanvas JS error: \(error)")
                }
            }
        }

        Self.logger.info("Loaded \(folders.count) folders, \(bookmarks.count) bookmarks, \(notes.count) notes, \(todos.count) todos onto canvas")
    }

    /// Place a folder group node on the canvas.
    private func placeFolder(id: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, metadata: [String: Any]) {
        guard let webView = canvasWebView else { return }

        let metadataJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: metadata),
           let str = String(data: data, encoding: .utf8) {
            metadataJSON = str
        } else {
            metadataJSON = "{}"
        }

        let escaped = escapeForJS(metadataJSON)
        let js = "window.canvasBridge?.placeFolder('\(id)', \(x), \(y), \(width), \(height), '\(escaped)')"
        webView.evaluateJavaScript(js) { _, error in
            if let error {
                Self.logger.error("placeFolder JS error: \(error)")
            }
        }
    }

    /// Place an item as a child of a folder group.
    private func placeChildItem(uuid: String, nodeType: String, x: CGFloat, y: CGFloat, parentId: String, metadata: [String: Any]) {
        guard let webView = canvasWebView else { return }

        let metadataJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: metadata),
           let str = String(data: data, encoding: .utf8) {
            metadataJSON = str
        } else {
            metadataJSON = "{}"
        }

        let escaped = escapeForJS(metadataJSON)
        let js = "window.canvasBridge?.placeChildItem('\(uuid)', '\(nodeType)', \(x), \(y), '\(parentId)', '\(escaped)')"
        webView.evaluateJavaScript(js) { _, error in
            if let error {
                Self.logger.error("placeChildItem JS error: \(error)")
            }
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

        let nodeType: String
        switch type {
        case "note", "noteCard": nodeType = "noteCard"
        case "todo", "todoCard": nodeType = "todoCard"
        default: nodeType = "bookmarkCard"
        }
        let escaped = escapeForJS(metadataJSON)
        let js = "window.canvasBridge?.placeItem('\(uuid)', '\(nodeType)', \(x), \(y), '\(escaped)')"
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

        guard let bookmarkID = UUID(uuidString: uuid) else { return }

        // Post canvas item selected — AppDelegate handles showing panel + opening details
        NotificationCenter.default.post(
            name: .canvasItemSelected,
            object: nil,
            userInfo: ["bookmarkID": bookmarkID, "type": type]
        )
    }

    func handleItemDoubleClicked(uuid: String, type: String) {
        Self.logger.info("Item double-clicked: \(uuid) (\(type))")
    }

    func handleFolderToggleCollapse(folderId: String, collapsed: Bool) {
        guard let webView = canvasWebView else { return }
        Self.logger.info("Folder \(folderId) collapsed: \(collapsed)")
        // Toggle visibility of child nodes
        let js = "window.canvasBridge?.toggleFolderCollapse('\(folderId)', \(collapsed))"
        webView.evaluateJavaScript(js) { _, _ in }
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

    private func noteMetadata(for note: Note) -> [String: Any] {
        var meta: [String: Any] = [
            "title": note.title,
            "isPinned": note.isPinned,
        ]

        // Content preview — first ~200 chars, strip markdown
        let content = note.resolvedContent
        let stripped = content
            .replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\*\*|__|\*|_|`"#, with: "", options: .regularExpression)
        let preview = String(stripped.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines)
        meta["preview"] = preview

        // Word count
        let words = content.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        meta["wordCount"] = words.count

        // Relative time
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        meta["timeAgo"] = formatter.localizedString(for: note.modifiedAt, relativeTo: Date())

        // Tags
        if !note.labelIDs.isEmpty {
            let labels = note.labelIDs.compactMap { id in
                CardLabelStorage.shared.labels.first { $0.id == id }
            }
            meta["tags"] = labels.map { ["name": $0.name, "color": $0.colorHex] }
        }

        return meta
    }

    private func todoMetadata(for todo: TodoCard) -> [String: Any] {
        var meta: [String: Any] = [
            "title": todo.title,
            "isCompleted": todo.isCompleted,
        ]

        if let priority = todo.priority {
            meta["priority"] = priority.rawValue
        }

        if let dueDate = todo.dueDate {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .none
            meta["dueDate"] = df.string(from: dueDate)
        }

        // Relative time
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        meta["timeAgo"] = formatter.localizedString(for: todo.createdAt, relativeTo: Date())

        // Checklist progress
        let total = todo.checklist.count
        let done = todo.checklist.filter(\.isCompleted).count
        meta["checklistTotal"] = total
        meta["checklistDone"] = done

        // Tags
        if !todo.labelIDs.isEmpty {
            let labels = todo.labelIDs.compactMap { id in
                CardLabelStorage.shared.labels.first { $0.id == id }
            }
            meta["tags"] = labels.map { ["name": $0.name, "color": $0.colorHex] }
        }

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

            case "folderToggleCollapse":
                if let jsonString = message.body as? String,
                   let data = jsonString.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let folderId = dict["folderId"] as? String,
                   let collapsed = dict["collapsed"] as? Bool {
                    viewModel.handleFolderToggleCollapse(folderId: folderId, collapsed: collapsed)
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
