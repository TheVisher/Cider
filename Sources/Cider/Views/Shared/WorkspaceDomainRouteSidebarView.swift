import SwiftUI

struct WorkspaceDomainRouteSidebarView: View {
    let domain: WorkspaceNavigationDomain
    let selectedRouteKind: WorkspaceDomainRouteKind
    var onSelectRoute: (WorkspaceDomainRoute, WorkspaceNavigationDomain) -> Void

    @Environment(\.textScale) private var textScale

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            ForEach(WorkspaceDomainRoutePolicy.routes(for: domain)) { route in
                routeButton(route)
            }
        }
    }

    private func routeButton(_ route: WorkspaceDomainRoute) -> some View {
        let isSelected = selectedRouteKind == route.kind

        return Button {
            onSelectRoute(route, domain)
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: route.systemImage)
                    .font(CiderFont.captionMedium(scale: textScale))
                    .foregroundColor(isSelected ? CiderColors.controlAccent : CiderColors.tertiary)
                    .frame(width: Spacing.lg, height: Spacing.lg)

                Text(route.title)
                    .font(CiderFont.captionMedium(scale: textScale))
                    .foregroundColor(isSelected ? CiderColors.primary : CiderColors.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isSelected ? CiderColors.accentSubtle : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
