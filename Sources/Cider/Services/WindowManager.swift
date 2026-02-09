import AppKit
import ApplicationServices

/// Wrapper to send AXUIElement across isolation boundaries.
/// AXUIElement is a thread-safe CF handle but isn't marked Sendable.
struct SendableAXElement: @unchecked Sendable {
    let element: AXUIElement
    init(_ element: AXUIElement) { self.element = element }
}

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
    case almostMaximize
    case center
    case firstThird
    case centerThird
    case lastThird
    case firstTwoThirds
    case lastTwoThirds

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
        case .almostMaximize: return "Almost Maximize"
        case .center: return "Center"
        case .firstThird: return "First Third"
        case .centerThird: return "Center Third"
        case .lastThird: return "Last Third"
        case .firstTwoThirds: return "First Two Thirds"
        case .lastTwoThirds: return "Last Two Thirds"
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
        case .almostMaximize: return "rectangle.inset.filled"
        case .center: return "rectangle.center.inset.filled"
        case .firstThird: return "rectangle.leadinghalf.inset.filled"
        case .centerThird: return "rectangle.center.inset.filled"
        case .lastThird: return "rectangle.trailinghalf.inset.filled"
        case .firstTwoThirds: return "rectangle.lefthalf.filled"
        case .lastTwoThirds: return "rectangle.righthalf.filled"
        }
    }

    var shortcutLabel: String {
        switch self {
        case .left: return "⌃⌥←"
        case .right: return "⌃⌥→"
        case .top: return "⌃⌥↑"
        case .bottom: return "⌃⌥↓"
        case .topLeft: return "⌃⌥U"
        case .topRight: return "⌃⌥I"
        case .bottomLeft: return "⌃⌥J"
        case .bottomRight: return "⌃⌥K"
        case .maximize: return "⌃⌥↩"
        case .almostMaximize: return "⌃⌥⇧↩"
        case .center: return "⌃⌥C"
        case .firstThird: return "⌃⌥D"
        case .centerThird: return "⌃⌥F"
        case .lastThird: return "⌃⌥G"
        case .firstTwoThirds: return "⌃⌥E"
        case .lastTwoThirds: return "⌃⌥T"
        }
    }

    static var halves: [TilePosition] { [.left, .right, .top, .bottom] }
    static var quarters: [TilePosition] { [.topLeft, .topRight, .bottomLeft, .bottomRight] }
    static var thirds: [TilePosition] { [.firstThird, .centerThird, .lastThird] }
    static var twoThirds: [TilePosition] { [.firstTwoThirds, .lastTwoThirds] }
    static var other: [TilePosition] { [.maximize, .almostMaximize, .center] }
}

enum TileAction {
    case tile(TilePosition)
    case larger
    case smaller
    case restore
    case nextDisplay
    case previousDisplay
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
    /// Threshold for distinguishing real CGWindowList IDs from pseudo-IDs generated for AX-only windows
    private static let pseudoWindowIDThreshold: CGWindowID = 1_000_000

    /// Generate a stable pseudo window ID for windows discovered via Accessibility API that lack a CGWindowID
    private static func generatePseudoWindowID(pid: pid_t, index: Int) -> CGWindowID {
        CGWindowID(Int(pid) * 1000 + index + Int(pseudoWindowIDThreshold))
    }

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

    /// Shared CGWindowList parsing: returns on-screen windows with all standard filtering applied.
    /// Both `fetchWindowsRaw()` and `fetchVisibleWindowsOnly()` use this as their foundation.
    private func parseOnScreenWindows() -> [WindowInfo] {
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

            // Filter out our own app
            if let running = NSRunningApplication(processIdentifier: ownerPID),
               running.bundleIdentifier == ownBundle { return nil }

            // Filter out system processes
            if Self.filteredOwners.contains(ownerName) { return nil }

            let title = info[kCGWindowName as String] as? String ?? ""

            // Filter out system window titles
            for pattern in Self.filteredTitlePatterns {
                if title.localizedCaseInsensitiveContains(pattern) { return nil }
            }

            // Extract window bounds
            var windowBounds = CGRect.zero
            if let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
               let x = boundsDict["X"], let y = boundsDict["Y"],
               let w = boundsDict["Width"], let h = boundsDict["Height"] {
                windowBounds = CGRect(x: x, y: y, width: w, height: h)
                if w < 50 || h < 50 { return nil }
            }

            if let alpha = info[kCGWindowAlpha as String] as? CGFloat, alpha < 0.1 { return nil }

            let bundleIdentifier = NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier ?? ""

            // Filter out Finder's special windows (Desktop, empty title windows)
            if bundleIdentifier == "com.apple.finder" && Self.filteredFinderTitles.contains(title) {
                return nil
            }

            let screenID = MonitorManager.shared.screenForWindow(windowBounds)?.id

            return WindowInfo(id: windowID, ownerPID: ownerPID, ownerName: ownerName,
                              title: title, bundleIdentifier: bundleIdentifier,
                              bounds: windowBounds, screenID: screenID)
        }
    }

    private func fetchWindowsRaw() -> [WindowInfo] {
        let ownBundle = Bundle.main.bundleIdentifier

        // PART 1: Get on-screen windows from CGWindowList (for accurate bounds and window IDs)
        var windows = parseOnScreenWindows()
        var seenWindowIDs = Set(windows.map { $0.id })

        // PART 2: Use Accessibility API to find minimized AND hidden windows
        // Visible windows are already captured by CGWindowList above
        // Hidden apps (via app.hide()) and minimized windows need AX to be seen
        guard AccessibilityHelpers.isTrusted() else { return windows }

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
                let finalWindowID = windowID ?? Self.generatePseudoWindowID(pid: pid, index: index)

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

    // CGWindowList only, for staging logic — no AX API overhead
    private func fetchVisibleWindowsOnly() -> [WindowInfo] {
        return deduplicateWindows(parseOnScreenWindows())
    }

    /// Remove duplicate windows from the same app with identical titles
    /// Prefers visible windows over minimized, and windows with valid IDs over pseudo-IDs
    /// Only deduplicates when one window has a pseudo-ID (likely a duplicate discovery).
    /// Two windows with different real IDs but same title are kept (e.g., two "New Tab" in Chrome).
    private func deduplicateWindows(_ windows: [WindowInfo]) -> [WindowInfo] {
        var seen: [String: WindowInfo] = [:]

        for window in windows {
            // Only dedup when one window has a pseudo-ID (AX-discovered duplicate
            // of a CGWindowList window). Two real window IDs with the same title
            // are legitimately different windows (e.g., two "New Tab" in Chrome).
            let hasPseudoID = window.id >= Self.pseudoWindowIDThreshold
            let key: String
            if hasPseudoID {
                // Pseudo-ID window: match by bundle + title (may be a duplicate)
                key = "\(window.bundleIdentifier)-\(window.title)"
            } else {
                // Real window ID: use it directly (unique per window)
                key = "\(window.bundleIdentifier)-wid:\(window.id)"
            }

            if let existing = seen[key] {
                // Prefer non-minimized over minimized
                if existing.isMinimized && !window.isMinimized {
                    seen[key] = window
                }
                // Prefer real window IDs over pseudo-IDs
                else if existing.id >= Self.pseudoWindowIDThreshold && window.id < Self.pseudoWindowIDThreshold {
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

    /// Activate an app and raise a specific window to the front.
    /// Used by completeFocus and tileWindow to bring a window forward before acting on it.
    private func activateAndRaise(window: WindowInfo, axWindow: AXUIElement) {
        guard let targetApp = NSRunningApplication(processIdentifier: window.ownerPID) else { return }
        _ = targetApp.activate(options: [.activateAllWindows])
        let appElement = AccessibilityHelpers.appElement(for: window.ownerPID)
        _ = AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, axWindow)
        _ = AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
    }

    private func completeFocus(window: WindowInfo, targetApp: NSRunningApplication, stageOthers: Bool) {
        // STEP 2: Activate target app and raise the specific window
        _ = targetApp.activate(options: [.activateAllWindows])

        // STEP 3: Find and raise the specific window
        if let target = findAXWindow(for: window) {
            activateAndRaise(window: window, axWindow: target)
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

        // STEP 5: Re-activate and raise to ensure window stays in front after hiding others
        if let target = findAXWindow(for: window) {
            activateAndRaise(window: window, axWindow: target)
        } else {
            _ = targetApp.activate(options: [])
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

    /// Stage (hide) other regular apps except the one with the given PID.
    /// If `onScreenID` is provided, only stages apps that have windows on that screen.
    func stageOtherApps(exceptPID targetPID: pid_t, onScreenID: UInt32? = nil) {
        let cache = WindowCache.shared
        let ownBundle = Bundle.main.bundleIdentifier
        let currentWindows = fetchVisibleWindowsOnly()

        // Collect PIDs to stage — optionally filtered by screen
        var pidsToStage: Set<pid_t> = []
        for window in currentWindows {
            if window.ownerPID == targetPID { continue }
            if let screenID = onScreenID, window.screenID != screenID { continue }
            pidsToStage.insert(window.ownerPID)
        }

        for pid in pidsToStage {
            if cache.isStaged(pid) { continue }
            guard let app = NSRunningApplication(processIdentifier: pid) else { continue }
            if app.bundleIdentifier == ownBundle { continue }
            if let bundleID = app.bundleIdentifier, Self.excludedFromStaging.contains(bundleID) { continue }
            if app.activationPolicy != .regular { continue }
            if app.isHidden { continue }

            let appWindows = currentWindows.filter { $0.ownerPID == pid }
            guard !appWindows.isEmpty else { continue }

            cache.stageWindows(for: pid, windows: appWindows)
            let windowIDs = appWindows.map { $0.id }
            WindowPreviewService.shared.prepareForHiding(windowIDs: windowIDs)
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

    /// Padding around windows when moved to a new monitor (like Rectangle's "almost maximize").
    /// Also used as the step size for larger/smaller hotkeys.
    static let windowPadding: CGFloat = 20
    /// Tolerance for frame verification after AX resize
    private static let frameApplyTolerance: CGFloat = 20

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
            Self.runAppleScriptResize(pid: window.ownerPID, axPosition: axPoint, size: newSize)
        }

        // Stage other apps on the destination monitor if requested
        if stageOthers {
            stageAppsOnMonitor(screen.id, except: window.ownerPID)
        }
    }

    /// Move an app's front window to the given screen using the same logic as drag-drop move.
    /// Returns true if a window was found and moved.
    @discardableResult
    func moveAppToScreen(pid: pid_t, screen: MonitorInfo) -> Bool {
        // Find the app's visible windows
        let appWindows = fetchVisibleWindowsOnly().filter { $0.ownerPID == pid }
        guard let window = appWindows.first else { return false }

        // Skip if already on the target screen
        if window.screenID == screen.id { return true }

        // Use the existing moveWindow which handles AX + AppleScript fallback
        moveWindow(window, to: screen)
        return true
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

    /// Tile a window to a position on a screen.
    /// - Parameter onComplete: Called on MainActor when the tile operation finishes.
    ///   For fullscreen windows the work is async, so this fires later.
    ///   The Bool indicates whether the frame was applied successfully.
    @discardableResult
    func tileWindow(_ window: WindowInfo, position: TilePosition, on screen: MonitorInfo,
                    onComplete: (@MainActor @Sendable (Bool) -> Void)? = nil) -> Bool {
        guard let axWindow = findAXWindow(for: window) else {
            onComplete?(false)
            return false
        }

        // Exit fullscreen if needed — done asynchronously to avoid blocking the main thread
        // (exitFullScreen polls with usleep for up to ~1s)
        if AccessibilityHelpers.isFullScreen(axWindow) {
            // Bridge AXUIElement across isolation — it's a thread-safe CF handle
            let ax = SendableAXElement(axWindow)
            let windowCopy = window
            Task.detached {
                let exited = AccessibilityHelpers.exitFullScreen(ax.element)
                guard exited else {
                    await onComplete?(false)
                    return
                }
                // Brief pause for fullscreen exit animation to settle
                try? await Task.sleep(nanoseconds: 200_000_000)
                let result = await MainActor.run {
                    WindowManager().applyTileFrame(windowCopy, axWindow: ax.element, position: position, on: screen)
                }
                await onComplete?(result)
            }
            // Async work dispatched — caller should NOT treat this as "done"
            return false
        }

        let result = applyTileFrame(window, axWindow: axWindow, position: position, on: screen)
        // Safe to call directly — we're already on @MainActor and callback is @MainActor
        onComplete?(result)
        return result
    }

    @discardableResult
    private func applyTileFrame(_ window: WindowInfo, axWindow: AXUIElement, position: TilePosition, on screen: MonitorInfo) -> Bool {
        // Activate and raise so AppleScript fallback targets the correct window
        activateAndRaise(window: window, axWindow: axWindow)

        let frame = calculateTileFrame(position: position, on: screen)
        return applyWindowFrame(window, axWindow: axWindow, origin: CGPoint(x: frame.minX, y: frame.minY), size: frame.size)
    }

    func splitWindows(_ window1: WindowInfo, _ window2: WindowInfo, on screen: MonitorInfo, leftRight: Bool = true,
                       onComplete: (@MainActor @Sendable () -> Void)? = nil) {
        guard let ax1 = findAXWindow(for: window1),
              let ax2 = findAXWindow(for: window2) else {
            onComplete?()
            return
        }

        let needsFullscreenExit = AccessibilityHelpers.isFullScreen(ax1) || AccessibilityHelpers.isFullScreen(ax2)

        if needsFullscreenExit {
            let sax1 = SendableAXElement(ax1)
            let sax2 = SendableAXElement(ax2)
            let w1 = window1, w2 = window2
            Task.detached {
                // Exit fullscreen for both if needed
                if AccessibilityHelpers.isFullScreen(sax1.element) {
                    let exited = AccessibilityHelpers.exitFullScreen(sax1.element)
                    if !exited {
                        await onComplete?()
                        return
                    }
                }
                if AccessibilityHelpers.isFullScreen(sax2.element) {
                    let exited = AccessibilityHelpers.exitFullScreen(sax2.element)
                    if !exited {
                        await onComplete?()
                        return
                    }
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
                await MainActor.run {
                    WindowManager().applySplitFrames(w1, ax1: sax1.element, w2, ax2: sax2.element, on: screen, leftRight: leftRight)
                }
                await onComplete?()
            }
        } else {
            applySplitFrames(window1, ax1: ax1, window2, ax2: ax2, on: screen, leftRight: leftRight)
            onComplete?()
        }
    }

    private func applySplitFrames(_ window1: WindowInfo, ax1: AXUIElement,
                                  _ window2: WindowInfo, ax2: AXUIElement,
                                  on screen: MonitorInfo, leftRight: Bool) {
        let frame1: CGRect
        let frame2: CGRect

        if leftRight {
            frame1 = calculateTileFrame(position: .left, on: screen)
            frame2 = calculateTileFrame(position: .right, on: screen)
        } else {
            frame1 = calculateTileFrame(position: .top, on: screen)
            frame2 = calculateTileFrame(position: .bottom, on: screen)
        }

        activateAndRaise(window: window1, axWindow: ax1)
        applyWindowFrame(window1, axWindow: ax1, origin: CGPoint(x: frame1.minX, y: frame1.minY), size: frame1.size)

        activateAndRaise(window: window2, axWindow: ax2)
        applyWindowFrame(window2, axWindow: ax2, origin: CGPoint(x: frame2.minX, y: frame2.minY), size: frame2.size)
    }

    func calculateTileFrame(position: TilePosition, on screen: MonitorInfo) -> CGRect {
        Self.calculateTileFrameStatic(position: position, on: screen)
    }

    static func calculateTileFrameStatic(position: TilePosition, on screen: MonitorInfo) -> CGRect {
        let frame = screen.visibleFrame
        let padding = windowPadding

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
        case .almostMaximize:
            return CGRect(x: frame.minX + padding, y: frame.minY + padding,
                          width: frame.width - padding * 2, height: frame.height - padding * 2)
        case .center:
            let width = frame.width * 0.7
            let height = frame.height * 0.7
            return CGRect(x: frame.midX - width / 2,
                          y: frame.midY - height / 2,
                          width: width, height: height)
        case .firstThird:
            return CGRect(x: frame.minX, y: frame.minY,
                          width: frame.width / 3, height: frame.height)
        case .centerThird:
            return CGRect(x: frame.minX + frame.width / 3, y: frame.minY,
                          width: frame.width / 3, height: frame.height)
        case .lastThird:
            return CGRect(x: frame.minX + frame.width * 2 / 3, y: frame.minY,
                          width: frame.width / 3, height: frame.height)
        case .firstTwoThirds:
            return CGRect(x: frame.minX, y: frame.minY,
                          width: frame.width * 2 / 3, height: frame.height)
        case .lastTwoThirds:
            return CGRect(x: frame.minX + frame.width / 3, y: frame.minY,
                          width: frame.width * 2 / 3, height: frame.height)
        }
    }

    // MARK: - Coordinate Conversion

    /// Convert from screen coordinates (bottom-left origin, NSScreen) to AX coordinates (top-left origin)
    /// The point should be the bottom-left corner of the window in screen coordinates.
    /// windowHeight is needed because AX expects top-left corner position.
    private func convertToAXPosition(_ bottomLeft: CGPoint, windowHeight: CGFloat) -> CGPoint {
        AccessibilityHelpers.convertToAXCoordinates(bottomLeft, windowHeight: windowHeight)
    }

    /// Applies frame using the three-step pattern (size → position → size), with Enhanced UI
    /// toggle, verify/retry, and AppleScript as absolute last resort. Returns true on success.
    @discardableResult
    private func applyWindowFrame(_ window: WindowInfo, axWindow: AXUIElement, origin: CGPoint, size: CGSize) -> Bool {
        let pid = window.ownerPID
        let hadEnhancedUI = AccessibilityHelpers.getEnhancedUI(for: pid) == true
        if hadEnhancedUI {
            AccessibilityHelpers.setEnhancedUI(for: pid, enabled: false)
        }
        defer {
            if hadEnhancedUI {
                AccessibilityHelpers.setEnhancedUI(for: pid, enabled: true)
            }
        }

        // Two attempts with AX before falling back to AppleScript
        for attempt in 0..<2 {
            if attempt > 0 {
                usleep(20_000) // 20ms between retries
            }

            // Three-step apply: size → position → size (Rectangle/yabai pattern)
            AccessibilityHelpers.setWindowSize(axWindow, to: size)
            let axPoint = convertToAXPosition(origin, windowHeight: size.height)
            AccessibilityHelpers.setWindowPosition(axWindow, to: axPoint)
            AccessibilityHelpers.setWindowSize(axWindow, to: size)

            // Verify final frame
            if verifyFrame(axWindow, expectedOrigin: axPoint, expectedSize: size) {
                return true
            }
        }

        // AppleScript as absolute last resort — fire-and-forget, result unknown
        applyWindowFrameWithAppleScript(window: window, origin: origin, size: size)
        return false
    }

    /// Check whether the window's actual frame is within tolerance of the expected values.
    private func verifyFrame(_ axWindow: AXUIElement, expectedOrigin: CGPoint, expectedSize: CGSize) -> Bool {
        guard let actualPos = AccessibilityHelpers.getWindowPosition(axWindow),
              let actualSize = AccessibilityHelpers.getWindowSize(axWindow) else {
            return false
        }
        let tol = Self.frameApplyTolerance
        return abs(actualPos.x - expectedOrigin.x) <= tol &&
               abs(actualPos.y - expectedOrigin.y) <= tol &&
               abs(actualSize.width - expectedSize.width) <= tol &&
               abs(actualSize.height - expectedSize.height) <= tol
    }

    private func applyWindowFrameWithAppleScript(window: WindowInfo, origin: CGPoint, size: CGSize) {
        let axPoint = convertToAXPosition(origin, windowHeight: size.height)
        Self.runAppleScriptResize(pid: window.ownerPID, axPosition: axPoint, size: size)
    }

    /// Fire-and-forget AppleScript resize+move via System Events. Used when AX fails.
    static func runAppleScriptResize(pid: pid_t, axPosition: CGPoint, size: CGSize) {
        let script = """
        tell application "System Events"
            tell (first process whose unix id is \(pid))
                set size of window 1 to {\(Int(size.width)), \(Int(size.height))}
                set position of window 1 to {\(Int(axPosition.x)), \(Int(axPosition.y))}
            end tell
        end tell
        """

        Task.detached {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", script]
            do {
                try task.run()
            } catch {
                return
            }

            // 3-second timeout: terminate the process if it hasn't exited
            let timeoutItem = DispatchWorkItem {
                if task.isRunning {
                    task.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: timeoutItem)
            task.waitUntilExit()
            timeoutItem.cancel()
        }
    }

    /// Apply an arbitrary frame to an AX window element (used by TileActionHandler for larger/smaller/restore).
    @discardableResult
    func applyFrame(axWindow: AXUIElement, pid: pid_t, origin: CGPoint, size: CGSize) -> Bool {
        let app = NSRunningApplication(processIdentifier: pid)
        let ownerName = app?.localizedName ?? "Unknown"
        let bundleID = app?.bundleIdentifier ?? ""
        let window = WindowInfo(id: 0, ownerPID: pid, ownerName: ownerName, title: "", bundleIdentifier: bundleID)
        return applyWindowFrame(window, axWindow: axWindow, origin: origin, size: size)
    }
}
