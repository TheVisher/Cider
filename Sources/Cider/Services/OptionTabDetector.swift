import AppKit
import Carbon.HIToolbox

/// Detects Option+Tab keyboard shortcut for window cycling
/// Uses CGEventTap for reliable detection when other apps have focus
final class OptionTabDetector: @unchecked Sendable {

    // Callbacks
    // onCycleStart receives direction: 1 for forward (Tab), -1 for backward (Shift+Tab)
    private let onCycleStart: @MainActor @Sendable (Int) -> Void
    private let onCycleNext: @MainActor @Sendable () -> Void
    private let onCyclePrevious: @MainActor @Sendable () -> Void
    private let onCycleEnd: @MainActor @Sendable (Bool) -> Void  // Bool = committed (vs cancelled)
    private let isCycleSessionActive: @MainActor @Sendable () -> Bool

    // State
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isOptionDown = false
    private var isCycling = false
    private var isEnabled = true
    private var retainedForEventTap = false
    private var healthCheckTimer: DispatchSourceTimer?
    private static let debugQueue = DispatchQueue(label: "cider.option-tab.debug")

    init(
        onCycleStart: @escaping @MainActor @Sendable (Int) -> Void,
        onCycleNext: @escaping @MainActor @Sendable () -> Void,
        onCyclePrevious: @escaping @MainActor @Sendable () -> Void,
        onCycleEnd: @escaping @MainActor @Sendable (Bool) -> Void,
        isCycleSessionActive: @escaping @MainActor @Sendable () -> Bool
    ) {
        self.onCycleStart = onCycleStart
        self.onCycleNext = onCycleNext
        self.onCyclePrevious = onCyclePrevious
        self.onCycleEnd = onCycleEnd
        self.isCycleSessionActive = isCycleSessionActive
    }

    func start() {
        guard eventTap == nil else { return }
        debugLog("start() called")

        // Create event tap to monitor key events
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                                      (1 << CGEventType.keyUp.rawValue) |
                                      (1 << CGEventType.flagsChanged.rawValue)

        // Create refcon pointer first as unretained for tapCreate
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let detector = Unmanaged<OptionTabDetector>.fromOpaque(refcon).takeUnretainedValue()
                return detector.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: refcon
        )

        guard let eventTap else {
            print("[OptionTabDetector] Failed to create event tap - check accessibility permissions")
            debugLog("start() failed: CGEvent.tapCreate returned nil")
            return
        }

        // Retain self only after tap is successfully created to avoid leak on failure
        _ = Unmanaged.passRetained(self)
        retainedForEventTap = true

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        CGEvent.tapEnable(tap: eventTap, enable: true)
        startHealthCheck()
        print("[OptionTabDetector] Started")
        debugLog("start() succeeded")
    }

    func stop() {
        debugLog("stop() called, isCycling=\(isCycling)")
        stopHealthCheck()
        if isCycling {
            endCycling(committed: false)
        }

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        eventTap = nil

        // Release the retained self to balance passRetained in start()
        if retainedForEventTap {
            Unmanaged.passUnretained(self).release()
            retainedForEventTap = false
        }

        print("[OptionTabDetector] Stopped")
        debugLog("stop() completed")
    }

    func setEnabled(_ enabled: Bool) {
        debugLog(
            "setEnabled(\(enabled)) eventTapExists=\(eventTap != nil) " +
            "eventTapValid=\(eventTap.map(CFMachPortIsValid) ?? false) " +
            "isCycling=\(isCycling)"
        )
        isEnabled = enabled
        if !enabled, isCycling {
            endCycling(committed: false)
        } else if enabled {
            recoverStaleCyclingIfNeeded(context: "setEnabled")
        }

        if let eventTap {
            if enabled && !CFMachPortIsValid(eventTap) {
                // Tap was invalidated by macOS — recreate it
                debugLog("event tap invalid in setEnabled(true), recreating")
                stop()
                start()
                return
            }
            CGEvent.tapEnable(tap: eventTap, enable: enabled)
        } else if enabled {
            // Tap doesn't exist — create it
            start()
        }
    }

    /// Recreate the tap so it is reinserted at the head of the event-tap chain.
    /// This helps recover precedence when another app installs a competing tap later.
    func reclaimPriority() {
        guard isEnabled else { return }
        guard !isCycling else {
            debugLog("reclaimPriority skipped while cycling")
            return
        }

        debugLog("reclaimPriority recreating event tap")
        stop()
        start()
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isEnabled else { return Unmanaged.passUnretained(event) }

        // Handle tap disabled events (need to re-enable)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            debugLog("received tap disabled event: \(type.rawValue), re-enabled tap")
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .flagsChanged:
            return handleFlagsChanged(event)
        case .keyDown:
            return handleKeyDown(event)
        case .keyUp:
            return handleKeyUp(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        let wasOptionDown = isOptionDown
        isOptionDown = flags.contains(.maskAlternate)
        debugLog("flagsChanged wasOptionDown=\(wasOptionDown) isOptionDown=\(isOptionDown) isCycling=\(isCycling)")

        syncCyclingStateWithSession()

        // Option was just released
        if wasOptionDown && !isOptionDown && isCycling {
            // End cycling and commit selection
            endCycling(committed: true)
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        syncCyclingStateWithSession()

        // Check for Tab key (keyCode 48)
        guard keyCode == kVK_Tab else {
            // If we're cycling and user presses Escape, cancel
            if isCycling && keyCode == kVK_Escape {
                debugLog("keyDown Escape while cycling, cancelling")
                endCycling(committed: false)
                return nil  // Consume the Escape
            }
            return Unmanaged.passUnretained(event)
        }

        // Tab pressed - check if Option is held
        guard flags.contains(.maskAlternate) else {
            return Unmanaged.passUnretained(event)
        }

        // Option+Tab detected!
        let isShiftHeld = flags.contains(.maskShift)
        let direction = isShiftHeld ? -1 : 1
        debugLog("keyDown Option+Tab detected shift=\(isShiftHeld) isCycling=\(isCycling)")

        if !isCycling {
            // Start cycling - the direction is passed so startCycling can
            // immediately select the right item (no separate next/prev call needed)
            isCycling = true
            // Suppress single-tap activation synchronously (before NSEvent monitors fire)
            DoubleTapDetector.suppressUntilNextOptionDown = true
            let startCallback = onCycleStart
            Task { @MainActor in
                startCallback(direction)
            }
            debugLog("started cycling session direction=\(direction)")
        } else {
            // Already cycling, move next or previous
            if isShiftHeld {
                let prevCallback = onCyclePrevious
                Task { @MainActor in
                    prevCallback()
                }
                debugLog("cycled previous")
            } else {
                let nextCallback = onCycleNext
                Task { @MainActor in
                    nextCallback()
                }
                debugLog("cycled next")
            }
        }

        // Consume the Tab event so it doesn't go to other apps
        return nil
    }

    private func handleKeyUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        // We don't need to do anything special on key up
        // But consume Tab key-up if we're cycling to prevent it going elsewhere
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if isCycling && keyCode == kVK_Tab {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func endCycling(committed: Bool) {
        guard isCycling else { return }
        isCycling = false
        debugLog("endCycling committed=\(committed)")

        let endCallback = onCycleEnd
        Task { @MainActor in
            endCallback(committed)
        }
    }

    private func syncCyclingStateWithSession() {
        guard isCycling else { return }

        if !isAnyOptionKeyDown() {
            debugLog("stale cycling detected (Option not down), cancelling")
            endCycling(committed: false)
            return
        }

        let sessionActive = isCycleSessionActiveOnMainThread()
        guard !sessionActive else { return }

        // If the window-cycling session ended externally (e.g. failed to start
        // while we already marked isCycling), recover so Option+Tab can start again.
        debugLog("stale cycling detected (session inactive), resetting local isCycling")
        isCycling = false
    }

    private func isCycleSessionActiveOnMainThread() -> Bool {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                isCycleSessionActive()
            }
        }

        return false
    }

    private func isAnyOptionKeyDown() -> Bool {
        CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Option))
            || CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_RightOption))
    }

    private func recoverStaleCyclingIfNeeded(context: String) {
        guard isCycling else { return }

        if !isAnyOptionKeyDown() {
            debugLog("recoverStaleCyclingIfNeeded(\(context)): Option not down, cancelling stale cycle")
            endCycling(committed: false)
        }
    }

    // MARK: - Health Check

    /// Periodically verify the CGEvent tap is still alive.
    /// macOS can silently disable a tap without invalidating the CFMachPort.
    private func startHealthCheck() {
        stopHealthCheck()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 3, repeating: 3)
        timer.setEventHandler { [weak self] in
            self?.performHealthCheck()
        }
        timer.resume()
        healthCheckTimer = timer
    }

    private func stopHealthCheck() {
        healthCheckTimer?.cancel()
        healthCheckTimer = nil
    }

    private func performHealthCheck() {
        guard isEnabled, let eventTap else { return }

        if !CFMachPortIsValid(eventTap) {
            debugLog("healthCheck: tap invalid, recreating")
            stop()
            start()
            return
        }

        if !CGEvent.tapIsEnabled(tap: eventTap) {
            debugLog("healthCheck: tap silently disabled by macOS, re-enabling")
            CGEvent.tapEnable(tap: eventTap, enable: true)

            // Verify it actually re-enabled
            if !CGEvent.tapIsEnabled(tap: eventTap) {
                debugLog("healthCheck: re-enable failed, recreating tap")
                stop()
                start()
            }
        }
    }

    private func debugLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [OptionTabDetector] \(message)\n"
        let path = "/tmp/cider-debug.log"

        Self.debugQueue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = FileHandle(forWritingAtPath: path) {
                defer { handle.closeFile() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                FileManager.default.createFile(atPath: path, contents: data)
            }
        }
    }

    deinit {
        stop()
    }
}
