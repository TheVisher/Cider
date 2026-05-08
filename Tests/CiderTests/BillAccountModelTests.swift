import XCTest
@testable import Cider

final class BillAccountModelTests: XCTestCase {
    func testBillAccountCodableRoundTripPreservesLedgerFields() throws {
        let accountID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let paymentID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let documentID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let dueAt = Date(timeIntervalSince1970: 1_746_144_000)
        let paidAt = Date(timeIntervalSince1970: 1_746_057_600)

        let original = BillAccount(
            id: accountID,
            providerName: "Cider Card",
            accountName: "Rewards Visa",
            dueAt: dueAt,
            recurrenceRule: DateCardRecurrenceRule(frequency: .monthly, interval: 1),
            amountDue: 125.50,
            amountPaid: 75,
            balanceRemaining: 840.25,
            apr: 21.99,
            paymentMode: .manual,
            actionURLString: "  billing.example.com/pay  ",
            notes: "Pay from checking",
            linkedEntities: [LibraryEntityRef(type: .bookmark, entityID: documentID)],
            payments: [
                BillPayment(
                    id: paymentID,
                    paidAt: paidAt,
                    amount: 75,
                    confirmation: "ABC123",
                    balanceAfterPayment: 840.25,
                    note: "Partial payment"
                )
            ],
            rules: [SurfacingRule(type: .surfaceDaysBeforeDate, integerValue: 5)],
            createdAt: dueAt,
            updatedAt: paidAt
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BillAccount.self, from: data)

        XCTAssertEqual(decoded.id, accountID)
        XCTAssertEqual(decoded.providerName, "Cider Card")
        XCTAssertEqual(decoded.accountName, "Rewards Visa")
        XCTAssertEqual(decoded.recurrenceRule?.frequency, .monthly)
        XCTAssertEqual(decoded.amountDue ?? 0, 125.50, accuracy: 0.001)
        XCTAssertEqual(decoded.amountPaid ?? 0, 75, accuracy: 0.001)
        XCTAssertEqual(decoded.balanceRemaining ?? 0, 840.25, accuracy: 0.001)
        XCTAssertEqual(decoded.apr ?? 0, 21.99, accuracy: 0.001)
        XCTAssertEqual(decoded.paymentMode, .manual)
        XCTAssertEqual(decoded.actionURLString, "billing.example.com/pay")
        XCTAssertEqual(decoded.actionURL?.absoluteString, "https://billing.example.com/pay")
        XCTAssertEqual(decoded.linkedEntities.first?.entityID, documentID)
        XCTAssertEqual(decoded.payments.first?.confirmation, "ABC123")
        XCTAssertEqual(decoded.rules.first?.integerValue, 5)
    }

    func testPaymentDerivedValuesAndCurrentCycleQuieting() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 8))!
        let dueAt = calendar.date(from: DateComponents(year: 2026, month: 5, day: 10))!
        let paidAt = calendar.date(from: DateComponents(year: 2026, month: 5, day: 7))!
        let oldPayment = calendar.date(from: DateComponents(year: 2026, month: 4, day: 7))!

        let paidCurrentCycle = BillAccount(
            providerName: "Rent",
            dueAt: dueAt,
            recurrenceRule: DateCardRecurrenceRule(frequency: .monthly),
            amountDue: 1200,
            payments: [
                BillPayment(paidAt: oldPayment, amount: 1200),
                BillPayment(paidAt: paidAt, amount: 1200, balanceAfterPayment: 0)
            ]
        )

        XCTAssertEqual(paidCurrentCycle.totalPaid, 2400, accuracy: 0.001)
        XCTAssertEqual(paidCurrentCycle.remainingAmountForCurrentCycle(now: now, calendar: calendar) ?? -1, 0, accuracy: 0.001)
        XCTAssertTrue(paidCurrentCycle.isPaidForCurrentCycle(now: now, calendar: calendar))
        XCTAssertNil(paidCurrentCycle.urgency(now: now, calendar: calendar, windowDays: 7))

        let partial = BillAccount(
            providerName: "Card",
            dueAt: dueAt,
            recurrenceRule: DateCardRecurrenceRule(frequency: .monthly),
            amountDue: 300,
            payments: [BillPayment(paidAt: paidAt, amount: 125)]
        )

        XCTAssertEqual(partial.remainingAmountForCurrentCycle(now: now, calendar: calendar) ?? -1, 175, accuracy: 0.001)
        XCTAssertFalse(partial.isPaidForCurrentCycle(now: now, calendar: calendar))
        XCTAssertEqual(partial.urgency(now: now, calendar: calendar, windowDays: 7), .approaching(daysUntil: 2))
    }
}
