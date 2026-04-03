import Foundation

// MARK: - Tool Mode

enum ToolMode: String, Sendable, Equatable {
    case clipboard
    case aiChat
    case search
    case capture
}

// MARK: - History Entry

struct PanelHistoryEntry: Identifiable, Sendable, Equatable {
    let id: UUID
    let type: PanelHistoryType

    init(id: UUID = UUID(), type: PanelHistoryType) {
        self.id = id
        self.type = type
    }
}

// MARK: - History Type

enum PanelHistoryType: Sendable, Equatable {
    case item(itemID: UUID)
    case splitView(itemID1: UUID, itemID2: UUID)
    case tool(ToolMode)
}

// MARK: - Panel History

@MainActor
final class PanelHistory: ObservableObject {

    static let maxEntries = 50

    @Published private(set) var stack: [PanelHistoryEntry] = []
    @Published private(set) var currentIndex: Int = -1

    // MARK: - Push

    /// Pushes a new entry, truncating any forward history.
    func push(_ entry: PanelHistoryEntry) {
        // Truncate forward history
        if currentIndex < stack.count - 1 {
            stack.removeSubrange((currentIndex + 1)...)
        }

        stack.append(entry)
        currentIndex = stack.count - 1

        // Cap history size — drop oldest entries
        if stack.count > Self.maxEntries {
            let overflow = stack.count - Self.maxEntries
            stack.removeFirst(overflow)
            currentIndex -= overflow
        }
    }

    // MARK: - Navigation

    var canGoBack: Bool {
        currentIndex > 0
    }

    var canGoForward: Bool {
        currentIndex < stack.count - 1
    }

    /// Moves back one entry and returns it.
    @discardableResult
    func back() -> PanelHistoryEntry? {
        guard canGoBack else { return nil }
        currentIndex -= 1
        return stack[currentIndex]
    }

    /// Moves forward one entry and returns it.
    @discardableResult
    func forward() -> PanelHistoryEntry? {
        guard canGoForward else { return nil }
        currentIndex += 1
        return stack[currentIndex]
    }

    // MARK: - Queries

    var current: PanelHistoryEntry? {
        guard stack.indices.contains(currentIndex) else { return nil }
        return stack[currentIndex]
    }

    var isEmpty: Bool {
        stack.isEmpty
    }
}
