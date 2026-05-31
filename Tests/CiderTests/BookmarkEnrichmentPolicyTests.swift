import Foundation
import Testing
@testable import Cider

@Suite("Bookmark Enrichment Policy Tests")
@MainActor
struct BookmarkEnrichmentPolicyTests {
    @Test("X generic title still uses rendered metadata fallback when HTML has thumbnail")
    func xGenericTitleStillUsesRenderedFallbackWithHTMLThumbnail() throws {
        let url = try #require(URL(string: "https://x.com/alexfinn/status/2053272800757272887?s=12"))

        #expect(VaultBookmarkService.shouldAttemptRenderedMetadataFallback(
            pageURL: url,
            htmlTitle: "X.Com",
            hasRealThumbnail: true
        ))
    }

    @Test("TikTok generic title uses OCR as visible title candidate")
    func tiktokGenericTitleUsesOCRAsVisibleTitleCandidate() {
        let suggested = BookmarkAIEnrichment.suggestedTitleFromOCR(
            "Richmond night market 5/29/26 BAU BOT TITKE",
            currentTitle: "TikTok - Make Your Day",
            urlString: "https://www.tiktok.com/t/ZP8poHUSr/",
            titleManuallySet: false
        )

        #expect(suggested == "Richmond Night Market 5/29/26")
    }

    @Test("TikTok OCR title candidate does not replace manual title")
    func tiktokOCRTitleCandidateDoesNotReplaceManualTitle() {
        let suggested = BookmarkAIEnrichment.suggestedTitleFromOCR(
            "Richmond night market 5/29/26",
            currentTitle: "My TikTok Dinner Ideas",
            urlString: "https://www.tiktok.com/t/ZP8poHUSr/",
            titleManuallySet: true
        )

        #expect(suggested == nil)
    }

    @Test("TikTok generic title uses recipe notes as visible title candidate")
    func tiktokGenericTitleUsesRecipeNotesAsVisibleTitleCandidate() {
        let suggested = BookmarkAIEnrichment.suggestedTitleFromNotes(
            "this viral smores bark is about to be your annual summer little treat after dinner\nBy ashleymarkletreats\nVia TikTok",
            currentTitle: "TikTok - Make Your Day",
            urlString: "https://www.tiktok.com/t/ZP8s1eSw4/",
            titleManuallySet: false
        )

        #expect(suggested == "Viral Smores Bark")
    }
}
