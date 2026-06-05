import Foundation

struct CaptureReceipt: Equatable {
    enum State: String {
        case saved
        case savedWithReview
        case duplicate
        case partialSideEffects
        case failed
    }

    let state: State
    let itemID: UUID?
    let itemType: String?
    let title: String?
    private let failureMessage: String?

    init(result: CiderCaptureResult) {
        self.itemID = result.item.id
        self.itemType = result.item.type
        self.title = result.item.title
        self.failureMessage = nil

        if Self.hasPartialSideEffects(result) {
            self.state = .partialSideEffects
        } else if Self.isDuplicate(result.duplicate.status) {
            self.state = .duplicate
        } else if result.routing.reviewNeeded
            || result.routing.reviewState == "needs_review"
            || result.nextSafeAction == "review_route" {
            self.state = .savedWithReview
        } else {
            self.state = .saved
        }
    }

    private init(state: State, message: String) {
        self.state = state
        self.itemID = nil
        self.itemType = nil
        self.title = nil
        self.failureMessage = message
    }

    static func failed(_ message: String) -> CaptureReceipt {
        CaptureReceipt(state: .failed, message: message)
    }

    var didPersist: Bool {
        state != .failed
    }

    var isSuccess: Bool {
        switch state {
        case .saved, .savedWithReview, .duplicate:
            return true
        case .partialSideEffects, .failed:
            return false
        }
    }

    func toastMessage(success: String) -> String {
        switch state {
        case .saved:
            return success
        case .savedWithReview:
            return "\(success) - review needed"
        case .duplicate:
            return "Already saved"
        case .partialSideEffects:
            return "\(success) - needs repair"
        case .failed:
            return failureMessage ?? "Could not save"
        }
    }

    private static func isDuplicate(_ status: String) -> Bool {
        let normalized = status.lowercased()
        return normalized == "duplicate"
            || normalized == "existing"
            || normalized == "already_exists"
    }

    private static func hasPartialSideEffects(_ result: CiderCaptureResult) -> Bool {
        if result.partialSuccess != nil {
            return true
        }
        return [result.provenance.status, result.indexing.status, result.routing.status]
            .contains(where: isPartialSideEffectStatus)
    }

    private static func isPartialSideEffectStatus(_ status: String) -> Bool {
        let normalized = status.lowercased()
        return normalized == "failed"
            || normalized == "unavailable"
            || normalized == "error"
            || normalized.hasSuffix("_failed")
    }
}

struct UICaptureReceipt: Equatable {
    struct ItemSummary: Equatable {
        var id: UUID?
        var type: String?
        var title: String?
        var relativePath: String?
        var folderID: UUID?
        var folderName: String?
    }

    struct DuplicateSummary: Equatable {
        var status: String
        var existingItemID: UUID?
        var reason: String?
        var evidence: String?

        var isDuplicate: Bool {
            UICaptureReceipt.isDuplicate(status)
        }
    }

    struct TargetSummary: Equatable {
        var kind: String
        var name: String
        var relativePath: String
        var folderID: UUID?
    }

    struct RoutingSummary: Equatable {
        var reviewNeeded: Bool
        var confidence: Double
        var reason: String
        var reviewState: String
        var status: String
        var statusReason: String?
        var candidateTarget: TargetSummary?
    }

    struct SideEffectSummary: Equatable {
        var status: String
        var reason: String?
        var ownerType: String?
        var ownerID: String?
        var captureEventID: UUID?

        var isIncomplete: Bool {
            UICaptureReceipt.isIncompleteSideEffectStatus(status)
        }
    }

    struct CaptureQualitySummary: Equatable {
        var degraded: Bool
        var degradedReasons: [String]
        var needsEnrichment: Bool
        var safeNextAction: String?
    }

    struct StagedIntentSummary: Equatable {
        var kind: String
        var name: String
        var detail: String?
        var confidence: Double
        var reason: String
        var source: String
    }

    let state: CaptureReceipt.State
    let item: ItemSummary
    let duplicate: DuplicateSummary
    let routing: RoutingSummary
    let provenance: SideEffectSummary
    let indexing: SideEffectSummary
    let captureQuality: CaptureQualitySummary?
    let stagedIntents: [StagedIntentSummary]
    let nextSafeAction: String
    private let legacyReceipt: CaptureReceipt

    init(result: CiderCaptureResult) {
        self.legacyReceipt = CaptureReceipt(result: result)
        self.state = legacyReceipt.state
        self.item = .init(
            id: result.item.id,
            type: result.item.type,
            title: result.item.title,
            relativePath: result.item.relativePath,
            folderID: result.item.folderID,
            folderName: result.item.folderName
        )
        self.duplicate = .init(
            status: result.duplicate.status,
            existingItemID: result.duplicate.existingItemID,
            reason: result.duplicate.reason,
            evidence: result.duplicate.evidence
        )
        self.routing = .init(
            reviewNeeded: result.routing.reviewNeeded,
            confidence: result.routing.confidence,
            reason: result.routing.reason,
            reviewState: result.routing.reviewState,
            status: result.routing.status,
            statusReason: result.routing.statusReason,
            candidateTarget: result.routing.candidateTarget.map {
                .init(
                    kind: $0.kind,
                    name: $0.name,
                    relativePath: $0.relativePath,
                    folderID: $0.folderID
                )
            }
        )
        self.provenance = .init(status: result.provenance)
        self.indexing = .init(status: result.indexing)
        self.captureQuality = result.captureQuality.map(Self.captureQualitySummary)
        self.stagedIntents = result.stagedIntents.map(Self.stagedIntentSummary)
        self.nextSafeAction = result.nextSafeAction
    }

    init(receipt: CaptureReceipt) {
        self.legacyReceipt = receipt
        self.state = receipt.state
        self.item = .init(
            id: receipt.itemID,
            type: receipt.itemType,
            title: receipt.title,
            relativePath: nil,
            folderID: nil,
            folderName: nil
        )
        self.duplicate = .init(status: receipt.state == .duplicate ? "duplicate" : "not_applicable", existingItemID: nil)
        self.routing = .init(
            reviewNeeded: receipt.state == .savedWithReview,
            confidence: 0,
            reason: "",
            reviewState: receipt.state == .savedWithReview ? "needs_review" : "not_applicable",
            status: "not_applicable",
            statusReason: nil,
            candidateTarget: nil
        )
        self.provenance = .notApplicable
        self.indexing = .notApplicable
        self.captureQuality = nil
        self.stagedIntents = []
        self.nextSafeAction = receipt.state == .savedWithReview ? "review_route" : "inspect_item"
    }

    var safeNextActionLabel: String {
        if let qualityAction = captureQuality?.safeNextAction, !qualityAction.isEmpty {
            return Self.humanizeAction(qualityAction)
        }
        return Self.humanizeAction(nextSafeAction)
    }

    func shortToastMessage(success: String) -> String {
        legacyReceipt.toastMessage(success: success)
    }

    private static func captureQualitySummary(_ dictionary: [String: Any]) -> CaptureQualitySummary {
        .init(
            degraded: dictionary["degraded"] as? Bool ?? false,
            degradedReasons: dictionary["degradedReasons"] as? [String] ?? [],
            needsEnrichment: dictionary["needsEnrichment"] as? Bool ?? false,
            safeNextAction: dictionary["safeNextAction"] as? String
        )
    }

    private static func stagedIntentSummary(_ intent: CiderCaptureResult.StagedIntent) -> StagedIntentSummary {
        switch intent.kind {
        case let .space(spaceName, area):
            return .init(
                kind: "space",
                name: spaceName,
                detail: area,
                confidence: intent.confidence,
                reason: intent.reason,
                source: intent.source
            )
        case let .project(projectName):
            return .init(
                kind: "project",
                name: projectName,
                detail: nil,
                confidence: intent.confidence,
                reason: intent.reason,
                source: intent.source
            )
        case let .entity(entityName, entityType):
            return .init(
                kind: "entity",
                name: entityName,
                detail: entityType,
                confidence: intent.confidence,
                reason: intent.reason,
                source: intent.source
            )
        }
    }

    private static func humanizeAction(_ action: String) -> String {
        let words = action
            .split(separator: "_")
            .map(String.init)
        guard let first = words.first else { return "Inspect item" }
        return ([first.capitalized] + words.dropFirst()).joined(separator: " ")
    }

    private static func isDuplicate(_ status: String) -> Bool {
        let normalized = status.lowercased()
        return normalized == "duplicate"
            || normalized == "existing"
            || normalized == "already_exists"
    }

    private static func isIncompleteSideEffectStatus(_ status: String) -> Bool {
        let normalized = status.lowercased()
        return normalized == "failed"
            || normalized == "unavailable"
            || normalized == "error"
            || normalized.hasSuffix("_failed")
    }
}

private extension UICaptureReceipt.SideEffectSummary {
    init(status: CiderCaptureResult.SideEffectStatus) {
        self.init(
            status: status.status,
            reason: status.reason,
            ownerType: status.ownerType,
            ownerID: status.ownerID,
            captureEventID: status.captureEventID
        )
    }

    static var notApplicable: Self {
        .init(
            status: "not_applicable",
            reason: nil,
            ownerType: nil,
            ownerID: nil,
            captureEventID: nil
        )
    }
}
