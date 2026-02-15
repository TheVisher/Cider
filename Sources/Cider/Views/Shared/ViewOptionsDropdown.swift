import SwiftUI

struct ViewOptionsDropdown: View {
    @Binding var displayMode: BookmarkDisplayMode
    @Binding var cardSizeScale: Double

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Card Size
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Card Size")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(CiderColors.secondary)

                HStack(spacing: Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(CiderColors.tertiary)

                    Slider(value: $cardSizeScale, in: 0...3)
                        .controlSize(.small)

                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(CiderColors.tertiary)
                }
            }

            Divider()
                .background(CiderColors.separator)

            // View
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("View")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(CiderColors.secondary)

                HStack(spacing: Spacing.sm) {
                    ForEach(BookmarkDisplayMode.allCases, id: \.self) { mode in
                        ViewModeIcon(
                            mode: mode,
                            isSelected: displayMode == mode,
                            onTap: {
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    displayMode = mode
                                }
                            }
                        )
                    }
                }
            }
        }
        .padding(Spacing.md)
        .frame(width: 200)
    }
}

private struct ViewModeIcon: View {
    let mode: BookmarkDisplayMode
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Image(systemName: mode.icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(isSelected ? CiderColors.controlAccent : isHovered ? CiderColors.primary : CiderColors.secondary)
            .frame(width: 32, height: 28)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isSelected ? CiderColors.controlAccent.opacity(0.18) : isHovered ? Color.white.opacity(0.14) : Color.white.opacity(0.08))
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .onHover { isHovered = $0 }
            .help(mode.displayName)
    }
}
