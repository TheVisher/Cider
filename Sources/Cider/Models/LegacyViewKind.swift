import Foundation

/// Discriminator for what a `LegacyView` tab renders.
/// `.library` is the default (existing behavior),
/// `.kanban` links to a YAML-backed Kanban board.
enum LegacyViewKind: Codable, Hashable {
    case dashboard
    case library
    case kanban(boardID: String)

    /// SF Symbol for this tab kind.
    var systemImage: String {
        switch self {
        case .dashboard: "gauge.medium"
        case .library: "square.grid.2x2"
        case .kanban: "square.split.2x1"
        }
    }

    // MARK: - Codable (tagged object for future extensibility)

    private enum CodingKeys: String, CodingKey {
        case type
        case boardID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "dashboard":
            self = .dashboard
        case "kanban":
            let boardID = try container.decode(String.self, forKey: .boardID)
            self = .kanban(boardID: boardID)
        default:
            self = .library
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .dashboard:
            try container.encode("dashboard", forKey: .type)
        case .library:
            try container.encode("library", forKey: .type)
        case .kanban(let boardID):
            try container.encode("kanban", forKey: .type)
            try container.encode(boardID, forKey: .boardID)
        }
    }
}
