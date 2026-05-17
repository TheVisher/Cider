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

    @Test("BookmarksStorage no longer exposes legacy folder writers")
    func bookmarksStorageNoLongerExposesLegacyFolderWriters() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Cider/Services/BookmarksStorage.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(!source.contains("func addFolderFromSync("))
        #expect(!source.contains("func updateFolderFromSync("))
        #expect(!source.contains("func deleteFolderFromSync("))
        #expect(!source.contains("func createFolder(name rawName:"))
        #expect(!source.contains("func renameFolder("))
        #expect(!source.contains("func setFolderIcon("))
        #expect(!source.contains("func deleteFolder(_ folderID:"))
        #expect(!source.contains("func setFolderCoverImage("))
        #expect(!source.contains("func setFolderCoverOffset("))
        #expect(!source.contains("func removeFolderCoverImage("))
        #expect(!source.contains("func folderCoverImageURL(for folder: Folder)"))
    }

    @Test("Direct folder table writes remain behind approved backend and repair boundaries")
    func directFolderTableWritesStayInApprovedFiles() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourcesRoot = projectRoot.appendingPathComponent("Sources/Cider")
        let allowedFiles: Set<String> = [
            "Sources/Cider/Services/VaultFolderService.swift",
            "Sources/Cider/Services/VaultDoctor.swift",
            "Sources/Cider/Services/CiderStorageAuditService.swift",
            "Sources/Cider/Database/DatabaseMigrations.swift"
        ]
        let writePatterns = [
            "INSERT INTO folders",
            "REPLACE INTO folders",
            "UPDATE folders",
            "DELETE FROM folders"
        ]

        let files = FileManager.default.enumerator(
            at: sourcesRoot,
            includingPropertiesForKeys: nil
        )?.compactMap { $0 as? URL } ?? []

        for file in files where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            guard writePatterns.contains(where: source.contains) else { continue }

            let relativePath = file.path
                .replacingOccurrences(of: projectRoot.path + "/", with: "")
            #expect(
                allowedFiles.contains(relativePath),
                "Unexpected direct folder table write in \(relativePath)"
            )
        }
    }
}
