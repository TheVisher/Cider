import AppKit
import Foundation
import os

// MARK: - Capture Result

struct BrowserCaptureResult {
    let bundleID: String
    let appName: String
    let tabs: [BrowserSessionTab]
}

// MARK: - Browser Tab Capture Service

@MainActor
enum BrowserTabCaptureService {
    private static let logger = Logger(subsystem: "com.cider", category: "BrowserTabCaptureService")

    private static let tabDelimiter = "---CIDERTAB---"

    private static let safariBundleIDs: Set<String> = [
        "com.apple.safari",
    ]

    private static let chromiumBundleIDHints: Set<String> = [
        "com.google.chrome",
        "com.google.chrome.canary",
        "com.brave.browser",
        "com.microsoft.edgemac",
        "org.chromium.chromium",
        "company.thebrowser.browser", // Arc
        "company.thebrowser.dia",     // Dia (The Browser Company)
        "org.kagi.dia",               // Dia (Kagi)
        "com.vivaldi.vivaldi",
        "com.opera.opera",
        "ai.perplexity.comet",
    ]

    // MARK: - Public API

    /// Captures all open tabs from all running browsers (Safari + Chromium).
    static func captureAllBrowsers() async -> [BrowserCaptureResult] {
        var results: [BrowserCaptureResult] = []

        // Only check regular GUI apps — skip background helpers, XPC services, agents
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
        }
        logger.info("Scanning \(runningApps.count) regular apps for browsers...")

        for app in runningApps {
            guard let bundleID = app.bundleIdentifier,
                  let appName = app.localizedName ?? app.bundleIdentifier else { continue }

            if isSafariFamily(bundleID: bundleID) {
                logger.info("Found Safari-family browser: \(appName) (\(bundleID))")
                if let result = captureFromSafari(bundleID: bundleID, appName: appName) {
                    logger.info("Captured \(result.tabs.count) tabs from \(appName)")
                    results.append(result)
                }
            } else if isChromiumFamily(bundleID: bundleID, appName: appName) {
                logger.info("Found Chromium-family browser: \(appName) (\(bundleID))")
                if let result = captureFromChromium(bundleID: bundleID, appName: appName) {
                    logger.info("Captured \(result.tabs.count) tabs from \(appName)")
                    results.append(result)
                }
            }
        }

        logger.info("Capture complete: \(results.count) browsers, \(results.flatMap(\.tabs).count) total tabs")
        return results
    }

    /// Captures all open tabs from a specific browser by bundle ID.
    static func captureFromBrowser(bundleID: String, appName: String) async -> BrowserCaptureResult? {
        if isSafariFamily(bundleID: bundleID) {
            return captureFromSafari(bundleID: bundleID, appName: appName)
        } else if isChromiumFamily(bundleID: bundleID, appName: appName) {
            return captureFromChromium(bundleID: bundleID, appName: appName)
        }
        return nil
    }

    /// Returns all currently running browsers that we can capture from.
    static func runningBrowsers() -> [(bundleID: String, appName: String)] {
        var browsers: [(bundleID: String, appName: String)] = []
        let runningApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        for app in runningApps {
            guard let bundleID = app.bundleIdentifier,
                  let appName = app.localizedName ?? app.bundleIdentifier else { continue }
            if isSafariFamily(bundleID: bundleID) || isChromiumFamily(bundleID: bundleID, appName: appName) {
                browsers.append((bundleID: bundleID, appName: appName))
            }
        }
        return browsers
    }

    /// Returns all installed browsers (running or not) by checking known bundle IDs.
    static func installedBrowsers() -> [(bundleID: String, appName: String)] {
        let knownBrowsers: [(bundleID: String, appName: String)] = [
            ("com.apple.Safari", "Safari"),
            ("com.google.Chrome", "Google Chrome"),
            ("org.mozilla.firefox", "Firefox"),
            ("com.microsoft.edgemac", "Microsoft Edge"),
            ("com.brave.Browser", "Brave Browser"),
            ("com.operasoftware.Opera", "Opera"),
            ("com.vivaldi.Vivaldi", "Vivaldi"),
            ("company.thebrowser.Browser", "Arc"),
            ("app.zen-browser.zen", "Zen Browser"),
            ("org.chromium.Chromium", "Chromium"),
        ]
        return knownBrowsers.filter { browser in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) != nil
        }
    }

    // MARK: - Safari Capture

    private static func captureFromSafari(bundleID: String, appName: String) -> BrowserCaptureResult? {
        let escapedBundleID = escapedAppleScriptLiteral(bundleID)
        let script = """
        tell application id "\(escapedBundleID)"
            set output to ""
            repeat with w in windows
                try
                    repeat with t in tabs of w
                        set output to output & (URL of t) & linefeed & (name of t) & linefeed & "\(tabDelimiter)" & linefeed
                    end repeat
                end try
            end repeat
            return output
        end tell
        """

        guard let tabs = executeAndParse(script: script, bundleID: bundleID, appName: appName) else {
            return nil
        }
        return BrowserCaptureResult(bundleID: bundleID, appName: appName, tabs: tabs)
    }

    // MARK: - Chromium Capture

    private static func captureFromChromium(bundleID: String, appName: String) -> BrowserCaptureResult? {
        let escapedBundleID = escapedAppleScriptLiteral(bundleID)
        let script = """
        tell application id "\(escapedBundleID)"
            set output to ""
            repeat with w in windows
                try
                    repeat with t in tabs of w
                        set output to output & (URL of t) & linefeed & (title of t) & linefeed & "\(tabDelimiter)" & linefeed
                    end repeat
                end try
            end repeat
            return output
        end tell
        """

        guard let tabs = executeAndParse(script: script, bundleID: bundleID, appName: appName) else {
            return nil
        }
        return BrowserCaptureResult(bundleID: bundleID, appName: appName, tabs: tabs)
    }

    // MARK: - Script Execution & Parsing

    private static func executeAndParse(script: String, bundleID: String, appName: String) -> [BrowserSessionTab]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger.error("Failed to launch osascript for \(appName): \(error)")
            return nil
        }

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            if errorString.contains("-1743") {
                logger.warning("Automation permission denied for \(appName). User must grant access in System Settings > Privacy > Automation.")
            } else if errorString.contains("-1712") {
                logger.warning("Timeout scripting \(appName) — app may not be responding.")
            } else {
                logger.error("osascript error for \(appName): \(errorString)")
            }
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8), !output.isEmpty else {
            return []
        }

        return parseTabOutput(output)
    }

    private static func parseTabOutput(_ output: String) -> [BrowserSessionTab] {
        let blocks = output.components(separatedBy: tabDelimiter)
        var tabs: [BrowserSessionTab] = []

        for block in blocks {
            let lines = block.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard lines.count >= 1 else { continue }

            let urlString = lines[0]
            // Skip non-web URLs (about:, chrome:, safari-resource:, etc.)
            guard urlString.hasPrefix("http://") || urlString.hasPrefix("https://") else { continue }

            let title = lines.count >= 2 ? lines[1] : nil
            tabs.append(BrowserSessionTab(urlString: urlString, title: title))
        }

        return tabs
    }

    // MARK: - Browser Detection

    private static func isSafariFamily(bundleID: String) -> Bool {
        safariBundleIDs.contains(bundleID.lowercased())
    }

    private static func isChromiumFamily(bundleID: String, appName: String) -> Bool {
        let normalizedBundleID = bundleID.lowercased()
        if chromiumBundleIDHints.contains(normalizedBundleID) {
            return true
        }
        let haystack = "\(normalizedBundleID) \(appName.lowercased())"
        let hints = ["chrome", "chromium", "brave", "edge", "arc", "vivaldi", "opera", "dia"]
        return hints.contains(where: { haystack.contains($0) })
    }

    private static func escapedAppleScriptLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
