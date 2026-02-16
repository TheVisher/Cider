import SwiftUI

struct CiderTabBar: View {
    @Binding var selectedTab: CiderTab
    let tabs: [CiderTab]
    let bookmarkCount: Int
    let noteCount: Int
    var onCloseTab: ((CiderTab) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CiderPanelDesign.tabSpacing) {
                ForEach(tabs) { tab in
                    tabButton(for: tab)
                }
            }
            .padding(.horizontal, CiderPanelDesign.tabHorizontalPadding)
        }
        .frame(height: CiderPanelDesign.tabBarHeight)
    }

    @ViewBuilder
    private func tabButton(for tab: CiderTab) -> some View {
        let isSelected = selectedTab == tab
        let count = badgeCount(for: tab)

        Button {
            withAnimation(reduceMotion ? .none : CiderAnimation.snappy) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: tab.systemImage)
                    .font(CiderFont.bodyMedium)

                Text(tab.displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)

                if count > 0 {
                    Text("\(count)")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(isSelected ? CiderColors.primary : CiderColors.tertiary)
                        .padding(.horizontal, CiderPanelDesign.tabBadgePadding)
                        .padding(.vertical, 1)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? CiderColors.separatorFirm : CiderColors.separatorLight)
                        )
                }

                if tab.isCloseable {
                    Button {
                        onCloseTab?(tab)
                    } label: {
                        Image(systemName: "xmark")
                            .font(CiderFont.badge)
                            .foregroundColor(CiderColors.tertiary)
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundColor(isSelected ? CiderColors.primary : CiderColors.secondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isSelected ? CiderColors.separatorMedium : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func badgeCount(for tab: CiderTab) -> Int {
        switch tab {
        case .home: 0
        case .bookmarks: bookmarkCount
        case .notes: noteCount
        case .search: 0
        case .project(let id, _): ProjectStorage.shared.itemCount(for: id)
        }
    }
}
