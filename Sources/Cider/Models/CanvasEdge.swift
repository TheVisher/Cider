import Foundation

/// A visual connection between two nodes on the canvas.
struct CanvasEdge: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var sourceID: String
    var targetID: String
    var label: String?

    init(
        id: String = UUID().uuidString,
        sourceID: String,
        targetID: String,
        label: String? = nil
    ) {
        self.id = id
        self.sourceID = sourceID
        self.targetID = targetID
        self.label = label
    }
}
