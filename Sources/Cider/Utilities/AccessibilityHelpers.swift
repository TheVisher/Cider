import AppKit
@preconcurrency import ApplicationServices

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
}
