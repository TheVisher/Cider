import Foundation
import Testing
@testable import Cider

@Suite("SyncService Payload Tests")
struct SyncServicePayloadTests {
    @Test("note payload includes tags for web sync")
    @MainActor
    func notePayloadIncludesTags() {
        let note = Note(
            id: UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!,
            title: "Tagged Note",
            content: "body",
            tags: ["swift", "sync"]
        )

        let payload = SyncService.notePayloadPreviewForTesting(from: note)

        #expect(payload.ciderSyncId == "a1b2c3d4-e5f6-7890-abcd-ef1234567890")
        #expect(payload.tags == ["swift", "sync"])
    }

    @Test("pulled bookmark decodes purge tombstone")
    func pulledBookmarkDecodesPurgeState() throws {
        let data = """
        {
            "ciderSyncId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
            "title": "Deleted",
            "urlString": "https://example.com",
            "createdAt": 1700000000000,
            "updatedAt": 1700000001000,
            "deleted": true,
            "deletedAt": 1700000001000,
            "purged": true,
            "purgedAt": 1700000002000
        }
        """.data(using: .utf8)!

        let bookmark = try JSONDecoder().decode(SyncPulledBookmark.self, from: data)

        #expect(bookmark.purged == true)
        #expect(bookmark.purgedAt == 1700000002000)
    }

    @Test("pulled note decodes tags and purge tombstone")
    func pulledNoteDecodesTagsAndPurgeState() throws {
        let data = """
        {
            "ciderSyncId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
            "title": "Deleted Note",
            "content": "body",
            "tags": ["swift", "sync"],
            "createdAt": 1700000000000,
            "updatedAt": 1700000001000,
            "deleted": true,
            "deletedAt": 1700000001000,
            "purged": true,
            "purgedAt": 1700000002000
        }
        """.data(using: .utf8)!

        let note = try JSONDecoder().decode(SyncPulledNote.self, from: data)

        #expect(note.tags == ["swift", "sync"])
        #expect(note.purged == true)
        #expect(note.purgedAt == 1700000002000)
    }
}
