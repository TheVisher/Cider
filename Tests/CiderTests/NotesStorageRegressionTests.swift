import Foundation
import Testing
@testable import Cider

@Suite("Notes Storage Regression Tests")
@MainActor
struct NotesStorageRegressionTests {
    @Test("Scan notes tolerates duplicate filename index entries")
    func scanNotesToleratesDuplicateFilenameIndexEntries() throws {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("Cider-NotesStorageRegression-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let duplicateFilename = "Duplicate.md"
        let noteURL = tempDirectory.appendingPathComponent(duplicateFilename)
        try "# Duplicate index regression\n".write(to: noteURL, atomically: true, encoding: .utf8)

        let uuidA = UUID()
        let uuidB = UUID()
        let duplicateIndex: [String: String] = [
            uuidA.uuidString: duplicateFilename,
            uuidB.uuidString: duplicateFilename
        ]

        let indexData = try JSONEncoder().encode(duplicateIndex)
        let indexURL = tempDirectory.appendingPathComponent("_cider_notes_index.json")
        try indexData.write(to: indexURL, options: .atomic)

        let storage = NotesStorage.shared
        let originalPath = CiderConfig.load().notesDirectory
        defer {
            storage.updateDirectory(to: originalPath)
            try? fileManager.removeItem(at: tempDirectory)
        }

        storage.updateDirectory(to: tempDirectory.path)

        #expect(storage.notes.count == 1)
        guard let note = storage.notes.first else {
            Issue.record("Expected one note after scanning duplicate index entries.")
            return
        }

        guard let expectedWinner = [uuidA, uuidB].min(by: { $0.uuidString < $1.uuidString }) else {
            Issue.record("Failed to compute expected UUID winner.")
            return
        }

        let expectedLoser = (expectedWinner == uuidA) ? uuidB : uuidA
        #expect(note.id == expectedWinner)
        #expect(note.relativePath == duplicateFilename)

        let rewrittenData = try Data(contentsOf: indexURL)
        let rewrittenIndex = try JSONDecoder().decode([String: String].self, from: rewrittenData)
        #expect(rewrittenIndex.count == 1)
        #expect(rewrittenIndex[expectedWinner.uuidString] == duplicateFilename)
        #expect(rewrittenIndex[expectedLoser.uuidString] == nil)
    }
}
