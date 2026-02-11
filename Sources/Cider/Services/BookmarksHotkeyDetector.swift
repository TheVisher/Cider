import AppKit
import Carbon.HIToolbox

/// Detects Option+B to toggle bookmarks and Option+Shift+B to capture active browser tab.
/// Uses CGEventTap so the shortcut works while other apps have focus.
final class BookmarksHotkeyDetector: @unchecked Sendable {

    private let onToggle: @MainActor @Sendable () -> Void
    private let onCapture: @MainActor @Sendable () -> Void

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isEnabled = true
    private var retainedForEventTap = false

    init(
        onToggle: @escaping @MainActor @Sendable () -> Void,
        onCapture: @escaping @MainActor @Sendable () -> Void
    ) {
        self.onToggle = onToggle
        self.onCapture = onCapture
    }

    func start() {
        guard eventTap == nil else { return }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let detector = Unmanaged<BookmarksHotkeyDetector>.fromOpaque(refcon).takeUnretainedValue()
                return detector.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: refcon
        )

        guard let eventTap else {
            print("[BookmarksHotkeyDetector] Failed to create event tap - check accessibility permissions")
            return
        }

        _ = Unmanaged.passRetained(self)
        retainedForEventTap = true

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        CGEvent.tapEnable(tap: eventTap, enable: true)
        print("[BookmarksHotkeyDetector] Started")
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

        if retainedForEventTap {
            Unmanaged.passUnretained(self).release()
            retainedForEventTap = false
        }

        print("[BookmarksHotkeyDetector] Stopped")
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if let eventTap {
            if enabled && !CFMachPortIsValid(eventTap) {
                stop()
                start()
                return
            }
            CGEvent.tapEnable(tap: eventTap, enable: enabled)
        } else if enabled {
            start()
        }
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isEnabled else { return Unmanaged.passUnretained(event) }

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        guard flags.contains(.maskAlternate),
              !flags.contains(.maskControl),
              !flags.contains(.maskCommand) else {
            return Unmanaged.passUnretained(event)
        }

        guard keyCode == Int64(kVK_ANSI_B) else {
            return Unmanaged.passUnretained(event)
        }

        DoubleTapDetector.suppressUntilNextOptionDown = true

        let callback = flags.contains(.maskShift) ? onCapture : onToggle
        Task { @MainActor in
            callback()
        }

        return nil
    }

    deinit {
        stop()
    }
}
