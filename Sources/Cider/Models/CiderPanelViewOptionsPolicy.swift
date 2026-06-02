import Foundation

enum CiderPanelViewOptionsPolicy {
    static func showsLibraryViewOptions(
        routePresentation: WorkspaceRoutePresentation?,
        selectedNavigationDomain: WorkspaceNavigationDomain?,
        hasSelectedFolder: Bool,
        hasSelectedTags: Bool,
        selectedTab: CiderTab?,
        showsLibraryRouteFeed: Bool
    ) -> Bool {
        if selectedNavigationDomain == .browse,
           routePresentation?.sidebarDomain == .browse,
           routePresentation?.showsLibraryViewOptions == true {
            return true
        }
        if hasSelectedFolder || hasSelectedTags || showsLibraryRouteFeed {
            return true
        }
        if case .search = selectedTab {
            return true
        }
        return false
    }
}
