import Foundation
import Testing
@testable import Cider

@Suite("Capture Provenance Historical Boundary Tests")
@MainActor
struct CiderCaptureProvenanceHistoricalBoundaryTests {
    private func makeDatabase() throws -> (CiderDatabase, URL) {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-capture-historical-boundary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(".cider"), withIntermediateDirectories: true)
        let database = CiderDatabase()
        try database.open(at: vault.appendingPathComponent(".cider/cider.db"))
        return (database, vault)
    }

    @discardableResult
    private func insertEvent(
        id: UUID,
        metadata: [String: String],
        createdAt: Date,
        into database: CiderDatabase
    ) throws -> UUID {
        try insertEvent(id: id, metadataJSON: DatabaseHelpers.encodeJSON(metadata) ?? "{}", createdAt: createdAt, into: database)
    }

    @discardableResult
    private func insertEvent(
        id: UUID,
        metadataJSON: String,
        createdAt: Date,
        into database: CiderDatabase
    ) throws -> UUID {
        let statement = try database.prepare("""
            INSERT INTO capture_events (
                id, source_kind, surface, channel, channel_id, thread_id, message_id,
                sender_id, sender_name, source_url, source_file, source_text,
                attachment_count, metadata, created_at
            ) VALUES (?, 'text', 'cli', 'local', NULL, NULL, NULL, NULL, NULL,
                      NULL, NULL, 'PRIVATE_CAPTURE_SENTINEL', 0, ?, ?);
            """)
        statement.bind(id.uuidString, at: 1)
            .bind(metadataJSON, at: 2)
            .bind(DatabaseHelpers.encode(createdAt), at: 3)
        try statement.step()
        return id
    }

    private func rowCounts(_ database: CiderDatabase) throws -> [String: Int] {
        var result: [String: Int] = [:]
        for table in ["capture_events", "owner_relations", "items", "mutation_audit", "agent_actions", "action_receipts"] {
            let statement = try database.prepare("SELECT count(*) FROM \(table);")
            _ = try statement.step()
            result[table] = statement.int(at: 0)
        }
        return result
    }

    @Test("mixed source-backed boundaries are deterministic, replayable, and non-mutating")
    func mixedBoundariesAreDeterministicAndNonMutating() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }
        let createdAt = Date(timeIntervalSince1970: 1_767_225_600)
        try insertEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            metadata: [
                "capture_schema_version": "1",
                "app_version": "2.4.0",
                "capture_outcome": "completed",
            ],
            createdAt: createdAt,
            into: database
        )
        try insertEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            metadata: [:],
            createdAt: createdAt,
            into: database
        )
        let before = try rowCounts(database)
        let service = CiderCaptureProvenanceDiagnosticService(database: database)

        let first = try service.aggregateUnresolvedGaps(limit: 20, sampleLimit: 10)
        let second = try service.aggregateUnresolvedGaps(limit: 20, sampleLimit: 10)
        let projection = first.historicalBoundaries

        #expect(try rowCounts(database) == before)
        #expect(first == second)
        #expect(projection.readOnly && !projection.changed)
        #expect(projection.classifiedCount == 2)
        #expect(projection.groups.count == 2)
        #expect(projection.groups.contains {
            $0.schemaMarkerStatus == .found
                && $0.versionMarkerStatus == .found
                && $0.lifecycleMarkerStatus == .found
                && $0.provenanceGuarantee == .activeRelationRequired
                && $0.versionBucket == "2.4.0"
        })
        #expect(projection.groups.contains {
            $0.schemaMarkerStatus == .missing
                && $0.versionMarkerStatus == .missing
                && $0.lifecycleMarkerStatus == .missing
                && $0.provenanceGuarantee == .notEvidenced
        })
        #expect(projection.safeVerificationCommands.first == "cider-cli capture provenance-gap-patterns --limit 20 --sample-limit 10 --json")
        #expect(projection.safeVerificationCommands.dropFirst().allSatisfy {
            $0.hasPrefix("cider-cli capture provenance-gap capture_event:") && $0.hasSuffix(" --json")
        })
        #expect(projection.truthBoundary.contains("no_ownership_inference"))
    }

    @Test("unsafe marker evidence fails closed without exposing private values")
    func unsafeMarkersFailClosedAndRemainContentFree() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }
        let old = Date(timeIntervalSince1970: 1_767_225_600)
        let fixtures: [[String: String]] = [
            ["capture_schema_version": "banana", "capture_outcome": "completed"],
            ["capture_schema_version": "2", "capture_outcome": "completed"],
            ["capture_schema_version": "1", "app_version": "1.0", "appVersion": "2.0", "capture_outcome": "completed"],
            ["capture_schema_version": "1", "app_version": "PRIVATE_VERSION_SENTINEL", "capture_outcome": "completed"],
            ["capture_schema_version": "1", "capture_outcome": "pending"],
            ["capture_schema_version": "1", "capture_outcome": "PRIVATE_LIFECYCLE_SENTINEL"],
        ]
        for (offset, metadata) in fixtures.enumerated() {
            try insertEvent(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", offset + 10))!,
                metadata: metadata,
                createdAt: old,
                into: database
            )
        }
        try insertEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
            metadataJSON: "{not-json",
            createdAt: old,
            into: database
        )

        let report = try CiderCaptureProvenanceDiagnosticService(database: database)
            .aggregateUnresolvedGaps(limit: 20, sampleLimit: 10)
        let projection = report.historicalBoundaries
        let serialized = report.toDictionary().description

        #expect(projection.failClosedCounts["malformed_schema_marker"] == 1)
        #expect(projection.failClosedCounts["unsupported_schema_marker"] == 1)
        #expect(projection.failClosedCounts["ambiguous_version_marker"] == 1)
        #expect(projection.failClosedCounts["privacy_sensitive_version_marker"] == 1)
        #expect(projection.failClosedCounts["stale_lifecycle_marker"] == 1)
        #expect(projection.failClosedCounts["privacy_sensitive_lifecycle_marker"] == 1)
        #expect(projection.failClosedCounts["malformed_capture_metadata"] == 1)
        #expect(projection.groups.allSatisfy { $0.provenanceGuarantee == .notEvidenced })
        for sentinel in ["PRIVATE_CAPTURE_SENTINEL", "PRIVATE_VERSION_SENTINEL", "PRIVATE_LIFECYCLE_SENTINEL"] {
            #expect(!serialized.contains(sentinel))
        }
    }

    @Test("boundary samples and scans are independently capped with explicit saturation")
    func capsAreExplicit() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }
        let createdAt = Date(timeIntervalSince1970: 1_767_225_600)
        for offset in 0..<5 {
            try insertEvent(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", offset + 100))!,
                metadata: ["capture_schema_version": "1", "capture_outcome": "completed"],
                createdAt: createdAt.addingTimeInterval(Double(offset)),
                into: database
            )
        }

        let projection = try CiderCaptureProvenanceDiagnosticService(database: database)
            .aggregateUnresolvedGaps(limit: 2, sampleLimit: 1).historicalBoundaries

        #expect(projection.classifiedCount == 2)
        #expect(projection.sampledCount == 1)
        #expect(projection.groups.flatMap(\.sampleCaptureEventRefs).count == 1)
        let hasTruncatedSamples = projection.groups.contains { $0.sampleRefsTruncated }
        #expect(hasTruncatedSamples)
        #expect(projection.saturated)
        #expect(projection.caps["scanEvents"] == 100)
        #expect(projection.caps["sampleCaptureEventRefs"] == 1)
    }
}
