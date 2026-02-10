import SwiftUI
import WebKit
import Carbon.HIToolbox

struct TipTapEditorView: NSViewRepresentable {
    @ObservedObject var viewModel: NotesViewModel

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = config.userContentController

        // Register message handlers for JS → Swift communication
        let handler = context.coordinator
        contentController.add(handler, name: "contentChanged")
        contentController.add(handler, name: "editorReady")
        contentController.add(handler, name: "imageDropped")
        contentController.add(handler, name: "slashCommandImage")
        contentController.add(handler, name: "slashPopupState")
        contentController.add(handler, name: "floatingToolbarState")
        contentController.add(handler, name: "editorError")

        let webView = TipTapWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        // Load editor.html from the bundled resources
        if let resourceURL = Bundle.module.url(forResource: "editor", withExtension: "html", subdirectory: "TipTapEditor") {
            // Editor content can include local note attachments from arbitrary
            // user directories, so use a broad file read root.
            let readAccessRoot = URL(fileURLWithPath: "/", isDirectory: true)
            webView.loadFileURL(resourceURL, allowingReadAccessTo: readAccessRoot)
        }

        // Store reference on viewModel for Swift → JS calls
        viewModel.editorWebView = webView

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Content updates are pushed via JS bridge, not through SwiftUI updates
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let viewModel: NotesViewModel

        init(viewModel: NotesViewModel) {
            self.viewModel = viewModel
        }

        nonisolated func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            Task { @MainActor [viewModel] in
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

                case "floatingToolbarState":
                    if let payload = message.body as? [String: Any],
                       let webView = viewModel.editorWebView as? TipTapWebView {
                        webView.updateFloatingToolbarState(payload)
                    }

                case "editorError":
                    if let payload = message.body as? [String: Any],
                       let kind = payload["kind"] as? String,
                       let detail = payload["message"] as? String {
                        NSLog("[TipTapEditor][\(kind)] \(detail)")
                    } else if let detail = message.body as? String {
                        NSLog("[TipTapEditor] \(detail)")
                    } else {
                        NSLog("[TipTapEditor] Unknown editor diagnostic payload")
                    }

                default:
                    break
                }
            }
        }

        // Allow file:// URLs for local image loading
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            if let url = navigationAction.request.url {
                if url.isFileURL || url.scheme == "about" {
                    return .allow
                }
                // Block external navigation (links in editor content)
                if navigationAction.navigationType == .linkActivated {
                    NSWorkspace.shared.open(url)
                    return .cancel
                }
            }
            return .allow
        }
    }
}

// MARK: - Custom WKWebView subclass

/// Prevents window drag when interacting with the editor.
private final class TipTapWebView: WKWebView {
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    private var slashPopupFrame: CGRect?
    private var slashPopupActive = false
    private var floatingToolbarFrame: CGRect?
    private var floatingToolbarActive = false
    private var localMouseDownMonitor: Any?
    private var localKeyDownMonitor: Any?

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

    func updateFloatingToolbarState(_ payload: [String: Any]) {
        let isActive = payload["active"] as? Bool ?? false
        floatingToolbarActive = isActive

        guard isActive,
              let left = payload["left"] as? Double,
              let top = payload["top"] as? Double,
              let right = payload["right"] as? Double,
              let bottom = payload["bottom"] as? Double else {
            floatingToolbarFrame = nil
            return
        }

        floatingToolbarFrame = CGRect(
            x: left,
            y: top,
            width: max(0, right - left),
            height: max(0, bottom - top)
        )
    }

    override func mouseDown(with event: NSEvent) {
        _ = window?.makeFirstResponder(self)

        if handleFloatingToolbarMouseDown(event) {
            return
        }

        if handleSlashPopupMouseDown(event) {
            return
        }

        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
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
           handleUndoRedoKeyDown(event) {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

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

    private func handleFloatingToolbarMouseDown(_ event: NSEvent) -> Bool {
        guard floatingToolbarActive,
              let floatingToolbarFrame else {
            return false
        }

        let localPoint = convert(event.locationInWindow, from: nil)
        guard bounds.contains(localPoint) else {
            return false
        }

        let domPoint = CGPoint(x: localPoint.x, y: bounds.height - localPoint.y)
        guard floatingToolbarFrame.contains(domPoint) else {
            return false
        }

        let js = "window.editorAPI.handleNativeFloatingToolbarClick(\(domPoint.x), \(domPoint.y));"
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

    private func installEventMonitorsIfNeeded() {
        if localMouseDownMonitor == nil {
            localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self else { return event }
                guard event.window === self.window else { return event }

                _ = self.window?.makeFirstResponder(self)
                if self.handleFloatingToolbarMouseDown(event) {
                    return nil
                }
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
