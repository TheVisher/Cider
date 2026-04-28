import AppKit

enum CiderWorkspaceSurface {
    case mainWindow
    case quickPanel
}

struct CiderSurfaceTransition {
    let activationPolicy: NSApplication.ActivationPolicy
    let shouldShowMainWindow: Bool
    let shouldHideMainWindow: Bool
    let shouldShowQuickPanel: Bool
    let shouldHideQuickPanel: Bool
    let shouldActivateApp: Bool
}

enum CiderSurfaceTransitionPolicy {
    static func launchTransition() -> CiderSurfaceTransition {
        transition(from: nil, to: .mainWindow)
    }

    static func transition(
        from currentSurface: CiderWorkspaceSurface?,
        to targetSurface: CiderWorkspaceSurface
    ) -> CiderSurfaceTransition {
        switch targetSurface {
        case .mainWindow:
            CiderSurfaceTransition(
                activationPolicy: .regular,
                shouldShowMainWindow: true,
                shouldHideMainWindow: false,
                shouldShowQuickPanel: false,
                shouldHideQuickPanel: currentSurface == .quickPanel,
                shouldActivateApp: true
            )

        case .quickPanel:
            CiderSurfaceTransition(
                activationPolicy: .regular,
                shouldShowMainWindow: false,
                shouldHideMainWindow: false,
                shouldShowQuickPanel: true,
                shouldHideQuickPanel: false,
                shouldActivateApp: false
            )
        }
    }
}
