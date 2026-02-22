import Foundation
import Combine

private struct DateCardsSnapshot: Codable {
    var dateCards: [DateCard]
}

@MainActor
final class DateCardStorage: ObservableObject {
    static let shared = DateCardStorage()

    @Published private(set) var dateCards: [DateCard] = []

    private let fileName = "_cider_date_cards.json"
    private var fileURL: URL {
        let dir = StoragePaths.ciderDataDirectoryURL()
        StoragePaths.ensureDirectory(dir)
        return StoragePaths.jsonFileURL(fileName: fileName, in: dir)
    }

    private init() {
        load()
    }

    func reload() {
        load()
    }

    @discardableResult
    func createDateCard(
        title: String,
        startAt: Date,
        endAt: Date? = nil,
        allDay: Bool = false,
        amount: Double? = nil
    ) -> DateCard {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmed.isEmpty ? "Untitled Date Card" : trimmed
        let dateCard = DateCard(
            title: finalTitle,
            startAt: startAt,
            endAt: endAt,
            allDay: allDay,
            amount: amount
        )
        dateCards.append(dateCard)
        sortCards()
        persist()
        return dateCard
    }

    @discardableResult
    func updateDateCard(_ updated: DateCard) -> Bool {
        guard let idx = dateCards.firstIndex(where: { $0.id == updated.id }) else { return false }
        var copy = updated
        copy.updatedAt = Date()
        dateCards[idx] = copy
        sortCards()
        persist()
        return true
    }

    @discardableResult
    func deleteDateCard(_ id: UUID) -> Bool {
        let oldCount = dateCards.count
        dateCards.removeAll { $0.id == id }
        guard dateCards.count != oldCount else { return false }
        persist()
        return true
    }

    @discardableResult
    func markCompleted(_ id: UUID, completed: Bool) -> Bool {
        guard let idx = dateCards.firstIndex(where: { $0.id == id }) else { return false }
        dateCards[idx].isCompleted = completed
        dateCards[idx].completedAt = completed ? Date() : nil
        dateCards[idx].updatedAt = Date()
        persist()
        return true
    }

    func dateCard(for id: UUID) -> DateCard? {
        dateCards.first { $0.id == id }
    }

    func restoreFromTrash(_ dateCard: DateCard) {
        guard !dateCards.contains(where: { $0.id == dateCard.id }) else { return }
        dateCards.append(dateCard)
        sortCards()
        persist()
    }

    private func sortCards() {
        dateCards.sort { lhs, rhs in
            if lhs.startAt != rhs.startAt {
                return lhs.startAt < rhs.startAt
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(DateCardsSnapshot.self, from: data)
            dateCards = snapshot.dateCards
            sortCards()
        } catch {
            dateCards = []
        }
    }

    private func persist() {
        let snapshot = DateCardsSnapshot(dateCards: dateCards)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Best-effort persistence.
        }
    }

}
