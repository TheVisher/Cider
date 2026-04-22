import Foundation

enum HomeTelemetryMetricKind: String, CaseIterable, Equatable {
    case bookmarks
    case notes
    case todos
    case events
    case unfiled
    case urgent

    var title: String {
        switch self {
        case .bookmarks: "Bookmarks"
        case .notes: "Notes"
        case .todos: "Todos"
        case .events: "Events"
        case .unfiled: "Unfiled"
        case .urgent: "Urgent"
        }
    }
}

enum HomeOverviewActionTarget: Equatable {
    case inbox
    case savedView(name: String, filterSpec: SavedViewFilterSpec, sortMode: LibrarySortMode)
}

struct HomeTelemetryMetric: Equatable, Identifiable {
    let kind: HomeTelemetryMetricKind
    let value: Int
    let target: HomeOverviewActionTarget

    var id: HomeTelemetryMetricKind { kind }
}

struct HomeOverviewChip: Equatable, Identifiable {
    let id: String
    let title: String
    let value: Int
    let target: HomeOverviewActionTarget
}

struct HomeAttentionMetric: Equatable, Identifiable {
    let id: String
    let title: String
    let value: Int
    let target: HomeOverviewActionTarget
}

struct HomeOverviewClosedTabSummary: Equatable, Identifiable {
    let id: UUID
    let name: String
    let kind: SavedViewKind
    let updatedAt: Date
}

struct HomeOverviewSnapshot: Equatable {
    let telemetry: [HomeTelemetryMetric]
    let pulse: String
    let overviewSummary: String
    let overviewChips: [HomeOverviewChip]
    let attentionMetrics: [HomeAttentionMetric]
    let recentItems: [LibraryItemV2]
    let upcomingItems: [LibraryItemV2]
    let resurfacedItems: [LibraryItemV2]
    let closedTabs: [HomeOverviewClosedTabSummary]
}

enum HomeOverviewPanelID {
    case pulse
    case overview
    case profile
    case recentActivity
    case upcoming
    case resurface
    case closedTabs
}

struct HomeOverviewLayoutMetrics {
    let snapshot: HomeOverviewSnapshot

    func requiredHeight(for panel: HomeOverviewPanelID) -> CGFloat {
        switch panel {
        case .pulse:
            return HomeOverviewDesign.topRowMinHeight
        case .overview:
            return HomeOverviewDesign.overviewPanelFixedHeight
        case .profile:
            return HomeOverviewDesign.profilePanelFixedHeight
        case .recentActivity:
            return max(
                HomeOverviewDesign.recentActivityBaseHeight,
                88 + (CGFloat(max(snapshot.recentItems.count, 1)) * HomeOverviewDesign.recentActivityRowHeightEstimate)
            )
        case .upcoming:
            return HomeOverviewDesign.upcomingPanelFixedHeight
        case .resurface:
            let visibleCardCount = min(snapshot.resurfacedItems.count, 2)
            let rowCount = CGFloat(max((visibleCardCount + 1) / 2, 1))
            return max(
                HomeOverviewDesign.resurfacePanelMinHeight,
                96 + (rowCount * HomeOverviewDesign.resurfacePanelRowHeightEstimate)
            )
        case .closedTabs:
            return snapshot.closedTabs.isEmpty
                ? HomeOverviewDesign.closedTabsBaseMinHeight
                : HomeOverviewDesign.closedTabsPanelMinHeight
        }
    }

    var topRowHeight: CGFloat {
        max(
            requiredHeight(for: .pulse),
            requiredHeight(for: .overview),
            requiredHeight(for: .profile)
        )
    }

    var activityRowHeight: CGFloat {
        max(
            requiredHeight(for: .recentActivity),
            requiredHeight(for: .upcoming)
        )
    }

    var bottomRowHeight: CGFloat {
        max(
            requiredHeight(for: .resurface),
            requiredHeight(for: .closedTabs)
        )
    }
}

struct HomeOverviewFullLayoutTracks {
    let first: CGFloat
    let second: CGFloat
    let third: CGFloat
    let fourth: CGFloat
    let gap: CGFloat

    init(availableWidth: CGFloat, gap: CGFloat = HomeOverviewDesign.columnSpacing) {
        let usableWidth = max(0, availableWidth - (gap * 3))
        let totalWeight = HomeOverviewDesign.fullLayoutTrackWeights.reduce(0, +)
        let widths = HomeOverviewDesign.fullLayoutTrackWeights.map { weight in
            usableWidth * (weight / totalWeight)
        }

        self.first = widths[safe: 0] ?? 0
        self.second = widths[safe: 1] ?? 0
        self.third = widths[safe: 2] ?? 0
        self.fourth = widths[safe: 3] ?? 0
        self.gap = gap
    }

    var pulseWidth: CGFloat { first }
    var overviewWidth: CGFloat { second + gap + third }
    var attentionWidth: CGFloat { fourth }
    var recentWidth: CGFloat { first + gap + second }
    var upcomingWidth: CGFloat { third + gap + fourth }
    var resurfaceWidth: CGFloat { first }
    var pinnedWidth: CGFloat { second + gap + third + gap + fourth }
}

private extension Array where Element == CGFloat {
    subscript(safe index: Int) -> CGFloat? {
        indices.contains(index) ? self[index] : nil
    }
}
