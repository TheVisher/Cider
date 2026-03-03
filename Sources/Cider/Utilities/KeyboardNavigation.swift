import Foundation

/// Pure spatial navigation logic for grid/list/masonry keyboard navigation.
/// No UI dependencies — input is item IDs and column count, output is next ID.
enum KeyboardNavigation {
    enum Direction { case up, down, left, right }

    /// Given current focused item, item list, column count, and direction,
    /// returns the ID of the item to focus next. Returns nil if at boundary.
    static func nextItem(
        from currentID: String,
        in items: [String],
        columns: Int,
        direction: Direction
    ) -> String? {
        guard let currentIndex = items.firstIndex(of: currentID) else { return nil }
        let cols = max(columns, 1)

        let targetIndex: Int
        switch direction {
        case .left:
            guard cols > 1, currentIndex % cols != 0 else { return nil }
            targetIndex = currentIndex - 1
        case .right:
            guard cols > 1, currentIndex % cols != cols - 1 else { return nil }
            targetIndex = currentIndex + 1
        case .up:
            targetIndex = currentIndex - cols
        case .down:
            targetIndex = currentIndex + cols
        }

        guard targetIndex >= 0, targetIndex < items.count else { return nil }
        return items[targetIndex]
    }

    /// Linear next (Tab)
    static func linearNext(from currentID: String, in items: [String]) -> String? {
        guard let index = items.firstIndex(of: currentID),
              index + 1 < items.count else { return nil }
        return items[index + 1]
    }

    /// Linear previous (Shift+Tab)
    static func linearPrevious(from currentID: String, in items: [String]) -> String? {
        guard let index = items.firstIndex(of: currentID),
              index - 1 >= 0 else { return nil }
        return items[index - 1]
    }

    /// Range selection: all items between anchor and target (inclusive)
    static func rangeSelection(
        from anchorID: String,
        to targetID: String,
        in items: [String]
    ) -> Set<String> {
        guard let anchorIndex = items.firstIndex(of: anchorID),
              let targetIndex = items.firstIndex(of: targetID) else { return [] }
        let lo = min(anchorIndex, targetIndex)
        let hi = max(anchorIndex, targetIndex)
        return Set(items[lo...hi])
    }
}
