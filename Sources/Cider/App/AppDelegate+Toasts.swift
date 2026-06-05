import AppKit
import SwiftUI

// MARK: - Undo Toast & Bookmark Capture/Review Toasts

extension AppDelegate {

    func observeUndoNotifications() {
        NotificationCenter.default.publisher(for: .showUndoToast)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                let message = notification.userInfo?["message"] as? String ?? ""
                let showViewTrash = notification.userInfo?["showViewTrash"] as? Bool ?? false
                self?.showUndoToast(message: message, showViewTrash: showViewTrash)
            }
            .store(in: &cancellables)
    }

    func showUndoToast(message: String, showViewTrash: Bool) {
        CiderSoundEffect.trash.play()
        stopUndoToastTimer()
        undoToastIsHovering = false
        undoToastRemaining = UndoToastDesign.autoHideDuration
        undoToastModel.progress = 1

        if undoToastPanel == nil {
            undoToastPanel = BookmarkCaptureToastPanel()
        }
        guard let panel = undoToastPanel else { return }

        let toastView = UndoToastView(
            model: undoToastModel,
            message: message,
            showViewTrash: showViewTrash,
            onUndo: { [weak self] in
                CiderUndoManager.shared.undo()
                self?.dismissUndoToast()
            },
            onViewTrash: { [weak self] in
                self?.dismissUndoToast()
                NotificationCenter.default.post(name: .openCiderSettings, object: nil,
                    userInfo: ["category": "data", "subcategory": "trash"])
            },
            onHoverChanged: { [weak self] hovering in
                guard let self else { return }
                if hovering {
                    self.undoToastIsHovering = true
                    self.stopUndoToastTimer()
                } else {
                    self.undoToastIsHovering = false
                    self.startUndoToastTimer()
                }
            }
        )
        let hostingView = BookmarkCaptureToastHostingView(rootView: toastView)
        hostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: UndoToastDesign.panelWidth, height: UndoToastDesign.panelHeight)
        )
        panel.contentView = hostingView
        panel.setContentSize(NSSize(width: UndoToastDesign.panelWidth, height: UndoToastDesign.panelHeight))

        let frame = undoToastFrame(position: CiderConfig.load().undoToastPosition)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()

        startUndoToastTimer()
    }

    func undoToastFrame(position: ToastPosition) -> NSRect {
        let w = UndoToastDesign.panelWidth
        let h = UndoToastDesign.panelHeight
        let inset = UndoToastDesign.panelEdgeInset

        switch position {
        case .topCenterScreen:
            let mouseLocation = NSEvent.mouseLocation
            let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
                ?? NSScreen.main ?? NSScreen.screens.first
            let visibleFrame = screen?.visibleFrame ?? .zero
            let x = visibleFrame.midX - w / 2
            let y = visibleFrame.maxY - h - Spacing.xxxl
            return NSRect(x: x, y: y, width: w, height: h)

        case .bottomRightPanel:
            guard let panelFrame = ciderWorkspaceAnchorFrame() else { return .zero }
            let x = panelFrame.maxX - w - inset
            let y = panelFrame.minY + inset
            return NSRect(x: x, y: y, width: w, height: h)

        case .bottomLeftPanel:
            guard let panelFrame = ciderWorkspaceAnchorFrame() else { return .zero }
            let x = panelFrame.minX + inset
            let y = panelFrame.minY + inset
            return NSRect(x: x, y: y, width: w, height: h)

        case .topRightPanel:
            guard let panelFrame = ciderWorkspaceAnchorFrame() else { return .zero }
            let x = panelFrame.maxX - w - inset
            let y = panelFrame.maxY - h - inset
            return NSRect(x: x, y: y, width: w, height: h)

        case .topLeftPanel:
            guard let panelFrame = ciderWorkspaceAnchorFrame() else { return .zero }
            let x = panelFrame.minX + inset
            let y = panelFrame.maxY - h - inset
            return NSRect(x: x, y: y, width: w, height: h)
        }
    }

    func startUndoToastTimer() {
        stopUndoToastTimer()
        undoToastLastTick = Date()

        let timer = Timer(timeInterval: BookmarksToastDesign.reviewProgressTickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.undoToastTimerTick()
            }
        }
        undoToastTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopUndoToastTimer() {
        undoToastTimer?.invalidate()
        undoToastTimer = nil
        undoToastLastTick = nil
    }

    func undoToastTimerTick() {
        guard !undoToastIsHovering else { return }
        guard let lastTick = undoToastLastTick else {
            undoToastLastTick = Date()
            return
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastTick)
        undoToastLastTick = now
        guard elapsed.isFinite, elapsed > 0 else { return }

        undoToastRemaining -= elapsed
        let duration = max(UndoToastDesign.autoHideDuration, 0.01)

        if undoToastRemaining <= 0 {
            undoToastModel.progress = 0
            dismissUndoToast()
            return
        }

        undoToastModel.progress = max(0, min(1, undoToastRemaining / duration))
    }

    func dismissUndoToast() {
        stopUndoToastTimer()
        undoToastPanel?.orderOut(nil)
        CiderUndoManager.shared.discard()
    }

    // MARK: - Bookmark Capture Toast

    func showBookmarkCaptureToast(message: String, isSuccess: Bool) {
        showBookmarkCaptureToast(content: BookmarkCaptureToastContent(message: message, isSuccess: isSuccess))
    }

    func showBookmarkCaptureToast(receipt: UICaptureReceipt, successMessage: String) {
        showBookmarkCaptureToast(content: BookmarkCaptureToastContent(receipt: receipt, successMessage: successMessage))
    }

    private func showBookmarkCaptureToast(content: BookmarkCaptureToastContent) {
        if content.isSuccess { CiderSoundEffect.save.play() }
        stopBookmarkClipboardReviewTimer()
        bookmarkClipboardReviewIsHovering = false
        bookmarkClipboardReviewToastModel.progress = 1
        bookmarkCaptureToastHideWorkItem?.cancel()
        bookmarkCaptureToastHideWorkItem = nil

        let panel = resolveBookmarkCaptureToastPanel()

        let toastView = BookmarkCaptureToastView(content: content)
        let hostingView = BookmarkCaptureToastHostingView(rootView: toastView)
        panel.contentView = hostingView
        showBookmarkToastPanel(panel, contentHeight: content.contentHeight)

        let hideWork = DispatchWorkItem { [weak self, weak panel] in
            panel?.orderOut(nil)
            self?.bookmarkCaptureToastHideWorkItem = nil
        }
        bookmarkCaptureToastHideWorkItem = hideWork
        DispatchQueue.main.asyncAfter(deadline: .now() + BookmarksToastDesign.autoHideDuration, execute: hideWork)
    }

    func showImageClipboardReviewToast() {
        CiderSoundEffect.clipboardReview.play()
        stopBookmarkClipboardReviewTimer()
        bookmarkClipboardReviewIsHovering = false
        bookmarkClipboardReviewRemaining = BookmarksToastDesign.reviewAutoHideDuration
        bookmarkClipboardReviewToastModel.progress = 1
        bookmarkCaptureToastHideWorkItem?.cancel()
        bookmarkCaptureToastHideWorkItem = nil

        let panel = resolveBookmarkCaptureToastPanel()
        let toastView = ImageClipboardReviewToastView(
            model: bookmarkClipboardReviewToastModel,
            onHoverChanged: { [weak self] hovering in
                self?.handleBookmarkClipboardReviewHoverChange(hovering)
            },
            onSave: { [weak self] in
                guard let self else { return }
                guard let imageData = BookmarksClipboardMonitor.readImageFromClipboard() else {
                    self.showBookmarkCaptureToast(message: "Image no longer on clipboard", isSuccess: false)
                    return
                }
                // Suspend monitor so the same clipboard image isn't re-detected
                BookmarksClipboardMonitor.shared.suspendFor(seconds: 3)
                // Try to get context from the frontmost browser (page title + URL)
                let browserCapture = ActiveBrowserCaptureService.captureFromFrontmostBrowser()
                let title = browserCapture?.title ?? "Saved Image"
                let sourceContext = CaptureSourceContext(
                    surface: "clipboard_image_review",
                    channel: "pasteboard",
                    attachments: [
                        CaptureSourceContext.Attachment(
                            mimeType: "image/*"
                        )
                    ],
                    metadata: [
                        "browser_title": browserCapture?.title ?? "",
                        "browser_url": browserCapture?.urlString ?? "",
                    ].filter { !$0.value.isEmpty }
                )
                guard let result = try? CiderCaptureService().addImageBookmarkCapture(
                    title: title,
                    imageData: imageData,
                    preferredFileExtension: nil,
                    sourceFile: nil,
                    sourceContext: sourceContext
                ) else {
                    self.showBookmarkCaptureToast(message: "Could not save copied image", isSuccess: false)
                    return
                }
                if let urlString = browserCapture?.urlString {
                    VaultBookmarkService.shared.updateURL(for: result.item.id, urlString: urlString)
                }
                let receipt = CaptureReceipt(result: result)
                self.showBookmarkCaptureToast(
                    message: receipt.toastMessage(success: "Saved copied image"),
                    isSuccess: receipt.isSuccess
                )
            },
            onDiscard: { [weak self] in
                BookmarksClipboardMonitor.shared.suspendFor(seconds: 3)
                self?.dismissBookmarkCaptureToast()
            }
        )
        let hostingView = BookmarkCaptureToastHostingView(rootView: toastView)
        panel.contentView = hostingView
        showBookmarkToastPanel(panel, contentHeight: BookmarksToastDesign.reviewHeight)
        startBookmarkClipboardReviewTimer(resetToFull: true)
    }

    func showBookmarkClipboardReviewToast(urlString: String) {
        CiderSoundEffect.clipboardReview.play()
        stopBookmarkClipboardReviewTimer()
        bookmarkClipboardReviewIsHovering = false
        bookmarkClipboardReviewRemaining = BookmarksToastDesign.reviewAutoHideDuration
        bookmarkClipboardReviewToastModel.progress = 1
        bookmarkCaptureToastHideWorkItem?.cancel()
        bookmarkCaptureToastHideWorkItem = nil

        guard let normalized = VaultBookmarkService.shared.previewNormalizedURLString(from: urlString),
              let url = URL(string: normalized) else {
            return
        }

        let panel = resolveBookmarkCaptureToastPanel()
        let urlDisplay = compactURLDisplay(from: url)
        let toastView = BookmarkClipboardReviewToastView(
            model: bookmarkClipboardReviewToastModel,
            urlDisplay: urlDisplay,
            onHoverChanged: { [weak self] hovering in
                self?.handleBookmarkClipboardReviewHoverChange(hovering)
            },
            onSave: { [weak self] in
                guard let self else { return }
                let receipt: CaptureReceipt
                if let result = try? CiderBookmarkCaptureAdapter().addURLBookmark(
                    urlString: normalized,
                    sourceContext: CaptureSourceContext(
                        surface: "clipboard_review_toast",
                        channel: "pasteboard",
                        originalText: normalized
                    )
                ) {
                    receipt = CaptureReceipt(result: result.captureResult)
                } else {
                    receipt = .failed("Could not save copied URL")
                }
                self.showBookmarkCaptureToast(
                    message: receipt.toastMessage(success: "Saved copied URL"),
                    isSuccess: receipt.isSuccess
                )
            },
            onDiscard: { [weak self] in
                self?.dismissBookmarkCaptureToast()
            }
        )
        let hostingView = BookmarkCaptureToastHostingView(rootView: toastView)
        panel.contentView = hostingView
        showBookmarkToastPanel(panel, contentHeight: BookmarksToastDesign.reviewHeight)
        startBookmarkClipboardReviewTimer(resetToFull: true)
    }

    func dismissBookmarkCaptureToast() {
        stopBookmarkClipboardReviewTimer()
        bookmarkClipboardReviewIsHovering = false
        bookmarkClipboardReviewToastModel.progress = 1
        bookmarkCaptureToastHideWorkItem?.cancel()
        bookmarkCaptureToastHideWorkItem = nil
        bookmarkCaptureToastPanel?.orderOut(nil)
    }

    func handleBookmarkClipboardReviewHoverChange(_ hovering: Bool) {
        guard bookmarkClipboardReviewIsHovering != hovering else { return }
        bookmarkClipboardReviewIsHovering = hovering

        if hovering {
            bookmarkClipboardReviewRemaining = BookmarksToastDesign.reviewAutoHideDuration
            bookmarkClipboardReviewToastModel.progress = 1
            stopBookmarkClipboardReviewTimer()
        } else {
            startBookmarkClipboardReviewTimer(resetToFull: true)
        }
    }

    func startBookmarkClipboardReviewTimer(resetToFull: Bool) {
        stopBookmarkClipboardReviewTimer()

        if resetToFull {
            bookmarkClipboardReviewRemaining = BookmarksToastDesign.reviewAutoHideDuration
            bookmarkClipboardReviewToastModel.progress = 1
        }
        bookmarkClipboardReviewLastTick = Date()

        let timer = Timer(timeInterval: BookmarksToastDesign.reviewProgressTickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.bookmarkClipboardReviewTimerTick()
            }
        }
        bookmarkClipboardReviewTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopBookmarkClipboardReviewTimer() {
        bookmarkClipboardReviewTimer?.invalidate()
        bookmarkClipboardReviewTimer = nil
        bookmarkClipboardReviewLastTick = nil
    }

    func bookmarkClipboardReviewTimerTick() {
        guard !bookmarkClipboardReviewIsHovering else { return }
        guard let lastTick = bookmarkClipboardReviewLastTick else {
            bookmarkClipboardReviewLastTick = Date()
            return
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastTick)
        bookmarkClipboardReviewLastTick = now
        guard elapsed.isFinite, elapsed > 0 else { return }

        bookmarkClipboardReviewRemaining -= elapsed
        let duration = max(BookmarksToastDesign.reviewAutoHideDuration, 0.01)

        if bookmarkClipboardReviewRemaining <= 0 {
            bookmarkClipboardReviewToastModel.progress = 0
            BookmarksClipboardMonitor.shared.suspendFor(seconds: 3)
            dismissBookmarkCaptureToast()
            return
        }

        bookmarkClipboardReviewToastModel.progress = max(0, min(1, bookmarkClipboardReviewRemaining / duration))
    }

    func resolveBookmarkCaptureToastPanel() -> BookmarkCaptureToastPanel {
        if let existingPanel = bookmarkCaptureToastPanel {
            return existingPanel
        }

        let newPanel = BookmarkCaptureToastPanel()
        bookmarkCaptureToastPanel = newPanel
        return newPanel
    }

    func showBookmarkToastPanel(_ panel: BookmarkCaptureToastPanel, contentHeight: CGFloat) {
        let panelWidth = BookmarksToastDesign.panelWidth
        let panelHeight = contentHeight + BookmarksToastDesign.shadowPadding * 2
        panel.setContentSize(NSSize(width: panelWidth, height: panelHeight))

        let position = CiderConfig.load().captureToastPosition
        let frame = captureToastFrame(position: position, panelWidth: panelWidth, panelHeight: panelHeight)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func captureToastFrame(position: ToastPosition, panelWidth: CGFloat, panelHeight: CGFloat) -> NSRect {
        let inset = UndoToastDesign.panelEdgeInset
        switch position {
        case .topCenterScreen:
            let mouseLocation = NSEvent.mouseLocation
            let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
                ?? NSScreen.main ?? NSScreen.screens.first
            let visibleFrame = screen?.visibleFrame ?? .zero
            let x = visibleFrame.midX - panelWidth / 2
            let y = visibleFrame.maxY - panelHeight - BookmarksToastDesign.topInset
            return NSRect(x: x, y: y, width: panelWidth, height: panelHeight)

        case .bottomRightPanel:
            guard let panelFrame = ciderWorkspaceAnchorFrame() else { return .zero }
            return NSRect(x: panelFrame.maxX - panelWidth - inset, y: panelFrame.minY + inset,
                          width: panelWidth, height: panelHeight)

        case .bottomLeftPanel:
            guard let panelFrame = ciderWorkspaceAnchorFrame() else { return .zero }
            return NSRect(x: panelFrame.minX + inset, y: panelFrame.minY + inset,
                          width: panelWidth, height: panelHeight)

        case .topRightPanel:
            guard let panelFrame = ciderWorkspaceAnchorFrame() else { return .zero }
            return NSRect(x: panelFrame.maxX - panelWidth - inset, y: panelFrame.maxY - panelHeight - inset,
                          width: panelWidth, height: panelHeight)

        case .topLeftPanel:
            guard let panelFrame = ciderWorkspaceAnchorFrame() else { return .zero }
            return NSRect(x: panelFrame.minX + inset, y: panelFrame.maxY - panelHeight - inset,
                          width: panelWidth, height: panelHeight)
        }
    }

    private func ciderWorkspaceAnchorFrame() -> NSRect? {
        if let frame = ciderMainWindow?.frame {
            return frame
        }

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        return screen?.visibleFrame
    }

    func compactURLDisplay(from url: URL) -> String {
        let host = url.host ?? url.absoluteString
        let path = url.path.isEmpty ? "" : url.path
        let query = url.query.map { "?\($0)" } ?? ""
        let compact = "\(host)\(path)\(query)"
        return compact.count > 72 ? "\(compact.prefix(69))..." : compact
    }
}
