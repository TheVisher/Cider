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
