import Testing
@testable import Cider

@Suite("Capture Event Provenance Contract Tests")
struct CaptureEventProvenanceContractTests {
    @Test("canonical markers are deterministic additive and content free")
    func canonicalMarkersAreDeterministicAdditiveAndContentFree() {
        let existing = [
            "channel_runtime": "matrix",
            "PRIVATE_CAPTURE_SENTINEL": "must remain caller owned",
            "capture_schema_version": "999",
            "capture_version": "PRIVATE_VERSION_SENTINEL",
            "capture_outcome": "PRIVATE_LIFECYCLE_SENTINEL",
        ]

        let first = CaptureEventProvenanceContract.metadata(
            merging: existing,
            outcome: .completed
        )
        let second = CaptureEventProvenanceContract.metadata(
            merging: existing,
            outcome: .completed
        )

        #expect(first == second)
        #expect(first == [
            "channel_runtime": "matrix",
            "PRIVATE_CAPTURE_SENTINEL": "must remain caller owned",
            "capture_schema_version": "1",
            "capture_version": "1",
            "capture_outcome": "completed",
        ])
        for key in CaptureEventProvenanceContract.markerKeys {
            let value = first[key] ?? ""
            #expect(!value.contains("PRIVATE_CAPTURE_SENTINEL"))
            #expect(value.count <= 16)
        }
    }

    @Test("terminal lifecycle outcomes have bounded explicit capability values")
    func terminalLifecycleOutcomesHaveBoundedExplicitCapabilityValues() {
        let outcomes: [(CaptureEventProvenanceContract.Outcome, String)] = [
            (.completed, "completed"),
            (.skipped, "skipped"),
            (.failed, "failed"),
            (.cancelled, "cancelled"),
        ]

        for (outcome, expected) in outcomes {
            let metadata = CaptureEventProvenanceContract.metadata(outcome: outcome)
            #expect(Set(metadata.keys) == Set(CaptureEventProvenanceContract.markerKeys))
            #expect(metadata["capture_schema_version"] == "1")
            #expect(metadata["capture_version"] == "1")
            #expect(metadata["capture_outcome"] == expected)
        }
    }
}
