import SwiftUI

struct HomeOverviewDashboardView: View {
    let snapshot: HomeOverviewSnapshot
    let onOpenItem: (LibraryItemV2) -> Void
    let onOpenTarget: (HomeOverviewActionTarget) -> Void
    let onOpenTab: (HomeOverviewClosedTabSummary) -> Void
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
            HStack(alignment: .top, spacing: HomeOverviewDesign.columnSpacing) {
                pulsePanel(fixedHeight: HomeOverviewDesign.fullLayoutTopRowHeight)
                    .frame(width: tracks.pulseWidth)

                overviewPanel(
                    fixedHeight: HomeOverviewDesign.fullLayoutTopRowHeight,
                    attentionColumnCount: 4
                )
                    .frame(width: tracks.overviewWidth)

                profilePanel(fixedHeight: HomeOverviewDesign.fullLayoutTopRowHeight)
                    .frame(width: tracks.attentionWidth)
            }

            HStack(alignment: .top, spacing: HomeOverviewDesign.columnSpacing) {
                resurfacePanel(fixedHeight: HomeOverviewDesign.fullLayoutMiddleRowHeight, cardLimit: 4)
                    .frame(width: tracks.recentWidth)
                upcomingPanel(fixedHeight: HomeOverviewDesign.fullLayoutMiddleRowHeight)
                    .frame(width: tracks.upcomingWidth)
            }

            HStack(alignment: .top, spacing: HomeOverviewDesign.columnSpacing) {
                recentActivityPanel(fixedHeight: HomeOverviewDesign.fullLayoutBottomRowHeight)
                    .frame(width: tracks.resurfaceWidth)
                closedTabsPanel(
                    fixedHeight: HomeOverviewDesign.fullLayoutBottomRowHeight,
                    columnCount: HomeOverviewDesign.closedTabsFullColumnCount
                )
                    .frame(width: tracks.pinnedWidth)
            }
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: HomeOverviewDesign.rowSpacing) {
            HStack(alignment: .top, spacing: HomeOverviewDesign.columnSpacing) {
                pulsePanel()
                profilePanel()
            }

            overviewPanel(attentionColumnCount: 2)
            upcomingPanel()
            HStack(alignment: .top, spacing: HomeOverviewDesign.columnSpacing) {
                resurfacePanel(cardLimit: 4)
                recentActivityPanel()
            }
            closedTabsPanel(columnCount: HomeOverviewDesign.closedTabsCompactColumnCount)
        }
    }

    private var singleColumnLayout: some View {
        VStack(alignment: .leading, spacing: HomeOverviewDesign.rowSpacing) {
            pulsePanel()
            overviewPanel(attentionColumnCount: 2)
            profilePanel()
            upcomingPanel()
            resurfacePanel(cardLimit: 4)
            recentActivityPanel()
            closedTabsPanel(columnCount: HomeOverviewDesign.closedTabsSingleColumnCount)
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
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(snapshot.recentItems, id: \.id) { item in
                        HomeOverviewTimelineRow(item: item, subtitle: item.dashboardSubtitle, onOpen: {
                            onOpenItem(item)
                        })
                    }
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

    private func resurfacePanel(fixedHeight: CGFloat? = nil, cardLimit: Int = 2) -> some View {
        HomeOverviewPanel(
            title: "Resurface",
            minHeight: layoutMetrics.requiredHeight(for: .resurface),
            fixedHeight: fixedHeight
        ) {
            if snapshot.resurfacedItems.isEmpty {
                Text("Nothing to resurface yet.")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.tertiary)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: Spacing.sm),
                    GridItem(.flexible(), spacing: Spacing.sm)
                ], spacing: Spacing.sm) {
                    ForEach(Array(snapshot.resurfacedItems.prefix(cardLimit)), id: \.id) { item in
                        HomeOverviewResurfaceCard(item: item) {
                            onOpenItem(item)
                        }
                    }
                }
            }
        }
    }

    private func closedTabsPanel(
        fixedHeight: CGFloat? = nil,
        columnCount: Int = HomeOverviewDesign.closedTabsFullColumnCount
    ) -> some View {
        HomeOverviewPanel(
            title: "Closed Tabs",
            minHeight: layoutMetrics.requiredHeight(for: .closedTabs),
            fixedHeight: fixedHeight
        ) {
            if snapshot.closedTabs.isEmpty {
                HomeOverviewEmptyStateCard(
                    title: "No closed tabs yet.",
                    subtitle: "Close a tab and it will show up here so you can reopen it from the dashboard."
                )
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: Spacing.sm),
                            count: max(columnCount, 1)
                        ),
                        spacing: Spacing.sm
                    ) {
                        ForEach(snapshot.closedTabs) { tab in
                            HomeOverviewClosedTabCard(tab: tab) {
                                onOpenTab(tab)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
