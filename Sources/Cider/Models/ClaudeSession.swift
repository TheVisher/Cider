import Foundation

/// Status of a Claude Code session process.
enum ClaudeSessionStatus: Codable, Hashable {
    case idle
    case working
    case waitingForApproval
    case error(String)
    case stopped

    // MARK: - Codable (tagged)

    private enum CodingKeys: String, CodingKey {
        case type, message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "idle": self = .idle
        case "working": self = .working
        case "waitingForApproval": self = .waitingForApproval
        case "error":
            let message = try container.decodeIfPresent(String.self, forKey: .message) ?? "Unknown error"
            self = .error(message)
        case "stopped": self = .stopped
        default: self = .idle
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .idle:
            try container.encode("idle", forKey: .type)
        case .working:
            try container.encode("working", forKey: .type)
        case .waitingForApproval:
            try container.encode("waitingForApproval", forKey: .type)
        case .error(let message):
            try container.encode("error", forKey: .type)
            try container.encode(message, forKey: .message)
        case .stopped:
            try container.encode("stopped", forKey: .type)
        }
    }
}

/// A single message in a Claude Code session chat.
struct ClaudeSessionMessage: Identifiable, Codable, Hashable {
    let id: UUID
    var role: Role
    var content: String
    var timestamp: Date
    var toolName: String?

    enum Role: String, Codable, Hashable {
        case user
        case assistant
        case toolUse
        case toolResult
        case system
    }

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = Date(),
        toolName: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolName = toolName
    }
}

/// A Claude Code agent session managed by Cider.
struct ClaudeSession: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var projectPath: String
    var status: ClaudeSessionStatus
    var messages: [ClaudeSessionMessage]
    /// Claude Code's own session ID (returned in the `system` event).
    /// Used with `--resume` to continue multi-turn conversations.
    var claudeSessionID: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        projectPath: String,
        status: ClaudeSessionStatus = .idle,
        messages: [ClaudeSessionMessage] = [],
        claudeSessionID: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.projectPath = projectPath
        self.status = status
        self.messages = messages
        self.claudeSessionID = claudeSessionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        projectPath = try container.decode(String.self, forKey: .projectPath)
        status = try container.decodeIfPresent(ClaudeSessionStatus.self, forKey: .status) ?? .idle
        messages = try container.decodeIfPresent([ClaudeSessionMessage].self, forKey: .messages) ?? []
        claudeSessionID = try container.decodeIfPresent(String.self, forKey: .claudeSessionID)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}
