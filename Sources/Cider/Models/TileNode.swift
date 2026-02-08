import Foundation
import CoreGraphics

enum SplitOrientation {
    case horizontal  // left | right
    case vertical    // top / bottom
}

enum SplitSide {
    case left, right, top, bottom
}

indirect enum TileNode {
    case leaf(windowID: CGWindowID, pid: pid_t)
    case split(orientation: SplitOrientation, ratio: CGFloat, left: TileNode, right: TileNode)

    // MARK: - Queries

    /// Collect all leaf window IDs and PIDs.
    func allWindowIDs() -> [(CGWindowID, pid_t)] {
        switch self {
        case .leaf(let windowID, let pid):
            return [(windowID, pid)]
        case .split(_, _, let left, let right):
            return left.allWindowIDs() + right.allWindowIDs()
        }
    }

    /// Check if tree contains a window.
    func containsWindow(_ windowID: CGWindowID) -> Bool {
        switch self {
        case .leaf(let wid, _):
            return wid == windowID
        case .split(_, _, let left, let right):
            return left.containsWindow(windowID) || right.containsWindow(windowID)
        }
    }

    /// Find the parent split's orientation and ratio for a given window.
    func findParentSplit(of windowID: CGWindowID) -> (SplitOrientation, CGFloat)? {
        switch self {
        case .leaf:
            return nil
        case .split(let orientation, let ratio, let left, let right):
            // Check if either child is the target leaf
            if case .leaf(let wid, _) = left, wid == windowID {
                return (orientation, ratio)
            }
            if case .leaf(let wid, _) = right, wid == windowID {
                return (orientation, ratio)
            }
            // Recurse
            return left.findParentSplit(of: windowID) ?? right.findParentSplit(of: windowID)
        }
    }

    // MARK: - Mutations (return new tree)

    /// Replace a leaf with a new subtree.
    func replaceLeaf(windowID: CGWindowID, with newNode: TileNode) -> TileNode {
        switch self {
        case .leaf(let wid, _):
            if wid == windowID { return newNode }
            return self
        case .split(let orientation, let ratio, let left, let right):
            return .split(
                orientation: orientation,
                ratio: ratio,
                left: left.replaceLeaf(windowID: windowID, with: newNode),
                right: right.replaceLeaf(windowID: windowID, with: newNode)
            )
        }
    }

    /// Remove a leaf and normalize the tree (collapse degenerate splits).
    /// Returns nil if the entire tree would be empty.
    func removeLeaf(windowID: CGWindowID) -> TileNode? {
        switch self {
        case .leaf(let wid, _):
            if wid == windowID { return nil }
            return self
        case .split(let orientation, let ratio, let left, let right):
            let newLeft = left.removeLeaf(windowID: windowID)
            let newRight = right.removeLeaf(windowID: windowID)

            switch (newLeft, newRight) {
            case (nil, nil):
                return nil
            case (nil, let remaining):
                return remaining  // Collapse: promote remaining child
            case (let remaining, nil):
                return remaining  // Collapse: promote remaining child
            case (let l?, let r?):
                return .split(orientation: orientation, ratio: ratio, left: l, right: r)
            }
        }
    }

    /// Update the ratio of the split that directly contains the given window.
    /// Clamps ratio to 0.1...0.9.
    func updateRatio(forWindow windowID: CGWindowID, newRatio: CGFloat) -> TileNode {
        let clamped = min(0.9, max(0.1, newRatio))

        switch self {
        case .leaf:
            return self
        case .split(let orientation, let ratio, let left, let right):
            // Check if either direct child is the target leaf
            let leftContains: Bool
            let rightContains: Bool

            if case .leaf(let wid, _) = left { leftContains = wid == windowID }
            else { leftContains = false }

            if case .leaf(let wid, _) = right { rightContains = wid == windowID }
            else { rightContains = false }

            if leftContains || rightContains {
                return .split(orientation: orientation, ratio: clamped, left: left, right: right)
            }

            // Recurse
            return .split(
                orientation: orientation,
                ratio: ratio,
                left: left.updateRatio(forWindow: windowID, newRatio: newRatio),
                right: right.updateRatio(forWindow: windowID, newRatio: newRatio)
            )
        }
    }

    // MARK: - Frame Calculation

    /// Recursively compute each leaf's frame within a bounding rect, subtracting gap at each split.
    func calculateFrames(in rect: CGRect, gap: CGFloat) -> [(CGWindowID, pid_t, CGRect)] {
        switch self {
        case .leaf(let windowID, let pid):
            return [(windowID, pid, rect)]
        case .split(let orientation, let ratio, let left, let right):
            let halfGap = gap / 2

            switch orientation {
            case .horizontal:
                let leftWidth = rect.width * ratio - halfGap
                let rightWidth = rect.width * (1 - ratio) - halfGap

                let leftRect = CGRect(
                    x: rect.minX,
                    y: rect.minY,
                    width: leftWidth,
                    height: rect.height
                )
                let rightRect = CGRect(
                    x: rect.minX + rect.width * ratio + halfGap,
                    y: rect.minY,
                    width: rightWidth,
                    height: rect.height
                )

                return left.calculateFrames(in: leftRect, gap: gap)
                     + right.calculateFrames(in: rightRect, gap: gap)

            case .vertical:
                let topHeight = rect.height * ratio - halfGap
                let bottomHeight = rect.height * (1 - ratio) - halfGap

                // NSScreen coords: Y increases upward. "top" = higher Y values.
                let topRect = CGRect(
                    x: rect.minX,
                    y: rect.minY + rect.height * (1 - ratio) + halfGap,
                    width: rect.width,
                    height: topHeight
                )
                let bottomRect = CGRect(
                    x: rect.minX,
                    y: rect.minY,
                    width: rect.width,
                    height: bottomHeight
                )

                // "left" child = top, "right" child = bottom
                return left.calculateFrames(in: topRect, gap: gap)
                     + right.calculateFrames(in: bottomRect, gap: gap)
            }
        }
    }
}
