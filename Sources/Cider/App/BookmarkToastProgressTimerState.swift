import Foundation

/// Small deterministic timer state for bookmark/clipboard review toasts.
///
/// The UI owns the real `Timer`; this type owns countdown semantics so hover pause,
/// resume, and app-activation expiry do not accidentally reset progress.
struct BookmarkToastProgressTimerState: Equatable {
    let duration: TimeInterval
    private(set) var remaining: TimeInterval
    private(set) var progress: Double

    private var startedAt: Date?
    private var lastTickAt: Date?
    private var isPaused = false
    private var isCompleted = false

    init(duration: TimeInterval) {
        self.duration = max(duration, 0.01)
        self.remaining = max(duration, 0.01)
        self.progress = 1
    }

    mutating func start(now: Date) {
        startedAt = now
        lastTickAt = now
        remaining = duration
        progress = 1
        isPaused = false
        isCompleted = false
    }

    mutating func pause() {
        guard !isCompleted else { return }
        isPaused = true
        lastTickAt = nil
    }

    mutating func resume(now: Date) {
        guard !isCompleted else { return }
        isPaused = false
        lastTickAt = now
    }

    /// Advances the countdown. Returns true once the toast should be dismissed.
    @discardableResult
    mutating func tick(now: Date) -> Bool {
        if isCompleted { return true }
        guard !isPaused else { return false }
        guard let lastTickAt else {
            self.lastTickAt = now
            return false
        }

        let elapsed = now.timeIntervalSince(lastTickAt)
        self.lastTickAt = now
        guard elapsed.isFinite, elapsed > 0 else { return false }

        remaining -= elapsed
        if remaining <= 0 {
            remaining = 0
            progress = 0
            isCompleted = true
            return true
        }

        progress = max(0, min(1, remaining / duration))
        return false
    }

    /// App activation/login can strand hover state and prevent Timer ticks. Expire any
    /// toast that has outlived its original wall-clock duration so it cannot survive
    /// activation indefinitely.
    func shouldExpireOnActivation(now: Date) -> Bool {
        if isCompleted { return true }
        guard let startedAt else { return false }
        let age = now.timeIntervalSince(startedAt)
        return age.isFinite && age >= duration
    }
}
