import Foundation
import Testing
@testable import Cider

struct CiderDetailNavigationPolicyTests {
    @Test("opening bookmark clears contact detail")
    func openingBookmarkClearsContactDetail() {
        #expect(CiderDetailNavigationPolicy.surfacesToClear(whenOpening: .bookmark).contains(.contact))
    }

    @Test("opening any detail keeps only the target surface")
    func openingAnyDetailKeepsOnlyTargetSurface() {
        for target in CiderDetailSurfaceKind.allCases {
            let cleared = CiderDetailNavigationPolicy.surfacesToClear(whenOpening: target)

            #expect(!cleared.contains(target))
            #expect(cleared.count == CiderDetailSurfaceKind.allCases.count - 1)
        }
    }

    @Test("opening kanban clears other detail surfaces")
    func openingKanbanClearsOtherDetailSurfaces() {
        let cleared = CiderDetailNavigationPolicy.surfacesToClear(whenOpening: .kanban)

        #expect(cleared.contains(.bookmark))
        #expect(cleared.contains(.note))
        #expect(cleared.contains(.todo))
        #expect(!cleared.contains(.kanban))
    }

    @Test("journal page mode routes to the generic detail page body")
    func journalPageModeRoutesToGenericDetailPageBody() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/Cider/Views/CiderPanelView+DetailViews.swift"),
            encoding: .utf8
        )

        #expect(source.contains("selectedVaultFile != nil || isJournalDetailOpen"))
        #expect(source.contains("} else if isJournalDetailOpen {\n            let projection = JournalLibraryReadModel.build(from: notesStorage.notes)"))
    }
}
