import Foundation

struct DashboardSnapshot: Hashable, Codable, Sendable {
    var schemaVersion: Int
    var topics: [DashboardTopic]
    var cards: [DashboardCard]
    var runs: [DashboardRun]
    var updatedAt: Int64

    init(
        schemaVersion: Int = 1,
        topics: [DashboardTopic] = [],
        cards: [DashboardCard] = [],
        runs: [DashboardRun] = [],
        updatedAt: Int64
    ) {
        self.schemaVersion = schemaVersion
        self.topics = topics
        self.cards = cards
        self.runs = runs
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case topics
        case cards
        case runs
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try container.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? 1
        topics = (try container.decodeIfPresent([DashboardTopic].self, forKey: .topics)) ?? []
        cards = (try container.decodeIfPresent([DashboardCard].self, forKey: .cards)) ?? []
        runs = (try container.decodeIfPresent([DashboardRun].self, forKey: .runs)) ?? []
        updatedAt = try container.decode(Int64.self, forKey: .updatedAt)
    }
}
