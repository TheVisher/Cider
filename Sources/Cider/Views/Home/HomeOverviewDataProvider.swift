import Foundation

enum HomeOverviewDataProvider {
    static func makeSnapshot(
        items: [LibraryItemV2],
        recentItems: [LibraryItemV2],
        folders: [Folder],
        savedViews: [SavedView] = [],
        tabOrder: [UUID] = [],
        surfacingDays: Int,
        now: Date = Date()
    ) -> HomeOverviewSnapshot {
        let unfiledCount = items.filter { $0.folderID == nil }.count
        let urgentCount = urgentCount(in: items, surfacingDays: surfacingDays, now: now)
        let dueTodayCount = dueTodayCount(in: items, now: now)
        let untitledNotesCount = untitledNotesCount(in: items)

        let telemetry = [
            HomeTelemetryMetric(
                kind: .bookmarks,
                value: items.filter { if case .bookmark = $0 { return true }; return false }.count,
                target: savedViewTarget(name: "Bookmarks", entityTypes: [.bookmark], sortMode: .createdDescending)
            ),
            HomeTelemetryMetric(
                kind: .notes,
                value: items.filter { if case .note = $0 { return true }; return false }.count,
                target: savedViewTarget(name: "Notes", entityTypes: [.note], sortMode: .updatedDescending)
            ),
            HomeTelemetryMetric(
                kind: .todos,
                value: items.filter { if case .todo = $0 { return true }; return false }.count,
                target: savedViewTarget(name: "Todos", entityTypes: [.todo], sortMode: .dateUpcoming)
            ),
            HomeTelemetryMetric(
                kind: .events,
                value: items.filter { if case .dateCard = $0 { return true }; return false }.count,
                target: savedViewTarget(name: "Events", entityTypes: [.dateCard], sortMode: .dateUpcoming)
            ),
            HomeTelemetryMetric(kind: .unfiled, value: unfiledCount, target: .inbox),
            HomeTelemetryMetric(
                kind: .urgent,
                value: urgentCount,
                target: savedViewTarget(name: "Urgent", entityTypes: [.todo, .dateCard], sortMode: .dateUpcoming)
            )
        ]

        let upcomingItems = items
            .filter { item in
                switch item {
                case .dateCard(let dateCard):
                    return dateCard.urgency(now: now, windowDays: surfacingDays) != nil
                case .todo(let todo):
                    return todo.urgency(now: now, windowDays: surfacingDays) != nil
                default:
                    return false
                }
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.dateAnchor ?? lhs.updatedDate
                let rhsDate = rhs.dateAnchor ?? rhs.updatedDate
                return lhsDate < rhsDate
            }

        let resurfacedItems = items
            .filter { !$0.isCompleted }
            .filter { item in
                guard recentItems.contains(item) == false else { return false }
                return item.updatedDate <= now.addingTimeInterval(-(60 * 60 * 24 * 14))
            }
            .sorted { lhs, rhs in
                lhs.updatedDate < rhs.updatedDate
            }
            .prefix(4)
            .map { $0 }

        let openTabIDs = Set(tabOrder)
        let closedTabs = savedViews
            .filter { savedView in
                !openTabIDs.contains(savedView.id) && !savedView.isOnboarding
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { savedView in
                HomeOverviewClosedTabSummary(
                    id: savedView.id,
                    name: savedView.name,
                    kind: savedView.kind,
                    updatedAt: savedView.updatedAt
                )
            }

        return HomeOverviewSnapshot(
            telemetry: telemetry,
            pulse: pulseText(unfiledCount: unfiledCount, urgentCount: urgentCount),
            overviewSummary: overviewText(
                recentCount: recentItems.count,
                dueTodayCount: dueTodayCount,
                urgentCount: urgentCount,
                resurfacedCount: resurfacedItems.count
            ),
            overviewChips: [
                HomeOverviewChip(
                    id: "recent",
                    title: "Recent",
                    value: recentItems.count,
                    target: savedViewTarget(
                        name: "Recent Activity",
                        entityTypes: LibraryEntityType.activeCases,
                        sortMode: .updatedDescending
                    )
                ),
                HomeOverviewChip(id: "unfiled", title: "Unfiled", value: unfiledCount, target: .inbox),
                HomeOverviewChip(
                    id: "dueToday",
                    title: "Due Today",
                    value: dueTodayCount,
                    target: savedViewTarget(name: "Upcoming", entityTypes: [.todo, .dateCard], sortMode: .dateUpcoming)
                ),
                HomeOverviewChip(
                    id: "resurfaced",
                    title: "Resurfaced",
                    value: resurfacedItems.count,
                    target: savedViewTarget(
                        name: "Resurface",
                        entityTypes: LibraryEntityType.activeCases,
                        sortMode: .updatedAscending
                    )
                )
            ],
            attentionMetrics: [
                HomeAttentionMetric(id: "unfiled", title: "Unfiled", value: unfiledCount, target: .inbox),
                HomeAttentionMetric(
                    id: "urgent",
                    title: "Urgent",
                    value: urgentCount,
                    target: savedViewTarget(name: "Urgent", entityTypes: [.todo, .dateCard], sortMode: .dateUpcoming)
                ),
                HomeAttentionMetric(
                    id: "dueToday",
                    title: "Due Today",
                    value: dueTodayCount,
                    target: savedViewTarget(name: "Upcoming", entityTypes: [.todo, .dateCard], sortMode: .dateUpcoming)
                ),
                HomeAttentionMetric(
                    id: "untitledNotes",
                    title: "Untitled Notes",
                    value: untitledNotesCount,
                    target: savedViewTarget(name: "Notes", entityTypes: [.note], sortMode: .updatedDescending)
                )
            ],
            recentItems: Array(recentItems.prefix(4)),
            upcomingItems: Array(upcomingItems.prefix(4)),
            resurfacedItems: resurfacedItems,
            closedTabs: closedTabs
        )
    }

    private static func urgentCount(in items: [LibraryItemV2], surfacingDays: Int, now: Date) -> Int {
        items.reduce(into: 0) { count, item in
            switch item {
            case .dateCard(let dateCard):
                if dateCard.urgency(now: now, windowDays: surfacingDays) != nil {
                    count += 1
                }
            case .todo(let todo):
                if todo.urgency(now: now, windowDays: surfacingDays) != nil {
                    count += 1
                }
            default:
                break
            }
        }
    }

    private static func pulseText(unfiledCount: Int, urgentCount: Int) -> String {
        switch (unfiledCount, urgentCount) {
        case (0...2, 0...1):
            return "Calm and under control."
        case (_, 4...):
            return "Busy and time-sensitive."
        case (8..., _):
            return "Active, slightly backlogged."
        default:
            return "Active, with a few loose ends."
        }
    }

    private static func dueTodayCount(in items: [LibraryItemV2], now: Date) -> Int {
        let calendar = Calendar.current
        return items.reduce(into: 0) { count, item in
            switch item {
            case .dateCard(let dateCard):
                if !dateCard.isCompleted && calendar.isDate(dateCard.effectiveDate(now: now), inSameDayAs: now) {
                    count += 1
                }
            case .todo(let todo):
                if !todo.isCompleted, let dueDate = todo.dueDate, calendar.isDate(dueDate, inSameDayAs: now) {
                    count += 1
                }
            default:
                break
            }
        }
    }

    private static func untitledNotesCount(in items: [LibraryItemV2]) -> Int {
        items.reduce(into: 0) { count, item in
            guard case .note(let note) = item else { return }
            let normalized = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized.isEmpty || normalized.hasPrefix("Untitled") {
                count += 1
            }
        }
    }

    private static func overviewText(
        recentCount: Int,
        dueTodayCount: Int,
        urgentCount: Int,
        resurfacedCount: Int
    ) -> String {
        "You have \(recentCount) recent captures, \(dueTodayCount) items due today, \(urgentCount) time-sensitive threads, and \(resurfacedCount) older cards worth revisiting."
    }

    private static func savedViewTarget(
        name: String,
        entityTypes: Set<LibraryEntityType>,
        sortMode: LibrarySortMode
    ) -> HomeOverviewActionTarget {
        .savedView(
            name: name,
            filterSpec: SavedViewFilterSpec(entityTypes: entityTypes),
            sortMode: sortMode
        )
    }
}
