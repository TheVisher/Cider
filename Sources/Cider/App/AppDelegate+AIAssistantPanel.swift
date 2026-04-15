import AppKit
import SwiftUI

// MARK: - AI Assistant Panel

extension AppDelegate {

    func startAIAssistantHotkeyDetection() {
        aiAssistantHotkeyDetector = AIAssistantHotkeyDetector()
        aiAssistantHotkeyDetector?.start()
    }

    func configureAIAssistantPanel() {
        let panel = AIAssistantPanel()
        self.aiAssistantPanel = panel

        let shadowPanel = CiderShadowPanel()
        self.aiAssistantShadowPanel = shadowPanel

        aiAssistantPanelFrameObservation = panel.observe(\.frame, options: [.new]) { [weak self] _, change in
            guard let frame = change.newValue else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let panel = self.aiAssistantPanel, panel.isVisible else { return }
                self.aiAssistantShadowPanel?.updateFrame(for: frame)
            }
        }

        let panelView = AIAssistantPanelView(viewModel: AIAssistantViewModel.shared)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        let hostingView = CiderPanelHostingView(rootView: panelView)
        panel.contentView = hostingView
    }

    func observeAIAssistantNotifications() {
        NotificationCenter.default.publisher(for: .toggleAIAssistantPanel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let panel = self.aiAssistantPanel else { return }
                if panel.isVisible {
                    self.hideAIAssistantPanel()
                } else {
                    self.showAIAssistantPanel()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .showAIAssistantPanel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let panel = self.aiAssistantPanel else { return }
                if !panel.isVisible {
                    self.showAIAssistantPanel()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .dismissAIAssistantPanel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.hideAIAssistantPanel()
            }
            .store(in: &cancellables)
    }

    func showAIAssistantPanel() {
        guard let panel = aiAssistantPanel else { return }

        let width = AIAssistantPanelDesign.defaultWidth
        let savedHeight = UserDefaults.standard.double(forKey: "cider.aiAssistantPanelHeight")
        let preferredHeight = savedHeight >= AIAssistantPanelDesign.minHeight
            ? savedHeight : AIAssistantPanelDesign.defaultHeight

        // Try to restore saved position
        let savedX = UserDefaults.standard.double(forKey: "cider.aiAssistantPanelX")
        let savedY = UserDefaults.standard.double(forKey: "cider.aiAssistantPanelY")

        let frame: NSRect
        if savedX != 0 || savedY != 0 {
            // Use saved position
            frame = NSRect(x: savedX, y: savedY, width: width, height: preferredHeight)
        } else {
            // Position near the Cider panel or center of screen
            let mouseLocation = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
                    ?? NSScreen.main else { return }

            let x = screen.visibleFrame.maxX - width - Spacing.lg
            let y = screen.visibleFrame.midY - preferredHeight / 2
            frame = NSRect(x: x, y: y, width: width, height: preferredHeight)
        }

        let clamped = clampedAIAssistantFrame(frame)
        if clamped.origin != frame.origin {
            UserDefaults.standard.set(clamped.origin.x, forKey: "cider.aiAssistantPanelX")
            UserDefaults.standard.set(clamped.origin.y, forKey: "cider.aiAssistantPanelY")
        }

        panel.setFrame(clamped, display: true)
        panel.orderFront(nil)
        panel.makeKey()
        aiAssistantShadowPanel?.updateFrame(for: panel.frame)
        aiAssistantShadowPanel?.order(.below, relativeTo: panel.windowNumber)
    }

    func hideAIAssistantPanel() {
        if let panel = aiAssistantPanel, panel.frame.height >= AIAssistantPanelDesign.minHeight {
            let previousSaved = UserDefaults.standard.double(forKey: "cider.aiAssistantPanelHeight")
            let toSave = max(panel.frame.height, previousSaved)
            UserDefaults.standard.set(toSave, forKey: "cider.aiAssistantPanelHeight")
        }
        aiAssistantPanel?.orderOut(nil)
        aiAssistantShadowPanel?.orderOut(nil)
    }

    private func clampedAIAssistantFrame(_ frame: NSRect) -> NSRect {
        let screen = NSScreen.screens.first(where: {
            $0.visibleFrame.intersects(frame)
        }) ?? NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main

        guard let screen else { return frame }

        let visible = screen.visibleFrame
        let width = min(frame.width, visible.width)
        let height = min(frame.height, visible.height)

        let minX = visible.minX
        let maxX = max(visible.minX, visible.maxX - width)
        let minY = visible.minY
        let maxY = max(visible.minY, visible.maxY - height)

        let x = min(max(frame.origin.x, minX), maxX)
        let y = min(max(frame.origin.y, minY), maxY)

        return NSRect(x: x, y: y, width: width, height: height)
    }
}
