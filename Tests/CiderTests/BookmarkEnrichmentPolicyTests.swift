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
}
