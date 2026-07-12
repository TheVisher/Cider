import Foundation
import XCTest
@testable import Cider

@MainActor
final class LegacyCandidateConflictDiagnosisTests: XCTestCase {
    func testDiagnosisModelIsVersionedOrderedBoundedAndCodable() throws {
        let diagnosis = LegacyCandidateConflictDiagnosis(
            affectedCandidateCount: .exact(3),
            counts: [
                .init(kind: .messageRecordIdentity, conflictingIdentityGroups: .exact(1)),
                .init(kind: .messageProvenanceIdentity, conflictingIdentityGroups: .exact(0)),
                .init(kind: .runtimeBindingIdentity, conflictingIdentityGroups: .exact(2)),
                .init(kind: .historicalTurnProvenanceIdentity, conflictingIdentityGroups: .atLeast100),
            ]
        )

        XCTAssertEqual(diagnosis.formatVersion, "cider.legacy-candidate-conflict-diagnosis.v1")
        XCTAssertEqual(diagnosis.counts.map(\.kind), LegacyCandidateConflictKind.allCases)
        XCTAssertTrue(diagnosis.isValid)
        XCTAssertEqual(try JSONDecoder().decode(
            LegacyCandidateConflictDiagnosis.self,
            from: JSONEncoder().encode(diagnosis)
        ), diagnosis)
        XCTAssertThrowsError(try JSONDecoder().decode(
            LegacyBoundedCount.self,
            from: Data(#"{"exact":100}"#.utf8)
        ))
    }

    func testAdapterProjectsExactConflictCopyAndOnlyNonzeroRows() {
        let diagnosis = makeDiagnosis(
            affected: .exact(3),
            record: .exact(1),
            provenance: .exact(0),
            runtime: .exact(2),
            turn: .atLeast100
        )
        let preview = LegacyConversationEligiblePreview.identityConflict(diagnosis)

        let state = EligibleLegacyAgentRoomsPreviewService(loadPreview: { preview }).loadWorkspace()
        guard case .legacyIdentityConflict(let authority, let notice) = state else {
            return XCTFail("Expected structured identity-conflict block")
        }
        XCTAssertEqual(authority, .legacyAuthoritativePreview)
        XCTAssertEqual(notice.title, "Legacy Rooms have an identity conflict")
        XCTAssertEqual(
            notice.detail,
            "Multiple registered rooms claim the same message or runtime identity. To avoid showing history under the wrong room, Cider is showing no rooms. Nothing was imported or changed."
        )
        XCTAssertEqual(notice.rows, [
            .init(label: "Message record ID conflicts", count: "1"),
            .init(label: "Runtime binding conflicts", count: "2"),
            .init(label: "Historical turn provenance conflicts", count: "99+"),
        ])
        XCTAssertEqual(notice.affectedCandidateCount, "3")
        XCTAssertTrue(notice.accessibilityLabel.hasSuffix(
            "Read-only, legacy authoritative, noncanonical preview. No rooms shown. Nothing imported or changed. Messaging disabled."
        ))
        XCTAssertEqual(
            state.projection(),
            .legacyIdentityConflict(authority: .legacyAuthoritativePreview, notice: notice)
        )
    }

    func testAdapterRejectsEveryForgedDiagnosisOrPreviewInvariantFailClosed() throws {
        let valid = makeDiagnosis(affected: .exact(2), record: .exact(1))
        let invalidDiagnoses = [
            makeDiagnosis(affected: .exact(0), record: .exact(1)),
            makeDiagnosis(affected: .exact(2)),
            LegacyCandidateConflictDiagnosis(affectedCandidateCount: .exact(2), counts: Array(valid.counts.dropLast())),
            LegacyCandidateConflictDiagnosis(affectedCandidateCount: .exact(2), counts: Array(valid.counts.reversed())),
            LegacyCandidateConflictDiagnosis(affectedCandidateCount: .exact(2), counts: [valid.counts[0], valid.counts[0], valid.counts[2], valid.counts[3]]),
            makeDiagnosis(affected: .exact(2), record: .exact(100)),
        ]

        for diagnosis in invalidDiagnoses {
            assertGenericBlock(LegacyConversationEligiblePreview.identityConflict(diagnosis))
        }

        var roomsPresent = LegacyConversationEligiblePreview.identityConflict(valid)
        roomsPresent.rooms = [LegacyConversationEligibleRoom(plan: .init(), totalMessages: 0, messageCapOmitted: 0)]
        assertGenericBlock(roomsPresent)

        var ordinaryCountsPresent = LegacyConversationEligiblePreview.identityConflict(valid)
        ordinaryCountsPresent.counts.registeredActiveTotal = 1
        assertGenericBlock(ordinaryCountsPresent)

        var wrongState = LegacyConversationEligiblePreview.identityConflict(valid)
        wrongState.state = .ready
        assertGenericBlock(wrongState)

        for (key, value) in [("readOnly", false), ("changed", true), ("safeForBackfill", true), ("safeForShadowWrites", true)] {
            let forged = try forgePreview(LegacyConversationEligiblePreview.identityConflict(valid), key: key, value: value)
            assertGenericBlock(forged)
        }
        assertGenericBlock(try forgePreview(
            LegacyConversationEligiblePreview.identityConflict(valid),
            key: "formatVersion",
            value: "forged.preview.version"
        ))

        var object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(LegacyConversationEligiblePreview.identityConflict(valid))
        ) as? [String: Any])
        var diagnosisObject = try XCTUnwrap(object["conflictDiagnosis"] as? [String: Any])
        diagnosisObject["formatVersion"] = "forged.diagnosis.version"
        object["conflictDiagnosis"] = diagnosisObject
        assertGenericBlock(try JSONDecoder().decode(
            LegacyConversationEligiblePreview.self,
            from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        ))
    }

    func testNondiagnosedPathsAndPrivateSentinelsRemainSanitized() throws {
        let sentinel = "PRIVATE auth/session/source/title/content/path/hash/timestamp"
        for state in [LegacyConversationEligiblePreviewState.empty, .ready, .eligibleEmpty, .blocked, .failed] {
            let preview = LegacyConversationEligiblePreview.sanitized(state)
            XCTAssertNil(preview.conflictDiagnosis)
            XCTAssertFalse(String(describing: preview).contains(sentinel))
        }

        let sourceFiles = [
            "Sources/Cider/Models/LegacyConversationEligiblePreviewModels.swift",
            "Sources/Cider/Services/Conversation/LegacyConversationEligiblePreviewService.swift",
            "Sources/Cider/Services/Conversation/EligibleLegacyAgentRoomsPreviewService.swift",
            "Sources/Cider/Models/AgentRoomsWorkspaceModels.swift",
            "Sources/Cider/Views/AgentRooms/AgentRoomsWorkspaceView.swift",
        ]
        for path in sourceFiles {
            let source = try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
            XCTAssertFalse(source.contains(sentinel))
        }
    }

    func testWorkspaceSourceUsesStructuredReasonsAndExactConflictRowsWithoutStringInference() throws {
        let source = try [
            "Sources/Cider/Models/AgentRoomsWorkspaceModels.swift",
            "Sources/Cider/Services/Conversation/EligibleLegacyAgentRoomsPreviewService.swift",
            "Sources/Cider/Views/AgentRooms/AgentRoomsWorkspaceView.swift",
        ].map {
            try String(contentsOf: repositoryRoot.appendingPathComponent($0), encoding: .utf8)
        }.joined(separator: "\n")
        for required in [
            "Legacy Rooms have an identity conflict",
            "Message record ID conflicts",
            "Message provenance conflicts",
            "Runtime binding conflicts",
            "Historical turn provenance conflicts",
            "Affected registered rooms",
            "Read-only, legacy authoritative, noncanonical preview. No rooms shown. Nothing imported or changed. Messaging disabled.",
        ] {
            XCTAssertTrue(source.contains(required), "Missing conflict UI contract: \(required)")
        }
        XCTAssertFalse(source.contains("message == EligibleLegacyAgentRoomsPreviewService"))
        XCTAssertFalse(source.contains("Button(\"Repair"))
        XCTAssertFalse(source.contains("source selector"))
    }

    private func makeDiagnosis(
        affected: LegacyBoundedCount,
        record: LegacyBoundedCount = .exact(0),
        provenance: LegacyBoundedCount = .exact(0),
        runtime: LegacyBoundedCount = .exact(0),
        turn: LegacyBoundedCount = .exact(0)
    ) -> LegacyCandidateConflictDiagnosis {
        .init(affectedCandidateCount: affected, counts: [
            .init(kind: .messageRecordIdentity, conflictingIdentityGroups: record),
            .init(kind: .messageProvenanceIdentity, conflictingIdentityGroups: provenance),
            .init(kind: .runtimeBindingIdentity, conflictingIdentityGroups: runtime),
            .init(kind: .historicalTurnProvenanceIdentity, conflictingIdentityGroups: turn),
        ])
    }

    private func assertGenericBlock(_ preview: LegacyConversationEligiblePreview) {
        XCTAssertEqual(
            EligibleLegacyAgentRoomsPreviewService(loadPreview: { preview }).loadWorkspace(),
            .eligiblePreviewBlocked(authority: .legacyAuthoritativePreview)
        )
    }

    private func forgePreview(
        _ preview: LegacyConversationEligiblePreview,
        key: String,
        value: Any
    ) throws -> LegacyConversationEligiblePreview {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(preview)) as? [String: Any])
        object[key] = value
        return try JSONDecoder().decode(
            LegacyConversationEligiblePreview.self,
            from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}
