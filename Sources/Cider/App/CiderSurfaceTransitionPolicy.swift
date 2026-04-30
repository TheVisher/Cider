import AppKit

enum CiderWorkspaceSurface {
    case mainWindow
}

struct CiderSurfaceTransition {
    let activationPolicy: NSApplication.ActivationPolicy
    let shouldShowMainWindow: Bool
    let shouldHideMainWindow: Bool
    let shouldActivateApp: Bool
}

enum CiderSurfaceTransitionPolicy {
    static func launchTransition() -> CiderSurfaceTransition {
        transitionToMainWindow()
    }

    static func transitionToMainWindow() -> CiderSurfaceTransition {
        CiderSurfaceTransition(
            activationPolicy: .regular,
            shouldShowMainWindow: true,
            shouldHideMainWindow: false,
            shouldActivateApp: true
        )
    }
}
