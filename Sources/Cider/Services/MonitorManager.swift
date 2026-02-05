import AppKit
import Combine

@MainActor
final class MonitorManager: ObservableObject {
    static let shared = MonitorManager()

    @Published var monitors: [MonitorInfo] = []

    private var screenChangeObserver: NSObjectProtocol?

    init() {
        refresh()
        observeScreenChanges()
    }

    @MainActor
    deinit {
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func refresh() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            monitors = []
            return
        }

        // Find primary screen (the one containing the menu bar)
        let primaryScreen = screens.first { $0.frame.origin == .zero } ?? screens[0]
        let primaryID = displayID(for: primaryScreen)

        // Calculate relative positions based on primary screen
        let positions = calculateRelativePositions(screens: screens, primaryScreen: primaryScreen)

        monitors = screens.compactMap { screen in
            guard let screenID = displayID(for: screen) else { return nil }
            let isPrimary = screenID == primaryID
            let position = positions[screenID] ?? (isPrimary ? .primary : .right)
            let name = screen.localizedName

            return MonitorInfo(
                id: screenID,
                name: name,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                isPrimary: isPrimary,
                relativePosition: position
            )
        }.sorted { lhs, rhs in
            // Primary first, then by position
            if lhs.isPrimary { return true }
            if rhs.isPrimary { return false }
            return lhs.relativePosition.rawValue < rhs.relativePosition.rawValue
        }
    }

    func screenForWindow(_ bounds: CGRect) -> MonitorInfo? {
        // CGWindowList uses top-left origin (Y=0 at top, increases downward)
        // NSScreen uses bottom-left origin (Y=0 at bottom, increases upward)
        // We need to convert CGWindowList bounds to NSScreen coordinates

        guard let primaryScreen = NSScreen.screens.first else {
            return monitors.first
        }
        let primaryHeight = primaryScreen.frame.height

        // Convert from CG (top-left) to NS (bottom-left) coordinates
        // CG Y of top edge -> NS Y of top edge = primaryHeight - cgY
        // NS Y of bottom edge = NS Y of top edge - height
        let nsTop = primaryHeight - bounds.minY
        let nsBottom = nsTop - bounds.height
        let convertedBounds = CGRect(x: bounds.minX, y: nsBottom, width: bounds.width, height: bounds.height)

        // Find the monitor that contains the center of the window
        let center = CGPoint(x: convertedBounds.midX, y: convertedBounds.midY)

        // First try to find exact match
        if let match = monitors.first(where: { $0.frame.contains(center) }) {
            return match
        }

        // Fall back to monitor with most overlap
        var maxOverlap: CGFloat = 0
        var bestMatch: MonitorInfo?

        for monitor in monitors {
            let intersection = monitor.frame.intersection(convertedBounds)
            if !intersection.isNull {
                let overlap = intersection.width * intersection.height
                if overlap > maxOverlap {
                    maxOverlap = overlap
                    bestMatch = monitor
                }
            }
        }

        return bestMatch ?? monitors.first
    }

    func monitor(for screenID: UInt32) -> MonitorInfo? {
        monitors.first { $0.id == screenID }
    }

    private func displayID(for screen: NSScreen) -> UInt32? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return screenNumber.uint32Value
    }

    private func calculateRelativePositions(screens: [NSScreen], primaryScreen: NSScreen) -> [UInt32: MonitorInfo.RelativePosition] {
        var positions: [UInt32: MonitorInfo.RelativePosition] = [:]

        guard let primaryID = displayID(for: primaryScreen) else { return positions }
        positions[primaryID] = .primary

        let primaryFrame = primaryScreen.frame

        for screen in screens {
            guard let screenID = displayID(for: screen), screenID != primaryID else { continue }

            let frame = screen.frame
            let position: MonitorInfo.RelativePosition

            // Determine relative position based on frame origin relative to primary
            if frame.maxX <= primaryFrame.minX {
                position = .left
            } else if frame.minX >= primaryFrame.maxX {
                position = .right
            } else if frame.maxY <= primaryFrame.minY {
                // Note: macOS coordinate system has origin at bottom-left
                position = .bottom
            } else if frame.minY >= primaryFrame.maxY {
                position = .top
            } else {
                // Overlapping or unusual arrangement - use horizontal position
                if frame.midX < primaryFrame.midX {
                    position = .left
                } else {
                    position = .right
                }
            }

            positions[screenID] = position
        }

        return positions
    }

    private func observeScreenChanges() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }
}
