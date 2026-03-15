import AppKit
import Combine
import os

/// Detects double-tap or single-tap of a modifier key (e.g., Option)
final class DoubleTapDetector: @unchecked Sendable {
    private var lastTapTime: Date?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyDownMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retainedForEventTap = false
    private let targetKey: NSEvent.ModifierFlags
    private let maxInterval: TimeInterval
    private let mode: ActivationMode
    private let onActivate: @MainActor @Sendable () -> Void

    private var wasKeyDown = false
    private var usedAsModifier = false
    private var keyDownTime: Date?

    /// Set synchronously by OptionTabDetector's CGEventTap to suppress activation.
    /// Reset on the next Option key-down so it doesn't persist across taps.
    /// Thread-safe via OSAllocatedUnfairLock since it's accessed from multiple threads.
    private static let _suppressLock = OSAllocatedUnfairLock(initialState: false)

    static var suppressUntilNextOptionDown: Bool {
        get { _suppressLock.withLock { $0 } }
        set { _suppressLock.withLock { $0 = newValue } }
    }

    init(key: NSEvent.ModifierFlags = .option, maxInterval: TimeInterval = 0.3, mode: ActivationMode = .doubleTap, onActivate: @escaping @MainActor @Sendable () -> Void) {
        self.targetKey = key
        self.maxInterval = maxInterval
        self.mode = mode
        self.onActivate = onActivate
    }

    func start() {
        // Global monitor - for when other apps have focus
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        // Local monitor - for when our app has focus (e.g., settings window open)
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        // For single-tap mode, also monitor keyDown to detect modifier usage
        if mode == .singleTap {
            globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
                self?.handleKeyDown()
            }

            localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyDown()
                return event
            }

            // CGEventTap catches system-level shortcuts (e.g., Opt+Tab) that NSEvent monitors miss
            startEventTap()
        }
    }

    func stop() {
        if let monitor = globalFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            globalFlagsMonitor = nil
        }
        if let monitor = localFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            localFlagsMonitor = nil
        }
        if let monitor = globalKeyDownMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyDownMonitor = nil
        }
        if let monitor = localKeyDownMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyDownMonitor = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            runLoopSource = nil
            eventTap = nil
            if retainedForEventTap {
                Unmanaged.passUnretained(self).release()
                retainedForEventTap = false
            }
        }
    }

    private func handleKeyDown() {
        // If the target key is held and another key is pressed, it's being used as a modifier
        if wasKeyDown {
            usedAsModifier = true
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let isKeyDown = event.modifierFlags.contains(targetKey)

        switch mode {
        case .doubleTap:
            handleDoubleTap(isKeyDown: isKeyDown)
        case .singleTap:
            handleSingleTap(isKeyDown: isKeyDown, event: event)
        }

        wasKeyDown = isKeyDown
    }

    private func handleDoubleTap(isKeyDown: Bool) {
        // We care about key-up events (when the modifier is released)
        if wasKeyDown && !isKeyDown {
            // Key was just released
            let now = Date()

            if let lastTap = lastTapTime, now.timeIntervalSince(lastTap) < maxInterval {
                // Double tap detected!
                lastTapTime = nil
                let callback = onActivate
                Task { @MainActor in
                    callback()
                }
            } else {
                // First tap, record time
                lastTapTime = now
            }
        }
    }

    private func handleSingleTap(isKeyDown: Bool, event: NSEvent) {
        if isKeyDown && !wasKeyDown {
            // Option key just pressed down — reset modifier tracking
            usedAsModifier = false
            keyDownTime = Date()
            Self.suppressUntilNextOptionDown = false

            // Check if other modifier keys are also held (e.g., Cmd+Option)
            let otherModifiers: NSEvent.ModifierFlags = [.command, .control, .shift]
            if !event.modifierFlags.intersection(otherModifiers).isEmpty {
                usedAsModifier = true
            }
        } else if isKeyDown && wasKeyDown {
            // Option still held — another modifier was added (e.g., pressed Shift while holding Option)
            let otherModifiers: NSEvent.ModifierFlags = [.command, .control, .shift]
            if !event.modifierFlags.intersection(otherModifiers).isEmpty {
                usedAsModifier = true
            }
        } else if wasKeyDown && !isKeyDown {
            // Option key just released — fire only if:
            // 1. Not used as a modifier
            // 2. Not suppressed by CGEventTap
            // 3. Held for less than maxInterval (quick tap, not a hold)
            let heldTooLong: Bool
            if let downTime = keyDownTime {
                heldTooLong = Date().timeIntervalSince(downTime) > maxInterval
            } else {
                heldTooLong = false
            }

            if !usedAsModifier && !Self.suppressUntilNextOptionDown && !heldTooLong {
                let callback = onActivate
                Task { @MainActor in
                    callback()
                }
            }
            keyDownTime = nil
        }
    }

    // MARK: - CGEventTap (catches system-level key events NSEvent monitors miss)

    private func startEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let detector = Unmanaged<DoubleTapDetector>.fromOpaque(refcon).takeUnretainedValue()
                detector.handleEventTap(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        )

        guard let eventTap else { return }

        _ = Unmanaged.passRetained(self)
        retainedForEventTap = true

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func handleEventTap(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }

        // If Option is held and any key is pressed, mark as modifier usage
        if wasKeyDown && event.flags.contains(.maskAlternate) {
            usedAsModifier = true
        }
    }

    deinit {
        stop()
    }
}
