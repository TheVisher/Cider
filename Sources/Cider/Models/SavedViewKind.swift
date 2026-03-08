import Foundation

/// Discriminator for what a `SavedView` tab renders.
/// `.library` is the default (existing behavior), `.whiteboard` links to an Excalidraw canvas.
enum SavedViewKind: Codable, Hashable {
    case library
    case whiteboard(canvasID: UUID)

    // MARK: - Codable (tagged object for future extensibility)

    private enum CodingKeys: String, CodingKey {
        case type
        case canvasID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "whiteboard":
            let canvasID = try container.decode(UUID.self, forKey: .canvasID)
            self = .whiteboard(canvasID: canvasID)
        default:
            self = .library
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .library:
            try container.encode("library", forKey: .type)
        case .whiteboard(let canvasID):
            try container.encode("whiteboard", forKey: .type)
            try container.encode(canvasID, forKey: .canvasID)
        }
    }
}
