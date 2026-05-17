import Foundation
import Testing
@testable import Cider

@Suite("Contact SQLite Tests")
@MainActor
struct ContactSQLiteTests {

    // MARK: - Helpers

    /// Create a temporary database URL for isolated testing.
    private func makeTempDBURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
        let filename = "cider-contact-test-\(UUID().uuidString).db"
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

    /// Create ContactStorage wired to the test database.
    private func makeService(_ db: CiderDatabase) -> ContactStorage {
        ContactStorage(database: db)
    }

    private func makeTempVaultURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-contact-vault-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: - Basic Round-Trip

    @Test("Contact round-trips through SQLite: displayName stored in items.title")
    func contactRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let contact = ContactCard(displayName: "Jane Doe", email: "jane@example.com")
        service.persistContactToDatabase(db, contact: contact)

        // Verify items.title holds the display name (not a separate column).
        let stmt = try db.prepare("SELECT title FROM items WHERE id = ?;")
        stmt.bind(DatabaseHelpers.encode(contact.id), at: 1)
        try stmt.step()
        #expect(stmt.string(at: 0) == "Jane Doe")

        let service2 = makeService(db)
        service2.loadContactsFromDatabase(db)

        #expect(service2.contacts.count == 1)
        let loaded = service2.contacts[0]
        #expect(loaded.id == contact.id)
        #expect(loaded.displayName == "Jane Doe")
        #expect(loaded.email == "jane@example.com")
    }

    // MARK: - All Fields

    @Test("Contact with all fields round-trips correctly")
    func contactAllFields() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let birthday = Date(timeIntervalSince1970: 500_000_000)
        let created = Date(timeIntervalSince1970: 1_700_000_000)

        let contact = ContactCard(
            displayName: "Full Contact",
            relationshipLabel: "Friend",
            birthday: birthday,
            notes: "Met at conference",
            email: "full@example.com",
            phone: "+1 555 1234",
            address: "123 Main St",
            hasAvatar: true,
            createdAt: created,
            updatedAt: created
        )
        service.persistContactToDatabase(db, contact: contact)

        let service2 = makeService(db)
        service2.loadContactsFromDatabase(db)

        let loaded = service2.contacts[0]
        #expect(loaded.displayName == "Full Contact")
        #expect(loaded.relationshipLabel == "Friend")
        #expect(loaded.notes == "Met at conference")
        #expect(loaded.email == "full@example.com")
        #expect(loaded.phone == "+1 555 1234")
        #expect(loaded.address == "123 Main St")
        #expect(loaded.hasAvatar == true)
        #expect(abs((loaded.birthday ?? .distantPast).timeIntervalSince(birthday)) < 0.001)
    }

    // MARK: - Nil Birthday

    @Test("Nil birthday round-trips as nil")
    func nilBirthdayRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let contact = ContactCard(displayName: "No Birthday", birthday: nil)
        service.persistContactToDatabase(db, contact: contact)

        let service2 = makeService(db)
        service2.loadContactsFromDatabase(db)

        #expect(service2.contacts[0].birthday == nil)
    }

    // MARK: - Update

    @Test("Updating an existing contact replaces its data including displayName in items.title")
    func updateContact() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        var contact = ContactCard(displayName: "Old Name", email: "old@example.com")
        service.persistContactToDatabase(db, contact: contact)

        contact.displayName = "New Name"
        contact.email = "new@example.com"
        contact.phone = "555-9999"
        service.persistContactToDatabase(db, contact: contact)

        // Verify items.title updated
        let stmt = try db.prepare("SELECT title FROM items WHERE id = ?;")
        stmt.bind(DatabaseHelpers.encode(contact.id), at: 1)
        try stmt.step()
        #expect(stmt.string(at: 0) == "New Name")

        let service2 = makeService(db)
        service2.loadContactsFromDatabase(db)

        #expect(service2.contacts.count == 1)
        let loaded = service2.contacts[0]
        #expect(loaded.displayName == "New Name")
        #expect(loaded.email == "new@example.com")
        #expect(loaded.phone == "555-9999")
    }

    @Test("Contact update and avatar deletion mutations record audit entries")
    func contactMetadataMutationsRecordAuditEntries() throws {
        let (db, url) = try makeTestDB()
        let vault = makeTempVaultURL()
        let fm = FileManager.default
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()
        try fm.createDirectory(
            at: StoragePaths.cachedInboxSubdirectoryURL(for: .contacts),
            withIntermediateDirectories: true
        )

        let contact = ContactCard(
            displayName: "Audit Contact",
            email: "old@example.com",
            phone: "555-1000",
            hasAvatar: true
        )
        let seed = makeService(db)
        seed.persistContactToDatabase(db, contact: contact)

        let service = makeService(db)
        service.loadContactsFromDatabase(db)

        var updated = try #require(service.contacts.first { $0.id == contact.id })
        updated.email = "new@example.com"
        updated.phone = "555-2000"
        #expect(service.updateContact(updated) == true)
        service.deleteAvatar(for: contact.id)

        let entries = MutationAuditService(database: db).loadEntries()
        let update = entries.first { $0.itemID == contact.id && $0.action == "update" }
        let avatar = entries.first { $0.itemID == contact.id && $0.action == "delete_avatar" }

        #expect(update?.itemType == "contact")
        #expect(update?.beforeState["email"] == "old@example.com")
        #expect(update?.afterState["email"] == "new@example.com")
        #expect(update?.afterState["phone"] == "555-2000")

        #expect(avatar?.itemType == "contact")
        #expect(avatar?.beforeState["hasAvatar"] == "true")
        #expect(avatar?.afterState["hasAvatar"] == "false")
    }

    // MARK: - Delete

    @Test("Delete contact removes items + CASCADE cleans join tables")
    func deleteContact() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let labelStorage = CardLabelStorage(database: db)
        let label = labelStorage.createLabel(name: "X")

        let service = makeService(db)

        // Target contact to link to.
        let target = ContactCard(displayName: "Target")
        service.persistContactToDatabase(db, contact: target)

        let contact = ContactCard(
            displayName: "Doomed",
            labelIDs: [label.id],
            linkedEntities: [LibraryEntityRef(type: .contact, entityID: target.id)]
        )
        service.persistContactToDatabase(db, contact: contact)

        service.deleteContactFromDatabase(db, contactID: contact.id)

        let service2 = makeService(db)
        service2.loadContactsFromDatabase(db)
        #expect(service2.contacts.contains(where: { $0.id == contact.id }) == false)
        #expect(service2.contacts.contains(where: { $0.id == target.id }) == true)

        // Join tables cleaned via CASCADE
        let labelsStmt = try db.prepare("SELECT count(*) FROM item_labels WHERE item_id = ?;")
        labelsStmt.bind(DatabaseHelpers.encode(contact.id), at: 1)
        try labelsStmt.step()
        #expect(labelsStmt.int(at: 0) == 0)

        let linksStmt = try db.prepare("SELECT count(*) FROM item_links WHERE source_id = ?;")
        linksStmt.bind(DatabaseHelpers.encode(contact.id), at: 1)
        try linksStmt.step()
        #expect(linksStmt.int(at: 0) == 0)

        // Detail row gone
        let contactStmt = try db.prepare("SELECT count(*) FROM contacts WHERE item_id = ?;")
        contactStmt.bind(DatabaseHelpers.encode(contact.id), at: 1)
        try contactStmt.step()
        #expect(contactStmt.int(at: 0) == 0)
    }

    // MARK: - Multiple

    @Test("Multiple contacts persist and load correctly")
    func multipleContacts() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let c1 = ContactCard(displayName: "Alice")
        let c2 = ContactCard(displayName: "Bob")
        let c3 = ContactCard(displayName: "Carol")

        service.persistContactToDatabase(db, contact: c1)
        service.persistContactToDatabase(db, contact: c2)
        service.persistContactToDatabase(db, contact: c3)

        let service2 = makeService(db)
        service2.loadContactsFromDatabase(db)

        #expect(service2.contacts.count == 3)
        let names = Set(service2.contacts.map(\.displayName))
        #expect(names == Set(["Alice", "Bob", "Carol"]))
    }

    // MARK: - Labels

    @Test("Label IDs round-trip through item_labels and updates replace old assignments")
    func labelIDsRoundTripAndUpdate() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let labelStorage = CardLabelStorage(database: db)
        let l1 = labelStorage.createLabel(name: "L1")
        let l2 = labelStorage.createLabel(name: "L2")
        let l3 = labelStorage.createLabel(name: "L3")

        let service = makeService(db)
        var contact = ContactCard(displayName: "Labeled", labelIDs: [l1.id, l2.id])
        service.persistContactToDatabase(db, contact: contact)

        let loaded1 = makeService(db)
        loaded1.loadContactsFromDatabase(db)
        #expect(Set(loaded1.contacts[0].labelIDs) == Set([l1.id, l2.id]))

        contact.labelIDs = [l2.id, l3.id]
        service.persistContactToDatabase(db, contact: contact)

        let loaded2 = makeService(db)
        loaded2.loadContactsFromDatabase(db)
        #expect(Set(loaded2.contacts[0].labelIDs) == Set([l2.id, l3.id]))
    }

    // MARK: - Folder

    @Test("Contact with folder ID round-trips")
    func contactWithFolder() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let folder = VaultFolder(relativePath: "Friends")
        let folderService = VaultFolderService(database: db)
        folderService.persistToDatabase(db, folder: folder)

        let service = makeService(db)
        let contact = ContactCard(displayName: "In Folder", folderID: folder.id)
        service.persistContactToDatabase(db, contact: contact)

        let service2 = makeService(db)
        service2.loadContactsFromDatabase(db)

        #expect(service2.contacts[0].folderID == folder.id)
    }

    // MARK: - Empty DB

    @Test("Empty database loads empty contacts array")
    func emptyDatabase() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        service.loadContactsFromDatabase(db)

        #expect(service.contacts.isEmpty)
    }

    // MARK: - Date Precision

    @Test("Date fields survive round-trip with reasonable precision")
    func datePrecision() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let now = Date()
        let birthday = Date(timeIntervalSince1970: 400_000_000.5)
        let contact = ContactCard(
            displayName: "Timed",
            birthday: birthday,
            createdAt: now,
            updatedAt: now
        )
        service.persistContactToDatabase(db, contact: contact)

        let service2 = makeService(db)
        service2.loadContactsFromDatabase(db)

        let loaded = service2.contacts[0]
        #expect(abs(loaded.createdAt.timeIntervalSince(now)) < 0.001)
        #expect(abs(loaded.updatedAt.timeIntervalSince(now)) < 0.001)
        #expect(abs((loaded.birthday ?? .distantPast).timeIntervalSince(birthday)) < 0.001)
    }

    // MARK: - hasAvatar

    @Test("hasAvatar true and false both round-trip")
    func hasAvatarRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let withAvatar = ContactCard(displayName: "HasPic", hasAvatar: true)
        let withoutAvatar = ContactCard(displayName: "NoPic", hasAvatar: false)
        service.persistContactToDatabase(db, contact: withAvatar)
        service.persistContactToDatabase(db, contact: withoutAvatar)

        let service2 = makeService(db)
        service2.loadContactsFromDatabase(db)

        let w = service2.contacts.first { $0.id == withAvatar.id }
        let wo = service2.contacts.first { $0.id == withoutAvatar.id }
        #expect(w?.hasAvatar == true)
        #expect(wo?.hasAvatar == false)
    }

    // MARK: - linkedEntities

    @Test("linkedEntities round-trip through item_links when target contact exists")
    func linkedEntitiesRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let target = ContactCard(displayName: "Target")
        service.persistContactToDatabase(db, contact: target)

        let source = ContactCard(
            displayName: "Source",
            linkedEntities: [LibraryEntityRef(type: .contact, entityID: target.id)]
        )
        service.persistContactToDatabase(db, contact: source)

        let service2 = makeService(db)
        service2.loadContactsFromDatabase(db)

        let loadedSource = service2.contacts.first { $0.id == source.id }
        #expect(loadedSource != nil)
        #expect(loadedSource?.linkedEntities.count == 1)
        #expect(loadedSource?.linkedEntities.first?.entityID == target.id)
        #expect(loadedSource?.linkedEntities.first?.type == .contact)
    }

    @Test("linkedEntities to non-existent target silently dropped")
    func linkedEntitiesDroppedWhenMissingTarget() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let fakeTarget = UUID()
        let contact = ContactCard(
            displayName: "Has dangling link",
            linkedEntities: [LibraryEntityRef(type: .contact, entityID: fakeTarget)]
        )
        service.persistContactToDatabase(db, contact: contact)

        let service2 = makeService(db)
        service2.loadContactsFromDatabase(db)

        let loaded = service2.contacts[0]
        #expect(loaded.linkedEntities.isEmpty)

        let stmt = try db.prepare("SELECT count(*) FROM item_links WHERE source_id = ?;")
        stmt.bind(DatabaseHelpers.encode(contact.id), at: 1)
        try stmt.step()
        #expect(stmt.int(at: 0) == 0)
    }

    @Test("linkedEntities to non-migrated types are silently filtered")
    func linkedEntitiesNonMigratedTypesFiltered() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let contact = ContactCard(
            displayName: "Has session link",
            linkedEntities: [
                LibraryEntityRef(type: .session, entityID: UUID()),
                LibraryEntityRef(type: .externalFile, entityID: UUID())
            ]
        )
        service.persistContactToDatabase(db, contact: contact)

        let stmt = try db.prepare("SELECT count(*) FROM item_links WHERE source_id = ?;")
        stmt.bind(DatabaseHelpers.encode(contact.id), at: 1)
        try stmt.step()
        #expect(stmt.int(at: 0) == 0)

        let service2 = makeService(db)
        service2.loadContactsFromDatabase(db)
        #expect(service2.contacts[0].linkedEntities.isEmpty)
    }

    @Test("Updating linkedEntities replaces old link rows")
    func linkedEntitiesUpdate() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let a = ContactCard(displayName: "A")
        let b = ContactCard(displayName: "B")
        service.persistContactToDatabase(db, contact: a)
        service.persistContactToDatabase(db, contact: b)

        var source = ContactCard(
            displayName: "Source",
            linkedEntities: [LibraryEntityRef(type: .contact, entityID: a.id)]
        )
        service.persistContactToDatabase(db, contact: source)

        source.linkedEntities = [LibraryEntityRef(type: .contact, entityID: b.id)]
        service.persistContactToDatabase(db, contact: source)

        let service2 = makeService(db)
        service2.loadContactsFromDatabase(db)

        let loaded = service2.contacts.first { $0.id == source.id }
        #expect(loaded?.linkedEntities.count == 1)
        #expect(loaded?.linkedEntities.first?.entityID == b.id)
    }

    // MARK: - Filename / relative_path round-trip

    @Test("Uniquified filename round-trips through items.relative_path")
    func uniquifiedFilenameRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        // Simulate the real creation path producing a collision-suffixed filename.
        let contact = ContactCard(displayName: "Jane Doe")
        service._setIndexEntryForTesting(contactID: contact.id, filename: "Jane Doe (2).vcf")

        service.persistContactToDatabase(db, contact: contact)

        // Verify relative_path was persisted to the items table.
        let stmt = try db.prepare("SELECT relative_path FROM items WHERE id = ?;")
        stmt.bind(DatabaseHelpers.encode(contact.id), at: 1)
        try stmt.step()
        let relPath = stmt.optionalString(at: 0)
        #expect(relPath == "Inbox/Contacts/Jane Doe (2).vcf")

        // Reload in a fresh service and verify the filename is recovered EXACTLY.
        let service2 = makeService(db)
        service2.loadContactsFromDatabase(db)

        #expect(service2.contacts.count == 1)
        let recovered = service2._indexFilenameForTesting(contactID: contact.id)
        #expect(recovered == "Jane Doe (2).vcf")
    }

    // MARK: - Special characters in displayName

    @Test("displayName with special characters round-trips unchanged in items.title")
    func displayNameWithSpecialCharacters() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        // Characters that sanitizedFilename would strip, but items.title should preserve.
        let contact = ContactCard(displayName: #"Jane "The Boss" O'Brien / Jr."#)
        service.persistContactToDatabase(db, contact: contact)

        let service2 = makeService(db)
        service2.loadContactsFromDatabase(db)

        let loaded = service2.contacts[0]
        #expect(loaded.displayName == #"Jane "The Boss" O'Brien / Jr."#)
    }

    // MARK: - Empty string fields

    @Test("Contact with empty string fields round-trips correctly")
    func emptyStringFields() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let contact = ContactCard(
            displayName: "Minimal",
            relationshipLabel: "",
            notes: "",
            email: "",
            phone: "",
            address: ""
        )
        service.persistContactToDatabase(db, contact: contact)

        let service2 = makeService(db)
        service2.loadContactsFromDatabase(db)

        let loaded = service2.contacts[0]
        #expect(loaded.displayName == "Minimal")
        #expect(loaded.relationshipLabel == "")
        #expect(loaded.notes == "")
        #expect(loaded.email == "")
        #expect(loaded.phone == "")
        #expect(loaded.address == "")
        #expect(loaded.birthday == nil)
        #expect(loaded.hasAvatar == false)
        #expect(loaded.labelIDs.isEmpty)
        #expect(loaded.linkedEntities.isEmpty)
    }

    // MARK: - Disk write failure gates SQLite persistence

    @Test("writeVCardFile returns false when the target directory does not exist")
    func writeVCardFileReturnsFalseOnDiskError() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        // Target a path whose parent directory does not exist → file write must fail.
        let bogusDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-nonexistent-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("deeper", isDirectory: true)
        let bogusURL = bogusDir.appendingPathComponent("contact.vcf")

        let contact = ContactCard(displayName: "Should not persist")
        let ok = service.writeVCardFile(for: contact, to: bogusURL)
        #expect(ok == false)
        #expect(FileManager.default.fileExists(atPath: bogusURL.path) == false)

        // And a sanity check: writing to a real path returns true.
        let realDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-contact-write-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: realDir) }
        let realURL = realDir.appendingPathComponent("contact.vcf")
        #expect(service.writeVCardFile(for: contact, to: realURL) == true)
        #expect(FileManager.default.fileExists(atPath: realURL.path) == true)
    }

    @Test("hasAvatar flag round-trips through SQLite when mutated via persist path")
    func hasAvatarFlagPersists() throws {
        // Validates that a direct persist call (as saveAvatar/deleteAvatar would do
        // after a successful .vcf write) reflects the hasAvatar change in SQLite.
        // We bypass the filesystem-dependent saveAvatar/deleteAvatar entrypoints here
        // because they depend on the real vault StoragePaths, but the end result is
        // the same: a mutated in-memory contact is written to the DB only after the
        // on-disk write has succeeded.
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        var contact = ContactCard(displayName: "Avatar Tester", hasAvatar: false)
        service.persistContactToDatabase(db, contact: contact)

        // Flip hasAvatar on (simulating a successful saveAvatar disk write)
        contact.hasAvatar = true
        service.persistContactToDatabase(db, contact: contact)

        let stmt1 = try db.prepare("SELECT has_avatar FROM contacts WHERE item_id = ?;")
        stmt1.bind(DatabaseHelpers.encode(contact.id), at: 1)
        try stmt1.step()
        #expect(stmt1.int(at: 0) == 1)

        // Flip hasAvatar off (simulating a deleteAvatar that updates state regardless
        // of whether the JPEG removal actually found a file — by design).
        contact.hasAvatar = false
        service.persistContactToDatabase(db, contact: contact)

        let stmt2 = try db.prepare("SELECT has_avatar FROM contacts WHERE item_id = ?;")
        stmt2.bind(DatabaseHelpers.encode(contact.id), at: 1)
        try stmt2.step()
        #expect(stmt2.int(at: 0) == 0)
    }
}
