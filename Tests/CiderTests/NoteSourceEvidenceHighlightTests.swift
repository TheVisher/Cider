import Foundation
import Testing

@Suite("Note Source Evidence Highlight Tests")
struct NoteSourceEvidenceHighlightTests {
    @Test("rich editor content pushes replay active find highlights after setContent")
    func richEditorContentPushesReplayActiveFindHighlightsAfterSetContent() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceURL = repoRoot.appendingPathComponent("Sources/Cider/ViewModels/NotesViewModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let pushBody = try #require(
            block(named: "private func pushContentToEditor", in: source),
            "Could not find pushContentToEditor in NotesViewModel"
        )

        #expect(pushBody.contains("reapplyFindQueryAfterEditorContentLoad()"))
    }

    @Test("find replay preserves the visible find bar and current query")
    func findReplayPreservesTheVisibleFindBarAndCurrentQuery() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceURL = repoRoot.appendingPathComponent("Sources/Cider/ViewModels/NotesViewModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let replayBody = try #require(
            block(named: "private func reapplyFindQueryAfterEditorContentLoad", in: source),
            "Could not find reapplyFindQueryAfterEditorContentLoad in NotesViewModel"
        )

        #expect(replayBody.contains("isFindBarVisible"))
        #expect(replayBody.contains("findQuery"))
        #expect(replayBody.contains("runFindCommand(\"findSetQuery\", stringArgument: query)"))
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
