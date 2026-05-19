import Foundation

struct KanbanTestingGuideStep: Hashable, Identifiable, Sendable {
    var id: String
    var text: String
}

enum KanbanTestingGuideStepStatus: String, Codable, Hashable, Sendable {
    case passed
    case failed
}

struct KanbanTestingGuideStepResult: Codable, Hashable, Sendable {
    var status: KanbanTestingGuideStepStatus
    var note: String?
    var updatedAt: Date
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

    @Published private var stepResultsByGuide: [String: [String: KanbanTestingGuideStepResult]] = [:] {
        didSet {
            persistStepResults()
        }
    }

    @Published private var overallNotesByGuide: [String: String] = [:] {
        didSet {
            persistOverallNotes()
        }
    }

    @Published private var completedStepIDsByGuide: [String: Set<String>] = [:] {
        didSet {
            persistCompletedStepIDs()
        }
    }

    private let defaultsKey = "kanbanTestingGuide.completedStepIDsByGuide"
    private let resultsDefaultsKey = "kanbanTestingGuide.stepResultsByGuide"
    private let overallNotesDefaultsKey = "kanbanTestingGuide.overallNotesByGuide"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        completedStepIDsByGuide = Self.loadCompletedStepIDs(from: defaults, key: defaultsKey)
        stepResultsByGuide = Self.loadStepResults(from: defaults, key: resultsDefaultsKey)
        overallNotesByGuide = Self.loadOverallNotes(from: defaults, key: overallNotesDefaultsKey)
        migrateCompletedStepsIntoResults()
    }

    func isCompleted(guideID: String, stepID: String) -> Bool {
        result(guideID: guideID, stepID: stepID)?.status == .passed
            || completedStepIDsByGuide[guideID, default: []].contains(stepID)
    }

    func result(guideID: String, stepID: String) -> KanbanTestingGuideStepResult? {
        stepResultsByGuide[guideID]?[stepID]
    }

    func overallNote(guideID: String) -> String? {
        overallNotesByGuide[guideID]
    }

    func setOverallNote(_ note: String?, guideID: String) {
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedNote, !trimmedNote.isEmpty {
            overallNotesByGuide[guideID] = trimmedNote
        } else {
            overallNotesByGuide.removeValue(forKey: guideID)
        }
    }

    func toggle(guideID: String, stepID: String) {
        setCompleted(!isCompleted(guideID: guideID, stepID: stepID), guideID: guideID, stepID: stepID)
    }

    func setCompleted(_ isCompleted: Bool, guideID: String, stepID: String) {
        if isCompleted {
            setResult(.passed, note: nil, guideID: guideID, stepID: stepID)
        } else {
            removeResult(guideID: guideID, stepID: stepID)
        }
    }

    func setResult(
        _ status: KanbanTestingGuideStepStatus,
        note: String? = nil,
        guideID: String,
        stepID: String
    ) {
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNote = trimmedNote?.isEmpty == false ? trimmedNote : nil
        var guideResults = stepResultsByGuide[guideID, default: [:]]
        guideResults[stepID] = KanbanTestingGuideStepResult(
            status: status,
            note: normalizedNote,
            updatedAt: Date()
        )
        stepResultsByGuide[guideID] = guideResults

        var completedStepIDs = completedStepIDsByGuide[guideID, default: []]
        if status == .passed {
            completedStepIDs.insert(stepID)
        } else {
            completedStepIDs.remove(stepID)
        }
        setCompletedStepIDs(completedStepIDs, guideID: guideID)
    }

    func removeResult(guideID: String, stepID: String) {
        var guideResults = stepResultsByGuide[guideID, default: [:]]
        guideResults.removeValue(forKey: stepID)
        if guideResults.isEmpty {
            stepResultsByGuide.removeValue(forKey: guideID)
        } else {
            stepResultsByGuide[guideID] = guideResults
        }

        var completedStepIDs = completedStepIDsByGuide[guideID, default: []]
        completedStepIDs.remove(stepID)
        setCompletedStepIDs(completedStepIDs, guideID: guideID)
    }

    func completedCount(guideID: String, steps: [KanbanTestingGuideStep]) -> Int {
        steps.filter { isCompleted(guideID: guideID, stepID: $0.id) }.count
    }

    func failedCount(guideID: String, steps: [KanbanTestingGuideStep]) -> Int {
        steps.filter { result(guideID: guideID, stepID: $0.id)?.status == .failed }.count
    }

    private func setCompletedStepIDs(_ completedStepIDs: Set<String>, guideID: String) {
        if completedStepIDs.isEmpty {
            completedStepIDsByGuide.removeValue(forKey: guideID)
        } else {
            completedStepIDsByGuide[guideID] = completedStepIDs
        }
    }

    private func persistCompletedStepIDs() {
        let payload = completedStepIDsByGuide.mapValues { Array($0).sorted() }
        defaults.set(payload, forKey: defaultsKey)
    }

    private func persistStepResults() {
        guard let data = try? JSONEncoder().encode(stepResultsByGuide) else { return }
        defaults.set(data, forKey: resultsDefaultsKey)
    }

    private func persistOverallNotes() {
        defaults.set(overallNotesByGuide, forKey: overallNotesDefaultsKey)
    }

    private func migrateCompletedStepsIntoResults() {
        var migrated = stepResultsByGuide
        var didMigrate = false
        for (guideID, stepIDs) in completedStepIDsByGuide {
            var guideResults = migrated[guideID, default: [:]]
            for stepID in stepIDs where guideResults[stepID] == nil {
                guideResults[stepID] = KanbanTestingGuideStepResult(status: .passed, note: nil, updatedAt: Date())
                didMigrate = true
            }
            migrated[guideID] = guideResults
        }
        if didMigrate {
            stepResultsByGuide = migrated
        }
    }

    private static func loadCompletedStepIDs(from defaults: UserDefaults, key: String) -> [String: Set<String>] {
        guard let payload = defaults.dictionary(forKey: key) as? [String: [String]] else {
            return [:]
        }
        return payload.mapValues(Set.init)
    }

    private static func loadStepResults(from defaults: UserDefaults, key: String) -> [String: [String: KanbanTestingGuideStepResult]] {
        guard let data = defaults.data(forKey: key),
              let payload = try? JSONDecoder().decode([String: [String: KanbanTestingGuideStepResult]].self, from: data) else {
            return [:]
        }
        return payload
    }

    private static func loadOverallNotes(from defaults: UserDefaults, key: String) -> [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }
}

enum KanbanTestingGuideCardResultSync {
    @MainActor
    static func record(
        payload: KanbanTestingGuidePanelPayload,
        step: KanbanTestingGuideStep,
        stepIndex: Int,
        status: KanbanTestingGuideStepStatus?,
        note: String?
    ) {
        guard let detail = KanbanStorage.shared.findCard(id: payload.cardID),
              detail.board.id == payload.boardID else { return }

        var card = detail.card
        let currentResults = KanbanTestingGuideProgressStore.sharedResults(
            guideID: payload.id,
            steps: payload.steps
        )
        let results = resultsByApplying(
            currentResults,
            step: step,
            status: status,
            note: note
        )
        let body = qaResultsBody(steps: payload.steps, results: results)
        let findingsBody = qaFindingsBody(
            steps: payload.steps,
            results: results,
            overallNote: KanbanTestingGuideProgressStore.sharedOverallNote(guideID: payload.id)
        )
        card.notes = KanbanCardSectionParser.updatingSection(in: card.notes, title: "QA Results", body: body)
        card.notes = KanbanCardSectionParser.updatingSection(in: card.notes, title: "QA Findings", body: findingsBody)
        KanbanStorage.shared.updateCard(boardID: payload.boardID, card: card)
    }

    @MainActor
    static func recordOverallNote(payload: KanbanTestingGuidePanelPayload, note: String?) {
        guard let detail = KanbanStorage.shared.findCard(id: payload.cardID),
              detail.board.id == payload.boardID else { return }

        var card = detail.card
        let currentResults = KanbanTestingGuideProgressStore.sharedResults(
            guideID: payload.id,
            steps: payload.steps
        )
        let findingsBody = qaFindingsBody(steps: payload.steps, results: currentResults, overallNote: note)
        card.notes = KanbanCardSectionParser.updatingSection(in: card.notes, title: "QA Findings", body: findingsBody)
        KanbanStorage.shared.updateCard(boardID: payload.boardID, card: card)
    }

    static func resultsByApplying(
        _ existing: [String: KanbanTestingGuideStepResult],
        step: KanbanTestingGuideStep,
        status: KanbanTestingGuideStepStatus?,
        note: String?
    ) -> [String: KanbanTestingGuideStepResult] {
        var results = existing
        guard let status else {
            results.removeValue(forKey: step.id)
            return results
        }

        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        results[step.id] = KanbanTestingGuideStepResult(
            status: status,
            note: trimmedNote?.isEmpty == false ? trimmedNote : nil,
            updatedAt: Date()
        )
        return results
    }

    static func qaResultsBody(
        steps: [KanbanTestingGuideStep],
        results: [String: KanbanTestingGuideStepResult]
    ) -> String {
        steps.enumerated().compactMap { index, step -> String? in
            guard let result = results[step.id] else { return nil }
            let status = result.status == .passed ? "passed" : "failed"
            var line = "- Step \(index + 1) \(status): \(step.text)"
            let trimmedNote = result.note?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let note = trimmedNote, !note.isEmpty {
                line += " Note: \(note)"
            }
            return line
        }
        .joined(separator: "\n")
    }

    static func qaFindingsBody(
        steps: [KanbanTestingGuideStep],
        results: [String: KanbanTestingGuideStepResult],
        overallNote: String?
    ) -> String {
        var sections: [String] = []
        let failedLines = steps.enumerated().compactMap { index, step -> String? in
            guard let result = results[step.id], result.status == .failed else { return nil }
            var line = "- Step \(index + 1) failed: \(step.text)"
            let trimmedNote = result.note?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let note = trimmedNote, !note.isEmpty {
                line += " Note: \(note)"
            }
            return line
        }
        if !failedLines.isEmpty {
            sections.append((["Failed steps:"] + failedLines).joined(separator: "\n"))
        }

        let trimmedOverallNote = overallNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedOverallNote, !trimmedOverallNote.isEmpty {
            sections.append("Overall QA notes:\n\(trimmedOverallNote)")
        }

        return sections.joined(separator: "\n\n")
    }
}

private extension KanbanTestingGuideProgressStore {
    static func sharedResults(
        guideID: String,
        steps: [KanbanTestingGuideStep]
    ) -> [String: KanbanTestingGuideStepResult] {
        Dictionary(uniqueKeysWithValues: steps.compactMap { step in
            guard let result = shared.result(guideID: guideID, stepID: step.id) else { return nil }
            return (step.id, result)
        })
    }

    static func sharedOverallNote(guideID: String) -> String? {
        shared.overallNote(guideID: guideID)
    }
}
