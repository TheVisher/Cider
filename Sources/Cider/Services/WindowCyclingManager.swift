import AppKit
import Combine

/// Tracks app activation order for MRU (Most Recently Used) sorting
final class AppActivationTracker: @unchecked Sendable {
    static let shared = AppActivationTracker()

    /// Bundle identifiers in MRU order (index 0 = most recent)
    private var activationOrder: [String] = []
    private let lock = NSLock()

    private var observer: NSObjectProtocol?

    private init() {
        startTracking()
    }

    private func startTracking() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }

            self?.recordActivation(bundleID)
        }

        // Initialize with currently running apps (frontmost first)
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           let bundleID = frontApp.bundleIdentifier {
            lock.lock()
            activationOrder = [bundleID]
            lock.unlock()
        }
    }

    func recordActivation(_ bundleID: String) {
        lock.lock()
        defer { lock.unlock() }

        // Remove if already in list, then add to front
        activationOrder.removeAll { $0 == bundleID }
        activationOrder.insert(bundleID, at: 0)

        // Keep list reasonable size
        if activationOrder.count > 50 {
            activationOrder = Array(activationOrder.prefix(50))
        }
    }

    /// Get MRU rank for a bundle ID (lower = more recent, nil = never activated)
    func rank(for bundleID: String) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return activationOrder.firstIndex(of: bundleID)
    }
}

/// Manages window cycling session state for Option+Tab
@MainActor
final class WindowCyclingManager: ObservableObject {
    @Published private(set) var windows: [WindowInfo] = []
    @Published private(set) var selectedIndex: Int = 0
    @Published private(set) var isActive: Bool = false

    private let windowManager: WindowManager
    private let cycleAllScreens: () -> Bool  // Closure to get current setting

    var selectedWindow: WindowInfo? {
        guard !windows.isEmpty, selectedIndex >= 0, selectedIndex < windows.count else {
            return nil
        }
        return windows[selectedIndex]
    }

    init(windowManager: WindowManager = WindowManager(), cycleAllScreens: @escaping () -> Bool = { true }) {
        self.windowManager = windowManager
        self.cycleAllScreens = cycleAllScreens

        // Ensure activation tracker is initialized
        _ = AppActivationTracker.shared
    }

    /// Start a new cycling session
    /// - Parameter initialDirection: 1 for forward (Tab), -1 for backward (Shift+Tab), 0 for no movement
    func startCycling(initialDirection: Int = 1) {
        guard !isActive else { return }

        var allWindows = windowManager.fetchWindows()

        // Optionally filter to current screen only
        if !cycleAllScreens() {
            let mouseLocation = NSEvent.mouseLocation
            if let currentScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }),
               let currentScreenID = MonitorManager.shared.monitors.first(where: {
                   // Match by frame origin
                   abs($0.frame.origin.x - currentScreen.frame.origin.x) < 1 &&
                   abs($0.frame.origin.y - currentScreen.frame.origin.y) < 1
               })?.id {
                allWindows = allWindows.filter { $0.screenID == currentScreenID }
            }
        }

        // Remove duplicates (same app, same title)
        var seen: Set<String> = []
        allWindows = allWindows.filter { window in
            let key = "\(window.bundleIdentifier)-\(window.title)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }

        // Sort by MRU (Most Recently Used) order
        let tracker = AppActivationTracker.shared
        allWindows.sort { w1, w2 in
            let rank1 = tracker.rank(for: w1.bundleIdentifier) ?? Int.max
            let rank2 = tracker.rank(for: w2.bundleIdentifier) ?? Int.max
            return rank1 < rank2
        }

        guard !allWindows.isEmpty else {
            print("[WindowCyclingManager] No windows to cycle")
            return
        }

        windows = allWindows
        isActive = true

        // Set initial selection based on direction
        // Forward (Tab): Start at index 1 (previous app) - traditional Alt+Tab behavior
        // Backward (Shift+Tab): Start at last index
        // No direction: Start at index 0 (current app)
        if initialDirection > 0 && allWindows.count > 1 {
            selectedIndex = 1  // Previous app
        } else if initialDirection < 0 && allWindows.count > 1 {
            selectedIndex = allWindows.count - 1  // Last app
        } else {
            selectedIndex = 0  // Current app
        }

        print("[WindowCyclingManager] Started cycling with \(windows.count) windows, selected: \(selectedIndex)")
        for (i, w) in windows.prefix(5).enumerated() {
            let rank = AppActivationTracker.shared.rank(for: w.bundleIdentifier) ?? -1
            print("  [\(i)] \(w.ownerName) (rank: \(rank))\(i == selectedIndex ? " <--" : "")")
        }
    }

    /// Move selection to next window
    func cycleNext() {
        guard isActive, !windows.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % windows.count
        print("[WindowCyclingManager] Cycled next: index \(selectedIndex)")
    }

    /// Move selection to previous window
    func cyclePrevious() {
        guard isActive, !windows.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + windows.count) % windows.count
        print("[WindowCyclingManager] Cycled previous: index \(selectedIndex)")
    }

    /// Commit selection - focus the selected window
    func commitSelection() {
        guard isActive, let window = selectedWindow else {
            cancelCycling()
            return
        }

        print("[WindowCyclingManager] Committing selection: \(window.displayTitle)")

        let config = CiderConfig.load()
        windowManager.focus(window: window, stageOthers: config.autoHideApps)

        endSession()
    }

    /// Cancel cycling without changing window focus
    func cancelCycling() {
        print("[WindowCyclingManager] Cancelled cycling")
        endSession()
    }

    private func endSession() {
        isActive = false
        windows = []
        selectedIndex = 0
    }
}
