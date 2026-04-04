import SwiftUI

// MARK: - Single Dot

struct UtilityPanelDotView: View {
    let slot: DotSlot?
    let isActive: Bool
    let index: Int
    @ObservedObject var buffer: DotBuffer
    var onTap: (Int) -> Void
    var onCompare: ((Int, Int) -> Void)?

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        dotContent
            .scaleEffect(isHovered && slot != nil ? 1.3 : 1.0)
            .animation(reduceMotion ? .none : .snappy, value: isHovered)
            .frame(
                width: UtilityPanelDesign.dotTapTarget,
                height: UtilityPanelDesign.dotTapTarget
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if slot != nil {
                    onTap(index)
                }
            }
            .onHover { hovering in
                isHovered = hovering
            }
            .help(slot?.title ?? "Empty")
            .contextMenu {
                if let slot {
                    Button(slot.isPinned ? "Unpin" : "Pin") {
                        if slot.isPinned {
                            buffer.unpin(at: index)
                        } else {
                            buffer.pin(at: index)
                        }
                    }
                    if !buffer.isLinked(index), let onCompare {
                        Menu("Compare with...") {
                            ForEach(0..<DotBuffer.capacity, id: \.self) { otherIndex in
                                if otherIndex != index, let otherSlot = buffer.slots[otherIndex] {
                                    Button(otherSlot.title) {
                                        onCompare(index, otherIndex)
                                    }
                                }
                            }
                        }
                    }
                    Button("Close") {
                        buffer.clear(at: index)
                    }
                }
            }
    }

    private var dotContent: some View {
        let pinSize = UtilityPanelDesign.dotDiameter * 0.4
        return Circle()
            .fill(dotFill)
            .frame(
                width: UtilityPanelDesign.dotDiameter,
                height: UtilityPanelDesign.dotDiameter
            )
            .overlay {
                if isActive, slot != nil {
                    Circle()
                        .stroke(CiderColors.borderStrong, lineWidth: CiderBorder.innerStrokeWidth)
                        .frame(
                            width: UtilityPanelDesign.dotDiameter + Spacing.xxs,
                            height: UtilityPanelDesign.dotDiameter + Spacing.xxs
                        )
                }
            }
            .overlay {
                if let slot, slot.isPinned {
                    Circle()
                        .fill(CiderColors.primary)
                        .frame(width: pinSize, height: pinSize)
                }
            }
    }

    private var dotFill: Color {
        guard let slot else {
            return CiderColors.surfaceSubtle
        }
        return slot.itemType.dotColor
    }
}

// MARK: - Dot Row

struct UtilityPanelDotRow: View {
    @ObservedObject var buffer: DotBuffer
    var onDotTap: (Int) -> Void
    var onCompare: ((Int, Int) -> Void)?

    var body: some View {
        HStack(spacing: UtilityPanelDesign.dotSpacing) {
            ForEach(0..<DotBuffer.capacity, id: \.self) { index in
                UtilityPanelDotView(
                    slot: buffer.slots[index],
                    isActive: buffer.activeIndex == index,
                    index: index,
                    buffer: buffer,
                    onTap: onDotTap,
                    onCompare: onCompare
                )
            }
        }
        .overlay {
            linkBarOverlay
        }
        .frame(height: UtilityPanelDesign.dotTapTarget)
    }

    @ViewBuilder
    private var linkBarOverlay: some View {
        if let pair = buffer.linkedPair {
            let dotSize = UtilityPanelDesign.dotTapTarget
            let spacing = UtilityPanelDesign.dotSpacing
            let totalDots = CGFloat(DotBuffer.capacity)
            let rowWidth = totalDots * dotSize + (totalDots - 1) * spacing
            let step = dotSize + spacing
            let center1 = CGFloat(pair.0) * step + dotSize / 2
            let center2 = CGFloat(pair.1) * step + dotSize / 2
            let barWidth = center2 - center1
            let barMidX = (center1 + center2) / 2

            RoundedRectangle(cornerRadius: 1)
                .fill(CiderColors.controlAccent)
                .frame(width: barWidth, height: UtilityPanelDesign.dotLinkBarHeight)
                .offset(
                    x: barMidX - rowWidth / 2,
                    y: UtilityPanelDesign.dotDiameter / 2 + Spacing.xxs
                )
        }
    }
}
