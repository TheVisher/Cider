import Foundation
import Testing
@testable import Cider

@Suite("Note Editor Import Provenance Tests")
struct NoteEditorImportProvenanceTests {

    @Test("Text file provenance preserves filename and path")
    func textFileProvenancePreservesFilenameAndPath() {
        let url = URL(fileURLWithPath: "/tmp/Cider Import/source note.md")
        let provenance = NoteEditorImportProvenance.textFile(url)

        #expect(provenance.auditMetadata["importSource"] == "text_file")
        #expect(provenance.auditMetadata["sourceFilename"] == "source note.md")
        #expect(provenance.auditMetadata["sourcePath"] == url.path)
    }

    @Test("Image provenance distinguishes pasteboard, remote URL, and local file sources")
    func imageProvenanceDistinguishesSourceKinds() {
        let pasteboard = NoteEditorImportProvenance.pasteboardImage(filename: "pasted-image.png")
        let remoteURL = URL(string: "https://example.com/image.png")!
        let remote = NoteEditorImportProvenance.remoteImageURL(remoteURL, filename: "image.png")
        let localURL = URL(fileURLWithPath: "/tmp/Cider Import/photo.png")
        let local = NoteEditorImportProvenance.imageFile(localURL)

        #expect(pasteboard.auditMetadata["importSource"] == "pasteboard_image")
        #expect(remote.auditMetadata["importSource"] == "remote_image_url")
        #expect(remote.auditMetadata["sourceURL"] == remoteURL.absoluteString)
        #expect(local.auditMetadata["importSource"] == "image_file")
        #expect(local.auditMetadata["sourceFilename"] == "photo.png")
        #expect(local.auditMetadata["sourcePath"] == localURL.path)
    }

    @Test("TipTap editor import handlers require provenance parameters")
    func editorImportHandlersRequireProvenanceParameters() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceURL = repoRoot.appendingPathComponent("Sources/Cider/ViewModels/NotesViewModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("func handleDroppedTextFileContent(_ content: String, provenance: NoteEditorImportProvenance)"))
        #expect(source.contains("func handleImageDrop(data: Data, filename: String, provenance: NoteEditorImportProvenance)"))
        #expect(source.contains("MutationAuditService.shared.record("))
        #expect(source.contains("editor_import_text"))
        #expect(source.contains("editor_import_image"))
    }
}
