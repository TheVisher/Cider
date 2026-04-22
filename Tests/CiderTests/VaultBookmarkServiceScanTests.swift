import Foundation
import Testing
@testable import Cider

struct VaultBookmarkServiceScanTests {
    @Test("deduplicate scanned bookmarks prefers filed bookmark over inbox duplicate")
    func deduplicateScannedBookmarksPrefersFiledBookmark() {
        let duplicateURL = "https://example.com/article"
        let inboxBookmark = Bookmark(
            title: "Inbox Copy",
            urlString: duplicateURL,
            folderID: nil,
            relativePath: "Inbox/Bookmarks/Inbox Copy.webloc"
        )
        let filedBookmark = Bookmark(
            title: "Filed Copy",
            urlString: duplicateURL,
            folderID: UUID(),
            relativePath: "Research/Filed Copy.webloc"
        )

        let result = VaultBookmarkService.deduplicateScannedBookmarks([inboxBookmark, filedBookmark])

        #expect(result.count == 1)
        #expect(result.first?.relativePath == "Research/Filed Copy.webloc")
    }

    @Test("deduplicate scanned bookmarks is stable regardless of duplicate order")
    func deduplicateScannedBookmarksIsStableRegardlessOfOrder() {
        let duplicateURL = "https://example.com/article"
        let firstFolder = Bookmark(
            title: "Zeta Copy",
            urlString: duplicateURL,
            folderID: UUID(),
            relativePath: "Zeta/Zeta Copy.webloc"
        )
        let secondFolder = Bookmark(
            title: "Alpha Copy",
            urlString: duplicateURL,
            folderID: UUID(),
            relativePath: "Alpha/Alpha Copy.webloc"
        )

        let forward = VaultBookmarkService.deduplicateScannedBookmarks([firstFolder, secondFolder])
        let reverse = VaultBookmarkService.deduplicateScannedBookmarks([secondFolder, firstFolder])

        #expect(forward.count == 1)
        #expect(reverse.count == 1)
        #expect(forward.first?.relativePath == "Alpha/Alpha Copy.webloc")
        #expect(reverse.first?.relativePath == "Alpha/Alpha Copy.webloc")
    }
}
