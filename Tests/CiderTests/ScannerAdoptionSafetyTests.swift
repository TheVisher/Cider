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

    @Test("native artifact scanners use path scoped inbox identity and mutable duplicate guards")
    func nativeArtifactScannersUseScopedIdentity() throws {
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
            if source.contains("filenameToUUID") {
                violations.append("\(relativePath): scanner still builds a bare filename reverse lookup")
            }
            if !source.contains("indexedInboxEntry(for filename: String)") {
                violations.append("\(relativePath): scanner does not scope inbox identity to unfiled index entries")
            }
            if source.contains("let allLoadedIDs") {
                violations.append("\(relativePath): scanner freezes loaded IDs before orphan adoption")
            }
            if !source.contains("guard index[") || !source.contains("Skipped duplicate orphan") {
                violations.append("\(relativePath): orphan adoption does not fail closed on duplicate embedded UUIDs")
            }
        }

        #expect(violations.isEmpty, "Native artifact scanner identity regressions:\n\(violations.joined(separator: "\n"))")
    }

    @Test("bookmark vault scan preserves duplicate URL artifacts for review")
    func bookmarkVaultScanPreservesDuplicateURLArtifacts() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fileURL = repoRoot.appendingPathComponent("Sources/Cider/Services/VaultBookmarkService.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        var violations: [String] = []

        if source.contains("seenURLs") {
            violations.append("full vault scan still drops duplicate URL .webloc files before duplicate audit can see them")
        }
        if !source.contains("existingFileExists") {
            violations.append("incremental adoption does not distinguish duplicate URL files from moved files")
        }
        if !source.contains("adopting as separate duplicate candidate") {
            violations.append("duplicate URL .webloc files are not promoted to reviewable duplicate candidates")
        }

        #expect(violations.isEmpty, "Bookmark duplicate artifact regressions:\n\(violations.joined(separator: "\n"))")
    }

    @Test("bookmark and vault file scanners audit missing file pruning")
    func bookmarkAndVaultFileScannersAuditMissingFilePruning() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let files: [(path: String, blockMarker: String, expectedAction: String)] = [
            (
                "Sources/Cider/Services/VaultBookmarkService.swift",
                "private func pruneMissingBookmarksFromDisk",
                "scanner.bookmark.prune_missing_file"
            ),
            (
                "Sources/Cider/Services/VaultFileService.swift",
                "if !staleKeys.isEmpty",
                "scanner.vaultFile.prune_missing_file"
            ),
        ]
        var violations: [String] = []

        for file in files {
            let fileURL = repoRoot.appendingPathComponent(file.path)
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let pruneBlock = try #require(
                block(named: file.blockMarker, in: source),
                "Could not find prune block in \(file.path)"
            )

            guard pruneBlock.contains("DELETE FROM items")
                || pruneBlock.contains("deleteVaultFileFromDatabase") else {
                violations.append("\(file.path): scanner prune block no longer appears to remove canonical rows")
                continue
            }
            if !pruneBlock.contains("MutationAuditService") {
                violations.append("\(file.path): scanner pruning removes canonical rows without mutation audit")
            }
            if !pruneBlock.contains(file.expectedAction) {
                violations.append("\(file.path): scanner pruning missing expected action \(file.expectedAction)")
            }
            if !pruneBlock.contains(#"source: .filesystem"#) {
                violations.append("\(file.path): scanner pruning does not mark audit source as filesystem")
            }
            if !pruneBlock.contains(#""operation": "prune_missing_file""#) {
                violations.append("\(file.path): scanner pruning audit lacks prune_missing_file operation metadata")
            }
        }

        #expect(violations.isEmpty, "Missing-file scanner prune audit regressions:\n\(violations.joined(separator: "\n"))")
    }

    @Test("startup reconcile has isolated shared database scanner harness")
    func startupReconcileHasIsolatedSharedDatabaseScannerHarness() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent("Tests/CiderTests/VaultReconcilerTests.swift"),
            encoding: .utf8
        )

        var violations: [String] = []
        if !source.contains(#"@Suite("VaultReconciler Tests", .serialized)"#) {
            violations.append("VaultReconciler tests that touch shared singletons must be serialized")
        }
        if !source.contains("startupReconcileScansTempVaultThroughSharedDatabase") {
            violations.append("missing temp-vault shared CiderDatabase startup reconcile regression")
        }
        if !source.contains("CiderDatabase.shared.open(at:") {
            violations.append("startup reconcile harness does not open CiderDatabase.shared on an isolated temp DB")
        }
        if !source.contains("StoragePaths.vaultOverride = vault") {
            violations.append("startup reconcile harness does not redirect StoragePaths.vaultOverride")
        }
        if source.contains("Full integration of reconcile() against a temp vault is covered by the") {
            violations.append("VaultReconcilerTests still document shared-DB reconcile integration as manual-only")
        }

        #expect(violations.isEmpty, "Startup reconcile harness regressions:\n\(violations.joined(separator: "\n"))")
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
