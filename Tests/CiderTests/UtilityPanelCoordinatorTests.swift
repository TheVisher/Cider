import XCTest
@testable import Cider

@MainActor
final class UtilityPanelCoordinatorTests: XCTestCase {

    // MARK: - Open Item

    func testOpenItemCreatesSlotAndSetsActive() {
        let coord = UtilityPanelCoordinator()
        let id = UUID()
        coord.openItem(.bookmark(id), title: "Test Bookmark")

        XCTAssertEqual(coord.activeItem, .bookmark(id))
        XCTAssertEqual(coord.buffer.filledCount, 1)
        XCTAssertEqual(coord.buffer.activeIndex, 0)
        XCTAssertEqual(coord.history.stack.count, 1)
    }

    func testOpenDuplicateFocusesExisting() {
        let coord = UtilityPanelCoordinator()
        let id = UUID()
        coord.openItem(.bookmark(id), title: "Bookmark")
        coord.openItem(.note(UUID()), title: "Note")

        XCTAssertEqual(coord.buffer.filledCount, 2)
        XCTAssertEqual(coord.buffer.activeIndex, 1)

        // Re-open same bookmark
        coord.openItem(.bookmark(id), title: "Bookmark")

        XCTAssertEqual(coord.buffer.filledCount, 2) // no duplicate
        XCTAssertEqual(coord.buffer.activeIndex, 0) // focused back
        XCTAssertEqual(coord.activeItem, .bookmark(id))
        XCTAssertEqual(coord.history.stack.count, 3) // 3 pushes
    }

    func testOpenRejectedWhenAllPinned() {
        let coord = UtilityPanelCoordinator()
        for i in 0..<5 {
            coord.openItem(.bookmark(UUID()), title: "Item \(i)")
            coord.buffer.pin(at: i)
        }

        let rejectedID = UUID()
        coord.openItem(.todo(rejectedID), title: "Rejected")

        XCTAssertNotEqual(coord.activeItem, .todo(rejectedID))
        XCTAssertEqual(coord.buffer.filledCount, 5)
    }

    // MARK: - Navigation

    func testBackAndForward() {
        let coord = UtilityPanelCoordinator()
        let id1 = UUID()
        let id2 = UUID()
        coord.openItem(.bookmark(id1), title: "First")
        coord.openItem(.note(id2), title: "Second")

        XCTAssertEqual(coord.activeItem, .note(id2))

        coord.goBack()
        XCTAssertEqual(coord.activeItem, .bookmark(id1))

        coord.goForward()
        XCTAssertEqual(coord.activeItem, .note(id2))
    }

    func testBackToEvictedItemReopensIt() {
        let coord = UtilityPanelCoordinator()
        var ids: [UUID] = []

        // Fill 5 slots
        for i in 0..<5 {
            let id = UUID()
            ids.append(id)
            coord.openItem(.bookmark(id), title: "Item \(i)")
        }

        // Open 6th — evicts slot 0 (ids[0])
        let sixthID = UUID()
        coord.openItem(.bookmark(sixthID), title: "Sixth")
        XCTAssertNil(coord.buffer.index(of: ids[0]))

        // Navigate back through history to ids[0]
        for _ in 0..<5 {
            coord.goBack()
        }

        // ids[0] should be re-opened into a dot
        XCTAssertEqual(coord.activeItem, .bookmark(ids[0]))
        XCTAssertNotNil(coord.buffer.index(of: ids[0]))
    }

    // MARK: - Dot Tap

    func testActivateDotSwitchesActiveItem() {
        let coord = UtilityPanelCoordinator()
        let id1 = UUID()
        let id2 = UUID()
        coord.openItem(.bookmark(id1), title: "First")
        coord.openItem(.note(id2), title: "Second")

        coord.activateDot(at: 0)

        XCTAssertEqual(coord.activeItem, .bookmark(id1))
        XCTAssertEqual(coord.buffer.activeIndex, 0)
    }

    // MARK: - Close Active

    func testCloseActiveClearsSlot() {
        let coord = UtilityPanelCoordinator()
        let id = UUID()
        coord.openItem(.bookmark(id), title: "Test")

        coord.closeActive()

        XCTAssertNil(coord.activeItem)
        XCTAssertEqual(coord.buffer.filledCount, 0)
    }

    // MARK: - Item Types

    func testDifferentItemTypesGetCorrectDotColors() {
        let coord = UtilityPanelCoordinator()
        coord.openItem(.bookmark(UUID()), title: "Bookmark")
        coord.openItem(.note(UUID()), title: "Note")
        coord.openItem(.todo(UUID()), title: "Todo")

        XCTAssertEqual(coord.buffer.slots[0]?.itemType, .bookmark)
        XCTAssertEqual(coord.buffer.slots[1]?.itemType, .note)
        XCTAssertEqual(coord.buffer.slots[2]?.itemType, .todo)
    }
}
