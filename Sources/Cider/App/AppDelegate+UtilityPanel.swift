import AppKit
import Combine
import SwiftUI
import os

private let logger = Logger(subsystem: "com.cider.app", category: "UtilityPanel")

// MARK: - Utility Panel Management

extension AppDelegate {

    func configureUtilityPanel() {
        guard let bookmarksViewModel, let notesViewModel else { return }

        let panel = CiderUtilityPanel()
        self.ciderUtilityPanel = panel

        panel.onNavigateBack = { [weak self] in
            self?.utilityPanelCoordinator.goBack()
        }
        panel.onNavigateForward = { [weak self] in
            self?.utilityPanelCoordinator.goForward()
        }

        let shadowPanel = CiderShadowPanel()
        self.utilityPanelShadowPanel = shadowPanel

        utilityPanelFrameObservation = panel.observe(\.frame, options: [.new]) { [weak self] _, change in
            guard let frame = change.newValue else { return }
            DispatchQueue.main.async { [weak self] in
                self?.utilityPanelShadowPanel?.updateFrame(for: frame)
                self?.persistCurrentUtilityPanelFrameIfNeeded()
            }
        }

        let rootView = UtilityPanelRootView(
            coordinator: utilityPanelCoordinator,
            bookmarksViewModel: bookmarksViewModel,
            notesViewModel: notesViewModel,
            onClose: { [weak self] in self?.hideUtilityPanel() },
            onMaximize: { [weak self] in self?.maximizeUtilityPanel() }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        let hostingView = CiderPanelHostingView(rootView: rootView)
        panel.contentView = hostingView
        panel.installMouseTracking()

        panel.setContentSize(NSSize(
            width: UtilityPanelDesign.panelContentWidth,
            height: UtilityPanelDesign.panelContentHeight
        ))

        // Animate panel width when switching between item/tool modes
        utilityPanelCoordinator.$activeTool
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.animateToPreferredWidth()
            }
            .store(in: &cancellables)

        utilityPanelCoordinator.$activeItem
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in
                guard item != nil else { return }
                self?.animateToPreferredWidth()
            }
            .store(in: &cancellables)

        utilityPanelCoordinator.$splitItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] split in
                guard split != nil else { return }
                self?.animateToPreferredWidth()
            }
            .store(in: &cancellables)
    }

    /// Resizes the panel to the current mode's preferred width, anchoring the left edge.
    private func animateToPreferredWidth() {
        guard let panel = ciderUtilityPanel, panel.isVisible else { return }

        let targetWidth: CGFloat
        if let preferred = utilityPanelCoordinator.preferredWidth {
            // Entering a narrow tool mode — save current width first
            if utilityPanelSavedItemWidth == nil {
                utilityPanelSavedItemWidth = panel.frame.width
            }
            targetWidth = preferred
        } else {
            // Returning to item/search mode — restore saved width
            if let saved = utilityPanelSavedItemWidth {
                targetWidth = saved
                utilityPanelSavedItemWidth = nil
            } else {
                return // No saved width, keep current
            }
        }

        let currentFrame = panel.frame
        guard abs(currentFrame.width - targetWidth) > 2 else {
            utilityPanelSavedItemWidth = nil
            return
        }

        // Decide anchor edge: pin to whichever screen edge the panel is closer to.
        // This keeps the panel stable where the user placed it.
        var newX = currentFrame.origin.x
        let screen = panel.screen ?? NSScreen.main
        if let visibleFrame = screen?.visibleFrame {
            let distToLeft = currentFrame.minX - visibleFrame.minX
            let distToRight = visibleFrame.maxX - currentFrame.maxX
            if distToRight < distToLeft {
                // Closer to right edge — anchor right, grow leftward
                let currentRight = currentFrame.maxX
                newX = max(visibleFrame.minX, currentRight - targetWidth)
            } else {
                // Closer to left edge — anchor left, grow rightward
                let rightEdge = newX + targetWidth
                if rightEdge > visibleFrame.maxX {
                    newX = max(visibleFrame.minX, visibleFrame.maxX - targetWidth)
                }
            }
        }

        let newFrame = NSRect(
            x: newX,
            y: currentFrame.origin.y,
            width: targetWidth,
            height: currentFrame.height
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(newFrame, display: true)
        }

        utilityPanelShadowPanel?.updateFrame(for: newFrame)
    }

    // MARK: - Notifications

    func observeUtilityPanelNotifications() {
        NotificationCenter.default.publisher(for: .toggleUtilityPanel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.toggleUtilityPanel()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .dismissUtilityPanel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.hideUtilityPanel()
            }
            .store(in: &cancellables)

        // Canvas item clicks → open in utility panel
        NotificationCenter.default.publisher(for: .canvasItemSelected)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self else { return }
                guard CiderConfig.load().useNewPanel else { return }
                guard let itemID = notification.userInfo?["bookmarkID"] as? UUID,
                      let type = notification.userInfo?["type"] as? String else { return }

                switch type {
                case "note":
                    let title = NotesStorage.shared.notes.first(where: { $0.id == itemID })?.title ?? "Note"
                    self.utilityPanelCoordinator.openItem(.note(itemID), title: title)
                case "todo":
                    let title = TodoCardStorage.shared.todoCard(for: itemID)?.title ?? "Todo"
                    self.utilityPanelCoordinator.openItem(.todo(itemID), title: title)
                default:
                    let title = VaultBookmarkService.shared.bookmarks.first(where: { $0.id == itemID })?.title ?? "Bookmark"
                    self.utilityPanelCoordinator.openItem(.bookmark(itemID), title: title)
                }

                self.showUtilityPanel()
            }
            .store(in: &cancellables)

        // Direct detail notifications → open in utility panel
        NotificationCenter.default.publisher(for: .openBookmarkDetails)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self, CiderConfig.load().useNewPanel else { return }
                guard let id = notification.userInfo?["bookmarkID"] as? UUID else { return }
                let title = VaultBookmarkService.shared.bookmarks.first(where: { $0.id == id })?.title ?? "Bookmark"
                self.utilityPanelCoordinator.openItem(.bookmark(id), title: title)
                self.showUtilityPanel()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .openNoteDetails)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self, CiderConfig.load().useNewPanel else { return }
                guard let id = notification.userInfo?["noteID"] as? UUID else { return }
                let title = NotesStorage.shared.notes.first(where: { $0.id == id })?.title ?? "Note"
                self.utilityPanelCoordinator.openItem(.note(id), title: title)
                self.showUtilityPanel()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .openTodoDetails)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self, CiderConfig.load().useNewPanel else { return }
                guard let id = notification.userInfo?["todoID"] as? UUID else { return }
                let title = TodoCardStorage.shared.todoCard(for: id)?.title ?? "Todo"
                self.utilityPanelCoordinator.openItem(.todo(id), title: title)
                self.showUtilityPanel()
            }
            .store(in: &cancellables)

        // Search results → open in utility panel
        NotificationCenter.default.publisher(for: .openSearchInPanel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self, CiderConfig.load().useNewPanel else { return }
                let query = notification.userInfo?["query"] as? String ?? ""
                let results = notification.userInfo?["results"] as? [SearchResult] ?? []
                self.utilityPanelCoordinator.openSearchInPanel(query: query, results: results)
                self.showUtilityPanel()
            }
            .store(in: &cancellables)

        // Option+V hotkey → open clipboard in utility panel
        NotificationCenter.default.publisher(for: .toggleClipboardViewer)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, CiderConfig.load().useNewPanel else { return }
                if self.ciderUtilityPanel?.isVisible == true,
                   self.utilityPanelCoordinator.activeTool == .clipboard {
                    self.hideUtilityPanel()
                } else {
                    self.utilityPanelCoordinator.openTool(.clipboard)
                    self.showUtilityPanel()
                }
            }
            .store(in: &cancellables)

        // Option+A hotkey → open AI chat in utility panel
        NotificationCenter.default.publisher(for: .toggleAIAssistantPanel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, CiderConfig.load().useNewPanel else { return }
                if self.ciderUtilityPanel?.isVisible == true,
                   self.utilityPanelCoordinator.activeTool == .aiChat {
                    self.hideUtilityPanel()
                } else {
                    self.utilityPanelCoordinator.openTool(.aiChat)
                    self.showUtilityPanel()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Toggle

    func toggleUtilityPanel() {
        guard let panel = ciderUtilityPanel else { return }

        if panel.isVisible {
            let config = CiderConfig.load()
            if config.openOnMouseScreen {
                let mouseLocation = NSEvent.mouseLocation
                let panelScreen = panel.screen ?? NSScreen.main
                let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
                if let mouseScreen, mouseScreen != panelScreen {
                    persistCurrentUtilityPanelFrameIfNeeded()
                    showUtilityPanel()
                    return
                }
            }
            hideUtilityPanel()
        } else {
            showUtilityPanel()
        }
    }

    // MARK: - Show

    func showUtilityPanel() {
        guard let panel = ciderUtilityPanel else { return }

        if panel.isVisible {
            persistCurrentUtilityPanelFrameIfNeeded()
        }

        let config = CiderConfig.load()
        if config.rememberPanelPosition {
            if config.openOnMouseScreen {
                let mouseLocation = NSEvent.mouseLocation
                let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
                if let savedFrame = utilityPanelPositionStore.frame(for: mouseScreen) {
                    if let mouseScreen,
                       !NSMouseInRect(NSPoint(x: savedFrame.midX, y: savedFrame.midY), mouseScreen.frame, false) {
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
            } else if let savedFrame = utilityPanelPositionStore.frame() {
                panel.show(frame: savedFrame)
            } else {
                panel.showAtMouse()
            }
        } else {
            panel.showAtMouse()
        }

        utilityPanelShadowPanel?.updateFrame(for: panel.frame)
        utilityPanelShadowPanel?.orderFront(nil)
        panel.orderFront(nil)

        logger.debug("Utility panel shown")
    }

    // MARK: - Hide

    func hideUtilityPanel() {
        persistCurrentUtilityPanelFrameIfNeeded()
        utilityPanelShadowPanel?.orderOut(nil)
        ciderUtilityPanel?.orderOut(nil)

        logger.debug("Utility panel hidden")
    }

    // MARK: - Maximize

    func maximizeUtilityPanel() {
        guard let panel = ciderUtilityPanel, panel.isVisible else { return }

        let panelCenter = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(panelCenter) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let visibleFrame = screen.visibleFrame

        // Toggle: if already maximized, restore to default size centered on screen
        let isMaximized = abs(panel.frame.width - visibleFrame.width) < 2
            && abs(panel.frame.height - visibleFrame.height) < 2

        if isMaximized {
            let defaultWidth = UtilityPanelDesign.panelContentWidth
            let defaultHeight = UtilityPanelDesign.panelContentHeight
            let x = visibleFrame.midX - defaultWidth / 2
            let y = visibleFrame.midY - defaultHeight / 2
            panel.setFrame(NSRect(x: x, y: y, width: defaultWidth, height: defaultHeight), display: true)
        } else {
            panel.setFrame(visibleFrame, display: true)
        }

        persistCurrentUtilityPanelFrameIfNeeded()
    }

    // MARK: - Persistence

    func persistCurrentUtilityPanelFrameIfNeeded() {
        guard let panel = ciderUtilityPanel, panel.isVisible else { return }
        // Don't persist a narrow tool-mode width as the saved frame —
        // save the remembered item width instead if we're in a narrow mode
        if utilityPanelCoordinator.preferredWidth != nil, let savedWidth = utilityPanelSavedItemWidth {
            var frame = panel.frame
            frame.size.width = savedWidth
            utilityPanelPositionStore.setFrame(frame)
        } else {
            utilityPanelPositionStore.setFrame(panel.frame)
        }
    }
}
