import Foundation
import Testing

@Suite("Folder Delete Safety Tests")
struct FolderDeleteSafetyTests {
    @Test("BookmarksViewModel delegates folder delete draining to VaultFolderService")
    func bookmarksViewModelDelegatesFolderDeleteDrainingToService() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Cider/ViewModels/BookmarksViewModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        guard let start = source.range(of: "    @discardableResult\n    func deleteFolder(_ folderID: UUID) -> Bool {"),
              let end = source.range(of: "\n\n    @discardableResult\n    func setFolderCover", range: start.upperBound..<source.endIndex)
        else {
            Issue.record("Could not locate BookmarksViewModel.deleteFolder body")
            return
        }

        let body = String(source[start.lowerBound..<end.lowerBound])

        #expect(body.contains("VaultFolderService.shared.deleteFolder(folderID)"))
        #expect(!body.contains("assignNote("))
        #expect(!body.contains("assignBookmark("))
        #expect(!body.contains("assignTodoCard("))
        #expect(!body.contains("assignDateCard("))
        #expect(!body.contains("assignContact("))
        #expect(!body.contains("assignFile("))
    }
}
