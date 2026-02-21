import SwiftUI

struct CiderTabBar: View {
    @Binding var selectedTab: CiderTab
    let tabs: [CiderTab]
    @Binding var selectedFolderID: UUID?
    @Binding var selectedSourceID: UUID?
    var onCloseTab: ((CiderTab) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var externalSourceRegistry = ExternalSourceRegistry.shared

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
        let isSelected = selectedTab == tab && selectedFolderID == nil && selectedSourceID == nil
        let count = badgeCount(for: tab)

        Button {
            withAnimation(reduceMotion ? .none : CiderAnimation.snappy) {
                selectedFolderID = nil
                selectedSourceID = nil
                selectedTab = tab
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: tab.systemImage)
                    .font(CiderFont.bodyMedium)

                Text(tab.displayName)
                    .font(isSelected ? CiderFont.labelSemibold : CiderFont.label)
                    .lineLimit(1)

                if count > 0 {
                    Text("\(count)")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(isSelected ? CiderColors.primary : CiderColors.tertiary)
                        .padding(.horizontal, CiderPanelDesign.tabBadgePadding)
                        .padding(.vertical, Spacing.hairline)
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
        case .savedView: 0
        case .search: 0
        case .externalSource(let id, _): externalSourceRegistry.files(for: id).count
        }
    }
}
