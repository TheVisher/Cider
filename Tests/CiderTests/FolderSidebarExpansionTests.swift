import XCTest
@testable import Cider

final class FolderSidebarExpansionTests: XCTestCase {
    func testExpandableFolderIDsIncludesOnlyFoldersWithChildren() {
        let rootID = UUID()
        let childID = UUID()
        let leafID = UUID()
        let siblingID = UUID()

        let folders = [
            Folder(id: rootID, name: "Projects"),
            Folder(id: childID, name: "Cider", parentID: rootID),
            Folder(id: leafID, name: "Design", parentID: childID),
            Folder(id: siblingID, name: "Archive")
        ]

        let expandableIDs = FolderSidebarExpansion.expandableFolderIDs(in: folders)

        XCTAssertEqual(expandableIDs, [rootID, childID])
    }

    func testToggleCollapsesWhenAnyFolderIsExpanded() {
        let rootID = UUID()
        let childID = UUID()
        let folders = [
            Folder(id: rootID, name: "Projects"),
            Folder(id: childID, name: "Cider", parentID: rootID)
        ]

        let nextExpandedIDs = FolderSidebarExpansion.toggledExpandedFolderIDs(
            currentExpandedIDs: [rootID],
            folders: folders
        )

        XCTAssertTrue(nextExpandedIDs.isEmpty)
    }

    func testToggleExpandsEveryExpandableFolderWhenAllAreCollapsed() {
        let rootID = UUID()
        let childID = UUID()
        let leafID = UUID()
        let folders = [
            Folder(id: rootID, name: "Projects"),
            Folder(id: childID, name: "Cider", parentID: rootID),
            Folder(id: leafID, name: "Design", parentID: childID)
        ]

        let nextExpandedIDs = FolderSidebarExpansion.toggledExpandedFolderIDs(
            currentExpandedIDs: [],
            folders: folders
        )

        XCTAssertEqual(nextExpandedIDs, [rootID, childID])
    }
}
