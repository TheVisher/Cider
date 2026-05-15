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
                    parentTitle: card.parentCardID.flatMap { titleByID[$0] }
                )
            }
        }
    }

    var needsErik: [Item] { items.filter { $0.owner == .needsErik } }
    var agentCanVerify: [Item] { items.filter { $0.owner == .agentCanVerify } }
    var mixed: [Item] { items.filter { $0.owner == .mixed } }

    private static func triage(card: KanbanCard) -> (owner: KanbanTestingOwner, reason: String, whatChanged: [String], testEvidence: [String], agentVerificationSteps: [String], manualQASteps: [String]) {
        let notes = card.notes ?? ""
        let haystack = "\(card.title)\n\(notes)".lowercased()
        let qualityReport = KanbanCardQualityReport(notes: notes)
        let hasManualQASection = qualityReport.items.contains { $0.section == .manualQAGuidance && $0.isPresent }
        let hasTestEvidenceSection = qualityReport.items.contains { $0.section == .testEvidence && $0.isPresent }
        let whatChanged = extractListEntries(from: notes, headings: ["what changed", "changes", "implementation notes", "implementation summary", "completion summary"])
        let testEvidence = extractListEntries(from: notes, headings: ["test evidence", "tests", "verification", "automated evidence", "build/qa evidence"])
        let agentVerificationSteps = extractListEntries(from: notes, headings: ["agent verification", "agent can verify", "automated verification", "agent qa"])
        let manualSteps = extractListEntries(from: notes, headings: ["manual qa guidance", "manual qa", "manual testing", "what to test"])

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

        if hasManualSignal && hasAgentSignal {
            return (.mixed, "Has manual/product QA guidance plus agent-verifiable test or build evidence.", whatChanged, testEvidence, agentVerificationSteps, manualSteps)
        }
        if hasManualSignal {
            return (.needsErik, "Needs visual/manual product judgment that an agent cannot fully verify.", whatChanged, testEvidence, agentVerificationSteps, manualSteps)
        }
        if hasAgentSignal {
            return (.agentCanVerify, "Looks verifiable through CLI/tests/build evidence without Erik at the Mac.", whatChanged, testEvidence, agentVerificationSteps, manualSteps)
        }
        return (.mixed, "No clear QA evidence or manual guidance found; needs an agent pass to classify before asking Erik.", whatChanged, testEvidence, agentVerificationSteps, manualSteps)
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

    private static func normalizedHeading(_ line: String) -> String {
        line
            .trimmingCharacters(in: CharacterSet(charactersIn: "#:-–— "))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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
