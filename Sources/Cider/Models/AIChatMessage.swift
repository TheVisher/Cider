import Foundation

struct AIChatMessage: Identifiable, Codable {
    let id: UUID
    let role: Role
    var content: String
    let timestamp: Date
    var isStreaming: Bool
    /// When true, the bubble shows a thinking indicator instead of raw content while streaming.
    var hideWhileStreaming: Bool

    enum Role: String, Codable {
        case user
        case assistant
        case system
    }

    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp, isStreaming
    }

    init(id: UUID = UUID(), role: Role, content: String, timestamp: Date = Date(), isStreaming: Bool = false, hideWhileStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.hideWhileStreaming = hideWhileStreaming
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        isStreaming = try container.decodeIfPresent(Bool.self, forKey: .isStreaming) ?? false
        hideWhileStreaming = false
    }
}
