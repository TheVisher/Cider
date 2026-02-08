import AppKit
import ApplicationServices
@preconcurrency import Combine

@MainActor
final class DynamicTileManager {
    static let shared = DynamicTileManager()

    private var groups: [UUID: TileGroup] = [:]
    private var windowToGroup: [CGWindowID: UUID] = [:]
    private var observers: [pid_t: (observer: AXObserver, windowCount: Int)] = [:]
    private var expectedFrames: [CGWindowID: CGRect] = [:]
    private var pendingCoalesce: [CGWindowID: DispatchWorkItem] = [:]
    private var monitorCancellable: AnyCancellable?
    private var terminationObserver: NSObjectProtocol?

    /// Windows currently being tiled by us — AX events for these are ignored.
    /// Follows the AeroSpace/yabai pattern for feedback loop prevention.
    private var currentlyTilingWindowIDs: Set<CGWindowID> = []

    /// Tolerance (in points) for expected-frame comparison when debouncing AX resize events.
    private let frameTolerance: CGFloat = 2

    init() {
        // Recompute all groups when monitors change
        monitorCancellable = MonitorManager.shared.$monitors
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reapplyAllGroups()
            }

        // Clean up when apps terminate
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in
                self?.handleAppTerminated(pid: app.processIdentifier)
            }
        }
    }

    // No deinit needed — singleton lives for app lifetime.
    // terminationObserver and monitorCancellable are cleaned up when process exits.

    // MARK: - Public API

    /// Tile a window to a zone position, automatically creating/extending tile groups.
    /// This is the unified entry point for all tile zone drops.
    func tileToZone(windowID: CGWindowID, pid: pid_t, position: TilePosition, monitor: MonitorInfo) {
        // Remove from any existing group first
        removeWindow(windowID)

        // Non-groupable positions: maximize, almostMaximize, center — single tile only
        let nonGroupable: Set<TilePosition> = [.maximize, .almostMaximize, .center]
        guard !nonGroupable.contains(position) else {
            applySingleTile(windowID: windowID, pid: pid, position: position, monitor: monitor)
            return
        }

        // If dynamic tiling is off, just single-tile
        let config = CiderConfig.load()
        guard config.enableDynamicTiling else {
            applySingleTile(windowID: windowID, pid: pid, position: position, monitor: monitor)
            return
        }

        // Check for existing group on this screen
        if let existingGroupID = findGroupOnScreen(screenID: monitor.id) {
            insertIntoExistingGroup(
                groupID: existingGroupID, windowID: windowID, pid: pid,
                position: position, monitor: monitor
            )
            return
        }

        // For halves, auto-pair with the topmost window on screen
        if TilePosition.halves.contains(position) {
            if let (topmostID, topmostPID) = findTopmostWindowOnScreen(monitor: monitor, excludeWindowID: windowID) {
                let side = splitSideForPosition(position)
                createGroup(
                    draggedWindowID: windowID, draggedPID: pid,
                    targetWindowID: topmostID, targetPID: topmostPID,
                    side: side, screenID: monitor.id
                )
                return
            }
        }

        // Fallback: single-window tile
        applySingleTile(windowID: windowID, pid: pid, position: position, monitor: monitor)
    }

    /// Create a new tile group from two windows (drag-to-split).
    func createGroup(
        draggedWindowID: CGWindowID, draggedPID: pid_t,
        targetWindowID: CGWindowID, targetPID: pid_t,
        side: SplitSide, screenID: UInt32
    ) {
        // Remove from any existing groups first
        removeWindow(draggedWindowID)
        removeWindow(targetWindowID)

        let leftNode: TileNode
        let rightNode: TileNode
        let orientation: SplitOrientation

        switch side {
        case .left:
            orientation = .horizontal
            leftNode = .leaf(windowID: draggedWindowID, pid: draggedPID)
            rightNode = .leaf(windowID: targetWindowID, pid: targetPID)
        case .right:
            orientation = .horizontal
            leftNode = .leaf(windowID: targetWindowID, pid: targetPID)
            rightNode = .leaf(windowID: draggedWindowID, pid: draggedPID)
        case .top:
            orientation = .vertical
            leftNode = .leaf(windowID: draggedWindowID, pid: draggedPID)
            rightNode = .leaf(windowID: targetWindowID, pid: targetPID)
        case .bottom:
            orientation = .vertical
            leftNode = .leaf(windowID: targetWindowID, pid: targetPID)
            rightNode = .leaf(windowID: draggedWindowID, pid: draggedPID)
        }

        let root = TileNode.split(orientation: orientation, ratio: 0.5, left: leftNode, right: rightNode)
        let group = TileGroup(screenID: screenID, root: root)

        groups[group.id] = group
        windowToGroup[draggedWindowID] = group.id
        windowToGroup[targetWindowID] = group.id

        // Start observing both windows
        startObserving(windowID: draggedWindowID, pid: draggedPID)
        startObserving(windowID: targetWindowID, pid: targetPID)

        // Apply frames
        applyGroupFrames(group)

        NotificationCenter.default.post(name: .ciderDynamicTileGroupChanged, object: nil)
    }

    /// Add a window to an existing group by splitting a target window.
    func addToGroup(
        draggedWindowID: CGWindowID, draggedPID: pid_t,
        targetWindowID: CGWindowID, side: SplitSide
    ) {
        guard let groupID = windowToGroup[targetWindowID],
              let group = groups[groupID] else { return }

        // Remove dragged window from any existing group first
        removeWindow(draggedWindowID)

        group.addWindow(newWindowID: draggedWindowID, newPID: draggedPID,
                        targetWindowID: targetWindowID, side: side)
        windowToGroup[draggedWindowID] = groupID

        startObserving(windowID: draggedWindowID, pid: draggedPID)
        applyGroupFrames(group)

        NotificationCenter.default.post(name: .ciderDynamicTileGroupChanged, object: nil)
    }

    /// Remove a window from its tile group. Group may dissolve.
    func removeWindow(_ windowID: CGWindowID) {
        guard let groupID = windowToGroup.removeValue(forKey: windowID),
              let group = groups[groupID] else { return }

        // Find the pid before removing
        let leafData = group.root.allWindowIDs().first(where: { $0.0 == windowID })
        let pid = leafData?.1 ?? 0

        stopObserving(windowID: windowID, pid: pid)
        expectedFrames.removeValue(forKey: windowID)
        cancelPendingCoalesce(windowID: windowID)

        let shouldDissolve = group.removeWindow(windowID)

        if shouldDissolve {
            // Get remaining window (if any) before dissolving
            let remaining = group.root.allWindowIDs()
            dissolveGroup(groupID)

            // Expand remaining window to fill the bounding rect
            if remaining.count == 1 {
                let (remainingID, remainingPID) = remaining[0]
                expandWindowToFill(windowID: remainingID, pid: remainingPID, screenID: group.screenID)
            }
        } else {
            // Recompute frames for remaining windows
            applyGroupFrames(group)
        }

        NotificationCenter.default.post(name: .ciderDynamicTileGroupChanged, object: nil)
    }

    /// Check if a window is in a dynamic tile group.
    func isInGroup(_ windowID: CGWindowID) -> Bool {
        windowToGroup[windowID] != nil
    }

    /// Get the group ID for a window (if any).
    func groupID(for windowID: CGWindowID) -> UUID? {
        windowToGroup[windowID]
    }

    // MARK: - Zone Tiling Helpers

    /// Find an existing tile group on a given screen.
    private func findGroupOnScreen(screenID: UInt32) -> UUID? {
        groups.first(where: { $0.value.screenID == screenID })?.key
    }

    /// Find the topmost regular window on a monitor (excluding our own panels and the dragged window).
    private func findTopmostWindowOnScreen(monitor: MonitorInfo, excludeWindowID: CGWindowID) -> (CGWindowID, pid_t)? {
        let ownBundle = Bundle.main.bundleIdentifier
        let cgOptions: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(cgOptions, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let filteredOwners: Set<String> = [
            "Window Server", "WindowManager", "Dock", "SystemUIServer",
            "Control Center", "Notification Center", "Spotlight",
            "universalAccessAuthWarn", "TextInputMenuAgent", "TextInputSwitcher"
        ]

        for info in infoList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let wid = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            guard let ownerName = info[kCGWindowOwnerName as String] as? String else { continue }
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t else { continue }

            if wid == excludeWindowID { continue }
            if filteredOwners.contains(ownerName) { continue }
            if let running = NSRunningApplication(processIdentifier: ownerPID),
               running.bundleIdentifier == ownBundle { continue }

            guard let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let w = boundsDict["Width"], let h = boundsDict["Height"],
                  let x = boundsDict["X"], let y = boundsDict["Y"] else { continue }
            if w < 50 || h < 50 { continue }
            if let alpha = info[kCGWindowAlpha as String] as? CGFloat, alpha < 0.1 { continue }

            let bounds = CGRect(x: x, y: y, width: w, height: h)
            if MonitorManager.shared.screenForWindow(bounds)?.id == monitor.id {
                return (wid, ownerPID)
            }
        }
        return nil
    }

    /// Apply a single-window tile (no grouping) — raise + move/resize.
    private func applySingleTile(windowID: CGWindowID, pid: pid_t, position: TilePosition, monitor: MonitorInfo) {
        let axWindows = AccessibilityHelpers.windows(for: pid)
        guard let axWindow = axWindows.first(where: { AccessibilityHelpers.windowID(of: $0) == windowID }) else { return }

        let frame = WindowManager.calculateTileFrameStatic(position: position, on: monitor)
        let windowManager = WindowManager()
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        windowManager.applyFrame(axWindow: axWindow, pid: pid, origin: frame.origin, size: frame.size)
    }

    /// Insert a window into an existing group by splitting the leaf whose frame overlaps most with the zone.
    private func insertIntoExistingGroup(groupID: UUID, windowID: CGWindowID, pid: pid_t,
                                         position: TilePosition, monitor: MonitorInfo) {
        guard let group = groups[groupID] else { return }

        let zoneFrame = WindowManager.calculateTileFrameStatic(position: position, on: monitor)
        let frames = group.recalculateFrames()

        // Find the leaf with the largest overlap to the zone frame
        var bestOverlap: CGFloat = -1
        var bestTargetID: CGWindowID?
        var bestTargetFrame: CGRect = .zero
        for (leafID, _, leafFrame) in frames {
            let overlap = zoneFrame.intersection(leafFrame)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > bestOverlap {
                bestOverlap = area
                bestTargetID = leafID
                bestTargetFrame = leafFrame
            }
        }

        guard let targetID = bestTargetID else {
            applySingleTile(windowID: windowID, pid: pid, position: position, monitor: monitor)
            return
        }

        // Determine split side by comparing zone frame geometry against the target leaf
        let side = determineSplitSide(zoneFrame: zoneFrame, targetFrame: bestTargetFrame)

        // Remove from any existing group (already done in tileToZone, but safe to call)
        removeWindow(windowID)

        group.addWindow(newWindowID: windowID, newPID: pid,
                        targetWindowID: targetID, side: side)
        windowToGroup[windowID] = groupID

        startObserving(windowID: windowID, pid: pid)
        applyGroupFrames(group)

        NotificationCenter.default.post(name: .ciderDynamicTileGroupChanged, object: nil)
    }

    /// Get the complement half position (left↔right, top↔bottom).
    private func complementPosition(for position: TilePosition) -> TilePosition {
        switch position {
        case .left: return .right
        case .right: return .left
        case .top: return .bottom
        case .bottom: return .top
        default: return position
        }
    }

    /// Map a TilePosition to SplitSide for group creation.
    private func splitSideForPosition(_ position: TilePosition) -> SplitSide {
        switch position {
        case .left: return .left
        case .right: return .right
        case .top: return .top
        case .bottom: return .bottom
        case .topLeft: return .left
        case .topRight: return .right
        case .bottomLeft: return .left
        case .bottomRight: return .right
        default: return .right
        }
    }

    /// Determine the split side by comparing the zone frame against the target leaf frame.
    /// Uses the relative offset of zone center vs target center to pick horizontal or vertical split.
    private func determineSplitSide(zoneFrame: CGRect, targetFrame: CGRect) -> SplitSide {
        let dx = abs(zoneFrame.midX - targetFrame.midX) / max(targetFrame.width, 1)
        let dy = abs(zoneFrame.midY - targetFrame.midY) / max(targetFrame.height, 1)

        if dx > dy {
            // Horizontal split
            return zoneFrame.midX < targetFrame.midX ? .left : .right
        } else if dy > dx {
            // Vertical split (NSScreen coords: Y increases upward, so higher midY = top)
            return zoneFrame.midY > targetFrame.midY ? .top : .bottom
        } else {
            // Equal offset (e.g., zone matches target exactly) — default to horizontal
            return zoneFrame.midX < targetFrame.midX ? .left : .right
        }
    }

    // MARK: - AXObserver Management

    private func startObserving(windowID: CGWindowID, pid: pid_t) {
        guard pid > 0 else { return }

        if var entry = observers[pid] {
            // Already observing this PID, just bump count
            entry.windowCount += 1
            observers[pid] = entry

            // Still need to add notification for this specific window's AX element
            addWindowNotifications(windowID: windowID, pid: pid, observer: entry.observer)
            return
        }

        // Create new observer for this PID
        var observerRef: AXObserver?
        let err = AXObserverCreate(pid, { (observer, element, notification, refcon) in
            // This callback runs on the main thread (observer added to main RunLoop)
            guard let refcon else { return }
            let manager = Unmanaged<DynamicTileManager>.fromOpaque(refcon).takeUnretainedValue()

            // Get the window ID from the AX element
            if let windowID = AccessibilityHelpers.windowID(of: element) {
                Task { @MainActor in
                    manager.scheduleResizeHandling(windowID: windowID)
                }
            }
        }, &observerRef)

        guard err == .success, let observer = observerRef else { return }

        // Add observer to main RunLoop
        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)

        // Retain self for the callback (prevent premature release)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // Add notifications for this window
        let axWindows = AccessibilityHelpers.windows(for: pid)

        for axWindow in axWindows {
            if AccessibilityHelpers.windowID(of: axWindow) == windowID {
                AXObserverAddNotification(observer, axWindow, kAXWindowResizedNotification as CFString, refcon)
                AXObserverAddNotification(observer, axWindow, kAXWindowMovedNotification as CFString, refcon)
                break
            }
        }

        observers[pid] = (observer: observer, windowCount: 1)
    }

    private func addWindowNotifications(windowID: CGWindowID, pid: pid_t, observer: AXObserver) {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let axWindows = AccessibilityHelpers.windows(for: pid)

        for axWindow in axWindows {
            if AccessibilityHelpers.windowID(of: axWindow) == windowID {
                AXObserverAddNotification(observer, axWindow, kAXWindowResizedNotification as CFString, refcon)
                AXObserverAddNotification(observer, axWindow, kAXWindowMovedNotification as CFString, refcon)
                break
            }
        }
    }

    private func stopObserving(windowID: CGWindowID, pid: pid_t) {
        guard pid > 0, var entry = observers[pid] else { return }

        // Remove notifications for this window
        let axWindows = AccessibilityHelpers.windows(for: pid)
        for axWindow in axWindows {
            if AccessibilityHelpers.windowID(of: axWindow) == windowID {
                AXObserverRemoveNotification(entry.observer, axWindow, kAXWindowResizedNotification as CFString)
                AXObserverRemoveNotification(entry.observer, axWindow, kAXWindowMovedNotification as CFString)
                break
            }
        }

        entry.windowCount -= 1
        if entry.windowCount <= 0 {
            cleanupObserver(for: pid)
        } else {
            observers[pid] = entry
        }
    }

    private func cleanupObserver(for pid: pid_t) {
        guard let entry = observers.removeValue(forKey: pid) else { return }
        let source = AXObserverGetRunLoopSource(entry.observer)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    // MARK: - Resize Handling

    private func scheduleResizeHandling(windowID: CGWindowID) {
        // Skip entirely if we're currently tiling this window (AeroSpace pattern)
        guard !currentlyTilingWindowIDs.contains(windowID) else { return }

        // Cancel any pending work for this window
        cancelPendingCoalesce(windowID: windowID)

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.handleWindowResized(windowID: windowID)
            }
        }

        pendingCoalesce[windowID] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    private func cancelPendingCoalesce(windowID: CGWindowID) {
        pendingCoalesce.removeValue(forKey: windowID)?.cancel()
    }

    private func handleWindowResized(windowID: CGWindowID) {
        pendingCoalesce.removeValue(forKey: windowID)

        // Skip if we're currently tiling this window
        guard !currentlyTilingWindowIDs.contains(windowID) else { return }

        guard let groupID = windowToGroup[windowID],
              let group = groups[groupID] else { return }

        // Get current window frame from AX
        guard let (_, currentFrame) = getWindowFrame(windowID: windowID, group: group) else { return }

        // Compare to expected frame
        if let expected = expectedFrames[windowID] {
            if framesMatch(expected, currentFrame) {
                return  // No actual user resize, just our own frame application
            }
        }

        // User resized — update the ratio in the tree
        // Convert AX frame to NSScreen coordinates for ratio calculation
        let nsFrame = convertAXFrameToNS(axFrame: currentFrame)
        group.updateRatio(forWindowID: windowID, newFrame: nsFrame)

        // Reapply all frames in the group (batch)
        applyGroupFrames(group)
    }

    private func framesMatch(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.origin.x - b.origin.x) <= frameTolerance &&
        abs(a.origin.y - b.origin.y) <= frameTolerance &&
        abs(a.width - b.width) <= frameTolerance &&
        abs(a.height - b.height) <= frameTolerance
    }

    /// Get the AX frame (position + size) for a window.
    private func getWindowFrame(windowID: CGWindowID, group: TileGroup) -> (AXUIElement, CGRect)? {
        guard let leafData = group.root.allWindowIDs().first(where: { $0.0 == windowID }) else { return nil }
        let pid = leafData.1

        let axWindows = AccessibilityHelpers.windows(for: pid)
        for axWindow in axWindows {
            if AccessibilityHelpers.windowID(of: axWindow) == windowID {
                guard let pos = AccessibilityHelpers.getWindowPosition(axWindow),
                      let size = AccessibilityHelpers.getWindowSize(axWindow) else { continue }
                return (axWindow, CGRect(origin: pos, size: size))
            }
        }
        return nil
    }

    /// Convert AX coordinates (top-left origin) to NSScreen coordinates (bottom-left origin).
    private func convertAXFrameToNS(axFrame: CGRect) -> CGRect {
        let nsOrigin = AccessibilityHelpers.convertFromAXCoordinates(
            axFrame.origin, windowHeight: axFrame.height)
        return CGRect(origin: nsOrigin, size: axFrame.size)
    }

    // MARK: - Frame Application

    /// Grace period after applying frames — ignore AX resize events during this window.
    private func applyGroupFrames(_ group: TileGroup) {
        let frames = group.recalculateFrames()
        debugLog("[ApplyFrames] \(frames.count) frames, boundingRect=\(group.boundingRect)")

        // Mark all windows as "currently tiling" to suppress AX feedback
        let windowIDs = Set(frames.map { $0.0 })
        currentlyTilingWindowIDs.formUnion(windowIDs)

        let windowManager = WindowManager()

        for (windowID, pid, nsRect) in frames {
            // Find the AX window
            let axWindows = AccessibilityHelpers.windows(for: pid)
            guard let axWindow = axWindows.first(where: { AccessibilityHelpers.windowID(of: $0) == windowID }) else {
                let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "?"
                debugLog("[ApplyFrames] MISS windowID=\(windowID) pid=\(pid) app=\(appName)")
                continue
            }

            let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "?"
            let ok = windowManager.applyFrame(axWindow: axWindow, pid: pid,
                                              origin: nsRect.origin, size: nsRect.size)
            debugLog("[ApplyFrames] windowID=\(windowID) app=\(appName) rect=\(nsRect) ok=\(ok)")

            // Raise the window so both tiled windows are visible side-by-side
            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)

            // Read back ACTUAL frame so the expected-frame comparison
            // respects window minimum sizes
            if let actualPos = AccessibilityHelpers.getWindowPosition(axWindow),
               let actualSize = AccessibilityHelpers.getWindowSize(axWindow) {
                expectedFrames[windowID] = CGRect(origin: actualPos, size: actualSize)
            }
        }

        // Clear the tiling guard after a short delay so AX events from our
        // frame application are fully drained before we start listening again
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.currentlyTilingWindowIDs.subtract(windowIDs)
        }
    }

    private func debugLog(_ message: String) {
        let path = "/tmp/cider-debug.log"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
        }
    }

    private func reapplyAllGroups() {
        for group in groups.values {
            applyGroupFrames(group)
        }
    }

    // MARK: - Group Lifecycle

    private func dissolveGroup(_ groupID: UUID) {
        guard let group = groups.removeValue(forKey: groupID) else { return }

        for (windowID, pid) in group.root.allWindowIDs() {
            windowToGroup.removeValue(forKey: windowID)
            stopObserving(windowID: windowID, pid: pid)
            expectedFrames.removeValue(forKey: windowID)
            cancelPendingCoalesce(windowID: windowID)
        }
    }

    /// Expand a single remaining window to fill the screen's visible frame.
    private func expandWindowToFill(windowID: CGWindowID, pid: pid_t, screenID: UInt32) {
        guard let monitor = MonitorManager.shared.monitor(for: screenID) else { return }
        let visibleFrame = monitor.visibleFrame

        let axWindows = AccessibilityHelpers.windows(for: pid)
        guard let axWindow = axWindows.first(where: { AccessibilityHelpers.windowID(of: $0) == windowID }) else { return }

        let windowManager = WindowManager()
        windowManager.applyFrame(axWindow: axWindow, pid: pid,
                                 origin: visibleFrame.origin, size: visibleFrame.size)
    }

    // MARK: - App Termination

    private func handleAppTerminated(pid: pid_t) {
        // Find all windows belonging to this PID and remove them
        let windowIDs = windowToGroup.keys.filter { windowID in
            for group in groups.values {
                if let leafData = group.root.allWindowIDs().first(where: { $0.0 == windowID }),
                   leafData.1 == pid {
                    return true
                }
            }
            return false
        }

        for windowID in windowIDs {
            removeWindow(windowID)
        }

        // Clean up the observer
        cleanupObserver(for: pid)
    }
}
