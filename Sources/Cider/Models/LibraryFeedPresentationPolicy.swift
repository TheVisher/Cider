import Foundation

enum LibraryFeedSurface: CaseIterable {
    case library
    case searchResults
    case tagDetail
}

enum LibraryFeedPresentationPolicy {
    static func showsComingUpSection(on surface: LibraryFeedSurface) -> Bool {
        switch surface {
        case .library, .searchResults, .tagDetail:
            return false
        }
    }
}
