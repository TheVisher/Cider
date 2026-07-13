import Foundation

enum ConversationAgentProfileValidationError: Error, Equatable, LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        }
    }
}

struct ConversationAgentCapability: Codable, Equatable, Hashable, Sendable {
    let id: String
    let displayName: String
}

struct ConversationAgentRuntimeBinding: Codable, Equatable, Hashable, Sendable {
    let providerID: String
    let runtimeID: String
}

enum ConversationAgentAvailability: Codable, Equatable, Hashable, Sendable {
    case available
    case unavailable(reason: String)

    var reason: String? {
        switch self {
        case .available: nil
        case .unavailable(let reason): reason
        }
    }

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

struct ConversationAgentProfile: Codable, Equatable, Hashable, Sendable {
    static let maximumIdentifierLength = 64
    static let maximumDisplayNameLength = 80
    static let maximumAvailabilityReasonLength = 240
    static let maximumCapabilityCount = 32

    let id: String
    let displayName: String
    let runtimeBinding: ConversationAgentRuntimeBinding
    let capabilities: [ConversationAgentCapability]
    let availability: ConversationAgentAvailability

    private init(
        id: String,
        displayName: String,
        runtimeBinding: ConversationAgentRuntimeBinding,
        capabilities: [ConversationAgentCapability],
        availability: ConversationAgentAvailability
    ) {
        self.id = id
        self.displayName = displayName
        self.runtimeBinding = runtimeBinding
        self.capabilities = capabilities
        self.availability = availability
    }

    static func validated(
        id: String,
        displayName: String,
        runtimeBinding: ConversationAgentRuntimeBinding,
        capabilities: [ConversationAgentCapability],
        availability: ConversationAgentAvailability
    ) throws -> ConversationAgentProfile {
        let profile = ConversationAgentProfile(
            id: id,
            displayName: displayName,
            runtimeBinding: runtimeBinding,
            capabilities: capabilities,
            availability: availability
        )
        try validate(profile)
        return profile
    }

    static func validate(_ profile: ConversationAgentProfile) throws {
        try validateIdentifier(profile.id, field: "profile id")
        try validateDisplayText(
            profile.displayName,
            maximumLength: maximumDisplayNameLength,
            field: "profile display name"
        )
        try validateIdentifier(profile.runtimeBinding.providerID, field: "provider id")
        try validateIdentifier(profile.runtimeBinding.runtimeID, field: "runtime id")
        guard !profile.capabilities.isEmpty,
              profile.capabilities.count <= maximumCapabilityCount
        else {
            throw ConversationAgentProfileValidationError.invalid(
                "Agent profiles must declare between 1 and \(maximumCapabilityCount) capabilities."
            )
        }
        var capabilityIDs = Set<String>()
        for capability in profile.capabilities {
            try validateIdentifier(capability.id, field: "capability id")
            try validateDisplayText(
                capability.displayName,
                maximumLength: maximumDisplayNameLength,
                field: "capability display name"
            )
            guard capabilityIDs.insert(capability.id).inserted else {
                throw ConversationAgentProfileValidationError.invalid(
                    "Agent capability ids must be unique within a profile."
                )
            }
        }
        switch profile.availability {
        case .available:
            break
        case .unavailable(let reason):
            try validateDisplayText(
                reason,
                maximumLength: maximumAvailabilityReasonLength,
                field: "availability reason"
            )
        }
    }

    private static func validateIdentifier(_ value: String, field: String) throws {
        guard !value.isEmpty,
              value.count <= maximumIdentifierLength,
              value.unicodeScalars.allSatisfy({ scalar in
                  CharacterSet.alphanumerics.contains(scalar)
                      || scalar == "-" || scalar == "_" || scalar == "."
              })
        else {
            throw ConversationAgentProfileValidationError.invalid(
                "Agent \(field) must be 1–\(maximumIdentifierLength) letters, numbers, dots, dashes, or underscores."
            )
        }
    }

    private static func validateDisplayText(
        _ value: String,
        maximumLength: Int,
        field: String
    ) throws {
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.count <= maximumLength,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw ConversationAgentProfileValidationError.invalid(
                "Agent \(field) must be nonempty, trimmed, control-free, and at most \(maximumLength) characters."
            )
        }
    }
}

struct ConversationRoomAgentAssignment: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let profile: ConversationAgentProfile
    let assignedAt: Date

    init(
        profile: ConversationAgentProfile,
        assignedAt: Date,
        schemaVersion: Int = ConversationRoomAgentAssignment.schemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.profile = profile
        self.assignedAt = assignedAt
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else {
            throw ConversationAgentProfileValidationError.invalid(
                "The room agent assignment uses an unsupported schema version."
            )
        }
        try ConversationAgentProfile.validate(profile)
    }
}

struct ConversationAgentProfileCatalog: Equatable, Sendable {
    static let maximumProfileCount = 64

    let profiles: [ConversationAgentProfile]
    let defaultProfileID: String

    init(profiles: [ConversationAgentProfile], defaultProfileID: String) throws {
        guard !profiles.isEmpty, profiles.count <= Self.maximumProfileCount else {
            throw ConversationAgentProfileValidationError.invalid(
                "Agent catalogs must contain between 1 and \(Self.maximumProfileCount) profiles."
            )
        }
        var ids = Set<String>()
        for profile in profiles {
            try ConversationAgentProfile.validate(profile)
            guard ids.insert(profile.id).inserted else {
                throw ConversationAgentProfileValidationError.invalid("Agent profile ids must be unique.")
            }
        }
        guard ids.contains(defaultProfileID) else {
            throw ConversationAgentProfileValidationError.invalid(
                "The default agent profile must exist in the catalog."
            )
        }
        self.profiles = profiles
        self.defaultProfileID = defaultProfileID
    }

    var defaultProfile: ConversationAgentProfile {
        profiles.first(where: { $0.id == defaultProfileID })!
    }

    func profile(id: String) -> ConversationAgentProfile? {
        profiles.first(where: { $0.id == id })
    }
}

enum AgentRoomsProductionAgentProfiles {
    static let catalog: ConversationAgentProfileCatalog = {
        let capabilities = [
            ConversationAgentCapability(id: "text-chat", displayName: "Text chat"),
            ConversationAgentCapability(id: "streaming", displayName: "Streaming"),
            ConversationAgentCapability(id: "cancel", displayName: "Cancel"),
            ConversationAgentCapability(id: "retry", displayName: "Retry"),
            ConversationAgentCapability(id: "file-attachments", displayName: "File attachments"),
        ]
        let hermes = try! ConversationAgentProfile.validated(
            id: "hermes",
            displayName: "Hermes",
            runtimeBinding: .init(providerID: "hermes", runtimeID: "hermes"),
            capabilities: capabilities,
            availability: .available
        )
        let codex = try! ConversationAgentProfile.validated(
            id: "codex",
            displayName: "Codex",
            runtimeBinding: .init(providerID: "openai", runtimeID: "codex"),
            capabilities: capabilities,
            availability: .unavailable(reason: "Codex is not connected to native Cider Rooms yet.")
        )
        return try! ConversationAgentProfileCatalog(
            profiles: [hermes, codex],
            defaultProfileID: hermes.id
        )
    }()
}
