import Foundation
import Testing
@testable import Cider

@MainActor
struct AgentCaptureToolResultTests {
    @Test("agent capture tool formatter returns structured success payload")
    func agentCaptureToolFormatterReturnsStructuredSuccessPayload() throws {
        let itemID = UUID()
        let decisionID = UUID()
        let result = CiderCaptureResult(
            command: "capture.add",
            source: .init(
                kind: "text",
                url: nil,
                file: nil,
                text: "Ship structured agent results",
                itemID: itemID,
                itemType: "note"
            ),
            item: .init(
                id: itemID,
                type: "note",
                title: "Structured Agent Results",
                relativePath: "Inbox/Notes/Structured Agent Results.md",
                folderID: nil,
                folderName: "Inbox"
            ),
            enrichment: .init(
                status: "not_applicable",
                isEnriching: false,
                titleState: "manual",
                lastEnrichedAt: nil
            ),
            duplicate: .init(status: "not_checked", existingItemID: nil),
            routing: .init(
                decisionID: decisionID,
                candidateTarget: .init(
                    kind: "folder",
                    name: "Inbox",
                    relativePath: "Inbox/Notes",
                    folderID: nil
                ),
                reviewNeeded: true,
                confidence: 0.0,
                reason: "Kept for review.",
                reviewState: "needs_review"
            ),
            nextSafeAction: "review_route"
        )

        let output = AgentCaptureToolResultFormatter.jsonString(
            message: "Created note \"Structured Agent Results\".",
            captureResult: result
        )
        let payload = try decodeJSON(output)

        #expect(payload["kind"] as? String == "capture")
        #expect(payload["message"] as? String == "Created note \"Structured Agent Results\".")
        #expect(payload["nextSafeAction"] as? String == "review_route")
        #expect((payload["partialFailures"] as? [[String: Any]])?.isEmpty == true)

        let item = try #require(payload["item"] as? [String: Any])
        #expect(item["id"] as? String == itemID.uuidString)
        #expect(item["type"] as? String == "note")
        #expect(item["ref"] as? String == "note:\(itemID.uuidString)")

        let routing = try #require(payload["routing"] as? [String: Any])
        #expect(routing["reviewState"] as? String == "needs_review")
        #expect(routing["reviewNeeded"] as? Bool == true)

        let duplicate = try #require(payload["duplicate"] as? [String: Any])
        #expect(duplicate["status"] as? String == "not_checked")

        let capture = try #require(payload["capture"] as? [String: Any])
        #expect(capture["command"] as? String == "capture.add")
    }

    @Test("agent capture tool formatter exposes partial failures")
    func agentCaptureToolFormatterExposesPartialFailures() throws {
        let itemID = UUID()
        let requestedFolderID = UUID()
        let result = CiderCaptureResult(
            command: "capture.add",
            source: .init(
                kind: "text",
                url: nil,
                file: nil,
                text: "Folder assignment should be visible",
                itemID: itemID,
                itemType: "note"
            ),
            item: .init(
                id: itemID,
                type: "note",
                title: "Assignment Failed",
                relativePath: "Inbox/Notes/Assignment Failed.md",
                folderID: nil,
                folderName: "Inbox"
            ),
            enrichment: .init(
                status: "not_applicable",
                isEnriching: false,
                titleState: "manual",
                lastEnrichedAt: nil
            ),
            duplicate: .init(status: "not_checked", existingItemID: nil),
            routing: .init(
                decisionID: nil,
                candidateTarget: nil,
                reviewNeeded: true,
                confidence: 0.0,
                reason: "Kept for review.",
                reviewState: "needs_review"
            ),
            nextSafeAction: "review_route",
            partialSuccess: .init(
                status: "assignment_failed",
                reason: "Could not assign note to requested folder.",
                requestedFolderID: requestedFolderID,
                actualFolderID: nil
            )
        )

        let output = AgentCaptureToolResultFormatter.jsonString(
            message: "Created note \"Assignment Failed\" but failed to move it.",
            captureResult: result,
            additionalPartialFailures: [
                [
                    "status": "tag_assignment_failed",
                    "reason": "Could not assign requested tag."
                ]
            ]
        )
        let payload = try decodeJSON(output)
        let failures = try #require(payload["partialFailures"] as? [[String: Any]])

        #expect(failures.count == 2)
        #expect(failures[0]["status"] as? String == "assignment_failed")
        #expect(failures[0]["requestedFolderID"] as? String == requestedFolderID.uuidString)
        #expect(failures[1]["status"] as? String == "tag_assignment_failed")
    }

    @Test("agent note and bookmark tools use structured capture results")
    func agentNoteAndBookmarkToolsUseStructuredCaptureResults() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let files: [(URL, [String])] = [
            (
                repoRoot.appendingPathComponent("Sources/Cider/Services/AI/MLXToolExecutor.swift"),
                ["private static func createNote", "private static func addBookmark"]
            ),
            (
                repoRoot.appendingPathComponent("Sources/Cider/Services/AI/AIAssistantTools.swift"),
                ["struct CreateNoteTool", "struct AddBookmarkTool"]
            ),
        ]
        var violations: [String] = []

        for (fileURL, markers) in files {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let relativePath = fileURL.path.replacingOccurrences(of: repoRoot.path + "/", with: "")
            for marker in markers {
                guard let body = block(named: marker, in: source) else {
                    violations.append("\(relativePath): missing \(marker) implementation")
                    continue
                }
                if !body.contains("AgentCaptureToolResultFormatter.jsonString(") {
                    violations.append("\(relativePath): \(marker) still returns prose-only capture output")
                }
            }
        }

        #expect(violations.isEmpty, "Agent capture tools must return structured capture payloads:\n\(violations.joined(separator: "\n"))")
    }

    private func decodeJSON(_ output: String) throws -> [String: Any] {
        let data = Data(output.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
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
