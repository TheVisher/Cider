import AppKit
import SwiftUI

// MARK: - Screen Capture

extension AppDelegate {

    func startScreenCaptureHotkeyDetection() {
        screenCaptureHotkeyDetector = ScreenCaptureHotkeyDetector()
        screenCaptureHotkeyDetector?.start()
    }

    func observeScreenCaptureNotifications() {
        NotificationCenter.default.publisher(for: .requestScreenCapture)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.performScreenCapture()
                }
            }
            .store(in: &cancellables)
    }

    func performScreenCapture() {
        // Hide the main Cider window so it doesn't appear in the captured region.
        let wasVisible = ciderMainWindow?.isVisible ?? false
        screenCaptureWasVisible = wasVisible
        if wasVisible { hideCiderMainWindow() }

        Task { @MainActor in
            // Small delay to allow the panel to fully hide before capture
            try? await Task.sleep(for: .milliseconds(150))

            let image: NSImage?
            do {
                image = try await ScreenCaptureService.capture()
            } catch ScreenCaptureService.CaptureError.permissionDenied {
                screenCaptureWasVisible = false
                if wasVisible { self.transitionToCiderMainWindow() }
                self.showBookmarkCaptureToast(
                    message: "Enable Screen Recording for Cider in System Settings",
                    isSuccess: false
                )
                return
            } catch {
                screenCaptureWasVisible = false
                if wasVisible { self.transitionToCiderMainWindow() }
                return
            }

            guard let image else {
                // User cancelled — restore the main window immediately.
                screenCaptureWasVisible = false
                if wasVisible { self.transitionToCiderMainWindow() }
                return
            }

            // Give the selection overlay a frame to fully dismiss before anything appears
            try? await Task.sleep(for: .milliseconds(100))

            // Run OCR and routing analysis — Cider stays hidden until toast action or expiry
            let ocrText = await ScreenCaptureService.extractText(from: image)
            let route = ScreenCaptureOCRRouter.detectRoute(in: ocrText ?? "")

            self.showScreenCaptureToast(route: route, image: image, ocrText: ocrText)
        }
    }

    func showScreenCaptureToast(route: CaptureRoute, image: NSImage, ocrText: String?) {
        stopScreenCaptureToastTimer()
        screenCaptureToastIsHovering = false
        let config = CiderConfig.load()
        screenCaptureToastRemaining = TimeInterval(config.screenCaptureToastTimeout > 0
            ? config.screenCaptureToastTimeout
            : Int(ScreenCaptureToastDesign.autoHideDuration))
        screenCaptureToastModel.progress = 1

        if screenCaptureToastPanel == nil {
            screenCaptureToastPanel = ScreenCaptureToastPanel()
        }
        guard let panel = screenCaptureToastPanel else { return }

        let toastView = ScreenCaptureRoutingToastView(
            model: screenCaptureToastModel,
            route: route,
            captureImage: image,
            onHoverChanged: { [weak self] hovering in
                guard let self else { return }
                self.screenCaptureToastIsHovering = hovering
                if hovering {
                    self.stopScreenCaptureToastTimer()
                } else {
                    self.startScreenCaptureToastTimer()
                }
            },
            onCreateNote: { [weak self] in
                self?.dismissScreenCaptureToast()
                if let result = try? CiderCaptureService().addScreenCaptureNoteCapture(
                        title: route.suggestedTitle.isEmpty ? "Screen Capture" : route.suggestedTitle,
                        ocrText: ocrText ?? "",
                        screenshot: image,
                        sourceURL: nil,
                        folderID: nil,
                        sourceContext: CaptureSourceContext(
                            surface: "screen_capture",
                            originalText: ocrText,
                            metadata: [
                                "routeTitle": route.suggestedTitle
                            ]
                        )
                    ) {
                    self?.showBookmarkCaptureToast(
                        receipt: UICaptureReceipt(result: result),
                        successMessage: "Saved screen capture"
                    )
                    self?.transitionToCiderMainWindow()
                } else {
                    self?.showBookmarkCaptureToast(message: "Could not save screen capture", isSuccess: false)
                    let shouldRestorePanel = self?.screenCaptureWasVisible ?? false
                    if shouldRestorePanel { self?.transitionToCiderMainWindow() }
                }
            },
            onCreateDateCard: { [weak self] in
                self?.dismissScreenCaptureToast()
                self?.transitionToCiderMainWindow()
                var info: [String: Any] = ["initialStep": "event"]
                if !route.suggestedTitle.isEmpty { info["suggestedTitle"] = route.suggestedTitle }
                if !route.detectedDates.isEmpty { info["detectedDates"] = route.detectedDates }
                if !route.suggestedLocation.isEmpty { info["suggestedLocation"] = route.suggestedLocation }
                if let ocrText, !ocrText.isEmpty { info["ocrText"] = ocrText }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .openNewItemPopover, object: nil, userInfo: info)
                }
            },
            onCreateContact: { [weak self] in
                self?.dismissScreenCaptureToast()
                self?.transitionToCiderMainWindow()
                var info: [String: Any] = ["initialStep": "contact"]
                if !route.suggestedTitle.isEmpty { info["suggestedTitle"] = route.suggestedTitle }
                if !route.detectedEmails.isEmpty { info["detectedEmails"] = route.detectedEmails }
                if !route.detectedPhones.isEmpty { info["detectedPhones"] = route.detectedPhones }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .openNewItemPopover, object: nil, userInfo: info)
                }
            }
        )

        let hostingView = BookmarkCaptureToastHostingView(rootView: toastView)
        hostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: ScreenCaptureToastDesign.panelWidth,
                         height: ScreenCaptureToastDesign.panelHeight)
        )
        panel.contentView = hostingView
        panel.setContentSize(NSSize(width: ScreenCaptureToastDesign.panelWidth,
                                    height: ScreenCaptureToastDesign.panelHeight))

        let frame = screenCaptureToastFrame()
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()

        startScreenCaptureToastTimer()
    }

    func screenCaptureToastFrame() -> NSRect {
        let w = ScreenCaptureToastDesign.panelWidth
        let h = ScreenCaptureToastDesign.panelHeight
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? .zero
        let x = visibleFrame.midX - w / 2
        let y = visibleFrame.maxY - h - Spacing.xxxl
        return NSRect(x: x, y: y, width: w, height: h)
    }

    func startScreenCaptureToastTimer() {
        stopScreenCaptureToastTimer()
        screenCaptureToastLastTick = Date()

        let timer = Timer(timeInterval: ScreenCaptureToastDesign.progressTickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.screenCaptureToastTimerTick()
            }
        }
        screenCaptureToastTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopScreenCaptureToastTimer() {
        screenCaptureToastTimer?.invalidate()
        screenCaptureToastTimer = nil
        screenCaptureToastLastTick = nil
    }

    func screenCaptureToastTimerTick() {
        guard !screenCaptureToastIsHovering else { return }
        guard let lastTick = screenCaptureToastLastTick else {
            screenCaptureToastLastTick = Date()
            return
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastTick)
        screenCaptureToastLastTick = now
        guard elapsed.isFinite, elapsed > 0 else { return }

        screenCaptureToastRemaining -= elapsed
        let config = CiderConfig.load()
        let duration = max(
            TimeInterval(config.screenCaptureToastTimeout > 0
                ? config.screenCaptureToastTimeout
                : Int(ScreenCaptureToastDesign.autoHideDuration)),
            0.01
        )

        if screenCaptureToastRemaining <= 0 {
            screenCaptureToastModel.progress = 0
            // Execute default action when timer expires
            executeScreenCaptureDefaultAction()
            return
        }

        screenCaptureToastModel.progress = max(0, min(1, screenCaptureToastRemaining / duration))
    }

    func executeScreenCaptureDefaultAction() {
        let shouldRestorePanel = screenCaptureWasVisible
        dismissScreenCaptureToast()
        if shouldRestorePanel { transitionToCiderMainWindow() }
    }

    func dismissScreenCaptureToast() {
        stopScreenCaptureToastTimer()
        screenCaptureToastPanel?.orderOut(nil)
        screenCaptureWasVisible = false
    }
}
