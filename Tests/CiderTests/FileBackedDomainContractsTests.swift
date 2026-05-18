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
}
