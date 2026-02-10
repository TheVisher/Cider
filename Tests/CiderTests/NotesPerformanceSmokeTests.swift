import Foundation
import Testing
@testable import Cider

@Suite("Notes Performance Smoke Tests")
struct NotesPerformanceSmokeTests {
    @Test("Markdown path codec handles large notes within smoke threshold")
    func markdownPathCodecLargeDocumentSmoke() {
        let notesDirectory = URL(fileURLWithPath: "/Users/test/Documents/Cider Notes")
        let paragraph = "This is a long paragraph used for smoke performance checks in notes.\n"

        var markdown = ""
        markdown.reserveCapacity(1_200_000)
        for index in 0..<8_000 {
            markdown += paragraph
            if index.isMultiple(of: 120) {
                markdown += "![img\(index)](./.attachments/img-\(index).png)\n"
            }
        }

        let start = Date()
        let editorVersion = NotesMarkdownPathCodec.markdownForEditor(
            markdown,
            notesDirectoryURL: notesDirectory
        )
        let persisted = NotesMarkdownPathCodec.markdownForPersistence(
            editorVersion,
            notesDirectoryURL: notesDirectory
        )
        let elapsed = Date().timeIntervalSince(start)

        #expect(editorVersion.count > markdown.count / 2)
        #expect(persisted.contains("./.attachments/"))
        #expect(elapsed < 5.0)
    }
}
