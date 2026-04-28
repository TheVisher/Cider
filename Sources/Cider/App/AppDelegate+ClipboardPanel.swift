import AppKit
import SwiftUI

// MARK: - Clipboard Panel

private enum ClipboardFloatRequest {
    static let notificationName = Notification.Name.floatCiderSurface

    static func matches(_ notification: Notification) -> Bool {
        if matchesPayload(notification.object) {
            return true
        }

        return matchesPayload(notification.userInfo?["surface"])
            || matchesPayload(notification.userInfo?["ciderSurface"])
            || matchesPayload(notification.userInfo?["floatableSurface"])
    }

    private static func matchesPayload(_ payload: Any?) -> Bool {
        guard let payload else { return false }

        if let string = payload as? String {
            return normalized(string) == "clipboard"
        }

        return normalized(String(describing: payload)) == "clipboard"
    }

    private static func normalized(_ value: String) -> String {
        let lastComponent = value.split(separator: ".").last.map(String.init) ?? value
        return lastComponent
            .filter { $0.isLetter || $0.isNumber }
            .lowercased()
    }
}

extension AppDelegate {

    func startClipboardHotkeyDetection() {
        let config = CiderConfig.load()
        guard config.enableClipboardHotkey else { return }
        clipboardHotkeyDetector = ClipboardHotkeyDetector()
        clipboardHotkeyDetector?.start()
    }

    func configureClipboardHistory() {
        let config = CiderConfig.load()
        ClipboardHistoryService.shared.setEnabled(config.enableClipboardHistory)
    }

    func configureClipboardPanel() {
        let panel = ClipboardPanel()
        self.clipboardPanel = panel

        let shadowPanel = CiderShadowPanel()
        self.clipboardShadowPanel = shadowPanel

        clipboardPanelFrameObservation = panel.observe(\.frame, options: [.new]) { [weak self] _, change in
            guard let frame = change.newValue else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let panel = self.clipboardPanel, panel.isVisible else { return }
                self.clipboardShadowPanel?.updateFrame(for: frame)
            }
        }

        let panelView = ClipboardPanelView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        let hostingView = CiderPanelHostingView(rootView: panelView)
        panel.contentView = hostingView
    }

    func observeClipboardViewerNotifications() {
        NotificationCenter.default.publisher(for: .toggleClipboardViewer)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let panel = self.clipboardPanel else { return }
                if panel.isVisible {
                    self.hideClipboardPanel()
                } else {
                    self.showClipboardPanel()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .dismissClipboardPanel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.hideClipboardPanel()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: ClipboardFloatRequest.notificationName)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard ClipboardFloatRequest.matches(notification) else { return }
                self?.showClipboardPanel()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .toggleClipboardPanelWidth)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.toggleClipboardPanelWidth()
            }
            .store(in: &cancellables)
    }

    func showClipboardPanel() {
        guard let panel = clipboardPanel else { return }

        let config = CiderConfig.load()
        let isWide = UserDefaults.standard.bool(forKey: "cider.clipboardWideMode")
        let targetWidth = isWide ? ClipboardPanelDesign.wideWidth : ClipboardPanelDesign.narrowWidth

        // Lock width constraints for current mode
        panel.minSize = NSSize(width: targetWidth, height: ClipboardPanelDesign.minHeight)
        panel.maxSize = NSSize(width: targetWidth, height: .greatestFiniteMagnitude)

        let width = targetWidth
        let savedHeight = UserDefaults.standard.double(forKey: "cider.clipboardPanelHeight")
        let preferredHeight = savedHeight >= ClipboardPanelDesign.minHeight ? savedHeight : ClipboardPanelDesign.defaultHeight

        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
                ?? NSScreen.main else { return }

        // Clamp height to fit the target screen (with padding)
        let height = min(preferredHeight, screen.visibleFrame.height - Spacing.lg * 2)

        let frame: NSRect
        switch config.clipboardPanelPosition {
        case .followMouse:
            let x = max(screen.visibleFrame.minX, min(mouseLocation.x - width / 2, screen.visibleFrame.maxX - width))
            let y = max(screen.visibleFrame.minY, min(mouseLocation.y - height / 2, screen.visibleFrame.maxY - height))
            frame = NSRect(x: x, y: y, width: width, height: height)
        case .leftEdge:
            let x = screen.visibleFrame.minX + Spacing.md
            let y = screen.visibleFrame.midY - height / 2
            frame = NSRect(x: x, y: y, width: width, height: height)
        case .rightEdge:
            let x = screen.visibleFrame.maxX - width - Spacing.md
            let y = screen.visibleFrame.midY - height / 2
            frame = NSRect(x: x, y: y, width: width, height: height)
        }

        panel.setFrame(frame, display: true)
        // Order main panel first, then shadow behind it — avoids flash of shadow-only
        panel.orderFront(nil)
        panel.makeKey()
        clipboardShadowPanel?.updateFrame(for: panel.frame)
        clipboardShadowPanel?.order(.below, relativeTo: panel.windowNumber)
    }

    func hideClipboardPanel() {
        if let panel = clipboardPanel, panel.frame.height >= ClipboardPanelDesign.minHeight {
            // Save the larger of current frame and previously saved height,
            // so clamping on a smaller screen doesn't shrink the preference.
            let previousSaved = UserDefaults.standard.double(forKey: "cider.clipboardPanelHeight")
            let toSave = max(panel.frame.height, previousSaved)
            UserDefaults.standard.set(toSave, forKey: "cider.clipboardPanelHeight")
        }
        // Order both out together to prevent ghost shadow
        clipboardPanel?.orderOut(nil)
        clipboardShadowPanel?.orderOut(nil)
    }

    func toggleClipboardPanelWidth() {
        guard let panel = clipboardPanel else { return }

        let isWide = UserDefaults.standard.bool(forKey: "cider.clipboardWideMode")
        let targetWidth = isWide ? ClipboardPanelDesign.wideWidth : ClipboardPanelDesign.narrowWidth

        // Temporarily relax constraints so animation can interpolate
        let flexMin = min(ClipboardPanelDesign.narrowWidth, ClipboardPanelDesign.wideWidth)
        let flexMax = max(ClipboardPanelDesign.narrowWidth, ClipboardPanelDesign.wideWidth)
        panel.minSize = NSSize(width: flexMin, height: ClipboardPanelDesign.minHeight)
        panel.maxSize = NSSize(width: flexMax, height: .greatestFiniteMagnitude)

        // Calculate new frame
        var newFrame = panel.frame
        let isExpanding = targetWidth > panel.frame.width

        if let screen = panel.screen ?? NSScreen.main {
            if isExpanding {
                let widthDelta = targetWidth - panel.frame.width
                if panel.frame.maxX + widthDelta <= screen.visibleFrame.maxX {
                    // Room to expand right — keep left edge
                    newFrame.size.width = targetWidth
                } else {
                    // Expand left — keep right edge
                    newFrame.origin.x = max(screen.visibleFrame.minX, panel.frame.maxX - targetWidth)
                    newFrame.size.width = targetWidth
                }
            } else {
                // Collapsing — anchor to whichever screen edge is closer
                let distToRight = screen.visibleFrame.maxX - panel.frame.maxX
                let distToLeft = panel.frame.minX - screen.visibleFrame.minX

                if distToRight < distToLeft {
                    // Closer to right edge — keep right edge fixed
                    newFrame.origin.x = panel.frame.maxX - targetWidth
                }
                // Else: closer to left — keep left edge (origin stays)
                newFrame.size.width = targetWidth
            }
        } else {
            newFrame.size.width = targetWidth
        }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            panel.setFrame(newFrame, display: true)
            panel.minSize = NSSize(width: targetWidth, height: ClipboardPanelDesign.minHeight)
            panel.maxSize = NSSize(width: targetWidth, height: .greatestFiniteMagnitude)
        } else {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.0, 0.0, 0.2, 1.0)
                panel.animator().setFrame(newFrame, display: true)
            }, completionHandler: { [weak panel] in
                // NSAnimationContext completion always fires on main; assumeIsolated is safe here.
                MainActor.assumeIsolated {
                    guard let panel else { return }
                    panel.minSize = NSSize(width: targetWidth, height: ClipboardPanelDesign.minHeight)
                    panel.maxSize = NSSize(width: targetWidth, height: .greatestFiniteMagnitude)
                }
            })
        }
    }
}
