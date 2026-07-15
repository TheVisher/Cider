import Foundation

struct JournalCaptureCandidateResult: Equatable {
    enum Status: String, Equatable {
        case suggested
        case none
    }

    var status: Status
    var captureEventID: String
    var journalOwner: SecondBrainOwnerRef
    var textSourceRef: String
    var outputs: [SecondBrainEnrichmentOutput]
    var discardedCount: Int
    var wasReused: Bool
    var wasBounded: Bool

    var reviewRequired: Bool { !outputs.isEmpty }
}

struct JournalCaptureCandidateError: Error, Equatable, LocalizedError {
    enum Code: String, Equatable {
        case sourceUnavailable
        case sourceMismatch
        case incompleteReceipt
        case persistenceFailed
    }

    var code: Code

    var errorDescription: String? {
        switch code {
        case .sourceUnavailable:
            "The committed Journal capture could not be resolved for candidate extraction."
        case .sourceMismatch:
            "Candidate extraction was blocked because the committed Journal source did not match its canonical day."
        case .incompleteReceipt:
            "The committed Journal capture has incomplete candidate state; no new enrichment was claimed."
        case .persistenceFailed:
            "The Journal capture was committed, but its reviewable candidate enrichment could not be completed."
        }
    }
}

/// Capture-time composition for the canonical Journal graph extractor and
/// enrichment-output store. The Journal capture remains the commit boundary;
/// this service may fail afterward without rewriting or rolling back source text.
@MainActor
final class JournalCaptureCandidateService {
    struct Hooks {
        var beforeRecord: @MainActor (SecondBrainEnrichmentOutput) throws -> Void

        init(beforeRecord: @escaping @MainActor (SecondBrainEnrichmentOutput) throws -> Void = { _ in }) {
            self.beforeRecord = beforeRecord
        }
    }

    private struct CaptureSource {
        var id: String
        var text: String
        var metadata: [String: String]
        var createdAt: Date
        var noteID: String
    }

    private static let completionStatusKey = "journal_candidate_extraction_status"
    private static let completionCountKey = "journal_candidate_count"
    private static let completionSourceRefKey = "journal_candidate_source_ref"
    private static let maximumSourceLength = 64_000
    private static let maximumEvidenceLength = 800
    private static let maximumCandidateCount = 32

    private let database: CiderDatabase
    private let outputService: SecondBrainEnrichmentOutputService
    private let extractor: SecondBrainJournalGraphCandidateExtractor
    private let hooks: Hooks

    init(
        database: CiderDatabase = .shared,
        outputService: SecondBrainEnrichmentOutputService? = nil,
        extractor: SecondBrainJournalGraphCandidateExtractor = .init(),
        hooks: Hooks = .init()
    ) {
        self.database = database
        self.outputService = outputService ?? SecondBrainEnrichmentOutputService(database: database)
        self.extractor = extractor
        self.hooks = hooks
    }

    func generate(
        captureEventID: String,
        journalOwner: SecondBrainOwnerRef
    ) throws -> JournalCaptureCandidateResult {
        guard database.isOpen,
              journalOwner.ownerType == "note",
              !captureEventID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw JournalCaptureCandidateError(code: .sourceUnavailable)
        }
        let capture = try loadCapture(id: captureEventID)
        guard capture.noteID == journalOwner.ownerID else {
            throw JournalCaptureCandidateError(code: .sourceMismatch)
        }
        let textSourceRef = "journal_source:journal-text-\(capture.id)"
        let existing = try outputs(for: journalOwner, captureEventID: capture.id)
        if capture.metadata[Self.completionStatusKey] == "complete" {
            let expectedCount = Int(capture.metadata[Self.completionCountKey] ?? "")
            guard expectedCount == existing.count,
                  capture.metadata[Self.completionSourceRefKey] == textSourceRef else {
                throw JournalCaptureCandidateError(code: .incompleteReceipt)
            }
            return result(
                capture: capture,
                owner: journalOwner,
                textSourceRef: textSourceRef,
                outputs: existing,
                discardedCount: Int(capture.metadata["journal_candidate_discarded_count"] ?? "") ?? 0,
                wasReused: true,
                wasBounded: capture.metadata["journal_candidate_was_bounded"] == "true"
            )
        }
        guard existing.isEmpty else {
            throw JournalCaptureCandidateError(code: .incompleteReceipt)
        }
        guard capture.text.count <= Self.maximumSourceLength else {
            throw JournalCaptureCandidateError(code: .persistenceFailed)
        }

        let extraction = extractor.extract(
            sourceOwner: journalOwner,
            rawContent: capture.text,
            date: capture.metadata["date"],
            time: capture.metadata["time"]
        )
        let privacySafe = extraction.outputs.filter(isPrivacySafeAndBounded)
        let sorted = privacySafe.sorted(by: candidateOrder)
        let bounded = Array(sorted.prefix(Self.maximumCandidateCount))
        let outputs = bounded.map {
            captureScopedOutput(
                $0,
                capture: capture,
                owner: journalOwner,
                textSourceRef: textSourceRef
            )
        }
        let discardedCount = extraction.outputs.count - outputs.count

        do {
            try database.withTransaction {
                for output in outputs {
                    try hooks.beforeRecord(output)
                    try outputService.record(output)
                }
                try markComplete(
                    capture: capture,
                    count: outputs.count,
                    textSourceRef: textSourceRef,
                    discardedCount: discardedCount,
                    wasBounded: sorted.count > outputs.count
                )
            }
        } catch {
            throw JournalCaptureCandidateError(code: .persistenceFailed)
        }

        return result(
            capture: capture,
            owner: journalOwner,
            textSourceRef: textSourceRef,
            outputs: outputs,
            discardedCount: discardedCount,
            wasReused: false,
            wasBounded: sorted.count > outputs.count
        )
    }

    private func loadCapture(id: String) throws -> CaptureSource {
        let statement = try database.prepare("""
            SELECT e.source_text, e.metadata, e.created_at, r.target_owner_id
            FROM capture_events e
            JOIN owner_relations r
              ON r.source_owner_type = 'capture_event'
             AND r.source_owner_id = e.id
             AND r.target_owner_type = 'note'
             AND r.relation_type = 'produced_item'
            WHERE e.id = ? AND e.source_kind = 'journal'
            LIMIT 1;
            """)
        statement.bind(id, at: 1)
        guard try statement.step() else {
            throw JournalCaptureCandidateError(code: .sourceUnavailable)
        }
        return CaptureSource(
            id: id,
            text: statement.optionalString(at: 0) ?? "",
            metadata: DatabaseHelpers.decodeJSON([String: String].self, from: statement.optionalString(at: 1)) ?? [:],
            createdAt: DatabaseHelpers.decodeDate(statement.double(at: 2)),
            noteID: statement.string(at: 3)
        )
    }

    private func outputs(
        for owner: SecondBrainOwnerRef,
        captureEventID: String
    ) throws -> [SecondBrainEnrichmentOutput] {
        try outputService.outputs(for: owner)
            .filter {
                ($0.kind == SecondBrainGraphCandidateContract.outputKind || $0.kind == "memory_candidate")
                    && $0.metadata["capture_event_id"] == captureEventID
            }
            .sorted(by: candidateOrder)
    }

    private func captureScopedOutput(
        _ raw: SecondBrainEnrichmentOutput,
        capture: CaptureSource,
        owner: SecondBrainOwnerRef,
        textSourceRef: String
    ) -> SecondBrainEnrichmentOutput {
        var output = raw
        let start = output.metadata["source_span_start"] ?? ""
        let end = output.metadata["source_span_end"] ?? ""
        let identitySeed = [
            "journal-candidate-v1",
            capture.id,
            output.kind,
            output.normalizedValue,
            output.source,
            start,
            end,
            output.metadata[SecondBrainGraphCandidateContract.MetadataKey.candidateKind] ?? "",
            output.metadata[SecondBrainGraphCandidateContract.MetadataKey.objectTypeGuesses] ?? "",
            output.metadata[SecondBrainGraphCandidateContract.MetadataKey.relationGuesses] ?? "",
        ].joined(separator: "|")
        output.id = JournalAtomicCaptureWriter.stableUUID(seed: identitySeed).uuidString
        output.owner = owner
        output.createdAt = capture.createdAt
        output.updatedAt = capture.createdAt
        output.metadata["capture_event_id"] = capture.id
        output.metadata["capture_event_ref"] = "capture_event:\(capture.id)"
        output.metadata[SecondBrainGraphCandidateContract.MetadataKey.sourceOwnerRef] = "capture_event:\(capture.id)"
        output.metadata["journal_note_ref"] = owner.canonicalRef
        output.metadata["journal_source_id"] = "journal-text-\(capture.id)"
        output.metadata["journal_source_ref"] = textSourceRef
        output.metadata["journal_source_kind"] = "text"
        output.metadata["source_coordinate_space"] = "capture_event.source_text"
        output.metadata["captured_at"] = ISO8601DateFormatter().string(from: capture.createdAt)
        output.metadata["extraction_run_id"] = "journal-capture:\(capture.id)"
        output.metadata["extraction_provider"] = "deterministic_local"
        output.metadata["truth_boundary"] = "reviewable_candidate_not_truth"
        if output.kind == "memory_candidate" {
            output.metadata["candidate_ref"] = "memory_candidate:\(output.id)"
        }
        return output
    }

    private func markComplete(
        capture: CaptureSource,
        count: Int,
        textSourceRef: String,
        discardedCount: Int,
        wasBounded: Bool
    ) throws {
        var metadata = capture.metadata
        metadata[Self.completionStatusKey] = "complete"
        metadata[Self.completionCountKey] = String(count)
        metadata[Self.completionSourceRefKey] = textSourceRef
        metadata["journal_candidate_discarded_count"] = String(discardedCount)
        metadata["journal_candidate_was_bounded"] = wasBounded ? "true" : "false"
        let statement = try database.prepare("UPDATE capture_events SET metadata = ? WHERE id = ?;")
        statement.bind(DatabaseHelpers.encodeJSON(metadata) ?? "{}", at: 1)
            .bind(capture.id, at: 2)
        try statement.step()
    }

    private func result(
        capture: CaptureSource,
        owner: SecondBrainOwnerRef,
        textSourceRef: String,
        outputs: [SecondBrainEnrichmentOutput],
        discardedCount: Int,
        wasReused: Bool,
        wasBounded: Bool
    ) -> JournalCaptureCandidateResult {
        JournalCaptureCandidateResult(
            status: outputs.isEmpty ? .none : .suggested,
            captureEventID: capture.id,
            journalOwner: owner,
            textSourceRef: textSourceRef,
            outputs: outputs,
            discardedCount: discardedCount,
            wasReused: wasReused,
            wasBounded: wasBounded
        )
    }

    private func isPrivacySafeAndBounded(_ output: SecondBrainEnrichmentOutput) -> Bool {
        let evidence = output.evidence
        guard !evidence.isEmpty,
              evidence.count <= Self.maximumEvidenceLength,
              !containsPrivatePath(evidence),
              !containsRawTransportShape(evidence),
              !containsCredentialBearingURL(evidence) else {
            return false
        }
        if let canonicalURL = output.metadata["canonical_url"],
           let url = URL(string: canonicalURL) {
            return CiderOpenPolicy.isAllowedUntrustedWebURL(url)
        }
        return true
    }

    private func containsCredentialBearingURL(_ text: String) -> Bool {
        let pattern = #"(?i)\bhttps?://[^\s<>()\[\]]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return true }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).contains { match in
            guard let matchRange = Range(match.range, in: text) else { return true }
            let raw = String(text[matchRange]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
            guard let components = URLComponents(string: raw) else { return true }
            return components.user != nil || components.password != nil || raw.contains("\\")
        }
    }

    private func containsPrivatePath(_ text: String) -> Bool {
        text.range(
            of: #"(?i)(?:file://|(?:^|\s)/(?:Users|private|tmp|var|Volumes)/)"#,
            options: .regularExpression
        ) != nil
    }

    private func containsRawTransportShape(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("content-length:")
            || lower.contains("authorization: bearer")
            || (lower.contains("\"jsonrpc\"") && lower.contains("\"method\""))
    }

    private func candidateOrder(
        _ lhs: SecondBrainEnrichmentOutput,
        _ rhs: SecondBrainEnrichmentOutput
    ) -> Bool {
        let lhsStart = Int(lhs.metadata["source_span_start"] ?? "") ?? Int.max
        let rhsStart = Int(rhs.metadata["source_span_start"] ?? "") ?? Int.max
        if lhsStart != rhsStart { return lhsStart < rhsStart }
        if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
        if lhs.normalizedValue != rhs.normalizedValue { return lhs.normalizedValue < rhs.normalizedValue }
        return lhs.id < rhs.id
    }
}
