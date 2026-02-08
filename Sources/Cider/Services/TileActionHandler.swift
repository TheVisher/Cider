import AppKit
import ApplicationServices

/// Executes tile actions triggered by global hotkeys on the currently focused window.
@MainActor
struct TileActionHandler {
    private let windowManager = WindowManager()

    func execute(_ action: TileAction) {
        guard let (axWindow, pid, monitor) = getFocusedWindow() else { return }

        // Remove from dynamic tile group before any tile/restore/display-move action
        let windowID = frameHistoryKey(axWindow: axWindow, pid: pid)
        DynamicTileManager.shared.removeWindow(windowID)

        switch action {
        case .tile(let position):
            saveCurrentFrame(axWindow: axWindow, pid: pid)
            let frame = WindowManager.calculateTileFrameStatic(position: position, on: monitor)
            windowManager.applyFrame(axWindow: axWindow, pid: pid,
                                     origin: CGPoint(x: frame.minX, y: frame.minY),
                                     size: frame.size)

        case .larger:
            saveCurrentFrame(axWindow: axWindow, pid: pid)
            applyLargerSmaller(axWindow: axWindow, pid: pid, monitor: monitor, growDirection: .larger)

        case .smaller:
            saveCurrentFrame(axWindow: axWindow, pid: pid)
            applyLargerSmaller(axWindow: axWindow, pid: pid, monitor: monitor, growDirection: .smaller)

        case .restore:
            applyRestore(axWindow: axWindow, pid: pid)

        case .nextDisplay:
            moveToAdjacentDisplay(axWindow: axWindow, pid: pid, currentMonitor: monitor, direction: 1)

        case .previousDisplay:
            moveToAdjacentDisplay(axWindow: axWindow, pid: pid, currentMonitor: monitor, direction: -1)
        }
    }

    // MARK: - Focused Window Discovery

    /// Returns the AX element, PID, and monitor of the currently focused window.
    private func getFocusedWindow() -> (AXUIElement, pid_t, MonitorInfo)? {
        guard AccessibilityHelpers.isTrusted() else { return nil }

        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontApp.processIdentifier

        let appElement = AccessibilityHelpers.appElement(for: pid)
        var focusedRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedRef)
        guard err == .success, let ref = focusedRef, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        let axWindow = unsafeDowncast(ref, to: AXUIElement.self)

        // Determine which monitor the window is on
        guard let pos = AccessibilityHelpers.getWindowPosition(axWindow),
              let size = AccessibilityHelpers.getWindowSize(axWindow) else { return nil }

        // AX coordinates are top-left origin; convert to CG bounds for screenForWindow
        let cgBounds = CGRect(origin: pos, size: size)
        let monitor = MonitorManager.shared.screenForWindow(cgBounds) ?? MonitorManager.shared.monitors.first

        guard let monitor else { return nil }
        return (axWindow, pid, monitor)
    }

    // MARK: - Frame History

    /// Stable key for frame history. Uses AX window ID when available; otherwise hashes
    /// pid + title so different windows of the same app don't collide.
    private func frameHistoryKey(axWindow: AXUIElement, pid: pid_t) -> CGWindowID {
        if let realID = AccessibilityHelpers.windowID(of: axWindow) {
            return realID
        }
        let title = AccessibilityHelpers.title(of: axWindow)
        var hasher = Hasher()
        hasher.combine(pid)
        hasher.combine(title)
        let hash = UInt(bitPattern: hasher.finalize())
        return CGWindowID(hash % 1_000_000 + 2_000_000)
    }

    private func saveCurrentFrame(axWindow: AXUIElement, pid: pid_t) {
        guard let pos = AccessibilityHelpers.getWindowPosition(axWindow),
              let size = AccessibilityHelpers.getWindowSize(axWindow) else { return }

        let windowID = frameHistoryKey(axWindow: axWindow, pid: pid)
        let frame = CGRect(origin: pos, size: size)
        WindowFrameHistory.shared.save(windowID: windowID, frame: frame)
    }

    // MARK: - Larger / Smaller

    private enum GrowDirection { case larger, smaller }

    private func applyLargerSmaller(axWindow: AXUIElement, pid: pid_t, monitor: MonitorInfo, growDirection: GrowDirection) {
        guard let pos = AccessibilityHelpers.getWindowPosition(axWindow),
              let size = AccessibilityHelpers.getWindowSize(axWindow) else { return }

        let visible = monitor.visibleFrame
        let step = WindowManager.windowPadding

        // Convert AX position (top-left origin) to NSScreen-style (bottom-left origin)
        let nsOrigin = AccessibilityHelpers.convertFromAXCoordinates(pos, windowHeight: size.height)

        // Calculate current insets from visible frame edges
        let insetLeft = pos.x - visible.minX
        let insetRight = visible.maxX - (pos.x + size.width)
        let insetTop = visible.maxY - (nsOrigin.y + size.height)
        let insetBottom = nsOrigin.y - visible.minY

        // Use minimum inset as the current "padding level"
        let currentPadding = max(0, min(insetLeft, insetRight, insetTop, insetBottom))

        let newPadding: CGFloat
        switch growDirection {
        case .larger:
            newPadding = max(0, currentPadding - step)
        case .smaller:
            // Don't shrink smaller than 1/4 of visible frame in either dimension
            let maxPadding = min(visible.width, visible.height) / 4
            newPadding = min(maxPadding, currentPadding + step)
        }

        // Apply symmetric padding from visible frame
        let newWidth = visible.width - newPadding * 2
        let newHeight = visible.height - newPadding * 2
        let newX = visible.minX + newPadding
        let newY = visible.minY + newPadding  // NSScreen coords (bottom-left)

        let newOrigin = CGPoint(x: newX, y: newY)
        let newSize = CGSize(width: newWidth, height: newHeight)

        windowManager.applyFrame(axWindow: axWindow, pid: pid, origin: newOrigin, size: newSize)
    }

    // MARK: - Restore

    private func applyRestore(axWindow: AXUIElement, pid: pid_t) {
        let windowID = frameHistoryKey(axWindow: axWindow, pid: pid)
        guard let savedFrame = WindowFrameHistory.shared.restore(windowID: windowID) else { return }

        // savedFrame stores AX coordinates (position = top-left), convert back to NSScreen origin
        let origin = AccessibilityHelpers.convertFromAXCoordinates(
            savedFrame.origin, windowHeight: savedFrame.height)

        windowManager.applyFrame(axWindow: axWindow, pid: pid, origin: origin, size: savedFrame.size)
    }

    // MARK: - Next / Previous Display

    private func moveToAdjacentDisplay(axWindow: AXUIElement, pid: pid_t, currentMonitor: MonitorInfo, direction: Int) {
        let monitors = MonitorManager.shared.monitors
        guard monitors.count > 1 else { return }

        guard let currentIndex = monitors.firstIndex(where: { $0.id == currentMonitor.id }) else { return }
        let nextIndex = (currentIndex + direction + monitors.count) % monitors.count
        let targetMonitor = monitors[nextIndex]

        // Build a minimal WindowInfo for moveWindow
        guard let pos = AccessibilityHelpers.getWindowPosition(axWindow),
              let size = AccessibilityHelpers.getWindowSize(axWindow) else { return }

        let windowID = AccessibilityHelpers.windowID(of: axWindow) ?? CGWindowID(pid)
        let app = NSRunningApplication(processIdentifier: pid)
        let ownerName = app?.localizedName ?? "Unknown"
        let bundleID = app?.bundleIdentifier ?? ""
        let bounds = CGRect(origin: pos, size: size)

        let windowInfo = WindowInfo(id: windowID, ownerPID: pid, ownerName: ownerName,
                                    title: "", bundleIdentifier: bundleID, bounds: bounds,
                                    screenID: currentMonitor.id)

        windowManager.moveWindow(windowInfo, to: targetMonitor)
    }
}
