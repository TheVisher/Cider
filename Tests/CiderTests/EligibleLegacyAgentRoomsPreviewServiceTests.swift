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

    func testEmptyBlockedAndFailedStatesProjectWithoutRoomsOrRawDiagnostics() {
        let privateDiagnostic = "/private/live-vault bearer-secret"
        XCTAssertEqual(
            EligibleLegacyAgentRoomsPreviewService(loadPreview: { .sanitized(.empty) }).loadWorkspace(),
            .empty(authority: .legacyAuthoritativePreview)
        )
        let blocked = EligibleLegacyAgentRoomsPreviewService(loadPreview: { .sanitized(.blocked) }).loadWorkspace()
        XCTAssertEqual(
            blocked,
            .eligiblePreviewBlocked(authority: .legacyAuthoritativePreview)
        )
        let failed = EligibleLegacyAgentRoomsPreviewService(loadPreview: {
            _ = privateDiagnostic
            return .sanitized(.failed)
        }).loadWorkspace()
        XCTAssertEqual(
            failed,
            .failed(authority: .legacyAuthoritativePreview, message: EligibleLegacyAgentRoomsPreviewService.failedMessage)
        )
        XCTAssertFalse(String(describing: blocked).contains(privateDiagnostic))
        XCTAssertFalse(String(describing: failed).contains(privateDiagnostic))
    }

    func testProductionCompositionUsesExactEligibleStackAndExcludesOldGlobalAdapter() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let composition = try String(contentsOf: root.appendingPathComponent("Sources/Cider/Views/CiderPanelView+ContentArea.swift"), encoding: .utf8)
        let block = try XCTUnwrap(composition.range(of: "case .agentRooms:").flatMap { start in
            composition.range(of: "case .aiAssistant:", range: start.upperBound..<composition.endIndex)
                .map { String(composition[start.lowerBound..<$0.lowerBound]) }
        })
        for required in [
            "let repository = ConversationRepository(database: CiderDatabase.shared)",
            "let canonical = AgentRoomsReadService(",
            "repository: repository",
            "agentAssignments: assignments",
            "participants: participants",
            "let paths = StoragePaths.legacyConversationPreviewDirectories()",
            "let parityReader = ConversationRepositoryParityReader(repository: repository)",
            "let eligible = LegacyConversationEligiblePreviewService(",
            "parityReader: parityReader",
            "try repository.rooms(lifecycle: .active, limit: 1).isEmpty",
            "let eligibleAdapter = EligibleLegacyAgentRoomsPreviewService(loadPreview: eligible.preview)",
            "loadCanonical: canonical.loadWorkspace",
            "loadLegacy: eligibleAdapter.loadWorkspace",
        ] {
            XCTAssertTrue(block.contains(required), "Missing eligible production composition: \(required)")
        }
        XCTAssertEqual(block.components(separatedBy: "ConversationRepository(database:").count - 1, 1)
        XCTAssertEqual(block.components(separatedBy: "ConversationRepositoryParityReader(repository:").count - 1, 1)
        XCTAssertNil(block.range(of: #"\bLegacyAgentRoomsPreviewService\("#, options: .regularExpression))
        for prohibited in [
            "LegacyConversationImportPreviewService", "AIConversationStorage", "CiderAgentChatRegistry",
            "createRoom(", "upsert", "import", "Shadow", "HealthStore", "Reconciler", "BridgeTransport",
            "Fixture", "debug", "tolerant", "createDirectory",
        ] {
            XCTAssertFalse(block.localizedCaseInsensitiveContains(prohibited), "Production block contains \(prohibited)")
        }
    }

    func testArbiterInvokesEligibleExactlyOnceOnlyForExplicitCanonicalIncompleteEmpty() {
        let canonicalRoom = AgentRoom(
            id: "canonical", title: "Canonical", preview: "Canonical", updatedAt: .distantPast,
            relativeTime: "Now", transcript: .init(runtimeLabel: "Hermes", messages: [], link: nil, receipt: nil, futureArtifact: nil)
        )
        let terminalStates: [AgentRoomsWorkspaceState] = [
            .loaded(authority: .canonicalIncomplete, rooms: [canonicalRoom], selectedRoomID: canonicalRoom.id),
            .failed(authority: .canonicalIncomplete, message: "sanitized"),
            .loading(authority: .canonicalIncomplete),
            .blocked(authority: .canonicalIncomplete, message: "sanitized"),
            .empty(authority: .legacyAuthoritativePreview),
        ]

        for canonical in terminalStates {
            var pathResolutions = 0
            var eligibleCalls = 0
            let result = AgentRoomsWorkspaceLoader(
                loadCanonical: { canonical },
                loadLegacy: {
                    pathResolutions += 1
                    eligibleCalls += 1
                    return .empty(authority: .legacyAuthoritativePreview)
                }
            ).loadWorkspace()
            XCTAssertEqual(result, canonical)
            XCTAssertEqual(pathResolutions, 0)
            XCTAssertEqual(eligibleCalls, 0)
        }

        var eligibleCalls = 0
        let eligible = AgentRoomsWorkspaceState.eligibleEmpty(
            authority: .legacyAuthoritativePreview,
            notice: .init(kind: .empty, displayed: 0, omitted: 2, capOmitted: 0, unregistered: 1)
        )
        XCTAssertEqual(
            AgentRoomsWorkspaceLoader(
                loadCanonical: { .empty(authority: .canonicalIncomplete) },
                loadLegacy: { eligibleCalls += 1; return eligible }
            ).loadWorkspace(),
            eligible
        )
        XCTAssertEqual(eligibleCalls, 1)
    }

    func testIdentityConflictRetryRetainsNativeButtonAccessibility() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/Cider/Views/AgentRooms/AgentRoomsWorkspaceView.swift"),
            encoding: .utf8
        )
        let block = try XCTUnwrap(source.range(of: "private func identityConflictState").flatMap { start in
            source.range(of: "private func failedState", range: start.upperBound..<source.endIndex)
                .map { String(source[start.lowerBound..<$0.lowerBound]) }
        })
        let summaryEnd = try XCTUnwrap(block.range(of: ".accessibilityLabel(\"\\(authorityPresentation(for: authority).badgeAccessibility). \\(notice.accessibilityLabel)\")"))
        let retry = try XCTUnwrap(block.range(of: "Button(\"Retry\")"))
        XCTAssertLessThan(summaryEnd.upperBound, retry.lowerBound)
        XCTAssertTrue(block.contains(".accessibilityLabel(\"Retry read-only legacy Rooms diagnosis\")"))
        XCTAssertFalse(block.hasSuffix(".accessibilityElement(children: .ignore)"))
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
