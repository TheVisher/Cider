import Foundation

enum FeatureSettingValue: Sendable {
    case bool(Bool)
    case string(String)
    case integer(Int)
    case double(Double)
}

protocol FeatureSettings {
    static var featureName: String { get }
    static var defaults: [String: FeatureSettingValue] { get }
}

struct BookmarksFeatureSettings: FeatureSettings {
    static let featureName = "Bookmarks"

    static let defaults: [String: FeatureSettingValue] = [
        "enableBookmarksHotkey": .bool(true),
        "enableBookmarksCaptureHotkey": .bool(true),
        "autoCaptureCopiedURLs": .bool(false),
        "confirmCopiedURLBeforeSave": .bool(false),
        "bookmarksDirectory": .string("~/Documents/Cider/Bookmarks"),
        "rememberBookmarksPanelPosition": .bool(false),
        "bookmarksDefaultViewMode": .string(BookmarkDisplayMode.masonry.rawValue),
    ]
}
