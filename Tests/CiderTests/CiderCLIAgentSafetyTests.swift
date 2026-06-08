import Foundation
import Testing
@testable import Cider
@testable import CiderCLI

@Suite("Cider CLI Agent Safety Tests", .serialized)
@MainActor
struct CiderCLIAgentSafetyTests {
    @Test("note JSON exposes project artifact metadata")
    func noteJSONExposesProjectArtifactMetadata() throws {
        let note = Note(
            title: "Cider Project Note",
            relativePath: "Projects/Cider/Notes/Cider Project Note.md",
            projectID: "cider",
            artifactType: "note"
        )

        let dict = noteToDict(note)

        #expect(dict["projectID"] as? String == "cider")
        #expect(dict["artifactType"] as? String == "note")
        #expect(dict["isProjectArtifact"] as? Bool == true)
    }

    @Test("note JSON exposes idea-plan frontmatter classification")
    func noteJSONExposesIdeaPlanFrontmatterClassification() throws {
        let note = Note(
            title: "Parked Native AI Assistant idea plan",
            content: """
            ---
            type: idea-plan
            status: parked
            category: product-surface
            source: CID-461
            dogfoodStatus: unproven
            ---

            # Parked Native AI Assistant
            """,
            relativePath: "Projects/Cider/Plans/Parked Native AI Assistant idea plan.md",
            projectID: "cider",
            artifactType: "plan"
        )

        let dict = noteToDict(note)
        let plan = try #require(dict["planClassification"] as? [String: Any])

        #expect(plan["type"] as? String == "idea-plan")
        #expect(plan["status"] as? String == "parked")
        #expect(plan["category"] as? String == "product-surface")
        #expect(plan["source"] as? String == "CID-461")
        #expect(plan["dogfoodStatus"] as? String == "unproven")
        #expect(plan["isParked"] as? Bool == true)
        #expect(plan["isTemplate"] as? Bool == false)
    }

    @Test("project artifact plan filters use shared frontmatter classification")
    func projectArtifactPlanFiltersUseSharedFrontmatterClassification() throws {
        let note = Note(
            title: "Parked Spaces Media Recipes idea plan",
            content: """
            ---
            type: idea-plan
            status: parked
            category: product-surface
            source: CID-460
            dogfoodStatus: unproven
            ---

            # Parked Spaces, Media, and Recipes
            """,
            relativePath: "Projects/Cider/Plans/Parked Spaces Media Recipes idea plan.md",
            projectID: "cider",
            artifactType: "plan"
        )

        #expect(CiderCLI.projectPlanFiltersMatch(
            note: note,
            status: "parked",
            category: "product-surface",
            dogfoodStatus: "unproven",
            source: "CID-460"
        ))
        #expect(!CiderCLI.projectPlanFiltersMatch(
            note: note,
            status: "active",
            category: nil,
            dogfoodStatus: nil,
            source: nil
        ))
    }

    @Test("regular note JSON marks non-project artifacts")
    func regularNoteJSONMarksNonProjectArtifacts() throws {
        let note = Note(title: "Inbox Note", relativePath: "Inbox/Notes/Inbox Note.md")

        let dict = noteToDict(note)

        #expect(dict["isProjectArtifact"] as? Bool == false)
        #expect(dict["projectID"] == nil)
        #expect(dict["artifactType"] == nil)
    }

    @Test("project artifact help documents typed relation flags")
    func projectArtifactHelpDocumentsTypedRelationFlags() throws {
        let result = try runCLI(args: ["note", "project-artifact", "help"])
        let output = result.stdout

        for snippet in [
            "--card-id <id>",
            "--decided-from-card <id>",
            "--decided-from-note <id>",
            "--source-card <id>",
            "--source-note <id>",
            "--validates-card <id>",
            "--validates-note <id>",
            "--found-bug-in-card <id>",
            "--found-bug-in-note <id>",
            "qa-audits",
            "plans-handoffs"
        ] {
            #expect(output.contains(snippet), "Expected project-artifact help to include \(snippet)")
        }
    }

    @Test("project artifact CLI relation targets use stable relation names")
    func projectArtifactCLIRelationTargetsUseStableRelationNames() throws {
        let targets = CiderCLI.projectArtifactRelationTargets(from: [
            "--card", "2afee0/e60be2",
            "--source-card", "2afee0/8b6f3c",
            "--decided-from-note", "C1A9A0AA",
            "--validates-card", "2afee0/2c0a04",
            "--validates-note", "53A4BDEB",
            "--found-bug-in-card", "2afee0/e60be2",
            "--found-bug-in-note", "D992F5E5"
        ])

        #expect(targets.map(\.relationType) == [
            ProjectArtifactRelationType.documents,
            ProjectArtifactRelationType.decidedFrom,
            ProjectArtifactRelationType.decidedFrom,
            ProjectArtifactRelationType.validates,
            ProjectArtifactRelationType.validates,
            ProjectArtifactRelationType.foundBugIn,
            ProjectArtifactRelationType.foundBugIn
        ])
        #expect(ProjectArtifactRelationType.displayName(for: ProjectArtifactRelationType.documents) == "documents")
        #expect(ProjectArtifactRelationType.displayName(for: ProjectArtifactRelationType.decidedFrom) == "decided from")
        #expect(ProjectArtifactRelationType.displayName(for: ProjectArtifactRelationType.foundBugIn) == "found bug in")

        let dict = CiderCLI.relationToDict(SecondBrainRelation(
            sourceOwner: SecondBrainOwnerRef(ownerType: "note", ownerID: "A890C2F0"),
            targetOwner: SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "2afee0/e60be2"),
            relationType: ProjectArtifactRelationType.foundBugIn,
            evidence: "QA found a bug.",
            source: "test",
            actor: "hermes",
            confidence: 1,
            metadata: [:]
        ))
        #expect(dict["relationType"] as? String == ProjectArtifactRelationType.foundBugIn)
        #expect(dict["relationLabel"] as? String == "found bug in")
    }

    @Test("item get JSON item summary exposes project artifact relation metadata")
    func itemGetJSONItemSummaryExposesProjectArtifactRelationMetadata() throws {
        let noteID = UUID(uuidString: "70EF7C58-E63E-40D8-9D38-FDB023E7FAEE")!
        let noteOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: noteID.uuidString)
        let projectOwner = SecondBrainOwnerRef(ownerType: "project", ownerID: "cider")
        let item = CiderItemSummary(
            id: noteID,
            type: .note,
            title: "Cider Project Note",
            relativePath: "Projects/Cider/Notes/Cider Project Note.md",
            folderID: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let relation = SecondBrainRelation(
            sourceOwner: noteOwner,
            targetOwner: projectOwner,
            relationType: "artifact_of",
            evidence: "Project note belongs to Cider.",
            source: "test",
            actor: "agent",
            confidence: 1,
            metadata: ["artifactType": "note"]
        )
        let bundle = CiderItemContextBundle(
            item: item,
            owner: noteOwner,
            sections: [],
            chunks: [],
            related: [],
            ownerRelations: [relation],
            backlinks: [],
            spaceMemberships: [],
            routingDecisions: [],
            agentActions: [],
            enrichmentOutputs: [],
            captureProvenance: []
        )

        let dict = CiderCLI.itemContextBundleToDict(bundle)
        let itemDict = try #require(dict["item"] as? [String: Any])

        #expect(itemDict["isProjectArtifact"] as? Bool == true)
        #expect(itemDict["projectID"] as? String == "cider")
        #expect(itemDict["artifactType"] as? String == "note")
    }

    @Test("reminder validation errors honor json output")
    func reminderValidationErrorsHonorJSONOutput() throws {
        let result = try runCLI(args: ["reminder", "complete", "todo", "--json"])

        let dict = try parseJSONObject(result.stdout)
        #expect(dict["ok"] as? Bool == false)
        #expect((dict["error"] as? String)?.contains("Usage: cider-cli reminder complete") == true)
    }

    @Test("bookmark date suggestion validation errors honor json output")
    func bookmarkDateSuggestionValidationErrorsHonorJSONOutput() throws {
        let result = try runCLI(args: ["bookmark", "date-suggestions", "--json"])

        let dict = try parseJSONObject(result.stdout)
        #expect(dict["ok"] as? Bool == false)
        #expect(dict["legacyRemoved"] as? Bool == true)
        #expect(dict["replacement"] as? String == "cider-cli review list --kind date-suggestion --json")
    }

    @Test("bookmark date suggestion approval validation errors honor json output")
    func bookmarkDateSuggestionApprovalValidationErrorsHonorJSONOutput() throws {
        let result = try runCLI(args: ["bookmark", "date-suggestions", "approve", "--json"])

        let dict = try parseJSONObject(result.stdout)
        #expect(dict["ok"] as? Bool == false)
        #expect(dict["legacyRemoved"] as? Bool == true)
        #expect(dict["replacement"] as? String == "cider-cli review list --kind date-suggestion --json")
    }

    @Test("review batch enrichment requires explicit confirmation")
    func reviewBatchEnrichmentRequiresExplicitConfirmation() throws {
        let result = try runCLI(args: ["review", "enrich-batch", "--json"])

        let dict = try parseJSONObject(result.stdout)
        #expect(dict["ok"] as? Bool == false)
        #expect((dict["error"] as? String)?.contains("--confirm") == true)
    }

    @Test("item batch plan validates stdin operations without mutating")
    func itemBatchPlanValidatesStdinOperationsWithoutMutating() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-batch-plan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let captureResult = try runCLI(
            args: [
                "capture", "add",
                "--kind", "note",
                "--title", "Batch Plan Source",
                "--stdin",
                "--json",
            ],
            vault: vault,
            stdin: "Move me only after approval."
        )
        let capturePayload = try parseJSONObject(captureResult.stdout)
        let note = try #require(capturePayload["item"] as? [String: Any])
        let noteID = try #require(note["id"] as? String)

        let request = """
        {
          "operations": [
            {
              "id": "move-note",
              "action": "move",
              "type": "note",
              "ref": "\(noteID)",
              "path": "Projects/Cider/Notes"
            }
          ]
        }
        """

        let result = try runCLI(
            args: ["item", "batch-plan", "--stdin", "--json"],
            vault: vault,
            stdin: request
        )
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status == 0)
        #expect(payload["ok"] as? Bool == true)
        #expect(payload["command"] as? String == "item.batch.plan")
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["approvalRequired"] as? Bool == true)
        #expect((payload["requiredApprovalToken"] as? String)?.hasPrefix("APPROVE_BATCH_") == true)
        #expect(payload["nextSafeAction"] as? String == "approve_batch_apply")
        let operations = try #require(payload["operations"] as? [[String: Any]])
        #expect(operations.count == 1)
        #expect(operations.first?["status"] as? String == "valid")
        #expect(operations.first?["action"] as? String == "move")
        #expect(operations.first?["targetRelativePath"] as? String == "Projects/Cider/Notes")

        let inspectResult = try runCLI(
            args: ["item", "get", "note", noteID, "--json"],
            vault: vault
        )
        let inspected = try parseJSONObject(inspectResult.stdout)
        let inspectedItem = try #require(inspected["item"] as? [String: Any])
        #expect((inspectedItem["relativePath"] as? String)?.contains("Projects/Cider/Notes") != true)
    }

    @Test("item batch apply requires approval token and execute flag")
    func itemBatchApplyRequiresApprovalTokenAndExecuteFlag() throws {
        let request = """
        {
          "operations": [
            {
              "id": "missing",
              "action": "move",
              "type": "note",
              "ref": "missing",
              "path": "Projects/Cider/Notes"
            }
          ]
        }
        """

        let result = try runCLI(
            args: ["item", "batch-apply", "--stdin", "--json"],
            stdin: request
        )
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status != 0)
        #expect(payload["ok"] as? Bool == false)
        #expect(payload["command"] as? String == "item.batch.apply")
        #expect(payload["approvalRequired"] as? Bool == true)
        #expect((payload["error"] as? String)?.contains("--approve") == true)
        #expect(payload["changed"] as? Bool == false)
    }

    @Test("item batch apply moves valid items through existing mutation service")
    func itemBatchApplyMovesValidItemsThroughExistingMutationService() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-batch-apply-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let captureResult = try runCLI(
            args: [
                "capture", "add",
                "--kind", "note",
                "--title", "Batch Apply Source",
                "--stdin",
                "--json",
            ],
            vault: vault,
            stdin: "Move me through the batch contract."
        )
        let capturePayload = try parseJSONObject(captureResult.stdout)
        let note = try #require(capturePayload["item"] as? [String: Any])
        let noteID = try #require(note["id"] as? String)

        let request = """
        {
          "operations": [
            {
              "id": "move-note",
              "action": "move",
              "type": "note",
              "ref": "\(noteID)",
              "path": "Projects/Cider/Notes"
            }
          ]
        }
        """

        let planResult = try runCLI(
            args: ["item", "batch-plan", "--stdin", "--json"],
            vault: vault,
            stdin: request
        )
        let plan = try parseJSONObject(planResult.stdout)
        let token = try #require(plan["requiredApprovalToken"] as? String)

        let applyResult = try runCLI(
            args: ["item", "batch-apply", "--stdin", "--approve", token, "--execute", "--json"],
            vault: vault,
            stdin: request
        )
        let apply = try parseJSONObject(applyResult.stdout)

        #expect(applyResult.status == 0)
        #expect(apply["ok"] as? Bool == true)
        #expect(apply["command"] as? String == "item.batch.apply")
        #expect(apply["changed"] as? Bool == true)
        let operations = try #require(apply["operations"] as? [[String: Any]])
        #expect(operations.first?["status"] as? String == "applied")
        #expect(operations.first?["mutationAuditEntryID"] as? String != nil)

        let db = CiderDatabase()
        try db.open(at: vault.appendingPathComponent(".cider/cider.db"))
        defer { db.close() }
        let audit = MutationAuditService(database: db)
            .loadEntries()
            .first { $0.itemID.uuidString == noteID && $0.action == "item_move" }
        #expect(audit?.metadata["source"] == "item.batch.apply")

        let inspectResult = try runCLI(
            args: ["item", "get", "note", noteID, "--json"],
            vault: vault
        )
        let inspected = try parseJSONObject(inspectResult.stdout)
        let inspectedItem = try #require(inspected["item"] as? [String: Any])
        #expect((inspectedItem["relativePath"] as? String)?.contains("Projects/Cider/Notes") == true)
    }

    @Test("item batch apply records route and link operations")
    func itemBatchApplyRecordsRouteAndLinkOperations() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-batch-route-link-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let sourceNoteID = try createNote(title: "Batch Route Link Source", content: "Source", vault: vault)
        let targetNoteID = try createNote(title: "Batch Route Link Target", content: "Target", vault: vault)
        _ = try runCLI(args: ["item", "move", "note", targetNoteID, "--path", "Projects/Cider/Routes", "--json"], vault: vault)
        let ownerGet = try runCLI(args: ["item", "owner-get", "folder", "Projects/Cider/Routes", "--json"], vault: vault)
        let ownerPayload = try parseJSONObject(ownerGet.stdout)
        let targetFolder = try #require(ownerPayload["folder"] as? [String: Any])
        let targetFolderID = try #require(targetFolder["id"] as? String)

        let request = """
        {
          "operations": [
            {
              "id": "route-source",
              "action": "route",
              "type": "note",
              "ref": "\(sourceNoteID)",
              "targetType": "folder",
              "targetPath": "Projects/Cider/Routes",
              "reason": "Batch route relation",
              "confidence": 0.75,
              "status": "accepted"
            },
            {
              "id": "link-source-target",
              "action": "link",
              "type": "note",
              "ref": "\(sourceNoteID)",
              "targetType": "note",
              "targetRef": "\(targetNoteID)"
            }
          ]
        }
        """

        let planResult = try runCLI(args: ["item", "batch-plan", "--stdin", "--json"], vault: vault, stdin: request)
        let plan = try parseJSONObject(planResult.stdout)
        let plannedOperations = try #require(plan["operations"] as? [[String: Any]])
        #expect(plannedOperations.allSatisfy { $0["applySupported"] as? Bool == true })
        let plannedRoute = try #require(plannedOperations.first { $0["id"] as? String == "route-source" })
        #expect(plannedRoute["targetID"] as? String == targetFolderID)
        #expect(plannedRoute["targetRelativePath"] as? String == "Projects/Cider/Routes")
        let token = try #require(plan["requiredApprovalToken"] as? String)

        let applyResult = try runCLI(
            args: ["item", "batch-apply", "--stdin", "--approve", token, "--execute", "--json"],
            vault: vault,
            stdin: request
        )
        let apply = try parseJSONObject(applyResult.stdout)

        #expect(applyResult.status == 0)
        #expect(apply["ok"] as? Bool == true)
        #expect(apply["changed"] as? Bool == true)
        let appliedOperations = try #require(apply["operations"] as? [[String: Any]])
        #expect(appliedOperations.count == 2)
        #expect(Set(appliedOperations.compactMap { $0["status"] as? String }) == ["applied"])
        let routeOperation = try #require(appliedOperations.first { $0["id"] as? String == "route-source" })
        #expect(routeOperation["action"] as? String == "route")
        #expect(routeOperation["routingDecision"] as? [String: Any] != nil)
        let linkOperation = try #require(appliedOperations.first { $0["id"] as? String == "link-source-target" })
        #expect(linkOperation["action"] as? String == "link")
        #expect(linkOperation["link"] as? [String: Any] != nil)

        let inspectResult = try runCLI(args: ["item", "get", "note", sourceNoteID, "--json"], vault: vault)
        let inspected = try parseJSONObject(inspectResult.stdout)
        let routingDecisions = try #require(inspected["routingDecisions"] as? [[String: Any]])
        #expect(routingDecisions.contains {
            $0["targetType"] as? String == "folder"
                && $0["targetPath"] as? String == "Projects/Cider/Routes"
                && $0["targetID"] as? String == targetFolderID
                && $0["reason"] as? String == "Batch route relation"
                && $0["source"] as? String == "item.batch.apply"
        })

        let relatedResult = try runCLI(args: ["item", "related", "note", sourceNoteID, "--json"], vault: vault)
        let related = try parseJSONArray(relatedResult.stdout)
        #expect(related.contains { $0["id"] as? String == targetNoteID })
    }

    @Test("item batch apply reports partial failures while applying valid route operations")
    func itemBatchApplyReportsPartialFailuresWhileApplyingValidRouteOperations() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-batch-route-partial-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let sourceNoteID = try createNote(title: "Batch Partial Route Source", content: "Source", vault: vault)
        let folderSeedID = try createNote(title: "Batch Partial Folder Seed", content: "Folder", vault: vault)
        _ = try runCLI(args: ["item", "move", "note", folderSeedID, "--path", "Projects/Cider/Partial", "--json"], vault: vault)

        let request = """
        {
          "operations": [
            {
              "id": "route-source",
              "action": "route",
              "type": "note",
              "ref": "\(sourceNoteID)",
              "targetType": "folder",
              "targetPath": "Projects/Cider/Partial",
              "reason": "Batch partial route"
            },
            {
              "id": "missing-link-target",
              "action": "link",
              "type": "note",
              "ref": "\(sourceNoteID)",
              "targetType": "note",
              "targetRef": "missing-note-id"
            }
          ]
        }
        """

        let planResult = try runCLI(args: ["item", "batch-plan", "--stdin", "--json"], vault: vault, stdin: request)
        let plan = try parseJSONObject(planResult.stdout)
        let token = try #require(plan["requiredApprovalToken"] as? String)

        let applyResult = try runCLI(
            args: ["item", "batch-apply", "--stdin", "--approve", token, "--execute", "--json"],
            vault: vault,
            stdin: request
        )
        let apply = try parseJSONObject(applyResult.stdout)

        #expect(applyResult.status == 0)
        #expect(apply["ok"] as? Bool == false)
        #expect(apply["changed"] as? Bool == true)
        let partialFailures = try #require(apply["partialFailures"] as? [String])
        #expect(partialFailures.contains { $0.contains("missing-link-target") })
        let operations = try #require(apply["operations"] as? [[String: Any]])
        #expect(operations.first { $0["id"] as? String == "route-source" }?["status"] as? String == "applied")
        #expect(operations.first { $0["id"] as? String == "missing-link-target" }?["status"] as? String == "invalid")

        let inspectResult = try runCLI(args: ["item", "get", "note", sourceNoteID, "--json"], vault: vault)
        let inspected = try parseJSONObject(inspectResult.stdout)
        let routingDecisions = try #require(inspected["routingDecisions"] as? [[String: Any]])
        #expect(routingDecisions.contains { $0["targetPath"] as? String == "Projects/Cider/Partial" })
    }

    @Test("item owner get folder returns read only metadata and counts")
    func itemOwnerGetFolderReturnsReadOnlyMetadataAndCounts() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-folder-owner-get-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let parentNote = try createNote(title: "Folder Parent Note", content: "Parent", vault: vault)
        _ = try runCLI(
            args: ["item", "move", "note", parentNote, "--path", "Projects/Cider/Notes", "--json"],
            vault: vault
        )
        let childNote = try createNote(title: "Folder Child Note", content: "Child", vault: vault)
        _ = try runCLI(
            args: ["item", "move", "note", childNote, "--path", "Projects/Cider/Notes/Child", "--json"],
            vault: vault
        )

        let result = try runCLI(
            args: ["item", "owner-get", "folder", "Projects/Cider/Notes", "--json"],
            vault: vault
        )
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status == 0)
        #expect(payload["ok"] as? Bool == true)
        #expect(payload["command"] as? String == "item.owner-get.folder")
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        let folder = try #require(payload["folder"] as? [String: Any])
        #expect(folder["name"] as? String == "Notes")
        #expect(folder["relativePath"] as? String == "Projects/Cider/Notes")
        #expect(folder["parentRelativePath"] as? String == "Projects/Cider")
        #expect(folder["isRoot"] as? Bool == false)
        #expect(folder["isInbox"] as? Bool == false)

        let counts = try #require(payload["counts"] as? [String: Any])
        #expect(counts["directItemCount"] as? Int == 1)
        #expect(counts["descendantItemCount"] as? Int == 2)
        #expect(counts["directChildFolderCount"] as? Int == 1)
        #expect(counts["descendantFolderCount"] as? Int == 1)
        let directByType = try #require(counts["directItemsByType"] as? [String: Any])
        let descendantByType = try #require(counts["descendantItemsByType"] as? [String: Any])
        #expect(directByType["note"] as? Int == 1)
        #expect(descendantByType["note"] as? Int == 2)

        let health = try #require(payload["health"] as? [String: Any])
        #expect(health["existsInIndex"] as? Bool == true)
        #expect(health["existsOnDisk"] as? Bool == true)
        #expect(health["isGhost"] as? Bool == false)
        #expect(health["missingDirectory"] as? Bool == false)

        let safeNextCommands = try #require(payload["safeNextCommands"] as? [String])
        #expect(safeNextCommands.contains("cider-cli item search <query> --json"))
        #expect(safeNextCommands.contains("cider-cli item move <type> <id-or-ref> --path \"Projects/Cider/Notes\" --json"))
        #expect(safeNextCommands.contains("cider-cli item route <type> <id-or-ref> --target-type folder --target-id \(folder["id"] as? String ?? "") --target-path \"Projects/Cider/Notes\" --reason <reason> --json"))
        #expect(safeNextCommands.contains("cider-cli storage audit --json"))
    }

    @Test("item owner get folder omits write commands for artifact-looking folder rows")
    func itemOwnerGetFolderOmitsWriteCommandsForArtifactLookingFolderRows() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-folder-owner-artifact-path-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        _ = try createNote(title: "Initialize Folder DB", content: "Init", vault: vault)
        try insertFolderRow(relativePath: "Projects/Cider/QA/Audit.md", vault: vault)
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent("Projects/Cider/QA/Audit.md"),
            withIntermediateDirectories: true
        )

        let result = try runCLI(
            args: ["item", "owner-get", "folder", "Projects/Cider/QA/Audit.md", "--json"],
            vault: vault
        )
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status == 0)
        let folder = try #require(payload["folder"] as? [String: Any])
        let folderID = try #require(folder["id"] as? String)
        #expect(folder["relativePath"] as? String == "Projects/Cider/QA/Audit.md")

        let safeNextCommands = try #require(payload["safeNextCommands"] as? [String])
        #expect(!safeNextCommands.contains("cider-cli item move <type> <id-or-ref> --path \"Projects/Cider/QA/Audit.md\" --json"))
        #expect(!safeNextCommands.contains("cider-cli item move <type> <id-or-ref> --folder \"\(folderID)\" --json"))
        #expect(!safeNextCommands.contains("cider-cli item route <type> <id-or-ref> --target-type folder --target-id \(folderID) --target-path \"Projects/Cider/QA/Audit.md\" --reason <reason> --json"))
        #expect(safeNextCommands.contains("cider-cli storage audit --json"))
        #expect(safeNextCommands.contains("cider-cli storage doctor-plan --json"))
    }

    @Test("storage audit reports artifact-looking registered folder rows")
    func storageAuditReportsArtifactLookingRegisteredFolderRows() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-storage-audit-artifact-folder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        _ = try createNote(title: "Initialize Folder DB", content: "Init", vault: vault)
        try insertFolderRow(relativePath: "Projects/Cider/QA/Audit.md", vault: vault)
        try insertFolderRow(relativePath: "[Media]/[Games]/Paralives.webloc", vault: vault)
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent("Projects/Cider/QA/Audit.md"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent("[Media]/[Games]/Paralives.webloc"),
            withIntermediateDirectories: true
        )

        let result = try runCLI(args: ["storage", "audit", "--json"], vault: vault)
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status == 0)
        let groups = try #require(payload["doctorFindingGroups"] as? [String: Int])
        #expect(groups["warning:artifactLookingFolderRow"] == 2)
        let samples = try #require(payload["doctorFindingSamples"] as? [[String: Any]])
        #expect(samples.contains {
            $0["kind"] as? String == "artifactLookingFolderRow" &&
            $0["relativePath"] as? String == "Projects/Cider/QA/Audit.md" &&
            $0["isFixable"] as? Bool == false
        })
        #expect(samples.contains {
            $0["kind"] as? String == "artifactLookingFolderRow" &&
            $0["relativePath"] as? String == "[Media]/[Games]/Paralives.webloc" &&
            $0["isFixable"] as? Bool == false
        })
    }

    @Test("item owner get folder reports ambiguous name matches")
    func itemOwnerGetFolderReportsAmbiguousNameMatches() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-folder-owner-ambiguous-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let first = try createNote(title: "First Shared", content: "First", vault: vault)
        _ = try runCLI(args: ["item", "move", "note", first, "--path", "Alpha/Shared", "--json"], vault: vault)
        let second = try createNote(title: "Second Shared", content: "Second", vault: vault)
        _ = try runCLI(args: ["item", "move", "note", second, "--path", "Beta/Shared", "--json"], vault: vault)

        let result = try runCLI(args: ["item", "owner-get", "folder", "Shared", "--json"], vault: vault)
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status != 0)
        #expect(payload["ok"] as? Bool == false)
        #expect(payload["command"] as? String == "item.owner-get.folder")
        #expect((payload["error"] as? String)?.contains("Ambiguous folder reference") == true)
        let matches = try #require(payload["matches"] as? [[String: Any]])
        #expect(matches.count == 2)
        #expect(Set(matches.compactMap { $0["relativePath"] as? String }) == ["Alpha/Shared", "Beta/Shared"])
    }

    @Test("item move folder name fails closed when folder name is ambiguous")
    func itemMoveFolderNameFailsClosedWhenFolderNameAmbiguous() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-move-folder-ambiguous-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let first = try createNote(title: "Move First Shared", content: "First", vault: vault)
        _ = try runCLI(args: ["item", "move", "note", first, "--path", "Alpha/Shared", "--json"], vault: vault)
        let second = try createNote(title: "Move Second Shared", content: "Second", vault: vault)
        _ = try runCLI(args: ["item", "move", "note", second, "--path", "Beta/Shared", "--json"], vault: vault)
        let noteID = try createNote(title: "Ambiguous Move Source", content: "Route me", vault: vault)

        let result = try runCLI(args: ["item", "move", "note", noteID, "--folder", "Shared", "--json"], vault: vault)
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status != 0)
        #expect(payload["ok"] as? Bool == false)
        #expect(payload["command"] as? String == "folder.resolve")
        #expect(payload["changed"] as? Bool == false)
        #expect((payload["error"] as? String)?.contains("Ambiguous folder reference") == true)
        let matches = try #require(payload["matches"] as? [[String: Any]])
        #expect(Set(matches.compactMap { $0["relativePath"] as? String }) == ["Alpha/Shared", "Beta/Shared"])
        let safeNextCommands = try #require(payload["safeNextCommands"] as? [String])
        #expect(safeNextCommands.contains("cider-cli item owner-get folder \"Shared\" --json"))
    }

    @Test("item owner get folder returns inbox metadata")
    func itemOwnerGetFolderReturnsInboxMetadata() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-folder-owner-inbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        _ = try createNote(title: "Inbox Metadata Note", content: "Inbox", vault: vault)

        let result = try runCLI(args: ["item", "owner-get", "folder", "Inbox", "--json"], vault: vault)
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status == 0)
        #expect(payload["ok"] as? Bool == true)
        #expect(payload["command"] as? String == "item.owner-get.folder")
        let folder = try #require(payload["folder"] as? [String: Any])
        #expect(folder["name"] as? String == "Inbox")
        #expect(folder["relativePath"] as? String == "Inbox")
        #expect(folder["isRoot"] as? Bool == true)
        #expect(folder["isInbox"] as? Bool == true)
        let counts = try #require(payload["counts"] as? [String: Any])
        #expect(counts["directItemCount"] as? Int == 1)
        let directByType = try #require(counts["directItemsByType"] as? [String: Any])
        #expect(directByType["note"] as? Int == 1)
        let health = try #require(payload["health"] as? [String: Any])
        #expect(health["existsInIndex"] as? Bool == true)
        #expect(health["existsOnDisk"] as? Bool == true)
    }

    @Test("item route folder path records canonical folder id")
    func itemRouteFolderPathRecordsCanonicalFolderID() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-route-folder-path-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let noteID = try createNote(title: "Route Folder Source", content: "Route me", vault: vault)
        _ = try runCLI(args: ["item", "move", "note", noteID, "--path", "Media/Games", "--json"], vault: vault)
        let ownerGet = try runCLI(args: ["item", "owner-get", "folder", "Media/Games", "--json"], vault: vault)
        let ownerPayload = try parseJSONObject(ownerGet.stdout)
        let folder = try #require(ownerPayload["folder"] as? [String: Any])
        let folderID = try #require(folder["id"] as? String)

        let result = try runCLI(
            args: [
                "item", "route", "note", noteID,
                "--target-type", "folder",
                "--target-path", "Media/Games",
                "--reason", "Games belong in Media/Games.",
                "--json",
            ],
            vault: vault
        )
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status == 0)
        #expect(payload["targetType"] as? String == "folder")
        #expect(payload["targetPath"] as? String == "Media/Games")
        #expect(payload["targetID"] as? String == folderID)

        let db = CiderDatabase()
        try db.open(at: vault.appendingPathComponent(".cider/cider.db"))
        defer { db.close() }
        let stmt = try db.prepare("""
            SELECT target_folder_id, target_relative_path
            FROM routing_decisions
            WHERE item_id = ?
            ORDER BY created_at DESC
            LIMIT 1;
            """)
        stmt.bind(noteID, at: 1)
        #expect(try stmt.step())
        #expect(stmt.optionalString(at: 0) == folderID)
        #expect(stmt.string(at: 1) == "Media/Games")
    }

    @Test("item route folder path fails closed when folder is missing")
    func itemRouteFolderPathFailsClosedWhenFolderMissing() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-route-folder-missing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let noteID = try createNote(title: "Route Missing Folder Source", content: "Route me", vault: vault)
        let result = try runCLI(
            args: [
                "item", "route", "note", noteID,
                "--target-type", "folder",
                "--target-path", "Media/Movies",
                "--reason", "Movies should route to Media/Movies.",
                "--json",
            ],
            vault: vault
        )
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status != 0)
        #expect(payload["ok"] as? Bool == false)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["targetType"] as? String == "folder")
        #expect(payload["targetPath"] as? String == "Media/Movies")
        #expect(payload["recommendedNextAction"] as? String == "review_route")
        #expect((payload["error"] as? String)?.contains("No folder found") == true)
    }

    @Test("item route folder name fails closed when folder name is ambiguous")
    func itemRouteFolderNameFailsClosedWhenFolderNameAmbiguous() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-route-folder-ambiguous-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let first = try createNote(title: "Route First Shared", content: "First", vault: vault)
        _ = try runCLI(args: ["item", "move", "note", first, "--path", "Alpha/Shared", "--json"], vault: vault)
        let second = try createNote(title: "Route Second Shared", content: "Second", vault: vault)
        _ = try runCLI(args: ["item", "move", "note", second, "--path", "Beta/Shared", "--json"], vault: vault)
        let noteID = try createNote(title: "Ambiguous Route Source", content: "Route me", vault: vault)

        let result = try runCLI(
            args: [
                "item", "route", "note", noteID,
                "--target-type", "folder",
                "--target-path", "Shared",
                "--reason", "Shared folder route.",
                "--json",
            ],
            vault: vault
        )
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status != 0)
        #expect(payload["ok"] as? Bool == false)
        #expect(payload["changed"] as? Bool == false)
        #expect((payload["error"] as? String)?.contains("Ambiguous folder reference") == true)
        let matches = try #require(payload["matches"] as? [[String: Any]])
        #expect(Set(matches.compactMap { $0["relativePath"] as? String }) == ["Alpha/Shared", "Beta/Shared"])
    }

    @Test("export folder JSON is bounded read only and includes stable refs")
    func exportFolderJSONIsBoundedReadOnlyAndIncludesStableRefs() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-export-folder-json-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let sourceNoteID = try createNote(title: "Export Source", content: "Export body", vault: vault)
        _ = try runCLI(args: ["item", "move", "note", sourceNoteID, "--path", "Projects/Cider/Exports", "--json"], vault: vault)
        let targetNoteID = try createNote(title: "Export Target", content: "Linked body", vault: vault)
        _ = try runCLI(args: ["item", "link", "note", sourceNoteID, "note", targetNoteID, "--json"], vault: vault)

        let result = try runCLI(
            args: ["export", "folder", "Projects/Cider/Exports", "--format", "json", "--limit", "10", "--json"],
            vault: vault
        )
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status == 0)
        #expect(payload["ok"] as? Bool == true)
        #expect(payload["command"] as? String == "export.folder")
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["format"] as? String == "json")
        let scope = try #require(payload["scope"] as? [String: Any])
        #expect(scope["type"] as? String == "folder")
        #expect(scope["relativePath"] as? String == "Projects/Cider/Exports")
        let counts = try #require(payload["counts"] as? [String: Any])
        #expect(counts["includedItems"] as? Int == 1)
        #expect(counts["totalItems"] as? Int == 1)
        let items = try #require(payload["items"] as? [[String: Any]])
        let exported = try #require(items.first)
        #expect(exported["type"] as? String == "note")
        #expect(exported["id"] as? String == sourceNoteID)
        #expect(exported["ref"] as? String == "note:\(sourceNoteID)")
        #expect(exported["relativePath"] as? String == "Projects/Cider/Exports/Export Source.md")
        #expect(exported["content"] as? String == "Export body")
        #expect(exported["owner"] as? [String: Any] != nil)
        #expect(exported["backlinks"] as? [[String: Any]] != nil)
        #expect(exported["captureProvenance"] as? [[String: Any]] != nil)
        let related = try #require(exported["related"] as? [[String: Any]])
        #expect(related.contains { $0["id"] as? String == targetNoteID })
        let safeNextCommands = try #require(payload["safeNextCommands"] as? [String])
        #expect(safeNextCommands.contains("cider-cli export folder \"Projects/Cider/Exports\" --format md --limit 10"))
        #expect(safeNextCommands.contains("cider-cli item owner-get folder \"Projects/Cider/Exports\" --json"))
    }

    @Test("export folder Markdown renders item metadata without JSON scraping")
    func exportFolderMarkdownRendersItemMetadataWithoutJSONScraping() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-export-folder-md-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let noteID = try createNote(title: "Markdown Export Source", content: "Markdown export body", vault: vault)
        _ = try runCLI(args: ["item", "move", "note", noteID, "--path", "Projects/Cider/Exports", "--json"], vault: vault)

        let result = try runCLI(
            args: ["export", "folder", "Projects/Cider/Exports", "--format", "md", "--limit", "10"],
            vault: vault
        )

        #expect(result.status == 0)
        #expect(result.stdout.contains("# Cider Export: Projects/Cider/Exports"))
        #expect(result.stdout.contains("Scope: folder"))
        #expect(result.stdout.contains("Ref: note:\(noteID)"))
        #expect(result.stdout.contains("Path: Projects/Cider/Exports/Markdown Export Source.md"))
        #expect(result.stdout.contains("Markdown export body"))
    }

    @Test("export vault refuses unbounded dumps")
    func exportVaultRefusesUnboundedDumps() throws {
        let result = try runCLI(args: ["export", "vault", "--format", "json", "--json"])
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status != 0)
        #expect(payload["ok"] as? Bool == false)
        #expect(payload["command"] as? String == "export.vault")
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect((payload["error"] as? String)?.contains("Whole-vault export is not available") == true)
        let safeNextCommands = try #require(payload["safeNextCommands"] as? [String])
        #expect(safeNextCommands.contains("cider-cli export folder <relative-path> --format json --limit 100 --json"))
    }

    @Test("review enrich json waits with bounded lifecycle result")
    func reviewEnrichJSONWaitsWithBoundedLifecycleResult() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-review-enrich-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let captureResult = try runCLI(
            args: [
                "capture", "add",
                "--kind", "bookmark",
                "--url", "https://example.com/review-enrich-\(UUID().uuidString)",
                "--title", "Needs CLI Enrichment",
                "--no-wait",
                "--json",
            ],
            vault: vault
        )
        let capturePayload = try parseJSONObject(captureResult.stdout)
        let bookmark = try #require(capturePayload["bookmark"] as? [String: Any])
        let itemID = try #require(bookmark["id"] as? String)

        let result = try runCLI(
            args: ["review", "enrich", itemID, "--actor", "agent", "--timeout", "0", "--json"],
            vault: vault
        )
        let payload = try parseJSONObject(result.stdout)

        #expect(payload["action"] as? String == "review.enrich")
        #expect(payload["status"] as? String == "timed_out")
        #expect(payload["waited"] as? Bool == true)
        #expect(payload["elapsedSeconds"] as? Double != nil)
        #expect(payload["before"] as? [String: Any] != nil)
        #expect(payload["after"] as? [String: Any] != nil)
        #expect(payload["changedFields"] as? [String] != nil)
        #expect(payload["reviewResolved"] as? Bool != nil)
    }

    @Test("legacy bookmark enrich is removed with review replacement")
    func legacyBookmarkEnrichIsRemovedWithReviewReplacement() throws {
        let result = try runCLI(args: ["bookmark", "enrich", "abc", "--json"])
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status != 0)
        #expect(payload["ok"] as? Bool == false)
        #expect(payload["legacyRemoved"] as? Bool == true)
        #expect(payload["command"] as? String == "bookmark enrich")
        #expect(payload["replacement"] as? String == "cider-cli review enrich <item-id> --json")
    }

    @Test("capture add json reports visible bookmark quality")
    func captureAddJSONReportsVisibleBookmarkQuality() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-capture-quality-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let result = try runCLI(
            args: [
                "capture", "add",
                "--kind", "bookmark",
                "--url", "https://example.com/capture-quality-\(UUID().uuidString)",
                "--title", "Example.Com",
                "--no-wait",
                "--json",
            ],
            vault: vault
        )
        let payload = try parseJSONObject(result.stdout)
        let bookmark = try #require(payload["bookmark"] as? [String: Any])
        let itemID = try #require(bookmark["id"] as? String)
        let quality = try #require(payload["captureQuality"] as? [String: Any])
        let reasons = try #require(quality["degradedReasons"] as? [String])
        let safeNextCommands = try #require(payload["safeNextCommands"] as? [String])

        #expect(quality["semanticStatus"] as? String == "pending")
        #expect(quality["metadataComplete"] as? Bool == false)
        #expect(quality["cardComplete"] as? Bool == false)
        #expect(quality["titleQuality"] as? String == "generic")
        #expect(quality["thumbnailStatus"] as? String == "missing")
        #expect(quality["visibleCardCurrent"] as? Bool == false)
        #expect(reasons.contains("metadata_pending"))
        #expect(reasons.contains("title_generic"))
        #expect(reasons.contains("card_image_missing"))
        #expect(safeNextCommands.contains("cider-cli review enrich \(itemID) --actor agent --timeout 20 --json"))
        #expect(safeNextCommands.contains("cider-cli item rebuild-chunks bookmark \(itemID) --json"))
    }

    @Test("note daily append upserts same-day food log and refreshes context")
    func noteDailyAppendUpsertsSameDayFoodLogAndRefreshesContext() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-daily-append-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let firstResult = try runCLI(
            args: [
                "note", "daily", "append",
                "--kind", "food-log",
                "--date", "2026-05-28",
                "--time", "13:30",
                "--content", "Coke Zero",
                "--source", "discord",
                "--json",
            ],
            vault: vault
        )
        let first = try parseJSONObject(firstResult.stdout)
        #expect(first["ok"] as? Bool == true)
        #expect(first["command"] as? String == "note.daily.append")
        #expect(first["created"] as? Bool == true)
        #expect(first["kind"] as? String == "food-log")
        #expect(first["date"] as? String == "2026-05-28")
        let firstNote = try #require(first["note"] as? [String: Any])
        let noteID = try #require(firstNote["id"] as? String)
        let firstContent = try #require(first["content"] as? String)
        #expect(firstContent.contains("Food Log 2026-05-28"))
        #expect(firstContent.contains("- 13:30 - Coke Zero"))

        let secondResult = try runCLI(
            args: [
                "note", "daily", "append",
                "--kind", "food-log",
                "--date", "2026-05-28",
                "--time", "15:45",
                "--content", "Protein shake",
                "--source", "discord",
                "--json",
            ],
            vault: vault
        )
        let second = try parseJSONObject(secondResult.stdout)
        #expect(second["ok"] as? Bool == true)
        #expect(second["created"] as? Bool == false)
        let secondNote = try #require(second["note"] as? [String: Any])
        #expect(secondNote["id"] as? String == noteID)
        let secondContent = try #require(second["content"] as? String)
        #expect(secondContent.contains("- 13:30 - Coke Zero"))
        #expect(secondContent.contains("- 15:45 - Protein shake"))

        let journalResult = try runCLI(
            args: [
                "note", "daily", "append",
                "--kind", "journal",
                "--date", "2026-05-28",
                "--time", "20:00",
                "--content", "Evening reflection",
                "--source", "discord",
                "--json",
            ],
            vault: vault
        )
        let journal = try parseJSONObject(journalResult.stdout)
        #expect(journal["ok"] as? Bool == true)
        #expect(journal["kind"] as? String == "journal")
        #expect(journal["created"] as? Bool == true)
        let journalContent = try #require(journal["content"] as? String)
        #expect(journalContent.contains("Daily Journal 2026-05-28"))
        #expect(journalContent.contains("- 20:00 - Evening reflection"))

        let inspectResult = try runCLI(args: ["item", "get", "note", noteID, "--json"], vault: vault)
        let inspected = try parseJSONObject(inspectResult.stdout)
        #expect(inspected["ok"] as? Bool == true)
        let chunks = try #require(inspected["chunks"] as? [[String: Any]])
        #expect(chunks.contains { ($0["body"] as? String)?.contains("Protein shake") == true })
    }

    @Test("item open resolves library refs and reports external open notification")
    func itemOpenResolvesLibraryRefsAndReportsExternalOpenNotification() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-item-open-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let createResult = try runCLI(
            args: ["note", "create", "Open Me", "--content", "Surface this note", "--json"],
            vault: vault
        )
        let created = try parseJSONObject(createResult.stdout)
        let noteID = try #require(created["id"] as? String)

        let openResult = try runCLI(
            args: ["item", "open", "note", noteID, "--json"],
            vault: vault
        )
        let payload = try parseJSONObject(openResult.stdout)
        #expect(payload["ok"] as? Bool == true)
        #expect(payload["command"] as? String == "item.open")
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["notificationPosted"] as? Bool == true)
        #expect(payload["notificationName"] as? String == "cider.externalOpenRequest")
        let target = try #require(payload["target"] as? [String: Any])
        #expect(target["type"] as? String == "note")
        #expect(target["id"] as? String == noteID)
        #expect(target["title"] as? String == "Open Me")
        let sourceRef = try #require(payload["sourceRef"] as? [String: Any])
        #expect(sourceRef["type"] as? String == "note")
        #expect(sourceRef["ref"] as? String == noteID)
    }

    @Test("item open resolves kanban cards with board context")
    func itemOpenResolvesKanbanCardsWithBoardContext() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-card-open-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        _ = try runCLI(args: ["board", "create", "Open Board"], vault: vault)
        let addResult = try runCLI(
            args: ["board", "add-card", "Open Board", "--column", "Backlog", "--title", "Open Card", "--json"],
            vault: vault
        )
        let added = try parseJSONObject(addResult.stdout)
        let card = try #require(added["card"] as? [String: Any])
        let cardID = try #require(card["id"] as? String)

        let openResult = try runCLI(args: ["item", "open", "card", cardID, "--json"], vault: vault)
        let payload = try parseJSONObject(openResult.stdout)
        #expect(payload["ok"] as? Bool == true)
        #expect(payload["command"] as? String == "item.open")
        let target = try #require(payload["target"] as? [String: Any])
        #expect(target["type"] as? String == "card")
        #expect(target["id"] as? String == cardID)
        #expect(target["title"] as? String == "Open Card")
        #expect(target["boardID"] as? String != nil)
        #expect(target["boardName"] as? String == "Open Board")
    }

    @Test("capture add json rejects missing source")
    func captureAddJSONRejectsMissingSource() throws {
        let result = try runCLI(args: ["capture", "add", "--json"])

        let dict = try parseJSONObject(result.stdout)
        #expect(result.status != 0)
        #expect(dict["ok"] as? Bool == false)
        #expect((dict["error"] as? String)?.contains("Usage: cider-cli capture add") == true)
    }

    @Test("capture add help prints usage before source validation")
    func captureAddHelpPrintsUsageBeforeSourceValidation() throws {
        let result = try runCLI(args: ["capture", "add", "--help"])

        #expect(result.status == 0)
        #expect(result.stdout.contains("Usage: cider-cli capture add"))
        #expect(result.stdout.contains("--kind note|todo|bookmark|file|event|contact|journal"))
        #expect(!result.stderr.contains("Source required"))
    }

    @Test("bookmark update usage documents AI summary clear flag")
    func bookmarkUpdateUsageDocumentsAISummaryClearFlag() throws {
        let result = try runCLI(args: ["bookmark", "update"])

        #expect(result.stdout.contains("Usage: cider-cli bookmark update <id>"))
        #expect(result.stdout.contains("--ai-summary <text>|--clear-ai-summary"))
    }

    @Test("cli help documents source path versus destination path flags")
    func cliHelpDocumentsSourcePathVersusDestinationPathFlags() throws {
        let captureHelp = try runCLI(args: ["capture", "add", "--help"])
        let itemHelp = try runCLI(args: ["item", "help"])
        let topHelp = try runCLI(args: ["help"])

        #expect(captureHelp.stdout.contains("--path <source-file-path>"))
        #expect(captureHelp.stdout.contains("--folder <target-folder-path>"))
        #expect(captureHelp.stdout.contains("Example destination: --folder \"Inbox/Notes\""))
        #expect(itemHelp.stdout.contains("--path <target-folder-path>"))
        #expect(itemHelp.stdout.contains("Do not pass artifact filenames such as Example.webloc to item move --path."))
        #expect(topHelp.stdout.contains("--path <source-file-path>"))
        #expect(topHelp.stdout.contains("--path <target-folder-path>"))
    }

    @Test("item search help and scope validation are agent safe")
    func itemSearchHelpAndScopeValidationAreAgentSafe() throws {
        let help = try runCLI(args: ["item", "search", "--help"])

        #expect(help.status == 0)
        #expect(help.stdout.contains("Valid --scope values: all, personalMemory, projectKanban, qaArtifacts, files"))
        #expect(help.stdout.contains("Use one scope value at a time; do not combine scope names"))
        #expect(help.stdout.contains("cider-cli item search \"event\" --scope personalMemory --json"))
        #expect(!help.stdout.contains("personalMemory/all"))

        let invalid = try runCLI(args: [
            "item", "search", "event",
            "--scope", "personalMemory/all",
            "--json",
        ])
        let payload = try parseJSONObject(invalid.stdout)
        let error = try #require(payload["error"] as? String)

        #expect(invalid.status != 0)
        #expect(payload["ok"] as? Bool == false)
        #expect(error.contains("Unsupported item search scope 'personalMemory/all'"))
        #expect(error.contains("Valid --scope values: all, personalMemory, projectKanban, qaArtifacts, files"))
        #expect(error.contains("Use --scope personalMemory or --scope all"))
    }

    @Test("capture add event and contact reject missing required fields")
    func captureAddEventAndContactRejectMissingRequiredFields() throws {
        let eventResult = try runCLI(args: [
            "capture", "add",
            "--kind", "event",
            "--title", "No Date",
            "--json",
        ])
        let eventDict = try parseJSONObject(eventResult.stdout)
        #expect(eventResult.status != 0)
        #expect(eventDict["ok"] as? Bool == false)
        #expect((eventDict["error"] as? String)?.contains("--date") == true)

        let contactResult = try runCLI(args: [
            "capture", "add",
            "--kind", "contact",
            "--json",
        ])
        let contactDict = try parseJSONObject(contactResult.stdout)
        #expect(contactResult.status != 0)
        #expect(contactDict["ok"] as? Bool == false)
        #expect((contactDict["error"] as? String)?.contains("--name") == true)
    }

    @Test("bookmark add json rejects missing url")
    func bookmarkAddJSONRejectsMissingURL() throws {
        let result = try runCLI(args: ["bookmark", "add", "--json"])

        let dict = try parseJSONObject(result.stdout)
        #expect(result.status != 0)
        #expect(dict["ok"] as? Bool == false)
        #expect((dict["error"] as? String)?.contains("Usage: cider-cli bookmark add") == true)
    }

    @Test("review approve json rejects missing item")
    func reviewApproveJSONRejectsMissingItem() throws {
        let result = try runCLI(args: ["review", "approve", "--json"])

        let dict = try parseJSONObject(result.stdout)
        #expect(result.status != 0)
        #expect(dict["ok"] as? Bool == false)
        #expect((dict["error"] as? String)?.contains("Usage: cider-cli review approve") == true)
    }

    @Test("unknown top level json command fails closed")
    func unknownTopLevelJSONCommandFailsClosed() throws {
        let result = try runCLI(args: ["definitely-not-a-command", "--json"])

        let dict = try parseJSONObject(result.stdout)
        #expect(result.status != 0)
        #expect(dict["ok"] as? Bool == false)
        #expect((dict["error"] as? String)?.contains("Unknown command") == true)
    }

    @Test("remaining command families fail closed with json errors")
    func remainingCommandFamiliesFailClosedWithJSONErrors() throws {
        let cases: [(args: [String], expectedError: String)] = [
            (["storage", "definitely-not-storage", "--json"], "Unknown storage command"),
            (["review", "definitely-not-review", "--json"], "Unknown review command"),
            (["space", "captures", "--json"], "Usage: cider-cli space captures"),
            (["routing", "explain", "--json"], "Usage: cider-cli routing explain"),
            (["board", "definitely-not-board", "--json"], "Unknown board command"),
        ]

        for testCase in cases {
            let result = try runCLI(args: testCase.args)
            let dict = try parseJSONObject(result.stdout)
            #expect(result.status != 0, "Expected \(testCase.args.joined(separator: " ")) to exit non-zero")
            #expect(dict["ok"] as? Bool == false, "Expected \(testCase.args.joined(separator: " ")) to report ok:false")
            #expect((dict["error"] as? String)?.contains(testCase.expectedError) == true)
            #expect(!result.stdout.hasPrefix("Error:"), "Expected JSON-only stdout for \(testCase.args.joined(separator: " "))")
            #expect(!result.stdout.hasPrefix("Unknown"), "Expected JSON-only stdout for \(testCase.args.joined(separator: " "))")
        }
    }

    @Test("review correct json rejects missing target")
    func reviewCorrectJSONRejectsMissingTarget() throws {
        let result = try runCLI(args: ["review", "correct", "missing-item", "--json"])

        let dict = try parseJSONObject(result.stdout)
        #expect(result.status != 0)
        #expect(dict["ok"] as? Bool == false)
        #expect((dict["error"] as? String)?.contains("requires --folder, --path, or --inbox") == true)
    }

    @Test("routing correct json rejects missing target")
    func routingCorrectJSONRejectsMissingTarget() throws {
        let result = try runCLI(args: ["routing", "correct", "missing-item", "--json"])

        let dict = try parseJSONObject(result.stdout)
        #expect(result.status != 0)
        #expect(dict["ok"] as? Bool == false)
        #expect((dict["error"] as? String)?.contains("requires --folder, --path, or --inbox") == true)
    }

    @Test("legacy bookmark batch enrichment is removed")
    func legacyBookmarkBatchEnrichmentIsRemoved() throws {
        let result = try runCLI(args: ["bookmark", "enrich", "--all", "--json"])

        let dict = try parseJSONObject(result.stdout)
        #expect(dict["ok"] as? Bool == false)
        #expect(dict["legacyRemoved"] as? Bool == true)
        #expect((dict["command"] as? String) == "bookmark enrich --all")
        #expect((dict["replacement"] as? String)?.contains("review enrich-batch") == true)
    }

    @Test("legacy CLI commands are removed with replacements")
    func legacyCLICommandsAreRemovedWithReplacements() throws {
        let commands = [
            ["memory", "show", "user", "--json"],
            ["embeddings", "backfill", "--json"],
            ["search", "anything", "--json"],
            ["query", "anything", "--json"],
            ["recent", "--json"],
            ["snapshot", "--json"],
            ["status", "--json"],
            ["folder", "kanban", "Inbox", "--json"],
        ]

        for command in commands {
            let result = try runCLI(args: command)
            let dict = try parseJSONObject(result.stdout)
            #expect(dict["ok"] as? Bool == false)
            #expect(dict["legacyRemoved"] as? Bool == true)
            #expect((dict["replacement"] as? String)?.isEmpty == false)
        }
    }

    @Test("hidden legacy type specific commands return structured replacement guidance")
    func hiddenLegacyTypeSpecificCommandsReturnStructuredReplacementGuidance() throws {
        let cases: [(args: [String], command: String, replacement: String)] = [
            (["bookmark", "list", "--json"], "bookmark list", "cider-cli item search <query> --json"),
            (["bookmark", "enrich", "abc", "--json"], "bookmark enrich", "cider-cli review enrich <item-id> --json"),
            (["note", "list", "--json"], "note list", "cider-cli item search <query> --json"),
            (["todo", "list", "--json"], "todo list", "cider-cli item search <query> --json"),
            (["event", "list", "--json"], "event list", "cider-cli item search <query> --json"),
            (["contact", "list", "--json"], "contact list", "cider-cli item search <query> --json"),
            (["file", "list", "--json"], "file list", "cider-cli item search <query> --json"),
            (["folder", "list", "--json"], "folder list", "cider-cli item search <query> --json"),
            (["folder", "create", "Projects", "--json"], "folder create", "cider-cli item search <query> --json"),
            (["label", "list", "--json"], "label list", "cider-cli item search <query> --json"),
            (["tag", "list", "--json"], "tag list", "cider-cli item search <query> --json"),
            (["dashboard", "topic", "list", "--json"], "dashboard topic", "cider-cli item graph-health --json"),
            (["link", "add", "note", "a", "note", "b", "--json"], "link add", "cider-cli item link"),
            (["view", "list", "--json"], "view list", "cider-cli item project-context <project-id-or-name> --json"),
            (["saved-view", "list", "--json"], "saved-view list", "cider-cli item project-context <project-id-or-name> --json"),
            (["trash", "list", "--json"], "trash list", "cider-cli storage audit --json"),
            (["clipboard", "import", "--json"], "clipboard import", "cider-cli capture add --kind note --stdin --json"),
            (["recall", "list", "--json"], "recall list", "cider-cli item search <query> --json"),
            (["duplicate-check", "run", "--json"], "duplicate-check run", "cider-cli item search <url-or-query> --json"),
            (["media", "scan", "--json"], "media scan", "cider-cli item search <query> --json"),
            (["bookmark", "move", "abc", "--json"], "bookmark move", "cider-cli item move bookmark <id> --folder <name|path> --json"),
            (["note", "move", "abc", "--json"], "note move", "cider-cli item move note <id> --folder <name|path> --json"),
            (["todo", "move", "abc", "--json"], "todo move", "cider-cli item move todo <id> --folder <name|path> --json"),
            (["file", "move", "abc", "--json"], "file move", "cider-cli item move file <id> --folder <name|path> --json"),
        ]

        for testCase in cases {
            let result = try runCLI(args: testCase.args)
            let dict = try parseJSONObject(result.stdout)
            #expect(result.status != 0, "Expected \(testCase.args.joined(separator: " ")) to exit non-zero")
            #expect(dict["ok"] as? Bool == false)
            #expect(dict["legacyRemoved"] as? Bool == true)
            #expect(dict["command"] as? String == testCase.command)
            #expect(dict["replacement"] as? String == testCase.replacement)
            #expect(dict["reason"] as? String == "Use the Second Brain v1 agent API.")
        }
    }

    @Test("type specific legacy handlers repeat the removed command guard")
    func typeSpecificLegacyHandlersRepeatRemovedCommandGuard() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try [
            "Sources/CiderCLI/CiderCLI.swift",
            "Sources/CiderCLI/MediaCLI.swift",
        ]
        .map { try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8) }
        .joined(separator: "\n")
        let guardedCommands = [
            "bookmark",
            "note",
            "todo",
            "event",
            "contact",
            "file",
            "folder",
            "label",
            "trash",
            "clipboard",
            "dashboard",
            "media",
            "recall",
            "duplicate-check",
        ]

        for command in guardedCommands {
            let guardLine = #"printHiddenLegacyCommandIfRemoved(command: "\#(command)""#
            #expect(source.contains(guardLine), "Missing handler-level legacy tombstone guard for \(command)")
        }
        #expect(source.contains(#""bookmark enrich", "cider-cli review enrich <item-id> --json""#) == false)
        #expect(source.contains("actions.insert(\"review enrich \\(itemID.uuidString) --timeout 20\", at: 0)"))
    }

    @Test("hidden legacy commands print concise text replacement guidance")
    func hiddenLegacyCommandsPrintConciseTextReplacementGuidance() throws {
        let result = try runCLI(args: ["note", "list"])

        #expect(result.status != 0)
        #expect(result.stdout.contains("Legacy command 'note list' has been removed"))
        #expect(result.stdout.contains("Replacement: cider-cli item search <query> --json"))
        #expect(result.stdout.contains("Use the Second Brain v1 agent API."))
    }

    @Test("legacy create import wrappers identify compatibility backend")
    func legacyCreateImportWrappersIdentifyCompatibilityBackend() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-compat-wrappers-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let sourceFile = vault.appendingPathComponent("wrapper source.txt")
        try "Wrapper file content".write(to: sourceFile, atomically: true, encoding: .utf8)

        let cases: [[String]] = [
            ["bookmark", "add", "https://example.com/wrapper", "--json"],
            ["note", "create", "Wrapper note", "--content", "Wrapper note body", "--json"],
            ["todo", "create", "Wrapper todo", "--json"],
            ["file", "import", sourceFile.path, "--json"],
        ]

        for args in cases {
            let result = try runCLI(args: args, vault: vault)
            let dict = try parseJSONObject(result.stdout)
            #expect(result.status == 0, "Expected \(args.joined(separator: " ")) to remain a compatibility wrapper")
            #expect(dict["compatibilityWrapper"] as? Bool == true)
            #expect(dict["backendCommand"] as? String == "capture.add")
            let capture = try #require(dict["capture"] as? [String: Any])
            #expect(capture["command"] as? String == "capture.add")
        }
    }

    @Test("top level help hides removed legacy commands")
    func topLevelHelpHidesRemovedLegacyCommands() throws {
        let result = try runCLI(args: ["help"])
        let output = result.stdout

        #expect(output.contains("cider-cli capture add"))
        #expect(output.contains("cider-cli item search"))
        #expect(output.contains("cider-cli storage audit"))
        #expect(output.contains("cider-cli db integrity"))
        #expect(!output.contains("cider-cli memory"))
        #expect(!output.contains("cider-cli embeddings"))
        #expect(!output.contains("cider-cli query"))
        #expect(!output.contains("cider-cli search <query>"))
        #expect(!output.contains("cider-cli recent"))
        #expect(!output.contains("cider-cli snapshot"))
        #expect(!output.contains("cider-cli status"))
        #expect(!output.contains("cider-cli folder kanban"))
    }

    @Test("top level help is limited to second brain v1 agent api")
    func topLevelHelpIsLimitedToSecondBrainV1AgentAPI() throws {
        let result = try runCLI(args: ["help"])
        let output = result.stdout

        let visibleSectionHeaders = output
            .split(separator: "\n")
            .map(String.init)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty
                    && trimmed == trimmed.uppercased()
                    && !trimmed.hasPrefix("  ")
                    && trimmed != "CiderCLI — Full command-line interface to Cider's vault"
            }

        #expect(visibleSectionHeaders == [
            "CAPTURE",
            "TEST RUN",
            "ITEM",
            "EXPORT",
            "REVIEW",
            "ROUTE",
            "STORAGE",
            "MIGRATE",
            "DOCTOR",
            "USAGE",
            "BOARD WORKFLOW",
            "DATABASE",
            "GLOBAL FLAGS",
        ])

        let hiddenLegacySnippets = [
            "BOOKMARKS",
            "NOTES",
            "TODOS",
            "EVENTS",
            "CONTACTS",
            "FILES",
            "FOLDERS",
            "LABELS",
            "SAVED VIEWS",
            "TRASH",
            "CLIPBOARD",
            "DASHBOARD",
            "MEDIA",
            "RECALL",
            "cider-cli bookmark",
            "cider-cli note",
            "cider-cli todo",
            "cider-cli event",
            "cider-cli contact",
            "cider-cli file",
            "cider-cli folder",
            "cider-cli label",
            "cider-cli view",
            "cider-cli trash",
            "cider-cli clipboard",
            "cider-cli dashboard",
            "cider-cli media",
            "cider-cli recall",
            "cider-cli link ",
            "cider-cli doctor",
            "cider-cli duplicate-check",
        ]
        for snippet in hiddenLegacySnippets {
            #expect(!output.contains(snippet), "Expected top-level help to hide \(snippet)")
        }

        #expect(output.contains("cider-cli item relations"))
        #expect(output.contains("cider-cli item backlinks"))
        #expect(output.contains("cider-cli item project-context"))
        #expect(output.contains("cider-cli item move"))
        #expect(output.contains("cider-cli item link"))
        #expect(output.contains("cider-cli storage audit"))
        #expect(output.contains("cider-cli db integrity"))
    }

    @Test("item graph health is a read-only JSON readiness report")
    func itemGraphHealthIsReadOnlyJSONReadinessReport() throws {
        let result = try runCLI(args: ["item", "graph-health", "--json"])

        let dict = try parseJSONObject(result.stdout)
        #expect(dict["command"] as? String == "item.graph-health")
        #expect(dict["readOnly"] as? Bool == true)
        #expect(dict["ok"] as? Bool == true)
        let components = try #require(dict["components"] as? [[String: Any]])
        #expect(components.contains { component in
            component["id"] as? String == "owner_relations"
                && component["state"] as? String == "implemented_empty"
        })
        #expect(components.contains { component in
            component["id"] as? String == "content_chunks"
                && component["state"] as? String == "implemented_empty"
        })
        let commands = try #require(dict["suggestedCommands"] as? [String])
        #expect(commands.contains("cider-cli item rebuild-chunks all --json"))
        let actions = try #require(dict["suggestedActions"] as? [[String: Any]])
        #expect(actions.contains { action in
            action["command"] as? String == "cider-cli item rebuild-chunks all --json"
                && action["readOnly"] as? Bool == false
                && action["requiresApproval"] as? Bool == true
                && action["mutationReason"] as? String == "rebuild_content_chunks"
        })
    }

    @Test("item graph health distinguishes unseeded intelligence stores")
    func itemGraphHealthDistinguishesUnseededIntelligenceStores() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-graph-intelligence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        _ = try runCLI(
            args: ["note", "create", "Launch graph", "--content", "Cider graph launch roadmap agent context Apple Park", "--json"],
            vault: vault
        )
        _ = try runCLI(
            args: ["note", "create", "Launch roadmap", "--content", "Apple Park product launch roadmap for Cider agent context", "--json"],
            vault: vault
        )

        let result = try runCLI(args: ["item", "graph-health", "--json"], vault: vault)
        let dict = try parseJSONObject(result.stdout)
        let components = try #require(dict["components"] as? [[String: Any]])
        #expect(components.contains { component in
            component["id"] as? String == "enrichment_outputs"
                && component["state"] as? String == "needs_rebuild"
                && component["emptyReason"] as? String == "unseeded"
        })
        #expect(components.contains { component in
            component["id"] as? String == "similarity_candidates"
                && component["state"] as? String == "needs_rebuild"
                && component["emptyReason"] as? String == "unseeded"
        })
        let commands = try #require(dict["suggestedCommands"] as? [String])
        #expect(commands.contains("cider-cli item dogfood-intelligence --limit 5 --json"))
        let actions = try #require(dict["suggestedActions"] as? [[String: Any]])
        #expect(actions.contains { action in
            action["command"] as? String == "cider-cli item dogfood-intelligence --limit 5 --json"
                && action["readOnly"] as? Bool == false
                && action["requiresApproval"] as? Bool == true
                && action["mutationReason"] as? String == "seed_reviewable_intelligence"
        })
    }

    @Test("item dogfood intelligence reports bounded reviewable JSON output")
    func itemDogfoodIntelligenceReportsBoundedReviewableJSONOutput() throws {
        let result = try runCLI(args: ["item", "dogfood-intelligence", "--limit", "2", "--json"])

        let dict = try parseJSONObject(result.stdout)
        #expect(dict["ok"] as? Bool == true)
        #expect(dict["command"] as? String == "item.dogfood-intelligence")
        #expect(dict["limit"] as? Int == 2)
        #expect(dict["ownerCount"] as? Int == 0)
        #expect(dict["reviewRequired"] as? Bool == false)
        #expect((dict["owners"] as? [[String: Any]])?.isEmpty == true)
    }

    @Test("read-only folder filters do not adopt untracked disk folders")
    func readOnlyFolderFiltersDoNotAdoptUntrackedDiskFolders() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-read-filter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent("LooseDiskFolder", isDirectory: true),
            withIntermediateDirectories: true
        )

        let listResult = try runCLI(args: ["bookmark", "list", "--folder", "LooseDiskFolder", "--json"], vault: vault)
        let payload = try parseJSONObject(listResult.stdout)
        #expect(listResult.status != 0)
        #expect(payload["legacyRemoved"] as? Bool == true)
        #expect(payload["replacement"] as? String == "cider-cli item search <query> --json")
    }

    @Test("item mutations fail closed when canonical database cannot open")
    func itemMutationsFailClosedWhenCanonicalDatabaseCannotOpen() throws {
        let fileVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-file-vault-\(UUID().uuidString)")
        try "not a directory".write(to: fileVault, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileVault) }

        let commands = [
            ["bookmark", "add", "https://example.com/fail-closed", "--json"],
            ["note", "create", "Fail closed note", "--json"],
            ["todo", "create", "Fail closed todo", "--json"],
            ["file", "add", "/tmp/missing.txt", "--json"]
        ]

        for command in commands {
            let result = try runCLI(args: command, vault: fileVault)
            let payload = try parseJSONObject(result.stdout)
            #expect(payload["ok"] as? Bool == false, "Expected \(command.joined(separator: " ")) to fail closed")
            #expect((payload["error"] as? String)?.contains("canonical SQLite database") == true)
        }
    }

    @Test("item move and unfile use confirmed second-brain mutation result shape")
    func itemMoveAndUnfileUseConfirmedMutationResultShape() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-item-mutation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let noteResult = try runCLI(args: ["note", "create", "Move via item door", "--json"], vault: vault)
        let note = try parseJSONObject(noteResult.stdout)
        let noteID = try #require(note["id"] as? String)

        let moveResult = try runCLI(args: ["item", "move", "note", noteID, "--path", "Projects", "--json"], vault: vault)
        let move = try parseJSONObject(moveResult.stdout)
        #expect(move["ok"] as? Bool == true)
        #expect(move["command"] as? String == "item.move")
        #expect(move["mutationAuditEntryID"] as? String != nil)
        #expect(move["routingDecisionID"] as? String != nil)
        #expect(move["agentActionID"] as? String != nil)
        let movedAfter = try #require(move["after"] as? [String: Any])
        #expect(movedAfter["folderID"] as? String != nil)

        let unfileResult = try runCLI(args: ["item", "unfile", "note", noteID, "--json"], vault: vault)
        let unfile = try parseJSONObject(unfileResult.stdout)
        #expect(unfile["ok"] as? Bool == true)
        #expect(unfile["command"] as? String == "item.unfile")
        #expect(unfile["mutationAuditEntryID"] as? String != nil)
        #expect(unfile["routingDecisionID"] as? String != nil)
        #expect(unfile["agentActionID"] as? String != nil)
        let unfiledAfter = try #require(unfile["after"] as? [String: Any])
        #expect(unfiledAfter["folderID"] == nil)
    }

    @Test("item delete previews then trashes through approved item API")
    func itemDeletePreviewsThenTrashesThroughApprovedItemAPI() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-item-delete-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let captureResult = try runCLI(
            args: [
                "capture", "add",
                "--kind", "note",
                "--title", "Dogfood cleanup delete fixture",
                "--stdin",
                "--json",
            ],
            vault: vault,
            stdin: "Temporary cleanup-safe item."
        )
        let capture = try parseJSONObject(captureResult.stdout)
        let noteID = try #require(
            (capture["item"] as? [String: Any])?["id"] as? String
                ?? (capture["note"] as? [String: Any])?["id"] as? String
                ?? capture["id"] as? String
        )

        let previewResult = try runCLI(
            args: ["item", "delete", "note", noteID, "--reason", "cleanup regression", "--json"],
            vault: vault
        )
        let preview = try parseJSONObject(previewResult.stdout)
        #expect(preview["ok"] as? Bool == true)
        #expect(preview["command"] as? String == "item.delete")
        #expect(preview["readOnly"] as? Bool == true)
        #expect(preview["changed"] as? Bool == false)
        #expect(preview["approvalRequired"] as? Bool == true)
        #expect(preview["nextSafeAction"] as? String == "approve_delete")
        let token = try #require(preview["requiredApprovalToken"] as? String)
        #expect(token.hasPrefix("DELETE_ITEM_"))

        let inspectBefore = try runCLI(args: ["item", "get", "note", noteID, "--json"], vault: vault)
        let before = try parseJSONObject(inspectBefore.stdout)
        #expect(before["ok"] as? Bool == true)

        let deleteResult = try runCLI(
            args: [
                "item", "delete", "note", noteID,
                "--reason", "cleanup regression",
                "--approve", token,
                "--execute",
                "--json",
            ],
            vault: vault
        )
        let deleted = try parseJSONObject(deleteResult.stdout)
        #expect(deleted["ok"] as? Bool == true)
        #expect(deleted["readOnly"] as? Bool == false)
        #expect(deleted["changed"] as? Bool == true)
        #expect(deleted["trashItemID"] as? String != nil)
        #expect(deleted["mutationAuditEntryID"] as? String != nil)
        #expect(deleted["agentActionID"] as? String != nil)

        let searchResult = try runCLI(
            args: ["item", "search", "Dogfood cleanup delete fixture", "--limit", "5", "--json"],
            vault: vault
        )
        let search = try parseJSONArray(searchResult.stdout)
        #expect(search.isEmpty)
    }

    @Test("item delete removes stale all library index entries")
    func itemDeleteRemovesStaleAllLibraryIndexEntries() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-item-delete-index-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let captureResult = try runCLI(
            args: [
                "capture", "add",
                "--kind", "note",
                "--title", "Dogfood cleanup stale index fixture",
                "--stdin",
                "--json",
            ],
            vault: vault,
            stdin: "Temporary cleanup-safe item."
        )
        let capture = try parseJSONObject(captureResult.stdout)
        let noteID = try #require(
            (capture["item"] as? [String: Any])?["id"] as? String
                ?? (capture["note"] as? [String: Any])?["id"] as? String
                ?? capture["id"] as? String
        )

        let ciderDir = vault.appendingPathComponent(".cider", isDirectory: true)
        try FileManager.default.createDirectory(at: ciderDir, withIntermediateDirectories: true)
        let indexURL = ciderDir.appendingPathComponent("index.json")
        let staleIndex: [String: Any] = [
            "version": 1,
            "items": [
                noteID: [
                    "type": "note",
                    "path": "Inbox/Notes/\(noteID).md",
                    "title": "Dogfood cleanup stale index fixture",
                    "createdAt": "2026-06-06T00:00:00Z",
                    "updatedAt": "2026-06-06T00:00:00Z",
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: staleIndex, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: indexURL)

        let previewResult = try runCLI(
            args: ["item", "delete", "note", noteID, "--reason", "cleanup stale index regression", "--json"],
            vault: vault
        )
        let preview = try parseJSONObject(previewResult.stdout)
        let token = try #require(preview["requiredApprovalToken"] as? String)

        _ = try runCLI(
            args: [
                "item", "delete", "note", noteID,
                "--reason", "cleanup stale index regression",
                "--approve", token,
                "--execute",
                "--json",
            ],
            vault: vault
        )

        let indexData = try Data(contentsOf: indexURL)
        let indexObject = try #require(JSONSerialization.jsonObject(with: indexData) as? [String: Any])
        let items = try #require(indexObject["items"] as? [String: Any])
        #expect(items[noteID] == nil)
    }

    @Test("item rebuild index prunes stale all library entries")
    func itemRebuildIndexPrunesStaleAllLibraryEntries() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-item-rebuild-index-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let staleID = UUID().uuidString
        let ciderDir = vault.appendingPathComponent(".cider", isDirectory: true)
        try FileManager.default.createDirectory(at: ciderDir, withIntermediateDirectories: true)
        let indexURL = ciderDir.appendingPathComponent("index.json")
        let staleIndex: [String: Any] = [
            "version": 1,
            "items": [
                staleID: [
                    "type": "bookmark",
                    "path": "Inbox/Bookmarks/\(staleID).json",
                    "title": "Dogfood cleanup stale all-library card",
                    "createdAt": "2026-06-06T00:00:00Z",
                    "updatedAt": "2026-06-06T00:00:00Z",
                    "url": "https://example.invalid/dogfood",
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: staleIndex, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: indexURL)

        let result = try runCLI(args: ["item", "rebuild-index", "--json"], vault: vault)
        let payload = try parseJSONObject(result.stdout)
        #expect(payload["ok"] as? Bool == true)
        #expect(payload["command"] as? String == "item.rebuild-index")
        #expect(payload["changed"] as? Bool == true)
        #expect(payload["removedStaleCount"] as? Int == 1)

        let indexData = try Data(contentsOf: indexURL)
        let indexObject = try #require(JSONSerialization.jsonObject(with: indexData) as? [String: Any])
        let items = try #require(indexObject["items"] as? [String: Any])
        #expect(items[staleID] == nil)
    }

    @Test("capture add with test run records manifest and cleanup command")
    func captureAddWithTestRunRecordsManifestAndCleanupCommand() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-test-run-manifest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let runID = "cid451-\(UUID().uuidString)"
        let result = try runCLI(
            args: [
                "capture", "add",
                "--kind", "note",
                "--title", "CID451 cleanup manifest fixture",
                "--test-run", runID,
                "--test-marker", "CID-451 cleanup-safe fixture",
                "--stdin",
                "--json",
            ],
            vault: vault,
            stdin: "Temporary agent test content."
        )
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status == 0)
        let testRun = try #require(payload["testRun"] as? [String: Any])
        #expect(testRun["runID"] as? String == runID)
        #expect(testRun["manifestPath"] as? String == ".cider/test-runs/\(runID).json")
        #expect(testRun["cleanupCommand"] as? String == "cider-cli test-run cleanup \(runID) --dry-run --json")
        let safeNextCommands = try #require(payload["safeNextCommands"] as? [String])
        #expect(safeNextCommands.contains("cider-cli test-run cleanup \(runID) --dry-run --json"))

        let manifestURL = vault.appendingPathComponent(".cider/test-runs/\(runID).json")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try #require(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        #expect(manifest["runID"] as? String == runID)
        #expect(manifest["marker"] as? String == "CID-451 cleanup-safe fixture")
        let items = try #require(manifest["items"] as? [[String: Any]])
        #expect(items.count == 1)
        #expect(items.first?["type"] as? String == "note")
        #expect(items.first?["title"] as? String == "CID451 cleanup manifest fixture")
        #expect(items.first?["captureEventID"] as? String != nil)
    }

    @Test("capture add titled stdin note stays consistent across recall and cleanup")
    func captureAddTitledStdinNoteStaysConsistentAcrossRecallAndCleanup() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-titled-note-capture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let title = "Memory trust audit blue notebook fixture"
        let body = "The spare blue notebook is on the lower shelf near the memory trust audit fixture marker 30956f."
        let runID = "cid468-\(UUID().uuidString)"
        let marker = "CID-468 memory trust note fixture"

        let captureResult = try runCLI(
            args: [
                "capture", "add",
                "--kind", "note",
                "--title", title,
                "--test-run", runID,
                "--test-marker", marker,
                "--stdin",
                "--json",
            ],
            vault: vault,
            stdin: body
        )
        let capture = try parseJSONObject(captureResult.stdout)
        let capturedItem = try #require(capture["item"] as? [String: Any])
        let noteID = try #require(capturedItem["id"] as? String)
        #expect(capturedItem["title"] as? String == title)
        #expect((capture["source"] as? [String: Any])?["text"] as? String == body)
        #expect((capture["indexing"] as? [String: Any])?["status"] as? String == "indexed")
        #expect((capture["testRun"] as? [String: Any])?["cleanupCommand"] as? String == "cider-cli test-run cleanup \(runID) --dry-run --json")

        let itemGetResult = try runCLI(args: ["item", "get", "note", noteID, "--json"], vault: vault)
        let itemGet = try parseJSONObject(itemGetResult.stdout)
        let itemGetItem = try #require(itemGet["item"] as? [String: Any])
        let chunks = try #require(itemGet["chunks"] as? [[String: Any]])
        #expect(itemGetItem["title"] as? String == title)
        #expect(chunks.contains { ($0["body"] as? String)?.contains(body) == true })

        let searchResult = try runCLI(args: ["item", "search", "spare blue notebook", "--limit", "3", "--json"], vault: vault)
        let search = try parseJSONArray(searchResult.stdout)
        #expect(search.prefix(3).contains {
            (($0["item"] as? [String: Any])?["id"] as? String) == noteID
                && (($0["item"] as? [String: Any])?["title"] as? String) == title
                && ($0["title"] as? String) == title
        })

        let cleanupResult = try runCLI(args: ["test-run", "cleanup", runID, "--dry-run", "--json"], vault: vault)
        let cleanup = try parseJSONObject(cleanupResult.stdout)
        let cleanupItems = try #require(cleanup["items"] as? [[String: Any]])
        #expect(cleanup["marker"] as? String == marker)
        #expect(cleanupItems.contains {
            ($0["id"] as? String) == noteID
                && ($0["title"] as? String) == title
                && ($0["status"] as? String) == "present"
        })

        let titleSearchResult = try runCLI(args: ["item", "search", title, "--limit", "3", "--json"], vault: vault)
        let titleSearch = try parseJSONArray(titleSearchResult.stdout)
        #expect(titleSearch.prefix(3).contains {
            (($0["item"] as? [String: Any])?["id"] as? String) == noteID
                && (($0["item"] as? [String: Any])?["title"] as? String) == title
                && ($0["title"] as? String) == title
        })
    }

    @Test("parallel capture add records every test-run item and indexes without transient lock drift")
    func parallelCaptureAddRecordsEveryTestRunItemAndIndexesWithoutTransientLockDrift() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-concurrent-capture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let runID = "cid465-\(UUID().uuidString)"
        let marker = "CID-465 concurrent capture fixture"
        let specs: [(label: String, expectedType: String, args: [String], stdin: String)] = [
            (
                "note",
                "note",
                [
                    "capture", "add",
                    "--kind", "note",
                    "--title", "CID465 concurrent note",
                    "--test-run", runID,
                    "--test-marker", marker,
                    "--stdin",
                    "--json",
                ],
                "Concurrent note body \(marker)"
            ),
            (
                "todo",
                "todo",
                [
                    "capture", "add",
                    "--kind", "todo",
                    "--title", "CID465 concurrent todo",
                    "--test-run", runID,
                    "--test-marker", marker,
                    "--stdin",
                    "--json",
                ],
                "Concurrent todo body \(marker)"
            ),
            (
                "contact",
                "contact",
                [
                    "capture", "add",
                    "--kind", "contact",
                    "--name", "CID465 Concurrent Contact",
                    "--email", "cid465@example.com",
                    "--test-run", runID,
                    "--test-marker", marker,
                    "--stdin",
                    "--json",
                ],
                "Concurrent contact notes \(marker)"
            ),
            (
                "event",
                "event",
                [
                    "capture", "add",
                    "--kind", "event",
                    "--title", "CID465 concurrent event",
                    "--date", "2026-06-09",
                    "--time", "10:00 AM",
                    "--location", "Test Room",
                    "--test-run", runID,
                    "--test-marker", marker,
                    "--stdin",
                    "--json",
                ],
                "Concurrent event notes \(marker)"
            ),
        ]

        let captures = try runCLIConcurrently(specs: specs, vault: vault)
        let payloads = try captures.map { capture -> [String: Any] in
            #expect(capture.status == 0, "\(capture.label) stderr: \(capture.stderr)")
            let payload = try parseJSONObject(capture.stdout)
            #expect(payload["command"] as? String == "capture.add")
            #expect((payload["item"] as? [String: Any])?["type"] as? String == capture.expectedType)
            #expect((payload["indexing"] as? [String: Any])?["status"] as? String == "indexed")
            #expect((payload["partialSuccess"] as? [String: Any])?["status"] as? String != "canonical_side_effects_incomplete")
            let safeCommands = try #require(payload["safeNextCommands"] as? [String])
            #expect(safeCommands.contains("cider-cli test-run cleanup \(runID) --dry-run --json"))
            return payload
        }
        let capturedIDs = Set(payloads.compactMap { ($0["item"] as? [String: Any])?["id"] as? String })
        #expect(capturedIDs.count == specs.count)

        let cleanupResult = try runCLI(args: ["test-run", "cleanup", runID, "--dry-run", "--json"], vault: vault)
        let cleanup = try parseJSONObject(cleanupResult.stdout)
        #expect(cleanup["itemCount"] as? Int == specs.count)
        let cleanupItems = try #require(cleanup["items"] as? [[String: Any]])
        let cleanupIDs = Set(cleanupItems.compactMap { $0["id"] as? String })
        #expect(cleanupIDs == capturedIDs)
        #expect(cleanupItems.allSatisfy { $0["status"] as? String == "present" })
    }

    @Test("test run cleanup previews and trashes only manifest items")
    func testRunCleanupPreviewsAndTrashesOnlyManifestItems() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-test-run-cleanup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let runID = "cid451-\(UUID().uuidString)"
        let captured = try runCLI(
            args: [
                "capture", "add",
                "--kind", "note",
                "--title", "CID451 cleanup execute fixture",
                "--test-run", runID,
                "--test-marker", "CID-451 cleanup execute fixture",
                "--stdin",
                "--json",
            ],
            vault: vault,
            stdin: "Temporary agent test content."
        )
        let capturePayload = try parseJSONObject(captured.stdout)
        let noteID = try #require((capturePayload["item"] as? [String: Any])?["id"] as? String)

        let bookmark = try runCLI(
            args: [
                "capture", "add",
                "--kind", "bookmark",
                "--url", "https://example.com/cid451-cleanup",
                "--title", "CID451 cleanup bookmark fixture",
                "--test-run", runID,
                "--test-marker", "CID-451 cleanup execute fixture",
                "--no-wait",
                "--json",
            ],
            vault: vault
        )
        let bookmarkPayload = try parseJSONObject(bookmark.stdout)
        let bookmarkID = try #require((bookmarkPayload["item"] as? [String: Any])?["id"] as? String)

        let sourceFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("cid451-cleanup-file-\(UUID().uuidString).txt")
        try "Temporary agent test file.".write(to: sourceFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: sourceFile) }
        let fileCapture = try runCLI(
            args: [
                "capture", "add",
                "--kind", "file",
                "--path", sourceFile.path,
                "--title", "CID451 cleanup file fixture",
                "--test-run", runID,
                "--test-marker", "CID-451 cleanup execute fixture",
                "--json",
            ],
            vault: vault
        )
        let filePayload = try parseJSONObject(fileCapture.stdout)
        let fileID = try #require((filePayload["item"] as? [String: Any])?["id"] as? String)

        let keeper = try runCLI(
            args: [
                "capture", "add",
                "--kind", "note",
                "--title", "Real note that must survive",
                "--stdin",
                "--json",
            ],
            vault: vault,
            stdin: "This is not in the test-run manifest."
        )
        let keeperPayload = try parseJSONObject(keeper.stdout)
        let keeperID = try #require((keeperPayload["item"] as? [String: Any])?["id"] as? String)

        let previewResult = try runCLI(
            args: ["test-run", "cleanup", runID, "--dry-run", "--json"],
            vault: vault
        )
        let preview = try parseJSONObject(previewResult.stdout)
        #expect(preview["ok"] as? Bool == true)
        #expect(preview["command"] as? String == "test-run.cleanup")
        #expect(preview["readOnly"] as? Bool == true)
        #expect(preview["changed"] as? Bool == false)
        #expect(preview["approvalRequired"] as? Bool == true)
        let token = try #require(preview["requiredApprovalToken"] as? String)
        #expect(token.hasPrefix("CLEANUP_TEST_RUN_"))
        let items = try #require(preview["items"] as? [[String: Any]])
        #expect(items.count == 3)
        #expect(Set(items.compactMap { $0["id"] as? String }) == [noteID, bookmarkID, fileID])
        #expect(items.allSatisfy { $0["reason"] as? String == "Recorded in test-run manifest \(runID)." })

        let cleanupResult = try runCLI(
            args: [
                "test-run", "cleanup", runID,
                "--approve", token,
                "--execute",
                "--json",
            ],
            vault: vault
        )
        let cleanup = try parseJSONObject(cleanupResult.stdout)
        #expect(cleanup["ok"] as? Bool == true)
        #expect(cleanup["readOnly"] as? Bool == false)
        #expect(cleanup["changed"] as? Bool == true)
        #expect(cleanup["trashedCount"] as? Int == 3)
        #expect(cleanup["verifiedGoneCount"] as? Int == 3)
        #expect(cleanup["indexRemovedCount"] as? Int == 3)

        let deletedGet = try runCLI(args: ["item", "get", "note", noteID, "--json"], vault: vault)
        #expect(deletedGet.status != 0)
        let bookmarkGet = try runCLI(args: ["item", "get", "bookmark", bookmarkID, "--json"], vault: vault)
        #expect(bookmarkGet.status != 0)
        let fileGet = try runCLI(args: ["item", "get", "vaultFile", fileID, "--json"], vault: vault)
        #expect(fileGet.status != 0)

        let keeperGet = try runCLI(args: ["item", "get", "note", keeperID, "--json"], vault: vault)
        #expect(keeperGet.status == 0)
    }

    @Test("test run cleanup refuses missing manifest")
    func testRunCleanupRefusesMissingManifest() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-test-run-cleanup-missing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let result = try runCLI(
            args: [
                "test-run", "cleanup", "missing-cid451",
                "--approve", "CLEANUP_TEST_RUN_FAKE",
                "--execute",
                "--json",
            ],
            vault: vault
        )
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status != 0)
        #expect(payload["ok"] as? Bool == false)
        #expect(payload["command"] as? String == "test-run.cleanup")
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["reason"] as? String == "manifest_not_found")
        #expect(payload["manualReviewRequired"] as? Bool == true)
    }

    @Test("file capture returns a canonical vault file id resolvable by item commands")
    func fileCaptureReturnsCanonicalVaultFileIDResolvableByItemCommands() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-file-capture-identity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-file-capture-source-\(UUID().uuidString).txt")
        try "file capture identity regression".write(to: source, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: source) }

        let captureResult = try runCLI(
            args: ["capture", "add", "--kind", "file", "--path", source.path, "--json"],
            vault: vault
        )
        let capture = try parseJSONObject(captureResult.stdout)
        let item = try #require(capture["item"] as? [String: Any])
        let itemID = try #require(item["id"] as? String)

        let getResult = try runCLI(args: ["item", "get", "vaultFile", itemID, "--json"], vault: vault)
        let get = try parseJSONObject(getResult.stdout)
        #expect(getResult.status == 0)
        #expect(get["ok"] as? Bool == true)

        let contextResult = try runCLI(args: ["item", "context", "file", itemID, "--json"], vault: vault)
        let context = try parseJSONObject(contextResult.stdout)
        #expect(contextResult.status == 0)
        #expect(context["ok"] as? Bool == true)

        let db = CiderDatabase()
        try db.open(at: vault.appendingPathComponent(".cider/cider.db"))
        defer { db.close() }

        let count = try db.prepare("SELECT COUNT(*) FROM items WHERE type = 'vaultFile';")
        #expect(try count.step())
        #expect(count.int(at: 0) == 1)

        let path = try db.prepare("SELECT relative_path FROM items WHERE type = 'vaultFile' LIMIT 1;")
        #expect(try path.step())
        #expect(path.string(at: 0).hasPrefix("Inbox/Files/"))
    }

    @Test("file capture indexes readable text files for item search")
    func fileCaptureIndexesReadableTextFilesForItemSearch() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-file-capture-text-index-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let distinctiveWord = "CID298SaffronQuasarReceipt"
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-file-capture-text-source-\(UUID().uuidString).txt")
        try """
        This source file checks text indexing for Cider captures.
        Distinctive body token: \(distinctiveWord)
        """.write(to: source, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: source) }

        let captureResult = try runCLI(
            args: ["capture", "add", "--kind", "file", "--path", source.path, "--json"],
            vault: vault
        )
        let capture = try parseJSONObject(captureResult.stdout)
        #expect(captureResult.status == 0)
        let item = try #require(capture["item"] as? [String: Any])
        let itemID = try #require(item["id"] as? String)
        let indexing = try #require(capture["indexing"] as? [String: Any])
        #expect(indexing["status"] as? String == "indexed")
        #expect(indexing["ownerType"] as? String == "vaultFile")
        #expect(indexing["ownerID"] as? String == itemID)

        let searchResult = try runCLI(
            args: ["item", "search", distinctiveWord, "--json"],
            vault: vault
        )
        let results = try parseJSONArray(searchResult.stdout)
        #expect(searchResult.status == 0)
        #expect(results.contains { result in
            guard let owner = result["owner"] as? [String: Any] else { return false }
            return owner["ownerType"] as? String == "vaultFile"
                && owner["ownerID"] as? String == itemID
        })
    }

    @Test("item apply-intent approves staged Space intent without moving bookmark files")
    func itemApplyIntentApprovesStagedSpaceIntentWithoutMovingBookmarkFiles() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-apply-space-intent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let captureResult = try runCLI(
            args: [
                "capture", "add",
                "--kind", "bookmark",
                "--url", "https://www.rottentomatoes.com/tv/the_vampire_lestat/s01",
                "--title", "The Vampire Lestat: Season 1 | Rotten Tomatoes",
                "--no-wait",
                "--json",
            ],
            vault: vault
        )
        let capture = try parseJSONObject(captureResult.stdout)
        #expect(captureResult.status == 0)
        let item = try #require(capture["item"] as? [String: Any])
        let itemID = try #require(item["id"] as? String)
        let originalPath = try #require(item["relativePath"] as? String)
        #expect(originalPath.hasPrefix("Inbox/Bookmarks/"))

        let spaceIntent = try #require(capture["spaceIntent"] as? [String: Any])
        #expect(spaceIntent["spaceName"] as? String == "Media")
        #expect(spaceIntent["area"] as? String == "Shows")
        let safeCommands = try #require(capture["safeNextCommands"] as? [String])
        #expect(safeCommands.contains("cider-cli item apply-intent bookmark \(itemID) --intent space --json"))

        let applyResult = try runCLI(
            args: ["item", "apply-intent", "bookmark", itemID, "--intent", "space", "--json"],
            vault: vault
        )
        let apply = try parseJSONObject(applyResult.stdout)
        #expect(applyResult.status == 0)
        #expect(apply["ok"] as? Bool == true)
        #expect(apply["command"] as? String == "item.apply-intent")
        #expect(apply["changed"] as? Bool == true)
        let approvedIntent = try #require(apply["approvedIntent"] as? [String: Any])
        #expect(approvedIntent["spaceName"] as? String == "Media")
        #expect(approvedIntent["area"] as? String == "Shows")
        #expect(approvedIntent["wouldRouteWithoutReview"] as? Bool == false)

        let contextResult = try runCLI(args: ["item", "context", "bookmark", itemID, "--json"], vault: vault)
        let context = try parseJSONObject(contextResult.stdout)
        let memberships = try #require(context["spaceMemberships"] as? [[String: Any]])
        #expect(memberships.contains {
            $0["spaceName"] as? String == "Media"
                && (($0["reason"] as? String)?.contains("Rotten Tomatoes") == true)
        })
        let contextItem = try #require(context["item"] as? [String: Any])
        #expect(contextItem["relativePath"] as? String == originalPath)
    }

    @Test("item apply-intent approves staged project intent without moving bookmark files")
    func itemApplyIntentApprovesStagedProjectIntentWithoutMovingBookmarkFiles() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-apply-project-intent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let captureResult = try runCLI(
            args: [
                "capture", "add",
                "--kind", "bookmark",
                "--url", "https://x.com/openaidevs/status/2062599291479478275?s=12",
                "--title", "OpenAI Developers Codex iOS app loop",
                "--no-wait",
                "--json",
            ],
            vault: vault
        )
        let capture = try parseJSONObject(captureResult.stdout)
        #expect(captureResult.status == 0)
        let item = try #require(capture["item"] as? [String: Any])
        let itemID = try #require(item["id"] as? String)
        let originalPath = try #require(item["relativePath"] as? String)
        #expect(originalPath.hasPrefix("Inbox/Bookmarks/"))

        let projectIntent = try #require(capture["projectIntent"] as? [String: Any])
        #expect(projectIntent["projectName"] as? String == "Cider iOS")
        #expect(capture["recommendedNextAction"] as? String == "review_intent")
        let safeCommands = try #require(capture["safeNextCommands"] as? [String])
        #expect(safeCommands.contains("cider-cli item apply-intent bookmark \(itemID) --intent project --json"))

        let applyResult = try runCLI(
            args: ["item", "apply-intent", "bookmark", itemID, "--intent", "project", "--json"],
            vault: vault
        )
        let apply = try parseJSONObject(applyResult.stdout)
        #expect(applyResult.status == 0)
        #expect(apply["ok"] as? Bool == true)
        #expect(apply["changed"] as? Bool == true)
        #expect(apply["intent"] as? String == "project")
        let approvedIntent = try #require(apply["approvedIntent"] as? [String: Any])
        #expect(approvedIntent["projectName"] as? String == "Cider iOS")
        #expect(approvedIntent["projectID"] as? String == "cider-ios")
        #expect(approvedIntent["wouldRouteWithoutReview"] as? Bool == false)

        let projectContextResult = try runCLI(args: ["item", "project-context", "cider-ios", "--json"], vault: vault)
        let projectContext = try parseJSONObject(projectContextResult.stdout)
        let backlinks = try #require(projectContext["backlinks"] as? [[String: Any]])
        #expect(backlinks.contains { relation in
            guard let source = relation["sourceOwner"] as? [String: Any] else { return false }
            return source["ownerType"] as? String == "bookmark"
                && source["ownerID"] as? String == itemID
                && relation["relationType"] as? String == "artifact_of"
        })

        let contextResult = try runCLI(args: ["item", "context", "bookmark", itemID, "--json"], vault: vault)
        let context = try parseJSONObject(contextResult.stdout)
        let contextItem = try #require(context["item"] as? [String: Any])
        #expect(contextItem["relativePath"] as? String == originalPath)
    }

    @Test("capture add accepts nested target folder paths through folder flag")
    func captureAddAcceptsNestedTargetFolderPathsThroughFolderFlag() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-capture-folder-path-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let result = try runCLI(
            args: [
                "capture", "add",
                "--kind", "note",
                "--folder", "Inbox/Notes",
                "Nested folder target note",
                "--json",
            ],
            vault: vault
        )
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status == 0)
        let item = try #require(payload["item"] as? [String: Any])
        #expect(item["relativePath"] as? String == "Inbox/Notes/Nested folder target note.md")
        let routing = try #require(payload["routing"] as? [String: Any])
        #expect(routing["status"] as? String == "recorded")
        #expect(routing["statusReason"] == nil)
    }

    @Test("item move path rejects filename shaped target folders")
    func itemMovePathRejectsFilenameShapedTargetFolders() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-item-move-file-path-guard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let createResult = try runCLI(
            args: ["note", "create", "Do Not File Shape", "--content", "body", "--json"],
            vault: vault
        )
        let created = try parseJSONObject(createResult.stdout)
        let noteID = try #require(created["id"] as? String)

        let moveResult = try runCLI(
            args: ["item", "move", "note", noteID, "--path", "Inbox/Bookmarks/Example.webloc", "--json"],
            vault: vault
        )
        let move = try parseJSONObject(moveResult.stdout)

        #expect(moveResult.status != 0)
        #expect(move["ok"] as? Bool == false)
        #expect((move["error"] as? String)?.contains("looks like a file path") == true)
        #expect((move["error"] as? String)?.contains("--folder Inbox/Bookmarks") == true)
    }

    @Test("item move note into project notes records project ownership and unfile clears it")
    func itemMoveNoteIntoProjectNotesRecordsProjectOwnership() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-project-note-move-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let createResult = try runCLI(
            args: ["note", "create", "Migrated Cider Note", "--content", "project note body", "--json"],
            vault: vault
        )
        let created = try parseJSONObject(createResult.stdout)
        let noteID = try #require(created["id"] as? String)

        let moveResult = try runCLI(
            args: ["item", "move", "note", noteID, "--path", "Projects/Cider/Notes", "--json"],
            vault: vault
        )
        let move = try parseJSONObject(moveResult.stdout)
        #expect(move["ok"] as? Bool == true)
        let after = try #require(move["after"] as? [String: Any])
        #expect(after["relativePath"] as? String == "Projects/Cider/Notes/Migrated Cider Note.md")

        let inspectResult = try runCLI(args: ["item", "get", "note", noteID, "--json"], vault: vault)
        let inspected = try parseJSONObject(inspectResult.stdout)
        let item = try #require(inspected["item"] as? [String: Any])
        #expect(item["relativePath"] as? String == "Projects/Cider/Notes/Migrated Cider Note.md")
        let ownerRelations = try #require(inspected["ownerRelations"] as? [[String: Any]])
        #expect(ownerRelations.contains { relation in
            guard relation["relationType"] as? String == "artifact_of",
                  let target = relation["targetOwner"] as? [String: Any],
                  target["ownerType"] as? String == "project",
                  target["ownerID"] as? String == "cider",
                  let metadata = relation["metadata"] as? [String: String]
            else { return false }
            return metadata["artifactType"] == "note"
                && metadata["path"] == "Projects/Cider/Notes/Migrated Cider Note.md"
        })

        let unfileResult = try runCLI(args: ["item", "unfile", "note", noteID, "--json"], vault: vault)
        let unfile = try parseJSONObject(unfileResult.stdout)
        #expect(unfile["ok"] as? Bool == true)

        let reinspectResult = try runCLI(args: ["item", "get", "note", noteID, "--json"], vault: vault)
        let reinspected = try parseJSONObject(reinspectResult.stdout)
        let clearedRelations = try #require(reinspected["ownerRelations"] as? [[String: Any]])
        #expect(!clearedRelations.contains { relation in
            relation["relationType"] as? String == "artifact_of"
                && (relation["targetOwner"] as? [String: Any])?["ownerType"] as? String == "project"
        })
    }

    @Test("sync project seeds known Cider workspace in a fresh vault")
    func syncProjectSeedsKnownCiderWorkspaceInFreshVault() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-project-context-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let boardCreate = try runCLI(args: ["board", "create", "Cider", "--json"], vault: vault)
        #expect(boardCreate.status == 0)

        let result = try runCLI(args: ["item", "sync-project", "cider", "--json"], vault: vault)
        let payload = try parseJSONObject(result.stdout)

        #expect(payload["ok"] as? Bool == true)
        #expect(payload["command"] as? String == "item.sync-project")
        #expect(payload["readOnly"] as? Bool == false)
        #expect(payload["changed"] as? Bool == true)
        let project = try #require(payload["project"] as? [String: Any])
        #expect(project["id"] as? String == "cider")
        let boardOwners = try #require(payload["boardOwners"] as? [[String: Any]])
        #expect(boardOwners.contains { $0["ownerType"] as? String == "kanban_board" })
    }

    @Test("project context reports read-only inspection contract")
    func projectContextReportsReadOnlyInspectionContract() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-project-context-readonly-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        _ = try runCLI(args: ["board", "create", "Cider", "--json"], vault: vault)
        _ = try runCLI(args: ["item", "sync-project", "cider", "--json"], vault: vault)

        let result = try runCLI(args: ["item", "project-context", "cider", "--json"], vault: vault)
        let payload = try parseJSONObject(result.stdout)

        #expect(payload["ok"] as? Bool == true)
        #expect(payload["command"] as? String == "item.project-context")
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["mutationReason"] == nil)
        let safeCommands = try #require(payload["safeCommands"] as? [String])
        #expect(safeCommands.contains("cider-cli item sync-project cider --json"))
    }

    @Test("memory suggest reports mutating reviewable candidate JSON contract")
    func memorySuggestReportsMutatingReviewableCandidateJSONContract() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-memory-suggest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        _ = try runCLI(args: ["board", "create", "Cider", "--json"], vault: vault)
        _ = try runCLI(args: ["item", "sync-project", "cider", "--json"], vault: vault)

        let result = try runCLI(args: [
            "item", "memory-suggest", "project", "cider",
            "--kind", "agent_lesson",
            "--value", "Prefer reviewable candidates before permanent memory writes.",
            "--evidence", "CID-351 requires no automatic memory promotion.",
            "--source", "codex",
            "--confidence", "0.9",
            "--json",
        ], vault: vault)
        let payload = try parseJSONObject(result.stdout)

        #expect(payload["ok"] as? Bool == true)
        #expect(payload["command"] as? String == "item.memory-suggest")
        #expect(payload["readOnly"] as? Bool == false)
        #expect(payload["changed"] as? Bool == true)
        let owner = try #require(payload["owner"] as? [String: Any])
        #expect(owner["ownerType"] as? String == "project")
        #expect(owner["ownerID"] as? String == "cider")
        let candidate = try #require(payload["candidate"] as? [String: Any])
        #expect(candidate["kind"] as? String == "memory_candidate")
        #expect(candidate["reviewState"] as? String == "suggested")
        let metadata = try #require(candidate["metadata"] as? [String: String])
        #expect(metadata["memory_kind"] == "agent_lesson")
        let action = try #require(payload["agentAction"] as? [String: Any])
        #expect(action["actionType"] as? String == "memory_candidate_suggested")
        let safeCommands = try #require(payload["safeNextCommands"] as? [String])
        #expect(safeCommands.contains("cider-cli item project-context cider --json"))
        #expect(safeCommands.contains("cider-cli capture review-queue --json"))
    }

    @Test("media identify json separates read-only review from mutating apply")
    func mediaIdentifyJSONSeparatesReadOnlyReviewFromMutatingApply() throws {
        let dryRunReport = MediaBackfillReport(
            proposedItems: [],
            reviewItems: [],
            skippedCount: 0,
            createdCount: 0,
            updatedCount: 0
        )
        let dryRun = CiderCLI.mediaBackfillReportToDict(dryRunReport, mode: .dryRun)

        #expect(dryRun["command"] as? String == "media.identify")
        #expect(dryRun["readOnly"] as? Bool == true)
        #expect(dryRun["changed"] as? Bool == false)
        #expect(dryRun["mutationReason"] == nil)
        let reviewLane = try #require(dryRun["reviewLane"] as? [String: Any])
        let safeActions = try #require(reviewLane["safeActions"] as? [String])
        #expect(safeActions == ["media identify --dry-run --json"])

        let actions = try #require(reviewLane["actions"] as? [[String: Any]])
        #expect(actions.contains { action in
            action["command"] as? String == "media identify --apply --json"
                && action["readOnly"] as? Bool == false
                && action["requiresApproval"] as? Bool == true
        })

        let applyReport = MediaBackfillReport(
            proposedItems: [],
            reviewItems: [],
            skippedCount: 0,
            createdCount: 1,
            updatedCount: 0,
            actionRecords: [
                MediaBackfillActionRecord(
                    mediaItemID: "steam-1145350",
                    action: "media.backfill.create",
                    status: "succeeded",
                    summary: "Created media item"
                )
            ]
        )
        let apply = CiderCLI.mediaBackfillReportToDict(applyReport, mode: .apply)

        #expect(apply["command"] as? String == "media.identify")
        #expect(apply["readOnly"] as? Bool == false)
        #expect(apply["changed"] as? Bool == true)
        #expect((apply["mutationReason"] as? String)?.contains("MediaItem YAML") == true)
    }

    @Test("media identify dry-run is reachable as strict process json")
    func mediaIdentifyDryRunIsReachableAsStrictProcessJSON() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-media-identify-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let result = try runCLI(args: ["media", "identify", "--dry-run", "--json"], vault: vault)
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status == 0)
        #expect(result.stdout.first == "{")
        #expect(payload["command"] as? String == "media.identify")
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["legacyRemoved"] == nil)
        let reviewLane = try #require(payload["reviewLane"] as? [String: Any])
        #expect(reviewLane["safeActions"] as? [String] == ["media identify --dry-run --json"])
    }

    @Test("contact profile and field commands are reachable as strict process json")
    func contactProfileAndFieldCommandsAreReachableAsStrictProcessJSON() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-contact-contract-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let profileJSON = #"{"displayName":"Agent Contract Contact","email":"agent@example.com"}"#
        let apply = try runCLI(
            args: [
                "contact", "profile", "apply", "Agent Contract Contact",
                "--profile-json", profileJSON,
                "--create",
                "--json",
            ],
            vault: vault
        )
        let applyPayload = try parseJSONObject(apply.stdout)
        #expect(apply.status == 0)
        #expect(apply.stdout.first == "{")
        #expect(applyPayload["ok"] as? Bool == true)
        #expect(applyPayload["command"] as? String == "contact.profile")
        #expect(applyPayload["action"] as? String == "created")
        #expect(applyPayload["changed"] as? Bool == true)
        #expect(applyPayload["mutationSource"] as? String == "contact.profile.apply")

        let show = try runCLI(args: ["contact", "profile", "show", "Agent Contract Contact", "--json"], vault: vault)
        let showPayload = try parseJSONObject(show.stdout)
        #expect(show.status == 0)
        #expect(show.stdout.first == "{")
        #expect(showPayload["ok"] as? Bool == true)
        #expect(showPayload["command"] as? String == "contact.profile")
        #expect(showPayload["action"] as? String == "show")
        #expect(showPayload["readOnly"] as? Bool == true)
        #expect(showPayload["changed"] as? Bool == false)

        let add = try runCLI(
            args: [
                "contact", "field", "add", "Agent Contract Contact",
                "--section", "Context",
                "--label", "Source",
                "--value", "Codex",
                "--json",
            ],
            vault: vault
        )
        let addPayload = try parseJSONObject(add.stdout)
        #expect(add.status == 0)
        #expect(add.stdout.first == "{")
        #expect(addPayload["ok"] as? Bool == true)
        #expect(addPayload["command"] as? String == "contact.field")
        #expect(addPayload["action"] as? String == "added")
        #expect(addPayload["changed"] as? Bool == true)
        #expect(addPayload["mutationSource"] as? String == "contact.field.add")
        let addedField = try #require(addPayload["field"] as? [String: Any])
        let fieldID = try #require(addedField["id"] as? String)
        #expect(addedField["label"] as? String == "Source")

        let update = try runCLI(
            args: [
                "contact", "field", "update", "Agent Contract Contact", String(fieldID.prefix(8)),
                "--value", "Hermes",
                "--json",
            ],
            vault: vault
        )
        let updatePayload = try parseJSONObject(update.stdout)
        #expect(update.status == 0)
        #expect(updatePayload["action"] as? String == "updated")
        let updatedField = try #require(updatePayload["field"] as? [String: Any])
        #expect(updatedField["value"] as? String == "Hermes")

        let list = try runCLI(args: ["contact", "field", "list", "Agent Contract Contact", "--json"], vault: vault)
        let listPayload = try parseJSONObject(list.stdout)
        #expect(list.status == 0)
        #expect(listPayload["ok"] as? Bool == true)
        #expect(listPayload["command"] as? String == "contact.field")
        #expect(listPayload["action"] as? String == "list")
        #expect(listPayload["readOnly"] as? Bool == true)
        #expect(listPayload["changed"] as? Bool == false)
        let fields = try #require(listPayload["fields"] as? [[String: Any]])
        #expect(fields.count == 1)

        let delete = try runCLI(
            args: ["contact", "field", "delete", "Agent Contract Contact", String(fieldID.prefix(8)), "--json"],
            vault: vault
        )
        let deletePayload = try parseJSONObject(delete.stdout)
        #expect(delete.status == 0)
        #expect(deletePayload["action"] as? String == "deleted")
        #expect(deletePayload["changed"] as? Bool == true)
    }

    @Test("board mutation commands return strict process json")
    func boardMutationCommandsReturnStrictProcessJSON() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-board-mutation-json-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let create = try runCLI(args: ["board", "create", "Agent Contract Board", "--json"], vault: vault)
        let createPayload = try parseJSONObject(create.stdout)
        #expect(create.status == 0)
        #expect(create.stdout.first == "{")
        #expect(createPayload["ok"] as? Bool == true)
        #expect(createPayload["command"] as? String == "board.create")
        let board = try #require(createPayload["board"] as? [String: Any])
        let boardID = try #require(board["id"] as? String)

        let addColumn = try runCLI(args: ["board", "add-column", boardID, "--name", "Review", "--json"], vault: vault)
        let addColumnPayload = try parseJSONObject(addColumn.stdout)
        #expect(addColumn.status == 0)
        #expect(addColumnPayload["command"] as? String == "board.add-column")

        let addCard = try runCLI(args: ["board", "add-card", boardID, "--column", "Backlog", "--title", "Board JSON card", "--json"], vault: vault)
        let addCardPayload = try parseJSONObject(addCard.stdout)
        #expect(addCard.status == 0)
        #expect(addCardPayload["command"] as? String == "board.add-card")
        let card = try #require(addCardPayload["card"] as? [String: Any])
        let cardID = try #require(card["id"] as? String)

        let updateCard = try runCLI(args: ["board", "update-card", boardID, "--card", cardID, "--title", "Board JSON card updated", "--json"], vault: vault)
        let updateCardPayload = try parseJSONObject(updateCard.stdout)
        #expect(updateCard.status == 0)
        #expect(updateCardPayload["command"] as? String == "board.update-card")
        #expect(updateCardPayload["changed"] as? Bool == true)
        #expect(updateCardPayload["projectionRefreshed"] as? Bool == true)

        let moveCard = try runCLI(args: ["board", "move-card", boardID, "--card", cardID, "--to", "Review", "--json"], vault: vault)
        let moveCardPayload = try parseJSONObject(moveCard.stdout)
        #expect(moveCard.status == 0)
        #expect(moveCardPayload["command"] as? String == "board.move-card")
        #expect(moveCardPayload["changed"] as? Bool == true)
        let toColumn = try #require(moveCardPayload["toColumn"] as? [String: Any])
        #expect(toColumn["name"] as? String == "Review")

        let setDone = try runCLI(args: ["board", "set-column-done", boardID, "--column", "Review", "--done", "--json"], vault: vault)
        let setDonePayload = try parseJSONObject(setDone.stdout)
        #expect(setDone.status == 0)
        #expect(setDonePayload["command"] as? String == "board.set-column-done")
        #expect(setDonePayload["changed"] as? Bool == true)

        let renameColumn = try runCLI(args: ["board", "rename-column", boardID, "--column", "Review", "--to", "Ready", "--json"], vault: vault)
        let renameColumnPayload = try parseJSONObject(renameColumn.stdout)
        #expect(renameColumn.status == 0)
        #expect(renameColumnPayload["command"] as? String == "board.rename-column")

        let deleteCard = try runCLI(args: ["board", "delete-card", boardID, "--card", cardID, "--json"], vault: vault)
        let deleteCardPayload = try parseJSONObject(deleteCard.stdout)
        #expect(deleteCard.status == 0)
        #expect(deleteCardPayload["command"] as? String == "board.delete-card")
        #expect(deleteCardPayload["changed"] as? Bool == true)

        let deleteColumn = try runCLI(args: ["board", "delete-column", boardID, "--column", "Ready", "--json"], vault: vault)
        let deleteColumnPayload = try parseJSONObject(deleteColumn.stdout)
        #expect(deleteColumn.status == 0)
        #expect(deleteColumnPayload["command"] as? String == "board.delete-column")

        let renameBoard = try runCLI(args: ["board", "rename", boardID, "--to", "Agent Contract Board Renamed", "--json"], vault: vault)
        let renameBoardPayload = try parseJSONObject(renameBoard.stdout)
        #expect(renameBoard.status == 0)
        #expect(renameBoardPayload["command"] as? String == "board.rename")

        let badMove = try runCLI(args: ["board", "move-card", boardID, "--card", cardID, "--to", "Missing", "--json"], vault: vault)
        let badMovePayload = try parseJSONObject(badMove.stdout)
        #expect(badMove.status == 1)
        #expect(badMovePayload["ok"] as? Bool == false)

        let deleteBoard = try runCLI(args: ["board", "delete", boardID, "--json"], vault: vault)
        let deleteBoardPayload = try parseJSONObject(deleteBoard.stdout)
        #expect(deleteBoard.status == 0)
        #expect(deleteBoardPayload["command"] as? String == "board.delete")
        #expect(deleteBoardPayload["changed"] as? Bool == true)
    }

    @Test("board read commands return normalized strict process json")
    func boardReadCommandsReturnNormalizedStrictProcessJSON() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-board-read-json-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let create = try runCLI(args: ["board", "create", "Agent Read Board", "--json"], vault: vault)
        let createPayload = try parseJSONObject(create.stdout)
        let board = try #require(createPayload["board"] as? [String: Any])
        let boardID = try #require(board["id"] as? String)

        let addCard = try runCLI(
            args: ["board", "add-card", boardID, "--column", "Backlog", "--title", "Read JSON card", "--json"],
            vault: vault
        )
        let addCardPayload = try parseJSONObject(addCard.stdout)
        let card = try #require(addCardPayload["card"] as? [String: Any])
        let cardID = try #require(card["id"] as? String)

        let list = try runCLI(args: ["board", "list", "--json"], vault: vault)
        let listPayload = try parseJSONObject(list.stdout)
        #expect(list.status == 0)
        #expect(listPayload["ok"] as? Bool == true)
        #expect(listPayload["command"] as? String == "board.list")
        #expect(listPayload["readOnly"] as? Bool == true)
        #expect(listPayload["changed"] as? Bool == false)
        #expect((listPayload["boards"] as? [[String: Any]])?.contains { $0["id"] as? String == boardID } == true)

        let show = try runCLI(args: ["board", "show", boardID, "--json"], vault: vault)
        let showPayload = try parseJSONObject(show.stdout)
        #expect(show.status == 0)
        #expect(showPayload["command"] as? String == "board.show")
        #expect(showPayload["readOnly"] as? Bool == true)
        #expect(showPayload["changed"] as? Bool == false)
        #expect(showPayload["boardDetail"] as? [String: Any] != nil)

        let workflow = try runCLI(args: ["board", "workflow", boardID, "--json"], vault: vault)
        let workflowPayload = try parseJSONObject(workflow.stdout)
        #expect(workflow.status == 0)
        #expect(workflowPayload["command"] as? String == "board.workflow")

        let recent = try runCLI(args: ["board", "recent", boardID, "--limit", "5", "--json"], vault: vault)
        let recentPayload = try parseJSONObject(recent.stdout)
        #expect(recent.status == 0)
        #expect(recentPayload["command"] as? String == "board.recent")
        #expect(recentPayload["limit"] as? Int == 5)

        let inspect = try runCLI(args: ["board", "card", "inspect", boardID, "--card", cardID, "--json"], vault: vault)
        let inspectPayload = try parseJSONObject(inspect.stdout)
        #expect(inspect.status == 0)
        #expect(inspectPayload["command"] as? String == "board.card.inspect")
        #expect(inspectPayload["readOnly"] as? Bool == true)
        #expect(inspectPayload["changed"] as? Bool == false)

        let children = try runCLI(args: ["board", "children", boardID, "--card", cardID, "--json"], vault: vault)
        let childrenPayload = try parseJSONObject(children.stdout)
        #expect(children.status == 0)
        #expect(childrenPayload["command"] as? String == "board.children")

        let missing = try runCLI(args: ["board", "show", "missing-board", "--json"], vault: vault)
        let missingPayload = try parseJSONObject(missing.stdout)
        #expect(missing.status == 1)
        #expect(missingPayload["ok"] as? Bool == false)
        #expect(missingPayload["command"] as? String == "board.show")
        #expect(missingPayload["readOnly"] as? Bool == true)
        #expect(missingPayload["changed"] as? Bool == false)
    }

    @Test("database admin commands return safe json envelopes")
    func databaseAdminCommandsReturnSafeJSONEnvelopes() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-db-json-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let integrity = try runCLI(args: ["db", "integrity", "--json"], vault: vault)
        let integrityPayload = try parseJSONObject(integrity.stdout)
        #expect(integrity.status == 0)
        #expect(integrityPayload["ok"] as? Bool == true)
        #expect(integrityPayload["command"] as? String == "db.integrity")
        #expect(integrityPayload["readOnly"] as? Bool == true)
        #expect(integrityPayload["changed"] as? Bool == false)

        let backup = try runCLI(args: ["db", "backup", "--json"], vault: vault)
        let backupPayload = try parseJSONObject(backup.stdout)
        #expect(backup.status == 0)
        #expect(backupPayload["ok"] as? Bool == true)
        #expect(backupPayload["command"] as? String == "db.backup")
        #expect(backupPayload["readOnly"] as? Bool == false)
        #expect(backupPayload["changed"] as? Bool == true)
        #expect(backupPayload["verification"] as? [String: Any] != nil)
        let createdBackup = try #require(backupPayload["backup"] as? [String: Any])
        #expect(createdBackup["path"] as? String != nil)

        let backups = try runCLI(args: ["db", "backups", "--json"], vault: vault)
        let backupsPayload = try parseJSONObject(backups.stdout)
        #expect(backupsPayload["command"] as? String == "db.backups")
        #expect(backupsPayload["readOnly"] as? Bool == true)
        #expect((backupsPayload["backups"] as? [[String: Any]])?.isEmpty == false)

        let dryRun = try runCLI(args: ["db", "restore", "latest", "--dry-run", "--json"], vault: vault)
        let dryRunPayload = try parseJSONObject(dryRun.stdout)
        #expect(dryRun.status == 0)
        #expect(dryRunPayload["ok"] as? Bool == true)
        #expect(dryRunPayload["command"] as? String == "db.restore")
        #expect(dryRunPayload["readOnly"] as? Bool == true)
        #expect(dryRunPayload["changed"] as? Bool == false)
        #expect(dryRunPayload["requiresConfirmation"] as? Bool == true)
        #expect(dryRunPayload["preRestoreSnapshotPlanned"] as? Bool == true)
        let activeAppBlocker = dryRunPayload["activeAppBlocker"] as? Bool == true

        let restoreWithoutConfirmation = try runCLI(args: ["db", "restore", "latest", "--json"], vault: vault)
        let restoreWithoutConfirmationPayload = try parseJSONObject(restoreWithoutConfirmation.stdout)
        #expect(restoreWithoutConfirmation.status == 1)
        #expect(restoreWithoutConfirmationPayload["ok"] as? Bool == false)
        #expect(restoreWithoutConfirmationPayload["command"] as? String == "db.restore")
        #expect(restoreWithoutConfirmationPayload["requiresConfirmation"] as? Bool == true)

        let restore = try runCLI(args: ["db", "restore", "latest", "--yes", "--json"], vault: vault)
        let restorePayload = try parseJSONObject(restore.stdout)
        #expect(restorePayload["command"] as? String == "db.restore")
        if activeAppBlocker {
            #expect(restore.status == 1)
            #expect(restorePayload["ok"] as? Bool == false)
            #expect(restorePayload["activeAppBlocker"] as? Bool == true)
            #expect(restorePayload["changed"] as? Bool == false)
        } else {
            #expect(restore.status == 0)
            #expect(restorePayload["ok"] as? Bool == true)
            #expect(restorePayload["readOnly"] as? Bool == false)
            #expect(restorePayload["changed"] as? Bool == true)
            #expect(restorePayload["preRestoreSnapshot"] as? [String: Any] != nil)
            let restoreIntegrity = try #require(restorePayload["integrity"] as? [String: Any])
            #expect(restoreIntegrity["healthy"] as? Bool == true)
        }
    }

    @Test("blessed agent JSON commands have process fixtures")
    func blessedAgentJSONCommandsHaveProcessFixtures() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-blessed-json-fixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let capture = try runCLI(
            args: [
                "capture", "add",
                "--kind", "bookmark",
                "--url", "https://example.com/blessed-json-fixture-\(UUID().uuidString)",
                "--title", "Blessed JSON Fixture",
                "--no-wait",
                "--json",
            ],
            vault: vault
        )
        let capturePayload = try assertStrictProcessJSON(capture, command: "capture.add")
        let bookmark = try #require(capturePayload["bookmark"] as? [String: Any])
        let bookmarkID = try #require(bookmark["id"] as? String)

        let journalCapture = try runCLI(
            args: [
                "capture", "add",
                "--kind", "journal",
                "--date", "today",
                "--time", "08:30",
                "--content", "Blessed journal fixture",
                "--json",
            ],
            vault: vault
        )
        let journalPayload = try assertStrictProcessJSON(journalCapture, command: "capture.add")
        #expect(journalPayload["kind"] as? String == "journal")
        #expect(journalPayload["nextSafeAction"] as? String == "inspect_item")

        let boardCreate = try runCLI(args: ["board", "create", "Fixture Board", "--json"], vault: vault)
        let boardPayload = try assertStrictProcessJSON(boardCreate, command: "board.create")
        let board = try #require(boardPayload["board"] as? [String: Any])
        let boardID = try #require(board["id"] as? String)

        let commands: [([String], String)] = [
            (["item", "get", "bookmark", bookmarkID, "--json"], "item.get"),
            (["item", "graph-health", "--json"], "item.graph-health"),
            (["item", "dogfood-intelligence", "--limit", "1", "--json"], "item.dogfood-intelligence"),
            (["review", "list", "--json"], "review.list"),
            (["storage", "audit", "--json"], "storage.audit"),
            (["db", "integrity", "--json"], "db.integrity"),
            (["board", "list", "--json"], "board.list"),
            (["board", "show", boardID, "--json"], "board.show"),
            (["media", "identify", "--dry-run", "--json"], "media.identify"),
        ]

        for (args, expectedCommand) in commands {
            let result = try runCLI(args: args, vault: vault)
            _ = try assertStrictProcessJSON(result, command: expectedCommand)
        }
    }

    @Test("project context summary bounds relation-heavy output")
    func projectContextSummaryBoundsRelationHeavyOutput() throws {
        let projectOwner = SecondBrainOwnerRef(ownerType: "project", ownerID: "cider")
        let cardOwners = (0..<5).map {
            SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "2afee0/card-\($0)")
        }
        let relations = cardOwners.map {
            SecondBrainRelation(
                sourceOwner: projectOwner,
                targetOwner: $0,
                relationType: "has_card",
                evidence: "Project includes \($0.ownerID).",
                source: "test",
                actor: "codex",
                confidence: 1
            )
        }
        let context = SecondBrainProjectContext(
            project: SecondBrainProject(id: "cider", title: "Cider", subtitle: "", status: "active"),
            owner: projectOwner,
            sections: [],
            outgoingRelations: relations,
            backlinks: [],
            artifactRelations: [],
            artifactOwners: [],
            boardOwners: [SecondBrainOwnerRef(ownerType: "kanban_board", ownerID: "2afee0")],
            cardOwners: cardOwners,
            safeCommands: ["cider-cli item project-context cider --json"]
        )

        let full = CiderCLI.projectContextToDict(context, command: "item.project-context", sourceRef: "cider")
        #expect((full["cardOwners"] as? [[String: Any]])?.count == 5)

        let summary = CiderCLI.projectContextToDict(
            context,
            command: "item.project-context",
            sourceRef: "cider",
            limits: .summary(maxSamples: 2)
        )
        let counts = try #require(summary["counts"] as? [String: Any])
        let truncation = try #require(summary["truncation"] as? [String: Any])
        let safeCommands = try #require(summary["safeCommands"] as? [String])

        #expect(summary["mode"] as? String == "summary")
        #expect(counts["cardOwners"] as? Int == 5)
        #expect((summary["cardOwners"] as? [[String: Any]])?.count == 2)
        #expect(truncation["cardOwners"] as? Bool == true)
        #expect(safeCommands.contains("cider-cli item project-context cider --full --json"))
    }

    @Test("reminder mutation ID resolution rejects ambiguous prefixes")
    func reminderMutationIDResolutionRejectsAmbiguousPrefixes() throws {
        let first = UUID(uuidString: "aaaaaaaa-1111-1111-1111-111111111111")!
        let second = UUID(uuidString: "aaaaaaaa-2222-2222-2222-222222222222")!

        let result = CiderCLI.resolveUniqueReminderID(
            prefix: "aaaaaaaa",
            candidates: [
                CiderCLI.CiderReminderIDCandidate(id: first, title: "First"),
                CiderCLI.CiderReminderIDCandidate(id: second, title: "Second"),
            ]
        )

        guard case .ambiguous(let matches) = result else {
            Issue.record("Expected ambiguous result, got \(result)")
            return
        }
        #expect(matches.map(\.id) == [first, second])
    }

    private func parseJSONObject(_ output: String) throws -> [String: Any] {
        let json = output.drop { $0 != "{" }
        let data = Data(json.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    private func parseJSONArray(_ output: String) throws -> [[String: Any]] {
        let json = output.drop { $0 != "[" }
        let data = Data(json.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [[String: Any]])
    }

    private func assertStrictProcessJSON(
        _ result: (stdout: String, stderr: String, status: Int32),
        command: String
    ) throws -> [String: Any] {
        #expect(result.status == 0, "Expected \(command) to exit 0; stderr: \(result.stderr)")
        #expect(result.stdout.first == "{", "Expected \(command) JSON to start at byte 0")
        let payload = try parseJSONObject(result.stdout)
        #expect(payload["command"] as? String == command)
        #expect(payload["legacyRemoved"] == nil)
        return payload
    }

    private func createNote(title: String, content: String, vault: URL) throws -> String {
        let result = try runCLI(
            args: ["note", "create", title, "--content", content, "--json"],
            vault: vault
        )
        let payload = try parseJSONObject(result.stdout)
        return try #require(payload["id"] as? String)
    }

    private func insertFolderRow(relativePath: String, vault: URL) throws {
        let db = CiderDatabase()
        try db.open(at: vault.appendingPathComponent(".cider/cider.db"))
        defer { db.close() }

        let folderID = UUID().uuidString
        let timestamp = Date().timeIntervalSince1970
        let stmt = try db.prepare("""
            INSERT INTO folders (id, relative_path, created_at, updated_at)
            VALUES (?, ?, ?, ?);
            """)
        stmt.bind(folderID, at: 1)
            .bind(relativePath, at: 2)
            .bind(timestamp, at: 3)
            .bind(timestamp, at: 4)
        try stmt.step()
    }

    private func runCLI(args: [String], stdin: String? = nil) throws -> (stdout: String, stderr: String, status: Int32) {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-agent-safety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        return try runCLI(args: args, vault: vault, stdin: stdin)
    }

    private func runCLI(args: [String], vault: URL, stdin: String? = nil) throws -> (stdout: String, stderr: String, status: Int32) {
        let cli = try cliURL()
        let process = Process()
        process.executableURL = cli
        process.arguments = ["--vault", vault.path] + args

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        if let stdin {
            let input = Pipe()
            process.standardInput = input
            try process.run()
            input.fileHandleForWriting.write(Data(stdin.utf8))
            try input.fileHandleForWriting.close()
        } else {
            try process.run()
        }
        process.waitUntilExit()

        return (
            String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            process.terminationStatus
        )
    }

    private func runCLIConcurrently(
        specs: [(label: String, expectedType: String, args: [String], stdin: String)],
        vault: URL
    ) throws -> [(label: String, expectedType: String, stdout: String, stderr: String, status: Int32)] {
        let cli = try cliURL()
        var running: [(
            label: String,
            expectedType: String,
            process: Process,
            stdout: Pipe,
            stderr: Pipe,
            input: Pipe,
            stdin: String
        )] = []

        for spec in specs {
            let process = Process()
            process.executableURL = cli
            process.arguments = ["--vault", vault.path] + spec.args

            let stdout = Pipe()
            let stderr = Pipe()
            let input = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = input
            try process.run()
            running.append((spec.label, spec.expectedType, process, stdout, stderr, input, spec.stdin))
        }

        for item in running {
            item.input.fileHandleForWriting.write(Data(item.stdin.utf8))
            try item.input.fileHandleForWriting.close()
        }

        return running.map { item in
            item.process.waitUntilExit()
            return (
                label: item.label,
                expectedType: item.expectedType,
                stdout: String(data: item.stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                stderr: String(data: item.stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                status: item.process.terminationStatus
            )
        }
    }

    private func cliURL() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidates = [
            root.appendingPathComponent(".build/arm64-apple-macosx/debug/cider-cli"),
            root.appendingPathComponent(".build/debug/cider-cli"),
        ]
        if let url = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return url
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
