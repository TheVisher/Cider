import SwiftUI
import WebKit
import Carbon.HIToolbox
import os

// MARK: - TipTapEditorView (container pattern)

/// A thin container that borrows the singleton WKWebView from the ViewModel.
/// Only one surface displays the editor at a time — when a new surface mounts,
/// its `makeNSView` steals the WebView. When a surface is dismantled the WebView
/// becomes parentless and the surviving surface re-adopts it via `updateNSView`.
struct TipTapEditorView: NSViewRepresentable {
    @ObservedObject var viewModel: NotesViewModel

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let webView = viewModel.ensureEditorWebView()
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let webView = viewModel.ensureEditorWebView()
        // Only re-parent if the WebView has no home (its previous container
        // was dismantled). Never steal from another live container.
        if webView.superview == nil {
            webView.frame = container.bounds
            webView.autoresizingMask = [.width, .height]
            container.addSubview(webView)
        }
    }
}

// MARK: - Coordinator

/// Handles WKScriptMessage routing and navigation policy for the editor WebView.
/// Owned by NotesViewModel so it outlives any individual TipTapEditorView mount.
final class TipTapEditorCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let viewModel: NotesViewModel
    private let logger = Logger(subsystem: "com.cider.app", category: "TipTapEditor")

    init(viewModel: NotesViewModel) {
        self.viewModel = viewModel
    }

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        Task { @MainActor [viewModel, logger] in
            switch message.name {
            case "editorReady":
                viewModel.editorDidBecomeReady()

            case "contentChanged":
                if let markdown = message.body as? String {
                    viewModel.contentChanged(markdown)
                }

            case "imageDropped":
                if let jsonString = message.body as? String,
                   let data = jsonString.data(using: .utf8),
                   let payload = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                   let base64 = payload["data"],
                   let name = payload["name"],
                   let imageData = Data(base64Encoded: base64) {
                    viewModel.handleImageDrop(data: imageData, filename: name)
                }

            case "slashCommandImage":
                viewModel.openImagePicker()

            case "slashPopupState":
                if let payload = message.body as? [String: Any],
                   let webView = viewModel.editorWebView as? TipTapWebView {
                    webView.updateSlashPopupState(payload)
                }

            case "editorFormatState":
                if let payload = message.body as? [String: Any] {
                    viewModel.updateEditorFormatState(payload)
                }

            case "editorRequestClose":
                NotificationCenter.default.post(name: .editorRequestClose, object: nil)

            case "linkClicked":
                if let urlString = message.body as? String,
                   let url = URL(string: urlString) {
                    openURLSafely(url)
                }

            case "editorError":
                if let payload = message.body as? [String: Any],
                   let kind = payload["kind"] as? String,
                   let detail = payload["message"] as? String {
                    logger.error("[\(kind, privacy: .public)] \(detail, privacy: .public)")
                } else if let detail = message.body as? String {
                    logger.error("\(detail, privacy: .public)")
                } else {
                    logger.error("Unknown editor diagnostic payload")
                }

            default:
                break
            }
        }
    }

    // Allow only file:// (editor HTML + local images) and about: (initial blank).
    // Everything else is blocked regardless of how the navigation was triggered —
    // only user-clicked links are additionally opened in the system browser.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }

        if url.isFileURL || url.scheme == "about" {
            return .allow
        }

        if navigationAction.navigationType == .linkActivated {
            openURLSafely(url)
        }
        return .cancel
    }
}

// MARK: - Custom WKWebView subclass

/// Prevents window drag when interacting with the editor.
final class TipTapWebView: WKWebView {
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    var onFindRequested: (() -> Void)?
    weak var viewModel: NotesViewModel?

    private let logger = Logger(subsystem: "com.cider.app", category: "TipTapWebView")

    private var slashPopupFrame: CGRect?
    private var slashPopupActive = false
    private var localMouseDownMonitor: Any?
    private var localKeyDownMonitor: Any?

    private static let textFileExtensions: Set<String> = ["md", "markdown", "txt", "text"]

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic"]

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        registerForDraggedTypes([.fileURL, .tiff, .png, .URL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            removeEventMonitors()
        } else {
            installEventMonitorsIfNeeded()
        }
    }

    func updateSlashPopupState(_ payload: [String: Any]) {
        let isActive = payload["active"] as? Bool ?? false
        slashPopupActive = isActive

        guard isActive,
              let left = payload["left"] as? Double,
              let top = payload["top"] as? Double,
              let right = payload["right"] as? Double,
              let bottom = payload["bottom"] as? Double else {
            slashPopupFrame = nil
            return
        }

        slashPopupFrame = CGRect(
            x: left,
            y: top,
            width: max(0, right - left),
            height: max(0, bottom - top)
        )
    }

    // MARK: - Mouse / Key Handling

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        _ = window?.makeFirstResponder(self)

        if handleSlashPopupMouseDown(event) {
            return
        }

        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleFindKeyDown(event) {
            return
        }

        if handleUndoRedoKeyDown(event) {
            return
        }

        if handleSlashPopupKeyDown(event) {
            return
        }

        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self,
           handleFindKeyDown(event) {
            return true
        }

        if window?.firstResponder === self,
           handleUndoRedoKeyDown(event) {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Drag & Drop (UTF-8 text file + web image interception)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasTextFileDrop(sender) || hasWebImageDrop(sender) {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasTextFileDrop(sender) || hasWebImageDrop(sender) {
            return .copy
        }
        return super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let content = readTextFileDrop(sender) {
            Task { @MainActor [weak viewModel] in
                viewModel?.handleDroppedTextFileContent(content)
            }
            return true
        }
        if handleWebImageDrop(sender) {
            return true
        }
        return super.performDragOperation(sender)
    }

    private func hasTextFileDrop(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else {
            return false
        }
        return urls.contains { Self.textFileExtensions.contains($0.pathExtension.lowercased()) }
    }

    private func readTextFileDrop(_ sender: NSDraggingInfo) -> String? {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else {
            return nil
        }
        guard let fileURL = urls.first(where: {
            Self.textFileExtensions.contains($0.pathExtension.lowercased())
        }) else {
            return nil
        }
        return try? String(contentsOf: fileURL, encoding: .utf8)
    }

    // MARK: - Web Image Drag & Drop

    private func hasWebImageDrop(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard

        // Check for image data on the pasteboard
        if pb.data(forType: .tiff) != nil || pb.data(forType: .png) != nil {
            return true
        }

        // Check for image file URLs (not text files — those are handled separately)
        if let urls = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL],
           urls.contains(where: { Self.imageExtensions.contains($0.pathExtension.lowercased()) }) {
            return true
        }

        // Check for web URLs that look like images
        if let urlString = pb.string(forType: .URL) ?? pb.string(forType: .string),
           let url = URL(string: urlString),
           (url.scheme == "http" || url.scheme == "https"),
           Self.imageExtensions.contains(url.pathExtension.lowercased()) {
            return true
        }

        return false
    }

    private func handleWebImageDrop(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard

        // Priority 1: Image data directly on pasteboard (Safari drags)
        if let tiffData = pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiffData),
           let pngData = rep.representation(using: .png, properties: [:]) {
            Task { @MainActor [weak viewModel] in
                viewModel?.handleImageDrop(data: pngData, filename: "dropped-image.png")
            }
            return true
        }

        if let pngData = pb.data(forType: .png) {
            Task { @MainActor [weak viewModel] in
                viewModel?.handleImageDrop(data: pngData, filename: "dropped-image.png")
            }
            return true
        }

        // Priority 2: Local image file URLs
        if let urls = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL],
           let imageURL = urls.first(where: { Self.imageExtensions.contains($0.pathExtension.lowercased()) }),
           let data = try? Data(contentsOf: imageURL) {
            Task { @MainActor [weak viewModel] in
                viewModel?.handleImageDrop(data: data, filename: imageURL.lastPathComponent)
            }
            return true
        }

        // Priority 3: Remote image URLs — download asynchronously
        if let urlString = pb.string(forType: .URL) ?? pb.string(forType: .string),
           let url = URL(string: urlString),
           (url.scheme == "http" || url.scheme == "https"),
           Self.imageExtensions.contains(url.pathExtension.lowercased()) {
            Task { @MainActor [weak viewModel, logger] in
                guard let viewModel else { return }
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    let filename = url.lastPathComponent.isEmpty ? "web-image.png" : url.lastPathComponent
                    viewModel.handleImageDrop(data: data, filename: filename)
                } catch {
                    logger.error("Failed to download web image: \(error.localizedDescription, privacy: .public)")
                }
            }
            return true
        }

        return false
    }

    // MARK: - Slash Popup / Floating Toolbar Hit Testing

    private func handleSlashPopupMouseDown(_ event: NSEvent) -> Bool {
        guard slashPopupActive,
              let slashPopupFrame else {
            return false
        }

        let localPoint = convert(event.locationInWindow, from: nil)
        guard bounds.contains(localPoint) else {
            return false
        }

        // AppKit view coordinates are bottom-left, while DOM client coordinates are top-left.
        let domPoint = CGPoint(x: localPoint.x, y: bounds.height - localPoint.y)
        guard slashPopupFrame.contains(domPoint) else {
            return false
        }

        let js = "window.editorAPI.handleNativeSlashClick(\(domPoint.x), \(domPoint.y));"
        evaluateJavaScript(js, completionHandler: nil)
        return true
    }

    private func handleSlashPopupKeyDown(_ event: NSEvent) -> Bool {
        guard slashPopupActive else {
            return false
        }

        let key: String
        switch Int(event.keyCode) {
        case kVK_DownArrow:
            key = "ArrowDown"
        case kVK_UpArrow:
            key = "ArrowUp"
        case kVK_Return, kVK_ANSI_KeypadEnter:
            key = "Enter"
        case kVK_Escape:
            key = "Escape"
        default:
            return false
        }

        let js = "window.editorAPI.handleNativeSlashKey(\"\(key)\");"
        evaluateJavaScript(js, completionHandler: nil)
        return true
    }

    private func handleUndoRedoKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              !flags.contains(.control),
              !flags.contains(.option) else {
            return false
        }

        let js: String
        switch Int(event.keyCode) {
        case kVK_ANSI_Z:
            js = flags.contains(.shift) ? "window.editorAPI.redo();" : "window.editorAPI.undo();"
        case kVK_ANSI_Y:
            guard !flags.contains(.shift) else { return false }
            js = "window.editorAPI.redo();"
        default:
            return false
        }

        evaluateJavaScript(js, completionHandler: nil)
        return true
    }

    private func handleFindKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              !flags.contains(.control),
              !flags.contains(.option),
              !flags.contains(.shift) else {
            return false
        }

        guard Int(event.keyCode) == kVK_ANSI_F else {
            return false
        }

        onFindRequested?()
        return true
    }

    // MARK: - Event Monitors

    private func installEventMonitorsIfNeeded() {
        if localMouseDownMonitor == nil {
            localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self else { return event }
                guard event.window === self.window else { return event }

                self.window?.makeKey()
                _ = self.window?.makeFirstResponder(self)
                if self.handleSlashPopupMouseDown(event) {
                    return nil
                }

                return event
            }
        }

        if localKeyDownMonitor == nil {
            localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                guard event.window === self.window else { return event }

                if self.handleFindKeyDown(event) {
                    return nil
                }

                if self.handleSlashPopupKeyDown(event) {
                    return nil
                }

                return event
            }
        }
    }

    private func removeEventMonitors() {
        if let localMouseDownMonitor {
            NSEvent.removeMonitor(localMouseDownMonitor)
            self.localMouseDownMonitor = nil
        }

        if let localKeyDownMonitor {
            NSEvent.removeMonitor(localKeyDownMonitor)
            self.localKeyDownMonitor = nil
        }
    }
}
