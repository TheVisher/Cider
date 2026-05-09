import XCTest
@testable import Cider

final class LibraryItemInboxTests: XCTestCase {
    func testPathBackedItemsMustLiveUnderInboxToBeInboxItems() {
        let curatedBookmark = Bookmark(
            title: "Curated",
            urlString: "https://example.com",
            relativePath: "Tech/Curated.webloc"
        )
        let inboxBookmark = Bookmark(
            title: "Inbox",
            urlString: "https://example.com/inbox",
            relativePath: "Inbox/Bookmarks/Inbox.webloc"
        )
        let rootFile = VaultFile(
            id: UUID(),
            filename: "screenshot.png",
            relativePath: "Screenshots/screenshot.png",
            fileType: .image,
            fileSize: 10,
            createdAt: Date(),
            modifiedAt: Date(),
            folderID: nil
        )
        let inboxFile = VaultFile(
            id: UUID(),
            filename: "capture.png",
            relativePath: "Inbox/Images/capture.png",
            fileType: .image,
            fileSize: 10,
            createdAt: Date(),
            modifiedAt: Date(),
            folderID: nil
        )

        XCTAssertFalse(LibraryItemV2.bookmark(curatedBookmark).isInboxItem)
        XCTAssertTrue(LibraryItemV2.bookmark(inboxBookmark).isInboxItem)
        XCTAssertFalse(LibraryItemV2.vaultFile(rootFile).isInboxItem)
        XCTAssertTrue(LibraryItemV2.vaultFile(inboxFile).isInboxItem)
    }

    func testPathlessCardsUseFolderAssignmentForInboxMembership() {
        let folderID = UUID()

        XCTAssertTrue(LibraryItemV2.todo(TodoCard(title: "Unfiled")).isInboxItem)
        XCTAssertFalse(LibraryItemV2.todo(TodoCard(title: "Filed", folderID: folderID)).isInboxItem)
        XCTAssertTrue(LibraryItemV2.contact(ContactCard(displayName: "Unfiled")).isInboxItem)
        XCTAssertFalse(LibraryItemV2.contact(ContactCard(displayName: "Filed", folderID: folderID)).isInboxItem)
    }
}
