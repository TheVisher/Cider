import SwiftUI

// MARK: - Single Tag Pill

/// Compact pill showing a colored dot and tag name.
struct TagPillView: View {
    let label: CardLabel
    var onTap: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(dotColor)
                .frame(width: TagDotDesign.pillDotSize, height: TagDotDesign.pillDotSize)

            Text(label.name)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.secondary)
                .lineLimit(1)

            if let onRemove, isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(CiderFont.micro)
                        .foregroundColor(CiderColors.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                .fill(tintColor.opacity(TagPillDesign.fillOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                .stroke(tintColor.opacity(TagPillDesign.strokeOpacity), lineWidth: CiderBorder.hairlineStrokeWidth)
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
        .onTapGesture { onTap?() }
        .hoverState($isHovered, animation: .snappy)
    }

    private var dotColor: Color {
        tintColor
    }

    private var tintColor: Color {
        Color(hex: label.colorHex) ?? CiderColors.secondary
    }
}

// MARK: - Tag Pill Row (Wrapping Flow)

/// Wrapping flow layout of tag pills, limited to a max number of visible lines.
struct TagPillRow: View {
    let labelIDs: [UUID]
    let labels: [CardLabel]
    var maxLines: Int = 2
    var onTapTag: ((UUID) -> Void)? = nil

    var body: some View {
        let resolved = resolvedLabels
        if !resolved.isEmpty {
            TagFlowLayout(spacing: Spacing.xs) {
                ForEach(resolved) { label in
                    TagPillView(label: label, onTap: onTapTag != nil ? { onTapTag?(label.id) } : nil)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: CGFloat(maxLines) * Spacing.xxl, alignment: .topLeading)
            .clipped()
        }
    }

    private var resolvedLabels: [CardLabel] {
        labelIDs.compactMap { id in labels.first(where: { $0.id == id }) }
    }
}

// MARK: - Sidebar Tag Pill (Compact)

/// Smaller pill used in the sidebar tag grid.
struct SidebarTagPill: View {
    let label: CardLabel
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Circle()
                .fill(tintColor)
                .frame(width: TagDotDesign.pillDotSize, height: TagDotDesign.pillDotSize)

            Text(label.name)
                .font(CiderFont.caption)
                .foregroundColor(isSelected ? CiderColors.primary : CiderColors.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xxs + 1)
        .background(
            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                .fill(isSelected ? CiderColors.selectedFill : (isHovered ? CiderColors.surfaceHover : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                .stroke(isSelected ? CiderColors.selectedBorder : (isHovered ? CiderColors.borderHover : Color.clear),
                        lineWidth: CiderBorder.innerStrokeWidth)
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
        .onTapGesture { onTap?() }
        .hoverState($isHovered, animation: .snappy)
    }

    private var tintColor: Color {
        Color(hex: label.colorHex) ?? CiderColors.secondary
    }
}

// MARK: - Flow Layout

/// Simple wrapping flow layout for tag pills.
struct TagFlowLayout: Layout {
    var spacing: CGFloat = Spacing.xs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeFrames(proposal: proposal, subviews: subviews)
        return result.totalSize
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeFrames(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.origin.x, y: bounds.minY + frame.origin.y),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private struct LayoutResult {
        var frames: [CGRect]
        var totalSize: CGSize
    }

    private func computeFrames(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: currentX, y: currentY), size: size))
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        let totalWidth = maxWidth == .infinity
            ? frames.reduce(0) { max($0, $1.maxX) }
            : maxWidth
        let totalHeight = currentY + rowHeight

        return LayoutResult(frames: frames, totalSize: CGSize(width: totalWidth, height: totalHeight))
    }
}
