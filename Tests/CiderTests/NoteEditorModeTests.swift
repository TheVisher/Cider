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

    @Test("Source editor initial content is applied before delegate is armed")
    func sourceEditorInitialContentIsAppliedBeforeDelegateIsArmed() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceURL = repoRoot.appendingPathComponent("Sources/Cider/Views/Notes/NativeMarkdownEditorView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        guard let stringRange = source.range(of: "textView.string = viewModel.editingContent"),
              let delegateRange = source.range(of: "textView.delegate = context.coordinator") else {
            Issue.record("NativeMarkdownEditorView should explicitly set initial text and delegate")
            return
        }

        #expect(
            stringRange.lowerBound < delegateRange.lowerBound,
            "Arming NSTextView.delegate before applying initial content can publish sourceContentChanged during SwiftUI view creation/mode switch."
        )
    }

    @Test("Source editor keeps a valid fallback selection when content shrinks")
    @MainActor
    func sourceEditorKeepsAValidFallbackSelectionWhenContentShrinks() {
        let ranges = NativeMarkdownEditorView.sanitizedSelectionRanges(
            [
                NSValue(range: NSRange(location: 42, length: 3)),
                NSValue(range: NSRange(location: NSNotFound, length: 0))
            ],
            contentUTF16Length: 6
        )

        #expect(ranges == [NSValue(range: NSRange(location: 6, length: 0))])
    }
}
