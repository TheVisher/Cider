import SwiftUI

/// Popover content shown on hover over the green traffic light button.
/// Provides one-click snap presets with consistent 15pt gaps from screen edges.
///
/// No @FocusState or animations — RemoteViewService (XPC) crashes on both
/// in non-activating NSPanel popovers.
struct SnapMenuView: View {
    let onSnap: (SnapTarget) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SnapMenuRow(
                symbol: "rectangle.inset.filled",
                label: "Almost Maximized",
                onTap: { onSnap(.almostMaximized) }
            )

            Divider()
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xxs)

            SnapMenuRow(
                symbol: "rectangle.lefthalf.inset.filled",
                label: "Left Half",
                onTap: { onSnap(.leftHalf) }
            )
            SnapMenuRow(
                symbol: "rectangle.righthalf.inset.filled",
                label: "Right Half",
                onTap: { onSnap(.rightHalf) }
            )

            Divider()
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xxs)

            SnapMenuRow(
                symbol: "rectangle.leadingthird.inset.filled",
                label: "Left Edge",
                onTap: { onSnap(.leftEdge) }
            )
            SnapMenuRow(
                symbol: "rectangle.trailingthird.inset.filled",
                label: "Right Edge",
                onTap: { onSnap(.rightEdge) }
            )
        }
        .padding(.vertical, Spacing.xs)
        .frame(width: 210)
    }
}

private struct SnapMenuRow: View {
    let symbol: String
    let label: String
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: symbol)
                    .font(CiderFont.body)
                    .foregroundStyle(CiderColors.secondary)
                    .frame(width: Spacing.xl, alignment: .center)
                Text(label)
                    .font(CiderFont.body)
                    .foregroundStyle(CiderColors.primary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    .fill(isHovered ? CiderColors.surfaceHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .hoverState($isHovered)
        .padding(.horizontal, Spacing.xs)
    }
}
