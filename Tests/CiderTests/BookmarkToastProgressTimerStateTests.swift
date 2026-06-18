import Foundation
import Testing
@testable import Cider

struct BookmarkToastProgressTimerStateTests {
    @Test("hover pause then resume continues remaining countdown and completes once")
    func hoverPauseThenResumeContinuesRemainingCountdownAndCompletesOnce() {
        var state = BookmarkToastProgressTimerState(duration: 5)
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        state.start(now: start)

        #expect(state.tick(now: start.addingTimeInterval(2)) == false)
        #expect(abs(state.progress - 0.6) < 0.001)

        state.pause()
        #expect(state.tick(now: start.addingTimeInterval(20)) == false)
        #expect(abs(state.progress - 0.6) < 0.001)

        state.resume(now: start.addingTimeInterval(20))
        #expect(state.tick(now: start.addingTimeInterval(22.9)) == false)
        #expect(state.tick(now: start.addingTimeInterval(23.1)) == true)
        #expect(state.progress == 0)
        #expect(state.tick(now: start.addingTimeInterval(24)) == true)
    }

    @Test("hover resume does not reset countdown to full progress")
    func hoverResumeDoesNotResetCountdownToFullProgress() {
        var state = BookmarkToastProgressTimerState(duration: 5)
        let start = Date(timeIntervalSinceReferenceDate: 2_000)
        state.start(now: start)
        _ = state.tick(now: start.addingTimeInterval(3))

        state.pause()
        state.resume(now: start.addingTimeInterval(10))

        #expect(abs(state.remaining - 2) < 0.001)
        #expect(abs(state.progress - 0.4) < 0.001)
    }

    @Test("activation expires stale paused toasts after original duration")
    func activationExpiresStalePausedToastsAfterOriginalDuration() {
        var state = BookmarkToastProgressTimerState(duration: 5)
        let start = Date(timeIntervalSinceReferenceDate: 3_000)
        state.start(now: start)
        state.pause()

        #expect(state.shouldExpireOnActivation(now: start.addingTimeInterval(4.9)) == false)
        #expect(state.shouldExpireOnActivation(now: start.addingTimeInterval(5.1)) == true)
    }
}
