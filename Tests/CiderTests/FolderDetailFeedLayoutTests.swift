import Testing
@testable import Cider

struct FolderDetailFeedLayoutTests {
    @Test("folder detail feed width subtracts direct card padding")
    func availableWidthSubtractsCardPadding() {
        let width = FolderDetailFeedLayout.availableWidth(
            contentWidth: 900,
            appliesCardPadding: true
        )

        #expect(width == 872)
    }

    @Test("folder detail feed width keeps list and kanban full width")
    func availableWidthKeepsUnpaddedLayoutsFullWidth() {
        let width = FolderDetailFeedLayout.availableWidth(
            contentWidth: 900,
            appliesCardPadding: false
        )

        #expect(width == 900)
    }

    @Test("folder detail feed layout identity changes when available width changes")
    func layoutIdentityChangesWithAvailableWidth() {
        let narrow = FolderDetailFeedLayout.layoutIdentity(
            displayMode: .grid,
            availableWidth: 760,
            minimumCardWidth: 240
        )
        let wide = FolderDetailFeedLayout.layoutIdentity(
            displayMode: .grid,
            availableWidth: 1_000,
            minimumCardWidth: 240
        )

        #expect(narrow != wide)
    }
}
