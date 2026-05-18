import Foundation
import Testing

struct CaptureParitySafetyTests {
    @Test("app and agent note creation use the canonical capture service")
    func noteCreationUsesCanonicalCaptureService() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let files = [
            repoRoot.appendingPathComponent("Sources/Cider/Views/CiderPanelView+QuickActions.swift"),
            repoRoot.appendingPathComponent("Sources/Cider/Services/AI/MLXToolExecutor.swift"),
        ]
        var violations: [String] = []

        for fileURL in files {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let relativePath = fileURL.path.replacingOccurrences(of: repoRoot.path + "/", with: "")
            let functionName = relativePath.contains("MLXToolExecutor")
                ? "private static func createNote"
                : "func createNoteAndOpen"
            let body = try #require(block(named: functionName, in: source), "Could not find \(functionName) in \(relativePath)")

            if !body.contains("CiderCaptureService().addNoteCapture(") {
                violations.append("\(relativePath): \(functionName) does not create notes through CiderCaptureService")
            }
            if body.contains("NotesStorage.shared.createNew(") {
                violations.append("\(relativePath): \(functionName) still creates notes through NotesStorage directly")
            }
        }

        #expect(violations.isEmpty, "Note capture paths must use the canonical capture door:\n\(violations.joined(separator: "\n"))")
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
