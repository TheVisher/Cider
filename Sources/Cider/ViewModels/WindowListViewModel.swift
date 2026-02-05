import AppKit
import Combine

struct MonitorWindowGroup: Identifiable, Hashable {
    let monitor: MonitorInfo
    var windowGroups: [WindowAppGroup]

    var id: UInt32 { monitor.id }
    var windowCount: Int { windowGroups.reduce(0) { $0 + $1.windows.count } }
}

@MainActor
final class WindowListViewModel: ObservableObject {
    @Published var groups: [WindowAppGroup] = []
    @Published var monitorGroups: [MonitorWindowGroup] = []
    @Published var expandedGroupIDs: Set<String> = []
    @Published var expandedMonitorIDs: Set<UInt32> = []
    @Published var isAccessibilityTrusted: Bool = AccessibilityHelpers.isTrusted()

    let windowManager: WindowManager
    @Published var monitors: [MonitorInfo] = []

    private var cancellable: AnyCancellable?
    private var monitorCancellable: AnyCancellable?
    private var knownGroupIDs: Set<String> = []
    private var knownMonitorIDs: Set<UInt32> = []

    init(windowManager: WindowManager = WindowManager()) {
        self.windowManager = windowManager

        // Subscribe to monitor changes
        monitorCancellable = MonitorManager.shared.$monitors
            .receive(on: DispatchQueue.main)
            .sink { [weak self] monitors in
                self?.monitors = monitors
                self?.refresh()
            }

        monitors = MonitorManager.shared.monitors
        refresh()
        startTimer()
    }

    func refresh() {
        isAccessibilityTrusted = AccessibilityHelpers.isTrusted()
        let allWindows = windowManager.fetchWindows()

        // Filter out windows from manually minimized apps (via Cider's minimize button)
        // These apps should only appear in the pinned apps area, not the window list
        // Note: Auto-hide staged apps should still appear in the window list
        let minimizedPIDs = WindowCache.shared.getManuallyMinimizedPIDs()
        let windows = allWindows.filter { !minimizedPIDs.contains($0.ownerPID) }

        // Group windows by app (legacy, for compact view)
        let grouped = Dictionary(grouping: windows, by: { keyFor(window: $0) })
        let newGroups = grouped.map { (key, windows) -> WindowAppGroup in
            let appName = windows.first?.ownerName ?? key
            let bundleID = windows.first?.bundleIdentifier ?? ""
            let sortedWindows = windows.sorted { $0.displayTitle.lowercased() < $1.displayTitle.lowercased() }
            return WindowAppGroup(id: key, appName: appName, bundleIdentifier: bundleID, windows: sortedWindows)
        }.sorted { $0.appName.lowercased() < $1.appName.lowercased() }

        groups = newGroups

        // Group windows by monitor, then by app
        let windowsByScreen = Dictionary(grouping: windows) { window -> UInt32 in
            window.screenID ?? monitors.first?.id ?? 0
        }

        var newMonitorGroups: [MonitorWindowGroup] = []
        for monitor in monitors {
            let monitorWindows = windowsByScreen[monitor.id] ?? []
            let appGrouped = Dictionary(grouping: monitorWindows, by: { keyFor(window: $0) })
            let appGroups = appGrouped.map { (key, wins) -> WindowAppGroup in
                let appName = wins.first?.ownerName ?? key
                let bundleID = wins.first?.bundleIdentifier ?? ""
                let sortedWindows = wins.sorted { $0.displayTitle.lowercased() < $1.displayTitle.lowercased() }
                return WindowAppGroup(id: key, appName: appName, bundleIdentifier: bundleID, windows: sortedWindows)
            }.sorted { $0.appName.lowercased() < $1.appName.lowercased() }

            newMonitorGroups.append(MonitorWindowGroup(monitor: monitor, windowGroups: appGroups))
        }
        monitorGroups = newMonitorGroups

        // Update expanded states
        let newIDs = Set(groups.map { $0.id })
        if knownGroupIDs.isEmpty {
            expandedGroupIDs = newIDs
        } else {
            let added = newIDs.subtracting(knownGroupIDs)
            expandedGroupIDs.formUnion(added)
            expandedGroupIDs = expandedGroupIDs.intersection(newIDs)
        }
        knownGroupIDs = newIDs

        // Auto-expand new monitors
        let newMonitorIDs = Set(monitors.map { $0.id })
        if knownMonitorIDs.isEmpty {
            expandedMonitorIDs = newMonitorIDs
        } else {
            let addedMonitors = newMonitorIDs.subtracting(knownMonitorIDs)
            expandedMonitorIDs.formUnion(addedMonitors)
            expandedMonitorIDs = expandedMonitorIDs.intersection(newMonitorIDs)
        }
        knownMonitorIDs = newMonitorIDs

        // NOTE: Screen capture disabled - not using live thumbnails in command palette
        // Uncomment when sidebar/thumbnails are re-enabled
        // let visibleWindows = windows.filter { !$0.isMinimized }
        // let visibleWindowIDs = visibleWindows.map { $0.id }
        // let allWindowIDs = Set(windows.map { $0.id })
        // Task { @MainActor in
        //     await WindowPreviewService.shared.startCapturing(windowIDs: visibleWindowIDs)
        //     WindowPreviewService.shared.cleanupPreviews(keepingWindowIDs: allWindowIDs)
        // }
    }

    func focus(window: WindowInfo) {
        let config = CiderConfig.load()
        print("[Cider] Focusing window: \(window.displayTitle), autoHideApps: \(config.autoHideApps)")
        windowManager.focus(window: window, stageOthers: config.autoHideApps)
    }

    func close(window: WindowInfo) {
        windowManager.close(window: window)
        refresh()
    }

    func minimize(window: WindowInfo) {
        windowManager.minimize(window: window)
        refresh()
    }

    func quitApp(for window: WindowInfo) {
        windowManager.quitApp(for: window)
        // Small delay to let the app quit before refreshing
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            await MainActor.run { self?.refresh() }
        }
    }

    func toggleGroup(_ group: WindowAppGroup) {
        if expandedGroupIDs.contains(group.id) {
            expandedGroupIDs.remove(group.id)
        } else {
            expandedGroupIDs.insert(group.id)
        }
    }

    func isExpanded(_ group: WindowAppGroup) -> Bool {
        expandedGroupIDs.contains(group.id)
    }

    func toggleMonitor(_ monitor: MonitorInfo) {
        if expandedMonitorIDs.contains(monitor.id) {
            expandedMonitorIDs.remove(monitor.id)
        } else {
            expandedMonitorIDs.insert(monitor.id)
        }
    }

    func isMonitorExpanded(_ monitor: MonitorInfo) -> Bool {
        expandedMonitorIDs.contains(monitor.id)
    }

    // MARK: - Window Management Actions

    func moveWindow(_ window: WindowInfo, to monitor: MonitorInfo) {
        let config = CiderConfig.load()

        // Check if the window being moved is from the frontmost (focused) app
        let isFocusedWindow = NSWorkspace.shared.frontmostApplication?.processIdentifier == window.ownerPID

        // OPTIMISTIC UI: Immediately update local state to show window in new monitor
        updateWindowMonitor(windowID: window.id, newMonitorID: monitor.id)

        // Move the window (and stage others if auto-hide is enabled and this is focused)
        let shouldStage = config.autoHideApps && isFocusedWindow
        windowManager.moveWindow(window, to: monitor, stageOthers: shouldStage)

        // Refresh to sync with actual window state
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            await MainActor.run { self?.refresh() }
        }
    }

    /// Optimistically update a window's monitor in the local state
    private func updateWindowMonitor(windowID: CGWindowID, newMonitorID: UInt32) {
        // Force view update
        objectWillChange.send()

        // Also update the cache in case this is a hidden/staged window
        WindowCache.shared.updateWindowScreen(windowID, screenID: newMonitorID)

        // Find the window in current groups and move it to the new monitor
        var allWindows: [WindowInfo] = []

        // Collect all windows, updating the moved one's screenID
        for group in groups {
            for var window in group.windows {
                if window.id == windowID {
                    window.screenID = newMonitorID
                }
                allWindows.append(window)
            }
        }

        // Rebuild monitor groups with updated window
        let windowsByScreen = Dictionary(grouping: allWindows) { window -> UInt32 in
            window.screenID ?? monitors.first?.id ?? 0
        }

        var newMonitorGroups: [MonitorWindowGroup] = []
        for monitor in monitors {
            let monitorWindows = windowsByScreen[monitor.id] ?? []
            let appGrouped = Dictionary(grouping: monitorWindows, by: { keyFor(window: $0) })
            let appGroups = appGrouped.map { (key, wins) -> WindowAppGroup in
                let appName = wins.first?.ownerName ?? key
                let bundleID = wins.first?.bundleIdentifier ?? ""
                let sortedWindows = wins.sorted { $0.displayTitle.lowercased() < $1.displayTitle.lowercased() }
                return WindowAppGroup(id: key, appName: appName, bundleIdentifier: bundleID, windows: sortedWindows)
            }.sorted { $0.appName.lowercased() < $1.appName.lowercased() }

            newMonitorGroups.append(MonitorWindowGroup(monitor: monitor, windowGroups: appGroups))
        }
        monitorGroups = newMonitorGroups

        // Also update the flat groups
        let grouped = Dictionary(grouping: allWindows, by: { keyFor(window: $0) })
        groups = grouped.map { (key, windows) -> WindowAppGroup in
            let appName = windows.first?.ownerName ?? key
            let bundleID = windows.first?.bundleIdentifier ?? ""
            let sortedWindows = windows.sorted { $0.displayTitle.lowercased() < $1.displayTitle.lowercased() }
            return WindowAppGroup(id: key, appName: appName, bundleIdentifier: bundleID, windows: sortedWindows)
        }.sorted { $0.appName.lowercased() < $1.appName.lowercased() }
    }

    func tileWindow(_ window: WindowInfo, position: TilePosition) {
        // Find the monitor this window is on
        guard let screenID = window.screenID,
              let monitor = monitors.first(where: { $0.id == screenID }) else {
            // Fall back to primary monitor
            guard let primaryMonitor = monitors.first else { return }
            windowManager.tileWindow(window, position: position, on: primaryMonitor)
            refresh()
            return
        }
        windowManager.tileWindow(window, position: position, on: monitor)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            await MainActor.run {
                self?.refresh()
            }
        }
    }

    func splitWindows(_ window1: WindowInfo, _ window2: WindowInfo, leftRight: Bool = true) {
        // Use the screen of the first window
        guard let screenID = window1.screenID,
              let monitor = monitors.first(where: { $0.id == screenID }) else {
            guard let primaryMonitor = monitors.first else { return }
            windowManager.splitWindows(window1, window2, on: primaryMonitor, leftRight: leftRight)
            refresh()
            return
        }
        windowManager.splitWindows(window1, window2, on: monitor, leftRight: leftRight)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            await MainActor.run {
                self?.refresh()
            }
        }
    }

    private func keyFor(window: WindowInfo) -> String {
        if !window.bundleIdentifier.isEmpty {
            return window.bundleIdentifier
        }
        return "\(window.ownerName)-\(window.ownerPID)"
    }

    private func startTimer() {
        cancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }
}
