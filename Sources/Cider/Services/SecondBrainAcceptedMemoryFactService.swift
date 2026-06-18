import Foundation

struct SecondBrainAcceptedMemoryFact: Identifiable, Equatable {
    var id: String { candidate.id }
    var candidate: SecondBrainEnrichmentOutput

    var factRef: String { "accepted_memory_fact:\(candidate.id)" }
    var candidateRef: String { "memory_candidate:\(candidate.id)" }
    var owner: SecondBrainOwnerRef { candidate.owner }
}

@MainActor
final class SecondBrainAcceptedMemoryFactService {
    enum AcceptedMemoryFactError: LocalizedError, Equatable {
        case missingID
        case notFound(String)
        case notAccepted(candidateID: String, reviewState: String)
        case wrongKind(candidateID: String, kind: String)

        var errorDescription: String? {
            switch self {
            case .missingID:
                return "Accepted memory fact id is required."
            case .notFound(let id):
                return "Accepted memory fact '\(id)' was not found."
            case .notAccepted(let candidateID, let reviewState):
                return "Memory candidate '\(candidateID)' is \(reviewState), not accepted memory truth."
            case .wrongKind(let candidateID, let kind):
                return "Candidate '\(candidateID)' is kind \(kind), not memory_candidate."
            }
        }
    }

    private let outputService: SecondBrainEnrichmentOutputService

    init(outputService: SecondBrainEnrichmentOutputService? = nil, database: CiderDatabase = .shared) {
        self.outputService = outputService ?? SecondBrainEnrichmentOutputService(database: database)
    }

    func list(owner: SecondBrainOwnerRef? = nil, limit: Int = 50) throws -> [SecondBrainAcceptedMemoryFact] {
        let cappedLimit = max(0, limit)
        guard cappedLimit > 0 else { return [] }
        let outputs: [SecondBrainEnrichmentOutput]
        if let owner {
            outputs = try outputService.outputs(for: owner)
                .filter { $0.kind == "memory_candidate" && $0.reviewState == "accepted" }
        } else {
            outputs = try outputService.outputs(kind: "memory_candidate", reviewStates: ["accepted"], limit: cappedLimit)
        }
        return Array(outputs.prefix(cappedLimit)).map { SecondBrainAcceptedMemoryFact(candidate: $0) }
    }

    func inspect(_ rawID: String?) throws -> SecondBrainAcceptedMemoryFact {
        let id = try normalizedFactID(rawID)
        guard let output = try outputService.output(id: id) else {
            throw AcceptedMemoryFactError.notFound(id)
        }
        guard output.kind == "memory_candidate" else {
            throw AcceptedMemoryFactError.wrongKind(candidateID: id, kind: output.kind)
        }
        guard output.reviewState == "accepted" else {
            throw AcceptedMemoryFactError.notAccepted(candidateID: id, reviewState: output.reviewState)
        }
        return SecondBrainAcceptedMemoryFact(candidate: output)
    }

    static func normalizedFactID(_ rawID: String?) throws -> String {
        guard let rawID else { throw AcceptedMemoryFactError.missingID }
        let trimmed = rawID
            .replacingOccurrences(of: "accepted_memory_fact:", with: "")
            .replacingOccurrences(of: "memory_candidate:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AcceptedMemoryFactError.missingID }
        return trimmed
    }

    private func normalizedFactID(_ rawID: String?) throws -> String {
        try Self.normalizedFactID(rawID)
    }
}
