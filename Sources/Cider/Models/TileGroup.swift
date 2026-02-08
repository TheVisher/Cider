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

    /// Extract all split line geometry from the tree.
    func splitLines() -> [SplitLineInfo] {
        root.splitLines(in: boundingRect, gap: gap)
    }

    /// Update the ratio of the split at the given tree path.
    func updateRatioAtPath(_ path: [Int], newRatio: CGFloat) {
        root = root.updateRatioAtPath(path, newRatio: newRatio)
    }

    /// Update the split ratio based on a window's new frame after user resize.
    func updateRatio(forWindowID windowID: CGWindowID, newFrame: CGRect) {
        guard let splitInfo = root.parentSplitInfo(of: windowID),
              let splitBounds = root.splitRect(at: splitInfo.path, in: boundingRect, gap: gap) else { return }
        guard splitBounds.width > 0, splitBounds.height > 0 else { return }

        let newRatio: CGFloat
        switch splitInfo.orientation {
        case .horizontal:
            if splitInfo.childIndex == 0 {
                // Left child: ratio = right edge of window / total width
                newRatio = (newFrame.maxX - splitBounds.minX + gap / 2) / splitBounds.width
            } else {
                // Right child: ratio = left edge of window / total width
                newRatio = (newFrame.minX - splitBounds.minX - gap / 2) / splitBounds.width
            }
        case .vertical:
            if splitInfo.childIndex == 0 {
                // Top child (left in our tree): ratio = distance from top to bottom edge of window
                newRatio = (splitBounds.maxY - newFrame.minY + gap / 2) / splitBounds.height
            } else {
                // Bottom child (right in our tree): ratio = distance from top to top edge of window
                newRatio = (splitBounds.maxY - newFrame.maxY - gap / 2) / splitBounds.height
            }
        }

        root = root.updateRatioAtPath(splitInfo.path, newRatio: newRatio)
    }
}
