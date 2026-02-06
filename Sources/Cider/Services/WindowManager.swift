import AppKit
import ApplicationServices

enum TilePosition: String, CaseIterable {
    case left
    case right
    case top
    case bottom
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case maximize
    case center

    var displayName: String {
        switch self {
        case .left: return "Left Half"
        case .right: return "Right Half"
        case .top: return "Top Half"
        case .bottom: return "Bottom Half"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .maximize: return "Maximize"
        case .center: return "Center"
        }
    }

    var icon: String {
        switch self {
        case .left: return "rectangle.lefthalf.filled"
        case .right: return "rectangle.righthalf.filled"
        case .top: return "rectangle.tophalf.filled"
        case .bottom: return "rectangle.bottomhalf.filled"
        case .topLeft: return "rectangle.inset.topleft.filled"
        case .topRight: return "rectangle.inset.topright.filled"
        case .bottomLeft: return "rectangle.inset.bottomleft.filled"
        case .bottomRight: return "rectangle.inset.bottomright.filled"
        case .maximize: return "rectangle.fill"
        case .center: return "rectangle.center.inset.filled"
        }
    }

    static var halves: [TilePosition] { [.left, .right, .top, .bottom] }
    static var quarters: [TilePosition] { [.topLeft, .topRight, .bottomLeft, .bottomRight] }
    static var other: [TilePosition] { [.maximize, .center] }
}

/// Tracks windows even when their apps are hidden, so Cider can still display them
@MainActor
final class WindowCache {
    static let shared = WindowCache()

    // Cache of windows from hidden apps, keyed by window ID
    private var hiddenWindows: [CGWindowID: WindowInfo] = [:]

    // Track which PIDs are currently staged (hidden by Cider's auto-hide)
    private var stagedPIDs: Set<pid_t> = []

    // Track which PIDs are manually minimized (via the minimize button)
    // These should NOT appear in the window list, only as app icons
    private var manuallyMinimizedPIDs: Set<pid_t> = []

    // Original positions of staged windows (for restoring when unstaged)
    private var originalPositions: [CGWindowID: CGPoint] = [:]

    /// Store windows for a PID that's about to be staged (moved off-screen)
    func stageWindows(for pid: pid_t, windows: [WindowInfo]) {
        stagedPIDs.insert(pid)
        for window in windows where window.ownerPID == pid {
            hiddenWindows[window.id] = window
            // Store original position
            originalPositions[window.id] = window.bounds.origin
        }
        print("[Cider] Staged \(windows.filter { $0.ownerPID == pid }.count) windows for PID \(pid)")
    }

    /// Get original position for a window
    func getOriginalPosition(for windowID: CGWindowID) -> CGPoint? {
        return originalPositions[windowID]
    }

    /// Remove windows from cache when app is unstaged (shown)
    func unstageWindows(for pid: pid_t) {
        stagedPIDs.remove(pid)
        let windowIDs = hiddenWindows.filter { $0.value.ownerPID == pid }.map { $0.key }
        for id in windowIDs {
            originalPositions.removeValue(forKey: id)
        }
        hiddenWindows = hiddenWindows.filter { $0.value.ownerPID != pid }
        print("[Cider] Unstaged windows for PID \(pid)")
    }

    /// Check if a PID is currently staged
    func isStaged(_ pid: pid_t) -> Bool {
        return stagedPIDs.contains(pid)
    }

    /// Get all staged PIDs
    func getStagedPIDs() -> Set<pid_t> {
        return stagedPIDs
    }

    /// Mark a PID as manually minimized (via Cider's minimize button)
    func setManuallyMinimized(_ pid: pid_t) {
        manuallyMinimizedPIDs.insert(pid)
        print("[Cider] Manually minimized PID \(pid)")
        // Notify observers that minimized state changed
        NotificationCenter.default.post(name: .ciderMinimizedStateChanged, object: nil)
    }

    /// Unmark a PID as manually minimized
    func clearManuallyMinimized(_ pid: pid_t) {
        manuallyMinimizedPIDs.remove(pid)
        print("[Cider] Cleared manually minimized PID \(pid)")
        // Notify observers that minimized state changed
        NotificationCenter.default.post(name: .ciderMinimizedStateChanged, object: nil)
    }

    /// Check if a PID is manually minimized
    func isManuallyMinimized(_ pid: pid_t) -> Bool {
        return manuallyMinimizedPIDs.contains(pid)
    }

    /// Get all manually minimized PIDs (these should not appear in window list)
    func getManuallyMinimizedPIDs() -> Set<pid_t> {
        return manuallyMinimizedPIDs
    }

    /// Get all cached hidden windows
    func getHiddenWindows() -> [WindowInfo] {
        return Array(hiddenWindows.values)
    }

    /// Get cached window by ID
    func getWindow(_ id: CGWindowID) -> WindowInfo? {
        return hiddenWindows[id]
    }

    /// Get cached windows for a PID
    func getWindows(for pid: pid_t) -> [WindowInfo] {
        return hiddenWindows.filter { $0.value.ownerPID == pid }.map { $0.value }
    }

    /// Get all window IDs for a specific PID
    func getWindowIDs(for pid: pid_t) -> [CGWindowID] {
        return hiddenWindows.filter { $0.value.ownerPID == pid }.map { $0.key }
    }

    /// Update a cached window's screen ID (for when window is moved while hidden)
    func updateWindowScreen(_ windowID: CGWindowID, screenID: UInt32) {
        if var window = hiddenWindows[windowID] {
            window.screenID = screenID
            hiddenWindows[windowID] = window
            print("[Cider] Updated cached window \(windowID) to screen \(screenID)")
        }
    }

    /// Clear all staged state (e.g., when disabling the feature)
    func clearAll() {
        stagedPIDs.removeAll()
        manuallyMinimizedPIDs.removeAll()
        hiddenWindows.removeAll()
        originalPositions.removeAll()
    }
}

@MainActor
struct WindowManager {
    // System processes and window titles to filter out
    private static let filteredOwners: Set<String> = [
        "Window Server", "WindowManager", "Dock", "SystemUIServer",
        "Control Center", "Notification Center", "Spotlight",
        "universalAccessAuthWarn", "TextInputMenuAgent", "TextInputSwitcher"
    ]

    private static let filteredTitlePatterns: [String] = [
        "App Icon Window", "gesture blocking overlay", "Menubar",
        "Item-0", "Menu Bar", "Backstop Menubar"
    ]

    // Finder window titles to filter (desktop, etc.)
    private static let filteredFinderTitles: Set<String> = [
        "", // Empty title windows (often the desktop)
        "Desktop"
    ]

    func fetchWindows() -> [WindowInfo] {
        // fetchWindowsRaw now uses both CGWindowList AND Accessibility API
        // to find all windows including minimized ones
        let allWindows = fetchWindowsRaw()
        // Deduplicate windows from same app with identical titles (e.g., fullscreen creates duplicate)
        return deduplicateWindows(allWindows)
    }

    private func fetchWindowsRaw() -> [WindowInfo] {
        let ownBundle = Bundle.main.bundleIdentifier
        var windows: [WindowInfo] = []
        var seenWindowIDs: Set<CGWindowID> = []

        // PART 1: Get on-screen windows from CGWindowList (for accurate bounds and window IDs)
        let cgOptions: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        if let infoList = CGWindowListCopyWindowInfo(cgOptions, kCGNullWindowID) as? [[String: Any]] {
            for info in infoList {
                guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
                guard let windowID = info[kCGWindowNumber as String] as? CGWindowID else { continue }
                guard let ownerName = info[kCGWindowOwnerName as String] as? String else { continue }
                guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t else { continue }

                // Filter out our own app
                if let running = NSRunningApplication(processIdentifier: ownerPID),
                   running.bundleIdentifier == ownBundle { continue }

                // Filter out system processes
                if Self.filteredOwners.contains(ownerName) { continue }

                let title = info[kCGWindowName as String] as? String ?? ""

                // Filter out system window titles
                var skipWindow = false
                for pattern in Self.filteredTitlePatterns {
                    if title.localizedCaseInsensitiveContains(pattern) {
                        skipWindow = true
                        break
                    }
                }
                if skipWindow { continue }

                // Extract window bounds
                var windowBounds = CGRect.zero
                if let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                   let x = boundsDict["X"], let y = boundsDict["Y"],
                   let w = boundsDict["Width"], let h = boundsDict["Height"] {
                    windowBounds = CGRect(x: x, y: y, width: w, height: h)
                    if w < 50 || h < 50 { continue }
                }

                if let alpha = info[kCGWindowAlpha as String] as? CGFloat, alpha < 0.1 { continue }

                let bundleIdentifier = NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier ?? ""

                // Filter out Finder's special windows (Desktop, empty title windows)
                if bundleIdentifier == "com.apple.finder" && Self.filteredFinderTitles.contains(title) {
                    continue
                }

                let screenID = MonitorManager.shared.screenForWindow(windowBounds)?.id

                windows.append(WindowInfo(
                    id: windowID,
                    ownerPID: ownerPID,
                    ownerName: ownerName,
                    title: title,
                    bundleIdentifier: bundleIdentifier,
                    bounds: windowBounds,
                    screenID: screenID
                ))
                seenWindowIDs.insert(windowID)
            }
        }

        // PART 2: Use Accessibility API to find minimized AND hidden windows
        // Visible windows are already captured by CGWindowList above
        // Hidden apps (via app.hide()) and minimized windows need AX to be seen
        guard AccessibilityHelpers.isTrusted() else { return windows }

        // Track PIDs that have visible windows from CGWindowList
        let pidsWithVisibleWindows = Set(windows.map { $0.ownerPID })

        for app in NSWorkspace.shared.runningApplications {
            // Skip non-regular apps (background processes, etc.)
            guard app.activationPolicy == .regular else { continue }
            guard app.bundleIdentifier != ownBundle else { continue }

            let pid = app.processIdentifier
            let ownerName = app.localizedName ?? "Unknown"
            let bundleID = app.bundleIdentifier ?? ""

            // Skip system apps we filter
            if Self.filteredOwners.contains(ownerName) { continue }

            // Check if the app itself is hidden (via app.hide(), which is what our staging does)
            let appIsHidden = app.isHidden

            // If the app was staged by Cider, use cached windows to keep stable IDs
            // This prevents thumbnails from disappearing when AX can't provide window IDs.
            if appIsHidden && WindowCache.shared.isStaged(pid) {
                let cachedWindows = WindowCache.shared.getWindows(for: pid)
                if !cachedWindows.isEmpty {
                    for var window in cachedWindows {
                        // Treat hidden windows as minimized so we don't attempt to capture them
                        window.isMinimized = true
                        if window.screenID == nil {
                            window.screenID = MonitorManager.shared.screenForWindow(window.bounds)?.id
                        }
                        windows.append(window)
                        seenWindowIDs.insert(window.id)
                    }
                    continue
                }
            }

            let axWindows = AccessibilityHelpers.windows(for: pid)
            for (index, axWindow) in axWindows.enumerated() {
                // Check if this specific window is minimized
                let isMinimized = AccessibilityHelpers.isMinimized(axWindow)

                // We want windows that are:
                // 1. Minimized (to dock), OR
                // 2. From a hidden app (staged by Cider)
                // Skip if neither - CGWindowList already has visible, non-hidden windows
                if !isMinimized && !appIsHidden { continue }

                // Get window ID if available
                let windowID = AccessibilityHelpers.windowID(of: axWindow)

                // Skip if we somehow already have this window
                if let wid = windowID, seenWindowIDs.contains(wid) { continue }

                // Get window properties
                let title = AccessibilityHelpers.title(of: axWindow)

                // Filter out Finder's special windows (Desktop, empty title windows)
                if bundleID == "com.apple.finder" && Self.filteredFinderTitles.contains(title) {
                    continue
                }

                // Get position and size
                let position = AccessibilityHelpers.getWindowPosition(axWindow) ?? .zero
                let size = AccessibilityHelpers.getWindowSize(axWindow) ?? CGSize(width: 800, height: 600)
                let bounds = CGRect(origin: position, size: size)

                // Determine screen - for hidden apps, use their last known position
                // For minimized, default to primary
                var screenID: UInt32? = nil
                if appIsHidden && bounds.width > 0 && bounds.origin != .zero {
                    // Hidden app - try to determine screen from position
                    screenID = MonitorManager.shared.screenForWindow(bounds)?.id
                }
                if screenID == nil {
                    screenID = MonitorManager.shared.monitors.first?.id
                }

                // Use window ID if available, otherwise generate a stable pseudo-ID
                let finalWindowID = windowID ?? CGWindowID(pid * 1000 + Int32(index) + 1000000)

                windows.append(WindowInfo(
                    id: finalWindowID,
                    ownerPID: pid,
                    ownerName: ownerName,
                    title: title,
                    bundleIdentifier: bundleID,
                    bounds: bounds,
                    screenID: screenID,
                    isMinimized: isMinimized || appIsHidden  // Treat hidden as "minimized" for UI purposes
                ))

                if let wid = windowID {
                    seenWindowIDs.insert(wid)
                }
            }
        }

        return windows
    }

    // Old fetchWindowsRaw for internal use (CGWindowList only, for staging logic)
    private func fetchVisibleWindowsOnly() -> [WindowInfo] {
        let ownBundle = Bundle.main.bundleIdentifier
        let cgOptions: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(cgOptions, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return infoList.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { return nil }
            guard let windowID = info[kCGWindowNumber as String] as? CGWindowID else { return nil }
            guard let ownerName = info[kCGWindowOwnerName as String] as? String else { return nil }
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t else { return nil }

            if let running = NSRunningApplication(processIdentifier: ownerPID),
               running.bundleIdentifier == ownBundle { return nil }
            if Self.filteredOwners.contains(ownerName) { return nil }

            let title = info[kCGWindowName as String] as? String ?? ""
            for pattern in Self.filteredTitlePatterns {
                if title.localizedCaseInsensitiveContains(pattern) { return nil }
            }

            var windowBounds = CGRect.zero
            if let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
               let x = boundsDict["X"], let y = boundsDict["Y"],
               let w = boundsDict["Width"], let h = boundsDict["Height"] {
                windowBounds = CGRect(x: x, y: y, width: w, height: h)
                if w < 50 || h < 50 { return nil }
            }

            if let alpha = info[kCGWindowAlpha as String] as? CGFloat, alpha < 0.1 { return nil }

            let bundleIdentifier = NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier ?? ""
            let screenID = MonitorManager.shared.screenForWindow(windowBounds)?.id

            return WindowInfo(id: windowID, ownerPID: ownerPID, ownerName: ownerName,
                              title: title, bundleIdentifier: bundleIdentifier,
                              bounds: windowBounds, screenID: screenID)
        }
    }

    /// Remove duplicate windows from the same app with identical titles
    /// Prefers visible windows over minimized, and windows with valid IDs over pseudo-IDs
    private func deduplicateWindows(_ windows: [WindowInfo]) -> [WindowInfo] {
        var seen: [String: WindowInfo] = [:]

        for window in windows {
            // Key by bundle ID + title for same-app windows
            let key = "\(window.bundleIdentifier)-\(window.title)"

            if let existing = seen[key] {
                // Prefer non-minimized over minimized
                if existing.isMinimized && !window.isMinimized {
                    seen[key] = window
                }
                // Prefer real window IDs (< 1000000) over pseudo-IDs
                else if existing.id >= 1000000 && window.id < 1000000 {
                    seen[key] = window
                }
                // Otherwise keep the first one
            } else {
                seen[key] = window
            }
        }

        return Array(seen.values)
    }

    func focus(window: WindowInfo, stageOthers: Bool = false) {
        guard AccessibilityHelpers.isTrusted() else {
            print("[Cider] Cannot focus window - accessibility not trusted")
            return
        }

        let cache = WindowCache.shared

        // Get the target application
        guard let targetApp = NSRunningApplication(processIdentifier: window.ownerPID) else {
            print("[Cider] Cannot find running application for PID \(window.ownerPID)")
            return
        }

        // Check if this app was hidden (staged)
        let wasStaged = cache.isStaged(window.ownerPID)

        // STEP 1: If target app was staged, unhide it
        if wasStaged {
            print("[Cider] Unstaging app: \(window.ownerName)")
            let windowIDs = cache.getWindowIDs(for: window.ownerPID)
            targetApp.unhide()
            cache.unstageWindows(for: window.ownerPID)
            // Unfreeze previews so they can update again
            WindowPreviewService.shared.unfreezePreviews(for: windowIDs)
            // Small delay to let unhide complete, then continue
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [self] in
                self.completeFocus(window: window, targetApp: targetApp, stageOthers: stageOthers)
            }
        } else {
            completeFocus(window: window, targetApp: targetApp, stageOthers: stageOthers)
        }
    }

    private func completeFocus(window: WindowInfo, targetApp: NSRunningApplication, stageOthers: Bool) {
        // STEP 2: Activate target app FIRST (before hiding others)
        // This prevents macOS from auto-activating Finder when we hide other apps
        _ = targetApp.activate(options: [.activateAllWindows])

        // STEP 3: Find and raise the specific window
        if let target = findAXWindow(for: window) {
            let appElement = AccessibilityHelpers.appElement(for: window.ownerPID)
            _ = AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, target)
            _ = AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        }

        // STEP 4: Now hide other apps (AFTER target is focused)
        if stageOthers {
            print("[Cider] stageOthers=true, staging other apps...")
            // Use visible-only windows for staging (don't stage based on minimized windows)
            let currentWindows = fetchVisibleWindowsOnly()
            stageOtherApps(except: window, currentWindows: currentWindows)
        } else {
            print("[Cider] stageOthers=false, not staging")
        }

        // STEP 5: Re-activate target to ensure it stays in front after hiding others
        _ = targetApp.activate(options: [])

        // STEP 6: Final raise to ensure window is on top
        if let target = findAXWindow(for: window) {
            _ = AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        }
    }

    // Apps that should never be staged (only true system UI, not Finder)
    private static let excludedFromStaging: Set<String> = [
        "com.apple.dock",
        "com.apple.SystemUIServer",
        "com.apple.controlcenter"
    ]

    /// Stage (hide) all apps except the focused one, per monitor
    private func stageOtherApps(except focusedWindow: WindowInfo, currentWindows: [WindowInfo]) {
        let cache = WindowCache.shared
        let ownBundle = Bundle.main.bundleIdentifier

        // Get the screen the focused window is on
        guard let focusedScreenID = focusedWindow.screenID else {
            print("[Cider] Cannot determine screen for focused window")
            return
        }

        // Find all PIDs that have windows on the same screen (excluding the focused app)
        var pidsToStage: Set<pid_t> = []
        for window in currentWindows {
            // Skip the focused app's windows
            if window.ownerPID == focusedWindow.ownerPID { continue }

            // Only stage apps with windows on the same screen
            if window.screenID == focusedScreenID {
                pidsToStage.insert(window.ownerPID)
            }
        }

        // Stage each app
        for pid in pidsToStage {
            // Skip if already staged
            if cache.isStaged(pid) { continue }

            guard let app = NSRunningApplication(processIdentifier: pid) else { continue }

            // Skip Cider itself
            if app.bundleIdentifier == ownBundle { continue }

            // Skip Finder and other system apps that have special behavior
            if let bundleID = app.bundleIdentifier, Self.excludedFromStaging.contains(bundleID) {
                continue
            }

            // Skip background apps
            if app.activationPolicy != .regular { continue }

            // Skip already hidden apps
            if app.isHidden { continue }

            // Cache the windows before staging
            let appWindows = currentWindows.filter { $0.ownerPID == pid }
            cache.stageWindows(for: pid, windows: appWindows)

            // Capture snapshots BEFORE hiding so thumbnails persist
            let windowIDs = appWindows.map { $0.id }
            WindowPreviewService.shared.prepareForHiding(windowIDs: windowIDs)

            // Now hide the app
            print("[Cider] Staging (hiding) app: \(app.localizedName ?? "Unknown") with \(appWindows.count) windows")
            app.hide()
        }
    }

    /// Unstage (unhide) all apps
    func unstageAllApps() {
        let cache = WindowCache.shared

        for app in NSWorkspace.shared.runningApplications {
            if cache.isStaged(app.processIdentifier) {
                app.unhide()
                cache.unstageWindows(for: app.processIdentifier)
            }
        }

        cache.clearAll()
        WindowPreviewService.shared.unfreezeAllPreviews()
    }

    /// Called on Cider startup - unhide all hidden apps
    /// This ensures Cider starts with a clean slate
    func unhideAllAppsOnStartup() {
        let ownBundle = Bundle.main.bundleIdentifier

        print("[Cider] Startup: unhiding all hidden apps...")

        for app in NSWorkspace.shared.runningApplications {
            // Skip Cider itself
            if app.bundleIdentifier == ownBundle { continue }

            // Skip background apps
            if app.activationPolicy != .regular { continue }

            // Unhide any hidden app
            if app.isHidden {
                print("[Cider] Unhiding: \(app.localizedName ?? "Unknown")")
                app.unhide()
            }
        }

        // Clear any stale cache
        WindowCache.shared.clearAll()
        WindowPreviewService.shared.unfreezeAllPreviews()
    }

    /// Stage (hide) all apps on a specific monitor, except the specified PID
    /// Used when moving a focused window to another monitor
    func stageAppsOnMonitor(_ monitorID: UInt32, except excludePID: pid_t) {
        let cache = WindowCache.shared
        let ownBundle = Bundle.main.bundleIdentifier
        // Use visible-only windows for staging decisions
        let currentWindows = fetchVisibleWindowsOnly()

        // Find all PIDs that have windows on this monitor (excluding the moved app)
        var pidsToStage: Set<pid_t> = []
        for window in currentWindows {
            if window.ownerPID == excludePID { continue }
            if window.screenID == monitorID {
                pidsToStage.insert(window.ownerPID)
            }
        }

        // Stage each app
        for pid in pidsToStage {
            // Skip if already staged
            if cache.isStaged(pid) { continue }

            guard let app = NSRunningApplication(processIdentifier: pid) else { continue }

            // Skip Cider itself
            if app.bundleIdentifier == ownBundle { continue }

            // Skip Finder and other system apps
            if let bundleID = app.bundleIdentifier, Self.excludedFromStaging.contains(bundleID) {
                continue
            }

            // Skip background apps
            if app.activationPolicy != .regular { continue }

            // Skip already hidden apps
            if app.isHidden { continue }

            // Cache the windows before staging
            let appWindows = currentWindows.filter { $0.ownerPID == pid }
            cache.stageWindows(for: pid, windows: appWindows)

            // Capture snapshots before hiding
            let windowIDs = appWindows.map { $0.id }
            WindowPreviewService.shared.prepareForHiding(windowIDs: windowIDs)

            // Hide the app
            print("[Cider] Staging app on monitor move: \(app.localizedName ?? "Unknown")")
            app.hide()
        }
    }

    func close(window: WindowInfo) {
        guard AccessibilityHelpers.isTrusted() else { return }
        if let target = findAXWindow(for: window) {
            var closeButton: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(target, kAXCloseButtonAttribute as CFString, &closeButton)
            if error == .success, let button = closeButton, CFGetTypeID(button) == AXUIElementGetTypeID() {
                let axButton = unsafeDowncast(button, to: AXUIElement.self)
                _ = AXUIElementPerformAction(axButton, kAXPressAction as CFString)
            }
        }
    }

    func minimize(window: WindowInfo) {
        // Instead of native macOS minimize (which goes to Dock), we stage/hide the app
        // This preserves thumbnails and keeps the window in Cider's control
        guard let app = NSRunningApplication(processIdentifier: window.ownerPID) else { return }

        // Get all windows for this app before hiding
        let allWindows = fetchWindows()
        let appWindows = allWindows.filter { $0.ownerPID == window.ownerPID }

        // Cache the windows before staging
        WindowCache.shared.stageWindows(for: window.ownerPID, windows: appWindows)

        // Mark as manually minimized (so it doesn't show in window list)
        WindowCache.shared.setManuallyMinimized(window.ownerPID)

        // Hide the app (stages it)
        NSLog("[WindowManager] Staging/minimizing app: \(app.localizedName ?? "Unknown")")
        app.hide()
    }

    func unminimize(window: WindowInfo) {
        // Unhide/unstage the app
        guard let app = NSRunningApplication(processIdentifier: window.ownerPID) else { return }

        NSLog("[WindowManager] Unstaging/unminimizing app: \(app.localizedName ?? "Unknown")")
        WindowCache.shared.clearManuallyMinimized(window.ownerPID)
        WindowCache.shared.unstageWindows(for: window.ownerPID)
        app.unhide()
        app.activate(options: [.activateAllWindows])
    }

    func quitApp(for window: WindowInfo) {
        // Find the running application and terminate it
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: window.bundleIdentifier).first {
            NSLog("[WindowManager] Quitting app: \(app.localizedName ?? "Unknown") (\(window.bundleIdentifier))")
            app.terminate()
        } else if window.ownerPID > 0 {
            // Fallback: terminate by PID
            if let app = NSRunningApplication(processIdentifier: window.ownerPID) {
                NSLog("[WindowManager] Quitting app by PID: \(app.localizedName ?? "Unknown") (PID: \(window.ownerPID))")
                app.terminate()
            }
        }
    }

    // MARK: - Window Movement and Tiling

    private func findAXWindow(for window: WindowInfo) -> AXUIElement? {
        guard AccessibilityHelpers.isTrusted() else {
            print("[Cider] findAXWindow: accessibility not trusted")
            return nil
        }

        let axWindows = AccessibilityHelpers.windows(for: window.ownerPID)
        if axWindows.isEmpty {
            print("[Cider] findAXWindow: no AX windows found for PID \(window.ownerPID)")
            return nil
        }

        // Strategy 1: Match by window ID (most reliable)
        if let byID = axWindows.first(where: { AccessibilityHelpers.windowID(of: $0) == window.id }) {
            print("[Cider] findAXWindow: matched by window ID \(window.id)")
            return byID
        }

        // Strategy 2: Match by title
        if !window.title.isEmpty {
            if let byTitle = axWindows.first(where: { AccessibilityHelpers.title(of: $0) == window.title }) {
                print("[Cider] findAXWindow: matched by title '\(window.title)'")
                return byTitle
            }
        }

        // Strategy 3: Match by bounds (position and size)
        for axWindow in axWindows {
            if let axPos = AccessibilityHelpers.getWindowPosition(axWindow),
               let axSize = AccessibilityHelpers.getWindowSize(axWindow) {
                // AX position is top-left, convert our bounds to compare
                // Allow some tolerance for position matching
                let tolerance: CGFloat = 5
                let boundsMatch = abs(axPos.x - window.bounds.minX) < tolerance &&
                                  abs(axSize.width - window.bounds.width) < tolerance &&
                                  abs(axSize.height - window.bounds.height) < tolerance
                if boundsMatch {
                    print("[Cider] findAXWindow: matched by bounds")
                    return axWindow
                }
            }
        }

        // Last resort: return first window (only if single window app)
        if axWindows.count == 1 {
            print("[Cider] findAXWindow: using only available window")
            return axWindows.first
        }

        print("[Cider] findAXWindow: could not match window ID=\(window.id) title='\(window.title)' among \(axWindows.count) AX windows")
        return nil
    }

    /// Padding around windows when moved to a new monitor (like Rectangle's "almost maximize")
    private static let windowPadding: CGFloat = 20

    func moveWindow(_ window: WindowInfo, to screen: MonitorInfo, stageOthers: Bool = false) {
        guard let axWindow = findAXWindow(for: window) else {
            print("[Cider] moveWindow: could not find AX window")
            return
        }

        let targetFrame = screen.visibleFrame
        let padding = Self.windowPadding

        // Fit window to destination monitor with padding on all sides
        let newSize = CGSize(
            width: targetFrame.width - padding * 2,
            height: targetFrame.height - padding * 2
        )
        let newOrigin = CGPoint(
            x: targetFrame.minX + padding,
            y: targetFrame.minY + padding
        )

        let axPoint = convertToAXPosition(newOrigin, windowHeight: newSize.height)

        // Resize first, then move (avoids macOS constraining large windows to current monitor)
        AccessibilityHelpers.setWindowSize(axWindow, to: newSize)
        AccessibilityHelpers.setWindowPosition(axWindow, to: axPoint)

        // Verify the resize took effect. Some apps (Firefox/Zen) ignore AX size changes.
        // Fall back to AppleScript which handles these apps correctly.
        let tolerance: CGFloat = 20
        if let actual = AccessibilityHelpers.getWindowSize(axWindow),
           abs(actual.width - newSize.width) > tolerance || abs(actual.height - newSize.height) > tolerance {
            let script = """
            tell application "System Events"
                tell (first process whose unix id is \(window.ownerPID))
                    set size of window 1 to {\(Int(newSize.width)), \(Int(newSize.height))}
                    set position of window 1 to {\(Int(axPoint.x)), \(Int(axPoint.y))}
                end tell
            end tell
            """
            let task = Process()
            task.launchPath = "/usr/bin/osascript"
            task.arguments = ["-e", script]
            try? task.run()
            task.waitUntilExit()
        }

        // Stage other apps on the destination monitor if requested
        if stageOthers {
            stageAppsOnMonitor(screen.id, except: window.ownerPID)
        }
    }

    func moveWindow(_ window: WindowInfo, to position: CGPoint) {
        guard let axWindow = findAXWindow(for: window) else { return }
        let axPoint = convertToAXPosition(position, windowHeight: window.bounds.height)
        AccessibilityHelpers.setWindowPosition(axWindow, to: axPoint)
    }

    func resizeWindow(_ window: WindowInfo, to size: CGSize) {
        guard let axWindow = findAXWindow(for: window) else { return }
        AccessibilityHelpers.setWindowSize(axWindow, to: size)
    }

    func tileWindow(_ window: WindowInfo, position: TilePosition, on screen: MonitorInfo) {
        guard let axWindow = findAXWindow(for: window) else { return }
        let frame = calculateTileFrame(position: position, on: screen)
        let axPoint = convertToAXPosition(CGPoint(x: frame.minX, y: frame.minY), windowHeight: frame.height)
        AccessibilityHelpers.setWindowFrame(axWindow, position: axPoint, size: frame.size)
    }

    func splitWindows(_ window1: WindowInfo, _ window2: WindowInfo, on screen: MonitorInfo, leftRight: Bool = true) {
        guard let ax1 = findAXWindow(for: window1),
              let ax2 = findAXWindow(for: window2) else { return }

        let leftFrame: CGRect
        let rightFrame: CGRect

        if leftRight {
            leftFrame = calculateTileFrame(position: .left, on: screen)
            rightFrame = calculateTileFrame(position: .right, on: screen)
        } else {
            leftFrame = calculateTileFrame(position: .top, on: screen)
            rightFrame = calculateTileFrame(position: .bottom, on: screen)
        }

        let leftAXPoint = convertToAXPosition(CGPoint(x: leftFrame.minX, y: leftFrame.minY), windowHeight: leftFrame.height)
        let rightAXPoint = convertToAXPosition(CGPoint(x: rightFrame.minX, y: rightFrame.minY), windowHeight: rightFrame.height)

        AccessibilityHelpers.setWindowFrame(ax1, position: leftAXPoint, size: leftFrame.size)
        AccessibilityHelpers.setWindowFrame(ax2, position: rightAXPoint, size: rightFrame.size)
    }

    func calculateTileFrame(position: TilePosition, on screen: MonitorInfo) -> CGRect {
        let frame = screen.visibleFrame

        switch position {
        case .left:
            return CGRect(x: frame.minX, y: frame.minY,
                          width: frame.width / 2, height: frame.height)
        case .right:
            return CGRect(x: frame.midX, y: frame.minY,
                          width: frame.width / 2, height: frame.height)
        case .top:
            return CGRect(x: frame.minX, y: frame.midY,
                          width: frame.width, height: frame.height / 2)
        case .bottom:
            return CGRect(x: frame.minX, y: frame.minY,
                          width: frame.width, height: frame.height / 2)
        case .topLeft:
            return CGRect(x: frame.minX, y: frame.midY,
                          width: frame.width / 2, height: frame.height / 2)
        case .topRight:
            return CGRect(x: frame.midX, y: frame.midY,
                          width: frame.width / 2, height: frame.height / 2)
        case .bottomLeft:
            return CGRect(x: frame.minX, y: frame.minY,
                          width: frame.width / 2, height: frame.height / 2)
        case .bottomRight:
            return CGRect(x: frame.midX, y: frame.minY,
                          width: frame.width / 2, height: frame.height / 2)
        case .maximize:
            return frame
        case .center:
            let width = frame.width * 0.7
            let height = frame.height * 0.7
            return CGRect(x: frame.midX - width / 2,
                          y: frame.midY - height / 2,
                          width: width, height: height)
        }
    }

    // MARK: - Coordinate Conversion

    /// Convert from screen coordinates (bottom-left origin, NSScreen) to AX coordinates (top-left origin)
    /// The point should be the bottom-left corner of the window in screen coordinates.
    /// windowHeight is needed because AX expects top-left corner position.
    private func convertToAXPosition(_ bottomLeft: CGPoint, windowHeight: CGFloat) -> CGPoint {
        // Get the primary screen height (menu bar screen)
        guard let primaryScreen = NSScreen.screens.first else { return bottomLeft }
        let primaryHeight = primaryScreen.frame.height

        // NSScreen: origin at bottom-left of primary screen, Y increases upward
        // AX: origin at top-left of primary screen, Y increases downward
        //
        // To convert bottom-left corner to top-left corner for AX:
        // 1. The top of the window in screen coords is: bottomLeft.y + windowHeight
        // 2. Convert to AX Y: primaryHeight - (bottomLeft.y + windowHeight)
        let axY = primaryHeight - bottomLeft.y - windowHeight

        return CGPoint(x: bottomLeft.x, y: axY)
    }
}
