import Foundation
@testable import Cider

struct CiderEventDateFactReviewCLIActionAdapterResult {
    var request: CiderReviewActionRequest
    var outcome: CiderReviewActionOutcome
    var before: SecondBrainEventDateFactCandidateView
    var after: SecondBrainEventDateFactCandidateView
    var expectedVersionSelector: String
    var canonicalReceipt: SecondBrainActionReceiptRecord?

    var safeVerificationCommands: [String] {
        canonicalReceipt?.safeVerificationCommands ?? after.safeVerificationCommands
    }

    var safeNextCommands: [String] {
        canonicalReceipt?.safeNextCommands ?? after.safeNextCommands
    }
}

@MainActor
struct CiderEventDateFactReviewCLIActionAdapter {
    private let database: CiderDatabase
    private let service: SecondBrainEventDateFactReviewService
    private let coordinator: CiderReviewActionCoordinator

    init(database: CiderDatabase = .shared) {
        self.database = database
        service = SecondBrainEventDateFactReviewService(database: database)
        coordinator = CiderReviewActionCoordinator(database: database)
    }

    func perform(
        candidateRef: String,
        action: CiderReviewAction,
        reason: String?,
        actor: String,
        expectedVersionSelector: String?
    ) throws -> CiderEventDateFactReviewCLIActionAdapterResult {
        let before: SecondBrainEventDateFactCandidateView
        do {
            before = try service.inspect(candidateID: candidateRef)
        } catch {
            throw CiderReviewCLIActionAdapterError.candidateUnavailable
        }
        let expectedVersion: CiderReviewExpectedVersion
        let emittedSelector: String
        if let expectedVersionSelector {
            guard let decoded = CiderReviewCLIActionAdapter.decodeExpectedVersionSelector(expectedVersionSelector) else {
                throw CiderReviewCLIActionAdapterError.malformedExpectedVersion
            }
            expectedVersion = decoded
            emittedSelector = expectedVersionSelector
        } else {
            expectedVersion = .init(
                reviewState: before.reviewState,
                updatedAt: before.candidate.candidate.updatedAt
            )
            emittedSelector = CiderReviewCLIActionAdapter.expectedVersionSelector(
                reviewState: before.reviewState,
                updatedAt: before.candidate.candidate.updatedAt
            )
        }
        let request = CiderReviewActionRequest(
            identity: .init(candidateRef: before.candidateRef, family: .eventDateFact),
            expectedVersion: expectedVersion,
            action: action,
            reason: reason,
            actor: actor,
            surface: .cli,
            exactEvidenceRequirement: .required,
            mutationAuthority: .reviewApprovedCandidate
        )
        let outcome = coordinator.perform(request)
        let after = (try? service.inspect(candidateID: before.id)) ?? before
        let receipt = try outcome.actionReceiptID.flatMap {
            try SecondBrainActionReceiptLedgerService(database: database).inspect(id: $0)
        }
        return CiderEventDateFactReviewCLIActionAdapterResult(
            request: request,
            outcome: outcome,
            before: before,
            after: after,
            expectedVersionSelector: emittedSelector,
            canonicalReceipt: receipt
        )
    }
}
