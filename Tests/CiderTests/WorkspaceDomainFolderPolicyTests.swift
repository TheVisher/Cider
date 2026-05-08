import XCTest
@testable import Cider

final class WorkspaceDomainFolderPolicyTests: XCTestCase {
    func testBrowseShowsAllFolders() {
        let folders = makeFolders()

        let result = WorkspaceDomainFolderPolicy.folders(folders, for: .browse)

        XCTAssertEqual(result.map(\.name), folders.map(\.name))
    }

    func testMediaDomainShowsMediaRootsAndDescendantsOnly() {
        let folders = makeFolders()

        let result = WorkspaceDomainFolderPolicy.folders(folders, for: .media)

        XCTAssertEqual(result.map(\.name), ["Media", "Movies", "Books"])
    }

    func testProjectsDomainShowsProjectsRootsAndDescendantsOnly() {
        let folders = makeFolders()

        let result = WorkspaceDomainFolderPolicy.folders(folders, for: .projects)

        XCTAssertEqual(result.map(\.name), ["Projects", "Cider"])
    }

    func testDomainWithoutMatchingRootsFallsBackToAllFolders() {
        let folders = [Folder(name: "Random")]

        let result = WorkspaceDomainFolderPolicy.folders(folders, for: .people)

        XCTAssertEqual(result.map(\.name), ["Random"])
    }

    private func makeFolders() -> [Folder] {
        let mediaID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let projectsID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
        return [
            Folder(id: mediaID, name: "Media"),
            Folder(name: "Movies", parentID: mediaID),
            Folder(name: "Books", parentID: mediaID),
            Folder(id: projectsID, name: "Projects"),
            Folder(name: "Cider", parentID: projectsID),
            Folder(name: "Inbox"),
            Folder(name: "Bookmarks")
        ]
    }
}
