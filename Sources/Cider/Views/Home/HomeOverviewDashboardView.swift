import SwiftUI

struct HomeOverviewDashboardView: View {
    let snapshot: HomeOverviewSnapshot
    let onOpenItem: (LibraryItemV2) -> Void
    let onOpenTarget: (HomeOverviewActionTarget) -> Void
    let onOpenTab: (HomeOverviewClosedTabSummary) -> Void
    let onOpenKanbanCard: (String, String) -> Void
    let onOpenSettings: () -> Void
    let onSyncNow: () -> Void
    let onCreateNew: () -> Void

    private let calendar = Calendar.current
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var syncService = SyncService.shared
    private var layoutMetrics: HomeOverviewLayoutMetrics { HomeOverviewLayoutMetrics(snapshot: snapshot) }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = min(
                max(0, proxy.size.width - (Spacing.md * 2)),
                HomeOverviewDesign.maxContentWidth
            )

            ScrollView {
                VStack(alignment: .leading, spacing: HomeOverviewDesign.rowSpacing) {
                    telemetryStrip

                    if proxy.size.width <= HomeOverviewDesign.singleColumnLayoutThreshold {
                        singleColumnLayout
                    } else if proxy.size.width <= HomeOverviewDesign.compactLayoutThreshold {
                        compactLayout
                    } else {
                        fullLayout(availableWidth: contentWidth)
                    }
                }
                .frame(maxWidth: contentWidth, alignment: .leading)
                .padding(.horizontal, Spacing.md)
                .padding(.top, HomeOverviewDesign.telemetryTopPadding)
                .padding(.bottom, Spacing.md)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var telemetryStrip: some View {
        HStack {
            Spacer(minLength: 0)

            HStack(spacing: Spacing.lg) {
                ForEach(snapshot.telemetry) { metric in
                    Button {
                        onOpenTarget(metric.target)
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Text(metric.kind.title.uppercased())
                                .font(CiderFont.captionSemibold)
                                .foregroundColor(CiderColors.tertiary)
                                .tracking(1.2)
                            Text("\(metric.value)")
                                .font(CiderFont.monospacedBody)
                                .foregroundColor(CiderColors.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, HomeOverviewDesign.telemetryInset)
            .padding(.vertical, Spacing.xs)
        }
    }

    private func fullLayout(availableWidth: CGFloat) -> some View {
        let tracks = HomeOverviewFullLayoutTracks(availableWidth: availableWidth)

        return VStack(alignment: .leading, spacing: HomeOverviewDesign.rowSpacing) {
            dailyBriefPanel(fixedHeight: HomeOverviewDesign.fullLayoutTopRowHeight)

            HStack(alignment: .top, spacing: HomeOverviewDesign.columnSpacing) {
                todoPanel(fixedHeight: HomeOverviewDesign.fullLayoutMiddleRowHeight)
                    .frame(width: tracks.recentWidth)
                upcomingPanel(fixedHeight: HomeOverviewDesign.fullLayoutMiddleRowHeight)
                    .frame(width: tracks.upcomingWidth)
            }

            HStack(alignment: .top, spacing: HomeOverviewDesign.columnSpacing) {
                recentActivityPanel(fixedHeight: HomeOverviewDesign.fullLayoutBottomRowHeight)
                    .frame(width: tracks.recentWidth)
                kanbanPulsePanel(fixedHeight: HomeOverviewDesign.fullLayoutBottomRowHeight)
                    .frame(width: tracks.third)
                triagePanel(fixedHeight: HomeOverviewDesign.fullLayoutBottomRowHeight)
                    .frame(width: tracks.third)
                closedTabsPanel(
                    fixedHeight: HomeOverviewDesign.fullLayoutBottomRowHeight,
                    columnCount: 1,
                    visibleCount: 5
                )
                    .frame(width: tracks.continueWidth)
            }
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: HomeOverviewDesign.rowSpacing) {
            dailyBriefPanel()
            upcomingPanel()
            HStack(alignment: .top, spacing: HomeOverviewDesign.columnSpacing) {
                todoPanel()
                recentActivityPanel()
            }
            kanbanPulsePanel()
            triagePanel()
            closedTabsPanel(columnCount: HomeOverviewDesign.closedTabsCompactColumnCount)
        }
    }

    private var singleColumnLayout: some View {
        VStack(alignment: .leading, spacing: HomeOverviewDesign.rowSpacing) {
            dailyBriefPanel()
            upcomingPanel()
            todoPanel()
            recentActivityPanel()
            kanbanPulsePanel()
            triagePanel()
            closedTabsPanel(columnCount: HomeOverviewDesign.closedTabsSingleColumnCount)
        }
    }

    private func dailyBriefPanel(fixedHeight: CGFloat? = nil) -> some View {
        return HomeOverviewPanel(
            title: "Today's Brief",
            minHeight: layoutMetrics.requiredHeight(for: .dailyBrief),
            fixedHeight: fixedHeight,
            headerAccessory: AnyView(dailyBriefHistoryChips)
        ) {
            Text(dailyGreeting)
                .font(CiderFont.displayBold)
                .foregroundColor(CiderColors.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(snapshot.dailyBrief.dateLabel)
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.tertiary)

            dailyBriefSummaryLine

            Divider()
                .background(CiderColors.separator)
                .padding(.top, Spacing.xs)

            Text("FOCUS")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)
                .tracking(1.4)

            if snapshot.dailyBrief.focusItems.isEmpty {
                Text("Nothing is pressing right now. A suspiciously civilized start.")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.tertiary)
            } else {
                LazyVGrid(columns: attentionColumns(for: 3), spacing: Spacing.sm) {
                    ForEach(snapshot.dailyBrief.focusItems) { item in
                        dailyBriefFocusCard(item)
                    }
                }
            }
        }
    }

    private var dailyBriefSummaryLine: some View {
        TagFlowLayout(spacing: Spacing.xs) {
            ForEach(snapshot.dailyBrief.summaryParts) { part in
                if let chip = part.chip {
                    Button {
                        onOpenTarget(chip.target)
                    } label: {
                        Text(chip.label)
                            .font(CiderFont.captionMedium)
                            .foregroundColor(CiderColors.primary)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xxs)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(CiderColors.surfaceInput)
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(CiderColors.borderSubtle, lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(part.text)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)
                }
            }
        }
    }

    private var dailyBriefHistoryChips: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(["Today", "Yesterday", "2d Ago"], id: \.self) { label in
                Text(label)
                    .font(CiderFont.captionMedium)
                    .foregroundColor(label == "Today" ? CiderColors.primary : CiderColors.tertiary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xxs)
                    .background(
                        Capsule(style: .continuous)
                            .fill(label == "Today" ? CiderColors.surfaceInput : CiderColors.surfaceSubtle)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(label == "Today" ? CiderColors.borderSubtle : Color.clear, lineWidth: 1)
                            )
                    )
            }
        }
    }

    private func pulsePanel(fixedHeight: CGFloat? = nil) -> some View {
        HomeOverviewPanel(
            title: "Vault Pulse",
            minHeight: layoutMetrics.requiredHeight(for: .pulse),
            fixedHeight: fixedHeight
        ) {
            Text(snapshot.pulse)
                .font(CiderFont.displaySemibold)
                .foregroundColor(CiderColors.primary)

            Text("Recent captures are flowing, while triage and resurfacing set the current pace.")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text(pulseStatsLine)
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.secondary)
                .tracking(0.6)
        }
    }

    private func overviewPanel(
        fixedHeight: CGFloat? = nil,
        attentionColumnCount: Int = 4
    ) -> some View {
        HomeOverviewPanel(
            title: "Overview",
            minHeight: layoutMetrics.requiredHeight(for: .overview),
            fixedHeight: fixedHeight
        ) {
            Text("Good \(greeting). Your vault has a few useful threads worth pulling on.")
                .font(CiderFont.displayBold)
                .foregroundColor(CiderColors.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(snapshot.overviewSummary)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            TagFlowLayout(spacing: Spacing.sm) {
                ForEach(snapshot.overviewChips) { chip in
                    Button {
                        onOpenTarget(chip.target)
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Text("\(chip.value)")
                                .font(CiderFont.labelSemibold)
                            Text(chip.title)
                                .font(CiderFont.captionMedium)
                        }
                        .foregroundColor(CiderColors.primary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            Capsule(style: .continuous)
                                .fill(CiderColors.surfaceInput)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(CiderColors.borderSubtle, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
                .background(CiderColors.separator)
                .padding(.top, Spacing.xs)

            Text("NEEDS ATTENTION")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)
                .tracking(1.4)

            let metrics = snapshot.attentionMetrics
            LazyVGrid(columns: attentionColumns(for: attentionColumnCount), spacing: Spacing.sm) {
                ForEach(metrics) { metric in
                    Button {
                        onOpenTarget(metric.target)
                    } label: {
                        HomeOverviewMetricBlock(
                            title: metric.title,
                            value: metric.value,
                            minHeight: HomeOverviewDesign.embeddedAttentionMetricTileHeight
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

        }
    }

    private func profilePanel(fixedHeight: CGFloat? = nil) -> some View {
        HomeOverviewPanel(
            title: "Profile",
            minHeight: layoutMetrics.requiredHeight(for: .profile),
            fixedHeight: fixedHeight
        ) {
            HStack(alignment: .center, spacing: Spacing.md) {
                Circle()
                    .fill(authService.isLoggedIn ? CiderColors.controlAccent.opacity(0.18) : CiderColors.surfaceInput)
                    .frame(width: 46, height: 46)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(CiderFont.headingMedium)
                            .foregroundColor(authService.isLoggedIn ? CiderColors.controlAccent : CiderColors.tertiary)
                    }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(authService.isLoggedIn ? authService.accountEmail : "Sign In")
                        .font(CiderFont.subheadingMedium)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    Text(authService.isLoggedIn ? "Signed in" : "Sync across devices")
                        .font(CiderFont.body)
                        .foregroundColor(authService.isLoggedIn ? CiderColors.success : CiderColors.tertiary)
                        .lineLimit(1)
                }
            }

            syncStatusBadge

            VStack(spacing: Spacing.xs) {
                HomeOverviewQuickActionButton(
                    title: "Settings",
                    systemImage: "gearshape",
                    action: onOpenSettings
                )
                HomeOverviewQuickActionButton(
                    title: authService.isLoggedIn ? "Sync Now" : "Sign In",
                    systemImage: authService.isLoggedIn ? "arrow.triangle.2.circlepath" : "person.crop.circle.badge.plus",
                    detail: authService.isLoggedIn && syncService.isSyncing ? "Working" : nil,
                    disabled: authService.isLoggedIn && syncService.isSyncing,
                    action: {
                        if authService.isLoggedIn {
                            onSyncNow()
                        } else {
                            onOpenSettings()
                        }
                    }
                )
                HomeOverviewQuickActionButton(
                    title: "New",
                    systemImage: "plus",
                    action: onCreateNew
                )
            }
        }
    }

    private func kanbanPulsePanel(fixedHeight: CGFloat? = nil) -> some View {
        HomeOverviewPanel(
            title: "Active Work",
            minHeight: layoutMetrics.requiredHeight(for: .kanbanPulse),
            fixedHeight: fixedHeight
        ) {
            if snapshot.kanbanPulseItems.isEmpty {
                HomeOverviewEmptyStateCard(
                    title: "No active work queued.",
                    subtitle: "Kanban is calm; nothing needs a dashboard pulse."
                )
            } else {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(snapshot.kanbanPulseItems) { pulseItem in
                        Button {
                            onOpenKanbanCard(pulseItem.boardID, pulseItem.cardID)
                        } label: {
                            HStack(alignment: .top, spacing: Spacing.sm) {
                                Image(systemName: pulseItem.priority <= 1 ? "bolt.circle" : "rectangle.stack.badge.person.crop")
                                    .font(CiderFont.captionSemibold)
                                    .foregroundColor(pulseItem.priority <= 1 ? CiderColors.controlAccent : CiderColors.secondary)
                                    .frame(width: 18)

                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(pulseItem.title)
                                        .font(CiderFont.labelMedium)
                                        .foregroundColor(CiderColors.primary)
                                        .lineLimit(1)

                                    if let parentTitle = pulseItem.parentTitle {
                                        Text(parentTitle)
                                            .font(CiderFont.caption)
                                            .foregroundColor(CiderColors.tertiary)
                                            .lineLimit(1)
                                    }

                                    HStack(spacing: Spacing.xs) {
                                        Text(pulseItem.statusLabel)
                                            .font(CiderFont.captionSemibold)
                                            .foregroundColor(CiderColors.secondary)
                                            .lineLimit(1)
                                        Text(pulseItem.suggestedAction)
                                            .font(CiderFont.caption)
                                            .foregroundColor(CiderColors.quaternary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        if pulseItem.id != snapshot.kanbanPulseItems.last?.id {
                            Divider()
                                .background(CiderColors.separator)
                        }
                    }
                }
            }
        }
    }

    private func triagePanel(fixedHeight: CGFloat? = nil) -> some View {
        HomeOverviewPanel(
            title: "Inbox Triage",
            minHeight: layoutMetrics.requiredHeight(for: .triage),
            fixedHeight: fixedHeight
        ) {
            if snapshot.triageItems.isEmpty {
                HomeOverviewEmptyStateCard(
                    title: "Inbox looks healthy.",
                    subtitle: "No obvious unfiled or under-enriched captures need attention."
                )
            } else {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(snapshot.triageItems) { triageItem in
                        Button {
                            onOpenItem(triageItem.item)
                        } label: {
                            HStack(alignment: .top, spacing: Spacing.sm) {
                                Image(systemName: triageItem.item.dashboardSymbol)
                                    .font(CiderFont.captionSemibold)
                                    .foregroundColor(triageItem.item.dashboardAccentColor)
                                    .frame(width: 18)

                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(triageItem.item.title)
                                        .font(CiderFont.labelMedium)
                                        .foregroundColor(CiderColors.primary)
                                        .lineLimit(1)

                                    Text(triageItem.reason)
                                        .font(CiderFont.caption)
                                        .foregroundColor(CiderColors.tertiary)
                                        .lineLimit(1)

                                    HStack(spacing: Spacing.xs) {
                                        Text(triageItem.suggestedAction)
                                            .font(CiderFont.captionSemibold)
                                            .foregroundColor(CiderColors.secondary)
                                            .lineLimit(1)
                                        Text(triageItem.confidenceLabel)
                                            .font(CiderFont.caption)
                                            .foregroundColor(CiderColors.quaternary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        if triageItem.id != snapshot.triageItems.last?.id {
                            Divider()
                                .background(CiderColors.separator)
                        }
                    }
                }
            }
        }
    }

    private func recentActivityPanel(fixedHeight: CGFloat? = nil) -> some View {
        HomeOverviewPanel(
            title: "Recent Activity",
            minHeight: layoutMetrics.requiredHeight(for: .recentActivity),
            fixedHeight: fixedHeight
        ) {
            if snapshot.recentItems.isEmpty {
                Text("No recent activity yet.")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.tertiary)
            } else {
                HomeOverviewCaptureTimeline(items: snapshot.recentItems) { item in
                    onOpenItem(item)
                }
            }
        }
    }

    private func upcomingPanel(fixedHeight: CGFloat? = nil) -> some View {
        HomeOverviewPanel(
            title: "Today + Upcoming",
            minHeight: layoutMetrics.requiredHeight(for: .upcoming),
            fixedHeight: fixedHeight
        ) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: HomeOverviewDesign.dayChipMinWidth), spacing: Spacing.sm), count: 7), spacing: Spacing.sm) {
                ForEach(currentWeekDates, id: \.self) { date in
                    HomeOverviewDayChip(date: date, isSelected: calendar.isDateInToday(date))
                }
            }

            if snapshot.upcomingItems.isEmpty {
                Text("No approaching items.")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.tertiary)
                    .padding(.top, Spacing.xs)
            } else {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(Array(snapshot.upcomingItems.enumerated()), id: \.element.id) { index, item in
                        Divider()
                            .background(CiderColors.separator)
                        HomeOverviewAgendaRow(item: item, isNow: index == 0, onOpen: {
                            onOpenItem(item)
                        })
                    }
                }
                .padding(.top, Spacing.xs)
            }
        }
    }

    private func todoPanel(fixedHeight: CGFloat? = nil) -> some View {
        HomeOverviewPanel(
            title: "Action Items",
            minHeight: layoutMetrics.requiredHeight(for: .todos),
            fixedHeight: fixedHeight
        ) {
            HStack(alignment: .top, spacing: Spacing.lg) {
                todoLane(title: "Open", todos: snapshot.todoItems, emptyText: "No open todo cards.") { todo in
                    HomeOverviewTodoRow(
                        todo: todo,
                        mode: .open,
                        onToggleComplete: {
                            TodoCardStorage.shared.markCompleted(todo.id, completed: true)
                        },
                        onOpen: {
                            onOpenItem(.todo(todo))
                        }
                    )
                }

                Divider()
                    .background(CiderColors.separator)

                todoLane(title: "Done", todos: snapshot.completedTodoItems, emptyText: "Completed items will land here.") { todo in
                    HomeOverviewTodoRow(
                        todo: todo,
                        mode: .completed,
                        onToggleComplete: {
                            TodoCardStorage.shared.markCompleted(todo.id, completed: false)
                        },
                        onOpen: {
                            onOpenItem(.todo(todo))
                        }
                    )
                }
            }
        }
    }

    private func todoLane<Content: View>(
        title: String,
        todos: [TodoCard],
        emptyText: String,
        @ViewBuilder row: @escaping (TodoCard) -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title.uppercased())
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)
                .tracking(1.2)

            if todos.isEmpty {
                Text(emptyText)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.tertiary)
                    .padding(.top, Spacing.xs)
            } else {
                ForEach(todos) { todo in
                    row(todo)
                    if todo.id != todos.last?.id {
                        Divider()
                            .background(CiderColors.separator)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func closedTabsPanel(
        fixedHeight: CGFloat? = nil,
        columnCount: Int = HomeOverviewDesign.closedTabsFullColumnCount,
        visibleCount: Int? = nil
    ) -> some View {
        let fallbackCount = max(columnCount, 1) * HomeOverviewDesign.closedTabsVisibleRowCount
        let visibleTabs = Array(snapshot.closedTabs.prefix(visibleCount ?? fallbackCount))

        return HomeOverviewPanel(
            title: "Continue",
            minHeight: layoutMetrics.requiredHeight(for: .closedTabs),
            fixedHeight: fixedHeight
        ) {
            if snapshot.closedTabs.isEmpty {
                HomeOverviewEmptyStateCard(
                    title: "Nothing to pick back up.",
                    subtitle: "Recent tabs and boards will show up here when there is a useful thread to continue."
                )
            } else {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: Spacing.sm),
                        count: max(columnCount, 1)
                    ),
                    spacing: Spacing.sm
                ) {
                    ForEach(visibleTabs) { tab in
                        HomeOverviewContinueChip(tab: tab) {
                            onOpenTab(tab)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var currentWeekDates: [Date] {
        let today = Date()
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: today)
        let start = weekInterval?.start ?? calendar.startOfDay(for: today)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var greeting: String {
        let hour = calendar.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "morning"
        case 12..<17:
            return "afternoon"
        default:
            return "evening"
        }
    }

    private var pulseStatsLine: String {
        let unfiled = snapshot.attentionMetrics.first(where: { $0.id == "unfiled" })?.value ?? 0
        let urgent = snapshot.attentionMetrics.first(where: { $0.id == "urgent" })?.value ?? 0
        return "\(unfiled) unfiled  •  \(urgent) urgent"
    }

    private var dailyGreeting: String {
        HomeOverviewDataProvider.dailyBriefGreetingText(
            for: snapshot.dailyBrief,
            displayName: dashboardDisplayName,
            now: Date(),
            calendar: calendar
        )
    }

    private var dashboardDisplayName: String {
        guard authService.isLoggedIn else { return "there" }
        let emailPrefix = authService.accountEmail.split(separator: "@").first.map(String.init) ?? ""
        return emailPrefix.isEmpty ? "there" : emailPrefix
    }

    @ViewBuilder
    private func dailyBriefFocusCard(_ item: HomeDailyBriefItem) -> some View {
        Button {
            switch item.target {
            case .item(let libraryItem):
                onOpenItem(libraryItem)
            case .action(let target):
                onOpenTarget(target)
            }
        } label: {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: item.systemImage)
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.controlAccent)
                    .frame(width: 18, height: 18)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(item.title)
                        .font(CiderFont.labelMedium)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    Text(item.subtitle)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: HomeOverviewDesign.embeddedAttentionMetricTileHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(CiderColors.surfaceInput)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .stroke(CiderColors.borderSubtle, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func attentionColumns(for count: Int) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: Spacing.sm),
            count: max(count, 1)
        )
    }

    @ViewBuilder
    private var syncStatusBadge: some View {
        HStack(spacing: Spacing.xs) {
            if syncService.isSyncing {
                ProgressView()
                    .controlSize(.small)
                Text("Syncing now")
            } else if let lastSync = syncService.lastSyncedAt, authService.isLoggedIn {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(CiderColors.success)
                Text("Synced \(lastSync.formatted(.relative(presentation: .named)))")
            } else if authService.isLoggedIn {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(CiderColors.tertiary)
                Text("Sync is active")
            } else {
                Image(systemName: "icloud.slash")
                    .foregroundColor(CiderColors.tertiary)
                Text("Not signed in")
            }
        }
        .font(CiderFont.caption)
        .foregroundColor(CiderColors.tertiary)
        .lineLimit(1)
    }
}
