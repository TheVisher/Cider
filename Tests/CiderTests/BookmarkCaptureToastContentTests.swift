import Foundation
import Testing
@testable import Cider

struct BookmarkCaptureToastContentTests {
    @Test("simple toast content preserves message fallback")
    func simpleToastContentPreservesMessageFallback() {
        let content = BookmarkCaptureToastContent(message: "Bookmark updated", isSuccess: true)

        #expect(content.kind == .simple)
        #expect(content.iconSystemName == "checkmark.circle.fill")
        #expect(content.title == "Bookmark updated")
        #expect(content.subtitle == nil)
        #expect(content.badges.isEmpty)
        #expect(content.contentHeight == BookmarksToastDesign.height)
        #expect(content.titleLineLimit == 2)
    }

    @Test("rich saved receipt content preserves title type and destination")
    func richSavedReceiptContentPreservesTitleTypeAndDestination() {
        let receipt = UICaptureReceipt(result: makeCaptureResult(
            title: "A very long page title that should be allowed to wrap cleanly inside the toast",
            relativePath: "Inbox/Links/Example.md",
            folderName: "Links"
        ))
        let content = BookmarkCaptureToastContent(
            receipt: receipt,
            successMessage: "Saved copied URL"
        )

        #expect(content.kind == .receipt)
        #expect(content.iconSystemName == "checkmark.circle.fill")
        #expect(content.title == "A very long page title that should be allowed to wrap cleanly inside the toast")
        #expect(content.subtitle == "Bookmark - Links")
        #expect(content.badges == ["Saved copied URL"])
        #expect(content.contentHeight == BookmarksToastDesign.richHeight)
        #expect(content.titleLineLimit == 2)
    }

    @Test("rich duplicate receipt content exposes duplicate badge")
    func richDuplicateReceiptContentExposesDuplicateBadge() {
        let receipt = UICaptureReceipt(result: makeCaptureResult(
            duplicate: .init(
                status: "duplicate",
                existingItemID: UUID(),
                reason: "URL already exists",
                evidence: "normalized_url"
            )
        ))
        let content = BookmarkCaptureToastContent(receipt: receipt, successMessage: "Saved copied URL")

        #expect(content.kind == .receipt)
        #expect(content.badges.contains("Already saved"))
        #expect(content.badges.contains("Duplicate"))
    }

    @Test("rich review receipt content exposes review destination")
    func richReviewReceiptContentExposesReviewDestination() {
        let receipt = UICaptureReceipt(result: makeCaptureResult(
            routingReviewNeeded: true,
            nextSafeAction: "review_route"
        ))
        let content = BookmarkCaptureToastContent(receipt: receipt, successMessage: "Saved dropped URL")

        #expect(content.badges.contains("Review needed"))
        #expect(content.badges.contains("Review route"))
        #expect(content.subtitle == "Bookmark - Inbox")
    }

    @Test("rich partial receipt content exposes repair badge")
    func richPartialReceiptContentExposesRepairBadge() {
        let receipt = UICaptureReceipt(result: makeCaptureResult(
            indexing: .init(
                status: "failed",
                reason: "Index write failed.",
                ownerType: "bookmark",
                ownerID: UUID().uuidString,
                captureEventID: nil
            )
        ))
        let content = BookmarkCaptureToastContent(receipt: receipt, successMessage: "Saved copied URL")

        #expect(content.iconSystemName == "exclamationmark.triangle.fill")
        #expect(content.badges.contains("Needs repair"))
        #expect(content.badges.contains("Indexing failed"))
    }

    @Test("rich degraded receipt content exposes quality badge")
    func richDegradedReceiptContentExposesQualityBadge() {
        let receipt = UICaptureReceipt(result: makeCaptureResult(
            captureQuality: [
                "degraded": true,
                "degradedReasons": ["missing_title"],
                "needsEnrichment": true,
            ]
        ))
        let content = BookmarkCaptureToastContent(receipt: receipt, successMessage: "Saved copied URL")

        #expect(content.badges.contains("Needs enrichment"))
        #expect(content.badges.contains("Quality warning"))
    }

    private func makeCaptureResult(
        title: String = "Example",
        relativePath: String? = "Inbox/Example.md",
        folderName: String = "Inbox",
        duplicate: CiderCaptureResult.Duplicate = .init(status: "new", existingItemID: nil),
        routingReviewNeeded: Bool = false,
        nextSafeAction: String = "none",
        indexing: CiderCaptureResult.SideEffectStatus = .init(
            status: "indexed",
            reason: nil,
            ownerType: "bookmark",
            ownerID: UUID().uuidString,
            captureEventID: UUID()
        ),
        captureQuality: [String: Any]? = nil
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
                title: title,
                relativePath: relativePath,
                folderID: nil,
                folderName: folderName
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
            captureEventID: UUID(),
            provenance: .init(
                status: "recorded",
                reason: nil,
                ownerType: "bookmark",
                ownerID: UUID().uuidString,
                captureEventID: UUID()
            ),
            indexing: indexing,
            captureQuality: captureQuality
        )
    }
}
