import SwiftUI

struct ProjectWorkspaceLocalTabStrip: View {
    let tabs: [ProjectWorkspaceLocalTab]
    var onSelect: (ProjectWorkspaceLocalTabKind) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xxs) {
                ForEach(tabs) { tab in
                    tabButton(tab)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tabButton(_ tab: ProjectWorkspaceLocalTab) -> some View {
        Button {
            onSelect(tab.kind)
        } label: {
            HStack(spacing: Spacing.xxs) {
                Image(systemName: tab.systemImage)
                    .font(CiderFont.caption)

                Text(tab.title)
                    .font(CiderFont.captionMedium)
                    .lineLimit(1)

                if let badge = tab.badge {
                    Text(badge)
                        .font(CiderFont.micro)
                        .foregroundColor(tab.isSelected ? CiderColors.controlAccent : CiderColors.tertiary)
                        .padding(.horizontal, Spacing.xxs)
                        .padding(.vertical, 1)
                        .background(
                            Capsule(style: .continuous)
                                .fill(tab.isSelected ? CiderColors.controlAccent.opacity(0.16) : CiderColors.surfaceElevated)
                        )
                }
            }
            .foregroundColor(tab.isSelected ? CiderColors.controlAccent : CiderColors.secondary)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(
                Capsule(style: .continuous)
                    .fill(tab.isSelected ? CiderColors.controlAccent.opacity(0.13) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help(tab.title)
    }
}
