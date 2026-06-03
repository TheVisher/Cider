import Foundation

enum CiderPanelViewOptionsPolicy {
    static func showsLibraryViewOptions(
        routePresentation: WorkspaceRoutePresentation?,
        selectedNavigationDomain: WorkspaceNavigationDomain?,
        hasSelectedFolder: Bool,
        hasSelectedTags: Bool,
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
        return false
    }
}
