import Foundation
import Testing
@testable import Cider

@Suite("CardLabelStorage SQLite Tests")
@MainActor
struct CardLabelStorageSQLiteTests {

    /// Create a temporary database URL for isolated testing.
    private func makeTempDBURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
        let filename = "cider-label-test-\(UUID().uuidString).db"
        return dir.appendingPathComponent(filename)
    }

    /// Remove a temporary database file and its WAL/SHM companions.
    private func cleanup(_ url: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        let path = url.path
        try? fm.removeItem(atPath: path + "-wal")
        try? fm.removeItem(atPath: path + "-shm")
    }

    /// Create and open a fresh database for testing.
    private func makeTestDB() throws -> (CiderDatabase, URL) {
        let url = makeTempDBURL()
        let db = CiderDatabase()
        try db.open(at: url)
        return (db, url)
    }

    // MARK: - Round-Trip

    @Test("Labels round-trip through SQLite: create, load, verify")
    func labelsRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let storage = CardLabelStorage(database: db)

        // Create two labels
        let label1 = storage.createLabel(name: "Work", colorHex: "#3B82F6", kind: .custom)
        let label2 = storage.createLabel(name: "Personal", colorHex: "#22C55E", kind: .custom)

        #expect(storage.labels.count == 2)

        // Create a fresh storage instance that loads from the same DB
        let storage2 = CardLabelStorage(database: db)
        #expect(storage2.labels.count == 2)

        // Verify data integrity
        let loaded1 = storage2.labels.first { $0.id == label1.id }
        #expect(loaded1 != nil)
        #expect(loaded1?.name == "Work")
        #expect(loaded1?.colorHex == "#3B82F6")
        #expect(loaded1?.kind == .custom)

        let loaded2 = storage2.labels.first { $0.id == label2.id }
        #expect(loaded2 != nil)
        #expect(loaded2?.name == "Personal")
        #expect(loaded2?.colorHex == "#22C55E")
    }

    @Test("Update label persists to SQLite")
    func updateLabelPersists() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let storage = CardLabelStorage(database: db)
        var label = storage.createLabel(name: "Draft", colorHex: "#EAB308")

        // Update the label
        label.name = "Final"
        label.colorHex = "#EF4444"
        let updated = storage.updateLabel(label)
        #expect(updated)

        // Reload from DB and verify
        let storage2 = CardLabelStorage(database: db)
        let loaded = storage2.labels.first { $0.id == label.id }
        #expect(loaded?.name == "Final")
        #expect(loaded?.colorHex == "#EF4444")
    }

    @Test("Delete label removes from SQLite")
    func deleteLabelRemoves() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let storage = CardLabelStorage(database: db)
        let label = storage.createLabel(name: "Temporary", colorHex: "#6B7280")
        #expect(storage.labels.count == 1)

        // Delete directly via the database method (skip cascade — other storages not initialized)
        storage.deleteFromDatabase(db, labelID: label.id)

        // Reload from DB and verify deletion
        let storage2 = CardLabelStorage(database: db)
        #expect(storage2.labels.isEmpty)
    }

    @Test("Labels load sorted by name (case-insensitive)")
    func labelsSortedByName() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let storage = CardLabelStorage(database: db)
        _ = storage.createLabel(name: "Zebra")
        _ = storage.createLabel(name: "alpha")
        _ = storage.createLabel(name: "Beta")

        // Reload and check order
        let storage2 = CardLabelStorage(database: db)
        let names = storage2.labels.map(\.name)
        #expect(names == ["alpha", "Beta", "Zebra"])
    }

    @Test("Date fields survive round-trip with reasonable precision")
    func dateFieldsPrecision() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let storage = CardLabelStorage(database: db)
        let before = Date()
        let label = storage.createLabel(name: "Timed")
        let after = Date()

        let storage2 = CardLabelStorage(database: db)
        let loaded = storage2.labels.first { $0.id == label.id }
        #expect(loaded != nil)

        // createdAt should be between before and after
        #expect(loaded!.createdAt.timeIntervalSince(before) >= -0.01)
        #expect(loaded!.createdAt.timeIntervalSince(after) <= 0.01)
    }

    @Test("Empty database loads empty labels array")
    func emptyDatabaseLoadsEmpty() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let storage = CardLabelStorage(database: db)
        #expect(storage.labels.isEmpty)
    }

    @Test("persistToDatabase with explicit db parameter works")
    func explicitDbPersist() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let label = CardLabel(name: "Direct", colorHex: "#8B5CF6")
        let storage = CardLabelStorage(database: db)
        storage.persistToDatabase(db, label: label)

        // Reload to verify
        let storage2 = CardLabelStorage(database: db)
        let loaded = storage2.labels.first { $0.id == label.id }
        #expect(loaded != nil)
        #expect(loaded?.name == "Direct")
    }

    @Test("deleteFromDatabase with explicit db parameter works")
    func explicitDbDelete() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let storage = CardLabelStorage(database: db)
        let label = storage.createLabel(name: "ToDelete")

        storage.deleteFromDatabase(db, labelID: label.id)

        // Reload to verify
        let storage2 = CardLabelStorage(database: db)
        #expect(storage2.labels.isEmpty)
    }
}
