import UniformTypeIdentifiers
import XCTest
@testable import Cider

final class CiderDragPayloadTests: XCTestCase {
    @MainActor
    func testDefaultNoteProviderUsesInternalTextPayloadOnly() {
        let note = Note(title: "Test Drag.md", relativePath: "Test Drag.md")

        let provider = NoteDragPayload.makeInternalProvider(for: note)

        XCTAssertFalse(provider.hasItemConformingToTypeIdentifier(NoteDragPayload.markdownTypeIdentifier))
        XCTAssertFalse(provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier))
    }

    func testMultiDragTextPayloadRoundTrips() {
        let items = [
            MultiDragPayload.Item(type: "bookmark", id: UUID()),
            MultiDragPayload.Item(type: "note", id: UUID()),
        ]

        let text = MultiDragPayload.encodeToText(items: items)
        let decoded = text.flatMap(MultiDragPayload.decodeFromText)

        XCTAssertEqual(decoded?.map(\.type), items.map(\.type))
        XCTAssertEqual(decoded?.map(\.id), items.map(\.id))
    }

    func testImageExportNameTreatsJPGAndJPEGAsEquivalent() {
        let fileURL = URL(fileURLWithPath: "/tmp/Cider/Images/asset.jpeg")

        let exportName = BookmarkDragPayload.suggestedImageExportName(
            title: "Your Name In Landsat.jpg",
            fileURL: fileURL
        )

        XCTAssertEqual(exportName, "Your Name In Landsat")
    }

    func testImageExportNamePreservesTitleWithoutExtension() {
        let fileURL = URL(fileURLWithPath: "/tmp/Cider/Images/asset.png")

        let exportName = BookmarkDragPayload.suggestedImageExportName(
            title: "Earthday",
            fileURL: fileURL
        )

        XCTAssertEqual(exportName, "Earthday")
    }

    func testMarkdownExportNameStripsExistingMDExtension() {
        let note = Note(title: "Test Drag.md", relativePath: "Test Drag.md")
        let fileURL = URL(fileURLWithPath: "/tmp/Cider/Notes/Test Drag.md")

        let exportName = NoteDragPayload.markdownExportName(for: note, fileURL: fileURL)

        XCTAssertEqual(exportName, "Test Drag")
    }

    func testMarkdownExportURLRequiresExistingBackingFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("Export Me.md")
        try "# Hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let note = Note(title: "Export Me", relativePath: fileURL.path)

        XCTAssertEqual(NoteDragPayload.markdownExportURL(for: note), fileURL)
        XCTAssertNil(NoteDragPayload.markdownExportURL(for: Note(title: "Missing", relativePath: directory.appendingPathComponent("Missing.md").path)))
    }

    func testBookmarkImageExportURLPrefersOriginalImage() throws {
        let directory = StoragePaths.cachedDirectoryURL(for: .bookmarks)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let originalName = "\(UUID().uuidString).jpg"
        let thumbnailName = "\(UUID().uuidString).png"
        let originalURL = directory.appendingPathComponent(originalName)
        let thumbnailURL = directory.appendingPathComponent(thumbnailName)
        try Data([1]).write(to: originalURL)
        try Data([2]).write(to: thumbnailURL)
        defer {
            try? FileManager.default.removeItem(at: originalURL)
            try? FileManager.default.removeItem(at: thumbnailURL)
        }

        let bookmark = Bookmark(
            title: "Image",
            urlString: "https://example.com",
            thumbnailRelativePath: thumbnailName,
            originalImageRelativePath: originalName
        )

        XCTAssertEqual(BookmarkDragPayload.imageExportURL(for: bookmark), originalURL)
    }
}
