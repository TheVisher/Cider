import SwiftUI

struct WorkspaceDomainRouteSidebarView: View {
    let domain: WorkspaceNavigationDomain
    let selectedRouteKind: WorkspaceDomainRouteKind?
    var onSelectRoute: (WorkspaceDomainRoute, WorkspaceNavigationDomain) -> Void

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
            WorkspaceSidebarNestedRowLabel(
                title: route.title,
                systemImage: route.systemImage,
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
    }
}
