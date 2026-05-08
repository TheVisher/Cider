import CoreGraphics
import Foundation

/// Repeatable, non-visual probes for the window-drag/live-resize jank path.
///
/// These probes intentionally avoid rendering SwiftUI. They exercise the pure layout
/// and per-visible-item work that scales when Cider publishes many tiny window width
/// changes during dragging/resizing. The elapsed time is useful as local evidence,
/// while `workUnitCount` is the stable cross-machine signal for item-count scaling.
@MainActor
enum CiderWindowJankPerformanceProbe {
    static let defaultIterations = 1
    static let widthSamples = Array(stride(from: CGFloat(720), through: CGFloat(1120), by: CGFloat(1)))

    static func measure(iterations: Int = defaultIterations) -> CiderWindowJankPerformanceReport {
        let iterations = max(iterations, 1)
        let scenarios: [CiderWindowJankScenarioSample] = [
            measureEmptyKanban(iterations: iterations),
            measurePopulatedKanban(iterations: iterations),
            measureLibraryMasonry(iterations: iterations)
        ]
        return CiderWindowJankPerformanceReport(scenarios: scenarios)
    }

    private static func measureEmptyKanban(iterations: Int) -> CiderWindowJankScenarioSample {
        let board = KanbanBoard(
            id: "empty-kanban",
            name: "Empty Probe",
            columns: [
                KanbanColumn(id: "backlog", name: "Backlog"),
                KanbanColumn(id: "queued", name: "Queued"),
                KanbanColumn(id: "in_progress", name: "In Progress"),
                KanbanColumn(id: "done", name: "Done", isDoneColumn: true)
            ]
        )
        return measureScenario(
            scenario: .emptyKanban,
            visibleItemCount: 0,
            iterations: iterations
        ) {
            var workUnits = 0
            for width in widthSamples {
                _ = KanbanBoardLayout.usesProjectLayout(for: board)
                _ = KanbanBoardLayout.lanes(for: board)
                _ = KanbanBoardLayout.shouldPushArchive(
                    activeColumnCount: board.columns.count,
                    archiveColumnCount: 0,
                    availableWidth: width,
                    columnWidth: KanbanDesign.columnWidth,
                    spacing: Spacing.md,
                    archiveExpanded: false
                )
                for column in board.columns {
                    workUnits += KanbanBoardLayout.cardGroups(for: column, in: board).count
                }
            }
            return workUnits
        }
    }

    private static func measurePopulatedKanban(iterations: Int) -> CiderWindowJankScenarioSample {
        let board = makePopulatedKanbanBoard(columnCount: 6, cardsPerColumn: 30)
        return measureScenario(
            scenario: .populatedKanban,
            visibleItemCount: board.allCards.count,
            iterations: iterations
        ) {
            var workUnits = 0
            for width in widthSamples {
                _ = KanbanBoardLayout.usesProjectLayout(for: board)
                _ = KanbanBoardLayout.lanes(for: board)
                _ = KanbanBoardLayout.shouldPushArchive(
                    activeColumnCount: board.columns.count,
                    archiveColumnCount: 0,
                    availableWidth: width,
                    columnWidth: KanbanDesign.columnWidth,
                    spacing: Spacing.md,
                    archiveExpanded: false
                )
                for column in board.columns {
                    let groups = KanbanBoardLayout.cardGroups(for: column, in: board)
                    for group in groups {
                        workUnits += measureKanbanNode(group.parent, column: column, board: board)
                        for child in group.children {
                            workUnits += measureKanbanNode(child, column: column, board: board)
                        }
                    }
                }
            }
            return workUnits
        }
    }

    private static func measureLibraryMasonry(iterations: Int) -> CiderWindowJankScenarioSample {
        let items = (0..<1_000).map { ProbeMasonryItem(id: $0, baseHeight: CGFloat(132 + ($0 % 9) * 18)) }
        return measureScenario(
            scenario: .libraryMasonry,
            visibleItemCount: items.count,
            iterations: iterations
        ) {
            var workUnits = 0
            var previousPlan = LazyMasonryColumnPlanner.Plan<Int>.empty
            for width in widthSamples {
                let layout = LazyMasonryColumnPlanner.layout(
                    containerWidth: width,
                    minimumColumnWidth: 220,
                    itemSpacing: Spacing.md
                )
                let plan = LazyMasonryColumnPlanner.stablePlan(
                    items: items,
                    layout: layout,
                    itemSpacing: Spacing.md,
                    estimatedHeight: { item in
                        workUnits += 1 // thumbnail/card height estimate work
                        return item.baseHeight + layout.columnWidth * 0.18
                    },
                    previousPlan: previousPlan
                )
                previousPlan = plan
                workUnits += items.count // per-visible-item frame/body/render proxy
            }
            return workUnits
        }
    }

    private static func measureScenario(
        scenario: CiderWindowJankScenario,
        visibleItemCount: Int,
        iterations: Int,
        work: () -> Int
    ) -> CiderWindowJankScenarioSample {
        var totalWorkUnits = 0
        let start = Date()
        for _ in 0..<iterations {
            totalWorkUnits += work()
        }
        let elapsed = Date().timeIntervalSince(start)
        return CiderWindowJankScenarioSample(
            scenario: scenario,
            visibleItemCount: visibleItemCount,
            widthSampleCount: widthSamples.count,
            iterations: iterations,
            workUnitCount: totalWorkUnits,
            elapsedSeconds: elapsed,
            ranOnMainThread: Thread.isMainThread
        )
    }

    private static func measureKanbanNode(
        _ node: KanbanColumnCardNode,
        column: KanbanColumn,
        board: KanbanBoard
    ) -> Int {
        _ = KanbanBoardLayout.previewText(for: node.card)
        _ = KanbanBoardLayout.parentBadge(for: node.card, in: column, board: board)
        _ = KanbanBoardLayout.planIndicator(for: node.card, in: board)
        _ = KanbanBoardLayout.childSummary(for: node.card.id, in: board)
        _ = KanbanBoardLayout.cardAccentColor(for: node.card, in: board)
        return 1
    }

    private static func makePopulatedKanbanBoard(columnCount: Int, cardsPerColumn: Int) -> KanbanBoard {
        let columns = (0..<columnCount).map { columnIndex in
            let columnID = "column-\(columnIndex)"
            let cards = (0..<cardsPerColumn).map { cardIndex in
                let isChild = cardIndex > 0 && cardIndex % 5 == 0
                let parentID = isChild ? "card-\(columnIndex)-\(cardIndex - 1)" : nil
                return KanbanCard(
                    id: "card-\(columnIndex)-\(cardIndex)",
                    title: "Card \(columnIndex)-\(cardIndex)",
                    notes: "Problem:\n- Probe card with enough text to exercise preview trimming.\n\nAcceptance criteria:\n- Keep layout measurement deterministic.",
                    color: KanbanCardColor.allCases[(columnIndex + cardIndex) % KanbanCardColor.allCases.count],
                    priority: cardIndex % 3 == 0 ? .high : .medium,
                    tags: ["performance", "probe", "column-\(columnIndex)"],
                    parentCardID: parentID
                )
            }
            return KanbanColumn(
                id: columnID,
                name: columnIndex == columnCount - 1 ? "Done" : "Column \(columnIndex)",
                isDoneColumn: columnIndex == columnCount - 1,
                cards: cards
            )
        }
        return KanbanBoard(id: "populated-kanban", name: "Cider", columns: columns)
    }

    private struct ProbeMasonryItem: Identifiable {
        let id: Int
        let baseHeight: CGFloat
    }
}

enum CiderWindowJankScenario: String, Codable, CaseIterable, Sendable {
    case emptyKanban
    case populatedKanban
    case libraryMasonry

    var title: String {
        switch self {
        case .emptyKanban: "Empty Kanban"
        case .populatedKanban: "Populated Kanban"
        case .libraryMasonry: "Library masonry"
        }
    }
}

struct CiderWindowJankScenarioSample: Codable, Equatable, Sendable {
    let scenario: CiderWindowJankScenario
    let visibleItemCount: Int
    let widthSampleCount: Int
    let iterations: Int
    let workUnitCount: Int
    let elapsedSeconds: TimeInterval
    let ranOnMainThread: Bool

    var workUnitsPerVisibleItem: Double {
        guard visibleItemCount > 0 else { return 0 }
        return Double(workUnitCount) / Double(visibleItemCount)
    }
}

struct CiderWindowJankPerformanceReport: Codable, Equatable, Sendable {
    let scenarios: [CiderWindowJankScenarioSample]

    subscript(_ scenario: CiderWindowJankScenario) -> CiderWindowJankScenarioSample {
        guard let sample = scenarios.first(where: { $0.scenario == scenario }) else {
            preconditionFailure("Missing performance scenario: \(scenario.rawValue)")
        }
        return sample
    }

    var slowestScenario: CiderWindowJankScenarioSample? {
        scenarios.max { lhs, rhs in
            if lhs.elapsedSeconds == rhs.elapsedSeconds {
                return lhs.workUnitCount < rhs.workUnitCount
            }
            return lhs.elapsedSeconds < rhs.elapsedSeconds
        }
    }

    var largestWorkScenario: CiderWindowJankScenarioSample? {
        scenarios.max { lhs, rhs in
            if lhs.workUnitCount == rhs.workUnitCount {
                return lhs.elapsedSeconds < rhs.elapsedSeconds
            }
            return lhs.workUnitCount < rhs.workUnitCount
        }
    }

    var recommendation: String {
        switch slowestScenario?.scenario {
        case .libraryMasonry:
            "Library masonry is the slowest measured non-visual path; profile item card rendering, thumbnails, and per-item SwiftUI body work next."
        case .populatedKanban:
            "Populated Kanban is the slowest measured non-visual path; profile per-card view recomputation and hierarchy metadata work next."
        case .emptyKanban:
            "Empty Kanban is unexpectedly slowest; focus on baseline window/container redraw overhead before item rendering."
        case nil:
            "No scenarios measured."
        }
    }

    var summaryLines: [String] {
        scenarios.map { sample in
            "\(sample.scenario.title): \(sample.visibleItemCount) visible items, \(sample.widthSampleCount) width samples, \(sample.workUnitCount) work units, \(String(format: "%.6f", sample.elapsedSeconds))s"
        } + [recommendation]
    }
}
