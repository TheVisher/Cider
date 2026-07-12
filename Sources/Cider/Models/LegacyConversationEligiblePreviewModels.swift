import Foundation

enum LegacyConversationEligiblePreviewState: String, Codable, Equatable, Sendable {
    case empty
    case ready
    case eligibleEmpty
    case blocked
    case failed
}

enum LegacyCandidateConflictKind: Codable, CaseIterable, Equatable, Sendable {
    case messageRecordIdentity
    case messageProvenanceIdentity
    case runtimeBindingIdentity
    case historicalTurnProvenanceIdentity

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case "messageRecordIdentity": self = .messageRecordIdentity
        case "messageProvenanceIdentity": self = .messageProvenanceIdentity
        case "runtimeBindingIdentity": self = .runtimeBindingIdentity
        case "historicalTurnProvenanceIdentity": self = .historicalTurnProvenanceIdentity
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported legacy candidate conflict category."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .messageRecordIdentity: try container.encode("messageRecordIdentity")
        case .messageProvenanceIdentity: try container.encode("messageProvenanceIdentity")
        case .runtimeBindingIdentity: try container.encode("runtimeBindingIdentity")
        case .historicalTurnProvenanceIdentity: try container.encode("historicalTurnProvenanceIdentity")
        }
    }
}

enum LegacyBoundedCount: Codable, Equatable, Sendable {
    case exact(UInt8)
    case atLeast100

    private enum CodingKeys: String, CodingKey {
        case exact
        case atLeast100
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let keys = container.allKeys
        guard keys.count == 1, let key = keys.first else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Expected exactly one bounded count representation."
            ))
        }
        switch key {
        case .exact:
            let value = try container.decode(UInt8.self, forKey: .exact)
            guard value <= 99 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .exact,
                    in: container,
                    debugDescription: "Exact bounded counts must be between zero and 99."
                )
            }
            self = .exact(value)
        case .atLeast100:
            guard try container.decode(Bool.self, forKey: .atLeast100) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .atLeast100,
                    in: container,
                    debugDescription: "The saturated count marker must be true."
                )
            }
            self = .atLeast100
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .exact(let value):
            guard value <= 99 else {
                throw EncodingError.invalidValue(value, .init(
                    codingPath: encoder.codingPath,
                    debugDescription: "Exact bounded counts must be between zero and 99."
                ))
            }
            try container.encode(value, forKey: .exact)
        case .atLeast100:
            try container.encode(true, forKey: .atLeast100)
        }
    }

    var isValid: Bool {
        switch self {
        case .exact(let value): value <= 99
        case .atLeast100: true
        }
    }

    var isZero: Bool { self == .exact(0) }

    var isAtLeastTwo: Bool {
        switch self {
        case .exact(let value): value >= 2 && value <= 99
        case .atLeast100: true
        }
    }

    var displayValue: String {
        switch self {
        case .exact(let value): String(value)
        case .atLeast100: "99+"
        }
    }
}

struct LegacyCandidateConflictCount: Codable, Equatable, Sendable {
    let kind: LegacyCandidateConflictKind
    let conflictingIdentityGroups: LegacyBoundedCount
}

struct LegacyCandidateConflictDiagnosis: Codable, Equatable, Sendable {
    static let currentFormatVersion = "cider.legacy-candidate-conflict-diagnosis.v1"

    let formatVersion: String
    let affectedCandidateCount: LegacyBoundedCount
    let counts: [LegacyCandidateConflictCount]

    init(
        affectedCandidateCount: LegacyBoundedCount,
        counts: [LegacyCandidateConflictCount]
    ) {
        formatVersion = Self.currentFormatVersion
        self.affectedCandidateCount = affectedCandidateCount
        self.counts = counts
    }

    var isValid: Bool {
        formatVersion == Self.currentFormatVersion &&
            affectedCandidateCount.isAtLeastTwo &&
            counts.count == LegacyCandidateConflictKind.allCases.count &&
            counts.map(\.kind) == LegacyCandidateConflictKind.allCases &&
            counts.allSatisfy(\.conflictingIdentityGroups.isValid) &&
            counts.contains { !$0.conflictingIdentityGroups.isZero }
    }
}

struct LegacyConversationEligibleCounts: Codable, Equatable, Sendable {
    var registeredActiveTotal: Int
    var eligibleTotal: Int
    var roomLocalOmitted: Int
    var displayedTotal: Int
    var eligibleCapOmitted: Int
    var unregisteredFileTotal: Int

    static let zero = Self(
        registeredActiveTotal: 0,
        eligibleTotal: 0,
        roomLocalOmitted: 0,
        displayedTotal: 0,
        eligibleCapOmitted: 0,
        unregisteredFileTotal: 0
    )

    var isExact: Bool {
        registeredActiveTotal == eligibleTotal + roomLocalOmitted &&
            displayedTotal == min(eligibleTotal, 20) &&
            eligibleCapOmitted == eligibleTotal - displayedTotal
    }
}

struct LegacyConversationEligibleRoom: Codable, Equatable, Sendable {
    var plan: LegacyConversationImportPlan
    var totalMessages: Int
    var messageCapOmitted: Int
}

struct LegacyConversationEligiblePreview: Codable, Equatable, Sendable {
    static let currentFormatVersion = "cider.legacy-conversation-eligible-preview.v1"

    let formatVersion: String
    let readOnly: Bool
    let changed: Bool
    let safeForBackfill: Bool
    let safeForShadowWrites: Bool
    var state: LegacyConversationEligiblePreviewState
    var counts: LegacyConversationEligibleCounts
    var rooms: [LegacyConversationEligibleRoom]
    var conflictDiagnosis: LegacyCandidateConflictDiagnosis?

    init(
        state: LegacyConversationEligiblePreviewState,
        counts: LegacyConversationEligibleCounts,
        rooms: [LegacyConversationEligibleRoom],
        conflictDiagnosis: LegacyCandidateConflictDiagnosis? = nil
    ) {
        formatVersion = Self.currentFormatVersion
        readOnly = true
        changed = false
        safeForBackfill = false
        safeForShadowWrites = false
        self.state = state
        self.counts = counts
        self.rooms = rooms
        self.conflictDiagnosis = conflictDiagnosis
    }

    static func sanitized(_ state: LegacyConversationEligiblePreviewState) -> Self {
        .init(state: state, counts: .zero, rooms: [])
    }

    static func identityConflict(_ diagnosis: LegacyCandidateConflictDiagnosis) -> Self {
        .init(state: .blocked, counts: .zero, rooms: [], conflictDiagnosis: diagnosis)
    }
}
