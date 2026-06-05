import Foundation
import Testing
@testable import Cider

@MainActor
@Suite(.serialized)
struct CiderServicesProviderTests {
    @Test("Services text intake saves plain text through capture service")
    func servicesTextIntakeSavesPlainTextThroughCaptureService() throws {
        var capturedText: String?
        var failureToasts: [(message: String, isSuccess: Bool)] = []
        var receiptToasts: [(receipt: UICaptureReceipt, successMessage: String)] = []
        let provider = CiderServicesProvider(
            noteCaptureHandler: { text in
                capturedText = text
                return Self.captureResult(
                    sourceKind: "text",
                    itemType: "note",
                    title: "Service Note",
                    relativePath: "Inbox/Notes/Service Note.md"
                )
            },
            imageCaptureHandler: { _, _, _ in
                Issue.record("image capture should not run for text intake")
                return Self.captureResult(sourceKind: "image", itemType: "bookmark", title: "Image", relativePath: "Inbox/Bookmarks/Image.webloc")
            },
            toastHandler: { message, isSuccess in
                failureToasts.append((message, isSuccess))
            },
            receiptToastHandler: { receipt, successMessage in
                receiptToasts.append((receipt, successMessage))
            }
        )

        provider.handleText("  Save this from Services  ")
        let toast = try #require(receiptToasts.first)

        #expect(capturedText == "Save this from Services")
        #expect(failureToasts.isEmpty)
        #expect(toast.successMessage == "Created note from Services")
        #expect(toast.receipt.item.type == "note")
        #expect(toast.receipt.shortToastMessage(success: toast.successMessage) == "Created note from Services - review needed")
        #expect(toast.receipt.isSuccess)
    }

    @Test("Services URL intake posts rich receipt")
    func servicesURLIntakePostsRichReceipt() throws {
        var capturedURL: String?
        var receiptToasts: [(receipt: UICaptureReceipt, successMessage: String)] = []
        let provider = CiderServicesProvider(
            urlCaptureHandler: { url in
                capturedURL = url
                return Self.captureResult(
                    sourceKind: "url",
                    itemType: "bookmark",
                    title: "Service URL",
                    relativePath: "Inbox/Bookmarks/Service URL.webloc"
                )
            },
            noteCaptureHandler: { _ in
                Issue.record("note capture should not run for URL intake")
                return Self.captureResult(sourceKind: "text", itemType: "note", title: "Note", relativePath: "Inbox/Notes/Note.md")
            },
            imageCaptureHandler: { _, _, _ in
                Issue.record("image capture should not run for URL intake")
                return Self.captureResult(sourceKind: "image", itemType: "bookmark", title: "Image", relativePath: "Inbox/Bookmarks/Image.webloc")
            },
            receiptToastHandler: { receipt, successMessage in
                receiptToasts.append((receipt, successMessage))
            }
        )

        provider.handleText("https://example.com")
        let toast = try #require(receiptToasts.first)

        #expect(capturedURL == "https://example.com")
        #expect(toast.successMessage == "Saved from Services")
        #expect(toast.receipt.item.type == "bookmark")
        #expect(toast.receipt.shortToastMessage(success: toast.successMessage) == "Saved from Services - review needed")
    }

    @Test("Services image intake reports thumbnail partial success")
    func servicesImageIntakeReportsThumbnailPartialSuccess() throws {
        var failureToasts: [(message: String, isSuccess: Bool)] = []
        var receiptToasts: [(receipt: UICaptureReceipt, successMessage: String)] = []
        let provider = CiderServicesProvider(
            noteCaptureHandler: { _ in
                Issue.record("note capture should not run for image intake")
                return Self.captureResult(sourceKind: "text", itemType: "note", title: "Note", relativePath: "Inbox/Notes/Note.md")
            },
            imageCaptureHandler: { data, preferredExtension, sourceFile in
                #expect(data == Data([1, 2, 3]))
                #expect(preferredExtension == nil)
                #expect(sourceFile == nil)
                return Self.captureResult(
                    sourceKind: "image",
                    itemType: "bookmark",
                    title: "Image from Services",
                    relativePath: "Inbox/Bookmarks/Image from Services.webloc",
                    partialSuccess: .init(
                        status: "thumbnail_assignment_failed",
                        reason: "thumbnail failed",
                        requestedFolderID: nil,
                        actualFolderID: nil
                    )
                )
            },
            toastHandler: { message, isSuccess in
                failureToasts.append((message, isSuccess))
            },
            receiptToastHandler: { receipt, successMessage in
                receiptToasts.append((receipt, successMessage))
            }
        )

        provider.handleImage(Data([1, 2, 3]))
        let toast = try #require(receiptToasts.first)

        #expect(failureToasts.isEmpty)
        #expect(toast.successMessage == "Saved image from Services")
        #expect(toast.receipt.shortToastMessage(success: toast.successMessage) == "Saved image from Services - needs repair")
        #expect(!toast.receipt.isSuccess)
    }

    @Test("Services empty text intake is ignored")
    func servicesEmptyTextIntakeIsIgnored() throws {
        var toasts: [(message: String, isSuccess: Bool)] = []
        let provider = CiderServicesProvider(
            noteCaptureHandler: { _ in
                Issue.record("empty text should not be captured")
                return Self.captureResult(sourceKind: "text", itemType: "note", title: "Note", relativePath: "Inbox/Notes/Note.md")
            },
            imageCaptureHandler: { _, _, _ in
                Issue.record("image capture should not run for empty text")
                return Self.captureResult(sourceKind: "image", itemType: "bookmark", title: "Image", relativePath: "Inbox/Bookmarks/Image.webloc")
            },
            toastHandler: { message, isSuccess in
                toasts.append((message, isSuccess))
            }
        )

        provider.handleText("   ")

        #expect(toasts.isEmpty)
    }

    private static func captureResult(
        sourceKind: String,
        itemType: String,
        title: String,
        relativePath: String,
        partialSuccess: CiderCaptureResult.PartialSuccess? = nil
    ) -> CiderCaptureResult {
        let id = UUID()
        let target = CiderCaptureResult.Target(
            kind: "inbox",
            name: "Inbox",
            relativePath: (relativePath as NSString).deletingLastPathComponent,
            folderID: nil
        )
        return CiderCaptureResult(
            command: "capture.add",
            source: .init(kind: sourceKind, url: nil, file: nil, text: nil, itemID: id, itemType: itemType),
            item: .init(id: id, type: itemType, title: title, relativePath: relativePath, folderID: nil, folderName: target.name),
            enrichment: .init(status: "not_applicable", isEnriching: false, titleState: "manual", lastEnrichedAt: nil),
            duplicate: .init(status: "not_checked", existingItemID: nil),
            routing: .init(decisionID: UUID(), candidateTarget: target, reviewNeeded: true, confidence: 0, reason: "test", reviewState: "needs_review"),
            nextSafeAction: "review_route",
            partialSuccess: partialSuccess
        )
    }

}
