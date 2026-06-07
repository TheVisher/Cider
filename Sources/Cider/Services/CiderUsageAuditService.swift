import Foundation
import os

enum CiderUsageAuditSource: String, Codable, Sendable {
    case app
    case cli
}

struct CiderUsageAuditEvent: Codable, Equatable, Sendable {
    var timestamp: Date
    var source: CiderUsageAuditSource
    var surface: String
    var domain: String?
    var route: String?
    var commandFamily: String?
    var outcome: String?
}

struct CiderUsageAuditGroup: Codable, Equatable, Sendable {
    var key: String
    var count: Int
    var latestTimestamp: Date
}

struct CiderUsageAuditReport: Codable, Equatable, Sendable {
    var generatedAt: Date
    var since: Date
    var eventCount: Int
    var sourceCounts: [CiderUsageAuditGroup]
    var surfaceCounts: [CiderUsageAuditGroup]
    var domainCounts: [CiderUsageAuditGroup]
    var routeCounts: [CiderUsageAuditGroup]
    var commandFamilyCounts: [CiderUsageAuditGroup]
    var privacy: [String]
}

struct CiderUsageAuditService: Sendable {
    static let shared = CiderUsageAuditService()
    static let privacyRules = [
        "Records local-only event categories, never cloud telemetry.",
        "CLI events persist command family only, not arguments.",
        "App events persist surface/domain/route only, not queries, URLs, titles, or note bodies.",
        "Arbitrary values are normalized to a small safe character set before writing."
    ]

    private let logURL: URL
    private let now: @Sendable () -> Date
    private let logger = Logger(subsystem: "com.cider.app", category: "UsageAudit")

    init(
        logURL: URL = CiderUsageAuditService.defaultLogURL(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.logURL = logURL
        self.now = now
    }

    static func defaultLogURL() -> URL {
        StoragePaths.cachedVaultDirectoryURL
            .appendingPathComponent(".cider")
            .appendingPathComponent("usage-audit.jsonl")
    }

    func recordCLI(command: String, subcommand: String?) {
        let family = sanitizedCommandFamily(command: command, subcommand: subcommand)
        record(
            CiderUsageAuditEvent(
                timestamp: now(),
                source: .cli,
                surface: "cli",
                domain: nil,
                route: nil,
                commandFamily: family,
                outcome: nil
            )
        )
    }

    func recordAppRouteOpen(domain: String?, route: String?, outcome: String? = "navigated") {
        let safeDomain = sanitize(domain)
        let safeRoute = sanitize(route)
        record(
            CiderUsageAuditEvent(
                timestamp: now(),
                source: .app,
                surface: safeDomain ?? safeRoute ?? "app",
                domain: safeDomain,
                route: safeRoute,
                commandFamily: nil,
                outcome: sanitize(outcome)
            )
        )
    }

    func record(_ event: CiderUsageAuditEvent) {
        do {
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoded = try JSONEncoder.ciderUsageAudit.encode(event)
            var output = encoded
            output.append(0x0A)
            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: output)
            } else {
                try output.write(to: logURL, options: .atomic)
            }
        } catch {
            logger.error("Failed to write usage audit event: \(String(describing: error), privacy: .public)")
        }
    }

    func loadEvents() -> [CiderUsageAuditEvent] {
        guard
            FileManager.default.fileExists(atPath: logURL.path),
            let data = try? Data(contentsOf: logURL),
            let content = String(data: data, encoding: .utf8)
        else {
            return []
        }

        return content
            .split(separator: "\n")
            .compactMap { line in
                guard let data = String(line).data(using: .utf8) else { return nil }
                return try? JSONDecoder.ciderUsageAudit.decode(CiderUsageAuditEvent.self, from: data)
            }
    }

    func report(days: Int = 30, limit: Int = 20) -> CiderUsageAuditReport {
        let generatedAt = now()
        let since = Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: -max(1, days), to: generatedAt) ?? generatedAt
        let events = loadEvents().filter { $0.timestamp >= since }
        let boundedLimit = max(1, limit)

        return CiderUsageAuditReport(
            generatedAt: generatedAt,
            since: since,
            eventCount: events.count,
            sourceCounts: grouped(events, limit: boundedLimit) { $0.source.rawValue },
            surfaceCounts: grouped(events, limit: boundedLimit) { $0.surface },
            domainCounts: grouped(events, limit: boundedLimit) { $0.domain },
            routeCounts: grouped(events, limit: boundedLimit) { $0.route },
            commandFamilyCounts: grouped(events, limit: boundedLimit) { $0.commandFamily },
            privacy: Self.privacyRules
        )
    }

    static func reportToDict(_ report: CiderUsageAuditReport) -> [String: Any] {
        [
            "ok": true,
            "generatedAt": ISO8601DateFormatter().string(from: report.generatedAt),
            "since": ISO8601DateFormatter().string(from: report.since),
            "eventCount": report.eventCount,
            "sourceCounts": report.sourceCounts.map(groupToDict),
            "surfaceCounts": report.surfaceCounts.map(groupToDict),
            "domainCounts": report.domainCounts.map(groupToDict),
            "routeCounts": report.routeCounts.map(groupToDict),
            "commandFamilyCounts": report.commandFamilyCounts.map(groupToDict),
            "privacy": report.privacy,
        ]
    }

    static func groupToDict(_ group: CiderUsageAuditGroup) -> [String: Any] {
        [
            "key": group.key,
            "count": group.count,
            "latestTimestamp": ISO8601DateFormatter().string(from: group.latestTimestamp),
        ]
    }

    private func grouped(
        _ events: [CiderUsageAuditEvent],
        limit: Int,
        by key: (CiderUsageAuditEvent) -> String?
    ) -> [CiderUsageAuditGroup] {
        var counts: [String: (count: Int, latest: Date)] = [:]
        for event in events {
            guard let rawKey = key(event), !rawKey.isEmpty else { continue }
            let current = counts[rawKey] ?? (0, event.timestamp)
            counts[rawKey] = (current.count + 1, max(current.latest, event.timestamp))
        }
        return counts.map { CiderUsageAuditGroup(key: $0.key, count: $0.value.count, latestTimestamp: $0.value.latest) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                if $0.latestTimestamp != $1.latestTimestamp { return $0.latestTimestamp > $1.latestTimestamp }
                return $0.key.localizedStandardCompare($1.key) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    private func sanitizedCommandFamily(command: String, subcommand: String?) -> String {
        let safeCommand = sanitize(command) ?? "unknown"
        guard let safeSubcommand = sanitize(subcommand), !safeSubcommand.isEmpty else {
            return safeCommand
        }
        return "\(safeCommand).\(safeSubcommand)"
    }

    private func sanitize(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains(":") || trimmed.contains("?") || trimmed.contains("/") || trimmed.contains("\\") {
            return "redacted"
        }
        let sanitized = trimmed.unicodeScalars.map { scalar -> String in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" || scalar == "."
                ? String(scalar)
                : "_"
        }.joined()
        return String(sanitized.prefix(80))
    }
}

private extension JSONEncoder {
    static var ciderUsageAudit: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var ciderUsageAudit: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
