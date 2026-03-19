import AppKit
import SwiftUI

// MARK: - Cider Panel Management

extension AppDelegate {

    func configureCiderPanel() {
        guard bookmarksViewModel != nil, notesViewModel != nil else { return }

        let panel = CiderPanel()
        self.ciderPanel = panel

        let shadowPanel = CiderShadowPanel()
        self.ciderShadowPanel = shadowPanel

        // Keep shadow panel frame in sync with main panel at every step —
        // including during user dragging, programmatic setFrame, and animations.
        panelFrameObservation = panel.observe(\.frame, options: [.new]) { [weak self] _, change in
            guard let frame = change.newValue else { return }
            DispatchQueue.main.async {
                self?.ciderShadowPanel?.updateFrame(for: frame)
            }
        }

        updateCiderPanelView()
    }

    func updateCiderPanelView() {
        guard let panel = ciderPanel,
              let bookmarksViewModel,
              let notesViewModel else { return }

        let panelView = CiderPanelView(
            bookmarksViewModel: bookmarksViewModel,
            notesViewModel: notesViewModel
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        let hostingView = CiderPanelHostingView(rootView: panelView)
        panel.contentView = hostingView

        panel.setContentSize(NSSize(
            width: CiderPanelDesign.panelContentWidth,
            height: CiderPanelDesign.panelContentHeight
        ))
    }

    func observeCiderPanelNotifications() {
        NotificationCenter.default.publisher(for: .toggleCiderPanel)
            .sink { [weak self] _ in
                self?.toggleCiderPanel()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .dismissCiderPanel)
            .sink { [weak self] _ in
                self?.hideCiderPanel()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .toggleCiderPanelCollapse)
            .sink { [weak self] _ in
                self?.toggleCiderPanelCollapsed()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .maximizeCiderPanel)
            .sink { [weak self] _ in
                self?.maximizeCiderPanel()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .snapCiderPanel)
            .sink { [weak self] notification in
                guard let raw = notification.userInfo?["target"] as? String,
                      let target = SnapTarget(rawValue: raw) else { return }
                self?.snapCiderPanel(to: target)
            }
            .store(in: &cancellables)

        // Note editor hotkey — show panel if hidden, CiderPanelView handles the rest
        NotificationCenter.default.publisher(for: .toggleNoteEditor)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.ciderPanel?.isVisible != true {
                    self.showCiderPanel()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .expandCiderPanelForSlideOut)
            .sink { [weak self] notification in
                let minWidth = notification.userInfo?["minimumWidth"] as? CGFloat
                    ?? BookmarksDesign.detailsSlideOutExpandedPanelMinWidth
                self?.expandCiderPanelForSlideOut(minimumWidth: minWidth)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .restoreCiderPanelAfterSlideOut)
            .sink { [weak self] _ in
                self?.restoreCiderPanelAfterSlideOut()
            }
            .store(in: &cancellables)

        // Bookmark capture hotkey
        NotificationCenter.default.publisher(for: .captureBookmark)
            .sink { [weak self] _ in
                self?.captureBookmarkFromHotkey()
            }
            .store(in: &cancellables)
    }

    func toggleCiderPanel() {
        guard let panel = ciderPanel else { return }

        if panel.isVisible {
            let config = CiderConfig.load()
            if config.openOnMouseScreen {
                // If mouse is on a different screen than the panel, move there instead of hiding
                let mouseLocation = NSEvent.mouseLocation
                let panelScreen = panel.screen ?? NSScreen.main
                let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
                if let mouseScreen, mouseScreen != panelScreen {
                    persistCurrentCiderPanelFrameIfNeeded()
                    showCiderPanel()
                    return
                }
            }
            hideCiderPanel()
        } else {
            showCiderPanel()
        }
    }

    func showCiderPanel() {
        guard let panel = ciderPanel else { return }
        if panel.isVisible {
            persistCurrentCiderPanelFrameIfNeeded()
        }

        panel.setCollapsed(false, animated: false)

        let config = CiderConfig.load()
        if config.rememberPanelPosition {
            if config.openOnMouseScreen {
                // Find the screen where the mouse is and use its saved frame
                let mouseLocation = NSEvent.mouseLocation
                let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
                if let savedFrame = ciderPanelPositionStore.frame(for: mouseScreen) {
                    // Check if the saved frame is on the mouse's screen
                    if let mouseScreen,
                       !NSMouseInRect(NSPoint(x: savedFrame.midX, y: savedFrame.midY), mouseScreen.frame, false) {
                        // Saved frame is for a different screen — center on mouse screen
                        let visible = mouseScreen.visibleFrame
                        let x = max(visible.minX, min(mouseLocation.x - savedFrame.width / 2, visible.maxX - savedFrame.width))
                        let y = max(visible.minY, min(mouseLocation.y - savedFrame.height / 2, visible.maxY - savedFrame.height))
                        panel.show(frame: NSRect(x: x, y: y, width: savedFrame.width, height: savedFrame.height))
                    } else {
                        panel.show(frame: savedFrame)
                    }
                } else {
                    panel.showAtMouse()
                }
            } else if let savedFrame = ciderPanelPositionStore.frame() {
                panel.show(frame: savedFrame)
            } else {
                panel.showAtMouse()
            }
        } else {
            panel.showAtMouse()
        }

        // Show shadow behind the main panel.
        ciderShadowPanel?.updateFrame(for: panel.frame)
        ciderShadowPanel?.orderFront(nil)
        panel.orderFront(nil)
    }

    func hideCiderPanel() {
        persistCurrentCiderPanelFrameIfNeeded()
        ciderShadowPanel?.orderOut(nil)
        ciderPanel?.orderOut(nil)
    }

    func toggleCiderPanelCollapsed() {
        guard let panel = ciderPanel, panel.isVisible else { return }
        panel.toggleCollapsed()
        persistCurrentCiderPanelFrameIfNeeded()
    }

    func maximizeCiderPanel() {
        guard let panel = ciderPanel, panel.isVisible else { return }

        if panel.isMaximized, let restoreFrame = panel.frameBeforeMaximize {
            // Restore to previous size
            panel.isMaximized = false
            panel.frameBeforeMaximize = nil
            panel.setCollapsed(false, animated: false)
            panel.setFrame(restoreFrame, display: true)
            persistCurrentCiderPanelFrameIfNeeded()
            return
        }

        // Save current frame for restore
        panel.frameBeforeMaximize = panel.frame

        let panelCenter = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(panelCenter) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let visibleFrame = screen.visibleFrame
        let padding = CiderPanelDesign.shadowPadding

        let maximizedFrame = NSRect(
            x: visibleFrame.minX - padding,
            y: visibleFrame.minY - CiderPanelDesign.bottomPadding - padding,
            width: visibleFrame.width + padding * 2,
            height: visibleFrame.height + CiderPanelDesign.topPadding + CiderPanelDesign.bottomPadding + padding
        )

        panel.setCollapsed(false, animated: false)
        panel.setFrame(maximizedFrame, display: true)
        panel.isMaximized = true
        persistCurrentCiderPanelFrameIfNeeded()
    }

    func expandCiderPanelForSlideOut(minimumWidth: CGFloat) {
        guard let panel = ciderPanel, panel.isVisible else { return }
        guard panel.frame.width < minimumWidth else { return }

        // Save full frame so restore can return to exact position and size
        frameBeforeSlideOut = panel.frame

        let currentFrame = panel.frame
        let delta = minimumWidth - currentFrame.width
        let center = NSPoint(x: currentFrame.midX, y: currentFrame.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(center) })
            ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? currentFrame

        // Anchor the right edge when near screen edge; otherwise expand to the right
        var newOriginX = currentFrame.minX
        if currentFrame.maxX + delta > visibleFrame.maxX {
            newOriginX = max(visibleFrame.minX, currentFrame.maxX - minimumWidth)
        }

        let newFrame = NSRect(
            x: newOriginX,
            y: currentFrame.minY,
            width: minimumWidth,
            height: currentFrame.height
        )
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.setFrame(newFrame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.0, 0.0, 0.2, 1.0)
            panel.animator().setFrame(newFrame, display: true)
        }
    }

    func restoreCiderPanelAfterSlideOut() {
        guard let panel = ciderPanel, let savedFrame = frameBeforeSlideOut else { return }
        frameBeforeSlideOut = nil

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.setFrame(savedFrame, display: true)
            persistCurrentCiderPanelFrameIfNeeded()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.0, 0.0, 0.2, 1.0)
            panel.animator().setFrame(savedFrame, display: true)
        }
        persistCurrentCiderPanelFrameIfNeeded()
    }

    func snapCiderPanel(to target: SnapTarget) {
        guard let panel = ciderPanel, panel.isVisible else { return }

        let panelCenter = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(panelCenter) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let vf = screen.visibleFrame
        let gap: CGFloat = Spacing.lg
        let minW = CiderPanelDesign.panelMinWidth

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
                width: vf.width / 2 - gap * 2,
                height: vf.height - gap * 2
            )
        case .rightHalf:
            targetFrame = NSRect(
                x: vf.midX + gap,
                y: vf.minY + gap,
                width: vf.width / 2 - gap * 2,
                height: vf.height - gap * 2
            )
        case .leftEdge:
            targetFrame = NSRect(
                x: vf.minX + gap,
                y: vf.minY + gap,
                width: minW,
                height: vf.height - gap * 2
            )
        case .rightEdge:
            targetFrame = NSRect(
                x: vf.maxX - gap - minW,
                y: vf.minY + gap,
                width: minW,
                height: vf.height - gap * 2
            )
        }

        panel.isMaximized = false
        panel.frameBeforeMaximize = nil
        panel.setCollapsed(false, animated: false)
        panel.setFrame(targetFrame, display: true)
        persistCurrentCiderPanelFrameIfNeeded()
    }

    func persistCurrentCiderPanelFrameIfNeeded() {
        guard let panel = ciderPanel, panel.isVisible else { return }
        ciderPanelPositionStore.setFrame(panel.persistableFrame)
    }
}
