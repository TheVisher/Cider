import AppKit
import Combine

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
    }

    /// Start a new cycling session
    func startCycling() {
        guard !isActive else { return }

        // Fetch windows sorted by most-recent (we'll use Z-order as approximation)
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

        guard !allWindows.isEmpty else {
            print("[WindowCyclingManager] No windows to cycle")
            return
        }

        windows = allWindows
        selectedIndex = 0
        isActive = true

        print("[WindowCyclingManager] Started cycling with \(windows.count) windows")
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
