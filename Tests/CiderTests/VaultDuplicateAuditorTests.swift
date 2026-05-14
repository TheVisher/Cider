import Foundation
import Testing
@testable import Cider

@Suite("VaultDuplicateAuditor Tests")
struct VaultDuplicateAuditorTests {
    @Test("notes with numeric suffix titles and identical content are exact duplicates")
    func notesWithSuffixTitlesAndSameContentAreDuplicates() {
        let notes = [
            Note(
                id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                title: "Games Library",
                content: "same body",
                relativePath: "Media/Games/Games Library.md"
            ),
            Note(
                id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
                title: "Games Library 2",
                content: "same body",
                relativePath: "Games/Games Library 2.md"
            ),
            Note(
                id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
                title: "Different",
                content: "different body",
                relativePath: "Different.md"
            ),
        ]

        let findings = VaultDuplicateAuditor.findDuplicateNotes(notes)

        #expect(findings.count == 1)
        #expect(findings.first?.entityType == .note)
        #expect(findings.first?.kind == .exactContent)
        #expect(findings.first?.confidence == .exact)
        #expect(findings.first?.items.map(\.title).sorted() == ["Games Library", "Games Library 2"])
    }

    @Test("bookmarks with tracking differences share a canonical URL")
    func bookmarksWithTrackingDifferencesShareCanonicalURL() {
        let bookmarks = [
            Bookmark(
                id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                title: "Example",
                urlString: "https://example.com/path/?utm_source=newsletter&x=1#section"
            ),
            Bookmark(
                id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
                title: "Example 2",
                urlString: "https://example.com/path?x=1"
            ),
        ]

        let findings = VaultDuplicateAuditor.findDuplicateBookmarks(bookmarks)

        #expect(findings.count == 1)
        #expect(findings.first?.entityType == .bookmark)
        #expect(findings.first?.kind == .canonicalURL)
        #expect(findings.first?.confidence == .exact)
    }

    @Test("contacts with same email or phone are exact duplicates")
    func contactsWithSameEmailOrPhoneAreDuplicates() {
        let contacts = [
            ContactCard(
                id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                displayName: "Baine Holum",
                email: "Baine@Example.com"
            ),
            ContactCard(
                id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
                displayName: "Baine Holum 2",
                email: "baine@example.com"
            ),
            ContactCard(
                id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
                displayName: "Other",
                phone: "+1 (555) 123-4567"
            ),
            ContactCard(
                id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
                displayName: "Other 2",
                phone: "5551234567"
            ),
        ]

        let findings = VaultDuplicateAuditor.findDuplicateContacts(contacts)

        #expect(findings.count == 2)
        #expect(Set(findings.map(\.kind)) == [.email, .phone])
        #expect(findings.allSatisfy { $0.entityType == .contact && $0.confidence == .exact })
    }

    @Test("VaultDoctor allows canonical root Media to coexist with nested Media topic folders")
    func rootMediaNestedMediaCollisionIsAllowlisted() {
        #expect(VaultDoctor.isAllowedRootNestedFolderNameCollision(
            rootRelativePath: "Media",
            nestedRelativePaths: ["Spaces/Media"]
        ))
        #expect(!VaultDoctor.isAllowedRootNestedFolderNameCollision(
            rootRelativePath: "Games",
            nestedRelativePaths: ["Media/Games"]
        ))
    }

    @Test("VaultDoctor detects repeated numeric suffix folder names")
    func repeatedNumericSuffixFolderNamesAreDuplicateCandidates() {
        #expect(VaultDoctor.hasNumericSuffix("Applications 2"))
        #expect(VaultDoctor.hasNumericSuffix("Applications 2 2"))
        #expect(!VaultDoctor.hasNumericSuffix("Applications"))
    }

    @Test("VaultDoctor detects repeated numeric suffix folder groups without a canonical sibling")
    func repeatedNumericSuffixFolderGroupsWithoutCanonicalAreDuplicateCandidates() {
        #expect(VaultDoctor.shouldFlagNumericSuffixFolderGroup(["Applications 2", "Applications 2 2"]))
        #expect(VaultDoctor.shouldFlagNumericSuffixFolderGroup(["Media 2", "Media 3"]))
        #expect(VaultDoctor.shouldFlagNumericSuffixFolderGroup(["Media", "Media 2"]))
        #expect(!VaultDoctor.shouldFlagNumericSuffixFolderGroup(["Applications 2"]))
        #expect(!VaultDoctor.shouldFlagNumericSuffixFolderGroup(["Applications", "Utilities"]))
    }

    @Test("empty notes with numeric suffix titles are duplicate candidates")
    func emptyNotesWithSuffixTitlesAreDuplicates() {
        let notes = [
            Note(
                id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                title: "CodexNote-1775948805",
                content: "",
                relativePath: "Inbox/Notes/CodexNote-1775948805.md"
            ),
            Note(
                id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
                title: "CodexNote-1775948805 2",
                content: "",
                relativePath: "Inbox/Notes/CodexNote-1775948805 2.md"
            ),
        ]

        let findings = VaultDuplicateAuditor.findDuplicateNotes(notes)

        #expect(findings.count == 1)
        #expect(findings.first?.entityType == .note)
        #expect(findings.first?.kind == .exactContent)
    }

    @Test("normalized titles strip numeric suffixes")
    func normalizedTitlesStripNumericSuffixes() {
        #expect(VaultDuplicateAuditor.normalizedDuplicateName("Games Library 3.md") == "games library")
        #expect(VaultDuplicateAuditor.normalizedDuplicateName("Games Library 2 2.md") == "games library")
        #expect(VaultDuplicateAuditor.normalizedDuplicateName("Cider 2") == "cider")
    }
}
