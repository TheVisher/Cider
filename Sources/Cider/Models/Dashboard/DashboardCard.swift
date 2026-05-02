import Foundation

struct DashboardCardFeedback: Hashable, Codable, Sendable {
    var rating: Int?
    var moreLikeThis: Bool?
    var lessLikeThis: Bool?
    var notInterested: Bool?
    var note: String?
    var updatedAt: Int64

    init(
        rating: Int? = nil,
        moreLikeThis: Bool? = nil,
        lessLikeThis: Bool? = nil,
        notInterested: Bool? = nil,
        note: String? = nil,
        updatedAt: Int64
    ) {
        self.rating = Self.clampedRating(rating)
        self.moreLikeThis = moreLikeThis
        self.lessLikeThis = lessLikeThis
        self.notInterested = notInterested
        self.note = note
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case rating
        case moreLikeThis
        case lessLikeThis
        case notInterested
        case note
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rating = Self.clampedRating(try container.decodeIfPresent(Int.self, forKey: .rating))
        moreLikeThis = try container.decodeIfPresent(Bool.self, forKey: .moreLikeThis)
        lessLikeThis = try container.decodeIfPresent(Bool.self, forKey: .lessLikeThis)
        notInterested = try container.decodeIfPresent(Bool.self, forKey: .notInterested)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        updatedAt = try container.decode(Int64.self, forKey: .updatedAt)
    }

    private static func clampedRating(_ rating: Int?) -> Int? {
        guard let rating else { return nil }
        return min(max(rating, 1), 5)
    }
}

struct DashboardCardActionState: Hashable, Codable, Sendable {
    var savedBookmarkSyncId: String?
    var savedMemorySyncId: String?
    var createdTodoSyncId: String?
    var createdEventSyncId: String?
    var reminderSyncId: String?
    var lastActionAt: Int64?

    init(
        savedBookmarkSyncId: String? = nil,
        savedMemorySyncId: String? = nil,
        createdTodoSyncId: String? = nil,
        createdEventSyncId: String? = nil,
        reminderSyncId: String? = nil,
        lastActionAt: Int64? = nil
    ) {
        self.savedBookmarkSyncId = savedBookmarkSyncId
        self.savedMemorySyncId = savedMemorySyncId
        self.createdTodoSyncId = createdTodoSyncId
        self.createdEventSyncId = createdEventSyncId
        self.reminderSyncId = reminderSyncId
        self.lastActionAt = lastActionAt
    }
}

struct DashboardCard: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var ciderSyncId: String
    var topicSyncIds: [String]

    var title: String
    var subtitle: String?
    var summary: String
    var whyItMatters: String?

    var sourceKind: DashboardCardSourceKind
    var sourceURL: String?
    var sourceTitle: String?
    var relatedItemSyncId: String?
    var relatedItemType: String?

    var status: DashboardCardStatus
    var priority: DashboardCardPriority
    var score: Double?

    var feedback: DashboardCardFeedback?
    var actionState: DashboardCardActionState?

    var createdAt: Int64
    var updatedAt: Int64
    var lastSeenAt: Int64?
    var dismissedAt: Int64?
    var deleted: Bool?
    var deletedAt: Int64?

    init(
        id: UUID = UUID(),
        ciderSyncId: String? = nil,
        topicSyncIds: [String] = [],
        title: String,
        subtitle: String? = nil,
        summary: String,
        whyItMatters: String? = nil,
        sourceKind: DashboardCardSourceKind = .manual,
        sourceURL: String? = nil,
        sourceTitle: String? = nil,
        relatedItemSyncId: String? = nil,
        relatedItemType: String? = nil,
        status: DashboardCardStatus = .new,
        priority: DashboardCardPriority = .normal,
        score: Double? = nil,
        feedback: DashboardCardFeedback? = nil,
        actionState: DashboardCardActionState? = nil,
        createdAt: Int64,
        updatedAt: Int64,
        lastSeenAt: Int64? = nil,
        dismissedAt: Int64? = nil,
        deleted: Bool? = nil,
        deletedAt: Int64? = nil
    ) {
        self.id = id
        self.ciderSyncId = DashboardModelIdentity.ciderSyncId(ciderSyncId, defaultingTo: id)
        self.topicSyncIds = topicSyncIds.map { $0.lowercased() }
        self.title = title
        self.subtitle = subtitle
        self.summary = summary
        self.whyItMatters = whyItMatters
        self.sourceKind = sourceKind
        self.sourceURL = sourceURL
        self.sourceTitle = sourceTitle
        self.relatedItemSyncId = relatedItemSyncId?.lowercased()
        self.relatedItemType = relatedItemType
        self.status = status
        self.priority = priority
        self.score = score
        self.feedback = feedback
        self.actionState = actionState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastSeenAt = lastSeenAt
        self.dismissedAt = dismissedAt
        self.deleted = deleted
        self.deletedAt = deletedAt
    }

    private enum CodingKeys: String, CodingKey {
        case ciderSyncId
        case topicSyncIds
        case title
        case subtitle
        case summary
        case whyItMatters
        case sourceKind
        case sourceURL
        case sourceTitle
        case relatedItemSyncId
        case relatedItemType
        case status
        case priority
        case score
        case feedback
        case actionState
        case createdAt
        case updatedAt
        case lastSeenAt
        case dismissedAt
        case deleted
        case deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSyncId = try container.decode(String.self, forKey: .ciderSyncId).lowercased()
        id = DashboardModelIdentity.localID(from: decodedSyncId)
        ciderSyncId = decodedSyncId
        topicSyncIds = try container.decode([String].self, forKey: .topicSyncIds).map { $0.lowercased() }
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        summary = try container.decode(String.self, forKey: .summary)
        whyItMatters = try container.decodeIfPresent(String.self, forKey: .whyItMatters)
        sourceKind = (try container.decodeIfPresent(DashboardCardSourceKind.self, forKey: .sourceKind)) ?? .manual
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        sourceTitle = try container.decodeIfPresent(String.self, forKey: .sourceTitle)
        relatedItemSyncId = try container.decodeIfPresent(String.self, forKey: .relatedItemSyncId)?.lowercased()
        relatedItemType = try container.decodeIfPresent(String.self, forKey: .relatedItemType)
        status = (try container.decodeIfPresent(DashboardCardStatus.self, forKey: .status)) ?? .new
        priority = (try container.decodeIfPresent(DashboardCardPriority.self, forKey: .priority)) ?? .normal
        score = try container.decodeIfPresent(Double.self, forKey: .score)
        feedback = try container.decodeIfPresent(DashboardCardFeedback.self, forKey: .feedback)
        actionState = try container.decodeIfPresent(DashboardCardActionState.self, forKey: .actionState)
        createdAt = try container.decode(Int64.self, forKey: .createdAt)
        updatedAt = try container.decode(Int64.self, forKey: .updatedAt)
        lastSeenAt = try container.decodeIfPresent(Int64.self, forKey: .lastSeenAt)
        dismissedAt = try container.decodeIfPresent(Int64.self, forKey: .dismissedAt)
        deleted = try container.decodeIfPresent(Bool.self, forKey: .deleted)
        deletedAt = try container.decodeIfPresent(Int64.self, forKey: .deletedAt)
    }
}
