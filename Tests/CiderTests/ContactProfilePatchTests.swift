import Foundation
import Testing
@testable import Cider

struct ContactProfilePatchTests {
    @Test("profile patch updates provided fields and preserves omitted fields")
    func patchUpdatesProvidedFieldsOnly() throws {
        let original = ContactCard(
            displayName: "Baine",
            relationshipLabel: "Son",
            notes: "Old notes",
            email: "old@example.com",
            phone: "555-0000",
            address: "Old address"
        )
        let patch = try ContactProfileJSON.decodePatch(from: """
        {
          "displayName": "Baine Holum",
          "phone": "555-1234",
          "notes": "Color: Black"
        }
        """)

        let updated = try patch.apply(to: original)

        #expect(updated.displayName == "Baine Holum")
        #expect(updated.phone == "555-1234")
        #expect(updated.notes == "Color: Black")
        #expect(updated.relationshipLabel == "Son")
        #expect(updated.email == "old@example.com")
        #expect(updated.address == "Old address")
    }

    @Test("profile patch null clears optional and string fields")
    func patchNullClearsFields() throws {
        let original = ContactCard(
            displayName: "Baine",
            relationshipLabel: "Son",
            birthday: Date(timeIntervalSince1970: 1_465_603_200),
            notes: "Existing",
            email: "baine@example.com",
            phone: "555-1234",
            address: "Home",
            linkedEntities: [LibraryEntityRef(type: .bookmark, entityID: UUID())]
        )
        let patch = try ContactProfileJSON.decodePatch(from: """
        {
          "relationship": null,
          "birthday": null,
          "email": null,
          "phone": null,
          "address": null,
          "notes": null,
          "linkedEntities": null
        }
        """)

        let updated = try patch.apply(to: original)

        #expect(updated.relationshipLabel == "")
        #expect(updated.birthday == nil)
        #expect(updated.email == "")
        #expect(updated.phone == "")
        #expect(updated.address == "")
        #expect(updated.notes == "")
        #expect(updated.linkedEntities.isEmpty)
    }

    @Test("profile patch parses birthday and related entity refs")
    func patchParsesBirthdayAndRelatedRefs() throws {
        let originalTimeZone = NSTimeZone.default
        let pacific = try #require(TimeZone(identifier: "America/Los_Angeles"))
        NSTimeZone.default = pacific
        defer { NSTimeZone.default = originalTimeZone }

        let bookmarkID = UUID()
        let noteID = UUID()
        let patch = try ContactProfileJSON.decodePatch(from: """
        {
          "birthday": "2016-06-15",
          "linkedEntities": [
            { "type": "bookmark", "id": "\(bookmarkID.uuidString)" },
            { "type": "note", "entityID": "\(noteID.uuidString)" }
          ]
        }
        """)

        let updated = try patch.apply(to: ContactCard(displayName: "Baine"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        let birthdayComponents = Calendar(identifier: .gregorian).dateComponents(
            in: pacific,
            from: try #require(updated.birthday)
        )

        #expect(birthdayComponents.year == 2016)
        #expect(birthdayComponents.month == 6)
        #expect(birthdayComponents.day == 15)
        #expect(calendar.component(.day, from: LibraryItemEditor.nextBirthdayOccurrence(
            from: try #require(updated.birthday),
            now: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 9)))
        )) == 15)
        #expect(updated.linkedEntities == [
            LibraryEntityRef(type: .bookmark, entityID: bookmarkID),
            LibraryEntityRef(type: .note, entityID: noteID)
        ])
    }

    @Test("profile dictionary exposes full agent writable contact surface")
    func profileDictionaryExposesFullSurface() throws {
        let id = UUID()
        let birthday = try #require(ContactProfileJSON.parseBirthday("2016-06-15"))
        let contact = ContactCard(
            id: id,
            displayName: "Baine Holum",
            relationshipLabel: "Son",
            birthday: birthday,
            notes: "Color: Black",
            email: "baine@example.com",
            phone: "555-1234",
            address: "Home",
            linkedEntities: [LibraryEntityRef(type: .bookmark, entityID: UUID())]
        )

        let dict = ContactProfileJSON.profileDictionary(for: contact)

        #expect(dict["id"] as? String == id.uuidString)
        #expect(dict["displayName"] as? String == "Baine Holum")
        #expect(dict["relationship"] as? String == "Son")
        #expect(dict["birthday"] as? String == "2016-06-15")
        #expect(dict["notes"] as? String == "Color: Black")
        #expect(dict["email"] as? String == "baine@example.com")
        #expect(dict["phone"] as? String == "555-1234")
        #expect(dict["address"] as? String == "Home")
        #expect((dict["linkedEntities"] as? [[String: String]])?.count == 1)
    }

    @Test("profile patch rejects invalid birthday")
    func profilePatchRejectsInvalidBirthday() throws {
        let patch = try ContactProfileJSON.decodePatch(from: #"{"birthday":"June 15"}"#)

        #expect(throws: ContactProfilePatchError.self) {
            _ = try patch.apply(to: ContactCard(displayName: "Baine"))
        }
    }
}
