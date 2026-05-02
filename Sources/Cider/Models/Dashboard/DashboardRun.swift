import Foundation

struct DashboardRun: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var ciderSyncId: String
    var source: DashboardRunSource
    var startedAt: Int64
    var finishedAt: Int64?
    var topicSyncIds: [String]
    var cardSyncIds: [String]
    var status: DashboardRunStatus
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        ciderSyncId: String? = nil,
        source: DashboardRunSource = .manual,
        startedAt: Int64,
        finishedAt: Int64? = nil,
        topicSyncIds: [String] = [],
        cardSyncIds: [String] = [],
        status: DashboardRunStatus = .running,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.ciderSyncId = DashboardModelIdentity.ciderSyncId(ciderSyncId, defaultingTo: id)
        self.source = source
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.topicSyncIds = topicSyncIds.map { $0.lowercased() }
        self.cardSyncIds = cardSyncIds.map { $0.lowercased() }
        self.status = status
        self.errorMessage = errorMessage
    }

    private enum CodingKeys: String, CodingKey {
        case ciderSyncId
        case source
        case startedAt
        case finishedAt
        case topicSyncIds
        case cardSyncIds
        case status
        case errorMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSyncId = try container.decode(String.self, forKey: .ciderSyncId).lowercased()
        id = DashboardModelIdentity.localID(from: decodedSyncId)
        ciderSyncId = decodedSyncId
        source = (try container.decodeIfPresent(DashboardRunSource.self, forKey: .source)) ?? .manual
        startedAt = try container.decode(Int64.self, forKey: .startedAt)
        finishedAt = try container.decodeIfPresent(Int64.self, forKey: .finishedAt)
        topicSyncIds = (try container.decodeIfPresent([String].self, forKey: .topicSyncIds))?.map { $0.lowercased() } ?? []
        cardSyncIds = (try container.decodeIfPresent([String].self, forKey: .cardSyncIds))?.map { $0.lowercased() } ?? []
        status = (try container.decodeIfPresent(DashboardRunStatus.self, forKey: .status)) ?? .running
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
    }
}
