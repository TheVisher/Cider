import Foundation

// MARK: - Browser Session Tab

struct BrowserSessionTab: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var urlString: String
    var title: String?

    var url: URL? {
        URL(string: urlString)
    }
}

// MARK: - Browser Session

struct BrowserSession: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var tabs: [BrowserSessionTab]
    var sourceBrowserBundleID: String?
    var sourceBrowserName: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var tabCount: Int { tabs.count }
}
