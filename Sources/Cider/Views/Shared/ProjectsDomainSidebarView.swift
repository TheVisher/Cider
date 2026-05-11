import SwiftUI

struct ProjectsDomainSidebarView: View {
    let catalog: ProjectWorkspaceCatalog
    let boards: [KanbanBoard]
    @Binding var selectedWorkspaceID: String?
    let selectedTab: CiderTab?
    var onSelectWorkspace: (ProjectWorkspace) -> Void
    var onSelectDestination: (ProjectWorkspaceSidebarDestination, ProjectWorkspace) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(ProjectWorkspaceSidebarModel.sections(for: catalog)) { section in
                    sectionView(section)
                }
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.bottom, Spacing.md)
        }
    }

    @ViewBuilder
    private func sectionView(_ section: ProjectWorkspaceSidebarSection) -> some View {
        let entries = section.entries.filter { $0.kind != .home }
        if entries.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                WorkspaceSidebarNestedSectionHeader(title: section.title)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    ForEach(entries) { workspace in
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            workspaceButton(workspace)

                            if workspace.kind == .project && selectedWorkspaceID == workspace.id {
                                projectDestinationTree(for: workspace)
                                    .padding(.leading, WorkspaceSidebarNestedRowMetrics.childIndent)
                            }
                        }
                    }
                }
            }
        }
    }

    private func workspaceButton(_ workspace: ProjectWorkspace) -> some View {
        let isSelected = selectedWorkspaceID == workspace.id || (selectedWorkspaceID == nil && workspace.kind == .home)

        return Button {
            selectedWorkspaceID = workspace.kind == .home ? nil : workspace.id
            onSelectWorkspace(workspace)
        } label: {
            WorkspaceSidebarNestedRowLabel(
                title: workspace.title,
                systemImage: workspace.systemImage,
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        .help(workspace.subtitle)
    }

    private func projectDestinationTree(for workspace: ProjectWorkspace) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            ForEach(ProjectWorkspaceSidebarTree.destinations(for: workspace, boards: boards)) { destination in
                projectDestinationButton(destination, workspace: workspace)
            }
        }
    }

    private func projectDestinationButton(
        _ destination: ProjectWorkspaceSidebarDestination,
        workspace: ProjectWorkspace
    ) -> some View {
        let isSelected = selectedDestinationKind == destination.kind

        return Button {
            guard destination.isSelectable else { return }
            onSelectDestination(destination, workspace)
        } label: {
            WorkspaceSidebarNestedRowLabel(
                title: destination.title,
                systemImage: destination.systemImage,
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        .disabled(!destination.isSelectable)
    }

    private var selectedDestinationKind: ProjectWorkspaceSidebarDestinationKind? {
        guard let selectedTab else { return nil }
        switch selectedTab {
        case .projectOverview:
            return .overview
        case .projectReferences:
            return .references
        case .savedView:
            return selectedBoardID.map { .board($0) }
        case .search, .tag, .domainDashboard, .spaceOverview, .spacesManager, .aiAssistant:
            return nil
        }
    }

    private var selectedBoardID: String? {
        guard case .savedView(let id, _) = selectedTab,
              let savedView = SavedViewStorage.shared.savedView(for: id),
              case .kanban(let boardID) = savedView.kind else {
            return nil
        }
        return boardID
    }
}
