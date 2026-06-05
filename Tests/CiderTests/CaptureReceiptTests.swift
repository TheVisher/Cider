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

    @Test("UI receipt preserves saved item destination and compatible toast message")
    func uiReceiptPreservesSavedItemDestinationAndCompatibleToast() {
        let itemID = UUID()
        let receipt = UICaptureReceipt(result: makeCaptureResult(itemID: itemID))

        #expect(receipt.state == .saved)
        #expect(receipt.item.id == itemID)
        #expect(receipt.item.type == "bookmark")
        #expect(receipt.item.title == "Example")
        #expect(receipt.item.relativePath == "Inbox/Example.md")
        #expect(receipt.item.folderName == "Inbox")
        #expect(receipt.shortToastMessage(success: "Saved copied URL") == "Saved copied URL")
    }

    @Test("UI receipt preserves duplicate evidence")
    func uiReceiptPreservesDuplicateEvidence() {
        let existingID = UUID()
        let receipt = UICaptureReceipt(result: makeCaptureResult(
            duplicate: .init(
                status: "duplicate",
                existingItemID: existingID,
                reason: "URL already exists",
                evidence: "normalized_url"
            )
        ))

        #expect(receipt.state == .duplicate)
        #expect(receipt.duplicate.isDuplicate)
        #expect(receipt.duplicate.existingItemID == existingID)
        #expect(receipt.duplicate.reason == "URL already exists")
        #expect(receipt.duplicate.evidence == "normalized_url")
        #expect(receipt.shortToastMessage(success: "Saved copied URL") == "Already saved")
    }

    @Test("UI receipt preserves review route details and safe action label")
    func uiReceiptPreservesReviewRouteDetails() {
        let receipt = UICaptureReceipt(result: makeCaptureResult(
            routingReviewNeeded: true,
            nextSafeAction: "review_route"
        ))

        #expect(receipt.state == .savedWithReview)
        #expect(receipt.routing.reviewNeeded)
        #expect(receipt.routing.reason == "Needs review.")
        #expect(receipt.routing.reviewState == "needs_review")
        #expect(receipt.routing.status == "recorded")
        #expect(receipt.routing.candidateTarget?.name == "Inbox")
        #expect(receipt.routing.candidateTarget?.relativePath == "Inbox")
        #expect(receipt.safeNextActionLabel == "Review route")
    }

    @Test("UI receipt preserves partial side effect status")
    func uiReceiptPreservesPartialSideEffectStatus() {
        let receipt = UICaptureReceipt(result: makeCaptureResult(
            provenance: .init(
                status: "failed",
                reason: "Provenance write failed.",
                ownerType: "bookmark",
                ownerID: UUID().uuidString,
                captureEventID: nil
            ),
            indexing: .init(
                status: "indexed",
                reason: nil,
                ownerType: "bookmark",
                ownerID: UUID().uuidString,
                captureEventID: UUID()
            )
        ))

        #expect(receipt.state == .partialSideEffects)
        #expect(receipt.provenance.status == "failed")
        #expect(receipt.provenance.reason == "Provenance write failed.")
        #expect(receipt.provenance.isIncomplete)
        #expect(receipt.indexing.status == "indexed")
        #expect(!receipt.indexing.isIncomplete)
    }

    @Test("UI receipt preserves degraded quality reasons")
    func uiReceiptPreservesDegradedQualityReasons() {
        let receipt = UICaptureReceipt(result: makeCaptureResult(
            nextSafeAction: "enrich",
            captureQuality: [
                "degraded": true,
                "degradedReasons": ["missing_title", "missing_preview"],
                "needsEnrichment": true,
                "safeNextAction": "enrich",
            ]
        ))

        #expect(receipt.captureQuality?.degraded == true)
        #expect(receipt.captureQuality?.needsEnrichment == true)
        #expect(receipt.captureQuality?.degradedReasons == ["missing_title", "missing_preview"])
        #expect(receipt.safeNextActionLabel == "Enrich")
    }

    @Test("UI receipt preserves staged intent summary")
    func uiReceiptPreservesStagedIntentSummary() {
        let receipt = UICaptureReceipt(result: makeCaptureResult(
            routingReviewNeeded: true,
            nextSafeAction: "review_intent",
            stagedIntents: [
                .init(
                    kind: .space(spaceName: "Garden", area: "Research"),
                    confidence: 0.82,
                    reason: "Mentions the Garden space.",
                    source: "agent"
                ),
            ]
        ))

        #expect(receipt.stagedIntents.count == 1)
        #expect(receipt.stagedIntents[0].kind == "space")
        #expect(receipt.stagedIntents[0].name == "Garden")
        #expect(receipt.stagedIntents[0].detail == "Research")
        #expect(receipt.stagedIntents[0].confidence == 0.82)
        #expect(receipt.stagedIntents[0].reason == "Mentions the Garden space.")
        #expect(receipt.safeNextActionLabel == "Review intent")
    }

    @Test("UI receipt can bridge from legacy failed receipt")
    func uiReceiptCanBridgeFromLegacyFailedReceipt() {
        let receipt = UICaptureReceipt(receipt: .failed("Could not save clipboard text"))

        #expect(receipt.state == .failed)
        #expect(receipt.item.id == nil)
        #expect(receipt.shortToastMessage(success: "Saved note") == "Could not save clipboard text")
    }

    private func makeCaptureResult(
        itemID: UUID = UUID(),
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
        ),
        captureQuality: [String: Any]? = nil,
        stagedIntents: [CiderCaptureResult.StagedIntent] = []
    ) -> CiderCaptureResult {
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
                itemID: itemID,
                itemType: "bookmark"
            ),
            item: .init(
                id: itemID,
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
            indexing: indexing,
            captureQuality: captureQuality,
            stagedIntents: stagedIntents
        )
    }
}
