import AppKit
import Combine

/// Detects double-tap of a modifier key (e.g., Option)
final class DoubleTapDetector: @unchecked Sendable {
    private var lastTapTime: Date?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let targetKey: NSEvent.ModifierFlags
    private let maxInterval: TimeInterval
    private let onDoubleTap: @MainActor @Sendable () -> Void

    private var wasKeyDown = false

    init(key: NSEvent.ModifierFlags = .option, maxInterval: TimeInterval = 0.3, onDoubleTap: @escaping @MainActor @Sendable () -> Void) {
        self.targetKey = key
        self.maxInterval = maxInterval
        self.onDoubleTap = onDoubleTap
    }

    func start() {
        // Global monitor - for when other apps have focus
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        // Local monitor - for when our app has focus (e.g., settings window open)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }

    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let isKeyDown = event.modifierFlags.contains(targetKey)

        // We care about key-up events (when the modifier is released)
        if wasKeyDown && !isKeyDown {
            // Key was just released
            let now = Date()

            if let lastTap = lastTapTime, now.timeIntervalSince(lastTap) < maxInterval {
                // Double tap detected!
                lastTapTime = nil
                let callback = onDoubleTap
                Task { @MainActor in
                    callback()
                }
            } else {
                // First tap, record time
                lastTapTime = now
            }
        }

        wasKeyDown = isKeyDown
    }

    deinit {
        stop()
    }
}
