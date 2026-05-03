import AppKit
import SwiftUI

// MARK: - Cider Main Window Management

extension AppDelegate {
    func configureCiderMainWindow() {
        guard bookmarksViewModel != nil, notesViewModel != nil else { return }

        let window = CiderMainWindow()
        ciderMainWindow = window
        updateCiderMainWindowView()
    }

    func updateCiderMainWindowView() {
        guard let window = ciderMainWindow,
              let bookmarksViewModel,
              let notesViewModel else { return }

        let windowView = CiderPanelView(
            bookmarksViewModel: bookmarksViewModel,
            notesViewModel: notesViewModel,
            surface: .mainWindow
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        window.contentView = CiderMainWindowHostingView(rootView: windowView)
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
    }

    @objc func openCiderMainWindowFromMenu() {
        transitionToCiderMainWindow()
    }

    func transitionToCiderMainWindow() {
        apply(CiderSurfaceTransitionPolicy.transitionToMainWindow())
    }

    func showCiderMainWindow() {
        guard let window = ciderMainWindow else { return }
        window.showCentered()
    }

    func hideCiderMainWindow() {
        ciderMainWindow?.persistCurrentFrame()
        ciderMainWindow?.orderOut(nil)
    }

    func minimizeCiderMainWindow() {
        ciderMainWindow?.persistCurrentFrame()
        ciderMainWindow?.miniaturize(nil)
    }

    func maximizeCiderMainWindow() {
        ciderMainWindow?.zoom(nil)
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
}
