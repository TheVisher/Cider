import Foundation

enum CiderPanelViewOptionsPolicy {
    static func showsLibraryViewOptions(
        hasSelectedFolder: Bool,
        hasSelectedTags: Bool,
        selectedTab: CiderTab?,
        showsLibraryRouteFeed: Bool
    ) -> Bool {
        if hasSelectedFolder || hasSelectedTags || showsLibraryRouteFeed {
            return true
        }
        if case .search = selectedTab {
            return true
        }
        return false
    }
}
