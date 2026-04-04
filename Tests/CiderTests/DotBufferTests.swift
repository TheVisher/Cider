import XCTest
@testable import Cider

@MainActor
final class DotBufferTests: XCTestCase {

    // MARK: - Helpers

    private func makeSlot(
        itemID: UUID = UUID(),
        type: PanelItemType = .bookmark,
        title: String = "Test",
        isPinned: Bool = false,
        canEvict: Bool = true
    ) -> DotSlot {
        DotSlot(itemID: itemID, itemType: type, title: title, isPinned: isPinned, canEvict: canEvict)
    }

    // MARK: - Basic Open

    func testOpenIntoEmptyBuffer() {
        let buffer = DotBuffer()
        let slot = makeSlot(title: "First")
        let result = buffer.open(item: slot)

        XCTAssertEqual(result, .opened(index: 0))
        XCTAssertEqual(buffer.activeIndex, 0)
        XCTAssertEqual(buffer.slots[0]?.title, "First")
        XCTAssertEqual(buffer.filledCount, 1)
    }

    func testOpenFillsFirstEmptySlot() {
        let buffer = DotBuffer()

        for i in 0..<3 {
            buffer.open(item: makeSlot(title: "Item \(i)"))
        }

        XCTAssertEqual(buffer.filledCount, 3)
        XCTAssertEqual(buffer.activeIndex, 2)

        // Slots 0-2 filled, 3-4 empty
        XCTAssertNotNil(buffer.slots[0])
        XCTAssertNotNil(buffer.slots[1])
        XCTAssertNotNil(buffer.slots[2])
        XCTAssertNil(buffer.slots[3])
        XCTAssertNil(buffer.slots[4])
    }

    func testOpenAllFiveSlots() {
        let buffer = DotBuffer()

        for i in 0..<5 {
            let result = buffer.open(item: makeSlot(title: "Item \(i)"))
            XCTAssertEqual(result, .opened(index: i))
        }

        XCTAssertEqual(buffer.filledCount, 5)
    }

    // MARK: - Dedup

    func testDedupFocusesExistingDot() {
        let buffer = DotBuffer()
        let itemID = UUID()

        buffer.open(item: makeSlot(itemID: itemID, title: "Original"))
        buffer.open(item: makeSlot(title: "Second"))

        XCTAssertEqual(buffer.activeIndex, 1)

        // Open same item again
        let result = buffer.open(item: makeSlot(itemID: itemID, title: "Original"))

        XCTAssertEqual(result, .focused(index: 0))
        XCTAssertEqual(buffer.activeIndex, 0)
        XCTAssertEqual(buffer.filledCount, 2, "Should not create duplicate")
    }

    // MARK: - Eviction

    func testEvictsOldestUnpinnedWhenFull() {
        let buffer = DotBuffer()
        var ids: [UUID] = []

        for i in 0..<5 {
            let id = UUID()
            ids.append(id)
            buffer.open(item: makeSlot(itemID: id, title: "Item \(i)"))
        }

        // Open 6th item — should evict slot 0 (oldest unpinned)
        let newID = UUID()
        let result = buffer.open(item: makeSlot(itemID: newID, title: "Sixth"))

        XCTAssertEqual(result, .opened(index: 0))
        XCTAssertEqual(buffer.slots[0]?.itemID, newID)
        XCTAssertEqual(buffer.filledCount, 5)
    }

    func testEvictsOldestUnpinnedSkippingPinned() {
        let buffer = DotBuffer()
        var ids: [UUID] = []

        for i in 0..<5 {
            let id = UUID()
            ids.append(id)
            buffer.open(item: makeSlot(itemID: id, title: "Item \(i)"))
        }

        // Pin the first two
        buffer.pin(at: 0)
        buffer.pin(at: 1)

        // Open 6th — should evict slot 2 (oldest unpinned)
        let newID = UUID()
        let result = buffer.open(item: makeSlot(itemID: newID, title: "Sixth"))

        XCTAssertEqual(result, .opened(index: 2))
        XCTAssertEqual(buffer.slots[0]?.itemID, ids[0], "Pinned slot 0 untouched")
        XCTAssertEqual(buffer.slots[1]?.itemID, ids[1], "Pinned slot 1 untouched")
        XCTAssertEqual(buffer.slots[2]?.itemID, newID)
    }

    // MARK: - All 5 Pinned → Rejected

    func testAllFivePinnedRejectsNewItem() {
        let buffer = DotBuffer()

        for i in 0..<5 {
            buffer.open(item: makeSlot(title: "Item \(i)"))
            buffer.pin(at: i)
        }

        let result = buffer.open(item: makeSlot(title: "Rejected"))

        XCTAssertEqual(result, .rejected)
        XCTAssertEqual(buffer.filledCount, 5)
    }

    // MARK: - canEvict = false Treated as Pinned for Eviction

    func testCanEvictFalseSkippedDuringEviction() {
        let buffer = DotBuffer()
        var ids: [UUID] = []

        for i in 0..<5 {
            let id = UUID()
            ids.append(id)
            buffer.open(item: makeSlot(itemID: id, title: "Item \(i)"))
        }

        // Mark slot 0 as non-evictable (unsaved work)
        buffer.setCanEvict(false, at: 0)

        // Open 6th — should skip slot 0 (canEvict=false), evict slot 1
        let newID = UUID()
        let result = buffer.open(item: makeSlot(itemID: newID, title: "Sixth"))

        XCTAssertEqual(result, .opened(index: 1))
        XCTAssertEqual(buffer.slots[0]?.itemID, ids[0], "Non-evictable slot untouched")
        XCTAssertEqual(buffer.slots[1]?.itemID, newID)
    }

    func testAllNonEvictableRejects() {
        let buffer = DotBuffer()

        for i in 0..<5 {
            buffer.open(item: makeSlot(title: "Item \(i)"))
            buffer.setCanEvict(false, at: i)
        }

        let result = buffer.open(item: makeSlot(title: "Rejected"))
        XCTAssertEqual(result, .rejected)
    }

    func testMixedPinnedAndNonEvictableRejects() {
        let buffer = DotBuffer()

        for i in 0..<5 {
            buffer.open(item: makeSlot(title: "Item \(i)"))
        }

        // Pin 3, mark 2 as non-evictable
        buffer.pin(at: 0)
        buffer.pin(at: 1)
        buffer.pin(at: 2)
        buffer.setCanEvict(false, at: 3)
        buffer.setCanEvict(false, at: 4)

        let result = buffer.open(item: makeSlot(title: "Rejected"))
        XCTAssertEqual(result, .rejected)
        XCTAssertTrue(buffer.allPinnedOrNonEvictable)
    }

    // MARK: - Pin / Unpin

    func testPinAndUnpin() {
        let buffer = DotBuffer()
        buffer.open(item: makeSlot(title: "Test"))

        XCTAssertEqual(buffer.slots[0]?.isPinned, false)

        buffer.pin(at: 0)
        XCTAssertEqual(buffer.slots[0]?.isPinned, true)

        buffer.unpin(at: 0)
        XCTAssertEqual(buffer.slots[0]?.isPinned, false)
    }

    func testPinOnEmptySlotIsNoOp() {
        let buffer = DotBuffer()
        buffer.pin(at: 0) // should not crash
        XCTAssertNil(buffer.slots[0])
    }

    func testPinOutOfBoundsIsNoOp() {
        let buffer = DotBuffer()
        buffer.pin(at: 99) // should not crash
    }

    // MARK: - Clear

    func testClearSlot() {
        let buffer = DotBuffer()
        buffer.open(item: makeSlot(title: "Test"))

        XCTAssertEqual(buffer.filledCount, 1)

        buffer.clear(at: 0)

        XCTAssertNil(buffer.slots[0])
        XCTAssertEqual(buffer.filledCount, 0)
        XCTAssertNil(buffer.activeIndex)
    }

    func testClearAll() {
        let buffer = DotBuffer()

        for i in 0..<5 {
            buffer.open(item: makeSlot(title: "Item \(i)"))
        }

        buffer.clearAll()

        XCTAssertEqual(buffer.filledCount, 0)
        XCTAssertNil(buffer.activeIndex)
    }

    // MARK: - Clear Reopens Slot for New Items

    func testClearedSlotCanBeReused() {
        let buffer = DotBuffer()

        for i in 0..<5 {
            buffer.open(item: makeSlot(title: "Item \(i)"))
        }

        buffer.clear(at: 2)

        let newID = UUID()
        let result = buffer.open(item: makeSlot(itemID: newID, title: "New"))

        XCTAssertEqual(result, .opened(index: 2))
        XCTAssertEqual(buffer.slots[2]?.itemID, newID)
    }

    // MARK: - Index Lookup

    func testIndexOfFindsItem() {
        let buffer = DotBuffer()
        let id = UUID()
        buffer.open(item: makeSlot(itemID: id, title: "Find Me"))

        XCTAssertEqual(buffer.index(of: id), 0)
    }

    func testIndexOfReturnsNilForMissingItem() {
        let buffer = DotBuffer()
        XCTAssertNil(buffer.index(of: UUID()))
    }

    // MARK: - Eviction Order After Multiple Opens

    func testEvictionOrderIsCorrectAfterGaps() {
        let buffer = DotBuffer()
        var ids: [UUID] = []

        // Fill all 5
        for i in 0..<5 {
            let id = UUID()
            ids.append(id)
            buffer.open(item: makeSlot(itemID: id, title: "Item \(i)"))
        }

        // Clear slot 1, open a new item (fills slot 1)
        buffer.clear(at: 1)
        let newID = UUID()
        buffer.open(item: makeSlot(itemID: newID, title: "New"))

        // Now eviction order: slot 0 is oldest (still original)
        let sixthID = UUID()
        let result = buffer.open(item: makeSlot(itemID: sixthID, title: "Sixth"))

        XCTAssertEqual(result, .opened(index: 0), "Slot 0 is oldest unpinned")
        XCTAssertEqual(buffer.slots[0]?.itemID, sixthID)
    }

    // MARK: - Linked Pair (Split View)

    func testLinkSetsLinkedPair() {
        let buffer = DotBuffer()
        buffer.open(item: makeSlot(title: "A"))
        buffer.open(item: makeSlot(title: "B"))
        buffer.link(0, 1)
        XCTAssertEqual(buffer.linkedPair?.0, 0)
        XCTAssertEqual(buffer.linkedPair?.1, 1)
        XCTAssertTrue(buffer.isLinked(0))
        XCTAssertTrue(buffer.isLinked(1))
        XCTAssertFalse(buffer.isLinked(2))
        XCTAssertEqual(buffer.linkedPartner(of: 0), 1)
    }

    func testUnlinkClearsLinkedPair() {
        let buffer = DotBuffer()
        buffer.open(item: makeSlot(title: "A"))
        buffer.open(item: makeSlot(title: "B"))
        buffer.link(0, 1)
        buffer.unlink()
        XCTAssertNil(buffer.linkedPair)
        XCTAssertFalse(buffer.isLinked(0))
    }

    func testLinkEmptySlotIsNoOp() {
        let buffer = DotBuffer()
        buffer.open(item: makeSlot(title: "A"))
        buffer.link(0, 1)
        XCTAssertNil(buffer.linkedPair)
    }

    func testClearLinkedSlotUnlinks() {
        let buffer = DotBuffer()
        buffer.open(item: makeSlot(title: "A"))
        buffer.open(item: makeSlot(title: "B"))
        buffer.link(0, 1)
        buffer.clear(at: 0)
        XCTAssertNil(buffer.linkedPair)
    }
}
