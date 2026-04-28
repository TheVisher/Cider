import Testing
@testable import Cider

struct CiderSurfaceTransitionPolicyTests {
    @Test("launching Cider starts as a regular app with the main window visible")
    func launchTransitionShowsMainWindow() {
        let transition = CiderSurfaceTransitionPolicy.launchTransition()

        #expect(transition.activationPolicy == .regular)
        #expect(transition.shouldShowMainWindow)
        #expect(!transition.shouldHideMainWindow)
        #expect(!transition.shouldShowQuickPanel)
        #expect(!transition.shouldHideQuickPanel)
        #expect(transition.shouldActivateApp)
    }

    @Test("opening the main window hides the quick panel and activates the regular app")
    func mainWindowTransitionUsesRegularAppActivation() {
        let transition = CiderSurfaceTransitionPolicy.transition(
            from: .quickPanel,
            to: .mainWindow
        )

        #expect(transition.activationPolicy == .regular)
        #expect(transition.shouldHideQuickPanel)
        #expect(transition.shouldShowMainWindow)
        #expect(!transition.shouldShowQuickPanel)
        #expect(!transition.shouldHideMainWindow)
        #expect(transition.shouldActivateApp)
    }

    @Test("summoning the quick panel keeps the app regular and leaves the main window alone")
    func quickPanelTransitionPreservesMainWindow() {
        let transition = CiderSurfaceTransitionPolicy.transition(
            from: .mainWindow,
            to: .quickPanel
        )

        #expect(transition.activationPolicy == .regular)
        #expect(!transition.shouldHideMainWindow)
        #expect(!transition.shouldHideQuickPanel)
        #expect(!transition.shouldShowMainWindow)
        #expect(transition.shouldShowQuickPanel)
        #expect(!transition.shouldActivateApp)
    }

    @Test("summoning the quick panel with no current surface keeps it as a floating supplement")
    func quickPanelTransitionFromNoSurfaceShowsOnlyPanel() {
        let transition = CiderSurfaceTransitionPolicy.transition(
            from: nil,
            to: .quickPanel
        )

        #expect(transition.activationPolicy == .regular)
        #expect(!transition.shouldShowMainWindow)
        #expect(!transition.shouldHideMainWindow)
        #expect(transition.shouldShowQuickPanel)
        #expect(!transition.shouldHideQuickPanel)
        #expect(!transition.shouldActivateApp)
    }
}
