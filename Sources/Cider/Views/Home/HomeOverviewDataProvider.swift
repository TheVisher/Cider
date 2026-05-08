import Foundation

enum HomeOverviewDataProvider {
    static func dailyBriefGreetingText(
        for brief: HomeDailyBrief,
        displayName: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "there" : displayName
        let variants: [String]
        switch brief.greetingBucket {
        case .morning:
            variants = [
                "Good morning, \(name). Let's make the day useful without making it dramatic.",
                "Morning, \(name). The vault is awake and mostly behaving.",
                "Good morning, \(name). A few threads are waiting, but nothing here gets to shout."
            ]
        case .afternoon:
            variants = [
                "Good afternoon, \(name). A clean middle chapter for the day.",
                "Afternoon, \(name). Let's pull the useful threads forward.",
                "Good afternoon, \(name). The vault has notes, nudges, and a little composure."
            ]
        case .evening:
            variants = [
                "Good evening, \(name). Time to sort the day gently.",
                "Evening, \(name). We can tidy the loose ends without turning it into a quest.",
                "Good evening, \(name). The dashboard brought receipts, but politely."
            ]
        case .lateNight:
            variants = [
                "Still up, \(name)? Cider is awake too, but with concerns.",
                "Late night, \(name). We can be productive, but let's not get weird about it.",
                "Hello, \(name). The vault is open, the hour is questionable, and we proceed."
            ]
        }

        let components = calendar.dateComponents([.day, .hour], from: now)
        let seed = (components.day ?? 0) + (components.hour ?? 0) + brief.focusItems.count
        return variants[seed % variants.count]
    }

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
        let agendaBriefing = AgendaBriefingService.build(
            todos: items.compactMap { if case .todo(let todo) = $0 { return todo }; return nil },
            dateCards: items.compactMap { if case .dateCard(let dateCard) = $0 { return dateCard }; return nil },
            now: now
        )
        let agendaSurfaceItems = agendaBriefing.items.filter(\.surfaceToday)
        let urgentCount = agendaSurfaceItems.count
        let dueTodayCount = agendaSurfaceItems.filter { $0.status == .today }.count
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
        let triageItems = triageItems(from: items)

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

        let recentTarget = savedViewTarget(
            name: "Recent Activity",
            entityTypes: LibraryEntityType.activeCases,
            sortMode: .updatedDescending
        )
        let upcomingTarget = savedViewTarget(
            name: "Upcoming",
            entityTypes: [.todo, .dateCard],
            sortMode: .dateUpcoming
        )
        let resurfaceTarget = savedViewTarget(
            name: "Resurface",
            entityTypes: LibraryEntityType.activeCases,
            sortMode: .updatedAscending
        )
        let urgentTarget = savedViewTarget(
            name: "Urgent",
            entityTypes: [.todo, .dateCard],
            sortMode: .dateUpcoming
        )
        let notesTarget = savedViewTarget(
            name: "Notes",
            entityTypes: [.note],
            sortMode: .updatedDescending
        )

        return HomeOverviewSnapshot(
            telemetry: telemetry,
            dailyBrief: HomeDailyBrief(
                dateLabel: briefDateLabel(now),
                greetingBucket: greetingBucket(for: now),
                summary: overviewText(
                    recentCount: recentItems.count,
                    dueTodayCount: dueTodayCount,
                    urgentCount: urgentCount,
                    resurfacedCount: resurfacedItems.count
                ),
                summaryParts: dailyBriefSummaryParts(
                    recentCount: recentItems.count,
                    unfiledCount: unfiledCount,
                    dueTodayCount: dueTodayCount,
                    urgentCount: urgentCount,
                    resurfacedCount: resurfacedItems.count,
                    recentTarget: recentTarget,
                    inboxTarget: .inbox,
                    upcomingTarget: upcomingTarget,
                    urgentTarget: urgentTarget,
                    resurfaceTarget: resurfaceTarget
                ),
                focusItems: dailyBriefFocusItems(
                    agendaItems: Array(agendaSurfaceItems.prefix(3)),
                    libraryItems: items,
                    unfiledCount: unfiledCount,
                    urgentCount: urgentCount,
                    dueTodayCount: dueTodayCount,
                    resurfacedItems: resurfacedItems,
                    inboxTarget: .inbox,
                    urgentTarget: urgentTarget,
                    upcomingTarget: upcomingTarget,
                    resurfaceTarget: resurfaceTarget
                )
            ),
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
                    target: recentTarget
                ),
                HomeOverviewChip(id: "unfiled", title: "Unfiled", value: unfiledCount, target: .inbox),
                HomeOverviewChip(
                    id: "dueToday",
                    title: "Due Today",
                    value: dueTodayCount,
                    target: upcomingTarget
                ),
                HomeOverviewChip(
                    id: "resurfaced",
                    title: "Resurfaced",
                    value: resurfacedItems.count,
                    target: resurfaceTarget
                )
            ],
            attentionMetrics: [
                HomeAttentionMetric(id: "unfiled", title: "Unfiled", value: unfiledCount, target: .inbox),
                HomeAttentionMetric(
                    id: "urgent",
                    title: "Urgent",
                    value: urgentCount,
                    target: urgentTarget
                ),
                HomeAttentionMetric(
                    id: "dueToday",
                    title: "Due Today",
                    value: dueTodayCount,
                    target: upcomingTarget
                ),
                HomeAttentionMetric(
                    id: "untitledNotes",
                    title: "Untitled Notes",
                    value: untitledNotesCount,
                    target: notesTarget
                )
            ],
            recentItems: Array(recentItems.prefix(4)),
            upcomingItems: Array(upcomingItems.prefix(4)),
            todoItems: Array(todoQueueItems(from: items, now: now).prefix(6)),
            completedTodoItems: Array(completedTodoItems(from: items).prefix(4)),
            resurfacedItems: resurfacedItems,
            triageItems: triageItems,
            closedTabs: closedTabs
        )
    }

    private static func todoQueueItems(from items: [LibraryItemV2], now: Date) -> [TodoCard] {
        items.compactMap { item -> TodoCard? in
            if case .todo(let todo) = item, !todo.isCompleted {
                return todo
            }
            return nil
        }
        .sorted { lhs, rhs in
            let lhsRank = todoSortRank(lhs, now: now)
            let rhsRank = todoSortRank(rhs, now: now)
            if lhsRank != rhsRank { return lhsRank < rhsRank }

            if lhs.priority != rhs.priority {
                return priorityRank(lhs.priority) < priorityRank(rhs.priority)
            }

            let lhsDate = lhs.earliestApproachingDate ?? lhs.updatedAt
            let rhsDate = rhs.earliestApproachingDate ?? rhs.updatedAt
            if lhsDate != rhsDate { return lhsDate < rhsDate }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private static func completedTodoItems(from items: [LibraryItemV2]) -> [TodoCard] {
        items.compactMap { item -> TodoCard? in
            if case .todo(let todo) = item, todo.isCompleted {
                return todo
            }
            return nil
        }
        .sorted { lhs, rhs in
            (lhs.completedAt ?? lhs.updatedAt) > (rhs.completedAt ?? rhs.updatedAt)
        }
    }

    private static func todoSortRank(_ todo: TodoCard, now: Date) -> Int {
        guard let target = todo.earliestApproachingDate else { return 3 }
        let calendar = Calendar.current
        if target < calendar.startOfDay(for: now) { return 0 }
        if calendar.isDate(target, inSameDayAs: now) { return 1 }
        return 2
    }

    private static func priorityRank(_ priority: TodoPriority?) -> Int {
        switch priority {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        case nil: return 3
        }
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

    private static func triageItems(from items: [LibraryItemV2]) -> [HomeTriageItem] {
        items
            .compactMap(triageItem(for:))
            .sorted { lhs, rhs in
                let lhsPriority = triageSortPriority(lhs)
                let rhsPriority = triageSortPriority(rhs)
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                if lhs.item.createdDate != rhs.item.createdDate {
                    return lhs.item.createdDate > rhs.item.createdDate
                }
                return lhs.item.title.localizedCaseInsensitiveCompare(rhs.item.title) == .orderedAscending
            }
            .prefix(6)
            .map { $0 }
    }

    private static func triageItem(for item: LibraryItemV2) -> HomeTriageItem? {
        switch item {
        case .bookmark(let bookmark):
            if bookmarkNeedsEnrichment(bookmark) {
                return HomeTriageItem(
                    id: "triage-\(item.id)-enrichment",
                    item: item,
                    reason: bookmarkGenericTitleReason(bookmark) ?? "Bookmark needs enrichment",
                    suggestedAction: "Enrich and route",
                    confidenceLabel: "Needs approval"
                )
            }
            if bookmark.folderID == nil {
                return HomeTriageItem(
                    id: "triage-\(item.id)-folder",
                    item: item,
                    reason: "Still in Inbox / unfiled",
                    suggestedAction: "Route to folder",
                    confidenceLabel: "Needs approval"
                )
            }
        case .note(let note):
            if note.folderID == nil || isInboxPath(note.relativePath) || isUntitled(note.title) {
                return HomeTriageItem(
                    id: "triage-\(item.id)-note",
                    item: item,
                    reason: isUntitled(note.title) ? "Untitled inbox note" : "Inbox note needs routing",
                    suggestedAction: "Ask Erik",
                    confidenceLabel: "Low confidence"
                )
            }
        case .vaultFile(let file):
            if file.folderID == nil || isInboxPath(file.relativePath) || file.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                return HomeTriageItem(
                    id: "triage-\(item.id)-file",
                    item: item,
                    reason: "Unfiled vault file",
                    suggestedAction: "Route to folder",
                    confidenceLabel: "Needs approval"
                )
            }
        case .dateCard, .contact, .todo:
            return nil
        }
        return nil
    }

    private static func triageSortPriority(_ item: HomeTriageItem) -> Int {
        switch item.suggestedAction {
        case "Enrich and route": 0
        case "Route to folder": 1
        default: 2
        }
    }

    private static func bookmarkNeedsEnrichment(_ bookmark: Bookmark) -> Bool {
        if bookmark.enrichmentStatus != "complete" || bookmark.lastEnrichedAt == nil {
            return true
        }
        return bookmarkGenericTitleReason(bookmark) != nil
    }

    private static func bookmarkGenericTitleReason(_ bookmark: Bookmark) -> String? {
        let title = bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let host = bookmark.hostDisplay.lowercased()
        guard !title.isEmpty else { return "Missing bookmark title" }
        if title == host || title == host.replacingOccurrences(of: "www.", with: "") {
            return "Generic host-only bookmark title"
        }
        if title == bookmark.urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            return "URL-only bookmark title"
        }
        return nil
    }

    private static func isInboxPath(_ path: String?) -> Bool {
        guard let path else { return false }
        return path.lowercased().hasPrefix("inbox/")
    }

    private static func isUntitled(_ title: String) -> Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("untitled")
    }

    private static func dailyBriefFocusItems(
        agendaItems: [AgendaBriefingItem],
        libraryItems: [LibraryItemV2],
        unfiledCount: Int,
        urgentCount: Int,
        dueTodayCount: Int,
        resurfacedItems: [LibraryItemV2],
        inboxTarget: HomeOverviewActionTarget,
        urgentTarget: HomeOverviewActionTarget,
        upcomingTarget: HomeOverviewActionTarget,
        resurfaceTarget: HomeOverviewActionTarget
    ) -> [HomeDailyBriefItem] {
        var briefItems = agendaItems.prefix(2).map { agendaItem in
            HomeDailyBriefItem(
                id: "agenda-\(agendaItem.id)",
                title: agendaItem.title,
                subtitle: agendaItem.reason,
                systemImage: agendaItem.itemType == .todo ? "checkmark.circle" : "calendar.badge.clock",
                target: libraryItems.first(where: { $0.id == "\(agendaItem.itemType.rawValue)-\(agendaItem.id.uuidString)" }).map { .item($0) } ?? .action(upcomingTarget)
            )
        }

        if dueTodayCount > 0, briefItems.contains(where: { $0.id == "due-today" }) == false {
            briefItems.append(
                HomeDailyBriefItem(
                    id: "due-today",
                    title: "\(dueTodayCount) due today",
                    subtitle: "Start with the calendar before the vault gets loud.",
                    systemImage: "calendar.badge.clock",
                    target: .action(upcomingTarget)
                )
            )
        } else if urgentCount > 0 {
            briefItems.append(
                HomeDailyBriefItem(
                    id: "urgent",
                    title: "\(urgentCount) time-sensitive",
                    subtitle: "Worth checking before you settle into deeper work.",
                    systemImage: "exclamationmark.circle",
                    target: .action(urgentTarget)
                )
            )
        }

        if unfiledCount > 0 {
            briefItems.append(
                HomeDailyBriefItem(
                    id: "unfiled",
                    title: "\(unfiledCount) unfiled captures",
                    subtitle: "A small tidy-up would make future you suspiciously pleased.",
                    systemImage: "tray",
                    target: .action(inboxTarget)
                )
            )
        } else if let resurfaced = resurfacedItems.first {
            briefItems.append(
                HomeDailyBriefItem(
                    id: "resurface-\(resurfaced.id)",
                    title: resurfaced.title,
                    subtitle: "An older item worth revisiting.",
                    systemImage: resurfaced.dashboardSymbol,
                    target: .item(resurfaced)
                )
            )
        } else if !resurfacedItems.isEmpty {
            briefItems.append(
                HomeDailyBriefItem(
                    id: "resurface",
                    title: "\(resurfacedItems.count) older items",
                    subtitle: "There are a few quiet threads worth revisiting.",
                    systemImage: "sparkle.magnifyingglass",
                    target: .action(resurfaceTarget)
                )
            )
        }

        return Array(briefItems.prefix(3))
    }

    private static func greetingBucket(for now: Date) -> HomeDailyBriefGreetingBucket {
        let hour = Calendar.current.component(.hour, from: now)
        switch hour {
        case 5..<12:
            return .morning
        case 12..<17:
            return .afternoon
        case 17..<23:
            return .evening
        default:
            return .lateNight
        }
    }

    private static func briefDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
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

    private static func dailyBriefSummaryParts(
        recentCount: Int,
        unfiledCount: Int,
        dueTodayCount: Int,
        urgentCount: Int,
        resurfacedCount: Int,
        recentTarget: HomeOverviewActionTarget,
        inboxTarget: HomeOverviewActionTarget,
        upcomingTarget: HomeOverviewActionTarget,
        urgentTarget: HomeOverviewActionTarget,
        resurfaceTarget: HomeOverviewActionTarget
    ) -> [HomeDailyBriefSummaryPart] {
        var chips: [HomeDailyBriefSummaryChip] = []

        if dueTodayCount > 0 {
            chips.append(.init(id: "dueToday", label: "\(dueTodayCount) due today", target: upcomingTarget))
        }
        if urgentCount > 0 {
            chips.append(.init(id: "urgent", label: "\(urgentCount) time-sensitive", target: urgentTarget))
        }
        if unfiledCount > 0 {
            chips.append(.init(id: "unfiled", label: "\(unfiledCount) unfiled", target: inboxTarget))
        }
        if resurfacedCount > 0 {
            chips.append(.init(id: "resurfaced", label: "\(resurfacedCount) resurfaced", target: resurfaceTarget))
        }
        if chips.isEmpty, recentCount > 0 {
            chips.append(.init(id: "recent", label: "\(recentCount) recent", target: recentTarget))
        }

        let visibleChips = Array(chips.prefix(3))
        guard !visibleChips.isEmpty else {
            return [
                .init(id: "text-empty", text: "Nothing is demanding the spotlight right now.", chip: nil)
            ]
        }

        var parts: [HomeDailyBriefSummaryPart] = [
            .init(id: "text-start", text: "You have ", chip: nil)
        ]

        for (index, chip) in visibleChips.enumerated() {
            if index > 0 {
                let connector = index == visibleChips.count - 1 ? ", and " : ", "
                parts.append(.init(id: "text-connector-\(index)", text: connector, chip: nil))
            }
            parts.append(.init(id: "chip-\(chip.id)", text: "", chip: chip))
        }

        let ending: String
        if visibleChips.contains(where: { $0.id == "dueToday" }) {
            ending = " to shape the day around."
        } else if visibleChips.contains(where: { $0.id == "urgent" }) {
            ending = " worth checking before deeper work."
        } else if visibleChips.contains(where: { $0.id == "unfiled" }) {
            ending = " waiting for a little triage."
        } else {
            ending = " worth a quick look."
        }
        parts.append(.init(id: "text-ending", text: ending, chip: nil))
        return parts
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
