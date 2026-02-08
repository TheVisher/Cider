import AppKit
@preconcurrency import ApplicationServices

// Private AX API — more reliable than AXWindowNumber attribute for getting CGWindowID
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

enum AccessibilityHelpers {
    private static let promptKey = "CiderPromptedAccessibility"

    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @MainActor
    @discardableResult
    static func promptForTrust() -> Bool {
        let key = "AXTrustedCheckOptionPrompt"
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    static func promptIfNeeded() {
        guard !isTrusted() else { return }
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: promptKey) {
            _ = promptForTrust()
            defaults.set(true, forKey: promptKey)
        }
    }

    static func appElement(for pid: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    static func windows(for pid: pid_t) -> [AXUIElement] {
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        guard error == .success, let windows = value as? [AXUIElement] else {
            return []
        }
        return windows
    }

    static func title(of window: AXUIElement) -> String {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value)
        guard error == .success, let title = value as? String else {
            return ""
        }
        return title
    }

    static func windowID(of window: AXUIElement) -> CGWindowID? {
        var windowID: CGWindowID = 0
        let error = _AXUIElementGetWindow(window, &windowID)
        guard error == .success, windowID != 0 else { return nil }
        return windowID
    }

    static func isMinimized(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value)
        guard error == .success, let minimized = value as? Bool else { return false }
        return minimized
    }

    // MARK: - Window Position and Size

    static func getWindowPosition(_ window: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value)
        guard error == .success, let cfValue = value else { return nil }

        // Verify the CFTypeRef is actually an AXValue
        guard CFGetTypeID(cfValue) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(cfValue, to: AXValue.self)

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    static func getWindowSize(_ window: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value)
        guard error == .success, let cfValue = value else { return nil }

        // Verify the CFTypeRef is actually an AXValue
        guard CFGetTypeID(cfValue) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(cfValue, to: AXValue.self)

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    @discardableResult
    static func setWindowPosition(_ window: AXUIElement, to point: CGPoint) -> Bool {
        var mutablePoint = point
        guard let axValue = AXValueCreate(.cgPoint, &mutablePoint) else { return false }
        let error = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, axValue)
        return error == .success
    }

    @discardableResult
    static func setWindowSize(_ window: AXUIElement, to size: CGSize) -> Bool {
        var mutableSize = size
        guard let axValue = AXValueCreate(.cgSize, &mutableSize) else { return false }
        let error = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, axValue)
        return error == .success
    }

    // MARK: - Enhanced User Interface

    /// Read AXEnhancedUserInterface for a process (used by VoiceOver-aware apps like Terminal)
    static func getEnhancedUI(for pid: pid_t) -> Bool? {
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, &value)
        guard error == .success, let boolValue = value as? Bool else { return nil }
        return boolValue
    }

    /// Set AXEnhancedUserInterface for a process
    @discardableResult
    static func setEnhancedUI(for pid: pid_t, enabled: Bool) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        let error = AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, enabled as CFBoolean)
        return error == .success
    }

    // MARK: - Fullscreen

    /// Check if a window is in native macOS fullscreen
    static func isFullScreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value)
        guard error == .success, let fullScreen = value as? Bool else { return false }
        return fullScreen
    }

    /// Exit native macOS fullscreen. Polls until the window leaves fullscreen or timeout (~1s).
    /// Must be called off the main thread. Returns true if exited, false if timed out.
    static func exitFullScreen(_ window: AXUIElement) -> Bool {
        guard isFullScreen(window) else { return true }

        // Try setting AXFullScreen = false
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(window, "AXFullScreen" as CFString, &settable)
        if settable.boolValue {
            AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, false as CFBoolean)
        } else {
            // Fallback: press the fullscreen button
            var buttonRef: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(window, "AXFullScreenButton" as CFString, &buttonRef)
            if err == .success, let button = buttonRef, CFGetTypeID(button) == AXUIElementGetTypeID() {
                let axButton = unsafeDowncast(button, to: AXUIElement.self)
                AXUIElementPerformAction(axButton, kAXPressAction as CFString)
            }
        }

        // Poll for up to ~1 second (20 × 50ms)
        for _ in 0..<20 {
            usleep(50_000)
            if !isFullScreen(window) {
                return true
            }
        }
        return false
    }

    // MARK: - Coordinate Conversion

    /// Convert from CGWindowList coordinates (bottom-left origin) to Accessibility coordinates (top-left origin)
    static func convertToAXCoordinates(_ cgPoint: CGPoint, windowHeight: CGFloat) -> CGPoint {
        // Get the total height of all screens to perform the conversion
        let screens = NSScreen.screens
        guard let primaryScreen = screens.first else { return cgPoint }

        // macOS uses bottom-left origin for CGWindowList
        // Accessibility API uses top-left origin
        let totalHeight = primaryScreen.frame.height
        return CGPoint(x: cgPoint.x, y: totalHeight - cgPoint.y - windowHeight)
    }

    /// Convert from Accessibility coordinates (top-left origin) to CGWindowList coordinates (bottom-left origin)
    static func convertFromAXCoordinates(_ axPoint: CGPoint, windowHeight: CGFloat) -> CGPoint {
        let screens = NSScreen.screens
        guard let primaryScreen = screens.first else { return axPoint }

        let totalHeight = primaryScreen.frame.height
        return CGPoint(x: axPoint.x, y: totalHeight - axPoint.y - windowHeight)
    }
}
