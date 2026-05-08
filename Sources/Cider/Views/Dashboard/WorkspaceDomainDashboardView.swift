import SwiftUI

struct WorkspaceDomainDashboardView: View {
    let model: WorkspaceDomainDashboardModel
    let onOpenTab: (CiderTab) -> Void
    let onBrowseAll: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header

                if let primaryAction = model.primaryAction {
                    Button {
                        open(primaryAction.target)
                    } label: {
                        Label(primaryAction.title, systemImage: primaryAction.systemImage)
                    }
                    .buttonStyle(CiderAccentButtonStyle())
                }

                if model.sections.isEmpty {
                    emptyState
                } else {
                    ForEach(model.sections) { section in
                        sectionView(section)
                    }
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(CiderColors.opaqueBackground)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Image(systemName: model.systemImage)
                .font(CiderFont.emptyStateIcon)
                .foregroundColor(CiderColors.controlAccent)
                .frame(width: 54, height: 54)
                .background(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(CiderColors.controlAccent.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(model.title)
                    .font(CiderFont.displayBold)
                    .foregroundColor(CiderColors.primary)
                Text(model.subtitle)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.secondary)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label(model.emptyStateTitle, systemImage: "tray")
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.secondary)
            Text(model.emptyStateSubtitle)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(CiderColors.surfaceElevated)
        )
    }

    private func sectionView(_ section: WorkspaceDomainDashboardSection) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(section.title)
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.primary)

            if let subtitle = section.subtitle {
                Text(subtitle)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: Spacing.sm)], spacing: Spacing.sm) {
                ForEach(section.items) { item in
                    Button {
                        open(item.target)
                    } label: {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Image(systemName: item.systemImage)
                                .font(CiderFont.bodySemibold)
                                .foregroundColor(CiderColors.controlAccent)
                            Text(item.title)
                                .font(CiderFont.labelSemibold)
                                .foregroundColor(CiderColors.primary)
                                .lineLimit(2)
                            if let subtitle = item.subtitle {
                                Text(subtitle)
                                    .font(CiderFont.caption)
                                    .foregroundColor(CiderColors.tertiary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(Spacing.md)
                        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(CiderColors.surfaceElevated)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(item.target == nil)
                }
            }
        }
    }

    private func open(_ target: CiderTab?) {
        if let target {
            onOpenTab(target)
        } else {
            onBrowseAll()
        }
    }
}
