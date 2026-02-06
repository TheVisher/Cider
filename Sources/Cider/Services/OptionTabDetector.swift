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

    // State
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isOptionDown = false
    private var isCycling = false
    private var isEnabled = true
    private var retainedForEventTap = false

    init(
        onCycleStart: @escaping @MainActor @Sendable (Int) -> Void,
        onCycleNext: @escaping @MainActor @Sendable () -> Void,
        onCyclePrevious: @escaping @MainActor @Sendable () -> Void,
        onCycleEnd: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        self.onCycleStart = onCycleStart
        self.onCycleNext = onCycleNext
        self.onCyclePrevious = onCyclePrevious
        self.onCycleEnd = onCycleEnd
    }

    func start() {
        guard eventTap == nil else { return }

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
        print("[OptionTabDetector] Started")
    }

    func stop() {
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
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: enabled)
        }
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isEnabled else { return Unmanaged.passUnretained(event) }

        // Handle tap disabled events (need to re-enable)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
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

        // Check for Tab key (keyCode 48)
        guard keyCode == kVK_Tab else {
            // If we're cycling and user presses Escape, cancel
            if isCycling && keyCode == kVK_Escape {
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
        } else {
            // Already cycling, move next or previous
            if isShiftHeld {
                let prevCallback = onCyclePrevious
                Task { @MainActor in
                    prevCallback()
                }
            } else {
                let nextCallback = onCycleNext
                Task { @MainActor in
                    nextCallback()
                }
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

        let endCallback = onCycleEnd
        Task { @MainActor in
            endCallback(committed)
        }
    }

    deinit {
        stop()
    }
}
