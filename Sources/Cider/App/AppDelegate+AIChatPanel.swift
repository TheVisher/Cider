import AppKit
import SwiftUI

// MARK: - AI Chat Panel

extension AppDelegate {

    func configureAIChatPanel() {
        let panel = AIChatPanel()
        self.aiChatPanel = panel

        let shadowPanel = CiderShadowPanel()
        self.aiChatShadowPanel = shadowPanel

        aiChatPanelFrameObservation = panel.observe(\.frame, options: [.new]) { [weak self] _, change in
            guard let frame = change.newValue else { return }
            DispatchQueue.main.async { [weak self] in
                self?.aiChatShadowPanel?.updateFrame(for: frame)
            }
        }

        // Host the pure SwiftUI chat view in the floating panel
        let chatView = AIChatView(viewModel: AIChatViewModel.shared, isDocked: false)
        let hostingView = NSHostingView(rootView: chatView)
        hostingView.sizingOptions = []  // Prevent hosting view from auto-resizing the window
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
    }

    func observeAIChatNotifications() {
        NotificationCenter.default.publisher(for: .toggleAIChatPanel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let panel = self.aiChatPanel else { return }
                if panel.isVisible {
                    self.hideAIChatPanel()
                } else {
                    self.showAIChatPanel()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .dismissAIChatPanel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.hideAIChatPanel()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .dockAIChat)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.dockAIChat()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .undockAIChat)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.undockAIChat()
            }
            .store(in: &cancellables)
    }

    func dockAIChat() {
        hideAIChatPanel()
        NotificationCenter.default.post(name: .selectAIChatTab, object: nil)
        var config = CiderConfig.load()
        config.aiChatDocked = true
        config.save()
    }

    func undockAIChat() {
        showAIChatPanel()
        var config = CiderConfig.load()
        config.aiChatDocked = false
        config.save()
    }

    func showAIChatPanel() {
        guard let panel = aiChatPanel else { return }

        let width = AIChatPanelDesign.defaultWidth
        let savedHeight = UserDefaults.standard.double(forKey: "cider.aiChatPanelHeight")
        let preferredHeight = savedHeight >= AIChatPanelDesign.minHeight ? savedHeight : AIChatPanelDesign.defaultHeight

        // Position next to CiderPanel if visible, otherwise at mouse
        let frame: NSRect
        if let ciderFrame = ciderPanel?.frame, ciderPanel?.isVisible == true {
            // Place to the right of the Cider panel
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(ciderFrame.origin) })
                    ?? NSScreen.main ?? NSScreen.screens.first else { return }
            let height = min(preferredHeight, screen.visibleFrame.height - Spacing.lg * 2)

            var x = ciderFrame.maxX + Spacing.sm
            // If it would go off-screen, place to the left instead
            if x + width > screen.visibleFrame.maxX {
                x = ciderFrame.minX - width - Spacing.sm
            }
            // Clamp to screen
            x = max(screen.visibleFrame.minX, min(x, screen.visibleFrame.maxX - width))

            // Align top edge with Cider panel
            let y = max(screen.visibleFrame.minY, ciderFrame.maxY - height)
            frame = NSRect(x: x, y: y, width: width, height: height)
        } else {
            let mouseLocation = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
                    ?? NSScreen.main else { return }
            let height = min(preferredHeight, screen.visibleFrame.height - Spacing.lg * 2)
            let x = max(screen.visibleFrame.minX, min(mouseLocation.x - width / 2, screen.visibleFrame.maxX - width))
            let y = max(screen.visibleFrame.minY, min(mouseLocation.y - height / 2, screen.visibleFrame.maxY - height))
            frame = NSRect(x: x, y: y, width: width, height: height)
        }

        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        aiChatShadowPanel?.updateFrame(for: panel.frame)
        aiChatShadowPanel?.order(.below, relativeTo: panel.windowNumber)
    }

    func hideAIChatPanel() {
        if let panel = aiChatPanel, panel.frame.height >= AIChatPanelDesign.minHeight {
            let previousSaved = UserDefaults.standard.double(forKey: "cider.aiChatPanelHeight")
            let toSave = max(panel.frame.height, previousSaved)
            UserDefaults.standard.set(toSave, forKey: "cider.aiChatPanelHeight")
        }
        aiChatPanel?.orderOut(nil)
        aiChatShadowPanel?.orderOut(nil)
    }
}
