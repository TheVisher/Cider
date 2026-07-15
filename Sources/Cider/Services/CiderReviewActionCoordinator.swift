import Foundation

struct CiderReviewCandidateFamily: RawRepresentable, Hashable, Sendable {
    var rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static let routingDecision = Self(rawValue: "routing_decision")
    static let enrichment = Self(rawValue: "enrichment")
    static let inboxBacklog = Self(rawValue: "inbox_backlog")
    static let duplicateCandidate = Self(rawValue: "duplicate_candidate")
    static let graphCandidate = Self(rawValue: "graph_candidate")
    static let memoryCandidate = Self(rawValue: "memory_candidate")
    static let eventDateFact = Self(rawValue: "event_date_fact")
    static let bookmarkDateSuggestion = Self(rawValue: "bookmark_date_suggestion")
    static let similarityCandidate = Self(rawValue: "similarity_candidate")
    static let entityResolutionCandidate = Self(rawValue: "entity_resolution_candidate")
    static let factValidityCandidate = Self(rawValue: "fact_validity_candidate")
}

struct CiderReviewCandidateIdentity: Equatable, Sendable {
    var candidateRef: String
    var family: CiderReviewCandidateFamily
}

struct CiderReviewExpectedVersion: Equatable, Sendable {
    var reviewState: String
    var updatedAt: Date
}

enum CiderReviewAction: String, CaseIterable, Equatable, Sendable {
    case approve
    case reject
    case `defer`
    case correct
}

enum CiderReviewMutationAuthority: String, Equatable, Sendable {
    case directUserAction = "direct_user_action"
    case deterministicCanonicalProjection = "deterministic_canonical_projection"
    case reviewApprovedCandidate = "review_approved_candidate"
    case inferredProposal = "inferred_proposal"
}

enum CiderReviewInvokingSurface: String, Equatable, Sendable {
    case home
    case journal
    case reviewQueue = "review_queue"
    case cli
}

enum CiderReviewExactEvidenceRequirement: String, Equatable, Sendable {
    case required
    case notRequired = "not_required"
}

enum CiderReviewExactEvidenceStatus: String, Equatable, Sendable {
    case verifiedExactEvidence = "verified_exact_evidence"
    case missingExactEvidence = "missing_exact_evidence"
    case notChecked = "not_checked"
    case notRequired = "not_required"
}

enum CiderReviewActionErrorClassification: String, Equatable, Sendable {
    case unsupportedFamily = "unsupported_family"
    case unsupportedSurface = "unsupported_surface"
    case unsupportedActionForSurface = "unsupported_action_for_surface"
    case invalidCandidateIdentity = "invalid_candidate_identity"
    case staleExpectedVersion = "stale_expected_version"
    case candidateUnavailable = "candidate_unavailable"
    case alreadyReviewed = "already_reviewed"
    case missingExactEvidence = "missing_exact_evidence"
    case exactEvidenceRequired = "exact_evidence_required"
    case correctionRequired = "correction_required"
    case targetRequired = "target_required"
    case targetUnavailable = "target_unavailable"
    case reviewApprovalRequired = "review_approval_required"
    case databaseFailure = "database_failure"
    case writerFailure = "writer_failure"
}

struct CiderReviewActionFailure: Equatable, Sendable {
    var classification: CiderReviewActionErrorClassification
    var message: String
}

enum CiderReviewActionAvailability: Equatable, Sendable {
    case available
    case unavailable(CiderReviewActionErrorClassification)
}

struct CiderReviewActionRequest: Equatable, Sendable {
    var identity: CiderReviewCandidateIdentity
    var expectedVersion: CiderReviewExpectedVersion
    var action: CiderReviewAction
    var correction: String?
    var targetOptionRef: String?
    var reason: String?
    var actor: String
    var surface: CiderReviewInvokingSurface
    var exactEvidenceRequirement: CiderReviewExactEvidenceRequirement
    var mutationAuthority: CiderReviewMutationAuthority

    init(
        identity: CiderReviewCandidateIdentity,
        expectedVersion: CiderReviewExpectedVersion,
        action: CiderReviewAction,
        correction: String? = nil,
        targetOptionRef: String? = nil,
        reason: String? = nil,
        actor: String,
        surface: CiderReviewInvokingSurface,
        exactEvidenceRequirement: CiderReviewExactEvidenceRequirement,
        mutationAuthority: CiderReviewMutationAuthority
    ) {
        self.identity = identity
        self.expectedVersion = expectedVersion
        self.action = action
        self.correction = correction
        self.targetOptionRef = targetOptionRef
        self.reason = reason
        self.actor = actor
        self.surface = surface
        self.exactEvidenceRequirement = exactEvidenceRequirement
        self.mutationAuthority = mutationAuthority
    }
}

struct CiderReviewActionOutcome: Equatable, Sendable {
    var identity: CiderReviewCandidateIdentity
    var action: CiderReviewAction
    var actor: String
    var surface: CiderReviewInvokingSurface
    var availability: CiderReviewActionAvailability
    var exactEvidenceRequirement: CiderReviewExactEvidenceRequirement
    var evidenceStatus: CiderReviewExactEvidenceStatus
    var mutationAuthority: CiderReviewMutationAuthority
    var changed: Bool
    var resultingReviewState: String
    var truthBoundary: String
    var actionReceiptID: String?
    var targetOwnerRef: String?
    var message: String
    var error: CiderReviewActionFailure?

    var isSuccessful: Bool { error == nil }

    func isSemanticallyEquivalentMutation(to other: Self) -> Bool {
        identity == other.identity
            && action == other.action
            && actor == other.actor
            && availability == other.availability
            && exactEvidenceRequirement == other.exactEvidenceRequirement
            && evidenceStatus == other.evidenceStatus
            && mutationAuthority == other.mutationAuthority
            && changed == other.changed
            && resultingReviewState == other.resultingReviewState
            && truthBoundary == other.truthBoundary
            && actionReceiptID == other.actionReceiptID
            && targetOwnerRef == other.targetOwnerRef
            && error == other.error
    }
}

@MainActor
final class CiderReviewActionCoordinator {
    typealias MutationBoundary = @MainActor (
        JournalIntelligenceReviewActionRequest,
        String
    ) throws -> JournalIntelligenceReviewActionOutcome

    private let performMutation: MutationBoundary

    init(database: CiderDatabase = .shared) {
        let service = JournalIntelligenceReviewActionService(database: database)
        performMutation = { request, actor in
            try service.perform(request, actor: actor)
        }
    }

    init(_ performMutation: @escaping MutationBoundary) {
        self.performMutation = performMutation
    }

    func perform(_ request: CiderReviewActionRequest) -> CiderReviewActionOutcome {
        if let failure = preflightFailure(for: request) {
            return failedOutcome(request, failure: failure)
        }

        do {
            let delegated = try performMutation(
                JournalIntelligenceReviewActionRequest(
                    candidateRef: request.identity.candidateRef,
                    family: request.identity.family.rawValue,
                    expectedReviewState: request.expectedVersion.reviewState,
                    expectedUpdatedAt: request.expectedVersion.updatedAt,
                    action: request.action.journalAction,
                    correctedValue: request.correction,
                    targetOptionRef: request.targetOptionRef,
                    reason: request.reason
                ),
                request.actor
            )
            return CiderReviewActionOutcome(
                identity: request.identity,
                action: request.action,
                actor: request.actor,
                surface: request.surface,
                availability: .available,
                exactEvidenceRequirement: request.exactEvidenceRequirement,
                evidenceStatus: .verifiedExactEvidence,
                mutationAuthority: request.mutationAuthority,
                changed: delegated.changed,
                resultingReviewState: delegated.reviewState,
                truthBoundary: delegated.truthBoundary,
                actionReceiptID: delegated.actionReceiptID,
                targetOwnerRef: delegated.targetOwnerRef,
                message: delegated.message,
                error: nil
            )
        } catch {
            return failedOutcome(request, failure: Self.failure(from: error))
        }
    }

    private func preflightFailure(for request: CiderReviewActionRequest) -> CiderReviewActionFailure? {
        guard request.mutationAuthority == .reviewApprovedCandidate else {
            return failure(.reviewApprovalRequired)
        }
        guard request.surface == .home || request.surface == .journal || request.surface == .cli else {
            return failure(.unsupportedSurface)
        }
        guard request.identity.family == .memoryCandidate || request.identity.family == .graphCandidate else {
            return failure(.unsupportedFamily)
        }
        guard request.identity.candidateRef.hasPrefix("\(request.identity.family.rawValue):"),
              request.identity.candidateRef.count > request.identity.family.rawValue.count + 1 else {
            return failure(.invalidCandidateIdentity)
        }
        guard request.exactEvidenceRequirement == .required else {
            return failure(.exactEvidenceRequired)
        }
        if request.surface == .home, request.action == .correct {
            return failure(.unsupportedActionForSurface)
        }
        if request.identity.family == .memoryCandidate,
           request.action == .correct,
           request.correction?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            return failure(.correctionRequired)
        }
        if request.identity.family == .graphCandidate,
           (request.action == .approve || request.action == .correct),
           request.targetOptionRef?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            return failure(.targetRequired)
        }
        return nil
    }

    private func failedOutcome(
        _ request: CiderReviewActionRequest,
        failure: CiderReviewActionFailure
    ) -> CiderReviewActionOutcome {
        CiderReviewActionOutcome(
            identity: request.identity,
            action: request.action,
            actor: request.actor,
            surface: request.surface,
            availability: .unavailable(failure.classification),
            exactEvidenceRequirement: request.exactEvidenceRequirement,
            evidenceStatus: failure.classification == .missingExactEvidence ? .missingExactEvidence : .notChecked,
            mutationAuthority: request.mutationAuthority,
            changed: false,
            resultingReviewState: request.expectedVersion.reviewState,
            truthBoundary: "reviewable_candidate_not_truth",
            actionReceiptID: nil,
            targetOwnerRef: nil,
            message: failure.message,
            error: failure
        )
    }

    private func failure(_ classification: CiderReviewActionErrorClassification) -> CiderReviewActionFailure {
        Self.failure(classification)
    }

    private static func failure(from error: Error) -> CiderReviewActionFailure {
        if let error = error as? JournalIntelligenceReviewActionError {
            switch error {
            case .unsupportedFamily:
                return failure(.unsupportedFamily)
            case .malformedCandidateRef, .wrongCandidateFamily:
                return failure(.invalidCandidateIdentity)
            case .missingCandidate:
                return failure(.candidateUnavailable)
            case .staleCandidate:
                return failure(.staleExpectedVersion)
            case .alreadyReviewed:
                return failure(.alreadyReviewed)
            case .missingSourceEvidence:
                return failure(.missingExactEvidence)
            case .correctionRequired:
                return failure(.correctionRequired)
            case .targetRequired:
                return failure(.targetRequired)
            case .targetUnavailable:
                return failure(.targetUnavailable)
            }
        }
        if error is CiderDatabaseError {
            return failure(.databaseFailure)
        }
        if let routingError = error as? CiderRoutingDecisionError,
           case .databaseUnavailable = routingError {
            return failure(.databaseFailure)
        }
        return failure(.writerFailure)
    }

    private static func failure(_ classification: CiderReviewActionErrorClassification) -> CiderReviewActionFailure {
        CiderReviewActionFailure(classification: classification, message: message(for: classification))
    }

    private static func message(for classification: CiderReviewActionErrorClassification) -> String {
        switch classification {
        case .unsupportedFamily:
            return "This suggestion family is not available through the shared review action yet. Nothing was changed."
        case .unsupportedSurface:
            return "This review surface is not connected to the shared action yet. Nothing was changed."
        case .unsupportedActionForSurface:
            return "This action is not available here yet. Open Journal Review for the full correction flow."
        case .invalidCandidateIdentity:
            return "This suggestion identity is no longer valid. Refresh the review list; nothing was changed."
        case .staleExpectedVersion:
            return "This suggestion changed after it loaded. Refresh the review list before acting."
        case .candidateUnavailable:
            return "This suggestion is no longer available. Refresh the review list; nothing was changed."
        case .alreadyReviewed:
            return "This suggestion was already reviewed. Refresh to see its current state."
        case .missingExactEvidence:
            return "Cider could not verify the exact source evidence, so the action was blocked."
        case .exactEvidenceRequired:
            return "This review action requires exact source evidence. Nothing was changed."
        case .correctionRequired:
            return "Enter explicit corrected wording before saving this correction."
        case .targetRequired:
            return "Choose the exact target in Journal Review before approving or correcting this link."
        case .targetUnavailable:
            return "That target is no longer available. Refresh Journal Review and choose again."
        case .reviewApprovalRequired:
            return "Inferred proposals must remain in review until a user explicitly approves them."
        case .databaseFailure:
            return "Cider could not safely update this suggestion. Nothing was changed; try again after reopening the review list."
        case .writerFailure:
            return "Cider could not complete this review action. Nothing was changed; refresh and try again."
        }
    }
}

private extension CiderReviewAction {
    var journalAction: JournalIntelligenceReviewAction {
        switch self {
        case .approve: .approve
        case .reject: .reject
        case .defer: .defer
        case .correct: .correct
        }
    }
}
