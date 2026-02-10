import Foundation
import Testing
@testable import Cider

@Suite("Notes Markdown Path Codec Tests")
struct NotesMarkdownPathCodecTests {
    private let notesDirectory = URL(fileURLWithPath: "/Users/test/Library/Mobile Documents/com~apple~CloudDocs/Cider Notes")

    @Test("Editor conversion resolves relative attachment paths to absolute")
    func editorConversionResolvesRelativeAttachmentPaths() {
        let markdown = """
        ![image](./.attachments/a-file.png)
        <img src="./.attachments/b-file.png" />
        """

        let converted = NotesMarkdownPathCodec.markdownForEditor(
            markdown,
            notesDirectoryURL: notesDirectory
        )

        #expect(converted.contains("Cider%20Notes/.attachments/a-file.png"))
        #expect(converted.contains("Cider%20Notes/.attachments/b-file.png"))
        #expect(!converted.contains("(./.attachments/"))
    }

    @Test("Persistence conversion restores absolute and file paths to relative")
    func persistenceConversionRestoresKnownAbsolutePathsToRelative() {
        let rawPrefix = notesDirectory.path
        let encodedPrefix = notesDirectory.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rawPrefix

        let markdown = """
        ![raw](\(rawPrefix)/.attachments/raw.png)
        ![encoded](\(encodedPrefix)/.attachments/encoded.png)
        ![fileraw](file://\(rawPrefix)/.attachments/file-raw.png)
        <img src="file://\(encodedPrefix)/.attachments/file-encoded.png" />
        """

        let converted = NotesMarkdownPathCodec.markdownForPersistence(
            markdown,
            notesDirectoryURL: notesDirectory
        )

        #expect(converted.contains("![raw](./.attachments/raw.png)"))
        #expect(converted.contains("![encoded](./.attachments/encoded.png)"))
        #expect(converted.contains("![fileraw](./.attachments/file-raw.png)"))
        #expect(converted.contains("<img src=\"./.attachments/file-encoded.png\" />"))
    }

    @Test("Persistence conversion normalizes legacy absolute attachment paths from other machines")
    func persistenceConversionNormalizesLegacyAttachmentPaths() {
        let markdown = """
        ![legacy](/Users/other/Notes/.attachments/legacy-a.png)
        ![legacy2](file:///Users/other/Library/Mobile Documents/com~apple~CloudDocs/Cider Notes/.attachments/legacy-b.png)
        <img src="/Users/other/Notes/.attachments/legacy-c.png" />
        """

        let converted = NotesMarkdownPathCodec.markdownForPersistence(
            markdown,
            notesDirectoryURL: notesDirectory
        )

        #expect(converted.contains("![legacy](./.attachments/legacy-a.png)"))
        #expect(converted.contains("![legacy2](./.attachments/legacy-b.png)"))
        #expect(converted.contains("<img src=\"./.attachments/legacy-c.png\" />"))
    }

    @Test("Round-trip keeps attachment paths portable")
    func roundTripKeepsAttachmentPathsPortable() {
        let source = """
        # Heading
        ![a](./.attachments/a.png)
        Text
        <img src="./.attachments/b.png" width="320" />
        """

        let editorMarkdown = NotesMarkdownPathCodec.markdownForEditor(
            source,
            notesDirectoryURL: notesDirectory
        )
        let persisted = NotesMarkdownPathCodec.markdownForPersistence(
            editorMarkdown,
            notesDirectoryURL: notesDirectory
        )

        #expect(persisted.contains("![a](./.attachments/a.png)"))
        #expect(persisted.contains("<img src=\"./.attachments/b.png\" width=\"320\" />"))
        #expect(!persisted.contains("file:///"))
        #expect(!persisted.contains("/Users/test/"))
    }
}
