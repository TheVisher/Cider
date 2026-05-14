import Foundation

struct KanbanCardDashboardEntry: Identifiable, Equatable {
    var id: String
    var title: String
    var body: String
    var dateLabel: String?
    var source: String?
}

struct KanbanCardAgentContext: Equatable {
    var notes: String
    var updateTargets: [String]

    func commands(board: String = "<board>", cardID: String = "<card-id>") -> [String] {
        [
            "cider-cli board recent \(board) --limit 20 --json",
            "cider-cli board card inspect \(board) --card \(cardID) --json",
            "cider-cli item get card \(cardID) --json",
            "cider-cli board section update \(board) --card \(cardID) --section \"Current State\" --value \"...\" --json",
            "cider-cli board history add \(board) --card \(cardID) --type implementation --text \"...\" --source \"...\" --json",
            "cider-cli board evidence add \(board) --card \(cardID) --text \"...\" --source \"...\" --json",
        ]
    }
}

struct KanbanCardDashboardModel: Equatable {
    var title: String
    var hasStructuredContent: Bool
    var sections: [KanbanCardSection]
    var currentState: String?
    var problem: String?
    var goal: String?
    var scope: String?
    var nextStep: String?
    var openLoops: [KanbanCardDashboardEntry]
    var decisions: [KanbanCardDashboardEntry]
    var historyEntries: [KanbanCardDashboardEntry]
    var evidenceEntries: [KanbanCardDashboardEntry]
    var relatedItems: [KanbanCardDashboardEntry]
    var agentContext: KanbanCardAgentContext
    var missingCoreSections: [String]
    var fallbackSummary: String

    init(title: String, notes: String?) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedSections = KanbanCardSectionParser.sections(from: notes)
        sections = parsedSections
        hasStructuredContent = !parsedSections.isEmpty

        currentState = Self.firstBody(in: parsedSections, matching: Self.currentStateKeys)
        problem = Self.firstBody(in: parsedSections, matching: ["problem"])
        goal = Self.firstBody(in: parsedSections, matching: ["goal"])
        scope = Self.firstBody(in: parsedSections, matching: Self.scopeKeys)
        nextStep = Self.firstActionLine(in: parsedSections, matching: Self.nextStepKeys)
        decisions = Self.entries(from: parsedSections, matching: Self.decisionKeys, fallbackTitle: "Decision")
        historyEntries = Self.evidenceEntries(from: parsedSections.filter { Self.historyKeys.contains($0.key) })
        evidenceEntries = Self.evidenceEntries(from: parsedSections)
        relatedItems = Self.entries(from: parsedSections, matching: Self.relatedKeys, fallbackTitle: "Related")
        openLoops = Self.openLoopEntries(from: parsedSections)
        agentContext = Self.agentContext(from: parsedSections)

        missingCoreSections = [
            ("Current State", currentState),
            ("Problem", problem),
            ("Goal", goal),
            ("Scope", scope),
            ("Next Step", nextStep),
        ].compactMap { label, value in
            value?.isEmpty == false ? nil : label
        }

        fallbackSummary = Self.fallbackSummary(title: self.title, sections: parsedSections, notes: notes)
    }

    private static func firstBody(in sections: [KanbanCardSection], matching keys: Set<String>) -> String? {
        sections.first { keys.contains($0.key) }?.body.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private static func entries(
        from sections: [KanbanCardSection],
        matching keys: Set<String>,
        fallbackTitle: String
    ) -> [KanbanCardDashboardEntry] {
        sections
            .filter { keys.contains($0.key) }
            .flatMap { section -> [KanbanCardDashboardEntry] in
                let lines = actionLines(from: section.body)
                if lines.isEmpty {
                    return [
                        KanbanCardDashboardEntry(
                            id: section.key,
                            title: section.title.isEmpty ? fallbackTitle : section.title,
                            body: section.body,
                            dateLabel: nil,
                            source: nil
                        ),
                    ]
                }
                return lines.enumerated().map { index, line in
                    KanbanCardDashboardEntry(
                        id: "\(section.key)-\(index)",
                        title: section.title.isEmpty ? fallbackTitle : section.title,
                        body: line,
                        dateLabel: nil,
                        source: nil
                    )
                }
            }
    }

    private static func evidenceEntries(from sections: [KanbanCardSection]) -> [KanbanCardDashboardEntry] {
        sections
            .filter { evidenceKeys.contains($0.key) }
            .flatMap { section in
                let lines = actionLines(from: section.body)
                let sourceLines = lines.isEmpty ? [section.body.trimmingCharacters(in: .whitespacesAndNewlines)] : lines
                return sourceLines.enumerated().compactMap { index, rawLine -> KanbanCardDashboardEntry? in
                    let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !line.isEmpty else { return nil }
                    let parsed = parseEvidenceLine(line)
                    return KanbanCardDashboardEntry(
                        id: "\(section.key)-\(index)",
                        title: section.title,
                        body: parsed.body,
                        dateLabel: parsed.dateLabel,
                        source: parsed.source
                    )
                }
            }
    }

    private static func openLoopEntries(from sections: [KanbanCardSection]) -> [KanbanCardDashboardEntry] {
        var loops = entries(from: sections, matching: openLoopKeys, fallbackTitle: "Open Loop")

        for section in sections where planKeys.contains(section.key) {
            let lines = actionLines(from: section.body)
                .filter { !isCompletedTaskLine($0) }
            loops.append(
                contentsOf: lines.enumerated().map { index, line in
                    KanbanCardDashboardEntry(
                        id: "\(section.key)-plan-\(index)",
                        title: "Plan step",
                        body: line,
                        dateLabel: nil,
                        source: nil
                    )
                }
            )
        }

        let uncheckedTasks = sections.flatMap { section in
            section.body.components(separatedBy: .newlines).compactMap { line -> KanbanCardDashboardEntry? in
                let stripped = line.trimmingCharacters(in: .whitespaces)
                guard stripped.hasPrefix("- [ ] ") || stripped.hasPrefix("* [ ] ") else { return nil }
                let body = String(stripped.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                guard !body.isEmpty else { return nil }
                return KanbanCardDashboardEntry(
                    id: "\(section.key)-task-\(body.hashValue)",
                    title: "Unchecked task",
                    body: body,
                    dateLabel: nil,
                    source: nil
                )
            }
        }
        loops.append(contentsOf: uncheckedTasks)

        var seen: Set<String> = []
        return loops.filter { entry in
            let key = entry.body.lowercased()
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private static func firstActionLine(in sections: [KanbanCardSection], matching keys: Set<String>) -> String? {
        for section in sections where keys.contains(section.key) {
            if let first = actionLines(from: section.body).first {
                return first
            }
            if let body = section.body.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
                return body
            }
        }
        return nil
    }

    private static func actionLines(from body: String) -> [String] {
        body.components(separatedBy: .newlines).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces).nilIfEmpty
            }
            if let range = line.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                return String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces).nilIfEmpty
            }
            return nil
        }
    }

    private static func isCompletedTaskLine(_ line: String) -> Bool {
        line.hasPrefix("[x] ") || line.hasPrefix("[X] ")
    }

    private static func parseEvidenceLine(_ line: String) -> (dateLabel: String?, body: String, source: String?) {
        var body = line
        var dateLabel: String?
        var source: String?

        if body.count >= 19 {
            let prefix = String(body.prefix(16))
            let separatorStart = body.index(body.startIndex, offsetBy: 16)
            if prefix.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$"#, options: .regularExpression) != nil,
               body[separatorStart...].hasPrefix(" - ") {
                dateLabel = prefix
                body = String(body.dropFirst(19))
            }
        }

        if let range = body.range(of: #"\s+\(source:\s*([^)]+)\)$"#, options: .regularExpression) {
            let suffix = String(body[range])
            source = suffix
                .replacingOccurrences(of: "(source:", with: "")
                .replacingOccurrences(of: ")", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            body.removeSubrange(range)
        }

        return (dateLabel, body.trimmingCharacters(in: .whitespacesAndNewlines), source?.nilIfEmpty)
    }

    private static func agentContext(from sections: [KanbanCardSection]) -> KanbanCardAgentContext {
        let notes = firstBody(in: sections, matching: agentContextKeys)
            ?? "Future agents should update this card through Cider CLI commands. Put implementation summaries in Implementation History, failed attempts in Failed Attempts, verification in Test Evidence, durable decisions in Decisions, and current status in Current State."
        return KanbanCardAgentContext(
            notes: notes,
            updateTargets: ["Current State", "Implementation History", "Failed Attempts", "Decisions", "Test Evidence", "Agent Handoff"]
        )
    }

    private static func fallbackSummary(title: String, sections: [KanbanCardSection], notes: String?) -> String {
        if let problem = firstBody(in: sections, matching: ["problem"]) {
            return problem
        }
        if let first = sections.first?.body.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            return first
        }
        return notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? (title.isEmpty ? "This card has no notes yet." : title)
    }

    private static let currentStateKeys: Set<String> = [
        "current_state",
        "status",
        "latest_verification_snapshot",
        "now",
    ]
    private static let scopeKeys: Set<String> = [
        "scope",
        "mvp_scope",
        "acceptance_criteria",
    ]
    private static let nextStepKeys: Set<String> = [
        "next_step",
        "next_steps",
        "next_action",
        "next_actions",
    ]
    private static let decisionKeys: Set<String> = [
        "decision",
        "decisions",
        "research_conclusion",
        "architecture_decisions",
    ]
    private static let evidenceKeys: Set<String> = [
        "evidence",
        "test_evidence",
        "implementation_evidence",
        "implementation_history",
        "verification",
        "latest_verification_snapshot",
        "failed_attempts",
    ]
    private static let historyKeys: Set<String> = [
        "implementation_history",
        "failed_attempts",
    ]
    private static let openLoopKeys: Set<String> = [
        "open_loop",
        "open_loops",
        "unresolved",
        "blockers",
        "questions",
        "follow_up",
        "follow_ups",
        "todo",
        "todos",
    ]
    private static let planKeys: Set<String> = [
        "phased_implementation_plan",
        "implementation_plan",
        "plan",
    ]
    private static let relatedKeys: Set<String> = [
        "related",
        "related_cards",
        "related_existing_cards",
        "parent",
        "parent_source_card",
        "source_card",
        "docs_backlink",
        "links",
    ]
    private static let agentContextKeys: Set<String> = [
        "agent_context",
        "agent_handoff",
        "handoff",
        "agent_notes",
    ]
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
