import Foundation

/// Deterministic, non-blocking readiness hints for Kanban cards.
///
/// The checklist intentionally uses simple heading/label heuristics. It helps agents
/// improve handoffs without enforcing a rigid template or generating content.
struct KanbanCardQualityReport: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case ready
        case needsContext
    }

    struct Item: Identifiable, Equatable, Sendable {
        var section: KanbanCardQualitySection
        var isPresent: Bool

        var id: String { section.rawValue }
    }

    var items: [Item]

    init(notes: String) {
        let normalized = KanbanCardQualityReport.normalizedLines(from: notes)
        items = KanbanCardQualitySection.allCases.map { section in
            Item(section: section, isPresent: section.matches(in: normalized))
        }
    }

    var status: Status {
        missingEssentials.isEmpty ? .ready : .needsContext
    }

    var presentEssentials: [Item] {
        items.filter { $0.section.isEssential && $0.isPresent }
    }

    var missingEssentials: [Item] {
        items.filter { $0.section.isEssential && !$0.isPresent }
    }

    var presentRecommended: [Item] {
        items.filter { !$0.section.isEssential && $0.isPresent }
    }

    var missingRecommended: [Item] {
        items.filter { !$0.section.isEssential && !$0.isPresent }
    }

    var summary: String {
        if missingEssentials.isEmpty {
            return "Agent-ready context present"
        }
        return "Needs context: " + missingEssentials.map { $0.section.displayName }.joined(separator: ", ")
    }

    private static func normalizedLines(from notes: String) -> [String] {
        notes
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "#-*•[]✓✅☑️ "))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }
            .filter { !$0.isEmpty }
    }
}

enum KanbanCardQualitySection: String, CaseIterable, Sendable {
    case currentState
    case problem
    case goal
    case mvpScope
    case nextStep
    case acceptanceCriteria
    case testEvidence
    case manualQAGuidance
    case followUp

    var displayName: String {
        switch self {
        case .currentState: "Current State"
        case .problem: "Problem"
        case .goal: "Goal"
        case .mvpScope: "MVP scope"
        case .nextStep: "Next Step"
        case .acceptanceCriteria: "Acceptance criteria"
        case .testEvidence: "Test evidence"
        case .manualQAGuidance: "Manual QA guidance"
        case .followUp: "Follow-up"
        }
    }

    var isEssential: Bool {
        switch self {
        case .currentState, .problem, .goal, .mvpScope, .nextStep, .acceptanceCriteria:
            return true
        case .testEvidence, .manualQAGuidance, .followUp:
            return false
        }
    }

    private var aliases: [String] {
        switch self {
        case .currentState:
            ["current state", "status", "state", "where things stand"]
        case .problem:
            ["problem", "issue", "bug", "context", "why"]
        case .goal:
            ["goal", "desired outcome", "outcome", "objective"]
        case .mvpScope:
            ["mvp scope", "scope", "implementation scope", "mvp"]
        case .nextStep:
            ["next step", "next steps", "next action", "handoff", "agent handoff"]
        case .acceptanceCriteria:
            ["acceptance criteria", "acceptance", "done when", "definition of done"]
        case .testEvidence:
            ["test evidence", "tests", "verification", "evidence"]
        case .manualQAGuidance:
            ["manual qa guidance", "manual qa", "manual testing", "qa guidance", "what to test"]
        case .followUp:
            ["follow-up", "follow up", "next steps", "future"]
        }
    }

    func matches(in normalizedLines: [String]) -> Bool {
        normalizedLines.contains { line in
            let heading = line.trimmingCharacters(in: CharacterSet(charactersIn: ":.-–— "))
            return aliases.contains { alias in
                heading == alias || heading.hasPrefix(alias + ":") || heading.hasPrefix(alias + " -")
            }
        }
    }
}
