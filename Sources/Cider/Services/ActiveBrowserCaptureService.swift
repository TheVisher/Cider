import AppKit
import ApplicationServices
import Foundation

struct ActiveBrowserCaptureResult {
    let urlString: String
    let title: String?
}

@MainActor
enum ActiveBrowserCaptureService {
    private struct BrowserTarget: Hashable {
        let bundleID: String
        let appName: String
    }

    private struct PasteboardSnapshot {
        let items: [NSPasteboardItem]
    }

    private static var lastActivatedBrowser: BrowserTarget?
    private static var captureFailureHint: String?

    private static let safariBundleIDs: Set<String> = [
        "com.apple.safari",
    ]

    private static let chromiumBundleIDHints: Set<String> = [
        "com.google.chrome",
        "com.google.chrome.canary",
        "com.brave.browser",
        "com.microsoft.edgemac",
        "org.chromium.chromium",
        "ai.perplexity.comet",
        "company.thebrowser.browser", // Arc
        "company.thebrowser.dia",
        "org.kagi.dia",
    ]

    private static let firefoxBundleIDHints: Set<String> = [
        "org.mozilla.firefox",
        "app.zen-browser.zen",
    ]

    private static let diaBundleIDs: Set<String> = [
        "company.thebrowser.dia",
        "org.kagi.dia",
    ]

    static func registerActivatedApplication(_ application: NSRunningApplication?) {
        guard let target = target(from: application),
              isBrowserCandidate(bundleID: target.bundleID, appName: target.appName) else {
            return
        }
        lastActivatedBrowser = target
    }

    static func consumeFailureHint() -> String? {
        defer { captureFailureHint = nil }
        return captureFailureHint
    }

    static func captureFromFrontmostBrowser() -> ActiveBrowserCaptureResult? {
        captureFailureHint = nil

        let frontmostTarget = target(from: NSWorkspace.shared.frontmostApplication)
        var candidates: [BrowserTarget] = []

        for activeTarget in activeBrowserTargets() where !candidates.contains(activeTarget) {
            candidates.append(activeTarget)
            lastActivatedBrowser = activeTarget
        }

        if let frontmostTarget,
           isBrowserCandidate(bundleID: frontmostTarget.bundleID, appName: frontmostTarget.appName) {
            if !candidates.contains(frontmostTarget) {
                candidates.append(frontmostTarget)
            }
            lastActivatedBrowser = frontmostTarget
        }

        if let lastActivatedBrowser, !candidates.contains(lastActivatedBrowser) {
            candidates.append(lastActivatedBrowser)
        }

        if candidates.isEmpty {
            candidates.append(contentsOf: fallbackRunningBrowserTargets(limit: 6))
        }

        for candidate in candidates {
            if let capture = capture(from: candidate) {
                return capture
            }
        }

        if captureFailureHint == nil {
            captureFailureHint = "Could not capture active browser tab"
        }
        return nil
    }

    private static func activeBrowserTargets() -> [BrowserTarget] {
        NSWorkspace.shared.runningApplications
            .filter(\.isActive)
            .compactMap(target(from:))
            .filter { isBrowserCandidate(bundleID: $0.bundleID, appName: $0.appName) }
    }

    private static func fallbackRunningBrowserTargets(limit: Int) -> [BrowserTarget] {
        let running = NSWorkspace.shared.runningApplications
            .compactMap(target(from:))
            .filter { isBrowserCandidate(bundleID: $0.bundleID, appName: $0.appName) }
        guard !running.isEmpty else { return [] }

        var deduped: [BrowserTarget] = []
        deduped.reserveCapacity(running.count)
        for target in running where !deduped.contains(target) {
            deduped.append(target)
            if deduped.count >= limit {
                break
            }
        }
        return deduped
    }

    private static func target(from application: NSRunningApplication?) -> BrowserTarget? {
        guard let application,
              let bundleID = application.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleID.isEmpty,
              !application.isTerminated,
              // Only regular-policy apps can be brought to the foreground and
              // scripted. Helpers, XPC services, Dock Extras, and plugin containers
              // all use .accessory or .prohibited — skip them all.
              application.activationPolicy == .regular else {
            return nil
        }

        // Skip ghost processes whose .app bundle no longer exists on disk.
        // Using guard (not if-let) so a nil bundleURL also rejects the app.
        guard let bundleURL = application.bundleURL,
              FileManager.default.fileExists(atPath: bundleURL.path) else {
            return nil
        }

        let appName = application.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return BrowserTarget(bundleID: bundleID, appName: appName)
    }

    private static func capture(from target: BrowserTarget) -> ActiveBrowserCaptureResult? {
        let targetName = target.appName.isEmpty ? target.bundleID : target.appName

        if isSafariFamily(bundleID: target.bundleID),
           let capture = runScript(
               safariScript(forBundleID: target.bundleID),
               targetName: targetName
           ) {
            return capture
        }

        if isDiaFamily(bundleID: target.bundleID),
           let capture = runScript(
               diaScript(forBundleID: target.bundleID),
               targetName: targetName
           ) {
            return capture
        }

        if isChromiumFamily(bundleID: target.bundleID, appName: target.appName) {
            if let capture = runScript(
                chromiumScript(forBundleID: target.bundleID),
                targetName: targetName
            ) {
                return capture
            }

            if !target.appName.isEmpty,
               let capture = runScript(
                   chromiumScript(forApplicationName: target.appName),
                   targetName: targetName
               ) {
                return capture
            }
        }

        if let accessibilityCapture = captureViaAccessibility(from: target) {
            return accessibilityCapture
        }

        if let copied = captureByCopyingAddressBar(from: target) {
            return copied
        }

        return nil
    }

    private static func runScript(_ scriptBody: String, targetName: String) -> ActiveBrowserCaptureResult? {
        guard let script = NSAppleScript(source: scriptBody) else { return nil }

        var errorInfo: NSDictionary?
        let output = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            if let errorCode = errorInfo[NSAppleScript.errorNumber] as? Int {
                switch errorCode {
                case -1743:
                    captureFailureHint = "Allow Cider to control \(targetName) in System Settings > Privacy & Security > Automation."
                case -1712:
                    captureFailureHint = "\(targetName) did not respond to capture request."
                default:
                    break
                }
            }
            if let message = errorInfo[NSAppleScript.errorMessage] as? String {
                NSLog("[BookmarksCapture] AppleScript error: \(message)")
            }
            return nil
        }

        let rawOutput = output.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawOutput.isEmpty else { return nil }

        let lines = rawOutput
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        guard let capturedURL = lines.first(where: { isValidWebURL($0) }) else {
            return nil
        }
        let title = lines.first(where: { $0 != capturedURL && !isValidWebURL($0) })

        return ActiveBrowserCaptureResult(
            urlString: capturedURL,
            title: title?.isEmpty == true ? nil : title
        )
    }

    private static func captureByCopyingAddressBar(from target: BrowserTarget) -> ActiveBrowserCaptureResult? {
        guard let browserApp = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID)
            .first(where: { !$0.isTerminated }) else {
            return nil
        }

        BookmarksClipboardMonitor.shared.suspendFor(seconds: 3.0)
        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboard(pasteboard)
        let previouslyFrontmost = NSWorkspace.shared.frontmostApplication
        var copiedURL: String?

        browserApp.activate(options: [])
        _ = waitUntilFrontmost(bundleID: target.bundleID, timeout: 1.2)
        waitFor(seconds: 0.08)

        for attempt in 0..<3 {
            let sentinel = "__CIDER_CAPTURE_SENTINEL__\(UUID().uuidString)"
            let sentinelChangeCount = writeSentinelToPasteboard(sentinel, pasteboard: pasteboard)

            guard triggerAddressBarCopyShortcut(for: target) else {
                restorePasteboard(snapshot, to: pasteboard)
                restoreFrontmostApplication(previouslyFrontmost)
                setAccessibilityHint(for: target)
                return nil
            }

            let clipboardChanged = waitForPasteboardChange(
                pasteboard,
                from: sentinelChangeCount,
                timeout: 0.95 + Double(attempt) * 0.2
            )
            let copiedValue = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)

            if clipboardChanged,
               let copiedValue,
               copiedValue != sentinel,
               isValidWebURL(copiedValue) {
                copiedURL = copiedValue
                break
            }
        }

        restorePasteboard(snapshot, to: pasteboard)
        restoreFrontmostApplication(previouslyFrontmost)

        guard let copiedURL else {
            if captureFailureHint == nil {
                let targetName = target.appName.isEmpty ? target.bundleID : target.appName
                captureFailureHint = "Could not copy the current URL from \(targetName)."
            }
            return nil
        }

        return ActiveBrowserCaptureResult(urlString: copiedURL, title: nil)
    }

    private static func captureViaAccessibility(from target: BrowserTarget) -> ActiveBrowserCaptureResult? {
        guard AXIsProcessTrusted() else {
            setAccessibilityHint(for: target)
            return nil
        }

        guard let browserApp = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID)
            .first(where: { !$0.isTerminated }) else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(browserApp.processIdentifier)

        if let focusedElement = copyAXElementAttribute(appElement, attribute: kAXFocusedUIElementAttribute),
           let capture = extractURLFromElementTree(startingAt: focusedElement) {
            return capture
        }

        if let focusedWindow = copyAXElementAttribute(appElement, attribute: kAXFocusedWindowAttribute),
           let capture = extractURLFromElementTree(startingAt: focusedWindow) {
            return capture
        }

        if let windows = copyAXElementArrayAttribute(appElement, attribute: kAXWindowsAttribute) {
            for window in windows {
                if let capture = extractURLFromElementTree(startingAt: window) {
                    return capture
                }
            }
        }

        return nil
    }

    private static func extractURLFromElementTree(startingAt root: AXUIElement) -> ActiveBrowserCaptureResult? {
        var queue: [AXUIElement] = [root]
        var visitedIDs = Set<ObjectIdentifier>()
        var steps = 0
        let maxSteps = 600

        while !queue.isEmpty, steps < maxSteps {
            steps += 1
            let element = queue.removeFirst()
            let identifier = ObjectIdentifier(element)
            guard !visitedIDs.contains(identifier) else { continue }
            visitedIDs.insert(identifier)

            if let urlString = copyAXURLLikeValue(from: element),
               isValidWebURL(urlString) {
                let title = copyAXStringAttribute(element, attribute: kAXTitleAttribute)
                return ActiveBrowserCaptureResult(urlString: urlString, title: title)
            }

            if let children = copyAXElementArrayAttribute(element, attribute: kAXChildrenAttribute) {
                queue.append(contentsOf: children)
            }
            if let visibleChildren = copyAXElementArrayAttribute(element, attribute: kAXVisibleChildrenAttribute) {
                queue.append(contentsOf: visibleChildren)
            }
        }

        return nil
    }

    private static func copyAXURLLikeValue(from element: AXUIElement) -> String? {
        if let url = copyAXStringAttribute(element, attribute: kAXURLAttribute),
           isValidWebURL(url) {
            return url
        }

        if let document = copyAXStringAttribute(element, attribute: kAXDocumentAttribute),
           isValidWebURL(document) {
            return document
        }

        if let value = copyAXStringAttribute(element, attribute: kAXValueAttribute),
           isValidWebURL(value) {
            return value
        }

        return nil
    }

    private static func copyAXStringAttribute(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard status == .success, let value else { return nil }

        if CFGetTypeID(value) == CFStringGetTypeID(),
           let string = value as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if CFGetTypeID(value) == CFURLGetTypeID(),
           let url = value as? URL {
            return url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private static func copyAXElementAttribute(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard status == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func copyAXElementArrayAttribute(_ element: AXUIElement, attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard status == .success, let value else { return nil }
        return value as? [AXUIElement]
    }

    private static func triggerAddressBarCopyShortcut(for target: BrowserTarget) -> Bool {
        let escapedBundleID = escapedAppleScriptLiteral(target.bundleID)
        let targetName = target.appName.isEmpty ? target.bundleID : target.appName
        let scriptBody = """
        tell application id "\(escapedBundleID)" to activate
        delay 0.08
        tell application "System Events"
            keystroke "l" using {command down}
            delay 0.08
            keystroke "c" using {command down}
        end tell
        """

        guard let script = NSAppleScript(source: scriptBody) else { return false }
        var errorInfo: NSDictionary?
        _ = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            if let errorCode = errorInfo[NSAppleScript.errorNumber] as? Int {
                switch errorCode {
                case -1743:
                    captureFailureHint =
                        "Allow Cider to control System Events and \(targetName) in System Settings > Privacy & Security > Automation."
                case -1719:
                    captureFailureHint =
                        "Allow Cider in System Settings > Privacy & Security > Accessibility to capture from \(targetName)."
                default:
                    break
                }
            }
            if let message = errorInfo[NSAppleScript.errorMessage] as? String {
                NSLog("[BookmarksCapture] Shortcut script error: \(message)")
            }
            return false
        }
        return true
    }

    private static func waitUntilFrontmost(bundleID: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID {
                return true
            }
            waitFor(seconds: 0.02)
        }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    private static func waitForPasteboardChange(
        _ pasteboard: NSPasteboard,
        from changeCount: Int,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pasteboard.changeCount != changeCount {
                return true
            }
            waitFor(seconds: 0.02)
        }
        return pasteboard.changeCount != changeCount
    }

    private static func waitFor(seconds: TimeInterval) {
        guard seconds > 0 else { return }
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private static func writeSentinelToPasteboard(_ value: String, pasteboard: NSPasteboard) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        return pasteboard.changeCount
    }

    private static func snapshotPasteboard(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let copiedItems = (pasteboard.pasteboardItems ?? []).map { item -> NSPasteboardItem in
            let newItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    newItem.setData(data, forType: type)
                }
            }
            return newItem
        }
        return PasteboardSnapshot(items: copiedItems)
    }

    private static func restorePasteboard(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return }
        _ = pasteboard.writeObjects(snapshot.items)
    }

    private static func restoreFrontmostApplication(_ application: NSRunningApplication?) {
        guard let application, !application.isTerminated else { return }
        application.activate(options: [])
    }

    private static func setAccessibilityHint(for target: BrowserTarget) {
        guard captureFailureHint == nil else { return }

        let targetName = target.appName.isEmpty ? target.bundleID : target.appName
        if !AXIsProcessTrusted() {
            captureFailureHint =
                "Allow Cider in System Settings > Privacy & Security > Accessibility to capture from \(targetName)."
        } else {
            captureFailureHint = "Capture failed for \(targetName). Try Auto-save copied URLs in Bookmarks settings."
        }
    }

    private static func safariScript(forBundleID bundleID: String) -> String {
        let escapedBundleID = escapedAppleScriptLiteral(bundleID)
        return """
        tell application id "\(escapedBundleID)"
            if not (exists front window) then return ""
            set currentTab to current tab of front window
            set tabURL to URL of currentTab
            set tabTitle to name of currentTab
            return tabURL & linefeed & tabTitle
        end tell
        """
    }

    private static func chromiumScript(forBundleID bundleID: String) -> String {
        let escapedBundleID = escapedAppleScriptLiteral(bundleID)
        return """
        tell application id "\(escapedBundleID)"
            if not (exists front window) then return ""
            set tabURL to URL of active tab of front window
            set tabTitle to title of active tab of front window
            return tabURL & linefeed & tabTitle
        end tell
        """
    }

    private static func diaScript(forBundleID bundleID: String) -> String {
        let escapedBundleID = escapedAppleScriptLiteral(bundleID)
        return """
        tell application id "\(escapedBundleID)"
            if not (exists front window) then return ""
            set w to front window

            try
                set focusedTabs to (tabs of w whose isFocused is true)
                if (count of focusedTabs) > 0 then
                    set t to item 1 of focusedTabs
                    return (URL of t) & linefeed & (title of t)
                end if
            end try

            if (count of tabs of w) = 0 then return ""
            set t to item 1 of tabs of w
            return (URL of t) & linefeed & (title of t)
        end tell
        """
    }

    private static func chromiumScript(forApplicationName appName: String) -> String {
        let escapedName = escapedAppleScriptLiteral(appName)
        return """
        tell application "\(escapedName)"
            if not (exists front window) then return ""
            set tabURL to URL of active tab of front window
            set tabTitle to title of active tab of front window
            return tabURL & linefeed & tabTitle
        end tell
        """
    }

    private static func escapedAppleScriptLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func isBrowserCandidate(bundleID: String, appName: String) -> Bool {
        isSafariFamily(bundleID: bundleID)
            || isChromiumFamily(bundleID: bundleID, appName: appName)
            || isFirefoxFamily(bundleID: bundleID, appName: appName)
    }

    private static func isSafariFamily(bundleID: String) -> Bool {
        safariBundleIDs.contains(bundleID.lowercased())
    }

    private static func isDiaFamily(bundleID: String) -> Bool {
        diaBundleIDs.contains(bundleID.lowercased())
    }

    private static func isChromiumFamily(bundleID: String, appName: String) -> Bool {
        let normalizedBundleID = bundleID.lowercased()
        if chromiumBundleIDHints.contains(normalizedBundleID) {
            return true
        }

        let haystack = "\(normalizedBundleID) \(appName.lowercased())"
        let hints = [
            "chrome",
            "chromium",
            "brave",
            "edge",
            "arc",
            "vivaldi",
            "opera",
            "dia",
        ]
        return hints.contains(where: { haystack.contains($0) })
    }

    private static func isFirefoxFamily(bundleID: String, appName: String) -> Bool {
        let normalizedBundleID = bundleID.lowercased()
        if firefoxBundleIDHints.contains(normalizedBundleID) {
            return true
        }

        let haystack = "\(normalizedBundleID) \(appName.lowercased())"
        let hints = [
            "firefox",
            "zen",
            "floorp",
            "librewolf",
        ]
        return hints.contains(where: { haystack.contains($0) })
    }

    private static func isValidWebURL(_ candidate: String) -> Bool {
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = components.host else {
            return false
        }

        if host == "localhost" { return true }
        if host.contains(".") { return true }
        if host.hasPrefix("[") && host.contains(":") { return true } // IPv6 literal

        let octets = host.split(separator: ".")
        if octets.count == 4,
           octets.allSatisfy({ part in
               guard let value = Int(part) else { return false }
               return (0...255).contains(value)
           }) {
            return true
        }

        return false
    }
}
