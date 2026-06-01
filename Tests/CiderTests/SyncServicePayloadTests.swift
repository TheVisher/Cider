import Foundation
import Testing
@testable import Cider

@Suite("SyncService Payload Tests")
struct SyncServicePayloadTests {
    private func pulledFolder(
        id: String,
        name: String,
        parentID: String? = nil,
        updatedAt: Double = 1_700_000_000_000,
        deleted: Bool = false,
        purged: Bool = false
    ) -> SyncPulledFolder {
        SyncPulledFolder(
            ciderSyncId: id,
            name: name,
            icon: nil,
            parentSyncId: parentID,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            deleted: deleted,
            deletedAt: deleted ? updatedAt : nil,
            purged: purged,
            purgedAt: purged ? updatedAt : nil
        )
    }

    @Test("pulled folder children wait for resolved parent instead of flattening to root")
    func pulledFolderChildrenRequireResolvedParent() {
        let parentID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        let child = pulledFolder(
            id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            name: "Games",
            parentID: parentID.uppercased()
        )
        let root = pulledFolder(
            id: "cccccccc-cccc-cccc-cccc-cccccccccccc",
            name: "Media"
        )

        let initial = SyncService.partitionPulledFoldersByResolvedParent(
            [child, root],
            availableFolderIDs: []
        )
        #expect(initial.ready.map(\.name) == ["Media"])
        #expect(initial.unresolved.map(\.name) == ["Games"])

        let afterParentExists = SyncService.partitionPulledFoldersByResolvedParent(
            [child],
            availableFolderIDs: [parentID]
        )
        #expect(afterParentExists.ready.map(\.name) == ["Games"])
        #expect(afterParentExists.unresolved.isEmpty)
    }

    @Test("pulled folders with missing parents remain unresolved")
    func pulledFolderMissingParentIsNotRootReady() {
        let child = pulledFolder(
            id: "dddddddd-dddd-dddd-dddd-dddddddddddd",
            name: "Cider",
            parentID: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"
        )

        let partition = SyncService.partitionPulledFoldersByResolvedParent(
            [child],
            availableFolderIDs: []
        )

        #expect(partition.ready.isEmpty)
        #expect(partition.unresolved.map(\.name) == ["Cider"])
    }

    @Test("pulled numeric-suffix folder aliases to canonical sibling")
    func pulledNumericSuffixFolderAliasesToCanonicalSibling() {
        let canonicalID = UUID()
        let folders = [
            VaultFolder(id: canonicalID, relativePath: "Applications"),
            VaultFolder(relativePath: "Food/Restaurants")
        ]

        let decision = SyncService.duplicateQuarantineDecisionForPulledFolder(
            name: "Applications 2",
            parentID: nil,
            folders: folders
        )

        #expect(decision.shouldQuarantine)
        #expect(decision.canonicalFolderID == canonicalID)
        #expect(decision.reason == "numeric_suffix_sibling")
    }

    @Test("pulled root folder aliasing unique nested folder is quarantined")
    func pulledRootFolderAliasesUniqueNestedFolder() {
        let nestedID = UUID()
        let folders = [
            VaultFolder(relativePath: "Personal"),
            VaultFolder(id: nestedID, relativePath: "Personal/Wallpapers")
        ]

        let decision = SyncService.duplicateQuarantineDecisionForPulledFolder(
            name: "Wallpapers",
            parentID: nil,
            folders: folders
        )

        #expect(decision.shouldQuarantine)
        #expect(decision.canonicalFolderID == nestedID)
        #expect(decision.reason == "root_duplicate_of_nested_folder")
    }

    @Test("pulled ambiguous root duplicate is quarantined without alias")
    func pulledAmbiguousRootDuplicateIsQuarantinedWithoutAlias() {
        let folders = [
            VaultFolder(relativePath: "Development/AI"),
            VaultFolder(relativePath: "Tech/AI")
        ]

        let decision = SyncService.duplicateQuarantineDecisionForPulledFolder(
            name: "AI",
            parentID: nil,
            folders: folders
        )

        #expect(decision.shouldQuarantine)
        #expect(decision.canonicalFolderID == nil)
        #expect(decision.reason == "ambiguous_root_duplicate_of_nested_folder")
    }

    @Test("folder tombstones do not wait for unresolved parents")
    func pulledFolderTombstonesBypassMissingParent() {
        let deletedChild = pulledFolder(
            id: "ffffffff-ffff-ffff-ffff-ffffffffffff",
            name: "Games",
            parentID: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
            deleted: true
        )
        let purgedChild = pulledFolder(
            id: "99999999-9999-9999-9999-999999999999",
            name: "Movies",
            parentID: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
            purged: true
        )

        let partition = SyncService.partitionPulledFoldersByResolvedParent(
            [deletedChild, purgedChild],
            availableFolderIDs: []
        )

        #expect(partition.ready.map(\.name) == ["Games", "Movies"])
        #expect(partition.unresolved.isEmpty)
    }

    @Test("SyncService has no active Convex runtime references")
    func syncServiceHasNoActiveConvexRuntimeReferences() throws {
        let source = try String(
            contentsOfFile: "Sources/Cider/Services/SyncService.swift",
            encoding: .utf8
        )

        #expect(!source.contains(["Convex", "Mobile"].joined()))
        #expect(!source.contains(["Convex", "Client"].joined()))
        #expect(!source.contains(["Convex", "Encodable"].joined()))
        #expect(!source.contains(["sync", "authenticate"].joined(separator: ":")))
        #expect(!source.contains("webSyncRuntimeEnabled"))
    }

    @Test("Package manifest no longer links Convex")
    func packageManifestNoLongerLinksConvex() throws {
        let manifest = try String(
            contentsOfFile: "Package.swift",
            encoding: .utf8
        )

        #expect(!manifest.contains(["convex", "swift"].joined(separator: "-")))
        #expect(!manifest.contains(["Convex", "Mobile"].joined()))
    }

    @Test("local mutation sync hooks remain callable no-ops")
    @MainActor
    func localMutationSyncHooksRemainCallableNoOps() {
        let service = SyncService.shared
        let bookmarkID = UUID()
        let folderID = UUID()
        let noteID = UUID()

        service.startIfEnabled()
        service.pushAfterLocalChange()
        service.syncNow()
        service.forceReconcile()
        service.trackDeletion(of: bookmarkID)
        service.cancelDeletion(of: bookmarkID)
        service.trackFolderDeletion(of: folderID)
        service.cancelFolderDeletion(of: folderID)
        service.trackNoteDeletion(of: noteID)
        service.cancelNoteDeletion(of: noteID)

        #expect(service.isSyncing == false)
        #expect(service.lastError == nil)
    }

    @Test("sync-neutral note payload preview includes tags")
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
