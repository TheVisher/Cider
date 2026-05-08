import SwiftUI

struct WorkspaceDomainDashboardView: View {
    let model: WorkspaceDomainDashboardModel
    let onOpenTab: (CiderTab) -> Void
    let onBrowseAll: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = min(max(0, proxy.size.width - (Spacing.md * 2)), HomeOverviewDesign.maxContentWidth)

            ScrollView {
                VStack(alignment: .leading, spacing: HomeOverviewDesign.rowSpacing) {
                    overviewPanel

                    if model.sections.isEmpty {
                        emptyStatePanel
                    } else {
                        ForEach(model.sections) { section in
                            sectionPanel(section)
                        }
                    }
                }
                .frame(maxWidth: contentWidth, alignment: .leading)
                .padding(.horizontal, Spacing.md)
                .padding(.top, HomeOverviewDesign.telemetryTopPadding)
                .padding(.bottom, Spacing.md)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var overviewPanel: some View {
        HomeOverviewPanel(title: "\(model.title) Dashboard") {
            Text(model.title)
                .font(CiderFont.displayBold)
                .foregroundColor(CiderColors.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(model.subtitle)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .background(CiderColors.separator)
                .padding(.top, Spacing.xs)

            Text("FOCUS")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)
                .tracking(1.4)

            HStack(alignment: .center, spacing: Spacing.sm) {
                Image(systemName: model.systemImage)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.controlAccent)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(model.sections.isEmpty ? model.emptyStateTitle : "Open a domain view")
                        .font(CiderFont.labelSemibold)
                        .foregroundColor(CiderColors.primary)
                    Text(model.sections.isEmpty ? model.emptyStateSubtitle : "Use a card below to jump into the matching saved view or tab.")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(2)
                }

                Spacer(minLength: Spacing.sm)

                if let primaryAction = model.primaryAction {
                    Button {
                        open(primaryAction.target)
                    } label: {
                        Label(primaryAction.title, systemImage: primaryAction.systemImage)
                            .font(CiderFont.captionSemibold)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(CiderColors.controlAccent)
                }
            }
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(CiderColors.surfaceInput)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .stroke(CiderColors.borderSubtle, lineWidth: 1)
                    )
            )
        }
    }

    private var emptyStatePanel: some View {
        HomeOverviewPanel(title: "Domain Items") {
            Text(model.emptyStateTitle)
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.primary)
            Text(model.emptyStateSubtitle)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionPanel(_ section: WorkspaceDomainDashboardSection) -> some View {
        HomeOverviewPanel(title: section.title) {
            if let subtitle = section.subtitle {
                Text(subtitle)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: Spacing.sm)], spacing: Spacing.sm) {
                ForEach(section.items) { item in
                    if item.target != nil {
                        Button {
                            open(item.target)
                        } label: {
                            dashboardItemCard(item)
                        }
                        .buttonStyle(.plain)
                    } else {
                        dashboardItemCard(item)
                    }
                }
            }
        }
    }

    private func dashboardItemCard(_ item: WorkspaceDomainDashboardItem) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: item.systemImage)
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.controlAccent)
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(item.title)
                    .font(CiderFont.labelSemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(CiderColors.surfaceInput)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(CiderColors.borderSubtle, lineWidth: 1)
                )
        )
    }

    private func open(_ target: CiderTab?) {
        if let target {
            onOpenTab(target)
        } else {
            onBrowseAll()
        }
    }
}
