import Foundation

enum TodoPriority: String, Codable, CaseIterable, Hashable {
    case low
    case medium
    case high

    var displayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var icon: String {
        switch self {
        case .low: "arrow.down"
        case .medium: "minus"
        case .high: "arrow.up"
        }
    }
}

struct TodoChecklistItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var completedAt: Date?
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.sortOrder = sortOrder
    }
}

struct TodoCard: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var details: String
    var checklist: [TodoChecklistItem]
    var dueDate: Date?
    var priority: TodoPriority?
    var isCompleted: Bool
    var completedAt: Date?
    var labelIDs: [UUID]
    var linkedEntities: [LibraryEntityRef]
    var folderID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        checklist: [TodoChecklistItem] = [],
        dueDate: Date? = nil,
        priority: TodoPriority? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        labelIDs: [UUID] = [],
        linkedEntities: [LibraryEntityRef] = [],
        folderID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.checklist = checklist
        self.dueDate = dueDate
        self.priority = priority
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.labelIDs = labelIDs
        self.linkedEntities = linkedEntities
        self.folderID = folderID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        details = (try c.decodeIfPresent(String.self, forKey: .details)) ?? ""
        checklist = (try c.decodeIfPresent([TodoChecklistItem].self, forKey: .checklist)) ?? []
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        priority = try c.decodeIfPresent(TodoPriority.self, forKey: .priority)
        isCompleted = (try c.decodeIfPresent(Bool.self, forKey: .isCompleted)) ?? false
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        labelIDs = (try c.decodeIfPresent([UUID].self, forKey: .labelIDs)) ?? []
        linkedEntities = (try c.decodeIfPresent([LibraryEntityRef].self, forKey: .linkedEntities)) ?? []
        folderID = try c.decodeIfPresent(UUID.self, forKey: .folderID)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    /// Number of completed checklist items.
    var completedCount: Int {
        checklist.filter(\.isCompleted).count
    }

    /// Total checklist items.
    var totalCount: Int {
        checklist.count
    }

    /// Whether this todo is overdue (has a due date in the past and is not completed).
    var isOverdue: Bool {
        guard !isCompleted, let dueDate else { return false }
        return dueDate < Date()
    }

    /// Whether this todo is due today.
    var isDueToday: Bool {
        guard !isCompleted, let dueDate else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }
}
