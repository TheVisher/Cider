import Foundation
import Testing
@testable import Cider

@Suite("Mutation Audit Tests")
@MainActor
struct MutationAuditServiceTests {

    private func makeTempDBURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
        let filename = "cider-audit-test-\(UUID().uuidString).db"
        return dir.appendingPathComponent(filename)
    }

    private func cleanup(_ url: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        let path = url.path
        try? fm.removeItem(atPath: path + "-wal")
        try? fm.removeItem(atPath: path + "-shm")
    }

    private func makeTestDB() throws -> (CiderDatabase, URL) {
        let url = makeTempDBURL()
        let db = CiderDatabase()
        try db.open(at: url)
        return (db, url)
    }

    @Test("Mutation audit entries round-trip with before/after snapshots")
    func auditEntryRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = MutationAuditService(database: db)
        let itemID = UUID()

        service.record(
            action: "rename",
            itemType: "note",
            itemID: itemID,
            before: ["title": "Old", "folderID": "inbox"],
            after: ["title": "New", "folderID": "Projects"],
            metadata: ["reason": "manual"]
        )

        let entries = service.loadEntries()
        #expect(entries.count == 1)
        #expect(entries[0].itemID == itemID)
        #expect(entries[0].action == "rename")
        #expect(entries[0].itemType == "note")
        #expect(entries[0].source == .ui)
        #expect(entries[0].beforeState["title"] == "Old")
        #expect(entries[0].afterState["title"] == "New")
        #expect(entries[0].metadata["reason"] == "manual")
    }

    @Test("Mutation audit context overrides source for agent writes")
    func auditContextOverridesSource() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = MutationAuditService(database: db)
        let itemID = UUID()

        MutationAuditContext.withSource(.agent) {
            service.record(
                action: "delete",
                itemType: "bookmark",
                itemID: itemID,
                before: ["title": "Example"],
                after: ["trashItemID": UUID().uuidString]
            )
        }

        let entries = service.loadEntries()
        #expect(entries.count == 1)
        #expect(entries[0].source == .agent)
        #expect(entries[0].action == "delete")
    }
}
