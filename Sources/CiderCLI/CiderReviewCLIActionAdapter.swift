import Foundation
@testable import Cider

struct CiderReviewCLIActionAdapterResult {
    var request: CiderReviewActionRequest
    var outcome: CiderReviewActionOutcome
    var before: SecondBrainEnrichmentOutput
    var after: SecondBrainEnrichmentOutput
    var queueItem: CiderReviewQueueItem?
    var expectedVersionSelector: String
    var canonicalReceipt: SecondBrainActionReceiptRecord?
    var canonicalRelation: SecondBrainRelation?

    var safeVerificationCommands: [String] {
        canonicalReceipt?.safeVerificationCommands ?? [inspectCommand]
    }

    var safeNextCommands: [String] {
        canonicalReceipt?.safeNextCommands ?? [
            inspectCommand,
            "cider-cli capture review-queue --kind \(request.identity.family.rawValue) --include-deferred --json",
        ]
    }

    var inspectCommand: String {
        let candidateID = request.identity.candidateRef.split(separator: ":", maxSplits: 1).last.map(String.init) ?? before.id
        switch request.identity.family {
        case .graphCandidate:
            return "cider-cli item graph-candidate \(candidateID) --json"
        default:
            return "cider-cli item memory-facts inspect \(candidateID) --json"
        }
    }

    func coordinatorOutcomeDictionary() -> [String: Any] {
        var dictionary: [String: Any] = [
            "surface": outcome.surface.rawValue,
            "candidateRef": outcome.identity.candidateRef,
            "reviewFamily": outcome.identity.family.rawValue,
            "action": outcome.action.rawValue,
            "actor": outcome.actor,
            "availability": availabilityString,
            "evidenceRequirement": outcome.exactEvidenceRequirement.rawValue,
            "evidenceStatus": outcome.evidenceStatus.rawValue,
            "mutationAuthority": outcome.mutationAuthority.rawValue,
            "readOnly": false,
            "changed": outcome.changed,
            "reviewState": outcome.resultingReviewState,
            "truthBoundary": outcome.truthBoundary,
            "expectedVersionSelector": expectedVersionSelector,
        ]
        if let receiptID = outcome.actionReceiptID {
            dictionary["actionReceiptID"] = receiptID
        }
        if let targetOwnerRef = outcome.targetOwnerRef {
            dictionary["targetOwnerRef"] = targetOwnerRef
        }
        if let error = outcome.error {
            dictionary["errorClassification"] = error.classification.rawValue
        }
        return dictionary
    }

    private var availabilityString: String {
        switch outcome.availability {
        case .available:
            return "available"
        case .unavailable:
            return "unavailable"
        }
    }
}

enum CiderReviewCLIActionAdapterError: LocalizedError, Equatable {
    case malformedExpectedVersion
    case candidateUnavailable
    case unsupportedFamily(String)

    var errorDescription: String? {
        switch self {
        case .malformedExpectedVersion:
            return "The expected candidate version selector is invalid. Refresh the candidate and use the exact emitted selector."
        case .candidateUnavailable:
            return "This suggestion is no longer available. Refresh the review list; nothing was changed."
        case .unsupportedFamily:
            return "This suggestion family is not available through the shared CLI review action. Nothing was changed."
        }
    }

    var classification: CiderReviewActionErrorClassification {
        switch self {
        case .malformedExpectedVersion: .staleExpectedVersion
        case .candidateUnavailable: .candidateUnavailable
        case .unsupportedFamily: .unsupportedFamily
        }
    }
}

@MainActor
struct CiderReviewCLIActionAdapter {
    private let database: CiderDatabase
    private let outputService: SecondBrainEnrichmentOutputService
    private let coordinator: CiderReviewActionCoordinator

    init(database: CiderDatabase = .shared) {
        self.database = database
        outputService = SecondBrainEnrichmentOutputService(database: database)
        coordinator = CiderReviewActionCoordinator(database: database)
    }

    func perform(
        candidateRef rawCandidateRef: String,
        family requestedFamily: CiderReviewCandidateFamily? = nil,
        action: CiderReviewAction,
        correction: String? = nil,
        targetOptionRef: String? = nil,
        reason: String? = nil,
        actor: String,
        expectedVersionSelector: String? = nil
    ) throws -> CiderReviewCLIActionAdapterResult {
        let rawID = rawCandidateRef.split(separator: ":", maxSplits: 1).last.map(String.init) ?? rawCandidateRef
        guard !rawID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let before = try outputService.output(id: rawID) else {
            throw CiderReviewCLIActionAdapterError.candidateUnavailable
        }
        let family = requestedFamily ?? CiderReviewCandidateFamily(rawValue: before.kind)
        guard family == .graphCandidate || family == .memoryCandidate else {
            throw CiderReviewCLIActionAdapterError.unsupportedFamily(before.kind)
        }
        guard before.kind == family.rawValue else {
            throw CiderReviewCLIActionAdapterError.unsupportedFamily(before.kind)
        }

        let currentQueueItem = try CiderReviewQueueService(database: database)
            .list(limit: Int.max, includeDeferred: true)
            .items
            .first { $0.candidateRef == "\(family.rawValue):\(before.id)" }
        let expectedVersion: CiderReviewExpectedVersion
        let emittedSelector: String
        if let expectedVersionSelector {
            guard let decoded = Self.decodeExpectedVersionSelector(expectedVersionSelector) else {
                throw CiderReviewCLIActionAdapterError.malformedExpectedVersion
            }
            expectedVersion = decoded
            emittedSelector = expectedVersionSelector
        } else {
            expectedVersion = .init(reviewState: before.reviewState, updatedAt: before.updatedAt)
            emittedSelector = Self.expectedVersionSelector(reviewState: before.reviewState, updatedAt: before.updatedAt)
        }
        let request = CiderReviewActionRequest(
            identity: .init(candidateRef: "\(family.rawValue):\(before.id)", family: family),
            expectedVersion: expectedVersion,
            action: action,
            correction: correction,
            targetOptionRef: targetOptionRef,
            reason: reason,
            actor: actor,
            surface: .cli,
            exactEvidenceRequirement: .required,
            mutationAuthority: .reviewApprovedCandidate
        )
        let outcome = coordinator.perform(request)
        let after = (try outputService.output(id: before.id)) ?? before
        let receipt = try outcome.actionReceiptID.flatMap {
            try SecondBrainActionReceiptLedgerService(database: database).inspect(id: $0)
        }
        let relation = try outcome.targetOwnerRef.flatMap { targetRef in
            try SecondBrainStore(database: database).outgoingRelations(for: after.owner).first { relation in
                relation.targetOwner.canonicalRef == targetRef
                    && relation.metadata["candidate_ref"] == "graph_candidate:\(after.id)"
            }
        }
        return CiderReviewCLIActionAdapterResult(
            request: request,
            outcome: outcome,
            before: before,
            after: after,
            queueItem: currentQueueItem,
            expectedVersionSelector: emittedSelector,
            canonicalReceipt: receipt,
            canonicalRelation: relation
        )
    }

    static func expectedVersionSelector(reviewState: String, updatedAt: Date) -> String {
        "\(reviewState)@\(String(format: "%016llx", updatedAt.timeIntervalSinceReferenceDate.bitPattern))"
    }

    static func decodeExpectedVersionSelector(_ selector: String) -> CiderReviewExpectedVersion? {
        guard let separator = selector.lastIndex(of: "@") else { return nil }
        let reviewState = String(selector[..<separator])
        let bitsText = String(selector[selector.index(after: separator)...])
        guard !reviewState.isEmpty, bitsText.count == 16, let bits = UInt64(bitsText, radix: 16) else { return nil }
        return CiderReviewExpectedVersion(
            reviewState: reviewState,
            updatedAt: Date(timeIntervalSinceReferenceDate: Double(bitPattern: bits))
        )
    }

}
