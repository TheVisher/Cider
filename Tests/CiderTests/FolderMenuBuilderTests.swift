import XCTest
@testable import Cider

final class FolderMenuBuilderTests: XCTestCase {
    func testMoveToFolderMenuBuildsNestedTreeFromParentIDs() {
        let rootID = UUID()
        let childID = UUID()
        let leafID = UUID()
        let siblingID = UUID()
        let folders = [
            Folder(id: leafID, name: "Leaf", parentID: childID),
            Folder(id: siblingID, name: "Archive"),
            Folder(id: rootID, name: "Projects"),
            Folder(id: childID, name: "Cider", parentID: rootID)
        ]

        let items = FolderMenuBuilder.moveToFolderMenuItems(folders: folders) { _ in }

        guard case .submenu("Move to Folder", let children) = items.first else {
            return XCTFail("Expected Move to Folder submenu")
        }
        XCTAssertEqual(children.menuTitles, ["No Folder", "-", "Archive", "Projects"])

        guard case .submenu("Projects", let projectChildren) = children[3] else {
            return XCTFail("Expected Projects submenu")
        }
        XCTAssertEqual(projectChildren.menuTitles, ["Cider"])

        guard case .submenu("Cider", let ciderChildren) = projectChildren[0] else {
            return XCTFail("Expected Cider submenu")
        }
        XCTAssertEqual(ciderChildren.menuTitles, ["Leaf"])
    }

    func testMoveToFolderMenuDropsOrphanedFoldersInsteadOfFlatteningThem() {
        let rootID = UUID()
        let orphanParentID = UUID()
        let folders = [
            Folder(id: rootID, name: "Root"),
            Folder(name: "Orphan", parentID: orphanParentID)
        ]

        let items = FolderMenuBuilder.moveToFolderMenuItems(folders: folders) { _ in }

        guard case .submenu("Move to Folder", let children) = items.first else {
            return XCTFail("Expected Move to Folder submenu")
        }
        XCTAssertEqual(children.menuTitles, ["No Folder", "-", "Root"])
    }
}

private extension Array where Element == CardMenuItem {
    var menuTitles: [String] {
        map { item in
            switch item {
            case .action(let title, _, _):
                title
            case .submenu(let title, _):
                title
            case .separator:
                "-"
            case .destructive(let title, _):
                title
            case .disabled(let title):
                title
            case .hint(let title):
                title
            }
        }
    }
}
