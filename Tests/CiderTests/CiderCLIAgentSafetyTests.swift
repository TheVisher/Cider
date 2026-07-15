import CryptoKit
import Foundation
import Testing
@testable import Cider
@testable import CiderCLI

private final class CLIOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = Data()

    func set(_ data: Data) {
        lock.lock()
        stored = data
        lock.unlock()
    }

    func data() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

@Suite("Cider CLI Agent Safety Tests", .serialized)
@MainActor
struct CiderCLIAgentSafetyTests {
    @Test("populated filtered review list JSON declares read-only unchanged contract")
    func populatedFilteredReviewListJSONDeclaresReadOnlyUnchangedContract() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-review-list-contract-populated-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let captureResult = try runCLI(
            args: [
                "capture", "add",
                "--kind", "todo",
                "--content", "Verify the review list JSON contract",
                "--title", "Review list contract fixture",
                "--json",
            ],
            vault: vault
        )
        let capture = try parseJSONObject(captureResult.stdout)
        let safeNextCommands = try #require(capture["safeNextCommands"] as? [String])
        #expect(safeNextCommands.contains("cider-cli review list --item-type todo --state needs_review --limit 10 --json"))

        let result = try runCLI(
            args: [
                "review", "list",
                "--item-type", "todo",
                "--state", "needs_review",
                "--limit", "10",
                "--json",
            ],
            vault: vault
        )
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status == 0)
        #expect(payload["command"] as? String == "review.list")
        #expect((payload["count"] as? Int ?? 0) > 0)
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        let filters = try #require(payload["filters"] as? [String: Any])
        #expect(filters["itemType"] as? String == "todo")
        #expect(filters["state"] as? String == "needs_review")
        #expect(filters["limit"] as? Int == 10)
    }

    @Test("empty filtered review list JSON declares read-only unchanged contract")
    func emptyFilteredReviewListJSONDeclaresReadOnlyUnchangedContract() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-review-list-contract-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let result = try runCLI(
            args: [
                "review", "list",
                "--item-type", "contact",
                "--state", "needs_review",
                "--limit", "10",
                "--json",
            ],
            vault: vault
        )
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status == 0)
        #expect(payload["command"] as? String == "review.list")
        #expect(payload["count"] as? Int == 0)
        #expect((payload["items"] as? [[String: Any]])?.isEmpty == true)
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        let filters = try #require(payload["filters"] as? [String: Any])
        #expect(filters["itemType"] as? String == "contact")
        #expect(filters["state"] as? String == "needs_review")
        #expect(filters["limit"] as? Int == 10)
    }

    @Test("populated review summary JSON declares read-only unchanged contract")
    func populatedReviewSummaryJSONDeclaresReadOnlyUnchangedContract() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-review-summary-contract-populated-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let captureResult = try runCLI(
            args: [
                "capture", "add",
                "--kind", "todo",
                "--content", "Verify the review summary JSON contract",
                "--title", "Review summary contract fixture",
                "--json",
            ],
            vault: vault
        )
        let capture = try parseJSONObject(captureResult.stdout)
        #expect(captureResult.status == 0)
        #expect(capture["command"] as? String == "capture.add")

        let result = try runCLI(
            args: ["review", "summary", "--json"],
            vault: vault
        )
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status == 0)
        #expect(payload["command"] as? String == "review.summary")
        #expect((payload["totalCount"] as? Int ?? 0) > 0)
        #expect((payload["groups"] as? [[String: Any]])?.isEmpty == false)
        #expect(payload["batchEnrichmentPreview"] as? [String: Any] != nil)
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
    }

    @Test("empty review summary JSON declares read-only unchanged contract")
    func emptyReviewSummaryJSONDeclaresReadOnlyUnchangedContract() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-review-summary-contract-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let result = try runCLI(
            args: ["review", "summary", "--json"],
            vault: vault
        )
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status == 0)
        #expect(payload["command"] as? String == "review.summary")
        #expect(payload["totalCount"] as? Int == 0)
        #expect((payload["groups"] as? [[String: Any]])?.isEmpty == true)
        #expect(payload["batchEnrichmentPreview"] as? [String: Any] != nil)
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
    }

    @Test("review summary help is command-specific and exits before vault access")
    func reviewSummaryHelpIsCommandSpecificAndExitsBeforeVaultAccess() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-review-summary-help-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let result = try runCLI(args: ["review", "summary", "--help"], vault: vault)

        #expect(result.status == 0)
        #expect(result.stdout.contains("Usage: cider-cli review summary"))
        #expect(result.stdout.contains("--include-deferred"))
        #expect(result.stdout.contains("Read-only"))
        #expect(FileManager.default.fileExists(atPath: vault.path) == false)
        #expect(FileManager.default.fileExists(atPath: vault.appendingPathComponent(".cider").path) == false)
    }

    @Test("review list help is command-specific and exits before vault access")
    func reviewListHelpIsCommandSpecificAndExitsBeforeVaultAccess() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-review-list-help-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let result = try runCLI(args: ["review", "list", "--help"], vault: vault)

        #expect(result.status == 0)
        #expect(result.stdout.contains("Usage: cider-cli review list"))
        #expect(result.stdout.contains("--item-type <type>"))
        #expect(result.stdout.contains("--state <state>"))
        #expect(FileManager.default.fileExists(atPath: vault.path) == false)
        #expect(FileManager.default.fileExists(atPath: vault.appendingPathComponent(".cider").path) == false)
    }

    @Test("capture review queue help is command-specific and exits before vault access")
    func captureReviewQueueHelpIsCommandSpecificAndExitsBeforeVaultAccess() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-capture-review-queue-help-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let result = try runCLI(args: ["capture", "review-queue", "--help"], vault: vault)

        #expect(result.status == 0)
        #expect(result.stdout.contains("Usage: cider-cli capture review-queue"))
        #expect(result.stdout.contains("--limit <n>"))
        #expect(result.stdout.contains("--json"))
        #expect(result.stdout.contains("Read-only"))
        #expect(!result.stdout.contains("Capture review queue:"))
        #expect(FileManager.default.fileExists(atPath: vault.path) == false)
        #expect(FileManager.default.fileExists(atPath: vault.appendingPathComponent(".cider").path) == false)
    }

    @Test("capture provenance diagnostic help is read only and machine actionable")
    func captureProvenanceDiagnosticHelpIsReadOnly() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-capture-provenance-help-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let result = try runCLI(
            args: ["capture", "provenance-gaps", "--help", "--json"],
            vault: vault
        )
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status == 0)
        #expect(payload["command"] as? String == "capture.provenance-gaps.help")
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["truthBoundary"] as? String == "help_contract_only_not_vault_truth")
        #expect((payload["safeVerificationCommands"] as? [String]) == ["cider-cli capture provenance-gaps --help --json"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: vault.path).isEmpty)
    }

    @Test("capture provenance gap drilldown help is read only and machine actionable")
    func captureProvenanceGapDrilldownHelpIsReadOnly() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-capture-provenance-gap-help-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let result = try runCLI(
            args: ["capture", "provenance-gap", "--help", "--json"],
            vault: vault
        )
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status == 0)
        #expect(payload["command"] as? String == "capture.provenance-gap.help")
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["truthBoundary"] as? String == "help_contract_only_not_vault_truth")
        #expect((payload["safeVerificationCommands"] as? [String]) == ["cider-cli capture provenance-gap --help --json"])
        #expect((payload["usage"] as? String)?.contains("--duplicate-audit-limit <1-500>") == true)
        #expect((payload["usage"] as? String)?.contains("--duplicate-audit-cursor <token>") == true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: vault.path).isEmpty)
    }

    @Test("capture provenance gap aggregate help is read only and machine actionable")
    func captureProvenanceGapAggregateHelpIsReadOnly() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-capture-provenance-gap-patterns-help-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let result = try runCLI(
            args: ["capture", "provenance-gap-patterns", "--help", "--json"],
            vault: vault
        )
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status == 0)
        #expect(payload["command"] as? String == "capture.provenance-gap-patterns.help")
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["truthBoundary"] as? String == "help_contract_only_not_vault_truth")
        #expect((payload["safeVerificationCommands"] as? [String]) == ["cider-cli capture provenance-gap-patterns --help --json"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: vault.path).isEmpty)
    }

    @Test("item early and full plain help use the same canonical text")
    func itemEarlyAndFullPlainHelpUseSameCanonicalText() throws {
        let earlyHelp = try captureStandardOutput {
            CiderCLI.printItemEarlyHelp()
        }
        let fullHelp = try captureStandardOutput {
            CiderCLI.handleItem(subcommand: nil, args: [])
        }

        #expect(earlyHelp == fullHelp)
    }

    @Test("dev fixture creates graph candidate smoke data through CLI review path")
    func devFixtureCreatesGraphCandidateSmokeDataThroughCLIReviewPath() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-dev-fixture-graph-candidate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let blockedResult = try runCLI(args: [
            "dev-fixture", "graph-candidate-smoke",
            "--label", "After Yang",
            "--json",
        ], vault: vault)
        let blocked = try parseJSONObject(blockedResult.stdout)
        #expect(blocked["ok"] as? Bool == false)
        #expect(blocked["errorCode"] as? String == "fixture_requires_explicit_temp_vault_allowance")

        let fixtureResult = try runCLI(args: [
            "dev-fixture", "graph-candidate-smoke",
            "--allow-temp-vault-fixture",
            "--label", "After Yang",
            "--owner-id", "cid634-after-yang",
            "--external-id", "tmdb=585378",
            "--json",
        ], vault: vault)
        let fixture = try parseJSONObject(fixtureResult.stdout)
        #expect(fixtureResult.status == 0)
        #expect(fixture["ok"] as? Bool == true)
        #expect(fixture["command"] as? String == "dev-fixture.graph-candidate-smoke")
        #expect(fixture["changed"] as? Bool == true)
        #expect(fixture["fixtureSafety"] as? [String] == [
            "temp_vault_only",
            "reviewable_candidate_not_truth",
            "accept_requires_explicit_target_option",
        ])

        let sourceItem = try #require(fixture["sourceItem"] as? [String: Any])
        let projectedOwner = try #require(fixture["projectedOwner"] as? [String: Any])
        let candidate = try #require(fixture["candidate"] as? [String: Any])
        #expect(sourceItem["type"] as? String == "note")
        #expect(projectedOwner["ref"] as? String == "media_item:cid634-after-yang")
        #expect(candidate["truthState"] as? String == "reviewable_candidate_not_truth")
        let candidateID = try #require(candidate["id"] as? String)

        let reviewList = try parseJSONObject(try runCLI(args: [
            "review", "list",
            "--kind", "graph_candidate",
            "--limit", "5",
            "--json",
        ], vault: vault).stdout)
        #expect(reviewList["command"] as? String == "review.list")
        let items = try #require(reviewList["items"] as? [[String: Any]])
        let reviewItem = try #require(items.first { $0["candidateID"] as? String == candidateID })
        let targetOptions = try #require(reviewItem["targetOptions"] as? [[String: Any]])
        let existing = try #require(targetOptions.first)
        let optionRef = try #require(existing["optionRef"] as? String)
        #expect(optionRef == "graph_target_option:\(candidateID):existing-1")
        #expect((existing["targetOwner"] as? [String: String])?["ref"] == "media_item:cid634-after-yang")
        #expect(existing["truthState"] as? String == "reviewable_candidate_not_truth")
        #expect((existing["externalIDs"] as? [String: String])?["tmdb"] == "585378")
        #expect((existing["sourceRefs"] as? [String])?.contains("media_item:cid634-after-yang") == true)
        #expect((existing["provenanceRefs"] as? [String])?.contains("source_evidence:dev-fixture-cid634-after-yang") == true)

        let approved = try parseJSONObject(try runCLI(args: [
            "review", "approve", candidateID,
            "--target-option", optionRef,
            "--actor", "codex",
            "--json",
        ], vault: vault).stdout)
        #expect(approved["changed"] as? Bool == true)
        #expect(approved["truthBoundary"] as? String == "accepted_graph_truth")
        let receipt = try #require(approved["actionReceipt"] as? [String: Any])
        #expect(receipt["truthBoundary"] as? String == "accepted_graph_truth")
        let provenance = try #require(approved["provenance"] as? [String: Any])
        #expect(provenance["sourceRef"] as? String == "note:\(sourceItem["id"] as? String ?? "")")
        #expect(provenance["targetOwnerRef"] as? String == "media_item:cid634-after-yang")
    }

    @Test("item help advertises recall action diagnostic facts commands without vault side effects")
    func itemHelpAdvertisesRecallActionDiagnosticFactsCommandsWithoutVaultSideEffects() throws {
        let commandsAndExpectedStrings: [([String], [String])] = [
            (["item", "--help"], [
                "cider-cli item recall-context (--item <type> <id-or-ref>|--query <topic>)",
                "cider-cli item action-ledger list",
                "cider-cli item action-ledger inspect <receipt-id> [--json]",
                "cider-cli item due-to-surface",
                "cider-cli item why-surfaced <type> <id-or-ref> [--json]",
                "cider-cli item capability-map [--json]",
                "cider-cli item graph-health [--json]",
                "cider-cli item memory-facts list [--limit <n>] [--json]",
                "cider-cli item memory-facts inspect <candidate-id|accepted_memory_fact:id|memory_candidate:id> [--json]",
            ]),
            (["item", "recall-context", "--help"], [
                "cider-cli item recall-context (--item <type> <id-or-ref>|--query <topic>)",
                "--history-command <command>",
                "--history-status <status>",
                "--history-source-ref <ref>",
                "--history-evidence-ref <ref>",
                "--history-limit <n>",
                "Read-only source-backed recall bundle",
            ]),
            (["item", "action-ledger", "--help"], [
                "cider-cli item action-ledger list",
                "cider-cli item action-ledger recap",
                "--owner <type:id>",
                "--command-prefix <prefix>",
                "--command <command>",
                "--source-ref <ref>",
                "--evidence-ref <ref>",
                "cider-cli item action-ledger inspect <receipt-id> [--json]",
                "Read-only durable action receipt history",
            ]),
            (["item", "action-ledger", "list", "--help"], [
                "cider-cli item action-ledger list",
                "--owner-type <type> --owner-id <id>",
                "--since <iso|yyyy-mm-dd>",
                "--before <iso|yyyy-mm-dd>",
                "--limit <n>",
            ]),
            (["item", "action-ledger", "recap", "--help"], [
                "cider-cli item action-ledger recap",
                "--family <command-family>",
                "--command-prefix <prefix>",
                "--action-prefix <prefix>",
                "--source-ref <ref>",
                "Read-only grouped recent action receipt recap",
            ]),
            (["item", "action-ledger", "inspect", "--help"], [
                "cider-cli item action-ledger inspect <receipt-id> [--json]",
                "Read-only inspection of one durable action receipt",
            ]),
            (["item", "capability-map", "--help"], [
                "cider-cli item capability-map [--json]",
                "Read-only static capability contract",
                "cider-cli item graph-health [--json]",
            ]),
            (["item", "graph-health", "--help"], [
                "cider-cli item graph-health [--json]",
                "Read-only graph readiness diagnostic",
                "cider-cli item capability-map [--json]",
            ]),
            (["item", "memory-facts", "--help"], [
                "cider-cli item memory-facts list [--limit <n>] [--json]",
                "cider-cli item memory-facts inspect <candidate-id|accepted_memory_fact:id|memory_candidate:id> [--json]",
                "cider-cli item memory-facts resurface [--fact <candidate-id>] [--limit <n>] [--json]",
                "Read-only accepted memory fact commands",
            ]),
        ]

        for (args, expectedStrings) in commandsAndExpectedStrings {
            let vault = FileManager.default.temporaryDirectory
                .appendingPathComponent("cider-item-help-no-side-effects-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: vault) }

            let result = try runCLI(args: args, vault: vault)

            #expect(result.status == 0)
            for expectedString in expectedStrings {
                #expect(result.stdout.contains(expectedString), "Expected help for \(args.joined(separator: " ")) to contain \(expectedString)")
            }
            let vaultContents = try FileManager.default.contentsOfDirectory(atPath: vault.path)
            #expect(vaultContents.isEmpty, "Help command \(args.joined(separator: " ")) should not create vault data")
        }
    }

    @Test("recall help json exposes machine readable read only contracts")
    func recallHelpJSONExposesMachineReadableReadOnlyContracts() throws {
        let cases: [(args: [String], command: String, subcommand: String, aliasOf: String?, usage: String)] = [
            (
                ["item", "preference-recall", "--help", "--json"],
                "item.preference-recall.help",
                "preference-recall",
                nil,
                "cider-cli item preference-recall <natural question>|--query <natural question> [--limit <n>] [--json]"
            ),
            (
                ["item", "recall-context", "--help", "--json"],
                "item.recall-context.help",
                "recall-context",
                nil,
                "cider-cli item recall-context (--item <type> <id-or-ref>|--query <topic>) [--query <topic>] [--limit <n>] [--history-command <command>] [--history-status <status>] [--history-source-ref <ref>] [--history-evidence-ref <ref>] [--history-since <iso|yyyy-mm-dd>] [--history-before <iso|yyyy-mm-dd>] [--history-limit <n>] [--json]"
            ),
            (
                ["item", "natural-recall", "--help", "--json"],
                "item.natural-recall.help",
                "natural-recall",
                "item.preference-recall",
                "cider-cli item natural-recall <natural question>|--query <natural question> [--limit <n>] [--json]"
            ),
            (
                ["item", "context-bundle", "--help", "--json"],
                "item.context-bundle.help",
                "context-bundle",
                "item.recall-context",
                "cider-cli item context-bundle (--item <type> <id-or-ref>|--query <topic>) [--query <topic>] [--limit <n>] [--history-command <command>] [--history-status <status>] [--history-source-ref <ref>] [--history-evidence-ref <ref>] [--history-since <iso|yyyy-mm-dd>] [--history-before <iso|yyyy-mm-dd>] [--history-limit <n>] [--json]"
            ),
            (
                ["item", "recall-bundle", "--help", "--json"],
                "item.recall-bundle.help",
                "recall-bundle",
                "item.recall-context",
                "cider-cli item recall-bundle (--item <type> <id-or-ref>|--query <topic>) [--query <topic>] [--limit <n>] [--history-command <command>] [--history-status <status>] [--history-source-ref <ref>] [--history-evidence-ref <ref>] [--history-since <iso|yyyy-mm-dd>] [--history-before <iso|yyyy-mm-dd>] [--history-limit <n>] [--json]"
            ),
        ]

        for testCase in cases {
            let vault = FileManager.default.temporaryDirectory
                .appendingPathComponent("cider-recall-help-json-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: vault) }

            let result = try runCLI(args: testCase.args, vault: vault)
            #expect(result.status == 0)
            #expect(result.stdout.first == "{")

            let payload = try parseJSONObject(result.stdout)
            #expect(payload["ok"] as? Bool == true)
            #expect(payload["status"] as? String == "ok")
            #expect(payload["readOnly"] as? Bool == true)
            #expect(payload["changed"] as? Bool == false)
            #expect(payload["command"] as? String == testCase.command)
            #expect(payload["subcommand"] as? String == testCase.subcommand)
            if let aliasOf = testCase.aliasOf {
                #expect(payload["aliasOf"] as? String == aliasOf)
            } else {
                #expect(payload["aliasOf"] == nil)
            }
            #expect(payload["usage"] as? String == testCase.usage)
            #expect((payload["description"] as? String)?.contains("Read-only") == true)
            #expect((payload["options"] as? [[String: Any]])?.isEmpty == false)
            #expect((payload["safeVerificationHints"] as? [String])?.contains(where: { $0.contains("--help --json") }) == true)
            #expect((payload["truthBoundary"] as? String)?.contains("command contract") == true)
            #expect((payload["truthBoundary"] as? String)?.contains("not memory truth") == true)

            let vaultContents = try FileManager.default.contentsOfDirectory(atPath: vault.path)
            #expect(vaultContents.isEmpty, "JSON help command \(testCase.args.joined(separator: " ")) should not create vault data")
        }
    }

    @Test("recall help without json remains plain text usage")
    func recallHelpWithoutJSONRemainsPlainTextUsage() throws {
        let cases: [(args: [String], usage: String)] = [
            (
                ["item", "preference-recall", "--help"],
                "cider-cli item preference-recall <natural question>|--query <natural question> [--limit <n>] [--json]"
            ),
            (
                ["item", "recall-context", "--help"],
                "cider-cli item recall-context (--item <type> <id-or-ref>|--query <topic>)"
            ),
            (
                ["item", "natural-recall", "--help"],
                "cider-cli item preference-recall <natural question>|--query <natural question> [--limit <n>] [--json]"
            ),
            (
                ["item", "context-bundle", "--help"],
                "cider-cli item recall-context (--item <type> <id-or-ref>|--query <topic>)"
            ),
            (
                ["item", "recall-bundle", "--help"],
                "cider-cli item recall-context (--item <type> <id-or-ref>|--query <topic>)"
            ),
        ]

        for testCase in cases {
            let result = try runCLI(args: testCase.args)
            #expect(result.status == 0)
            #expect(result.stdout.contains(testCase.usage))
            #expect(result.stdout.first != "{")
        }
    }

    @Test("recall context query json executes recall instead of help")
    func recallContextQueryJSONExecutesRecallInsteadOfHelp() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-recall-context-query-dispatch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let noteID = try createNote(
            title: "Recall Dispatch Sentinel",
            content: "A source-backed fixture for recall-context query dispatch.",
            vault: vault
        )

        for subcommand in ["recall-context", "context-bundle", "recall-bundle"] {
            let result = try runCLI(
                args: ["item", subcommand, "--query", "Recall Dispatch Sentinel", "--json"],
                vault: vault
            )
            let payload = try parseJSONObject(result.stdout)

            #expect(result.status == 0)
            #expect(payload["command"] as? String == "item.recall-context")
            #expect(payload["command"] as? String != "item.\(subcommand).help")
            #expect(payload["readOnly"] as? Bool == true)
            #expect(payload["changed"] as? Bool == false)
            let anchors = try #require(payload["anchors"] as? [[String: Any]])
            #expect(anchors.contains { (($0["item"] as? [String: Any])?["id"] as? String) == noteID })
        }
    }

    @Test("recall context item json executes recall instead of help")
    func recallContextItemJSONExecutesRecallInsteadOfHelp() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-recall-context-item-dispatch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let noteID = try createNote(
            title: "Recall Item Dispatch Sentinel",
            content: "A source-backed fixture for recall-context item dispatch.",
            vault: vault
        )

        let result = try runCLI(
            args: ["item", "recall-context", "--item", "note", noteID, "--json"],
            vault: vault
        )
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status == 0)
        #expect(payload["command"] as? String == "item.recall-context")
        #expect(payload["command"] as? String != "item.recall-context.help")
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        let anchors = try #require(payload["anchors"] as? [[String: Any]])
        #expect(anchors.contains { (($0["item"] as? [String: Any])?["id"] as? String) == noteID })
    }

    @Test("reminder mutation result exposes shared action receipt")
    func reminderMutationResultExposesSharedActionReceipt() throws {
        let id = UUID()
        let result = CiderReminderActionResult(
            itemType: .todo,
            id: id,
            title: "Pay utilities",
            action: .complete,
            completed: true,
            snoozedUntil: nil,
            surfacing: nil
        )

        let dict = reminderActionResultToDict(result)

        #expect(dict["command"] as? String == "reminder.complete")
        #expect(dict["readOnly"] as? Bool == false)
        #expect(dict["changed"] as? Bool == true)
        let receipt = try #require(dict["actionReceipt"] as? [String: Any])
        #expect(receipt["command"] as? String == "reminder.complete")
        #expect(receipt["action"] as? String == "complete")
        #expect(receipt["actor"] as? String == "cider-cli")
        #expect(receipt["readOnly"] as? Bool == false)
        #expect(receipt["changed"] as? Bool == true)
        let owner = try #require(receipt["owner"] as? [String: Any])
        #expect(owner["ownerType"] as? String == "todo")
        #expect(owner["ownerID"] as? String == id.uuidString)
        #expect((receipt["safeVerificationCommands"] as? [String])?.contains("cider-cli item why-surfaced todo \(id.uuidString) --json") == true)
        #expect((receipt["safeNextCommands"] as? [String])?.contains("cider-cli item due-to-surface --json") == true)
    }

    @Test("link mutation persists action receipt and appears in item context")
    func linkMutationPersistsActionReceiptAndAppearsInItemContext() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-link-action-ledger-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let sourceID = try createNote(title: "Ledger Link Source", content: "Source", vault: vault)
        let targetID = try createNote(title: "Ledger Link Target", content: "Target", vault: vault)

        let link = try parseJSONObject(try runCLI(args: ["item", "link", "note", sourceID, "note", targetID, "--json"], vault: vault).stdout)
        #expect(link["command"] as? String == "link.add")
        #expect(link["readOnly"] as? Bool == false)
        #expect(link["changed"] as? Bool == true)
        let receipt = try #require(link["actionReceipt"] as? [String: Any])
        #expect(receipt["command"] as? String == "link.add")
        #expect(receipt["commandFamily"] as? String == "link")
        #expect(receipt["subcommand"] as? String == "add")
        #expect(receipt["status"] as? String == "succeeded")
        #expect(receipt["resultStatus"] as? String == "succeeded")
        #expect(receipt["timestamp"] as? String != nil)
        #expect(receipt["action"] as? String == "link")
        #expect((receipt["sourceRefs"] as? [String])?.contains("note:\(sourceID)") == true)
        #expect((receipt["evidenceRefs"] as? [String])?.contains("note:\(targetID)") == true)
        #expect((receipt["safeVerificationCommands"] as? [String])?.contains("cider-cli item action-ledger list --owner note:\(sourceID) --json") == true)

        let ledger = try parseJSONObject(try runCLI(args: ["item", "action-ledger", "list", "--owner", "note:\(sourceID)", "--action", "link", "--json"], vault: vault).stdout)
        let entries = try #require(ledger["entries"] as? [[String: Any]])
        #expect(entries.contains { entry in
            entry["command"] as? String == "link.add"
                && entry["commandFamily"] as? String == "link"
                && entry["subcommand"] as? String == "add"
                && entry["status"] as? String == "succeeded"
                && entry["resultStatus"] as? String == "succeeded"
                && entry["timestamp"] as? String != nil
                && entry["changed"] as? Bool == true
                && (entry["evidenceRefs"] as? [String])?.contains("note:\(targetID)") == true
        })

        let context = try parseJSONObject(try runCLI(args: ["item", "context", "note", sourceID, "--max-history", "10", "--json"], vault: vault).stdout)
        let recentHistory = try #require(context["recentHistory"] as? [[String: Any]])
        #expect(recentHistory.contains { entry in
            entry["kind"] as? String == "action_receipt"
                && entry["command"] as? String == "link.add"
                && entry["action"] as? String == "link"
                && entry["changed"] as? Bool == true
        })
    }

    @Test("review defer persists one canonical receipt and keeps missing item failure receipt free")
    func reviewDeferPersistsActionReceiptAndRecordsMissingItemFailure() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-review-defer-action-ledger-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let bookmark = try assertStrictProcessJSON(
            runCLI(args: [
                "bookmark", "add", "https://example.com/review-defer-ledger",
                "--no-wait",
                "--json",
            ], vault: vault),
            command: "bookmark.add"
        )
        let bookmarkID = try #require(bookmark["id"] as? String)

        let deferPayload = try assertStrictProcessJSON(
            runCLI(args: [
                "review", "defer", bookmarkID,
                "--reason", "Need a better folder choice.",
                "--actor", "agent",
                "--json",
            ], vault: vault),
            command: "review.routing.defer"
        )
        #expect(deferPayload["reviewState"] as? String == "deferred")
        #expect(deferPayload["changed"] as? Bool == true)
        let receipt = try #require(deferPayload["actionReceipt"] as? [String: Any])
        #expect(receipt["command"] as? String == "review.routing.defer")
        #expect(receipt["commandFamily"] as? String == "review")
        #expect(receipt["subcommand"] as? String == "defer")
        #expect(receipt["action"] as? String == "defer")
        #expect(receipt["actor"] as? String == "agent")
        #expect(receipt["readOnly"] as? Bool == false)
        #expect(receipt["changed"] as? Bool == true)
        #expect(receipt["status"] as? String == "deferred")
        #expect(receipt["resultStatus"] as? String == "deferred")
        #expect(receipt["timestamp"] as? String != nil)
        #expect(receipt["ownerRef"] as? String == "bookmark:\(bookmarkID)")
        #expect((receipt["sourceRefs"] as? [String])?.contains("bookmark:\(bookmarkID)") == true)
        #expect((receipt["safeVerificationCommands"] as? [String])?.contains("cider-cli item action-ledger list --owner bookmark:\(bookmarkID) --command review.routing.defer --json") == true)
        #expect((receipt["safeCommandRefs"] as? [String])?.contains("cider-cli item context bookmark \(bookmarkID) --max-history 10 --json") == true)
        #expect(receipt["verificationHint"] as? String == "verify_with_safe_commands_and_source_refs")
        #expect(receipt["truthBoundary"] as? String == "receipt_proves_command_execution_and_review_state_outcome_not_memory_truth")

        let ledger = try assertStrictProcessJSON(
            runCLI(args: ["item", "action-ledger", "list", "--owner", "bookmark:\(bookmarkID)", "--command", "review.routing.defer", "--json"], vault: vault),
            command: "item.action-ledger.list"
        )
        let entries = try #require(ledger["entries"] as? [[String: Any]])
        let entry = try #require(entries.first { $0["command"] as? String == "review.routing.defer" })
        #expect(entry["action"] as? String == "defer")
        #expect(entry["status"] as? String == "deferred")
        #expect(entry["resultStatus"] as? String == "deferred")
        #expect(entry["changed"] as? Bool == true)

        let context = try assertStrictProcessJSON(
            runCLI(args: ["item", "context", "bookmark", bookmarkID, "--max-history", "10", "--json"], vault: vault),
            command: "item.context"
        )
        let recentHistory = try #require(context["recentHistory"] as? [[String: Any]])
        #expect(recentHistory.contains { history in
            history["kind"] as? String == "action_receipt"
                && history["command"] as? String == "review.routing.defer"
                && history["action"] as? String == "defer"
                && history["changed"] as? Bool == true
        })

        let missing = try assertStrictFailureJSON(
            runCLI(args: ["review", "defer", "missing-review-item", "--actor", "agent", "--json"], vault: vault),
            command: "review.routing.defer",
            errorCode: "item_not_found"
        )
        #expect(missing["actionReceipt"] == nil)

        let failedLedger = try assertStrictProcessJSON(
            runCLI(args: ["item", "action-ledger", "list", "--command", "review.routing.defer", "--status", "failed", "--json"], vault: vault),
            command: "item.action-ledger.list"
        )
        let failedEntries = try #require(failedLedger["entries"] as? [[String: Any]])
        #expect(failedEntries.isEmpty)
    }

    @Test("review approve persists one canonical receipt and keeps missing item failure receipt free")
    func reviewApprovePersistsActionReceiptAndRecordsMissingItemFailure() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-review-approve-action-ledger-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let bookmark = try assertStrictProcessJSON(
            runCLI(args: [
                "bookmark", "add", "https://example.com/review-approve-ledger",
                "--no-wait",
                "--json",
            ], vault: vault),
            command: "bookmark.add"
        )
        let bookmarkID = try #require(bookmark["id"] as? String)

        let approvePayload = try assertStrictProcessJSON(
            runCLI(args: [
                "review", "approve", bookmarkID,
                "--actor", "agent",
                "--json",
            ], vault: vault),
            command: "review.routing.approve"
        )
        #expect(approvePayload["reviewState"] as? String == "accepted")
        #expect(approvePayload["changed"] as? Bool == true)
        let receipt = try #require(approvePayload["actionReceipt"] as? [String: Any])
        #expect(receipt["command"] as? String == "review.routing.approve")
        #expect(receipt["commandFamily"] as? String == "review")
        #expect(receipt["subcommand"] as? String == "approve")
        #expect(receipt["action"] as? String == "approve")
        #expect(receipt["actor"] as? String == "agent")
        #expect(receipt["readOnly"] as? Bool == false)
        #expect(receipt["changed"] as? Bool == true)
        #expect(receipt["status"] as? String == "accepted")
        #expect(receipt["resultStatus"] as? String == "accepted")
        #expect(receipt["timestamp"] as? String != nil)
        #expect(receipt["ownerRef"] as? String == "bookmark:\(bookmarkID)")
        #expect((receipt["sourceRefs"] as? [String])?.contains("bookmark:\(bookmarkID)") == true)
        #expect((receipt["evidenceRefs"] as? [String])?.contains("bookmark:\(bookmarkID)") == true)
        #expect((receipt["safeVerificationCommands"] as? [String])?.contains("cider-cli item action-ledger list --owner bookmark:\(bookmarkID) --command review.routing.approve --json") == true)
        #expect((receipt["safeCommandRefs"] as? [String])?.contains("cider-cli item context bookmark \(bookmarkID) --max-history 10 --json") == true)
        #expect(receipt["verificationHint"] as? String == "verify_with_safe_commands_and_source_refs")
        #expect(receipt["truthBoundary"] as? String == "receipt_proves_command_execution_and_review_state_outcome_not_memory_truth")

        let ledger = try assertStrictProcessJSON(
            runCLI(args: ["item", "action-ledger", "list", "--owner", "bookmark:\(bookmarkID)", "--command", "review.routing.approve", "--json"], vault: vault),
            command: "item.action-ledger.list"
        )
        let entries = try #require(ledger["entries"] as? [[String: Any]])
        let entry = try #require(entries.first { $0["command"] as? String == "review.routing.approve" })
        let entryID = try #require(entry["id"] as? String)
        #expect(entry["action"] as? String == "approve")
        #expect(entry["status"] as? String == "accepted")
        #expect(entry["resultStatus"] as? String == "accepted")
        #expect(entry["changed"] as? Bool == true)

        let inspected = try assertStrictProcessJSON(
            runCLI(args: ["item", "action-ledger", "inspect", entryID, "--json"], vault: vault),
            command: "item.action-ledger.inspect"
        )
        let inspectedEntry = try #require(inspected["entry"] as? [String: Any])
        #expect(inspectedEntry["command"] as? String == "review.routing.approve")
        #expect(inspectedEntry["ownerRef"] as? String == "bookmark:\(bookmarkID)")

        let context = try assertStrictProcessJSON(
            runCLI(args: ["item", "context", "bookmark", bookmarkID, "--max-history", "10", "--json"], vault: vault),
            command: "item.context"
        )
        let recentHistory = try #require(context["recentHistory"] as? [[String: Any]])
        #expect(recentHistory.contains { history in
            history["kind"] as? String == "action_receipt"
                && history["command"] as? String == "review.routing.approve"
                && history["action"] as? String == "approve"
                && history["changed"] as? Bool == true
        })

        let missing = try assertStrictFailureJSON(
            runCLI(args: ["review", "approve", "missing-review-item", "--actor", "agent", "--json"], vault: vault),
            command: "review.routing.approve",
            errorCode: "item_not_found"
        )
        #expect(missing["actionReceipt"] == nil)

        let failedLedger = try assertStrictProcessJSON(
            runCLI(args: ["item", "action-ledger", "list", "--command", "review.routing.approve", "--status", "failed", "--json"], vault: vault),
            command: "item.action-ledger.list"
        )
        let failedEntries = try #require(failedLedger["entries"] as? [[String: Any]])
        #expect(failedEntries.isEmpty)
    }

    @Test("review correct persists one canonical receipt and keeps missing item failure receipt free")
    func reviewCorrectPersistsActionReceiptAndRecordsMissingItemFailure() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-review-correct-action-ledger-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let bookmark = try assertStrictProcessJSON(
            runCLI(args: [
                "bookmark", "add", "https://example.com/review-correct-ledger",
                "--no-wait",
                "--json",
            ], vault: vault),
            command: "bookmark.add"
        )
        let bookmarkID = try #require(bookmark["id"] as? String)
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent("Research"),
            withIntermediateDirectories: true
        )
        let folderDatabase = CiderDatabase()
        try folderDatabase.open(at: vault.appendingPathComponent(".cider/cider.db"))
        let folder = try folderDatabase.prepare("""
            INSERT INTO folders (id, relative_path, created_at, updated_at)
            VALUES (?, 'Research', ?, ?);
            """)
        let folderTimestamp = Date()
        folder.bind(UUID().uuidString, at: 1)
            .bind(DatabaseHelpers.encode(folderTimestamp), at: 2)
            .bind(DatabaseHelpers.encode(folderTimestamp), at: 3)
        try folder.step()
        folderDatabase.close()

        let correctPayload = try assertStrictProcessJSON(
            runCLI(args: [
                "review", "correct", bookmarkID,
                "--path", "Research",
                "--reason", "Correct folder from review queue.",
                "--actor", "agent",
                "--json",
            ], vault: vault),
            command: "review.routing.correct"
        )
        #expect(correctPayload["reviewState"] as? String == "corrected")
        #expect(correctPayload["changed"] as? Bool == true)
        let receipt = try #require(correctPayload["actionReceipt"] as? [String: Any])
        #expect(receipt["command"] as? String == "review.routing.correct")
        #expect(receipt["commandFamily"] as? String == "review")
        #expect(receipt["subcommand"] as? String == "correct")
        #expect(receipt["action"] as? String == "correct")
        #expect(receipt["actor"] as? String == "agent")
        #expect(receipt["readOnly"] as? Bool == false)
        #expect(receipt["changed"] as? Bool == true)
        #expect(receipt["status"] as? String == "corrected")
        #expect(receipt["resultStatus"] as? String == "corrected")
        #expect(receipt["timestamp"] as? String != nil)
        #expect(receipt["ownerRef"] as? String == "bookmark:\(bookmarkID)")
        #expect((receipt["sourceRefs"] as? [String])?.contains("bookmark:\(bookmarkID)") == true)
        #expect((receipt["evidenceRefs"] as? [String])?.contains("bookmark:\(bookmarkID)") == true)
        #expect((receipt["safeVerificationCommands"] as? [String])?.contains("cider-cli item action-ledger list --owner bookmark:\(bookmarkID) --command review.routing.correct --json") == true)
        #expect((receipt["safeCommandRefs"] as? [String])?.contains("cider-cli item context bookmark \(bookmarkID) --max-history 10 --json") == true)
        #expect(receipt["verificationHint"] as? String == "verify_with_safe_commands_and_source_refs")
        #expect(receipt["truthBoundary"] as? String == "receipt_proves_command_execution_and_review_state_outcome_not_memory_truth")

        let ledger = try assertStrictProcessJSON(
            runCLI(args: ["item", "action-ledger", "list", "--owner", "bookmark:\(bookmarkID)", "--command", "review.routing.correct", "--json"], vault: vault),
            command: "item.action-ledger.list"
        )
        let entries = try #require(ledger["entries"] as? [[String: Any]])
        let entry = try #require(entries.first { $0["command"] as? String == "review.routing.correct" })
        let entryID = try #require(entry["id"] as? String)
        #expect(entry["action"] as? String == "correct")
        #expect(entry["status"] as? String == "corrected")
        #expect(entry["resultStatus"] as? String == "corrected")
        #expect(entry["changed"] as? Bool == true)

        let inspected = try assertStrictProcessJSON(
            runCLI(args: ["item", "action-ledger", "inspect", entryID, "--json"], vault: vault),
            command: "item.action-ledger.inspect"
        )
        let inspectedEntry = try #require(inspected["entry"] as? [String: Any])
        #expect(inspectedEntry["command"] as? String == "review.routing.correct")
        #expect(inspectedEntry["ownerRef"] as? String == "bookmark:\(bookmarkID)")

        let context = try assertStrictProcessJSON(
            runCLI(args: ["item", "context", "bookmark", bookmarkID, "--max-history", "10", "--json"], vault: vault),
            command: "item.context"
        )
        let recentHistory = try #require(context["recentHistory"] as? [[String: Any]])
        #expect(recentHistory.contains { history in
            history["kind"] as? String == "action_receipt"
                && history["command"] as? String == "review.routing.correct"
                && history["action"] as? String == "correct"
                && history["changed"] as? Bool == true
        })

        let missing = try assertStrictFailureJSON(
            runCLI(args: ["review", "correct", "missing-review-item", "--path", "Research", "--actor", "agent", "--json"], vault: vault),
            command: "review.routing.correct",
            errorCode: "item_not_found"
        )
        #expect(missing["actionReceipt"] == nil)

        let failedLedger = try assertStrictProcessJSON(
            runCLI(args: ["item", "action-ledger", "list", "--command", "review.routing.correct", "--status", "failed", "--json"], vault: vault),
            command: "item.action-ledger.list"
        )
        let failedEntries = try #require(failedLedger["entries"] as? [[String: Any]])
        #expect(failedEntries.isEmpty)
    }

    @Test("action ledger CLI lists and inspects recorded receipts")
    func actionLedgerCLIListsAndInspectsRecordedReceipts() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-action-ledger-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let capture = try assertStrictProcessJSON(
            runCLI(args: [
                "capture", "add", "--kind", "event",
                "--title", "Ledger smoke dinner",
                "--date", "2026-06-16",
                "--json",
            ], vault: vault),
            command: "capture.add"
        )
        let item = try #require(capture["item"] as? [String: Any])
        let id = try #require(item["id"] as? String)

        let why = try assertStrictProcessJSON(
            runCLI(args: ["item", "why-surfaced", "dateCard", id, "--json"], vault: vault),
            command: "item.why-surfaced"
        )
        #expect((why["actionReceipt"] as? [String: Any])?["changed"] as? Bool == false)

        let list = try assertStrictProcessJSON(
            runCLI(args: ["item", "action-ledger", "list", "--owner", "dateCard:\(id)", "--action", "inspect_surfacing", "--limit", "5", "--json"], vault: vault),
            command: "item.action-ledger.list"
        )
        #expect(list["readOnly"] as? Bool == true)
        #expect(list["changed"] as? Bool == false)
        let entries = try #require(list["entries"] as? [[String: Any]])
        let entry = try #require(entries.first)
        #expect(entry["command"] as? String == "item.why-surfaced")
        #expect(entry["action"] as? String == "inspect_surfacing")
        #expect(entry["status"] as? String == "succeeded")
        #expect(entry["changed"] as? Bool == false)
        let entryID = try #require(entry["id"] as? String)

        let inspect = try assertStrictProcessJSON(
            runCLI(args: ["item", "action-ledger", "inspect", entryID, "--json"], vault: vault),
            command: "item.action-ledger.inspect"
        )
        let inspected = try #require(inspect["entry"] as? [String: Any])
        #expect(inspected["id"] as? String == entryID)
        #expect((inspected["safeVerificationCommands"] as? [String])?.contains("cider-cli item why-surfaced dateCard \(id) --json") == true)
    }

    @Test("ping receipt CLI records transport neutral surfaced receipt")
    func pingReceiptCLIRecordsTransportNeutralSurfacedReceipt() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-ping-receipt-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let capture = try assertStrictProcessJSON(
            runCLI(args: [
                "capture", "add", "--kind", "todo",
                "--content", "Ping receipt CLI todo",
                "--date", "2026-07-13",
                "--json",
            ], vault: vault),
            command: "capture.add"
        )
        let item = try #require(capture["item"] as? [String: Any])
        let id = try #require(item["id"] as? String)

        let receipt = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "ping-receipt", "record", "todo", id,
                "--transport", "discord",
                "--surface", "agent-chat",
                "--delivery-id", "discord-message-1",
                "--json",
            ], vault: vault),
            command: "item.ping-receipt.record"
        )

        #expect(receipt["readOnly"] as? Bool == false)
        #expect(receipt["changed"] as? Bool == true)
        #expect(receipt["truthBoundary"] as? String == "ping_receipt_records_delivery_not_item_truth")
        let actionReceipt = try #require(receipt["actionReceipt"] as? [String: Any])
        #expect(actionReceipt["action"] as? String == "record_ping_surface")
        #expect(actionReceipt["commandFamily"] as? String == "reminder_ping")
        #expect(actionReceipt["ownerRef"] as? String == "todo:\(id)")
        let safeCommands = try #require(receipt["safeNextCommands"] as? [String])
        #expect(safeCommands.contains("cider-cli item action-ledger list --owner todo:\(id) --action record_ping_surface --json"))

        let ledger = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "action-ledger", "list",
                "--owner", "todo:\(id)",
                "--action", "record_ping_surface",
                "--limit", "5",
                "--json",
            ], vault: vault),
            command: "item.action-ledger.list"
        )
        let entries = try #require(ledger["entries"] as? [[String: Any]])
        let entry = try #require(entries.first)
        #expect(entry["command"] as? String == "item.ping-receipt.record")
        #expect(entry["action"] as? String == "record_ping_surface")
        #expect(entry["changed"] as? Bool == true)
    }

    @Test("reminder ping intents CLI suppresses after matching ping receipt")
    func reminderPingIntentsCLISuppressesAfterMatchingPingReceipt() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-reminder-ping-intents-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let dueDate = Self.relativeDateString(daysFromToday: -1)

        let capture = try assertStrictProcessJSON(
            runCLI(args: [
                "capture", "add", "--kind", "todo",
                "--content", "Reminder ping intents CLI todo",
                "--date", dueDate,
                "--json",
            ], vault: vault),
            command: "capture.add"
        )
        let item = try #require(capture["item"] as? [String: Any])
        let id = try #require(item["id"] as? String)

        let before = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-intents",
                "--limit", "10",
                "--stale-after-days", "999",
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-intents"
        )
        #expect(before["readOnly"] as? Bool == true)
        #expect(before["changed"] as? Bool == false)
        #expect(before["truthBoundary"] as? String == "cider_items_plus_action_receipts")
        let actionReceipt = try #require(before["actionReceipt"] as? [String: Any])
        #expect(actionReceipt["readOnly"] as? Bool == true)
        #expect(actionReceipt["changed"] as? Bool == false)
        #expect(actionReceipt["transportBoundary"] as? String == "no_transport_send")
        let intents = try #require(before["intents"] as? [[String: Any]])
        let intent = try #require(intents.first { $0["itemID"] as? String == id })
        let duplicateKey = try #require(intent["duplicateKey"] as? String)
        #expect(intent["safeRecordPingCommand"] as? String == "cider-cli item ping-receipt record todo \(id) --transport <transport> --surface <surface> --json")
        #expect((intent["safeVerificationCommands"] as? [String])?.contains("cider-cli item action-ledger list --owner todo:\(id) --action record_ping_surface --json") == true)

        let receipt = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "ping-receipt", "record", "todo", id,
                "--transport", "discord",
                "--surface", "agent-chat",
                "--delivery-id", "discord-message-1",
                "--json",
            ], vault: vault),
            command: "item.ping-receipt.record"
        )
        #expect(receipt["duplicateKey"] as? String == duplicateKey)
        #expect(receipt["deliveryDuplicateKey"] as? String == "todo:\(id):discord:agent-chat:discord-message-1")

        let after = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-intents",
                "--limit", "10",
                "--stale-after-days", "999",
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-intents"
        )
        let afterIntents = try #require(after["intents"] as? [[String: Any]])
        #expect(afterIntents.contains { $0["itemID"] as? String == id } == false)
        let suppressed = try #require(after["suppressed"] as? [[String: Any]])
        let suppressedIntent = try #require(suppressed.first { $0["itemID"] as? String == id })
        #expect(suppressedIntent["duplicateKey"] as? String == duplicateKey)
        #expect(suppressedIntent["reason"] as? String == "matching_record_ping_surface_receipt")
    }

    @Test("reminder ping delivery preview CLI is no-send and records no receipts")
    func reminderPingDeliveryPreviewCLIIsNoSendAndRecordsNoReceipts() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-reminder-ping-delivery-preview-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let dueDate = Self.relativeDateString(daysFromToday: -1)

        let help = try runCLI(args: ["item", "reminder-ping-delivery-preview", "--help"], vault: vault)
        #expect(help.status == 0)
        #expect(help.stdout.contains("reminder-ping-delivery-preview"))
        #expect(help.stdout.contains("--transport"))
        #expect(help.stdout.contains("--surface"))

        let capture = try assertStrictProcessJSON(
            runCLI(args: [
                "capture", "add", "--kind", "todo",
                "--content", "Reminder ping delivery preview CLI todo",
                "--date", dueDate,
                "--json",
            ], vault: vault),
            command: "capture.add"
        )
        let item = try #require(capture["item"] as? [String: Any])
        let id = try #require(item["id"] as? String)

        let beforeLedger = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "action-ledger", "list",
                "--owner", "todo:\(id)",
                "--action", "record_ping_surface",
                "--limit", "5",
                "--json",
            ], vault: vault),
            command: "item.action-ledger.list"
        )
        #expect((beforeLedger["entries"] as? [[String: Any]])?.isEmpty == true)

        let preview = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-delivery-preview",
                "--transport", "discord",
                "--surface", "agent-chat",
                "--limit", "10",
                "--stale-after-days", "999",
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-delivery-preview"
        )
        #expect(preview["readOnly"] as? Bool == true)
        #expect(preview["changed"] as? Bool == false)
        #expect(preview["truthBoundary"] as? String == "cider_items_plus_action_receipts_no_send_preview")
        let actionReceipt = try #require(preview["actionReceipt"] as? [String: Any])
        #expect(actionReceipt["readOnly"] as? Bool == true)
        #expect(actionReceipt["changed"] as? Bool == false)
        #expect(actionReceipt["transportBoundary"] as? String == "no_transport_send")
        let envelopes = try #require(preview["envelopes"] as? [[String: Any]])
        let envelope = try #require(envelopes.first { $0["itemID"] as? String == id })
        let duplicateKey = try #require(envelope["duplicateKey"] as? String)
        #expect(envelope["transport"] as? String == "discord")
        #expect(envelope["surface"] as? String == "agent-chat")
        #expect(envelope["deliveryKey"] as? String == "\(duplicateKey):discord:agent-chat")
        #expect(envelope["safeRecordPingCommand"] as? String == "cider-cli item reminder-ping-confirm-delivery todo \(id) --transport discord --surface agent-chat --delivery-id <delivery-id> --json")
        #expect((envelope["message"] as? String)?.contains("Reminder ping delivery preview CLI todo") == true)

        let afterPreviewLedger = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "action-ledger", "list",
                "--owner", "todo:\(id)",
                "--action", "record_ping_surface",
                "--limit", "5",
                "--json",
            ], vault: vault),
            command: "item.action-ledger.list"
        )
        #expect((afterPreviewLedger["entries"] as? [[String: Any]])?.isEmpty == true)

        _ = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "ping-receipt", "record", "todo", id,
                "--transport", "discord",
                "--surface", "agent-chat",
                "--delivery-id", "discord-message-1",
                "--json",
            ], vault: vault),
            command: "item.ping-receipt.record"
        )
        let after = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-delivery-preview",
                "--transport", "discord",
                "--surface", "agent-chat",
                "--limit", "10",
                "--stale-after-days", "999",
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-delivery-preview"
        )
        #expect((after["envelopes"] as? [[String: Any]])?.contains { $0["itemID"] as? String == id } == false)
        let suppressed = try #require(after["suppressed"] as? [[String: Any]])
        #expect(suppressed.contains { $0["itemID"] as? String == id && $0["duplicateKey"] as? String == duplicateKey })
    }

    @Test("reminder ping dry run CLI summarizes no-send worker pass without receipts")
    func reminderPingDryRunCLISummarizesNoSendWorkerPassWithoutReceipts() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-reminder-ping-dry-run-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let dueDate = Self.relativeDateString(daysFromToday: -1)

        let help = try runCLI(args: ["item", "reminder-ping-dry-run", "--help"], vault: vault)
        #expect(help.status == 0)
        #expect(help.stdout.contains("reminder-ping-dry-run"))
        #expect(help.stdout.contains("reminder-ping-delivery-preview"))

        let capture = try assertStrictProcessJSON(
            runCLI(args: [
                "capture", "add", "--kind", "todo",
                "--content", "Reminder ping dry run CLI todo",
                "--date", dueDate,
                "--json",
            ], vault: vault),
            command: "capture.add"
        )
        let item = try #require(capture["item"] as? [String: Any])
        let id = try #require(item["id"] as? String)

        let before = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-dry-run",
                "--transport", "discord",
                "--surface", "agent-chat",
                "--limit", "10",
                "--stale-after-days", "999",
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-dry-run"
        )
        #expect(before["readOnly"] as? Bool == true)
        #expect(before["changed"] as? Bool == false)
        #expect(before["truthBoundary"] as? String == "cider_items_plus_action_receipts_remain_source_of_truth_no_send_dry_run")
        #expect(before["transport"] as? String == "discord")
        #expect(before["surface"] as? String == "agent-chat")
        #expect(before["runKey"] as? String != nil)
        let counts = try #require(before["counts"] as? [String: Any])
        #expect(counts["eligible"] as? Int == 1)
        #expect(counts["planned"] as? Int == 1)
        #expect(counts["suppressed"] as? Int == 0)
        #expect(counts["duplicates"] as? Int == 0)
        let refs = try #require(before["eligibleEnvelopeRefs"] as? [String])
        #expect(refs.count == 1)
        let planned = try #require(before["planned"] as? [[String: Any]])
        let plannedPing = try #require(planned.first)
        #expect(plannedPing["wouldSend"] as? Bool == false)
        #expect(plannedPing["readOnly"] as? Bool == true)
        #expect(plannedPing["changed"] as? Bool == false)
        let envelope = try #require(plannedPing["envelope"] as? [String: Any])
        #expect(envelope["itemID"] as? String == id)
        let duplicateKey = try #require(envelope["duplicateKey"] as? String)
        let safeRecordCommands = try #require(before["safeRecordPingCommands"] as? [String])
        #expect(safeRecordCommands == ["cider-cli item reminder-ping-confirm-delivery todo \(id) --transport discord --surface agent-chat --delivery-id <delivery-id> --json"])
        let actionReceipt = try #require(before["actionReceipt"] as? [String: Any])
        #expect(actionReceipt["readOnly"] as? Bool == true)
        #expect(actionReceipt["changed"] as? Bool == false)
        #expect(actionReceipt["transportBoundary"] as? String == "no_transport_send")
        #expect(actionReceipt["pendingEnvelopeCount"] as? Int == 1)

        let afterDryRunLedger = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "action-ledger", "list",
                "--owner", "todo:\(id)",
                "--action", "record_ping_surface",
                "--limit", "5",
                "--json",
            ], vault: vault),
            command: "item.action-ledger.list"
        )
        #expect((afterDryRunLedger["entries"] as? [[String: Any]])?.isEmpty == true)

        _ = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "ping-receipt", "record", "todo", id,
                "--transport", "discord",
                "--surface", "agent-chat",
                "--delivery-id", "discord-message-1",
                "--json",
            ], vault: vault),
            command: "item.ping-receipt.record"
        )
        let after = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-dry-run",
                "--transport", "discord",
                "--surface", "agent-chat",
                "--limit", "10",
                "--stale-after-days", "999",
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-dry-run"
        )
        #expect((after["planned"] as? [[String: Any]])?.isEmpty == true)
        let afterCounts = try #require(after["counts"] as? [String: Any])
        #expect(afterCounts["planned"] as? Int == 0)
        #expect(afterCounts["suppressed"] as? Int == 1)
        let suppressed = try #require(after["suppressed"] as? [[String: Any]])
        #expect(suppressed.contains { $0["itemID"] as? String == id && $0["duplicateKey"] as? String == duplicateKey })
    }

    @Test("reminder ping confirm delivery CLI requires transport delivery ID before receipt")
    func reminderPingConfirmDeliveryCLIRequiresTransportDeliveryIDBeforeReceipt() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-reminder-ping-confirm-delivery-missing-id-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let dueDate = Self.relativeDateString(daysFromToday: -1)

        let help = try runCLI(args: ["item", "reminder-ping-confirm-delivery", "--help"], vault: vault)
        #expect(help.status == 0)
        #expect(help.stdout.contains("reminder-ping-confirm-delivery"))
        #expect(help.stdout.contains("--delivery-id"))

        let capture = try assertStrictProcessJSON(
            runCLI(args: [
                "capture", "add", "--kind", "todo",
                "--content", "Reminder ping confirmed delivery missing id todo",
                "--date", dueDate,
                "--json",
            ], vault: vault),
            command: "capture.add"
        )
        let item = try #require(capture["item"] as? [String: Any])
        let id = try #require(item["id"] as? String)

        let missingID = try parseJSONObject(try runCLI(args: [
            "item", "reminder-ping-confirm-delivery", "todo", id,
            "--transport", "discord",
            "--surface", "agent-chat",
            "--limit", "10",
            "--stale-after-days", "999",
            "--json",
        ], vault: vault).stdout)

        #expect(missingID["ok"] as? Bool == false)
        #expect(missingID["command"] as? String == "item.reminder-ping-confirm-delivery")
        #expect(missingID["readOnly"] as? Bool == false)
        #expect(missingID["changed"] as? Bool == false)
        #expect(missingID["errorCode"] as? String == "missing_delivery_id")
        #expect(missingID["truthBoundary"] as? String == "transport_confirmation_required_before_ping_receipt")

        let ledger = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "action-ledger", "list",
                "--owner", "todo:\(id)",
                "--action", "record_ping_surface",
                "--limit", "5",
                "--json",
            ], vault: vault),
            command: "item.action-ledger.list"
        )
        #expect((ledger["entries"] as? [[String: Any]])?.isEmpty == true)
    }

    @Test("reminder ping confirm delivery CLI records eligible envelope once")
    func reminderPingConfirmDeliveryCLIRecordsEligibleEnvelopeOnce() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-reminder-ping-confirm-delivery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let dueDate = Self.relativeDateString(daysFromToday: -1)

        let capture = try assertStrictProcessJSON(
            runCLI(args: [
                "capture", "add", "--kind", "todo",
                "--content", "Reminder ping confirmed delivery todo",
                "--date", dueDate,
                "--json",
            ], vault: vault),
            command: "capture.add"
        )
        let item = try #require(capture["item"] as? [String: Any])
        let id = try #require(item["id"] as? String)

        let before = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-dry-run",
                "--transport", "discord",
                "--surface", "agent-chat",
                "--limit", "10",
                "--stale-after-days", "999",
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-dry-run"
        )
        let planned = try #require(before["planned"] as? [[String: Any]])
        #expect(planned.count == 1)
        let envelope = try #require(planned.first?["envelope"] as? [String: Any])
        let duplicateKey = try #require(envelope["duplicateKey"] as? String)

        let receipt = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-confirm-delivery", "todo", id,
                "--transport", "discord",
                "--surface", "agent-chat",
                "--delivery-id", "discord-message-confirmed-1",
                "--limit", "10",
                "--stale-after-days", "999",
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-confirm-delivery"
        )
        #expect(receipt["readOnly"] as? Bool == false)
        #expect(receipt["changed"] as? Bool == true)
        #expect(receipt["truthBoundary"] as? String == "transport_confirmation_required_before_ping_receipt")
        #expect(receipt["duplicateKey"] as? String == duplicateKey)
        #expect(receipt["deliveryID"] as? String == "discord-message-confirmed-1")
        let actionReceipt = try #require(receipt["actionReceipt"] as? [String: Any])
        #expect(actionReceipt["command"] as? String == "item.ping-receipt.record")
        #expect(actionReceipt["action"] as? String == "record_ping_surface")

        let duplicate = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-confirm-delivery", "todo", id,
                "--transport", "discord",
                "--surface", "agent-chat",
                "--delivery-id", "discord-message-confirmed-2",
                "--limit", "10",
                "--stale-after-days", "999",
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-confirm-delivery"
        )
        #expect(duplicate["readOnly"] as? Bool == false)
        #expect(duplicate["changed"] as? Bool == false)
        #expect(duplicate["reason"] as? String == "matching_record_ping_surface_receipt")
        #expect(duplicate["duplicateKey"] as? String == duplicateKey)

        let after = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-dry-run",
                "--transport", "discord",
                "--surface", "agent-chat",
                "--limit", "10",
                "--stale-after-days", "999",
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-dry-run"
        )
        let afterCounts = try #require(after["counts"] as? [String: Any])
        #expect(afterCounts["planned"] as? Int == 0)
        #expect(afterCounts["suppressed"] as? Int == 1)

        let ledger = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "action-ledger", "list",
                "--owner", "todo:\(id)",
                "--action", "record_ping_surface",
                "--limit", "5",
                "--json",
            ], vault: vault),
            command: "item.action-ledger.list"
        )
        let entries = try #require(ledger["entries"] as? [[String: Any]])
        #expect(entries.count == 1)
    }

    @Test("reminder ping import ack CLI records delivered transcript rows safely")
    func reminderPingImportAckCLIRecordsDeliveredTranscriptRowsSafely() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-reminder-ping-import-ack-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let dueDate = Self.relativeDateString(daysFromToday: -1)

        let help = try runCLI(args: ["item", "reminder-ping-import-ack", "--help"], vault: vault)
        #expect(help.status == 0)
        #expect(help.stdout.contains("reminder-ping-import-ack"))
        #expect(help.stdout.contains("--file"))
        #expect(help.stdout.contains("JSONL"))

        let firstCapture = try assertStrictProcessJSON(
            runCLI(args: [
                "capture", "add", "--kind", "todo",
                "--content", "Reminder ping import ack first todo",
                "--date", dueDate,
                "--json",
            ], vault: vault),
            command: "capture.add"
        )
        let firstItem = try #require(firstCapture["item"] as? [String: Any])
        let firstID = try #require(firstItem["id"] as? String)

        let secondCapture = try assertStrictProcessJSON(
            runCLI(args: [
                "capture", "add", "--kind", "todo",
                "--content", "Reminder ping import ack second todo",
                "--date", dueDate,
                "--json",
            ], vault: vault),
            command: "capture.add"
        )
        let secondItem = try #require(secondCapture["item"] as? [String: Any])
        let secondID = try #require(secondItem["id"] as? String)

        let before = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-dry-run",
                "--transport", "discord",
                "--surface", "agent-chat",
                "--limit", "10",
                "--stale-after-days", "999",
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-dry-run"
        )
        let beforeCounts = try #require(before["counts"] as? [String: Any])
        #expect(beforeCounts["planned"] as? Int == 2)

        let transcript = vault.appendingPathComponent("delivered-reminder-pings.jsonl")
        let rows = [
            #"{"status":"delivered","itemType":"todo","itemID":"\#(firstID)","transport":"discord","surface":"agent-chat","deliveryID":"discord-import-1"}"#,
            #"{"status":"delivered","itemType":"todo","itemID":"\#(firstID)","transport":"discord","surface":"agent-chat","deliveryID":"discord-import-duplicate"}"#,
            #"{"status":"delivered","itemType":"todo","itemID":"\#(secondID)","transport":"discord","surface":"agent-chat"}"#,
            #"{"status":"delivered","itemType":"todo","itemID":"not-a-real-id","transport":"discord","surface":"agent-chat","deliveryID":"discord-import-unknown"}"#,
            #"{"status":"delivered","itemType":"todo""#,
        ].joined(separator: "\n")
        try rows.write(to: transcript, atomically: true, encoding: .utf8)

        let imported = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-import-ack",
                "--file", transcript.path,
                "--limit", "10",
                "--stale-after-days", "999",
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-import-ack"
        )
        #expect(imported["readOnly"] as? Bool == false)
        #expect(imported["changed"] as? Bool == true)
        #expect(imported["truthBoundary"] as? String == "transport_run_import_confirms_delivery_only")
        #expect(imported["transportBoundary"] as? String == "no_send_import_ack_only")
        let counts = try #require(imported["counts"] as? [String: Any])
        #expect(counts["changed"] as? Int == 1)
        #expect(counts["duplicates"] as? Int == 1)
        #expect(counts["failed"] as? Int == 3)
        #expect(counts["skipped"] as? Int == 0)
        let results = try #require(imported["rows"] as? [[String: Any]])
        #expect(results.count == 5)
        #expect(results.contains { $0["status"] as? String == "changed" && $0["itemID"] as? String == firstID })
        #expect(results.contains { $0["status"] as? String == "duplicate" && $0["itemID"] as? String == firstID })
        #expect(results.contains { $0["errorCode"] as? String == "missing_delivery_id" && $0["itemID"] as? String == secondID })
        #expect(results.contains { $0["errorCode"] as? String == "item_not_found" })
        #expect(results.contains { $0["errorCode"] as? String == "malformed_row" })

        let firstLedger = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "action-ledger", "list",
                "--owner", "todo:\(firstID)",
                "--action", "record_ping_surface",
                "--limit", "5",
                "--json",
            ], vault: vault),
            command: "item.action-ledger.list"
        )
        #expect((firstLedger["entries"] as? [[String: Any]])?.count == 1)

        let secondLedger = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "action-ledger", "list",
                "--owner", "todo:\(secondID)",
                "--action", "record_ping_surface",
                "--limit", "5",
                "--json",
            ], vault: vault),
            command: "item.action-ledger.list"
        )
        #expect((secondLedger["entries"] as? [[String: Any]])?.isEmpty == true)

        let after = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-dry-run",
                "--transport", "discord",
                "--surface", "agent-chat",
                "--limit", "10",
                "--stale-after-days", "999",
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-dry-run"
        )
        let afterCounts = try #require(after["counts"] as? [String: Any])
        #expect(afterCounts["planned"] as? Int == 1)
        #expect(afterCounts["suppressed"] as? Int == 1)
        let planned = try #require(after["planned"] as? [[String: Any]])
        #expect(planned.contains { $0["itemID"] as? String == secondID })
    }

    @Test("reminder ping transcript CLI writes no-send JSONL rows import ack skips safely")
    func reminderPingTranscriptCLIWritesNoSendJSONLRowsImportAckSkipsSafely() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-reminder-ping-transcript-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let dueDate = Self.relativeDateString(daysFromToday: -1)

        let help = try runCLI(args: ["item", "reminder-ping-transcript", "--help"], vault: vault)
        #expect(help.status == 0)
        #expect(help.stdout.contains("reminder-ping-transcript"))
        #expect(help.stdout.contains("--file"))
        #expect(help.stdout.contains("JSONL"))

        let firstCapture = try assertStrictProcessJSON(
            runCLI(args: [
                "capture", "add", "--kind", "todo",
                "--content", "Reminder ping transcript first todo",
                "--date", dueDate,
                "--json",
            ], vault: vault),
            command: "capture.add"
        )
        let firstItem = try #require(firstCapture["item"] as? [String: Any])
        let firstID = try #require(firstItem["id"] as? String)

        let secondCapture = try assertStrictProcessJSON(
            runCLI(args: [
                "capture", "add", "--kind", "todo",
                "--content", "Reminder ping transcript second todo",
                "--date", dueDate,
                "--json",
            ], vault: vault),
            command: "capture.add"
        )
        let secondItem = try #require(secondCapture["item"] as? [String: Any])
        let secondID = try #require(secondItem["id"] as? String)

        let transcriptFile = vault.appendingPathComponent("planned-reminder-pings.jsonl")
        let produced = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-transcript",
                "--transport", "discord",
                "--surface", "agent-chat",
                "--limit", "10",
                "--stale-after-days", "999",
                "--file", transcriptFile.path,
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-transcript"
        )
        #expect(produced["readOnly"] as? Bool == true)
        #expect(produced["changed"] as? Bool == false)
        #expect(produced["truthBoundary"] as? String == "cider_items_plus_action_receipts_remain_source_of_truth_no_send_transcript")
        #expect(produced["transportBoundary"] as? String == "no_transport_send_transcript_delivery_proof_required")
        let counts = try #require(produced["counts"] as? [String: Any])
        #expect(counts["rows"] as? Int == 2)
        #expect(counts["noSend"] as? Int == 2)
        #expect(counts["delivered"] as? Int == 0)
        let rows = try #require(produced["rows"] as? [[String: Any]])
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0["status"] as? String == "not_delivered" })
        #expect(rows.allSatisfy { $0["deliveryID"] == nil && $0["messageID"] == nil })
        #expect(rows.contains { $0["itemType"] as? String == "todo" && $0["itemID"] as? String == firstID && $0["ownerRef"] as? String == "todo:\(firstID)" })
        #expect(rows.contains { $0["itemType"] as? String == "todo" && $0["itemID"] as? String == secondID && $0["ownerRef"] as? String == "todo:\(secondID)" })
        #expect(rows.allSatisfy { $0["transport"] as? String == "discord" && $0["surface"] as? String == "agent-chat" })
        let artifact = try #require(produced["artifact"] as? [String: Any])
        #expect(artifact["path"] as? String == transcriptFile.path)
        #expect(artifact["format"] as? String == "jsonl")

        let lines = try String(contentsOf: transcriptFile, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        #expect(lines.count == 2)
        let firstRow = try parseJSONObject(lines[0])
        #expect(firstRow["status"] as? String == "not_delivered")
        #expect(firstRow["deliveryID"] == nil)

        let skipped = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-import-ack",
                "--file", transcriptFile.path,
                "--limit", "10",
                "--stale-after-days", "999",
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-import-ack"
        )
        let skippedCounts = try #require(skipped["counts"] as? [String: Any])
        #expect(skippedCounts["changed"] as? Int == 0)
        #expect(skippedCounts["skipped"] as? Int == 2)

        let ledger = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "action-ledger", "list",
                "--action", "record_ping_surface",
                "--limit", "5",
                "--json",
            ], vault: vault),
            command: "item.action-ledger.list"
        )
        #expect((ledger["entries"] as? [[String: Any]])?.isEmpty == true)

        var proofRows = try lines.map { try parseJSONObject($0) }
        proofRows[0]["deliveryID"] = "discord-transcript-proof-1"
        let proofLines = try proofRows.map { row -> String in
            let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            return String(data: data, encoding: .utf8) ?? "{}"
        }
        let proofFile = vault.appendingPathComponent("delivered-one-reminder-ping.jsonl")
        try proofLines.joined(separator: "\n").write(to: proofFile, atomically: true, encoding: .utf8)

        let imported = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-import-ack",
                "--file", proofFile.path,
                "--limit", "10",
                "--stale-after-days", "999",
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-import-ack"
        )
        let importedCounts = try #require(imported["counts"] as? [String: Any])
        #expect(importedCounts["changed"] as? Int == 1)
        #expect(importedCounts["skipped"] as? Int == 1)

        let afterProofLedger = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "action-ledger", "list",
                "--owner", "todo:\(firstID)",
                "--action", "record_ping_surface",
                "--limit", "5",
                "--json",
            ], vault: vault),
            command: "item.action-ledger.list"
        )
        #expect((afterProofLedger["entries"] as? [[String: Any]])?.count == 1)
    }

    @Test("reminder ping fake sender CLI writes proof transcript without receipts")
    func reminderPingFakeSenderCLIWritesProofTranscriptWithoutReceipts() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-reminder-ping-fake-sender-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let dueDate = Self.relativeDateString(daysFromToday: -1)

        let help = try runCLI(args: ["item", "reminder-ping-fake-send", "--help"], vault: vault)
        #expect(help.status == 0)
        #expect(help.stdout.contains("reminder-ping-fake-send"))
        #expect(help.stdout.contains("--output"))
        #expect(help.stdout.contains("no real send"))

        let firstCapture = try assertStrictProcessJSON(
            runCLI(args: [
                "capture", "add", "--kind", "todo",
                "--content", "Reminder ping fake sender first todo",
                "--date", dueDate,
                "--json",
            ], vault: vault),
            command: "capture.add"
        )
        let firstItem = try #require(firstCapture["item"] as? [String: Any])
        let firstID = try #require(firstItem["id"] as? String)

        let secondCapture = try assertStrictProcessJSON(
            runCLI(args: [
                "capture", "add", "--kind", "todo",
                "--content", "Reminder ping fake sender second todo",
                "--date", dueDate,
                "--json",
            ], vault: vault),
            command: "capture.add"
        )
        let secondItem = try #require(secondCapture["item"] as? [String: Any])
        let secondID = try #require(secondItem["id"] as? String)

        let plannedFile = vault.appendingPathComponent("planned-reminder-pings.jsonl")
        _ = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-transcript",
                "--transport", "discord",
                "--surface", "agent-chat",
                "--limit", "10",
                "--stale-after-days", "999",
                "--file", plannedFile.path,
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-transcript"
        )

        let deliveredFile = vault.appendingPathComponent("fake-delivered-reminder-pings.jsonl")
        let sent = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-fake-send",
                "--file", plannedFile.path,
                "--output", deliveredFile.path,
                "--limit", "1",
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-fake-send"
        )
        #expect(sent["readOnly"] as? Bool == true)
        #expect(sent["changed"] as? Bool == false)
        #expect(sent["truthBoundary"] as? String == "cider_items_plus_action_receipts_remain_source_of_truth_fake_transport_no_receipts")
        #expect(sent["transportBoundary"] as? String == "fake_transport_no_real_send_delivery_proof_only")
        let counts = try #require(sent["counts"] as? [String: Any])
        #expect(counts["rows"] as? Int == 2)
        #expect(counts["delivered"] as? Int == 1)
        #expect(counts["noSend"] as? Int == 1)
        let fileWrites = try #require(sent["fileWriteCounts"] as? [String: Any])
        #expect(fileWrites["written"] as? Int == 1)
        let artifact = try #require(sent["artifact"] as? [String: Any])
        #expect(artifact["path"] as? String == deliveredFile.path)

        let deliveredLines = try String(contentsOf: deliveredFile, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        #expect(deliveredLines.count == 2)
        let deliveredRows = try deliveredLines.map { try parseJSONObject($0) }
        let deliveredRow = try #require(deliveredRows.first { $0["status"] as? String == "delivered" })
        #expect(deliveredRow["deliveryID"] as? String == "fake-delivery:\(deliveredRow["envelopeID"] as? String ?? "")")
        #expect(deliveredRow["messageID"] as? String == "fake-message:\(deliveredRow["envelopeID"] as? String ?? "")")
        #expect(deliveredRow["fakeTransport"] as? Bool == true)
        #expect(deliveredRow["noRealSend"] as? Bool == true)
        #expect(deliveredRows.contains { $0["status"] as? String == "not_delivered" && $0["itemID"] as? String == secondID })

        let beforeImportLedger = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "action-ledger", "list",
                "--action", "record_ping_surface",
                "--limit", "5",
                "--json",
            ], vault: vault),
            command: "item.action-ledger.list"
        )
        #expect((beforeImportLedger["entries"] as? [[String: Any]])?.isEmpty == true)

        let imported = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-import-ack",
                "--file", deliveredFile.path,
                "--limit", "10",
                "--stale-after-days", "999",
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-import-ack"
        )
        let importedCounts = try #require(imported["counts"] as? [String: Any])
        #expect(importedCounts["changed"] as? Int == 1)
        #expect(importedCounts["skipped"] as? Int == 1)

        let firstLedger = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "action-ledger", "list",
                "--owner", "todo:\(firstID)",
                "--action", "record_ping_surface",
                "--limit", "5",
                "--json",
            ], vault: vault),
            command: "item.action-ledger.list"
        )
        #expect((firstLedger["entries"] as? [[String: Any]])?.count == 1)

        let secondLedger = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "action-ledger", "list",
                "--owner", "todo:\(secondID)",
                "--action", "record_ping_surface",
                "--limit", "5",
                "--json",
            ], vault: vault),
            command: "item.action-ledger.list"
        )
        #expect((secondLedger["entries"] as? [[String: Any]])?.isEmpty == true)
    }

    @Test("reminder ping transport worker CLI validates contract and writes proof transcript without receipts")
    func reminderPingTransportWorkerCLIValidatesContractAndWritesProofTranscriptWithoutReceipts() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-reminder-ping-transport-worker-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let dueDate = Self.relativeDateString(daysFromToday: -1)

        let help = try runCLI(args: ["item", "reminder-ping-transport-worker", "--help"], vault: vault)
        #expect(help.status == 0)
        #expect(help.stdout.contains("reminder-ping-transport-worker"))
        #expect(help.stdout.contains("--config-file"))
        #expect(help.stdout.contains("--worker-id"))
        #expect(help.stdout.contains("no real send"))

        let capture = try assertStrictProcessJSON(
            runCLI(args: [
                "capture", "add", "--kind", "todo",
                "--content", "Reminder ping transport worker contract todo",
                "--date", dueDate,
                "--json",
            ], vault: vault),
            command: "capture.add"
        )
        let item = try #require(capture["item"] as? [String: Any])
        let itemID = try #require(item["id"] as? String)

        let plannedFile = vault.appendingPathComponent("planned-reminder-pings.jsonl")
        _ = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-transcript",
                "--transport", "discord",
                "--surface", "agent-chat",
                "--limit", "10",
                "--stale-after-days", "999",
                "--file", plannedFile.path,
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-transcript"
        )

        let deliveredFile = vault.appendingPathComponent("worker-delivered-reminder-pings.jsonl")
        let delivered = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-transport-worker",
                "--file", plannedFile.path,
                "--output", deliveredFile.path,
                "--transport", "discord",
                "--worker-id", "discord-reminder-worker",
                "--sender-id", "discord-bot-local-stub",
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-transport-worker"
        )
        #expect(delivered["readOnly"] as? Bool == true)
        #expect(delivered["changed"] as? Bool == false)
        #expect(delivered["noRealSend"] as? Bool == true)
        #expect(delivered["truthBoundary"] as? String == "cider_items_plus_action_receipts_remain_source_of_truth_transport_worker_no_receipts")
        #expect(delivered["transportBoundary"] as? String == "transport_worker_contract_stub_no_real_send_delivery_proof_only")
        let counts = try #require(delivered["counts"] as? [String: Any])
        #expect(counts["rows"] as? Int == 1)
        #expect(counts["delivered"] as? Int == 1)
        let artifact = try #require(delivered["artifact"] as? [String: Any])
        #expect(artifact["path"] as? String == deliveredFile.path)

        let deliveredLine = try #require(String(contentsOf: deliveredFile, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
            .first)
        let deliveredRow = try parseJSONObject(deliveredLine)
        #expect(deliveredRow["itemID"] as? String == itemID)
        #expect(deliveredRow["status"] as? String == "delivered")
        #expect(deliveredRow["deliveryID"] as? String == "transport-worker:discord-reminder-worker:\(deliveredRow["envelopeID"] as? String ?? "")")
        #expect(deliveredRow["messageID"] as? String == "transport-worker-message:discord-reminder-worker:\(deliveredRow["envelopeID"] as? String ?? "")")
        #expect(deliveredRow["transportWorkerContract"] as? String == "stub")
        #expect(deliveredRow["noRealSend"] as? Bool == true)

        let beforeImportLedger = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "action-ledger", "list",
                "--owner", "todo:\(itemID)",
                "--action", "record_ping_surface",
                "--limit", "5",
                "--json",
            ], vault: vault),
            command: "item.action-ledger.list"
        )
        #expect((beforeImportLedger["entries"] as? [[String: Any]])?.isEmpty == true)

        let imported = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-import-ack",
                "--file", deliveredFile.path,
                "--limit", "10",
                "--stale-after-days", "999",
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-import-ack"
        )
        let importedCounts = try #require(imported["counts"] as? [String: Any])
        #expect(importedCounts["changed"] as? Int == 1)

        let afterImportLedger = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "action-ledger", "list",
                "--owner", "todo:\(itemID)",
                "--action", "record_ping_surface",
                "--limit", "5",
                "--json",
            ], vault: vault),
            command: "item.action-ledger.list"
        )
        #expect((afterImportLedger["entries"] as? [[String: Any]])?.count == 1)
    }

    @Test("reminder ping delivered validation gates planned import ack without receipts")
    func reminderPingDeliveredValidationGatesPlannedImportAckWithoutReceipts() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-reminder-ping-delivered-validation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let dueDate = Self.relativeDateString(daysFromToday: -1)

        let help = try runCLI(args: ["item", "reminder-ping-validate-delivered", "--help"], vault: vault)
        #expect(help.status == 0)
        #expect(help.stdout.contains("reminder-ping-validate-delivered"))
        #expect(help.stdout.contains("--planned-file"))
        #expect(help.stdout.contains("read-only"))

        let capture = try assertStrictProcessJSON(
            runCLI(args: [
                "capture", "add", "--kind", "todo",
                "--content", "Reminder ping delivered validation todo",
                "--date", dueDate,
                "--json",
            ], vault: vault),
            command: "capture.add"
        )
        let item = try #require(capture["item"] as? [String: Any])
        let itemID = try #require(item["id"] as? String)

        let plannedFile = vault.appendingPathComponent("planned-reminder-pings.jsonl")
        _ = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-transcript",
                "--transport", "discord",
                "--surface", "agent-chat",
                "--limit", "10",
                "--stale-after-days", "999",
                "--file", plannedFile.path,
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-transcript"
        )

        let configFile = vault.appendingPathComponent("worker.yaml")
        try """
        schemaVersion: 1
        transport: discord
        workerID: discord-reminder-worker
        senderID: discord-bot-local-stub
        """.write(to: configFile, atomically: true, encoding: .utf8)

        let deliveredFile = vault.appendingPathComponent("worker-delivered-reminder-pings.jsonl")
        _ = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-transport-worker",
                "--file", plannedFile.path,
                "--output", deliveredFile.path,
                "--config-file", configFile.path,
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-transport-worker"
        )

        let validated = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-validate-delivered",
                "--file", deliveredFile.path,
                "--planned-file", plannedFile.path,
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-validate-delivered"
        )
        #expect(validated["readOnly"] as? Bool == true)
        #expect(validated["changed"] as? Bool == false)
        #expect(validated["ok"] as? Bool == true)
        let validationCounts = try #require(validated["counts"] as? [String: Any])
        #expect(validationCounts["valid"] as? Int == 1)
        #expect(validationCounts["failed"] as? Int == 0)

        let beforeImportLedger = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "action-ledger", "list",
                "--owner", "todo:\(itemID)",
                "--action", "record_ping_surface",
                "--limit", "5",
                "--json",
            ], vault: vault),
            command: "item.action-ledger.list"
        )
        #expect((beforeImportLedger["entries"] as? [[String: Any]])?.isEmpty == true)

        let imported = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-import-ack",
                "--file", deliveredFile.path,
                "--planned-file", plannedFile.path,
                "--limit", "10",
                "--stale-after-days", "999",
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-import-ack"
        )
        let importedCounts = try #require(imported["counts"] as? [String: Any])
        #expect(importedCounts["changed"] as? Int == 1)

        var tampered = try parseJSONObject(try #require(String(contentsOf: deliveredFile, encoding: .utf8).split(separator: "\n").first).description)
        tampered["surface"] = "wrong-chat"
        let tamperedData = try JSONSerialization.data(withJSONObject: tampered, options: [.sortedKeys])
        let tamperedFile = vault.appendingPathComponent("tampered-delivered-reminder-pings.jsonl")
        try (String(data: tamperedData, encoding: .utf8) ?? "{}").write(to: tamperedFile, atomically: true, encoding: .utf8)

        let tamperedImport = try parseJSONObject(
            runCLI(args: [
                "item", "reminder-ping-import-ack",
                "--file", tamperedFile.path,
                "--planned-file", plannedFile.path,
                "--limit", "10",
                "--stale-after-days", "999",
                "--json",
            ], vault: vault).stdout
        )
        #expect(tamperedImport["ok"] as? Bool == false)
        #expect(tamperedImport["changed"] as? Bool == false)
        #expect(tamperedImport["errorCode"] as? String == "delivered_transcript_validation_failed")
    }

    @Test("reminder ping status CLI replays planned delivered import and duplicate receipt state read only")
    func reminderPingStatusCLIReplaysPlannedDeliveredImportAndDuplicateReceiptStateReadOnly() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-reminder-ping-status-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let dueDate = Self.relativeDateString(daysFromToday: -1)

        let help = try runCLI(args: ["item", "reminder-ping-status", "--help"], vault: vault)
        #expect(help.status == 0)
        #expect(help.stdout.contains("reminder-ping-status"))
        #expect(help.stdout.contains("--planned-file"))
        #expect(help.stdout.contains("--delivered-file"))
        #expect(help.stdout.contains("read-only"))

        let firstCapture = try assertStrictProcessJSON(
            runCLI(args: [
                "capture", "add", "--kind", "todo",
                "--content", "Reminder ping status first todo",
                "--date", dueDate,
                "--json",
            ], vault: vault),
            command: "capture.add"
        )
        let firstItem = try #require(firstCapture["item"] as? [String: Any])
        let firstID = try #require(firstItem["id"] as? String)

        let secondCapture = try assertStrictProcessJSON(
            runCLI(args: [
                "capture", "add", "--kind", "todo",
                "--content", "Reminder ping status second todo",
                "--date", dueDate,
                "--json",
            ], vault: vault),
            command: "capture.add"
        )
        let secondItem = try #require(secondCapture["item"] as? [String: Any])
        let secondID = try #require(secondItem["id"] as? String)

        let plannedFile = vault.appendingPathComponent("planned-reminder-pings.jsonl")
        _ = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-transcript",
                "--transport", "discord",
                "--surface", "agent-chat",
                "--limit", "10",
                "--stale-after-days", "999",
                "--file", plannedFile.path,
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-transcript"
        )

        let noDelivered = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-status",
                "--planned-file", plannedFile.path,
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-status"
        )
        #expect(noDelivered["readOnly"] as? Bool == true)
        #expect(noDelivered["changed"] as? Bool == false)
        #expect(noDelivered["runState"] as? String == "planned_not_delivered")
        let noDeliveredCounts = try #require(noDelivered["counts"] as? [String: Any])
        #expect(noDeliveredCounts["plannedRows"] as? Int == 2)
        #expect(noDeliveredCounts["deliveredRows"] as? Int == 0)
        #expect(noDeliveredCounts["missingReceipts"] as? Int == 2)
        #expect((noDelivered["safeNextCommands"] as? [String])?.contains("cider-cli item reminder-ping-transport-worker --file <planned-transcript.jsonl> --output <delivered-transcript.jsonl> --config-file <worker-config.yaml> --json") == true)

        let configFile = vault.appendingPathComponent("worker.yaml")
        try """
        schemaVersion: 1
        transport: discord
        workerID: discord-reminder-worker
        senderID: discord-bot-local-stub
        """.write(to: configFile, atomically: true, encoding: .utf8)

        let deliveredFile = vault.appendingPathComponent("worker-delivered-reminder-pings.jsonl")
        _ = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-transport-worker",
                "--file", plannedFile.path,
                "--output", deliveredFile.path,
                "--config-file", configFile.path,
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-transport-worker"
        )

        let beforeImport = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-status",
                "--planned-file", plannedFile.path,
                "--delivered-file", deliveredFile.path,
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-status"
        )
        #expect(beforeImport["runState"] as? String == "delivered_not_imported")
        let beforeCounts = try #require(beforeImport["counts"] as? [String: Any])
        #expect(beforeCounts["deliveredRows"] as? Int == 2)
        #expect(beforeCounts["validationValid"] as? Int == 2)
        #expect(beforeCounts["existingReceiptMatches"] as? Int == 0)
        #expect(beforeCounts["missingReceipts"] as? Int == 2)
        let beforeRows = try #require(beforeImport["rows"] as? [[String: Any]])
        #expect(beforeRows.allSatisfy { $0["receiptStatus"] as? String == "missing_receipt" })
        #expect((beforeImport["safeNextCommands"] as? [String])?.contains("cider-cli item reminder-ping-import-ack --file <delivered-transcript.jsonl> --planned-file <planned-transcript.jsonl> --json") == true)

        let imported = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-import-ack",
                "--file", deliveredFile.path,
                "--planned-file", plannedFile.path,
                "--limit", "10",
                "--stale-after-days", "999",
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-import-ack"
        )
        let importedCounts = try #require(imported["counts"] as? [String: Any])
        #expect(importedCounts["changed"] as? Int == 2)

        let afterImport = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-status",
                "--planned-file", plannedFile.path,
                "--delivered-file", deliveredFile.path,
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-status"
        )
        #expect(afterImport["runState"] as? String == "imported")
        let afterCounts = try #require(afterImport["counts"] as? [String: Any])
        #expect(afterCounts["existingReceiptMatches"] as? Int == 2)
        #expect(afterCounts["duplicateOrImportSkippedRows"] as? Int == 2)
        #expect(afterCounts["missingReceipts"] as? Int == 0)
        let afterRows = try #require(afterImport["rows"] as? [[String: Any]])
        #expect(afterRows.contains { $0["itemID"] as? String == firstID && $0["receiptStatus"] as? String == "receipt_exists" })
        #expect(afterRows.contains { $0["itemID"] as? String == secondID && $0["receiptStatus"] as? String == "receipt_exists" })
        #expect(afterRows.allSatisfy { ($0["matchingReceiptID"] as? String)?.isEmpty == false })
    }

    @Test("reminder ping status CLI reports tampered delivered validation failures without receipts")
    func reminderPingStatusCLIReportsTamperedDeliveredValidationFailuresWithoutReceipts() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-reminder-ping-status-tampered-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let dueDate = Self.relativeDateString(daysFromToday: -1)

        let capture = try assertStrictProcessJSON(
            runCLI(args: [
                "capture", "add", "--kind", "todo",
                "--content", "Reminder ping status tampered todo",
                "--date", dueDate,
                "--json",
            ], vault: vault),
            command: "capture.add"
        )
        let item = try #require(capture["item"] as? [String: Any])
        let itemID = try #require(item["id"] as? String)

        let plannedFile = vault.appendingPathComponent("planned-reminder-pings.jsonl")
        _ = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-transcript",
                "--transport", "discord",
                "--surface", "agent-chat",
                "--limit", "10",
                "--stale-after-days", "999",
                "--file", plannedFile.path,
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-transcript"
        )

        let deliveredFile = vault.appendingPathComponent("delivered-reminder-pings.jsonl")
        _ = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-fake-send",
                "--file", plannedFile.path,
                "--output", deliveredFile.path,
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-fake-send"
        )
        var tampered = try parseJSONObject(try #require(String(contentsOf: deliveredFile, encoding: .utf8).split(separator: "\n").first).description)
        tampered["surface"] = "wrong-chat"
        let tamperedData = try JSONSerialization.data(withJSONObject: tampered, options: [.sortedKeys])
        let tamperedFile = vault.appendingPathComponent("tampered-delivered-reminder-pings.jsonl")
        try (String(data: tamperedData, encoding: .utf8) ?? "{}").write(to: tamperedFile, atomically: true, encoding: .utf8)

        let status = try parseJSONObject(
            runCLI(args: [
                "item", "reminder-ping-status",
                "--planned-file", plannedFile.path,
                "--delivered-file", tamperedFile.path,
                "--json",
            ], vault: vault).stdout
        )
        #expect(status["ok"] as? Bool == false)
        #expect(status["readOnly"] as? Bool == true)
        #expect(status["changed"] as? Bool == false)
        #expect(status["runState"] as? String == "blocked_by_validation")
        #expect(status["errorCode"] as? String == "delivered_transcript_validation_failed")
        let counts = try #require(status["counts"] as? [String: Any])
        #expect(counts["validationFailed"] as? Int == 1)
        #expect(counts["existingReceiptMatches"] as? Int == 0)

        let ledger = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "action-ledger", "list",
                "--owner", "todo:\(itemID)",
                "--action", "record_ping_surface",
                "--limit", "5",
                "--json",
            ], vault: vault),
            command: "item.action-ledger.list"
        )
        #expect((ledger["entries"] as? [[String: Any]])?.isEmpty == true)
    }

    @Test("reminder ping transport worker CLI loads config file and fails closed on identity conflicts")
    func reminderPingTransportWorkerCLILoadsConfigFileAndFailsClosedOnIdentityConflicts() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-reminder-ping-transport-worker-config-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let dueDate = Self.relativeDateString(daysFromToday: -1)

        let capture = try assertStrictProcessJSON(
            runCLI(args: [
                "capture", "add", "--kind", "todo",
                "--content", "Reminder ping transport worker config todo",
                "--date", dueDate,
                "--json",
            ], vault: vault),
            command: "capture.add"
        )
        let item = try #require(capture["item"] as? [String: Any])
        let itemID = try #require(item["id"] as? String)

        let plannedFile = vault.appendingPathComponent("planned-reminder-pings.jsonl")
        _ = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-transcript",
                "--transport", "discord",
                "--surface", "agent-chat",
                "--limit", "10",
                "--stale-after-days", "999",
                "--file", plannedFile.path,
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-transcript"
        )

        let configFile = vault.appendingPathComponent("worker.yaml")
        try """
        schemaVersion: 1
        transport: discord
        workerID: discord-reminder-worker
        senderID: discord-bot-local-stub
        senderMetadataDefaults:
          workspace: local-dev
        """.write(to: configFile, atomically: true, encoding: .utf8)

        let deliveredFile = vault.appendingPathComponent("worker-delivered-reminder-pings.jsonl")
        let delivered = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "reminder-ping-transport-worker",
                "--file", plannedFile.path,
                "--output", deliveredFile.path,
                "--config-file", configFile.path,
                "--json",
            ], vault: vault),
            command: "item.reminder-ping-transport-worker"
        )
        #expect(delivered["readOnly"] as? Bool == true)
        #expect(delivered["changed"] as? Bool == false)
        #expect(delivered["noRealSend"] as? Bool == true)
        #expect((delivered["safeNextCommands"] as? [String])?.contains("cider-cli item reminder-ping-import-ack --file <transport-worker-delivered.jsonl> --json") == true)

        let worker = try #require(delivered["worker"] as? [String: Any])
        #expect(worker["configFile"] as? String == configFile.path)
        #expect(worker["transport"] as? String == "discord")
        #expect(worker["workerID"] as? String == "discord-reminder-worker")

        let deliveredLine = try #require(String(contentsOf: deliveredFile, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
            .first)
        let deliveredRow = try parseJSONObject(deliveredLine)
        #expect(deliveredRow["itemID"] as? String == itemID)
        let metadata = try #require(deliveredRow["senderMetadata"] as? [String: Any])
        #expect(metadata["workspace"] as? String == "local-dev")
        #expect(metadata["noRealSend"] as? String == "true")

        let beforeImportLedger = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "action-ledger", "list",
                "--owner", "todo:\(itemID)",
                "--action", "record_ping_surface",
                "--limit", "5",
                "--json",
            ], vault: vault),
            command: "item.action-ledger.list"
        )
        #expect((beforeImportLedger["entries"] as? [[String: Any]])?.isEmpty == true)

        let conflict = try parseJSONObject(
            runCLI(args: [
                "item", "reminder-ping-transport-worker",
                "--file", plannedFile.path,
                "--output", deliveredFile.path,
                "--config-file", configFile.path,
                "--transport", "telegram",
                "--json",
            ], vault: vault).stdout
        )
        #expect(conflict["ok"] as? Bool == false)
        #expect(conflict["readOnly"] as? Bool == true)
        #expect(conflict["changed"] as? Bool == false)
        #expect(conflict["noRealSend"] as? Bool == true)
        #expect((conflict["error"] as? String)?.contains("conflicts") == true)
        #expect((conflict["safeNextCommands"] as? [String])?.contains("cider-cli item reminder-ping-import-ack --file <transport-worker-delivered.jsonl> --json") == true)
    }

    @Test("reminder ping transport worker CLI rejects invalid config with agent safe JSON")
    func reminderPingTransportWorkerCLIRejectsInvalidConfigWithAgentSafeJSON() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-reminder-ping-transport-worker-invalid-config-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let plannedFile = vault.appendingPathComponent("planned-reminder-pings.jsonl")
        try "".write(to: plannedFile, atomically: true, encoding: .utf8)
        let outputFile = vault.appendingPathComponent("worker-delivered-reminder-pings.jsonl")
        let configFile = vault.appendingPathComponent("worker.json")
        try #"{"schemaVersion":99,"transport":"discord","workerID":"worker","senderID":"sender"}"#
            .write(to: configFile, atomically: true, encoding: .utf8)

        let invalid = try parseJSONObject(
            runCLI(args: [
                "item", "reminder-ping-transport-worker",
                "--file", plannedFile.path,
                "--output", outputFile.path,
                "--config-file", configFile.path,
                "--json",
            ], vault: vault).stdout
        )

        #expect(invalid["ok"] as? Bool == false)
        #expect(invalid["readOnly"] as? Bool == true)
        #expect(invalid["changed"] as? Bool == false)
        #expect(invalid["noRealSend"] as? Bool == true)
        #expect((invalid["error"] as? String)?.contains("Unsupported transport worker config schemaVersion") == true)
        #expect((invalid["safeNextCommands"] as? [String])?.contains("cider-cli item reminder-ping-import-ack --file <transport-worker-delivered.jsonl> --json") == true)
        #expect(FileManager.default.fileExists(atPath: outputFile.path) == false)
    }

    @Test("action ledger CLI filters by command refs and time windows")
    func actionLedgerCLIFiltersByCommandRefsAndTimeWindows() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-action-ledger-filter-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let sourceID = try createNote(title: "Ledger Filter Source", content: "Source", vault: vault)
        let targetID = try createNote(title: "Ledger Filter Target", content: "Target", vault: vault)
        let beforeMutation = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60))
        _ = try parseJSONObject(try runCLI(args: ["item", "link", "note", sourceID, "note", targetID, "--json"], vault: vault).stdout)
        let afterMutation = ISO8601DateFormatter().string(from: Date().addingTimeInterval(60))
        _ = try parseJSONObject(try runCLI(args: ["item", "why-surfaced", "note", sourceID, "--json"], vault: vault).stdout)

        let byCommand = try assertStrictProcessJSON(
            runCLI(args: ["item", "action-ledger", "list", "--owner", "note:\(sourceID)", "--command", "link.add", "--limit", "10", "--json"], vault: vault),
            command: "item.action-ledger.list"
        )
        let commandEntries = try #require(byCommand["entries"] as? [[String: Any]])
        #expect(commandEntries.map { $0["command"] as? String } == ["link.add"])
        #expect((byCommand["filters"] as? [String: Any])?["command"] as? String == "link.add")

        let byEvidence = try assertStrictProcessJSON(
            runCLI(args: ["item", "action-ledger", "list", "--evidence-ref", "note:\(targetID)", "--since", beforeMutation, "--before", afterMutation, "--json"], vault: vault),
            command: "item.action-ledger.list"
        )
        let evidenceEntries = try #require(byEvidence["entries"] as? [[String: Any]])
        #expect(evidenceEntries.contains { entry in
            entry["command"] as? String == "link.add"
                && (entry["evidenceRefs"] as? [String])?.contains("note:\(targetID)") == true
        })
        let filters = try #require(byEvidence["filters"] as? [String: Any])
        #expect(filters["evidenceRef"] as? String == "note:\(targetID)")
        #expect(filters["since"] as? String == beforeMutation)
        #expect(filters["before"] as? String == afterMutation)
    }

    @Test("action ledger CLI recap groups recent read-only and mutation receipts")
    func actionLedgerCLIRecapGroupsRecentReadOnlyAndMutationReceipts() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-action-ledger-recap-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let sourceID = try createNote(title: "Ledger Recap Source", content: "Source", vault: vault)
        let targetID = try createNote(title: "Ledger Recap Target", content: "Target", vault: vault)
        _ = try assertStrictProcessJSON(
            runCLI(args: ["item", "why-surfaced", "note", sourceID, "--json"], vault: vault),
            command: "item.why-surfaced"
        )
        _ = try assertStrictProcessJSON(
            runCLI(args: ["item", "link", "note", sourceID, "note", targetID, "--json"], vault: vault),
            command: "link.add"
        )

        let recap = try assertStrictProcessJSON(
            runCLI(args: ["item", "action-ledger", "recap", "--owner", "note:\(sourceID)", "--limit", "10", "--json"], vault: vault),
            command: "item.action-ledger.recap"
        )
        #expect(recap["readOnly"] as? Bool == true)
        #expect(recap["changed"] as? Bool == false)
        #expect(recap["truthBoundary"] as? String == "action_receipt_not_fact_truth")
        let groups = try #require(recap["groups"] as? [[String: Any]])
        #expect(groups.contains { group in
            group["family"] as? String == "item"
                && group["command"] as? String == "item.why-surfaced"
                && group["status"] as? String == "succeeded"
        })
        #expect(groups.contains { group in
            group["family"] as? String == "link"
                && group["command"] as? String == "link.add"
                && group["status"] as? String == "succeeded"
        })
        let allEntries = groups.flatMap { ($0["entries"] as? [[String: Any]]) ?? [] }
        let readOnlyEntry = try #require(allEntries.first { $0["command"] as? String == "item.why-surfaced" })
        #expect(readOnlyEntry["readOnly"] as? Bool == true)
        #expect(readOnlyEntry["changed"] as? Bool == false)
        #expect(readOnlyEntry["truthBoundary"] as? String == "action_receipt_not_fact_truth")
        #expect(readOnlyEntry["outcomeBoundary"] as? String == "receipt_proves_command_outcome_only")
        #expect(readOnlyEntry["displaySummary"] as? String == "item.why-surfaced succeeded (read-only, unchanged)")
        let safeCommands = try #require(readOnlyEntry["safeVerificationCommands"] as? [String])
        #expect(safeCommands.contains { $0.hasPrefix("cider-cli item action-ledger inspect ") })
        #expect(safeCommands.contains("cider-cli item why-surfaced note \(sourceID) --json"))

        let mutationEntry = try #require(allEntries.first { $0["command"] as? String == "link.add" })
        #expect(mutationEntry["readOnly"] as? Bool == false)
        #expect(mutationEntry["changed"] as? Bool == true)
        #expect((mutationEntry["sourceRefs"] as? [String])?.contains("note:\(sourceID)") == true)

        let filtered = try assertStrictProcessJSON(
            runCLI(args: ["item", "action-ledger", "recap", "--owner", "note:\(sourceID)", "--family", "link", "--limit", "10", "--json"], vault: vault),
            command: "item.action-ledger.recap"
        )
        let filteredGroups = try #require(filtered["groups"] as? [[String: Any]])
        #expect(filteredGroups.map { $0["family"] as? String } == ["link"])
    }

    @Test("fact validity inspect not found returns and persists structured failure receipt")
    func factValidityInspectNotFoundReturnsAndPersistsStructuredFailureReceipt() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-fact-validity-failure-receipt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let missingID = "missing-cid-531"
        let result = try runCLI(args: ["item", "fact-validity", "inspect", missingID, "--json"], vault: vault)
        #expect(result.status != 0)
        let payload = try parseJSONObject(result.stdout)
        #expect(payload["ok"] as? Bool == false)
        #expect(payload["command"] as? String == "item.fact-validity.inspect")
        #expect(payload["errorCode"] as? String == "fact_validity_candidate_not_found")
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        let receipt = try #require(payload["actionReceipt"] as? [String: Any])
        #expect(receipt["command"] as? String == "item.fact-validity.inspect")
        #expect(receipt["action"] as? String == "inspect")
        #expect(receipt["status"] as? String == "failed")
        #expect(receipt["readOnly"] as? Bool == true)
        #expect(receipt["changed"] as? Bool == false)
        #expect(receipt["errorCode"] as? String == "fact_validity_candidate_not_found")
        #expect((receipt["sourceRefs"] as? [String])?.contains("fact_validity_candidate:\(missingID)") == true)

        let ledger = try assertStrictProcessJSON(
            runCLI(args: ["item", "action-ledger", "list", "--command", "item.fact-validity.inspect", "--status", "failed", "--limit", "5", "--json"], vault: vault),
            command: "item.action-ledger.list"
        )
        let entries = try #require(ledger["entries"] as? [[String: Any]])
        #expect(entries.contains { entry in
            entry["errorCode"] as? String == "fact_validity_candidate_not_found"
                && (entry["sourceRefs"] as? [String])?.contains("fact_validity_candidate:\(missingID)") == true
        })
    }

    @Test("entity resolution inspect persists receipt and appears in item context history")
    func entityResolutionInspectPersistsReceiptAndAppearsInItemContextHistory() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-entity-resolution-inspect-receipt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let noteID = try createNote(
            title: "Entity Resolution Inspect Source",
            content: "We went to Cactus for dinner.",
            vault: vault
        )
        let targetID = try createNote(title: "Cactus Restaurant", content: "Saved place entity.", vault: vault)
        let sourceOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: noteID)
        let sourceEntity = SecondBrainOwnerRef(ownerType: "graph_object", ownerID: "cactus-inspect")
        let targetEntity = SecondBrainOwnerRef(ownerType: "note", ownerID: targetID)

        let db = CiderDatabase()
        try db.open(at: vault.appendingPathComponent(".cider/cider.db"))
        let candidate = try SecondBrainEntityResolutionService(database: db, store: SecondBrainStore(database: db)).suggest(
            candidateType: "place_alias",
            sourceEntity: sourceEntity,
            sourceLabel: "Cactus",
            inputMention: "Cactus",
            targetEntity: targetEntity,
            targetLabel: "Cactus Restaurant",
            sourceOwner: sourceOwner,
            sourceQuote: "We went to Cactus for dinner.",
            confidence: 0.91,
            confidenceReasons: ["exact_alias", "place_visit_context"],
            actor: "test-agent",
            source: "entity_resolution.test"
        )
        db.close()

        let inspect = try assertStrictProcessJSON(
            runCLI(args: ["item", "entity-resolution", "inspect", candidate.id, "--json"], vault: vault),
            command: "item.entity-resolution.inspect"
        )
        #expect(inspect["readOnly"] as? Bool == true)
        #expect(inspect["changed"] as? Bool == false)
        let receipt = try #require(inspect["actionReceipt"] as? [String: Any])
        #expect(receipt["action"] as? String == "inspect")
        #expect(receipt["ownerRef"] as? String == "note:\(noteID)")
        #expect((receipt["sourceRefs"] as? [String])?.contains("entity_resolution_candidate:\(candidate.id)") == true)

        let context = try assertStrictProcessJSON(
            runCLI(args: ["item", "context", "note", noteID, "--max-history", "10", "--json"], vault: vault),
            command: "item.context"
        )
        let history = try #require(context["recentHistory"] as? [[String: Any]])
        #expect(history.contains { entry in
            entry["kind"] as? String == "action_receipt"
                && entry["command"] as? String == "item.entity-resolution.inspect"
                && entry["action"] as? String == "inspect"
                && entry["changed"] as? Bool == false
        })
    }

    @Test("action ledger inspect missing returns and persists structured failure receipt")
    func actionLedgerInspectMissingReturnsAndPersistsStructuredFailureReceipt() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-action-ledger-missing-receipt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let missingID = "missing-action-receipt-cid532"
        let result = try runCLI(args: ["item", "action-ledger", "inspect", missingID, "--json"], vault: vault)
        #expect(result.status != 0)
        let payload = try parseJSONObject(result.stdout)
        #expect(payload["ok"] as? Bool == false)
        #expect(payload["command"] as? String == "item.action-ledger.inspect")
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["errorCode"] as? String == "action_receipt_not_found")
        let receipt = try #require(payload["actionReceipt"] as? [String: Any])
        #expect(receipt["command"] as? String == "item.action-ledger.inspect")
        #expect(receipt["action"] as? String == "inspect")
        #expect(receipt["status"] as? String == "failed")
        #expect(receipt["readOnly"] as? Bool == true)
        #expect(receipt["changed"] as? Bool == false)
        #expect(receipt["errorCode"] as? String == "action_receipt_not_found")
        #expect((receipt["sourceRefs"] as? [String])?.contains("action_receipt:\(missingID)") == true)

        let ledger = try assertStrictProcessJSON(
            runCLI(args: ["item", "action-ledger", "list", "--command", "item.action-ledger.inspect", "--status", "failed", "--json"], vault: vault),
            command: "item.action-ledger.list"
        )
        let entries = try #require(ledger["entries"] as? [[String: Any]])
        #expect(entries.contains { entry in
            entry["errorCode"] as? String == "action_receipt_not_found"
                && (entry["sourceRefs"] as? [String])?.contains("action_receipt:\(missingID)") == true
        })
    }

    @Test("entity resolution inspect missing returns and persists structured failure receipt")
    func entityResolutionInspectMissingReturnsAndPersistsStructuredFailureReceipt() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-entity-resolution-missing-receipt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let missingID = "missing-entity-resolution-cid532"
        let result = try runCLI(args: ["item", "entity-resolution", "inspect", missingID, "--json"], vault: vault)
        #expect(result.status != 0)
        let payload = try parseJSONObject(result.stdout)
        #expect(payload["ok"] as? Bool == false)
        #expect(payload["command"] as? String == "item.entity-resolution.inspect")
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["errorCode"] as? String == "entity_resolution_candidate_not_found")
        let receipt = try #require(payload["actionReceipt"] as? [String: Any])
        #expect(receipt["command"] as? String == "item.entity-resolution.inspect")
        #expect(receipt["status"] as? String == "failed")
        #expect(receipt["errorCode"] as? String == "entity_resolution_candidate_not_found")
        #expect((receipt["sourceRefs"] as? [String])?.contains("entity_resolution_candidate:\(missingID)") == true)

        let ledger = try assertStrictProcessJSON(
            runCLI(args: ["item", "action-ledger", "list", "--command", "item.entity-resolution.inspect", "--status", "failed", "--json"], vault: vault),
            command: "item.action-ledger.list"
        )
        let entries = try #require(ledger["entries"] as? [[String: Any]])
        #expect(entries.contains { entry in entry["errorCode"] as? String == "entity_resolution_candidate_not_found" })
    }

    @Test("fact validity missing and duplicate defer return structured failure or no-op receipts")
    func factValidityMissingAndDuplicateDeferReturnStructuredReceipts() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-fact-validity-noop-receipt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let missingID = "missing-fact-validity-cid532"
        let missing = try runCLI(args: ["item", "fact-validity", "reject", missingID, "--reason", "Missing candidate.", "--json"], vault: vault)
        #expect(missing.status != 0)
        let missingPayload = try parseJSONObject(missing.stdout)
        #expect(missingPayload["command"] as? String == "item.fact-validity.reject")
        #expect(missingPayload["errorCode"] as? String == "fact_validity_candidate_not_found")
        #expect(missingPayload["readOnly"] as? Bool == false)
        #expect(missingPayload["changed"] as? Bool == false)
        let missingReceipt = try #require(missingPayload["actionReceipt"] as? [String: Any])
        #expect(missingReceipt["status"] as? String == "failed")
        #expect(missingReceipt["errorCode"] as? String == "fact_validity_candidate_not_found")
        #expect((missingReceipt["sourceRefs"] as? [String])?.contains("fact_validity_candidate:\(missingID)") == true)

        let noteID = try createNote(title: "Fact Validity No-op Source", content: "Newer evidence exists.", vault: vault)
        let propose = try runCLI(
            args: [
                "item", "fact-validity", "propose",
                "--target-ref", "owner_relation:cid532-target",
                "--state", "superseded",
                "--source-owner", "note:\(noteID)",
                "--quote", "Newer evidence exists.",
                "--reason", "Testing no-op defer.",
                "--json",
            ],
            vault: vault
        )
        let proposed = try parseJSONObject(propose.stdout)
        let candidate = try #require(proposed["candidate"] as? [String: Any])
        let candidateID = try #require(candidate["id"] as? String)

        let firstDefer = try runCLI(args: ["item", "fact-validity", "defer", candidateID, "--reason", "Later.", "--json"], vault: vault)
        #expect(firstDefer.status == 0)
        let duplicateDefer = try runCLI(args: ["item", "fact-validity", "defer", candidateID, "--reason", "Still later.", "--json"], vault: vault)
        let duplicatePayload = try parseJSONObject(duplicateDefer.stdout)
        #expect(duplicateDefer.status == 0)
        #expect(duplicatePayload["changed"] as? Bool == false)
        #expect(duplicatePayload["errorCode"] as? String == "fact_validity_already_deferred")
        let duplicateReceipt = try #require(duplicatePayload["actionReceipt"] as? [String: Any])
        #expect(duplicateReceipt["status"] as? String == "no_op")
        #expect(duplicateReceipt["changed"] as? Bool == false)
        #expect(duplicateReceipt["errorCode"] as? String == "fact_validity_already_deferred")

        let ledger = try assertStrictProcessJSON(
            runCLI(args: ["item", "action-ledger", "list", "--source-ref", "fact_validity_candidate:\(candidateID)", "--json"], vault: vault),
            command: "item.action-ledger.list"
        )
        let entries = try #require(ledger["entries"] as? [[String: Any]])
        #expect(entries.contains { $0["errorCode"] as? String == "fact_validity_already_deferred" && $0["status"] as? String == "no_op" })
    }

    @Test("legacy item read failures return structured agent-safe JSON")
    func legacyItemReadFailuresReturnStructuredAgentSafeJSON() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-structured-read-failures-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let unsupportedContext = try assertStrictFailureJSON(
            runCLI(args: ["item", "context", "badtype", "missing-cid533", "--json"], vault: vault),
            command: "item.context",
            errorCode: "unsupported_item_type"
        )
        #expect(unsupportedContext["readOnly"] as? Bool == true)
        #expect(unsupportedContext["changed"] as? Bool == false)
        #expect((unsupportedContext["supportedTypes"] as? [String])?.contains("note") == true)

        let missingContext = try assertStrictFailureJSON(
            runCLI(args: ["item", "context", "note", "missing-cid533", "--json"], vault: vault),
            command: "item.context",
            errorCode: "item_not_found"
        )
        #expect(missingContext["readOnly"] as? Bool == true)
        #expect(missingContext["changed"] as? Bool == false)
        let sourceRef = try #require(missingContext["sourceRef"] as? [String: Any])
        #expect(sourceRef["type"] as? String == "note")
        #expect(sourceRef["ref"] as? String == "missing-cid533")

        let missingGet = try assertStrictFailureJSON(
            runCLI(args: ["item", "get", "note", "missing-cid533", "--json"], vault: vault),
            command: "item.get",
            errorCode: "item_not_found"
        )
        #expect(missingGet["readOnly"] as? Bool == true)
        #expect(missingGet["changed"] as? Bool == false)

        let missingWhy = try assertStrictFailureJSON(
            runCLI(args: ["item", "why-surfaced", "note", "missing-cid533", "--json"], vault: vault),
            command: "item.why-surfaced",
            errorCode: "item_not_found"
        )
        #expect(missingWhy["readOnly"] as? Bool == true)
        #expect(missingWhy["changed"] as? Bool == false)
        let whyReceipt = try #require(missingWhy["actionReceipt"] as? [String: Any])
        #expect(whyReceipt["status"] as? String == "failed")
        #expect(whyReceipt["changed"] as? Bool == false)
    }

    @Test("feed filter failures distinguish invalid selectors from valid empty reads")
    func feedFilterFailuresDistinguishInvalidSelectorsFromValidEmptyReads() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-feed-filter-failures-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let invalidCaptureKind = try assertStrictFailureJSON(
            runCLI(args: ["capture", "review-queue", "--kind", "not_a_review_kind", "--json"], vault: vault),
            command: "capture.review-queue",
            errorCode: "unsupported_review_filter_value"
        )
        #expect(invalidCaptureKind["readOnly"] as? Bool == true)
        #expect(invalidCaptureKind["changed"] as? Bool == false)
        let captureFilter = try #require(invalidCaptureKind["filter"] as? [String: Any])
        #expect(captureFilter["name"] as? String == "kind")
        #expect(captureFilter["value"] as? String == "not_a_review_kind")
        #expect((invalidCaptureKind["supportedValues"] as? [String])?.contains("graph_candidate") == true)

        let invalidReviewState = try assertStrictFailureJSON(
            runCLI(args: ["review", "list", "--state", "not_a_state", "--json"], vault: vault),
            command: "review.list",
            errorCode: "unsupported_review_filter_value"
        )
        let reviewFilter = try #require(invalidReviewState["filter"] as? [String: Any])
        #expect(reviewFilter["name"] as? String == "state")
        #expect((invalidReviewState["supportedValues"] as? [String])?.contains("needs_review") == true)

        let malformedResurfaceLimit = try assertStrictFailureJSON(
            runCLI(args: ["item", "due-to-surface", "--limit", "not-a-number", "--json"], vault: vault),
            command: "item.due-to-surface",
            errorCode: "malformed_numeric_filter"
        )
        let resurfaceFilter = try #require(malformedResurfaceLimit["filter"] as? [String: Any])
        #expect(resurfaceFilter["name"] as? String == "limit")
        #expect(resurfaceFilter["value"] as? String == "not-a-number")
        #expect(malformedResurfaceLimit["readOnly"] as? Bool == true)
        #expect(malformedResurfaceLimit["changed"] as? Bool == false)
    }

    @Test("valid owner relation reads stay successful and read-only")
    func validOwnerRelationReadsStaySuccessfulAndReadOnly() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-owner-zero-results-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let noteID = try createNote(title: "Unlinked Owner", content: "No owner relations yet.", vault: vault)

        let ownerGet = try assertStrictProcessJSON(
            runCLI(args: ["item", "owner-get", "note", noteID, "--json"], vault: vault),
            command: "item.owner-get"
        )
        #expect(ownerGet["ok"] as? Bool == true)
        #expect(ownerGet["readOnly"] as? Bool == true)
        #expect(ownerGet["changed"] as? Bool == false)
        #expect(ownerGet["relationCount"] as? Int == 0)
        #expect(ownerGet["ownerResolved"] as? Bool == true)

        let relations = try assertStrictProcessJSON(
            runCLI(args: ["item", "relations", "note", noteID, "--json"], vault: vault),
            command: "item.relations"
        )
        #expect(relations["ok"] as? Bool == true)
        #expect(relations["readOnly"] as? Bool == true)
        #expect(relations["changed"] as? Bool == false)
        #expect(relations["relationCount"] as? Int == 0)
        let relationRows = try #require(relations["relations"] as? [[String: Any]])
        #expect(relationRows.isEmpty)

        let backlinks = try assertStrictProcessJSON(
            runCLI(args: ["item", "backlinks", "note", noteID, "--json"], vault: vault),
            command: "item.backlinks"
        )
        #expect(backlinks["ok"] as? Bool == true)
        #expect(backlinks["readOnly"] as? Bool == true)
        #expect(backlinks["changed"] as? Bool == false)
        #expect((backlinks["relationCount"] as? Int ?? 0) >= 1)
        let backlinkRows = try #require(backlinks["relations"] as? [[String: Any]])
        #expect(backlinkRows.contains {
            $0["relationType"] as? String == "produced_item"
                && (($0["sourceOwner"] as? [String: Any])?["ownerType"] as? String) == "capture_event"
        })

        let relatedResult = try runCLI(args: ["item", "related", "note", noteID, "--json"], vault: vault)
        #expect(relatedResult.status == 0)
        let related = try parseJSONArray(relatedResult.stdout)
        #expect(related.isEmpty)
    }

    @Test("review drilldown selector failures are structured and do not default to empty feeds")
    func reviewDrilldownSelectorFailuresAreStructuredAndDoNotDefaultToEmptyFeeds() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-review-drilldown-selector-failures-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let malformed = try assertStrictFailureJSON(
            runCLI(args: ["review", "drilldown", "bad-group", "--json"], vault: vault),
            command: "review.drilldown",
            errorCode: "malformed_review_drilldown_group_id"
        )
        #expect(malformed["readOnly"] as? Bool == true)
        #expect(malformed["changed"] as? Bool == false)
        let malformedSelector = try #require(malformed["selector"] as? [String: Any])
        #expect(malformedSelector["name"] as? String == "groupID")
        #expect(malformedSelector["value"] as? String == "bad-group")
        #expect(malformed["expectedFormat"] as? String == "kind:reviewState:requiredSafeAction:itemType")

        let unknownKind = try assertStrictFailureJSON(
            runCLI(args: ["review", "drilldown", "unknown_kind:needs_review:accept:note", "--json"], vault: vault),
            command: "review.drilldown",
            errorCode: "unsupported_review_drilldown_group_value"
        )
        let unknownSelector = try #require(unknownKind["selector"] as? [String: Any])
        #expect(unknownSelector["name"] as? String == "kind")
        #expect(unknownSelector["value"] as? String == "unknown_kind")
        #expect((unknownKind["supportedValues"] as? [String])?.contains("graph_candidate") == true)

        let malformedLimit = try assertStrictFailureJSON(
            runCLI(args: ["review", "drilldown", "graph_candidate:needs_review:accept:note", "--limit", "not-a-number", "--json"], vault: vault),
            command: "review.drilldown",
            errorCode: "malformed_numeric_filter"
        )
        let limitFilter = try #require(malformedLimit["filter"] as? [String: Any])
        #expect(limitFilter["name"] as? String == "limit")
        #expect(limitFilter["value"] as? String == "not-a-number")
    }

    @Test("unsupported owner selector policy fails while valid empty graph owner reads stay read-only")
    func unsupportedOwnerSelectorPolicyFailsWhileValidEmptyGraphOwnerReadsStayReadOnly() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-owner-selector-policy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let unsupportedRelations = try assertStrictFailureJSON(
            runCLI(args: ["item", "relations", "made_up_owner", "ref", "--json"], vault: vault),
            command: "item.relations",
            errorCode: "unsupported_owner_type"
        )
        #expect(unsupportedRelations["readOnly"] as? Bool == true)
        #expect(unsupportedRelations["changed"] as? Bool == false)
        let relationSelector = try #require(unsupportedRelations["selector"] as? [String: Any])
        #expect(relationSelector["type"] as? String == "made_up_owner")
        #expect(relationSelector["ref"] as? String == "ref")
        #expect((unsupportedRelations["supportedTypes"] as? [String])?.contains("graph_object") == true)

        let unsupportedOwnerGet = try assertStrictFailureJSON(
            runCLI(args: ["item", "owner-get", "made_up_owner", "ref", "--json"], vault: vault),
            command: "item.owner-get",
            errorCode: "unsupported_owner_type"
        )
        #expect(unsupportedOwnerGet["readOnly"] as? Bool == true)
        #expect(unsupportedOwnerGet["changed"] as? Bool == false)

        let validGraphRelations = try assertStrictProcessJSON(
            runCLI(args: ["item", "relations", "graph_object", "cid536-empty-owner", "--json"], vault: vault),
            command: "item.relations"
        )
        #expect(validGraphRelations["ok"] as? Bool == true)
        #expect(validGraphRelations["readOnly"] as? Bool == true)
        #expect(validGraphRelations["changed"] as? Bool == false)
        #expect(validGraphRelations["relationCount"] as? Int == 0)
        let graphRows = try #require(validGraphRelations["relations"] as? [[String: Any]])
        #expect(graphRows.isEmpty)
    }

    @Test("accepted memory facts list inspect and recall stay separate from reviewable candidates")
    func acceptedMemoryFactsListInspectAndRecallStaySeparateFromReviewableCandidates() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-accepted-memory-facts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let noteID = try createNote(title: "Memory Source", content: "Erik prefers espresso in the morning.", vault: vault)
        let acceptedCandidate = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "memory-suggest", "note", noteID,
                "--kind", "preference",
                "--value", "Erik prefers espresso in the morning",
                "--evidence", "Erik prefers espresso in the morning.",
                "--memory-key", "erik.morning.coffee",
                "--confidence", "0.93",
                "--json",
            ], vault: vault),
            command: "item.memory-suggest"
        )
        let acceptedCandidateDict = try #require(acceptedCandidate["candidate"] as? [String: Any])
        let acceptedCandidateID = try #require(acceptedCandidateDict["id"] as? String)

        let suggestedCandidate = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "memory-suggest", "note", noteID,
                "--kind", "pattern",
                "--value", "Erik sometimes mentions afternoon walks",
                "--evidence", "Maybe afternoon walks are useful.",
                "--memory-key", "erik.afternoon.walks",
                "--json",
            ], vault: vault),
            command: "item.memory-suggest"
        )
        let suggestedCandidateDict = try #require(suggestedCandidate["candidate"] as? [String: Any])
        let suggestedCandidateID = try #require(suggestedCandidateDict["id"] as? String)
        try seedCoordinatorExactEvidence(candidateIDs: [acceptedCandidateID], vault: vault)

        _ = try assertStrictProcessJSON(
            runCLI(args: ["item", "accept-memory-candidate", acceptedCandidateID, "--actor", "cody-test", "--json"], vault: vault),
            command: "item.accept-memory-candidate"
        )

        let list = try assertStrictProcessJSON(
            runCLI(args: ["item", "memory-facts", "list", "--json"], vault: vault),
            command: "item.memory-facts.list"
        )
        #expect(list["readOnly"] as? Bool == true)
        #expect(list["changed"] as? Bool == false)
        let listReceipt = try #require(list["actionReceipt"] as? [String: Any])
        #expect(listReceipt["command"] as? String == "item.memory-facts.list")
        #expect(listReceipt["readOnly"] as? Bool == true)
        #expect(listReceipt["changed"] as? Bool == false)
        #expect(listReceipt["status"] as? String == "succeeded")
        #expect(listReceipt["matchedCount"] as? Int == 1)
        #expect((listReceipt["matchedSourceRefs"] as? [String])?.contains("memory_candidate:\(acceptedCandidateID)") == true)
        #expect((listReceipt["safeCommandRefs"] as? [String])?.contains("cider-cli item memory-facts inspect \(acceptedCandidateID) --json") == true)
        #expect(listReceipt["truthBoundary"] as? String == "receipt_proves_command_execution_not_memory_truth")
        let facts = try #require(list["facts"] as? [[String: Any]])
        #expect(facts.count == 1)
        #expect(facts.first?["candidateID"] as? String == acceptedCandidateID)
        #expect(facts.first?["truthBoundary"] as? String == "accepted_memory_fact")
        #expect(facts.first?["truthState"] as? String == "accepted")
        #expect(facts.first?["reviewState"] as? String == "accepted")
        #expect(facts.first?["sourceEvidenceRecord"] != nil)
        #expect(facts.first?["actionHistory"] != nil)
        #expect(facts.first?["reviewActionCommands"] == nil)
        #expect(facts.contains { $0["candidateID"] as? String == suggestedCandidateID } == false)

        let inspect = try assertStrictProcessJSON(
            runCLI(args: ["item", "memory-facts", "inspect", acceptedCandidateID, "--json"], vault: vault),
            command: "item.memory-facts.inspect"
        )
        let inspectReceipt = try #require(inspect["actionReceipt"] as? [String: Any])
        #expect(inspectReceipt["command"] as? String == "item.memory-facts.inspect")
        #expect(inspectReceipt["readOnly"] as? Bool == true)
        #expect(inspectReceipt["changed"] as? Bool == false)
        #expect(inspectReceipt["status"] as? String == "succeeded")
        #expect((inspectReceipt["matchedSourceRefs"] as? [String])?.contains("memory_candidate:\(acceptedCandidateID)") == true)
        #expect((inspectReceipt["safeCommandRefs"] as? [String])?.contains("cider-cli item memory-facts inspect \(acceptedCandidateID) --json") == true)
        #expect(inspectReceipt["truthBoundary"] as? String == "receipt_proves_command_execution_not_memory_truth")
        let inspectedFact = try #require(inspect["fact"] as? [String: Any])
        #expect(inspectedFact["candidateRef"] as? String == "memory_candidate:\(acceptedCandidateID)")
        #expect(inspectedFact["sourceQuote"] as? String == "Erik prefers espresso in the morning.")
        #expect((inspectedFact["safeVerificationCommands"] as? [String])?.contains("cider-cli item memory-facts inspect \(acceptedCandidateID) --json") == true)
        let inspectedRelevance = try #require(inspectedFact["surfacingRelevance"] as? [String: Any])
        #expect(inspectedRelevance["factRef"] as? String == "accepted_memory_fact:\(acceptedCandidateID)")
        #expect(inspectedRelevance["truthBoundary"] as? String == "accepted_memory_fact")
        #expect(inspectedRelevance["candidateBoundary"] as? String == "reviewable_memory_candidates_excluded")
        #expect((inspectedRelevance["verificationCommands"] as? [String])?.contains("cider-cli item memory-facts inspect \(acceptedCandidateID) --json") == true)

        let recall = try assertStrictProcessJSON(
            runCLI(args: ["item", "recall-context", "--item", "note", noteID, "--json"], vault: vault),
            command: "item.recall-context"
        )
        let acceptedFacts = try #require(recall["acceptedFacts"] as? [[String: Any]])
        #expect(acceptedFacts.contains { fact in
            fact["kind"] as? String == "accepted_memory_fact"
                && fact["candidateID"] as? String == acceptedCandidateID
                && fact["truthBoundary"] as? String == "accepted_memory_fact"
        })
        let acceptedMemoryFacts = try #require(recall["acceptedMemoryFacts"] as? [[String: Any]])
        let recalledFact = try #require(acceptedMemoryFacts.first { $0["candidateID"] as? String == acceptedCandidateID })
        let recallRelevance = try #require(recalledFact["surfacingRelevance"] as? [String: Any])
        #expect(recallRelevance["context"] as? String == "recall_context")
        #expect(recallRelevance["factRef"] as? String == "accepted_memory_fact:\(acceptedCandidateID)")
        #expect(recallRelevance["truthBoundary"] as? String == "accepted_memory_fact")
        #expect(recallRelevance["candidateBoundary"] as? String == "reviewable_memory_candidates_excluded")
        #expect(((recallRelevance["sourceRefs"] as? [String]) ?? []).contains("memory_candidate:\(acceptedCandidateID)"))
        #expect((recallRelevance["contextCommands"] as? [String])?.contains("cider-cli item recall-context --item note \(noteID) --json") == true)
        #expect((recallRelevance["verificationCommands"] as? [String])?.contains("cider-cli item memory-facts inspect \(acceptedCandidateID) --json") == true)
        #expect(((recallRelevance["relevanceReasons"] as? [[String: Any]]) ?? []).isEmpty == false)
        let recallReceipt = try #require(recall["actionReceipt"] as? [String: Any])
        #expect(recallReceipt["command"] as? String == "item.recall-context")
        #expect(recallReceipt["readOnly"] as? Bool == true)
        #expect(recallReceipt["changed"] as? Bool == false)
        #expect(recallReceipt["status"] as? String == "succeeded")
        #expect((recallReceipt["matchedSourceRefs"] as? [String])?.contains("note:\(noteID)") == true)
        #expect((recallReceipt["safeCommandRefs"] as? [String])?.contains("cider-cli item context note \(noteID) --json") == true)
        #expect(recallReceipt["truthBoundary"] as? String == "receipt_proves_command_execution_not_memory_truth")
        let reviewable = try #require(recall["reviewableCandidates"] as? [[String: Any]])
        #expect(reviewable.contains { candidate in
            candidate["id"] as? String == suggestedCandidateID
                && candidate["truthState"] as? String == "reviewable_candidate_not_truth"
        })
        #expect(reviewable.contains { $0["id"] as? String == acceptedCandidateID } == false)
    }

    @Test("accepted memory fact selectors return structured failures")
    func acceptedMemoryFactSelectorsReturnStructuredFailures() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-accepted-memory-fact-failures-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let missing = try assertStrictFailureJSON(
            runCLI(args: ["item", "memory-facts", "inspect", "missing-memory-fact", "--json"], vault: vault),
            command: "item.memory-facts.inspect",
            errorCode: "accepted_memory_fact_not_found"
        )
        #expect(missing["readOnly"] as? Bool == true)
        #expect(missing["changed"] as? Bool == false)
        let missingReceipt = try #require(missing["actionReceipt"] as? [String: Any])
        #expect(missingReceipt["command"] as? String == "item.memory-facts.inspect")
        #expect(missingReceipt["readOnly"] as? Bool == true)
        #expect(missingReceipt["changed"] as? Bool == false)
        #expect(missingReceipt["status"] as? String == "failed")
        #expect(missingReceipt["errorCode"] as? String == "accepted_memory_fact_not_found")
        #expect(missingReceipt["truthBoundary"] as? String == "receipt_proves_command_execution_not_memory_truth")
        let selector = try #require(missing["selector"] as? [String: Any])
        #expect(selector["candidateID"] as? String == "missing-memory-fact")

        let noteID = try createNote(title: "Unaccepted Memory Source", content: "Candidate only.", vault: vault)
        let candidatePayload = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "memory-suggest", "note", noteID,
                "--kind", "preference",
                "--value", "Candidate only memory",
                "--evidence", "Candidate only.",
                "--json",
            ], vault: vault),
            command: "item.memory-suggest"
        )
        let candidate = try #require(candidatePayload["candidate"] as? [String: Any])
        let candidateID = try #require(candidate["id"] as? String)
        let unaccepted = try assertStrictFailureJSON(
            runCLI(args: ["item", "memory-facts", "inspect", candidateID, "--json"], vault: vault),
            command: "item.memory-facts.inspect",
            errorCode: "memory_candidate_not_accepted"
        )
        #expect(unaccepted["reviewState"] as? String == "suggested")
        let unacceptedReceipt = try #require(unaccepted["actionReceipt"] as? [String: Any])
        #expect(unacceptedReceipt["command"] as? String == "item.memory-facts.inspect")
        #expect(unacceptedReceipt["status"] as? String == "failed")
        #expect(unacceptedReceipt["errorCode"] as? String == "memory_candidate_not_accepted")
        #expect((unaccepted["safeNextCommands"] as? [String])?.contains("cider-cli capture review-queue --kind memory_candidate --json") == true)
    }

    @Test("accepted memory fact resurfacing surfaces accepted truth and excludes reviewable candidates")
    func acceptedMemoryFactResurfacingSurfacesAcceptedTruthAndExcludesReviewableCandidates() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-accepted-memory-resurface-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let noteID = try createNote(title: "Memory Resurface Source", content: "Erik wants follow-up hooks for accepted memory facts.", vault: vault)
        let acceptedPayload = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "memory-suggest", "note", noteID,
                "--kind", "agent_lesson",
                "--value", "Accepted memory facts need follow-up hooks",
                "--evidence", "Erik wants follow-up hooks for accepted memory facts.",
                "--memory-key", "cid507.accepted-memory.resurface",
                "--confidence", "0.94",
                "--json",
            ], vault: vault),
            command: "item.memory-suggest"
        )
        let acceptedCandidate = try #require(acceptedPayload["candidate"] as? [String: Any])
        let acceptedID = try #require(acceptedCandidate["id"] as? String)
        try seedCoordinatorExactEvidence(candidateIDs: [acceptedID], vault: vault)
        let reviewablePayload = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "memory-suggest", "note", noteID,
                "--kind", "pattern",
                "--value", "Reviewable memory should not resurface as truth",
                "--evidence", "Still only a suggestion.",
                "--json",
            ], vault: vault),
            command: "item.memory-suggest"
        )
        let reviewableCandidate = try #require(reviewablePayload["candidate"] as? [String: Any])
        let reviewableID = try #require(reviewableCandidate["id"] as? String)
        _ = try assertStrictProcessJSON(
            runCLI(args: ["item", "accept-memory-candidate", acceptedID, "--actor", "cody-test", "--json"], vault: vault),
            command: "item.accept-memory-candidate"
        )

        let relevance = try assertStrictProcessJSON(
            runCLI(args: ["item", "memory-facts", "resurface", "--json"], vault: vault),
            command: "item.memory-facts.resurface"
        )
        #expect(relevance["readOnly"] as? Bool == true)
        #expect(relevance["changed"] as? Bool == false)
        let relevanceReceipt = try #require(relevance["actionReceipt"] as? [String: Any])
        #expect(relevanceReceipt["command"] as? String == "item.memory-facts.resurface")
        #expect(relevanceReceipt["readOnly"] as? Bool == true)
        #expect(relevanceReceipt["changed"] as? Bool == false)
        #expect(relevanceReceipt["status"] as? String == "succeeded")
        #expect((relevanceReceipt["matchedSourceRefs"] as? [String])?.contains("memory_candidate:\(acceptedID)") == true)
        #expect((relevanceReceipt["safeCommandRefs"] as? [String])?.contains("cider-cli item memory-facts inspect \(acceptedID) --json") == true)
        #expect(relevanceReceipt["truthBoundary"] as? String == "receipt_proves_command_execution_not_memory_truth")
        let candidates = try #require(relevance["candidates"] as? [[String: Any]])
        #expect(candidates.contains { candidate in
            candidate["family"] as? String == "accepted_memory_fact"
                && candidate["factRef"] as? String == "accepted_memory_fact:\(acceptedID)"
                && candidate["truthBoundary"] as? String == "accepted_memory_fact"
                && candidate["candidateBoundary"] as? String == "reviewable_memory_candidates_excluded"
                && (candidate["reasonCodes"] as? [String])?.contains("follow_up_relevance") == true
        })
        #expect(candidates.contains { $0["candidateRef"] as? String == "memory_candidate:\(reviewableID)" } == false)
        let surfaced = try #require(candidates.first { $0["factRef"] as? String == "accepted_memory_fact:\(acceptedID)" })
        #expect(surfaced["sourceCitation"] != nil)
        #expect((surfaced["citedEvidence"] as? [[String: Any]])?.isEmpty == false)
        #expect((surfaced["safeVerificationCommands"] as? [String])?.contains("cider-cli item memory-facts inspect \(acceptedID) --json") == true)
        let surfacedRelevance = try #require(surfaced["surfacingRelevance"] as? [String: Any])
        #expect(surfacedRelevance["context"] as? String == "due_to_surface")
        #expect(surfacedRelevance["factRef"] as? String == "accepted_memory_fact:\(acceptedID)")
        #expect(surfacedRelevance["truthBoundary"] as? String == "accepted_memory_fact")
        #expect(surfacedRelevance["candidateBoundary"] as? String == "reviewable_memory_candidates_excluded")
        #expect((surfacedRelevance["verificationCommands"] as? [String])?.contains("cider-cli item memory-facts inspect \(acceptedID) --json") == true)
        #expect(((surfacedRelevance["relevanceReasons"] as? [[String: Any]]) ?? []).contains { $0["kind"] as? String == "follow_up_relevance" })

        let due = try assertStrictProcessJSON(
            runCLI(args: ["item", "due-to-surface", "--limit", "10", "--stale-after-days", "999", "--json"], vault: vault),
            command: "item.due-to-surface"
        )
        let dueReceipt = try #require(due["actionReceipt"] as? [String: Any])
        #expect(dueReceipt["command"] as? String == "item.due-to-surface")
        #expect(dueReceipt["readOnly"] as? Bool == true)
        #expect(dueReceipt["changed"] as? Bool == false)
        #expect(dueReceipt["status"] as? String == "succeeded")
        #expect((dueReceipt["matchedSourceRefs"] as? [String])?.contains("memory_candidate:\(acceptedID)") == true)
        #expect((dueReceipt["safeCommandRefs"] as? [String])?.contains("cider-cli item memory-facts inspect \(acceptedID) --json") == true)
        let dueCandidates = try #require(due["candidates"] as? [[String: Any]])
        let dueAccepted = try #require(dueCandidates.first { $0["family"] as? String == "accepted_memory_fact" && $0["factRef"] as? String == "accepted_memory_fact:\(acceptedID)" })
        let dueRelevance = try #require(dueAccepted["surfacingRelevance"] as? [String: Any])
        #expect(dueRelevance["truthBoundary"] as? String == "accepted_memory_fact")
        #expect((dueRelevance["contextCommands"] as? [String])?.contains("cider-cli item recall-context --item note \(noteID) --json") == true)
        #expect(dueCandidates.contains { $0["candidateRef"] as? String == "memory_candidate:\(reviewableID)" && $0["family"] as? String == "accepted_memory_fact" } == false)
    }

    @Test("accepted memory fact resurfacing selectors return structured failures")
    func acceptedMemoryFactResurfacingSelectorsReturnStructuredFailures() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-accepted-memory-resurface-failure-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let missing = try assertStrictFailureJSON(
            runCLI(args: ["item", "memory-facts", "resurface", "--fact", "missing-resurface-fact", "--json"], vault: vault),
            command: "item.memory-facts.resurface",
            errorCode: "accepted_memory_fact_not_found"
        )
        #expect(missing["readOnly"] as? Bool == true)
        #expect(missing["changed"] as? Bool == false)
        let missingReceipt = try #require(missing["actionReceipt"] as? [String: Any])
        #expect(missingReceipt["command"] as? String == "item.memory-facts.resurface")
        #expect(missingReceipt["status"] as? String == "failed")
        #expect(missingReceipt["errorCode"] as? String == "accepted_memory_fact_not_found")

        let badLimit = try assertStrictFailureJSON(
            runCLI(args: ["item", "memory-facts", "resurface", "--limit", "not-a-number", "--json"], vault: vault),
            command: "item.memory-facts.resurface",
            errorCode: "malformed_numeric_filter"
        )
        let filter = try #require(badLimit["filter"] as? [String: Any])
        #expect(filter["name"] as? String == "limit")
    }

    @Test("accepted memory fact action intents are read-only and referenced by resurfacing")
    func acceptedMemoryFactActionIntentsAreReadOnlyAndReferencedByResurfacing() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-accepted-memory-intents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let noteID = try createNote(title: "Memory Intent Source", content: "Accepted memory facts should suggest safe next actions.", vault: vault)
        let suggested = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "memory-suggest", "note", noteID,
                "--kind", "agent_lesson",
                "--value", "Accepted memory facts should suggest safe next actions",
                "--evidence", "Accepted memory facts should suggest safe next actions.",
                "--memory-key", "cid507.accepted-memory.action-intent",
                "--confidence", "0.96",
                "--json",
            ], vault: vault),
            command: "item.memory-suggest"
        )
        let candidate = try #require(suggested["candidate"] as? [String: Any])
        let acceptedID = try #require(candidate["id"] as? String)
        try seedCoordinatorExactEvidence(candidateIDs: [acceptedID], vault: vault)
        _ = try assertStrictProcessJSON(
            runCLI(args: ["item", "accept-memory-candidate", acceptedID, "--actor", "cody-test", "--json"], vault: vault),
            command: "item.accept-memory-candidate"
        )

        let intentsPayload = try assertStrictProcessJSON(
            runCLI(args: ["item", "memory-facts", "intents", "--fact", acceptedID, "--json"], vault: vault),
            command: "item.memory-facts.intents"
        )
        #expect(intentsPayload["readOnly"] as? Bool == true)
        #expect(intentsPayload["changed"] as? Bool == false)
        #expect(intentsPayload["truthBoundary"] as? String == "accepted_memory_fact")
        #expect(intentsPayload["candidateBoundary"] as? String == "reviewable_memory_candidates_excluded")
        let receipt = try #require(intentsPayload["actionReceipt"] as? [String: Any])
        #expect(receipt["command"] as? String == "item.memory-facts.intents")
        #expect(receipt["action"] as? String == "propose_action_intents")
        #expect(receipt["readOnly"] as? Bool == true)
        #expect(receipt["changed"] as? Bool == false)
        let intents = try #require(intentsPayload["intents"] as? [[String: Any]])
        let intent = try #require(intents.first)
        #expect(intent["factRef"] as? String == "accepted_memory_fact:\(acceptedID)")
        #expect(intent["candidateRef"] as? String == "memory_candidate:\(acceptedID)")
        #expect(intent["intentType"] as? String == "follow_up_review")
        #expect(intent["sourceCitation"] != nil)
        #expect(intent["reason"] != nil)
        #expect(intent["proposedCommandFamily"] as? String == "recall_context")
        #expect(intent["requiresConfirmation"] as? Bool == true)
        #expect(intent["mutationBoundary"] as? String == "read_only_intent_no_mutation")
        #expect((intent["safeVerificationCommands"] as? [String])?.contains("cider-cli item memory-facts inspect \(acceptedID) --json") == true)

        let due = try assertStrictProcessJSON(
            runCLI(args: ["item", "due-to-surface", "--limit", "10", "--stale-after-days", "999", "--json"], vault: vault),
            command: "item.due-to-surface"
        )
        let dueCandidates = try #require(due["candidates"] as? [[String: Any]])
        let surfaced = try #require(dueCandidates.first { $0["factRef"] as? String == "accepted_memory_fact:\(acceptedID)" })
        let intentRefs = try #require(surfaced["actionIntentRefs"] as? [String])
        #expect(intentRefs.contains("accepted_memory_fact_action_intent:\(acceptedID):follow_up_review"))
    }

    @Test("accepted memory fact action intent selectors return structured no-op and failures")
    func acceptedMemoryFactActionIntentSelectorsReturnStructuredNoOpAndFailures() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-accepted-memory-intents-failures-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let empty = try assertStrictProcessJSON(
            runCLI(args: ["item", "memory-facts", "intents", "--json"], vault: vault),
            command: "item.memory-facts.intents"
        )
        #expect(empty["status"] as? String == "no_op")
        #expect(empty["errorCode"] as? String == "no_action_intents")
        #expect(empty["readOnly"] as? Bool == true)
        #expect(empty["changed"] as? Bool == false)

        let missing = try assertStrictFailureJSON(
            runCLI(args: ["item", "memory-facts", "intents", "--fact", "missing-intent-fact", "--json"], vault: vault),
            command: "item.memory-facts.intents",
            errorCode: "accepted_memory_fact_not_found"
        )
        #expect(missing["readOnly"] as? Bool == true)
        #expect(missing["changed"] as? Bool == false)

        let badLimit = try assertStrictFailureJSON(
            runCLI(args: ["item", "memory-facts", "intents", "--limit", "nope", "--json"], vault: vault),
            command: "item.memory-facts.intents",
            errorCode: "malformed_numeric_filter"
        )
        let filter = try #require(badLimit["filter"] as? [String: Any])
        #expect(filter["name"] as? String == "limit")
    }

    @Test("accepted memory follow-up proposals create list inspect and lifecycle without side effects")
    func acceptedMemoryFollowUpProposalsCreateListInspectAndLifecycleWithoutSideEffects() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-follow-up-proposals-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let noteID = try createNote(title: "Proposal Source", content: "Accepted memory follow-up proposals must stay reviewable.", vault: vault)
        let suggested = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "memory-suggest", "note", noteID,
                "--kind", "agent_lesson",
                "--value", "Accepted memory follow-up proposals must stay reviewable",
                "--evidence", "Accepted memory follow-up proposals must stay reviewable.",
                "--memory-key", "cid507.follow-up.proposals",
                "--confidence", "0.97",
                "--json",
            ], vault: vault),
            command: "item.memory-suggest"
        )
        let candidate = try #require(suggested["candidate"] as? [String: Any])
        let acceptedID = try #require(candidate["id"] as? String)
        try seedCoordinatorExactEvidence(candidateIDs: [acceptedID], vault: vault)
        _ = try assertStrictProcessJSON(
            runCLI(args: ["item", "accept-memory-candidate", acceptedID, "--actor", "cody-test", "--json"], vault: vault),
            command: "item.accept-memory-candidate"
        )

        let created = try assertStrictProcessJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "create", "--fact", acceptedID, "--actor", "cody-test", "--json"], vault: vault),
            command: "item.memory-facts.proposals.create"
        )
        #expect(created["readOnly"] as? Bool == false)
        #expect(created["changed"] as? Bool == true)
        #expect(created["mutationBoundary"] as? String == "proposal_record_only_no_external_mutation")
        let proposal = try #require(created["proposal"] as? [String: Any])
        let proposalID = try #require(proposal["proposalID"] as? String)
        #expect(proposal["status"] as? String == "suggested")
        #expect(proposal["truthBoundary"] as? String == "reviewable_follow_up_proposal_not_truth")
        #expect(proposal["factRef"] as? String == "accepted_memory_fact:\(acceptedID)")
        #expect(proposal["createsReminder"] as? Bool == false)
        #expect(proposal["createsTodo"] as? Bool == false)
        #expect(proposal["createsLink"] as? Bool == false)
        #expect(proposal["createsNag"] as? Bool == false)
        let receipt = try #require(created["actionReceipt"] as? [String: Any])
        #expect(receipt["command"] as? String == "item.memory-facts.proposals.create")
        #expect(receipt["action"] as? String == "create_follow_up_proposal")
        #expect(receipt["truthBoundary"] as? String == "action_receipt_not_fact_truth")

        let listed = try assertStrictProcessJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "list", "--json"], vault: vault),
            command: "item.memory-facts.proposals.list"
        )
        let proposals = try #require(listed["proposals"] as? [[String: Any]])
        #expect(proposals.contains { $0["proposalID"] as? String == proposalID })

        let inspected = try assertStrictProcessJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "inspect", proposalID, "--json"], vault: vault),
            command: "item.memory-facts.proposals.inspect"
        )
        #expect((inspected["proposal"] as? [String: Any])?["proposalRef"] as? String == "follow_up_proposal:\(proposalID)")

        let due = try assertStrictProcessJSON(
            runCLI(args: ["item", "due-to-surface", "--limit", "20", "--stale-after-days", "999", "--json"], vault: vault),
            command: "item.due-to-surface"
        )
        let dueCandidates = try #require(due["candidates"] as? [[String: Any]])
        let dueProposal = try #require(dueCandidates.first { $0["family"] as? String == "review_item" && ($0["sourceRefs"] as? [String])?.contains("follow_up_proposal:\(proposalID)") == true })
        #expect((dueProposal["safeNextCommands"] as? [String])?.contains("cider-cli item memory-facts proposals preview \(proposalID) --json") == true)

        let accepted = try assertStrictProcessJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "accept", proposalID, "--actor", "cody-test", "--json"], vault: vault),
            command: "item.memory-facts.proposals.accept"
        )
        let acceptedProposal = try #require(accepted["proposal"] as? [String: Any])
        #expect(acceptedProposal["status"] as? String == "accepted")
        #expect(acceptedProposal["createsReminder"] as? Bool == false)
        #expect(acceptedProposal["createsTodo"] as? Bool == false)
        #expect(acceptedProposal["createsLink"] as? Bool == false)
        #expect(acceptedProposal["createsNag"] as? Bool == false)
    }

    @Test("accepted memory follow-up proposal execution preview is dry run and non mutating")
    func acceptedMemoryFollowUpProposalExecutionPreviewIsDryRunAndNonMutating() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-follow-up-preview-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let noteID = try createNote(title: "Preview Source", content: "Accepted proposals need preview before acting.", vault: vault)
        let suggested = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "memory-suggest", "note", noteID,
                "--kind", "agent_lesson",
                "--value", "Accepted proposals need preview before acting",
                "--evidence", "Accepted proposals need preview before acting.",
                "--memory-key", "cid541.preview",
                "--confidence", "0.97",
                "--json",
            ], vault: vault),
            command: "item.memory-suggest"
        )
        let candidate = try #require(suggested["candidate"] as? [String: Any])
        let acceptedID = try #require(candidate["id"] as? String)
        try seedCoordinatorExactEvidence(candidateIDs: [acceptedID], vault: vault)
        _ = try assertStrictProcessJSON(
            runCLI(args: ["item", "accept-memory-candidate", acceptedID, "--actor", "cody-test", "--json"], vault: vault),
            command: "item.accept-memory-candidate"
        )
        let created = try assertStrictProcessJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "create", "--fact", acceptedID, "--actor", "cody-test", "--json"], vault: vault),
            command: "item.memory-facts.proposals.create"
        )
        let createdProposal = try #require(created["proposal"] as? [String: Any])
        let proposalID = try #require(createdProposal["proposalID"] as? String)
        _ = try assertStrictProcessJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "accept", proposalID, "--actor", "cody-test", "--json"], vault: vault),
            command: "item.memory-facts.proposals.accept"
        )

        let preview = try assertStrictProcessJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "preview", proposalID, "--json"], vault: vault),
            command: "item.memory-facts.proposals.preview"
        )
        #expect(preview["readOnly"] as? Bool == true)
        #expect(preview["changed"] as? Bool == false)
        #expect(preview["truthBoundary"] as? String == "execution_preview_not_truth")
        #expect(preview["executionBoundary"] as? String == "dry_run_preview_not_execution")
        let previewBody = try #require(preview["executionPreview"] as? [String: Any])
        #expect(previewBody["proposalRef"] as? String == "follow_up_proposal:\(proposalID)")
        #expect(previewBody["mappedCommandFamily"] as? String == "recall_context")
        #expect(previewBody["mappedCommand"] as? String == "cider-cli item recall-context --item note \(noteID) --json")
        #expect(previewBody["dryRun"] as? Bool == true)
        #expect(previewBody["wouldExecute"] as? Bool == false)
        #expect(previewBody["requiresConfirmation"] as? Bool == true)
        #expect(previewBody["predictedMutationType"] as? String == "none_read_only_context_review")
        #expect(previewBody["createsReminder"] as? Bool == false)
        #expect(previewBody["createsTodo"] as? Bool == false)
        #expect(previewBody["createsLink"] as? Bool == false)
        #expect(previewBody["createsNag"] as? Bool == false)
        let receipt = try #require(preview["actionReceipt"] as? [String: Any])
        #expect(receipt["command"] as? String == "item.memory-facts.proposals.preview")
        #expect(receipt["action"] as? String == "preview_follow_up_proposal_execution")
        #expect(receipt["readOnly"] as? Bool == true)
        #expect(receipt["changed"] as? Bool == false)
        #expect(receipt["truthBoundary"] as? String == "action_receipt_not_fact_truth")

        let inspected = try assertStrictProcessJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "inspect", proposalID, "--json"], vault: vault),
            command: "item.memory-facts.proposals.inspect"
        )
        let inspectedProposal = try #require(inspected["proposal"] as? [String: Any])
        #expect(inspectedProposal["status"] as? String == "accepted")
        #expect(inspectedProposal["createsReminder"] as? Bool == false)
        #expect(inspectedProposal["createsTodo"] as? Bool == false)
        #expect(inspectedProposal["createsLink"] as? Bool == false)
        #expect(inspectedProposal["createsNag"] as? Bool == false)
    }

    @Test("accepted memory follow-up proposal execution requires confirmation before running safe command")
    func acceptedMemoryFollowUpProposalExecutionRequiresConfirmationBeforeRunningSafeCommand() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-follow-up-execution-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let noteID = try createNote(title: "Execution Source", content: "Confirmed execution should run only after explicit token.", vault: vault)
        let suggested = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "memory-suggest", "note", noteID,
                "--kind", "agent_lesson",
                "--value", "Confirmed execution should run only after explicit token",
                "--evidence", "Confirmed execution should run only after explicit token.",
                "--memory-key", "cid542.execute",
                "--confidence", "0.97",
                "--json",
            ], vault: vault),
            command: "item.memory-suggest"
        )
        let candidate = try #require(suggested["candidate"] as? [String: Any])
        let acceptedID = try #require(candidate["id"] as? String)
        try seedCoordinatorExactEvidence(candidateIDs: [acceptedID], vault: vault)
        _ = try assertStrictProcessJSON(
            runCLI(args: ["item", "accept-memory-candidate", acceptedID, "--actor", "cody-test", "--json"], vault: vault),
            command: "item.accept-memory-candidate"
        )
        let created = try assertStrictProcessJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "create", "--fact", acceptedID, "--actor", "cody-test", "--json"], vault: vault),
            command: "item.memory-facts.proposals.create"
        )
        let proposalID = try #require((created["proposal"] as? [String: Any])?["proposalID"] as? String)
        _ = try assertStrictProcessJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "accept", proposalID, "--actor", "cody-test", "--json"], vault: vault),
            command: "item.memory-facts.proposals.accept"
        )

        let refused = try assertStrictFailureJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "execute", proposalID, "--json"], vault: vault),
            command: "item.memory-facts.proposals.execute",
            errorCode: "follow_up_execution_confirmation_required"
        )
        #expect(refused["readOnly"] as? Bool == true)
        #expect(refused["changed"] as? Bool == false)
        let refusedDetails = try #require(refused["details"] as? [String: Any])
        #expect(refusedDetails["executionBoundary"] as? String == "dry_run_preview_not_execution")
        let refusedPreview = try #require(refusedDetails["executionPreview"] as? [String: Any])
        #expect(refusedPreview["dryRun"] as? Bool == true)
        #expect(refusedPreview["wouldExecute"] as? Bool == false)
        #expect(refusedPreview["createsReminder"] as? Bool == false)
        #expect(refusedPreview["createsTodo"] as? Bool == false)
        #expect(refusedPreview["createsLink"] as? Bool == false)
        #expect(refusedPreview["createsNag"] as? Bool == false)

        let executed = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "memory-facts", "proposals", "execute", proposalID,
                "--confirm-execution",
                "--confirmation-token", "execute:\(proposalID)",
                "--json",
            ], vault: vault),
            command: "item.memory-facts.proposals.execute"
        )
        #expect(executed["readOnly"] as? Bool == true)
        #expect(executed["changed"] as? Bool == false)
        #expect(executed["executionBoundary"] as? String == "confirmed_existing_safe_command_execution")
        #expect(executed["mutationBoundary"] as? String == "existing_safe_command_read_only_execution")
        #expect(executed["truthBoundary"] as? String == "execution_result_not_memory_truth")
        let executionResult = try #require(executed["executionResult"] as? [String: Any])
        #expect(executionResult["mappedCommandFamily"] as? String == "recall_context")
        #expect(executionResult["mappedCommand"] as? String == "cider-cli item recall-context --item note \(noteID) --json")
        #expect(executionResult["readOnly"] as? Bool == true)
        #expect(executionResult["changed"] as? Bool == false)
        #expect((executionResult["result"] as? [String: Any])?["command"] as? String == "item.recall-context")
        #expect(executionResult["createsReminder"] as? Bool == false)
        #expect(executionResult["createsTodo"] as? Bool == false)
        #expect(executionResult["createsLink"] as? Bool == false)
        #expect(executionResult["createsNag"] as? Bool == false)
        let receipt = try #require(executed["actionReceipt"] as? [String: Any])
        #expect(receipt["action"] as? String == "execute_follow_up_proposal")
        #expect(receipt["truthBoundary"] as? String == "action_receipt_not_fact_truth")
        #expect(receipt["outcomeBoundary"] as? String == "command_outcome_not_memory_truth")
    }

    @Test("accepted memory follow-up proposal lifecycle and execution receipts persist to ledger and context")
    func acceptedMemoryFollowUpProposalLifecycleAndExecutionReceiptsPersistToLedgerAndContext() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-follow-up-ledger-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let noteID = try createNote(title: "Proposal Ledger Source", content: "Durable proposal receipts should explain the follow-up lifecycle.", vault: vault)
        let suggested = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "memory-suggest", "note", noteID,
                "--kind", "agent_lesson",
                "--value", "Durable proposal receipts should explain the follow-up lifecycle",
                "--evidence", "Durable proposal receipts should explain the follow-up lifecycle.",
                "--memory-key", "cid615.proposal.ledger",
                "--confidence", "0.97",
                "--json",
            ], vault: vault),
            command: "item.memory-suggest"
        )
        let acceptedID = try #require((suggested["candidate"] as? [String: Any])?["id"] as? String)
        try seedCoordinatorExactEvidence(candidateIDs: [acceptedID], vault: vault)
        _ = try assertStrictProcessJSON(
            runCLI(args: ["item", "accept-memory-candidate", acceptedID, "--actor", "cody-test", "--json"], vault: vault),
            command: "item.accept-memory-candidate"
        )

        let created = try assertStrictProcessJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "create", "--fact", acceptedID, "--actor", "cody-test", "--json"], vault: vault),
            command: "item.memory-facts.proposals.create"
        )
        let proposalID = try #require((created["proposal"] as? [String: Any])?["proposalID"] as? String)
        let proposalRef = "follow_up_proposal:\(proposalID)"
        let factRef = "accepted_memory_fact:\(acceptedID)"
        let createReceipt = try #require(created["actionReceipt"] as? [String: Any])
        #expect((createReceipt["sourceRefs"] as? [String])?.contains(proposalRef) == true)
        #expect((createReceipt["sourceRefs"] as? [String])?.contains(factRef) == true)

        _ = try assertStrictProcessJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "accept", proposalID, "--actor", "cody-test", "--json"], vault: vault),
            command: "item.memory-facts.proposals.accept"
        )
        _ = try assertStrictProcessJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "preview", proposalID, "--json"], vault: vault),
            command: "item.memory-facts.proposals.preview"
        )
        _ = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "memory-facts", "proposals", "execute", proposalID,
                "--confirm-execution",
                "--confirmation-token", "execute:\(proposalID)",
                "--json",
            ], vault: vault),
            command: "item.memory-facts.proposals.execute"
        )

        let ledgerByProposal = try assertStrictProcessJSON(
            runCLI(args: ["item", "action-ledger", "list", "--owner", "note:\(noteID)", "--source-ref", proposalRef, "--limit", "20", "--json"], vault: vault),
            command: "item.action-ledger.list"
        )
        let entries = try #require(ledgerByProposal["entries"] as? [[String: Any]])
        #expect(entries.contains { entry in
            entry["command"] as? String == "item.memory-facts.proposals.create"
                && entry["action"] as? String == "create_follow_up_proposal"
                && entry["changed"] as? Bool == true
                && (entry["sourceRefs"] as? [String])?.contains(factRef) == true
        })
        #expect(entries.contains { entry in
            entry["command"] as? String == "item.memory-facts.proposals.accept"
                && entry["action"] as? String == "accept_follow_up_proposal"
                && entry["changed"] as? Bool == true
        })
        #expect(entries.contains { entry in
            entry["command"] as? String == "item.memory-facts.proposals.preview"
                && entry["action"] as? String == "preview_follow_up_proposal_execution"
                && entry["readOnly"] as? Bool == true
                && entry["changed"] as? Bool == false
        })
        #expect(entries.contains { entry in
            entry["command"] as? String == "item.memory-facts.proposals.execute"
                && entry["action"] as? String == "execute_follow_up_proposal"
                && entry["readOnly"] as? Bool == true
                && entry["changed"] as? Bool == false
        })

        let previewLedger = try assertStrictProcessJSON(
            runCLI(args: ["item", "action-ledger", "list", "--command", "item.memory-facts.proposals.preview", "--source-ref", proposalRef, "--json"], vault: vault),
            command: "item.action-ledger.list"
        )
        #expect((previewLedger["entries"] as? [[String: Any]])?.isEmpty == false)

        let inspectedEntryID = try #require(entries.first { $0["command"] as? String == "item.memory-facts.proposals.execute" }?["id"] as? String)
        let inspectedLedger = try assertStrictProcessJSON(
            runCLI(args: ["item", "action-ledger", "inspect", inspectedEntryID, "--json"], vault: vault),
            command: "item.action-ledger.inspect"
        )
        let inspectedEntry = try #require(inspectedLedger["entry"] as? [String: Any])
        #expect((inspectedEntry["sourceRefs"] as? [String])?.contains(proposalRef) == true)
        #expect((inspectedEntry["safeVerificationCommands"] as? [String])?.contains("cider-cli item recall-context --item note \(noteID) --json") == true)

        let context = try assertStrictProcessJSON(
            runCLI(args: ["item", "context", "note", noteID, "--max-history", "20", "--json"], vault: vault),
            command: "item.context"
        )
        let recentHistory = try #require(context["recentHistory"] as? [[String: Any]])
        #expect(recentHistory.contains { history in
            history["kind"] as? String == "action_receipt"
                && history["command"] as? String == "item.memory-facts.proposals.execute"
                && (history["sourceRefs"] as? [String])?.contains(proposalRef) == true
        })

        let recall = try assertStrictProcessJSON(
            runCLI(args: ["item", "recall-context", "--item", "note", noteID, "--history-limit", "20", "--action-history-source-ref", proposalRef, "--json"], vault: vault),
            command: "item.recall-context"
        )
        let actionHistory = try #require(recall["actionHistory"] as? [[String: Any]])
        #expect(actionHistory.contains { history in
            history["kind"] as? String == "action_receipt"
                && history["command"] as? String == "item.memory-facts.proposals.create"
                && history["truthBoundary"] as? String == "action_receipt_not_fact_truth"
        })
    }

    @Test("accepted memory follow-up proposal confirmation failures persist structured receipts")
    func acceptedMemoryFollowUpProposalConfirmationFailuresPersistStructuredReceipts() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-follow-up-failure-ledger-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let noteID = try createNote(title: "Proposal Failure Ledger Source", content: "Confirmation failures should be durable action history.", vault: vault)
        let suggested = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "memory-suggest", "note", noteID,
                "--kind", "agent_lesson",
                "--value", "Confirmation failures should be durable action history",
                "--evidence", "Confirmation failures should be durable action history.",
                "--memory-key", "cid615.proposal.failure",
                "--confidence", "0.97",
                "--json",
            ], vault: vault),
            command: "item.memory-suggest"
        )
        let acceptedID = try #require((suggested["candidate"] as? [String: Any])?["id"] as? String)
        try seedCoordinatorExactEvidence(candidateIDs: [acceptedID], vault: vault)
        _ = try assertStrictProcessJSON(
            runCLI(args: ["item", "accept-memory-candidate", acceptedID, "--actor", "cody-test", "--json"], vault: vault),
            command: "item.accept-memory-candidate"
        )
        let created = try assertStrictProcessJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "create", "--fact", acceptedID, "--json"], vault: vault),
            command: "item.memory-facts.proposals.create"
        )
        let proposalID = try #require((created["proposal"] as? [String: Any])?["proposalID"] as? String)
        _ = try assertStrictProcessJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "accept", proposalID, "--json"], vault: vault),
            command: "item.memory-facts.proposals.accept"
        )

        let refused = try assertStrictFailureJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "execute", proposalID, "--json"], vault: vault),
            command: "item.memory-facts.proposals.execute",
            errorCode: "follow_up_execution_confirmation_required"
        )
        let details = try #require(refused["details"] as? [String: Any])
        let receipt = try #require(details["actionReceipt"] as? [String: Any])
        #expect(receipt["status"] as? String == "failed")
        #expect(receipt["errorCode"] as? String == "follow_up_execution_confirmation_required")
        #expect(receipt["readOnly"] as? Bool == true)
        #expect(receipt["changed"] as? Bool == false)
        #expect((receipt["sourceRefs"] as? [String])?.contains("follow_up_proposal:\(proposalID)") == true)

        let ledger = try assertStrictProcessJSON(
            runCLI(args: ["item", "action-ledger", "list", "--owner", "note:\(noteID)", "--status", "failed", "--source-ref", "follow_up_proposal:\(proposalID)", "--json"], vault: vault),
            command: "item.action-ledger.list"
        )
        let entries = try #require(ledger["entries"] as? [[String: Any]])
        #expect(entries.contains { entry in
            entry["command"] as? String == "item.memory-facts.proposals.execute"
                && entry["errorCode"] as? String == "follow_up_execution_confirmation_required"
                && entry["changed"] as? Bool == false
        })
    }

    @Test("accepted memory follow-up proposal execution failures are structured")
    func acceptedMemoryFollowUpProposalExecutionFailuresAreStructured() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-follow-up-execution-failures-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let empty = try assertStrictProcessJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "executions", "--json"], vault: vault),
            command: "item.memory-facts.proposals.executions"
        )
        #expect(empty["status"] as? String == "no_op")
        #expect(empty["readOnly"] as? Bool == true)
        #expect(empty["changed"] as? Bool == false)
        #expect(empty["count"] as? Int == 0)

        let missing = try assertStrictFailureJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "execute", "missing-execution", "--confirm-execution", "--confirmation-token", "execute:missing-execution", "--json"], vault: vault),
            command: "item.memory-facts.proposals.execute",
            errorCode: "follow_up_proposal_not_found"
        )
        #expect(missing["readOnly"] as? Bool == true)
        #expect(missing["changed"] as? Bool == false)

        let noteID = try createNote(title: "Execution Failure Source", content: "Unaccepted execution must fail.", vault: vault)
        let suggested = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "memory-suggest", "note", noteID,
                "--kind", "agent_lesson",
                "--value", "Unaccepted execution must fail",
                "--evidence", "Unaccepted execution must fail.",
                "--memory-key", "cid542.execute.unaccepted",
                "--confidence", "0.97",
                "--json",
            ], vault: vault),
            command: "item.memory-suggest"
        )
        let acceptedID = try #require((suggested["candidate"] as? [String: Any])?["id"] as? String)
        try seedCoordinatorExactEvidence(candidateIDs: [acceptedID], vault: vault)
        _ = try assertStrictProcessJSON(
            runCLI(args: ["item", "accept-memory-candidate", acceptedID, "--actor", "cody-test", "--json"], vault: vault),
            command: "item.accept-memory-candidate"
        )
        let created = try assertStrictProcessJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "create", "--fact", acceptedID, "--actor", "cody-test", "--json"], vault: vault),
            command: "item.memory-facts.proposals.create"
        )
        let proposalID = try #require((created["proposal"] as? [String: Any])?["proposalID"] as? String)
        let unaccepted = try assertStrictFailureJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "execute", proposalID, "--confirm-execution", "--confirmation-token", "execute:\(proposalID)", "--json"], vault: vault),
            command: "item.memory-facts.proposals.execute",
            errorCode: "follow_up_proposal_not_accepted"
        )
        #expect(unaccepted["readOnly"] as? Bool == true)
        #expect(unaccepted["changed"] as? Bool == false)

        var unsupportedOutput = SecondBrainEnrichmentOutput(
            owner: SecondBrainOwnerRef(ownerType: "note", ownerID: noteID),
            kind: SecondBrainFollowUpProposalService.outputKind,
            value: "Unsupported execution mapping",
            normalizedValue: "unsupported-execution-mapping",
            label: "Follow-up proposal",
            evidence: "Unsupported execution mapping.",
            source: "test",
            confidence: 0.5,
            reviewState: "accepted",
            metadata: [
                "proposed_command_family": "unsupported_family",
                "proposed_command": "cider-cli unsupported command --json",
                "confirmation_policy": "explicit_existing_command_required",
                "requires_confirmation": "true",
            ]
        )
        unsupportedOutput.id = "unsupported-execution-proposal"
        let unsupportedProposal = SecondBrainFollowUpProposal(output: unsupportedOutput)
        let unsupportedPreview = SecondBrainFollowUpProposalService.preview(for: unsupportedProposal)
        #expect(throws: SecondBrainFollowUpProposalService.FollowUpProposalError.self) {
            _ = try SecondBrainFollowUpProposalService.executionResult(for: unsupportedPreview, confirmed: true, confirmationToken: "execute:unsupported-execution-proposal")
        }
    }

    @Test("accepted memory follow-up proposal execution preview failures and no op reads are structured")
    func acceptedMemoryFollowUpProposalExecutionPreviewFailuresAndNoOpReadsAreStructured() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-follow-up-preview-failures-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let empty = try assertStrictProcessJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "previews", "--json"], vault: vault),
            command: "item.memory-facts.proposals.previews"
        )
        #expect(empty["status"] as? String == "no_op")
        #expect(empty["readOnly"] as? Bool == true)
        #expect(empty["changed"] as? Bool == false)
        #expect(empty["count"] as? Int == 0)

        let missing = try assertStrictFailureJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "preview", "missing-preview", "--json"], vault: vault),
            command: "item.memory-facts.proposals.preview",
            errorCode: "follow_up_proposal_not_found"
        )
        #expect(missing["readOnly"] as? Bool == true)
        #expect(missing["changed"] as? Bool == false)

        let noteID = try createNote(title: "Unaccepted Preview Source", content: "Unaccepted proposals must not preview as executable.", vault: vault)
        let suggested = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "memory-suggest", "note", noteID,
                "--kind", "agent_lesson",
                "--value", "Unaccepted proposals must not preview as executable",
                "--evidence", "Unaccepted proposals must not preview as executable.",
                "--memory-key", "cid541.preview.unaccepted",
                "--confidence", "0.97",
                "--json",
            ], vault: vault),
            command: "item.memory-suggest"
        )
        let candidate = try #require(suggested["candidate"] as? [String: Any])
        let acceptedID = try #require(candidate["id"] as? String)
        try seedCoordinatorExactEvidence(candidateIDs: [acceptedID], vault: vault)
        _ = try assertStrictProcessJSON(
            runCLI(args: ["item", "accept-memory-candidate", acceptedID, "--actor", "cody-test", "--json"], vault: vault),
            command: "item.accept-memory-candidate"
        )
        let created = try assertStrictProcessJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "create", "--fact", acceptedID, "--actor", "cody-test", "--json"], vault: vault),
            command: "item.memory-facts.proposals.create"
        )
        let proposalID = try #require((created["proposal"] as? [String: Any])?["proposalID"] as? String)
        let unaccepted = try assertStrictFailureJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "preview", proposalID, "--json"], vault: vault),
            command: "item.memory-facts.proposals.preview",
            errorCode: "follow_up_proposal_not_accepted"
        )
        #expect(unaccepted["readOnly"] as? Bool == true)
        #expect(unaccepted["changed"] as? Bool == false)
        #expect((unaccepted["safeNextCommands"] as? [String])?.contains("cider-cli item memory-facts proposals accept \(proposalID) --json") == true)

        let unsupported = try assertStrictFailureJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "bogus-action", proposalID, "--json"], vault: vault),
            command: "item.memory-facts.proposals",
            errorCode: "unsupported_follow_up_proposal_action"
        )
        let unsupportedDetails = try #require(unsupported["details"] as? [String: Any])
        #expect((unsupportedDetails["supportedActions"] as? [String])?.contains("preview") == true)
    }

    @Test("accepted memory follow-up proposal failures and empty reads are structured")
    func acceptedMemoryFollowUpProposalFailuresAndEmptyReadsAreStructured() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-follow-up-proposals-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let empty = try assertStrictProcessJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "list", "--json"], vault: vault),
            command: "item.memory-facts.proposals.list"
        )
        #expect(empty["readOnly"] as? Bool == true)
        #expect(empty["changed"] as? Bool == false)
        #expect(empty["count"] as? Int == 0)

        let missingInspect = try assertStrictFailureJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "inspect", "missing-proposal", "--json"], vault: vault),
            command: "item.memory-facts.proposals.inspect",
            errorCode: "follow_up_proposal_not_found"
        )
        #expect(missingInspect["readOnly"] as? Bool == true)
        #expect(missingInspect["changed"] as? Bool == false)

        let missingFact = try assertStrictFailureJSON(
            runCLI(args: ["item", "memory-facts", "proposals", "create", "--fact", "missing-fact", "--json"], vault: vault),
            command: "item.memory-facts.proposals.create",
            errorCode: "accepted_memory_fact_not_found"
        )
        #expect(missingFact["readOnly"] as? Bool == false)
        #expect(missingFact["changed"] as? Bool == false)
    }

    @Test("link helper failures return structured receipts without mutation")
    func linkHelperFailuresReturnStructuredReceiptsWithoutMutation() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-structured-link-failures-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let unsupported = try assertStrictFailureJSON(
            runCLI(args: ["item", "link", "badtype", "source", "note", "target", "--json"], vault: vault),
            command: "link.add",
            errorCode: "unsupported_item_type"
        )
        #expect(unsupported["readOnly"] as? Bool == false)
        #expect(unsupported["changed"] as? Bool == false)
        #expect((unsupported["supportedTypes"] as? [String])?.contains("note") == true)
        let unsupportedReceipt = try #require(unsupported["actionReceipt"] as? [String: Any])
        #expect(unsupportedReceipt["status"] as? String == "failed")
        #expect(unsupportedReceipt["commandFamily"] as? String == "link")
        #expect(unsupportedReceipt["subcommand"] as? String == "add")
        #expect(unsupportedReceipt["resultStatus"] as? String == "failed")
        #expect(unsupportedReceipt["timestamp"] as? String != nil)
        #expect(unsupportedReceipt["readOnly"] as? Bool == false)
        #expect(unsupportedReceipt["changed"] as? Bool == false)

        let sourceID = try createNote(title: "Failed Link Source", content: "Source should remain unlinked.", vault: vault)
        let backlinksBefore = try assertStrictProcessJSON(
            runCLI(args: ["item", "backlinks", "note", sourceID, "--json"], vault: vault),
            command: "item.backlinks"
        )
        let relationCountBefore = backlinksBefore["relationCount"] as? Int
        let missing = try assertStrictFailureJSON(
            runCLI(args: ["item", "link", "note", sourceID, "note", "missing-target", "--json"], vault: vault),
            command: "link.add",
            errorCode: "item_not_found"
        )
        #expect(missing["readOnly"] as? Bool == false)
        #expect(missing["changed"] as? Bool == false)
        let missingReceipt = try #require(missing["actionReceipt"] as? [String: Any])
        #expect((missingReceipt["sourceRefs"] as? [String])?.contains("note:\(sourceID)") == true)

        let failedLedger = try parseJSONObject(try runCLI(args: ["item", "action-ledger", "list", "--command", "link.add", "--status", "failed", "--json"], vault: vault).stdout)
        let failedEntries = try #require(failedLedger["entries"] as? [[String: Any]])
        #expect(failedEntries.contains { entry in
            entry["command"] as? String == "link.add"
                && entry["commandFamily"] as? String == "link"
                && entry["subcommand"] as? String == "add"
                && entry["resultStatus"] as? String == "failed"
                && entry["readOnly"] as? Bool == false
                && entry["changed"] as? Bool == false
                && (entry["sourceRefs"] as? [String])?.contains("note:\(sourceID)") == true
        })

        let backlinks = try assertStrictProcessJSON(
            runCLI(args: ["item", "backlinks", "note", sourceID, "--json"], vault: vault),
            command: "item.backlinks"
        )
        #expect(backlinks["relationCount"] as? Int == relationCountBefore)
    }

    @Test("recall context action history supports filters windows and selector echo")
    func recallContextActionHistorySupportsFiltersWindowsAndSelectorEcho() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-recall-history-filter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let sourceID = try createNote(title: "Recall History Source", content: "Source", vault: vault)
        let targetID = try createNote(title: "Recall History Target", content: "Target", vault: vault)
        let since = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60))
        _ = try parseJSONObject(try runCLI(args: ["item", "link", "note", sourceID, "note", targetID, "--json"], vault: vault).stdout)
        _ = try parseJSONObject(try runCLI(args: ["item", "why-surfaced", "note", sourceID, "--json"], vault: vault).stdout)
        let before = ISO8601DateFormatter().string(from: Date().addingTimeInterval(60))

        let recall = try assertStrictProcessJSON(
            runCLI(args: [
                "item", "recall-context", "--item", "note", sourceID,
                "--history-command", "link.add",
                "--history-status", "succeeded",
                "--history-evidence-ref", "note:\(targetID)",
                "--history-since", since,
                "--history-before", before,
                "--history-limit", "1",
                "--json",
            ], vault: vault),
            command: "item.recall-context"
        )
        let filters = try #require(recall["actionHistoryFilters"] as? [String: Any])
        #expect(filters["command"] as? String == "link.add")
        #expect(filters["status"] as? String == "succeeded")
        #expect(filters["evidenceRef"] as? String == "note:\(targetID)")
        #expect(filters["since"] as? String == since)
        #expect(filters["before"] as? String == before)
        #expect(filters["limit"] as? Int == 1)
        let history = try #require(recall["actionHistory"] as? [[String: Any]])
        #expect(history.count == 1)
        #expect(history.first?["command"] as? String == "link.add")
        #expect(history.first?["status"] as? String == "succeeded")
        #expect((history.first?["evidenceRefs"] as? [String])?.contains("note:\(targetID)") == true)
        #expect(history.first?["truthBoundary"] as? String == "action_receipt_not_fact_truth")
    }

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

    @Test("top level project artifact help is discoverable and side effect free")
    func topLevelProjectArtifactHelpIsDiscoverableAndSideEffectFree() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-project-artifact-help-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let before = try vaultRelativeFileList(vault)
        let result = try runCLI(args: ["project-artifact", "--help"], vault: vault)
        let after = try vaultRelativeFileList(vault)

        #expect(result.status == 0)
        #expect(result.stdout.contains("Project artifact commands:"))
        #expect(result.stdout.contains("cider-cli project-artifact create"))
        #expect(result.stdout.contains("cider-cli project-artifact list"))
        #expect(result.stdout.contains("Compatibility: cider-cli note project-artifact"))
        #expect(after == before)

        let beforeSubcommandHelp = try vaultRelativeFileList(vault)
        let subcommandHelp = try runCLI(args: ["project-artifact", "create", "--help"], vault: vault)
        let afterSubcommandHelp = try vaultRelativeFileList(vault)

        #expect(subcommandHelp.status == 0)
        #expect(subcommandHelp.stdout.contains("cider-cli project-artifact create"))
        #expect(afterSubcommandHelp == beforeSubcommandHelp)
    }

    @Test("root help advertises top level project artifact namespace")
    func rootHelpAdvertisesTopLevelProjectArtifactNamespace() throws {
        let result = try runCLI(args: ["help"])

        #expect(result.status == 0)
        #expect(result.stdout.contains("PROJECT ARTIFACT"))
        #expect(result.stdout.contains("cider-cli project-artifact create"))
        #expect(result.stdout.contains("cider-cli project-artifact get <note-id-prefix> [--json]"))
    }

    @Test("top level project artifact namespace delegates to project artifact implementation")
    func topLevelProjectArtifactNamespaceDelegatesToProjectArtifactImplementation() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-project-artifact-flow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let create = try parseJSONObject(try runCLI(args: [
            "project-artifact", "create",
            "--project", "cider",
            "--type", "qa",
            "--title", "Top Level Artifact QA",
            "--content", "Initial finding.",
            "--json",
        ], vault: vault).stdout)
        #expect(create["ok"] as? Bool == true)
        #expect(create["command"] as? String == "project-artifact.create")
        #expect(create["compatibilityAlias"] as? String == "note.project-artifact.create")
        let artifactID = try #require(create["id"] as? String)

        let list = try parseJSONObject(try runCLI(args: [
            "project-artifact", "list",
            "--project", "cider",
            "--json",
        ], vault: vault).stdout)
        #expect(list["ok"] as? Bool == true)
        #expect(list["command"] as? String == "project-artifact.list")
        let notes = try #require(list["notes"] as? [[String: Any]])
        #expect(notes.map { $0["id"] as? String }.contains(artifactID))

        let get = try parseJSONObject(try runCLI(args: [
            "project-artifact", "get", artifactID,
            "--json",
        ], vault: vault).stdout)
        #expect(get["command"] as? String == "project-artifact.get")
        #expect(get["content"] as? String == "Initial finding.")

        let append = try parseJSONObject(try runCLI(args: [
            "project-artifact", "append", artifactID,
            "--content", "Follow-up evidence.",
            "--json",
        ], vault: vault).stdout)
        #expect(append["ok"] as? Bool == true)
        #expect(append["command"] as? String == "project-artifact.append")
        #expect((append["content"] as? String)?.contains("Initial finding.\n\nFollow-up evidence.") == true)

        let legacyGet = try parseJSONObject(try runCLI(args: [
            "note", "project-artifact", "get", artifactID,
            "--json",
        ], vault: vault).stdout)
        #expect(legacyGet["command"] as? String == "note.project-artifact.get")
        #expect((legacyGet["content"] as? String)?.contains("Follow-up evidence.") == true)
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
            metadata: [
                "artifactType": "note",
                "candidate_id": "candidate-123",
                "candidate_ref": "graph_candidate:candidate-123",
                "mention_text": "Cider Project Note",
                "source_kind": "journal",
                "source_quote": "Project note belongs to Cider.",
            ]
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
            actionReceipts: [],
            enrichmentOutputs: [],
            relationCandidates: [],
            captureProvenance: []
        )

        let dict = CiderCLI.itemContextBundleToDict(bundle)
        let itemDict = try #require(dict["item"] as? [String: Any])

        #expect(itemDict["isProjectArtifact"] as? Bool == true)
        #expect(itemDict["projectID"] as? String == "cider")
        #expect(itemDict["artifactType"] as? String == "note")

        let sourceEvidence = try #require(dict["sourceEvidence"] as? [String: Any])
        #expect(sourceEvidence["count"] as? Int == 1)
        #expect(sourceEvidence["acceptedRelationCount"] as? Int == 1)
        let facts = try #require(sourceEvidence["facts"] as? [[String: Any]])
        let fact = try #require(facts.first)
        #expect(fact["direction"] as? String == "outgoing")
        #expect(fact["currentOwnerRole"] as? String == "source")
        #expect(fact["relationType"] as? String == "artifact_of")
        #expect(fact["sourceQuote"] as? String == "Project note belongs to Cider.")
        #expect(fact["candidateRef"] as? String == "graph_candidate:candidate-123")
        #expect(fact["mentionText"] as? String == "Cider Project Note")
        #expect(fact["sourceKind"] as? String == "journal")
        let safeNextCommands = try #require(fact["safeNextCommands"] as? [String])
        #expect(safeNextCommands.contains("cider-cli item graph-candidate candidate-123 --json"))
        #expect(safeNextCommands.contains("cider-cli item context note \(noteID.uuidString) --json"))
        #expect(safeNextCommands.contains("cider-cli item project-context cider --json"))
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
                "--target-path", "Media/Documentaries",
                "--reason", "Documentaries should route to Media/Documentaries.",
                "--json",
            ],
            vault: vault
        )
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status != 0)
        #expect(payload["ok"] as? Bool == false)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["targetType"] as? String == "folder")
        #expect(payload["targetPath"] as? String == "Media/Documentaries")
        #expect(payload["recommendedNextAction"] as? String == "review_route")
        #expect((payload["error"] as? String)?.contains("No folder found") == true)
        let candidateDestinations = try #require(payload["candidateDestinations"] as? [[String: Any]])
        #expect(candidateDestinations.contains { $0["relativePath"] as? String == "Media/Movies" })
        #expect(candidateDestinations.contains { $0["relativePath"] as? String == "Media/Games" })
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

    @Test("CLI provenance is private by default and exact only after trusted-local opt in")
    func cliProvenanceProjectionIsSafeByDefaultAndTrustedLocalOnOptIn() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-private-provenance-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let intentionalBody = "CID834_INTENTIONAL_EXPORTED_BODY_ALLOWED"
        let captureResult = try runCLI(
            args: [
                "capture", "add", "--kind", "note",
                "--title", "CID834 Safe Export Subject",
                "--content", intentionalBody,
                "--json",
            ],
            vault: vault
        )
        let capture = try parseJSONObject(captureResult.stdout)
        let item = try #require(capture["item"] as? [String: Any])
        let noteID = try #require(item["id"] as? String)
        let relativePath = try #require(item["relativePath"] as? String)
        let provenanceReceipt = try #require(capture["provenance"] as? [String: Any])
        let eventID = try #require(provenanceReceipt["captureEventID"] as? String)

        let sentinels: [String: String] = [
            "sourceURL": "https://user:CID834_URL_SECRET@private.example/journal?token=CID834_TOKEN_SECRET",
            "sourceFile": "/Users/private/CID834_PATH_SECRET/journal.md",
            "sourceText": "CID834_SOURCE_TEXT_SECRET private journal paragraph",
            "channelID": "CID834_CHANNEL_ID_SECRET",
            "threadID": "CID834_THREAD_ID_SECRET",
            "messageID": "CID834_MESSAGE_ID_SECRET",
            "senderID": "CID834_SENDER_ID_SECRET",
            "senderName": "CID834_SENDER_NAME_SECRET",
            "metadataKey": "CID834_METADATA_KEY_SECRET",
            "metadataValue": "CID834_METADATA_VALUE_SECRET",
        ]
        let metadataData = try JSONSerialization.data(
            withJSONObject: [sentinels["metadataKey"]!: sentinels["metadataValue"]!],
            options: [.sortedKeys]
        )
        let metadataJSON = String(decoding: metadataData, as: UTF8.self)
        let databaseURL = vault.appendingPathComponent(".cider/cider.db")
        let database = CiderDatabase()
        try database.open(at: databaseURL)
        do {
            let update = try database.prepare("""
                UPDATE capture_events
                SET surface = ?, channel = ?, channel_id = ?, thread_id = ?, message_id = ?,
                    sender_id = ?, sender_name = ?, source_url = ?, source_file = ?, source_text = ?, metadata = ?
                WHERE id = ?;
                """)
            update.bind("chat", at: 1)
                .bind("discord", at: 2)
                .bind(sentinels["channelID"]!, at: 3)
                .bind(sentinels["threadID"]!, at: 4)
                .bind(sentinels["messageID"]!, at: 5)
                .bind(sentinels["senderID"]!, at: 6)
                .bind(sentinels["senderName"]!, at: 7)
                .bind(sentinels["sourceURL"]!, at: 8)
                .bind(sentinels["sourceFile"]!, at: 9)
                .bind(sentinels["sourceText"]!, at: 10)
                .bind(metadataJSON, at: 11)
                .bind(eventID, at: 12)
            try update.step()
        }
        database.close()

        func canonicalEventSnapshot() throws -> [String] {
            let snapshotDatabase = CiderDatabase()
            try snapshotDatabase.open(at: databaseURL)
            defer { snapshotDatabase.close() }
            let statement = try snapshotDatabase.prepare("""
                SELECT surface, channel, channel_id, thread_id, message_id, sender_id, sender_name,
                       source_url, source_file, source_text, metadata, attachment_count, created_at
                FROM capture_events WHERE id = ?;
                """)
            statement.bind(eventID, at: 1)
            #expect(try statement.step())
            return (0...10).map { statement.optionalString(at: $0) ?? "<nil>" }
                + [String(statement.int(at: 11)), String(statement.double(at: 12))]
        }

        let canonicalBefore = try canonicalEventSnapshot()
        let noteURL = vault.appendingPathComponent(relativePath)
        let noteBefore = try Data(contentsOf: noteURL)
        let defaultCommands: [[String]] = [
            ["item", "get", "note", noteID, "--json"],
            ["item", "context", "note", noteID, "--json"],
            ["item", "recall-context", "--item", "note", noteID, "--json"],
            ["export", "item", "note", noteID, "--format", "json", "--json"],
            ["export", "folder", "Inbox", "--format", "json", "--limit", "10", "--json"],
        ]
        var defaultOutputs: [[String]: String] = [:]
        for command in defaultCommands {
            let result = try runCLI(args: command, vault: vault)
            #expect(result.status == 0)
            #expect(!result.stdout.isEmpty)
            for sentinel in sentinels.values {
                #expect(!result.stdout.contains(sentinel))
            }
            defaultOutputs[command] = result.stdout
        }
        #expect(defaultOutputs[defaultCommands[3]]?.contains(intentionalBody) == true)
        #expect(defaultOutputs[defaultCommands[4]]?.contains(intentionalBody) == true)

        let defaultGetPayload = try parseJSONObject(try #require(defaultOutputs[defaultCommands[0]]))
        let defaultGetProvenance = try #require(defaultGetPayload["captureProvenance"] as? [[String: Any]])
        #expect(defaultGetProvenance.first?["projection"] as? String == "cli_default")
        #expect(defaultGetProvenance.first?["containsPrivateData"] as? Bool == false)
        let defaultContextPayload = try parseJSONObject(try #require(defaultOutputs[defaultCommands[1]]))
        let defaultContextProvenance = try #require(defaultContextPayload["captureProvenance"] as? [[String: Any]])
        #expect(defaultContextProvenance.first?["projection"] as? String == "cli_default")
        let defaultRecallPayload = try parseJSONObject(try #require(defaultOutputs[defaultCommands[2]]))
        let defaultRecallAnchors = try #require(defaultRecallPayload["anchors"] as? [[String: Any]])
        let defaultRecallProvenance = try #require(defaultRecallAnchors.first?["captureProvenance"] as? [[String: Any]])
        #expect(defaultRecallProvenance.first?["projection"] as? String == "cli_default")
        for exportCommand in [defaultCommands[3], defaultCommands[4]] {
            let exportPayload = try parseJSONObject(try #require(defaultOutputs[exportCommand]))
            let exportedItems = try #require(exportPayload["items"] as? [[String: Any]])
            let exportProvenance = try #require(exportedItems.first?["captureProvenance"] as? [[String: Any]])
            #expect(exportProvenance.first?["projection"] as? String == "portable_export")
            #expect(exportProvenance.first?["containsPrivateData"] as? Bool == false)
        }

        let repeatedGet = try runCLI(args: defaultCommands[0], vault: vault)
        let firstGetPayload = defaultGetPayload
        let repeatedGetPayload = try parseJSONObject(repeatedGet.stdout)
        let firstProjectedProvenance = try #require(firstGetPayload["captureProvenance"] as? [[String: Any]])
        let repeatedProjectedProvenance = try #require(repeatedGetPayload["captureProvenance"] as? [[String: Any]])
        #expect(
            try JSONSerialization.data(withJSONObject: firstProjectedProvenance, options: [.sortedKeys])
                == JSONSerialization.data(withJSONObject: repeatedProjectedProvenance, options: [.sortedKeys])
        )

        let trustedCommands: [[String]] = [
            ["item", "get", "note", noteID, "--include-private-provenance", "--json"],
            ["item", "context", "note", noteID, "--include-private-provenance", "--json"],
            ["item", "recall-context", "--item", "note", noteID, "--include-private-provenance", "--json"],
            ["export", "item", "note", noteID, "--format", "json", "--include-private-provenance", "--json"],
            ["export", "folder", "Inbox", "--format", "json", "--limit", "10", "--include-private-provenance", "--json"],
        ]
        for command in trustedCommands {
            let result = try runCLI(args: command, vault: vault)
            #expect(result.status == 0)
            #expect(result.stdout.contains("\"projection\" : \"trusted_local\""), "Trusted command did not declare its projection: \(command)")
            #expect(result.stdout.contains("\"containsPrivateData\" : true"), "Trusted command did not declare private output: \(command)")
            let trustedPayloadDescription = String(describing: try parseJSONObject(result.stdout))
            for sentinel in sentinels.values {
                #expect(trustedPayloadDescription.contains(sentinel), "Trusted command did not restore \(sentinel): \(command)")
            }
        }

        #expect(try canonicalEventSnapshot() == canonicalBefore)
        #expect(try Data(contentsOf: noteURL) == noteBefore)
    }

    @Test("private provenance opt in is documented by early help without vault access")
    func privateProvenanceOptInHelpIsEarlyAndExplicit() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-private-provenance-help-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: vault) }

        for args in [
            ["item", "get", "--help"],
            ["item", "context", "--help"],
            ["item", "recall-context", "--help"],
            ["item", "search", "--help"],
            ["export", "help"],
        ] {
            let result = try runCLI(args: args, vault: vault)
            #expect(result.status == 0)
            #expect(result.stdout.contains("--include-private-provenance"))
        }
        let exportHelp = try runCLI(args: ["export", "help"], vault: vault)
        #expect(exportHelp.stdout.contains("trusted-local"))
        #expect(exportHelp.stdout.contains("containsPrivateData=true"))
        #expect(!FileManager.default.fileExists(atPath: vault.path))
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
        #expect(payload["reason"] as? String == "timeout")
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

    @Test("item get explains rich social bookmark with remote-only thumbnail")
    func itemGetExplainsRichSocialBookmarkWithRemoteOnlyThumbnail() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-social-remote-thumbnail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        _ = try runCLI(args: ["db", "integrity", "--json"], vault: vault)
        let bookmarkID = "D7521D2A-C273-49B4-A019-55FA2948BDC1"
        try seedRichRemoteOnlySocialBookmark(bookmarkID: bookmarkID, vault: vault)

        let getResult = try runCLI(
            args: ["item", "get", "bookmark", bookmarkID, "--json"],
            vault: vault,
            environment: ["CIDER_DISABLE_BOOKMARK_ENRICHMENT": "1"]
        )
        let payload = try parseJSONObject(getResult.stdout)
        let quality = try #require(payload["captureQuality"] as? [String: Any])
        let reasons = try #require(quality["degradedReasons"] as? [String])
        let readiness = try #require(quality["thumbnailReadiness"] as? [String: Any])
        let safeCommands = try #require(payload["safeNextCommands"] as? [String])

        #expect(quality["semanticStatus"] as? String == "complete")
        #expect(quality["cardStatus"] as? String == "degraded")
        #expect(quality["visibleCardCurrent"] as? Bool == false)
        #expect(quality["thumbnailStatus"] as? String == "remote_only")
        #expect(reasons == ["card_image_not_local"])
        #expect(quality["safeNextAction"] as? String == "verify_or_localize_thumbnail")
        #expect(readiness["status"] as? String == "remote_only")
        #expect(readiness["localReady"] as? Bool == false)
        #expect(readiness["provider"] as? String == "tiktok")
        #expect(readiness["fallbackReason"] as? String == "remote_provider_image_without_local_thumbnail")
        #expect((readiness["safeVerificationCommands"] as? [String])?.contains("cider-cli item get bookmark \(bookmarkID) --json") == true)
        #expect((readiness["safeNextCommands"] as? [String])?.contains("cider-cli review enrich \(bookmarkID) --actor agent --timeout 20 --json") == true)
        #expect(safeCommands.contains("cider-cli item get bookmark \(bookmarkID) --json"))
        #expect(safeCommands.contains("cider-cli review enrich \(bookmarkID) --actor agent --timeout 20 --json"))
    }

    @Test("item get treats canonical local thumbnail artifact as local ready")
    func itemGetTreatsCanonicalLocalThumbnailArtifactAsLocalReady() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-social-local-thumbnail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        _ = try runCLI(args: ["db", "integrity", "--json"], vault: vault)
        let bookmarkID = "D7521D2A-C273-49B4-A019-55FA2948BDC1"
        try seedRichRemoteOnlySocialBookmark(bookmarkID: bookmarkID, vault: vault)
        let thumbnailURL = vault
            .appendingPathComponent(".cider/bookmarks/.thumbnails/\(bookmarkID).png")
        try FileManager.default.createDirectory(
            at: thumbnailURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("localized thumbnail".utf8).write(to: thumbnailURL)

        let getResult = try runCLI(
            args: ["item", "get", "bookmark", bookmarkID, "--json"],
            vault: vault,
            environment: ["CIDER_DISABLE_BOOKMARK_ENRICHMENT": "1"]
        )
        let payload = try parseJSONObject(getResult.stdout)
        let quality = try #require(payload["captureQuality"] as? [String: Any])
        let reasons = try #require(quality["degradedReasons"] as? [String])
        let readiness = try #require(quality["thumbnailReadiness"] as? [String: Any])
        let safeCommands = try #require(payload["safeNextCommands"] as? [String])

        #expect(quality["thumbnailStatus"] as? String == "local")
        #expect(quality["cardStatus"] as? String == "complete")
        #expect(quality["cardComplete"] as? Bool == true)
        #expect(quality["visibleCardCurrent"] as? Bool == true)
        #expect(!reasons.contains("card_image_not_local"))
        #expect(readiness["status"] as? String == "local")
        #expect(readiness["localReady"] as? Bool == true)
        #expect(!safeCommands.contains("cider-cli review enrich \(bookmarkID) --actor agent --timeout 20 --json"))
    }

    @Test("item get explains route review when bookmark card quality is current")
    func itemGetExplainsRouteReviewWhenBookmarkCardQualityIsCurrent() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-social-route-review-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        _ = try runCLI(args: ["db", "integrity", "--json"], vault: vault)
        let bookmarkID = "9E4893B3-B845-4FE9-816C-A9F39990D04B"
        try seedRichRemoteOnlyBookmark(
            bookmarkID: bookmarkID,
            vault: vault,
            title: "Codex skill update",
            urlString: "https://x.com/codex/status/123",
            notes: "Rich X capture with Codex skill context.",
            aiSummary: "Codex skill social bookmark.",
            mediaType: "post",
            thumbnailRemoteURLString: "https://example.invalid/codex-skill.png"
        )
        let thumbnailURL = vault
            .appendingPathComponent(".cider/bookmarks/.thumbnails/\(bookmarkID).png")
        try FileManager.default.createDirectory(
            at: thumbnailURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("localized codex thumbnail".utf8).write(to: thumbnailURL)
        try recordNeedsReviewRoute(bookmarkID: bookmarkID, vault: vault)

        let getResult = try runCLI(
            args: ["item", "get", "bookmark", bookmarkID, "--json"],
            vault: vault,
            environment: ["CIDER_DISABLE_BOOKMARK_ENRICHMENT": "1"]
        )
        let payload = try parseJSONObject(getResult.stdout)
        let quality = try #require(payload["captureQuality"] as? [String: Any])
        let routingReadiness = try #require(quality["routingReadiness"] as? [String: Any])
        let topRoutingReadiness = try #require(payload["routingReadiness"] as? [String: Any])
        let blockingIssues = try #require(payload["blockingIssues"] as? [String])
        let safeCommands = try #require(payload["safeNextCommands"] as? [String])

        #expect(quality["thumbnailStatus"] as? String == "local")
        #expect(quality["visibleCardCurrent"] as? Bool == true)
        #expect(routingReadiness["status"] as? String == "needs_review")
        #expect(routingReadiness["routeReviewNeeded"] as? Bool == true)
        #expect(routingReadiness["agentMayRoute"] as? Bool == false)
        #expect(topRoutingReadiness["status"] as? String == "needs_review")
        #expect(payload["useful"] as? Bool == false)
        #expect(payload["recommendedNextAction"] as? String == "review_route")
        #expect(blockingIssues == ["routing_needs_review"])
        #expect(safeCommands.contains("cider-cli routing explain \(bookmarkID) --json"))
        #expect(safeCommands.contains("cider-cli review list --item-type bookmark --state needs_review --limit 10 --json"))
    }

    @Test("item get exposes media route intent without mutating bookmark routing")
    func itemGetExposesMediaRouteIntentWithoutMutatingBookmarkRouting() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-media-route-intent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        _ = try runCLI(args: ["db", "integrity", "--json"], vault: vault)
        let bookmarkID = "7E357853-8331-4AA0-8F13-657F6BC852EB"
        try seedRichRemoteOnlyBookmark(
            bookmarkID: bookmarkID,
            vault: vault,
            title: "The Vampire Lestat: Season 1 | Rotten Tomatoes",
            urlString: "https://www.rottentomatoes.com/tv/the_vampire_lestat/s01",
            notes: "Rotten Tomatoes TV season page.",
            aiSummary: "A rich TV season capture.",
            mediaType: "tv",
            thumbnailRemoteURLString: "https://example.invalid/vampire-lestat.png"
        )

        let getResult = try runCLI(
            args: ["item", "get", "bookmark", bookmarkID, "--json"],
            vault: vault,
            environment: ["CIDER_DISABLE_BOOKMARK_ENRICHMENT": "1"]
        )
        let payload = try parseJSONObject(getResult.stdout)
        let routeIntent = try #require(payload["routeIntent"] as? [String: Any])
        let routingReadiness = try #require(payload["routingReadiness"] as? [String: Any])

        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(routeIntent["route"] as? String == "media/shows")
        #expect(routeIntent["source"] as? String == "capture.intent.url_provider")
        #expect(routeIntent["wouldRouteWithoutReview"] as? Bool == false)
        #expect(routeIntent["truthBoundary"] as? String == "reviewable_candidate_not_truth")
        #expect(routeIntent["provenance"] as? [String] == ["url_host:rottentomatoes.com", "url_path:/tv/the_vampire_lestat/s01"])
        #expect(routingReadiness["status"] as? String == "ready")
        #expect(routingReadiness["routeReviewNeeded"] as? Bool == false)
        #expect(routingReadiness["agentMayRoute"] as? Bool == false)

        let reviewList = try parseJSONObject(try runCLI(args: [
            "review", "list",
            "--item-type", "bookmark",
            "--state", "needs_review",
            "--limit", "10",
            "--json",
        ], vault: vault).stdout)
        #expect(reviewList["count"] as? Int == 1)
        let reviewItems = try #require(reviewList["items"] as? [[String: Any]])
        let reviewItem = try #require(reviewItems.first)
        let reviewRouteIntent = try #require(reviewItem["routeIntent"] as? [String: Any])
        #expect(reviewItem["kind"] as? String == "inbox_backlog")
        #expect(reviewRouteIntent["route"] as? String == "media/shows")
        #expect(reviewRouteIntent["wouldRouteWithoutReview"] as? Bool == false)
        #expect(reviewItem["relativePath"] as? String == "Inbox/Bookmarks/The Vampire Lestat- Season 1 - Rotten Tomatoes.webloc")
    }

    @Test("item thumbnail plan explains remote-only social bookmark without creating local thumbnail")
    func itemThumbnailPlanExplainsRemoteOnlySocialBookmarkWithoutCreatingLocalThumbnail() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-social-thumbnail-plan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        _ = try runCLI(args: ["db", "integrity", "--json"], vault: vault)
        let bookmarkID = "D7521D2A-C273-49B4-A019-55FA2948BDC1"
        try seedRichRemoteOnlyBookmark(
            bookmarkID: bookmarkID,
            vault: vault,
            title: "Sodam Chicken - Korean fried chicken in Everett",
            urlString: "https://www.tiktok.com/@sodamchicken/video/7521",
            notes: "Rich chunks mention Sodam Chicken, Korean fried chicken, Everett, and TikTok restaurant context.",
            aiSummary: "TikTok restaurant capture for Sodam Chicken in Everett.",
            mediaType: "video",
            thumbnailRemoteURLString: "https://example.invalid/sodam-remote-only.jpeg"
        )
        let thumbnailPath = vault
            .appendingPathComponent(".cider/bookmarks/.thumbnails/\(bookmarkID).png")
        #expect(!FileManager.default.fileExists(atPath: thumbnailPath.path))

        let result = try runCLI(
            args: ["item", "thumbnail-plan", "bookmark", bookmarkID, "--json"],
            vault: vault,
            environment: ["CIDER_DISABLE_BOOKMARK_ENRICHMENT": "1"]
        )
        let payload = try parseJSONObject(result.stdout)
        let state = try #require(payload["thumbnailState"] as? [String: Any])
        let commands = try #require(payload["safeNextCommands"] as? [String])
        let verificationCommands = try #require(payload["safeVerificationCommands"] as? [String])
        let selectors = try #require(payload["stableSelectors"] as? [String: Any])

        #expect(payload["command"] as? String == "item.thumbnail-plan")
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["safeNextAction"] as? String == "verify_or_localize_thumbnail")
        #expect(payload["fallbackReason"] as? String == "remote_provider_image_without_local_thumbnail")
        #expect(payload["truthBoundary"] as? String == "read_only_thumbnail_plan_from_stored_bookmark_metadata_no_network_or_mutation")
        #expect(payload["readinessBoundary"] as? String == "localReady requires an existing non-empty local thumbnail asset; remote provider URLs are not downloaded by this command")
        #expect(payload["applyCommandCaveat"] as? String == "The enrich/apply command may perform network/provider work and mutate stored bookmark metadata or thumbnail files; run it only with explicit user approval.")
        #expect(state["localReady"] as? Bool == false)
        #expect(state["thumbnailStatus"] as? String == "remote_only")
        #expect(state["provider"] as? String == "tiktok")
        #expect(state["remoteImageURL"] as? String == "https://example.invalid/sodam-remote-only.jpeg")
        #expect(verificationCommands.contains("cider-cli item get bookmark \(bookmarkID) --json"))
        #expect(commands.contains("cider-cli review enrich \(bookmarkID) --actor agent --timeout 20 --json"))
        #expect(selectors["itemID"] as? String == bookmarkID)
        #expect(selectors["itemRef"] as? String == "bookmark:\(bookmarkID)")
        #expect(!FileManager.default.fileExists(atPath: thumbnailPath.path))
    }

    @Test("item thumbnail plan replays bookmark drift audit safe verification command")
    func itemThumbnailPlanReplaysBookmarkDriftAuditSafeVerificationCommand() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-thumbnail-plan-audit-replay-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        _ = try runCLI(args: ["db", "integrity", "--json"], vault: vault)
        let bookmarkID = "D7521D2A-C273-49B4-A019-55FA2948BDC1"
        try seedRichRemoteOnlySocialBookmark(bookmarkID: bookmarkID, vault: vault)

        let auditResult = try runCLI(
            args: ["storage", "bookmark-drift-audit", "--limit", "20", "--json"],
            vault: vault,
            environment: ["CIDER_DISABLE_BOOKMARK_ENRICHMENT": "1"]
        )
        let auditPayload = try parseJSONObject(auditResult.stdout)
        let findings = try #require(auditPayload["findings"] as? [[String: Any]])
        let finding = try #require(findings.first { $0["kind"] as? String == "bookmark_thumbnail_readiness" })
        let plan = try #require(finding["thumbnailLocalizationPlan"] as? [String: Any])
        let selectors = try #require(plan["stableSelectors"] as? [String: Any])
        let commands = try #require(finding["safeVerificationCommands"] as? [String])
        let replayCommand = try #require(commands.first { $0.contains(" item thumbnail-plan bookmark ") })
        let replayArgs = replayCommand.split(separator: " ").dropFirst().map(String.init)

        #expect(selectors["itemRef"] as? String == "bookmark:\(bookmarkID)")
        #expect(replayCommand == "cider-cli item thumbnail-plan bookmark bookmark:\(bookmarkID) --json")

        let replayResult = try runCLI(
            args: replayArgs,
            vault: vault,
            environment: ["CIDER_DISABLE_BOOKMARK_ENRICHMENT": "1"]
        )
        let replayPayload = try parseJSONObject(replayResult.stdout)
        let state = try #require(replayPayload["thumbnailState"] as? [String: Any])
        let thumbnailPath = vault
            .appendingPathComponent(".cider/bookmarks/.thumbnails/\(bookmarkID).png")

        #expect(replayPayload["readOnly"] as? Bool == true)
        #expect(replayPayload["changed"] as? Bool == false)
        #expect(replayPayload["itemID"] as? String == bookmarkID)
        #expect(state["thumbnailStatus"] as? String == "remote_only")
        #expect(!FileManager.default.fileExists(atPath: thumbnailPath.path))
    }

    @Test("item thumbnail plan fails closed for invalid bookmark selector")
    func itemThumbnailPlanFailsClosedForInvalidBookmarkSelector() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-thumbnail-plan-invalid-selector-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        _ = try runCLI(args: ["db", "integrity", "--json"], vault: vault)

        let result = try runCLI(
            args: ["item", "thumbnail-plan", "bookmark", "note:not-a-bookmark", "--json"],
            vault: vault,
            environment: ["CIDER_DISABLE_BOOKMARK_ENRICHMENT": "1"]
        )
        let payload = try parseJSONObject(result.stdout)
        let sourceRef = try #require(payload["sourceRef"] as? [String: Any])
        let safeNextCommands = try #require(payload["safeNextCommands"] as? [String])

        #expect(result.status != 0)
        #expect(payload["ok"] as? Bool == false)
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["errorCode"] as? String == "item_not_found")
        #expect(sourceRef["type"] as? String == "bookmark")
        #expect(sourceRef["ref"] as? String == "note:not-a-bookmark")
        #expect(safeNextCommands.contains("cider-cli item search <query> --json"))
    }

    @Test("item thumbnail plan explains generic remote-only bookmark with provider unknown")
    func itemThumbnailPlanExplainsGenericRemoteOnlyBookmarkWithProviderUnknown() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-generic-thumbnail-plan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        _ = try runCLI(args: ["db", "integrity", "--json"], vault: vault)
        let bookmarkID = "2F29F4C4-2801-4E47-8D82-A182E6E3B350"
        try seedRichRemoteOnlyBookmark(
            bookmarkID: bookmarkID,
            vault: vault,
            title: "Open Graph image debugging notes",
            urlString: "https://example.invalid/articles/open-graph-debugging",
            notes: "Generic remote-only bookmark fixture with stored metadata and a remote Open Graph image.",
            aiSummary: "Generic article capture with remote-only Open Graph image.",
            mediaType: "article",
            thumbnailRemoteURLString: "https://cdn.example.invalid/open-graph-debugging.jpg"
        )

        let result = try runCLI(
            args: ["item", "thumbnail-plan", "bookmark", bookmarkID, "--json"],
            vault: vault,
            environment: ["CIDER_DISABLE_BOOKMARK_ENRICHMENT": "1"]
        )
        let payload = try parseJSONObject(result.stdout)
        let state = try #require(payload["thumbnailState"] as? [String: Any])

        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(state["localReady"] as? Bool == false)
        #expect(state["thumbnailStatus"] as? String == "remote_only")
        #expect(state["providerUnknown"] as? Bool == true)
        #expect(state["provider"] as? String == "unknown")
        #expect(payload["safeNextAction"] as? String == "verify_or_localize_thumbnail")
        #expect((payload["safeNextCommands"] as? [String])?.contains("cider-cli review enrich \(bookmarkID) --actor agent --timeout 20 --json") == true)
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
        #expect(journal["command"] as? String == "note.daily.append")
        #expect(journal["backendCommand"] as? String == "capture.add")
        #expect(journal["deprecatedBy"] as? String == "capture.add")
        #expect(journal["kind"] as? String == "journal")
        #expect((journal["agentGuidance"] as? String)?.contains("cider-cli capture add --kind journal --date today --stdin --json") == true)
        let safeNextCommands = try #require(journal["safeNextCommands"] as? [String])
        #expect(safeNextCommands.contains("cider-cli capture add --kind journal --date 2026-05-28 --time 20:00 --stdin --json"))
        let capture = try #require(journal["capture"] as? [String: Any])
        #expect(capture["command"] as? String == "capture.add")
        #expect(capture["created"] as? Bool == true)
        let journalContent = try #require(capture["content"] as? String)
        #expect(journalContent.contains("Journal 05-28-2026"))
        #expect(journalContent.contains("## 20:00"))
        #expect(journalContent.contains("Source: discord"))
        #expect(journalContent.contains("Evening reflection"))

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

    @Test("capture add content flag creates dated todo")
    func captureAddContentFlagCreatesDatedTodo() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-capture-content-todo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let result = try runCLI(
            args: [
                "capture", "add",
                "--kind", "todo",
                "--content", "Hermes due-date smoke test",
                "--date", "2026-07-13",
                "--json",
            ],
            vault: vault
        )

        let dict = try parseJSONObject(result.stdout)
        #expect(result.status == 0)
        #expect(dict["ok"] as? Bool != false)
        let item = try #require(dict["item"] as? [String: Any])
        #expect(item["title"] as? String == "Hermes due-date smoke test")
        #expect(item["type"] as? String == "todo")
        let relativePath = try #require(item["relativePath"] as? String)
        let icsURL = vault.appendingPathComponent(relativePath)
        let ics = try String(contentsOf: icsURL, encoding: .utf8)
        #expect(ics.contains("SUMMARY:Hermes due-date smoke test"))
        #expect(ics.contains("DUE;VALUE=DATE:20260713"))
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
        #expect(result.stdout.contains("--clear-ocr-text"))
    }

    @Test("bookmark update help documents repair flags without ID lookup")
    func bookmarkUpdateHelpDocumentsRepairFlagsWithoutIDLookup() throws {
        let result = try runCLI(args: ["bookmark", "update", "--help"])

        #expect(result.status == 0)
        #expect(result.stdout.contains("Usage: cider-cli bookmark update <id>"))
        #expect(result.stdout.contains("--ai-summary <text>|--clear-ai-summary"))
        #expect(result.stdout.contains("--clear-ocr-text"))
        #expect(!result.stdout.contains("No bookmark found with ID prefix: --help"))
        #expect(!result.stderr.contains("No bookmark found with ID prefix: --help"))
    }

    @Test("bookmark help points agents to blessed update repair flags")
    func bookmarkHelpPointsAgentsToBlessedUpdateRepairFlags() throws {
        let result = try runCLI(args: ["bookmark", "--help"])

        #expect(result.status == 0)
        #expect(result.stdout.contains("Legacy bookmark workflows remain removed"))
        #expect(result.stdout.contains("cider-cli bookmark update --help"))
        #expect(result.stdout.contains("--clear-ai-summary"))
        #expect(result.stdout.contains("--clear-ocr-text"))
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
        #expect(itemHelp.stdout.contains("Read-only traversal commands"))
        #expect(itemHelp.stdout.contains("cider-cli item related <type> <id-or-ref> [--json]"))
        #expect(itemHelp.stdout.contains("cider-cli item relations <owner-type> <owner-id-or-ref> [--json]"))
        #expect(itemHelp.stdout.contains("cider-cli item backlinks <owner-type> <owner-id-or-ref> [--json]"))
        #expect(itemHelp.stdout.contains("cider-cli item owner-get <owner-type> <owner-id-or-ref> [--json]"))
        #expect(topHelp.stdout.contains("--path <source-file-path>"))
        #expect(topHelp.stdout.contains("--path <target-folder-path>"))
    }

    @Test("item search help scope and sort validation are agent safe")
    func itemSearchHelpScopeAndSortValidationAreAgentSafe() throws {
        let help = try runCLI(args: ["item", "search", "--help"])
        let itemHelp = try runCLI(args: ["item", "help"])
        let topHelp = try runCLI(args: ["help"])

        #expect(help.status == 0)
        #expect(help.stdout.contains("Valid --scope values: all, personalMemory, projectKanban, qaArtifacts, files"))
        #expect(help.stdout.contains("Use one scope value at a time; do not combine scope names"))
        #expect(help.stdout.contains("Valid --sort values: relevance, newest, oldest"))
        #expect(help.stdout.contains("Default is relevance; newest/oldest use capture provenance timestamps when present"))
        #expect(help.stdout.contains("cider-cli item search \"event\" --scope personalMemory --json"))
        #expect(help.stdout.contains("cider-cli item search \"Panda Express\" --sort newest --limit 5 --json"))
        #expect(!help.stdout.contains("personalMemory/all"))
        #expect(itemHelp.stdout.contains("[--sort relevance|newest|oldest]"))
        #expect(topHelp.stdout.contains("[--sort relevance|newest|oldest]"))

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

        let invalidSort = try runCLI(args: [
            "item", "search", "event",
            "--sort", "recent",
            "--json",
        ])
        let sortPayload = try parseJSONObject(invalidSort.stdout)
        let sortError = try #require(sortPayload["error"] as? String)

        #expect(invalidSort.status != 0)
        #expect(sortPayload["ok"] as? Bool == false)
        #expect(sortError.contains("Unsupported item search sort 'recent'"))
        #expect(sortError.contains("Valid --sort values: relevance, newest, oldest"))
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

    @Test("board help aliases print usage instead of unknown command")
    func boardHelpAliasesPrintUsageInsteadOfUnknownCommand() throws {
        for alias in ["--help", "-h", "help"] {
            let result = try runCLI(args: ["board", alias])

            #expect(result.status == 0, "Expected cider-cli board \(alias) to exit successfully")
            #expect(result.stdout.contains("BOARD WORKFLOW"))
            #expect(result.stdout.contains("cider-cli board add-card"))
            #expect(!result.stdout.contains("Unknown board command"))
        }
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
        let genericReason = "Use the Second Brain v1 agent API."
        let dashboardReason = "Dashboard topics and cards are UI preference state, not second-brain truth. HomeOverviewDataProvider remains the graph-backed read model for what matters now."
        let cases: [(args: [String], command: String, replacement: String, reason: String)] = [
            (["bookmark", "list", "--json"], "bookmark list", "cider-cli item search <query> --json", genericReason),
            (["bookmark", "enrich", "abc", "--json"], "bookmark enrich", "cider-cli review enrich <item-id> --json", genericReason),
            (["note", "list", "--json"], "note list", "cider-cli item search <query> --json", genericReason),
            (["todo", "list", "--json"], "todo list", "cider-cli item search <query> --json", genericReason),
            (["event", "list", "--json"], "event list", "cider-cli item search <query> --json", genericReason),
            (["contact", "list", "--json"], "contact list", "cider-cli item search <query> --json", genericReason),
            (["file", "list", "--json"], "file list", "cider-cli item search <query> --json", genericReason),
            (["folder", "list", "--json"], "folder list", "cider-cli item search <query> --json", genericReason),
            (["folder", "create", "Projects", "--json"], "folder create", "cider-cli item search <query> --json", genericReason),
            (["label", "list", "--json"], "label list", "cider-cli item search <query> --json", genericReason),
            (["tag", "list", "--json"], "tag list", "cider-cli item search <query> --json", genericReason),
            (["dashboard", "topic", "list", "--json"], "dashboard topic", "cider-cli item graph-health --json", dashboardReason),
            (["link", "add", "note", "a", "note", "b", "--json"], "link add", "cider-cli item link", genericReason),
            (["view", "list", "--json"], "view list", "cider-cli item project-context <project-id-or-name> --json", genericReason),
            (["saved-view", "list", "--json"], "saved-view list", "cider-cli item project-context <project-id-or-name> --json", genericReason),
            (["trash", "list", "--json"], "trash list", "cider-cli storage audit --json", genericReason),
            (["clipboard", "import", "--json"], "clipboard import", "cider-cli capture add --kind note --stdin --json", genericReason),
            (["recall", "list", "--json"], "recall list", "cider-cli item search <query> --json", genericReason),
            (["duplicate-check", "run", "--json"], "duplicate-check run", "cider-cli item search <url-or-query> --json", genericReason),
            (["media", "scan", "--json"], "media scan", "cider-cli item search <query> --json", genericReason),
            (["bookmark", "move", "abc", "--json"], "bookmark move", "cider-cli item move bookmark <id> --folder <name|path> --json", genericReason),
            (["note", "move", "abc", "--json"], "note move", "cider-cli item move note <id> --folder <name|path> --json", genericReason),
            (["todo", "move", "abc", "--json"], "todo move", "cider-cli item move todo <id> --folder <name|path> --json", genericReason),
            (["file", "move", "abc", "--json"], "file move", "cider-cli item move file <id> --folder <name|path> --json", genericReason),
        ]

        for testCase in cases {
            let result = try runCLI(args: testCase.args)
            let dict = try parseJSONObject(result.stdout)
            #expect(result.status != 0, "Expected \(testCase.args.joined(separator: " ")) to exit non-zero")
            #expect(dict["ok"] as? Bool == false)
            #expect(dict["legacyRemoved"] as? Bool == true)
            #expect(dict["command"] as? String == testCase.command)
            #expect(dict["replacement"] as? String == testCase.replacement)
            #expect(dict["reason"] as? String == testCase.reason)
        }
    }

    @Test("dashboard topic legacy CLI explains ui preference contract")
    func dashboardTopicLegacyCLIExplainsUIPreferenceContract() throws {
        let result = try runCLI(args: ["dashboard", "topic", "list", "--json"])
        let dict = try parseJSONObject(result.stdout)

        #expect(result.status != 0)
        #expect(dict["legacyRemoved"] as? Bool == true)
        #expect(dict["replacement"] as? String == "cider-cli item graph-health --json")
        #expect((dict["reason"] as? String)?.contains("Dashboard topics and cards are UI preference state") == true)
        #expect((dict["reason"] as? String)?.contains("HomeOverviewDataProvider") == true)
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
            "PROJECT ARTIFACT",
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

        let receipt = try #require(dict["actionReceipt"] as? [String: Any])
        #expect(receipt["command"] as? String == "item.graph-health")
        #expect(receipt["commandFamily"] as? String == "item")
        #expect(receipt["subcommand"] as? String == "graph-health")
        #expect(receipt["readOnly"] as? Bool == true)
        #expect(receipt["changed"] as? Bool == false)
        #expect(receipt["status"] as? String == dict["status"] as? String)
        #expect(receipt["resultStatus"] as? String == dict["status"] as? String)
        #expect(receipt["diagnosticCount"] as? Int == components.count)
        #expect((receipt["matchedSourceRefs"] as? [String])?.contains("graph-health:owner_relations") == true)
        #expect((receipt["provenanceRefs"] as? [String])?.contains("schemaVersion:\(dict["schemaVersion"] as? Int ?? -1)") == true)
        #expect((receipt["safeCommandRefs"] as? [String])?.contains("cider-cli item graph-health --json") == true)
        #expect((receipt["safeCommandRefs"] as? [String])?.contains("cider-cli storage audit --json") == true)
        #expect(receipt["verificationHint"] as? String == "verify_with_safe_commands_and_source_refs")
        #expect(receipt["truthBoundary"] as? String == "receipt_proves_diagnostic_execution_not_graph_truth")
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

    @Test("item dogfood intelligence seeds reviewable stores and exposes safe follow-up commands")
    func itemDogfoodIntelligenceSeedsReviewableStoresAndExposesSafeFollowUpCommands() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-dogfood-intelligence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        _ = try runCLI(
            args: [
                "note", "create", "Launch graph",
                "--content", "Cider graph launch roadmap agent context Apple Park https://example.com/launch #ProductLaunch",
                "--json"
            ],
            vault: vault
        )
        _ = try runCLI(
            args: [
                "note", "create", "Launch roadmap",
                "--content", "Apple Park product launch roadmap for Cider agent context https://example.com/roadmap #ProductLaunch",
                "--json"
            ],
            vault: vault
        )

        let seedResult = try runCLI(args: ["item", "dogfood-intelligence", "--limit", "2", "--json"], vault: vault)
        let seed = try parseJSONObject(seedResult.stdout)
        #expect(seed["command"] as? String == "item.dogfood-intelligence")
        #expect(seed["reviewRequired"] as? Bool == true)
        #expect((seed["enrichmentOutputCount"] as? Int ?? 0) > 0)
        #expect((seed["similarityCandidateCount"] as? Int ?? 0) > 0)

        let owners = try #require(seed["owners"] as? [[String: Any]])
        #expect(owners.allSatisfy { owner in
            let outputCount = owner["enrichmentOutputCount"] as? Int ?? 0
            let states = owner["enrichmentReviewStates"] as? [String: Int] ?? [:]
            return states["suggested", default: 0] == outputCount
        })
        #expect(owners.contains { owner in
            let states = owner["similarityReviewStates"] as? [String: Int] ?? [:]
            return states["suggested", default: 0] > 0
        })

        let safeNextCommands = try #require(seed["safeNextCommands"] as? [String])
        #expect(safeNextCommands.contains("cider-cli capture review-queue --limit 20 --json"))
        #expect(safeNextCommands.contains("cider-cli item graph-health --json"))
        #expect(safeNextCommands.contains { $0.hasPrefix("cider-cli item context ") && $0.hasSuffix(" --json") })

        let safeNextActions = try #require(seed["safeNextActions"] as? [[String: Any]])
        #expect(safeNextActions.contains { action in
            action["command"] as? String == "cider-cli capture review-queue --limit 20 --json"
                && action["readOnly"] as? Bool == true
                && action["requiresApproval"] as? Bool == false
                && action["reason"] as? String == "review_seeded_intelligence"
        })

        let healthResult = try runCLI(args: ["item", "graph-health", "--json"], vault: vault)
        let health = try parseJSONObject(healthResult.stdout)
        let components = try #require(health["components"] as? [[String: Any]])
        #expect(components.contains { component in
            component["id"] as? String == "enrichment_outputs"
                && component["state"] as? String == "healthy"
                && (component["count"] as? Int ?? 0) > 0
        })
        #expect(components.contains { component in
            component["id"] as? String == "similarity_candidates"
                && component["state"] as? String == "healthy"
                && (component["count"] as? Int ?? 0) > 0
        })
    }

    @Test("item backfill journals reprocesses only Daily Journal notes into reviewable candidates")
    func itemBackfillJournalsReprocessesOnlyDailyJournalNotesIntoReviewableCandidates() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-backfill-journals-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let journalID = try createNote(
            title: "Daily Journal 2026-06-01",
            content: "Jami loved pineapple coconut drink. First weekend overtime in five years; hourly wages motivation helped.",
            vault: vault
        )
        _ = try createNote(
            title: "Regular Project Note",
            content: "I gave Jami that pineapple coconut drink and she loved it.",
            vault: vault
        )

        let result = try runCLI(args: ["item", "backfill-journals", "--limit", "5", "--json"], vault: vault)
        let payload = try parseJSONObject(result.stdout)

        #expect(payload["ok"] as? Bool == true)
        #expect(payload["command"] as? String == "item.backfill-journals")
        #expect(payload["changed"] as? Bool == true)
        #expect(payload["scope"] as? String == "daily_journal")
        #expect(payload["selectedCount"] as? Int == 1)
        #expect(payload["ownerCount"] as? Int == 1)
        #expect(payload["reviewRequired"] as? Bool == true)
        #expect((payload["chunkCount"] as? Int ?? 0) > 0)
        #expect((payload["enrichmentOutputCount"] as? Int ?? 0) > 0)
        #expect((payload["similarityCandidateCount"] as? Int ?? 0) >= 0)
        #expect((payload["graphCandidateCount"] as? Int ?? 0) > 0)
        #expect((payload["memoryCandidateCount"] as? Int ?? 0) > 0)

        let owners = try #require(payload["owners"] as? [[String: Any]])
        let owner = try #require(owners.first)
        let ownerRef = try #require(owner["owner"] as? [String: Any])
        #expect(ownerRef["ownerType"] as? String == "note")
        #expect(ownerRef["ownerID"] as? String == journalID)
        #expect(owner["title"] as? String == "Daily Journal 2026-06-01")
        #expect((owner["graphCandidateCount"] as? Int ?? 0) > 0)
        #expect((owner["memoryCandidateCount"] as? Int ?? 0) > 0)
        let graphCandidates = try #require(owner["graphCandidates"] as? [[String: Any]])
        #expect(graphCandidates.contains { candidate in
            candidate["reviewState"] as? String == "suggested"
                && (candidate["mentionText"] as? String)?.localizedCaseInsensitiveContains("pineapple coconut drink") == true
        })

        let safeNextCommands = try #require(payload["safeNextCommands"] as? [String])
        #expect(safeNextCommands.contains("cider-cli capture review-queue --limit 20 --json"))
        #expect(safeNextCommands.contains("cider-cli item graph-candidates note \(journalID) --json"))
        #expect(safeNextCommands.contains("cider-cli item context note \(journalID) --json"))

        let reviewResult = try runCLI(args: ["capture", "review-queue", "--limit", "20", "--json"], vault: vault)
        let review = try parseJSONObject(reviewResult.stdout)
        let reviewItems = try #require(review["items"] as? [[String: Any]])
        #expect(reviewItems.contains { item in
            item["kind"] as? String == "graph_candidate"
                || item["kind"] as? String == "memory_candidate"
        })
    }

    @Test("item backfill journals persists July 3 preview as one reviewable memory candidate")
    func itemBackfillJournalsPersistsJuly3PreviewAsOneReviewableMemoryCandidate() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-backfill-july3-memory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let journalID = try createNote(
            title: "Daily Journal 2026-07-03",
            content: """
            At the LaVassars house on Whidbey Island, Cultus Bay. About to watch the fireworks in a bit. We try to come here every 3rd of July. It's a good time.

            Timing notes for next year: left our house at 10:50 AM, got in the ferry line at 11:20 AM, and got onto the 1:00 PM ferry.
            """,
            vault: vault
        )

        let before = try assertStrictProcessJSON(
            runCLI(args: ["item", "graph-candidates", "note", journalID, "--json"], vault: vault),
            command: "item.graph-candidates"
        )
        let beforeDiagnostic = try #require(before["journalExtractionDiagnostic"] as? [String: Any])
        #expect(beforeDiagnostic["status"] as? String == "current_extractor_preview_available")
        #expect(beforeDiagnostic["storedMemoryCandidateCount"] as? Int == 0)
        #expect((beforeDiagnostic["persistedMemoryCandidates"] as? [[String: Any]])?.isEmpty == true)
        let beforePreview = try #require((beforeDiagnostic["memoryCandidatePreviews"] as? [[String: Any]])?.first)
        #expect(beforePreview["previewOnly"] as? Bool == true)
        #expect(beforePreview["persisted"] as? Bool == false)
        #expect(beforePreview["truthState"] as? String == "reviewable_candidate_not_truth")

        let firstBackfill = try assertStrictProcessJSON(
            runCLI(args: ["item", "backfill-journals", "--date", "2026-07-03", "--limit", "1", "--json"], vault: vault),
            command: "item.backfill-journals"
        )
        #expect(firstBackfill["selectedCount"] as? Int == 1)
        #expect(firstBackfill["memoryCandidateCount"] as? Int == 1)
        let owners = try #require(firstBackfill["owners"] as? [[String: Any]])
        let owner = try #require(owners.first)
        let memoryCandidates = try #require(owner["memoryCandidates"] as? [[String: Any]])
        let memory = try #require(memoryCandidates.first)
        #expect(memory["truthState"] as? String == "reviewable_candidate_not_truth")
        #expect(memory["memoryKind"] as? String == "future_planning_tradition")
        #expect(memory["previewOnly"] as? Bool == false)
        #expect(memory["persisted"] as? Bool == true)
        #expect((memory["sourceQuote"] as? String)?.contains("Timing notes for next year") == true)
        #expect((memory["sourceQuote"] as? String)?.contains("1:00 PM ferry") == true)

        let after = try assertStrictProcessJSON(
            runCLI(args: ["item", "graph-candidates", "note", journalID, "--json"], vault: vault),
            command: "item.graph-candidates"
        )
        let afterDiagnostic = try #require(after["journalExtractionDiagnostic"] as? [String: Any])
        #expect(afterDiagnostic["status"] as? String == "stored_memory_candidates_available")
        #expect(afterDiagnostic["storedMemoryCandidateCount"] as? Int == 1)
        let persisted = try #require((afterDiagnostic["persistedMemoryCandidates"] as? [[String: Any]])?.first)
        #expect(persisted["truthState"] as? String == "reviewable_candidate_not_truth")
        #expect(persisted["previewOnly"] as? Bool == false)
        #expect(persisted["persisted"] as? Bool == true)

        let secondBackfill = try assertStrictProcessJSON(
            runCLI(args: ["item", "backfill-journals", "--date", "2026-07-03", "--limit", "1", "--json"], vault: vault),
            command: "item.backfill-journals"
        )
        #expect(secondBackfill["memoryCandidateCount"] as? Int == 1)
        let secondOwners = try #require(secondBackfill["owners"] as? [[String: Any]])
        let secondOwner = try #require(secondOwners.first)
        #expect(secondOwner["memoryCandidateCount"] as? Int == 1)

        let review = try assertStrictProcessJSON(
            runCLI(args: ["capture", "review-queue", "--kind", "memory_candidate", "--limit", "20", "--json"], vault: vault),
            command: "capture.review-queue"
        )
        let reviewItems = try #require(review["items"] as? [[String: Any]])
        #expect(reviewItems.count == 1)
        #expect(reviewItems.first?["truthState"] as? String == "reviewable_candidate_not_truth")
    }

    @Test("item backfill journals help is side effect free")
    func itemBackfillJournalsHelpIsSideEffectFree() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-backfill-journals-help-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        _ = try createNote(
            title: "Daily Journal 2026-06-20",
            content: "Help requests must not backfill this journal into graph or memory review candidates.",
            vault: vault
        )
        let beforeCounts = try generatedSecondBrainRowCounts(vault: vault)

        let result = try runCLI(args: ["item", "backfill-journals", "--help"], vault: vault)

        #expect(result.status == 0)
        #expect(result.stdout.contains("cider-cli item backfill-journals"))
        #expect(result.stdout.localizedCaseInsensitiveContains("Backfilled") == false)
        #expect(try generatedSecondBrainRowCounts(vault: vault) == beforeCounts)
    }

    @Test("item journal migration preview reports Journal card eligibility without mutation")
    func itemJournalMigrationPreviewReportsJournalCardEligibilityWithoutMutation() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-journal-preview-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        _ = try createNote(
            title: "Journal 05-30-2026",
            content: "Already canonical.",
            vault: vault
        )
        _ = try createNote(
            title: "Driving voice journal from May 29, 2026",
            content: "Drove home and talked through the day.",
            vault: vault
        )
        _ = try createNote(
            title: "Cider journal IA — dashboard module plus Notes filter or Journal sidebar",
            content: "Product IA notes should not become personal Journal entries.",
            vault: vault
        )
        _ = try createNote(
            title: "Research journal taxonomy",
            content: "Could be personal or product.",
            vault: vault
        )
        let beforeCounts = try generatedSecondBrainRowCounts(vault: vault)

        let preview = try assertStrictProcessJSON(
            runCLI(args: ["item", "journal-migration-preview", "--json"], vault: vault),
            command: "item.journal-migration-preview"
        )

        #expect(preview["readOnly"] as? Bool == true)
        #expect(preview["changed"] as? Bool == false)
        #expect(preview["mutatesLiveNotes"] as? Bool == false)
        #expect(preview["journalLibraryEligibleCount"] as? Int == 2)
        let counts = try #require(preview["counts"] as? [String: Any])
        #expect(counts["canonical"] as? Int == 1)
        #expect(counts["safePersonalCandidate"] as? Int == 1)
        #expect(counts["excludedProductOrDev"] as? Int == 1)
        #expect(counts["ambiguous"] as? Int == 1)
        let rows = try #require(preview["rows"] as? [[String: Any]])
        let rowsByTitle = Dictionary(uniqueKeysWithValues: rows.compactMap { row -> (String, [String: Any])? in
            guard let note = row["note"] as? [String: Any],
                  let title = note["title"] as? String else {
                return nil
            }
            return (title, row)
        })
        #expect(rowsByTitle["Journal 05-30-2026"]?["journalLibraryEligible"] as? Bool == true)
        #expect(rowsByTitle["Driving voice journal from May 29, 2026"]?["journalLibraryEligible"] as? Bool == true)
        #expect(rowsByTitle["Driving voice journal from May 29, 2026"]?["proposedCanonicalTitle"] as? String == "Journal 05-29-2026")
        #expect(rowsByTitle["Driving voice journal from May 29, 2026"]?["dateIneligibilityReason"] is NSNull)
        let personalEvidence = try #require(rowsByTitle["Driving voice journal from May 29, 2026"]?["dateEvidence"] as? [[String: Any]])
        #expect(personalEvidence.first?["isoDate"] as? String == "2026-05-29")
        #expect(personalEvidence.first?["source"] as? String == "title")
        #expect(personalEvidence.first?["kind"] as? String == "monthNameDate")
        #expect(personalEvidence.first?["rawValue"] as? String == "May 29, 2026")
        #expect(rowsByTitle["Cider journal IA — dashboard module plus Notes filter or Journal sidebar"]?["journalLibraryEligible"] as? Bool == false)
        #expect(rowsByTitle["Research journal taxonomy"]?["journalLibraryEligible"] as? Bool == false)
        #expect(rowsByTitle["Research journal taxonomy"]?["dateIneligibilityReason"] as? String == "No unambiguous source-backed date found in title or body.")
        #expect(try generatedSecondBrainRowCounts(vault: vault) == beforeCounts)
    }

    @Test("adjacent item migration help exits before vault access")
    func adjacentItemMigrationHelpExitsBeforeVaultAccess() throws {
        let commands: [[String]] = [
            ["item", "backfill-kanban", "--help"],
            ["item", "rebuild-references", "--help"],
            ["item", "rebuild-chunks", "--help"],
            ["item", "rebuild-enrichment", "--help"],
            ["item", "rebuild-similarity", "--help"],
            ["item", "dogfood-intelligence", "--help"],
            ["item", "backfill-journals", "--help"],
            ["item", "sync-project", "--help"],
        ]

        for args in commands {
            let vault = FileManager.default.temporaryDirectory
                .appendingPathComponent("cider-cli-migration-help-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: vault) }

            let result = try runCLI(args: args, vault: vault)

            #expect(result.status == 0, "Expected \(args.joined(separator: " ")) help to exit 0")
            #expect(result.stdout.contains("Usage: cider-cli \(args[0]) \(args[1])"))
            #expect(FileManager.default.fileExists(atPath: vault.path) == false)
            #expect(FileManager.default.fileExists(atPath: vault.appendingPathComponent(".cider").path) == false)
        }
    }

    @Test("review queue candidate rows explain source storage proposed change and quality")
    func reviewQueueCandidateRowsExplainSourceStorageProposedChangeAndQuality() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-review-explain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let journalID = try createNote(
            title: "Daily Journal 2026-06-08",
            content: "He usually wants really expensive stuff like an e-bike, but I am not buying that for this birthday. Later it moved closer and Ryker to have one became a confusing fragment. Jami loved pineapple coconut drink.",
            vault: vault
        )
        _ = try runCLI(args: ["item", "backfill-journals", "--date", "2026-06-08", "--limit", "5", "--json"], vault: vault)

        let reviewResult = try runCLI(args: ["capture", "review-queue", "--kind", "graph_candidate", "--limit", "20", "--json"], vault: vault)
        let review = try parseJSONObject(reviewResult.stdout)
        let items = try #require(review["items"] as? [[String: Any]])
        let graphItem = try #require(items.first { $0["kind"] as? String == "graph_candidate" })

        #expect(graphItem["reviewFamily"] as? String == "graph_candidate")
        #expect(graphItem["sourceItemRef"] as? String == "note:\(journalID)")
        #expect(graphItem["sourceItemTitle"] as? String == "Daily Journal 2026-06-08")
        #expect(graphItem["sourceItemDate"] as? String == "2026-06-08")
        #expect((graphItem["sourceQuote"] as? String)?.contains("e-bike") == true
            || (graphItem["sourceQuote"] as? String)?.contains("pineapple coconut") == true)
        #expect((graphItem["extractionReason"] as? String)?.contains("not accepted graph truth") == true
            || (graphItem["extractionReason"] as? String)?.contains("not truth") == true)
        #expect(graphItem["truthState"] as? String == "reviewable_candidate_not_truth")
        #expect((graphItem["safeNextCommands"] as? [String])?.contains { $0.contains("item graph-candidate") } == true)

        let proposedChange = try #require(graphItem["proposedChange"] as? [String: Any])
        #expect(proposedChange["changeType"] as? String == "graph_relation_candidate")
        #expect(proposedChange["truthState"] as? String == "reviewable_candidate_not_truth")
        let storage = try #require(graphItem["storage"] as? [String: Any])
        #expect(storage["table"] as? String == "enrichment_outputs")
        #expect(storage["service"] as? String == "SecondBrainEnrichmentOutputService")
        let quality = try #require(graphItem["quality"] as? [String: Any])
        #expect(quality["level"] as? String != nil)

        let lowQuality = CiderReviewQueueService.candidateQualitySignal(
            mentionText: "it moved closer",
            sourceQuote: "Later it moved closer."
        )
        #expect(lowQuality.level == "low")
        #expect(lowQuality.codes.contains("event_clause_not_object"))
    }

    @Test("review queue memory candidate filter exposes visible rows and explanation fields")
    func reviewQueueMemoryCandidateFilterExposesVisibleRowsAndExplanationFields() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-review-memory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let journalID = try createNote(
            title: "Daily Journal 2026-06-09",
            content: "Jami loved pineapple coconut drink. First weekend overtime in five years; hourly wages motivation helped. Jami wants Thai food next Friday.",
            vault: vault
        )
        _ = try runCLI(args: ["item", "backfill-journals", "--date", "2026-06-09", "--limit", "5", "--json"], vault: vault)

        let summaryResult = try runCLI(args: ["review", "summary", "--json"], vault: vault)
        let summary = try parseJSONObject(summaryResult.stdout)
        let countsByKind = try #require(summary["countsByKind"] as? [String: Any])
        let memoryCount = countsByKind["memory_candidate"] as? Int ?? 0
        #expect(memoryCount > 0)

        let memoryResult = try runCLI(args: ["capture", "review-queue", "--kind", "memory_candidate", "--limit", "20", "--json"], vault: vault)
        let memory = try parseJSONObject(memoryResult.stdout)
        let visibleMemoryItems = try #require(memory["items"] as? [[String: Any]])
        #expect(visibleMemoryItems.count == memoryCount)
        let item = try #require(visibleMemoryItems.first)
        #expect(item["kind"] as? String == "memory_candidate")
        #expect(item["reviewFamily"] as? String == "memory_candidate")
        #expect(item["sourceItemRef"] as? String == "note:\(journalID)")
        #expect(item["truthState"] as? String == "reviewable_candidate_not_truth")
        #expect((item["extractionReason"] as? String)?.contains("not promoted until accepted") == true)
        #expect((item["acceptEffect"] as? String)?.contains("never writes user-owned memory truth") == true)
        let proposedChange = try #require(item["proposedChange"] as? [String: Any])
        #expect(proposedChange["changeType"] as? String == "memory_candidate")
        let storage = try #require(item["storage"] as? [String: Any])
        #expect(storage["kind"] as? String == "memory_candidate")

        let candidateID = try #require(item["candidateID"] as? String)
        try seedCoordinatorExactEvidence(candidateIDs: [candidateID], vault: vault)
        let acceptResult = try runCLI(args: ["item", "accept-memory-candidate", candidateID, "--actor", "codex-test", "--json"], vault: vault)
        let accept = try parseJSONObject(acceptResult.stdout)
        #expect(acceptResult.status == 0)
        #expect(accept["command"] as? String == "item.accept-memory-candidate")
        let receipt = try #require(accept["actionReceipt"] as? [String: Any])
        #expect(receipt["action"] as? String == "accept")
        #expect(receipt["actor"] as? String == "codex-test")
        #expect(receipt["changed"] as? Bool == true)
        #expect((receipt["sourceRefs"] as? [String])?.contains("memory_candidate:\(candidateID)") == true)

        let ledger = try parseJSONObject(try runCLI(args: ["item", "action-ledger", "list", "--owner", "note:\(journalID)", "--action", "approve", "--json"], vault: vault).stdout)
        let entries = try #require(ledger["entries"] as? [[String: Any]])
        #expect(entries.contains { entry in
            entry["command"] as? String == "review.memory-candidates.approve"
                && entry["status"] as? String == "succeeded"
                && entry["changed"] as? Bool == true
                && (entry["sourceRefs"] as? [String])?.contains("memory_candidate:\(candidateID)") == true
        })
    }

    @Test("item backfill journals supports dry run date selector and repeated runs stay bounded")
    func itemBackfillJournalsSupportsDryRunDateSelectorAndRepeatedRunsStayBounded() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-backfill-journals-selectors-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let selectedJournalID = try createNote(
            title: "Daily Journal 2026-06-01",
            content: "Jami loved pineapple coconut drink. First weekend overtime in five years; hourly wages motivation helped.",
            vault: vault
        )
        _ = try createNote(
            title: "Daily Journal 2026-06-02",
            content: "Alex prefers late coffee catch-ups.",
            vault: vault
        )
        _ = try createNote(
            title: "Regular Project Note",
            content: "Jami loved pineapple coconut drink.",
            vault: vault
        )

        let dryRunResult = try runCLI(args: [
            "item", "backfill-journals",
            "--date", "2026-06-01",
            "--limit", "5",
            "--dry-run",
            "--json",
        ], vault: vault)
        let dryRun = try parseJSONObject(dryRunResult.stdout)
        #expect(dryRun["ok"] as? Bool == true)
        #expect(dryRun["dryRun"] as? Bool == true)
        #expect(dryRun["changed"] as? Bool == false)
        #expect(dryRun["readOnly"] as? Bool == true)
        #expect(dryRun["selectedCount"] as? Int == 1)
        #expect(dryRun["skippedCount"] as? Int == 1)
        #expect(dryRun["errorCount"] as? Int == 0)
        #expect(dryRun["graphCandidateCount"] as? Int == 0)
        #expect(dryRun["memoryCandidateCount"] as? Int == 0)
        let dryRunOwners = try #require(dryRun["owners"] as? [[String: Any]])
        let dryRunOwner = try #require(dryRunOwners.first)
        #expect(dryRunOwner["date"] as? String == "2026-06-01")
        let dryRunOwnerRef = try #require(dryRunOwner["owner"] as? [String: Any])
        #expect(dryRunOwnerRef["ownerID"] as? String == selectedJournalID)

        let firstRunResult = try runCLI(args: [
            "item", "backfill-journals",
            "--date", "2026-06-01",
            "--limit", "5",
            "--json",
        ], vault: vault)
        let firstRun = try parseJSONObject(firstRunResult.stdout)
        #expect(firstRun["dryRun"] as? Bool == false)
        #expect(firstRun["selectedCount"] as? Int == 1)
        #expect(firstRun["skippedCount"] as? Int == 1)
        #expect((firstRun["graphCandidateCount"] as? Int ?? 0) > 0)
        #expect((firstRun["memoryCandidateCount"] as? Int ?? 0) > 0)

        let secondRunResult = try runCLI(args: [
            "item", "backfill-journals",
            "--date", "2026-06-01",
            "--limit", "5",
            "--json",
        ], vault: vault)
        let secondRun = try parseJSONObject(secondRunResult.stdout)
        #expect(secondRun["selectedCount"] as? Int == 1)
        #expect(secondRun["skippedCount"] as? Int == 1)
        #expect(secondRun["graphCandidateCount"] as? Int == firstRun["graphCandidateCount"] as? Int)
        #expect(secondRun["memoryCandidateCount"] as? Int == firstRun["memoryCandidateCount"] as? Int)
        #expect(secondRun["enrichmentOutputCount"] as? Int == firstRun["enrichmentOutputCount"] as? Int)
    }

    @Test("item backfill journals undated limit continues past already seeded owners")
    func itemBackfillJournalsUndatedLimitContinuesPastAlreadySeededOwners() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-backfill-journals-continuation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let seededJournalID = try createNote(
            title: "Daily Journal 2026-06-03",
            content: "Jami loved pineapple coconut drink. First weekend overtime in five years; hourly wages motivation helped.",
            vault: vault
        )
        let nextJournalID = try createNote(
            title: "Daily Journal 2026-06-02",
            content: "Alex prefers late coffee catch-ups and wants Thai food next Friday.",
            vault: vault
        )
        _ = try createNote(
            title: "Daily Journal 2026-06-01",
            content: "Morgan wants the rowing machine moved into the garage.",
            vault: vault
        )

        let seedRun = try parseJSONObject(try runCLI(args: [
            "item", "backfill-journals",
            "--date", "2026-06-03",
            "--limit", "1",
            "--json",
        ], vault: vault).stdout)
        #expect(seedRun["selectedCount"] as? Int == 1)
        #expect((seedRun["graphCandidateCount"] as? Int ?? 0) > 0)

        let beforeDryRunCounts = try generatedSecondBrainRowCounts(vault: vault)
        let dryRun = try parseJSONObject(try runCLI(args: [
            "item", "backfill-journals",
            "--limit", "1",
            "--dry-run",
            "--json",
        ], vault: vault).stdout)

        #expect(dryRun["dryRun"] as? Bool == true)
        #expect(dryRun["readOnly"] as? Bool == true)
        #expect(dryRun["selectedCount"] as? Int == 1)
        #expect(dryRun["skippedAlreadySeededCount"] as? Int == 1)
        #expect(dryRun["skippedCount"] as? Int == 2)
        #expect(try generatedSecondBrainRowCounts(vault: vault) == beforeDryRunCounts)

        let owners = try #require(dryRun["owners"] as? [[String: Any]])
        let selectedOwner = try #require(owners.first)
        let selectedRef = try #require(selectedOwner["owner"] as? [String: Any])
        #expect(selectedRef["ownerID"] as? String == nextJournalID)
        #expect(selectedOwner["date"] as? String == "2026-06-02")

        let skippedOwners = try #require(dryRun["skippedOwners"] as? [[String: Any]])
        let skippedSeeded = try #require(skippedOwners.first)
        let skippedRef = try #require(skippedSeeded["owner"] as? [String: Any])
        #expect(skippedRef["ownerID"] as? String == seededJournalID)
        #expect(skippedSeeded["date"] as? String == "2026-06-03")
        #expect(skippedSeeded["reason"] as? String == "already_seeded")
    }

    @Test("item dogfood intelligence exposes entity relation candidates through similarity JSON")
    func itemDogfoodIntelligenceExposesEntityRelationCandidatesThroughSimilarityJSON() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-entity-relation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        _ = try runCLI(
            args: [
                "capture", "add",
                "--kind", "contact",
                "--name", "Avery Stone",
                "--content", "Avery Stone",
                "--json"
            ],
            vault: vault
        )
        let noteID = try createNote(
            title: "Cafe follow-up",
            content: "Met Avery Stone at Sightglass and promised to send the launch graph notes.",
            vault: vault
        )

        let seedResult = try runCLI(args: ["item", "dogfood-intelligence", "--limit", "5", "--json"], vault: vault)
        let seed = try parseJSONObject(seedResult.stdout)
        #expect(seed["command"] as? String == "item.dogfood-intelligence")
        #expect((seed["similarityCandidateCount"] as? Int ?? 0) > 0)

        let similarityResult = try runCLI(args: ["item", "similarity", "note", noteID, "--json"], vault: vault)
        let similarity = try parseJSONObject(similarityResult.stdout)
        #expect(similarity["command"] as? String == "item.similarity")
        let candidates = try #require(similarity["candidates"] as? [[String: Any]])
        let candidate = try #require(candidates.first { $0["signal"] as? String == "entity_enrichment" })
        let targetOwner = try #require(candidate["targetOwner"] as? [String: Any])
        let metadata = try #require(candidate["metadata"] as? [String: Any])

        #expect(candidate["candidateType"] as? String == "mentions")
        #expect(candidate["source"] as? String == "enrichment_output")
        #expect(candidate["reviewState"] as? String == "suggested")
        #expect((candidate["evidence"] as? String)?.contains("Avery Stone") == true)
        #expect(targetOwner["ownerType"] as? String == "contact")
        #expect(metadata["matched_entity"] as? String == "Avery Stone")
        #expect(metadata["target_type"] as? String == "contact")

        let contextResult = try runCLI(args: ["item", "get", "note", noteID, "--json"], vault: vault)
        let context = try parseJSONObject(contextResult.stdout)
        let contextCandidates = try #require(context["relationCandidates"] as? [[String: Any]])
        #expect(contextCandidates.contains { relationCandidate in
            relationCandidate["signal"] as? String == "entity_enrichment"
                && relationCandidate["candidateType"] as? String == "mentions"
                && relationCandidate["reviewState"] as? String == "suggested"
        })
        let blockingIssues = try #require(context["blockingIssues"] as? [String])
        #expect(context["needsReview"] as? Bool == true)
        #expect(blockingIssues.contains("relation_candidates_need_review"))
    }

    @Test("item graph candidates exposes read-only list and inspect JSON")
    func itemGraphCandidatesExposesReadOnlyListAndInspectJSON() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-graph-candidates-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let noteID = try createNote(
            title: "Graph Candidate Source",
            content: "I gave Jami that pineapple coconut drink and she loved it.",
            vault: vault
        )
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: noteID)
        let output = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: "pineapple coconut drink",
            sourceQuote: "I gave Jami that pineapple coconut drink and she loved it.",
            sourceKind: "journal",
            objectTypeGuesses: [.drink],
            relationGuesses: [.likesDrink],
            actionGuesses: ["liked"],
            safeActions: [.inspectSource, .accept, .correct, .reject, .delegateEnrichment],
            confidence: 0.88,
            confidenceReason: "Sentence explicitly says Jami loved the drink.",
            subjectText: "Jami",
            source: "graph_candidate.test"
        )

        let db = CiderDatabase()
        try db.open(at: vault.appendingPathComponent(".cider/cider.db"))
        try SecondBrainEnrichmentOutputService(database: db).record(output)
        db.close()

        let listResult = try runCLI(args: ["item", "graph-candidates", "--json"], vault: vault)
        let list = try parseJSONObject(listResult.stdout)
        #expect(listResult.status == 0)
        #expect(list["ok"] as? Bool == true)
        #expect(list["command"] as? String == "item.graph-candidates")
        #expect(list["readOnly"] as? Bool == true)
        #expect(list["changed"] as? Bool == false)
        #expect(list["count"] as? Int == 1)
        #expect(list["limit"] as? Int == 20)

        let candidates = try #require(list["candidates"] as? [[String: Any]])
        let candidate = try #require(candidates.first)
        #expect(candidate["id"] as? String == output.id)
        #expect(candidate["ref"] as? String == "graph_candidate:\(output.id)")
        #expect(candidate["contractValid"] as? Bool == true)
        #expect(candidate["candidateKind"] as? String == "object_relation")
        #expect(candidate["mentionText"] as? String == "pineapple coconut drink")
        #expect(candidate["sourceQuote"] as? String == "I gave Jami that pineapple coconut drink and she loved it.")
        #expect(candidate["sourceKind"] as? String == "journal")
        #expect(candidate["reviewState"] as? String == "suggested")
        #expect(candidate["reviewable"] as? Bool == true)
        #expect(candidate["objectTypeGuesses"] as? [String] == ["drink"])
        #expect(candidate["relationGuesses"] as? [String] == ["likes_drink"])
        #expect(candidate["actionGuesses"] as? [String] == ["liked"])
        #expect(candidate["safeActions"] as? [String] == ["inspect_source", "accept", "correct", "reject", "delegate_enrichment"])
        let delegatedEnrichmentActions = try #require(candidate["delegatedEnrichmentActions"] as? [[String: Any]])
        #expect(delegatedEnrichmentActions.contains { action in
            action["kind"] as? String == "find_recipe_or_menu_evidence"
                && action["resultPolicy"] as? String == "return_reviewable_evidence_not_truth"
                && (action["command"] as? String)?.contains("delegate-graph-candidate \(output.id) --task-kind find_recipe_or_menu_evidence") == true
        })
        #expect(candidate["subjectText"] as? String == "Jami")
        #expect(candidate["confidenceReason"] as? String == "Sentence explicitly says Jami loved the drink.")

        let safeNextCommands = try #require(candidate["safeNextCommands"] as? [String])
        #expect(safeNextCommands.contains("cider-cli item graph-candidate \(output.id) --json"))
        #expect(safeNextCommands.contains("cider-cli item context note \(noteID) --json"))
        #expect(safeNextCommands.contains("cider-cli item graph-candidates note \(noteID) --json"))
        #expect(!safeNextCommands.contains { $0.contains("accept-graph-candidate") })

        let reviewActionCommands = try #require(candidate["reviewActionCommands"] as? [[String: Any]])
        #expect(reviewActionCommands.contains { action in
            action["action"] as? String == "accept"
                && action["readOnly"] as? Bool == false
                && action["status"] as? String == "available"
        })

        let reviewQueueResult = try runCLI(args: ["capture", "review-queue", "--kind", "graph_candidate", "--json"], vault: vault)
        let reviewQueue = try parseJSONObject(reviewQueueResult.stdout)
        #expect(reviewQueueResult.status == 0)
        #expect(reviewQueue["command"] as? String == "capture.review-queue")
        #expect(reviewQueue["readOnly"] as? Bool == true)
        #expect(reviewQueue["changed"] as? Bool == false)
        let reviewItems = try #require(reviewQueue["items"] as? [[String: Any]])
        #expect(reviewItems.allSatisfy { $0["kind"] as? String == "graph_candidate" })
        let reviewItem = try #require(reviewItems.first { $0["candidateID"] as? String == output.id })
        #expect(reviewItem["kind"] as? String == "graph_candidate")
        #expect(reviewItem["reviewState"] as? String == "suggested")
        #expect(reviewItem["sourceQuote"] as? String == "I gave Jami that pineapple coconut drink and she loved it.")
        #expect(reviewItem["possibleTypes"] as? [String] == ["drink"])
        #expect(reviewItem["recommendedNextAction"] as? String == "review_graph_candidate")
        let reviewSafeNext = try #require(reviewItem["safeNextCommands"] as? [String])
        #expect(reviewSafeNext.contains("cider-cli item graph-candidate \(output.id) --json"))
        #expect(!reviewSafeNext.contains { $0.contains("accept-graph-candidate") })

        let ownerListResult = try runCLI(args: ["item", "graph-candidates", "note", noteID, "--json"], vault: vault)
        let ownerList = try parseJSONObject(ownerListResult.stdout)
        #expect(ownerListResult.status == 0)
        #expect(ownerList["readOnly"] as? Bool == true)
        #expect(ownerList["changed"] as? Bool == false)
        #expect(ownerList["count"] as? Int == 1)
        let ownerPayload = try #require(ownerList["owner"] as? [String: Any])
        #expect(ownerPayload["ownerType"] as? String == "note")
        #expect(ownerPayload["ownerID"] as? String == noteID)

        let cappedListResult = try runCLI(args: ["item", "graph-candidates", "--limit", "0", "--json"], vault: vault)
        let cappedList = try parseJSONObject(cappedListResult.stdout)
        #expect(cappedListResult.status == 0)
        #expect(cappedList["count"] as? Int == 0)
        #expect(cappedList["limit"] as? Int == 0)
        let cappedCandidates = try #require(cappedList["candidates"] as? [[String: Any]])
        #expect(cappedCandidates.isEmpty)

        let inspectResult = try runCLI(args: ["item", "graph-candidate", output.id, "--json"], vault: vault)
        let inspect = try parseJSONObject(inspectResult.stdout)
        #expect(inspectResult.status == 0)
        #expect(inspect["ok"] as? Bool == true)
        #expect(inspect["command"] as? String == "item.graph-candidate")
        #expect(inspect["readOnly"] as? Bool == true)
        #expect(inspect["changed"] as? Bool == false)
        let inspected = try #require(inspect["candidate"] as? [String: Any])
        #expect(inspected["id"] as? String == output.id)
        let inspectSafeCommands = try #require(inspect["safeNextCommands"] as? [String])
        #expect(!inspectSafeCommands.contains("cider-cli item graph-candidate \(output.id) --json"))
        #expect(inspectSafeCommands.contains("cider-cli item context note \(noteID) --json"))
    }

    @Test("recall context finds journal gas spending facts from natural fill up query")
    func recallContextFindsJournalGasSpendingFactsFromNaturalFillUpQuery() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-recall-gas-spending-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let journalID = try createNote(
            title: "Daily Journal 2026-06-11",
            content: """
            - 03:50 - Retroactive recovered journal entry — 2026-06-11 morning gas fill-up / commute

            Recovered from Hermes Discord session search after Visher clarified this was the later morning fill-up after the Duvall trip.

            Gas/fuel spending:
            - Filled up while driving to work in the morning.
            - Total: $81.07.
            - Fuel amount: 12.87 gallons.
            - Effective price: about $6.30/gallon.
            - Fuel grade: mid-grade / 89 octane.
            - Vehicle context: Visher said he should be getting premium because of the turbo in his Mazda CX-5, but premium would be even more expensive, so he has been using mid-grade.
            - Reaction: gas was "fricking ridiculous" / "too fucking expensive."
            """,
            vault: vault
        )

        let backfill = try parseJSONObject(try runCLI(args: ["item", "backfill-journals", "--date", "2026-06-11", "--json"], vault: vault).stdout)
        #expect(backfill["ok"] as? Bool == true)
        #expect(backfill["memoryCandidateCount"] as? Int == 1)

        let _ = try createNote(
            title: "Last Harbor on Steam",
            content: "A game page saved last time; unrelated to fuel spending.",
            vault: vault
        )

        for query in ["last time I filled up", "what did I spend on gas", "that expensive morning fill-up", "$81.07", "12.87 gallons"] {
            let result = try runCLI(args: ["item", "recall-context", "--query", query, "--limit", "1", "--json"], vault: vault)
            let payload = try parseJSONObject(result.stdout)
            #expect(result.status == 0, "query should succeed: \(query)")
            #expect(payload["ok"] as? Bool == true, "query should return ok=true: \(query)")
            let anchors = try #require(payload["anchors"] as? [[String: Any]])
            #expect(anchors.contains { (($0["item"] as? [String: Any])?["id"] as? String) == journalID }, "query should anchor the gas journal: \(query)")
            let candidates = try #require(payload["reviewableCandidates"] as? [[String: Any]])
            let gasCandidate = try #require(candidates.first { ($0["metadata"] as? [String: String])?["memory_key"] == "spending-gas-fill-up-2026-06-11-81.07" })
            #expect(gasCandidate["truthState"] as? String == "reviewable_candidate_not_truth")
            #expect(gasCandidate["sourceQuote"] as? String != nil)
            #expect((gasCandidate["metadata"] as? [String: String])?["amount"] == "81.07")
            #expect((gasCandidate["metadata"] as? [String: String])?["quantity"] == "12.87")
            #expect((gasCandidate["metadata"] as? [String: String])?["unit_price"] == "6.30")
            #expect((gasCandidate["sourceEvidenceRecord"] as? [String: Any])?["sourceOwnerRef"] as? String == "note:\(journalID)")
            let review = try #require(payload["reviewStatus"] as? [String: Any])
            #expect(review["needsReview"] as? Bool == true)
            #expect((review["blockingIssues"] as? [String])?.contains("memory_candidates_need_review") == true)
        }
    }

    @Test("recall context finds prose journal spending candidates")
    func recallContextFindsProseJournalSpendingCandidates() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-recall-prose-spending-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let journalID = try createNote(
            title: "Daily Journal 2026-06-13",
            content: """
            Lunch and errand spending:
            Visher grabbed Panda Express for lunch and spent $17.42 on orange chicken and chow mein.
            At the gas station, he also bought a Monster and a protein bar for about $9.58.
            """,
            vault: vault
        )
        let _ = try createNote(
            title: "Panda movie list",
            content: "A distracting note about panda documentaries and gas station scenery, but no spending facts.",
            vault: vault
        )

        let backfill = try parseJSONObject(try runCLI(args: ["item", "backfill-journals", "--date", "2026-06-13", "--json"], vault: vault).stdout)
        #expect(backfill["ok"] as? Bool == true)
        #expect(backfill["memoryCandidateCount"] as? Int == 2)

        for (query, key) in [
            ("what did I spend on food", "spending-food-2026-06-13-17.42"),
            ("Panda Express $17.42", "spending-food-2026-06-13-17.42"),
            ("gas station treats", "spending-gas-station-2026-06-13-9.58"),
        ] {
            let result = try runCLI(args: ["item", "recall-context", "--query", query, "--limit", "1", "--json"], vault: vault)
            let payload = try parseJSONObject(result.stdout)
            #expect(result.status == 0, "query should succeed: \(query)")
            #expect(payload["ok"] as? Bool == true, "query should return ok=true: \(query)")
            let anchors = try #require(payload["anchors"] as? [[String: Any]])
            #expect(anchors.contains { (($0["item"] as? [String: Any])?["id"] as? String) == journalID }, "query should anchor the spending journal: \(query)")
            let candidates = try #require(payload["reviewableCandidates"] as? [[String: Any]])
            let candidate = try #require(candidates.first { ($0["metadata"] as? [String: String])?["memory_key"] == key })
            #expect(candidate["truthState"] as? String == "reviewable_candidate_not_truth")
            #expect((candidate["sourceEvidenceRecord"] as? [String: Any])?["sourceOwnerRef"] as? String == "note:\(journalID)")
        }
    }

    @Test("journal spending memory candidates can be accepted and recalled as cited truth")
    func journalSpendingMemoryCandidatesCanBeAcceptedAndRecalledAsCitedTruth() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-accept-journal-spending-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let journalID = try createNote(
            title: "Daily Journal 2026-06-11",
            content: """
            - 03:50 - Retroactive recovered journal entry — 2026-06-11 morning gas fill-up / commute

            Recovered from Hermes Discord session search after Visher clarified this was the later morning fill-up after the Duvall trip.

            Gas/fuel spending:
            - Filled up while driving to work in the morning.
            - Total: $81.07.
            - Fuel amount: 12.87 gallons.
            - Effective price: about $6.30/gallon.
            - Fuel grade: mid-grade / 89 octane.
            - Vehicle context: Visher said he should be getting premium because of the turbo in his Mazda CX-5, but premium would be even more expensive, so he has been using mid-grade.
            - Reaction: gas was "fricking ridiculous" / "too fucking expensive."
            """,
            vault: vault
        )

        let backfill = try parseJSONObject(try runCLI(args: ["item", "backfill-journals", "--date", "2026-06-11", "--json"], vault: vault).stdout)
        let owners = try #require(backfill["owners"] as? [[String: Any]])
        let owner = try #require(owners.first)
        let memoryCandidates = try #require(owner["memoryCandidates"] as? [[String: Any]])
        let gasCandidate = try #require(memoryCandidates.first { ($0["metadata"] as? [String: String])?["memory_key"] == "spending-gas-fill-up-2026-06-11-81.07" })
        let candidateID = try #require(gasCandidate["id"] as? String)

        let accept = try assertStrictProcessJSON(
            runCLI(args: ["item", "accept-memory-candidate", candidateID, "--actor", "cody-test", "--json"], vault: vault),
            command: "item.accept-memory-candidate"
        )
        #expect(accept["changed"] as? Bool == true)
        #expect(accept["reviewState"] as? String == "accepted")
        let acceptedFact = try #require(accept["acceptedFact"] as? [String: Any])
        #expect(acceptedFact["truthBoundary"] as? String == "accepted_memory_fact")
        #expect(acceptedFact["truthState"] as? String == "accepted")
        #expect(acceptedFact["amount"] as? String == "81.07")
        #expect(acceptedFact["currency"] as? String == "USD")
        #expect(acceptedFact["quantity"] as? String == "12.87")
        #expect(acceptedFact["quantityUnit"] as? String == "gallons")
        #expect(acceptedFact["unitPrice"] as? String == "6.30")
        #expect(acceptedFact["unitPriceUnit"] as? String == "USD_per_gallon")
        #expect(acceptedFact["factType"] as? String == "fuel_purchase")
        #expect(acceptedFact["spendingCategory"] as? String == "gas")
        #expect(acceptedFact["dateContext"] as? String == "2026-06-11")
        #expect(acceptedFact["timeContext"] as? String == "03:50")
        #expect((acceptedFact["sourceEvidenceRecord"] as? [String: Any])?["sourceOwnerRef"] as? String == "note:\(journalID)")
        #expect((acceptedFact["sourceEvidenceRecord"] as? [String: Any])?["sourceQuote"] as? String != nil)
        #expect((acceptedFact["lifecycleHistory"] as? [[String: Any]])?.contains { $0["eventKind"] as? String == "accepted_truth_recorded" } == true)
        #expect(accept["actionReceipt"] != nil)

        let inspect = try assertStrictProcessJSON(
            runCLI(args: ["item", "memory-facts", "inspect", candidateID, "--json"], vault: vault),
            command: "item.memory-facts.inspect"
        )
        let inspectedFact = try #require(inspect["fact"] as? [String: Any])
        #expect(inspectedFact["amount"] as? String == "81.07")
        #expect(inspectedFact["sourceQuote"] as? String != nil)

        let recall = try assertStrictProcessJSON(
            runCLI(args: ["item", "recall-context", "--query", "what did I spend on gas", "--limit", "1", "--json"], vault: vault),
            command: "item.recall-context"
        )
        let acceptedFacts = try #require(recall["acceptedFacts"] as? [[String: Any]])
        #expect(acceptedFacts.contains { fact in
            fact["candidateID"] as? String == candidateID
                && fact["truthState"] as? String == "accepted"
                && fact["truthBoundary"] as? String == "accepted_memory_fact"
                && fact["amount"] as? String == "81.07"
        })
        let reviewable = try #require(recall["reviewableCandidates"] as? [[String: Any]])
        #expect(!reviewable.contains { $0["id"] as? String == candidateID })
        let contentBlocks = try #require(recall["contentBlocks"] as? [[String: Any]])
        #expect(contentBlocks.contains { ($0["citation"] as? [String: Any])?["ownerID"] as? String == journalID })
    }

    @Test("accepted and reviewable prose spending facts stay distinct in recall")
    func acceptedAndReviewableProseSpendingFactsStayDistinctInRecall() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-accept-prose-spending-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let journalID = try createNote(
            title: "Daily Journal 2026-06-13",
            content: """
            Lunch and errand spending:
            Visher grabbed Panda Express for lunch and spent $17.42 on orange chicken and chow mein.
            At the gas station, he also bought a Monster and a protein bar for about $9.58.
            """,
            vault: vault
        )

        let backfill = try parseJSONObject(try runCLI(args: ["item", "backfill-journals", "--date", "2026-06-13", "--json"], vault: vault).stdout)
        let owners = try #require(backfill["owners"] as? [[String: Any]])
        let owner = try #require(owners.first)
        let memoryCandidates = try #require(owner["memoryCandidates"] as? [[String: Any]])
        let foodCandidate = try #require(memoryCandidates.first { ($0["metadata"] as? [String: String])?["memory_key"] == "spending-food-2026-06-13-17.42" })
        let gasStationCandidate = try #require(memoryCandidates.first { ($0["metadata"] as? [String: String])?["memory_key"] == "spending-gas-station-2026-06-13-9.58" })
        let foodID = try #require(foodCandidate["id"] as? String)
        let gasStationID = try #require(gasStationCandidate["id"] as? String)

        let accept = try assertStrictProcessJSON(
            runCLI(args: ["item", "accept-memory-candidate", foodID, "--actor", "cody-test", "--json"], vault: vault),
            command: "item.accept-memory-candidate"
        )
        let acceptedFact = try #require(accept["acceptedFact"] as? [String: Any])
        #expect(acceptedFact["amount"] as? String == "17.42")
        #expect(acceptedFact["merchant"] as? String == "Panda Express")
        #expect(acceptedFact["factType"] as? String == "food_purchase")
        #expect((acceptedFact["sourceEvidenceRecord"] as? [String: Any])?["spanStart"] != nil)
        #expect((acceptedFact["sourceEvidenceRecord"] as? [String: Any])?["spanEnd"] != nil)

        let recall = try assertStrictProcessJSON(
            runCLI(args: ["item", "recall-context", "--query", "Panda Express lunch gas station Monster protein bar", "--limit", "1", "--json"], vault: vault),
            command: "item.recall-context"
        )
        let acceptedFacts = try #require(recall["acceptedFacts"] as? [[String: Any]])
        #expect(acceptedFacts.contains { fact in
            fact["candidateID"] as? String == foodID
                && fact["truthState"] as? String == "accepted"
                && fact["merchant"] as? String == "Panda Express"
        })
        let reviewable = try #require(recall["reviewableCandidates"] as? [[String: Any]])
        #expect(reviewable.contains { candidate in
            candidate["id"] as? String == gasStationID
                && candidate["truthState"] as? String == "reviewable_candidate_not_truth"
                && (candidate["metadata"] as? [String: String])?["amount"] == "9.58"
        })
        #expect(!reviewable.contains { $0["id"] as? String == foodID })
        let contentBlocks = try #require(recall["contentBlocks"] as? [[String: Any]])
        #expect(contentBlocks.contains { ($0["citation"] as? [String: Any])?["ownerID"] as? String == journalID })
    }

    @Test("payroll rate facts recall and gross pay calculation stay source backed")
    func payrollRateFactsRecallAndGrossPayCalculationStaySourceBacked() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-payroll-rate-recall-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let journalID = try createNote(
            title: "Daily Journal 2026-06-13",
            content: """
            Current Wage Card note:
            IAM Grade 5 max at Boeing has straight-time hourly rate $54.84/hr.
            Time-and-a-half overtime rate is $82.26/hr.
            Double-time Sunday rate is $109.68/hr.
            """,
            vault: vault
        )
        _ = try createNote(
            title: "Gross Pay Worksheet",
            content: "A distracting note about 40 straight hours, 16.2 overtime hours, and 8.3 double-time hours without source-backed rates.",
            vault: vault
        )

        let backfill = try parseJSONObject(try runCLI(args: ["item", "backfill-journals", "--date", "2026-06-13", "--json"], vault: vault).stdout)
        #expect(backfill["ok"] as? Bool == true)
        #expect(backfill["memoryCandidateCount"] as? Int == 3)

        let reviewableRecall = try assertStrictProcessJSON(
            runCLI(args: ["item", "recall-context", "--query", "what is my hourly rate, time and a half, and double time rate?", "--limit", "1", "--json"], vault: vault),
            command: "item.recall-context"
        )
        let reviewableCandidates = try #require(reviewableRecall["reviewableCandidates"] as? [[String: Any]])
        let straightReviewable = try #require(reviewableCandidates.first { ($0["metadata"] as? [String: String])?["rate_kind"] == "straight_time" })
        #expect(straightReviewable["truthState"] as? String == "reviewable_candidate_not_truth")
        #expect((straightReviewable["metadata"] as? [String: String])?["hourly_rate"] == "54.84")
        #expect((straightReviewable["sourceEvidenceRecord"] as? [String: Any])?["sourceOwnerRef"] as? String == "note:\(journalID)")
        #expect((reviewableRecall["acceptedFacts"] as? [[String: Any]])?.isEmpty == true)
        let reviewableAnswer = try #require(reviewableRecall["answer"] as? [String: Any])
        #expect(reviewableAnswer["kind"] as? String == "payroll_rates")
        #expect(reviewableAnswer["acceptedTruthAvailable"] as? Bool == false)
        #expect(reviewableAnswer["reviewRequired"] as? Bool == true)
        #expect(reviewableAnswer["truthBoundary"] as? String == "derived_from_reviewable_source_backed_evidence_not_accepted_truth")
        #expect((reviewableAnswer["summary"] as? String)?.contains("reviewable source-backed payroll rate candidates, not accepted memory truth") == true)
        let reviewableRates = try #require(reviewableAnswer["rates"] as? [[String: Any]])
        #expect(reviewableRates.contains { $0["rateKind"] as? String == "straight_time" && $0["label"] as? String == "straight-time hourly rate" && $0["formattedHourlyRate"] as? String == "$54.84/hr" && $0["truthState"] as? String == "reviewable_candidate_not_truth" })
        #expect(reviewableRates.contains { $0["rateKind"] as? String == "time_and_a_half" && $0["label"] as? String == "time-and-a-half" && $0["formattedHourlyRate"] as? String == "$82.26/hr" && $0["truthState"] as? String == "reviewable_candidate_not_truth" })
        #expect(reviewableRates.contains { $0["rateKind"] as? String == "double_time" && $0["label"] as? String == "double-time" && $0["formattedHourlyRate"] as? String == "$109.68/hr" && $0["truthState"] as? String == "reviewable_candidate_not_truth" })

        let reviewableGrossRecall = try assertStrictProcessJSON(
            runCLI(args: ["item", "recall-context", "--query", "gross pay for 40 straight + 16.2 OT + 8.3 DT", "--limit", "1", "--json"], vault: vault),
            command: "item.recall-context"
        )
        #expect((reviewableGrossRecall["acceptedFacts"] as? [[String: Any]])?.isEmpty == true)
        let reviewableGrossAnswer = try #require(reviewableGrossRecall["answer"] as? [String: Any])
        #expect(reviewableGrossAnswer["kind"] as? String == "gross_pay")
        #expect(reviewableGrossAnswer["acceptedTruthAvailable"] as? Bool == false)
        #expect(reviewableGrossAnswer["reviewRequired"] as? Bool == true)
        #expect(reviewableGrossAnswer["formattedTotal"] as? String == "$4,436.56")
        #expect(reviewableGrossAnswer["truthBoundary"] as? String == "derived_from_reviewable_source_backed_evidence_not_accepted_truth")
        #expect((reviewableGrossAnswer["summary"] as? String)?.contains("reviewable source-backed payroll rate candidates, not accepted memory truth") == true)
        let reviewableGrossComponents = try #require(reviewableGrossAnswer["components"] as? [[String: Any]])
        #expect(reviewableGrossComponents.contains { $0["rateKind"] as? String == "straight_time" && $0["expression"] as? String == "40 * 54.84" && $0["amount"] as? String == "2193.60" && $0["truthState"] as? String == "reviewable_candidate_not_truth" })
        #expect(reviewableGrossComponents.contains { $0["rateKind"] as? String == "time_and_a_half" && $0["expression"] as? String == "16.2 * 82.26" && $0["amount"] as? String == "1332.61" && $0["truthState"] as? String == "reviewable_candidate_not_truth" })
        #expect(reviewableGrossComponents.contains { $0["rateKind"] as? String == "double_time" && $0["expression"] as? String == "8.3 * 109.68" && $0["amount"] as? String == "910.34" && $0["truthState"] as? String == "reviewable_candidate_not_truth" })
        let calculations = try #require(reviewableGrossRecall["derivedCalculations"] as? [[String: Any]])
        let grossPay = try #require(calculations.first { $0["kind"] as? String == "gross_pay" })
        #expect(grossPay["mathBoundary"] as? String == "deterministic_decimal")
        #expect(grossPay["truthBoundary"] as? String == "derived_from_source_backed_memory_facts")
        #expect(grossPay["reviewRequired"] as? Bool == true)
        #expect(grossPay["formattedTotal"] as? String == "$4,436.56")
        #expect(grossPay["total"] as? String == "4436.56")
        #expect(grossPay["formula"] as? String == "40 * 54.84 + 16.2 * 82.26 + 8.3 * 109.68")
        let components = try #require(grossPay["components"] as? [[String: Any]])
        #expect(components.contains { $0["rateKind"] as? String == "straight_time" && $0["expression"] as? String == "40 * 54.84" && $0["amount"] as? String == "2193.60" && $0["truthState"] as? String == "reviewable_candidate_not_truth" })
        #expect(components.contains { $0["rateKind"] as? String == "time_and_a_half" && $0["expression"] as? String == "16.2 * 82.26" && $0["amount"] as? String == "1332.61" && $0["truthState"] as? String == "reviewable_candidate_not_truth" })
        #expect(components.contains { $0["rateKind"] as? String == "double_time" && $0["expression"] as? String == "8.3 * 109.68" && $0["amount"] as? String == "910.34" && $0["truthState"] as? String == "reviewable_candidate_not_truth" })
        let contentBlocks = try #require(reviewableGrossRecall["contentBlocks"] as? [[String: Any]])
        #expect(contentBlocks.contains { ($0["citation"] as? [String: Any])?["ownerID"] as? String == journalID })
    }

    @Test("drive home journal backfill recalls daily life candidates as source backed reviewables")
    func driveHomeJournalBackfillRecallsDailyLifeCandidatesAsSourceBackedReviewables() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-drive-home-life-facts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let journalID = try createNote(
            title: "Daily Journal 2026-06-19",
            content: """
            Drive-home journal, 2026-06-19.
            I had my dental appointment at 12:30 today where they placed the dental implant post in my jaw. Later I need the crown or veneer or tooth put on, and I was a little worried about recovery, so I decided to be lazy and rest after.
            At work I practiced riveting for the first time in 5+ years. I shot size 8 rivets through the skin with a narrow bucking bar, damaged the stringer a little, but it is probably not serious and the other rivets came out fine.
            For breakfast I had a Costco meat stick and a Costco chocolate-chip granola bar. Around 8:00 I got the cafeteria chicken-fried-steak burrito, liked it, and want to know if they have it every Friday so I can get it more often.
            I decided not to work this weekend.
            My best friend Chris has a son Jacob and Jacob's birthday party is today with Alfie's pizza and maybe a movie, but I will probably skip it because of the dental appointment.
            """,
            vault: vault
        )
        _ = try createNote(
            title: "Dental tools reference",
            content: "Raw searchable distractor about dental implants, movies, pizza, and weekends.",
            vault: vault
        )

        let backfillResult = try runCLI(args: ["item", "backfill-journals", "--date", "2026-06-19"], vault: vault)
        #expect(backfillResult.status == 0)
        let reviewQueue = try parseJSONObject(try runCLI(args: ["capture", "review-queue", "--kind", "memory_candidate", "--limit", "20", "--json"], vault: vault).stdout)
        let candidates = try #require(reviewQueue["items"] as? [[String: Any]])
        let keys = Set(candidates.compactMap { $0["memoryKey"] as? String })
        #expect(keys.contains("dental-implant-post-placed-2026-06-19"))
        #expect(keys.contains("riveting-practice-stringer-incident-2026-06-19"))
        #expect(keys.contains("breakfast-costco-meat-stick-granola-bar-2026-06-19"))
        #expect(keys.contains("cafeteria-chicken-fried-steak-burrito-friday-2026-06-19"))
        #expect(keys.contains("no-weekend-work-plan-2026-06-19"))
        #expect(keys.contains("chris-son-jacob-birthday-party-2026-06-19"))

        for key in [
            "dental-implant-post-placed-2026-06-19",
            "riveting-practice-stringer-incident-2026-06-19",
            "breakfast-costco-meat-stick-granola-bar-2026-06-19",
            "cafeteria-chicken-fried-steak-burrito-friday-2026-06-19",
            "no-weekend-work-plan-2026-06-19",
            "chris-son-jacob-birthday-party-2026-06-19",
        ] {
            let candidate = try #require(candidates.first { $0["memoryKey"] as? String == key })
            #expect(candidate["truthState"] as? String == "reviewable_candidate_not_truth")
            #expect((candidate["sourceEvidenceRecord"] as? [String: Any])?["sourceOwnerRef"] as? String == "note:\(journalID)")
            #expect((candidate["sourceEvidenceRecord"] as? [String: Any])?["spanStart"] != nil)
            #expect((candidate["sourceEvidenceRecord"] as? [String: Any])?["sourceQuote"] as? String != nil)
        }

        let recall = try assertStrictProcessJSON(
            runCLI(args: ["item", "recall-context", "--query", "what was the dental implant recovery plan?", "--limit", "1", "--json"], vault: vault),
            command: "item.recall-context"
        )
        #expect(recall["readOnly"] as? Bool == true)
        #expect(recall["changed"] as? Bool == false)
        let recallCandidates = try #require(recall["reviewableCandidates"] as? [[String: Any]])
        let recallCandidate = try #require(recallCandidates.first {
            $0["reviewFamily"] as? String == "memory_candidate"
                && $0["memoryKey"] as? String == "dental-implant-post-placed-2026-06-19"
        })
        #expect((recallCandidate["candidateRef"] as? String)?.hasPrefix("memory_candidate:") == true)
        #expect(recallCandidate["truthState"] as? String == "reviewable_candidate_not_truth")
        #expect((recallCandidate["extractionReason"] as? String)?.contains("not user-owned memory truth until accepted") == true)
        #expect((recallCandidate["sourceEvidenceRecord"] as? [String: Any])?["sourceOwnerRef"] as? String == "note:\(journalID)")
        #expect((recallCandidate["sourceEvidenceRecord"] as? [String: Any])?["sourceQuote"] as? String != nil)
        #expect(recallCandidate["citation"] as? [String: Any] != nil)
        #expect((recallCandidate["safeNextCommands"] as? [String])?.contains("cider-cli item context note \(journalID) --json") == true)

        let graphQueue = try parseJSONObject(try runCLI(args: ["capture", "review-queue", "--kind", "graph_candidate", "--limit", "20", "--json"], vault: vault).stdout)
        let graphItems = try #require(graphQueue["items"] as? [[String: Any]])
        #expect(!graphItems.contains { $0["value"] as? String == "to get it more often" })
    }

    @Test("daily tracker rows roll up journal food spending and routine candidates without making reviewables truth")
    func dailyTrackerRowsRollUpJournalFoodSpendingAndRoutineCandidatesWithoutMakingReviewablesTruth() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-daily-tracker-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let firstJournalID = try createNote(
            title: "Daily Journal 2026-06-13",
            content: """
            Lunch and errand spending:
            Visher grabbed Panda Express for lunch and spent $17.42 on orange chicken and chow mein.
            At the gas station, he also bought a Monster and a protein bar for about $9.58.
            """,
            vault: vault
        )
        let secondJournalID = try createNote(
            title: "Daily Journal 2026-06-19",
            content: """
            For breakfast I had a Costco meat stick and a Costco chocolate-chip granola bar.
            Around 8:00 I got the cafeteria chicken-fried-steak burrito, liked it, and want to know if they have it every Friday so I can get it more often.
            I decided not to work this weekend.
            """,
            vault: vault
        )

        _ = try parseJSONObject(try runCLI(args: ["item", "backfill-journals", "--date", "2026-06-13", "--json"], vault: vault).stdout)
        _ = try parseJSONObject(try runCLI(args: ["item", "backfill-journals", "--date", "2026-06-19", "--json"], vault: vault).stdout)

        let payload = try assertStrictProcessJSON(
            runCLI(args: ["item", "daily-tracker", "--from", "2026-06-13", "--to", "2026-06-19", "--json"], vault: vault),
            command: "item.daily-tracker"
        )
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["candidateBoundary"] as? String == "reviewable_candidates_are_not_truth")
        #expect(payload["truthBoundary"] as? String == "accepted_rows_are_user_reviewed_truth_only")

        let rows = try #require(payload["rows"] as? [[String: Any]])
        #expect(rows.count >= 5)
        let panda = try #require(rows.first { $0["date"] as? String == "2026-06-13" && $0["amount"] as? String == "17.42" })
        #expect(panda["signalType"] as? String == "spending")
        #expect(panda["value"] as? String == "food")
        #expect(panda["reviewState"] as? String == "suggested")
        #expect(panda["truthState"] as? String == "reviewable_candidate_not_truth")
        #expect((panda["sourceRefs"] as? [String])?.contains("note:\(firstJournalID)") == true)
        #expect((panda["citation"] as? [String: Any])?["ownerID"] as? String == firstJournalID)
        #expect((panda["safeNextCommands"] as? [String])?.contains("cider-cli item context note \(firstJournalID) --json") == true)

        let breakfast = try #require(rows.first { $0["date"] as? String == "2026-06-19" && $0["value"] as? String == "breakfast" })
        #expect(breakfast["signalType"] as? String == "food")
        #expect(breakfast["truthState"] as? String == "reviewable_candidate_not_truth")
        #expect((breakfast["sourceRefs"] as? [String])?.contains("note:\(secondJournalID)") == true)

        let routine = try #require(rows.first { $0["date"] as? String == "2026-06-19" && $0["signalType"] as? String == "routine" })
        #expect(routine["value"] as? String == "weekend_work")
        #expect(routine["truthState"] as? String == "reviewable_candidate_not_truth")

        let rollups = try #require(payload["rollups"] as? [[String: Any]])
        let firstRollup = try #require(rollups.first { $0["date"] as? String == "2026-06-13" })
        #expect(firstRollup["spendingAmount"] as? String == "27.00")
        #expect(firstRollup["spendingRowCount"] as? Int == 2)
        #expect(firstRollup["acceptedRowCount"] as? Int == 0)
        #expect(firstRollup["reviewableRowCount"] as? Int == 2)
        let secondRollup = try #require(rollups.first { $0["date"] as? String == "2026-06-19" })
        #expect(secondRollup["foodRowCount"] as? Int == 2)
        #expect(secondRollup["routineRowCount"] as? Int == 1)

        let limitedPayload = try assertStrictProcessJSON(
            runCLI(args: ["item", "daily-tracker", "--from", "2026-06-13", "--to", "2026-06-19", "--limit", "2", "--json"], vault: vault),
            command: "item.daily-tracker"
        )
        #expect((limitedPayload["filters"] as? [String: Any])?["limit"] as? Int == 2)
        let limitedRows = try #require(limitedPayload["rows"] as? [[String: Any]])
        #expect(limitedRows.count == 2)
        let limitedRollups = try #require(limitedPayload["rollups"] as? [[String: Any]])
        let limitedRollupRowCount = limitedRollups.compactMap { $0["rowCount"] as? Int }.reduce(0, +)
        #expect(limitedRollupRowCount == limitedRows.count)
    }

    @Test("daily tracker backfill surfaces natural journal prose as source backed reviewables")
    func dailyTrackerBackfillSurfacesNaturalJournalProseAsSourceBackedReviewables() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-daily-tracker-natural-prose-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let firstJournalID = try createNote(
            title: "Daily Journal 2026-06-13",
            content: """
            Breakfast was overnight oats at home. Lunch was Panda Express, orange chicken and fried rice, cost $11.91. Took a shower after work.
            """,
            vault: vault
        )
        let secondJournalID = try createNote(
            title: "Daily Journal 2026-06-14",
            content: """
            Dinner was chicken casserole at home. Everyone liked the chicken casserole. Stopped for gas and paid $27.00. No workout today, just a family routine night.
            """,
            vault: vault
        )

        _ = try assertStrictProcessJSON(
            runCLI(args: ["item", "backfill-journals", "--date", "2026-06-13", "--json"], vault: vault),
            command: "item.backfill-journals"
        )
        _ = try assertStrictProcessJSON(
            runCLI(args: ["item", "backfill-journals", "--date", "2026-06-14", "--json"], vault: vault),
            command: "item.backfill-journals"
        )

        let payload = try assertStrictProcessJSON(
            runCLI(args: ["item", "daily-tracker", "--from", "2026-06-13", "--to", "2026-06-14", "--json"], vault: vault),
            command: "item.daily-tracker"
        )
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["candidateBoundary"] as? String == "reviewable_candidates_are_not_truth")

        let rows = try #require(payload["rows"] as? [[String: Any]])
        #expect(rows.count >= 7)
        #expect(rows.allSatisfy { $0["reviewState"] as? String == "suggested" })
        #expect(rows.allSatisfy { $0["truthState"] as? String == "reviewable_candidate_not_truth" })

        let breakfast = try #require(rows.first { $0["date"] as? String == "2026-06-13" && $0["signalType"] as? String == "food" && $0["value"] as? String == "breakfast" })
        #expect((breakfast["metadata"] as? [String: String])?["food_item"] == "overnight oats")
        #expect((breakfast["sourceRefs"] as? [String])?.contains("note:\(firstJournalID)") == true)
        #expect((breakfast["citation"] as? [String: Any])?["ownerID"] as? String == firstJournalID)
        #expect((breakfast["safeNextCommands"] as? [String])?.contains("cider-cli item context note \(firstJournalID) --json") == true)

        let panda = try #require(rows.first { $0["date"] as? String == "2026-06-13" && $0["amount"] as? String == "11.91" })
        #expect(panda["signalType"] as? String == "spending")
        #expect(panda["value"] as? String == "food")
        #expect((panda["metadata"] as? [String: String])?["merchant"] == "Panda Express")

        let shower = try #require(rows.first { $0["date"] as? String == "2026-06-13" && $0["signalType"] as? String == "routine" && $0["value"] as? String == "shower" })
        #expect((shower["sourceRefs"] as? [String])?.contains("note:\(firstJournalID)") == true)

        let dinner = try #require(rows.first { $0["date"] as? String == "2026-06-14" && $0["signalType"] as? String == "food" && $0["value"] as? String == "dinner" })
        #expect((dinner["metadata"] as? [String: String])?["food_item"] == "chicken casserole")
        #expect((dinner["sourceRefs"] as? [String])?.contains("note:\(secondJournalID)") == true)

        let familyPreference = try #require(rows.first { $0["date"] as? String == "2026-06-14" && $0["signalType"] as? String == "food" && ($0["metadata"] as? [String: String])?["preference_subject"] == "family" })
        #expect(familyPreference["value"] as? String == "chicken casserole")

        let gas = try #require(rows.first { $0["date"] as? String == "2026-06-14" && $0["amount"] as? String == "27.00" })
        #expect(gas["signalType"] as? String == "spending")
        #expect(gas["value"] as? String == "gas")

        let noWorkout = try #require(rows.first { $0["date"] as? String == "2026-06-14" && $0["signalType"] as? String == "routine" && $0["value"] as? String == "workout" })
        #expect((noWorkout["metadata"] as? [String: String])?["routine_status"] == "skipped")

        let rollups = try #require(payload["rollups"] as? [[String: Any]])
        let firstRollup = try #require(rollups.first { $0["date"] as? String == "2026-06-13" })
        #expect(firstRollup["foodRowCount"] as? Int == 1)
        #expect(firstRollup["spendingRowCount"] as? Int == 1)
        #expect(firstRollup["routineRowCount"] as? Int == 1)
        #expect(firstRollup["spendingAmount"] as? String == "11.91")
        #expect(firstRollup["reviewableRowCount"] as? Int == 3)
        let secondRollup = try #require(rollups.first { $0["date"] as? String == "2026-06-14" })
        #expect(secondRollup["foodRowCount"] as? Int == 2)
        #expect(secondRollup["spendingRowCount"] as? Int == 1)
        #expect(secondRollup["routineRowCount"] as? Int == 1)
        #expect(secondRollup["spendingAmount"] as? String == "27.00")
        #expect(secondRollup["reviewableRowCount"] as? Int == 4)
    }

    @Test("daily tracker query filters food spending amount gas and routine rows without crossing review boundary")
    func dailyTrackerQueryFiltersFoodSpendingAmountGasAndRoutineRowsWithoutCrossingReviewBoundary() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-daily-tracker-query-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let firstJournalID = try createNote(
            title: "Daily Journal 2026-06-13",
            content: "Lunch was Panda Express, orange chicken and fried rice, cost $11.91. Took a shower after work.",
            vault: vault
        )
        let secondJournalID = try createNote(
            title: "Daily Journal 2026-06-14",
            content: "Stopped for gas and paid $27.00. No workout today.",
            vault: vault
        )

        _ = try assertStrictProcessJSON(
            runCLI(args: ["item", "backfill-journals", "--date", "2026-06-13", "--json"], vault: vault),
            command: "item.backfill-journals"
        )
        _ = try assertStrictProcessJSON(
            runCLI(args: ["item", "backfill-journals", "--date", "2026-06-14", "--json"], vault: vault),
            command: "item.backfill-journals"
        )

        let pandaPayload = try assertStrictProcessJSON(
            runCLI(args: ["item", "daily-tracker", "--from", "2026-06-13", "--to", "2026-06-14", "--query", "Panda Express", "--json"], vault: vault),
            command: "item.daily-tracker"
        )
        #expect(pandaPayload["readOnly"] as? Bool == true)
        #expect(pandaPayload["changed"] as? Bool == false)
        #expect(pandaPayload["candidateBoundary"] as? String == "reviewable_candidates_are_not_truth")
        #expect((pandaPayload["filters"] as? [String: Any])?["query"] as? String == "Panda Express")
        #expect(pandaPayload["recallFallbacks"] == nil)
        let pandaRows = try #require(pandaPayload["rows"] as? [[String: Any]])
        #expect(!pandaRows.isEmpty)
        #expect(pandaRows.allSatisfy { ($0["metadata"] as? [String: String])?["merchant"] == "Panda Express" || ($0["sourceQuote"] as? String)?.contains("Panda Express") == true })
        let panda = try #require(pandaRows.first { $0["amount"] as? String == "11.91" })
        #expect(panda["signalType"] as? String == "spending")
        #expect(panda["reviewState"] as? String == "suggested")
        #expect(panda["truthState"] as? String == "reviewable_candidate_not_truth")
        #expect((panda["sourceRefs"] as? [String])?.contains("note:\(firstJournalID)") == true)
        #expect((panda["citation"] as? [String: Any])?["ownerID"] as? String == firstJournalID)

        let gasPayload = try assertStrictProcessJSON(
            runCLI(args: ["item", "daily-tracker", "--from", "2026-06-13", "--to", "2026-06-14", "--query", "gas", "--json"], vault: vault),
            command: "item.daily-tracker"
        )
        let gasRows = try #require(gasPayload["rows"] as? [[String: Any]])
        #expect(gasRows.count == 1)
        let gas = try #require(gasRows.first)
        #expect(gas["date"] as? String == "2026-06-14")
        #expect(gas["signalType"] as? String == "spending")
        #expect(gas["value"] as? String == "gas")
        #expect(gas["amount"] as? String == "27.00")
        #expect((gas["sourceRefs"] as? [String])?.contains("note:\(secondJournalID)") == true)
        #expect((gas["citation"] as? [String: Any])?["ownerID"] as? String == secondJournalID)

        let amountPayload = try assertStrictProcessJSON(
            runCLI(args: ["item", "daily-tracker", "--query", "27.00", "--json"], vault: vault),
            command: "item.daily-tracker"
        )
        let amountRows = try #require(amountPayload["rows"] as? [[String: Any]])
        #expect(amountRows.count == 1)
        #expect(amountRows.first?["amount"] as? String == "27.00")
        let amountRollups = try #require(amountPayload["rollups"] as? [[String: Any]])
        #expect(amountRollups.count == 1)
        #expect(amountRollups.first?["spendingAmount"] as? String == "27.00")
        #expect(amountRollups.first?["spendingRowCount"] as? Int == 1)
        #expect(amountRollups.first?["reviewableRowCount"] as? Int == 1)

        let workoutPayload = try assertStrictProcessJSON(
            runCLI(args: ["item", "daily-tracker", "--from", "2026-06-13", "--to", "2026-06-14", "--query", "workout", "--json"], vault: vault),
            command: "item.daily-tracker"
        )
        let workoutRows = try #require(workoutPayload["rows"] as? [[String: Any]])
        #expect(workoutRows.count == 1)
        let workout = try #require(workoutRows.first)
        #expect(workout["signalType"] as? String == "routine")
        #expect(workout["value"] as? String == "workout")
        #expect(workout["truthState"] as? String == "reviewable_candidate_not_truth")
        let workoutRollups = try #require(workoutPayload["rollups"] as? [[String: Any]])
        #expect(workoutRollups.count == 1)
        #expect(workoutRollups.first?["routineRowCount"] as? Int == 1)
        #expect(workoutRollups.first?["spendingRowCount"] as? Int == 0)
    }

    @Test("daily tracker yesterday queries narrow date while preserving reviewable food boundary")
    func dailyTrackerYesterdayQueriesNarrowDateWhilePreservingReviewableFoodBoundary() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-daily-tracker-yesterday-query-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let olderJournalID = try createNote(
            title: "Daily Journal 2026-06-18",
            content: "Breakfast was yogurt and berries.",
            vault: vault
        )
        let yesterdayJournalID = try createNote(
            title: "Daily Journal 2026-06-19",
            content: "For breakfast I had a Costco meat stick and a Costco chocolate-chip granola bar. Lunch was a cafeteria burrito.",
            vault: vault
        )

        let db = CiderDatabase()
        try db.open(at: vault.appendingPathComponent(".cider/cider.db"))
        defer { db.close() }
        let outputService = SecondBrainEnrichmentOutputService(database: db)
        try outputService.record(SecondBrainEnrichmentOutput(
            owner: SecondBrainOwnerRef(ownerType: "note", ownerID: olderJournalID),
            kind: "memory_candidate",
            value: "breakfast",
            normalizedValue: "cid-559-breakfast-older",
            label: "Breakfast",
            evidence: "Breakfast was yogurt and berries.",
            source: "daily_tracker_yesterday.test",
            confidence: 0.9,
            reviewState: "suggested",
            metadata: [
                "memory_kind": "food_routine",
                "candidate_kind": "food_routine",
                "meal": "breakfast",
                "food_item": "yogurt and berries",
                "journal_date": "2026-06-18",
                "source_owner_ref": "note:\(olderJournalID)",
                "source_quote": "Breakfast was yogurt and berries.",
            ]
        ))
        try outputService.record(SecondBrainEnrichmentOutput(
            owner: SecondBrainOwnerRef(ownerType: "note", ownerID: yesterdayJournalID),
            kind: "memory_candidate",
            value: "breakfast",
            normalizedValue: "cid-559-breakfast-yesterday",
            label: "Breakfast",
            evidence: "For breakfast I had a Costco meat stick and a Costco chocolate-chip granola bar.",
            source: "daily_tracker_yesterday.test",
            confidence: 0.9,
            reviewState: "suggested",
            metadata: [
                "memory_kind": "food_routine",
                "candidate_kind": "food_routine",
                "meal": "breakfast",
                "food_item": "Costco meat stick and Costco chocolate-chip granola bar",
                "journal_date": "2026-06-19",
                "source_owner_ref": "note:\(yesterdayJournalID)",
                "source_quote": "For breakfast I had a Costco meat stick and a Costco chocolate-chip granola bar.",
            ]
        ))
        try outputService.record(SecondBrainEnrichmentOutput(
            owner: SecondBrainOwnerRef(ownerType: "note", ownerID: yesterdayJournalID),
            kind: "memory_candidate",
            value: "lunch",
            normalizedValue: "cid-559-lunch-yesterday",
            label: "Lunch",
            evidence: "Lunch was a cafeteria burrito.",
            source: "daily_tracker_yesterday.test",
            confidence: 0.9,
            reviewState: "suggested",
            metadata: [
                "memory_kind": "food_routine",
                "candidate_kind": "food_routine",
                "meal": "lunch",
                "food_item": "cafeteria burrito",
                "journal_date": "2026-06-19",
                "source_owner_ref": "note:\(yesterdayJournalID)",
                "source_quote": "Lunch was a cafeteria burrito.",
            ]
        ))

        let environment = ["CIDER_DAILY_TRACKER_REFERENCE_DATE": "2026-06-20"]
        let breakfastPayload = try assertStrictProcessJSON(
            runCLI(
                args: ["item", "daily-tracker", "--query", "yesterday breakfast", "--sort", "newest", "--limit", "5", "--json"],
                vault: vault,
                environment: environment
            ),
            command: "item.daily-tracker"
        )
        #expect(breakfastPayload["readOnly"] as? Bool == true)
        #expect(breakfastPayload["changed"] as? Bool == false)
        #expect(breakfastPayload["candidateBoundary"] as? String == "reviewable_candidates_are_not_truth")
        #expect((breakfastPayload["filters"] as? [String: Any])?["query"] as? String == "yesterday breakfast")
        #expect((breakfastPayload["filters"] as? [String: Any])?["from"] as? String == "2026-06-19")
        #expect((breakfastPayload["filters"] as? [String: Any])?["to"] as? String == "2026-06-19")
        let breakfastInterpretation = try #require(breakfastPayload["queryInterpretation"] as? [String: Any])
        #expect(breakfastInterpretation["originalQuery"] as? String == "yesterday breakfast")
        #expect(breakfastInterpretation["remainingQuery"] as? String == "breakfast")
        #expect(breakfastInterpretation["normalizedMatchingQuery"] as? String == "breakfast")
        #expect(breakfastInterpretation["interpretationType"] as? String == "relativeYesterday")
        #expect(breakfastInterpretation["dateRangeSource"] as? String == "query")
        #expect(breakfastInterpretation["recognizedQueryDateType"] as? String == "relativeYesterday")
        #expect(breakfastInterpretation["recognizedQueryDateText"] as? String == "yesterday")
        #expect(breakfastInterpretation["recognizedQueryDate"] as? String == "2026-06-19")
        #expect((breakfastInterpretation["resolvedDateRange"] as? [String: Any])?["from"] as? String == "2026-06-19")
        #expect((breakfastInterpretation["resolvedDateRange"] as? [String: Any])?["to"] as? String == "2026-06-19")

        let breakfastRows = try #require(breakfastPayload["rows"] as? [[String: Any]])
        #expect(breakfastRows.count == 1)
        let breakfast = try #require(breakfastRows.first)
        #expect(breakfast["date"] as? String == "2026-06-19")
        #expect(breakfast["signalType"] as? String == "food")
        #expect(breakfast["value"] as? String == "breakfast")
        #expect(breakfast["reviewState"] as? String == "suggested")
        #expect(breakfast["truthState"] as? String == "reviewable_candidate_not_truth")
        #expect((breakfast["sourceRefs"] as? [String])?.contains("note:\(yesterdayJournalID)") == true)
        #expect((breakfast["citation"] as? [String: Any])?["ownerID"] as? String == yesterdayJournalID)
        #expect((breakfast["metadata"] as? [String: String])?["food_item"] == "Costco meat stick and Costco chocolate-chip granola bar")

        let eatPayload = try assertStrictProcessJSON(
            runCLI(
                args: ["item", "daily-tracker", "--query", "what did I eat yesterday", "--sort", "newest", "--limit", "5", "--json"],
                vault: vault,
                environment: environment
            ),
            command: "item.daily-tracker"
        )
        #expect(eatPayload["readOnly"] as? Bool == true)
        #expect(eatPayload["changed"] as? Bool == false)
        #expect(eatPayload["candidateBoundary"] as? String == "reviewable_candidates_are_not_truth")
        #expect((eatPayload["filters"] as? [String: Any])?["from"] as? String == "2026-06-19")
        #expect((eatPayload["filters"] as? [String: Any])?["to"] as? String == "2026-06-19")

        let eatRows = try #require(eatPayload["rows"] as? [[String: Any]])
        #expect(eatRows.count == 2)
        #expect(eatRows.allSatisfy { $0["date"] as? String == "2026-06-19" })
        #expect(eatRows.allSatisfy { $0["signalType"] as? String == "food" })
        #expect(eatRows.allSatisfy { $0["truthState"] as? String == "reviewable_candidate_not_truth" })
        #expect(eatRows.contains { $0["value"] as? String == "breakfast" })
        #expect(eatRows.contains { $0["value"] as? String == "lunch" })

        let rollups = try #require(eatPayload["rollups"] as? [[String: Any]])
        #expect(rollups.count == 1)
        #expect(rollups.first?["date"] as? String == "2026-06-19")
        #expect(rollups.first?["foodRowCount"] as? Int == 2)
        #expect(rollups.first?["reviewableRowCount"] as? Int == 2)
    }

    @Test("daily tracker explicit date flags win over yesterday query date normalization")
    func dailyTrackerExplicitDateFlagsWinOverYesterdayQueryDateNormalization() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-daily-tracker-yesterday-explicit-dates-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let olderJournalID = try createNote(
            title: "Daily Journal 2026-06-18",
            content: "Breakfast was yogurt and berries.",
            vault: vault
        )
        let yesterdayJournalID = try createNote(
            title: "Daily Journal 2026-06-19",
            content: "Breakfast was a Costco granola bar.",
            vault: vault
        )

        let db = CiderDatabase()
        try db.open(at: vault.appendingPathComponent(".cider/cider.db"))
        defer { db.close() }
        let outputService = SecondBrainEnrichmentOutputService(database: db)
        try outputService.record(SecondBrainEnrichmentOutput(
            owner: SecondBrainOwnerRef(ownerType: "note", ownerID: olderJournalID),
            kind: "memory_candidate",
            value: "breakfast",
            normalizedValue: "cid-559-explicit-breakfast-older",
            label: "Breakfast",
            evidence: "Breakfast was yogurt and berries.",
            source: "daily_tracker_yesterday.test",
            confidence: 0.9,
            reviewState: "suggested",
            metadata: [
                "memory_kind": "food_routine",
                "candidate_kind": "food_routine",
                "meal": "breakfast",
                "food_item": "yogurt and berries",
                "journal_date": "2026-06-18",
                "source_owner_ref": "note:\(olderJournalID)",
                "source_quote": "Breakfast was yogurt and berries.",
            ]
        ))
        try outputService.record(SecondBrainEnrichmentOutput(
            owner: SecondBrainOwnerRef(ownerType: "note", ownerID: yesterdayJournalID),
            kind: "memory_candidate",
            value: "breakfast",
            normalizedValue: "cid-559-explicit-breakfast-yesterday",
            label: "Breakfast",
            evidence: "Breakfast was a Costco granola bar.",
            source: "daily_tracker_yesterday.test",
            confidence: 0.9,
            reviewState: "suggested",
            metadata: [
                "memory_kind": "food_routine",
                "candidate_kind": "food_routine",
                "meal": "breakfast",
                "food_item": "Costco granola bar",
                "journal_date": "2026-06-19",
                "source_owner_ref": "note:\(yesterdayJournalID)",
                "source_quote": "Breakfast was a Costco granola bar.",
            ]
        ))

        let payload = try assertStrictProcessJSON(
            runCLI(
                args: [
                    "item", "daily-tracker",
                    "--from", "2026-06-18",
                    "--to", "2026-06-18",
                    "--query", "yesterday breakfast",
                    "--sort", "newest",
                    "--limit", "5",
                    "--json",
                ],
                vault: vault,
                environment: ["CIDER_DAILY_TRACKER_REFERENCE_DATE": "2026-06-20"]
            ),
            command: "item.daily-tracker"
        )
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["candidateBoundary"] as? String == "reviewable_candidates_are_not_truth")
        #expect((payload["filters"] as? [String: Any])?["query"] as? String == "yesterday breakfast")
        #expect((payload["filters"] as? [String: Any])?["from"] as? String == "2026-06-18")
        #expect((payload["filters"] as? [String: Any])?["to"] as? String == "2026-06-18")
        let interpretation = try #require(payload["queryInterpretation"] as? [String: Any])
        #expect(interpretation["originalQuery"] as? String == "yesterday breakfast")
        #expect(interpretation["remainingQuery"] as? String == "breakfast")
        #expect(interpretation["normalizedMatchingQuery"] as? String == "breakfast")
        #expect(interpretation["interpretationType"] as? String == "explicitDateFlags")
        #expect(interpretation["dateRangeSource"] as? String == "explicitDateFlags")
        #expect(interpretation["recognizedQueryDateType"] as? String == "relativeYesterday")
        #expect(interpretation["recognizedQueryDateText"] as? String == "yesterday")
        #expect(interpretation["recognizedQueryDate"] as? String == "2026-06-19")
        #expect((interpretation["resolvedDateRange"] as? [String: Any])?["from"] as? String == "2026-06-18")
        #expect((interpretation["resolvedDateRange"] as? [String: Any])?["to"] as? String == "2026-06-18")

        let rows = try #require(payload["rows"] as? [[String: Any]])
        #expect(rows.count == 1)
        let breakfast = try #require(rows.first)
        #expect(breakfast["date"] as? String == "2026-06-18")
        #expect((breakfast["metadata"] as? [String: String])?["food_item"] == "yogurt and berries")
        #expect((breakfast["sourceRefs"] as? [String])?.contains("note:\(olderJournalID)") == true)
        #expect((breakfast["citation"] as? [String: Any])?["ownerID"] as? String == olderJournalID)
    }

    @Test("daily tracker month day queries narrow date while preserving reviewable food boundary")
    func dailyTrackerMonthDayQueriesNarrowDateWhilePreservingReviewableFoodBoundary() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-daily-tracker-month-day-query-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let olderJournalID = try createNote(
            title: "Daily Journal 2026-06-18",
            content: "Breakfast was yogurt and berries.",
            vault: vault
        )
        let june19JournalID = try createNote(
            title: "Daily Journal 2026-06-19",
            content: "For breakfast I had a Costco meat stick and a Costco chocolate-chip granola bar. Lunch was a cafeteria burrito.",
            vault: vault
        )

        let db = CiderDatabase()
        try db.open(at: vault.appendingPathComponent(".cider/cider.db"))
        defer { db.close() }
        let outputService = SecondBrainEnrichmentOutputService(database: db)
        try outputService.record(SecondBrainEnrichmentOutput(
            owner: SecondBrainOwnerRef(ownerType: "note", ownerID: olderJournalID),
            kind: "memory_candidate",
            value: "breakfast",
            normalizedValue: "cid-560-breakfast-older",
            label: "Breakfast",
            evidence: "Breakfast was yogurt and berries.",
            source: "daily_tracker_month_day.test",
            confidence: 0.9,
            reviewState: "suggested",
            metadata: [
                "memory_kind": "food_routine",
                "candidate_kind": "food_routine",
                "meal": "breakfast",
                "food_item": "yogurt and berries",
                "journal_date": "2026-06-18",
                "source_owner_ref": "note:\(olderJournalID)",
                "source_quote": "Breakfast was yogurt and berries.",
            ]
        ))
        try outputService.record(SecondBrainEnrichmentOutput(
            owner: SecondBrainOwnerRef(ownerType: "note", ownerID: june19JournalID),
            kind: "memory_candidate",
            value: "breakfast",
            normalizedValue: "cid-560-breakfast-june-19",
            label: "Breakfast",
            evidence: "For breakfast I had a Costco meat stick and a Costco chocolate-chip granola bar.",
            source: "daily_tracker_month_day.test",
            confidence: 0.9,
            reviewState: "suggested",
            metadata: [
                "memory_kind": "food_routine",
                "candidate_kind": "food_routine",
                "meal": "breakfast",
                "food_item": "Costco meat stick and Costco chocolate-chip granola bar",
                "journal_date": "2026-06-19",
                "source_owner_ref": "note:\(june19JournalID)",
                "source_quote": "For breakfast I had a Costco meat stick and a Costco chocolate-chip granola bar.",
            ]
        ))
        try outputService.record(SecondBrainEnrichmentOutput(
            owner: SecondBrainOwnerRef(ownerType: "note", ownerID: june19JournalID),
            kind: "memory_candidate",
            value: "lunch",
            normalizedValue: "cid-560-lunch-june-19",
            label: "Lunch",
            evidence: "Lunch was a cafeteria burrito.",
            source: "daily_tracker_month_day.test",
            confidence: 0.9,
            reviewState: "suggested",
            metadata: [
                "memory_kind": "food_routine",
                "candidate_kind": "food_routine",
                "meal": "lunch",
                "food_item": "cafeteria burrito",
                "journal_date": "2026-06-19",
                "source_owner_ref": "note:\(june19JournalID)",
                "source_quote": "Lunch was a cafeteria burrito.",
            ]
        ))

        let environment = ["CIDER_DAILY_TRACKER_REFERENCE_DATE": "2026-06-20"]
        for query in [
            "June 19 breakfast",
            "June 19 2026 breakfast",
            "19 June breakfast",
            "19 June 2026 breakfast",
            "19 Jun breakfast",
            "6/19 breakfast",
            "6-19 breakfast",
            "6/19/2026 breakfast",
            "6-19-2026 breakfast",
        ] {
            let payload = try assertStrictProcessJSON(
                runCLI(
                    args: ["item", "daily-tracker", "--query", query, "--sort", "newest", "--limit", "5", "--json"],
                    vault: vault,
                    environment: environment
                ),
                command: "item.daily-tracker"
            )
            #expect(payload["readOnly"] as? Bool == true)
            #expect(payload["changed"] as? Bool == false)
            #expect(payload["candidateBoundary"] as? String == "reviewable_candidates_are_not_truth")
            #expect((payload["filters"] as? [String: Any])?["query"] as? String == query)
            #expect((payload["filters"] as? [String: Any])?["from"] as? String == "2026-06-19")
            #expect((payload["filters"] as? [String: Any])?["to"] as? String == "2026-06-19")
            let interpretation = try #require(payload["queryInterpretation"] as? [String: Any])
            #expect(interpretation["originalQuery"] as? String == query)
            #expect(interpretation["remainingQuery"] as? String == "breakfast")
            #expect(interpretation["normalizedMatchingQuery"] as? String == "breakfast")
            #expect((interpretation["resolvedDateRange"] as? [String: Any])?["from"] as? String == "2026-06-19")
            #expect((interpretation["resolvedDateRange"] as? [String: Any])?["to"] as? String == "2026-06-19")
            #expect(interpretation["dateRangeSource"] as? String == "query")
            if query == "19 June breakfast" {
                #expect(interpretation["interpretationType"] as? String == "dayMonthLiteral")
                #expect(interpretation["recognizedQueryDateType"] as? String == "dayMonthLiteral")
                #expect(interpretation["recognizedQueryDateText"] as? String == "19 June")
                #expect(interpretation["recognizedQueryDate"] as? String == "2026-06-19")
            }
            if query == "6/19 breakfast" {
                #expect(interpretation["interpretationType"] as? String == "numericDateLiteral")
                #expect(interpretation["recognizedQueryDateType"] as? String == "numericDateLiteral")
                #expect(interpretation["recognizedQueryDateText"] as? String == "6/19")
                #expect(interpretation["recognizedQueryDate"] as? String == "2026-06-19")
            }

            let rows = try #require(payload["rows"] as? [[String: Any]])
            #expect(rows.count == 1)
            let breakfast = try #require(rows.first)
            #expect(breakfast["date"] as? String == "2026-06-19")
            #expect(breakfast["signalType"] as? String == "food")
            #expect(breakfast["value"] as? String == "breakfast")
            #expect(breakfast["reviewState"] as? String == "suggested")
            #expect(breakfast["truthState"] as? String == "reviewable_candidate_not_truth")
            #expect((breakfast["sourceRefs"] as? [String])?.contains("note:\(june19JournalID)") == true)
            #expect((breakfast["citation"] as? [String: Any])?["ownerID"] as? String == june19JournalID)
            #expect((breakfast["metadata"] as? [String: String])?["food_item"] == "Costco meat stick and Costco chocolate-chip granola bar")

            let rollups = try #require(payload["rollups"] as? [[String: Any]])
            #expect(rollups.count == 1)
            #expect(rollups.first?["date"] as? String == "2026-06-19")
            #expect(rollups.first?["foodRowCount"] as? Int == 1)
            #expect(rollups.first?["reviewableRowCount"] as? Int == 1)

            if query == "19 June breakfast" {
                let safeVerificationCommands = try #require(payload["safeVerificationCommands"] as? [String])
                #expect(safeVerificationCommands.contains("cider-cli item daily-tracker --query '19 June breakfast' --sort newest --limit 5 --json"))
                #expect(safeVerificationCommands.contains("cider-cli item daily-tracker --json"))
                let safeNextCommands = try #require(payload["safeNextCommands"] as? [String])
                #expect(safeNextCommands.contains("cider-cli item daily-tracker --query '19 June breakfast' --sort newest --limit 5 --json"))
                #expect(safeNextCommands.contains("cider-cli capture review-queue --kind memory_candidate --json"))
            }
        }
    }

    @Test("daily tracker explicit date flags win over month day query date normalization")
    func dailyTrackerExplicitDateFlagsWinOverMonthDayQueryDateNormalization() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-daily-tracker-month-day-explicit-dates-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let olderJournalID = try createNote(
            title: "Daily Journal 2026-06-18",
            content: "Breakfast was yogurt and berries.",
            vault: vault
        )
        let june19JournalID = try createNote(
            title: "Daily Journal 2026-06-19",
            content: "Breakfast was a Costco granola bar.",
            vault: vault
        )

        let db = CiderDatabase()
        try db.open(at: vault.appendingPathComponent(".cider/cider.db"))
        defer { db.close() }
        let outputService = SecondBrainEnrichmentOutputService(database: db)
        try outputService.record(SecondBrainEnrichmentOutput(
            owner: SecondBrainOwnerRef(ownerType: "note", ownerID: olderJournalID),
            kind: "memory_candidate",
            value: "breakfast",
            normalizedValue: "cid-560-explicit-breakfast-older",
            label: "Breakfast",
            evidence: "Breakfast was yogurt and berries.",
            source: "daily_tracker_month_day.test",
            confidence: 0.9,
            reviewState: "suggested",
            metadata: [
                "memory_kind": "food_routine",
                "candidate_kind": "food_routine",
                "meal": "breakfast",
                "food_item": "yogurt and berries",
                "journal_date": "2026-06-18",
                "source_owner_ref": "note:\(olderJournalID)",
                "source_quote": "Breakfast was yogurt and berries.",
            ]
        ))
        try outputService.record(SecondBrainEnrichmentOutput(
            owner: SecondBrainOwnerRef(ownerType: "note", ownerID: june19JournalID),
            kind: "memory_candidate",
            value: "breakfast",
            normalizedValue: "cid-560-explicit-breakfast-june-19",
            label: "Breakfast",
            evidence: "Breakfast was a Costco granola bar.",
            source: "daily_tracker_month_day.test",
            confidence: 0.9,
            reviewState: "suggested",
            metadata: [
                "memory_kind": "food_routine",
                "candidate_kind": "food_routine",
                "meal": "breakfast",
                "food_item": "Costco granola bar",
                "journal_date": "2026-06-19",
                "source_owner_ref": "note:\(june19JournalID)",
                "source_quote": "Breakfast was a Costco granola bar.",
            ]
        ))

        let payload = try assertStrictProcessJSON(
            runCLI(
                args: [
                    "item", "daily-tracker",
                    "--from", "2026-06-18",
                    "--to", "2026-06-18",
                    "--query", "19 June breakfast",
                    "--sort", "newest",
                    "--limit", "5",
                    "--json",
                ],
                vault: vault,
                environment: ["CIDER_DAILY_TRACKER_REFERENCE_DATE": "2026-06-20"]
            ),
            command: "item.daily-tracker"
        )
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["candidateBoundary"] as? String == "reviewable_candidates_are_not_truth")
        #expect((payload["filters"] as? [String: Any])?["query"] as? String == "19 June breakfast")
        #expect((payload["filters"] as? [String: Any])?["from"] as? String == "2026-06-18")
        #expect((payload["filters"] as? [String: Any])?["to"] as? String == "2026-06-18")

        let rows = try #require(payload["rows"] as? [[String: Any]])
        #expect(rows.count == 1)
        let breakfast = try #require(rows.first)
        #expect(breakfast["date"] as? String == "2026-06-18")
        #expect((breakfast["metadata"] as? [String: String])?["food_item"] == "yogurt and berries")
        #expect((breakfast["sourceRefs"] as? [String])?.contains("note:\(olderJournalID)") == true)
        #expect((breakfast["citation"] as? [String: Any])?["ownerID"] as? String == olderJournalID)

        let safeVerificationCommands = try #require(payload["safeVerificationCommands"] as? [String])
        #expect(safeVerificationCommands.contains("cider-cli item daily-tracker --from 2026-06-18 --to 2026-06-18 --query '19 June breakfast' --sort newest --limit 5 --json"))
        #expect(safeVerificationCommands.contains("cider-cli item daily-tracker --json"))
        let safeNextCommands = try #require(payload["safeNextCommands"] as? [String])
        #expect(safeNextCommands.contains("cider-cli item daily-tracker --from 2026-06-18 --to 2026-06-18 --query '19 June breakfast' --sort newest --limit 5 --json"))
        #expect(safeNextCommands.contains("cider-cli capture review-queue --kind memory_candidate --json"))
    }

    @Test("daily tracker zero-result query emits broader item search fallback without making tracker truth")
    func dailyTrackerZeroResultQueryEmitsBroaderItemSearchFallbackWithoutMakingTrackerTruth() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-daily-tracker-zero-result-fallback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let payload = try assertStrictProcessJSON(
            runCLI(
                args: [
                    "item", "daily-tracker",
                    "--query", "last Panda Express",
                    "--sort", "newest",
                    "--limit", "3",
                    "--json",
                ],
                vault: vault
            ),
            command: "item.daily-tracker"
        )
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["candidateBoundary"] as? String == "reviewable_candidates_are_not_truth")
        #expect(payload["rowCount"] as? Int == 0)
        #expect((payload["rows"] as? [[String: Any]])?.isEmpty == true)
        #expect((payload["rollups"] as? [[String: Any]])?.isEmpty == true)

        let interpretation = try #require(payload["queryInterpretation"] as? [String: Any])
        #expect(interpretation["originalQuery"] as? String == "last Panda Express")
        #expect(interpretation["interpretationType"] as? String == "keywordOnly")

        let safeVerificationCommands = try #require(payload["safeVerificationCommands"] as? [String])
        #expect(safeVerificationCommands.contains("cider-cli item daily-tracker --query 'last Panda Express' --sort newest --limit 3 --json"))
        let safeNextCommands = try #require(payload["safeNextCommands"] as? [String])
        #expect(safeNextCommands.contains("cider-cli item daily-tracker --query 'last Panda Express' --sort newest --limit 3 --json"))

        let fallbacks = try #require(payload["recallFallbacks"] as? [[String: Any]])
        #expect(fallbacks.count == 1)
        let fallback = try #require(fallbacks.first)
        #expect(fallback["kind"] as? String == "broaderItemSearch")
        #expect(fallback["readOnly"] as? Bool == true)
        #expect(fallback["changed"] as? Bool == false)
        #expect(fallback["truthBoundary"] as? String == "broader_search_possible_source_lookup_not_daily_tracker_truth")
        #expect(fallback["candidateBoundary"] as? String == "not_a_reviewable_candidate")
        #expect(fallback["note"] as? String == "Daily tracker found no rows; use this read-only broader item search to look for possible source items without treating them as tracker truth.")
        #expect(fallback["originalQuery"] as? String == "last Panda Express")
        #expect(fallback["searchQuery"] as? String == "Panda Express")
        #expect(fallback["sort"] as? String == "newest")
        #expect(fallback["queryTransform"] as? String == "recency_operator_stripped")
        let fallbackCommands = try #require(fallback["safeNextCommands"] as? [String])
        #expect(fallbackCommands == ["cider-cli item search 'Panda Express' --sort newest --json"])
        #expect(payload["relatedSearchCommands"] as? [String] == ["cider-cli item search 'Panda Express' --sort newest --json"])
    }

    @Test("daily tracker zero-result most recent query strips recency operators from broader item search fallback")
    func dailyTrackerZeroResultMostRecentQueryStripsRecencyOperatorsFromBroaderItemSearchFallback() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-daily-tracker-most-recent-fallback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let payload = try assertStrictProcessJSON(
            runCLI(
                args: [
                    "item", "daily-tracker",
                    "--query", "most recent Panda Express",
                    "--json",
                ],
                vault: vault
            ),
            command: "item.daily-tracker"
        )
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["candidateBoundary"] as? String == "reviewable_candidates_are_not_truth")
        #expect(payload["rowCount"] as? Int == 0)

        let interpretation = try #require(payload["queryInterpretation"] as? [String: Any])
        #expect(interpretation["originalQuery"] as? String == "most recent Panda Express")

        let fallbacks = try #require(payload["recallFallbacks"] as? [[String: Any]])
        let fallback = try #require(fallbacks.first)
        #expect(fallback["readOnly"] as? Bool == true)
        #expect(fallback["changed"] as? Bool == false)
        #expect(fallback["truthBoundary"] as? String == "broader_search_possible_source_lookup_not_daily_tracker_truth")
        #expect(fallback["candidateBoundary"] as? String == "not_a_reviewable_candidate")
        #expect(fallback["originalQuery"] as? String == "most recent Panda Express")
        #expect(fallback["searchQuery"] as? String == "Panda Express")
        #expect(fallback["sort"] as? String == "newest")
        #expect(fallback["queryTransform"] as? String == "recency_operator_stripped")
        let fallbackCommands = try #require(fallback["safeNextCommands"] as? [String])
        #expect(fallbackCommands == ["cider-cli item search 'Panda Express' --sort newest --json"])
        #expect(payload["relatedSearchCommands"] as? [String] == ["cider-cli item search 'Panda Express' --sort newest --json"])
    }

    @Test("daily tracker zero-result non-recency query keeps broader item search relevance order")
    func dailyTrackerZeroResultNonRecencyQueryKeepsBroaderItemSearchRelevanceOrder() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-daily-tracker-zero-result-non-recency-fallback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let payload = try assertStrictProcessJSON(
            runCLI(
                args: [
                    "item", "daily-tracker",
                    "--query", "Panda Express",
                    "--json",
                ],
                vault: vault
            ),
            command: "item.daily-tracker"
        )
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["candidateBoundary"] as? String == "reviewable_candidates_are_not_truth")
        #expect(payload["rowCount"] as? Int == 0)

        let fallbacks = try #require(payload["recallFallbacks"] as? [[String: Any]])
        let fallback = try #require(fallbacks.first)
        #expect(fallback["truthBoundary"] as? String == "broader_search_possible_source_lookup_not_daily_tracker_truth")
        #expect(fallback["originalQuery"] as? String == "Panda Express")
        #expect(fallback["searchQuery"] as? String == "Panda Express")
        #expect(fallback["sort"] == nil)
        #expect(fallback["queryTransform"] == nil)
        let fallbackCommands = try #require(fallback["safeNextCommands"] as? [String])
        #expect(fallbackCommands == ["cider-cli item search 'Panda Express' --json"])
        #expect(payload["relatedSearchCommands"] as? [String] == ["cider-cli item search 'Panda Express' --json"])
    }

    @Test("daily tracker query replay command shell quotes apostrophes")
    func dailyTrackerQueryReplayCommandShellQuotesApostrophes() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-daily-tracker-query-replay-quoting-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let payload = try assertStrictProcessJSON(
            runCLI(
                args: [
                    "item", "daily-tracker",
                    "--from", "2026-06-18",
                    "--to", "2026-06-19",
                    "--query", "19 June Erik's gas",
                    "--sort", "newest",
                    "--limit", "3",
                    "--json",
                ],
                vault: vault,
                environment: ["CIDER_DAILY_TRACKER_REFERENCE_DATE": "2026-06-20"]
            ),
            command: "item.daily-tracker"
        )
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["candidateBoundary"] as? String == "reviewable_candidates_are_not_truth")

        let safeVerificationCommands = try #require(payload["safeVerificationCommands"] as? [String])
        #expect(safeVerificationCommands.contains("cider-cli item daily-tracker --from 2026-06-18 --to 2026-06-19 --query '19 June Erik'\\''s gas' --sort newest --limit 3 --json"))
        let safeNextCommands = try #require(payload["safeNextCommands"] as? [String])
        #expect(safeNextCommands.contains("cider-cli item daily-tracker --from 2026-06-18 --to 2026-06-19 --query '19 June Erik'\\''s gas' --sort newest --limit 3 --json"))
        let relatedSearchCommands = try #require(payload["relatedSearchCommands"] as? [String])
        #expect(relatedSearchCommands == ["cider-cli item search '19 June Erik'\\''s gas' --json"])
    }

    @Test("daily tracker query matches natural gas fill up phrasing without accepting reviewables")
    func dailyTrackerQueryMatchesNaturalGasFillUpPhrasingWithoutAcceptingReviewables() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-daily-tracker-gas-query-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let journalID = try createNote(
            title: "Daily Journal 2026-06-11",
            content: """
            - 03:50 - Retroactive recovered journal entry — 2026-06-11 morning gas fill-up / commute

            Recovered from Hermes Discord session search after Visher clarified this was the later morning fill-up after the Duvall trip.

            Gas/fuel spending:
            - Filled up while driving to work in the morning.
            - Total: $81.07.
            - Fuel amount: 12.87 gallons.
            - Effective price: about $6.30/gallon.
            - Fuel grade: mid-grade / 89 octane.
            - Vehicle context: Visher said he should be getting premium because of the turbo in his Mazda CX-5, but premium would be even more expensive, so he has been using mid-grade.
            - Reaction: gas was "fricking ridiculous" / "too fucking expensive."
            """,
            vault: vault
        )
        _ = try assertStrictProcessJSON(
            runCLI(args: ["item", "backfill-journals", "--date", "2026-06-11", "--json"], vault: vault),
            command: "item.backfill-journals"
        )

        for query in ["that expensive morning fill-up", "last expensive gas fillup", "$81.07", "12.87 gallons"] {
            let payload = try assertStrictProcessJSON(
                runCLI(args: ["item", "daily-tracker", "--from", "2026-06-11", "--to", "2026-06-11", "--query", query, "--json"], vault: vault),
                command: "item.daily-tracker"
            )
            #expect(payload["readOnly"] as? Bool == true, "query should stay read-only: \(query)")
            #expect(payload["changed"] as? Bool == false, "query should not mutate state: \(query)")
            #expect(payload["candidateBoundary"] as? String == "reviewable_candidates_are_not_truth")
            #expect((payload["filters"] as? [String: Any])?["query"] as? String == query)

            let rows = try #require(payload["rows"] as? [[String: Any]], "query should return rows: \(query)")
            #expect(rows.count == 1, "query should return only the gas row: \(query)")
            let gas = try #require(rows.first, "query should include the gas row: \(query)")
            #expect(gas["date"] as? String == "2026-06-11")
            #expect(gas["signalType"] as? String == "spending")
            #expect(gas["value"] as? String == "gas")
            #expect(gas["amount"] as? String == "81.07")
            #expect(gas["currency"] as? String == "USD")
            #expect(gas["reviewState"] as? String == "suggested")
            #expect(gas["truthState"] as? String == "reviewable_candidate_not_truth")
            #expect((gas["sourceRefs"] as? [String])?.contains("note:\(journalID)") == true)
            #expect((gas["citation"] as? [String: Any])?["ownerID"] as? String == journalID)
            #expect((gas["metadata"] as? [String: String])?["quantity"] == "12.87")
            #expect((gas["metadata"] as? [String: String])?["review_query_terms"]?.contains("expensive morning fill-up") == true)

            let rollups = try #require(payload["rollups"] as? [[String: Any]])
            #expect(rollups.count == 1)
            #expect(rollups.first?["date"] as? String == "2026-06-11")
            #expect(rollups.first?["spendingAmount"] as? String == "81.07")
            #expect(rollups.first?["spendingRowCount"] as? Int == 1)
            #expect(rollups.first?["reviewableRowCount"] as? Int == 1)
            #expect(rollups.first?["acceptedRowCount"] as? Int == 0)
        }

        let locationPayload = try assertStrictProcessJSON(
            runCLI(args: ["item", "daily-tracker", "--query", "gas fill up location", "--sort", "newest", "--limit", "1", "--json"], vault: vault),
            command: "item.daily-tracker"
        )
        #expect(locationPayload["readOnly"] as? Bool == true)
        #expect(locationPayload["changed"] as? Bool == false)
        #expect(locationPayload["candidateBoundary"] as? String == "reviewable_candidates_are_not_truth")
        #expect((locationPayload["filters"] as? [String: Any])?["query"] as? String == "gas fill up location")
        #expect((locationPayload["filters"] as? [String: Any])?["limit"] as? Int == 1)
        #expect((locationPayload["filters"] as? [String: Any])?["sort"] as? String == "newest")

        let locationRows = try #require(locationPayload["rows"] as? [[String: Any]])
        #expect(locationRows.count == 1)
        let locationGas = try #require(locationRows.first)
        #expect(locationGas["date"] as? String == "2026-06-11")
        #expect(locationGas["signalType"] as? String == "spending")
        #expect(locationGas["value"] as? String == "gas")
        #expect(locationGas["amount"] as? String == "81.07")
        #expect(locationGas["reviewState"] as? String == "suggested")
        #expect(locationGas["truthState"] as? String == "reviewable_candidate_not_truth")
        #expect((locationGas["sourceRefs"] as? [String])?.contains("note:\(journalID)") == true)
        #expect((locationGas["citation"] as? [String: Any])?["ownerID"] as? String == journalID)
        #expect((locationGas["metadata"] as? [String: String])?["related_entities"]?.contains("Duvall") == true)
        #expect((locationGas["metadata"] as? [String: String])?["related_entities"]?.contains("Mazda CX-5") == true)

        let locationRollups = try #require(locationPayload["rollups"] as? [[String: Any]])
        #expect(locationRollups.count == 1)
        #expect(locationRollups.first?["date"] as? String == "2026-06-11")
        #expect(locationRollups.first?["spendingAmount"] as? String == "81.07")
        #expect(locationRollups.first?["spendingRowCount"] as? Int == 1)
        #expect(locationRollups.first?["reviewableRowCount"] as? Int == 1)
        #expect(locationRollups.first?["acceptedRowCount"] as? Int == 0)

        let genericLocationPayload = try assertStrictProcessJSON(
            runCLI(args: ["item", "daily-tracker", "--query", "location", "--sort", "newest", "--limit", "1", "--json"], vault: vault),
            command: "item.daily-tracker"
        )
        #expect(genericLocationPayload["readOnly"] as? Bool == true)
        #expect(genericLocationPayload["changed"] as? Bool == false)
        #expect(genericLocationPayload["candidateBoundary"] as? String == "reviewable_candidates_are_not_truth")
        #expect((genericLocationPayload["rows"] as? [[String: Any]])?.isEmpty == true)
        #expect((genericLocationPayload["rollups"] as? [[String: Any]])?.isEmpty == true)
    }

    @Test("daily tracker newest sort returns latest matching query row without changing default limit order")
    func dailyTrackerNewestSortReturnsLatestMatchingQueryRowWithoutChangingDefaultLimitOrder() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-daily-tracker-newest-sort-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let olderJournalID = try createNote(
            title: "Daily Journal 2026-06-11",
            content: "Morning gas fill-up on the commute. Filled up with 12.87 gallons, 89 octane, and paid $81.07.",
            vault: vault
        )
        let newerJournalID = try createNote(
            title: "Daily Journal 2026-06-19",
            content: "Latest gas stop after work. Filled up with 9.12 gallons of fuel and paid $48.32.",
            vault: vault
        )

        let db = CiderDatabase()
        try db.open(at: vault.appendingPathComponent(".cider/cider.db"))
        defer { db.close() }
        let outputService = SecondBrainEnrichmentOutputService(database: db)
        try outputService.record(SecondBrainEnrichmentOutput(
            owner: SecondBrainOwnerRef(ownerType: "note", ownerID: olderJournalID),
            kind: "memory_candidate",
            value: "gas",
            normalizedValue: "cid-554-gas-older",
            label: "Gas spending",
            evidence: "Morning gas fill-up on the commute. Filled up with 12.87 gallons, 89 octane, and paid $81.07.",
            source: "daily_tracker_sort.test",
            confidence: 0.92,
            reviewState: "suggested",
            metadata: [
                "memory_kind": "spending_fact",
                "candidate_kind": "spending_fact",
                "spending_category": "gas",
                "amount": "81.07",
                "currency": "USD",
                "journal_date": "2026-06-11",
                "source_owner_ref": "note:\(olderJournalID)",
                "source_quote": "Morning gas fill-up on the commute. Filled up with 12.87 gallons, 89 octane, and paid $81.07.",
            ]
        ))
        try outputService.record(SecondBrainEnrichmentOutput(
            owner: SecondBrainOwnerRef(ownerType: "note", ownerID: newerJournalID),
            kind: "memory_candidate",
            value: "gas",
            normalizedValue: "cid-554-gas-newer",
            label: "Gas spending",
            evidence: "Latest gas stop after work. Filled up with 9.12 gallons of fuel and paid $48.32.",
            source: "daily_tracker_sort.test",
            confidence: 0.92,
            reviewState: "suggested",
            metadata: [
                "memory_kind": "spending_fact",
                "candidate_kind": "spending_fact",
                "spending_category": "gas",
                "amount": "48.32",
                "currency": "USD",
                "journal_date": "2026-06-19",
                "source_owner_ref": "note:\(newerJournalID)",
                "source_quote": "Latest gas stop after work. Filled up with 9.12 gallons of fuel and paid $48.32.",
            ]
        ))

        let defaultPayload = try assertStrictProcessJSON(
            runCLI(args: ["item", "daily-tracker", "--query", "gas", "--limit", "1", "--json"], vault: vault),
            command: "item.daily-tracker"
        )
        #expect(defaultPayload["readOnly"] as? Bool == true)
        #expect(defaultPayload["changed"] as? Bool == false)
        #expect(defaultPayload["candidateBoundary"] as? String == "reviewable_candidates_are_not_truth")
        #expect((defaultPayload["filters"] as? [String: Any])?["query"] as? String == "gas")
        #expect((defaultPayload["filters"] as? [String: Any])?["limit"] as? Int == 1)
        #expect((defaultPayload["filters"] as? [String: Any])?["sort"] == nil)

        let defaultRows = try #require(defaultPayload["rows"] as? [[String: Any]])
        #expect(defaultRows.count == 1)
        let defaultGas = try #require(defaultRows.first)
        #expect(defaultGas["date"] as? String == "2026-06-11")
        #expect(defaultGas["amount"] as? String == "81.07")
        #expect(defaultGas["truthState"] as? String == "reviewable_candidate_not_truth")
        #expect((defaultGas["sourceRefs"] as? [String])?.contains("note:\(olderJournalID)") == true)

        let newestPayload = try assertStrictProcessJSON(
            runCLI(args: ["item", "daily-tracker", "--query", "gas", "--sort", "newest", "--limit", "1", "--json"], vault: vault),
            command: "item.daily-tracker"
        )
        #expect(newestPayload["readOnly"] as? Bool == true)
        #expect(newestPayload["changed"] as? Bool == false)
        #expect(newestPayload["candidateBoundary"] as? String == "reviewable_candidates_are_not_truth")
        #expect((newestPayload["filters"] as? [String: Any])?["query"] as? String == "gas")
        #expect((newestPayload["filters"] as? [String: Any])?["limit"] as? Int == 1)
        #expect((newestPayload["filters"] as? [String: Any])?["sort"] as? String == "newest")

        let newestRows = try #require(newestPayload["rows"] as? [[String: Any]])
        #expect(newestRows.count == 1)
        let newestGas = try #require(newestRows.first)
        #expect(newestGas["date"] as? String == "2026-06-19")
        #expect(newestGas["amount"] as? String == "48.32")
        #expect(newestGas["reviewState"] as? String == "suggested")
        #expect(newestGas["truthState"] as? String == "reviewable_candidate_not_truth")
        #expect((newestGas["sourceRefs"] as? [String])?.contains("note:\(newerJournalID)") == true)
        #expect((newestGas["citation"] as? [String: Any])?["ownerID"] as? String == newerJournalID)

        let newestRollups = try #require(newestPayload["rollups"] as? [[String: Any]])
        #expect(newestRollups.count == 1)
        #expect(newestRollups.first?["date"] as? String == "2026-06-19")
        #expect(newestRollups.first?["spendingAmount"] as? String == "48.32")
        #expect(newestRollups.first?["spendingRowCount"] as? Int == 1)
        #expect(newestRollups.first?["reviewableRowCount"] as? Int == 1)
        #expect(newestRollups.first?["acceptedRowCount"] as? Int == 0)

        for query in [
            "last time I filled up",
            "latest gas spend",
            "most recent gas purchase",
            "what did gas cost",
            "how much did I spend on gas",
            "how much was gas",
            "how much did I pay for gas",
            "when did I last buy gas",
            "where did I get gas",
            "how many gallons of gas",
        ] {
            let synonymPayload = try assertStrictProcessJSON(
                runCLI(args: ["item", "daily-tracker", "--query", query, "--sort", "newest", "--limit", "1", "--json"], vault: vault),
                command: "item.daily-tracker"
            )
            #expect(synonymPayload["readOnly"] as? Bool == true, "query should stay read-only: \(query)")
            #expect(synonymPayload["changed"] as? Bool == false, "query should not mutate state: \(query)")
            #expect(synonymPayload["candidateBoundary"] as? String == "reviewable_candidates_are_not_truth")
            #expect((synonymPayload["filters"] as? [String: Any])?["query"] as? String == query)
            #expect((synonymPayload["filters"] as? [String: Any])?["limit"] as? Int == 1)
            #expect((synonymPayload["filters"] as? [String: Any])?["sort"] as? String == "newest")

            let synonymRows = try #require(synonymPayload["rows"] as? [[String: Any]], "query should return rows: \(query)")
            #expect(synonymRows.count == 1, "query should return only the newest gas row: \(query)")
            let synonymGas = try #require(synonymRows.first, "query should include the newest gas row: \(query)")
            #expect(synonymGas["date"] as? String == "2026-06-19")
            #expect(synonymGas["signalType"] as? String == "spending")
            #expect(synonymGas["value"] as? String == "gas")
            #expect(synonymGas["amount"] as? String == "48.32")
            #expect(synonymGas["reviewState"] as? String == "suggested")
            #expect(synonymGas["truthState"] as? String == "reviewable_candidate_not_truth")
            #expect((synonymGas["sourceRefs"] as? [String])?.contains("note:\(newerJournalID)") == true)
            #expect((synonymGas["citation"] as? [String: Any])?["ownerID"] as? String == newerJournalID)

            let synonymRollups = try #require(synonymPayload["rollups"] as? [[String: Any]])
            #expect(synonymRollups.count == 1)
            #expect(synonymRollups.first?["date"] as? String == "2026-06-19")
            #expect(synonymRollups.first?["spendingAmount"] as? String == "48.32")
            #expect(synonymRollups.first?["spendingRowCount"] as? Int == 1)
            #expect(synonymRollups.first?["reviewableRowCount"] as? Int == 1)
            #expect(synonymRollups.first?["acceptedRowCount"] as? Int == 0)
        }

        let genericQuestionPayload = try assertStrictProcessJSON(
            runCLI(args: ["item", "daily-tracker", "--query", "how much", "--sort", "newest", "--limit", "1", "--json"], vault: vault),
            command: "item.daily-tracker"
        )
        #expect(genericQuestionPayload["readOnly"] as? Bool == true)
        #expect(genericQuestionPayload["changed"] as? Bool == false)
        #expect(genericQuestionPayload["candidateBoundary"] as? String == "reviewable_candidates_are_not_truth")
        #expect((genericQuestionPayload["rows"] as? [[String: Any]])?.isEmpty == true)
        #expect((genericQuestionPayload["rollups"] as? [[String: Any]])?.isEmpty == true)

        let genericWherePayload = try assertStrictProcessJSON(
            runCLI(args: ["item", "daily-tracker", "--query", "where did I get", "--sort", "newest", "--limit", "1", "--json"], vault: vault),
            command: "item.daily-tracker"
        )
        #expect(genericWherePayload["readOnly"] as? Bool == true)
        #expect(genericWherePayload["changed"] as? Bool == false)
        #expect(genericWherePayload["candidateBoundary"] as? String == "reviewable_candidates_are_not_truth")
        #expect((genericWherePayload["rows"] as? [[String: Any]])?.isEmpty == true)
        #expect((genericWherePayload["rollups"] as? [[String: Any]])?.isEmpty == true)
    }

    @Test("recall context bundle cites accepted graph evidence and reviewable candidates")
    func recallContextBundleCitesAcceptedGraphEvidenceAndReviewableCandidates() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-recall-context-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let journalID = try createNote(
            title: "Daily Journal 2026-06-14",
            content: "Jami loved the pineapple coconut drink. Avery Stone mentioned Pine House after the graph conversation.",
            vault: vault
        )
        let relatedNoteID = try createNote(
            title: "Pine House dinner notes",
            content: "Pine House looked like a possible restaurant to review later.",
            vault: vault
        )
        let journalRef = LibraryEntityRef(type: .note, entityID: UUID(uuidString: journalID)!)
        let relatedRef = LibraryEntityRef(type: .note, entityID: UUID(uuidString: relatedNoteID)!)
        let journalOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: journalID)
        let drinkOutput = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: journalOwner,
            candidateKind: .object,
            mentionText: "pineapple coconut drink",
            sourceQuote: "Jami loved the pineapple coconut drink.",
            sourceKind: "journal",
            objectTypeGuesses: [.drink],
            safeActions: [.inspectSource, .createObject, .reject],
            confidence: 0.82,
            source: "recall_context.test"
        )
        let placeOutput = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: journalOwner,
            candidateKind: .objectRelation,
            mentionText: "Pine House",
            sourceQuote: "Avery Stone mentioned Pine House after the graph conversation.",
            sourceKind: "journal",
            objectTypeGuesses: [.restaurant, .place],
            relationGuesses: [.mentions],
            safeActions: [.inspectSource, .linkExisting, .createObject, .correct, .reject],
            confidence: 0.7,
            source: "recall_context.test"
        )
        let db = CiderDatabase()
        try db.open(at: vault.appendingPathComponent(".cider/cider.db"))
        let store = SecondBrainStore(database: db)
        let outputService = SecondBrainEnrichmentOutputService(database: db)
        try outputService.record(drinkOutput)
        try outputService.record(placeOutput)
        try store.recordRelation(SecondBrainRelation(
            sourceOwner: journalOwner,
            targetOwner: SecondBrainOwnerRef(ownerType: "graph_object", ownerID: "drink-pineapple-coconut-drink"),
            relationType: "liked",
            evidence: "Jami loved the pineapple coconut drink.",
            source: "graph_candidate.accept",
            actor: "codex-test",
            confidence: 0.82,
            metadata: [
                "candidate_id": drinkOutput.id,
                "candidate_ref": "graph_candidate:\(drinkOutput.id)",
                "mention_text": "pineapple coconut drink",
                "source_quote": "Jami loved the pineapple coconut drink.",
            ]
        ))
        try ItemLinkService(database: db).addDirectLink(from: journalRef, to: relatedRef)
        try store.upsertSection(SecondBrainSection(
            owner: journalOwner,
            itemID: journalID,
            sectionKey: "summary",
            title: "Summary",
            body: "Journal mentions Jami's pineapple coconut drink and Pine House.",
            source: "test",
            sortOrder: 0
        ))
        try store.replaceChunks(owner: journalOwner, chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: journalID,
                source: "note-body",
                title: "Journal body",
                body: "Jami loved the pineapple coconut drink. Avery Stone mentioned Pine House after the graph conversation.",
                chunkIndex: 0
            )
        ])
        db.close()

        let result = try runCLI(args: ["item", "recall-context", "--item", "note", journalID, "--query", "Pine House", "--json"], vault: vault)
        let payload = try parseJSONObject(result.stdout)
        #expect(result.status == 0)
        #expect(payload["ok"] as? Bool == true)
        #expect(payload["command"] as? String == "item.recall-context")
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["safetyBoundary"] as? [String] == [
            "accepted_facts_are_cited",
            "reviewable_candidates_are_not_truth",
            "accept_requires_explicit_command",
            "no_silent_memory_or_graph_promotion",
        ])
        let anchors = try #require(payload["anchors"] as? [[String: Any]])
        let anchor = try #require(anchors.first { ($0["owner"] as? [String: Any])?["ownerID"] as? String == journalID })
        let anchorReasons = try #require(anchor["scoreReasons"] as? [[String: Any]])
        #expect(anchorReasons.contains { $0["kind"] as? String == "explicit_item_anchor" })
        #expect(anchorReasons.contains { $0["kind"] as? String == "query_match" })
        #expect(anchor["recallScore"] as? Double != nil)
        let contentBlocks = try #require(payload["contentBlocks"] as? [[String: Any]])
        let citedContent = try #require(contentBlocks.first { ($0["citation"] as? [String: Any])?["ownerID"] as? String == journalID })
        let contentReasons = try #require(citedContent["scoreReasons"] as? [[String: Any]])
        #expect(contentReasons.contains { $0["kind"] as? String == "source_chunk" || $0["kind"] as? String == "source_section" })
        let relatedItems = try #require(payload["relatedItems"] as? [[String: Any]])
        let related = try #require(relatedItems.first { ($0["id"] as? String) == relatedNoteID })
        let relatedReasons = try #require(related["scoreReasons"] as? [[String: Any]])
        #expect(relatedReasons.contains { $0["kind"] as? String == "related_item_link" })
        let acceptedFacts = try #require(payload["acceptedFacts"] as? [[String: Any]])
        let accepted = try #require(acceptedFacts.first { $0["candidateRef"] as? String == "graph_candidate:\(drinkOutput.id)" })
        #expect(accepted["truthState"] as? String == "accepted")
        #expect(accepted["sourceQuote"] as? String == "Jami loved the pineapple coconut drink.")
        #expect((accepted["citation"] as? [String: Any])?["ownerID"] as? String == journalID)
        let acceptedReasons = try #require(accepted["scoreReasons"] as? [[String: Any]])
        #expect(acceptedReasons.contains { $0["kind"] as? String == "accepted_graph_fact" })
        #expect(acceptedReasons.contains { $0["kind"] as? String == "source_evidence" })
        let acceptedEvidence = try #require(accepted["sourceEvidenceRecord"] as? [String: Any])
        #expect(acceptedEvidence["sourceOwnerRef"] as? String == "note:\(journalID)")
        #expect(acceptedEvidence["sourceQuote"] as? String == "Jami loved the pineapple coconut drink.")
        #expect(acceptedEvidence["derivedOwnerRef"] as? String == "owner_relation:\(accepted["id"] as? String ?? "")")
        #expect(acceptedEvidence["candidateRef"] as? String == "graph_candidate:\(drinkOutput.id)")
        #expect(acceptedEvidence["extractionSource"] as? String == "graph_candidate.accept")
        let acceptedLifecycle = try #require(accepted["lifecycleHistory"] as? [[String: Any]])
        #expect(acceptedLifecycle.contains { $0["eventKind"] as? String == "suggested" })
        #expect(acceptedLifecycle.contains { $0["eventKind"] as? String == "accepted_truth_recorded" })
        #expect(acceptedLifecycle.last?["truthBoundary"] as? String == "accepted_truth_requires_explicit_event")
        let candidates = try #require(payload["reviewableCandidates"] as? [[String: Any]])
        let candidate = try #require(candidates.first { $0["id"] as? String == placeOutput.id })
        #expect(candidate["truthState"] as? String == "reviewable_candidate_not_truth")
        #expect(candidate["sourceQuote"] as? String == "Avery Stone mentioned Pine House after the graph conversation.")
        #expect((candidate["citation"] as? [String: Any])?["ownerID"] as? String == journalID)
        let candidateEvidence = try #require(candidate["sourceEvidenceRecord"] as? [String: Any])
        #expect(candidateEvidence["sourceOwnerRef"] as? String == "note:\(journalID)")
        #expect(candidateEvidence["sourceQuote"] as? String == "Avery Stone mentioned Pine House after the graph conversation.")
        #expect(candidateEvidence["derivedOwnerRef"] as? String == "enrichment_output:\(placeOutput.id)")
        #expect(candidateEvidence["candidateRef"] as? String == "graph_candidate:\(placeOutput.id)")
        #expect(candidateEvidence["extractionSource"] as? String == "recall_context.test")
        let candidateReasons = try #require(candidate["scoreReasons"] as? [[String: Any]])
        #expect(candidateReasons.contains { $0["kind"] as? String == "reviewable_candidate" })
        #expect(candidateReasons.contains { $0["kind"] as? String == "source_evidence" })
        #expect(candidateReasons.contains { $0["kind"] as? String == "lifecycle_state" })
        let candidateLifecycle = try #require(candidate["lifecycleHistory"] as? [[String: Any]])
        #expect(candidateLifecycle.map { $0["eventKind"] as? String }.contains("suggested"))
        #expect(candidateLifecycle.last?["truthBoundary"] as? String == "reviewable_candidate_not_truth")
        let review = try #require(payload["reviewStatus"] as? [String: Any])
        #expect(review["needsReview"] as? Bool == true)
        #expect((review["blockingIssues"] as? [String])?.contains("graph_candidates_need_review") == true)
        let commands = try #require(payload["safeNextCommands"] as? [String])
        #expect(commands.contains("cider-cli item context note \(journalID) --json"))
        #expect(commands.contains("cider-cli item graph-candidates note \(journalID) --json"))
        let accessLog = try #require(payload["accessLog"] as? [String: Any])
        #expect(accessLog["recorded"] as? Bool == true)
        #expect(accessLog["queryHash"] as? String != nil)
        #expect(accessLog["queryTextStored"] as? Bool == false)
        #expect(String(describing: accessLog).contains("Pine House") == false)

        let logResult = try runCLI(args: ["item", "recall-access-log", "--limit", "1", "--json"], vault: vault)
        let logPayload = try parseJSONObject(logResult.stdout)
        #expect(logResult.status == 0)
        #expect(logPayload["ok"] as? Bool == true)
        let events = try #require(logPayload["events"] as? [[String: Any]])
        let event = try #require(events.first)
        #expect(event["queryHash"] as? String == accessLog["queryHash"] as? String)
        #expect(event["queryText"] == nil)
        #expect(String(describing: event).contains("Pine House") == false)
    }

    @Test("recall context demotes accepted facts after accepted validity supersession")
    func recallContextDemotesAcceptedFactsAfterAcceptedValiditySupersession() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-fact-validity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let noteID = try createNote(
            title: "Daily Journal Fact Validity",
            content: "Jami's favorite restaurant was Pine House. Jami now says Lotus Garden is her favorite.",
            vault: vault
        )
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: noteID)
        let relation = SecondBrainRelation(
            sourceOwner: owner,
            targetOwner: SecondBrainOwnerRef(ownerType: "graph_object", ownerID: "pine-house"),
            relationType: "favorite_restaurant",
            evidence: "Jami's favorite restaurant was Pine House.",
            source: "graph_candidate.accept",
            actor: "test",
            confidence: 0.88,
            metadata: [
                "candidate_ref": "graph_candidate:favorite-pine-house",
                "candidate_id": "favorite-pine-house",
                "source_quote": "Jami's favorite restaurant was Pine House.",
                "mention_text": "Pine House",
            ]
        )
        let db = CiderDatabase()
        try db.open(at: vault.appendingPathComponent(".cider/cider.db"))
        try SecondBrainStore(database: db).recordRelation(relation)
        try SecondBrainStore(database: db).replaceChunks(owner: owner, chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: noteID,
                source: "note-body",
                title: "Journal body",
                body: "Jami's favorite restaurant was Pine House. Jami now says Lotus Garden is her favorite.",
                chunkIndex: 0
            )
        ])
        db.close()

        let propose = try runCLI(
            args: [
                "item", "fact-validity", "propose",
                "--target-ref", "owner_relation:\(relation.id)",
                "--state", "superseded",
                "--source-owner", "note:\(noteID)",
                "--quote", "Jami now says Lotus Garden is her favorite.",
                "--reason", "Newer journal evidence supersedes the prior favorite restaurant fact.",
                "--superseded-by-ref", "owner_relation:favorite-lotus-garden",
                "--json",
            ],
            vault: vault
        )
        let proposedPayload = try parseJSONObject(propose.stdout)
        #expect(propose.status == 0)
        let proposeReceipt = try #require(proposedPayload["actionReceipt"] as? [String: Any])
        #expect(proposeReceipt["command"] as? String == "item.fact-validity.propose")
        #expect(proposeReceipt["action"] as? String == "propose")
        #expect(proposeReceipt["actor"] as? String == "cider-cli")
        #expect(proposeReceipt["changed"] as? Bool == true)
        #expect((proposeReceipt["sourceRefs"] as? [String])?.contains("owner_relation:\(relation.id)") == true)
        let proposed = try #require(proposedPayload["candidate"] as? [String: Any])
        #expect(proposed["truthBoundary"] as? String == "reviewable_candidate_not_truth")
        let candidateID = try #require(proposed["id"] as? String)

        let accept = try runCLI(
            args: ["item", "fact-validity", "accept", candidateID, "--reason", "Confirmed newer evidence.", "--json"],
            vault: vault
        )
        let acceptedPayload = try parseJSONObject(accept.stdout)
        #expect(accept.status == 0)
        let acceptReceipt = try #require(acceptedPayload["actionReceipt"] as? [String: Any])
        #expect(acceptReceipt["command"] as? String == "item.fact-validity.accept")
        #expect(acceptReceipt["action"] as? String == "accept")
        #expect(acceptReceipt["changed"] as? Bool == true)
        #expect((acceptReceipt["sourceRefs"] as? [String])?.contains("fact_validity_candidate:\(candidateID)") == true)
        let acceptedCandidate = try #require(acceptedPayload["candidate"] as? [String: Any])
        #expect(acceptedCandidate["truthBoundary"] as? String == "accepted_fact_validity")
        let acceptedState = try #require(acceptedPayload["factValidity"] as? [String: Any])
        #expect(acceptedState["currentState"] as? String == "superseded")
        #expect(acceptedState["isCurrent"] as? Bool == false)
        #expect(acceptedState["sourceEvidenceRecord"] as? [String: Any] != nil)

        let duplicateAccept = try runCLI(
            args: ["item", "fact-validity", "accept", candidateID, "--reason", "Already accepted.", "--json"],
            vault: vault
        )
        let duplicatePayload = try parseJSONObject(duplicateAccept.stdout)
        #expect(duplicateAccept.status == 0)
        #expect(duplicatePayload["changed"] as? Bool == false)
        #expect(duplicatePayload["errorCode"] as? String == "fact_validity_already_accepted")
        let duplicateReceipt = try #require(duplicatePayload["actionReceipt"] as? [String: Any])
        #expect(duplicateReceipt["status"] as? String == "no_op")
        #expect(duplicateReceipt["changed"] as? Bool == false)
        #expect(duplicateReceipt["errorCode"] as? String == "fact_validity_already_accepted")

        let ledger = try parseJSONObject(try runCLI(args: ["item", "action-ledger", "list", "--owner", "note:\(noteID)", "--limit", "20", "--json"], vault: vault).stdout)
        let ledgerEntries = try #require(ledger["entries"] as? [[String: Any]])
        #expect(ledgerEntries.contains { entry in
            entry["command"] as? String == "item.fact-validity.accept"
                && entry["action"] as? String == "accept"
                && entry["changed"] as? Bool == true
                && (entry["sourceRefs"] as? [String])?.contains("fact_validity_candidate:\(candidateID)") == true
        })
        #expect(ledgerEntries.contains { entry in
            entry["command"] as? String == "item.fact-validity.accept"
                && entry["status"] as? String == "no_op"
                && entry["errorCode"] as? String == "fact_validity_already_accepted"
        })

        let recallResult = try runCLI(args: ["item", "recall-context", "--item", "note", noteID, "--query", "Pine House", "--json"], vault: vault)
        let recall = try parseJSONObject(recallResult.stdout)
        #expect(recallResult.status == 0)
        let facts = try #require(recall["acceptedFacts"] as? [[String: Any]])
        let fact = try #require(facts.first { $0["id"] as? String == relation.id })
        #expect(fact["truthState"] as? String == "stale_or_superseded_truth")
        #expect(fact["isCurrentTruth"] as? Bool == false)
        let factValidity = try #require(fact["factValidity"] as? [String: Any])
        #expect(factValidity["currentState"] as? String == "superseded")
        #expect(factValidity["supersededByRef"] as? String == "owner_relation:favorite-lotus-garden")
        #expect(factValidity["sourceEvidenceRecord"] as? [String: Any] != nil)
        let actionHistory = try #require(recall["actionHistory"] as? [[String: Any]])
        #expect(actionHistory.contains { entry in
            entry["kind"] as? String == "action_receipt"
                && entry["command"] as? String == "item.fact-validity.accept"
                && entry["action"] as? String == "accept"
                && entry["truthBoundary"] as? String == "action_receipt_not_fact_truth"
        })
    }

    @Test("entity resolution merge persists action receipt and recall action history")
    func entityResolutionMergePersistsActionReceiptAndRecallActionHistory() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-entity-resolution-receipt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let noteID = try createNote(
            title: "Daily Journal Entity Resolution",
            content: "We went to Cactus for dinner and it should resolve to the saved Cactus place.",
            vault: vault
        )
        let targetID = try createNote(
            title: "Cactus Restaurant",
            content: "Saved restaurant entity for Cactus.",
            vault: vault
        )
        let sourceOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: noteID)
        let sourceEntity = SecondBrainOwnerRef(ownerType: "graph_object", ownerID: "cactus-mention")
        let targetEntity = SecondBrainOwnerRef(ownerType: "note", ownerID: targetID)

        let db = CiderDatabase()
        try db.open(at: vault.appendingPathComponent(".cider/cider.db"))
        let candidate = try SecondBrainEntityResolutionService(database: db, store: SecondBrainStore(database: db)).suggest(
            candidateType: "place_alias",
            sourceEntity: sourceEntity,
            sourceLabel: "Cactus",
            inputMention: "Cactus",
            targetEntity: targetEntity,
            targetLabel: "Cactus Restaurant",
            sourceOwner: sourceOwner,
            sourceQuote: "We went to Cactus for dinner.",
            confidence: 0.91,
            confidenceReasons: ["exact_alias", "place_visit_context"],
            actor: "test-agent",
            source: "entity_resolution.test"
        )
        db.close()

        let mergeResult = try runCLI(args: ["item", "entity-resolution", "merge", candidate.id, "--actor", "codex-test", "--reason", "Confirmed Cactus place entity.", "--json"], vault: vault)
        let merge = try parseJSONObject(mergeResult.stdout)
        #expect(mergeResult.status == 0)
        #expect(merge["command"] as? String == "item.entity-resolution.merge")
        #expect(merge["changed"] as? Bool == true)
        let receipt = try #require(merge["actionReceipt"] as? [String: Any])
        #expect(receipt["action"] as? String == "merge")
        #expect(receipt["actor"] as? String == "codex-test")
        #expect(receipt["ownerRef"] as? String == "note:\(noteID)")
        #expect((receipt["sourceRefs"] as? [String])?.contains("entity_resolution_candidate:\(candidate.id)") == true)
        #expect((receipt["sourceRefs"] as? [String])?.contains("graph_object:cactus-mention") == true)
        #expect((receipt["evidenceRefs"] as? [String])?.contains("note:\(noteID)") == true)

        let ledger = try parseJSONObject(try runCLI(args: ["item", "action-ledger", "list", "--owner", "note:\(noteID)", "--action", "merge", "--json"], vault: vault).stdout)
        let entries = try #require(ledger["entries"] as? [[String: Any]])
        #expect(entries.contains { entry in
            entry["command"] as? String == "item.entity-resolution.merge"
                && entry["status"] as? String == "succeeded"
                && entry["changed"] as? Bool == true
                && (entry["sourceRefs"] as? [String])?.contains("entity_resolution_candidate:\(candidate.id)") == true
        })

        let recallResult = try runCLI(args: ["item", "recall-context", "--item", "note", noteID, "--query", "Cactus", "--json"], vault: vault)
        let recall = try parseJSONObject(recallResult.stdout)
        #expect(recallResult.status == 0)
        let actionHistory = try #require(recall["actionHistory"] as? [[String: Any]])
        #expect(actionHistory.contains { entry in
            entry["kind"] as? String == "action_receipt"
                && entry["command"] as? String == "item.entity-resolution.merge"
                && entry["action"] as? String == "merge"
                && entry["truthBoundary"] as? String == "action_receipt_not_fact_truth"
        })
    }

    @Test("recall context bundle returns structured selector failures")
    func recallContextBundleReturnsStructuredSelectorFailures() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-recall-context-errors-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let malformedResult = try runCLI(args: ["item", "recall-context", "--item", "note", "not-a-uuid", "--json"], vault: vault)
        let malformed = try parseJSONObject(malformedResult.stdout)
        #expect(malformedResult.status != 0)
        #expect(malformed["ok"] as? Bool == false)
        #expect(malformed["errorCode"] as? String == "malformed_or_unresolved_selector")
        #expect(malformed["readOnly"] as? Bool == true)
        #expect(malformed["changed"] as? Bool == false)

        let noMatchResult = try runCLI(args: ["item", "recall-context", "--query", "zzzz no such topic", "--json"], vault: vault)
        let noMatch = try parseJSONObject(noMatchResult.stdout)
        #expect(noMatchResult.status != 0)
        #expect(noMatch["ok"] as? Bool == false)
        #expect(noMatch["errorCode"] as? String == "no_recall_matches")
        #expect(noMatch["warnings"] as? [[String: Any]] != nil)
        let commands = try #require(noMatch["safeNextCommands"] as? [String])
        #expect(commands.contains("cider-cli item search \"zzzz no such topic\" --json"))
        let noMatchReceipt = try #require(noMatch["actionReceipt"] as? [String: Any])
        #expect(noMatchReceipt["command"] as? String == "item.recall-context")
        #expect(noMatchReceipt["readOnly"] as? Bool == true)
        #expect(noMatchReceipt["changed"] as? Bool == false)
        #expect(noMatchReceipt["status"] as? String == "failed")
        #expect(noMatchReceipt["matchedCount"] as? Int == 0)
        #expect((noMatchReceipt["safeCommandRefs"] as? [String])?.contains("cider-cli item search \"zzzz no such topic\" --json") == true)
        #expect(noMatchReceipt["truthBoundary"] as? String == "receipt_proves_command_execution_not_memory_truth")
    }

    @Test("graph object candidates expose stable hub identity and conflicts")
    func graphObjectCandidatesExposeStableHubIdentityAndConflicts() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-graph-object-hub-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let firstNoteID = try createNote(
            title: "Daily Journal 2026-06-14",
            content: "Avery Stone mentioned Pine House after the Cider graph hub conversation.",
            vault: vault
        )
        let secondNoteID = try createNote(
            title: "Daily Journal 2026-06-15",
            content: "Avery Stone said Pine House might be a restaurant or a project codename.",
            vault: vault
        )
        let firstOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: firstNoteID)
        let secondOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: secondNoteID)
        let firstOutput = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: firstOwner,
            candidateKind: .objectRelation,
            mentionText: "Pine House",
            sourceQuote: "Avery Stone mentioned Pine House after the Cider graph hub conversation.",
            sourceKind: "journal",
            objectTypeGuesses: [.place, .restaurant],
            relationGuesses: [.mentions],
            safeActions: [.inspectSource, .linkExisting, .createObject, .correct, .reject, .delegateEnrichment],
            confidence: 0.71,
            subjectText: "Avery Stone",
            source: "graph_candidate.test"
        )
        let conflictingOutput = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: secondOwner,
            candidateKind: .object,
            mentionText: "Pine House",
            sourceQuote: "Avery Stone said Pine House might be a restaurant or a project codename.",
            sourceKind: "journal",
            objectTypeGuesses: [.project, .restaurant],
            safeActions: [.inspectSource, .linkExisting, .createObject, .correct, .reject, .delegateEnrichment],
            confidence: 0.66,
            source: "graph_candidate.test"
        )

        let db = CiderDatabase()
        try db.open(at: vault.appendingPathComponent(".cider/cider.db"))
        let service = SecondBrainEnrichmentOutputService(database: db)
        try service.record(firstOutput)
        try service.record(conflictingOutput)
        db.close()

        let listResult = try runCLI(args: ["item", "graph-candidates", "--json"], vault: vault)
        let list = try parseJSONObject(listResult.stdout)
        #expect(listResult.status == 0)
        let candidates = try #require(list["candidates"] as? [[String: Any]])
        let firstCandidate = try #require(candidates.first { $0["id"] as? String == firstOutput.id })
        let hub = try #require(firstCandidate["objectHubCandidate"] as? [String: Any])
        #expect(hub["stableKey"] as? String == "graph_object:pine-house")
        #expect(hub["displayName"] as? String == "Pine House")
        #expect(hub["aliases"] as? [String] == ["Pine House"])
        #expect(hub["possibleTypes"] as? [String] == ["place", "restaurant"])
        #expect(hub["reviewState"] as? String == "suggested")
        #expect(hub["acceptedAsTruth"] as? Bool == false)
        #expect(hub["reviewSafety"] as? [String] == [
            "reviewable_candidate_not_truth",
            "accept_requires_explicit_command",
            "no_auto_merge",
        ])

        let sourceEvidence = try #require(hub["sourceEvidence"] as? [[String: Any]])
        #expect(sourceEvidence.contains { evidence in
            evidence["candidateID"] as? String == firstOutput.id
                && evidence["sourceQuote"] as? String == "Avery Stone mentioned Pine House after the Cider graph hub conversation."
                && (evidence["sourceOwner"] as? [String: Any])?["ownerID"] as? String == firstNoteID
        })
        #expect(hub["conflictCount"] as? Int == 1)
        let conflicts = try #require(hub["conflicts"] as? [[String: Any]])
        #expect(conflicts.contains { conflict in
            conflict["candidateID"] as? String == conflictingOutput.id
                && conflict["stableKey"] as? String == "graph_object:pine-house"
                && conflict["conflictReason"] as? String == "same_stable_key_different_type_guesses"
                && conflict["possibleTypes"] as? [String] == ["project", "restaurant"]
        })

        let inspectResult = try runCLI(args: ["item", "graph-candidate", firstOutput.id, "--json"], vault: vault)
        let inspect = try parseJSONObject(inspectResult.stdout)
        let inspected = try #require(inspect["candidate"] as? [String: Any])
        #expect(inspected["objectHubCandidate"] as? [String: Any] != nil)
    }

    @Test("rich item graph compatibility mutations accept reject and delegate explicitly")
    func itemGraphCandidateMutationsAcceptRejectAndDelegateExplicitly() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-graph-candidate-mutations-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let noteID = try createNote(
            title: "Graph Candidate Mutation Source",
            content: "Watched The Way Way Back. Jami loved that pineapple coconut drink. We stopped at Cactus.",
            vault: vault
        )
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: noteID)
        let acceptOutput = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: "The Way Way Back",
            sourceQuote: "Watched The Way Way Back.",
            sourceKind: "journal",
            objectTypeGuesses: [.movie, .media],
            relationGuesses: [.watched],
            actionGuesses: ["watched"],
            safeActions: [.inspectSource, .linkExisting, .createObject, .correct, .reject, .delegateEnrichment],
            confidence: 0.78,
            source: "graph_candidate.test"
        )
        let rejectOutput = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: "pineapple coconut drink",
            sourceQuote: "Jami loved that pineapple coconut drink.",
            sourceKind: "journal",
            objectTypeGuesses: [.drink],
            relationGuesses: [.likesDrink],
            actionGuesses: ["liked"],
            safeActions: [.inspectSource, .linkExisting, .createObject, .correct, .reject, .delegateEnrichment],
            confidence: 0.72,
            subjectText: "Jami",
            source: "graph_candidate.test"
        )
        let delegateOutput = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: "Cactus",
            sourceQuote: "We stopped at Cactus.",
            sourceKind: "journal",
            objectTypeGuesses: [.restaurant, .place],
            relationGuesses: [.visited],
            actionGuesses: ["visited"],
            safeActions: [.inspectSource, .linkExisting, .createObject, .correct, .reject, .delegateEnrichment],
            confidence: 0.74,
            source: "graph_candidate.test"
        )

        let db = CiderDatabase()
        try db.open(at: vault.appendingPathComponent(".cider/cider.db"))
        let service = SecondBrainEnrichmentOutputService(database: db)
        try service.record(acceptOutput)
        try service.record(rejectOutput)
        try service.record(delegateOutput)
        db.close()
        try seedCoordinatorExactEvidence(
            candidateIDs: [acceptOutput.id, rejectOutput.id, delegateOutput.id],
            vault: vault
        )

        let acceptResult = try runCLI(args: [
            "item", "accept-graph-candidate", acceptOutput.id,
            "--target-owner", "graph_object:movie-the-way-way-back",
            "--relation", "watched",
            "--actor", "codex-test",
            "--json",
        ], vault: vault)
        let accept = try parseJSONObject(acceptResult.stdout)
        #expect(acceptResult.status == 0)
        #expect(accept["ok"] as? Bool == true)
        #expect(accept["command"] as? String == "item.accept-graph-candidate")
        #expect(accept["readOnly"] as? Bool == false)
        #expect(accept["changed"] as? Bool == true)
        #expect(accept["reviewState"] as? String == "accepted")
        let relation = try #require(accept["relation"] as? [String: Any])
        #expect(relation["sourceOwner"] as? [String: Any] != nil)
        #expect(relation["relationType"] as? String == "watched")
        let targetOwner = try #require(accept["targetOwner"] as? [String: Any])
        #expect(targetOwner["ownerType"] as? String == "graph_object")
        #expect(targetOwner["ownerID"] as? String == "movie-the-way-way-back")

        let rejectResult = try runCLI(args: [
            "item", "reject-graph-candidate", rejectOutput.id,
            "--reason", "Not useful",
            "--actor", "codex-test",
            "--json",
        ], vault: vault)
        let reject = try parseJSONObject(rejectResult.stdout)
        #expect(rejectResult.status == 0)
        #expect(reject["command"] as? String == "item.reject-graph-candidate")
        #expect(reject["reviewState"] as? String == "rejected")
        #expect(reject["relation"] == nil)

        let delegateResult = try runCLI(args: [
            "item", "delegate-graph-candidate", delegateOutput.id,
            "--task-kind", "find_place_match",
            "--actor", "codex-test",
            "--json",
        ], vault: vault)
        let delegate = try parseJSONObject(delegateResult.stdout)
        #expect(delegateResult.status == 0)
        #expect(delegate["command"] as? String == "item.delegate-graph-candidate")
        #expect(delegate["reviewState"] as? String == "deferred")
        let delegation = try #require(delegate["delegation"] as? [String: Any])
        #expect(delegation["taskKind"] as? String == "find_place_match")
        #expect((delegation["instructions"] as? String)?.contains("place or restaurant matches") == true)
        #expect(delegation["resultPolicy"] as? String == "return_reviewable_evidence_not_truth")
        let delegatedTask = try #require(delegation["task"] as? [String: Any])
        #expect(delegatedTask["kind"] as? String == "find_place_match")
        #expect(delegatedTask["status"] as? String == "available")

        let contextResult = try runCLI(args: ["item", "get", "note", noteID, "--json"], vault: vault)
        let context = try parseJSONObject(contextResult.stdout)
        let ownerRelations = try #require(context["ownerRelations"] as? [[String: Any]])
        #expect(ownerRelations.count == 1)
        #expect(ownerRelations.first?["relationType"] as? String == "watched")
        let sourceEvidence = try #require(context["sourceEvidence"] as? [String: Any])
        #expect((sourceEvidence["count"] as? Int ?? 0) >= 1)
        let facts = try #require(sourceEvidence["facts"] as? [[String: Any]])
        let fact = try #require(facts.first { $0["candidateRef"] as? String == "graph_candidate:\(acceptOutput.id)" })
        #expect(fact["relationType"] as? String == "watched")
        #expect(fact["sourceQuote"] as? String == "Watched The Way Way Back.")
        #expect(fact["candidateRef"] as? String == "graph_candidate:\(acceptOutput.id)")
        #expect(fact["mentionText"] as? String == "The Way Way Back")
        let factCommands = try #require(fact["safeNextCommands"] as? [String])
        #expect(factCommands.contains("cider-cli item graph-candidate \(acceptOutput.id) --json"))

        let relatedResult = try runCLI(args: ["item", "related-owners", "note", noteID, "--json"], vault: vault)
        let related = try parseJSONObject(relatedResult.stdout)
        #expect(related["command"] as? String == "item.related-owners")
        #expect(related["readOnly"] as? Bool == true)
        #expect(related["changed"] as? Bool == false)
        #expect((related["relationCount"] as? Int ?? 0) >= 1)
        let relatedEvidence = try #require(related["sourceEvidence"] as? [String: Any])
        let relatedFacts = try #require(relatedEvidence["facts"] as? [[String: Any]])
        let relatedFact = try #require(relatedFacts.first { $0["candidateRef"] as? String == "graph_candidate:\(acceptOutput.id)" })
        #expect(relatedFact["sourceQuote"] as? String == "Watched The Way Way Back.")
        #expect(relatedFact["mentionText"] as? String == "The Way Way Back")
        let relatedCommands = try #require(related["safeNextCommands"] as? [String])
        #expect(relatedCommands.contains("cider-cli item context note \(noteID) --json"))

        let agentActions = try #require(context["agentActions"] as? [[String: Any]])
        #expect(agentActions.contains { $0["actionType"] as? String == "graph_candidate.accept" })
        #expect(agentActions.contains { $0["actionType"] as? String == "graph_candidate.reject" })
        #expect(agentActions.contains { $0["actionType"] as? String == "graph_candidate.delegate_enrichment" })

        let acceptReceipt = try #require(accept["actionReceipt"] as? [String: Any])
        #expect(acceptReceipt["command"] as? String == "item.accept-graph-candidate")
        #expect(acceptReceipt["action"] as? String == "accept")
        #expect(acceptReceipt["actor"] as? String == "codex-test")
        #expect(acceptReceipt["changed"] as? Bool == true)
        #expect((acceptReceipt["sourceRefs"] as? [String])?.contains("graph_candidate:\(acceptOutput.id)") == true)
        #expect((acceptReceipt["evidenceRefs"] as? [String])?.contains("note:\(noteID)") == true)

        let ledger = try parseJSONObject(try runCLI(args: ["item", "action-ledger", "list", "--owner", "note:\(noteID)", "--action", "accept", "--json"], vault: vault).stdout)
        let entries = try #require(ledger["entries"] as? [[String: Any]])
        #expect(entries.contains { entry in
            entry["command"] as? String == "item.accept-graph-candidate"
                && entry["status"] as? String == "succeeded"
                && entry["changed"] as? Bool == true
                && (entry["sourceRefs"] as? [String])?.contains("graph_candidate:\(acceptOutput.id)") == true
        })

        let agentContextResult = try runCLI(args: ["item", "context", "note", noteID, "--max-history", "10", "--json"], vault: vault)
        let agentContext = try parseJSONObject(agentContextResult.stdout)
        let recentHistory = try #require(agentContext["recentHistory"] as? [[String: Any]])
        #expect(recentHistory.contains { entry in
            entry["kind"] as? String == "action_receipt"
                && entry["command"] as? String == "item.accept-graph-candidate"
                && entry["action"] as? String == "accept"
                && entry["status"] as? String == "succeeded"
                && entry["changed"] as? Bool == true
        })

        let defaultList = try parseJSONObject(try runCLI(args: ["item", "graph-candidates", "note", noteID, "--json"], vault: vault).stdout)
        #expect(defaultList["count"] as? Int == 1)
        let reviewedList = try parseJSONObject(try runCLI(args: ["item", "graph-candidates", "note", noteID, "--include-reviewed", "--json"], vault: vault).stdout)
        #expect(reviewedList["count"] as? Int == 3)
    }

    @Test("graph object candidate accept creates cited canonical entity and blocks conflicts without approval")
    func graphObjectCandidateAcceptCreatesCitedCanonicalEntityAndBlocksConflictsWithoutApproval() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-canonical-entity-accept-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let sourceNoteID = try createNote(
            title: "Daily Journal 2026-06-16",
            content: "Jami wants to try Pine House again. Pinehouse is how the group typed it later.",
            vault: vault
        )
        let conflictNoteID = try createNote(
            title: "Daily Journal 2026-06-17",
            content: "Pine House might be the project codename, not the restaurant.",
            vault: vault
        )
        let sourceOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: sourceNoteID)
        let conflictOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: conflictNoteID)
        let acceptOutput = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: sourceOwner,
            candidateKind: .objectRelation,
            mentionText: "Pine House",
            sourceQuote: "Jami wants to try Pine House again.",
            sourceKind: "journal",
            objectTypeGuesses: [.restaurant, .place],
            relationGuesses: [.wants],
            actionGuesses: ["wants_to_try"],
            safeActions: [.inspectSource, .linkExisting, .createObject, .correct, .reject, .delegateEnrichment],
            confidence: 0.77,
            subjectText: "Jami",
            source: "graph_candidate.test"
        )
        let conflictOutput = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: conflictOwner,
            candidateKind: .object,
            mentionText: "Pine House",
            sourceQuote: "Pine House might be the project codename, not the restaurant.",
            sourceKind: "journal",
            objectTypeGuesses: [.project],
            safeActions: [.inspectSource, .linkExisting, .createObject, .correct, .reject, .delegateEnrichment],
            confidence: 0.65,
            source: "graph_candidate.test"
        )

        let db = CiderDatabase()
        try db.open(at: vault.appendingPathComponent(".cider/cider.db"))
        let service = SecondBrainEnrichmentOutputService(database: db)
        try service.record(acceptOutput)
        try service.record(conflictOutput)
        db.close()

        let blockedResult = try runCLI(args: [
            "item", "accept-graph-candidate", acceptOutput.id,
            "--actor", "codex-test",
            "--json",
        ], vault: vault)
        let blocked = try parseJSONObject(blockedResult.stdout)
        #expect(blockedResult.status != 0)
        #expect(blocked["ok"] as? Bool == false)
        #expect(blocked["command"] as? String == "item.accept-graph-candidate")
        #expect(blocked["changed"] as? Bool == false)
        #expect(blocked["errorCode"] as? String == "graph_candidate_conflicts_block_accept")
        #expect((blocked["blockingIssues"] as? [String])?.contains("graph_object_conflict") == true)
        #expect(((blocked["conflicts"] as? [[String: Any]]) ?? []).contains { $0["candidateID"] as? String == conflictOutput.id })
        #expect(((blocked["safeNextCommands"] as? [String]) ?? []).contains("cider-cli item delegate-graph-candidate \(acceptOutput.id) --task-kind find_object_evidence --json"))
        let blockedReceipt = try #require(blocked["actionReceipt"] as? [String: Any])
        #expect(blockedReceipt["status"] as? String == "failed")
        #expect(blockedReceipt["errorCode"] as? String == "graph_candidate_conflicts_block_accept")
        #expect((blockedReceipt["sourceRefs"] as? [String])?.contains("graph_candidate:\(acceptOutput.id)") == true)
        let failedLedger = try parseJSONObject(try runCLI(args: ["item", "action-ledger", "list", "--status", "failed", "--action", "accept", "--json"], vault: vault).stdout)
        let failedEntries = try #require(failedLedger["entries"] as? [[String: Any]])
        #expect(failedEntries.contains { entry in
            entry["command"] as? String == "item.accept-graph-candidate"
                && entry["errorCode"] as? String == "graph_candidate_conflicts_block_accept"
                && entry["changed"] as? Bool == false
        })

        let acceptResult = try runCLI(args: [
            "item", "accept-graph-candidate", acceptOutput.id,
            "--actor", "codex-test",
            "--allow-conflicts",
            "--alias", "Pinehouse",
            "--json",
        ], vault: vault)
        let accept = try parseJSONObject(acceptResult.stdout)
        #expect(acceptResult.status == 0)
        #expect(accept["command"] as? String == "item.accept-graph-candidate")
        #expect(accept["changed"] as? Bool == true)
        #expect(accept["reviewState"] as? String == "accepted")
        let canonicalEntity = try #require(accept["canonicalEntity"] as? [String: Any])
        #expect(canonicalEntity["stableKey"] as? String == "graph_object:pine-house")
        #expect(canonicalEntity["displayName"] as? String == "Pine House")
        #expect(canonicalEntity["owner"] as? [String: Any] != nil)
        #expect((canonicalEntity["aliases"] as? [String])?.contains("Pinehouse") == true)
        #expect(canonicalEntity["acceptedAsTruth"] as? Bool == true)
        #expect(canonicalEntity["approvalSource"] as? String == "explicit_command")
        #expect(canonicalEntity["acceptedCandidateRef"] as? String == "graph_candidate:\(acceptOutput.id)")
        #expect(canonicalEntity["conflictPolicy"] as? String == "accepted_with_explicit_conflict_override")
        #expect((canonicalEntity["blockingIssues"] as? [String])?.contains("conflicts_reviewed_by_explicit_override") == true)
        let sourceEvidence = try #require(canonicalEntity["sourceEvidence"] as? [[String: Any]])
        #expect(sourceEvidence.contains { evidence in
            evidence["candidateRef"] as? String == "graph_candidate:\(acceptOutput.id)"
                && evidence["sourceQuote"] as? String == "Jami wants to try Pine House again."
        })
        let aliasDecisions = try #require(accept["aliasDecisions"] as? [[String: Any]])
        #expect(aliasDecisions.contains { decision in
            decision["alias"] as? String == "Pinehouse"
                && decision["relationType"] as? String == "alias_of"
                && decision["approvalSource"] as? String == "explicit_command"
        })
        let candidate = try #require(accept["candidate"] as? [String: Any])
        let acceptedHub = try #require(candidate["objectHubCandidate"] as? [String: Any])
        #expect(acceptedHub["acceptedAsTruth"] as? Bool == true)
        #expect(acceptedHub["canonicalEntity"] as? [String: Any] != nil)

        let recall = try parseJSONObject(try runCLI(args: ["item", "recall-context", "--item", "note", sourceNoteID, "--json"], vault: vault).stdout)
        let acceptedFacts = try #require(recall["acceptedFacts"] as? [[String: Any]])
        #expect(acceptedFacts.contains { fact in
            fact["candidateRef"] as? String == "graph_candidate:\(acceptOutput.id)"
                && fact["truthState"] as? String == "accepted"
                && fact["sourceQuote"] as? String == "Jami wants to try Pine House again."
        })
        let defaultCandidates = try parseJSONObject(try runCLI(args: ["item", "graph-candidates", "--json"], vault: vault).stdout)
        let reviewableCandidates = try #require(defaultCandidates["candidates"] as? [[String: Any]])
        #expect(!reviewableCandidates.contains { $0["id"] as? String == acceptOutput.id })
        #expect(reviewableCandidates.contains { $0["id"] as? String == conflictOutput.id })

        let secondAcceptResult = try runCLI(args: [
            "item", "accept-graph-candidate", acceptOutput.id,
            "--actor", "codex-test",
            "--json",
        ], vault: vault)
        let secondAccept = try parseJSONObject(secondAcceptResult.stdout)
        #expect(secondAcceptResult.status != 0)
        #expect(secondAccept["ok"] as? Bool == false)
        #expect(secondAccept["errorCode"] as? String == "graph_candidate_not_reviewable")
        #expect(secondAccept["changed"] as? Bool == false)
    }

    @Test("graph object candidate accept returns structured errors for malformed and missing refs")
    func graphObjectCandidateAcceptReturnsStructuredErrorsForMalformedAndMissingRefs() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-canonical-entity-errors-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let missing = try parseJSONObject(try runCLI(args: [
            "item", "accept-graph-candidate", "missing-candidate-id", "--json",
        ], vault: vault).stdout)
        #expect(missing["ok"] as? Bool == false)
        #expect(missing["command"] as? String == "item.accept-graph-candidate")
        #expect(missing["errorCode"] as? String == "graph_candidate_not_found")
        #expect(missing["changed"] as? Bool == false)

        let noteID = try createNote(title: "Daily Journal 2026-06-18", content: "Try Cactus later.", vault: vault)
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: noteID)
        let output = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .object,
            mentionText: "Cactus",
            sourceQuote: "Try Cactus later.",
            sourceKind: "journal",
            objectTypeGuesses: [.restaurant],
            safeActions: [.inspectSource, .createObject, .reject],
            confidence: 0.7,
            source: "graph_candidate.test"
        )
        let db = CiderDatabase()
        try db.open(at: vault.appendingPathComponent(".cider/cider.db"))
        try SecondBrainEnrichmentOutputService(database: db).record(output)
        db.close()

        let malformedResult = try runCLI(args: [
            "item", "accept-graph-candidate", output.id,
            "--target-owner", "not-a-canonical-ref",
            "--json",
        ], vault: vault)
        let malformed = try parseJSONObject(malformedResult.stdout)
        #expect(malformedResult.status != 0)
        #expect(malformed["ok"] as? Bool == false)
        #expect(malformed["command"] as? String == "item.accept-graph-candidate")
        #expect(malformed["errorCode"] as? String == "malformed_target_owner")
        #expect(malformed["changed"] as? Bool == false)
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
        let noteSearchResult = try #require(search.first {
            (($0["item"] as? [String: Any])?["id"] as? String) == noteID
        })
        let temporal = try #require(noteSearchResult["temporal"] as? [String: Any])
        #expect(temporal["sortDate"] as? String != nil)
        #expect(temporal["dateSource"] as? String != nil)
        let provenance = try #require(noteSearchResult["provenance"] as? [String: Any])
        #expect(provenance["sourceType"] as? String == "note")
        #expect(provenance["sourceID"] as? String == noteID)
        #expect(provenance["sourceTitle"] as? String == title)
        #expect(provenance["sourceLocation"] as? String != nil)
        #expect(provenance["evidenceExcerpt"] as? String != nil)
        #expect((noteSearchResult["contextCommands"] as? [String]) == ["cider-cli item context note \(noteID) --json"])
        #expect((noteSearchResult["verificationCommands"] as? [String]) == ["cider-cli item get note \(noteID) --json"])

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
        #expect(routing["reviewNeeded"] as? Bool == false)
        #expect(routing["reviewState"] as? String == "accepted")
        let routingReadiness = try #require(payload["routingReadiness"] as? [String: Any])
        #expect(routingReadiness["status"] as? String == "ready")
        #expect(routingReadiness["routeReviewNeeded"] as? Bool == false)
        let safeNextCommands = try #require(payload["safeNextCommands"] as? [String])
        let itemID = try #require(item["id"] as? String)
        #expect(safeNextCommands.first == "cider-cli item get note \(itemID) --json")
        #expect(!safeNextCommands.contains("cider-cli routing explain \(itemID) --json"))
        #expect(!safeNextCommands.contains("cider-cli review list --item-type note --state needs_review --limit 10 --json"))
        #expect(payload["readOnly"] as? Bool == false)
        #expect(payload["changed"] as? Bool == true)
    }

    @Test("plain note capture without folder is quiet when filed in Inbox Notes")
    func plainNoteCaptureWithoutFolderIsQuietWhenFiledInInboxNotes() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-capture-plain-note-quiet-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let result = try runCLI(
            args: [
                "capture", "add",
                "--kind", "note",
                "Plain note safe-command contract",
                "--json",
            ],
            vault: vault
        )
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status == 0)
        let item = try #require(payload["item"] as? [String: Any])
        let itemID = try #require(item["id"] as? String)
        #expect(item["type"] as? String == "note")
        #expect((item["relativePath"] as? String)?.hasPrefix("Inbox/Notes/") == true)
        let routing = try #require(payload["routing"] as? [String: Any])
        #expect(routing["status"] as? String == "recorded")
        #expect(routing["reviewNeeded"] as? Bool == false)
        #expect(routing["reviewState"] as? String == "accepted")
        let routingReadiness = try #require(payload["routingReadiness"] as? [String: Any])
        #expect(routingReadiness["status"] as? String == "ready")
        #expect(routingReadiness["routeReviewNeeded"] as? Bool == false)
        let safeNextCommands = try #require(payload["safeNextCommands"] as? [String])
        #expect(safeNextCommands == ["cider-cli item get note \(itemID) --json"])
        #expect(payload["readOnly"] as? Bool == false)
        #expect(payload["changed"] as? Bool == true)
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

    @Test("item move resolves obvious media and recipe folder aliases")
    func itemMoveResolvesObviousMediaAndRecipeFolderAliases() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-folder-alias-move-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let movieID = try createNote(title: "Movie Alias Source", content: "movie", vault: vault)
        let movieMove = try parseJSONObject(try runCLI(
            args: ["item", "move", "note", movieID, "--folder", "Media/Movies", "--json"],
            vault: vault
        ).stdout)
        #expect(movieMove["ok"] as? Bool == true)
        let movieAfter = try #require(movieMove["after"] as? [String: Any])
        #expect(movieAfter["relativePath"] as? String == "Media/Movies/Movie Alias Source.md")

        let gameID = try createNote(title: "Game Alias Source", content: "game", vault: vault)
        let gameMove = try parseJSONObject(try runCLI(
            args: ["item", "move", "note", gameID, "--folder", "Games", "--json"],
            vault: vault
        ).stdout)
        #expect(gameMove["ok"] as? Bool == true)
        let gameAfter = try #require(gameMove["after"] as? [String: Any])
        #expect(gameAfter["relativePath"] as? String == "Media/Games/Game Alias Source.md")

        let recipeID = try createNote(title: "Recipe Alias Source", content: "recipe", vault: vault)
        let recipeMove = try parseJSONObject(try runCLI(
            args: ["item", "move", "note", recipeID, "--folder", "Recipes", "--json"],
            vault: vault
        ).stdout)
        #expect(recipeMove["ok"] as? Bool == true)
        let recipeAfter = try #require(recipeMove["after"] as? [String: Any])
        #expect(recipeAfter["relativePath"] as? String == "Spaces/Recipes/Recipe Alias Source.md")
    }

    @Test("item route and review correct resolve destination aliases without accepting truth")
    func itemRouteAndReviewCorrectResolveDestinationAliasesWithoutAcceptingTruth() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-folder-alias-route-review-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let bookmarkCapture = try parseJSONObject(try runCLI(
            args: [
                "capture", "add",
                "--kind", "bookmark",
                "--url", "https://www.imdb.com/title/tt0111161/",
                "--title", "Movie Alias Bookmark",
                "--json",
            ],
            vault: vault
        ).stdout)
        let bookmark = try #require(bookmarkCapture["item"] as? [String: Any])
        let bookmarkID = try #require(bookmark["id"] as? String)

        let routePayload = try parseJSONObject(try runCLI(
            args: [
                "item", "route", "bookmark", bookmarkID,
                "--target-type", "folder",
                "--target-path", "Movies",
                "--reason", "Movie bookmarks belong in Movies.",
                "--status", "needs_review",
                "--json",
            ],
            vault: vault
        ).stdout)
        #expect(routePayload["id"] as? String != nil)
        #expect(routePayload["targetPath"] as? String == "Media/Movies")
        #expect(routePayload["status"] as? String == "needs_review")

        let reviewPayload = try parseJSONObject(try runCLI(
            args: [
                "review", "correct", bookmarkID,
                "--folder", "Media/Games",
                "--reason", "Corrected to game media folder.",
                "--actor", "agent",
                "--json",
            ],
            vault: vault
        ).stdout)
        #expect(reviewPayload["changed"] as? Bool == true)
        let target = try #require(reviewPayload["target"] as? [String: Any])
        #expect(target["relativePath"] as? String == "Media/Games")

        let inspected = try parseJSONObject(try runCLI(args: ["item", "get", "bookmark", bookmarkID, "--json"], vault: vault).stdout)
        let item = try #require(inspected["item"] as? [String: Any])
        #expect((item["relativePath"] as? String)?.contains(".webloc") == true)
        #expect((item["relativePath"] as? String)?.hasPrefix("Media/Games/") == true)
    }

    @Test("item move folder alias rejects webloc shaped destinations without folder creation")
    func itemMoveFolderAliasRejectsWeblocShapedDestinationsWithoutFolderCreation() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-folder-alias-webloc-guard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let noteID = try createNote(title: "Webloc Guard Source", content: "body", vault: vault)
        let result = try runCLI(
            args: ["item", "move", "note", noteID, "--folder", "Media/Movies/Example.webloc", "--json"],
            vault: vault
        )
        let payload = try parseJSONObject(result.stdout)

        #expect(result.status != 0)
        #expect(payload["ok"] as? Bool == false)
        #expect((payload["error"] as? String)?.contains("looks like a file path") == true)
        #expect((payload["error"] as? String)?.contains("--folder Media/Movies") == true)
        #expect(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Media/Movies/Example.webloc").path) == false)
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

    @Test("memory suggest stores linked owner metadata and appears in item context JSON")
    func memorySuggestStoresLinkedOwnerMetadataAndAppearsInItemContextJSON() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-memory-suggest-linked-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let createResult = try runCLI(
            args: ["note", "create", "Alex context", "--content", "Alex prefers late coffee catch-ups.", "--json"],
            vault: vault
        )
        let created = try parseJSONObject(createResult.stdout)
        let noteID = try #require(created["id"] as? String)

        let result = try runCLI(args: [
            "item", "memory-suggest", "note", noteID,
            "--kind", "relationship_context",
            "--value", "Alex prefers late coffee catch-ups.",
            "--evidence", "Journal note says Alex prefers late coffee catch-ups.",
            "--linked-owner", "contact:alex",
            "--linked-owner", "project:cider",
            "--observed-date", "2026-06-10",
            "--memory-key", "alex-coffee-catchups",
            "--memory-status", "current",
            "--source", "codex",
            "--confidence", "0.83",
            "--json",
        ], vault: vault)
        let payload = try parseJSONObject(result.stdout)

        #expect(payload["ok"] as? Bool == true)
        #expect(payload["command"] as? String == "item.memory-suggest")
        let candidate = try #require(payload["candidate"] as? [String: Any])
        #expect(candidate["memoryKind"] as? String == "relationship_context")
        #expect(candidate["observedDate"] as? String == "2026-06-10")
        #expect(candidate["memoryKey"] as? String == "alex-coffee-catchups")
        #expect(candidate["memoryStatus"] as? String == "current")
        #expect(candidate["linkedOwnerRefs"] as? [String] == ["contact:alex", "project:cider"])

        let contextResult = try runCLI(args: ["item", "context", "note", noteID, "--json"], vault: vault)
        let context = try parseJSONObject(contextResult.stdout)
        let memoryCandidates = try #require(context["memoryCandidates"] as? [[String: Any]])
        let contextCandidate = try #require(memoryCandidates.first)
        #expect(contextCandidate["id"] as? String == candidate["id"] as? String)
        #expect(contextCandidate["linkedOwnerRefs"] as? [String] == ["contact:alex", "project:cider"])
        #expect(context["needsReview"] as? Bool == true)
        let blockingIssues = try #require(context["blockingIssues"] as? [String])
        #expect(blockingIssues.contains("memory_candidates_need_review"))

        let reviewQueueResult = try runCLI(args: ["capture", "review-queue", "--kind", "memory_candidate", "--json"], vault: vault)
        let reviewQueue = try parseJSONObject(reviewQueueResult.stdout)
        #expect(reviewQueueResult.status == 0)
        #expect(reviewQueue["command"] as? String == "capture.review-queue")
        #expect(reviewQueue["readOnly"] as? Bool == true)
        #expect(reviewQueue["changed"] as? Bool == false)
        let reviewItems = try #require(reviewQueue["items"] as? [[String: Any]])
        #expect(reviewItems.allSatisfy { $0["kind"] as? String == "memory_candidate" })
        let reviewItem = try #require(reviewItems.first { $0["candidateID"] as? String == candidate["id"] as? String })
        #expect(reviewItem["sourceQuote"] as? String == "Journal note says Alex prefers late coffee catch-ups.")
        #expect(reviewItem["memoryKind"] as? String == "relationship_context")
        #expect(reviewItem["linkedOwnerRefs"] as? [String] == ["contact:alex", "project:cider"])
        #expect(reviewItem["recommendedNextAction"] as? String == "review_memory_candidate")
        let reviewSafeNext = try #require(reviewItem["safeNextCommands"] as? [String])
        #expect(reviewSafeNext.contains("cider-cli item context note \(noteID) --json"))
        #expect(!reviewSafeNext.contains { $0.contains("accept") || $0.contains("promote") })
    }

    @Test("memory candidate review actions are explicit and audited")
    func memoryCandidateReviewActionsAreExplicitAndAudited() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-memory-actions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let createResult = try runCLI(
            args: ["note", "create", "Memory action context", "--content", "Alex likes coffee. Jami likes pineapple drinks.", "--json"],
            vault: vault
        )
        let created = try parseJSONObject(createResult.stdout)
        let noteID = try #require(created["id"] as? String)

        func suggest(_ value: String) throws -> String {
            let result = try runCLI(args: [
                "item", "memory-suggest", "note", noteID,
                "--kind", "relationship_context",
                "--value", value,
                "--evidence", "Source says: \(value)",
                "--linked-owner", "contact:alex",
                "--source", "codex-test",
                "--confidence", "0.8",
                "--json",
            ], vault: vault)
            let payload = try parseJSONObject(result.stdout)
            let candidate = try #require(payload["candidate"] as? [String: Any])
            return try #require(candidate["id"] as? String)
        }

        let acceptID = try suggest("Alex likes coffee.")
        let rejectID = try suggest("Alex dislikes all warm drinks.")
        let deferID = try suggest("Alex may like evening tea.")
        let correctID = try suggest("Jami likes pineapple drinks.")
        let delegateID = try suggest("Alex mentioned a favorite cafe.")
        try seedCoordinatorExactEvidence(
            candidateIDs: [acceptID, rejectID, deferID, correctID, delegateID],
            vault: vault
        )

        let acceptResult = try runCLI(args: [
            "item", "accept-memory-candidate", acceptID,
            "--actor", "codex-test",
            "--json",
        ], vault: vault)
        let accept = try parseJSONObject(acceptResult.stdout)
        #expect(acceptResult.status == 0)
        #expect(accept["command"] as? String == "item.accept-memory-candidate")
        #expect(accept["readOnly"] as? Bool == false)
        #expect(accept["changed"] as? Bool == true)
        #expect(accept["reviewState"] as? String == "accepted")
        let acceptedCandidate = try #require(accept["candidate"] as? [String: Any])
        let acceptedMetadata = try #require(acceptedCandidate["metadata"] as? [String: String])
        #expect(acceptedMetadata["reviewed_by"] == "codex-test")
        #expect(acceptedMetadata["accepted_value"] == "Alex likes coffee.")

        let rejectResult = try runCLI(args: [
            "item", "reject-memory-candidate", rejectID,
            "--reason", "Contradicted by source.",
            "--actor", "codex-test",
            "--json",
        ], vault: vault)
        let reject = try parseJSONObject(rejectResult.stdout)
        #expect(rejectResult.status == 0)
        #expect(reject["command"] as? String == "item.reject-memory-candidate")
        #expect(reject["reviewState"] as? String == "rejected")
        let rejectedCandidate = try #require(reject["candidate"] as? [String: Any])
        let rejectedMetadata = try #require(rejectedCandidate["metadata"] as? [String: String])
        #expect(rejectedMetadata["rejection_reason"] == "Contradicted by source.")

        let deferResult = try runCLI(args: [
            "item", "defer-memory-candidate", deferID,
            "--reason", "Needs user confirmation.",
            "--actor", "codex-test",
            "--json",
        ], vault: vault)
        let deferPayload = try parseJSONObject(deferResult.stdout)
        #expect(deferResult.status == 0)
        #expect(deferPayload["command"] as? String == "item.defer-memory-candidate")
        #expect(deferPayload["reviewState"] as? String == "deferred")
        let deferredCandidate = try #require(deferPayload["candidate"] as? [String: Any])
        let deferredMetadata = try #require(deferredCandidate["metadata"] as? [String: String])
        #expect(deferredMetadata["deferral_reason"] == "Needs user confirmation.")

        let correctResult = try runCLI(args: [
            "item", "correct-memory-candidate", correctID,
            "--value", "Jami likes pineapple coconut drinks.",
            "--evidence", "Corrected source says Jami likes pineapple coconut drinks.",
            "--linked-owner", "contact:jami",
            "--memory-key", "jami-pineapple-coconut-drinks",
            "--actor", "codex-test",
            "--json",
        ], vault: vault)
        let correct = try parseJSONObject(correctResult.stdout)
        #expect(correctResult.status == 0)
        #expect(correct["command"] as? String == "item.correct-memory-candidate")
        #expect(correct["reviewState"] as? String == "needs_review")
        #expect(correct["changedFields"] as? [String] == ["value", "evidence", "linked_owner_refs", "memory_key"])
        let correctedCandidate = try #require(correct["candidate"] as? [String: Any])
        #expect(correctedCandidate["value"] as? String == "Jami likes pineapple coconut drinks.")
        #expect(correctedCandidate["linkedOwnerRefs"] as? [String] == ["contact:jami"])

        let delegateResult = try runCLI(args: [
            "item", "delegate-memory-candidate", delegateID,
            "--task-kind", "confirm_person_preference",
            "--instructions", "Ask for source-backed confirmation only.",
            "--actor", "codex-test",
            "--json",
        ], vault: vault)
        let delegate = try parseJSONObject(delegateResult.stdout)
        #expect(delegateResult.status == 0)
        #expect(delegate["command"] as? String == "item.delegate-memory-candidate")
        #expect(delegate["reviewState"] as? String == "deferred")
        let delegation = try #require(delegate["delegation"] as? [String: Any])
        #expect(delegation["taskKind"] as? String == "confirm_person_preference")
        #expect(delegation["resultPolicy"] as? String == "return_reviewable_evidence_not_truth")

        let rejectedAgain = try runCLI(args: [
            "item", "reject-memory-candidate", acceptID,
            "--reason", "Too late",
            "--json",
        ], vault: vault)
        #expect(rejectedAgain.status != 0)
        let rejectedAgainPayload = try parseJSONObject(rejectedAgain.stdout)
        #expect((rejectedAgainPayload["error"] as? String)?.contains("accepted") == true)

        let queueResult = try runCLI(args: ["capture", "review-queue", "--kind", "memory_candidate", "--json"], vault: vault)
        let queue = try parseJSONObject(queueResult.stdout)
        let queueItems = try #require(queue["items"] as? [[String: Any]])
        #expect(!queueItems.contains { $0["candidateID"] as? String == acceptID })
        #expect(!queueItems.contains { $0["candidateID"] as? String == rejectID })
        #expect(!queueItems.contains { $0["candidateID"] as? String == deferID })
        #expect(!queueItems.contains { $0["candidateID"] as? String == delegateID })
        #expect(queueItems.contains { $0["candidateID"] as? String == correctID && $0["reviewState"] as? String == "needs_review" })

        let getResult = try runCLI(args: ["item", "get", "note", noteID, "--json"], vault: vault)
        let get = try parseJSONObject(getResult.stdout)
        let agentActions = try #require(get["agentActions"] as? [[String: Any]])
        #expect(agentActions.contains { $0["actionType"] as? String == "memory_candidate.accept" })
        #expect(agentActions.contains { $0["actionType"] as? String == "memory_candidate.reject" })
        #expect(agentActions.contains { $0["actionType"] as? String == "memory_candidate.defer" })
        #expect(agentActions.contains { $0["actionType"] as? String == "memory_candidate.correct" })
        #expect(agentActions.contains { $0["actionType"] as? String == "memory_candidate.delegate_enrichment" })
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
        let actionRecords = try #require(apply["actionRecords"] as? [[String: Any]])
        let firstRecord = try #require(actionRecords.first)
        let owner = try #require(firstRecord["owner"] as? [String: Any])
        #expect(owner["ownerType"] as? String == "media_item")
        #expect(owner["ownerID"] as? String == "steam-1145350")
        #expect(owner["ref"] as? String == "media_item:steam-1145350")
        let safeCommands = try #require(firstRecord["safeCommands"] as? [String])
        #expect(safeCommands.contains("cider-cli item owner-get media_item steam-1145350 --json"))
        #expect(safeCommands.contains("cider-cli item search \"steam-1145350\" --json"))
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

    @Test("board milestone inspect counts done column children missing completed metadata")
    func boardMilestoneInspectCountsDoneColumnChildrenMissingCompletedMetadata() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-milestone-done-column-progress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let create = try runCLI(args: ["board", "create", "Milestone Progress Board", "--json"], vault: vault)
        let createPayload = try parseJSONObject(create.stdout)
        let board = try #require(createPayload["board"] as? [String: Any])
        let boardID = try #require(board["id"] as? String)

        let milestone = try runCLI(args: ["board", "milestone", "create", boardID, "--title", "Progress parity", "--json"], vault: vault)
        let milestonePayload = try parseJSONObject(milestone.stdout)
        let milestoneDict = try #require(milestonePayload["milestone"] as? [String: Any])
        let milestoneID = try #require(milestoneDict["id"] as? String)

        _ = try runCLI(args: ["board", "set-column-done", boardID, "--column", "Done", "--done", "--json"], vault: vault)
        let addDoneChild = try runCLI(
            args: ["board", "add-card", boardID, "--column", "Done", "--title", "Done child without metadata", "--parent", milestoneID, "--json"],
            vault: vault
        )
        let addDonePayload = try parseJSONObject(addDoneChild.stdout)
        let doneChild = try #require(addDonePayload["card"] as? [String: Any])
        #expect(doneChild["completed"] == nil)

        _ = try runCLI(
            args: ["board", "add-card", boardID, "--column", "Backlog", "--title", "Queued child", "--parent", milestoneID, "--json"],
            vault: vault
        )

        let inspect = try runCLI(args: ["board", "milestone", "inspect", boardID, "--milestone", milestoneID, "--json"], vault: vault)
        let inspectPayload = try parseJSONObject(inspect.stdout)
        let inspectedMilestone = try #require(inspectPayload["milestone"] as? [String: Any])
        #expect(inspect.status == 0)
        #expect(inspectedMilestone["childCount"] as? Int == 2)
        #expect(inspectedMilestone["completedChildCount"] as? Int == 1)
        #expect(inspectedMilestone["progressFraction"] as? Double == 0.5)

        let audit = try runCLI(args: ["board", "audit", "--json"], vault: vault)
        let auditPayload = try parseJSONObject(audit.stdout)
        let warnings = try #require(auditPayload["warnings"] as? [[String: Any]])
        #expect(warnings.contains { warning in
            warning["type"] as? String == "done_card_missing_completed"
                && warning["cardTitle"] as? String == "Done child without metadata"
        })
    }

    @Test("board move card to done sets completed metadata")
    func boardMoveCardToDoneSetsCompletedMetadata() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-move-card-done-completed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let create = try runCLI(args: ["board", "create", "Move Done Board", "--json"], vault: vault)
        let createPayload = try parseJSONObject(create.stdout)
        let board = try #require(createPayload["board"] as? [String: Any])
        let boardID = try #require(board["id"] as? String)

        _ = try runCLI(args: ["board", "set-column-done", boardID, "--column", "Done", "--done", "--json"], vault: vault)
        let addCard = try runCLI(args: ["board", "add-card", boardID, "--column", "Backlog", "--title", "Move me", "--json"], vault: vault)
        let addPayload = try parseJSONObject(addCard.stdout)
        let card = try #require(addPayload["card"] as? [String: Any])
        let cardID = try #require(card["id"] as? String)
        #expect(card["completed"] == nil)

        let move = try runCLI(args: ["board", "move-card", boardID, "--card", cardID, "--to", "Done", "--json"], vault: vault)
        let movePayload = try parseJSONObject(move.stdout)
        let movedCard = try #require(movePayload["card"] as? [String: Any])
        #expect(move.status == 0)
        #expect(movedCard["completed"] as? String != nil)

        let inspect = try runCLI(args: ["board", "card", "inspect", boardID, "--card", cardID, "--json"], vault: vault)
        let inspectPayload = try parseJSONObject(inspect.stdout)
        let inspectedCard = try #require(inspectPayload["card"] as? [String: Any])
        #expect(inspectedCard["completed"] as? String != nil)
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

    private func assertStrictFailureJSON(
        _ result: (stdout: String, stderr: String, status: Int32),
        command: String,
        errorCode: String
    ) throws -> [String: Any] {
        #expect(result.status != 0, "Expected \(command) to fail")
        #expect(result.stdout.first == "{", "Expected \(command) JSON failure to start at byte 0; stdout: \(result.stdout)")
        let payload = try parseJSONObject(result.stdout)
        #expect(payload["ok"] as? Bool == false)
        #expect(payload["command"] as? String == command)
        #expect(payload["errorCode"] as? String == errorCode)
        #expect(payload["changed"] as? Bool == false)
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

    private func seedRichRemoteOnlySocialBookmark(bookmarkID: String, vault: URL) throws {
        try seedRichRemoteOnlyBookmark(
            bookmarkID: bookmarkID,
            vault: vault,
            title: "Sodam Chicken - Korean fried chicken in Everett",
            urlString: "https://www.tiktok.com/@sodamchicken/video/7521",
            notes: "Rich chunks mention Sodam Chicken, Korean fried chicken, Everett, and TikTok restaurant context.",
            aiSummary: "TikTok restaurant capture for Sodam Chicken in Everett.",
            mediaType: "video",
            thumbnailRemoteURLString: "https://example.invalid/sodam-remote-only.jpeg"
        )
    }

    private func seedRichRemoteOnlyBookmark(
        bookmarkID: String,
        vault: URL,
        title: String,
        urlString: String,
        notes: String,
        aiSummary: String,
        mediaType: String,
        thumbnailRemoteURLString: String
    ) throws {
        let bookmarkUUID = try #require(UUID(uuidString: bookmarkID))
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent("Inbox/Bookmarks"),
            withIntermediateDirectories: true
        )
        let relativePath = try BookmarkFileService.shared.write(
            bookmark: Bookmark(
                id: bookmarkUUID,
                title: title,
                urlString: urlString
            ),
            toDirectory: vault.appendingPathComponent("Inbox/Bookmarks"),
            dirRelativePath: "Inbox/Bookmarks"
        )
        let db = CiderDatabase()
        try db.open(at: vault.appendingPathComponent(".cider/cider.db"))
        defer { db.close() }

        let now = Date().timeIntervalSince1970
        let itemStmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, 'bookmark', ?, ?, ?, NULL, ?);
            """)
        itemStmt.bind(bookmarkID, at: 1)
            .bind(title, at: 2)
            .bind(now, at: 3)
            .bind(now, at: 4)
            .bind(relativePath, at: 5)
        try itemStmt.step()

        let bookmarkStmt = try db.prepare("""
            INSERT INTO bookmarks (
                item_id, url, notes, notes_manually_set, title_manually_set,
                ai_summary, media_type, thumbnail_relative_path, thumbnail_remote_url,
                original_image_path, enrichment_status, last_enriched_at
            )
            VALUES (?, ?, ?, 0, 0, ?, ?, NULL, ?, NULL, 'metadata_complete', ?);
            """)
        bookmarkStmt.bind(bookmarkID, at: 1)
            .bind(urlString, at: 2)
            .bind(notes, at: 3)
            .bind(aiSummary, at: 4)
            .bind(mediaType, at: 5)
            .bind(thumbnailRemoteURLString, at: 6)
            .bind(now, at: 7)
        try bookmarkStmt.step()

        let metadataURL = vault
            .appendingPathComponent(".cider/bookmarks/_cider_bookmarks_index.json")
        try FileManager.default.createDirectory(
            at: metadataURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let bookmarks: [[String: Any]] = [[
            "id": bookmarkID,
            "title": title,
            "urlString": urlString,
            "createdAt": now,
            "updatedAt": now,
            "notes": notes,
            "tags": [],
            "labelIDs": [],
            "dismissedLabelIDs": [],
            "relativePath": relativePath,
            "titleManuallySet": false,
            "notesManuallySet": false,
            "aiSummary": aiSummary,
            "enrichmentStatus": "metadata_complete",
            "lastEnrichedAt": now,
            "metadataUpdatedAt": now,
            "thumbnailRemoteURLString": thumbnailRemoteURLString,
            "mediaType": mediaType,
        ]]
        let updated = try JSONSerialization.data(withJSONObject: bookmarks, options: [.prettyPrinted, .sortedKeys])
        try updated.write(to: metadataURL, options: .atomic)

        let bookmarkAssets = vault.appendingPathComponent(".cider/bookmarks")
        try? FileManager.default.removeItem(at: bookmarkAssets.appendingPathComponent(".thumbnails"))
        try? FileManager.default.removeItem(at: bookmarkAssets.appendingPathComponent(".originals"))
    }

    private func recordNeedsReviewRoute(bookmarkID: String, vault: URL) throws {
        let db = CiderDatabase()
        try db.open(at: vault.appendingPathComponent(".cider/cider.db"))
        defer { db.close() }

        try SecondBrainStore(database: db).recordRoutingDecision(
            SecondBrainRoutingDecision(
                owner: SecondBrainOwnerRef(ownerType: "bookmark", ownerID: bookmarkID),
                itemID: bookmarkID,
                targetType: "folder",
                targetID: nil,
                targetPath: "Inbox/Bookmarks",
                confidence: 0.0,
                reason: "Route review remains required after visible card quality is current.",
                status: "needs_review",
                actor: "agent",
                source: "test.fixture",
                candidatesJSON: nil
            )
        )
    }

    @Test("shared CLI review adapter preserves general and direct memory semantic parity and exact retry")
    func sharedCLIReviewAdapterPreservesMemoryParityAndRetry() throws {
        let homeVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-review-adapter-home-\(UUID().uuidString)", isDirectory: true)
        let journalVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-review-adapter-journal-\(UUID().uuidString)", isDirectory: true)
        let generalVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-review-adapter-general-\(UUID().uuidString)", isDirectory: true)
        let directVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-review-adapter-direct-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: homeVault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: journalVault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: generalVault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directVault, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: homeVault)
            try? FileManager.default.removeItem(at: journalVault)
            try? FileManager.default.removeItem(at: generalVault)
            try? FileManager.default.removeItem(at: directVault)
        }
        let candidateID = "cli-parity-memory"
        try seedCoordinatorMemoryCandidate(id: candidateID, vault: homeVault)
        try seedCoordinatorMemoryCandidate(id: candidateID, vault: journalVault)
        try seedCoordinatorMemoryCandidate(id: candidateID, vault: generalVault)
        try seedCoordinatorMemoryCandidate(id: candidateID, vault: directVault)
        let generalTablesBefore = try coordinatorCLITableFingerprint(vault: generalVault)
        let generalFilesBefore = try coordinatorCLISourceFileFingerprint(vault: generalVault)
        let homeOutcome = try performCoordinatorMemoryApproval(
            candidateID: candidateID,
            surface: .home,
            actor: "cli-parity-actor",
            vault: homeVault
        )
        let journalOutcome = try performCoordinatorMemoryApproval(
            candidateID: candidateID,
            surface: .journal,
            actor: "cli-parity-actor",
            vault: journalVault
        )

        let generalResult = try runCLI(args: [
            "review", "approve", candidateID, "--actor", "cli-parity-actor", "--json",
        ], vault: generalVault)
        let directResult = try runCLI(args: [
            "item", "accept-memory-candidate", candidateID, "--actor", "cli-parity-actor", "--json",
        ], vault: directVault)
        let general = try parseJSONObject(generalResult.stdout)
        let direct = try parseJSONObject(directResult.stdout)

        #expect(generalResult.status == 0)
        #expect(directResult.status == 0)
        for payload in [general, direct] {
            #expect(payload["readOnly"] as? Bool == false)
            #expect(payload["changed"] as? Bool == true)
            #expect(payload["reviewState"] as? String == "accepted")
            #expect(payload["truthBoundary"] as? String == "accepted_memory_candidate")
            #expect(payload["availability"] as? String == "available")
            #expect(payload["evidenceStatus"] as? String == "verified_exact_evidence")
            #expect(payload["exactEvidenceRequirement"] as? String == "required")
            #expect(payload["mutationAuthority"] as? String == "review_approved_candidate")
            #expect(payload["actionReceiptID"] as? String != nil)
            #expect(payload["expectedVersionSelector"] as? String != nil)
        }
        let homeSnapshot = reviewSemanticSnapshot(homeOutcome)
        let generalSnapshot = try reviewSemanticSnapshot(general)
        let directSnapshot = try reviewSemanticSnapshot(direct)
        #expect(homeSnapshot == reviewSemanticSnapshot(journalOutcome))
        #expect(homeSnapshot == generalSnapshot)
        #expect(homeSnapshot == directSnapshot)
        #expect(general["actionReceiptID"] as? String == direct["actionReceiptID"] as? String)
        #expect(general["actionReceiptID"] as? String == homeOutcome.actionReceiptID)
        #expect(try coordinatorCLITableFingerprint(vault: generalVault) != generalTablesBefore)
        #expect(try coordinatorCLISourceFileFingerprint(vault: generalVault) == generalFilesBefore)
        let generalReceipt = try #require(general["actionReceipt"] as? [String: Any])
        let directReceipt = try #require(direct["actionReceipt"] as? [String: Any])
        #expect(generalReceipt["id"] as? String == directReceipt["id"] as? String)
        #expect(generalReceipt["command"] as? String == "review.memory-candidates.approve")
        #expect(generalReceipt["action"] as? String == "approve")
        #expect(direct["command"] as? String == "item.accept-memory-candidate")
        #expect(directReceipt["command"] as? String == "item.accept-memory-candidate")
        #expect(directReceipt["action"] as? String == "accept")
        #expect(directReceipt["canonicalCommand"] as? String == "review.memory-candidates.approve")
        #expect(directReceipt["canonicalAction"] as? String == "approve")

        let selector = try #require(general["expectedVersionSelector"] as? String)
        let beforeRetry = try coordinatorCLITableFingerprint(vault: generalVault)
        let retryResult = try runCLI(args: [
            "review", "approve", candidateID,
            "--actor", "cli-parity-actor",
            "--expected-version", selector,
            "--json",
        ], vault: generalVault)
        let retry = try parseJSONObject(retryResult.stdout)
        #expect(retryResult.status == 0)
        #expect(retry["changed"] as? Bool == false)
        #expect(retry["actionReceiptID"] as? String == general["actionReceiptID"] as? String)
        #expect(try coordinatorCLITableFingerprint(vault: generalVault) == beforeRetry)
        #expect(try coordinatorCLISourceFileFingerprint(vault: generalVault) == generalFilesBefore)

        let safeCommands = try #require(general["safeVerificationCommands"] as? [String])
        let ledgerSafe = try #require(safeCommands.first { $0.contains("item action-ledger list") })
        #expect(ledgerSafe.contains("--command review.memory-candidates.approve"))
        let safeArgs = ledgerSafe.split(separator: " ").map(String.init).dropFirst().map { $0 }
        let safeResult = try runCLI(args: safeArgs, vault: generalVault)
        let safePayload = try parseJSONObject(safeResult.stdout)
        let safeEntries = try #require(safePayload["entries"] as? [[String: Any]])
        #expect(safeResult.status == 0)
        #expect(safeEntries.contains { $0["id"] as? String == general["actionReceiptID"] as? String })
        #expect(safePayload["usage"] == nil)
        print("CID837-CLI-SMOKE schema=ok,command,action,readOnly,changed,candidateRef,reviewFamily,reviewState,truthBoundary,availability,evidenceStatus,mutationAuthority,expectedVersionSelector,actionReceiptID,safeVerificationCommands receipt=\(general["actionReceiptID"] as? String ?? "missing") tablesBefore=\(coordinatorCLIFingerprintDigest(generalTablesBefore)) tablesAfter=\(coordinatorCLIFingerprintDigest(beforeRetry)) files=\(coordinatorCLIFingerprintDigest(generalFilesBefore)) retryUnchanged=true safeLedgerCount=\(safeEntries.count)")
    }

    @Test("shared CLI review adapter preserves general and direct graph target and receipt parity")
    func sharedCLIReviewAdapterPreservesGraphParity() throws {
        let generalVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-review-graph-general-\(UUID().uuidString)", isDirectory: true)
        let directVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-review-graph-direct-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: generalVault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directVault, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: generalVault)
            try? FileManager.default.removeItem(at: directVault)
        }
        let candidateID = "cli-parity-graph"
        try seedCoordinatorGraphCandidate(id: candidateID, vault: generalVault)
        try seedCoordinatorGraphCandidate(id: candidateID, vault: directVault)
        let inspect = try parseJSONObject(try runCLI(
            args: ["item", "graph-candidate", candidateID, "--json"],
            vault: generalVault
        ).stdout)
        let inspectedCandidate = try #require(inspect["candidate"] as? [String: Any])
        let options = try #require(inspectedCandidate["targetOptions"] as? [[String: Any]])
        let option = try #require(options.first)
        let optionRef = try #require(option["optionRef"] as? String)

        let generalResult = try runCLI(args: [
            "review", "approve", candidateID,
            "--target-option", optionRef,
            "--actor", "cli-graph-parity-actor",
            "--json",
        ], vault: generalVault)
        let directResult = try runCLI(args: [
            "item", "graph-candidate-accept", candidateID,
            "--target-option", optionRef,
            "--actor", "cli-graph-parity-actor",
            "--json",
        ], vault: directVault)
        let general = try parseJSONObject(generalResult.stdout)
        let direct = try parseJSONObject(directResult.stdout)

        #expect(generalResult.status == 0)
        #expect(directResult.status == 0)
        for payload in [general, direct] {
            #expect(payload["changed"] as? Bool == true)
            #expect(payload["reviewState"] as? String == "accepted")
            #expect(payload["truthBoundary"] as? String == "accepted_graph_truth")
            #expect(payload["availability"] as? String == "available")
            #expect(payload["evidenceStatus"] as? String == "verified_exact_evidence")
            #expect(payload["mutationAuthority"] as? String == "review_approved_candidate")
        }
        #expect(general["actionReceiptID"] as? String == direct["actionReceiptID"] as? String)
        #expect((general["coordinatorOutcome"] as? [String: Any])?["targetOwnerRef"] as? String
            == (direct["coordinatorOutcome"] as? [String: Any])?["targetOwnerRef"] as? String)
        let relation = try #require(direct["relation"] as? [String: Any])
        #expect(relation["relationType"] as? String == "visited")
        #expect(direct["command"] as? String == "item.accept-graph-candidate")
    }

    @Test("shared CLI review adapter rejects changed correction against the original exact version without writes")
    func sharedCLIReviewAdapterRejectsChangedCorrectionWithoutWrites() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-review-adapter-correction-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let candidateID = "cli-correction-memory"
        try seedCoordinatorMemoryCandidate(id: candidateID, vault: vault)

        let firstResult = try runCLI(args: [
            "review", "correct", candidateID,
            "--value", "Corrected private preference A.",
            "--actor", "cli-correction-actor",
            "--json",
        ], vault: vault)
        let first = try parseJSONObject(firstResult.stdout)
        #expect(firstResult.status == 0)
        #expect(first["changed"] as? Bool == true)
        #expect(first["reviewState"] as? String == "needs_review")
        let selector = try #require(first["expectedVersionSelector"] as? String)
        let fingerprint = try coordinatorCLITableFingerprint(vault: vault)

        let changedResult = try runCLI(args: [
            "review", "correct", candidateID,
            "--value", "Corrected private preference B.",
            "--actor", "cli-correction-actor",
            "--expected-version", selector,
            "--json",
        ], vault: vault)
        let changed = try parseJSONObject(changedResult.stdout)
        #expect(changedResult.status != 0)
        #expect(changed["changed"] as? Bool == false)
        #expect(changed["errorClassification"] as? String == "stale_expected_version")
        #expect(changed["actionReceiptID"] is NSNull)
        #expect(try coordinatorCLITableFingerprint(vault: vault) == fingerprint)
        #expect(!changedResult.stdout.contains("Corrected private preference A."))
        #expect(!changedResult.stdout.contains("Corrected private preference B."))
    }

    @Test("shared CLI review adapter fails closed for required evidence and unavailable graph targets without private output")
    func sharedCLIReviewAdapterFailsClosedWithoutPrivateOutput() throws {
        let memoryVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-review-missing-evidence-\(UUID().uuidString)", isDirectory: true)
        let directMemoryVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-direct-missing-evidence-\(UUID().uuidString)", isDirectory: true)
        let graphVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-review-target-unavailable-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: memoryVault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directMemoryVault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: graphVault, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: memoryVault)
            try? FileManager.default.removeItem(at: directMemoryVault)
            try? FileManager.default.removeItem(at: graphVault)
        }
        let memoryID = "cli-missing-evidence-memory"
        try seedCoordinatorMemoryCandidate(id: memoryID, vault: memoryVault, exactEvidence: false)
        try seedCoordinatorMemoryCandidate(id: memoryID, vault: directMemoryVault, exactEvidence: false)
        let memoryTables = try coordinatorCLITableFingerprint(vault: memoryVault)
        let memoryFiles = try coordinatorCLISourceFileFingerprint(vault: memoryVault)
        let directMemoryTables = try coordinatorCLITableFingerprint(vault: directMemoryVault)
        let directMemoryFiles = try coordinatorCLISourceFileFingerprint(vault: directMemoryVault)
        let memoryReceiptCount = try coordinatorTableRowCount("action_receipts", vault: memoryVault)
        let memoryActionCount = try coordinatorTableRowCount("agent_actions", vault: memoryVault)
        let memoryRelationCount = try coordinatorTableRowCount("owner_relations", vault: memoryVault)
        let directMemoryReceiptCount = try coordinatorTableRowCount("action_receipts", vault: directMemoryVault)
        let directMemoryActionCount = try coordinatorTableRowCount("agent_actions", vault: directMemoryVault)
        let directMemoryRelationCount = try coordinatorTableRowCount("owner_relations", vault: directMemoryVault)
        let privateReason = "PRIVATE-REJECTION-REASON-6f2b"
        let missingResult = try runCLI(args: [
            "review", "reject", memoryID,
            "--reason", privateReason,
            "--actor", "cli-private-test",
            "--json",
        ], vault: memoryVault)
        let missing = try parseJSONObject(missingResult.stdout)
        #expect(missingResult.status != 0)
        #expect(missing["errorClassification"] as? String == "missing_exact_evidence")
        #expect(missing["evidenceStatus"] as? String == "missing_exact_evidence")
        #expect(missing["actionReceiptID"] is NSNull)
        #expect(!missingResult.stdout.contains(privateReason))
        #expect(try coordinatorCLITableFingerprint(vault: memoryVault) == memoryTables)
        #expect(try coordinatorCLISourceFileFingerprint(vault: memoryVault) == memoryFiles)
        #expect(try coordinatorTableRowCount("action_receipts", vault: memoryVault) == memoryReceiptCount)
        #expect(try coordinatorTableRowCount("agent_actions", vault: memoryVault) == memoryActionCount)
        #expect(try coordinatorTableRowCount("owner_relations", vault: memoryVault) == memoryRelationCount)

        let directMissingResult = try runCLI(args: [
            "item", "reject-memory-candidate", memoryID,
            "--reason", privateReason,
            "--actor", "cli-private-test",
            "--json",
        ], vault: directMemoryVault)
        let directMissing = try parseJSONObject(directMissingResult.stdout)
        #expect(directMissingResult.status != 0)
        #expect(directMissing["errorClassification"] as? String == "missing_exact_evidence")
        #expect(directMissing["evidenceStatus"] as? String == "missing_exact_evidence")
        #expect(directMissing["actionReceiptID"] is NSNull)
        #expect(!directMissingResult.stdout.contains(privateReason))
        #expect(try coordinatorCLITableFingerprint(vault: directMemoryVault) == directMemoryTables)
        #expect(try coordinatorCLISourceFileFingerprint(vault: directMemoryVault) == directMemoryFiles)
        #expect(try coordinatorTableRowCount("action_receipts", vault: directMemoryVault) == directMemoryReceiptCount)
        #expect(try coordinatorTableRowCount("agent_actions", vault: directMemoryVault) == directMemoryActionCount)
        #expect(try coordinatorTableRowCount("owner_relations", vault: directMemoryVault) == directMemoryRelationCount)
        print("CID837-MISSING-EVIDENCE generalTables=\(coordinatorCLIFingerprintDigest(memoryTables)) generalFiles=\(coordinatorCLIFingerprintDigest(memoryFiles)) directTables=\(coordinatorCLIFingerprintDigest(directMemoryTables)) directFiles=\(coordinatorCLIFingerprintDigest(directMemoryFiles)) unchanged=true receiptsAdded=0 actionsAdded=0 relationsAdded=0")

        let graphID = "cli-target-unavailable-graph"
        try seedCoordinatorGraphCandidate(id: graphID, vault: graphVault)
        let graphTables = try coordinatorCLITableFingerprint(vault: graphVault)
        let privateTarget = "target-option:/private/graph-target-SENTINEL-91"
        let unavailableResult = try runCLI(args: [
            "review", "approve", graphID,
            "--target-option", privateTarget,
            "--actor", "cli-private-test",
            "--json",
        ], vault: graphVault)
        let unavailable = try parseJSONObject(unavailableResult.stdout)
        #expect(unavailableResult.status != 0)
        #expect(unavailable["errorClassification"] as? String == "target_unavailable")
        #expect(unavailable["actionReceiptID"] is NSNull)
        #expect(!unavailableResult.stdout.contains(privateTarget))
        #expect(try coordinatorCLITableFingerprint(vault: graphVault) == graphTables)
    }

    @Test("general and direct graph approval never select among multiple targets without an explicit option")
    func sharedCLIReviewAdapterRequiresExplicitGraphTargetWithoutWrites() throws {
        let generalVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-review-target-required-general-\(UUID().uuidString)", isDirectory: true)
        let directVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-review-target-required-direct-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: generalVault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directVault, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: generalVault)
            try? FileManager.default.removeItem(at: directVault)
        }
        let candidateID = "cli-explicit-target-required"
        try seedCoordinatorGraphCandidate(id: candidateID, vault: generalVault, includeMatchingOwners: true)
        try seedCoordinatorGraphCandidate(id: candidateID, vault: directVault, includeMatchingOwners: true)
        let generalOptions = try coordinatorGraphTargetOptions(candidateID: candidateID, vault: generalVault)
        let directOptions = try coordinatorGraphTargetOptions(candidateID: candidateID, vault: directVault)
        #expect(generalOptions.count >= 2)
        #expect(directOptions.count >= 2)
        let generalTables = try coordinatorCLITableFingerprint(vault: generalVault)
        let generalFiles = try coordinatorCLISourceFileFingerprint(vault: generalVault)
        let directTables = try coordinatorCLITableFingerprint(vault: directVault)
        let directFiles = try coordinatorCLISourceFileFingerprint(vault: directVault)
        let generalReceiptCount = try coordinatorTableRowCount("action_receipts", vault: generalVault)
        let generalRelationCount = try coordinatorTableRowCount("owner_relations", vault: generalVault)
        let directReceiptCount = try coordinatorTableRowCount("action_receipts", vault: directVault)
        let directRelationCount = try coordinatorTableRowCount("owner_relations", vault: directVault)

        let generalResult = try runCLI(args: [
            "review", "approve", candidateID, "--actor", "cli-target-required", "--json",
        ], vault: generalVault)
        let directResult = try runCLI(args: [
            "item", "accept-graph-candidate", candidateID, "--actor", "cli-target-required", "--json",
        ], vault: directVault)
        let general = try parseJSONObject(generalResult.stdout)
        let direct = try parseJSONObject(directResult.stdout)

        for (result, payload) in [(generalResult, general), (directResult, direct)] {
            #expect(result.status != 0)
            #expect(payload["changed"] as? Bool == false)
            #expect(payload["errorClassification"] as? String == "target_required")
            #expect(payload["actionReceiptID"] is NSNull)
        }
        #expect(try coordinatorCLITableFingerprint(vault: generalVault) == generalTables)
        #expect(try coordinatorCLISourceFileFingerprint(vault: generalVault) == generalFiles)
        #expect(try coordinatorCLITableFingerprint(vault: directVault) == directTables)
        #expect(try coordinatorCLISourceFileFingerprint(vault: directVault) == directFiles)
        #expect(try coordinatorTableRowCount("action_receipts", vault: generalVault) == generalReceiptCount)
        #expect(try coordinatorTableRowCount("owner_relations", vault: generalVault) == generalRelationCount)
        #expect(try coordinatorTableRowCount("action_receipts", vault: directVault) == directReceiptCount)
        #expect(try coordinatorTableRowCount("owner_relations", vault: directVault) == directRelationCount)
        print("CID837-NO-TARGET options=\(generalOptions.count) generalTables=\(coordinatorCLIFingerprintDigest(generalTables)) generalFiles=\(coordinatorCLIFingerprintDigest(generalFiles)) directTables=\(coordinatorCLIFingerprintDigest(directTables)) directFiles=\(coordinatorCLIFingerprintDigest(directFiles)) unchanged=true receiptsAdded=0 relationsAdded=0")
    }

    @Test("Home Journal general CLI and direct CLI preserve one checkpoint-one durable receipt")
    func reviewSurfacesPreserveCheckpointOneDurableReceipt() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-review-durable-receipt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let candidateID = "cli-durable-receipt-memory"
        let actor = "cli-durable-receipt-actor"
        try seedCoordinatorMemoryCandidate(id: candidateID, vault: vault)

        let databaseURL = vault.appendingPathComponent(".cider/cider.db")
        let homeDatabase = CiderDatabase()
        try homeDatabase.open(at: databaseURL)
        let original = try #require(try SecondBrainEnrichmentOutputService(database: homeDatabase).output(id: candidateID))
        let expectedSelector = CiderReviewCLIActionAdapter.expectedVersionSelector(
            reviewState: original.reviewState,
            updatedAt: original.updatedAt
        )
        let baseRequest = CiderReviewActionRequest(
            identity: .init(candidateRef: "memory_candidate:\(candidateID)", family: .memoryCandidate),
            expectedVersion: .init(reviewState: original.reviewState, updatedAt: original.updatedAt),
            action: .approve,
            actor: actor,
            surface: .home,
            exactEvidenceRequirement: .required,
            mutationAuthority: .reviewApprovedCandidate
        )
        let homeOutcome = CiderReviewActionCoordinator(database: homeDatabase).perform(baseRequest)
        let receiptID = try #require(homeOutcome.actionReceiptID)
        let homeReceipt = try #require(
            try SecondBrainActionReceiptLedgerService(database: homeDatabase).inspect(id: receiptID)
        )
        homeDatabase.close()

        let journalDatabase = CiderDatabase()
        try journalDatabase.open(at: databaseURL)
        var journalRequest = baseRequest
        journalRequest.surface = .journal
        let journalOutcome = CiderReviewActionCoordinator(database: journalDatabase).perform(journalRequest)
        let journalReceipt = try #require(
            try SecondBrainActionReceiptLedgerService(database: journalDatabase).inspect(id: receiptID)
        )
        journalDatabase.close()

        let generalResult = try runCLI(args: [
            "review", "approve", candidateID,
            "--actor", actor,
            "--expected-version", expectedSelector,
            "--json",
        ], vault: vault)
        let directResult = try runCLI(args: [
            "item", "accept-memory-candidate", candidateID,
            "--actor", actor,
            "--expected-version", expectedSelector,
            "--json",
        ], vault: vault)
        let general = try parseJSONObject(generalResult.stdout)
        let direct = try parseJSONObject(directResult.stdout)
        let generalReceipt = try coordinatorReceipt(id: receiptID, vault: vault)
        let directReceipt = try coordinatorReceipt(id: receiptID, vault: vault)

        #expect(homeOutcome.changed)
        #expect(journalOutcome.isSuccessful)
        #expect(!journalOutcome.changed)
        #expect(generalResult.status == 0)
        #expect(directResult.status == 0)
        #expect(general["changed"] as? Bool == false)
        #expect(direct["changed"] as? Bool == false)
        #expect(general["actionReceiptID"] as? String == receiptID)
        #expect(direct["actionReceiptID"] as? String == receiptID)
        #expect(homeReceipt == journalReceipt)
        #expect(homeReceipt == generalReceipt)
        #expect(homeReceipt == directReceipt)

        let ownerRef = original.owner.canonicalRef
        let evidenceRef = try #require(original.metadata["source_evidence_ref"])
        #expect(homeReceipt.command == "review.memory-candidates.approve")
        #expect(homeReceipt.action == "approve")
        #expect(homeReceipt.actor == actor)
        #expect(homeReceipt.status == "succeeded")
        #expect(homeReceipt.owner == original.owner)
        #expect(homeReceipt.sourceRefs == ["memory_candidate:\(candidateID)", ownerRef])
        #expect(homeReceipt.evidenceRefs == [evidenceRef])
        #expect(!homeReceipt.readOnly)
        #expect(homeReceipt.changed)
        #expect(homeReceipt.errorCode == nil)
        #expect(homeReceipt.correlationID == "journal-review:memory_candidate:\(candidateID)")
        #expect(homeReceipt.safeVerificationCommands == [
            "cider-cli item memory-facts inspect \(candidateID) --json",
            "cider-cli item action-ledger list --owner \(ownerRef) --command review.memory-candidates.approve --json",
            "cider-cli capture review-queue --kind memory_candidate --include-deferred --json",
        ])
        #expect(homeReceipt.safeNextCommands == [
            "cider-cli item memory-facts inspect \(candidateID) --json",
            "cider-cli capture review-queue --kind memory_candidate --json",
            "cider-cli review summary --json",
        ])
        #expect(DatabaseHelpers.decodeJSON([String: String].self, from: homeReceipt.beforeJSON)?["reviewState"] == "suggested")
        let after = try #require(DatabaseHelpers.decodeJSON([String: String].self, from: homeReceipt.afterJSON))
        #expect(after["requestFingerprint"]?.count == 64)
        #expect(after["resultingCandidateVersion"]?.count == 16)
        #expect(after["reviewState"] == "accepted")
        #expect(after["truthBoundary"] == "accepted_memory_candidate")
        let receiptJSON = try #require(homeReceipt.receiptJSON)
        let decodedReceipt = try #require(
            JSONSerialization.jsonObject(with: Data(receiptJSON.utf8)) as? [String: Any]
        )
        #expect(decodedReceipt["command"] as? String == "review.memory-candidates.approve")
        #expect(decodedReceipt["action"] as? String == "approve")

        let projectedDirectReceipt = try #require(direct["actionReceipt"] as? [String: Any])
        #expect(projectedDirectReceipt["command"] as? String == "item.accept-memory-candidate")
        #expect(projectedDirectReceipt["action"] as? String == "accept")
        #expect(projectedDirectReceipt["canonicalCommand"] as? String == homeReceipt.command)
        #expect(projectedDirectReceipt["canonicalAction"] as? String == homeReceipt.action)
        #expect(try coordinatorTableRowCount("action_receipts", vault: vault) == 1)
        #expect(try coordinatorTableRowCount("agent_actions", vault: vault) == 1)
        print("CID837-DURABLE-RECEIPT id=\(receiptID) command=\(homeReceipt.command) action=\(homeReceipt.action) sourceRefs=\(homeReceipt.sourceRefs.count) evidenceRefs=\(homeReceipt.evidenceRefs.count) identicalAcross=home,journal,general-cli,direct-cli")
    }

    @Test("candidate mutation help is side effect free for text JSON canonical commands and aliases")
    func candidateMutationHelpIsSideEffectFree() throws {
        let commands: [[String]] = [
            ["review", "approve"], ["review", "reject"], ["review", "defer"], ["review", "correct"],
            ["item", "accept-graph-candidate"], ["item", "graph-candidate-accept"],
            ["item", "reject-graph-candidate"], ["item", "graph-candidate-reject"],
            ["item", "accept-memory-candidate"], ["item", "memory-candidate-accept"],
            ["item", "reject-memory-candidate"], ["item", "memory-candidate-reject"],
            ["item", "defer-memory-candidate"], ["item", "memory-candidate-defer"],
            ["item", "correct-memory-candidate"], ["item", "memory-candidate-correct"],
        ]
        for command in commands {
            for json in [false, true] {
                let vault = FileManager.default.temporaryDirectory
                    .appendingPathComponent("cider-cli-candidate-help-\(UUID().uuidString)")
                var args = command + ["--help"]
                if json { args.append("--json") }
                let result = try runCLI(args: args, vault: vault)
                #expect(result.status == 0)
                if json {
                    let payload = try parseJSONObject(result.stdout)
                    #expect(payload["readOnly"] as? Bool == true)
                    #expect(payload["changed"] as? Bool == false)
                    #expect((payload["command"] as? String)?.hasSuffix(".help") == true)
                } else {
                    #expect(result.stdout.contains("Usage: cider-cli"))
                }
                #expect(!FileManager.default.fileExists(atPath: vault.path))
            }
        }
    }

    private struct ReviewSemanticSnapshot: Equatable {
        var candidateRef: String
        var family: String
        var action: String
        var actor: String
        var availability: String
        var evidenceRequirement: String
        var evidenceStatus: String
        var mutationAuthority: String
        var changed: Bool
        var reviewState: String
        var truthBoundary: String
        var actionReceiptID: String?
        var targetOwnerRef: String?
    }

    private func reviewSemanticSnapshot(_ outcome: CiderReviewActionOutcome) -> ReviewSemanticSnapshot {
        let availability: String
        switch outcome.availability {
        case .available: availability = "available"
        case .unavailable: availability = "unavailable"
        }
        return ReviewSemanticSnapshot(
            candidateRef: outcome.identity.candidateRef,
            family: outcome.identity.family.rawValue,
            action: outcome.action.rawValue,
            actor: outcome.actor,
            availability: availability,
            evidenceRequirement: outcome.exactEvidenceRequirement.rawValue,
            evidenceStatus: outcome.evidenceStatus.rawValue,
            mutationAuthority: outcome.mutationAuthority.rawValue,
            changed: outcome.changed,
            reviewState: outcome.resultingReviewState,
            truthBoundary: outcome.truthBoundary,
            actionReceiptID: outcome.actionReceiptID,
            targetOwnerRef: outcome.targetOwnerRef
        )
    }

    private func reviewSemanticSnapshot(_ payload: [String: Any]) throws -> ReviewSemanticSnapshot {
        let outcome = try #require(payload["coordinatorOutcome"] as? [String: Any])
        return ReviewSemanticSnapshot(
            candidateRef: try #require(outcome["candidateRef"] as? String),
            family: try #require(outcome["reviewFamily"] as? String),
            action: try #require(outcome["action"] as? String),
            actor: try #require(outcome["actor"] as? String),
            availability: try #require(outcome["availability"] as? String),
            evidenceRequirement: try #require(outcome["evidenceRequirement"] as? String),
            evidenceStatus: try #require(outcome["evidenceStatus"] as? String),
            mutationAuthority: try #require(outcome["mutationAuthority"] as? String),
            changed: try #require(outcome["changed"] as? Bool),
            reviewState: try #require(outcome["reviewState"] as? String),
            truthBoundary: try #require(outcome["truthBoundary"] as? String),
            actionReceiptID: outcome["actionReceiptID"] as? String,
            targetOwnerRef: outcome["targetOwnerRef"] as? String
        )
    }

    private func performCoordinatorMemoryApproval(
        candidateID: String,
        surface: CiderReviewInvokingSurface,
        actor: String,
        vault: URL
    ) throws -> CiderReviewActionOutcome {
        let database = CiderDatabase()
        try database.open(at: vault.appendingPathComponent(".cider/cider.db"))
        defer { database.close() }
        let output = try #require(try SecondBrainEnrichmentOutputService(database: database).output(id: candidateID))
        return CiderReviewActionCoordinator(database: database).perform(
            CiderReviewActionRequest(
                identity: .init(candidateRef: "memory_candidate:\(candidateID)", family: .memoryCandidate),
                expectedVersion: .init(reviewState: output.reviewState, updatedAt: output.updatedAt),
                action: .approve,
                actor: actor,
                surface: surface,
                exactEvidenceRequirement: .required,
                mutationAuthority: .reviewApprovedCandidate
            )
        )
    }

    private func seedCoordinatorMemoryCandidate(
        id: String,
        vault: URL,
        exactEvidence: Bool = true
    ) throws {
        let noteID = try createNote(
            title: "CLI coordinator source",
            content: "A private source-backed statement.",
            vault: vault
        )
        let database = CiderDatabase()
        try database.open(at: vault.appendingPathComponent(".cider/cider.db"))
        defer { database.close() }
        let timestamp = Date(timeIntervalSince1970: 1_800_000_001)
        let updatedTimestamp = timestamp.addingTimeInterval(1)
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: noteID)
        var output = SecondBrainEnrichmentOutput(
            id: id,
            owner: owner,
            kind: "memory_candidate",
            value: "A durable memory candidate.",
            normalizedValue: "a durable memory candidate.",
            label: "Memory candidate",
            evidence: "A private source-backed statement.",
            source: "test.cli.review.coordinator",
            confidence: 0.91,
            reviewState: "suggested",
            metadata: [
                "memory_kind": "preference",
                "candidate_kind": "preference",
                "requires_review": "true",
                "truth_boundary": "reviewable_candidate_not_truth",
            ],
            createdAt: timestamp,
            updatedAt: updatedTimestamp
        )
        if exactEvidence {
            output.metadata["capture_event_id"] = "capture-\(id)"
            output.metadata["source_span_start"] = "0"
            output.metadata["source_span_end"] = String(output.evidence.count)
        }
        try SecondBrainEnrichmentOutputService(database: database).record(output)
    }

    private func seedCoordinatorGraphCandidate(
        id: String,
        vault: URL,
        exactEvidence: Bool = true,
        includeMatchingOwners: Bool = false
    ) throws {
        let noteID = try createNote(
            title: "CLI graph coordinator source",
            content: "Visited Private Target.",
            vault: vault
        )
        let database = CiderDatabase()
        try database.open(at: vault.appendingPathComponent(".cider/cider.db"))
        defer { database.close() }
        let timestamp = Date(timeIntervalSince1970: 1_800_000_101)
        var output = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: SecondBrainOwnerRef(ownerType: "note", ownerID: noteID),
            candidateKind: .objectRelation,
            mentionText: "Private Target",
            sourceQuote: "Visited Private Target.",
            sourceKind: "journal",
            objectTypeGuesses: [.place],
            relationGuesses: [.visited],
            confidence: 0.91,
            source: "test.cli.review.coordinator"
        )
        output.id = id
        output.createdAt = timestamp
        output.updatedAt = timestamp.addingTimeInterval(1)
        if exactEvidence {
            output.metadata["capture_event_id"] = "capture-\(id)"
            output.metadata["source_span_start"] = "0"
            output.metadata["source_span_end"] = String(output.evidence.count)
        }
        try SecondBrainEnrichmentOutputService(database: database).record(output)
        if includeMatchingOwners {
            let labels = SecondBrainOwnerLabelIndexService(database: database)
            _ = try labels.upsertLabel(
                owner: SecondBrainOwnerRef(ownerType: "place", ownerID: "private-target-a"),
                ownerKind: "place",
                canonicalLabel: "Private Target",
                sourceRefs: ["place:private-target-a"],
                labelSource: "test.cli.review.coordinator"
            )
            _ = try labels.upsertLabel(
                owner: SecondBrainOwnerRef(ownerType: "place", ownerID: "private-target-b"),
                ownerKind: "place",
                canonicalLabel: "Private Target Annex",
                aliases: ["Private Target"],
                sourceRefs: ["place:private-target-b"],
                labelSource: "test.cli.review.coordinator"
            )
        }
    }

    private func coordinatorGraphTargetOptions(candidateID: String, vault: URL) throws -> [CiderGraphCandidateTargetOption] {
        let database = CiderDatabase()
        try database.open(at: vault.appendingPathComponent(".cider/cider.db"))
        defer { database.close() }
        let item = try #require(
            try CiderReviewQueueService(database: database)
                .list(limit: Int.max, includeDeferred: true)
                .items
                .first { $0.candidateRef == "graph_candidate:\(candidateID)" }
        )
        return item.targetOptions
    }

    private func seedCoordinatorExactEvidence(candidateIDs: [String], vault: URL) throws {
        let database = CiderDatabase()
        try database.open(at: vault.appendingPathComponent(".cider/cider.db"))
        defer { database.close() }
        let service = SecondBrainEnrichmentOutputService(database: database)
        for (index, candidateID) in candidateIDs.enumerated() {
            var output = try #require(try service.output(id: candidateID))
            output.metadata["capture_event_id"] = "capture-\(candidateID)"
            output.metadata["source_span_start"] = "0"
            output.metadata["source_span_end"] = String(output.evidence.count)
            output.updatedAt = output.updatedAt.addingTimeInterval(Double(index + 1))
            try service.record(output)
        }
    }

    private func coordinatorReceipt(id: String, vault: URL) throws -> SecondBrainActionReceiptRecord {
        let database = CiderDatabase()
        try database.open(at: vault.appendingPathComponent(".cider/cider.db"))
        defer { database.close() }
        return try #require(try SecondBrainActionReceiptLedgerService(database: database).inspect(id: id))
    }

    private func coordinatorTableRowCount(_ table: String, vault: URL) throws -> Int {
        let allowed = ["action_receipts", "agent_actions", "owner_relations"]
        precondition(allowed.contains(table))
        let database = CiderDatabase()
        try database.open(at: vault.appendingPathComponent(".cider/cider.db"))
        defer { database.close() }
        let statement = try database.prepare("SELECT COUNT(*) FROM \(table);")
        guard try statement.step() else { return 0 }
        return statement.int(at: 0)
    }

    private func coordinatorCLITableFingerprint(vault: URL) throws -> [String] {
        let database = CiderDatabase()
        try database.open(at: vault.appendingPathComponent(".cider/cider.db"))
        defer { database.close() }
        let tableStatement = try database.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name;")
        var tables: [String] = []
        while try tableStatement.step() { tables.append(tableStatement.string(at: 0)) }
        return try tables.map { table in
            let pragma = try database.prepare("PRAGMA table_info(\"\(table.replacingOccurrences(of: "\"", with: "\"\""))\");")
            var columns: [String] = []
            while try pragma.step() { columns.append(pragma.string(at: 1)) }
            let pairs = columns.flatMap { ["'\($0)'", "quote(\"\($0)\")"] }.joined(separator: ", ")
            let rowsStatement = try database.prepare("SELECT json_object(\(pairs)) FROM \"\(table.replacingOccurrences(of: "\"", with: "\"\""))\";")
            var rows: [String] = []
            while try rowsStatement.step() { rows.append(rowsStatement.string(at: 0)) }
            let digest = SHA256.hash(data: Data(rows.sorted().joined(separator: "\n").utf8))
                .map { String(format: "%02x", $0) }
                .joined()
            return "\(table):count=\(rows.count);sha256=\(digest)"
        }
    }

    private func coordinatorCLISourceFileFingerprint(vault: URL) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: vault,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var fingerprints: [String] = []
        for case let url as URL in enumerator {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let relative = url.path.replacingOccurrences(of: vault.path + "/", with: "")
            let digest = SHA256.hash(data: try Data(contentsOf: url))
                .map { String(format: "%02x", $0) }
                .joined()
            fingerprints.append("\(relative):sha256=\(digest)")
        }
        return fingerprints.sorted()
    }

    private func coordinatorCLIFingerprintDigest(_ fingerprints: [String]) -> String {
        SHA256.hash(data: Data(fingerprints.joined(separator: "\n").utf8))
            .map { String(format: "%02x", $0) }
            .joined()
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

    private func tableRowCount(_ table: String, vault: URL) throws -> Int {
        let allowedTables: Set<String> = [
            "content_chunks",
            "enrichment_outputs",
            "similarity_candidates",
            "owner_relations",
        ]
        precondition(allowedTables.contains(table))

        let db = CiderDatabase()
        try db.open(at: vault.appendingPathComponent(".cider/cider.db"))
        defer { db.close() }

        let stmt = try db.prepare("SELECT count(*) FROM \(table);")
        guard try stmt.step() else {
            return 0
        }
        return stmt.int(at: 0)
    }

    private func generatedSecondBrainRowCounts(vault: URL) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for table in ["content_chunks", "enrichment_outputs", "similarity_candidates", "owner_relations"] {
            counts[table] = try tableRowCount(table, vault: vault)
        }
        return counts
    }

    private func runCLI(args: [String], stdin: String? = nil) throws -> (stdout: String, stderr: String, status: Int32) {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-agent-safety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        return try runCLI(args: args, vault: vault, stdin: stdin)
    }

    private func captureStandardOutput(_ action: () throws -> Void) throws -> String {
        fflush(stdout)
        let originalStdout = dup(STDOUT_FILENO)
        let pipe = Pipe()
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        do {
            try action()
            fflush(stdout)
            try pipe.fileHandleForWriting.close()
            dup2(originalStdout, STDOUT_FILENO)
            close(originalStdout)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            fflush(stdout)
            try? pipe.fileHandleForWriting.close()
            dup2(originalStdout, STDOUT_FILENO)
            close(originalStdout)
            _ = pipe.fileHandleForReading.readDataToEndOfFile()
            throw error
        }
    }

    private func runCLI(
        args: [String],
        vault: URL,
        stdin: String? = nil,
        environment: [String: String] = [:]
    ) throws -> (stdout: String, stderr: String, status: Int32) {
        let cli = try cliURL()
        let process = Process()
        process.executableURL = cli
        process.arguments = ["--vault", vault.path] + args
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let outputGroup = DispatchGroup()
        let stdoutBuffer = CLIOutputBuffer()
        let stderrBuffer = CLIOutputBuffer()
        outputGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutBuffer.set(stdout.fileHandleForReading.readDataToEndOfFile())
            outputGroup.leave()
        }
        outputGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrBuffer.set(stderr.fileHandleForReading.readDataToEndOfFile())
            outputGroup.leave()
        }
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
        outputGroup.wait()

        return (
            String(data: stdoutBuffer.data(), encoding: .utf8) ?? "",
            String(data: stderrBuffer.data(), encoding: .utf8) ?? "",
            process.terminationStatus
        )
    }

    private func vaultRelativeFileList(_ vault: URL) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: vault,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return enumerator.compactMap { item in
            guard let url = item as? URL else { return nil }
            return String(url.path.dropFirst(vault.path.count + 1))
        }.sorted()
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

    private static func relativeDateString(daysFromToday: Int) -> String {
        let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: daysFromToday, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
