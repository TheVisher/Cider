import SwiftUI

/// Folder group container on the canvas with collapsible header and child card grid.
struct CanvasFolderGroupView: View {
    let node: CanvasNode
    let zoom: CGFloat
    @ObservedObject var viewModel: CanvasViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var folderName: String {
        viewModel.titleCache[node.id] ?? "Folder"
    }

    private var childNodes: [CanvasNode] {
        viewModel.nodes.filter { $0.parentNodeID == node.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar

            if !node.collapsed {
                childGrid
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, Spacing.md)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .stroke(CiderColors.borderSubtle, lineWidth: 1)
                )
        )
        .frame(width: node.collapsed ? nil : node.size.width)
    }

    // MARK: - Header

    private var headerBar: some View {
        Button {
            withAnimation(reduceMotion ? .none : .snappy(duration: 0.25)) {
                viewModel.toggleCollapse(nodeID: node.id)
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: node.collapsed ? "chevron.right" : "chevron.down")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: 12)

                Image(systemName: "folder.fill")
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(CiderColors.secondary)

                Text(folderName)
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(CiderColors.primary)

                Text("\(childNodes.count)")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxs)
                    .background(CiderColors.surfaceSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))

                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Child Grid

    private var childGrid: some View {
        let columns = min(4, max(1, childNodes.count))
        let gridItems = Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: columns)

        return LazyVGrid(columns: gridItems, spacing: Spacing.md) {
            ForEach(childNodes) { child in
                CanvasCardView(
                    node: child,
                    zoom: zoom,
                    viewModel: viewModel
                )
            }
        }
    }
}
