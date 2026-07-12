import Foundation
import XCTest
@testable import Cider

@MainActor
final class EligibleLegacyAgentRoomsPreviewServiceTests: XCTestCase {
    func testExactLoadedEmptyBlockedFailedAndAccessibilityCopy() {
        let loaded = AgentRoomsEligibleNotice(kind: .loaded, displayed: 20, omitted: 3, capOmitted: 2, unregistered: 4)
        XCTAssertEqual(loaded.title, "Eligible legacy preview")
        XCTAssertEqual(
            loaded.detail,
            "Showing 20 independently validated room(s). 3 registered room(s) were omitted after validation. 2 additional eligible room(s) are not shown by the 20-room limit. 4 unregistered conversation file(s) were excluded. Read-only, noncanonical legacy history. Nothing has been imported or changed."
        )
        XCTAssertTrue(loaded.accessibilityLabel.hasSuffix("Read-only, legacy authoritative, noncanonical preview, not imported. Messaging disabled."))

        let empty = AgentRoomsEligibleNotice(kind: .empty, displayed: 0, omitted: 140, capOmitted: 0, unregistered: 101)
        XCTAssertEqual(empty.title, "No eligible legacy rooms")
        XCTAssertTrue(empty.detail.contains("99+ registered room(s)"))
        XCTAssertTrue(empty.detail.contains("99+ unregistered conversation file(s)"))
        XCTAssertEqual(EligibleLegacyAgentRoomsPreviewService.blockedMessage, "We couldn’t establish a complete, conflict-free read-only view. No legacy rooms are shown.")
        XCTAssertEqual(EligibleLegacyAgentRoomsPreviewService.failedMessage, "No legacy rooms are shown. Try again.")
    }

    func testEligibleFlagsAreMandatoryAndNeverBecomeWriteAuthorization() {
        var counts = LegacyConversationEligibleCounts.zero
        counts.registeredActiveTotal = 1
        counts.roomLocalOmitted = 1
        let preview = LegacyConversationEligiblePreview(state: .eligibleEmpty, counts: counts, rooms: [])
        XCTAssertFalse(preview.safeForBackfill)
        XCTAssertFalse(preview.safeForShadowWrites)
        XCTAssertEqual(
            EligibleLegacyAgentRoomsPreviewService(loadPreview: { preview }).loadWorkspace(),
            .eligibleEmpty(
                authority: .legacyAuthoritativePreview,
                notice: .init(kind: .empty, displayed: 0, omitted: 1, capOmitted: 0, unregistered: 0)
            )
        )
    }

    func testProductionCompositionRemainsCID794StrictGlobalLoader() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let composition = try String(contentsOf: root.appendingPathComponent("Sources/Cider/Views/CiderPanelView+ContentArea.swift"), encoding: .utf8)
        let block = try XCTUnwrap(composition.range(of: "case .agentRooms:").flatMap { start in
            composition.range(of: "case .aiAssistant:", range: start.upperBound..<composition.endIndex)
                .map { String(composition[start.lowerBound..<$0.lowerBound]) }
        })
        XCTAssertTrue(block.contains("LegacyAgentRoomsPreviewService"))
        XCTAssertFalse(block.contains("EligibleLegacyAgentRoomsPreviewService"))
        XCTAssertFalse(block.contains("LegacyConversationEligiblePreviewService"))
    }

    func testNewServicesHaveNoLoggingDebugPrintingOrMutationDependencies() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for path in [
            "Sources/Cider/Services/Conversation/LegacyConversationEligiblePreviewService.swift",
            "Sources/Cider/Services/Conversation/EligibleLegacyAgentRoomsPreviewService.swift",
        ] {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            for prohibited in ["debugPrint", "Logger(", "os_log", "createDirectory", "write(to:", "createRoom(", "upsert"] {
                XCTAssertFalse(source.localizedCaseInsensitiveContains(prohibited), "\(path) contains \(prohibited)")
            }
            XCTAssertFalse(source.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("print(") })
        }
    }
}
