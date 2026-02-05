import Foundation

struct AppInfo: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var bundleIdentifier: String
    var path: String

    init(id: UUID = UUID(), name: String, bundleIdentifier: String, path: String) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.path = path
    }
}
