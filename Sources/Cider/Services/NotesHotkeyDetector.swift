import AppKit
import Carbon.HIToolbox

/// Detects Option+N keyboard shortcut to toggle the inline note editor.
/// Posts `.toggleNoteEditor` notification.
final class NotesHotkeyDetector: @unchecked Sendable {

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
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let detector = Unmanaged<NotesHotkeyDetector>.fromOpaque(refcon).takeUnretainedValue()
                return detector.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: refcon
        )

        guard let eventTap else {
            if registerHotKeyFallback() {
                print("[NotesHotkeyDetector] Started (Carbon hotkey fallback)")
            } else {
                print("[NotesHotkeyDetector] Failed to create event tap or fallback hotkey")
            }
            return
        }

        // Retain self only after tap is successfully created
        _ = Unmanaged.passRetained(self)
        retainedForEventTap = true

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        CGEvent.tapEnable(tap: eventTap, enable: true)
        print("[NotesHotkeyDetector] Started")
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

        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let hotKeyHandler {
            RemoveEventHandler(hotKeyHandler)
            self.hotKeyHandler = nil
        }

        if retainedForHotKey {
            Unmanaged.passUnretained(self).release()
            retainedForHotKey = false
        }

        print("[NotesHotkeyDetector] Stopped")
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
        } else if hotKeyRef == nil && enabled {
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
                let detector = Unmanaged<NotesHotkeyDetector>.fromOpaque(userData).takeUnretainedValue()
                return detector.handleHotKeyEvent(eventRef)
            },
            1,
            &eventSpec,
            userData,
            &hotKeyHandler
        )
        guard installStatus == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_N),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr, hotKeyRef != nil else {
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
        guard status == noErr, hotKeyID.signature == Self.signature, hotKeyID.id == 1 else {
            return OSStatus(eventNotHandledErr)
        }

        DoubleTapDetector.suppressUntilNextOptionDown = true
        Task { @MainActor in
            NotificationCenter.default.post(name: .toggleNoteEditor, object: nil)
        }
        return noErr
    }

    private static let signature: OSType = 0x434E544E // "CNTN"

    // MARK: - Event Handling

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isEnabled else { return Unmanaged.passUnretained(event) }

        // Re-enable tap if macOS disabled it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Must have Option held, no other modifiers (Ctrl, Cmd, Shift)
        guard flags.contains(.maskAlternate),
              !flags.contains(.maskControl),
              !flags.contains(.maskCommand),
              !flags.contains(.maskShift) else {
            return Unmanaged.passUnretained(event)
        }

        // Check for N key
        guard keyCode == Int64(kVK_ANSI_N) else {
            return Unmanaged.passUnretained(event)
        }

        // Suppress DoubleTapDetector so Option release doesn't also open the palette
        DoubleTapDetector.suppressUntilNextOptionDown = true

        Task { @MainActor in
            NotificationCenter.default.post(name: .toggleNoteEditor, object: nil)
        }

        // Consume event to prevent n-tilde character
        return nil
    }

    deinit {
        stop()
    }
}
