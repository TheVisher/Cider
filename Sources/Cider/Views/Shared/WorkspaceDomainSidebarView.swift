import SwiftUI

struct WorkspaceDomainSidebarView<DomainContent: View>: View {
    @Binding var selectedDomain: WorkspaceNavigationDomain?
    @Binding var expandedDomains: Set<WorkspaceNavigationDomain>
    @Binding var searchText: String
    let domains: [WorkspaceNavigationDomain]
    let pinnedSpaces: [CiderSpace]
    let selectedSpaceID: String?
    let isSpacesManagerSelected: Bool
    let onTriggerSearch: () -> Void
    let onSelectDomain: (WorkspaceNavigationDomain) -> Void
    let onSelectSpace: (CiderSpace) -> Void
    let onOpenSpacesManager: () -> Void
    @ViewBuilder let domainContent: (WorkspaceNavigationDomain) -> DomainContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        persistentDomainList
        .animation(reduceMotion ? .none : CiderAnimation.snappy, value: selectedDomain)
        .animation(reduceMotion ? .none : CiderAnimation.snappy, value: expandedDomains)
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

                            if isExpanded(domain) {
                                domainContent(domain)
                                    .padding(.leading, WorkspaceSidebarNestedRowMetrics.childIndent)
                            }
                        }

                        if domain == .browse {
                            spacesSection
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

    private var spacesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            WorkspaceSidebarNestedSectionHeader(title: "Spaces", count: pinnedSpaces.isEmpty ? nil : pinnedSpaces.count)

            ForEach(pinnedSpaces) { space in
                Button {
                    onSelectSpace(space)
                } label: {
                    WorkspaceSidebarNestedRowLabel(
                        title: space.name,
                        systemImage: space.systemImage,
                        isSelected: selectedSpaceID == space.id
                    )
                }
                .buttonStyle(.plain)
                .help(space.purpose)
            }

            Button {
                onOpenSpacesManager()
            } label: {
                WorkspaceSidebarNestedRowLabel(
                    title: "All Spaces",
                    systemImage: "square.grid.2x2",
                    isSelected: isSpacesManagerSelected
                )
            }
            .buttonStyle(.plain)
            .help("Manage Spaces")
        }
        .padding(.leading, WorkspaceSidebarNestedRowMetrics.childIndent)
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

            Button {
                toggleAllDomains()
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(allExpandableDomainsExpanded ? CiderColors.controlAccent : CiderColors.tertiary)
                    .frame(width: Spacing.lg, height: Spacing.lg)
            }
            .buttonStyle(.plain)
            .help(allExpandableDomainsExpanded ? "Collapse all domains" : "Expand all domains")
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.separatorLight)
        )
    }

    private func domainButton(_ domain: WorkspaceNavigationDomain) -> some View {
        let isSelected = WorkspaceDomainSidebarModel.isDomainSelected(
            domain,
            selectedDomain: selectedDomain,
            selectedSpaceID: selectedSpaceID,
            isSpacesManagerSelected: isSpacesManagerSelected
        )
        let showsChildren = domain != .mainDashboard
        let isExpanded = isExpanded(domain)

        return HStack(spacing: Spacing.xs) {
            Button {
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
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsChildren {
                Button {
                    toggleDomainExpansion(domain)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.quaternary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: Spacing.xl, height: Spacing.xl)
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse \(domain.title)" : "Expand \(domain.title)")
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs + 1)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isSelected ? CiderColors.accentSubtle : CiderColors.separatorLight.opacity(0.65))
        )
        .help(domain.subtitle)
    }

    private func isExpanded(_ domain: WorkspaceNavigationDomain) -> Bool {
        WorkspaceDomainSidebarExpansionState(expandedDomains: expandedDomains).isExpanded(domain)
    }

    private var allExpandableDomainsExpanded: Bool {
        let expandableDomains = contextualDomains.filter { $0 != .mainDashboard }
        guard !expandableDomains.isEmpty else { return false }
        return expandableDomains.allSatisfy(isExpanded)
    }

    private func toggleDomainExpansion(_ domain: WorkspaceNavigationDomain) {
        var state = WorkspaceDomainSidebarExpansionState(expandedDomains: expandedDomains)
        state.toggle(domain)
        expandedDomains = state.expandedDomains
    }

    private func expandAllDomains() {
        var state = WorkspaceDomainSidebarExpansionState(expandedDomains: expandedDomains)
        state.expandAll(in: contextualDomains)
        expandedDomains = state.expandedDomains
    }

    private func collapseAllDomains() {
        var state = WorkspaceDomainSidebarExpansionState(expandedDomains: expandedDomains)
        state.collapseAll()
        expandedDomains = state.expandedDomains
    }

    private func toggleAllDomains() {
        if allExpandableDomainsExpanded {
            collapseAllDomains()
        } else {
            expandAllDomains()
        }
    }
}
