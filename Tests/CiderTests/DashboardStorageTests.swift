import Foundation
import Testing
@testable import Cider

@MainActor
@Suite("Dashboard storage tests")
struct DashboardStorageTests {
    @Test("dashboard storage path lives under .cider dashboard")
    func dashboardStoragePathLivesUnderCiderDashboard() throws {
        let vaultURL = try makeTemporaryDirectory()
        var config = CiderConfig.default
        config.vaultDirectory = vaultURL.path

        let directoryURL = StoragePaths.directoryURL(for: .dashboard, config: config)

        #expect(directoryURL.path == vaultURL.appendingPathComponent(".cider/dashboard").path)
    }

    @Test("missing dashboard snapshot loads empty state")
    func missingDashboardSnapshotLoadsEmptyState() throws {
        let storage = DashboardStorage(directoryURL: try makeTemporaryDirectory())

        #expect(storage.topics.isEmpty)
        #expect(storage.cards.isEmpty)
        #expect(storage.runs.isEmpty)
    }

    @Test("sample data seeding is explicit and not part of loading")
    func sampleDataSeedingIsExplicitAndNotPartOfLoading() throws {
        let directoryURL = try makeTemporaryDirectory()
        let storage = DashboardStorage(directoryURL: directoryURL)

        #expect(storage.topics.isEmpty)
        #expect(storage.cards.isEmpty)

        storage.seedSampleDataIfEmpty()

        #expect(storage.topics.isEmpty == false)
        #expect(storage.cards.isEmpty == false)
    }

    @Test("invalid dashboard JSON keeps empty safe state")
    func invalidDashboardJSONKeepsEmptySafeState() throws {
        let directoryURL = try makeTemporaryDirectory()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appendingPathComponent("_cider_dashboard.json")
        try "{ nope".write(to: fileURL, atomically: true, encoding: .utf8)

        let storage = DashboardStorage(directoryURL: directoryURL)

        #expect(storage.topics.isEmpty)
        #expect(storage.cards.isEmpty)
        #expect(storage.runs.isEmpty)
    }

    @Test("upserting dashboard topic card and run persists through reload")
    func upsertingDashboardTopicCardAndRunPersistsThroughReload() throws {
        let directoryURL = try makeTemporaryDirectory()
        let storage = DashboardStorage(directoryURL: directoryURL)
        let topic = makeTopic(title: "Tech News")
        let card = makeCard(topicSyncId: topic.ciderSyncId, title: "Swift release")
        let run = makeRun(topicSyncId: topic.ciderSyncId, cardSyncId: card.ciderSyncId)

        storage.upsertTopic(topic)
        storage.upsertCard(card)
        storage.upsertRun(run)

        let reloaded = DashboardStorage(directoryURL: directoryURL)
        #expect(reloaded.topics == [topic])
        #expect(reloaded.cards == [card])
        #expect(reloaded.runs == [run])
    }

    @Test("card seen dismiss and rating actions persist and clamp rating")
    func cardSeenDismissAndRatingActionsPersistAndClampRating() throws {
        let directoryURL = try makeTemporaryDirectory()
        let storage = DashboardStorage(directoryURL: directoryURL)
        let card = makeCard(title: "Rate me")
        storage.upsertCard(card)

        #expect(storage.markSeen(card.ciderSyncId, at: 1_777_708_800_010))
        #expect(storage.dismissCard(card.ciderSyncId, at: 1_777_708_800_011))
        #expect(storage.rateCard(card.ciderSyncId, rating: 99, at: 1_777_708_800_012))

        let reloaded = DashboardStorage(directoryURL: directoryURL)
        let persisted = try #require(reloaded.cards.first)
        #expect(persisted.status == .dismissed)
        #expect(persisted.lastSeenAt == 1_777_708_800_010)
        #expect(persisted.dismissedAt == 1_777_708_800_011)
        #expect(persisted.feedback?.rating == 5)
        #expect(persisted.feedback?.updatedAt == 1_777_708_800_012)
    }

    @Test("card preference actions keep more and less signals exclusive")
    func cardPreferenceActionsKeepMoreAndLessSignalsExclusive() throws {
        let directoryURL = try makeTemporaryDirectory()
        let storage = DashboardStorage(directoryURL: directoryURL)
        let card = makeCard(title: "Taste signal")
        storage.upsertCard(card)

        #expect(storage.markMoreLikeThis(card.ciderSyncId, at: 1_777_708_800_010))
        var reloaded = DashboardStorage(directoryURL: directoryURL)
        var persisted = try #require(reloaded.cards.first)
        #expect(persisted.feedback?.moreLikeThis == true)
        #expect(persisted.feedback?.lessLikeThis == false)

        #expect(storage.markLessLikeThis(card.ciderSyncId, at: 1_777_708_800_011))
        reloaded = DashboardStorage(directoryURL: directoryURL)
        persisted = try #require(reloaded.cards.first)
        #expect(persisted.feedback?.moreLikeThis == false)
        #expect(persisted.feedback?.lessLikeThis == true)
    }

    @Test("card topic move archive and delete actions persist")
    func cardTopicMoveArchiveAndDeleteActionsPersist() throws {
        let directoryURL = try makeTemporaryDirectory()
        let storage = DashboardStorage(directoryURL: directoryURL)
        let topic = makeTopic(title: "Tech News")
        let card = makeCard(topicSyncId: topic.ciderSyncId, title: "Move me")
        storage.upsertTopic(topic)
        storage.upsertCard(card)

        #expect(storage.setCardTopics(card.ciderSyncId, topicSyncIds: ["Sports"], at: 1_777_708_800_010))
        #expect(storage.archiveCard(card.ciderSyncId, at: 1_777_708_800_011))
        #expect(storage.deleteCard(card.ciderSyncId, at: 1_777_708_800_012))

        let reloaded = DashboardStorage(directoryURL: directoryURL)
        let persisted = try #require(reloaded.cards.first)
        #expect(persisted.topicSyncIds == ["sports"])
        #expect(persisted.status == .archived)
        #expect(persisted.deleted == true)
        #expect(persisted.deletedAt == 1_777_708_800_012)
    }

    @Test("upserting a card preserves existing user feedback note")
    func upsertingCardPreservesExistingUserFeedbackNote() throws {
        let directoryURL = try makeTemporaryDirectory()
        let storage = DashboardStorage(directoryURL: directoryURL)
        var card = makeCard(title: "User note card")
        card.feedback = DashboardCardFeedback(
            rating: 4,
            note: "Keep this user note.",
            updatedAt: 1_777_708_800_010
        )
        storage.upsertCard(card)

        var generatedUpdate = makeCard(title: "Updated by importer")
        generatedUpdate.feedback = DashboardCardFeedback(
            rating: 2,
            note: "Generated text should not win.",
            updatedAt: 1_777_708_800_011
        )
        storage.upsertCard(generatedUpdate)

        let reloaded = DashboardStorage(directoryURL: directoryURL)
        let persisted = try #require(reloaded.cards.first)
        #expect(persisted.title == "Updated by importer")
        #expect(persisted.feedback?.rating == 2)
        #expect(persisted.feedback?.note == "Keep this user note.")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-dashboard-storage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeTopic(title: String = "Cider Projects") -> DashboardTopic {
        DashboardTopic(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: title,
            position: 0,
            createdAt: 1_777_708_800_000,
            updatedAt: 1_777_708_800_001
        )
    }

    private func makeCard(topicSyncId: String? = nil, title: String = "Dashboard card") -> DashboardCard {
        DashboardCard(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            topicSyncIds: topicSyncId.map { [$0] } ?? [],
            title: title,
            summary: "A useful dashboard item.",
            createdAt: 1_777_708_800_002,
            updatedAt: 1_777_708_800_003
        )
    }

    private func makeRun(topicSyncId: String, cardSyncId: String) -> DashboardRun {
        DashboardRun(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            startedAt: 1_777_708_800_004,
            finishedAt: 1_777_708_800_005,
            topicSyncIds: [topicSyncId],
            cardSyncIds: [cardSyncId],
            status: .completed
        )
    }
}
