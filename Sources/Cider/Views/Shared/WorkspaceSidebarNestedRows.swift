import SwiftUI

enum WorkspaceSidebarNestedRowMetrics {
    static let iconFrame: CGFloat = Spacing.lg
    static let horizontalPadding: CGFloat = Spacing.sm
    static let verticalPadding: CGFloat = Spacing.xxs
    static let childIndent: CGFloat = Spacing.lg
}

struct WorkspaceSidebarNestedSectionHeader: View {
    let title: String
    var count: Int?

    @Environment(\.textScale) private var textScale

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Text(title)
                .font(CiderFont.captionSemibold(scale: textScale))
                .foregroundColor(CiderColors.tertiary)

            Spacer(minLength: 0)

            if let count {
                Text("\(count)")
                    .font(CiderFont.microMonospaced)
                    .foregroundColor(CiderColors.tertiary)
            }
        }
        .padding(.horizontal, WorkspaceSidebarNestedRowMetrics.horizontalPadding)
    }
}

struct WorkspaceSidebarNestedRowLabel: View {
    let title: String
    var subtitle: String?
    let systemImage: String
    let isSelected: Bool
    var badge: String?

    @Environment(\.textScale) private var textScale

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: systemImage)
                .font(CiderFont.captionMedium(scale: textScale))
                .foregroundColor(isSelected ? CiderColors.controlAccent : CiderColors.tertiary)
                .frame(
                    width: WorkspaceSidebarNestedRowMetrics.iconFrame,
                    height: WorkspaceSidebarNestedRowMetrics.iconFrame
                )

            VStack(alignment: .leading, spacing: Spacing.hairline) {
                HStack(spacing: Spacing.xs) {
                    Text(title)
                        .font(CiderFont.captionMedium(scale: textScale))
                        .foregroundColor(isSelected ? CiderColors.primary : CiderColors.secondary)
                        .lineLimit(1)

                    if let badge {
                        Text(badge)
                            .font(CiderFont.micro)
                            .foregroundColor(CiderColors.tertiary)
                            .lineLimit(1)
                    }
                }

                if let subtitle {
                    Text(subtitle)
                        .font(CiderFont.caption(scale: textScale))
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, WorkspaceSidebarNestedRowMetrics.horizontalPadding)
        .padding(.vertical, WorkspaceSidebarNestedRowMetrics.verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isSelected ? CiderColors.accentSubtle : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
