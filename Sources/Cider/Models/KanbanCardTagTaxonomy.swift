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

enum KanbanBoardDiscoveryMatchReason: String, Equatable, Sendable {
    case title
    case notes
    case tag
    case comment
    case attachmentType
}

struct KanbanBoardDiscoveryFilter: Equatable, Sendable {
    var query: String
    var tags: [String]
    var attachmentTypes: [KanbanCardCommentAttachmentType]

    init(
        query: String = "",
        tags: [String] = [],
        attachmentTypes: [KanbanCardCommentAttachmentType] = []
    ) {
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tags = KanbanCardTagTaxonomy.normalizedTags(from: tags)
        self.attachmentTypes = Self.uniqueAttachmentTypes(attachmentTypes)
    }

    var isEmpty: Bool {
        query.isEmpty && tags.isEmpty && attachmentTypes.isEmpty
    }

    private static func uniqueAttachmentTypes(_ types: [KanbanCardCommentAttachmentType]) -> [KanbanCardCommentAttachmentType] {
        var seen = Set<KanbanCardCommentAttachmentType>()
        return types.filter { seen.insert($0).inserted }
    }
}

struct KanbanBoardDiscoveryCardMatch: Equatable, Sendable {
    var cardID: String
    var reasons: [KanbanBoardDiscoveryMatchReason]
    var attachmentTypes: [KanbanCardCommentAttachmentType]
    var commentIDs: [String]
    var attachmentIDs: [String]
}

struct KanbanBoardDiscoveryResult: Equatable, Sendable {
    var board: KanbanBoard
    var matchesByCardID: [String: KanbanBoardDiscoveryCardMatch]
}

extension KanbanBoard {
    func filteredForDiscovery(_ filter: KanbanBoardDiscoveryFilter) throws -> KanbanBoardDiscoveryResult {
        guard !filter.isEmpty else {
            return KanbanBoardDiscoveryResult(board: self, matchesByCardID: [:])
        }

        var matchesByCardID: [String: KanbanBoardDiscoveryCardMatch] = [:]
        var copy = self
        copy.columns = columns.map { column in
            var filteredColumn = column
            filteredColumn.cards = column.cards.compactMap { card in
                guard let match = discoveryMatch(for: card, filter: filter) else { return nil }
                matchesByCardID[card.id] = match
                return card
            }
            return filteredColumn
        }
        return KanbanBoardDiscoveryResult(board: copy, matchesByCardID: matchesByCardID)
    }

    private func discoveryMatch(
        for card: KanbanCard,
        filter: KanbanBoardDiscoveryFilter
    ) -> KanbanBoardDiscoveryCardMatch? {
        var reasons: [KanbanBoardDiscoveryMatchReason] = []
        var attachmentTypes: [KanbanCardCommentAttachmentType] = []
        var commentIDs: [String] = []
        var attachmentIDs: [String] = []

        if !filter.tags.isEmpty {
            guard KanbanCardTagTaxonomy.card(card, matchesAll: filter.tags) else { return nil }
            appendUnique(.tag, to: &reasons)
        }

        if !filter.query.isEmpty {
            let query = filter.query
            var queryMatched = false
            if card.title.localizedCaseInsensitiveContains(query) {
                appendUnique(.title, to: &reasons)
                queryMatched = true
            }
            if card.notes?.localizedCaseInsensitiveContains(query) == true {
                appendUnique(.notes, to: &reasons)
                queryMatched = true
            }
            if card.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) }) {
                appendUnique(.tag, to: &reasons)
                queryMatched = true
            }
            if card.comments.contains(where: { $0.body.localizedCaseInsensitiveContains(query) }) {
                appendUnique(.comment, to: &reasons)
                queryMatched = true
            }
            guard queryMatched else { return nil }
        }

        if !filter.attachmentTypes.isEmpty {
            let requestedTypes = Set(filter.attachmentTypes)
            for comment in card.comments {
                let matchingAttachments = comment.attachments.filter { requestedTypes.contains($0.type) }
                guard !matchingAttachments.isEmpty else { continue }
                appendUnique(comment.id, to: &commentIDs)
                for attachment in matchingAttachments {
                    appendUnique(attachment.type, to: &attachmentTypes)
                    appendUnique(attachment.id, to: &attachmentIDs)
                }
            }
            guard !attachmentIDs.isEmpty else { return nil }
            appendUnique(.attachmentType, to: &reasons)
        }

        return KanbanBoardDiscoveryCardMatch(
            cardID: card.id,
            reasons: reasons,
            attachmentTypes: attachmentTypes,
            commentIDs: commentIDs,
            attachmentIDs: attachmentIDs
        )
    }

    private func appendUnique<T: Equatable>(_ value: T, to values: inout [T]) {
        guard !values.contains(value) else { return }
        values.append(value)
    }
}
