import Foundation
import Testing
@testable import Cider

@MainActor
@Suite(.serialized)
struct CiderServicesProviderTests {
    @Test("Services text intake saves plain text through capture service")
    func servicesTextIntakeSavesPlainTextThroughCaptureService() throws {
        var capturedText: String?
        var toasts: [(message: String, isSuccess: Bool)] = []
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
                toasts.append((message, isSuccess))
            }
        )

        provider.handleText("  Save this from Services  ")
        let toast = try #require(toasts.first)

        #expect(capturedText == "Save this from Services")
        #expect(toast.message == "Created note from Services - review needed")
        #expect(toast.isSuccess == true)
    }

    @Test("Services image intake reports thumbnail partial success")
    func servicesImageIntakeReportsThumbnailPartialSuccess() throws {
        var toasts: [(message: String, isSuccess: Bool)] = []
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
                toasts.append((message, isSuccess))
            }
        )

        provider.handleImage(Data([1, 2, 3]))
        let toast = try #require(toasts.first)

        #expect(toast.message == "Saved image from Services - needs repair")
        #expect(toast.isSuccess == false)
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
