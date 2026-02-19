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
        self.rules = rules
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
