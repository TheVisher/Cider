import Foundation

struct KanbanCardSection: Identifiable, Equatable {
    var id: String { key }
    var key: String
    var title: String
    var body: String
    var sortOrder: Int
}

enum KanbanCardSectionParser {
    static func sections(from notes: String?) -> [KanbanCardSection] {
        let text = normalizedLineBreaks(in: notes ?? "")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let lines = text.components(separatedBy: .newlines)
        var sections: [KanbanCardSection] = []
        var currentTitle = "Notes"
        var currentKey = "notes"
        var currentBody: [String] = []
        var isInsideFence = false

        func flush() {
            let body = currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return }
            appendSection(key: currentKey, title: currentTitle, body: body, to: &sections)
        }

        for line in lines {
            if isFenceDelimiter(line) {
                isInsideFence.toggle()
                currentBody.append(line)
            } else if !isInsideFence, let heading = markdownHeadingTitle(in: line) {
                flush()
                currentTitle = heading
                currentKey = normalizedKey(for: heading)
                currentBody = []
            } else if !isInsideFence, let label = knownLabelHeading(in: line) {
                flush()
                currentTitle = label.title
                currentKey = normalizedKey(for: label.title)
                currentBody = label.initialBody.map { [$0] } ?? []
            } else {
                currentBody.append(line)
            }
        }
        flush()

        return sections
    }

    private static func appendSection(
        key: String,
        title: String,
        body: String,
        to sections: inout [KanbanCardSection]
    ) {
        if let existingIndex = sections.firstIndex(where: { $0.key == key }) {
            let existingBody = sections[existingIndex].body.trimmingCharacters(in: .whitespacesAndNewlines)
            sections[existingIndex].body = [existingBody, body]
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            return
        }

        sections.append(
            KanbanCardSection(
                key: key,
                title: title,
                body: body,
                sortOrder: sections.count
            )
        )
    }

    static func updatingSection(in notes: String?, title: String, body: String) -> String {
        let original = normalizedLineBreaks(in: notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let targetKey = normalizedKey(for: title)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let range = sectionRange(in: original, matching: targetKey) else {
            let addition = "## \(title)\n\(body.trimmingCharacters(in: .whitespacesAndNewlines))"
            return [original, addition]
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        }

        var lines = original.components(separatedBy: .newlines)
        let replacement: [String]
        switch range.kind {
        case .markdownHeading:
            replacement = [lines[range.startLine], trimmedBody]
                .filter { !$0.isEmpty }
        case .plainLabel:
            replacement = ["\(range.title):", trimmedBody]
                .filter { !$0.isEmpty }
        }
        lines.replaceSubrange(range.startLine..<range.endLine, with: replacement)
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func appendingEvidence(to notes: String?, text: String, source: String?, at date: Date = Date()) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        let timestamp = evidenceDateFormatter.string(from: date)
        let sourceSuffix = source.flatMap { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : " (source: \(trimmed))"
        } ?? ""
        let line = "- \(timestamp) - \(trimmedText)\(sourceSuffix)"
        let current = sections(from: notes).first { $0.key == "test_evidence" || $0.key == "evidence" }

        if let current {
            let existingBody = current.body.trimmingCharacters(in: .whitespacesAndNewlines)
            let nextBody = [existingBody, line].filter { !$0.isEmpty }.joined(separator: "\n")
            return updatingSection(in: notes, title: current.title, body: nextBody)
        }

        return updatingSection(in: notes, title: "Test Evidence", body: line)
    }

    static func appendingHistory(
        to notes: String?,
        type: String,
        text: String,
        source: String?,
        at date: Date = Date()
    ) -> String? {
        guard let section = historySection(for: type) else { return nil }
        if section.key == "test_evidence" {
            return appendingEvidence(to: notes, text: text, source: source, at: date)
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        let timestamp = evidenceDateFormatter.string(from: date)
        let sourceSuffix = source.flatMap { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : " (source: \(trimmed))"
        } ?? ""
        let line = "- \(timestamp) - \(trimmedText)\(sourceSuffix)"
        let current = sections(from: notes).first { $0.key == section.key }

        if let current {
            let existingBody = current.body.trimmingCharacters(in: .whitespacesAndNewlines)
            let nextBody = [existingBody, line].filter { !$0.isEmpty }.joined(separator: "\n")
            return updatingSection(in: notes, title: current.title, body: nextBody)
        }

        return updatingSection(in: notes, title: section.title, body: line)
    }

    static let supportedHistoryTypes = [
        "implementation",
        "failed-attempt",
        "test",
        "decision",
        "handoff",
        "commit",
    ]

    static func normalizedKey(for title: String) -> String {
        let scalars = title.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar)
                ? Character(String(scalar).lowercased())
                : "_"
        }
        let collapsed = String(scalars)
            .split(separator: "_")
            .joined(separator: "_")
        return collapsed.isEmpty ? "section" : collapsed
    }

    private static func markdownHeadingTitle(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("##") else { return nil }
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard hashes >= 2 && hashes <= 6 else { return nil }
        let remainder = trimmed.dropFirst(hashes)
        guard remainder.first?.isWhitespace == true else { return nil }
        let title = remainder.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }

    private static func knownLabelHeading(in line: String) -> (title: String, initialBody: String?)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard line == trimmed, let colonIndex = trimmed.firstIndex(of: ":") else { return nil }

        let rawTitle = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
        guard rawTitle.count >= 3, rawTitle.count <= 48 else { return nil }
        guard knownLabelKeys.contains(normalizedKey(for: rawTitle)) else { return nil }

        let remainder = trimmed[trimmed.index(after: colonIndex)...]
            .trimmingCharacters(in: .whitespaces)
        return (rawTitle, remainder.isEmpty ? nil : remainder)
    }

    private static func isFenceDelimiter(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    private enum SectionRangeKind {
        case markdownHeading
        case plainLabel
    }

    private struct SectionRange {
        var title: String
        var startLine: Int
        var endLine: Int
        var kind: SectionRangeKind
    }

    private static func sectionRange(in text: String, matching targetKey: String) -> SectionRange? {
        let lines = normalizedLineBreaks(in: text).components(separatedBy: .newlines)
        var ranges: [SectionRange] = []
        var current: (title: String, key: String, startLine: Int, kind: SectionRangeKind)?
        var isInsideFence = false

        func flush(endingAt endLine: Int) {
            guard let current else { return }
            ranges.append(
                SectionRange(
                    title: current.title,
                    startLine: current.startLine,
                    endLine: endLine,
                    kind: current.kind
                )
            )
        }

        for (index, line) in lines.enumerated() {
            if isFenceDelimiter(line) {
                isInsideFence.toggle()
                continue
            }
            guard !isInsideFence else { continue }

            if let title = markdownHeadingTitle(in: line) {
                flush(endingAt: index)
                current = (title, normalizedKey(for: title), index, .markdownHeading)
            } else if let label = knownLabelHeading(in: line) {
                flush(endingAt: index)
                current = (label.title, normalizedKey(for: label.title), index, .plainLabel)
            }
        }
        flush(endingAt: lines.count)

        return ranges.first { range in
            normalizedKey(for: range.title) == targetKey
        }
    }

    private static func normalizedLineBreaks(in text: String) -> String {
        text
            .replacingOccurrences(of: "\\r\\n", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\r", with: "\n")
    }

    private static func historySection(for rawType: String) -> (key: String, title: String)? {
        switch normalizedKey(for: rawType) {
        case "implementation",
             "implementation_summary",
             "implementation_history",
             "summary",
             "fix",
             "fix_summary":
            return ("implementation_history", "Implementation History")
        case "failed_attempt",
             "failed_attempts",
             "failure",
             "attempt":
            return ("failed_attempts", "Failed Attempts")
        case "test",
             "test_evidence",
             "evidence",
             "verification":
            return ("test_evidence", "Test Evidence")
        case "decision",
             "decisions":
            return ("decisions", "Decisions")
        case "handoff",
             "agent_handoff":
            return ("agent_handoff", "Agent Handoff")
        case "commit",
             "commits",
             "git",
             "git_commit",
             "repo_change",
             "repo_changes":
            return ("commits", "Commits")
        default:
            return nil
        }
    }

    private static let knownLabelKeys: Set<String> = [
        "acceptance_criteria",
        "agent_context",
        "agent_handoff",
        "agent_notes",
        "architecture_decisions",
        "blockers",
        "created",
        "current_state",
        "decision",
        "decisions",
        "deferred",
        "docs_backlink",
        "evidence",
        "failed_attempts",
        "follow_up",
        "follow_ups",
        "follow_up_recommendation",
        "goal",
        "handoff",
        "implementation_evidence",
        "implementation_handoff",
        "implementation_history",
        "implementation_plan",
        "latest_verification_snapshot",
        "links",
        "manual_qa",
        "mvp_scope",
        "next_action",
        "next_actions",
        "next_step",
        "next_steps",
        "non_goals",
        "non_goals_for_this_branch",
        "notes",
        "open_loop",
        "open_loops",
        "parent",
        "parent_source",
        "parent_source_card",
        "phased_implementation_plan",
        "plan",
        "problem",
        "questions",
        "related",
        "related_cards",
        "related_existing_cards",
        "research_conclusion",
        "scope",
        "source_card",
        "test_evidence",
        "todo",
        "todos",
        "unresolved",
        "verification",
        "verification_evidence",
        "visual_flow",
    ]

    private static let evidenceDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
