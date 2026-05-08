import Testing
@testable import Cider

@MainActor
struct CiderWindowJankPerformanceProbeTests {
    @Test("window jank probe compares empty Kanban, populated Kanban, and library masonry")
    func comparesItemCountScaledScenarios() {
        let report = CiderWindowJankPerformanceProbe.measure(iterations: 1)
        for line in report.summaryLines {
            print("WINDOW_JANK_PROBE \(line)")
        }

        #expect(report.scenarios.map(\.scenario) == [
            .emptyKanban,
            .populatedKanban,
            .libraryMasonry
        ])
        #expect(report.scenarios.allSatisfy { $0.ranOnMainThread })
        #expect(report.scenarios.allSatisfy { $0.iterations == 1 })

        let empty = report[.emptyKanban]
        let populated = report[.populatedKanban]
        let library = report[.libraryMasonry]

        #expect(empty.visibleItemCount == 0)
        #expect(populated.visibleItemCount > empty.visibleItemCount)
        #expect(library.visibleItemCount > populated.visibleItemCount)
        #expect(populated.workUnitCount > empty.workUnitCount)
        #expect(library.workUnitCount > populated.workUnitCount)

        #expect(report.slowestScenario?.scenario == .populatedKanban)
        #expect(report.largestWorkScenario?.scenario == .libraryMasonry)
        #expect(report.recommendation.contains("Populated Kanban"))
        #expect(report.summaryLines.contains { $0.contains("visible items") })
    }
}
