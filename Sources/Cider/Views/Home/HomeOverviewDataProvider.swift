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
        kanbanBoards: [KanbanBoard] = [],
        reviewQueueItems: [CiderReviewQueueItem] = [],
        reviewQueueSummary: CiderReviewQueueSummaryResult? = nil,
        bookmarkDateSuggestionResults: [CiderBookmarkDateSuggestionResult] = [],
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
                target: libraryTarget(name: "Bookmarks", entityTypes: [.bookmark], sortMode: .createdDescending)
            ),
            HomeTelemetryMetric(
                kind: .notes,
                value: items.filter { if case .note = $0 { return true }; return false }.count,
                target: libraryTarget(name: "Notes", entityTypes: [.note], sortMode: .updatedDescending)
            ),
            HomeTelemetryMetric(
                kind: .todos,
                value: items.filter { if case .todo = $0 { return true }; return false }.count,
                target: libraryTarget(name: "Todos", entityTypes: [.todo], sortMode: .dateUpcoming)
            ),
            HomeTelemetryMetric(
                kind: .events,
                value: items.filter { if case .dateCard = $0 { return true }; return false }.count,
                target: libraryTarget(name: "Events", entityTypes: [.dateCard], sortMode: .dateUpcoming)
            ),
            HomeTelemetryMetric(kind: .unfiled, value: unfiledCount, target: .inbox),
            HomeTelemetryMetric(
                kind: .urgent,
                value: urgentCount,
                target: libraryTarget(name: "Urgent", entityTypes: [.todo, .dateCard], sortMode: .dateUpcoming)
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
        let visibleReviewQueueItems = reviewQueueItems.filter(isVisibleReviewCockpitItem)
        let reviewCockpitItems = reviewCockpitItems(
            from: visibleReviewQueueItems,
            bookmarkDateSuggestionResults: bookmarkDateSuggestionResults,
            libraryItems: items
        )
        let triageItems = triageItems(from: items)
        let kanbanPulseItems = kanbanPulseItems(from: kanbanBoards)

        let recentTarget = libraryTarget(
            name: "Recent Activity",
            entityTypes: LibraryEntityType.activeCases,
            sortMode: .updatedDescending
        )
        let upcomingTarget = libraryTarget(
            name: "Upcoming",
            entityTypes: [.todo, .dateCard],
            sortMode: .dateUpcoming
        )
        let resurfaceTarget = libraryTarget(
            name: "Resurface",
            entityTypes: LibraryEntityType.activeCases,
            sortMode: .updatedAscending
        )
        let urgentTarget = libraryTarget(
            name: "Urgent",
            entityTypes: [.todo, .dateCard],
            sortMode: .dateUpcoming
        )
        let notesTarget = libraryTarget(
            name: "Notes",
            entityTypes: [.note],
            sortMode: .updatedDescending
        )

        let reviewCount = reviewQueueSummary?.totalCount ?? visibleReviewQueueItems.count
        let attentionMetrics = primaryAttentionMetrics(
            reviewCount: reviewCount,
            unfiledCount: unfiledCount,
            urgentCount: urgentCount,
            dueTodayCount: dueTodayCount,
            untitledNotesCount: untitledNotesCount,
            urgentTarget: urgentTarget,
            upcomingTarget: upcomingTarget,
            notesTarget: notesTarget
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
            attentionMetrics: attentionMetrics,
            recentItems: Array(recentItems.prefix(6)),
            recentCaptureItems: recentCaptureItems(from: recentItems, folders: folders),
            upcomingItems: Array(upcomingItems.prefix(4)),
            todoItems: Array(todoQueueItems(from: items, now: now).prefix(6)),
            completedTodoItems: Array(completedTodoItems(from: items).prefix(4)),
            resurfacedItems: resurfacedItems,
            reviewCockpitItems: reviewCockpitItems,
            reviewCockpitSummary: reviewCockpitSummary(
                from: reviewQueueSummary,
                fallbackItems: visibleReviewQueueItems,
                now: now
            ),
            triageItems: triageItems,
            kanbanPulseItems: kanbanPulseItems
        )
    }

    private static func primaryAttentionMetrics(
        reviewCount: Int,
        unfiledCount: Int,
        urgentCount: Int,
        dueTodayCount: Int,
        untitledNotesCount: Int,
        urgentTarget: HomeOverviewActionTarget,
        upcomingTarget: HomeOverviewActionTarget,
        notesTarget: HomeOverviewActionTarget
    ) -> [HomeAttentionMetric] {
        var metrics: [HomeAttentionMetric] = []
        if reviewCount > 0 {
            metrics.append(HomeAttentionMetric(id: "review", title: "Review", value: reviewCount, target: .review))
        }
        metrics.append(contentsOf: [
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
        ])
        return Array(metrics.prefix(4))
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

    private static func recentCaptureItems(from recentItems: [LibraryItemV2], folders: [Folder]) -> [HomeRecentCaptureItem] {
        let folderNames = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0.name) })
        return recentItems.prefix(6).map { item in
            let explanation = recentCaptureSurfacingExplanation(for: item)
            let destinationLabel = locationLabel(for: item, folderNames: folderNames)
            return HomeRecentCaptureItem(
                id: "recent-capture-\(item.id)",
                item: item,
                title: item.title,
                typeLabel: typeLabel(for: item),
                sourceTypeLabel: sourceTypeLabel(for: item),
                itemTypeLabel: typeLabel(for: item),
                locationLabel: destinationLabel,
                destinationLabel: destinationLabel,
                reviewState: explanation.reviewState,
                reviewNeeded: explanation.reviewState == "needs_review",
                suggestedAction: explanation.suggestedAction,
                safeFollowUpActions: safeFollowUpActions(for: item, explanation: explanation),
                surfacingExplanation: explanation
            )
        }
    }

    private static func locationLabel(for item: LibraryItemV2, folderNames: [UUID: String]) -> String {
        guard let folderID = item.folderID, let name = folderNames[folderID] else {
            return "Inbox / Unfiled"
        }
        return name
    }

    private static func typeLabel(for item: LibraryItemV2) -> String {
        switch item {
        case .journal: return "Journal"
        case .bookmark: return "Bookmark"
        case .note: return "Note"
        case .dateCard: return "Date"
        case .contact: return "Contact"
        case .todo: return "Todo"
        case .vaultFile: return "File"
        }
    }

    private static func sourceTypeLabel(for item: LibraryItemV2) -> String {
        switch item {
        case .journal:
            return "Journal"
        case .bookmark:
            return "URL"
        case .note:
            return "Text"
        case .todo:
            return "Todo"
        case .vaultFile(let file):
            return file.fileType == .image ? "Image" : "File"
        case .dateCard:
            return "Date"
        case .contact:
            return "Contact"
        }
    }

    private static func safeFollowUpActions(for item: LibraryItemV2, explanation: CiderSurfacingExplanation) -> [String] {
        switch explanation.reviewState {
        case "needs_review":
            var actions = ["Review"]
            if ["Clean up title", "Needs enrichment"].contains(explanation.suggestedAction) {
                actions.append("Check metadata")
            }
            actions.append("Open item")
            actions.append("Defer")
            return actions
        case "pending":
            if case .todo = item, explanation.suggestedAction == "Add reminder" {
                return ["Review reminder", "Open item", "Defer"]
            }
            return ["Review", "Open item", "Defer"]
        default:
            return ["Open item"]
        }
    }

    private static func recentCaptureSurfacingExplanation(for item: LibraryItemV2) -> CiderSurfacingExplanation {
        CiderSurfacingExplanationService.recentCaptureExplanation(for: item)
    }

    private static func kanbanPulseItems(from boards: [KanbanBoard]) -> [HomeKanbanPulseItem] {
        let preferredBoards = boards.sorted { lhs, rhs in
            let lhsPreferred = lhs.id == "2afee0" || lhs.name.localizedCaseInsensitiveContains("Cider")
            let rhsPreferred = rhs.id == "2afee0" || rhs.name.localizedCaseInsensitiveContains("Cider")
            if lhsPreferred != rhsPreferred { return lhsPreferred }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return preferredBoards.flatMap { board -> [HomeKanbanPulseItem] in
            board.columns.flatMap { column -> [HomeKanbanPulseItem] in
                column.cards.compactMap { card in
                    kanbanPulseItem(board: board, column: column, card: card)
                }
            }
        }
        .sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        .prefix(6)
        .map { $0 }
    }

    private static func kanbanPulseItem(board: KanbanBoard, column: KanbanColumn, card: KanbanCard) -> HomeKanbanPulseItem? {
        let columnID = column.id.lowercased()
        let columnName = column.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let isTesting = columnID.contains("test") || columnName.localizedCaseInsensitiveContains("ready to test")
        let isActive = columnID == "in_progress" || columnName.localizedCaseInsensitiveContains("progress")
        let isQueued = columnID == "queued" || columnName.localizedCaseInsensitiveContains("queued")
        let isBlocked = columnID.contains("block") || columnName.localizedCaseInsensitiveContains("blocked") || (card.notes ?? "").localizedCaseInsensitiveContains("blocked")
        guard isActive || isTesting || isQueued || isBlocked else { return nil }

        let children = board.childCards(of: card.id)
        let isParentPlan = !children.isEmpty
        let parentTitle = card.parentCardID.flatMap { board.card(id: $0)?.title }
        let statusLabel: String
        let suggestedAction: String
        let priority: Int
        if isBlocked {
            statusLabel = "Blocked"
            suggestedAction = "Unblock"
            priority = 0
        } else if isActive {
            statusLabel = columnName.isEmpty ? "In Progress" : columnName
            suggestedAction = "Keep moving"
            priority = 1
        } else if isTesting {
            statusLabel = columnName.isEmpty ? "Testing" : columnName
            suggestedAction = "Needs Erik QA"
            priority = 2
        } else if isParentPlan {
            statusLabel = "Queued plan"
            suggestedAction = "Review scope"
            priority = 3
        } else {
            statusLabel = columnName.isEmpty ? "Queued" : columnName
            suggestedAction = "Next up"
            priority = 4
        }

        return HomeKanbanPulseItem(
            id: "kanban-\(board.id)-\(card.id)",
            boardID: board.id,
            boardName: board.name,
            cardID: card.id,
            title: card.title,
            statusLabel: statusLabel,
            parentTitle: parentTitle,
            suggestedAction: suggestedAction,
            priority: priority
        )
    }

    private static func reviewCockpitItems(
        from reviewItems: [CiderReviewQueueItem],
        bookmarkDateSuggestionResults: [CiderBookmarkDateSuggestionResult],
        libraryItems: [LibraryItemV2]
    ) -> [HomeReviewCockpitItem] {
        let itemsByUUID = Dictionary(libraryItems.compactMap { item in
            itemUUID(for: item).map { ($0, item) }
        }, uniquingKeysWith: { first, _ in first })

        let queueItems = reviewItems.map { reviewItem in
            let linkedItem = itemsByUUID[reviewItem.itemID] ?? fallbackSourceItem(for: reviewItem)
            let safeActions = Set(reviewItem.safeActions.map { $0.lowercased() })
            let hasRoutingDecision = reviewItem.routingDecisionID != nil
            let reviewActions = reviewActions(
                for: reviewItem,
                linkedItem: linkedItem,
                safeActions: safeActions,
                hasRoutingDecision: hasRoutingDecision
            )

            return HomeReviewCockpitItem(
                id: "review-cockpit-\(reviewItem.id)",
                sourceReviewID: reviewItem.id,
                itemID: reviewItem.itemID,
                itemType: reviewItem.itemType,
                item: linkedItem,
                title: reviewItem.title,
                kindLabel: reviewKindLabel(reviewItem.kind),
                reason: reviewItem.reason,
                suggestedAction: reviewItem.suggestedAction,
                reviewStateLabel: reviewStateLabel(reviewItem.reviewState),
                confidenceLabel: reviewItem.confidence.map(confidenceLabel),
                targetLabel: reviewTargetLabel(for: reviewItem),
                sourceLabel: reviewSourceLabel(reviewItem.source),
                canApprove: reviewActions.contains(.accept),
                canCorrect: reviewActions.contains(.openSource),
                canDefer: reviewActions.contains(.deferReview),
                safeActions: reviewItem.safeActions,
                dateSuggestionApproval: nil,
                reviewActions: reviewActions,
                candidateID: reviewItem.candidateID,
                candidateRef: reviewItem.candidateRef,
                candidateExpectedReviewState: reviewItem.reviewState,
                candidateUpdatedAt: reviewItem.candidateUpdatedAt,
                sourceQuote: reviewItem.sourceQuote,
                sourceProvenanceLabel: reviewSourceProvenanceLabel(linkedItem: linkedItem, reviewItem: reviewItem),
                memoryKind: reviewItem.memoryKind,
                linkedOwnerRefs: reviewItem.linkedOwnerRefs,
                possibleTypeLabels: reviewItem.possibleTypes,
                possibleRelationLabels: reviewItem.possibleRelations,
                candidateActionLabels: reviewItem.candidateActions,
                confidenceReason: reviewItem.confidenceReason,
                truthState: reviewItem.truthState,
                extractionReason: reviewItem.extractionReason,
                proposedChangeLabel: reviewProposedChangeLabel(reviewItem.proposedChange),
                storageLabel: reviewStorageLabel(reviewItem.storage),
                candidateQualityLevel: reviewItem.candidateQualityLevel,
                candidateQualityFlags: reviewItem.candidateQualityCodes,
                candidateQualityExplanation: reviewItem.candidateQualityExplanation
            )
        }

        let suggestionItems: [HomeReviewCockpitItem] = bookmarkDateSuggestionResults.compactMap { result in
            var preferredSuggestion: (index: Int, suggestion: CiderBookmarkDateSuggestion)?
            for (index, suggestion) in result.suggestions.enumerated() {
                guard approvedDateSuggestionExists(
                    bookmarkID: result.bookmarkID,
                    suggestion: suggestion,
                    libraryItems: libraryItems
                ) == false else {
                    continue
                }

                if preferredSuggestion == nil || suggestion.confidence > preferredSuggestion!.suggestion.confidence {
                    preferredSuggestion = (index, suggestion)
                }
            }

            guard let preferredSuggestion else { return nil }
            return dateSuggestionReviewItem(
                result: result,
                suggestion: preferredSuggestion.suggestion,
                suggestionIndex: preferredSuggestion.index,
                linkedItem: itemsByUUID[result.bookmarkID]
            )
        }

        return cappedReviewCockpitItems(queueItems: queueItems, suggestionItems: suggestionItems)
    }

    private static func reviewProposedChangeLabel(_ proposedChange: [String: String]) -> String? {
        guard let changeType = proposedChange["changeType"] else { return nil }
        switch changeType {
        case "graph_relation_candidate":
            let relation = proposedChange["relationType"] ?? "mentions"
            let mention = proposedChange["mentionText"] ?? "candidate"
            let target = proposedChange["targetKind"] ?? "object"
            return "Proposes \(relation) → \(mention) (\(target)); still reviewable, not truth."
        case "memory_candidate":
            let kind = proposedChange["memoryKind"] ?? "memory"
            let value = proposedChange["value"] ?? "candidate"
            return "Proposes \(kind.replacingOccurrences(of: "_", with: " ")) memory: \(value); still reviewable, not truth."
        default:
            return proposedChange.values.joined(separator: " • ")
        }
    }

    private static func reviewStorageLabel(_ storage: [String: String]) -> String? {
        guard let table = storage["table"], let service = storage["service"] else { return nil }
        let kind = storage["kind"].map { " kind=\($0)" } ?? ""
        return "Stored in \(table) via \(service)\(kind)."
    }

    private static func fallbackSourceItem(for reviewItem: CiderReviewQueueItem) -> LibraryItemV2? {
        guard isSourceBackedCandidate(reviewItem.kind),
              reviewItem.itemType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "note" else {
            return nil
        }

        let relativePath = reviewItem.relativePath ?? ""
        let pathTitle = relativePath
            .split(separator: "/")
            .last
            .map(String.init)?
            .replacingOccurrences(of: ".md", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String
        if let pathTitle, pathTitle.isEmpty == false {
            title = pathTitle
        } else {
            title = reviewItem.title
        }

        return .note(Note(
            id: reviewItem.itemID,
            title: title,
            createdAt: reviewItem.createdAt,
            modifiedAt: reviewItem.createdAt,
            relativePath: relativePath
        ))
    }

    private static func isSourceBackedCandidate(_ kind: String) -> Bool {
        switch kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "memory_candidate", "graph_candidate":
            return true
        default:
            return false
        }
    }

    private static func reviewSourceProvenanceLabel(
        linkedItem: LibraryItemV2?,
        reviewItem: CiderReviewQueueItem
    ) -> String? {
        guard isSourceBackedCandidate(reviewItem.kind) else { return nil }
        if let relativePath = reviewItem.relativePath,
           let dailyJournalDate = dailyJournalDateLabel(from: relativePath) {
            return "Daily Journal \(dailyJournalDate)"
        }

        if let title = linkedItem?.title.trimmingCharacters(in: .whitespacesAndNewlines),
           title.isEmpty == false {
            return title
        }

        guard let relativePath = reviewItem.relativePath else { return nil }
        let pathTitle = relativePath
            .split(separator: "/")
            .last
            .map(String.init)?
            .replacingOccurrences(of: ".md", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return pathTitle?.isEmpty == false ? pathTitle : nil
    }

    private static func dailyJournalDateLabel(from relativePath: String) -> String? {
        let pattern = #"\b\d{4}-\d{2}-\d{2}\b"#
        guard let range = relativePath.range(of: pattern, options: .regularExpression) else { return nil }
        return String(relativePath[range])
    }

    private static func isVisibleReviewCockpitItem(_ item: CiderReviewQueueItem) -> Bool {
        isVisibleReviewCockpitKind(item.kind)
    }

    private static func isVisibleReviewCockpitKind(_ kind: String) -> Bool {
        switch kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "low_confidence_routing", "deferred_routing", "inbox_backlog":
            return false
        default:
            return true
        }
    }

    private static func cappedReviewCockpitItems(
        queueItems: [HomeReviewCockpitItem],
        suggestionItems: [HomeReviewCockpitItem],
        limit: Int = 6
    ) -> [HomeReviewCockpitItem] {
        guard limit > 0 else { return [] }
        let baseLimit = suggestionItems.isEmpty ? limit : max(0, limit - 1)
        var selected: [HomeReviewCockpitItem] = []
        var selectedIDs = Set<String>()

        // Keep count badges honest: when a lane such as Memory Candidate has nonzero
        // items but Graph Candidate rows sort first, reserve a representative row per
        // source-backed review family before filling the remaining slots.
        for family in ["Memory Candidate", "Graph Candidate"] where selected.count < baseLimit {
            if let item = queueItems.first(where: { $0.kindLabel == family }), selectedIDs.insert(item.id).inserted {
                selected.append(item)
            }
        }

        for item in queueItems where selected.count < baseLimit {
            if selectedIDs.insert(item.id).inserted {
                selected.append(item)
            }
        }

        let combined = selected + suggestionItems.prefix(max(0, limit - selected.count))
        return Array(combined.prefix(limit))
    }

    private static func reviewCockpitSummary(
        from summary: CiderReviewQueueSummaryResult?,
        fallbackItems: [CiderReviewQueueItem],
        now: Date
    ) -> HomeReviewCockpitSummary {
        if let summary {
            let visibleCountsByKind = summary.countsByKind.filter { kind, _ in
                isVisibleReviewCockpitKind(kind)
            }
            let visibleGroups = summary.groups.filter { group in
                isVisibleReviewCockpitKind(group.kind)
            }

            return HomeReviewCockpitSummary(
                totalCount: visibleCountsByKind.values.reduce(0, +),
                badges: reviewCockpitBadges(from: visibleCountsByKind),
                itemTypeCounts: summary.countsByItemType,
                reviewStateCounts: summary.countsByReviewState,
                safeActionCounts: summary.countsBySafeAction,
                groups: reviewCockpitGroups(from: visibleGroups),
                batchEnrichmentPreview: reviewCockpitBatchEnrichmentPreview(from: summary.batchEnrichmentPreview),
                generatedAt: summary.generatedAt
            )
        }

        return HomeReviewCockpitSummary(
            totalCount: fallbackItems.count,
            badges: reviewCockpitBadges(from: groupedCounts(fallbackItems.map(\.kind))),
            itemTypeCounts: groupedCounts(fallbackItems.map(\.itemType)),
            reviewStateCounts: groupedCounts(fallbackItems.map(\.reviewState)),
            safeActionCounts: groupedCounts(fallbackItems.flatMap(\.safeActions)),
            groups: reviewCockpitGroups(from: fallbackReviewCockpitGroups(for: fallbackItems)),
            batchEnrichmentPreview: fallbackBatchEnrichmentPreview(for: fallbackItems),
            generatedAt: now
        )
    }

    private static func reviewCockpitGroups(from groups: [CiderReviewQueueGroup]) -> [HomeReviewCockpitGroup] {
        groups.map { group in
            HomeReviewCockpitGroup(
                id: group.id,
                label: reviewKindLabel(group.kind),
                reviewState: group.reviewState,
                requiredSafeAction: group.requiredSafeAction,
                itemType: group.itemType,
                count: group.count,
                sampleTitles: group.sampleItems.map(\.title)
            )
        }
    }

    private static func reviewCockpitBatchEnrichmentPreview(
        from preview: CiderReviewQueueBatchEnrichmentPreview
    ) -> HomeReviewCockpitBatchEnrichmentPreview {
        HomeReviewCockpitBatchEnrichmentPreview(
            action: preview.action,
            isMutating: preview.isMutating,
            candidateCount: preview.candidateCount,
            candidateSampleLimit: preview.candidateSampleLimit,
            candidateSampleTitles: preview.candidateSamples.map(\.title),
            excludedCount: preview.excludedCount,
            exclusionsByReason: preview.exclusionsByReason
        )
    }

    private static func fallbackReviewCockpitGroups(for items: [CiderReviewQueueItem]) -> [CiderReviewQueueGroup] {
        let grouped = Dictionary(grouping: items) { item in
            "\(item.kind):\(item.reviewState):\(primaryReviewCockpitSafeAction(for: item)):\(item.itemType)"
        }

        return grouped.map { id, items in
            let first = items[0]
            return CiderReviewQueueGroup(
                id: id,
                kind: first.kind,
                reviewState: first.reviewState,
                requiredSafeAction: primaryReviewCockpitSafeAction(for: first),
                itemType: first.itemType,
                count: items.count,
                sampleItems: Array(items.prefix(3))
            )
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.id < rhs.id
        }
    }

    private static func fallbackBatchEnrichmentPreview(
        for items: [CiderReviewQueueItem]
    ) -> HomeReviewCockpitBatchEnrichmentPreview {
        let candidates = items.filter { item in
            item.kind == "enrichment"
                && item.itemType == "bookmark"
                && item.safeActions.contains("enrich")
        }
        let excludedReasons = items.compactMap { fallbackBatchEnrichmentExclusionReason(for: $0) }

        return HomeReviewCockpitBatchEnrichmentPreview(
            action: "review.enrich",
            isMutating: false,
            candidateCount: candidates.count,
            candidateSampleLimit: 10,
            candidateSampleTitles: candidates.prefix(10).map(\.title),
            excludedCount: excludedReasons.count,
            exclusionsByReason: groupedCounts(excludedReasons)
        )
    }

    private static func fallbackBatchEnrichmentExclusionReason(for item: CiderReviewQueueItem) -> String? {
        if item.kind == "enrichment",
           item.itemType == "bookmark",
           item.safeActions.contains("enrich") {
            return nil
        }
        switch item.kind {
        case "low_confidence_routing", "deferred_routing":
            return "routing_requires_explicit_approval"
        case "inbox_backlog":
            return "manual_routing_required"
        case "duplicate_candidate":
            return "duplicate_review_required"
        default:
            return item.itemType == "bookmark" ? "not_enrichment_candidate" : "unsupported_item_type"
        }
    }

    private static func primaryReviewCockpitSafeAction(for item: CiderReviewQueueItem) -> String {
        for action in ["enrich", "approve", "correct", "defer"] where item.safeActions.contains(action) {
            return action
        }
        return item.safeActions.first ?? "none"
    }

    private static func reviewCockpitBadges(from countsByKind: [String: Int]) -> [HomeReviewCockpitBadge] {
        countsByKind
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return reviewKindLabel(lhs.key).localizedCaseInsensitiveCompare(reviewKindLabel(rhs.key)) == .orderedAscending
            }
            .map { kind, count in
                HomeReviewCockpitBadge(
                    id: "kind-\(kind)",
                    label: reviewKindLabel(kind),
                    value: count
                )
            }
    }

    private static func groupedCounts(_ values: [String]) -> [String: Int] {
        values.reduce(into: [:]) { counts, value in
            counts[value, default: 0] += 1
        }
    }

    static func bookmarkDateSuggestionResults(
        from items: [LibraryItemV2],
        service: CiderBookmarkDateSuggestionService = CiderBookmarkDateSuggestionService(maximumFieldLength: 2_000)
    ) -> [CiderBookmarkDateSuggestionResult] {
        items.compactMap { item in
            guard case .bookmark(let bookmark) = item else { return nil }
            let result = service.result(for: bookmark)
            return result.suggestions.isEmpty ? nil : result
        }
    }

    private static func dateSuggestionReviewItem(
        result: CiderBookmarkDateSuggestionResult,
        suggestion: CiderBookmarkDateSuggestion,
        suggestionIndex: Int,
        linkedItem: LibraryItemV2?
    ) -> HomeReviewCockpitItem? {
        guard linkedItem != nil else { return nil }
        let destination = dateSuggestionDestination(for: suggestion)

        return HomeReviewCockpitItem(
            id: "review-cockpit-date-suggestion-\(result.bookmarkID.uuidString)-\(suggestion.suggestionKey)",
            sourceReviewID: "date-suggestion-\(result.bookmarkID.uuidString)-\(suggestion.suggestionKey)",
            itemID: result.bookmarkID,
            itemType: "bookmark",
            item: linkedItem,
            title: result.bookmarkTitle,
            kindLabel: "Date Suggestion",
            reason: dateSuggestionReason(for: suggestion),
            suggestedAction: destination == .todo ? "Approve Todo" : "Approve Date Card",
            reviewStateLabel: "Needs Review",
            confidenceLabel: confidenceLabel(suggestion.confidence),
            targetLabel: destination == .todo ? "Todo due date" : "Date card",
            sourceLabel: "Bookmark",
            canApprove: true,
            canCorrect: true,
            canDefer: false,
            safeActions: ["approve", "open"],
            dateSuggestionApproval: HomeReviewCockpitDateSuggestionApproval(
                bookmarkID: result.bookmarkID,
                suggestionIndex: suggestionIndex,
                suggestionKey: suggestion.suggestionKey,
                destination: destination
            ),
            reviewActions: [.openSource, .accept]
        )
    }

    private static func dateSuggestionDestination(for suggestion: CiderBookmarkDateSuggestion) -> LibraryEntityType {
        switch suggestion.kind {
        case "deadline", "sale_end":
            return .todo
        default:
            return .dateCard
        }
    }

    private static func dateSuggestionReason(for suggestion: CiderBookmarkDateSuggestion) -> String {
        let kind = suggestion.kind
            .split(separator: "_")
            .map { word in word.prefix(1).uppercased() + word.dropFirst() }
            .joined(separator: " ")
        return "\(kind) from \(suggestion.sourceField): \(suggestion.sourceSnippet)"
    }

    private static func approvedDateSuggestionExists(
        bookmarkID: UUID,
        suggestion: CiderBookmarkDateSuggestion,
        libraryItems: [LibraryItemV2],
        calendar: Calendar = .current
    ) -> Bool {
        let bookmarkRef = LibraryEntityRef(type: .bookmark, entityID: bookmarkID)
        let destination = dateSuggestionDestination(for: suggestion)

        return libraryItems.contains { item in
            switch (destination, item) {
            case (.todo, .todo(let todo)):
                return todo.linkedEntities.contains(bookmarkRef)
                    && todo.dueDate.map { calendar.isDate($0, inSameDayAs: suggestion.date) } == true
                    && todo.details.localizedCaseInsensitiveContains("Date suggestion kind: \(suggestion.kind)")
            case (.dateCard, .dateCard(let dateCard)):
                return dateCard.linkedEntities.contains(bookmarkRef)
                    && calendar.isDate(dateCard.startAt, inSameDayAs: suggestion.date)
                    && dateCard.details.localizedCaseInsensitiveContains("Date suggestion kind: \(suggestion.kind)")
            default:
                return false
            }
        }
    }

    private static func itemUUID(for item: LibraryItemV2) -> UUID? {
        switch item {
        case .journal:
            return nil
        case .bookmark(let bookmark):
            return bookmark.id
        case .note(let note):
            return note.id
        case .dateCard(let dateCard):
            return dateCard.id
        case .contact(let contact):
            return contact.id
        case .todo(let todo):
            return todo.id
        case .vaultFile(let file):
            return file.id
        }
    }

    private static func reviewKindLabel(_ kind: String) -> String {
        let normalized = kind.lowercased()
        if normalized.contains("graph_candidate") { return "Graph Candidate" }
        if normalized.contains("memory_candidate") { return "Memory Candidate" }
        if normalized.contains("routing") { return "Routing" }
        if normalized.contains("enrichment") { return "Enrichment" }
        if normalized.contains("duplicate") { return "Duplicate" }
        if normalized.contains("inbox") { return "Inbox" }
        return "Review"
    }

    private static func reviewStateLabel(_ state: String) -> String {
        state
            .split(separator: "_")
            .map { word in word.prefix(1).uppercased() + word.dropFirst() }
            .joined(separator: " ")
    }

    private static func reviewSourceLabel(_ source: String) -> String {
        source
            .split(separator: "_")
            .map { word in word.prefix(1).uppercased() + word.dropFirst() }
            .joined(separator: " ")
    }

    private static func confidenceLabel(_ confidence: Double) -> String {
        "\(Int((confidence * 100).rounded()))% confidence"
    }

    private static func reviewTargetLabel(for item: CiderReviewQueueItem) -> String? {
        if let target = item.target {
            return target.relativePath.isEmpty ? target.name : target.relativePath
        }
        if !item.possibleTypes.isEmpty {
            return item.possibleTypes.joined(separator: ", ")
        }
        if item.kind == "memory_candidate" {
            let memoryKind = item.memoryKind?
                .split(separator: "_")
                .map { word in word.prefix(1).uppercased() + word.dropFirst() }
                .joined(separator: " ")
            let owners = item.linkedOwnerRefs.isEmpty ? nil : item.linkedOwnerRefs.joined(separator: ", ")
            if let memoryKind, let owners {
                return "\(memoryKind) • \(owners)"
            }
            return memoryKind ?? owners
        }
        return item.relativePath
    }

    private static func reviewActions(
        for item: CiderReviewQueueItem,
        linkedItem: LibraryItemV2?,
        safeActions: Set<String>,
        hasRoutingDecision: Bool
    ) -> [HomeReviewCockpitAction] {
        var actions: [HomeReviewCockpitAction] = []
        let normalizedKind = item.kind.lowercased()
        let reviewable = !["accepted", "rejected"].contains(item.reviewState.lowercased())
        let hasCandidateID = item.candidateID != nil || item.candidateRef != nil

        if linkedItem != nil,
           safeActions.contains("correct")
            || ["memory_candidate", "graph_candidate"].contains(normalizedKind) {
            actions.append(.openSource)
        }

        switch normalizedKind {
        case "memory_candidate":
            guard reviewable, hasCandidateID else { break }
            actions.append(.accept)
            actions.append(.reject)
            actions.append(.deferReview)

        case "graph_candidate":
            guard reviewable, hasCandidateID else { break }
            if safeActions.contains("accept") {
                actions.append(.accept)
            }
            actions.append(.reject)
            if safeActions.contains("defer") {
                actions.append(.deferReview)
            }

        default:
            if hasRoutingDecision && safeActions.contains("approve") {
                actions.append(.accept)
            }
            if hasRoutingDecision && safeActions.contains("defer") {
                actions.append(.deferReview)
            }
        }

        var seen = Set<HomeReviewCockpitAction>()
        return actions.filter { seen.insert($0).inserted }
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
        case .journal:
            return nil
        case .bookmark(let bookmark):
            if bookmarkNeedsEnrichment(bookmark) {
                return HomeTriageItem(
                    id: "triage-\(item.id)-enrichment",
                    item: item,
                    reason: bookmarkGenericTitleReason(bookmark) ?? "Bookmark needs enrichment",
                    suggestedAction: "Needs enrichment",
                    confidenceLabel: "Needs approval"
                )
            }
        case .note(let note):
            if isUntitled(note.title) {
                return HomeTriageItem(
                    id: "triage-\(item.id)-note",
                    item: item,
                    reason: "Untitled inbox note",
                    suggestedAction: "Ask Erik",
                    confidenceLabel: "Low confidence"
                )
            }
        case .vaultFile:
            return nil
        case .dateCard, .contact, .todo:
            return nil
        }
        return nil
    }

    private static func triageSortPriority(_ item: HomeTriageItem) -> Int {
        switch item.suggestedAction {
        case "Needs enrichment": 0
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
                target: libraryItems.first(where: { $0.id == "\(agendaItem.itemType.rawValue)-\(agendaItem.id.uuidString)" }).map { .item($0) } ?? .action(upcomingTarget),
                surfacingExplanation: agendaItem.surfacingExplanation
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

    private static func libraryTarget(
        name: String,
        entityTypes: Set<LibraryEntityType>,
        sortMode: LibrarySortMode
    ) -> HomeOverviewActionTarget {
        .inbox
    }
}
