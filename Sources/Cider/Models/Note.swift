import Foundation

struct Note: Identifiable, Hashable {
    let id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var modifiedAt: Date
    /// Relative path within the notes directory (e.g. "My Note.md")
    var relativePath: String
    var folderID: UUID?

    init(id: UUID = UUID(), title: String, content: String = "", createdAt: Date = Date(), modifiedAt: Date = Date(), relativePath: String = "", folderID: UUID? = nil) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.relativePath = relativePath
        self.folderID = folderID
    }
}
