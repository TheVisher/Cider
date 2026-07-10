import Foundation

@MainActor
final class CiderMainWindowFramePersistenceDebouncer {
    private let delayNanoseconds: UInt64
    private var pendingTask: Task<Void, Never>?

    init(delay: Duration = .milliseconds(350)) {
        self.delayNanoseconds = Self.nanoseconds(for: delay)
    }

    deinit {
        pendingTask?.cancel()
    }

    func schedule(_ action: @escaping @MainActor @Sendable () -> Void) {
        pendingTask?.cancel()
        pendingTask = Task.detached { [delayNanoseconds] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await action()
        }
    }

    func flush(_ action: @escaping @MainActor @Sendable () -> Void) {
        pendingTask?.cancel()
        pendingTask = nil
        action()
    }

    private static func nanoseconds(for duration: Duration) -> UInt64 {
        let components = duration.components
        let seconds = UInt64(max(components.seconds, 0)) * 1_000_000_000
        let attoseconds = max(components.attoseconds, 0)
        return seconds + UInt64(attoseconds / 1_000_000_000)
    }
}
