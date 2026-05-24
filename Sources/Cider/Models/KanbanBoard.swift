import Foundation

// MARK: - Supporting Enums

enum KanbanCardColor: String, Codable, CaseIterable, Sendable {
    case blue, green, orange, red, purple
}

enum KanbanPriority: String, Codable, CaseIterable, Sendable {
    case low, medium, high
}

enum KanbanCardHistoryEntryType: String, Codable, CaseIterable, Sendable {
    case note
    case implementation
    case failedAttempt = "failed_attempt"
    case testEvidence = "test_evidence"
    case decision
    case handoff
    case finalSummary = "final_summary"
    case commit

    var displayName: String {
        switch self {
        case .note: "Note"
        case .implementation: "Implementation"
        case .failedAttempt: "Failed Attempt"
        case .testEvidence: "Test Evidence"
        case .decision: "Decision"
        case .handoff: "Handoff"
        case .finalSummary: "Final Summary"
        case .commit: "Commit"
        }
    }

    var symbolName: String {
        switch self {
        case .note: "note.text"
        case .implementation: "hammer"
        case .failedAttempt: "xmark.octagon"
        case .testEvidence: "checkmark.seal"
        case .decision: "checkmark.seal.fill"
        case .handoff: "person.2.wave.2"
        case .finalSummary: "flag.checkered"
        case .commit: "point.3.connected.trianglepath.dotted"
        }
    }
}

struct KanbanCardHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var type: KanbanCardHistoryEntryType
    var body: String
    var author: String?
    var createdAt: Date

    init(
        id: String = KanbanID.generate(),
        type: KanbanCardHistoryEntryType,
        body: String,
        author: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.body = body
        self.author = author
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, type, body, author, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(KanbanCardHistoryEntryType.self, forKey: .type)
        body = try c.decode(String.self, forKey: .body)
        author = try c.decodeIfPresent(String.self, forKey: .author)
        createdAt = try c.decode(KanbanHistoryDate.self, forKey: .createdAt).date
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        try c.encode(body, forKey: .body)
        try c.encodeIfPresent(author, forKey: .author)
        try c.encode(KanbanHistoryDate(date: createdAt), forKey: .createdAt)
    }
}

// MARK: - KanbanCard

struct KanbanCard: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var notes: String?
    var aiSummary: String?
    /// Human-readable command-center key (for example, CID-42). Internal ids remain canonical.
    var displayKey: String?
    var color: KanbanCardColor?
    var priority: KanbanPriority?
    var agent: String?
    var tags: [String]
    var linkedEntities: [LibraryEntityRef]
    var relatedCardIDs: [String]
    var parentCardID: String?
    var historyEntries: [KanbanCardHistoryEntry]
    var created: Date
    var completed: Date?
    var updatedAt: Date?
    var lastActivityKind: String?

    init(
        id: String = KanbanID.generate(),
        title: String,
        notes: String? = nil,
        aiSummary: String? = nil,
        displayKey: String? = nil,
        color: KanbanCardColor? = nil,
        priority: KanbanPriority? = nil,
        agent: String? = nil,
        tags: [String] = [],
        linkedEntities: [LibraryEntityRef] = [],
        relatedCardIDs: [String] = [],
        parentCardID: String? = nil,
        historyEntries: [KanbanCardHistoryEntry] = [],
        created: Date = Date(),
        completed: Date? = nil,
        updatedAt: Date? = nil,
        lastActivityKind: String? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.aiSummary = aiSummary
        self.displayKey = displayKey
        self.color = color
        self.priority = priority
        self.agent = agent
        self.tags = tags
        self.linkedEntities = linkedEntities
        self.relatedCardIDs = relatedCardIDs
        self.parentCardID = parentCardID
        self.historyEntries = historyEntries
        self.created = created
        self.completed = completed
        self.updatedAt = updatedAt
        self.lastActivityKind = lastActivityKind
    }

    mutating func markActivity(_ kind: String, at date: Date = Date()) {
        updatedAt = date
        lastActivityKind = kind
    }

    // Custom Codable for date format and backward compatibility
    enum CodingKeys: String, CodingKey {
        case id, title, notes, aiSummary, displayKey, color, priority, agent, tags, linkedEntities, relatedCardIDs, parentCardID, historyEntries, created, completed, updatedAt, lastActivityKind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        aiSummary = try c.decodeIfPresent(String.self, forKey: .aiSummary)
        displayKey = try c.decodeIfPresent(String.self, forKey: .displayKey)
        color = try c.decodeIfPresent(KanbanCardColor.self, forKey: .color)
        priority = try c.decodeIfPresent(KanbanPriority.self, forKey: .priority)
        agent = try c.decodeIfPresent(String.self, forKey: .agent)
        tags = (try c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        linkedEntities = (try c.decodeIfPresent([LibraryEntityRef].self, forKey: .linkedEntities)) ?? []
        relatedCardIDs = (try c.decodeIfPresent([String].self, forKey: .relatedCardIDs)) ?? []
        parentCardID = try c.decodeIfPresent(String.self, forKey: .parentCardID)
        historyEntries = (try c.decodeIfPresent([KanbanCardHistoryEntry].self, forKey: .historyEntries)) ?? []
        created = (try c.decodeIfPresent(KanbanDate.self, forKey: .created))?.date ?? Date()
        completed = try c.decodeIfPresent(KanbanDate.self, forKey: .completed)?.date
        updatedAt = try c.decodeIfPresent(KanbanTimestamp.self, forKey: .updatedAt)?.date
        lastActivityKind = try c.decodeIfPresent(String.self, forKey: .lastActivityKind)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(aiSummary, forKey: .aiSummary)
        try c.encodeIfPresent(displayKey, forKey: .displayKey)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(priority, forKey: .priority)
        try c.encodeIfPresent(agent, forKey: .agent)
        if !tags.isEmpty { try c.encode(tags, forKey: .tags) }
        if !linkedEntities.isEmpty { try c.encode(linkedEntities, forKey: .linkedEntities) }
        if !relatedCardIDs.isEmpty { try c.encode(relatedCardIDs, forKey: .relatedCardIDs) }
        try c.encodeIfPresent(parentCardID, forKey: .parentCardID)
        if !historyEntries.isEmpty { try c.encode(historyEntries, forKey: .historyEntries) }
        try c.encode(KanbanDate(date: created), forKey: .created)
        try c.encodeIfPresent(completed.map { KanbanDate(date: $0) }, forKey: .completed)
        try c.encodeIfPresent(updatedAt.map { KanbanTimestamp(date: $0) }, forKey: .updatedAt)
        try c.encodeIfPresent(lastActivityKind, forKey: .lastActivityKind)
    }
}

// MARK: - KanbanColumn

struct KanbanColumn: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var isDoneColumn: Bool
    var cards: [KanbanCard]

    init(
        id: String,
        name: String,
        isDoneColumn: Bool = false,
        cards: [KanbanCard] = []
    ) {
        self.id = id
        self.name = name
        self.isDoneColumn = isDoneColumn
        self.cards = cards
    }

    enum CodingKeys: String, CodingKey {
        case id, name, cards
        case isDoneColumn = "is_done_column"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        isDoneColumn = (try c.decodeIfPresent(Bool.self, forKey: .isDoneColumn)) ?? false
        cards = (try c.decodeIfPresent([KanbanCard].self, forKey: .cards)) ?? []
    }
}

// MARK: - KanbanBoard

struct KanbanBoard: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var created: Date
    var columns: [KanbanColumn]

    init(
        id: String = KanbanID.generate(),
        name: String,
        created: Date = Date(),
        columns: [KanbanColumn] = []
    ) {
        self.id = id
        self.name = name
        self.created = created
        self.columns = columns
    }

    /// Create a new board with default columns.
    static func new(name: String) -> KanbanBoard {
        KanbanBoard(
            name: name,
            columns: [
                KanbanColumn(id: "backlog", name: "Backlog"),
                KanbanColumn(id: "in_progress", name: "In Progress"),
                KanbanColumn(id: "done", name: "Done", isDoneColumn: true),
            ]
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name = "board"
        case created, columns
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        created = try c.decode(KanbanDate.self, forKey: .created).date
        columns = (try c.decodeIfPresent([KanbanColumn].self, forKey: .columns)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(KanbanDate(date: created), forKey: .created)
        try c.encode(columns, forKey: .columns)
    }

    var allCards: [KanbanCard] {
        columns.flatMap(\.cards)
    }

    /// Short board prefix for human-readable card keys. Kept separate from persisted board/card ids.
    var displayKeyPrefix: String {
        let normalized = name
            .replacingOccurrences(of: "&", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        if normalized.count >= 2 {
            let initials = normalized.prefix(3).compactMap { $0.first }.map(String.init).joined()
            if initials.count >= 2 { return initials.uppercased() }
        }

        let compact = normalized.first ?? id
        let scalars = compact.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        let prefix = String(String.UnicodeScalarView(scalars)).prefix(3).uppercased()
        return prefix.isEmpty ? "CID" : prefix
    }

    func displayKey(for card: KanbanCard) -> String {
        if let key = card.displayKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return key.uppercased()
        }
        let index = allCards.firstIndex { $0.id == card.id }.map { $0 + 1 } ?? 1
        return "\(displayKeyPrefix)-\(index)"
    }

    func nextDisplayKey() -> String {
        let prefix = displayKeyPrefix.uppercased()
        let highest = allCards.compactMap { card -> Int? in
            let key = displayKey(for: card).uppercased()
            guard key.hasPrefix("\(prefix)-") else { return nil }
            return Int(key.dropFirst(prefix.count + 1))
        }.max() ?? 0
        return "\(prefix)-\(highest + 1)"
    }

    mutating func assignMissingDisplayKeys() {
        let prefix = displayKeyPrefix.uppercased()
        var usedNumbers = Set<Int>()
        for card in allCards {
            guard let key = card.displayKey?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                  key.hasPrefix("\(prefix)-"),
                  let number = Int(key.dropFirst(prefix.count + 1)) else { continue }
            usedNumbers.insert(number)
        }

        var nextNumber = 1
        for columnIndex in columns.indices {
            for cardIndex in columns[columnIndex].cards.indices {
                let key = columns[columnIndex].cards[cardIndex].displayKey?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard key?.isEmpty != false else { continue }
                while usedNumbers.contains(nextNumber) { nextNumber += 1 }
                columns[columnIndex].cards[cardIndex].displayKey = "\(prefix)-\(nextNumber)"
                usedNumbers.insert(nextNumber)
            }
        }
    }

    func card(id cardID: String) -> KanbanCard? {
        allCards.first { $0.id == cardID }
    }

    func card(matching ref: String) -> KanbanCard? {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let exact = card(id: trimmed) { return exact }
        return allCards.first { displayKey(for: $0).localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
    }

    func columnID(containing cardID: String) -> String? {
        columns.first { column in
            column.cards.contains { $0.id == cardID }
        }?.id
    }

    func parentCard(for cardID: String) -> KanbanCard? {
        guard let parentID = card(id: cardID)?.parentCardID else { return nil }
        return card(id: parentID)
    }

    func ancestorCards(for cardID: String) -> [KanbanCard] {
        guard let card = card(id: cardID) else { return [] }

        var ancestors: [KanbanCard] = []
        var visited = Set([card.id])
        var nextParentID = card.parentCardID

        while let parentID = nextParentID,
              let parent = self.card(id: parentID),
              visited.insert(parent.id).inserted {
            ancestors.append(parent)
            nextParentID = parent.parentCardID
        }

        return ancestors.reversed()
    }

    func lineageCards(for cardID: String) -> [KanbanCard] {
        guard let card = card(id: cardID) else { return [] }
        return ancestorCards(for: cardID) + [card]
    }

    func childCards(of parentID: String) -> [KanbanCard] {
        allCards.filter { $0.parentCardID == parentID }
    }

    func relatedCards(for cardID: String) -> [KanbanCard] {
        guard let source = card(id: cardID) else { return [] }

        var seen = Set([cardID])
        return source.relatedCardIDs.compactMap { relatedID in
            guard seen.insert(relatedID).inserted else { return nil }
            return card(id: relatedID)
        }
    }

    func cards(linking ref: LibraryEntityRef) -> [KanbanCard] {
        var seen: Set<String> = []
        return allCards.compactMap { card in
            guard card.linkedEntities.contains(ref), seen.insert(card.id).inserted else { return nil }
            return card
        }
    }

    func relatedCardCandidates(
        for cardID: String,
        matching query: String,
        excluding excludedCardIDs: Set<String> = []
    ) -> [KanbanCard] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        let existingRelatedIDs = Set(card(id: cardID)?.relatedCardIDs ?? [])
        let unavailableIDs = existingRelatedIDs
            .union(excludedCardIDs)
            .union([cardID])

        return allCards.filter { candidate in
            guard !unavailableIDs.contains(candidate.id) else { return false }
            return candidate.id.localizedCaseInsensitiveContains(trimmedQuery)
                || candidate.title.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    func descendantCards(of parentID: String) -> [KanbanCard] {
        let orderedCards = allCards
        var descendants: [KanbanCard] = []
        var visited = Set([parentID])

        func appendChildren(of currentParentID: String) {
            for child in orderedCards where child.parentCardID == currentParentID {
                guard visited.insert(child.id).inserted else { continue }
                descendants.append(child)
                appendChildren(of: child.id)
            }
        }

        appendChildren(of: parentID)
        return descendants
    }

    func canAssignParent(cardID: String, parentCardID: String?) -> Bool {
        guard card(id: cardID) != nil else { return false }
        guard let parentCardID else { return true }
        guard cardID != parentCardID, card(id: parentCardID) != nil else { return false }

        var visited = Set<String>()
        var nextParentID: String? = parentCardID
        while let current = nextParentID {
            if current == cardID { return false }
            if !visited.insert(current).inserted { return false }
            nextParentID = card(id: current)?.parentCardID
        }
        return true
    }

    mutating func clearParentReferences(to parentID: String) {
        for columnIndex in columns.indices {
            for cardIndex in columns[columnIndex].cards.indices
            where columns[columnIndex].cards[cardIndex].parentCardID == parentID {
                columns[columnIndex].cards[cardIndex].parentCardID = nil
            }
        }
    }
}

// MARK: - History Date Wrapper (ISO-8601)

private struct KanbanHistoryDate: Codable, Sendable {
    let date: Date

    init(date: Date) { self.date = date }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let directDate = try? container.decode(Date.self) {
            date = directDate
            return
        }
        let string = try container.decode(String.self)
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        if let parsed = fractionalFormatter.date(from: string) ?? fallbackFormatter.date(from: string) {
            date = parsed
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid history timestamp: \(string). Expected ISO-8601."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var container = encoder.singleValueContainer()
        try container.encode(formatter.string(from: date))
    }
}

// MARK: - Date Wrapper (yyyy-MM-dd)

private struct KanbanTimestamp: Codable, Sendable {
    let date: Date

    init(date: Date) { self.date = date }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let directDate = try? container.decode(Date.self) {
            date = directDate
        } else if let string = try? container.decode(String.self),
                  let parsed = ISO8601DateFormatter().date(from: string) {
            date = parsed
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid timestamp format. Expected ISO-8601."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(ISO8601DateFormatter().string(from: date))
    }
}

/// Wraps a Date for YAML encoding as a bare date string (2026-03-20).
private struct KanbanDate: Codable, Sendable {
    let date: Date

    init(date: Date) { self.date = date }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Yams parses unquoted dates (2026-03-20) as Date, quoted ones ('2026-03-20') as String
        if let directDate = try? container.decode(Date.self) {
            date = CiderLocalDate.localDate(fromUTCDateOnlyInstant: directDate)
        } else if let string = try? container.decode(String.self) {
            if let parsed = CiderLocalDate.parseDashed(string) {
                date = parsed
            } else if let parsed = ISO8601DateFormatter().date(from: string) {
                date = parsed
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid date format: \(string). Expected yyyy-MM-dd or ISO-8601."
                )
            }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Could not decode date as Date or String."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(CiderLocalDate.formatDashed(date))
    }
}

// MARK: - ID Generation

enum KanbanID {
    /// Generate a 6-character lowercase hex ID.
    static func generate() -> String {
        (0..<3).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    /// Generate a slug from a display name (e.g. "In Progress" → "in_progress").
    static func slug(from name: String) -> String {
        name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }
}
