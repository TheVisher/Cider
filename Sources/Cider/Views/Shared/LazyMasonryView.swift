import SwiftUI

struct LazyMasonryView<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let minimumColumnWidth: CGFloat
    let itemSpacing: CGFloat
    let estimatedHeight: (Item, CGFloat) -> CGFloat
    @ViewBuilder let content: (Item, CGFloat) -> Content

    @State private var containerWidth: CGFloat = 0
    @State private var plannedColumns = LazyMasonryColumnPlanner.Plan<Item.ID>.empty

    var body: some View {
        let layout = LazyMasonryColumnPlanner.layout(
            containerWidth: max(containerWidth, minimumColumnWidth),
            minimumColumnWidth: minimumColumnWidth,
            itemSpacing: itemSpacing
        )
        let itemLookup = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let resolvedPlan = LazyMasonryColumnPlanner.stablePlan(
            items: items,
            layout: layout,
            itemSpacing: itemSpacing,
            estimatedHeight: { item in
                estimatedHeight(item, layout.columnWidth)
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

            HStack(alignment: .top, spacing: itemSpacing) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, columnItems in
                    LazyVStack(spacing: itemSpacing) {
                        ForEach(columnItems) { item in
                            content(item, layout.columnWidth)
                                .frame(width: layout.columnWidth, alignment: .topLeading)
                        }
                    }
                    .frame(width: layout.columnWidth, alignment: .top)
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
        let resolvedWidth = max(containerWidth, minimumColumnWidth)
        let denominator = max(minimumColumnWidth + itemSpacing, 1)
        let rawColumnCount = Int(((resolvedWidth + itemSpacing) / denominator).rounded(.down))
        let columnCount = max(1, rawColumnCount)
        let totalSpacing = itemSpacing * CGFloat(columnCount - 1)
        let columnWidth = max(1, (resolvedWidth - totalSpacing) / CGFloat(columnCount))
        return LayoutMetrics(columnCount: columnCount, columnWidth: columnWidth)
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
        let key = PlanKey(itemIDs: items.map(\.id), layout: layout)
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
}
