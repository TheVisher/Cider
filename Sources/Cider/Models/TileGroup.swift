import AppKit
import Foundation

@MainActor
final class TileGroup {
    let id: UUID
    var screenID: UInt32
    var root: TileNode
    let gap: CGFloat

    /// Computed from MonitorManager each time — never stale.
    var boundingRect: CGRect {
        MonitorManager.shared.monitor(for: screenID)?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? .zero
    }

    init(id: UUID = UUID(), screenID: UInt32, root: TileNode, gap: CGFloat = CiderDesign.tileGap) {
        self.id = id
        self.screenID = screenID
        self.root = root
        self.gap = gap
    }

    /// Add a window by splitting an existing leaf.
    func addWindow(newWindowID: CGWindowID, newPID: pid_t,
                   targetWindowID: CGWindowID, side: SplitSide) {
        let newLeaf = TileNode.leaf(windowID: newWindowID, pid: newPID)

        // Preserve the target's pid from the existing tree
        let targetLeafData = root.allWindowIDs().first(where: { $0.0 == targetWindowID })
        let targetPID = targetLeafData?.1 ?? 0
        let targetLeaf = TileNode.leaf(windowID: targetWindowID, pid: targetPID)

        let splitNode: TileNode
        switch side {
        case .left:
            splitNode = .split(orientation: .horizontal, ratio: 0.5, left: newLeaf, right: targetLeaf)
        case .right:
            splitNode = .split(orientation: .horizontal, ratio: 0.5, left: targetLeaf, right: newLeaf)
        case .top:
            splitNode = .split(orientation: .vertical, ratio: 0.5, left: newLeaf, right: targetLeaf)
        case .bottom:
            splitNode = .split(orientation: .vertical, ratio: 0.5, left: targetLeaf, right: newLeaf)
        }

        root = root.replaceLeaf(windowID: targetWindowID, with: splitNode)
    }

    /// Remove a window from the group. Returns true if the group should be dissolved (0 or 1 window left).
    func removeWindow(_ windowID: CGWindowID) -> Bool {
        guard let newRoot = root.removeLeaf(windowID: windowID) else {
            return true  // Tree is empty
        }

        // Check if only one leaf remains
        if case .leaf = newRoot {
            root = newRoot
            return true  // Only 1 window left, dissolve
        }

        root = newRoot
        return false
    }

    /// Recalculate frames for all windows in the group.
    func recalculateFrames() -> [(CGWindowID, pid_t, CGRect)] {
        root.calculateFrames(in: boundingRect, gap: gap)
    }

    /// Update the split ratio based on a window's new frame after user resize.
    func updateRatio(forWindowID windowID: CGWindowID, newFrame: CGRect) {
        guard let (orientation, _) = root.findParentSplit(of: windowID) else { return }

        let bounds = boundingRect
        guard bounds.width > 0, bounds.height > 0 else { return }

        let newRatio: CGFloat
        switch orientation {
        case .horizontal:
            // Figure out if this window is the "left" or "right" child
            // by checking where it sits relative to the bounding rect center
            let midX = newFrame.midX
            if midX < bounds.midX {
                // Left child: ratio = right edge of window / total width
                newRatio = (newFrame.maxX - bounds.minX + gap / 2) / bounds.width
            } else {
                // Right child: ratio = left edge of window / total width
                newRatio = (newFrame.minX - bounds.minX - gap / 2) / bounds.width
            }
        case .vertical:
            let midY = newFrame.midY
            if midY > bounds.midY {
                // Top child (left in our tree): ratio = distance from top to bottom edge of window
                newRatio = (bounds.maxY - newFrame.minY + gap / 2) / bounds.height
            } else {
                // Bottom child (right in our tree): ratio = distance from top to top edge of window
                newRatio = (bounds.maxY - newFrame.maxY - gap / 2) / bounds.height
            }
        }

        root = root.updateRatio(forWindow: windowID, newRatio: newRatio)
    }
}
