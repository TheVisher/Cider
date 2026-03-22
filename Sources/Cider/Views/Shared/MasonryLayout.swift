import SwiftUI

// MARK: - Column Span Layout Value

/// Layout value key for per-item column spanning in MasonryLayout.
/// Usage: `.layoutValue(key: MasonryColumnSpan.self, value: 2)`
/// Or use the convenience modifier: `.masonryColumnSpan(2)`
struct MasonryColumnSpan: LayoutValueKey {
    static let defaultValue: Int = 1
}

extension View {
    /// Set how many columns this item should span in a MasonryLayout.
    func masonryColumnSpan(_ span: Int) -> some View {
        layoutValue(key: MasonryColumnSpan.self, value: max(1, span))
    }
}

// MARK: - MasonryLayout

struct MasonryLayout: Layout {
    let minimumColumnWidth: CGFloat
    let itemSpacing: CGFloat

    struct Cache {
        var frames: [CGRect] = []
        var measuredWidth: CGFloat = 0
        var measuredHeight: CGFloat = 0
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(frames: Array(repeating: .zero, count: subviews.count))
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        if cache.frames.count != subviews.count {
            cache.frames = Array(repeating: .zero, count: subviews.count)
        }
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        let availableWidth = resolvedLayoutWidth(proposal.width)
        computeFrames(availableWidth: availableWidth, subviews: subviews, cache: &cache)
        return CGSize(width: availableWidth, height: cache.measuredHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        let availableWidth = resolvedLayoutWidth(bounds.width)
        if cache.measuredWidth != availableWidth || cache.frames.count != subviews.count {
            computeFrames(availableWidth: availableWidth, subviews: subviews, cache: &cache)
        }

        for index in subviews.indices {
            let frame = cache.frames[index]
            let origin = CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY)
            subviews[index].place(
                at: origin,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func computeFrames(
        availableWidth: CGFloat,
        subviews: Subviews,
        cache: inout Cache
    ) {
        if cache.frames.count != subviews.count {
            cache.frames = Array(repeating: .zero, count: subviews.count)
        }

        let columnCount = resolvedColumnCount(for: availableWidth)
        let columnWidth = resolvedColumnWidth(for: availableWidth, columnCount: columnCount)
        var columnHeights = Array(repeating: CGFloat(0), count: columnCount)

        for index in subviews.indices {
            let requestedSpan = subviews[index][MasonryColumnSpan.self]
            let span = min(requestedSpan, columnCount)

            if span > 1 {
                // Multi-column span: find the best starting column where `span` consecutive
                // columns have the lowest maximum height.
                let startColumn = bestStartColumn(for: span, columnHeights: columnHeights)
                let spanWidth = columnWidth * CGFloat(span) + itemSpacing * CGFloat(span - 1)
                let y = (startColumn..<(startColumn + span)).map { columnHeights[$0] }.max() ?? 0
                let measured = subviews[index].sizeThatFits(
                    ProposedViewSize(width: spanWidth, height: nil)
                )
                let x = CGFloat(startColumn) * (columnWidth + itemSpacing)
                cache.frames[index] = CGRect(x: x, y: y, width: spanWidth, height: measured.height)
                // Update all spanned columns to the same bottom edge
                for col in startColumn..<(startColumn + span) {
                    columnHeights[col] = y + measured.height + itemSpacing
                }
            } else {
                // Single column: place in shortest column
                let column = columnHeights.enumerated().min(by: { $0.element < $1.element })!.offset
                let measured = subviews[index].sizeThatFits(
                    ProposedViewSize(width: columnWidth, height: nil)
                )
                let x = CGFloat(column) * (columnWidth + itemSpacing)
                let y = columnHeights[column]
                cache.frames[index] = CGRect(x: x, y: y, width: columnWidth, height: measured.height)
                columnHeights[column] += measured.height + itemSpacing
            }
        }

        cache.measuredWidth = availableWidth
        cache.measuredHeight = max(0, (columnHeights.max() ?? 0) - itemSpacing)
    }

    /// Find the starting column index where `span` consecutive columns
    /// have the lowest maximum height (best fit for a spanning item).
    private func bestStartColumn(for span: Int, columnHeights: [CGFloat]) -> Int {
        guard columnHeights.count >= span else { return 0 }
        var bestStart = 0
        var bestMaxHeight = CGFloat.infinity
        for start in 0...(columnHeights.count - span) {
            let maxHeight = (start..<(start + span)).map { columnHeights[$0] }.max() ?? 0
            if maxHeight < bestMaxHeight {
                bestMaxHeight = maxHeight
                bestStart = start
            }
        }
        return bestStart
    }

    private func resolvedColumnCount(for width: CGFloat) -> Int {
        guard width.isFinite, width > minimumColumnWidth else { return 1 }

        let denominator = minimumColumnWidth + itemSpacing
        guard denominator.isFinite, denominator > 0 else { return 1 }

        let rawCount = ((width + itemSpacing) / denominator).rounded(.down)
        guard rawCount.isFinite, rawCount > 0 else { return 1 }

        let count = Int(rawCount)
        return max(1, count)
    }

    private func resolvedColumnWidth(for width: CGFloat, columnCount: Int) -> CGFloat {
        guard width.isFinite, width > 0 else { return minimumColumnWidth }
        guard columnCount > 1 else { return width }
        let totalSpacing = itemSpacing * CGFloat(columnCount - 1)
        let computed = (width - totalSpacing) / CGFloat(columnCount)
        guard computed.isFinite, computed > 0 else { return minimumColumnWidth }
        return max(1, computed)
    }

    private func resolvedLayoutWidth(_ proposedWidth: CGFloat?) -> CGFloat {
        let rawWidth = proposedWidth ?? minimumColumnWidth
        guard rawWidth.isFinite, rawWidth > 0 else { return minimumColumnWidth }
        return rawWidth
    }
}
