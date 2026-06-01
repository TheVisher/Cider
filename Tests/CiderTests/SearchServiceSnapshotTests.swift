import Foundation
import Testing
@testable import Cider

struct SearchServiceSnapshotTests {
    @Test("snapshot search covers a large mixed vault without shared storage")
    func snapshotSearchCoversLargeMixedVaultWithoutSharedStorage() async {
        let targetFolderID = UUID()
        let labelID = UUID()
        let now = Date()

        let bookmarks: [Bookmark] = (0..<400).map {
            Self.bookmark(index: $0, labelID: labelID, folderID: targetFolderID, now: now)
        }
        let notes: [Note] = (0..<400).map {
            Self.note(index: $0, labelID: labelID, folderID: targetFolderID, now: now)
        }
        let dateCards: [DateCard] = (0..<250).map {
            Self.dateCard(index: $0, labelID: labelID, folderID: targetFolderID, now: now)
        }
        let contacts: [ContactCard] = (0..<250).map {
            Self.contact(index: $0, labelID: labelID, folderID: targetFolderID, now: now)
        }
        let todos: [TodoCard] = (0..<250).map {
            Self.todo(index: $0, labelID: labelID, folderID: targetFolderID, now: now)
        }
        let files: [VaultFile] = (0..<250).map {
            Self.file(index: $0, labelID: labelID, folderID: targetFolderID, now: now)
        }

        let snapshot = SearchService.Snapshot(
            query: "needle",
            bookmarks: bookmarks,
            notes: notes,
            dateCards: dateCards,
            contacts: contacts,
            todos: todos,
            vaultFiles: files,
            folders: [Folder(id: targetFolderID, name: "Needle Folder")],
            labels: [CardLabel(id: labelID, name: "Needle Label")]
        )

        let results = await SearchService.search(snapshot: snapshot)
        let resultTypes: Set<SearchResultType> = Set(results.map(\.type))

        #expect(resultTypes == Set<SearchResultType>([.bookmark, .note, .dateCard, .contact, .todo, .vaultFile]))
    }

    @Test("snapshot search surfaces daily journal notes as journal capture results")
    func snapshotSearchSurfacesDailyJournalNotesAsJournalCaptureResults() async throws {
        let journal = Note(
            title: "Daily Journal 2026-05-28",
            content: "# Daily Journal 2026-05-28\n\n- 08:15 - Morning commute planning insight",
            modifiedAt: Date(timeIntervalSince1970: 1_770_000_000),
            relativePath: "Inbox/Notes/Daily Journal 2026-05-28.md"
        )
        let reference = Note(
            title: "Commute Reference",
            content: "Morning commute planning insight",
            modifiedAt: Date(timeIntervalSince1970: 1_760_000_000),
            relativePath: "Inbox/Notes/Commute Reference.md"
        )

        let snapshot = SearchService.Snapshot(
            query: "planning insight",
            bookmarks: [],
            notes: [journal, reference],
            dateCards: [],
            contacts: [],
            todos: [],
            vaultFiles: [],
            folders: [],
            labels: []
        )

        let results = await SearchService.search(snapshot: snapshot)
        let journalResult = try #require(results.first { $0.id == journal.id })

        #expect(journalResult.type == .note)
        #expect(journalResult.title == "Daily Journal 2026-05-28")
        #expect(journalResult.subtitle == "Journal capture - 2026-05-28")
        #expect(journalResult.snippet?.match.localizedCaseInsensitiveContains("planning") == true)
    }

    private static func bookmark(index: Int, labelID: UUID, folderID: UUID, now: Date) -> Bookmark {
        Bookmark(
            title: index == 123 ? "Needle bookmark" : "Bookmark \(index)",
            urlString: "https://example.com/\(index)",
            updatedAt: now.addingTimeInterval(TimeInterval(index)),
            notes: index == 124 ? "needle bookmark notes" : "",
            labelIDs: index == 123 ? [labelID] : [],
            folderID: index == 123 ? folderID : nil
        )
    }

    private static func note(index: Int, labelID: UUID, folderID: UUID, now: Date) -> Note {
        Note(
            title: index == 223 ? "Needle note" : "Note \(index)",
            content: "",
            modifiedAt: now.addingTimeInterval(TimeInterval(index)),
            labelIDs: index == 223 ? [labelID] : [],
            folderID: index == 223 ? folderID : nil
        )
    }

    private static func dateCard(index: Int, labelID: UUID, folderID: UUID, now: Date) -> DateCard {
        DateCard(
            title: index == 42 ? "Needle event" : "Event \(index)",
            details: "",
            startAt: now,
            labelIDs: index == 42 ? [labelID] : [],
            folderID: index == 42 ? folderID : nil,
            updatedAt: now.addingTimeInterval(TimeInterval(index))
        )
    }

    private static func contact(index: Int, labelID: UUID, folderID: UUID, now: Date) -> ContactCard {
        ContactCard(
            displayName: index == 77 ? "Needle Contact" : "Contact \(index)",
            labelIDs: index == 77 ? [labelID] : [],
            folderID: index == 77 ? folderID : nil,
            updatedAt: now.addingTimeInterval(TimeInterval(index))
        )
    }

    private static func todo(index: Int, labelID: UUID, folderID: UUID, now: Date) -> TodoCard {
        TodoCard(
            title: index == 88 ? "Needle todo" : "Todo \(index)",
            labelIDs: index == 88 ? [labelID] : [],
            folderID: index == 88 ? folderID : nil,
            updatedAt: now.addingTimeInterval(TimeInterval(index))
        )
    }

    private static func file(index: Int, labelID: UUID, folderID: UUID, now: Date) -> VaultFile {
        VaultFile(
            id: UUID(),
            filename: index == 99 ? "needle-file.pdf" : "file-\(index).pdf",
            relativePath: "Files/file-\(index).pdf",
            fileType: .pdf,
            fileSize: 1,
            createdAt: now,
            modifiedAt: now.addingTimeInterval(TimeInterval(index)),
            folderID: index == 99 ? folderID : nil,
            labelIDs: index == 99 ? [labelID] : []
        )
    }
}
