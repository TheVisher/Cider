import Foundation
import Testing
@testable import Cider

struct SearchPaletteSearchPublishPolicyTests {
    @Test("cancelled searches do not publish results")
    func cancelledSearchesDoNotPublishResults() {
        #expect(!SearchPaletteSearchPublishPolicy.canPublish(
            taskQuery: "needle",
            currentQuery: "needle",
            isCancelled: true
        ))
    }

    @Test("superseded searches do not publish stale results")
    func supersededSearchesDoNotPublishStaleResults() {
        #expect(!SearchPaletteSearchPublishPolicy.canPublish(
            taskQuery: "old query",
            currentQuery: "new query",
            isCancelled: false
        ))
    }

    @Test("current non-cancelled search publishes results")
    func currentNonCancelledSearchPublishesResults() {
        #expect(SearchPaletteSearchPublishPolicy.canPublish(
            taskQuery: "needle",
            currentQuery: "  needle  ",
            isCancelled: false
        ))
    }

    @Test("typing with the full query selected replaces instead of appending")
    func fullSelectionTypingReplacesQueryInsteadOfAppending() {
        let original = "Jami smores"
        let result = SearchPaletteQueryEditing.replacingSelectedText(
            in: original,
            selection: 0..<original.count,
            replacement: "Botan Ramen"
        )

        #expect(result == "Botan Ramen")
    }

    @Test("typing without a selection still inserts at the caret")
    func caretTypingStillInsertsAtCaret() {
        let result = SearchPaletteQueryEditing.replacingSelectedText(
            in: "Botan",
            selection: 5..<5,
            replacement: " Ramen"
        )

        #expect(result == "Botan Ramen")
    }

    @Test("normal result selection previews without changing the current route")
    func normalResultSelectionPreviewsWithoutChangingCurrentRoute() throws {
        let noteID = UUID()
        let currentRoute = WorkspaceRoute.projects(.workspace(projectID: "cider", section: .docs))
        let result = SearchResult(
            id: noteID,
            type: .note,
            title: "Preview me",
            subtitle: nil,
            snippet: nil,
            date: Date(),
            note: Note(id: noteID, title: "Preview me", content: "Keep the route still")
        )

        let action = try #require(SearchPaletteResultSelectionPolicy.action(
            for: result,
            mode: .preview,
            currentRoute: currentRoute
        ))

        #expect(action.previewRef == LibraryEntityRef(type: .note, entityID: noteID))
        #expect(action.routeAfterSelection == currentRoute)
        #expect(action.sourceRoute == nil)
    }

    @Test("source result selection is distinct and may navigate to Library")
    func sourceResultSelectionIsDistinctAndMayNavigateToLibrary() throws {
        let bookmarkID = UUID()
        let currentRoute = WorkspaceRoute.spaces(.manager)
        let result = SearchResult(
            id: bookmarkID,
            type: .bookmark,
            title: "Source me",
            subtitle: nil,
            snippet: nil,
            date: Date(),
            bookmark: Bookmark(id: bookmarkID, title: "Source me", urlString: "https://example.com")
        )

        let action = try #require(SearchPaletteResultSelectionPolicy.action(
            for: result,
            mode: .showInLibrary,
            currentRoute: currentRoute
        ))

        #expect(action.previewRef == LibraryEntityRef(type: .bookmark, entityID: bookmarkID))
        #expect(action.routeAfterSelection == .library(.bookmarks))
        #expect(action.sourceRoute == .library(.bookmarks))
    }
}
