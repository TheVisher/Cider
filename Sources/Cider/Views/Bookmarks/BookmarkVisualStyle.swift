import AppKit
import SwiftUI

enum BookmarkVisualStyle {
    private static let gradientPairs: [(NSColor, NSColor)] = [
        (.systemBlue, .systemTeal),
        (.systemOrange, .systemYellow),
        (.systemPink, .systemRed),
        (.systemIndigo, .systemBlue),
        (.systemMint, .systemGreen),
        (.systemCyan, .systemBlue)
    ]

    static func gradient(for bookmark: Bookmark) -> (Color, Color) {
        let hashValue = abs(bookmark.urlString.hashValue)
        let index = hashValue % gradientPairs.count
        let pair = gradientPairs[index]
        return (Color(pair.0), Color(pair.1))
    }
}
