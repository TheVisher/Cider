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
    func createStack(template: StackTemplateKind, nameOverride: String? = nil) -> CardStack {
        let stack: CardStack

        switch template {
        case .blank:
            stack = CardStack(name: cleanName(nameOverride) ?? "Untitled Stack")

        case .bills:
            stack = CardStack(
                name: cleanName(nameOverride) ?? "Bills",
                isPinned: true,
                sortMode: .attention,
                matchRules: [
                    StackMatchRule(condition: .entityType, value: LibraryEntityType.dateCard.rawValue)
                ],
                surfaceRules: [
                    SurfacingRule(type: .pinUntilDone),
                    SurfacingRule(type: .surfaceDaysBeforeDate, integerValue: 7)
                ],
                summaryModule: .bills
            )

        case .birthdays:
            stack = CardStack(
                name: cleanName(nameOverride) ?? "Birthdays",
                isPinned: true,
                sortMode: .time,
                matchRules: [
                    StackMatchRule(condition: .entityType, value: LibraryEntityType.dateCard.rawValue)
                ],
                surfaceRules: [
                    SurfacingRule(type: .surfaceDaysBeforeDate, integerValue: 14)
                ],
                summaryModule: .none
            )

        case .schedule:
            stack = CardStack(
                name: cleanName(nameOverride) ?? "Schedule",
                isPinned: false,
                sortMode: .time,
                matchRules: [
                    StackMatchRule(condition: .hasDate)
                ],
                surfaceRules: [
                    SurfacingRule(type: .remindBeforeMinutes, integerValue: 30)
                ],
                summaryModule: .none
            )
        }

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

    private func cleanName(_ candidate: String?) -> String? {
        guard let candidate else { return nil }
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
