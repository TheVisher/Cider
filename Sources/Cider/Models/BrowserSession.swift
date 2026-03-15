import Foundation

// MARK: - Browser Session Tab

struct BrowserSessionTab: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var urlString: String
    var title: String?

    var url: URL? {
        URL(string: urlString)
    }
}

// MARK: - Browser Session

struct BrowserSession: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var tabs: [BrowserSessionTab]
    var sourceBrowserBundleID: String?
    var sourceBrowserName: String?
    var folderID: UUID?
    var labelIDs: [UUID] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var tabCount: Int { tabs.count }

    init(id: UUID = UUID(), name: String, tabs: [BrowserSessionTab], sourceBrowserBundleID: String? = nil, sourceBrowserName: String? = nil, folderID: UUID? = nil, labelIDs: [UUID] = [], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.tabs = tabs
        self.sourceBrowserBundleID = sourceBrowserBundleID
        self.sourceBrowserName = sourceBrowserName
        self.folderID = folderID
        self.labelIDs = labelIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        tabs = try container.decode([BrowserSessionTab].self, forKey: .tabs)
        sourceBrowserBundleID = try container.decodeIfPresent(String.self, forKey: .sourceBrowserBundleID)
        sourceBrowserName = try container.decodeIfPresent(String.self, forKey: .sourceBrowserName)
        folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
        labelIDs = try container.decodeIfPresent([UUID].self, forKey: .labelIDs) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}
