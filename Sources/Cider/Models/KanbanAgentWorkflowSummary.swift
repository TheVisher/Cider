import Foundation

/// Deterministic board projection for agent-driven implementation / testing loops.
///
/// This does not create a scheduler or spawn agents. It gives Cider, CLI, and future UI
/// surfaces one shared way to answer: what is ready to pick up, what is in progress,
/// what needs review, what needs a fix, and what is already complete?
struct KanbanAgentWorkflowSummary: Equatable, Sendable {
    struct LaneSummary: Equatable, Sendable {
        var role: KanbanAgentWorkflowRole
        var columnID: String
        var columnName: String
        var cards: [KanbanCard]

        var count: Int { cards.count }
    }

    var boardID: String
    var boardName: String
    var laneSummaries: [LaneSummary]

    init(board: KanbanBoard) {
        boardID = board.id
        boardName = board.name
        laneSummaries = board.columns.compactMap { column in
            guard let role = KanbanAgentWorkflowRole(column: column) else { return nil }
            return LaneSummary(
                role: role,
                columnID: column.id,
                columnName: column.name,
                cards: column.cards
            )
        }
    }

    var nextImplementationCards: [KanbanCard] {
        cards(for: .implementationQueue)
    }

    var backlogCards: [KanbanCard] {
        cards(for: .backlog)
    }

    var activeAgentCards: [KanbanCard] {
        cards(for: .inProgress)
    }

    var testingCards: [KanbanCard] {
        cards(for: .testing)
    }

    var needsFixCards: [KanbanCard] {
        cards(for: .needsFix)
    }

    var completedCards: [KanbanCard] {
        cards(for: .done)
    }

    var agentNames: [String] {
        let names = laneSummaries
            .flatMap(\.cards)
            .compactMap { $0.agent?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(names)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func cards(for role: KanbanAgentWorkflowRole) -> [KanbanCard] {
        laneSummaries
            .filter { $0.role == role }
            .flatMap(\.cards)
    }
}

struct KanbanTestingTriageSummary: Equatable, Sendable {
    struct Item: Equatable, Identifiable, Sendable {
        var id: String { card.id }
        var card: KanbanCard
        var columnID: String
        var columnName: String
        var owner: KanbanTestingOwner
        var reason: String
        var whatChanged: [String]
        var testEvidence: [String]
        var agentVerificationSteps: [String]
        var manualQASteps: [String]
        var failedQASteps: [String]
        var parentTitle: String?
    }

    var boardID: String
    var boardName: String
    var items: [Item]

    init(board: KanbanBoard) {
        boardID = board.id
        boardName = board.name
        let titleByID = Dictionary(uniqueKeysWithValues: board.columns.flatMap(\.cards).map { ($0.id, $0.title) })
        items = board.columns.flatMap { column -> [Item] in
            guard KanbanAgentWorkflowRole(column: column) == .testing else { return [] }
            return column.cards.map { card in
                let triage = KanbanTestingTriageSummary.triage(card: card)
                return Item(
                    card: card,
                    columnID: column.id,
                    columnName: column.name,
                    owner: triage.owner,
                    reason: triage.reason,
                    whatChanged: triage.whatChanged,
                    testEvidence: triage.testEvidence,
                    agentVerificationSteps: triage.agentVerificationSteps,
                    manualQASteps: triage.manualQASteps,
                    failedQASteps: triage.failedQASteps,
                    parentTitle: card.parentCardID.flatMap { titleByID[$0] }
                )
            }
        }
    }

    var needsErik: [Item] { items.filter { $0.owner == .needsErik } }
    var agentCanVerify: [Item] { items.filter { $0.owner == .agentCanVerify } }
    var mixed: [Item] { items.filter { $0.owner == .mixed } }

    private static func triage(card: KanbanCard) -> (owner: KanbanTestingOwner, reason: String, whatChanged: [String], testEvidence: [String], agentVerificationSteps: [String], manualQASteps: [String], failedQASteps: [String]) {
        let notes = card.notes ?? ""
        let haystack = "\(card.title)\n\(notes)".lowercased()
        let qualityReport = KanbanCardQualityReport(notes: notes)
        let hasManualQASection = qualityReport.items.contains { $0.section == .manualQAGuidance && $0.isPresent }
        let hasTestEvidenceSection = qualityReport.items.contains { $0.section == .testEvidence && $0.isPresent }
        let whatChanged = extractListEntries(from: notes, headings: ["what changed", "changes", "implementation notes", "implementation summary", "completion summary"])
        let testEvidence = extractListEntries(from: notes, headings: ["test evidence", "tests", "verification", "automated evidence", "build/qa evidence"])
        let agentVerificationSteps = extractListEntries(from: notes, headings: ["agent verification", "agent can verify", "automated verification", "agent qa"])
        let manualSteps = extractListEntries(from: notes, headings: ["manual qa guidance", "manual qa", "manual testing", "what to test"])
        let failedQASteps = failedQASteps(in: notes)

        let manualSignals = [
            "manual qa", "manual testing", "needs erik", "erik should", "visual", "visually",
            "feel", "jank", "resize", "drag", "click", "open the app", "launch", "screenshot",
            "window", "sidebar", "dashboard", "card detail", "confirm"
        ]
        let agentSignals = [
            "swift test", "tests:", "test evidence", "build complete", "build:", "cli", "json",
            "doctor", "snapshot", "agent can verify", "model-only", "backend-only", "codable", "round trip"
        ]
        let hasManualSignal = hasManualQASection || manualSignals.contains { haystack.contains($0) }
        let hasAgentSignal = hasTestEvidenceSection || !testEvidence.isEmpty || !agentVerificationSteps.isEmpty || agentSignals.contains { haystack.contains($0) }

        if !failedQASteps.isEmpty {
            return (.agentCanVerify, "Manual QA failed; an agent should inspect and fix before asking Erik to retest.", whatChanged, testEvidence, agentVerificationSteps, manualSteps, failedQASteps)
        }
        if hasManualSignal && hasAgentSignal {
            return (.mixed, "Has manual/product QA guidance plus agent-verifiable test or build evidence.", whatChanged, testEvidence, agentVerificationSteps, manualSteps, failedQASteps)
        }
        if hasManualSignal {
            return (.needsErik, "Needs visual/manual product judgment that an agent cannot fully verify.", whatChanged, testEvidence, agentVerificationSteps, manualSteps, failedQASteps)
        }
        if hasAgentSignal {
            return (.agentCanVerify, "Looks verifiable through CLI/tests/build evidence without Erik at the Mac.", whatChanged, testEvidence, agentVerificationSteps, manualSteps, failedQASteps)
        }
        return (.mixed, "No clear QA evidence or manual guidance found; needs an agent pass to classify before asking Erik.", whatChanged, testEvidence, agentVerificationSteps, manualSteps, failedQASteps)
    }

    private static func extractListEntries(from notes: String, headings: [String]) -> [String] {
        let lines = notes.components(separatedBy: .newlines)
        var steps: [String] = []
        var collecting = false

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = normalizedHeading(trimmed)

            if headings.contains(where: { normalized == $0 || normalized.hasPrefix($0 + " ") }) {
                collecting = true
                continue
            }

            if collecting, trimmed.hasPrefix("#") {
                break
            }

            if collecting, !trimmed.isEmpty {
                let step = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "-•* "))
                if !step.isEmpty { steps.append(step) }
            }
        }

        return Array(steps.prefix(5))
    }

    static func failedQASteps(in notes: String) -> [String] {
        extractListEntries(from: notes, headings: ["qa results", "testing results", "manual qa results"])
            .filter(isFailedQAResultLine)
    }

    private static func isFailedQAResultLine(_ line: String) -> Bool {
        let normalized = line
            .trimmingCharacters(in: CharacterSet(charactersIn: "-•* "))
            .lowercased()
        if normalized.range(of: #"^step\s+\d+\s+failed:"#, options: .regularExpression) != nil {
            return true
        }
        return normalized.hasPrefix("failed:") || normalized.hasPrefix("failed ")
    }

    private static func normalizedHeading(_ line: String) -> String {
        line
            .trimmingCharacters(in: CharacterSet(charactersIn: "#:-–— "))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

struct KanbanParentChildRollup: Equatable, Sendable {
    struct Counts: Equatable, Sendable {
        var backlog = 0
        var queued = 0
        var inProgress = 0
        var testing = 0
        var needsFix = 0
        var done = 0
        var other = 0
    }

    struct Child: Equatable, Identifiable, Sendable {
        var id: String
        var title: String
        var columnID: String
        var columnName: String
        var role: KanbanParentChildRole
        var failedQASteps: [String]

        var hasFailedQA: Bool { !failedQASteps.isEmpty }
    }

    var parentID: String
    var children: [Child]
    var counts: Counts

    init?(board: KanbanBoard, parentID: String) {
        let childCards = board.childCards(of: parentID)
        guard !childCards.isEmpty else { return nil }

        self.parentID = parentID
        children = board.columns.flatMap { column in
            column.cards.compactMap { card -> Child? in
                guard card.parentCardID == parentID else { return nil }
                return Child(
                    id: card.id,
                    title: card.title,
                    columnID: column.id,
                    columnName: column.name,
                    role: KanbanParentChildRole(column: column),
                    failedQASteps: KanbanTestingTriageSummary.failedQASteps(in: card.notes ?? "")
                )
            }
        }

        counts = children.reduce(into: Counts()) { partial, child in
            switch child.role {
            case .backlog: partial.backlog += 1
            case .queued: partial.queued += 1
            case .inProgress: partial.inProgress += 1
            case .testing: partial.testing += 1
            case .needsFix: partial.needsFix += 1
            case .done: partial.done += 1
            case .other: partial.other += 1
            }
        }
    }

    var totalChildCount: Int { children.count }
    var isComplete: Bool { totalChildCount > 0 && counts.done == totalChildCount }

    var failedQAChild: Child? {
        children.first { $0.hasFailedQA }
    }

    var blockedChild: Child? {
        children.first { $0.role == .needsFix }
    }

    var testingChild: Child? {
        children.first { $0.role == .testing }
    }

    var activeChild: Child? {
        children.first { $0.role == .inProgress }
    }

    var nextQueuedChild: Child? {
        children.first { $0.role == .queued }
    }

    var backlogChild: Child? {
        children.first { $0.role == .backlog }
    }

    var currentGate: Child? {
        failedQAChild ?? blockedChild ?? testingChild ?? activeChild ?? nextQueuedChild ?? backlogChild
    }

    var nextActionableChild: Child? {
        currentGate
    }

    var statusLine: String {
        let parts: [String] = [
            formattedCount(counts.backlog, singular: "backlog"),
            formattedCount(counts.queued, singular: "queued"),
            formattedCount(counts.inProgress, singular: "in progress"),
            formattedCount(counts.testing, singular: "testing"),
            formattedCount(counts.needsFix, singular: "needs fix"),
            formattedCount(counts.done, singular: "done"),
            formattedCount(counts.other, singular: "other"),
        ].compactMap { $0 }
        let childLabel = totalChildCount == 1 ? "child" : "children"
        return "\(totalChildCount) \(childLabel): \(parts.joined(separator: ", "))."
    }

    var nextActionLine: String {
        if let failedQAChild {
            return "Fix failed QA on \(failedQAChild.title)."
        }
        if let blockedChild {
            return "Resolve \(blockedChild.title)."
        }
        if let testingChild {
            return "Finish testing \(testingChild.title)."
        }
        if let activeChild {
            return "Continue \(activeChild.title)."
        }
        if let nextQueuedChild {
            return "Start \(nextQueuedChild.title)."
        }
        if let backlogChild {
            return "Queue \(backlogChild.title)."
        }
        return "All child cards are done."
    }

    private func formattedCount(_ count: Int, singular: String) -> String? {
        count > 0 ? "\(count) \(singular)" : nil
    }
}

struct KanbanRoadmapNextUpProjection: Equatable, Sendable {
    struct SequenceItem: Equatable, Identifiable, Sendable {
        var id: String
        var title: String
        var columnID: String
        var columnName: String
        var role: KanbanParentChildRole
        var stepNumber: Int
        var stepCount: Int
        var isCurrentGate: Bool
        var isNextActionable: Bool
        var hasFailedQA: Bool
        var failedQASteps: [String]
    }

    struct SuggestedInsertion: Equatable, Sendable {
        var parentID: String
        var columnID: String
        var columnName: String
        var afterChildID: String?
        var command: String
        var reason: String
    }

    var parentID: String
    var sequence: [SequenceItem]
    var currentGate: SequenceItem?
    var nextActionableChild: SequenceItem?
    var nextActionLine: String
    var suggestedInsertion: SuggestedInsertion

    init?(board: KanbanBoard, parentID: String) {
        guard let rollup = KanbanParentChildRollup(board: board, parentID: parentID) else { return nil }

        self.parentID = parentID
        nextActionLine = rollup.nextActionLine
        let currentGateID = rollup.currentGate?.id
        let nextActionableID = rollup.nextActionableChild?.id
        let stepCount = rollup.children.count
        sequence = rollup.children.enumerated().map { index, child in
            SequenceItem(
                id: child.id,
                title: child.title,
                columnID: child.columnID,
                columnName: child.columnName,
                role: child.role,
                stepNumber: index + 1,
                stepCount: stepCount,
                isCurrentGate: child.id == currentGateID,
                isNextActionable: child.id == nextActionableID,
                hasFailedQA: child.hasFailedQA,
                failedQASteps: child.failedQASteps
            )
        }
        currentGate = sequence.first { $0.isCurrentGate }
        nextActionableChild = sequence.first { $0.isNextActionable }
        suggestedInsertion = Self.suggestedInsertion(
            board: board,
            parentID: parentID,
            rollup: rollup,
            sequence: sequence
        )
    }

    private static func suggestedInsertion(
        board: KanbanBoard,
        parentID: String,
        rollup: KanbanParentChildRollup,
        sequence: [SequenceItem]
    ) -> SuggestedInsertion {
        let targetChild = rollup.nextActionableChild ?? rollup.nextQueuedChild ?? rollup.backlogChild ?? rollup.children.first
        let queuedColumn = board.columns.first { KanbanParentChildRole(column: $0) == .queued }
        let fallbackColumn = board.columns.first(where: { !$0.isDoneColumn }) ?? board.columns.first
        let columnID = queuedColumn?.id ?? targetChild?.columnID ?? fallbackColumn?.id ?? "backlog"
        let columnName = queuedColumn?.name ?? targetChild?.columnName ?? fallbackColumn?.name ?? "Backlog"
        let afterChildID = sequence.last?.id
        let command = "cider-cli board add-card \(quoted(board.name)) --column \(quoted(columnName)) --title \"<title>\" --parent \(parentID)"
        let reason = targetChild.map {
            "Adds a child under the same parent near the current roadmap gate: \($0.title)."
        } ?? "Adds the first child under this roadmap parent."

        return SuggestedInsertion(
            parentID: parentID,
            columnID: columnID,
            columnName: columnName,
            afterChildID: afterChildID,
            command: command,
            reason: reason
        )
    }

    private static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

enum KanbanParentChildRole: String, Codable, CaseIterable, Sendable {
    case backlog
    case queued
    case inProgress = "in_progress"
    case testing
    case needsFix = "needs_fix"
    case done
    case other

    init(column: KanbanColumn) {
        if column.isDoneColumn {
            self = .done
            return
        }

        let normalized = column.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")

        if normalized == "backlog" {
            self = .backlog
        } else if normalized == "queued" || normalized == "queue" {
            self = .queued
        } else if normalized == "in progress" || normalized == "doing" || normalized == "active" {
            self = .inProgress
        } else if normalized == "testing" || normalized == "ready to test" || normalized.contains("testing") {
            self = .testing
        } else if normalized == "needs fix" || normalized == "blocked" || normalized.contains("needs fix") {
            self = .needsFix
        } else {
            self = .other
        }
    }
}

enum KanbanTestingOwner: String, Codable, CaseIterable, Sendable {
    case needsErik = "needs_erik"
    case agentCanVerify = "agent_can_verify"
    case mixed

    var displayName: String {
        switch self {
        case .needsErik: "Needs Erik"
        case .agentCanVerify: "Agent can verify"
        case .mixed: "Mixed / needs triage"
        }
    }
}

enum KanbanAgentWorkflowRole: String, Codable, CaseIterable, Sendable {
    case backlog
    case implementationQueue = "implementation_queue"
    case inProgress = "in_progress"
    case testing = "testing"
    case needsFix = "needs_fix"
    case done = "done"

    init?(column: KanbanColumn) {
        if column.isDoneColumn {
            self = .done
            return
        }

        let haystack = "\(column.id) \(column.name)"
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        if haystack.contains("needs_fix") || haystack.contains("fix") || haystack.contains("bug") {
            self = .needsFix
        } else if haystack.contains("testing") || haystack.contains("ready_to_test") || haystack.contains("qa") || haystack.contains("review") {
            self = .testing
        } else if haystack.contains("in_progress") || haystack.contains("active") || haystack.contains("doing") {
            self = .inProgress
        } else if haystack.contains("queued") || haystack.contains("ready") || haystack.contains("next") {
            self = .implementationQueue
        } else if haystack.contains("backlog") {
            self = .backlog
        } else {
            return nil
        }
    }
}
