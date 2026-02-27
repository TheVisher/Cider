import Foundation

enum DateCardRecurrenceFrequency: String, Codable, CaseIterable, Hashable {
    case daily
    case weekly
    case monthly
    case yearly
}

struct DateCardRecurrenceRule: Codable, Hashable {
    var frequency: DateCardRecurrenceFrequency
    var interval: Int
    var endDate: Date?

    init(
        frequency: DateCardRecurrenceFrequency,
        interval: Int = 1,
        endDate: Date? = nil
    ) {
        self.frequency = frequency
        self.interval = max(interval, 1)
        self.endDate = endDate
    }
}

enum DateCardUrgency: Equatable {
    case approaching(daysUntil: Int)  // 1...windowDays, not completed
    case today                         // startAt is today, not completed
    case overdue                       // startAt in the past, not completed
}

struct DateCard: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var details: String
    var startAt: Date
    var endAt: Date?
    var allDay: Bool
    var location: String
    var amount: Double?
    var recurrenceRule: DateCardRecurrenceRule?
    var isCompleted: Bool
    var completedAt: Date?
    var labelIDs: [UUID]
    var linkedEntities: [LibraryEntityRef]
    var folderID: UUID?
    var rules: [SurfacingRule]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        startAt: Date,
        endAt: Date? = nil,
        allDay: Bool = false,
        location: String = "",
        amount: Double? = nil,
        recurrenceRule: DateCardRecurrenceRule? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        labelIDs: [UUID] = [],
        linkedEntities: [LibraryEntityRef] = [],
        folderID: UUID? = nil,
        rules: [SurfacingRule] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.startAt = startAt
        self.endAt = endAt
        self.allDay = allDay
        self.location = location
        self.amount = amount
        self.recurrenceRule = recurrenceRule
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.labelIDs = labelIDs
        self.linkedEntities = linkedEntities
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
        startAt = try c.decode(Date.self, forKey: .startAt)
        endAt = try c.decodeIfPresent(Date.self, forKey: .endAt)
        allDay = (try c.decodeIfPresent(Bool.self, forKey: .allDay)) ?? false
        location = (try c.decodeIfPresent(String.self, forKey: .location)) ?? ""
        amount = try c.decodeIfPresent(Double.self, forKey: .amount)
        recurrenceRule = try c.decodeIfPresent(DateCardRecurrenceRule.self, forKey: .recurrenceRule)
        isCompleted = (try c.decodeIfPresent(Bool.self, forKey: .isCompleted)) ?? false
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        labelIDs = (try c.decodeIfPresent([UUID].self, forKey: .labelIDs)) ?? []
        linkedEntities = (try c.decodeIfPresent([LibraryEntityRef].self, forKey: .linkedEntities)) ?? []
        folderID = try c.decodeIfPresent(UUID.self, forKey: .folderID)
        rules = (try c.decodeIfPresent([SurfacingRule].self, forKey: .rules)) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    func urgency(now: Date = Date(), windowDays: Int = 7) -> DateCardUrgency? {
        guard !isCompleted else { return nil }
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let startOfEvent = calendar.startOfDay(for: startAt)
        let days = calendar.dateComponents([.day], from: startOfToday, to: startOfEvent).day ?? 0
        if days < 0 { return .overdue }
        if days == 0 { return .today }
        if days <= windowDays { return .approaching(daysUntil: days) }
        return nil
    }
}
