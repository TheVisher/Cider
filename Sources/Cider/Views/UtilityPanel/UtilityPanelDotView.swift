import SwiftUI

// MARK: - Single Dot

struct UtilityPanelDotView: View {
    let slot: DotSlot?
    let isActive: Bool
    let index: Int
    @ObservedObject var buffer: DotBuffer
    var onTap: (Int) -> Void

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

    var body: some View {
        HStack(spacing: UtilityPanelDesign.dotSpacing) {
            ForEach(0..<DotBuffer.capacity, id: \.self) { index in
                UtilityPanelDotView(
                    slot: buffer.slots[index],
                    isActive: buffer.activeIndex == index,
                    index: index,
                    buffer: buffer,
                    onTap: onDotTap
                )
            }
        }
    }
}
