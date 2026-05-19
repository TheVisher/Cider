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
