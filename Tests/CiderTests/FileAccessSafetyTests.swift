import Foundation
import XCTest
@testable import Cider

final class FileAccessSafetyTests: XCTestCase {
    override func tearDown() {
        StoragePaths.vaultOverride = nil
        StoragePaths.invalidateCachedDirectory()
        super.tearDown()
    }

    func testNoteImageURLsRejectAbsoluteFilesOutsideNoteDirectory() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        StoragePaths.vaultOverride = root
        StoragePaths.invalidateCachedDirectory()

        let noteDir = root.appendingPathComponent("Inbox/Notes", isDirectory: true)
        let attachmentDir = noteDir.appendingPathComponent(".attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: attachmentDir, withIntermediateDirectories: true)

        let attachment = attachmentDir.appendingPathComponent("safe.png")
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-secret.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: attachment)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }

        let note = Note(title: "Test", relativePath: "Inbox/Notes/Test.md")
        let markdown = """
        ![safe](./.attachments/safe.png)
        ![outside](\(outside.path))
        ![outside-file](\(outside.absoluteString))
        """

        let urls = note.imageURLs(from: markdown)
        XCTAssertEqual(urls, [attachment.standardizedFileURL])
        XCTAssertEqual(note.attachmentImageURLs(from: markdown), [attachment.standardizedFileURL])
    }

    func testCiderVaultSchemeAllowsOnlyVaultImages() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        StoragePaths.vaultOverride = root
        StoragePaths.invalidateCachedDirectory()

        let attachmentDir = root.appendingPathComponent("Inbox/Notes/.attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: attachmentDir, withIntermediateDirectories: true)
        let allowed = attachmentDir.appendingPathComponent("image.png")
        let rejected = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-image.png")
        let rejectedText = attachmentDir.appendingPathComponent("secret.txt")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: allowed)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: rejected)
        try "secret".write(to: rejectedText, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rejected) }

        XCTAssertEqual(CiderVaultSchemeHandler.allowedFileURL(for: schemeURL(for: allowed))?.path, allowed.path)
        XCTAssertNil(CiderVaultSchemeHandler.allowedFileURL(for: schemeURL(for: rejected)))
        XCTAssertNil(CiderVaultSchemeHandler.allowedFileURL(for: schemeURL(for: rejectedText)))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func schemeURL(for fileURL: URL) -> URL {
        let encoded = fileURL.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileURL.path
        return URL(string: "cider-vault://\(encoded)")!
    }
}
