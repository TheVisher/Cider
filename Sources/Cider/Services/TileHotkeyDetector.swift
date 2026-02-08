import AppKit
import Carbon.HIToolbox

/// Detects Ctrl+Option keyboard shortcuts for Rectangle-style window tiling.
/// Uses CGEventTap for reliable detection when other apps have focus.
final class TileHotkeyDetector: @unchecked Sendable {

    private let onAction: @MainActor @Sendable (TileAction) -> Void

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isEnabled = true
    private var retainedForEventTap = false

    init(onAction: @escaping @MainActor @Sendable (TileAction) -> Void) {
        self.onAction = onAction
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
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let detector = Unmanaged<TileHotkeyDetector>.fromOpaque(refcon).takeUnretainedValue()
                return detector.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: refcon
        )

        guard let eventTap else {
            print("[TileHotkeyDetector] Failed to create event tap - check accessibility permissions")
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
        print("[TileHotkeyDetector] Started")
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

        print("[TileHotkeyDetector] Stopped")
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: enabled)
        } else if enabled {
            // Retry creation if the initial start() failed (e.g. permissions weren't granted yet)
            start()
        }
    }

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

        // Must have Ctrl+Option held
        guard flags.contains(.maskControl), flags.contains(.maskAlternate) else {
            return Unmanaged.passUnretained(event)
        }

        let hasShift = flags.contains(.maskShift)
        let hasCommand = flags.contains(.maskCommand)

        if let action = mapKeyToAction(keyCode: keyCode, hasShift: hasShift, hasCommand: hasCommand) {
            let callback = onAction
            Task { @MainActor in
                callback(action)
            }
            return nil  // Consume the event
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Key Mapping

    private func mapKeyToAction(keyCode: Int64, hasShift: Bool, hasCommand: Bool) -> TileAction? {
        // Ctrl+Opt+Cmd combos (next/prev display)
        if hasCommand && !hasShift {
            switch keyCode {
            case Int64(kVK_RightArrow): return .nextDisplay
            case Int64(kVK_LeftArrow): return .previousDisplay
            default: return nil
            }
        }

        // Don't match if Cmd is held for non-Cmd combos
        if hasCommand { return nil }

        // Ctrl+Opt+Shift combos
        if hasShift {
            switch keyCode {
            case Int64(kVK_Return): return .tile(.almostMaximize)
            default: return nil
            }
        }

        // Ctrl+Opt combos (no Shift, no Cmd)
        switch keyCode {
        // Arrow keys — halves
        case Int64(kVK_LeftArrow): return .tile(.left)
        case Int64(kVK_RightArrow): return .tile(.right)
        case Int64(kVK_UpArrow): return .tile(.top)
        case Int64(kVK_DownArrow): return .tile(.bottom)

        // Quarters
        case Int64(kVK_ANSI_U): return .tile(.topLeft)
        case Int64(kVK_ANSI_I): return .tile(.topRight)
        case Int64(kVK_ANSI_J): return .tile(.bottomLeft)
        case Int64(kVK_ANSI_K): return .tile(.bottomRight)

        // Maximize & center
        case Int64(kVK_Return): return .tile(.maximize)
        case Int64(kVK_ANSI_C): return .tile(.center)

        // Larger / smaller
        case Int64(kVK_ANSI_Equal): return .larger
        case Int64(kVK_ANSI_Minus): return .smaller

        // Restore
        case Int64(kVK_Delete): return .restore

        // Thirds
        case Int64(kVK_ANSI_D): return .tile(.firstThird)
        case Int64(kVK_ANSI_F): return .tile(.centerThird)
        case Int64(kVK_ANSI_G): return .tile(.lastThird)

        // Two-thirds
        case Int64(kVK_ANSI_E): return .tile(.firstTwoThirds)
        case Int64(kVK_ANSI_T): return .tile(.lastTwoThirds)

        default: return nil
        }
    }

    deinit {
        stop()
    }
}
