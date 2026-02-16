import SwiftUI

protocol DisplayModeOption: Hashable, CaseIterable {
    var displayName: String { get }
    var icon: String { get }
}

extension BookmarkDisplayMode: DisplayModeOption {}
extension NoteDisplayMode: DisplayModeOption {}

struct ViewOptionsDropdown<Mode: DisplayModeOption>: View {
    @Binding var displayMode: Mode
    @Binding var cardSizeScale: Double

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Card Size
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Card Size")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.secondary)

                HStack(spacing: Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.tertiary)

                    Slider(value: $cardSizeScale, in: 0...3)
                        .controlSize(.small)

                    Image(systemName: "magnifyingglass")
                        .font(CiderFont.subheadingMedium)
                        .foregroundColor(CiderColors.tertiary)
                }
            }

            Divider()
                .background(CiderColors.separator)

            // View
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("View")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.secondary)

                HStack(spacing: Spacing.sm) {
                    ForEach(Array(Mode.allCases), id: \.self) { mode in
                        ViewModeIcon(
                            icon: mode.icon,
                            displayName: mode.displayName,
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
    let icon: String
    let displayName: String
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Image(systemName: icon)
            .font(CiderFont.subheadingSemibold)
            .foregroundColor(isSelected ? CiderColors.controlAccent : isHovered ? CiderColors.primary : CiderColors.secondary)
            .frame(width: 32, height: 28)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isSelected ? CiderColors.accentSelected : isHovered ? CiderColors.surfaceHover : CiderColors.surfaceInput)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .hoverState($isHovered)
            .help(displayName)
    }
}
