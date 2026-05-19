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
        ] {
            #expect(cliSource.contains(snippet), "Docs/CLI.md missing graph CLI contract snippet: \(snippet)")
        }
    }
}
