import Foundation
import Testing

struct ScannerAdoptionSafetyTests {
    @Test("todo calendar and contact scanners audit canonical row adoption and pruning")
    func calendarAndContactScannersAuditCanonicalRowChanges() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let files = [
            repoRoot.appendingPathComponent("Sources/Cider/Services/TodoCardStorage.swift"),
            repoRoot.appendingPathComponent("Sources/Cider/Services/DateCardStorage.swift"),
            repoRoot.appendingPathComponent("Sources/Cider/Services/ContactStorage.swift"),
        ]
        var violations: [String] = []

        for fileURL in files {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let relativePath = fileURL.path.replacingOccurrences(of: repoRoot.path + "/", with: "")

            let adoptedBlock = try #require(
                block(
                    named: "if !adopted",
                    in: source
                ),
                "Could not find adopted persistence block in \(relativePath)"
            )
            if !adoptedBlock.contains("MutationAuditService(database: resolvedDatabase).record(") {
                violations.append("\(relativePath): adopted scanner rows are persisted without mutation audit")
            }

            let syncBlock = try #require(
                block(
                    named: "private func syncScanToDatabase",
                    in: source
                ),
                "Could not find syncScanToDatabase in \(relativePath)"
            )
            if syncBlock.contains("DELETE FROM items")
                && !syncBlock.contains("MutationAuditService(database: resolvedDatabase).record(") {
                violations.append("\(relativePath): scanner pruning deletes canonical rows without mutation audit")
            }
        }

        #expect(violations.isEmpty, "Scanner canonical row changes need provenance:\n\(violations.joined(separator: "\n"))")
    }

    private func block(named marker: String, in source: String) -> String? {
        guard let markerRange = source.range(of: marker) else { return nil }
        let tail = source[markerRange.lowerBound...]
        guard let openBrace = tail.firstIndex(of: "{") else { return nil }
        var depth = 0
        var cursor = openBrace
        while cursor < source.endIndex {
            let char = source[cursor]
            if char == "{" {
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[markerRange.lowerBound...cursor])
                }
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }
}
