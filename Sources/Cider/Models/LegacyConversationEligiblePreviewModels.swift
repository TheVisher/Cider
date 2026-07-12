import Foundation

enum LegacyConversationEligiblePreviewState: String, Codable, Equatable, Sendable {
    case empty
    case ready
    case eligibleEmpty
    case blocked
    case failed
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
    let formatVersion: String
    let readOnly: Bool
    let changed: Bool
    let safeForBackfill: Bool
    let safeForShadowWrites: Bool
    var state: LegacyConversationEligiblePreviewState
    var counts: LegacyConversationEligibleCounts
    var rooms: [LegacyConversationEligibleRoom]

    init(
        state: LegacyConversationEligiblePreviewState,
        counts: LegacyConversationEligibleCounts,
        rooms: [LegacyConversationEligibleRoom]
    ) {
        formatVersion = "cider.legacy-conversation-eligible-preview.v1"
        readOnly = true
        changed = false
        safeForBackfill = false
        safeForShadowWrites = false
        self.state = state
        self.counts = counts
        self.rooms = rooms
    }

    static func sanitized(_ state: LegacyConversationEligiblePreviewState) -> Self {
        .init(state: state, counts: .zero, rooms: [])
    }
}
