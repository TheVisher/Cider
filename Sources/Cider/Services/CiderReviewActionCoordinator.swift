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
    case enrich
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
    case destinationRequired = "destination_required"
    case destinationInvalid = "destination_invalid"
    case destinationUnresolved = "destination_unresolved"
    case destinationAmbiguous = "destination_ambiguous"
    case routingUnauthorized = "routing_unauthorized"
    case unsupportedRoutingCorrection = "unsupported_routing_correction"
    case reviewApprovalRequired = "review_approval_required"
    case unauthorizedActor = "unauthorized_actor"
    case schedulingConflict = "scheduling_conflict"
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
    var routingItemID: UUID?
    var routingDestination: CiderRoutingDecisionTarget?
    var bookmarkDateItemID: UUID?
    var bookmarkDateDestination: CiderBookmarkDateSuggestionDestination?
    var bookmarkDateExactEvidence: CiderBookmarkDateSuggestion?
    var enrichmentItemID: UUID?
    var enrichmentBatchContext: CiderBookmarkEnrichmentBatchContext?
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
        routingItemID: UUID? = nil,
        routingDestination: CiderRoutingDecisionTarget? = nil,
        bookmarkDateItemID: UUID? = nil,
        bookmarkDateDestination: CiderBookmarkDateSuggestionDestination? = nil,
        bookmarkDateExactEvidence: CiderBookmarkDateSuggestion? = nil,
        enrichmentItemID: UUID? = nil,
        enrichmentBatchContext: CiderBookmarkEnrichmentBatchContext? = nil,
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
        self.routingItemID = routingItemID
        self.routingDestination = routingDestination
        self.bookmarkDateItemID = bookmarkDateItemID
        self.bookmarkDateDestination = bookmarkDateDestination
        self.bookmarkDateExactEvidence = bookmarkDateExactEvidence
        self.enrichmentItemID = enrichmentItemID
        self.enrichmentBatchContext = enrichmentBatchContext
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
    var routingItemID: UUID?
    var routingDecisionID: UUID?
    var routingDestination: CiderRoutingDecisionTarget?
    var bookmarkDateDestination: CiderBookmarkDateSuggestionDestination?
    var bookmarkDateApprovalAction: CiderBookmarkDateSuggestionApprovalAction?
    var enrichmentQueueDisposition: CiderBookmarkEnrichmentQueueScheduleDisposition? = nil
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
            && routingItemID == other.routingItemID
            && routingDecisionID == other.routingDecisionID
            && routingDestination == other.routingDestination
            && bookmarkDateDestination == other.bookmarkDateDestination
            && bookmarkDateApprovalAction == other.bookmarkDateApprovalAction
            && enrichmentQueueDisposition == other.enrichmentQueueDisposition
            && error == other.error
    }
}

@MainActor
struct CiderEventDateFactReviewActionAdapter {
    private let service: SecondBrainEventDateFactReviewService

    init(database: CiderDatabase) {
        service = SecondBrainEventDateFactReviewService(database: database)
    }

    func perform(_ request: CiderReviewActionRequest) throws -> SecondBrainEventDateFactReviewMutationResult {
        try service.performReviewAction(
            candidateID: request.identity.candidateRef,
            expectedReviewState: request.expectedVersion.reviewState,
            expectedUpdatedAt: request.expectedVersion.updatedAt,
            action: request.action,
            actor: request.actor,
            reason: request.reason
        )
    }
}

@MainActor
struct CiderRoutingDecisionReviewActionAdapter {
    private let service: CiderRoutingDecisionService
    private let bookmarkService: VaultBookmarkService

    init(
        database: CiderDatabase,
        bookmarkService: VaultBookmarkService,
        failureInjector: (@MainActor (CiderRoutingReviewMutationCheckpoint) throws -> Void)? = nil
    ) {
        service = CiderRoutingDecisionService(database: database, failureInjector: failureInjector)
        self.bookmarkService = bookmarkService
    }

    func perform(_ request: CiderReviewActionRequest) throws -> CiderRoutingReviewMutationResult {
        guard let itemID = request.routingItemID,
              let destination = request.routingDestination,
              let separator = request.identity.candidateRef.lastIndex(of: ":"),
              let decisionID = UUID(uuidString: String(request.identity.candidateRef[request.identity.candidateRef.index(after: separator)...])) else {
            throw CiderRoutingReviewActionError.malformedCandidate
        }
        return try service.performReviewAction(
            candidateID: decisionID,
            itemID: itemID,
            expectedReviewState: request.expectedVersion.reviewState,
            expectedCreatedAt: request.expectedVersion.updatedAt,
            action: request.action,
            destination: destination,
            reason: request.reason,
            actor: request.actor,
            bookmarkService: bookmarkService
        )
    }
}

@MainActor
struct CiderBookmarkDateSuggestionReviewActionAdapter {
    private let service: CiderBookmarkDateSuggestionApprovalService

    init(
        database: CiderDatabase,
        bookmarkService: VaultBookmarkService,
        dateCardStorage: DateCardStorage,
        todoStorage: TodoCardStorage,
        failureInjector: (@MainActor (CiderBookmarkDateSuggestionMutationCheckpoint) throws -> Void)? = nil
    ) {
        service = CiderBookmarkDateSuggestionApprovalService(
            database: database,
            bookmarkService: bookmarkService,
            dateCardStorage: dateCardStorage,
            todoStorage: todoStorage,
            failureInjector: failureInjector
        )
    }

    init(service: CiderBookmarkDateSuggestionApprovalService) {
        self.service = service
    }

    func perform(
        _ request: CiderReviewActionRequest
    ) throws -> CiderBookmarkDateSuggestionApprovalMutationResult {
        guard request.action == .approve else {
            throw CiderBookmarkDateSuggestionApprovalError.unsupportedAction
        }
        guard let bookmarkID = request.bookmarkDateItemID else {
            throw CiderBookmarkDateSuggestionApprovalError.invalidCandidateIdentity
        }
        guard let destination = request.bookmarkDateDestination else {
            throw CiderBookmarkDateSuggestionApprovalError.destinationRequired
        }
        guard let exactEvidence = request.bookmarkDateExactEvidence else {
            throw CiderBookmarkDateSuggestionApprovalError.missingExactEvidence
        }
        return try service.perform(
            CiderBookmarkDateSuggestionApprovalRequest(
                candidateRef: request.identity.candidateRef,
                bookmarkID: bookmarkID,
                expectedReviewState: request.expectedVersion.reviewState,
                expectedUpdatedAt: request.expectedVersion.updatedAt,
                exactEvidence: exactEvidence,
                destination: destination,
                actor: request.actor
            )
        )
    }
}

@MainActor
struct CiderBookmarkEnrichmentReviewActionAdapter {
    private let service: CiderBookmarkEnrichmentSchedulingService

    init(service: CiderBookmarkEnrichmentSchedulingService) {
        self.service = service
    }

    func perform(
        _ request: CiderReviewActionRequest
    ) throws -> CiderBookmarkEnrichmentSchedulingMutationResult {
        guard request.action == .enrich,
              let bookmarkID = request.enrichmentItemID else {
            throw CiderBookmarkEnrichmentSchedulingError.invalidCandidateIdentity
        }
        return try service.perform(
            CiderBookmarkEnrichmentSchedulingRequest(
                candidateRef: request.identity.candidateRef,
                bookmarkID: bookmarkID,
                expectedReviewState: request.expectedVersion.reviewState,
                expectedUpdatedAt: request.expectedVersion.updatedAt,
                actor: request.actor,
                batchContext: request.enrichmentBatchContext
            )
        )
    }
}

@MainActor
final class CiderReviewActionCoordinator {
    typealias MutationBoundary = @MainActor (
        JournalIntelligenceReviewActionRequest,
        String
    ) throws -> JournalIntelligenceReviewActionOutcome

    typealias EventDateMutationBoundary = @MainActor (
        CiderReviewActionRequest
    ) throws -> SecondBrainEventDateFactReviewMutationResult

    typealias RoutingMutationBoundary = @MainActor (
        CiderReviewActionRequest
    ) throws -> CiderRoutingReviewMutationResult

    typealias BookmarkDateMutationBoundary = @MainActor (
        CiderReviewActionRequest
    ) throws -> CiderBookmarkDateSuggestionApprovalMutationResult

    typealias EnrichmentMutationBoundary = @MainActor (
        CiderReviewActionRequest
    ) throws -> CiderBookmarkEnrichmentSchedulingMutationResult

    private let performMutation: MutationBoundary
    private let performEventDateMutation: EventDateMutationBoundary
    private let performRoutingMutation: RoutingMutationBoundary
    private let performBookmarkDateMutation: BookmarkDateMutationBoundary
    private let performEnrichmentMutation: EnrichmentMutationBoundary

    init(
        database: CiderDatabase = .shared,
        bookmarkService: VaultBookmarkService = .shared,
        dateCardStorage: DateCardStorage = .shared,
        todoStorage: TodoCardStorage = .shared,
        routingFailureInjector: (@MainActor (CiderRoutingReviewMutationCheckpoint) throws -> Void)? = nil,
        bookmarkDateFailureInjector: (@MainActor (CiderBookmarkDateSuggestionMutationCheckpoint) throws -> Void)? = nil,
        enrichmentScheduler: CiderBookmarkEnrichmentSchedulingService.Scheduler? = nil,
        enrichmentScheduleCanceller: CiderBookmarkEnrichmentSchedulingService.ScheduleCanceller? = nil,
        enrichmentFailureInjector: (@MainActor (CiderBookmarkEnrichmentSchedulingCheckpoint) throws -> Void)? = nil
    ) {
        let service = JournalIntelligenceReviewActionService(database: database)
        performMutation = { request, actor in
            try service.perform(request, actor: actor)
        }
        let eventDateAdapter = CiderEventDateFactReviewActionAdapter(database: database)
        performEventDateMutation = { request in
            try eventDateAdapter.perform(request)
        }
        let routingAdapter = CiderRoutingDecisionReviewActionAdapter(
            database: database,
            bookmarkService: bookmarkService,
            failureInjector: routingFailureInjector
        )
        performRoutingMutation = { request in
            try routingAdapter.perform(request)
        }
        let bookmarkDateAdapter = CiderBookmarkDateSuggestionReviewActionAdapter(
            database: database,
            bookmarkService: bookmarkService,
            dateCardStorage: dateCardStorage,
            todoStorage: todoStorage,
            failureInjector: bookmarkDateFailureInjector
        )
        performBookmarkDateMutation = { request in
            try bookmarkDateAdapter.perform(request)
        }
        let enrichmentService: CiderBookmarkEnrichmentSchedulingService
        if let enrichmentScheduler {
            enrichmentService = CiderBookmarkEnrichmentSchedulingService(
                database: database,
                scheduler: enrichmentScheduler,
                scheduleCanceller: enrichmentScheduleCanceller,
                failureInjector: enrichmentFailureInjector
            )
        } else {
            enrichmentService = CiderBookmarkEnrichmentSchedulingService(
                database: database,
                bookmarkService: bookmarkService,
                failureInjector: enrichmentFailureInjector
            )
        }
        let enrichmentAdapter = CiderBookmarkEnrichmentReviewActionAdapter(service: enrichmentService)
        performEnrichmentMutation = { request in
            try enrichmentAdapter.perform(request)
        }
    }

    init(_ performMutation: @escaping MutationBoundary) {
        self.performMutation = performMutation
        performEventDateMutation = { request in
            throw SecondBrainEventDateFactReviewService.EventDateFactReviewError.unsupportedReviewAction(request.action.rawValue)
        }
        performRoutingMutation = { _ in
            throw CiderRoutingReviewActionError.unsupportedAction
        }
        performBookmarkDateMutation = { _ in
            throw CiderBookmarkDateSuggestionApprovalError.unsupportedAction
        }
        performEnrichmentMutation = { _ in
            throw CiderBookmarkEnrichmentSchedulingError.schedulerFailure
        }
    }

    init(bookmarkDateService: CiderBookmarkDateSuggestionApprovalService) {
        performMutation = { request, actor in
            throw JournalIntelligenceReviewActionError.unsupportedFamily(request.family)
        }
        performEventDateMutation = { request in
            throw SecondBrainEventDateFactReviewService.EventDateFactReviewError.unsupportedReviewAction(request.action.rawValue)
        }
        performRoutingMutation = { _ in
            throw CiderRoutingReviewActionError.unsupportedAction
        }
        let adapter = CiderBookmarkDateSuggestionReviewActionAdapter(service: bookmarkDateService)
        performBookmarkDateMutation = { request in
            try adapter.perform(request)
        }
        performEnrichmentMutation = { _ in
            throw CiderBookmarkEnrichmentSchedulingError.schedulerFailure
        }
    }

    func perform(_ request: CiderReviewActionRequest) -> CiderReviewActionOutcome {
        if let failure = preflightFailure(for: request) {
            return failedOutcome(request, failure: failure)
        }

        do {
            if request.identity.family == .routingDecision {
                let delegated = try performRoutingMutation(request)
                return CiderReviewActionOutcome(
                    identity: request.identity,
                    action: request.action,
                    actor: request.actor,
                    surface: request.surface,
                    availability: .available,
                    exactEvidenceRequirement: request.exactEvidenceRequirement,
                    evidenceStatus: .notRequired,
                    mutationAuthority: request.mutationAuthority,
                    changed: delegated.changed,
                    resultingReviewState: delegated.decision.reviewState,
                    truthBoundary: delegated.truthBoundary,
                    actionReceiptID: delegated.receiptID,
                    targetOwnerRef: delegated.decision.target.folderID.map { "folder:\($0.uuidString)" },
                    routingItemID: delegated.item.id,
                    routingDecisionID: delegated.decision.id,
                    routingDestination: delegated.decision.target,
                    bookmarkDateDestination: nil,
                    bookmarkDateApprovalAction: nil,
                    message: routingOutcomeMessage(action: request.action),
                    error: nil
                )
            }
            if request.identity.family == .bookmarkDateSuggestion {
                let delegated = try performBookmarkDateMutation(request)
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
                    resultingReviewState: "accepted",
                    truthBoundary: delegated.truthBoundary,
                    actionReceiptID: delegated.receiptID,
                    targetOwnerRef: delegated.approval.targetOwnerRef,
                    routingItemID: nil,
                    routingDecisionID: nil,
                    routingDestination: nil,
                    bookmarkDateDestination: delegated.approval.destination,
                    bookmarkDateApprovalAction: delegated.approval.action,
                    message: bookmarkDateOutcomeMessage(destination: delegated.approval.destination),
                    error: nil
                )
            }
            if request.identity.family == .eventDateFact {
                let delegated = try performEventDateMutation(request)
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
                    resultingReviewState: delegated.view.reviewState,
                    truthBoundary: delegated.view.truthBoundary,
                    actionReceiptID: delegated.receiptID,
                    targetOwnerRef: delegated.view.structuredFactRef,
                    routingItemID: nil,
                    routingDecisionID: nil,
                    routingDestination: nil,
                    bookmarkDateDestination: nil,
                    bookmarkDateApprovalAction: nil,
                    message: eventDateOutcomeMessage(action: request.action),
                    error: nil
                )
            }
            if request.identity.family == .enrichment {
                let delegated = try performEnrichmentMutation(request)
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
                    actionReceiptID: delegated.receiptID,
                    targetOwnerRef: "bookmark:\(request.enrichmentItemID?.uuidString ?? "")",
                    routingItemID: nil,
                    routingDecisionID: nil,
                    routingDestination: nil,
                    bookmarkDateDestination: nil,
                    bookmarkDateApprovalAction: nil,
                    enrichmentQueueDisposition: delegated.queueDisposition,
                    message: delegated.changed
                        ? "Scheduled bookmark enrichment. Completion remains asynchronous."
                        : "Reused the existing bookmark enrichment schedule. Completion remains asynchronous.",
                    error: nil
                )
            }
            guard let journalAction = request.action.journalAction else {
                throw JournalIntelligenceReviewActionError.unsupportedFamily(request.identity.family.rawValue)
            }
            let delegated = try performMutation(
                JournalIntelligenceReviewActionRequest(
                    candidateRef: request.identity.candidateRef,
                    family: request.identity.family.rawValue,
                    expectedReviewState: request.expectedVersion.reviewState,
                    expectedUpdatedAt: request.expectedVersion.updatedAt,
                    action: journalAction,
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
                routingItemID: nil,
                routingDecisionID: nil,
                routingDestination: nil,
                bookmarkDateDestination: nil,
                bookmarkDateApprovalAction: nil,
                message: delegated.message,
                error: nil
            )
        } catch {
            return failedOutcome(request, failure: Self.failure(from: error))
        }
    }

    private func preflightFailure(for request: CiderReviewActionRequest) -> CiderReviewActionFailure? {
        if request.identity.family == .enrichment {
            guard request.mutationAuthority == .directUserAction else {
                return failure(.reviewApprovalRequired)
            }
        } else {
            guard request.mutationAuthority == .reviewApprovedCandidate else {
                return failure(.reviewApprovalRequired)
            }
        }
        guard request.identity.family == .memoryCandidate
                || request.identity.family == .graphCandidate
                || request.identity.family == .eventDateFact
                || request.identity.family == .routingDecision
                || request.identity.family == .bookmarkDateSuggestion
                || request.identity.family == .enrichment else {
            return failure(.unsupportedFamily)
        }
        let supportedSurfaces: [CiderReviewInvokingSurface] = request.identity.family == .eventDateFact
            ? [.home, .journal, .reviewQueue, .cli]
            : request.identity.family == .enrichment
                ? [.home, .reviewQueue, .cli]
            : request.identity.family == .routingDecision || request.identity.family == .bookmarkDateSuggestion
                ? [.home, .reviewQueue, .cli]
                : [.home, .journal, .cli]
        guard supportedSurfaces.contains(request.surface) else {
            return failure(.unsupportedSurface)
        }
        let identityPrefix = request.identity.family == .eventDateFact
            ? "fact_validity_candidate:"
            : "\(request.identity.family.rawValue):"
        guard request.identity.candidateRef.hasPrefix(identityPrefix),
              request.identity.candidateRef.count > identityPrefix.count else {
            return failure(.invalidCandidateIdentity)
        }
        if request.identity.family == .routingDecision {
            guard request.exactEvidenceRequirement == .notRequired else {
                return failure(.unsupportedActionForSurface)
            }
            guard request.action != .reject else {
                return failure(.unsupportedActionForSurface)
            }
            guard request.routingItemID != nil else {
                return failure(.invalidCandidateIdentity)
            }
            guard request.routingDestination != nil else {
                return failure(.destinationRequired)
            }
        } else if request.identity.family == .bookmarkDateSuggestion {
            guard request.exactEvidenceRequirement == .required else {
                return failure(.exactEvidenceRequired)
            }
            guard request.action == .approve else {
                return failure(.unsupportedActionForSurface)
            }
            guard request.bookmarkDateItemID != nil else {
                return failure(.invalidCandidateIdentity)
            }
            guard request.bookmarkDateDestination != nil else {
                return failure(.destinationRequired)
            }
            guard request.bookmarkDateExactEvidence != nil else {
                return failure(.missingExactEvidence)
            }
        } else if request.identity.family == .enrichment {
            guard request.exactEvidenceRequirement == .required else {
                return failure(.exactEvidenceRequired)
            }
            guard request.action == .enrich else {
                return failure(.unsupportedActionForSurface)
            }
            guard request.enrichmentItemID != nil,
                  request.identity.candidateRef == request.enrichmentItemID.map(CiderBookmarkEnrichmentSchedulingService.candidateRef(for:)) else {
                return failure(.invalidCandidateIdentity)
            }
        } else if request.exactEvidenceRequirement != .required {
            return failure(.exactEvidenceRequired)
        }
        if request.surface == .home,
           request.action == .correct,
           request.identity.family != .routingDecision {
            return failure(.unsupportedActionForSurface)
        }
        if request.identity.family == .eventDateFact, request.action == .correct {
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
            routingItemID: request.routingItemID,
            routingDecisionID: nil,
            routingDestination: request.routingDestination,
            bookmarkDateDestination: request.bookmarkDateDestination,
            bookmarkDateApprovalAction: nil,
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
        if let error = error as? SecondBrainEventDateFactReviewService.EventDateFactReviewError {
            switch error {
            case .candidateNotFound:
                return failure(.candidateUnavailable)
            case .unsupportedCandidate:
                return failure(.invalidCandidateIdentity)
            case .staleCandidate:
                return failure(.staleExpectedVersion)
            case .alreadyReviewed:
                return failure(.alreadyReviewed)
            case .missingSourceEvidence:
                return failure(.missingExactEvidence)
            case .unsupportedReviewAction:
                return failure(.unsupportedActionForSurface)
            case .invalidProposedDate, .noBoundedEventDateFactFound, .ambiguousEventDateFact:
                return failure(.writerFailure)
            }
        }
        if let error = error as? CiderRoutingReviewActionError {
            switch error {
            case .malformedCandidate, .itemMismatch:
                return failure(.invalidCandidateIdentity)
            case .candidateUnavailable:
                return failure(.candidateUnavailable)
            case .staleCandidate:
                return failure(.staleExpectedVersion)
            case .alreadyReviewed:
                return failure(.alreadyReviewed)
            case .unsupportedAction:
                return failure(.unsupportedActionForSurface)
            case .missingDestination:
                return failure(.destinationRequired)
            case .invalidDestination:
                return failure(.destinationInvalid)
            case .unresolvedDestination:
                return failure(.destinationUnresolved)
            case .ambiguousDestination:
                return failure(.destinationAmbiguous)
            case .unauthorizedDestination:
                return failure(.routingUnauthorized)
            case .unsupportedCorrectionItemType:
                return failure(.unsupportedRoutingCorrection)
            case .assignmentFailed:
                return failure(.writerFailure)
            }
        }
        if let error = error as? CiderBookmarkDateSuggestionApprovalError {
            switch error {
            case .databaseUnavailable:
                return failure(.databaseFailure)
            case .bookmarkNotFound, .candidateUnavailable:
                return failure(.candidateUnavailable)
            case .invalidCandidateIdentity:
                return failure(.invalidCandidateIdentity)
            case .ambiguousCandidate:
                return failure(.destinationAmbiguous)
            case .staleExpectedVersion:
                return failure(.staleExpectedVersion)
            case .alreadyReviewed:
                return failure(.alreadyReviewed)
            case .missingExactEvidence:
                return failure(.missingExactEvidence)
            case .destinationRequired:
                return failure(.destinationRequired)
            case .unsupportedAction:
                return failure(.unsupportedActionForSurface)
            case .createFailed, .linkFailed:
                return failure(.writerFailure)
            case .compensationFailed:
                return CiderReviewActionFailure(
                    classification: .writerFailure,
                    message: error.localizedDescription
                )
            }
        }
        if let error = error as? CiderBookmarkEnrichmentSchedulingError {
            switch error {
            case .databaseUnavailable:
                return failure(.databaseFailure)
            case .invalidCandidateIdentity, .unsupportedItemType:
                return failure(.invalidCandidateIdentity)
            case .candidateUnavailable:
                return failure(.candidateUnavailable)
            case .staleCandidate:
                return failure(.staleExpectedVersion)
            case .missingSource:
                return failure(.missingExactEvidence)
            case .unauthorizedActor:
                return failure(.unauthorizedActor)
            case .schedulingConflict:
                return failure(.schedulingConflict)
            case .schedulerFailure, .compensationUnavailable, .compensationFailed:
                return CiderReviewActionFailure(
                    classification: .writerFailure,
                    message: error.localizedDescription
                )
            }
        }
        return failure(.writerFailure)
    }

    private func routingOutcomeMessage(action: CiderReviewAction) -> String {
        switch action {
        case .approve: return "Approved the proposed routing destination."
        case .defer: return "Deferred the routing decision for later review."
        case .correct: return "Applied the explicitly selected routing destination."
        case .reject: return "Routing rejection is unavailable."
        case .enrich: return "Enrichment is not a routing action."
        }
    }

    private func eventDateOutcomeMessage(action: CiderReviewAction) -> String {
        switch action {
        case .approve:
            return "Approved the exact source-backed event/date fact as structured truth."
        case .reject:
            return "Rejected the event/date fact without accepting truth."
        case .defer:
            return "Deferred the event/date fact for later review without accepting truth."
        case .correct:
            return "Event/date fact correction remains unavailable."
        case .enrich:
            return "Enrichment is not an event/date fact action."
        }
    }

    private func bookmarkDateOutcomeMessage(
        destination: CiderBookmarkDateSuggestionDestination
    ) -> String {
        switch destination {
        case .dateCard:
            return "Approved the exact bookmark date evidence to the explicitly selected Date Card destination."
        case .todo:
            return "Approved the exact bookmark date evidence to the explicitly selected Todo destination."
        }
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
        case .destinationRequired:
            return "Choose an explicit routing destination before continuing. Nothing was changed."
        case .destinationInvalid:
            return "That routing destination is invalid. Refresh the available destinations; nothing was changed."
        case .destinationUnresolved:
            return "That routing destination no longer exists. Refresh the available destinations; nothing was changed."
        case .destinationAmbiguous:
            return "That routing destination is ambiguous. Choose one exact destination; nothing was changed."
        case .routingUnauthorized:
            return "Cider could not verify authority for that routing destination. Nothing was changed."
        case .unsupportedRoutingCorrection:
            return "Use the item's Move action to correct this non-bookmark destination. Nothing was changed."
        case .reviewApprovalRequired:
            return "Inferred proposals must remain in review until a user explicitly approves them."
        case .unauthorizedActor:
            return "This actor cannot schedule enrichment. Nothing was changed."
        case .schedulingConflict:
            return "This enrichment candidate already has scheduled work under a different exact request. Refresh before retrying."
        case .databaseFailure:
            return "Cider could not safely update this suggestion. Nothing was changed; try again after reopening the review list."
        case .writerFailure:
            return "Cider could not complete this review action. Nothing was changed; refresh and try again."
        }
    }
}

private extension CiderReviewAction {
    var journalAction: JournalIntelligenceReviewAction? {
        switch self {
        case .approve: .approve
        case .reject: .reject
        case .defer: .defer
        case .correct: .correct
        case .enrich: nil
        }
    }
}
