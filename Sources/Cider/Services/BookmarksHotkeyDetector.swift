import AppKit
import Carbon.HIToolbox

/// Detects Option+B to toggle bookmarks and Option+Shift+B to capture active browser tab.
/// Uses CGEventTap so the shortcut works while other apps have focus.
final class BookmarksHotkeyDetector: @unchecked Sendable {

    private let onToggle: @MainActor @Sendable () -> Void
    private let onCapture: @MainActor @Sendable () -> Void

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var toggleHotKeyRef: EventHotKeyRef?
    private var captureHotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var isEnabled = true
    private var retainedForEventTap = false
    private var retainedForHotKey = false

    init(
        onToggle: @escaping @MainActor @Sendable () -> Void,
        onCapture: @escaping @MainActor @Sendable () -> Void
    ) {
        self.onToggle = onToggle
        self.onCapture = onCapture
    }

    func start() {
        guard eventTap == nil, toggleHotKeyRef == nil, captureHotKeyRef == nil else { return }

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
            if registerHotKeyFallback() {
                print("[BookmarksHotkeyDetector] Started (Carbon hotkey fallback)")
            } else {
                print("[BookmarksHotkeyDetector] Failed to create event tap or fallback hotkey")
            }
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

        if let toggleHotKeyRef {
            UnregisterEventHotKey(toggleHotKeyRef)
            self.toggleHotKeyRef = nil
        }

        if let captureHotKeyRef {
            UnregisterEventHotKey(captureHotKeyRef)
            self.captureHotKeyRef = nil
        }

        if let hotKeyHandler {
            RemoveEventHandler(hotKeyHandler)
            self.hotKeyHandler = nil
        }

        if retainedForHotKey {
            Unmanaged.passUnretained(self).release()
            retainedForHotKey = false
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
        } else if toggleHotKeyRef == nil && captureHotKeyRef == nil && enabled {
            start()
        }
    }

    private func registerHotKeyFallback() -> Bool {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let eventRef, let userData else { return OSStatus(eventNotHandledErr) }
                let detector = Unmanaged<BookmarksHotkeyDetector>.fromOpaque(userData).takeUnretainedValue()
                return detector.handleHotKeyEvent(eventRef)
            },
            1,
            &eventSpec,
            userData,
            &hotKeyHandler
        )
        guard installStatus == noErr else { return false }

        let toggleID = EventHotKeyID(signature: Self.signature, id: 1)
        let toggleStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_B),
            UInt32(optionKey),
            toggleID,
            GetApplicationEventTarget(),
            0,
            &toggleHotKeyRef
        )

        let captureID = EventHotKeyID(signature: Self.signature, id: 2)
        let captureStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_B),
            UInt32(optionKey | shiftKey),
            captureID,
            GetApplicationEventTarget(),
            0,
            &captureHotKeyRef
        )

        guard toggleStatus == noErr, captureStatus == noErr,
              toggleHotKeyRef != nil, captureHotKeyRef != nil else {
            if let toggleHotKeyRef {
                UnregisterEventHotKey(toggleHotKeyRef)
                self.toggleHotKeyRef = nil
            }
            if let captureHotKeyRef {
                UnregisterEventHotKey(captureHotKeyRef)
                self.captureHotKeyRef = nil
            }
            if let hotKeyHandler {
                RemoveEventHandler(hotKeyHandler)
                self.hotKeyHandler = nil
            }
            return false
        }

        _ = Unmanaged.passRetained(self)
        retainedForHotKey = true
        return true
    }

    private func handleHotKeyEvent(_ eventRef: EventRef) -> OSStatus {
        guard isEnabled else { return OSStatus(eventNotHandledErr) }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == Self.signature else {
            return OSStatus(eventNotHandledErr)
        }

        DoubleTapDetector.suppressUntilNextOptionDown = true

        switch hotKeyID.id {
        case 1:
            let callback = onToggle
            Task { @MainActor in callback() }
            return noErr
        case 2:
            let callback = onCapture
            Task { @MainActor in callback() }
            return noErr
        default:
            return OSStatus(eventNotHandledErr)
        }
    }

    private static let signature: OSType = 0x43424B59 // "CBKY"

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
