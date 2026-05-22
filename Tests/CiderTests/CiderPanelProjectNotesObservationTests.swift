import Foundation
import Testing

@Suite("Cider panel project notes observation tests")
struct CiderPanelProjectNotesObservationTests {
    @Test("project notes surface observes NotesStorage directly instead of reading singleton statically")
    func projectNotesSurfaceObservesNotesStorageDirectly() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CiderTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        let panelSource = try String(contentsOf: repoRoot.appendingPathComponent("Sources/Cider/Views/CiderPanelView.swift"), encoding: .utf8)
        let contentAreaSource = try String(contentsOf: repoRoot.appendingPathComponent("Sources/Cider/Views/CiderPanelView+ContentArea.swift"), encoding: .utf8)

        #expect(panelSource.contains("@ObservedObject var notesStorage = NotesStorage.shared"))
        #expect(contentAreaSource.contains("notes: notesStorage.notes"))
        #expect(!contentAreaSource.contains("notes: NotesStorage.shared.notes"))
    }
}
