import Foundation
import Testing
@testable import Cider

@Suite("Capture Event Writer Coverage Tests")
struct CaptureEventWriterCoverageTests {
    @Test("every production capture event insertion uses the provenance contract")
    func everyProductionCaptureEventInsertionUsesTheProvenanceContract() throws {
        let report = try CaptureEventWriterCoverageGuard.auditRepository(at: Self.repositoryRoot)

        #expect(report.productionWriters == [
            .init(
                relativePath: "Sources/Cider/Services/ChatCaptureIntakeService.swift",
                functionName: "recordUnsupportedAttachmentReview",
                outcome: "skipped"
            ),
            .init(
                relativePath: "Sources/Cider/Services/CiderCaptureService.swift",
                functionName: "attachCaptureEvent",
                outcome: "completed"
            ),
            .init(
                relativePath: "Sources/CiderCLI/CiderCLI.swift",
                functionName: "recordJournalCaptureProvenance",
                outcome: "completed"
            ),
        ])
        #expect(report.violations.isEmpty, "\(report.violations.joined(separator: "\n"))")
        #expect(report.testOnlyInsertionCount > 0)
        #expect(report.intentionallyExemptProductionBoundaries == [
            "Sources/Cider/Database/CiderSchema.swift: schema DDL only",
            "Sources/Cider/Database/DatabaseMigrations.swift: schema/index migration only",
            "Sources/Cider/Services/CiderStorageAuditService.swift: schema repair DDL only",
            "Sources/CiderCLI/CiderCLI.swift: test-run cleanup deletion is not creation",
        ])
    }

    @Test("synthetic direct insertion bypass fails the guard")
    func syntheticDirectInsertionBypassFailsTheGuard() {
        let source = """
        func futureWriter() throws {
            let statement = try database.prepare("INSERT INTO capture_events (id) VALUES (?);")
            try statement.step()
        }
        """

        let report = CaptureEventWriterCoverageGuard.auditSource(
            source,
            relativePath: "Sources/Cider/Services/FutureCaptureWriter.swift"
        )

        #expect(report.productionWriters.isEmpty)
        #expect(report.violations == [
            "Sources/Cider/Services/FutureCaptureWriter.swift:2 futureWriter inserts capture_events without CaptureEventProvenanceContract.metadata"
        ])
    }

    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private enum CaptureEventWriterCoverageGuard {
    struct Writer: Equatable {
        let relativePath: String
        let functionName: String
        let outcome: String
    }

    struct Report {
        var productionWriters: [Writer] = []
        var violations: [String] = []
        var testOnlyInsertionCount = 0
        var intentionallyExemptProductionBoundaries: [String] = []
    }

    private struct Exemption {
        let relativePath: String
        let reason: String
        let evidence: String

        var description: String {
            "\(relativePath): \(reason)"
        }
    }

    private static let insertionPattern = #"\bINSERT\s+(?:OR\s+\w+\s+)?INTO\s+capture_events\b"#
    private static let functionPattern = #"(?m)^\s*(?:(?:private|fileprivate|internal|package|public|static|class|final)\s+)*func\s+([A-Za-z_][A-Za-z0-9_]*)"#
    private static let markerPattern = #"CaptureEventProvenanceContract\.metadata\s*\([\s\S]*?outcome:\s*\.([A-Za-z]+)"#

    private static let exemptions = [
        Exemption(
            relativePath: "Sources/Cider/Database/CiderSchema.swift",
            reason: "schema DDL only",
            evidence: "CREATE TABLE IF NOT EXISTS capture_events"
        ),
        Exemption(
            relativePath: "Sources/Cider/Database/DatabaseMigrations.swift",
            reason: "schema/index migration only",
            evidence: "CREATE INDEX IF NOT EXISTS idx_capture_events_source"
        ),
        Exemption(
            relativePath: "Sources/Cider/Services/CiderStorageAuditService.swift",
            reason: "schema repair DDL only",
            evidence: "CREATE INDEX IF NOT EXISTS idx_capture_events_source"
        ),
        Exemption(
            relativePath: "Sources/CiderCLI/CiderCLI.swift",
            reason: "test-run cleanup deletion is not creation",
            evidence: "DELETE FROM capture_events WHERE id = ?"
        ),
    ]

    static func auditRepository(at root: URL) throws -> Report {
        var report = Report()
        let productionRoot = root.appendingPathComponent("Sources", isDirectory: true)

        for file in try swiftFiles(under: productionRoot) {
            let relativePath = relativePath(for: file, root: root)
            let source = try String(contentsOf: file, encoding: .utf8)
            let fileReport = auditSource(source, relativePath: relativePath)
            report.productionWriters.append(contentsOf: fileReport.productionWriters)
            report.violations.append(contentsOf: fileReport.violations)
        }

        let testsRoot = root.appendingPathComponent("Tests", isDirectory: true)
        for file in try swiftFiles(under: testsRoot) {
            let source = try String(contentsOf: file, encoding: .utf8)
            report.testOnlyInsertionCount += matches(insertionPattern, in: source).count
        }

        for exemption in exemptions {
            let file = root.appendingPathComponent(exemption.relativePath)
            let source = try String(contentsOf: file, encoding: .utf8)
            if source.contains(exemption.evidence) {
                report.intentionallyExemptProductionBoundaries.append(exemption.description)
            } else {
                report.violations.append(
                    "\(exemption.relativePath) no longer contains bounded exemption evidence: \(exemption.evidence)"
                )
            }
        }

        report.productionWriters.sort {
            ($0.relativePath, $0.functionName, $0.outcome)
                < ($1.relativePath, $1.functionName, $1.outcome)
        }
        return report
    }

    static func auditSource(_ source: String, relativePath: String) -> Report {
        var report = Report()
        let functionMatches = matches(functionPattern, in: source)

        for insertion in matches(insertionPattern, in: source) {
            let function = functionMatches.last { $0.range.location < insertion.range.location }
            let functionName = function.flatMap { capture(1, from: $0, in: source) } ?? "<unknown>"
            let functionStart = function?.range.location ?? 0
            let boundedStart = max(functionStart, insertion.range.location - 1_200)
            let markerSearchRange = NSRange(
                location: boundedStart,
                length: insertion.range.location - boundedStart
            )
            let marker = matches(markerPattern, in: source, range: markerSearchRange).last
            let line = sourceLine(at: insertion.range.location, in: source)

            guard let marker,
                  let outcome = capture(1, from: marker, in: source) else {
                report.violations.append(
                    "\(relativePath):\(line) \(functionName) inserts capture_events without CaptureEventProvenanceContract.metadata"
                )
                continue
            }

            report.productionWriters.append(Writer(
                relativePath: relativePath,
                functionName: functionName,
                outcome: outcome
            ))
        }

        return report
    }

    private static func swiftFiles(under root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        return enumerator.compactMap { element in
            guard let url = element as? URL, url.pathExtension == "swift" else {
                return nil
            }
            return url
        }
        .sorted { $0.path < $1.path }
    }

    private static func relativePath(for file: URL, root: URL) -> String {
        let prefix = root.path.hasSuffix("/") ? root.path : "\(root.path)/"
        guard file.path.hasPrefix(prefix) else { return file.path }
        return String(file.path.dropFirst(prefix.count))
    }

    private static func matches(
        _ pattern: String,
        in source: String,
        range: NSRange? = nil
    ) -> [NSTextCheckingResult] {
        let expression = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        return expression.matches(
            in: source,
            range: range ?? NSRange(source.startIndex..., in: source)
        )
    }

    private static func capture(
        _ index: Int,
        from match: NSTextCheckingResult,
        in source: String
    ) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound,
              let swiftRange = Range(range, in: source) else {
            return nil
        }
        return String(source[swiftRange])
    }

    private static func sourceLine(at utf16Offset: Int, in source: String) -> Int {
        let prefix = String(source.utf16.prefix(utf16Offset)) ?? ""
        return prefix.reduce(into: 1) { line, character in
            if character == "\n" { line += 1 }
        }
    }
}
