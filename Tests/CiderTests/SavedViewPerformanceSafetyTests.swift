import Foundation
import XCTest

final class SavedViewPerformanceSafetyTests: XCTestCase {
    func testSavedViewItemCardDoesNotLoadConfigPerRenderedItem() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Cider/Views/SavedViews/SavedViewTabContent.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        guard let itemCardRange = source.range(of: "private func itemCard(") else {
            XCTFail("SavedViewTabContent.itemCard helper not found")
            return
        }
        let tail = source[itemCardRange.lowerBound...]
        let end = tail.range(of: "\n    private func contextMenuItems")?.lowerBound ?? tail.endIndex
        let itemCardBody = String(tail[..<end])

        XCTAssertFalse(
            itemCardBody.contains("CiderConfig.load()"),
            "Per-item SavedView rendering should use cached view/config state instead of loading config from disk for each card during resize."
        )
    }
}
