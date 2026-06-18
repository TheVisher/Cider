import Foundation

struct SecondBrainFollowUpProposal: Identifiable, Equatable {
    var id: String { output.id }
    var output: SecondBrainEnrichmentOutput
    var proposalRef: String { "follow_up_proposal:\(output.id)" }
    var intentRef: String { output.metadata["intent_ref"] ?? "" }
    var factRef: String { output.metadata["fact_ref"] ?? "" }
    var candidateRef: String { output.metadata["candidate_ref"] ?? "" }
    var status: String { output.reviewState }
    var owner: SecondBrainOwnerRef { output.owner }
}

struct SecondBrainFollowUpExecutionPreview: Identifiable, Equatable {
    var id: String { "follow_up_execution_preview:\(proposal.id)" }
    var proposal: SecondBrainFollowUpProposal
    var mappedCommandFamily: String
    var mappedCommand: String
    var predictedMutationType: String
    var requiresConfirmation: Bool
    var confirmationPolicy: String
    var dryRun: Bool = true
    var wouldExecute: Bool = false
    var createsReminder: Bool = false
    var createsTodo: Bool = false
    var createsLink: Bool = false
    var createsNag: Bool = false
}

struct SecondBrainFollowUpExecutionResult: Identifiable, Equatable {
    var id: String { "follow_up_execution_result:\(preview.proposal.id)" }
    var preview: SecondBrainFollowUpExecutionPreview
    var status: String = "succeeded"
    var readOnly: Bool = true
    var changed: Bool = false
    var mutationBoundary: String = "existing_safe_command_read_only_execution"
    var executionBoundary: String = "confirmed_existing_safe_command_execution"
    var truthBoundary: String = "execution_result_not_memory_truth"
    var outcomeBoundary: String = "command_outcome_not_memory_truth"
}

@MainActor
final class SecondBrainFollowUpProposalService {
    static let outputKind = "follow_up_proposal"

    enum FollowUpProposalError: LocalizedError, Equatable {
        case missingID
        case notFound(String)
        case wrongKind(proposalID: String, kind: String)
        case missingIntent(String)
        case notAccepted(proposalID: String, status: String)
        case confirmationRequired(proposalID: String)
        case unsupportedExecutionFamily(String)

        var errorDescription: String? {
            switch self {
            case .missingID:
                return "Follow-up proposal id is required."
            case .notFound(let id):
                return "Follow-up proposal '\(id)' was not found."
            case .wrongKind(let proposalID, let kind):
                return "Record '\(proposalID)' is kind \(kind), not follow_up_proposal."
            case .missingIntent(let factID):
                return "Accepted memory fact '\(factID)' has no action intent to propose."
            case .notAccepted(let proposalID, let status):
                return "Follow-up proposal '\(proposalID)' is \(status), not accepted for execution preview."
            case .confirmationRequired(let proposalID):
                return "Follow-up proposal '\(proposalID)' requires explicit execution confirmation."
            case .unsupportedExecutionFamily(let family):
                return "Follow-up proposal execution family '\(family)' is not supported."
            }
        }
    }

    private let outputService: SecondBrainEnrichmentOutputService

    init(outputService: SecondBrainEnrichmentOutputService? = nil, database: CiderDatabase = .shared) {
        self.outputService = outputService ?? SecondBrainEnrichmentOutputService(database: database)
    }

    func create(from fact: SecondBrainAcceptedMemoryFact, actor: String = "cider-cli") throws -> SecondBrainFollowUpProposal {
        guard let intent = SecondBrainAcceptedMemoryFactActionIntentService.intents(for: fact).first else {
            throw FollowUpProposalError.missingIntent(fact.id)
        }
        var metadata: [String: String] = [
            "proposal_kind": "follow_up_action_intent",
            "intent_ref": intent.intentRef,
            "intent_type": intent.intentType,
            "fact_ref": intent.factRef,
            "candidate_ref": intent.candidateRef,
            "source_citation": intent.sourceCitation,
            "proposed_command_family": intent.proposedCommandFamily,
            "proposed_command": intent.proposedCommand,
            "requires_confirmation": String(intent.requiresConfirmation),
            "confirmation_policy": intent.confirmationPolicy,
            "mutation_boundary": "proposal_record_only_no_external_mutation",
            "truth_boundary": "reviewable_follow_up_proposal_not_truth",
            "candidate_boundary": "accepted_fact_action_intent_review_record",
            "creates_reminder": "false",
            "creates_todo": "false",
            "creates_link": "false",
            "creates_nag": "false",
            "created_by": actor,
        ]
        metadata["source_refs"] = DatabaseHelpers.encodeJSON(intent.sourceRefs) ?? "[]"
        metadata["evidence_refs"] = DatabaseHelpers.encodeJSON(intent.evidenceRefs) ?? "[]"
        metadata["safe_next_commands"] = DatabaseHelpers.encodeJSON(intent.safeNextCommands) ?? "[]"
        metadata["safe_verification_commands"] = DatabaseHelpers.encodeJSON(intent.safeVerificationCommands) ?? "[]"

        let now = Date()
        let output = SecondBrainEnrichmentOutput(
            owner: intent.owner,
            chunkID: nil,
            kind: Self.outputKind,
            value: intent.reason,
            normalizedValue: intent.intentRef,
            label: "Follow-up proposal",
            evidence: intent.explanation,
            source: "accepted_memory_action_intent.\(intent.intentType)",
            confidence: 0.82,
            reviewState: "suggested",
            metadata: metadata,
            createdAt: now,
            updatedAt: now
        )
        try outputService.record(output)
        return SecondBrainFollowUpProposal(output: output)
    }

    func list(statuses: Set<String>? = nil, limit: Int = 50) throws -> [SecondBrainFollowUpProposal] {
        let capped = max(0, limit)
        guard capped > 0 else { return [] }
        return try outputService.outputs(kind: Self.outputKind, reviewStates: statuses, limit: capped)
            .map { SecondBrainFollowUpProposal(output: $0) }
    }

    func inspect(_ rawID: String?) throws -> SecondBrainFollowUpProposal {
        let id = try normalizedProposalID(rawID)
        guard let output = try outputService.output(id: id) else {
            throw FollowUpProposalError.notFound(id)
        }
        guard output.kind == Self.outputKind else {
            throw FollowUpProposalError.wrongKind(proposalID: id, kind: output.kind)
        }
        return SecondBrainFollowUpProposal(output: output)
    }

    func transition(_ rawID: String?, status: String, actor: String = "cider-cli") throws -> SecondBrainFollowUpProposal {
        var proposal = try inspect(rawID)
        let now = Date()
        proposal.output.reviewState = status
        proposal.output.updatedAt = now
        proposal.output.metadata["reviewed_by"] = actor
        proposal.output.metadata["reviewed_at"] = ISO8601DateFormatter().string(from: now)
        proposal.output.metadata["proposal_lifecycle_action"] = status
        try outputService.record(proposal.output)
        return proposal
    }

    func preview(_ rawID: String?) throws -> SecondBrainFollowUpExecutionPreview {
        let proposal = try inspect(rawID)
        guard proposal.status == "accepted" else {
            throw FollowUpProposalError.notAccepted(proposalID: proposal.id, status: proposal.status)
        }
        return Self.preview(for: proposal)
    }

    func previews(limit: Int = 50) throws -> [SecondBrainFollowUpExecutionPreview] {
        try list(statuses: ["accepted"], limit: limit).map { Self.preview(for: $0) }
    }

    func execute(_ rawID: String?, confirmed: Bool, confirmationToken: String?) throws -> SecondBrainFollowUpExecutionResult {
        let preview = try self.preview(rawID)
        return try Self.executionResult(for: preview, confirmed: confirmed, confirmationToken: confirmationToken)
    }

    static func executionResult(
        for preview: SecondBrainFollowUpExecutionPreview,
        confirmed: Bool,
        confirmationToken: String?
    ) throws -> SecondBrainFollowUpExecutionResult {
        guard preview.mappedCommandFamily == "recall_context" else {
            throw FollowUpProposalError.unsupportedExecutionFamily(preview.mappedCommandFamily)
        }
        guard confirmed, confirmationToken == "execute:\(preview.proposal.id)" else {
            throw FollowUpProposalError.confirmationRequired(proposalID: preview.proposal.id)
        }
        return SecondBrainFollowUpExecutionResult(preview: preview)
    }

    static func preview(for proposal: SecondBrainFollowUpProposal) -> SecondBrainFollowUpExecutionPreview {
        let family = proposal.output.metadata["proposed_command_family"] ?? "recall_context"
        let command = proposal.output.metadata["proposed_command"] ?? "cider-cli item recall-context --item \(proposal.owner.ownerType) \(proposal.owner.ownerID) --json"
        let predictedMutation: String
        switch family {
        case "recall_context":
            predictedMutation = "none_read_only_context_review"
        case "reminder", "todo", "link", "nag":
            predictedMutation = "requires_confirmed_\(family)_mutation"
        default:
            predictedMutation = "unknown_requires_confirmation"
        }
        return SecondBrainFollowUpExecutionPreview(
            proposal: proposal,
            mappedCommandFamily: family,
            mappedCommand: command,
            predictedMutationType: predictedMutation,
            requiresConfirmation: proposal.output.metadata["requires_confirmation"] != "false",
            confirmationPolicy: proposal.output.metadata["confirmation_policy"] ?? "explicit_existing_command_required"
        )
    }

    static func normalizedProposalID(_ rawID: String?) throws -> String {
        guard let rawID else { throw FollowUpProposalError.missingID }
        let trimmed = rawID
            .replacingOccurrences(of: "follow_up_proposal:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FollowUpProposalError.missingID }
        return trimmed
    }

    private func normalizedProposalID(_ rawID: String?) throws -> String {
        try Self.normalizedProposalID(rawID)
    }
}
