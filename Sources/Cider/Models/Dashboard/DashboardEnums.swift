import Foundation

enum DashboardCardSourceKind: Hashable, Codable, Sendable {
    case url
    case bookmark
    case note
    case todo
    case event
    case project
    case board
    case repo
    case manual
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "url": self = .url
        case "bookmark": self = .bookmark
        case "note": self = .note
        case "todo": self = .todo
        case "event": self = .event
        case "project": self = .project
        case "board": self = .board
        case "repo": self = .repo
        case "manual": self = .manual
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .url: "url"
        case .bookmark: "bookmark"
        case .note: "note"
        case .todo: "todo"
        case .event: "event"
        case .project: "project"
        case .board: "board"
        case .repo: "repo"
        case .manual: "manual"
        case .unknown(let rawValue): rawValue
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum DashboardCardStatus: Hashable, Codable, Sendable {
    case new
    case seen
    case saved
    case dismissed
    case reminded
    case archived
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "new": self = .new
        case "seen": self = .seen
        case "saved": self = .saved
        case "dismissed": self = .dismissed
        case "reminded": self = .reminded
        case "archived": self = .archived
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .new: "new"
        case .seen: "seen"
        case .saved: "saved"
        case .dismissed: "dismissed"
        case .reminded: "reminded"
        case .archived: "archived"
        case .unknown(let rawValue): rawValue
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum DashboardCardPriority: Hashable, Codable, Sendable {
    case low
    case normal
    case high
    case urgent
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "low": self = .low
        case "normal": self = .normal
        case "high": self = .high
        case "urgent": self = .urgent
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .low: "low"
        case .normal: "normal"
        case .high: "high"
        case .urgent: "urgent"
        case .unknown(let rawValue): rawValue
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum DashboardRunSource: Hashable, Codable, Sendable {
    case manual
    case agent
    case cron
    case `import`
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "manual": self = .manual
        case "agent": self = .agent
        case "cron": self = .cron
        case "import": self = .import
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .manual: "manual"
        case .agent: "agent"
        case .cron: "cron"
        case .import: "import"
        case .unknown(let rawValue): rawValue
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum DashboardRunStatus: Hashable, Codable, Sendable {
    case running
    case completed
    case failed
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "running": self = .running
        case "completed": self = .completed
        case "failed": self = .failed
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .running: "running"
        case .completed: "completed"
        case .failed: "failed"
        case .unknown(let rawValue): rawValue
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum DashboardModelIdentity {
    static func ciderSyncId(_ ciderSyncId: String?, defaultingTo id: UUID) -> String {
        guard let ciderSyncId, !ciderSyncId.isEmpty else {
            return id.uuidString.lowercased()
        }
        return ciderSyncId.lowercased()
    }

    static func localID(from ciderSyncId: String) -> UUID {
        UUID(uuidString: ciderSyncId) ?? UUID()
    }
}
