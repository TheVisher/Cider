import Foundation
import Testing
@testable import Cider

@Suite("Bookmark Summary Sanitization Tests")
@MainActor
struct BookmarkSummarySanitizationTests {
    @Test("privacy troubleshooting reader failures are not saved as AI summaries")
    func privacyTroubleshootingReaderFailuresAreNotSavedAsAISummaries() async {
        SummaryService.shared._setSummarizeArticleOverrideForTesting { _ in
            "There was a privacy-related issue with the website x.com. To resolve this, the user should disable any privacy-related extensions and try again."
        }
        defer { SummaryService.shared._resetSummarizeArticleOverrideForTesting() }

        let summary = await SummaryService.shared.summarize(articleText: "X post content placeholder")

        #expect(summary == nil)
    }

    @Test("normal summaries still pass through")
    func normalSummariesStillPassThrough() async {
        SummaryService.shared._setSummarizeArticleOverrideForTesting { _ in
            "IGN shared a first look at Hands Over, a multiplayer horror party game built around childhood-game nostalgia. The post highlights the trailer reveal and tone rather than browser troubleshooting."
        }
        defer { SummaryService.shared._resetSummarizeArticleOverrideForTesting() }

        let summary = await SummaryService.shared.summarize(articleText: "IGN post text")

        #expect(summary?.contains("Hands Over") == true)
    }
}
