import AppKit
import Foundation

@MainActor
final class SavedTileLayoutManager: ObservableObject {
    static let shared = SavedTileLayoutManager()

    @Published var layouts: [SavedTileLayout] = []

    private let storageKey = "SavedTileLayouts"
    private let appLauncher = AppLauncher()

    init() {
        load()
    }

    // MARK: - CRUD

    /// Save the current tile group as a persistent layout.
    func saveCurrentGroup(groupID: UUID) {
        guard let group = DynamicTileManager.shared.group(for: groupID) else { return }

        let savedRoot = convertToSavedNode(group.root)
        let screenIndex = screenIndex(for: group.screenID)

        let layout = SavedTileLayout(
            root: savedRoot,
            targetScreenIndex: screenIndex,
            gap: group.gap
        )

        layouts.append(layout)
        persist()
    }

    func deleteLayout(_ layout: SavedTileLayout) {
        layouts.removeAll { $0.id == layout.id }
        persist()
    }

    func renameLayout(_ layout: SavedTileLayout, to newName: String) {
        guard let idx = layouts.firstIndex(where: { $0.id == layout.id }) else { return }
        layouts[idx].name = newName
        persist()
    }

    func moveLayoutToMonitor(_ layout: SavedTileLayout, screenIndex: Int) {
        guard let idx = layouts.firstIndex(where: { $0.id == layout.id }) else { return }
        layouts[idx].targetScreenIndex = screenIndex
        persist()
    }

    // MARK: - Restore

    /// Restore a saved layout: launch missing apps, collect windows, re-tile.
    func restoreLayout(_ layout: SavedTileLayout) {
        let apps = layout.root.apps
        let targetScreenID = screenID(for: layout.targetScreenIndex)

        Task { @MainActor in
            // Track which window IDs we've claimed so the same window isn't used twice
            var claimedWindowIDs = Set<CGWindowID>()
            var resolvedLeaves: [(bundleID: String, windowID: CGWindowID, pid: pid_t)] = []

            for app in apps {
                // Check if app is already running
                let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).first

                if let running, !running.isTerminated {
                    // App running — grab frontmost unclaimed window
                    if let (wid, pid) = findWindow(for: running.processIdentifier, excluding: claimedWindowIDs) {
                        claimedWindowIDs.insert(wid)
                        resolvedLeaves.append((app.bundleIdentifier, wid, pid))
                        continue
                    }
                }

                // App not running or no unclaimed window — launch it
                let appInfo = AppInfo(name: app.appName, bundleIdentifier: app.bundleIdentifier, path: app.appPath)
                appLauncher.launchOrFocus(appInfo)

                // Poll for window appearance (200ms intervals, up to 10s)
                var found = false
                for _ in 0..<50 {
                    try? await Task.sleep(nanoseconds: 200_000_000)

                    guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).first,
                          !runningApp.isTerminated else { continue }

                    if let (wid, pid) = findWindow(for: runningApp.processIdentifier, excluding: claimedWindowIDs) {
                        claimedWindowIDs.insert(wid)
                        resolvedLeaves.append((app.bundleIdentifier, wid, pid))
                        found = true
                        break
                    }
                }

                if !found {
                    NSLog("[SavedTileLayoutManager] Timeout waiting for window: \(app.appName)")
                }
            }

            // Build live TileNode tree from resolved leaves
            guard resolvedLeaves.count >= 2 else {
                NSLog("[SavedTileLayoutManager] Not enough windows resolved (\(resolvedLeaves.count)) to restore layout")
                return
            }

            var leafIndex = 0
            let liveRoot = buildLiveNode(from: layout.root, resolvedLeaves: resolvedLeaves, index: &leafIndex)
            guard let liveRoot else {
                NSLog("[SavedTileLayoutManager] Failed to build live node tree")
                return
            }

            let group = TileGroup(screenID: targetScreenID, root: liveRoot, gap: layout.gap)
            DynamicTileManager.shared.registerRestoredGroup(group)
        }
    }

    // MARK: - Conversion Helpers

    /// Convert a live TileNode tree to a SavedTileNode tree using NSRunningApplication lookups.
    private func convertToSavedNode(_ node: TileNode) -> SavedTileNode {
        switch node {
        case .leaf(_, let pid):
            let running = NSRunningApplication(processIdentifier: pid)
            let bundleID = running?.bundleIdentifier ?? ""
            let appName = running?.localizedName ?? ""
            let appPath = running?.bundleURL?.path ?? ""
            return .leaf(bundleIdentifier: bundleID, appName: appName, appPath: appPath)

        case .split(let orientation, let ratio, let left, let right):
            return .split(
                orientation: orientation,
                ratio: ratio,
                left: convertToSavedNode(left),
                right: convertToSavedNode(right)
            )
        }
    }

    /// Build a live TileNode tree from a SavedTileNode, mapping leaves to resolved windows in order.
    private func buildLiveNode(from saved: SavedTileNode, resolvedLeaves: [(bundleID: String, windowID: CGWindowID, pid: pid_t)], index: inout Int) -> TileNode? {
        switch saved {
        case .leaf:
            guard index < resolvedLeaves.count else { return nil }
            let leaf = resolvedLeaves[index]
            index += 1
            return .leaf(windowID: leaf.windowID, pid: leaf.pid)

        case .split(let orientation, let ratio, let left, let right):
            guard let liveLeft = buildLiveNode(from: left, resolvedLeaves: resolvedLeaves, index: &index),
                  let liveRight = buildLiveNode(from: right, resolvedLeaves: resolvedLeaves, index: &index) else {
                return nil
            }
            return .split(orientation: orientation, ratio: ratio, left: liveLeft, right: liveRight)
        }
    }

    /// Find a window for a PID that isn't already claimed.
    private func findWindow(for pid: pid_t, excluding claimed: Set<CGWindowID>) -> (CGWindowID, pid_t)? {
        let cgOptions: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(cgOptions, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for info in infoList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else { continue }
            guard let wid = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }

            // Check minimum size
            if let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
               let w = boundsDict["Width"], let h = boundsDict["Height"],
               w < 50 || h < 50 { continue }

            if !claimed.contains(wid) {
                return (wid, pid)
            }
        }
        return nil
    }

    /// Convert a screenID to a stable screen index (0 = primary).
    private func screenIndex(for screenID: UInt32) -> Int {
        let screens = NSScreen.screens
        for (index, screen) in screens.enumerated() {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
               number.uint32Value == screenID {
                return index
            }
        }
        return 0
    }

    /// Convert a screen index back to a screenID.
    private func screenID(for index: Int) -> UInt32 {
        let screens = NSScreen.screens
        let safeIndex = min(index, screens.count - 1)
        guard safeIndex >= 0, safeIndex < screens.count else {
            // Fallback to primary
            if let primary = screens.first,
               let number = primary.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                return number.uint32Value
            }
            return 0
        }
        if let number = screens[safeIndex].deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.uint32Value
        }
        return 0
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            layouts = []
            return
        }
        do {
            layouts = try JSONDecoder().decode([SavedTileLayout].self, from: data)
        } catch {
            NSLog("[SavedTileLayoutManager] Failed to decode layouts: \(error)")
            layouts = []
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(layouts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
