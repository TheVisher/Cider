import Foundation
import Testing
@testable import Cider
@testable import CiderCLI

@Suite("Dashboard model tests")
struct DashboardModelTests {
    @Test("default dashboard topics are stable and user-facing")
    func defaultDashboardTopicsAreStableAndUserFacing() {
        let topics = DashboardDefaultTopics.topics

        #expect(topics.map(\.title) == ["Tech News", "Sports", "Cider Projects"])
        #expect(topics.map(\.position) == [0, 1, 2])
        #expect(topics.map(\.ciderSyncId) == [
            "01000000-0000-0000-0000-000000000001",
            "01000000-0000-0000-0000-000000000002",
            "01000000-0000-0000-0000-000000000003"
        ])
    }

    @Test("dashboard models default to lowercase sync identifiers")
    func dashboardModelsDefaultToLowercaseSyncIdentifiers() {
        let id = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!
        let topic = DashboardTopic(id: id, title: "Tech News", position: 0, createdAt: 1_700_000_000_000, updatedAt: 1_700_000_000_000)
        let card = DashboardCard(id: id, topicSyncIds: [topic.ciderSyncId], title: "Swift", summary: "Swift 6.2 shipped.", createdAt: 1_700_000_000_000, updatedAt: 1_700_000_000_000)
        let run = DashboardRun(id: id, startedAt: 1_700_000_000_000)

        #expect(topic.ciderSyncId == "a1b2c3d4-e5f6-7890-abcd-ef1234567890")
        #expect(card.ciderSyncId == "a1b2c3d4-e5f6-7890-abcd-ef1234567890")
        #expect(run.ciderSyncId == "a1b2c3d4-e5f6-7890-abcd-ef1234567890")
    }

    @Test("dashboard snapshot encodes timestamps as numeric milliseconds")
    func dashboardSnapshotEncodesTimestampsAsNumericMilliseconds() throws {
        let topic = DashboardTopic(title: "Cider Projects", position: 1, createdAt: 1_777_708_800_000, updatedAt: 1_777_708_800_001)
        let feedback = DashboardCardFeedback(rating: 4, updatedAt: 1_777_708_800_002)
        let card = DashboardCard(topicSyncIds: [topic.ciderSyncId], title: "Ship dashboard", summary: "Model first.", feedback: feedback, createdAt: 1_777_708_800_003, updatedAt: 1_777_708_800_004, lastSeenAt: 1_777_708_800_005)
        let run = DashboardRun(startedAt: 1_777_708_800_006, finishedAt: 1_777_708_800_007, topicSyncIds: [topic.ciderSyncId], cardSyncIds: [card.ciderSyncId], status: .completed)
        let snapshot = DashboardSnapshot(topics: [topic], cards: [card], runs: [run], updatedAt: 1_777_708_800_008)

        let data = try JSONEncoder().encode(snapshot)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let decoded = try JSONDecoder().decode(DashboardSnapshot.self, from: data)

        #expect(object["updatedAt"] as? Int == 1_777_708_800_008)
        let encodedTopics = try #require(object["topics"] as? [[String: Any]])
        #expect(encodedTopics.first?["createdAt"] as? Int == 1_777_708_800_000)
        let encodedCards = try #require(object["cards"] as? [[String: Any]])
        #expect(encodedCards.first?["lastSeenAt"] as? Int == 1_777_708_800_005)
        let encodedFeedback = try #require(encodedCards.first?["feedback"] as? [String: Any])
        #expect(encodedFeedback["updatedAt"] as? Int == 1_777_708_800_002)
        let encodedRuns = try #require(object["runs"] as? [[String: Any]])
        #expect(encodedRuns.first?["startedAt"] as? Int == 1_777_708_800_006)
        #expect(decoded.updatedAt == snapshot.updatedAt)
        #expect(decoded.cards.first?.feedback?.updatedAt == feedback.updatedAt)
    }

    @Test("dashboard snapshot includes runs")
    func dashboardSnapshotIncludesRuns() throws {
        let run = DashboardRun(source: .manual, startedAt: 1_700_000_000_000, status: .running)
        let snapshot = DashboardSnapshot(runs: [run], updatedAt: 1_700_000_000_001)

        let decoded = try JSONDecoder().decode(DashboardSnapshot.self, from: JSONEncoder().encode(snapshot))

        #expect(decoded.runs == [run])
    }

    @Test("dashboard feedback clamps ratings to one through five")
    func dashboardFeedbackClampsRatingsToOneThroughFive() throws {
        let low = DashboardCardFeedback(rating: -10, updatedAt: 1_700_000_000_000)
        let highData = """
        {
          "rating": 9,
          "updatedAt": 1700000000000
        }
        """.data(using: .utf8)!

        let high = try JSONDecoder().decode(DashboardCardFeedback.self, from: highData)

        #expect(low.rating == 1)
        #expect(high.rating == 5)
    }

    @Test("dashboard enums safely decode unknown future values")
    func dashboardEnumsSafelyDecodeUnknownFutureValues() throws {
        let data = """
        {
          "schemaVersion": 1,
          "topics": [],
          "cards": [
            {
              "ciderSyncId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
              "topicSyncIds": [],
              "title": "Future card",
              "summary": "From a future source.",
              "sourceKind": "podcast",
              "status": "snoozed",
              "priority": "critical",
              "createdAt": 1700000000000,
              "updatedAt": 1700000000001
            }
          ],
          "runs": [
            {
              "ciderSyncId": "b1b2c3d4-e5f6-7890-abcd-ef1234567890",
              "source": "webhook",
              "startedAt": 1700000000002,
              "topicSyncIds": [],
              "cardSyncIds": [],
              "status": "paused"
            }
          ],
          "updatedAt": 1700000000003
        }
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder().decode(DashboardSnapshot.self, from: data)

        #expect(snapshot.cards.first?.sourceKind == .unknown("podcast"))
        #expect(snapshot.cards.first?.status == .unknown("snoozed"))
        #expect(snapshot.cards.first?.priority == .unknown("critical"))
        #expect(snapshot.runs.first?.source == .unknown("webhook"))
        #expect(snapshot.runs.first?.status == .unknown("paused"))
    }

    @Test("dashboard topics and cards declare ui preference second brain contract")
    @MainActor
    func dashboardTopicsAndCardsDeclareUIPreferenceSecondBrainContract() throws {
        let topic = DashboardTopic(
            title: "Cider Projects",
            position: 1,
            createdAt: 1_777_708_800_000,
            updatedAt: 1_777_708_800_001
        )
        let card = DashboardCard(
            topicSyncIds: [topic.ciderSyncId],
            title: "Dashboard preference",
            summary: "Local dashboard preference state.",
            relatedItemSyncId: "note-123",
            relatedItemType: "note",
            createdAt: 1_777_708_800_002,
            updatedAt: 1_777_708_800_003
        )

        #expect(DashboardStorage.secondBrainContract.authority == .uiPreferenceState)
        #expect(DashboardStorage.secondBrainContract.isSecondBrainTruth == false)
        #expect(DashboardStorage.secondBrainContract.homePrimaryReadModel == "HomeOverviewDataProvider")
        #expect(DashboardStorage.secondBrainContract.safeGraphCommands == ["cider-cli item graph-health --json"])
        #expect(topic.secondBrainContract.authority == .uiPreferenceState)
        #expect(card.secondBrainContract.authority == .uiPreferenceState)
        #expect(card.secondBrainOwnerRef == nil)

        let topicDict = dashboardTopicToDict(topic)
        let cardDict = dashboardCardToDict(card)
        #expect(topicDict["secondBrainTruth"] as? Bool == false)
        #expect(topicDict["authority"] as? String == "ui_preference_state")
        #expect(cardDict["secondBrainTruth"] as? Bool == false)
        #expect(cardDict["authority"] as? String == "ui_preference_state")
        #expect(cardDict["relatedItemSyncId"] as? String == "note-123")
        #expect(cardDict["secondBrainOwnerRef"] == nil)
        #expect(cardDict["safeGraphCommands"] as? [String] == ["cider-cli item graph-health --json"])
    }
}
