import SwiftUI

struct WorkspaceDomainSidebarView<DomainContent: View>: View {
    @Binding var selectedDomain: WorkspaceNavigationDomain?
    @Binding var searchText: String
    let domains: [WorkspaceNavigationDomain]
    let selectedAnchor: WorkspaceSidebarAnchor?
    let selectedDomainRowIsCurrent: Bool
    let onTriggerSearch: () -> Void
    let onSelectDomain: (WorkspaceNavigationDomain) -> Void
    @ViewBuilder let domainContent: () -> DomainContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let selectedDomain {
                domainSidebar(for: selectedDomain)
            } else {
                globalDomainList
            }
        }
        .animation(reduceMotion ? .none : CiderAnimation.snappy, value: selectedDomain)
    }

    private var globalDomainList: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sidebarSearchField
                .padding(.horizontal, Spacing.sm)

            persistentAnchors
                .padding(.horizontal, Spacing.xs)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Domains")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.top, Spacing.sm)

                    ForEach(contextualDomains) { domain in
                        domainButton(domain)
                    }
                }
                .padding(.horizontal, Spacing.xs)
                .padding(.bottom, Spacing.md)
            }
        }
        .frame(width: BookmarksDesign.folderSidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func domainSidebar(for domain: WorkspaceNavigationDomain) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sidebarSearchField
                .padding(.horizontal, Spacing.sm)

            persistentAnchors
                .padding(.horizontal, Spacing.xs)

            if showsCurrentDomainRow(for: domain) {
                currentDomainButton(domain)
                    .padding(.horizontal, Spacing.xs)
            }

            domainContent()
        }
        .frame(width: BookmarksDesign.folderSidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func showsCurrentDomainRow(for domain: WorkspaceNavigationDomain) -> Bool {
        switch domain {
        case .media, .bookmarks, .notes, .projects, .tasksEvents, .files, .people, .aiAssistant:
            true
        case .mainDashboard, .browse:
            false
        }
    }

    private var contextualDomains: [WorkspaceNavigationDomain] {
        domains.filter { domain in
            domain != .mainDashboard && domain != .browse
        }
    }

    private var persistentAnchors: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            ForEach(WorkspaceSidebarAnchor.allCases) { anchor in
                anchorButton(anchor)
            }
        }
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

    private func anchorButton(_ anchor: WorkspaceSidebarAnchor) -> some View {
        let isSelected = selectedAnchor == anchor

        return Button {
            onSelectDomain(anchor.domain)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: anchor.systemImage)
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(isSelected ? CiderColors.controlAccent : CiderColors.secondary)
                    .frame(width: Spacing.xl, height: Spacing.xl)

                Text(anchor.title)
                    .font(CiderFont.labelSemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
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
        .help(anchor.subtitle)
    }

    private func domainButton(_ domain: WorkspaceNavigationDomain) -> some View {
        Button {
            if domain.opensDomainSidebar {
                selectedDomain = domain
            }
            onSelectDomain(domain)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: domain.systemImage)
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.secondary)
                    .frame(width: Spacing.xl, height: Spacing.xl)

                Text(domain.title)
                    .font(CiderFont.labelSemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.quaternary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs + 1)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.separatorLight.opacity(0.65))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(domain.subtitle)
    }

    private func currentDomainButton(_ domain: WorkspaceNavigationDomain) -> some View {
        Button {
            onSelectDomain(domain)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: domain.systemImage)
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(selectedDomainRowIsCurrent ? CiderColors.controlAccent : CiderColors.secondary)
                    .frame(width: Spacing.xl, height: Spacing.xl)

                Text(domain.title)
                    .font(CiderFont.labelSemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs + 1)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(selectedDomainRowIsCurrent ? CiderColors.accentSubtle : CiderColors.separatorLight.opacity(0.65))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(domain.subtitle)
    }
}
