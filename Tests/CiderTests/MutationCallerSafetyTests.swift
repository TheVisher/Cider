import Foundation
import Testing

struct MutationCallerSafetyTests {
    @Test("Vault file assignment callers outside undo check the success result")
    func vaultFileAssignmentCallersOutsideUndoCheckSuccessResult() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceRoot = repoRoot.appendingPathComponent("Sources")
        let enumerator = try #require(FileManager.default.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: nil
        ))
        var unchecked: [String] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift" else { continue }
            guard !fileURL.path.hasSuffix("CiderUndoManager.swift") else { continue }
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            for (offset, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                guard line.contains("VaultFileService.shared.assignFile(") else { continue }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let checksResult = trimmed.hasPrefix("guard ")
                    || trimmed.hasPrefix("if ")
                    || trimmed.hasPrefix("let ")
                if !checksResult {
                    let relativePath = fileURL.path.replacingOccurrences(of: repoRoot.path + "/", with: "")
                    unchecked.append("\(relativePath):\(offset + 1): \(trimmed)")
                }
            }
        }

        #expect(unchecked.isEmpty, "Unchecked vault file assignment callers:\n\(unchecked.joined(separator: "\n"))")
    }

    @Test("UI domain assignment callers check the success result before side effects")
    func uiDomainAssignmentCallersCheckSuccessResult() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let scanRoots = [
            repoRoot.appendingPathComponent("Sources/Cider/Views"),
            repoRoot.appendingPathComponent("Sources/Cider/ViewModels"),
        ]
        let assignmentCalls = [
            "VaultBookmarkService.shared.assignBookmark(",
            "bookmarksViewModel.assign(",
            "bvm.assign(",
            "NotesStorage.shared.assignNote(",
            "notesViewModel.assignNote(",
            "nvm.assignNote(",
            "DateCardStorage.shared.assignDateCard(",
            "ContactStorage.shared.assignContact(",
            "TodoCardStorage.shared.assignTodoCard(",
        ]
        var unchecked: [String] = []

        for scanRoot in scanRoots {
            let enumerator = try #require(FileManager.default.enumerator(
                at: scanRoot,
                includingPropertiesForKeys: nil
            ))
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "swift" else { continue }
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                for (offset, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    guard assignmentCalls.contains(where: { line.contains($0) }) else { continue }
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.contains("onAssign") else { continue }
                    let checksResult = trimmed.hasPrefix("guard ")
                        || trimmed.hasPrefix("if ")
                        || trimmed.hasPrefix("let ")
                        || trimmed.hasPrefix("return ")
                    if !checksResult {
                        let relativePath = fileURL.path.replacingOccurrences(of: repoRoot.path + "/", with: "")
                        unchecked.append("\(relativePath):\(offset + 1): \(trimmed)")
                    }
                }
            }
        }

        #expect(unchecked.isEmpty, "Unchecked UI domain assignment callers:\n\(unchecked.joined(separator: "\n"))")
    }
}
