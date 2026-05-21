import Foundation

enum LibraryFeedSurface: CaseIterable {
    case savedView
    case searchResults
    case tagDetail
}

enum LibraryFeedPresentationPolicy {
    static func showsComingUpSection(on surface: LibraryFeedSurface) -> Bool {
        switch surface {
        case .savedView, .searchResults, .tagDetail:
            return false
        }
    }
}
