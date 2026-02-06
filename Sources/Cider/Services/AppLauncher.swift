import AppKit

@MainActor
struct AppLauncher {
    func launchOrFocus(_ app: AppInfo) {
        NSLog("[AppLauncher] launchOrFocus called for: \(app.name)")

        // Check if app is already running
        if !app.bundleIdentifier.isEmpty,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).first {

            // Check if this app was manually minimized by Cider
            if WindowCache.shared.isManuallyMinimized(running.processIdentifier) {
                NSLog("[AppLauncher] App is manually minimized, restoring: \(app.name)")
                WindowCache.shared.clearManuallyMinimized(running.processIdentifier)
                WindowCache.shared.unstageWindows(for: running.processIdentifier)
                running.unhide()
                running.activate(options: [.activateAllWindows])
                return
            }

            // Check if this app is staged by auto-hide (but not manually minimized)
            if WindowCache.shared.isStaged(running.processIdentifier) {
                NSLog("[AppLauncher] App is staged, unstaging: \(app.name)")
                WindowCache.shared.unstageWindows(for: running.processIdentifier)
                running.unhide()
                running.activate(options: [.activateAllWindows])
                return
            }

            // Check if the app is hidden (but not staged by us)
            if running.isHidden {
                NSLog("[AppLauncher] App is hidden, unhiding: \(app.name)")
                running.unhide()
                running.activate(options: [.activateAllWindows])
                return
            }

            // Check if the app has any visible windows
            let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            let hasWindows = windowList.contains { info in
                guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32 else { return false }
                return ownerPID == running.processIdentifier
            }

            if hasWindows {
                NSLog("[AppLauncher] Activating running app with windows: \(app.name)")
                running.activate(options: [.activateAllWindows])
                return
            }

            // App running but no windows - use AppleScript to activate like dock click
            // This sends the proper "reopen" event that apps respond to
            NSLog("[AppLauncher] App running but no windows, using AppleScript to reopen: \(app.name)")
            if !app.bundleIdentifier.isEmpty {
                let script = """
                tell application id "\(app.bundleIdentifier)"
                    reopen
                    activate
                end tell
                """
                if let appleScript = NSAppleScript(source: script) {
                    var error: NSDictionary?
                    appleScript.executeAndReturnError(&error)
                    if let error = error {
                        NSLog("[AppLauncher] AppleScript error: \(error)")
                        // Fallback to opening the app
                        let url = URL(fileURLWithPath: app.path)
                        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
                    }
                }
            } else {
                NSLog("[AppLauncher] No bundle identifier, falling back to NSWorkspace: \(app.name)")
                let url = URL(fileURLWithPath: app.path)
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            }
            return
        }

        // App not running - launch it
        guard !app.path.isEmpty else {
            NSLog("[AppLauncher] Cannot launch \(app.name): path is empty")
            return
        }

        let url = URL(fileURLWithPath: app.path)

        // Check if the app exists at the path
        guard FileManager.default.fileExists(atPath: app.path) else {
            NSLog("[AppLauncher] Cannot launch \(app.name): app not found at \(app.path)")
            return
        }

        NSLog("[AppLauncher] Launching app: \(app.name) from \(app.path)")
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { runningApp, error in
            if let error = error {
                NSLog("[AppLauncher] Failed to launch \(app.name): \(error.localizedDescription)")
            } else if let runningApp = runningApp {
                NSLog("[AppLauncher] Successfully launched \(app.name) (PID: \(runningApp.processIdentifier))")
            }
        }
    }

    func showInFinder(_ app: AppInfo) {
        guard !app.path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
    }
}
