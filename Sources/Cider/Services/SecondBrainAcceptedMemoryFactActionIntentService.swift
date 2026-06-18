import Foundation

struct SecondBrainAcceptedMemoryFactActionIntent: Identifiable, Equatable {
    var id: String
    var intentRef: String { id }
    var factRef: String
    var candidateRef: String
    var owner: SecondBrainOwnerRef
    var intentType: String
    var proposedCommandFamily: String
    var proposedCommand: String
    var reason: String
    var explanation: String
    var sourceCitation: String
    var sourceRefs: [String]
    var evidenceRefs: [String]
    var truthBoundary: String = "accepted_memory_fact"
    var candidateBoundary: String = "reviewable_memory_candidates_excluded"
    var mutationBoundary: String = "read_only_intent_no_mutation"
    var requiresConfirmation: Bool = true
    var confirmationPolicy: String = "explicit_existing_command_required"
    var safeNextCommands: [String]
    var safeVerificationCommands: [String]
}

enum SecondBrainAcceptedMemoryFactActionIntentService {
    static func intents(for facts: [SecondBrainAcceptedMemoryFact], limit: Int = 50) -> [SecondBrainAcceptedMemoryFactActionIntent] {
        Array(facts.flatMap { intents(for: $0) }.prefix(max(0, limit)))
    }

    static func intents(for fact: SecondBrainAcceptedMemoryFact) -> [SecondBrainAcceptedMemoryFactActionIntent] {
        let output = fact.candidate
        let memoryKind = output.metadata["accepted_memory_kind"] ?? output.metadata["memory_kind"] ?? output.metadata["candidate_kind"] ?? "memory"
        let sourceCitation = output.metadata["source_owner_ref"] ?? output.owner.canonicalRef
        let evidenceRef = output.metadata["source_evidence_ref"] ?? "source_evidence:\(output.id)"
        let proposedCommand = "cider-cli item recall-context --item \(output.owner.ownerType) \(output.owner.ownerID) --json"
        let reason = "Accepted memory fact may need a safe follow-up review before any action is taken."
        let safeVerification = [
            "cider-cli item memory-facts inspect \(output.id) --json",
            proposedCommand,
        ]
        let safeNext = [
            proposedCommand,
            "cider-cli item memory-facts resurface --fact \(output.id) --json",
            "cider-cli item action-ledger list --owner \(output.owner.canonicalRef) --json",
        ]
        return [
            SecondBrainAcceptedMemoryFactActionIntent(
                id: "accepted_memory_fact_action_intent:\(output.id):follow_up_review",
                factRef: fact.factRef,
                candidateRef: fact.candidateRef,
                owner: output.owner,
                intentType: "follow_up_review",
                proposedCommandFamily: "recall_context",
                proposedCommand: proposedCommand,
                reason: reason,
                explanation: "This is a read-only action intent derived from accepted memory truth. It suggests inspecting surrounding context and action history, not mutating reminders, links, todos, or review state automatically.",
                sourceCitation: sourceCitation,
                sourceRefs: Array(Set([fact.factRef, fact.candidateRef, output.owner.canonicalRef, sourceCitation])).sorted(),
                evidenceRefs: [evidenceRef],
                safeNextCommands: safeNext,
                safeVerificationCommands: safeVerification
            )
        ].filter { _ in !memoryKind.isEmpty }
    }

    static func intentRefs(for fact: SecondBrainAcceptedMemoryFact) -> [String] {
        intents(for: fact).map(\.intentRef)
    }
}
