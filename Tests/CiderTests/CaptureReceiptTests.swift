import Testing
import Foundation
@testable import Cider

struct CaptureReceiptTests {
    @Test("complete capture maps to saved receipt")
    func completeCaptureMapsToSavedReceipt() {
        let receipt = CaptureReceipt(result: makeCaptureResult())

        #expect(receipt.state == .saved)
        #expect(receipt.didPersist)
        #expect(receipt.isSuccess)
        #expect(receipt.toastMessage(success: "Saved copied URL") == "Saved copied URL")
    }

    @Test("review-needed routing maps to saved with review")
    func reviewNeededRoutingMapsToSavedWithReview() {
        let receipt = CaptureReceipt(result: makeCaptureResult(
            routingReviewNeeded: true,
            nextSafeAction: "review_route"
        ))

        #expect(receipt.state == .savedWithReview)
        #expect(receipt.didPersist)
        #expect(receipt.isSuccess)
        #expect(receipt.toastMessage(success: "Saved dropped URL") == "Saved dropped URL - review needed")
    }

    @Test("duplicate capture maps to duplicate receipt")
    func duplicateCaptureMapsToDuplicateReceipt() {
        let existingID = UUID()
        let receipt = CaptureReceipt(result: makeCaptureResult(
            duplicate: .init(status: "duplicate", existingItemID: existingID)
        ))

        #expect(receipt.state == .duplicate)
        #expect(receipt.didPersist)
        #expect(receipt.isSuccess)
        #expect(receipt.toastMessage(success: "Saved copied URL") == "Already saved")
    }

    @Test("partial provenance or indexing maps to partial side effects")
    func partialProvenanceOrIndexingMapsToPartialSideEffects() {
        let receipt = CaptureReceipt(result: makeCaptureResult(
            indexing: .init(
                status: "failed",
                reason: "Index write failed.",
                ownerType: "bookmark",
                ownerID: UUID().uuidString,
                captureEventID: nil
            )
        ))

        #expect(receipt.state == .partialSideEffects)
        #expect(receipt.didPersist)
        #expect(!receipt.isSuccess)
        #expect(receipt.toastMessage(success: "Saved as bookmark") == "Saved as bookmark - needs repair")
    }

    @Test("explicit failure receipt does not persist")
    func explicitFailureReceiptDoesNotPersist() {
        let receipt = CaptureReceipt.failed("Could not save note")

        #expect(receipt.state == .failed)
        #expect(!receipt.didPersist)
        #expect(!receipt.isSuccess)
        #expect(receipt.toastMessage(success: "Saved as note") == "Could not save note")
    }

    private func makeCaptureResult(
        duplicate: CiderCaptureResult.Duplicate = .init(status: "new", existingItemID: nil),
        routingReviewNeeded: Bool = false,
        nextSafeAction: String = "none",
        partialSuccess: CiderCaptureResult.PartialSuccess? = nil,
        provenance: CiderCaptureResult.SideEffectStatus = .init(
            status: "recorded",
            reason: nil,
            ownerType: "bookmark",
            ownerID: UUID().uuidString,
            captureEventID: UUID()
        ),
        indexing: CiderCaptureResult.SideEffectStatus = .init(
            status: "indexed",
            reason: nil,
            ownerType: "bookmark",
            ownerID: UUID().uuidString,
            captureEventID: UUID()
        )
    ) -> CiderCaptureResult {
        let id = UUID()
        let target = CiderCaptureResult.Target(
            kind: "folder",
            name: "Inbox",
            relativePath: "Inbox",
            folderID: nil
        )
        return CiderCaptureResult(
            command: "capture.add",
            source: .init(
                kind: "url",
                url: "https://example.com",
                file: nil,
                text: nil,
                itemID: id,
                itemType: "bookmark"
            ),
            item: .init(
                id: id,
                type: "bookmark",
                title: "Example",
                relativePath: "Inbox/Example.md",
                folderID: nil,
                folderName: "Inbox"
            ),
            enrichment: .init(
                status: "not_applicable",
                isEnriching: false,
                titleState: "manual",
                lastEnrichedAt: nil
            ),
            duplicate: duplicate,
            routing: .init(
                decisionID: routingReviewNeeded ? UUID() : nil,
                candidateTarget: routingReviewNeeded ? target : nil,
                reviewNeeded: routingReviewNeeded,
                confidence: routingReviewNeeded ? 0.4 : 1,
                reason: routingReviewNeeded ? "Needs review." : "Confident route.",
                reviewState: routingReviewNeeded ? "needs_review" : "not_needed",
                status: routingReviewNeeded ? "recorded" : "not_applicable",
                statusReason: nil
            ),
            nextSafeAction: nextSafeAction,
            partialSuccess: partialSuccess,
            captureEventID: UUID(),
            sourceContext: nil,
            provenance: provenance,
            indexing: indexing
        )
    }
}
