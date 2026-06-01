import Foundation
import Testing
@testable import Cider

@Suite(.serialized)
@MainActor
struct AgentCaptureToolResultTests {
    private func makeTempVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-agent-capture-tool-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func withSharedIsolatedVault<T>(_ body: () throws -> T) throws -> T {
        let previousOverride = StoragePaths.vaultOverride
        let vault = try makeTempVault()
        CiderDatabase.shared.close()
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()
        StoragePaths.ensureVaultStructure()
        let dbURL = vault.appendingPathComponent(".cider/cider.db")
        try FileManager.default.createDirectory(
            at: dbURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try CiderDatabase.shared.open(at: dbURL)
        ReminderReconciler.shared.setSkipReconcileWorkForTesting(true)
        defer {
            ReminderReconciler.shared.setSkipReconcileWorkForTesting(false)
            CiderDatabase.shared.close()
            StoragePaths.vaultOverride = previousOverride
            StoragePaths.invalidateCachedDirectory()
            try? FileManager.default.removeItem(at: vault)
        }
        return try body()
    }

    private func withSharedIsolatedVault<T>(_ body: () async throws -> T) async throws -> T {
        let previousOverride = StoragePaths.vaultOverride
        let vault = try makeTempVault()
        CiderDatabase.shared.close()
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()
        StoragePaths.ensureVaultStructure()
        let dbURL = vault.appendingPathComponent(".cider/cider.db")
        try FileManager.default.createDirectory(
            at: dbURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try CiderDatabase.shared.open(at: dbURL)
        ReminderReconciler.shared.setSkipReconcileWorkForTesting(true)
        defer {
            ReminderReconciler.shared.setSkipReconcileWorkForTesting(false)
            CiderDatabase.shared.close()
            StoragePaths.vaultOverride = previousOverride
            StoragePaths.invalidateCachedDirectory()
            try? FileManager.default.removeItem(at: vault)
        }
        return try await body()
    }

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

    @Test("agent reminder and summary save tools use structured capture results")
    func agentReminderAndSummarySaveToolsUseStructuredCaptureResults() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let files: [(URL, [String])] = [
            (
                repoRoot.appendingPathComponent("Sources/Cider/Services/AI/MLXToolExecutor.swift"),
                ["private static func createReminder"]
            ),
            (
                repoRoot.appendingPathComponent("Sources/Cider/Services/AI/AIAssistantTools.swift"),
                ["struct CreateReminderTool", "struct SummarizeTextTool"]
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

        #expect(violations.isEmpty, "Agent reminder and summary-save tools must return structured capture payloads:\n\(violations.joined(separator: "\n"))")
    }

    @Test("MLX create reminder returns a structured capture payload")
    func mlxCreateReminderReturnsStructuredCapturePayload() throws {
        try withSharedIsolatedVault {
            let output = MLXToolExecutor.execute(
                name: "createReminder",
                arguments: [
                    "title": "CID343 structured reminder",
                    "date": "2026-06-15",
                    "details": "Verify assistant reminder capture JSON",
                    "remindMinutesBefore": 30,
                ]
            )
            let payload = try decodeJSON(output)

            #expect(payload["toolResultVersion"] as? Int == 1)
            #expect(payload["kind"] as? String == "capture")
            #expect(payload["ok"] as? Bool == true)
            #expect((payload["message"] as? String)?.contains("Created reminder") == true)
            #expect(payload["nextSafeAction"] as? String != nil)

            let item = try #require(payload["item"] as? [String: Any])
            let itemID = try #require(item["id"] as? String)
            let itemType = try #require(item["type"] as? String)
            #expect(item["ref"] as? String == "\(itemType):\(itemID)")

            let capture = try #require(payload["capture"] as? [String: Any])
            let source = try #require(capture["source"] as? [String: Any])
            #expect(source["itemID"] as? String == itemID)
            #expect(source["itemType"] as? String == itemType)
            #expect(capture["routing"] as? [String: Any] != nil)
            #expect(capture["provenance"] as? [String: Any] != nil)
            #expect(capture["indexing"] as? [String: Any] != nil)

            let safeNextCommands = try #require(payload["safeNextCommands"] as? [String])
            #expect(safeNextCommands.contains("cider-cli item get \(itemType) \(itemID) --json"))
        }
    }

    @Test("MLX create reminder reports final persisted indexing trace")
    func mlxCreateReminderReportsFinalPersistedIndexingTrace() throws {
        try withSharedIsolatedVault {
            let output = MLXToolExecutor.execute(
                name: "createReminder",
                arguments: [
                    "title": "CID343 final indexing reminder",
                    "date": "2026-06-16",
                    "details": "Verify final persisted recurrence indexing",
                    "frequency": "weekly",
                    "remindMinutesBefore": 45,
                ]
            )
            let payload = try decodeJSON(output)
            let item = try #require(payload["item"] as? [String: Any])
            let itemID = try #require(item["id"] as? String)
            let capture = try #require(payload["capture"] as? [String: Any])
            let indexing = try #require(capture["indexing"] as? [String: Any])
            let chunks = try #require(indexing["chunks"] as? [[String: Any]])
            let responseChunkID = try #require(chunks.first?["id"] as? String)
            let currentChunk = try #require(try contentChunk(ownerType: "dateCard", ownerID: itemID))

            #expect(indexing["status"] as? String == "indexed")
            #expect(responseChunkID == currentChunk.id)
            #expect(currentChunk.body.contains("Recurrence:"))
            #expect(currentChunk.body.contains("weekly"))
        }
    }

    @Test("MLX create reminder validates invalid frequency before capture")
    func mlxCreateReminderValidatesInvalidFrequencyBeforeCapture() throws {
        try withSharedIsolatedVault {
            let beforeCount = DateCardStorage.shared.dateCards.count
            let output = MLXToolExecutor.execute(
                name: "createReminder",
                arguments: [
                    "title": "CID343 invalid frequency reminder",
                    "date": "2026-06-17",
                    "frequency": "fortnightly",
                ]
            )
            let payload = try decodeJSON(output)
            let error = try #require(payload["error"] as? [String: Any])

            #expect(payload["ok"] as? Bool == false)
            #expect(error["code"] as? String == "invalid_reminder_frequency")
            #expect(payload["item"] == nil)
            #expect(DateCardStorage.shared.dateCards.count == beforeCount)
        }
    }

    @Test("MLX create reminder reports update failure with capture identity")
    func mlxCreateReminderReportsUpdateFailureWithCaptureIdentity() throws {
        try withSharedIsolatedVault {
            AgentReminderToolSupport._setDateCardUpdateHandlerForTesting { _ in false }
            defer { AgentReminderToolSupport._resetDateCardUpdateHandlerForTesting() }

            let output = MLXToolExecutor.execute(
                name: "createReminder",
                arguments: [
                    "title": "CID343 update failure reminder",
                    "date": "2026-06-18",
                    "details": "This capture succeeds before reminder mutation fails",
                    "frequency": "monthly",
                ]
            )
            let payload = try decodeJSON(output)
            let item = try #require(payload["item"] as? [String: Any])
            let itemID = try #require(item["id"] as? String)
            let failures = try #require(payload["partialFailures"] as? [[String: Any]])
            let safeNextCommands = try #require(payload["safeNextCommands"] as? [String])

            #expect(payload["ok"] as? Bool == false)
            #expect(item["type"] as? String == "event")
            #expect(failures.contains { $0["status"] as? String == "reminder_update_failed" })
            #expect(safeNextCommands.contains("cider-cli item get event \(itemID) --json"))
        }
    }

    @Test("assistant create reminder reports update failure with capture identity")
    func assistantCreateReminderReportsUpdateFailureWithCaptureIdentity() async throws {
        try await withSharedIsolatedVault {
            AgentReminderToolSupport._setDateCardUpdateHandlerForTesting { _ in false }
            defer { AgentReminderToolSupport._resetDateCardUpdateHandlerForTesting() }

            let output = try await CreateReminderTool().call(
                arguments: CreateReminderTool.Arguments(
                    title: "CID343 assistant update failure reminder",
                    date: "2026-06-19",
                    frequency: "yearly",
                    remindMinutesBefore: 60,
                    secondRemindMinutesBefore: nil,
                    allDay: true,
                    location: nil,
                    details: "Foundation tool capture succeeds before reminder mutation fails"
                )
            )
            let payload = try decodeJSON(output)
            let item = try #require(payload["item"] as? [String: Any])
            let itemID = try #require(item["id"] as? String)
            let failures = try #require(payload["partialFailures"] as? [[String: Any]])
            let safeNextCommands = try #require(payload["safeNextCommands"] as? [String])

            #expect(payload["ok"] as? Bool == false)
            #expect(item["type"] as? String == "event")
            #expect(failures.contains { $0["status"] as? String == "reminder_update_failed" })
            #expect(safeNextCommands.contains("cider-cli item get event \(itemID) --json"))
        }
    }

    @Test("summary save tool executes and returns structured capture JSON")
    func summarySaveToolExecutesStructuredCaptureJSON() async throws {
        try await withSharedIsolatedVault {
            SummaryService.shared._setSummarizeArticleOverrideForTesting { _ in
                "CID343 saved summary body from test override."
            }
            defer { SummaryService.shared._resetSummarizeArticleOverrideForTesting() }

            let output = try await SummarizeTextTool().call(
                arguments: SummarizeTextTool.Arguments(
                    text: "A long pasted article for summary-save JSON verification.",
                    saveAsNote: true,
                    noteTitle: "CID343 Summary Save",
                    folderName: nil
                )
            )
            let payload = try decodeJSON(output)
            let item = try #require(payload["item"] as? [String: Any])
            let capture = try #require(payload["capture"] as? [String: Any])

            #expect(payload["toolResultVersion"] as? Int == 1)
            #expect(payload["kind"] as? String == "capture")
            #expect(payload["ok"] as? Bool != nil)
            #expect(item["type"] as? String == "note")
            #expect(capture["indexing"] as? [String: Any] != nil)
        }
    }

    private func decodeJSON(_ output: String) throws -> [String: Any] {
        let data = Data(output.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    private func contentChunk(ownerType: String, ownerID: String) throws -> (id: String, body: String)? {
        let stmt = try CiderDatabase.shared.prepare("""
            SELECT id, body
            FROM content_chunks
            WHERE owner_type = ? AND owner_id = ?
            ORDER BY chunk_index ASC
            LIMIT 1;
            """)
        stmt.bind(ownerType, at: 1)
            .bind(ownerID, at: 2)
        guard try stmt.step() else { return nil }
        return (stmt.string(at: 0), stmt.string(at: 1))
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
