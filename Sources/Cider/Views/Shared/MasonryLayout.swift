import SwiftUI

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
        // Reuse frames from sizeThatFits if width matches (same layout pass).
        // Cross-pass subview size changes are caught by sizeThatFits which always recomputes.
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
            let column = columnHeights.enumerated().min(by: { $0.element < $1.element })!.offset
            let measured = subviews[index].sizeThatFits(
                ProposedViewSize(width: columnWidth, height: nil)
            )
            let height = measured.height
            let x = CGFloat(column) * (columnWidth + itemSpacing)
            let y = columnHeights[column]
            cache.frames[index] = CGRect(x: x, y: y, width: columnWidth, height: height)
            columnHeights[column] += height + itemSpacing
        }

        cache.measuredWidth = availableWidth
        cache.measuredHeight = max(0, (columnHeights.max() ?? 0) - itemSpacing)
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
