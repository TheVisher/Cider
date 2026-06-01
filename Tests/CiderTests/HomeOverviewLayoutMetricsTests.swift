import XCTest
@testable import Cider

final class HomeOverviewLayoutMetricsTests: XCTestCase {
    func testOverviewPanelHeightAbsorbsNeedsAttentionStructure() {
        let metrics = HomeOverviewLayoutMetrics(snapshot: makeSnapshot())

        XCTAssertGreaterThan(metrics.requiredHeight(for: .overview), HomeOverviewDesign.topRowMinHeight)
    }

    func testTopRowHeightIsDrivenByOverviewInsteadOfSeparateAttentionPanel() {
        let metrics = HomeOverviewLayoutMetrics(snapshot: makeSnapshot())

        XCTAssertEqual(metrics.topRowHeight, metrics.requiredHeight(for: .overview))
        XCTAssertGreaterThan(metrics.topRowHeight, metrics.requiredHeight(for: .profile))
    }

    func testActivityRowHeightUsesStableUpcomingBaselineWhenFeedIsShort() {
        let metrics = HomeOverviewLayoutMetrics(snapshot: makeSnapshot(recentCount: 1, upcomingCount: 1))

        XCTAssertEqual(metrics.activityRowHeight, HomeOverviewDesign.upcomingPanelFixedHeight)
    }

    func testActivityRowHeightExpandsWhenRecentActivityNeedsMoreRoom() {
        let metrics = HomeOverviewLayoutMetrics(snapshot: makeSnapshot(recentCount: 6, upcomingCount: 1))

        XCTAssertGreaterThan(metrics.activityRowHeight, HomeOverviewDesign.upcomingPanelFixedHeight)
        XCTAssertEqual(metrics.activityRowHeight, metrics.requiredHeight(for: .recentActivity))
    }

    func testActivityTimelineUsesStableTimelinePanelHeight() {
        let metrics = HomeOverviewLayoutMetrics(snapshot: makeSnapshot(recentCount: 6))

        XCTAssertEqual(metrics.requiredHeight(for: .activityTimeline), HomeOverviewDesign.activityTimelinePanelHeight)
    }

    func testFullLayoutTracksFillAvailableWidthWithSharedGutters() {
        let tracks = HomeOverviewFullLayoutTracks(availableWidth: 1200, gap: 12)

        XCTAssertEqual(
            tracks.first + tracks.second + tracks.third + tracks.fourth + (tracks.gap * 3),
            1200,
            accuracy: 0.001
        )
        XCTAssertEqual(tracks.recentWidth, tracks.first + tracks.gap + tracks.second, accuracy: 0.001)
        XCTAssertEqual(tracks.upcomingWidth, tracks.third + tracks.gap + tracks.fourth, accuracy: 0.001)
        XCTAssertEqual(tracks.pinnedWidth, tracks.second + tracks.gap + tracks.third + tracks.gap + tracks.fourth, accuracy: 0.001)
    }

    private func makeSnapshot(
        recentCount: Int = 4,
        upcomingCount: Int = 1,
        resurfacedCount: Int = 2
    ) -> HomeOverviewSnapshot {
        HomeOverviewSnapshot(
            telemetry: [],
            dailyBrief: HomeDailyBrief(
                dateLabel: "Monday, Apr 13",
                greetingBucket: .morning,
                summary: "Summary",
                summaryParts: [],
                focusItems: []
            ),
            pulse: "Active",
            overviewSummary: "Summary",
            overviewChips: [
                HomeOverviewChip(id: "recent", title: "Recent", value: 4, target: .inbox),
                HomeOverviewChip(id: "unfiled", title: "Unfiled", value: 2, target: .inbox)
            ],
            attentionMetrics: [
                HomeAttentionMetric(id: "unfiled", title: "Unfiled", value: 4, target: .inbox),
                HomeAttentionMetric(id: "urgent", title: "Urgent", value: 1, target: .inbox),
                HomeAttentionMetric(id: "dueToday", title: "Due Today", value: 2, target: .inbox),
                HomeAttentionMetric(id: "untitledNotes", title: "Untitled Notes", value: 1, target: .inbox)
            ],
            recentItems: Array(repeating: makeItem(title: "Recent"), count: recentCount),
            recentCaptureItems: Array(repeating: makeRecentCapture(title: "Recent"), count: recentCount),
            upcomingItems: Array(repeating: makeItem(title: "Upcoming"), count: upcomingCount),
            todoItems: [],
            completedTodoItems: [],
            resurfacedItems: Array(repeating: makeItem(title: "Resurfaced"), count: resurfacedCount),
            reviewCockpitItems: [],
            reviewCockpitSummary: HomeReviewCockpitSummary(
                totalCount: 0,
                badges: [],
                itemTypeCounts: [:],
                reviewStateCounts: [:],
                safeActionCounts: [:],
                groups: [],
                batchEnrichmentPreview: HomeReviewCockpitBatchEnrichmentPreview(
                    action: "review.enrich",
                    isMutating: false,
                    candidateCount: 0,
                    candidateSampleLimit: 0,
                    candidateSampleTitles: [],
                    excludedCount: 0,
                    exclusionsByReason: [:]
                ),
                generatedAt: Date(timeIntervalSince1970: 1_745_084_400)
            ),
            triageItems: [],
            kanbanPulseItems: []
        )
    }

    private func makeItem(title: String) -> LibraryItemV2 {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        return .note(
            Note(
                id: UUID(),
                title: title,
                createdAt: now,
                modifiedAt: now
            )
        )
    }

    private func makeRecentCapture(title: String) -> HomeRecentCaptureItem {
        let item = makeItem(title: title)
        return HomeRecentCaptureItem(
            id: UUID().uuidString,
            item: item,
            title: title,
            typeLabel: "Note",
            sourceTypeLabel: "Text",
            itemTypeLabel: "Note",
            locationLabel: "Inbox / Unfiled",
            destinationLabel: "Inbox / Unfiled",
            reviewState: "ok",
            reviewNeeded: false,
            suggestedAction: "Open",
            safeFollowUpActions: ["Open item"],
            surfacingExplanation: CiderSurfacingExplanation(
                reason: "Layout test item",
                urgency: "normal",
                sourceSignal: "test",
                reviewState: "ok",
                suggestedAction: "Open",
                actionURLString: nil
            )
        )
    }

}
