import Foundation

enum BillPaymentMode: String, Codable, CaseIterable, Hashable {
    case manual
    case autopay
}

struct BillPayment: Identifiable, Codable, Hashable {
    let id: UUID
    var paidAt: Date
    var amount: Double
    var confirmation: String?
    var balanceAfterPayment: Double?
    var note: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        paidAt: Date,
        amount: Double,
        confirmation: String? = nil,
        balanceAfterPayment: Double? = nil,
        note: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.paidAt = paidAt
        self.amount = max(amount, 0)
        self.confirmation = BillAccount.normalizedOptionalString(confirmation)
        self.balanceAfterPayment = balanceAfterPayment
        self.note = note
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        paidAt = try c.decode(Date.self, forKey: .paidAt)
        amount = max((try c.decodeIfPresent(Double.self, forKey: .amount)) ?? 0, 0)
        confirmation = BillAccount.normalizedOptionalString(try c.decodeIfPresent(String.self, forKey: .confirmation))
        balanceAfterPayment = try c.decodeIfPresent(Double.self, forKey: .balanceAfterPayment)
        note = (try c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        createdAt = (try c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? paidAt
    }
}

struct BillAccount: Identifiable, Codable, Hashable {
    let id: UUID
    var providerName: String
    var accountName: String
    var dueAt: Date
    var recurrenceRule: DateCardRecurrenceRule?
    var amountDue: Double?
    var amountPaid: Double?
    var balanceRemaining: Double?
    var apr: Double?
    var paymentMode: BillPaymentMode
    var actionURLString: String?
    var notes: String
    var linkedEntities: [LibraryEntityRef]
    var payments: [BillPayment]
    var rules: [SurfacingRule]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        providerName: String,
        accountName: String = "",
        dueAt: Date,
        recurrenceRule: DateCardRecurrenceRule? = nil,
        amountDue: Double? = nil,
        amountPaid: Double? = nil,
        balanceRemaining: Double? = nil,
        apr: Double? = nil,
        paymentMode: BillPaymentMode = .manual,
        actionURLString: String? = nil,
        notes: String = "",
        linkedEntities: [LibraryEntityRef] = [],
        payments: [BillPayment] = [],
        rules: [SurfacingRule] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.providerName = providerName
        self.accountName = accountName
        self.dueAt = dueAt
        self.recurrenceRule = recurrenceRule
        self.amountDue = amountDue.map { max($0, 0) }
        self.amountPaid = amountPaid.map { max($0, 0) }
        self.balanceRemaining = balanceRemaining
        self.apr = apr
        self.paymentMode = paymentMode
        self.actionURLString = BillAccount.normalizedOptionalString(actionURLString)
        self.notes = notes
        self.linkedEntities = linkedEntities
        self.payments = payments.sorted { $0.paidAt < $1.paidAt }
        self.rules = rules
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        providerName = try c.decode(String.self, forKey: .providerName)
        accountName = (try c.decodeIfPresent(String.self, forKey: .accountName)) ?? ""
        dueAt = try c.decode(Date.self, forKey: .dueAt)
        recurrenceRule = try c.decodeIfPresent(DateCardRecurrenceRule.self, forKey: .recurrenceRule)
        amountDue = (try c.decodeIfPresent(Double.self, forKey: .amountDue)).map { max($0, 0) }
        amountPaid = (try c.decodeIfPresent(Double.self, forKey: .amountPaid)).map { max($0, 0) }
        balanceRemaining = try c.decodeIfPresent(Double.self, forKey: .balanceRemaining)
        apr = try c.decodeIfPresent(Double.self, forKey: .apr)
        paymentMode = (try c.decodeIfPresent(BillPaymentMode.self, forKey: .paymentMode)) ?? .manual
        actionURLString = BillAccount.normalizedOptionalString(try c.decodeIfPresent(String.self, forKey: .actionURLString))
        notes = (try c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
        linkedEntities = (try c.decodeIfPresent([LibraryEntityRef].self, forKey: .linkedEntities)) ?? []
        payments = ((try c.decodeIfPresent([BillPayment].self, forKey: .payments)) ?? []).sorted { $0.paidAt < $1.paidAt }
        rules = (try c.decodeIfPresent([SurfacingRule].self, forKey: .rules)) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    static func normalizedOptionalString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    var actionURL: URL? {
        guard let actionURLString else { return nil }
        if let url = URL(string: actionURLString), url.scheme != nil { return url }
        return URL(string: "https://\(actionURLString)")
    }

    var totalPaid: Double {
        payments.reduce(0) { $0 + max($1.amount, 0) }
    }

    func effectiveDueDate(now: Date = Date(), calendar: Calendar = .current) -> Date {
        guard let rule = recurrenceRule else { return dueAt }
        var candidate = dueAt
        while calendar.startOfDay(for: candidate) < calendar.startOfDay(for: now) {
            guard let next = calendar.date(byAdding: rule.frequency.calendarComponent, value: rule.interval, to: candidate) else { break }
            candidate = next
            if let endDate = rule.endDate, candidate > endDate { break }
        }
        return candidate
    }

    func paymentsForCurrentCycle(now: Date = Date(), calendar: Calendar = .current) -> [BillPayment] {
        let dueDate = effectiveDueDate(now: now, calendar: calendar)
        let cycleStart: Date
        if let rule = recurrenceRule,
           let previous = calendar.date(byAdding: rule.frequency.calendarComponent, value: -rule.interval, to: dueDate) {
            cycleStart = previous
        } else {
            cycleStart = calendar.startOfDay(for: dueDate)
        }
        let cycleEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: dueDate)) ?? dueDate
        return payments.filter { payment in
            payment.paidAt >= cycleStart && payment.paidAt < cycleEnd
        }
    }

    func remainingAmountForCurrentCycle(now: Date = Date(), calendar: Calendar = .current) -> Double? {
        guard let amountDue else { return balanceRemaining }
        let cyclePaid = paymentsForCurrentCycle(now: now, calendar: calendar).reduce(amountPaid ?? 0) { $0 + max($1.amount, 0) }
        return max(amountDue - cyclePaid, 0)
    }

    func isPaidForCurrentCycle(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        if let remaining = remainingAmountForCurrentCycle(now: now, calendar: calendar) {
            return remaining <= 0.0001
        }
        if let latestBalance = paymentsForCurrentCycle(now: now, calendar: calendar).compactMap(\.balanceAfterPayment).last {
            return latestBalance <= 0.0001
        }
        return false
    }

    func urgency(now: Date = Date(), calendar: Calendar = .current, windowDays: Int = 7) -> DateCardUrgency? {
        guard !isPaidForCurrentCycle(now: now, calendar: calendar) else { return nil }
        let effectiveWindowDays = rules.first(where: { $0.type == .surfaceDaysBeforeDate && $0.isEnabled })?.integerValue ?? windowDays
        let target = effectiveDueDate(now: now, calendar: calendar)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: target)).day ?? 0
        if days < 0 { return .overdue }
        if days == 0 { return .today }
        if days <= effectiveWindowDays { return .approaching(daysUntil: days) }
        return nil
    }
}
