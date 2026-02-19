import Foundation
import Combine

private struct CardStacksSnapshot: Codable {
    var stacks: [CardStack]
}

@MainActor
final class CardStackStorage: ObservableObject {
    static let shared = CardStackStorage()

    @Published private(set) var stacks: [CardStack] = []

    private let fileName = "_cider_stacks.json"
    private var fileURL: URL

    private init() {
        let directoryURL = StoragePaths.ciderDataDirectoryURL()
        fileURL = StoragePaths.jsonFileURL(fileName: fileName, in: directoryURL)
        StoragePaths.ensureDirectory(directoryURL)
        load()
    }

    @discardableResult
    func createStack(name: String) -> CardStack {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Untitled Stack" : trimmed
        let stack = CardStack(name: finalName)
        stacks.append(stack)
        sortStacks()
        persist()
        return stack
    }

    @discardableResult
    func updateStack(_ updated: CardStack) -> Bool {
        guard let idx = stacks.firstIndex(where: { $0.id == updated.id }) else { return false }
        var copy = updated
        copy.updatedAt = Date()
        stacks[idx] = copy
        sortStacks()
        persist()
        return true
    }

    @discardableResult
    func deleteStack(_ id: UUID) -> Bool {
        let oldCount = stacks.count
        stacks.removeAll { $0.id == id }
        guard stacks.count != oldCount else { return false }
        persist()
        return true
    }

    func stack(for id: UUID) -> CardStack? {
        stacks.first { $0.id == id }
    }

    private func sortStacks() {
        stacks.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(CardStacksSnapshot.self, from: data)
            stacks = snapshot.stacks
            sortStacks()
        } catch {
            stacks = []
        }
    }

    private func persist() {
        let snapshot = CardStacksSnapshot(stacks: stacks)
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
