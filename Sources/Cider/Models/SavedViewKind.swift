import Foundation

/// Discriminator for what a `SavedView` tab renders.
/// `.library` is the default (existing behavior), `.whiteboard` links to an Excalidraw canvas,
/// `.kanban` links to a YAML-backed Kanban board.
enum SavedViewKind: Codable, Hashable {
    case library
    case whiteboard(canvasID: UUID)
    case kanban(boardID: String)
    case sessions

    /// SF Symbol for this tab kind.
    var systemImage: String {
        switch self {
        case .library: "square.grid.2x2"
        case .whiteboard: "scribble"
        case .kanban: "square.split.2x1"
        case .sessions: "terminal"
        }
    }

    // MARK: - Codable (tagged object for future extensibility)

    private enum CodingKeys: String, CodingKey {
        case type
        case canvasID
        case boardID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "whiteboard":
            let canvasID = try container.decode(UUID.self, forKey: .canvasID)
            self = .whiteboard(canvasID: canvasID)
        case "kanban":
            let boardID = try container.decode(String.self, forKey: .boardID)
            self = .kanban(boardID: boardID)
        case "sessions":
            self = .sessions
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
        case .kanban(let boardID):
            try container.encode("kanban", forKey: .type)
            try container.encode(boardID, forKey: .boardID)
        case .sessions:
            try container.encode("sessions", forKey: .type)
        }
    }
}
