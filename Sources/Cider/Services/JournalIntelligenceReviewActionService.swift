import CryptoKit
import Foundation

enum JournalIntelligenceReviewAction: String, CaseIterable, Equatable {
    case approve
    case correct
    case reject
    case `defer`
}

enum JournalIntelligenceReviewActionAvailability: Equatable {
    case available
    case requiresCorrection
    case requiresTarget
    case unavailable
    case alreadyReviewed
}

struct JournalIntelligenceReviewTargetOption: Identifiable, Equatable {
    var id: String
    var label: String
    var targetOwnerRef: String
    var relationType: String
    var targetKind: String
    var sourceQuote: String
}

struct JournalIntelligenceReviewActionDescriptor: Identifiable, Equatable {
    var id: String { action.rawValue }
    var action: JournalIntelligenceReviewAction
    var label: String
    var availability: JournalIntelligenceReviewActionAvailability
    var preview: String
    var guidance: String
    var targetOptions: [JournalIntelligenceReviewTargetOption] = []

    var isDirectlyPerformable: Bool { availability == .available }
}

struct JournalIntelligenceReviewActionSet: Equatable {
    var family: String
    var reviewState: String
    var descriptors: [JournalIntelligenceReviewActionDescriptor]

    func descriptor(for action: JournalIntelligenceReviewAction) -> JournalIntelligenceReviewActionDescriptor? {
        descriptors.first { $0.action == action }
    }

    static func unsupported(family: String, reviewState: String, guidance: String) -> Self {
        Self(
            family: family,
            reviewState: reviewState,
            descriptors: JournalIntelligenceReviewAction.allCases.map { action in
                JournalIntelligenceReviewActionDescriptor(
                    action: action,
                    label: action.label,
                    availability: .unavailable,
                    preview: "No canonical \(action.rawValue) mutation is available for this suggestion family.",
                    guidance: guidance
                )
            }
        )
    }

    static func reviewed(family: String, reviewState: String) -> Self {
        Self(
            family: family,
            reviewState: reviewState,
            descriptors: JournalIntelligenceReviewAction.allCases.map { action in
                JournalIntelligenceReviewActionDescriptor(
                    action: action,
                    label: action.label,
                    availability: .alreadyReviewed,
                    preview: "This suggestion is already \(reviewState).",
                    guidance: "Its source evidence remains available. Refresh before taking any different action."
                )
            }
        )
    }

    func blocked(_ guidance: String) -> Self {
        Self(
            family: family,
            reviewState: reviewState,
            descriptors: descriptors.map { descriptor in
                var blocked = descriptor
                blocked.availability = .unavailable
                blocked.guidance = guidance
                return blocked
            }
        )
    }
}

private extension JournalIntelligenceReviewAction {
    var label: String {
        switch self {
        case .approve: return "Approve"
        case .correct: return "Correct"
        case .reject: return "Reject"
        case .defer: return "Defer"
        }
    }
}

struct JournalIntelligenceReviewActionRequest: Equatable {
    var candidateRef: String
    var family: String
    var expectedReviewState: String
    var expectedUpdatedAt: Date
    var action: JournalIntelligenceReviewAction
    var correctedValue: String? = nil
    var targetOptionRef: String? = nil

    init(
        candidateRef: String,
        family: String,
        expectedReviewState: String,
        expectedUpdatedAt: Date,
        action: JournalIntelligenceReviewAction,
        correctedValue: String? = nil,
        targetOptionRef: String? = nil
    ) {
        self.candidateRef = candidateRef
        self.family = family
        self.expectedReviewState = expectedReviewState
        self.expectedUpdatedAt = expectedUpdatedAt
        self.action = action
        self.correctedValue = correctedValue
        self.targetOptionRef = targetOptionRef
    }

    init(
        proposal: JournalIntelligenceReviewProposal,
        action: JournalIntelligenceReviewAction,
        correctedValue: String? = nil,
        targetOptionRef: String? = nil
    ) {
        self.init(
            candidateRef: proposal.candidateRef,
            family: proposal.family,
            expectedReviewState: proposal.reviewState,
            expectedUpdatedAt: proposal.candidateUpdatedAt,
            action: action,
            correctedValue: correctedValue,
            targetOptionRef: targetOptionRef
        )
    }
}

struct JournalIntelligenceReviewActionOutcome: Equatable {
    var candidateRef: String
    var action: JournalIntelligenceReviewAction
    var reviewState: String
    var truthBoundary: String
    var changed: Bool
    var message: String
    var actionReceiptID: String?
    var targetOwnerRef: String?
}

enum JournalIntelligenceReviewActionError: LocalizedError, Equatable {
    case unsupportedFamily(String)
    case malformedCandidateRef(String)
    case missingCandidate(String)
    case wrongCandidateFamily(expected: String, actual: String)
    case staleCandidate(String)
    case alreadyReviewed(String, String)
    case missingSourceEvidence(String)
    case correctionRequired(String)
    case targetRequired(String)
    case targetUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFamily(let family):
            return "This \(family) suggestion does not have a canonical Journal Review action service yet. Nothing was changed."
        case .malformedCandidateRef:
            return "This suggestion has an invalid candidate reference. Refresh Journal Review; nothing was changed."
        case .missingCandidate:
            return "This suggestion no longer exists. Refresh Journal Review; nothing was changed."
        case .wrongCandidateFamily:
            return "This suggestion changed families. Refresh Journal Review; nothing was changed."
        case .staleCandidate:
            return "This suggestion changed after the page loaded. Refresh Journal Review before acting."
        case .alreadyReviewed(_, let state):
            return "This suggestion is already \(state). Its source remains available; refresh before choosing another action."
        case .missingSourceEvidence:
            return "Cider cannot verify this suggestion's exact source evidence, so the action was blocked."
        case .correctionRequired:
            return "Enter explicit corrected wording before saving this correction."
        case .targetRequired:
            return "Choose the exact target first. Cider will not guess what to approve or correct."
        case .targetUnavailable:
            return "That target is no longer available. Refresh Journal Review and choose again."
        }
    }
}

@MainActor
final class JournalIntelligenceReviewActionService {
    private let database: CiderDatabase
    private let outputService: SecondBrainEnrichmentOutputService

    init(database: CiderDatabase = .shared) {
        self.database = database
        outputService = SecondBrainEnrichmentOutputService(database: database)
    }

    func actionSets(candidateRefs: [String]) throws -> [String: JournalIntelligenceReviewActionSet] {
        let requested = Set(candidateRefs)
        let queueItems = try CiderReviewQueueService(database: database)
            .list(limit: Int.max, includeDeferred: true)
            .items
        let queueByRef: [String: CiderReviewQueueItem] = Dictionary(uniqueKeysWithValues: queueItems.compactMap { item -> (String, CiderReviewQueueItem)? in
            guard let ref = item.candidateRef, requested.contains(ref) else { return nil }
            return (ref, item)
        })
        var result: [String: JournalIntelligenceReviewActionSet] = [:]
        for candidateRef in requested {
            guard let selector = Self.selector(candidateRef) else {
                result[candidateRef] = .unsupported(
                    family: "unknown",
                    reviewState: "unknown",
                    guidance: JournalIntelligenceReviewActionError.malformedCandidateRef(candidateRef).localizedDescription
                )
                continue
            }
            guard let output = try outputService.output(id: selector.id) else {
                result[candidateRef] = .unsupported(
                    family: selector.family,
                    reviewState: "missing",
                    guidance: JournalIntelligenceReviewActionError.missingCandidate(candidateRef).localizedDescription
                )
                continue
            }
            result[candidateRef] = actionSet(output: output, queueItem: queueByRef[candidateRef])
        }
        return result
    }

    func perform(
        _ request: JournalIntelligenceReviewActionRequest,
        actor: String = "user"
    ) throws -> JournalIntelligenceReviewActionOutcome {
        guard ["memory_candidate", "graph_candidate"].contains(request.family) else {
            throw JournalIntelligenceReviewActionError.unsupportedFamily(request.family)
        }
        guard let selector = Self.selector(request.candidateRef), selector.family == request.family else {
            throw JournalIntelligenceReviewActionError.malformedCandidateRef(request.candidateRef)
        }
        guard let before = try outputService.output(id: selector.id) else {
            throw JournalIntelligenceReviewActionError.missingCandidate(request.candidateRef)
        }
        guard before.kind == request.family else {
            throw JournalIntelligenceReviewActionError.wrongCandidateFamily(expected: request.family, actual: before.kind)
        }
        if let replayed = try replayedOutcome(for: request, current: before, actor: actor) {
            return replayed
        }
        guard before.reviewState == request.expectedReviewState,
              Self.preciseVersion(before.updatedAt) == Self.preciseVersion(request.expectedUpdatedAt) else {
            if ["accepted", "rejected"].contains(before.reviewState) {
                throw JournalIntelligenceReviewActionError.alreadyReviewed(request.candidateRef, before.reviewState)
            }
            throw JournalIntelligenceReviewActionError.staleCandidate(request.candidateRef)
        }
        if ["accepted", "rejected"].contains(before.reviewState) {
            throw JournalIntelligenceReviewActionError.alreadyReviewed(request.candidateRef, before.reviewState)
        }
        guard before.metadata["source_evidence_ref"] != nil,
              before.metadata["capture_event_id"] != nil,
              before.metadata["source_span_start"] != nil,
              before.metadata["source_span_end"] != nil else {
            throw JournalIntelligenceReviewActionError.missingSourceEvidence(request.candidateRef)
        }

        let queue = CiderReviewQueueService(database: database)
        let normalizedTargetOptionRef = Self.normalizedTargetOptionRef(request.targetOptionRef)
        if request.family == "graph_candidate",
           request.action == .approve || request.action == .correct {
            guard let normalizedTargetOptionRef, !normalizedTargetOptionRef.isEmpty else {
                throw JournalIntelligenceReviewActionError.targetRequired(request.candidateRef)
            }
            let currentQueueItem = try queue.list(limit: Int.max, includeDeferred: true)
                .items
                .first { $0.candidateRef == request.candidateRef }
            guard currentQueueItem?.targetOptions.contains(where: { $0.optionRef == normalizedTargetOptionRef }) == true else {
                throw JournalIntelligenceReviewActionError.targetUnavailable(normalizedTargetOptionRef)
            }
        }
        var actionResult: CiderReviewCandidateQueueActionResult!
        var postMutation: SecondBrainEnrichmentOutput!
        var receiptID: String?
        let requestFingerprint = Self.requestFingerprint(for: request, actor: actor)
        try database.withTransaction {
            switch (request.family, request.action) {
            case ("memory_candidate", .approve):
                actionResult = try queue.approveMemoryCandidate(candidateID: selector.id, actor: actor)
            case ("memory_candidate", .correct):
                guard let value = request.correctedValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                    throw JournalIntelligenceReviewActionError.correctionRequired(request.candidateRef)
                }
                actionResult = try queue.correctMemoryCandidate(
                    candidateID: selector.id,
                    correctedValue: value,
                    reason: "Corrected from Journal Review.",
                    actor: actor
                )
            case ("memory_candidate", .reject):
                actionResult = try queue.rejectMemoryCandidate(
                    candidateID: selector.id,
                    reason: "Rejected from Journal Review.",
                    actor: actor
                )
            case ("memory_candidate", .defer):
                guard before.reviewState != "deferred" else {
                    throw JournalIntelligenceReviewActionError.alreadyReviewed(request.candidateRef, "deferred")
                }
                actionResult = try queue.deferMemoryCandidate(
                    candidateID: selector.id,
                    reason: "Deferred from Journal Review.",
                    actor: actor
                )
            case ("graph_candidate", .approve):
                guard let normalizedTargetOptionRef, !normalizedTargetOptionRef.isEmpty else {
                    throw JournalIntelligenceReviewActionError.targetRequired(request.candidateRef)
                }
                actionResult = try queue.approveGraphCandidate(
                    candidateID: selector.id,
                    actor: actor,
                    targetOptionRef: normalizedTargetOptionRef
                )
            case ("graph_candidate", .correct):
                guard let normalizedTargetOptionRef, !normalizedTargetOptionRef.isEmpty else {
                    throw JournalIntelligenceReviewActionError.targetRequired(request.candidateRef)
                }
                actionResult = try queue.correctGraphCandidate(
                    candidateID: selector.id,
                    targetOptionRef: normalizedTargetOptionRef,
                    reason: "Corrected from Journal Review without approval.",
                    actor: actor
                )
            case ("graph_candidate", .reject):
                actionResult = try queue.rejectGraphCandidate(
                    candidateID: selector.id,
                    reason: "Rejected from Journal Review.",
                    actor: actor
                )
            case ("graph_candidate", .defer):
                guard before.reviewState != "deferred" else {
                    throw JournalIntelligenceReviewActionError.alreadyReviewed(request.candidateRef, "deferred")
                }
                actionResult = try queue.deferGraphCandidate(
                    candidateID: selector.id,
                    reason: "Deferred from Journal Review.",
                    actor: actor
                )
            default:
                throw JournalIntelligenceReviewActionError.unsupportedFamily(request.family)
            }

            guard actionResult.changed else {
                throw JournalIntelligenceReviewActionError.alreadyReviewed(request.candidateRef, actionResult.reviewState)
            }
            guard let canonicalAfter = try outputService.output(id: selector.id) else {
                throw JournalIntelligenceReviewActionError.missingCandidate(request.candidateRef)
            }
            guard canonicalAfter.kind == request.family else {
                throw JournalIntelligenceReviewActionError.wrongCandidateFamily(
                    expected: request.family,
                    actual: canonicalAfter.kind
                )
            }
            postMutation = canonicalAfter
            let record = actionReceipt(
                result: actionResult,
                owner: before.owner,
                evidenceRef: before.metadata["source_evidence_ref"],
                request: request,
                requestFingerprint: requestFingerprint,
                postMutation: canonicalAfter
            )
            receiptID = try SecondBrainActionReceiptLedgerService(database: database).record(record)
        }

        return JournalIntelligenceReviewActionOutcome(
            candidateRef: request.candidateRef,
            action: request.action,
            reviewState: postMutation.reviewState,
            truthBoundary: Self.truthBoundary(family: postMutation.kind, reviewState: postMutation.reviewState),
            changed: actionResult.changed,
            message: outcomeMessage(action: request.action, family: request.family, state: postMutation.reviewState),
            actionReceiptID: receiptID,
            targetOwnerRef: acceptedTargetOwnerRef(from: postMutation)
        )
    }

    private func actionSet(
        output: SecondBrainEnrichmentOutput,
        queueItem: CiderReviewQueueItem?
    ) -> JournalIntelligenceReviewActionSet {
        let family = output.kind
        if ["accepted", "rejected"].contains(output.reviewState) {
            return .reviewed(family: family, reviewState: output.reviewState)
        }
        guard ["memory_candidate", "graph_candidate"].contains(family) else {
            return .unsupported(
                family: family,
                reviewState: output.reviewState,
                guidance: "This suggestion family does not have a canonical review service yet."
            )
        }
        if family == "memory_candidate" {
            return JournalIntelligenceReviewActionSet(
                family: family,
                reviewState: output.reviewState,
                descriptors: [
                    .init(
                        action: .approve,
                        label: "Approve memory",
                        availability: .available,
                        preview: "Accept this exact wording as a Cider memory. This does not create a task, entity, relation, trip, or media item.",
                        guidance: "Approval promotes only the canonical memory candidate shown here."
                    ),
                    .init(
                        action: .correct,
                        label: "Correct wording",
                        availability: .requiresCorrection,
                        preview: "Save explicit corrected wording while keeping the original Journal source unchanged. The correction remains reviewable and is not approved.",
                        guidance: "Enter the wording Cider should review next."
                    ),
                    .init(
                        action: .reject,
                        label: "Reject",
                        availability: .available,
                        preview: "Mark this suggestion rejected without creating accepted truth.",
                        guidance: "The exact Journal evidence stays attached to the reviewed record."
                    ),
                    .init(
                        action: .defer,
                        label: output.reviewState == "deferred" ? "Deferred" : "Defer",
                        availability: output.reviewState == "deferred" ? .alreadyReviewed : .available,
                        preview: "Keep this suggestion pending for later without creating accepted truth.",
                        guidance: output.reviewState == "deferred" ? "This suggestion is already deferred." : "You can return to it later."
                    ),
                ]
            )
        }

        let options = (queueItem?.targetOptions ?? []).map { option in
            JournalIntelligenceReviewTargetOption(
                id: option.optionRef,
                label: option.label,
                targetOwnerRef: option.targetOwner.canonicalRef,
                relationType: option.relationType,
                targetKind: option.targetKind,
                sourceQuote: option.sourceQuote
            )
        }
        let targetAvailability: JournalIntelligenceReviewActionAvailability = options.isEmpty ? .unavailable : .requiresTarget
        let targetGuidance = options.isEmpty
            ? "No canonical target is available. Correct the candidate elsewhere or refresh after the target exists."
            : "Choose the exact target. Cider will not select one for you."
        return JournalIntelligenceReviewActionSet(
            family: family,
            reviewState: output.reviewState,
            descriptors: [
                .init(
                    action: .approve,
                    label: "Approve link",
                    availability: targetAvailability,
                    preview: "Create only the displayed canonical relation to the target you explicitly choose.",
                    guidance: targetGuidance,
                    targetOptions: options
                ),
                .init(
                    action: .correct,
                    label: "Correct target",
                    availability: targetAvailability,
                    preview: "Save the chosen target as a correction. This does not approve or create a relation.",
                    guidance: targetGuidance,
                    targetOptions: options
                ),
                .init(
                    action: .reject,
                    label: "Reject",
                    availability: .available,
                    preview: "Mark this graph suggestion rejected without creating a relation or object.",
                    guidance: "The exact Journal evidence stays attached to the reviewed record."
                ),
                .init(
                    action: .defer,
                    label: output.reviewState == "deferred" ? "Deferred" : "Defer",
                    availability: output.reviewState == "deferred" ? .alreadyReviewed : .available,
                    preview: "Keep this graph suggestion pending without creating accepted truth.",
                    guidance: output.reviewState == "deferred" ? "This suggestion is already deferred." : "You can return to it later."
                ),
            ]
        )
    }

    private func actionReceipt(
        result: CiderReviewCandidateQueueActionResult,
        owner: SecondBrainOwnerRef,
        evidenceRef: String?,
        request: JournalIntelligenceReviewActionRequest,
        requestFingerprint: String,
        postMutation: SecondBrainEnrichmentOutput
    ) -> SecondBrainActionReceiptRecord {
        let durableTruthBoundary = Self.truthBoundary(
            family: postMutation.kind,
            reviewState: postMutation.reviewState
        )
        return SecondBrainActionReceiptRecord(
            id: Self.actionReceiptID(for: request, actor: result.actor),
            command: result.command,
            action: result.action,
            actor: result.actor,
            status: result.reviewState == "deferred" ? "deferred" : "succeeded",
            owner: owner,
            sourceRefs: [result.candidateRef, owner.canonicalRef],
            evidenceRefs: [evidenceRef].compactMap { $0 },
            readOnly: false,
            changed: result.changed,
            beforeJSON: DatabaseHelpers.encodeJSON(["reviewState": result.beforeState ?? ""]),
            afterJSON: DatabaseHelpers.encodeJSON([
                "requestFingerprint": requestFingerprint,
                "resultingCandidateVersion": Self.preciseVersion(postMutation.updatedAt),
                "reviewState": postMutation.reviewState,
                "truthBoundary": durableTruthBoundary,
            ]),
            safeVerificationCommands: result.safeVerificationCommands,
            safeNextCommands: result.safeNextCommands,
            correlationID: "journal-review:\(result.candidateRef)",
            receiptJSON: Self.jsonString(result.toDictionary())
        )
    }

    private func replayedOutcome(
        for request: JournalIntelligenceReviewActionRequest,
        current: SecondBrainEnrichmentOutput,
        actor: String
    ) throws -> JournalIntelligenceReviewActionOutcome? {
        let requestFingerprint = Self.requestFingerprint(for: request, actor: actor)
        let receiptID = Self.actionReceiptID(for: request, actor: actor)
        let canonicalCandidateRef = "\(current.kind):\(current.id)"
        let expectedReviewState = Self.resultingReviewState(for: request.action)
        let expectedTruthBoundary = Self.truthBoundary(
            family: request.family,
            reviewState: expectedReviewState
        )
        let expectedStatus = request.action == .defer ? "deferred" : "succeeded"
        guard let receipt = try SecondBrainActionReceiptLedgerService(database: database).inspect(id: receiptID),
              receipt.action == request.action.rawValue,
              receipt.actor == actor,
              receipt.status == expectedStatus,
              receipt.owner == current.owner,
              Set(receipt.sourceRefs) == Set([canonicalCandidateRef, current.owner.canonicalRef]),
              !receipt.readOnly,
              receipt.changed,
              let durableOutcome = DatabaseHelpers.decodeJSON([String: String].self, from: receipt.afterJSON),
              durableOutcome["requestFingerprint"] == requestFingerprint,
              durableOutcome["resultingCandidateVersion"] == Self.preciseVersion(current.updatedAt),
              durableOutcome["reviewState"] == expectedReviewState,
              durableOutcome["truthBoundary"] == expectedTruthBoundary,
              current.reviewState == expectedReviewState else {
            return nil
        }
        return JournalIntelligenceReviewActionOutcome(
            candidateRef: request.candidateRef,
            action: request.action,
            reviewState: expectedReviewState,
            truthBoundary: expectedTruthBoundary,
            changed: false,
            message: outcomeMessage(action: request.action, family: request.family, state: current.reviewState),
            actionReceiptID: receipt.id,
            targetOwnerRef: acceptedTargetOwnerRef(from: current)
        )
    }

    private func acceptedTargetOwnerRef(from output: SecondBrainEnrichmentOutput) -> String? {
        guard let ownerType = output.metadata[SecondBrainGraphCandidateContract.MetadataKey.acceptedTargetOwnerType],
              let ownerID = output.metadata[SecondBrainGraphCandidateContract.MetadataKey.acceptedTargetOwnerID],
              !ownerType.isEmpty,
              !ownerID.isEmpty else {
            return nil
        }
        return SecondBrainOwnerRef(ownerType: ownerType, ownerID: ownerID).canonicalRef
    }

    static func requestFingerprint(
        for request: JournalIntelligenceReviewActionRequest,
        actor: String
    ) -> String {
        let family = request.family.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let candidateRef: String
        if let selector = selector(request.candidateRef) {
            candidateRef = "\(selector.family.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()):\(selector.id)"
        } else {
            candidateRef = request.candidateRef.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let fields = [
            "journal-review-request-v1",
            candidateRef,
            family,
            request.action.rawValue,
            actor,
            request.expectedReviewState,
            preciseVersion(request.expectedUpdatedAt),
            normalizedCorrection(request.correctedValue),
            normalizedTargetOptionRef(request.targetOptionRef) ?? "",
        ]
        let canonical = fields.map { field in
            "\(field.utf8.count):\(field)"
        }.joined(separator: "|")
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func actionReceiptID(
        for request: JournalIntelligenceReviewActionRequest,
        actor: String
    ) -> String {
        let family = request.family.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "journal-review:\(family):\(request.action.rawValue):\(requestFingerprint(for: request, actor: actor))"
    }

    private static func normalizedCorrection(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func normalizedTargetOptionRef(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty else {
            return nil
        }
        return normalized
    }

    private static func preciseVersion(_ date: Date) -> String {
        String(format: "%016llx", date.timeIntervalSinceReferenceDate.bitPattern)
    }

    private static func resultingReviewState(for action: JournalIntelligenceReviewAction) -> String {
        switch action {
        case .approve: "accepted"
        case .correct: "needs_review"
        case .reject: "rejected"
        case .defer: "deferred"
        }
    }

    private static func truthBoundary(family: String, reviewState: String) -> String {
        switch (family, reviewState) {
        case ("memory_candidate", "accepted"):
            return "accepted_memory_candidate"
        case ("graph_candidate", "accepted"):
            return "accepted_graph_truth"
        default:
            return "reviewable_candidate_not_truth"
        }
    }

    private func outcomeMessage(
        action: JournalIntelligenceReviewAction,
        family: String,
        state: String
    ) -> String {
        switch action {
        case .approve:
            return family == "memory_candidate"
                ? "Approved this exact suggestion as a Cider memory. The Journal source was not changed."
                : "Approved the explicitly selected graph link. The Journal source was not changed."
        case .correct:
            return "Saved the explicit correction for review without accepting truth."
        case .reject:
            return "Rejected this suggestion without accepting truth."
        case .defer:
            return "Deferred this suggestion for later review without accepting truth."
        }
    }

    private static func selector(_ candidateRef: String) -> (family: String, id: String)? {
        let parts = candidateRef.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (parts[0], parts[1])
    }

    private static func jsonString(_ dictionary: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(dictionary),
              let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
