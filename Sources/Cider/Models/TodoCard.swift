import Foundation
import SwiftUI

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

    var color: Color {
        switch self {
        case .high: CiderColors.destructive
        case .medium: CiderColors.warning
        case .low: CiderColors.controlAccent
        }
    }
}

struct TodoSubtask: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.completedAt = completedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        isCompleted = (try c.decodeIfPresent(Bool.self, forKey: .isCompleted)) ?? false
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}

struct TodoChecklistItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var completedAt: Date?
    var sortOrder: Int
    var dueDate: Date?
    var amount: Double?
    var urlString: String?
    var subtasks: [TodoSubtask]

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        sortOrder: Int = 0,
        dueDate: Date? = nil,
        amount: Double? = nil,
        urlString: String? = nil,
        subtasks: [TodoSubtask] = []
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.sortOrder = sortOrder
        self.dueDate = dueDate
        self.amount = amount
        self.urlString = urlString
        self.subtasks = subtasks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        isCompleted = (try c.decodeIfPresent(Bool.self, forKey: .isCompleted)) ?? false
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        sortOrder = (try c.decodeIfPresent(Int.self, forKey: .sortOrder)) ?? 0
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        amount = try c.decodeIfPresent(Double.self, forKey: .amount)
        urlString = try c.decodeIfPresent(String.self, forKey: .urlString)
        subtasks = (try c.decodeIfPresent([TodoSubtask].self, forKey: .subtasks)) ?? []
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
    var notes: String
    var linkedEntities: [LibraryEntityRef]
    var actionURLString: String?
    var folderID: UUID?
    var rules: [SurfacingRule]
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
        notes: String = "",
        linkedEntities: [LibraryEntityRef] = [],
        actionURLString: String? = nil,
        folderID: UUID? = nil,
        rules: [SurfacingRule] = [],
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
        self.notes = notes
        self.linkedEntities = linkedEntities
        self.actionURLString = TodoCard.normalizedActionURLString(actionURLString)
        self.folderID = folderID
        self.rules = rules
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
        notes = (try c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
        linkedEntities = (try c.decodeIfPresent([LibraryEntityRef].self, forKey: .linkedEntities)) ?? []
        actionURLString = TodoCard.normalizedActionURLString(try c.decodeIfPresent(String.self, forKey: .actionURLString))
        folderID = try c.decodeIfPresent(UUID.self, forKey: .folderID)
        rules = (try c.decodeIfPresent([SurfacingRule].self, forKey: .rules)) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    static func normalizedActionURLString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    var actionURL: URL? {
        guard let actionURLString else { return nil }
        if let url = URL(string: actionURLString), url.scheme != nil { return url }
        return URL(string: "https://\(actionURLString)")
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

    var hasExplicitDueTime: Bool {
        guard let dueDate else { return false }
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: dueDate)
        return (components.hour ?? 0) != 0 || (components.minute ?? 0) != 0 || (components.second ?? 0) != 0
    }

    /// The earliest approaching due date — either the card's own dueDate or any checklist item's dueDate.
    var earliestApproachingDate: Date? {
        var dates: [Date] = []
        if let dueDate { dates.append(dueDate) }
        for item in checklist where !item.isCompleted {
            if let itemDue = item.dueDate { dates.append(itemDue) }
        }
        return dates.min()
    }

    /// Urgency based on the card's due date or any checklist item's due date.
    func urgency(now: Date = Date(), windowDays: Int = 7) -> DateCardUrgency? {
        guard !isCompleted else { return nil }
        guard let target = earliestApproachingDate else { return nil }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: target)).day ?? 0
        if days < 0 { return .overdue }
        if days == 0 { return .today }
        if days <= windowDays { return .approaching(daysUntil: days) }
        return nil
    }

    /// Sum of all checklist item amounts (for bills tracking).
    var totalAmount: Double? {
        let amounts = checklist.compactMap(\.amount)
        guard !amounts.isEmpty else { return nil }
        return amounts.reduce(0, +)
    }

    /// Sum of uncompleted checklist item amounts.
    var unpaidAmount: Double? {
        let amounts = checklist.filter { !$0.isCompleted }.compactMap(\.amount)
        guard !amounts.isEmpty else { return nil }
        return amounts.reduce(0, +)
    }

    /// Shared currency formatter for todo amount displays.
    static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
