import Foundation
import Testing

struct FileBackedDomainContractsTests {
    @Test("storage docs declare file-backed domain contracts")
    func storageDocsDeclareFileBackedDomainContracts() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let storageDoc = repoRoot.appendingPathComponent("Docs/STORAGE.md")
        let agentDoc = repoRoot.appendingPathComponent("Docs/AGENT.md")
        let source = try String(contentsOf: storageDoc, encoding: .utf8)
        let agentSource = try String(contentsOf: agentDoc, encoding: .utf8)

        #expect(source.contains("## File-Backed Domain Contracts"))
        for domain in [
            "Kanban board YAML",
            "Kanban SQLite projection",
            "Spaces",
            "Media",
            "Agent memory",
            "Folder Kanban",
            "Dashboard topics and cards",
            "Vault folders",
        ] {
            #expect(source.contains("| \(domain) |"), "Missing file-backed contract for \(domain)")
        }
        for status in ["Canonical file store", "Projection", "Hybrid", "Legacy"] {
            #expect(source.contains("| \(status) |") || source.contains(" \(status) |"), "Missing contract status \(status)")
        }
        #expect(agentSource.contains("file-backed domain contracts in `Docs/STORAGE.md`"))
        #expect(agentSource.contains("legacy memory files and folder-kanban YAML are not first-class second-brain truth"))
    }

    @Test("core docs declare accepted second brain graph contract")
    func coreDocsDeclareAcceptedSecondBrainGraphContract() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let storageDoc = repoRoot.appendingPathComponent("Docs/STORAGE.md")
        let agentDoc = repoRoot.appendingPathComponent("Docs/AGENT.md")
        let cliDoc = repoRoot.appendingPathComponent("Docs/CLI.md")
        let storageSource = try String(contentsOf: storageDoc, encoding: .utf8)
        let agentSource = try String(contentsOf: agentDoc, encoding: .utf8)
        let cliSource = try String(contentsOf: cliDoc, encoding: .utf8)

        for snippet in [
            "## Accepted Backend Graph Contract",
            "`owner_relations`",
            "`capture_events`",
            "`capture_attachments`",
            "`projects`",
            "`enrichment_outputs`",
            "`similarity_candidates`",
            "`item graph-health --json`",
            "`item project-context <project> --json`",
        ] {
            #expect(storageSource.contains(snippet), "Docs/STORAGE.md missing accepted graph contract snippet: \(snippet)")
        }

        for snippet in [
            "## Accepted Graph Workflow",
            "Run `cider-cli item graph-health --json` before raw SQLite inspection",
            "Use `cider-cli item project-context <project> --json` for project graph context",
            "Record friction as scoped Kanban follow-up cards",
        ] {
            #expect(agentSource.contains(snippet), "Docs/AGENT.md missing accepted graph workflow snippet: \(snippet)")
        }

        for snippet in [
            "`item graph-health --json`: read-only graph readiness",
            "`item project-context <project> --json`: project graph context",
            "Graph-heavy commands should expose counts and safe follow-up commands",
            "`media identify --dry-run --json`: read-only media identification preview",
            "`media identify --apply --json`: mutating media identification apply path",
        ] {
            #expect(cliSource.contains(snippet), "Docs/CLI.md missing graph CLI contract snippet: \(snippet)")
        }
    }

    @Test("cli docs declare second brain v1 agent capture contract")
    func cliDocsDeclareSecondBrainV1AgentCaptureContract() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let cliDoc = repoRoot.appendingPathComponent("Docs/CLI.md")
        let agentDoc = repoRoot.appendingPathComponent("Docs/AGENT.md")
        let cliSource = try String(contentsOf: cliDoc, encoding: .utf8)
        let agentSource = try String(contentsOf: agentDoc, encoding: .utf8)

        for snippet in [
            "## Second Brain v1 Agent CLI Surface",
            "`cider-cli capture add` is the canonical agent capture API.",
            "`--kind note|todo|bookmark|file|event|contact`",
            "`--stdin` reads exact raw source text from standard input.",
            "`--text-file <path>` reads exact raw source text from a file.",
            "`--url <url>` is the explicit bookmark source.",
            "`--path <source-file-path>` is the explicit file source for `capture add`.",
            "`--folder <target-folder-path>` is the destination folder selector for `capture add`",
            "In `capture add`, `--path` always means source file, never destination.",
            "Use `--folder \"Inbox/Notes\"` when capturing a note directly to the Notes inbox.",
            "Do not pass artifact filenames to `item move --path`",
            "`--json` is required for agent verification.",
            "printf '%s' \"$RAW_NOTE\" | cider-cli capture add --kind note --stdin --json",
            "cider-cli capture add --kind note --folder \"Inbox/Notes\" \"Quick note\" --json",
            "printf '%s' \"$RAW_TODO\" | cider-cli capture add --kind todo --stdin --json",
            "cider-cli capture add --kind bookmark --url \"https://example.com?a=1&b=two\" --json",
            "cider-cli capture add --kind file --path \"/path/with spaces.txt\" --json",
            "cider-cli capture add --kind event --title \"Passport appointment\" --date 2026-05-20 --time \"10:30 AM\" --location \"City Hall\" --stdin --json",
            "cider-cli capture add --kind contact --name \"Avery Example\" --email avery@example.com --phone \"555-0100\" --stdin --json",
            "`bookmark add`, `note create`, `todo create`, and `file import` are temporary compatibility wrappers.",
            "`compatibilityWrapper: true`",
            "Hidden or removed legacy commands return `legacyRemoved: true`",
        ] {
            #expect(cliSource.contains(snippet), "Docs/CLI.md missing Second Brain v1 CLI snippet: \(snippet)")
        }

        for legacySnippet in [
            "event create --json` and `contact create --json` should return",
            "Legacy bookmark batch enrichment remains available as `bookmark enrich --all --confirm`",
            "- bookmarks: add, get, list/search",
            "- todos/events/contacts/files: create, list",
            "Active todos come from non-completed `todo list --json` items only.",
        ] {
            #expect(!cliSource.contains(legacySnippet), "Docs/CLI.md still presents legacy command contract: \(legacySnippet)")
        }

        for snippet in [
            "New agent capture must use `cider-cli capture add --kind ... --json`.",
            "Do not call hidden type-specific legacy commands such as `bookmark`, `note`, `todo`, `event`, `contact`, `file`, `folder`, `tag`, `label`, or `dashboard` as alternate APIs.",
            "Use `cider-cli board ...` commands for routine Kanban mutations",
            "Do not patch board YAML by hand for normal card work.",
            "If a needed Kanban mutation is not supported by `cider-cli board ...`, create or update a scoped follow-up card to add the missing CLI command",
        ] {
            #expect(agentSource.contains(snippet), "Docs/AGENT.md missing Second Brain v1 CLI agent rule: \(snippet)")
        }

        for snippet in [
            "Use supported `cider-cli board ...` commands for routine card creation",
            "If a command lacks a needed routine operation, create a scoped follow-up to add the missing CLI command",
            "Raw board YAML edits are only for parser/storage debugging or emergency repair.",
        ] {
            #expect(cliSource.contains(snippet), "Docs/CLI.md missing Kanban CLI safety snippet: \(snippet)")
        }
    }

    @Test("root agent instructions declare canonical bookmark capture workflow")
    func rootAgentInstructionsDeclareCanonicalBookmarkCaptureWorkflow() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let rootAgentDoc = repoRoot.appendingPathComponent("AGENTS.md")
        let rootSource = try String(contentsOf: rootAgentDoc, encoding: .utf8)

        for snippet in [
            "cider-cli capture add --kind bookmark --url \"<url>\" --json",
            "Inspect the capture JSON for duplicate, routing, review, provenance, indexing, `nextSafeAction`, and `safeNextCommands`.",
            "cider-cli item get bookmark <id> --json",
            "Route or review only through backend-backed `item`/`review` commands.",
        ] {
            #expect(rootSource.contains(snippet), "AGENTS.md missing canonical bookmark capture snippet: \(snippet)")
        }

        for legacySnippet in [
            "duplicate-check <url> --json",
            "bookmark enrich <id>",
            "bookmark get <id> --json",
        ] {
            #expect(!rootSource.contains(legacySnippet), "AGENTS.md still presents legacy bookmark capture command: \(legacySnippet)")
        }
    }

    @Test("integration script uses isolated canonical capture workflow")
    func integrationScriptUsesIsolatedCanonicalCaptureWorkflow() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let script = repoRoot.appendingPathComponent("scripts/integration-test.sh")
        let source = try String(contentsOf: script, encoding: .utf8)

        for snippet in [
            "TEST_VAULT=$(mktemp -d",
            "trap cleanup EXIT",
            "run_cli()",
            "\"$CLI\" --vault \"$TEST_VAULT\"",
            "assert_capture_receipt",
            "capture add --kind bookmark",
            "capture add --kind note",
            "capture add --kind todo",
            "capture add --kind file",
            "capture add --kind event",
            "capture add --kind contact",
            "item get bookmark",
            "review list --json",
        ] {
            #expect(source.contains(snippet), "scripts/integration-test.sh missing isolated capture snippet: \(snippet)")
        }

        for legacySnippet in [
            "$CLI trash empty",
            "~/CiderVault",
            "$HOME/CiderVault",
            "bookmark add",
            "event create",
            "contact create",
            "duplicate-check",
            "$CLI query",
        ] {
            #expect(!source.contains(legacySnippet), "scripts/integration-test.sh still uses real-vault or legacy surface: \(legacySnippet)")
        }
    }

    @Test("core docs declare sync and media bridge boundaries")
    func coreDocsDeclareSyncAndMediaBridgeBoundaries() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let storageDoc = repoRoot.appendingPathComponent("Docs/STORAGE.md")
        let cliDoc = repoRoot.appendingPathComponent("Docs/CLI.md")
        let storageSource = try String(contentsOf: storageDoc, encoding: .utf8)
        let cliSource = try String(contentsOf: cliDoc, encoding: .utf8)

        for snippet in [
            "Cider Web sync currently covers bookmarks, folders, and notes.",
            "It does not sync second-brain graph tables",
            "MediaItem metadata remains YAML-backed",
            "`media identify --apply` writes MediaItem YAML and records `media_item` action provenance",
        ] {
            #expect(storageSource.contains(snippet), "Docs/STORAGE.md missing sync/media bridge snippet: \(snippet)")
        }

        for snippet in [
            "`media identify --dry-run --json` reports `readOnly: true` and `changed: false`",
            "`media identify --apply --json` reports `readOnly: false`",
            "`reviewLane.safeActions` must include only read-only commands",
        ] {
            #expect(cliSource.contains(snippet), "Docs/CLI.md missing media CLI bridge snippet: \(snippet)")
        }
    }

    @Test("core docs declare native spaces cutover plan")
    func coreDocsDeclareNativeSpacesCutoverPlan() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let storageDoc = repoRoot.appendingPathComponent("Docs/STORAGE.md")
        let cliDoc = repoRoot.appendingPathComponent("Docs/CLI.md")
        let featuresDoc = repoRoot.appendingPathComponent("Docs/FEATURES.md")
        let storageSource = try String(contentsOf: storageDoc, encoding: .utf8)
        let cliSource = try String(contentsOf: cliDoc, encoding: .utf8)
        let featuresSource = try String(contentsOf: featuresDoc, encoding: .utf8)

        for snippet in [
            "The native cutover target is a SQLite `spaces` table",
            "Path containment is storage topology, not semantic membership.",
            "`.cider-space.yaml` should become an export/projection compatibility surface",
        ] {
            #expect(storageSource.contains(snippet), "Docs/STORAGE.md missing native Spaces cutover snippet: \(snippet)")
        }

        for snippet in [
            "`space list --json` and `space explain <name-or-id> --json` expose an `authority` object",
            "`authority.pathContainmentIsSemantic: false`",
        ] {
            #expect(cliSource.contains(snippet), "Docs/CLI.md missing native Spaces CLI snippet: \(snippet)")
        }

        #expect(featuresSource.contains("The target backend shape is a native SQLite `spaces` table"))
    }

    @Test("core docs declare space membership owner relation bridge")
    func coreDocsDeclareSpaceMembershipOwnerRelationBridge() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let storageDoc = repoRoot.appendingPathComponent("Docs/STORAGE.md")
        let cliDoc = repoRoot.appendingPathComponent("Docs/CLI.md")
        let storageSource = try String(contentsOf: storageDoc, encoding: .utf8)
        let cliSource = try String(contentsOf: cliDoc, encoding: .utf8)

        for snippet in [
            "`space_memberships` writes are mirrored into `owner_relations`",
            "`belongs_to_space`",
            "`space` owner",
        ] {
            #expect(storageSource.contains(snippet), "Docs/STORAGE.md missing Space owner relation bridge snippet: \(snippet)")
        }

        for snippet in [
            "`item route ... --target-type space`",
            "creates a `belongs_to_space` owner relation",
        ] {
            #expect(cliSource.contains(snippet), "Docs/CLI.md missing Space owner relation bridge snippet: \(snippet)")
        }
    }
}
