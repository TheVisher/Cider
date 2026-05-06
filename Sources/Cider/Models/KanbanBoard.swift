import Foundation

// MARK: - Supporting Enums

enum KanbanCardColor: String, Codable, CaseIterable, Sendable {
    case blue, green, orange, red, purple
}

enum KanbanPriority: String, Codable, CaseIterable, Sendable {
    case low, medium, high
}

// MARK: - KanbanCard

struct KanbanCard: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var notes: String?
    var color: KanbanCardColor?
    var priority: KanbanPriority?
    var agent: String?
    var tags: [String]
    var linkedEntities: [LibraryEntityRef]
    var parentCardID: String?
    var created: Date
    var completed: Date?

    init(
        id: String = KanbanID.generate(),
        title: String,
        notes: String? = nil,
        color: KanbanCardColor? = nil,
        priority: KanbanPriority? = nil,
        agent: String? = nil,
        tags: [String] = [],
        linkedEntities: [LibraryEntityRef] = [],
        parentCardID: String? = nil,
        created: Date = Date(),
        completed: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.color = color
        self.priority = priority
        self.agent = agent
        self.tags = tags
        self.linkedEntities = linkedEntities
        self.parentCardID = parentCardID
        self.created = created
        self.completed = completed
    }

    // Custom Codable for date format and backward compatibility
    enum CodingKeys: String, CodingKey {
        case id, title, notes, color, priority, agent, tags, linkedEntities, parentCardID, created, completed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        color = try c.decodeIfPresent(KanbanCardColor.self, forKey: .color)
        priority = try c.decodeIfPresent(KanbanPriority.self, forKey: .priority)
        agent = try c.decodeIfPresent(String.self, forKey: .agent)
        tags = (try c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        linkedEntities = (try c.decodeIfPresent([LibraryEntityRef].self, forKey: .linkedEntities)) ?? []
        parentCardID = try c.decodeIfPresent(String.self, forKey: .parentCardID)
        created = (try c.decodeIfPresent(KanbanDate.self, forKey: .created))?.date ?? Date()
        completed = try c.decodeIfPresent(KanbanDate.self, forKey: .completed)?.date
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(priority, forKey: .priority)
        try c.encodeIfPresent(agent, forKey: .agent)
        if !tags.isEmpty { try c.encode(tags, forKey: .tags) }
        if !linkedEntities.isEmpty { try c.encode(linkedEntities, forKey: .linkedEntities) }
        try c.encodeIfPresent(parentCardID, forKey: .parentCardID)
        try c.encode(KanbanDate(date: created), forKey: .created)
        try c.encodeIfPresent(completed.map { KanbanDate(date: $0) }, forKey: .completed)
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

    func card(id cardID: String) -> KanbanCard? {
        allCards.first { $0.id == cardID }
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

// MARK: - Date Wrapper (yyyy-MM-dd)

/// Wraps a Date for YAML encoding as a bare date string (2026-03-20).
private struct KanbanDate: Codable, Sendable {
    let date: Date

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    init(date: Date) { self.date = date }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Yams parses unquoted dates (2026-03-20) as Date, quoted ones ('2026-03-20') as String
        if let directDate = try? container.decode(Date.self) {
            date = directDate
        } else if let string = try? container.decode(String.self) {
            if let parsed = Self.formatter.date(from: string) {
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
        try container.encode(Self.formatter.string(from: date))
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
