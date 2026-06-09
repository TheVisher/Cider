import Foundation

struct SecondBrainEnrichmentOutput: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var owner: SecondBrainOwnerRef
    var chunkID: String?
    var kind: String
    var value: String
    var normalizedValue: String
    var label: String
    var evidence: String
    var source: String
    var confidence: Double?
    var reviewState: String = "suggested"
    var metadata: [String: String] = [:]
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

struct SecondBrainEnrichmentRebuildResult: Codable, Equatable {
    var owner: SecondBrainOwnerRef
    var outputCount: Int
    var kindCounts: [String: Int]
}

@MainActor
final class SecondBrainEnrichmentOutputService {
    private let database: CiderDatabase

    init(database: CiderDatabase = .shared) {
        self.database = database
    }

    func outputs(for owner: SecondBrainOwnerRef) throws -> [SecondBrainEnrichmentOutput] {
        let stmt = try database.prepare("""
            SELECT id, chunk_id, kind, value, normalized_value, label, evidence,
                   source, confidence, review_state, metadata, created_at, updated_at
            FROM enrichment_outputs
            WHERE owner_type = ? AND owner_id = ?
            ORDER BY kind COLLATE NOCASE ASC, confidence DESC, value COLLATE NOCASE ASC;
            """)
        stmt.bind(owner.ownerType, at: 1)
            .bind(owner.ownerID, at: 2)

        var outputs: [SecondBrainEnrichmentOutput] = []
        while try stmt.step() {
            outputs.append(output(from: stmt, owner: owner))
        }
        return outputs
    }

    func rebuildFromChunks(owner: SecondBrainOwnerRef) throws -> SecondBrainEnrichmentRebuildResult {
        let chunks = try chunks(for: owner)
        var outputs: [SecondBrainEnrichmentOutput] = []
        for chunk in chunks {
            outputs.append(contentsOf: extractOutputs(owner: owner, chunk: chunk))
        }

        try replaceOutputs(owner: owner, sourcePrefix: "chunk_enrichment.", with: outputs)
        return SecondBrainEnrichmentRebuildResult(
            owner: owner,
            outputCount: outputs.count,
            kindCounts: Dictionary(grouping: outputs, by: \.kind).mapValues(\.count)
        )
    }

    func replaceOutputs(
        owner: SecondBrainOwnerRef,
        sourcePrefix: String,
        with outputs: [SecondBrainEnrichmentOutput]
    ) throws {
        try database.withTransaction {
            let escapedPrefix = sourcePrefix
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            let deleteStmt = try database.prepare("""
                DELETE FROM enrichment_outputs
                WHERE owner_type = ?
                  AND owner_id = ?
                  AND source LIKE ? ESCAPE '\\';
                """)
            deleteStmt.bind(owner.ownerType, at: 1)
                .bind(owner.ownerID, at: 2)
                .bind("\(escapedPrefix)%", at: 3)
            try deleteStmt.step()

            for output in outputs {
                try record(output)
            }
        }
    }

    func record(_ output: SecondBrainEnrichmentOutput) throws {
        let now = Date()
        let createdAt = DatabaseHelpers.encode(output.createdAt)
        let updatedAt = DatabaseHelpers.encode(output.updatedAt > output.createdAt ? output.updatedAt : now)
        let metadata = DatabaseHelpers.encodeJSON(output.metadata) ?? "{}"
        let stmt = try database.prepare("""
            INSERT INTO enrichment_outputs (
                id, owner_type, owner_id, chunk_id, kind, value, normalized_value,
                label, evidence, source, confidence, review_state, metadata, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(owner_type, owner_id, kind, normalized_value, source)
            DO UPDATE SET
                chunk_id = excluded.chunk_id,
                value = excluded.value,
                label = excluded.label,
                evidence = excluded.evidence,
                confidence = excluded.confidence,
                review_state = excluded.review_state,
                metadata = excluded.metadata,
                updated_at = excluded.updated_at;
            """)
        stmt.bind(output.id, at: 1)
            .bind(output.owner.ownerType, at: 2)
            .bind(output.owner.ownerID, at: 3)
            .bind(output.chunkID, at: 4)
            .bind(output.kind, at: 5)
            .bind(output.value, at: 6)
            .bind(output.normalizedValue, at: 7)
            .bind(output.label, at: 8)
            .bind(output.evidence, at: 9)
            .bind(output.source, at: 10)
            .bind(output.confidence, at: 11)
            .bind(output.reviewState, at: 12)
            .bind(metadata, at: 13)
            .bind(createdAt, at: 14)
            .bind(updatedAt, at: 15)
        try stmt.step()
    }

    private struct ChunkSource {
        var id: String
        var title: String
        var body: String
        var source: String
    }

    private func chunks(for owner: SecondBrainOwnerRef) throws -> [ChunkSource] {
        let stmt = try database.prepare("""
            SELECT id, title, body, source
            FROM content_chunks
            WHERE owner_type = ? AND owner_id = ?
            ORDER BY chunk_index ASC;
            """)
        stmt.bind(owner.ownerType, at: 1)
            .bind(owner.ownerID, at: 2)

        var chunks: [ChunkSource] = []
        while try stmt.step() {
            chunks.append(ChunkSource(id: stmt.string(at: 0), title: stmt.string(at: 1), body: stmt.string(at: 2), source: stmt.string(at: 3)))
        }
        return chunks
    }

    private func extractOutputs(owner: SecondBrainOwnerRef, chunk: ChunkSource) -> [SecondBrainEnrichmentOutput] {
        var outputs: [SecondBrainEnrichmentOutput] = []
        outputs.append(contentsOf: detectLinks(owner: owner, chunk: chunk))
        outputs.append(contentsOf: detectDates(owner: owner, chunk: chunk))
        outputs.append(contentsOf: detectHashtagTopics(owner: owner, chunk: chunk))
        outputs.append(contentsOf: detectEntityCandidates(owner: owner, chunk: chunk))
        return uniqueOutputs(outputs)
    }

    private func detectLinks(owner: SecondBrainOwnerRef, chunk: ChunkSource) -> [SecondBrainEnrichmentOutput] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let text = chunk.body
        let nsText = text as NSString
        let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) ?? []
        return matches.compactMap { match in
            guard let url = match.url?.absoluteString else { return nil }
            return output(owner: owner, chunk: chunk, kind: "link", value: url, label: match.url?.host ?? "URL", evidenceRange: match.range, confidence: 0.95)
        }
    }

    private func detectDates(owner: SecondBrainOwnerRef, chunk: ChunkSource) -> [SecondBrainEnrichmentOutput] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let text = chunk.body
        let nsText = text as NSString
        let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) ?? []
        return matches.compactMap { match in
            guard let date = match.date else { return nil }
            let value = ISO8601DateFormatter().string(from: date)
            return output(owner: owner, chunk: chunk, kind: "date", value: value, label: "Detected date", evidenceRange: match.range, confidence: 0.74)
        }
    }

    private func detectHashtagTopics(owner: SecondBrainOwnerRef, chunk: ChunkSource) -> [SecondBrainEnrichmentOutput] {
        regexMatches(pattern: "#([A-Za-z][A-Za-z0-9_-]{2,})", in: chunk.body).compactMap { match in
            guard let topic = match.captures.first else { return nil }
            return output(owner: owner, chunk: chunk, kind: "topic", value: topic, label: "Hashtag topic", evidenceRange: match.range, confidence: 0.86)
        }
    }

    private func detectEntityCandidates(owner: SecondBrainOwnerRef, chunk: ChunkSource) -> [SecondBrainEnrichmentOutput] {
        regexMatches(pattern: "\\b([A-Z][a-z]+(?:\\s+[A-Z][a-z]+){1,3})\\b", in: chunk.body).compactMap { match in
            guard let rawValue = match.captures.first,
                  let value = entityCandidate(from: rawValue) else { return nil }
            return output(owner: owner, chunk: chunk, kind: "entity", value: value, label: "Name candidate", evidenceRange: match.range, confidence: 0.62)
        }
    }

    private func entityCandidate(from rawValue: String) -> String? {
        var words = rawValue.split(separator: " ").map(String.init)
        while let first = words.first, entityLeadStopwords.contains(first) {
            words.removeFirst()
        }

        let value = words.joined(separator: " ")
        guard words.count >= 2,
              !entityLeadStopwords.contains(value) else { return nil }
        return value
    }

    private var entityLeadStopwords: Set<String> {
        ["Content", "Details", "Meet", "Met", "Notes", "Read", "See", "Summary", "Title", "URL"]
    }

    private struct RegexMatch {
        var range: NSRange
        var captures: [String]
    }

    private func regexMatches(pattern: String, in text: String) -> [RegexMatch] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).map { match in
            let captures = (1..<match.numberOfRanges).compactMap { index -> String? in
                let range = match.range(at: index)
                guard range.location != NSNotFound else { return nil }
                return nsText.substring(with: range)
            }
            return RegexMatch(range: match.range, captures: captures)
        }
    }

    private func output(
        owner: SecondBrainOwnerRef,
        chunk: ChunkSource,
        kind: String,
        value: String,
        label: String,
        evidenceRange: NSRange,
        confidence: Double
    ) -> SecondBrainEnrichmentOutput {
        let nsText = chunk.body as NSString
        let evidence = snippet(range: evidenceRange, in: nsText)
        return SecondBrainEnrichmentOutput(
            owner: owner,
            chunkID: chunk.id,
            kind: kind,
            value: value,
            normalizedValue: normalized(value),
            label: label,
            evidence: evidence,
            source: "chunk_enrichment.\(chunk.source)",
            confidence: confidence,
            reviewState: "suggested",
            metadata: ["chunk_title": chunk.title]
        )
    }

    private func snippet(range: NSRange, in text: NSString) -> String {
        let lower = max(0, range.location - 80)
        let upper = min(text.length, range.location + range.length + 80)
        return text.substring(with: NSRange(location: lower, length: upper - lower))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalized(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func uniqueOutputs(_ outputs: [SecondBrainEnrichmentOutput]) -> [SecondBrainEnrichmentOutput] {
        var seen = Set<String>()
        var result: [SecondBrainEnrichmentOutput] = []
        for output in outputs {
            let key = "\(output.kind)|\(output.normalizedValue)|\(output.source)"
            guard seen.insert(key).inserted else { continue }
            result.append(output)
        }
        return result
    }

    private func output(from stmt: SQLStatement, owner: SecondBrainOwnerRef) -> SecondBrainEnrichmentOutput {
        SecondBrainEnrichmentOutput(
            id: stmt.string(at: 0),
            owner: owner,
            chunkID: stmt.optionalString(at: 1),
            kind: stmt.string(at: 2),
            value: stmt.string(at: 3),
            normalizedValue: stmt.string(at: 4),
            label: stmt.string(at: 5),
            evidence: stmt.string(at: 6),
            source: stmt.string(at: 7),
            confidence: stmt.optionalDouble(at: 8),
            reviewState: stmt.string(at: 9),
            metadata: DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 10)) ?? [:],
            createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 11)),
            updatedAt: DatabaseHelpers.decodeDate(stmt.double(at: 12))
        )
    }
}
