import Foundation
import Testing
@testable import Cider

@Suite("Note Editor Mode Tests")
struct NoteEditorModeTests {

    @Test("Rich editor mode is the default")
    func richEditorModeIsDefault() {
        #expect(NoteEditorMode.default == .rich)
    }

    @Test("Editor modes expose native toolbar metadata")
    func editorModesExposeToolbarMetadata() {
        #expect(NoteEditorMode.rich.displayName == "Rich")
        #expect(NoteEditorMode.rich.icon == "textformat")
        #expect(NoteEditorMode.source.displayName == "Markdown")
        #expect(NoteEditorMode.source.icon == "chevron.left.forwardslash.chevron.right")
    }

    @Test("Old config without editor mode decodes to rich mode")
    func oldConfigWithoutEditorModeDecodesToRichMode() throws {
        let data = "{}".data(using: .utf8)!
        let config = try JSONDecoder().decode(CiderConfig.self, from: data)

        #expect(config.noteEditorMode == .rich)
    }
}
