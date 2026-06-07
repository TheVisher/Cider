import Foundation
import Testing
@testable import Cider

struct CiderUsageAuditServiceTests {
    @Test("usage audit records local app and CLI categories and groups them in reports")
    func recordsAndReportsUsageCategories() throws {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-usage-audit-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: logURL) }

        let baseDate = try #require(ISO8601DateFormatter().date(from: "2026-06-06T20:00:00Z"))
        let service = CiderUsageAuditService(logURL: logURL, now: { baseDate })

        service.recordAppRouteOpen(domain: "Library", route: "search")
        service.recordAppRouteOpen(domain: "Review", route: "review")
        service.recordCLI(command: "item", subcommand: "search")
        service.recordCLI(command: "item", subcommand: "search")

        let events = service.loadEvents()
        #expect(events.count == 4)
        #expect(events.map(\.source).contains(.app))
        #expect(events.map(\.source).contains(.cli))

        let report = service.report(days: 7, limit: 10)
        #expect(report.eventCount == 4)
        #expect(report.surfaceCounts.first(where: { $0.key == "cli" })?.count == 2)
        #expect(report.domainCounts.first(where: { $0.key == "Library" })?.count == 1)
        #expect(report.routeCounts.first(where: { $0.key == "review" })?.count == 1)
        #expect(report.commandFamilyCounts.first(where: { $0.key == "item.search" })?.count == 2)
    }

    @Test("usage audit does not persist raw CLI arguments or query-like app values")
    func redactsRawContentAndArguments() throws {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-usage-audit-privacy-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: logURL) }

        let service = CiderUsageAuditService(logURL: logURL)

        service.recordCLI(command: "item", subcommand: "search")
        service.recordAppRouteOpen(domain: "Search: private family query", route: "library/search?query=secret")

        let log = try String(contentsOf: logURL, encoding: .utf8)
        #expect(log.contains("item.search"))
        #expect(!log.contains("private family query"))
        #expect(!log.contains("secret"))
        #expect(!log.contains("library/search"))
        #expect(log.contains("redacted"))
    }

    @Test("usage audit JSON formatter includes privacy rules")
    func jsonFormatterIncludesPrivacyRules() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-06-06T20:00:00Z"))
        let report = CiderUsageAuditReport(
            generatedAt: date,
            since: date,
            eventCount: 1,
            sourceCounts: [CiderUsageAuditGroup(key: "cli", count: 1, latestTimestamp: date)],
            surfaceCounts: [],
            domainCounts: [],
            routeCounts: [],
            commandFamilyCounts: [CiderUsageAuditGroup(key: "usage.report", count: 1, latestTimestamp: date)],
            privacy: CiderUsageAuditService.privacyRules
        )

        let dict = CiderUsageAuditService.reportToDict(report)

        #expect(dict["eventCount"] as? Int == 1)
        #expect((dict["privacy"] as? [String])?.contains { $0.contains("not arguments") } == true)
        let commandGroups = try #require(dict["commandFamilyCounts"] as? [[String: Any]])
        let firstKey = commandGroups.first?["key"] as? String
        #expect(firstKey == "usage.report")
    }
}
