import Foundation

struct KanbanTestingGuideStep: Hashable, Identifiable, Sendable {
    var id: String
    var text: String
}

struct KanbanTestingGuidePanelPayload: Hashable, Identifiable, Sendable {
    var boardID: String
    var boardName: String
    var cardID: String
    var cardTitle: String
    var steps: [KanbanTestingGuideStep]

    var id: String {
        "\(boardID):\(cardID)"
    }
}

struct KanbanTestingGuidePanelModel: Equatable {
    var boardID: String
    var boardName: String
    var cardID: String
    var cardTitle: String
    var steps: [KanbanTestingGuideStep]

    init(
        boardID: String,
        boardName: String,
        cardID: String,
        cardTitle: String,
        entries: [KanbanCardDashboardEntry]
    ) {
        self.boardID = boardID
        self.boardName = boardName
        self.cardID = cardID
        self.cardTitle = cardTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        steps = entries.enumerated().compactMap { index, entry in
            let text = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return KanbanTestingGuideStep(id: "\(entry.id)-\(index)", text: text)
        }
    }

    var payload: KanbanTestingGuidePanelPayload {
        KanbanTestingGuidePanelPayload(
            boardID: boardID,
            boardName: boardName,
            cardID: cardID,
            cardTitle: cardTitle.isEmpty ? "Untitled Kanban Card" : cardTitle,
            steps: steps
        )
    }
}

@MainActor
final class KanbanTestingGuideProgressStore: ObservableObject {
    static let shared = KanbanTestingGuideProgressStore()

    @Published private var completedStepIDsByGuide: [String: Set<String>] = [:] {
        didSet {
            persistCompletedStepIDs()
        }
    }

    private let defaultsKey = "kanbanTestingGuide.completedStepIDsByGuide"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        completedStepIDsByGuide = Self.loadCompletedStepIDs(from: defaults, key: defaultsKey)
    }

    func isCompleted(guideID: String, stepID: String) -> Bool {
        completedStepIDsByGuide[guideID, default: []].contains(stepID)
    }

    func toggle(guideID: String, stepID: String) {
        setCompleted(!isCompleted(guideID: guideID, stepID: stepID), guideID: guideID, stepID: stepID)
    }

    func setCompleted(_ isCompleted: Bool, guideID: String, stepID: String) {
        var completedStepIDs = completedStepIDsByGuide[guideID, default: []]
        if isCompleted {
            completedStepIDs.insert(stepID)
        } else {
            completedStepIDs.remove(stepID)
        }

        if completedStepIDs.isEmpty {
            completedStepIDsByGuide.removeValue(forKey: guideID)
        } else {
            completedStepIDsByGuide[guideID] = completedStepIDs
        }
    }

    func completedCount(guideID: String, steps: [KanbanTestingGuideStep]) -> Int {
        let completedStepIDs = completedStepIDsByGuide[guideID, default: []]
        return steps.filter { completedStepIDs.contains($0.id) }.count
    }

    private func persistCompletedStepIDs() {
        let payload = completedStepIDsByGuide.mapValues { Array($0).sorted() }
        defaults.set(payload, forKey: defaultsKey)
    }

    private static func loadCompletedStepIDs(from defaults: UserDefaults, key: String) -> [String: Set<String>] {
        guard let payload = defaults.dictionary(forKey: key) as? [String: [String]] else {
            return [:]
        }
        return payload.mapValues(Set.init)
    }
}
