import Foundation
import XCTest
@testable import Cider

final class VaultFileMediaPreviewPolicyTests: XCTestCase {
    func testOggAudioUsesExternalFallbackInsteadOfAVKitSwiftUIPreview() {
        let file = VaultFile(
            id: UUID(),
            filename: "discord-voice-note.ogg",
            relativePath: "Journal/Audio/discord-voice-note.ogg",
            fileType: .audio,
            fileSize: 1,
            createdAt: Date(),
            modifiedAt: Date(),
            folderID: nil
        )

        XCTAssertEqual(VaultFileMediaPreviewPolicy.presentation(for: file), .externalAudio)
    }

    func testVideoKeepsInlineAVKitPreview() {
        let file = VaultFile(
            id: UUID(),
            filename: "clip.mov",
            relativePath: "Inbox/Files/clip.mov",
            fileType: .video,
            fileSize: 1,
            createdAt: Date(),
            modifiedAt: Date(),
            folderID: nil
        )

        XCTAssertEqual(VaultFileMediaPreviewPolicy.presentation(for: file), .inlineVideo)
    }

    func testJournalOriginalIsIdentifiedForLibraryClutterFiltering() {
        let file = VaultFile(
            id: UUID(),
            filename: "IMG_8741.jpeg",
            relativePath: "Journal/Photos/IMG_8741.jpeg",
            fileType: .image,
            fileSize: 1,
            createdAt: Date(),
            modifiedAt: Date(),
            folderID: nil,
            title: "Reflection Lake overlook"
        )

        XCTAssertTrue(file.isJournalSourceOriginal)
        XCTAssertEqual(file.displayTitle, "Reflection Lake overlook")
        XCTAssertEqual(file.filename, "IMG_8741.jpeg")
    }
}
