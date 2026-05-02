import Foundation

enum DashboardDefaultTopics {
    static let topics: [DashboardTopic] = {
        let timestamp = seedTimestamp
        return [
            DashboardTopic(
                id: UUID(uuidString: "01000000-0000-0000-0000-000000000001")!,
                title: "Tech News",
                icon: "desktopcomputer",
                position: 0,
                isPinned: true,
                createdAt: timestamp,
                updatedAt: timestamp
            ),
            DashboardTopic(
                id: UUID(uuidString: "01000000-0000-0000-0000-000000000002")!,
                title: "Sports",
                icon: "sportscourt",
                position: 1,
                createdAt: timestamp,
                updatedAt: timestamp
            ),
            DashboardTopic(
                id: UUID(uuidString: "01000000-0000-0000-0000-000000000003")!,
                title: "Cider Projects",
                icon: "hammer",
                position: 2,
                isPinned: true,
                createdAt: timestamp,
                updatedAt: timestamp
            )
        ]
    }()

    private static let seedTimestamp: Int64 = 1_777_708_800_000
}

enum DashboardSeedData {
    static let topics = DashboardDefaultTopics.topics

    static let cards: [DashboardCard] = {
        let timestamp = seedTimestamp
        let tech = topics[0].ciderSyncId
        let sports = topics[1].ciderSyncId
        let projects = topics[2].ciderSyncId

        return [
            DashboardCard(
                id: UUID(uuidString: "02000000-0000-0000-0000-000000000001")!,
                topicSyncIds: [tech],
                title: "Add sources for the tech desk",
                subtitle: "Manual placeholder",
                summary: "Drop in the blogs, release feeds, or saved searches you actually trust. Until then, this is intentionally not pretending to be live news.",
                whyItMatters: "The dashboard is useful when it reflects your sources, not the internet's loudest recycling bin.",
                sourceKind: .manual,
                priority: .normal,
                createdAt: timestamp + 1,
                updatedAt: timestamp + 1
            ),
            DashboardCard(
                id: UUID(uuidString: "02000000-0000-0000-0000-000000000002")!,
                topicSyncIds: [sports],
                title: "Pick teams or leagues to follow",
                subtitle: "Manual placeholder",
                summary: "Use this lane for score links, schedule notes, or clips you want to revisit. No fake scores, no suspiciously confident bot play-by-play.",
                whyItMatters: "Sports tabs get better when they know which games you care about.",
                sourceKind: .manual,
                priority: .low,
                createdAt: timestamp + 2,
                updatedAt: timestamp + 2
            ),
            DashboardCard(
                id: UUID(uuidString: "02000000-0000-0000-0000-000000000003")!,
                topicSyncIds: [projects],
                title: "Wire the desktop dashboard MVP",
                subtitle: "Manual placeholder",
                summary: "Keep Main as the existing overview, add topic tabs, and make feedback actions persist through DashboardStorage.",
                whyItMatters: "A dashboard that can remember tiny reactions is already more useful than a pretty static wall.",
                sourceKind: .manual,
                priority: .high,
                createdAt: timestamp + 3,
                updatedAt: timestamp + 3
            )
        ]
    }()

    private static let seedTimestamp: Int64 = 1_777_708_800_000
}

@MainActor
extension DashboardStorage {
    func seedSampleDataIfEmpty() {
        guard topics.isEmpty, cards.isEmpty else { return }

        DashboardSeedData.topics.forEach(upsertTopic)
        DashboardSeedData.cards.forEach(upsertCard)
    }
}
