import SwiftUI

struct DashboardTopicTabsView: View {
    let topics: [DashboardTopic]
    @Binding var selection: DashboardHubSelection
    let cardCounts: [String: Int]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                tabButton(
                    title: "Main",
                    icon: "square.grid.2x2",
                    count: nil,
                    isSelected: selection == .main
                ) {
                    selection = .main
                }

                ForEach(topics) { topic in
                    tabButton(
                        title: topic.title,
                        icon: topic.icon ?? "rectangle.stack",
                        count: cardCounts[topic.ciderSyncId],
                        isSelected: selection == .topic(topic.ciderSyncId)
                    ) {
                        selection = .topic(topic.ciderSyncId)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .background(CiderColors.surfaceSubtle)
    }

    private func tabButton(
        title: String,
        icon: String,
        count: Int?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(CiderFont.captionMedium)
                    .foregroundColor(isSelected ? CiderColors.controlAccent : CiderColors.tertiary)

                Text(title)
                    .font(CiderFont.labelMedium)
                    .foregroundColor(isSelected ? CiderColors.primary : CiderColors.secondary)
                    .lineLimit(1)

                if let count, count > 0 {
                    Text("\(count)")
                        .font(CiderFont.microSemibold)
                        .foregroundColor(isSelected ? CiderColors.controlAccent : CiderColors.quaternary)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? CiderColors.accentLight : CiderColors.surfaceInput)
                        )
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isSelected ? CiderColors.selectedFill : CiderColors.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .stroke(isSelected ? CiderColors.selectedBorder : CiderColors.borderSubtle, lineWidth: CiderBorder.innerStrokeWidth)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
