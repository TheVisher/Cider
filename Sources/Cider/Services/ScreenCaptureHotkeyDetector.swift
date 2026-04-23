import AppKit
import Carbon.HIToolbox
import os

/// Detects Option+Cmd+2 and posts `.requestScreenCapture`.
/// Falls back to Carbon `RegisterEventHotKey` if CGEventTap creation fails.
/// @unchecked Sendable: all mutable state accessed only from main thread event monitors.
final class ScreenCaptureHotkeyDetector: @unchecked Sendable {

    private let logger = Logger(subsystem: "com.cider.app", category: "ScreenCaptureHotkeyDetector")

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var isEnabled = true
    private var retainedForEventTap = false
    private var retainedForHotKey = false

    func start() {
        guard eventTap == nil, hotKeyRef == nil else { return }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let detector = Unmanaged<ScreenCaptureHotkeyDetector>.fromOpaque(refcon).takeUnretainedValue()
                return detector.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: refcon
        )

        guard let tap = eventTap else {
            if registerHotKeyFallback() {
                logger.info("Started (Carbon hotkey fallback)")
            } else {
                logger.error("Failed to create event tap or fallback hotkey")
            }
            return
        }

        _ = Unmanaged.passRetained(self)
        retainedForEventTap = true

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let src = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("Started")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            runLoopSource = nil
        }
        eventTap = nil
        if retainedForEventTap {
            Unmanaged.passUnretained(self).release()
            retainedForEventTap = false
        }
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = hotKeyHandler {
            RemoveEventHandler(handler)
            hotKeyHandler = nil
        }
        if retainedForHotKey {
            Unmanaged.passUnretained(self).release()
            retainedForHotKey = false
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if let tap = eventTap {
            if enabled && !CFMachPortIsValid(tap) {
                stop()
                start()
                return
            }
            CGEvent.tapEnable(tap: tap, enable: enabled)
        } else if hotKeyRef == nil && enabled {
            start()
        }
    }

    // MARK: - Carbon Fallback

    private static let signature: OSType = 0x53435459 // "SCTY"

    private func registerHotKeyFallback() -> Bool {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let eventRef, let userData else { return OSStatus(eventNotHandledErr) }
                let d = Unmanaged<ScreenCaptureHotkeyDetector>.fromOpaque(userData).takeUnretainedValue()
                return d.handleHotKeyEvent(eventRef)
            },
            1, &eventSpec, userData, &hotKeyHandler
        )
        guard status == noErr else { return false }

        // Opt+Cmd+2
        let keyID = EventHotKeyID(signature: Self.signature, id: 1)
        let regStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_2),
            UInt32(optionKey | cmdKey),
            keyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard regStatus == noErr, hotKeyRef != nil else {
            if let h = hotKeyHandler { RemoveEventHandler(h); hotKeyHandler = nil }
            return false
        }
        _ = Unmanaged.passRetained(self)
        retainedForHotKey = true
        return true
    }

    private func handleHotKeyEvent(_ eventRef: EventRef) -> OSStatus {
        guard isEnabled else { return OSStatus(eventNotHandledErr) }
        var keyID = EventHotKeyID()
        let s = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &keyID
        )
        guard s == noErr, keyID.signature == Self.signature else {
            return OSStatus(eventNotHandledErr)
        }
        DoubleTapDetector.suppressUntilNextOptionDown = true
        Task { @MainActor in
            NotificationCenter.default.post(name: .requestScreenCapture, object: nil)
        }
        return noErr
    }

    // MARK: - CGEventTap Handler

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isEnabled else { return Unmanaged.passUnretained(event) }

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Opt+Cmd+2
        guard flags.contains(.maskAlternate),
              flags.contains(.maskCommand),
              !flags.contains(.maskControl),
              keyCode == Int64(kVK_ANSI_2)
        else { return Unmanaged.passUnretained(event) }

        DoubleTapDetector.suppressUntilNextOptionDown = true
        Task { @MainActor in
            NotificationCenter.default.post(name: .requestScreenCapture, object: nil)
        }
        return nil
    }

    deinit { stop() }
}
