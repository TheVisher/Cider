import Foundation

enum LibraryInboxPresentationPolicy {
    static let maxVisibleItems = 60
    static let preferredDisplayMode: LibraryDisplayMode = .list

    static func visibleItems(_ items: [LibraryItemV2]) -> [LibraryItemV2] {
        Array(items.prefix(maxVisibleItems))
    }
}
