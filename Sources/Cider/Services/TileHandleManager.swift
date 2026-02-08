import AppKit

/// Computed info for a single drag handle at a split intersection or midpoint.
struct HandleInfo {
    let point: CGPoint  // NSScreen coordinates
    let groupID: UUID
    /// The horizontal split line (drag left/right changes this ratio). Nil if vertical-only.
    let horizontalSplit: SplitLineInfo?
    /// The vertical split line (drag up/down changes this ratio). Nil if horizontal-only.
    let verticalSplit: SplitLineInfo?
}

/// Manages the lifecycle of tile drag handle panels.
/// Observes tile group changes and positions handle panels at split boundaries.
/// Panels are invisible until hover — the user discovers handles by mousing over the gap.
@MainActor
final class TileHandleManager {
    static let shared = TileHandleManager()

    private var handlePanels: [(panel: TileHandlePanel, view: TileHandleView, info: HandleInfo)] = []
    private var isVisible = true
    private var isDragging = false
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .ciderDynamicTileGroupChanged,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isDragging else { return }
                self.recalculateHandles()
            }
        }
    }

    // MARK: - Visibility

    func setVisible(_ visible: Bool) {
        isVisible = visible
        if visible {
            recalculateHandles()
        } else {
            removeAllHandles()
        }
    }

    // MARK: - Handle Computation

    private func recalculateHandles() {
        removeAllHandles()
        guard isVisible else { return }

        let allGroupLines = DynamicTileManager.shared.groupSplitLines()
        var allHandleInfos: [HandleInfo] = []

        for groupData in allGroupLines {
            let handles = computeHandles(
                groupID: groupData.groupID,
                lines: groupData.lines
            )
            allHandleInfos.append(contentsOf: handles)
        }

        for info in allHandleInfos {
            createHandlePanel(for: info)
        }
    }

    /// Reposition existing panels without destroying them (safe during drag).
    private func repositionHandles() {
        let allGroupLines = DynamicTileManager.shared.groupSplitLines()
        var allHandleInfos: [HandleInfo] = []

        for groupData in allGroupLines {
            let handles = computeHandles(
                groupID: groupData.groupID,
                lines: groupData.lines
            )
            allHandleInfos.append(contentsOf: handles)
        }

        // Update positions 1:1 (handle count doesn't change during drag)
        for (i, newInfo) in allHandleInfos.enumerated() where i < handlePanels.count {
            let panel = handlePanels[i].panel
            let size = panelSize(for: newInfo)
            let origin = NSPoint(
                x: newInfo.point.x - size.width / 2,
                y: newInfo.point.y - size.height / 2
            )
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
        }
    }

    private func computeHandles(groupID: UUID, lines: [SplitLineInfo]) -> [HandleInfo] {
        let horizontalLines = lines.filter { $0.orientation == .horizontal }
        let verticalLines = lines.filter { $0.orientation == .vertical }

        var handles: [HandleInfo] = []
        var usedHorizontal = Set<Int>()
        var usedVertical = Set<Int>()

        let tolerance = CiderDesign.tileGap + 2

        // Find intersections between perpendicular lines
        for (hi, hLine) in horizontalLines.enumerated() {
            for (vi, vLine) in verticalLines.enumerated() {
                let hX = hLine.position
                let vY = vLine.position

                let hOverlapsV = vY >= hLine.rangeStart - tolerance && vY <= hLine.rangeEnd + tolerance
                let vOverlapsH = hX >= vLine.rangeStart - tolerance && hX <= vLine.rangeEnd + tolerance

                if hOverlapsV && vOverlapsH {
                    handles.append(HandleInfo(
                        point: CGPoint(x: hX, y: vY),
                        groupID: groupID,
                        horizontalSplit: hLine,
                        verticalSplit: vLine
                    ))
                    usedHorizontal.insert(hi)
                    usedVertical.insert(vi)
                }
            }
        }

        // Lone horizontal lines → handle at midpoint
        for (hi, hLine) in horizontalLines.enumerated() where !usedHorizontal.contains(hi) {
            let midY = (hLine.rangeStart + hLine.rangeEnd) / 2
            handles.append(HandleInfo(
                point: CGPoint(x: hLine.position, y: midY),
                groupID: groupID,
                horizontalSplit: hLine,
                verticalSplit: nil
            ))
        }

        // Lone vertical lines → handle at midpoint
        for (vi, vLine) in verticalLines.enumerated() where !usedVertical.contains(vi) {
            let midX = (vLine.rangeStart + vLine.rangeEnd) / 2
            handles.append(HandleInfo(
                point: CGPoint(x: midX, y: vLine.position),
                groupID: groupID,
                horizontalSplit: nil,
                verticalSplit: vLine
            ))
        }

        return handles
    }

    // MARK: - Panel Sizing

    /// Panel extends along the split line for a larger hover-detection area.
    /// Clicks outside the circle pass through via TileHandleView.hitTest.
    private func panelSize(for info: HandleInfo) -> NSSize {
        let narrow: CGFloat = 20
        let maxExtent: CGFloat = 120

        if info.horizontalSplit != nil && info.verticalSplit != nil {
            // Intersection — generous square
            return NSSize(width: 40, height: 40)
        } else if let hSplit = info.horizontalSplit {
            // Vertical divider line — tall and narrow
            let lineLength = hSplit.rangeEnd - hSplit.rangeStart
            return NSSize(width: narrow, height: min(lineLength, maxExtent))
        } else if let vSplit = info.verticalSplit {
            // Horizontal divider line — wide and narrow
            let lineLength = vSplit.rangeEnd - vSplit.rangeStart
            return NSSize(width: min(lineLength, maxExtent), height: narrow)
        }
        return NSSize(width: narrow, height: narrow)
    }

    // MARK: - Panel Management

    private func createHandlePanel(for info: HandleInfo) {
        let size = panelSize(for: info)
        let panel = TileHandlePanel()
        let view = TileHandleView(
            frame: NSRect(x: 0, y: 0, width: size.width, height: size.height)
        )

        view.isHorizontal = info.horizontalSplit != nil
        view.isVertical = info.verticalSplit != nil

        view.onDragStart = { [weak self] in
            self?.handleDragStart(info: info)
        }
        view.onDrag = { [weak self] screenPoint in
            self?.handleDrag(screenPoint: screenPoint, info: info)
        }
        view.onDragEnd = { [weak self] in
            self?.handleDragEnd(info: info)
        }

        panel.contentView = view

        let origin = NSPoint(
            x: info.point.x - size.width / 2,
            y: info.point.y - size.height / 2
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFront(nil)

        handlePanels.append((panel: panel, view: view, info: info))
    }

    private func removeAllHandles() {
        for entry in handlePanels {
            entry.panel.orderOut(nil)
        }
        handlePanels.removeAll()
    }

    // MARK: - Drag Handling

    /// Called by DynamicTileManager when minimum-size correction shifts a split during drag.
    func repositionHandlesAfterCorrection() {
        guard isDragging else { return }
        repositionHandles()
    }

    private func handleDragStart(info: HandleInfo) {
        isDragging = true
        DynamicTileManager.shared.beginHandleDrag(groupID: info.groupID)
    }

    private func handleDrag(screenPoint: NSPoint, info: HandleInfo) {
        // Update horizontal split ratio (drag left/right) — throttled
        if let hSplit = info.horizontalSplit {
            let rect = hSplit.boundingRect
            guard rect.width > 0 else { return }
            let newRatio = (screenPoint.x - rect.minX) / rect.width
            DynamicTileManager.shared.updateSplitRatioDrag(
                groupID: info.groupID,
                path: hSplit.path,
                newRatio: newRatio
            )
        }

        // Update vertical split ratio (drag up/down) — throttled
        if let vSplit = info.verticalSplit {
            let rect = vSplit.boundingRect
            guard rect.height > 0 else { return }
            let newRatio = (rect.maxY - screenPoint.y) / rect.height
            DynamicTileManager.shared.updateSplitRatioDrag(
                groupID: info.groupID,
                path: vSplit.path,
                newRatio: newRatio
            )
        }

        // Reposition panels in place — don't destroy/recreate (preserves mouse capture)
        repositionHandles()
    }

    private func handleDragEnd(info: HandleInfo) {
        isDragging = false
        DynamicTileManager.shared.endHandleDrag(groupID: info.groupID)
        // Full rebuild to pick up any structural changes
        recalculateHandles()
    }
}
