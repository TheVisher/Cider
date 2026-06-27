import AppKit
import SwiftUI

// MARK: - Cider Main Window Management

extension AppDelegate {
    func configureCiderMainWindow() {
        guard bookmarksViewModel != nil, notesViewModel != nil else { return }

        if CiderMainWindowChromePolicy.usesQAVisibleWindowChrome(
            environment: ProcessInfo.processInfo.environment
        ) {
            qaCiderMainWindow = makeQACiderMainWindow()
        } else {
            let window = CiderMainWindow()
            ciderMainWindow = window
        }
        updateCiderMainWindowView()
    }

    func updateCiderMainWindowView() {
        guard let bookmarksViewModel,
              let notesViewModel else { return }

        let windowView = CiderPanelView(
            bookmarksViewModel: bookmarksViewModel,
            notesViewModel: notesViewModel,
            surface: .mainWindow
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        if let qaCiderMainWindow {
            qaCiderMainWindow.contentView = NSHostingView(rootView: windowView)
        } else {
            ciderMainWindow?.contentView = CiderMainWindowHostingView(rootView: windowView)
        }
    }

    func observeCiderMainWindowNotifications() {
        NotificationCenter.default.publisher(for: .openCiderMainWindow)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.transitionToCiderMainWindow()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .dismissCiderMainWindow)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.hideCiderMainWindow()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .minimizeCiderMainWindow)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.minimizeCiderMainWindow()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .maximizeCiderMainWindow)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.maximizeCiderMainWindow()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .reanchorCiderSurface)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let surface = CiderFloatingPanelManager.SurfaceNotificationPayload.surface(from: notification) else {
                    return
                }

                self.transitionToCiderMainWindow()
                self.floatingPanelManager?.dock(surface)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .openCiderSurfaceInMainWindow,
                        object: surface,
                        userInfo: [CiderFloatingPanelManager.surfaceUserInfoKey: surface]
                    )
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .openCiderLibraryHubNavigationTargetInMainWindow)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard LibraryHubNavigationRequest.target(from: notification) != nil else { return }
                self?.transitionToCiderMainWindow()
            }
            .store(in: &cancellables)
    }

    func observeExternalOpenRequests() {
        externalOpenObserver = CiderExternalOpenBridge.startForwardingToLocalNotificationCenter()
        NotificationCenter.default.publisher(for: .openCiderExternalTarget)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.transitionToCiderMainWindow()
            }
            .store(in: &cancellables)
    }

    @objc func openCiderMainWindowFromMenu() {
        transitionToCiderMainWindow()
    }

    func transitionToCiderMainWindow() {
        apply(CiderSurfaceTransitionPolicy.transitionToMainWindow())
    }

    func showCiderMainWindow() {
        if let qaCiderMainWindow {
            showQACiderMainWindow(qaCiderMainWindow)
        } else {
            guard let window = ciderMainWindow else { return }
            window.showCentered()
        }
    }

    func hideCiderMainWindow() {
        qaCiderMainWindow?.orderOut(nil)
        ciderMainWindow?.persistCurrentFrame()
        ciderMainWindow?.orderOut(nil)
    }

    func minimizeCiderMainWindow() {
        if let qaCiderMainWindow {
            qaCiderMainWindow.miniaturize(nil)
            return
        }
        ciderMainWindow?.persistCurrentFrame()
        ciderMainWindow?.miniaturize(nil)
    }

    func maximizeCiderMainWindow() {
        (qaCiderMainWindow ?? ciderMainWindow)?.zoom(nil)
    }

    private func apply(_ transition: CiderSurfaceTransition) {
        NSApplication.shared.setActivationPolicy(transition.activationPolicy)

        if transition.shouldHideMainWindow {
            hideCiderMainWindow()
        }

        if transition.shouldShowMainWindow {
            showCiderMainWindow()
        }

        if transition.shouldActivateApp {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func makeQACiderMainWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Cider"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 920, height: 560)
        return window
    }

    private func showQACiderMainWindow(_ window: NSWindow) {
        let targetScreen = NSScreen.screens.first {
            $0.frame.origin == .zero || $0.visibleFrame.origin == .zero
        } ?? NSScreen.main ?? NSScreen.screens.first

        if let visibleFrame = targetScreen?.visibleFrame {
            window.setFrame(
                CiderMainWindowPlacement.qaVisibleFrame(
                    in: visibleFrame,
                    preferredSize: window.frame.size,
                    minimumSize: window.minSize
                ),
                display: true
            )
        } else {
            window.center()
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        let frame = window.frame
        print("CIDER_QA_WINDOW visible x=\(Int(frame.minX)) y=\(Int(frame.minY)) width=\(Int(frame.width)) height=\(Int(frame.height))")
    }
}
