import Foundation
import Testing
@testable import Cider

@Suite("Bookmark & Folder Model Tests")
struct BookmarkModelTests {

    // MARK: - Bookmark Backward Compat

    @Test("Bookmark decodes with only required fields")
    func bookmarkMinimalJSON() throws {
        let json = """
        {
            "id": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
            "title": "Test",
            "urlString": "https://example.com",
            "createdAt": 1700000000,
            "updatedAt": 1700000000,
            "notes": "",
            "tags": []
        }
        """
        let data = json.data(using: .utf8)!
        let bookmark = try JSONDecoder().decode(Bookmark.self, from: data)

        #expect(bookmark.title == "Test")
        #expect(bookmark.urlString == "https://example.com")
        #expect(bookmark.notes == "")
        #expect(bookmark.tags.isEmpty)
        #expect(bookmark.labelIDs.isEmpty)
        #expect(bookmark.dismissedLabelIDs.isEmpty)
        #expect(bookmark.folderID == nil)
        #expect(bookmark.thumbnailRelativePath == nil)
        #expect(bookmark.aiSummary == nil)
        #expect(bookmark.ocrText == nil)
        #expect(bookmark.dominantColors == nil)
        #expect(bookmark.mediaType == nil)
        #expect(bookmark.carouselImagePaths == nil)
        #expect(bookmark.readerUnavailable == nil)
        #expect(bookmark.preferredHeroMode == nil)
        #expect(bookmark.relativePath == nil)
    }

    @Test("Bookmark round-trip preserves all fields")
    func bookmarkRoundTrip() throws {
        let folderID = UUID()
        let bookmark = Bookmark(
            title: "Full Test",
            urlString: "https://example.com/page",
            notes: "Some notes",
            tags: ["swift", "ios"],
            labelIDs: [UUID()],
            dismissedLabelIDs: [UUID()],
            folderID: folderID,
            thumbnailRemoteURLString: "https://cdn.example.com/img.jpg",
            thumbnailRelativePath: ".thumbnails/abc.png",
            originalImageRelativePath: ".originals/abc.jpg",
            aiSummary: "A test page.",
            ocrText: "OCR content",
            dominantColors: ["#FF0000", "#00FF00"],
            mediaType: .gif,
            carouselImagePaths: [".originals/carousel1.jpg"],
            readerUnavailable: true,
            preferredHeroMode: "web",
            relativePath: "Inbox/Bookmarks/Full Test.webloc"
        )

        let data = try JSONEncoder().encode(bookmark)
        let decoded = try JSONDecoder().decode(Bookmark.self, from: data)

        #expect(decoded.id == bookmark.id)
        #expect(decoded.title == "Full Test")
        #expect(decoded.urlString == "https://example.com/page")
        #expect(decoded.notes == "Some notes")
        #expect(decoded.tags == ["swift", "ios"])
        #expect(decoded.labelIDs.count == 1)
        #expect(decoded.dismissedLabelIDs.count == 1)
        #expect(decoded.folderID == folderID)
        #expect(decoded.thumbnailRemoteURLString == "https://cdn.example.com/img.jpg")
        #expect(decoded.thumbnailRelativePath == ".thumbnails/abc.png")
        #expect(decoded.originalImageRelativePath == ".originals/abc.jpg")
        #expect(decoded.aiSummary == "A test page.")
        #expect(decoded.ocrText == "OCR content")
        #expect(decoded.dominantColors == ["#FF0000", "#00FF00"])
        #expect(decoded.mediaType == .gif)
        #expect(decoded.carouselImagePaths == [".originals/carousel1.jpg"])
        #expect(decoded.readerUnavailable == true)
        #expect(decoded.preferredHeroMode == "web")
        #expect(decoded.relativePath == "Inbox/Bookmarks/Full Test.webloc")
    }

    @Test("Bookmark.hasURL returns true for http/https URLs")
    func hasURLValid() {
        let bookmark = Bookmark(title: "Test", urlString: "https://example.com")
        #expect(bookmark.hasURL == true)
    }

    @Test("Bookmark.hasURL returns false for empty string")
    func hasURLEmpty() {
        let bookmark = Bookmark(title: "Test", urlString: "")
        #expect(bookmark.hasURL == false)
    }

    @Test("Bookmark.hostDisplay strips www prefix")
    func hostDisplayStripsWWW() {
        let bookmark = Bookmark(title: "Test", urlString: "https://www.example.com/page")
        #expect(bookmark.hostDisplay == "example.com")
    }

    @Test("Bookmark.hostDisplay returns host without www")
    func hostDisplayBare() {
        let bookmark = Bookmark(title: "Test", urlString: "https://github.com/repo")
        #expect(bookmark.hostDisplay == "github.com")
    }

    @Test("Bookmark.hostDisplay returns 'Unknown Source' for invalid URL")
    func hostDisplayInvalid() {
        let bookmark = Bookmark(title: "Test", urlString: "")
        #expect(bookmark.hostDisplay == "Unknown Source")
    }

    // MARK: - Folder Model

    @Test("Folder round-trip preserves all fields")
    func folderRoundTrip() throws {
        let parentID = UUID()
        let folder = Folder(
            name: "Test Folder",
            parentID: parentID,
            coverImagePath: ".folder-covers/abc.jpg",
            coverImageOffsetY: 0.3,
            icon: "star"
        )

        let data = try JSONEncoder().encode(folder)
        let decoded = try JSONDecoder().decode(Folder.self, from: data)

        #expect(decoded.id == folder.id)
        #expect(decoded.name == "Test Folder")
        #expect(decoded.parentID == parentID)
        #expect(decoded.coverImagePath == ".folder-covers/abc.jpg")
        #expect(decoded.coverImageOffsetY == 0.3)
        #expect(decoded.icon == "star")
    }

    @Test("Folder decodes without optional fields")
    func folderMinimal() throws {
        let json = """
        {
            "id": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
            "name": "Simple",
            "createdAt": 1700000000,
            "updatedAt": 1700000000
        }
        """
        let data = json.data(using: .utf8)!
        let folder = try JSONDecoder().decode(Folder.self, from: data)

        #expect(folder.name == "Simple")
        #expect(folder.parentID == nil)
        #expect(folder.coverImagePath == nil)
        #expect(folder.icon == nil)
    }

    @Test("Folder.iconIsEmoji detects emoji")
    func folderIconIsEmoji() {
        let emoji = Folder(name: "Test", icon: "🎨")
        let symbol = Folder(name: "Test", icon: "star")
        let none = Folder(name: "Test", icon: nil)

        #expect(emoji.iconIsEmoji == true)
        #expect(symbol.iconIsEmoji == false)
        #expect(none.iconIsEmoji == false)
    }

    // MARK: - BookmarkMediaType

    @Test("BookmarkMediaType round-trips correctly")
    func mediaTypeRoundTrip() throws {
        for mediaType in [BookmarkMediaType.image, .gif, .video] {
            let data = try JSONEncoder().encode(mediaType)
            let decoded = try JSONDecoder().decode(BookmarkMediaType.self, from: data)
            #expect(decoded == mediaType)
        }
    }
}
