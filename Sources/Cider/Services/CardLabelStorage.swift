import Foundation
import Combine

private struct CardLabelsSnapshot: Codable {
    var labels: [CardLabel]
}

@MainActor
final class CardLabelStorage: ObservableObject {
    static let shared = CardLabelStorage()

    @Published private(set) var labels: [CardLabel] = []

    private let fileName = "_cider_labels.json"
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
    func createLabel(
        name: String,
        colorHex: String = "#6B7280",
        kind: CardLabelKind = .custom
    ) -> CardLabel {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Untitled Label" : trimmed
        let label = CardLabel(name: finalName, colorHex: colorHex, kind: kind)
        labels.append(label)
        sortLabels()
        persist()
        return label
    }

    @discardableResult
    func updateLabel(_ updated: CardLabel) -> Bool {
        guard let idx = labels.firstIndex(where: { $0.id == updated.id }) else { return false }
        var copy = updated
        copy.updatedAt = Date()
        labels[idx] = copy
        sortLabels()
        persist()
        return true
    }

    @discardableResult
    func deleteLabel(_ id: UUID) -> Bool {
        let oldCount = labels.count
        labels.removeAll { $0.id == id }
        guard labels.count != oldCount else { return false }
        persist()
        return true
    }

    func label(for id: UUID) -> CardLabel? {
        labels.first { $0.id == id }
    }

    private func sortLabels() {
        labels.sort { lhs, rhs in
            let cmp = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if cmp != .orderedSame {
                return cmp == .orderedAscending
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
            let snapshot = try decoder.decode(CardLabelsSnapshot.self, from: data)
            labels = snapshot.labels
            sortLabels()
        } catch {
            labels = []
        }
    }

    private func persist() {
        let snapshot = CardLabelsSnapshot(labels: labels)
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
