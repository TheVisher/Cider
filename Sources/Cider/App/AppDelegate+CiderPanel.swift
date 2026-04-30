import AppKit
import SwiftUI

// MARK: - Deprecated Full-App Panel Compatibility

extension AppDelegate {
    func configureCiderPanel() {
        // The old full-app NSPanel is intentionally no longer created. The normal
        // app window is the primary workspace; individual surfaces float as panels.
    }

    func updateCiderPanelView() {}

    func observeCiderPanelNotifications() {
        NotificationCenter.default.publisher(for: .toggleCiderPanel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.performCiderActivation()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .dismissCiderPanel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.hideCiderMainWindow()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .toggleCiderPanelCollapse)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.minimizeCiderMainWindow()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .maximizeCiderPanel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.maximizeCiderMainWindow()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .snapCiderPanel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let raw = notification.userInfo?["target"] as? String,
                      let target = SnapTarget(rawValue: raw) else { return }
                self?.snapCiderPanel(to: target)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .toggleNoteEditor)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.transitionToCiderMainWindow()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .captureBookmark)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.captureBookmarkFromHotkey()
            }
            .store(in: &cancellables)
    }

    func toggleCiderPanel() {
        performCiderActivation()
    }

    func showCiderPanel() {
        transitionToCiderMainWindow()
    }

    func hideCiderPanel() {
        hideCiderMainWindow()
    }

    func toggleCiderPanelCollapsed() {
        minimizeCiderMainWindow()
    }

    func maximizeCiderPanel() {
        maximizeCiderMainWindow()
    }

    func expandCiderPanelForSlideOut(minimumWidth: CGFloat) {}

    func restoreCiderPanelAfterSlideOut() {}

    func snapCiderPanel(to target: SnapTarget) {
        guard let window = ciderMainWindow else { return }

        let windowCenter = NSPoint(x: window.frame.midX, y: window.frame.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(windowCenter) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let vf = screen.visibleFrame
        let gap: CGFloat = Spacing.lg
        let minWidth = window.minSize.width

        let targetFrame: NSRect
        switch target {
        case .almostMaximized:
            targetFrame = NSRect(
                x: vf.minX + gap,
                y: vf.minY + gap,
                width: vf.width - gap * 2,
                height: vf.height - gap * 2
            )
        case .leftHalf:
            targetFrame = NSRect(
                x: vf.minX + gap,
                y: vf.minY + gap,
                width: max(minWidth, vf.width / 2 - gap * 2),
                height: vf.height - gap * 2
            )
        case .rightHalf:
            let width = max(minWidth, vf.width / 2 - gap * 2)
            targetFrame = NSRect(
                x: vf.maxX - gap - width,
                y: vf.minY + gap,
                width: width,
                height: vf.height - gap * 2
            )
        case .leftEdge:
            targetFrame = NSRect(
                x: vf.minX + gap,
                y: vf.minY + gap,
                width: minWidth,
                height: vf.height - gap * 2
            )
        case .rightEdge:
            targetFrame = NSRect(
                x: vf.maxX - gap - minWidth,
                y: vf.minY + gap,
                width: minWidth,
                height: vf.height - gap * 2
            )
        }

        window.setFrame(targetFrame, display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    func persistCurrentCiderPanelFrameIfNeeded() {}
}
