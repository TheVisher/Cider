import Foundation

/// A positioned item on the native canvas.
struct CanvasNode: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var itemID: String?
    var itemType: String // "bookmark", "note", "todo", "folderGroup"
    var position: CGPoint
    var size: CGSize
    var parentNodeID: String?
    var layoutMode: String? // "grid", "list", "masonry"
    var collapsed: Bool

    init(
        id: String = UUID().uuidString,
        itemID: String? = nil,
        itemType: String,
        position: CGPoint,
        size: CGSize = CGSize(width: 280, height: 260),
        parentNodeID: String? = nil,
        layoutMode: String? = nil,
        collapsed: Bool = false
    ) {
        self.id = id
        self.itemID = itemID
        self.itemType = itemType
        self.position = position
        self.size = size
        self.parentNodeID = parentNodeID
        self.layoutMode = layoutMode
        self.collapsed = collapsed
    }
}
