import Foundation
import Testing
@testable import Cider
@testable import CiderCLI

@Suite("Cider CLI Agent Safety Tests")
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
        let quality = try #require(payload["captureQuality"] as? [String: Any])
        let reasons = try #require(quality["degradedReasons"] as? [String])

        #expect(quality["semanticStatus"] as? String == "pending")
        #expect(quality["metadataComplete"] as? Bool == false)
        #expect(quality["cardComplete"] as? Bool == false)
        #expect(quality["titleQuality"] as? String == "generic")
        #expect(quality["thumbnailStatus"] as? String == "missing")
        #expect(quality["visibleCardCurrent"] as? Bool == false)
        #expect(reasons.contains("metadata_pending"))
        #expect(reasons.contains("title_generic"))
        #expect(reasons.contains("card_image_missing"))
    }

    @Test("capture add json rejects missing source")
    func captureAddJSONRejectsMissingSource() throws {
        let result = try runCLI(args: ["capture", "add", "--json"])

        let dict = try parseJSONObject(result.stdout)
        #expect(result.status != 0)
        #expect(dict["ok"] as? Bool == false)
        #expect((dict["error"] as? String)?.contains("Usage: cider-cli capture add") == true)
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
            "ITEM",
            "REVIEW",
            "ROUTE",
            "STORAGE",
            "MIGRATE",
            "DOCTOR",
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

    private func runCLI(args: [String]) throws -> (stdout: String, stderr: String, status: Int32) {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-agent-safety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        return try runCLI(args: args, vault: vault)
    }

    private func runCLI(args: [String], vault: URL) throws -> (stdout: String, stderr: String, status: Int32) {
        let cli = try cliURL()
        let process = Process()
        process.executableURL = cli
        process.arguments = ["--vault", vault.path] + args

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        return (
            String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            process.terminationStatus
        )
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
