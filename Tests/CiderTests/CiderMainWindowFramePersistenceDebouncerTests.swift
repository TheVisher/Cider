import XCTest
@testable import Cider

@MainActor
final class CiderMainWindowFramePersistenceDebouncerTests: XCTestCase {
    func testRepeatedMoveEventsCoalesceIntoOnePersistenceAction() async throws {
        let debouncer = CiderMainWindowFramePersistenceDebouncer(delay: .milliseconds(20))
        var persistCount = 0

        for _ in 0..<20 {
            debouncer.schedule {
                persistCount += 1
            }
        }

        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(persistCount, 1)
    }

    func testFlushCancelsPendingPersistenceAndPersistsImmediately() async throws {
        let debouncer = CiderMainWindowFramePersistenceDebouncer(delay: .seconds(5))
        var persistCount = 0

        debouncer.schedule {
            persistCount += 1
        }
        debouncer.flush {
            persistCount += 1
        }

        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(persistCount, 1)
    }
}
