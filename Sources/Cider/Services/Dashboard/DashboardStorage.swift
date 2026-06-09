import Combine
import Foundation
import os

@MainActor
final class DashboardStorage: ObservableObject {
    static let shared = DashboardStorage()
    static let secondBrainContract = DashboardSecondBrainContract.uiPreferenceState

    @Published private(set) var topics: [DashboardTopic] = []
    @Published private(set) var cards: [DashboardCard] = []
    @Published private(set) var runs: [DashboardRun] = []

    private static let fileName = "_cider_dashboard.json"

    private let logger = Logger(subsystem: "com.cider.app", category: "DashboardStorage")
    private let fileURL: URL

    private init() {
        let directoryURL = StoragePaths.directoryURL(for: .dashboard)
        self.fileURL = directoryURL.appendingPathComponent(Self.fileName)
        load()
    }

    init(directoryURL: URL) {
        self.fileURL = directoryURL.appendingPathComponent(Self.fileName)
        load()
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    func reload() {
        load()
    }

    func upsertTopic(_ topic: DashboardTopic) {
        var copy = topic
        copy.ciderSyncId = copy.ciderSyncId.lowercased()
        if let index = topics.firstIndex(where: { $0.ciderSyncId == copy.ciderSyncId }) {
            topics[index] = copy
        } else {
            topics.append(copy)
        }
        persist()
    }

    @discardableResult
    func archiveTopic(_ ciderSyncId: String, at timestamp: Int64 = DashboardStorage.currentMilliseconds()) -> Bool {
        guard let index = topics.firstIndex(where: { $0.ciderSyncId == ciderSyncId.lowercased() }) else {
            return false
        }
        topics[index].isArchived = true
        topics[index].updatedAt = timestamp
        persist()
        return true
    }

    @discardableResult
    func moveTopic(_ ciderSyncId: String, to position: Int, at timestamp: Int64 = DashboardStorage.currentMilliseconds()) -> Bool {
        guard let index = topics.firstIndex(where: { $0.ciderSyncId == ciderSyncId.lowercased() }) else {
            return false
        }
        topics[index].position = max(0, position)
        topics[index].updatedAt = timestamp
        topics.sort { lhs, rhs in
            if lhs.position == rhs.position {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.position < rhs.position
        }
        persist()
        return true
    }

    func upsertCard(_ card: DashboardCard) {
        var copy = card
        copy.ciderSyncId = copy.ciderSyncId.lowercased()
        copy.topicSyncIds = copy.topicSyncIds.map { $0.lowercased() }
        copy.relatedItemSyncId = copy.relatedItemSyncId?.lowercased()
        if let index = cards.firstIndex(where: { $0.ciderSyncId == copy.ciderSyncId }) {
            copy.feedback = feedbackPreservingUserNote(
                incoming: copy.feedback,
                existing: cards[index].feedback
            )
            cards[index] = copy
        } else {
            cards.append(copy)
        }
        persist()
    }

    @discardableResult
    func setCardTopics(
        _ ciderSyncId: String,
        topicSyncIds: [String],
        at timestamp: Int64 = DashboardStorage.currentMilliseconds()
    ) -> Bool {
        guard let index = cards.firstIndex(where: { $0.ciderSyncId == ciderSyncId.lowercased() }) else {
            return false
        }
        cards[index].topicSyncIds = topicSyncIds.map { $0.lowercased() }
        cards[index].updatedAt = timestamp
        persist()
        return true
    }

    @discardableResult
    func markSeen(_ ciderSyncId: String, at timestamp: Int64 = DashboardStorage.currentMilliseconds()) -> Bool {
        guard let index = cards.firstIndex(where: { $0.ciderSyncId == ciderSyncId.lowercased() }) else {
            return false
        }
        cards[index].status = .seen
        cards[index].lastSeenAt = timestamp
        cards[index].updatedAt = timestamp
        persist()
        return true
    }

    @discardableResult
    func dismissCard(_ ciderSyncId: String, at timestamp: Int64 = DashboardStorage.currentMilliseconds()) -> Bool {
        guard let index = cards.firstIndex(where: { $0.ciderSyncId == ciderSyncId.lowercased() }) else {
            return false
        }
        cards[index].status = .dismissed
        cards[index].dismissedAt = timestamp
        cards[index].updatedAt = timestamp
        persist()
        return true
    }

    @discardableResult
    func archiveCard(_ ciderSyncId: String, at timestamp: Int64 = DashboardStorage.currentMilliseconds()) -> Bool {
        guard let index = cards.firstIndex(where: { $0.ciderSyncId == ciderSyncId.lowercased() }) else {
            return false
        }
        cards[index].status = .archived
        cards[index].updatedAt = timestamp
        persist()
        return true
    }

    @discardableResult
    func deleteCard(_ ciderSyncId: String, at timestamp: Int64 = DashboardStorage.currentMilliseconds()) -> Bool {
        guard let index = cards.firstIndex(where: { $0.ciderSyncId == ciderSyncId.lowercased() }) else {
            return false
        }
        cards[index].deleted = true
        cards[index].deletedAt = timestamp
        cards[index].updatedAt = timestamp
        persist()
        return true
    }

    @discardableResult
    func rateCard(_ ciderSyncId: String, rating: Int, at timestamp: Int64 = DashboardStorage.currentMilliseconds()) -> Bool {
        guard let index = cards.firstIndex(where: { $0.ciderSyncId == ciderSyncId.lowercased() }) else {
            return false
        }
        let existing = cards[index].feedback
        cards[index].feedback = DashboardCardFeedback(
            rating: rating,
            moreLikeThis: existing?.moreLikeThis,
            lessLikeThis: existing?.lessLikeThis,
            notInterested: existing?.notInterested,
            note: existing?.note,
            updatedAt: timestamp
        )
        cards[index].updatedAt = timestamp
        persist()
        return true
    }

    @discardableResult
    func markMoreLikeThis(_ ciderSyncId: String, at timestamp: Int64 = DashboardStorage.currentMilliseconds()) -> Bool {
        setCardPreference(
            ciderSyncId,
            moreLikeThis: true,
            lessLikeThis: false,
            at: timestamp
        )
    }

    @discardableResult
    func markLessLikeThis(_ ciderSyncId: String, at timestamp: Int64 = DashboardStorage.currentMilliseconds()) -> Bool {
        setCardPreference(
            ciderSyncId,
            moreLikeThis: false,
            lessLikeThis: true,
            at: timestamp
        )
    }

    @discardableResult
    func setCardPreference(
        _ ciderSyncId: String,
        moreLikeThis: Bool? = nil,
        lessLikeThis: Bool? = nil,
        at timestamp: Int64 = DashboardStorage.currentMilliseconds()
    ) -> Bool {
        guard let index = cards.firstIndex(where: { $0.ciderSyncId == ciderSyncId.lowercased() }) else {
            return false
        }
        let existing = cards[index].feedback
        cards[index].feedback = DashboardCardFeedback(
            rating: existing?.rating,
            moreLikeThis: moreLikeThis ?? existing?.moreLikeThis,
            lessLikeThis: lessLikeThis ?? existing?.lessLikeThis,
            notInterested: existing?.notInterested,
            note: existing?.note,
            updatedAt: timestamp
        )
        cards[index].updatedAt = timestamp
        persist()
        return true
    }

    func upsertRun(_ run: DashboardRun) {
        var copy = run
        copy.ciderSyncId = copy.ciderSyncId.lowercased()
        copy.topicSyncIds = copy.topicSyncIds.map { $0.lowercased() }
        copy.cardSyncIds = copy.cardSyncIds.map { $0.lowercased() }
        if let index = runs.firstIndex(where: { $0.ciderSyncId == copy.ciderSyncId }) {
            runs[index] = copy
        } else {
            runs.append(copy)
        }
        persist()
    }

    func persist() {
        let snapshot = DashboardSnapshot(
            topics: topics,
            cards: cards,
            runs: runs,
            updatedAt: Self.currentMilliseconds()
        )

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try Self.encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to persist dashboard snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            clearState()
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try JSONDecoder().decode(DashboardSnapshot.self, from: data)
            topics = snapshot.topics
            cards = snapshot.cards
            runs = snapshot.runs
        } catch {
            logger.error("Failed to load dashboard snapshot, using empty state: \(error.localizedDescription, privacy: .public)")
            clearState()
        }
    }

    private func clearState() {
        topics = []
        cards = []
        runs = []
    }

    private func feedbackPreservingUserNote(
        incoming: DashboardCardFeedback?,
        existing: DashboardCardFeedback?
    ) -> DashboardCardFeedback? {
        guard let existingNote = existing?.note, !existingNote.isEmpty else {
            return incoming
        }
        guard var incoming else {
            return existing
        }
        incoming.note = existingNote
        return incoming
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static func currentMilliseconds() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded())
    }
}
