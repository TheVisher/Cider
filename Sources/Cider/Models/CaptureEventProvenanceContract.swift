import Foundation

public enum CaptureEventProvenanceContract {
    public enum Outcome: String, CaseIterable {
        case completed
        case skipped
        case failed
        case cancelled
    }

    static let markerKeys = [
        "capture_schema_version",
        "capture_version",
        "capture_outcome",
    ]

    public static func metadata(
        merging metadata: [String: String] = [:],
        outcome: Outcome
    ) -> [String: String] {
        var result = metadata
        result["capture_schema_version"] = "1"
        result["capture_version"] = "1"
        result["capture_outcome"] = outcome.rawValue
        return result
    }
}
