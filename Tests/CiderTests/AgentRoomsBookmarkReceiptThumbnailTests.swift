import AppKit
import Foundation
import Testing
@testable import Cider

@MainActor
struct AgentRoomsBookmarkReceiptThumbnailTests {
    @Test("saved bookmark receipt loads its verified canonical local thumbnail")
    func validCanonicalLocalThumbnail() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let reference = try #require(
            AgentRoomsBookmarkReceiptThumbnail.reference(
                for: fixture.bookmark,
                cacheRoot: fixture.cacheRoot
            )
        )
        let image = await AgentRoomsBookmarkReceiptThumbnail.load(
            reference,
            expectedBookmarkID: fixture.bookmark.id,
            cacheRoot: fixture.cacheRoot
        )

        #expect(image != nil)
        #expect(reference.bookmarkID == fixture.bookmark.id)
        #expect(reference.relativePath == fixture.bookmark.thumbnailRelativePath)
    }

    @Test("saved bookmark receipt falls back when the local thumbnail is missing")
    func missingLocalThumbnail() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let reference = try #require(
            AgentRoomsBookmarkReceiptThumbnail.reference(for: fixture.bookmark, cacheRoot: fixture.cacheRoot)
        )
        try FileManager.default.removeItem(at: fixture.thumbnailURL)

        let image = await AgentRoomsBookmarkReceiptThumbnail.load(
            reference,
            expectedBookmarkID: fixture.bookmark.id,
            cacheRoot: fixture.cacheRoot
        )

        #expect(image == nil)
    }

    @Test("saved bookmark receipt falls back when its local thumbnail fingerprint is stale")
    func staleLocalThumbnail() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let reference = try #require(
            AgentRoomsBookmarkReceiptThumbnail.reference(for: fixture.bookmark, cacheRoot: fixture.cacheRoot)
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: reference.modifiedAt + 60)],
            ofItemAtPath: fixture.thumbnailURL.path
        )

        let image = await AgentRoomsBookmarkReceiptThumbnail.load(
            reference,
            expectedBookmarkID: fixture.bookmark.id,
            cacheRoot: fixture.cacheRoot
        )

        #expect(image == nil)
    }

    @Test("saved bookmark receipt ignores remote-only thumbnail metadata")
    func remoteOnlyThumbnail() {
        let cacheRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cacheRoot) }
        let bookmark = Bookmark(
            title: "Remote only",
            urlString: "https://example.com/remote-only",
            thumbnailRemoteURLString: "https://images.example.com/remote.png"
        )

        #expect(
            AgentRoomsBookmarkReceiptThumbnail.reference(for: bookmark, cacheRoot: cacheRoot) == nil
        )
    }

    @Test("saved bookmark receipt falls back when thumbnail identity mismatches its Open route")
    func mismatchedBookmarkIdentity() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let reference = try #require(
            AgentRoomsBookmarkReceiptThumbnail.reference(for: fixture.bookmark, cacheRoot: fixture.cacheRoot)
        )

        let image = await AgentRoomsBookmarkReceiptThumbnail.load(
            reference,
            expectedBookmarkID: UUID(),
            cacheRoot: fixture.cacheRoot
        )

        #expect(image == nil)
    }

    @Test("saved bookmark receipt falls back when canonical local thumbnail bytes are unreadable")
    func unreadableLocalThumbnail() async throws {
        let fixture = try makeFixture(data: Data("not an image".utf8))
        defer { fixture.cleanup() }
        let reference = try #require(
            AgentRoomsBookmarkReceiptThumbnail.reference(for: fixture.bookmark, cacheRoot: fixture.cacheRoot)
        )

        let image = await AgentRoomsBookmarkReceiptThumbnail.load(
            reference,
            expectedBookmarkID: fixture.bookmark.id,
            cacheRoot: fixture.cacheRoot
        )

        #expect(image == nil)
    }

    @Test("saved bookmark receipt rejects a local thumbnail named for another bookmark")
    func mismatchedCanonicalFilename() throws {
        let cacheRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cacheRoot) }
        let bookmark = Bookmark(
            title: "Wrong file",
            urlString: "https://example.com/wrong-file",
            thumbnailRelativePath: ".thumbnails/\(UUID().uuidString).png"
        )
        let thumbnailURL = cacheRoot.appendingPathComponent(bookmark.thumbnailRelativePath!)
        try FileManager.default.createDirectory(
            at: thumbnailURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try pngData().write(to: thumbnailURL)

        #expect(
            AgentRoomsBookmarkReceiptThumbnail.reference(for: bookmark, cacheRoot: cacheRoot) == nil
        )
    }

    private func makeFixture(data: Data? = nil) throws -> ThumbnailFixture {
        let cacheRoot = temporaryDirectory()
        let bookmarkID = UUID()
        let relativePath = ".thumbnails/\(bookmarkID.uuidString).png"
        let thumbnailURL = cacheRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: thumbnailURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try (data ?? pngData()).write(to: thumbnailURL)
        let modifiedAt = Date(timeIntervalSince1970: 1_805_000_000)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: thumbnailURL.path)
        let bookmark = Bookmark(
            id: bookmarkID,
            title: "Canonical thumbnail",
            urlString: "https://example.com/canonical",
            thumbnailRemoteURLString: "https://images.example.com/canonical.png",
            thumbnailRelativePath: relativePath,
            metadataUpdatedAt: modifiedAt
        )
        return ThumbnailFixture(
            cacheRoot: cacheRoot,
            thumbnailURL: thumbnailURL,
            bookmark: bookmark
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cid-810-\(UUID().uuidString)", isDirectory: true)
    }

    private func pngData() throws -> Data {
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 12,
                pixelsHigh: 8,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}

private struct ThumbnailFixture {
    let cacheRoot: URL
    let thumbnailURL: URL
    let bookmark: Bookmark

    func cleanup() {
        try? FileManager.default.removeItem(at: cacheRoot)
    }
}
