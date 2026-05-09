import SwiftUI

struct WorkspaceDomainSidebarView<DomainContent: View>: View {
    @Binding var selectedDomain: WorkspaceNavigationDomain?
    @Binding var searchText: String
    let domains: [WorkspaceNavigationDomain]
    let onTriggerSearch: () -> Void
    let onSelectDomain: (WorkspaceNavigationDomain) -> Void
    @ViewBuilder let domainContent: () -> DomainContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        persistentDomainList
        .animation(reduceMotion ? .none : CiderAnimation.snappy, value: selectedDomain)
    }

    private var persistentDomainList: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sidebarSearchField
                .padding(.horizontal, Spacing.sm)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(contextualDomains) { domain in
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            domainButton(domain)

                            if selectedDomain == domain, domain != .mainDashboard {
                                domainContent()
                                    .padding(.leading, Spacing.lg)
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.xs)
                .padding(.bottom, Spacing.md)
            }
        }
        .frame(width: BookmarksDesign.folderSidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var contextualDomains: [WorkspaceNavigationDomain] {
        WorkspaceDomainSidebarModel.primaryDomains(selectedDomain: selectedDomain)
    }

    private var sidebarSearchField: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.tertiary)

            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(CiderFont.label)
                .foregroundColor(CiderColors.primary)
                .onSubmit(onTriggerSearch)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.tertiary)
                }
                .buttonStyle(.plain)
            } else {
                Text("\u{2318}K")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.quaternary)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.separatorLight)
        )
    }

    private func domainButton(_ domain: WorkspaceNavigationDomain) -> some View {
        let isSelected = selectedDomain == domain
            || (domain == .mainDashboard && selectedDomain == nil)
        let showsChildren = domain != .mainDashboard

        return Button {
            onSelectDomain(domain)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: domain.systemImage)
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(isSelected ? CiderColors.controlAccent : CiderColors.secondary)
                    .frame(width: Spacing.xl, height: Spacing.xl)

                Text(domain.title)
                    .font(CiderFont.labelSemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if showsChildren {
                    Image(systemName: "chevron.right")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.quaternary)
                        .rotationEffect(.degrees(isSelected ? 90 : 0))
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs + 1)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isSelected ? CiderColors.accentSubtle : CiderColors.separatorLight.opacity(0.65))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(domain.subtitle)
    }
}
