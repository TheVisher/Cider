import XCTest
@testable import Cider

@MainActor
final class PanelHistoryTests: XCTestCase {

    // MARK: - Helpers

    private func itemEntry(_ itemID: UUID = UUID()) -> PanelHistoryEntry {
        PanelHistoryEntry(type: .item(itemID: itemID))
    }

    private func toolEntry(_ mode: ToolMode) -> PanelHistoryEntry {
        PanelHistoryEntry(type: .tool(mode))
    }

    private func splitEntry(_ id1: UUID = UUID(), _ id2: UUID = UUID()) -> PanelHistoryEntry {
        PanelHistoryEntry(type: .splitView(itemID1: id1, itemID2: id2))
    }

    // MARK: - Basic Push & Navigation

    func testEmptyHistory() {
        let history = PanelHistory()

        XCTAssertTrue(history.isEmpty)
        XCTAssertNil(history.current)
        XCTAssertFalse(history.canGoBack)
        XCTAssertFalse(history.canGoForward)
    }

    func testPushSetsCurrentIndex() {
        let history = PanelHistory()
        let entry = itemEntry()

        history.push(entry)

        XCTAssertEqual(history.currentIndex, 0)
        XCTAssertEqual(history.current?.id, entry.id)
        XCTAssertFalse(history.canGoBack)
        XCTAssertFalse(history.canGoForward)
    }

    func testPushMultipleEntries() {
        let history = PanelHistory()

        let e1 = itemEntry()
        let e2 = itemEntry()
        let e3 = itemEntry()

        history.push(e1)
        history.push(e2)
        history.push(e3)

        XCTAssertEqual(history.stack.count, 3)
        XCTAssertEqual(history.currentIndex, 2)
        XCTAssertEqual(history.current?.id, e3.id)
    }

    func testBackAndForward() {
        let history = PanelHistory()

        let e1 = itemEntry()
        let e2 = itemEntry()
        let e3 = itemEntry()

        history.push(e1)
        history.push(e2)
        history.push(e3)

        // Back to e2
        let back1 = history.back()
        XCTAssertEqual(back1?.id, e2.id)
        XCTAssertEqual(history.currentIndex, 1)
        XCTAssertTrue(history.canGoBack)
        XCTAssertTrue(history.canGoForward)

        // Back to e1
        let back2 = history.back()
        XCTAssertEqual(back2?.id, e1.id)
        XCTAssertEqual(history.currentIndex, 0)
        XCTAssertFalse(history.canGoBack)

        // Can't go back further
        let backNil = history.back()
        XCTAssertNil(backNil)
        XCTAssertEqual(history.currentIndex, 0)

        // Forward to e2
        let fwd1 = history.forward()
        XCTAssertEqual(fwd1?.id, e2.id)

        // Forward to e3
        let fwd2 = history.forward()
        XCTAssertEqual(fwd2?.id, e3.id)
        XCTAssertFalse(history.canGoForward)

        // Can't go forward further
        let fwdNil = history.forward()
        XCTAssertNil(fwdNil)
    }

    // MARK: - Push Truncates Forward History

    func testPushTruncatesForwardHistory() {
        let history = PanelHistory()

        let e1 = itemEntry()
        let e2 = itemEntry()
        let e3 = itemEntry()

        history.push(e1)
        history.push(e2)
        history.push(e3)

        // Back to e1
        history.back()
        history.back()
        XCTAssertEqual(history.currentIndex, 0)

        // Push new entry — e2 and e3 are discarded
        let e4 = itemEntry()
        history.push(e4)

        XCTAssertEqual(history.stack.count, 2)
        XCTAssertEqual(history.currentIndex, 1)
        XCTAssertEqual(history.current?.id, e4.id)
        XCTAssertFalse(history.canGoForward)
    }

    // MARK: - Tool Mode Cycling

    func testToolModeCycling() {
        let history = PanelHistory()

        let bookmark = itemEntry()
        let clipboard = toolEntry(.clipboard)
        let ai = toolEntry(.aiChat)

        history.push(bookmark)
        history.push(clipboard)
        history.push(ai)

        // Back → Back → should be at bookmark
        history.back()
        XCTAssertEqual(history.current?.type, .tool(.clipboard))

        history.back()
        XCTAssertEqual(history.current?.type, bookmark.type)

        // Forward → Forward → back at AI
        history.forward()
        XCTAssertEqual(history.current?.type, .tool(.clipboard))

        history.forward()
        XCTAssertEqual(history.current?.type, .tool(.aiChat))
    }

    // MARK: - Split View in History

    func testSplitViewInHistory() {
        let history = PanelHistory()

        let id1 = UUID()
        let id2 = UUID()

        let single = itemEntry()
        let split = splitEntry(id1, id2)
        let after = itemEntry()

        history.push(single)
        history.push(split)
        history.push(after)

        // Back to split view
        let backToSplit = history.back()
        if case .splitView(let a, let b) = backToSplit?.type {
            XCTAssertEqual(a, id1)
            XCTAssertEqual(b, id2)
        } else {
            XCTFail("Expected split view entry")
        }

        // Forward re-enters the post-split item
        let fwd = history.forward()
        XCTAssertEqual(fwd?.id, after.id)

        // Back again still lands on split
        history.back()
        if case .splitView = history.current?.type {
            // OK
        } else {
            XCTFail("Expected split view on second back")
        }
    }

    // MARK: - History Cap

    func testHistoryCapAt50() {
        let history = PanelHistory()

        for _ in 0..<60 {
            history.push(itemEntry())
        }

        XCTAssertEqual(history.stack.count, PanelHistory.maxEntries)
        XCTAssertEqual(history.currentIndex, PanelHistory.maxEntries - 1)
    }

    func testHistoryCapPreservesRecentEntries() {
        let history = PanelHistory()

        // Push 49 random entries
        for _ in 0..<49 {
            history.push(itemEntry())
        }

        // Push a known entry as #50
        let known = itemEntry()
        history.push(known)

        XCTAssertEqual(history.stack.count, 50)
        XCTAssertEqual(history.current?.id, known.id)

        // Push one more — oldest dropped, known still in stack
        history.push(itemEntry())

        XCTAssertEqual(history.stack.count, 50)
        XCTAssertTrue(history.stack.contains(where: { $0.id == known.id }))
    }

    // MARK: - Cap Doesn't Break Navigation

    func testCapDoesNotBreakBackNavigation() {
        let history = PanelHistory()

        for _ in 0..<60 {
            history.push(itemEntry())
        }

        // Should be able to go back 49 times (50 entries, index starts at 49)
        var backCount = 0
        while history.canGoBack {
            history.back()
            backCount += 1
        }

        XCTAssertEqual(backCount, PanelHistory.maxEntries - 1)
        XCTAssertEqual(history.currentIndex, 0)
    }

    // MARK: - Mixed Entry Types

    func testMixedItemsAndToolsInHistory() {
        let history = PanelHistory()

        let itemA = itemEntry()
        let clip = toolEntry(.clipboard)
        let itemB = itemEntry()
        let ai = toolEntry(.aiChat)
        let search = toolEntry(.search)

        history.push(itemA)
        history.push(clip)
        history.push(itemB)
        history.push(ai)
        history.push(search)

        XCTAssertEqual(history.stack.count, 5)

        // Walk back through all
        history.back() // ai
        XCTAssertEqual(history.current?.type, .tool(.aiChat))

        history.back() // itemB
        if case .item = history.current?.type {} else {
            XCTFail("Expected item entry")
        }

        history.back() // clipboard
        XCTAssertEqual(history.current?.type, .tool(.clipboard))

        history.back() // itemA
        if case .item = history.current?.type {} else {
            XCTFail("Expected item entry")
        }

        XCTAssertFalse(history.canGoBack)
    }

    // MARK: - Push After Back at Midpoint

    func testPushAfterBackAtMidpoint() {
        let history = PanelHistory()

        history.push(itemEntry())
        history.push(itemEntry())
        history.push(itemEntry())
        history.push(itemEntry())
        history.push(itemEntry())

        // Go back 2
        history.back()
        history.back()
        XCTAssertEqual(history.currentIndex, 2)

        // Push new — should truncate entries 3 and 4
        let newEntry = toolEntry(.clipboard)
        history.push(newEntry)

        XCTAssertEqual(history.stack.count, 4)
        XCTAssertEqual(history.currentIndex, 3)
        XCTAssertEqual(history.current?.id, newEntry.id)
        XCTAssertFalse(history.canGoForward)
    }

    // MARK: - Edge: Single Entry

    func testSingleEntryNoNavigation() {
        let history = PanelHistory()
        let entry = itemEntry()
        history.push(entry)

        XCTAssertFalse(history.canGoBack)
        XCTAssertFalse(history.canGoForward)
        XCTAssertEqual(history.current?.id, entry.id)
    }
}
