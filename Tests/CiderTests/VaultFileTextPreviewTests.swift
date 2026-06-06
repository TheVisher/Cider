import Foundation
import XCTest
@testable import Cider

final class VaultFileTextPreviewTests: XCTestCase {
    func testPlainTextVaultFilesUseInlineTextPreview() throws {
        let file = VaultFile(
            id: UUID(),
            filename: "redacted_recovery_codes_capture_test.txt",
            relativePath: "Inbox/Files/redacted_recovery_codes_capture_test.txt",
            fileType: .document,
            fileSize: 806,
            createdAt: Date(),
            modifiedAt: Date(),
            folderID: nil
        )

        XCTAssertTrue(VaultFileTextPreview.canPreview(file))
    }

    func testInlineTextPreviewReadsUtf8Content() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-text-preview-\(UUID().uuidString).txt")
        try "Generated codes\n---------------\nDistinctive smoke-test phrase".write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try VaultFileTextPreview.loadText(from: url)

        XCTAssertTrue(text.contains("Generated codes"))
        XCTAssertTrue(text.contains("Distinctive smoke-test phrase"))
    }
}
