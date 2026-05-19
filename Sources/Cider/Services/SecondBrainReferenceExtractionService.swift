import Foundation

struct SecondBrainReferenceExtractionResult: Equatable {
    var sourceOwner: SecondBrainOwnerRef
    var surface: String
    var relations: [SecondBrainRelation]
}

@MainActor
final class SecondBrainReferenceExtractionService {
    static let sourcePrefix = "reference_extraction."

    private let store: SecondBrainStore
    private let notesStorage: NotesStorage
    private let kanbanStorage: KanbanStorage

    init(
        store: SecondBrainStore = SecondBrainStore(),
        notesStorage: NotesStorage = .shared,
        kanbanStorage: KanbanStorage = .shared
    ) {
        self.store = store
        self.notesStorage = notesStorage
        self.kanbanStorage = kanbanStorage
    }

    func rebuildNote(_ note: Note) throws -> SecondBrainReferenceExtractionResult {
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: note.id.uuidString)
        return try rebuild(
            sourceOwner: owner,
            surface: "note",
            title: note.title,
            text: notesStorage.loadContent(for: note)
        )
    }

    func rebuildCard(boardID: String, card: KanbanCard) throws -> SecondBrainReferenceExtractionResult {
        let owner = SecondBrainKanbanProjectionService.owner(boardID: boardID, cardID: card.id)
        return try rebuild(
            sourceOwner: owner,
            surface: "kanban_card",
            title: card.title,
            text: [card.title, card.aiSummary, card.notes].compactMap { $0 }.joined(separator: "\n\n")
        )
    }

    func rebuildBoard(_ board: KanbanBoard) throws -> [SecondBrainReferenceExtractionResult] {
        try board.allCards.map { card in
            try rebuildCard(boardID: board.id, card: card)
        }
    }

    func rebuild(
        sourceOwner: SecondBrainOwnerRef,
        surface: String,
        title: String?,
        text: String
    ) throws -> SecondBrainReferenceExtractionResult {
        let source = "\(Self.sourcePrefix)\(surface)"
        let relations = extractRelations(
            sourceOwner: sourceOwner,
            surface: surface,
            source: source,
            title: title,
            text: text
        )
        try store.replaceRelations(
            sourceOwner: sourceOwner,
            sourcePrefix: Self.sourcePrefix,
            with: relations
        )
        return SecondBrainReferenceExtractionResult(
            sourceOwner: sourceOwner,
            surface: surface,
            relations: relations
        )
    }

    func extractRelations(
        sourceOwner: SecondBrainOwnerRef,
        surface: String,
        source: String,
        title: String?,
        text: String
    ) -> [SecondBrainRelation] {
        let haystack = [title, text].compactMap { $0 }.joined(separator: "\n\n")
        guard !haystack.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        var drafts: [ReferenceDraft] = []
        drafts.append(contentsOf: canonicalOwnerReferences(in: haystack))
        drafts.append(contentsOf: labelledReferences(in: haystack))
        drafts.append(contentsOf: markdownLinkReferences(in: haystack))
        drafts.append(contentsOf: bareURLReferences(in: haystack))
        drafts.append(contentsOf: knownKanbanIDReferences(in: haystack))
        drafts.append(contentsOf: knownNotePrefixReferences(in: haystack))

        var seen = Set<String>()
        var relations: [SecondBrainRelation] = []
        for draft in drafts {
            guard let target = resolveTarget(type: draft.targetType, ref: draft.targetRef),
                  target != sourceOwner else {
                continue
            }
            let key = "\(target.canonicalRef)|\(source)"
            guard seen.insert(key).inserted else { continue }
            var metadata = draft.metadata
            metadata["source_surface"] = surface
            metadata["extractor"] = "SecondBrainReferenceExtractionService"
            metadata["raw_ref"] = draft.targetRef
            relations.append(SecondBrainRelation(
                sourceOwner: sourceOwner,
                targetOwner: target,
                relationType: draft.relationType,
                evidence: evidenceSnippet(around: draft.range, in: haystack),
                source: source,
                actor: "system",
                confidence: draft.confidence,
                metadata: metadata
            ))
        }
        return relations
    }

    private func canonicalOwnerReferences(in text: String) -> [ReferenceDraft] {
        matches(
            pattern: #"\b([A-Za-z][A-Za-z0-9_-]{1,40}):([A-Za-z0-9][A-Za-z0-9_./-]{2,})\b"#,
            in: text
        ).compactMap { match in
            guard match.groups.count == 2 else { return nil }
            let type = match.groups[0].lowercased()
            guard !["http", "https", "mailto", "file"].contains(type) else { return nil }
            return ReferenceDraft(
                targetType: type,
                targetRef: match.groups[1],
                relationType: "references",
                confidence: 1,
                range: match.range,
                metadata: ["syntax": "canonical_owner_ref"]
            )
        }
    }

    private func labelledReferences(in text: String) -> [ReferenceDraft] {
        matches(
            pattern: #"\b(note|card|kanban card|board|space|project)\s+#?([A-Za-z0-9][A-Za-z0-9_./-]{2,})\b"#,
            options: [.caseInsensitive],
            in: text
        ).map { match in
            let rawType = match.groups[0].lowercased().replacingOccurrences(of: " ", with: "_")
            return ReferenceDraft(
                targetType: rawType == "card" ? "kanban_card" : rawType,
                targetRef: match.groups[1],
                relationType: "references",
                confidence: 1,
                range: match.range,
                metadata: ["syntax": "labelled_ref"]
            )
        }
    }

    private func markdownLinkReferences(in text: String) -> [ReferenceDraft] {
        matches(pattern: #"\[([^\]]+)\]\(([^)\s]+)\)"#, in: text).compactMap { match in
            guard match.groups.count == 2 else { return nil }
            let url = match.groups[1]
            if let cider = ciderURLReference(url, range: match.range, linkText: match.groups[0]) {
                return cider
            }
            guard url.lowercased().hasPrefix("http://") || url.lowercased().hasPrefix("https://") else {
                return nil
            }
            return ReferenceDraft(
                targetType: "url",
                targetRef: url,
                relationType: "references",
                confidence: 0.95,
                range: match.range,
                metadata: ["syntax": "markdown_link", "link_text": match.groups[0]]
            )
        }
    }

    private func bareURLReferences(in text: String) -> [ReferenceDraft] {
        matches(pattern: #"https?://[^\s<>)\]]+"#, in: text).map { match in
            ReferenceDraft(
                targetType: "url",
                targetRef: match.text.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?")),
                relationType: "references",
                confidence: 0.9,
                range: match.range,
                metadata: ["syntax": "bare_url"]
            )
        }
    }

    private func knownKanbanIDReferences(in text: String) -> [ReferenceDraft] {
        kanbanStorage.boards.flatMap { board in
            board.allCards.compactMap { card in
                guard card.id.count >= 6,
                      containsToken(card.id, in: text),
                      let range = text.range(of: card.id) else {
                    return nil
                }
                return ReferenceDraft(
                    targetType: "kanban_card",
                    targetRef: "\(board.id)/\(card.id)",
                    relationType: "mentions",
                    confidence: 0.98,
                    range: NSRange(range, in: text),
                    metadata: [
                        "syntax": "known_card_id",
                        "board_id": board.id,
                        "card_id": card.id,
                    ]
                )
            }
        }
    }

    private func knownNotePrefixReferences(in text: String) -> [ReferenceDraft] {
        notesStorage.notes.compactMap { note in
            let prefix = String(note.id.uuidString.prefix(8))
            guard containsToken(prefix, in: text),
                  let range = text.range(of: prefix, options: [.caseInsensitive]) else {
                return nil
            }
            return ReferenceDraft(
                targetType: "note",
                targetRef: note.id.uuidString,
                relationType: "mentions",
                confidence: 0.98,
                range: NSRange(range, in: text),
                metadata: [
                    "syntax": "known_note_prefix",
                    "note_id": note.id.uuidString,
                ]
            )
        }
    }

    private func ciderURLReference(_ url: String, range: NSRange, linkText: String) -> ReferenceDraft? {
        guard url.lowercased().hasPrefix("cider://") else { return nil }
        let trimmed = String(url.dropFirst("cider://".count))
        let parts = trimmed.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let type: String
        let ref: String
        if parts[0] == "item", parts.count >= 3 {
            type = parts[1]
            ref = parts.dropFirst(2).joined(separator: "/")
        } else {
            type = parts[0]
            ref = parts.dropFirst().joined(separator: "/")
        }
        return ReferenceDraft(
            targetType: type,
            targetRef: ref,
            relationType: "references",
            confidence: 1,
            range: range,
            metadata: ["syntax": "cider_url", "link_text": linkText]
        )
    }

    private func resolveTarget(type rawType: String, ref rawRef: String) -> SecondBrainOwnerRef? {
        let type = rawType.lowercased().replacingOccurrences(of: "-", with: "_")
        let ref = rawRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ref.isEmpty else { return nil }

        switch type {
        case "note":
            if let note = notesStorage.notes.first(where: {
                $0.id.uuidString.lowercased().hasPrefix(ref.lowercased())
            }) {
                return SecondBrainOwnerRef(ownerType: "note", ownerID: note.id.uuidString)
            }
            return SecondBrainOwnerRef(ownerType: "note", ownerID: ref)
        case "card", "kanban_card", "kanban":
            if ref.contains("/") {
                return SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: ref)
            }
            if let detail = kanbanStorage.findCard(id: ref) {
                return SecondBrainKanbanProjectionService.owner(boardID: detail.board.id, cardID: detail.card.id)
            }
            return SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: ref)
        case "board", "kanban_board":
            if let board = kanbanStorage.boards.first(where: {
                $0.id == ref || $0.name.localizedCaseInsensitiveCompare(ref) == .orderedSame
            }) {
                return SecondBrainOwnerRef(ownerType: "kanban_board", ownerID: board.id)
            }
            return SecondBrainOwnerRef(ownerType: "kanban_board", ownerID: ref)
        case "url":
            return SecondBrainOwnerRef(ownerType: "url", ownerID: ref)
        default:
            return SecondBrainOwnerRef(ownerType: type, ownerID: ref)
        }
    }

    private func containsToken(_ token: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: token)
        return !matches(pattern: #"(?<![A-Za-z0-9_])\#(escaped)(?![A-Za-z0-9_])"#, options: [.caseInsensitive], in: text).isEmpty
    }

    private func evidenceSnippet(around range: NSRange, in text: String) -> String {
        guard let swiftRange = Range(range, in: text) else { return "" }
        let lower = text.index(swiftRange.lowerBound, offsetBy: -80, limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(swiftRange.upperBound, offsetBy: 80, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[lower..<upper])
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matches(
        pattern: String,
        options: NSRegularExpression.Options = [],
        in text: String
    ) -> [RegexMatch] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: nsRange).compactMap { result in
            guard let range = Range(result.range, in: text) else { return nil }
            let groups = (1..<result.numberOfRanges).compactMap { index -> String? in
                guard let groupRange = Range(result.range(at: index), in: text) else { return nil }
                return String(text[groupRange])
            }
            return RegexMatch(text: String(text[range]), groups: groups, range: result.range)
        }
    }

    private struct ReferenceDraft {
        var targetType: String
        var targetRef: String
        var relationType: String
        var confidence: Double
        var range: NSRange
        var metadata: [String: String]
    }

    private struct RegexMatch {
        var text: String
        var groups: [String]
        var range: NSRange
    }
}
