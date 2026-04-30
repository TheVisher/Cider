import Foundation
import Testing
@testable import Cider

@Suite("Contact Custom Fields Tests")
@MainActor
struct ContactCustomFieldsTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-contact-fields-\(UUID().uuidString).db")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
    }

    private func makeTestDB() throws -> (CiderDatabase, URL) {
        let url = makeTempDBURL()
        let db = CiderDatabase()
        try db.open(at: url)
        return (db, url)
    }

    @Test("Contact custom fields round-trip through SQLite")
    func customFieldsRoundTripThroughSQLite() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = ContactStorage(database: db)
        let fields = [
            ContactCustomField(section: "Favorites", label: "Color", value: "Black", kind: .text, isPinned: true),
            ContactCustomField(section: "Sizes", label: "Shirt", value: "Youth M", kind: .text, isPinned: false)
        ]
        let contact = ContactCard(displayName: "Baine", customFields: fields)

        service.persistContactToDatabase(db, contact: contact)

        let loadedService = ContactStorage(database: db)
        loadedService.loadContactsFromDatabase(db)
        let loaded = try #require(loadedService.contacts.first)

        #expect(loaded.customFields == fields)
    }

    @Test("Contact custom fields round-trip through vCard")
    func customFieldsRoundTripThroughVCard() throws {
        let fields = [
            ContactCustomField(section: "Favorites", label: "Color", value: "Black", kind: .text, isPinned: true)
        ]
        let contact = ContactCard(displayName: "Baine", customFields: fields)

        let parsed = try #require(VCardSerializer.parse(VCardSerializer.serialize(contact)))

        #expect(parsed.customFields == fields)
    }

    @Test("Profile patch replaces custom fields when fields are supplied")
    func profilePatchReplacesFields() throws {
        let fieldID = UUID()
        let original = ContactCard(
            displayName: "Baine",
            customFields: [
                ContactCustomField(section: "Favorites", label: "Color", value: "Blue")
            ]
        )
        let patch = try ContactProfileJSON.decodePatch(from: """
        {
          "fields": [
            { "id": "\(fieldID.uuidString)", "section": "Favorites", "label": "Color", "value": "Black", "kind": "text", "pinned": true }
          ]
        }
        """)

        let updated = try patch.apply(to: original)

        #expect(updated.customFields == [
            ContactCustomField(id: fieldID, section: "Favorites", label: "Color", value: "Black", kind: .text, isPinned: true)
        ])
    }

    @Test("Profile dictionary includes custom fields")
    func profileDictionaryIncludesFields() {
        let fieldID = UUID()
        let contact = ContactCard(
            displayName: "Baine",
            customFields: [
                ContactCustomField(
                    id: fieldID,
                    section: "Favorites",
                    label: "Color",
                    value: "Black",
                    kind: .text,
                    isPinned: true
                )
            ]
        )

        let dict = ContactProfileJSON.profileDictionary(for: contact)
        let fields = dict["fields"] as? [[String: Any]]

        #expect(fields?.count == 1)
        #expect(fields?.first?["id"] as? String == fieldID.uuidString)
        #expect(fields?.first?["section"] as? String == "Favorites")
        #expect(fields?.first?["label"] as? String == "Color")
        #expect(fields?.first?["value"] as? String == "Black")
        #expect(fields?.first?["kind"] as? String == "text")
        #expect(fields?.first?["pinned"] as? Bool == true)
    }
}
