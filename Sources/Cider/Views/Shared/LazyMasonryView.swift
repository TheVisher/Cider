import SwiftUI

struct LazyMasonryView<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let minimumColumnWidth: CGFloat
    let itemSpacing: CGFloat
    var viewportWidth: CGFloat?
    let estimatedHeight: (Item, CGFloat) -> CGFloat
    @ViewBuilder let content: (Item, CGFloat) -> Content

    @State private var containerWidth: CGFloat = 0
    @State private var plannedColumns = LazyMasonryColumnPlanner.Plan<Item.ID>.empty

    var body: some View {
        let resolvedContainerWidth = LazyMasonryColumnPlanner.explicitContainerWidth(
            viewportWidth,
            fallbackWidth: max(containerWidth, minimumColumnWidth)
        )
        let layout = LazyMasonryColumnPlanner.layout(
            containerWidth: resolvedContainerWidth,
            minimumColumnWidth: minimumColumnWidth,
            itemSpacing: itemSpacing
        )
        let renderingColumnWidth = LazyMasonryColumnPlanner.renderingColumnWidth(for: layout)
        let itemLookup = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let resolvedPlan = LazyMasonryColumnPlanner.stablePlan(
            items: items,
            layout: layout,
            itemSpacing: itemSpacing,
            estimatedHeight: { item in
                estimatedHeight(item, renderingColumnWidth)
            },
            previousPlan: plannedColumns
        )
        let columns = resolvedPlan.columns.map { columnIDs in
            columnIDs.compactMap { itemLookup[$0] }
        }

        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(maxWidth: .infinity)
                .background {
                    if viewportWidth == nil {
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear {
                                    updateContainerWidth(parentWidth: proxy.size.width)
                                }
                                .onChange(of: proxy.size.width) { _, width in
                                    updateContainerWidth(parentWidth: width)
                                }
                            }
                    }
                }

            HStack(alignment: .top, spacing: itemSpacing) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, columnItems in
                    LazyVStack(spacing: itemSpacing) {
                        ForEach(columnItems) { item in
                            content(item, renderingColumnWidth)
                                .frame(width: renderingColumnWidth, alignment: .topLeading)
                        }
                    }
                    .frame(width: renderingColumnWidth, alignment: .top)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: resolvedPlan.key) {
            syncPlan(with: resolvedPlan)
        }
    }

    private func updateContainerWidth(parentWidth: CGFloat) {
        let width = LazyMasonryColumnPlanner.resolvedContainerWidth(
            parentWidth: parentWidth,
            measuredContentWidth: containerWidth,
            minimumColumnWidth: minimumColumnWidth
        )
        guard width.isFinite, width > 0 else { return }
        guard abs(width - containerWidth) > 0.5 else { return }
        guard LazyMasonryColumnPlanner.shouldPublishContainerWidth(
            currentWidth: containerWidth,
            candidateWidth: width,
            minimumColumnWidth: minimumColumnWidth,
            itemSpacing: itemSpacing
        ) else { return }
        containerWidth = width
    }

    private func syncPlan(with plan: LazyMasonryColumnPlanner.Plan<Item.ID>) {
        guard plannedColumns != plan else { return }
        plannedColumns = plan
    }
}

enum LazyMasonryColumnPlanner {
    struct LayoutMetrics: Equatable {
        let columnCount: Int
        let columnWidth: CGFloat
    }

    /// Resize gestures can publish a new container width every pixel. Replanning the
    /// whole masonry column assignment for each tiny width change is expensive and
    /// visually unnecessary because card frames still receive the exact live column
    /// width. Bucket only the planning key so we keep layout responsive while avoiding
    /// hundreds of full column-plan recalculations during window drags.
    static let planningColumnWidthBucket: CGFloat = 8

    struct PlanKey<ID: Hashable>: Equatable {
        let itemIDs: [ID]
        let layout: LayoutMetrics
    }

    struct Plan<ID: Hashable>: Equatable {
        let key: PlanKey<ID>
        let columns: [[ID]]

        static var empty: Self {
            .init(
                key: .init(itemIDs: [], layout: .init(columnCount: 1, columnWidth: 0)),
                columns: []
            )
        }
    }

    static func layout(
        containerWidth: CGFloat,
        minimumColumnWidth: CGFloat,
        itemSpacing: CGFloat
    ) -> LayoutMetrics {
        let resolvedWidth = max(containerWidth, 1)
        let denominator = max(minimumColumnWidth + itemSpacing, 1)
        let rawColumnCount = Int(((resolvedWidth + itemSpacing) / denominator).rounded(.down))
        let columnCount = max(1, rawColumnCount)
        let totalSpacing = itemSpacing * CGFloat(columnCount - 1)
        let columnWidth = max(1, (resolvedWidth - totalSpacing) / CGFloat(columnCount))
        return LayoutMetrics(columnCount: columnCount, columnWidth: columnWidth)
    }

    static func explicitContainerWidth(_ width: CGFloat?, fallbackWidth: CGFloat) -> CGFloat {
        if let width, width.isFinite, width > 0 {
            return width
        }
        guard fallbackWidth.isFinite, fallbackWidth > 0 else { return 1 }
        return fallbackWidth
    }

    static func resolvedContainerWidth(
        parentWidth: CGFloat,
        measuredContentWidth: CGFloat,
        minimumColumnWidth: CGFloat
    ) -> CGFloat {
        if parentWidth.isFinite, parentWidth > 0 {
            return max(parentWidth, minimumColumnWidth)
        }
        if measuredContentWidth.isFinite, measuredContentWidth > 0 {
            return max(measuredContentWidth, minimumColumnWidth)
        }
        return minimumColumnWidth
    }

    static func shouldPublishContainerWidth(
        currentWidth: CGFloat,
        candidateWidth: CGFloat,
        minimumColumnWidth: CGFloat,
        itemSpacing: CGFloat
    ) -> Bool {
        guard candidateWidth.isFinite, candidateWidth > 0 else { return false }
        guard currentWidth.isFinite, currentWidth > 0 else { return true }

        let currentLayout = layout(
            containerWidth: currentWidth,
            minimumColumnWidth: minimumColumnWidth,
            itemSpacing: itemSpacing
        )
        let candidateLayout = layout(
            containerWidth: candidateWidth,
            minimumColumnWidth: minimumColumnWidth,
            itemSpacing: itemSpacing
        )

        guard currentLayout.columnCount == candidateLayout.columnCount else { return true }
        return renderingColumnWidth(for: currentLayout) != renderingColumnWidth(for: candidateLayout)
    }

    static func plan<Item: Identifiable>(
        items: [Item],
        columnCount: Int,
        itemSpacing: CGFloat,
        estimatedHeight: (Item) -> CGFloat
    ) -> [[Item]] {
        guard columnCount > 1 else { return [items] }

        var columns = Array(repeating: [Item](), count: columnCount)
        var heights = Array(repeating: CGFloat(0), count: columnCount)

        for item in items {
            let targetColumn = heights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            columns[targetColumn].append(item)
            heights[targetColumn] += estimatedHeight(item) + itemSpacing
        }

        return columns
    }

    static func stablePlan<Item: Identifiable>(
        items: [Item],
        layout: LayoutMetrics,
        itemSpacing: CGFloat,
        estimatedHeight: (Item) -> CGFloat,
        previousPlan: Plan<Item.ID>
    ) -> Plan<Item.ID> {
        let key = PlanKey(itemIDs: items.map(\.id), layout: planningKeyLayout(for: layout))
        guard previousPlan.key != key else { return previousPlan }

        let columns = plan(
            items: items,
            columnCount: layout.columnCount,
            itemSpacing: itemSpacing,
            estimatedHeight: estimatedHeight
        ).map { column in
            column.map(\.id)
        }

        return Plan(key: key, columns: columns)
    }

    static func planningKeyLayout(for layout: LayoutMetrics) -> LayoutMetrics {
        guard layout.columnWidth.isFinite, layout.columnWidth > 0 else { return layout }
        let bucket = max(planningColumnWidthBucket, 1)
        let bucketedWidth = (layout.columnWidth / bucket).rounded() * bucket
        return LayoutMetrics(columnCount: layout.columnCount, columnWidth: bucketedWidth)
    }

    static func renderingColumnWidth(for layout: LayoutMetrics) -> CGFloat {
        guard layout.columnWidth.isFinite, layout.columnWidth > 0 else { return layout.columnWidth }
        let bucket = max(planningColumnWidthBucket, 1)
        return max(1, (layout.columnWidth / bucket).rounded(.down) * bucket)
    }
}
