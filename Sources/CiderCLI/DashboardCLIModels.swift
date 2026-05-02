@testable import Cider
import Foundation

struct DashboardCardUpsertPayload: Decodable {
    var ciderSyncId: String?
    var topicSyncIds: [String]?
    var topics: [String]?
    var title: String?
    var subtitle: String?
    var summary: String?
    var whyItMatters: String?
    var sourceKind: String?
    var sourceURL: String?
    var sourceTitle: String?
    var relatedItemSyncId: String?
    var relatedItemType: String?
    var status: String?
    var priority: String?
    var score: Double?
    var rating: Int?
    var moreLikeThis: Bool?
    var lessLikeThis: Bool?

    init(
        ciderSyncId: String? = nil,
        topicSyncIds: [String]? = nil,
        topics: [String]? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        summary: String? = nil,
        whyItMatters: String? = nil,
        sourceKind: String? = nil,
        sourceURL: String? = nil,
        sourceTitle: String? = nil,
        relatedItemSyncId: String? = nil,
        relatedItemType: String? = nil,
        status: String? = nil,
        priority: String? = nil,
        score: Double? = nil,
        rating: Int? = nil,
        moreLikeThis: Bool? = nil,
        lessLikeThis: Bool? = nil
    ) {
        self.ciderSyncId = ciderSyncId
        self.topicSyncIds = topicSyncIds
        self.topics = topics
        self.title = title
        self.subtitle = subtitle
        self.summary = summary
        self.whyItMatters = whyItMatters
        self.sourceKind = sourceKind
        self.sourceURL = sourceURL
        self.sourceTitle = sourceTitle
        self.relatedItemSyncId = relatedItemSyncId
        self.relatedItemType = relatedItemType
        self.status = status
        self.priority = priority
        self.score = score
        self.rating = rating
        self.moreLikeThis = moreLikeThis
        self.lessLikeThis = lessLikeThis
    }
}
