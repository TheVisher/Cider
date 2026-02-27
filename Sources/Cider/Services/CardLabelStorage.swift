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
        let dir = StoragePaths.directoryURL(for: .labels)
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

    /// Find an existing label by case-insensitive name match, or create a new one.
    @discardableResult
    func findOrCreate(name: String, colorHex: String? = nil) -> CardLabel {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = labels.first(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        return createLabel(name: trimmed, colorHex: colorHex ?? Self.randomPresetColor())
    }

    @discardableResult
    func deleteLabel(_ id: UUID) -> Bool {
        let oldCount = labels.count
        labels.removeAll { $0.id == id }
        guard labels.count != oldCount else { return false }
        persist()
        // Cascade: remove this label from all items
        BookmarksStorage.shared.removeLabelsFromAll(labelID: id)
        NotesStorage.shared.removeLabelsFromAll(labelID: id)
        DateCardStorage.shared.removeLabelsFromAll(labelID: id)
        ContactStorage.shared.removeLabelsFromAll(labelID: id)
        return true
    }

    /// Merge multiple source labels into a single target label.
    /// All items with source labels get the target label, then sources are deleted.
    func mergeLabels(sourceIDs: [UUID], into targetID: UUID) {
        guard labels.contains(where: { $0.id == targetID }) else { return }
        let sources = Set(sourceIDs).subtracting([targetID])
        guard !sources.isEmpty else { return }

        // Reassign items: for each source label, find items and give them the target
        for sourceID in sources {
            reassignLabelOnAllItems(from: sourceID, to: targetID)
            labels.removeAll { $0.id == sourceID }
        }
        persist()
    }

    /// Color presets for tags.
    static let tagColorPresets: [(name: String, hex: String)] = [
        ("Red", "#EF4444"), ("Orange", "#F97316"), ("Yellow", "#EAB308"),
        ("Green", "#22C55E"), ("Teal", "#14B8A6"), ("Blue", "#3B82F6"),
        ("Purple", "#8B5CF6"), ("Pink", "#EC4899"), ("Gray", "#6B7280"),
        ("Brown", "#78716C")
    ]

    static func randomPresetColor() -> String {
        tagColorPresets.randomElement()?.hex ?? "#6B7280"
    }

    private func reassignLabelOnAllItems(from sourceID: UUID, to targetID: UUID) {
        // Bookmarks
        for bookmark in BookmarksStorage.shared.bookmarks where bookmark.labelIDs.contains(sourceID) {
            BookmarksStorage.shared.removeLabel(bookmark.id, labelID: sourceID)
            BookmarksStorage.shared.assignLabel(bookmark.id, labelID: targetID)
        }
        // Notes
        for note in NotesStorage.shared.notes where note.labelIDs.contains(sourceID) {
            NotesStorage.shared.removeLabel(note.id, labelID: sourceID)
            NotesStorage.shared.assignLabel(note.id, labelID: targetID)
        }
        // DateCards
        for card in DateCardStorage.shared.dateCards where card.labelIDs.contains(sourceID) {
            var updated = card
            updated.labelIDs.removeAll { $0 == sourceID }
            if !updated.labelIDs.contains(targetID) { updated.labelIDs.append(targetID) }
            DateCardStorage.shared.updateDateCard(updated)
        }
        // Contacts
        for contact in ContactStorage.shared.contacts where contact.labelIDs.contains(sourceID) {
            var updated = contact
            updated.labelIDs.removeAll { $0 == sourceID }
            if !updated.labelIDs.contains(targetID) { updated.labelIDs.append(targetID) }
            ContactStorage.shared.updateContact(updated)
        }
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
