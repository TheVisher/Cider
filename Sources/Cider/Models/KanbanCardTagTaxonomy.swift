import Foundation

/// Shared Kanban tag conventions for agent-readable feature history.
///
/// Tags remain plain strings on cards for compatibility, but this helper keeps
/// the small core workflow vocabulary deterministic and gives CLI/UI surfaces a
/// single normalization/filtering rule.
enum KanbanCardTagTaxonomy {
    static let coreTags: [String] = [
        "bug",
        "fix",
        "feature",
        "improvement",
        "qa",
        "docs",
        "design",
        "refactor",
        "spike",
        "agent-handoff",
        "blocked",
        "follow-up",
    ]

    static func normalized(_ tag: String) -> String {
        tag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    static func normalizedTags(from values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            for part in value.split(separator: ",") {
                let tag = normalized(String(part))
                guard !tag.isEmpty, !seen.contains(tag) else { continue }
                seen.insert(tag)
                result.append(tag)
            }
        }
        return result
    }

    static func isCoreTag(_ tag: String) -> Bool {
        coreTags.contains(normalized(tag))
    }

    static func card(_ card: KanbanCard, matchesAll tags: [String]) -> Bool {
        let normalizedFilters = normalizedTags(from: tags)
        guard !normalizedFilters.isEmpty else { return true }
        let cardTags = Set(normalizedTags(from: card.tags))
        return normalizedFilters.allSatisfy { cardTags.contains($0) }
    }
}

extension KanbanBoard {
    func filteredByTags(_ tags: [String]) -> KanbanBoard {
        let normalizedFilters = KanbanCardTagTaxonomy.normalizedTags(from: tags)
        guard !normalizedFilters.isEmpty else { return self }

        var copy = self
        copy.columns = columns.map { column in
            var filteredColumn = column
            filteredColumn.cards = column.cards.filter { card in
                KanbanCardTagTaxonomy.card(card, matchesAll: normalizedFilters)
            }
            return filteredColumn
        }
        return copy
    }
}
