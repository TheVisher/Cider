import Combine
import Foundation
import os
import WebKit

/// Custom WKWebView subclass that prevents window dragging.
final class ExcalidrawWebView: WKWebView {
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
final class WhiteboardViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.cider", category: "WhiteboardViewModel")

    private(set) var whiteboardWebView: WKWebView?
    private var coordinator: ExcalidrawCoordinator?

    @Published private(set) var loadedCanvasID: UUID?
    @Published private(set) var isReady = false

    /// Stores the latest scene JSON received from JS — used for flush-saves without JS round-trip.
    private var latestSceneJSON: Data?
    private var saveTask: Task<Void, Never>?

    @discardableResult
    func ensureWebView() -> WKWebView {
        if let existing = whiteboardWebView {
            return existing
        }

        let coord = ExcalidrawCoordinator(viewModel: self)
        coordinator = coord

        let config = WKWebViewConfiguration()
        let contentController = config.userContentController
        contentController.add(coord, name: "excalidrawReady")
        contentController.add(coord, name: "sceneChanged")
        contentController.add(coord, name: "excalidrawError")

        let webView = ExcalidrawWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coord
        webView.setValue(false, forKey: "drawsBackground")

        if let resourceURL = Bundle.main.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "ExcalidrawEditor"
        ) {
            let readAccessRoot = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            webView.loadFileURL(resourceURL, allowingReadAccessTo: readAccessRoot)
        } else {
            Self.logger.error("ExcalidrawEditor/index.html not found in bundle")
        }

        whiteboardWebView = webView
        return webView
    }

    func loadCanvas(_ canvas: WhiteboardCanvas) {
        guard loadedCanvasID != canvas.id else { return }

        // Flush-save the outgoing canvas before switching
        flushSave()

        loadedCanvasID = canvas.id

        guard let sceneData = WhiteboardStorage.shared.loadScene(canvasID: canvas.id) else {
            Self.logger.warning("No scene data for canvas \(canvas.id)")
            return
        }

        guard let jsonString = String(data: sceneData, encoding: .utf8) else { return }
        latestSceneJSON = nil

        if isReady {
            loadSceneIntoWebView(jsonString)
        }
        // If not ready yet, the coordinator will call loadSceneIntoWebView when excalidrawReady fires
    }

    func loadSceneIntoWebView(_ jsonString: String) {
        guard let webView = whiteboardWebView else { return }
        let escaped = jsonString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        webView.evaluateJavaScript("window.excalidrawBridge.loadScene('\(escaped)')") { _, error in
            if let error {
                Self.logger.error("loadScene JS error: \(error)")
            }
        }
    }

    /// Called by the coordinator when scene data changes.
    func handleSceneChanged(_ jsonString: String) {
        latestSceneJSON = Data(jsonString.utf8)
        scheduleDebouncedSave()
    }

    /// Immediately saves any pending scene data to storage.
    func flushSave() {
        saveTask?.cancel()
        saveTask = nil

        guard let canvasID = loadedCanvasID, let data = latestSceneJSON else { return }
        WhiteboardStorage.shared.updateScene(canvasID: canvasID, excalidrawJSON: data)
        latestSceneJSON = nil
    }

    /// Saves current scene by evaluating JS (used when latestSceneJSON might be stale).
    func saveCurrentCanvas() {
        flushSave()
    }

    private func scheduleDebouncedSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.flushSave()
        }
    }

    func markReady() {
        isReady = true
    }

    func setTheme(_ theme: String) {
        guard let webView = whiteboardWebView else { return }
        let safeTheme = theme == "light" ? "light" : "dark"
        webView.evaluateJavaScript("window.excalidrawBridge?.setTheme('\(safeTheme)')") { _, _ in }
    }

    func clearCanvas() {
        loadedCanvasID = nil
        latestSceneJSON = nil
        guard let webView = whiteboardWebView else { return }
        webView.evaluateJavaScript("window.excalidrawBridge?.resetScene()") { _, _ in }
    }
}

// MARK: - Coordinator

final class ExcalidrawCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private static let logger = Logger(subsystem: "com.cider", category: "ExcalidrawCoordinator")
    private weak var viewModel: WhiteboardViewModel?

    init(viewModel: WhiteboardViewModel) {
        self.viewModel = viewModel
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor [weak self] in
            guard let self, let viewModel = self.viewModel else { return }

            switch message.name {
            case "excalidrawReady":
                viewModel.markReady()
                // If a canvas was queued for loading, load it now
                if let canvasID = viewModel.loadedCanvasID,
                   let sceneData = WhiteboardStorage.shared.loadScene(canvasID: canvasID),
                   let jsonString = String(data: sceneData, encoding: .utf8) {
                    viewModel.loadSceneIntoWebView(jsonString)
                }

            case "sceneChanged":
                if let jsonString = message.body as? String {
                    viewModel.handleSceneChanged(jsonString)
                }

            case "excalidrawError":
                if let errorMsg = message.body as? String {
                    Self.logger.error("Excalidraw error: \(errorMsg)")
                }

            default:
                break
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        let scheme = url.scheme ?? ""
        // Allow local file loads and about: pages
        if scheme == "file" || scheme == "about" || scheme == "blob" {
            decisionHandler(.allow)
            return
        }

        // Open external URLs in the user's browser
        if scheme == "http" || scheme == "https" {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }
}
