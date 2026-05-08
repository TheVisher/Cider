import SwiftUI

struct ProjectsDomainSidebarView: View {
    let catalog: ProjectWorkspaceCatalog
    @Binding var selectedWorkspaceID: String?
    var onSelectWorkspace: (ProjectWorkspace) -> Void

    @Environment(\.textScale) private var textScale

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

    private func sectionView(_ section: ProjectWorkspaceSidebarSection) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(section.title)
                .font(CiderFont.captionSemibold(scale: textScale))
                .foregroundColor(CiderColors.tertiary)
                .padding(.horizontal, Spacing.sm)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                ForEach(section.entries) { workspace in
                    workspaceButton(workspace)
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
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: workspace.systemImage)
                    .font(CiderFont.bodyMedium(scale: textScale))
                    .foregroundColor(isSelected ? CiderColors.controlAccent : CiderColors.secondary)
                    .frame(width: Spacing.xl, height: Spacing.xl)

                VStack(alignment: .leading, spacing: Spacing.hairline) {
                    Text(workspace.title)
                        .font(CiderFont.labelSemibold(scale: textScale))
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)
                    Text(workspace.subtitle)
                        .font(CiderFont.caption(scale: textScale))
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isSelected ? CiderColors.accentSubtle : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(workspace.subtitle)
    }
}
