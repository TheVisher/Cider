import Testing
@testable import Cider

struct CiderSurfaceTransitionPolicyTests {
    @Test("launching Cider starts as a regular app with the main window visible")
    func launchTransitionShowsMainWindow() {
        let transition = CiderSurfaceTransitionPolicy.launchTransition()

        #expect(transition.activationPolicy == .regular)
        #expect(transition.shouldShowMainWindow)
        #expect(!transition.shouldHideMainWindow)
        #expect(transition.shouldActivateApp)
    }

    @Test("opening the main window uses regular app activation")
    func mainWindowTransitionUsesRegularAppActivation() {
        let transition = CiderSurfaceTransitionPolicy.transitionToMainWindow()

        #expect(transition.activationPolicy == .regular)
        #expect(transition.shouldShowMainWindow)
        #expect(!transition.shouldHideMainWindow)
        #expect(transition.shouldActivateApp)
    }
}
