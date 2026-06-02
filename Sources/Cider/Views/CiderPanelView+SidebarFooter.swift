import SwiftUI

/// A quick action button for the AI sidebar section.
private struct AIQuickAction {
    let icon: String
    let label: String
    let execute: () -> Void
}

extension CiderPanelView {

    // MARK: - Sidebar Footer

    var sidebarFooterView: some View {
        VStack(spacing: Spacing.sm) {
            SidebarProfilePanel(
                isExpanded: $sidebarProfileExpanded,
                showAIQuickActions: $aiSectionExpanded,
                onOpenSettings: {
                    NotificationCenter.default.post(name: .openCiderSettings, object: nil)
                },
                onSyncNow: {
                    SyncService.shared.syncNow()
                },
                onCreateNew: {
                    showNewItemPicker.toggle()
                },
                onOpenAI: {
                    openOrSelectAIAssistantTab()
                }
            ) {
                expandedViewOptionsButton
            } compactViewOptions: {
                compactViewOptionsButton
            } aiQuickActions: {
                aiQuickActionsList
            }
            .popover(isPresented: $showNewItemPicker, arrowEdge: .bottom) {
                newItemPickerContent
            }

            if !sidebarProfileExpanded && aiSectionExpanded {
                aiQuickActionsList
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(reduceMotion ? .none : .snappy, value: sidebarProfileExpanded)
        .animation(reduceMotion ? .none : .snappy, value: aiSectionExpanded)
        .padding(.top, Spacing.sm)
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.sm)
        .frame(width: BookmarksDesign.folderSidebarWidth)
    }

    var expandedViewOptionsButton: some View {
        Group {
            if showFolderViewOptions {
                expandedFilterButton(isEnabled: true) {
                    isHomeViewOptionsVisible.toggle()
                }
                .popover(isPresented: $isHomeViewOptionsVisible) {
                    ViewOptionsDropdown(
                        displayMode: $homeDisplayMode,
                        cardSizeScale: $homeCardSizeScale,
                        hideCardFooters: $hideCardFooters,
                        showCardDetailsOnHover: $showCardDetailsOnHover
                    )
                }
            } else {
                expandedFilterButton(isEnabled: false) {}
            }
        }
    }

    private func expandedFilterButton(isEnabled: Bool, action: @escaping () -> Void) -> some View {
        HomeOverviewQuickActionButton(
            title: "Filter",
            systemImage: "slider.horizontal.3",
            disabled: !isEnabled,
            action: action
        )
        .opacity(isEnabled ? 1 : 0.55)
        .help(isEnabled ? "View options" : "No view options")
    }

    var compactViewOptionsButton: some View {
        Group {
            if showFolderViewOptions {
                compactFilterButton(isEnabled: true) {
                    isHomeViewOptionsVisible.toggle()
                }
                .popover(isPresented: $isHomeViewOptionsVisible) {
                    ViewOptionsDropdown(
                        displayMode: $homeDisplayMode,
                        cardSizeScale: $homeCardSizeScale,
                        hideCardFooters: $hideCardFooters,
                        showCardDetailsOnHover: $showCardDetailsOnHover
                    )
                }
            } else {
                compactFilterButton(isEnabled: false) {}
            }
        }
    }

    private func compactFilterButton(isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "slider.horizontal.3")
                .font(CiderFont.bodyMedium)
                .foregroundColor(isEnabled ? CiderColors.secondary : CiderColors.quaternary.opacity(0.55))
                .frame(width: CiderPanelDesign.trafficLightTapTarget, height: CiderPanelDesign.trafficLightTapTarget)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(isHomeViewOptionsVisible && isEnabled ? CiderColors.controlAccent.opacity(0.12) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(isEnabled ? "View options" : "No view options")
    }

    var newItemPickerContent: some View {
        let bvm = bookmarksViewModel
        return NewItemPopover(
            folders: bvm.folders,
            onCreateBookmark: { urlString, title in
                _ = bvm.addBookmark(urlString: urlString, title: title)
            },
            onCreateNote: { [self] title, content in
                createNoteAndOpen(title: title, content: content)
            },
            onCreateEvent: { [self] title, date, allDay in
                guard let result = try? CiderCaptureService().addDateCardCapture(
                    title: title,
                    sourceText: nil,
                    startAt: date,
                    endAt: nil,
                    allDay: allDay,
                    location: nil,
                    folderID: nil
                ),
                let card = DateCardStorage.shared.dateCards.first(where: { $0.id == result.item.id })
                else { return }
                DispatchQueue.main.async {
                    self.newEventEditorContext = DateCardEditorContext(
                        existingCard: card,
                        defaultDate: date
                    )
                }
            },
            onCreateContact: { [self] name, relationship in
                guard let result = try? CiderCaptureService().addContactCapture(
                    displayName: name,
                    sourceText: nil,
                    relationshipLabel: relationship,
                    email: nil,
                    phone: nil,
                    folderID: nil
                ),
                let contact = ContactStorage.shared.contacts.first(where: { $0.id == result.item.id })
                else { return }
                DispatchQueue.main.async {
                    self.newContactEditorContext = ContactEditorContext(existingContact: contact)
                }
            },
            onCreateTodo: { card in
                _ = try? CiderCaptureService().addTodoCapture(
                    title: card.title,
                    sourceText: card.title,
                    dueDate: card.dueDate,
                    priority: card.priority,
                    folderID: nil
                )
            },
            onOpenTodoEditor: {
                newTodoEditorContext = TodoEditorContext(existingCard: nil)
            },
            onCreateFolder: { name, parentID in
                bvm.createFolder(name: name, parentID: parentID)
            },
            onCreateTab: { [self] name, entityTypes in
                selectedFolderID = nil
                if entityTypes == [.bookmark] {
                    selectedDomainRouteKind = .bookmarks
                } else if entityTypes == [.note] {
                    selectedDomainRouteKind = .notes
                } else if entityTypes == [.vaultFile] {
                    selectedDomainRouteKind = .files
                } else {
                    selectedDomainRouteKind = .all
                }
                selectedNavigationDomain = .browse
                selectedTab = .domainDashboard(.browse)
            },
            onCreateTag: { name, colorHex in
                CardLabelStorage.shared.createLabel(name: name, colorHex: colorHex)
            },
            onDismiss: { [self] in
                showNewItemPicker = false
            }
        )
    }

    // MARK: - AI Sidebar Section

    var aiQuickActionsList: some View {
        VStack(spacing: Spacing.xxs) {
            ForEach(aiQuickActions, id: \.label) { action in
                Button {
                    action.execute()
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: action.icon)
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.controlAccent)
                            .frame(width: 14, alignment: .center)
                        Text(action.label)
                            .font(CiderFont.label)
                            .foregroundColor(CiderColors.primary)
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Divider()
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xxs)

            Button {
                requestFloatingAIAssistant()
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.controlAccent)
                        .frame(width: 14, alignment: .center)
                    Text("Pop Out Chat")
                        .font(CiderFont.label)
                        .foregroundColor(CiderColors.primary)
                    Spacer()
                    Text("⌥A")
                        .font(CiderFont.captionMonospaced)
                        .foregroundColor(CiderColors.quaternary)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Spacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
        )
    }

    /// Quick actions — general actions always available in sidebar.
    /// Context-specific actions (Summarize, Find Similar, etc.) live in the detail panel toolbar.
    private var aiQuickActions: [AIQuickAction] {
        [
            AIQuickAction(icon: "chart.bar", label: "Library Summary") {
                sendQuickMessage("Give me a summary of my entire library")
            },
            AIQuickAction(icon: "clock", label: "Recent Activity") {
                sendQuickMessage("What did I save in the last 7 days?")
            },
            AIQuickAction(icon: "exclamationmark.circle", label: "Overdue Tasks") {
                sendQuickMessage("Do I have any overdue todos?")
            }
        ]
    }

    /// Send a message to the AI assistant (opens panel if needed).
    private func sendQuickMessage(_ message: String) {
        openOrSelectAIAssistantTab()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            AIAssistantViewModel.shared.send(message)
        }
    }

    private func requestFloatingAIAssistant() {
        NotificationCenter.default.post(
            name: .floatCiderSurface,
            object: CiderFloatableSurface.aiAssistant,
            userInfo: [CiderFloatingPanelManager.surfaceUserInfoKey: CiderFloatableSurface.aiAssistant]
        )
    }

    var showFolderViewOptions: Bool {
        if selectedNavigationDomain == .browse,
           workspaceRouter.presentation.sidebarDomain == .browse,
           workspaceRouter.presentation.showsLibraryViewOptions {
            return true
        }
        return CiderPanelViewOptionsPolicy.showsLibraryViewOptions(
            hasSelectedFolder: selectedFolderID != nil,
            hasSelectedTags: !selectedTagIDs.isEmpty,
            selectedTab: selectedTab,
            showsLibraryRouteFeed: selectedLibraryRouteFeed != nil
        )
    }

    @ViewBuilder
    var viewOptionsButton: some View {
        if showFolderViewOptions {
            // Folder view uses home display mode
            Image(systemName: "slider.horizontal.3")
                .font(CiderFont.bodySemibold)
                .foregroundColor(isHomeViewOptionsVisible ? CiderColors.controlAccent : CiderColors.secondary)
                .frame(width: CiderPanelDesign.trafficLightTapTarget, height: CiderPanelDesign.trafficLightTapTarget)
                .contentShape(Rectangle())
                .onTapGesture { isHomeViewOptionsVisible.toggle() }
                .help("View options")
                .popover(isPresented: $isHomeViewOptionsVisible) {
                    ViewOptionsDropdown(
                        displayMode: $homeDisplayMode,
                        cardSizeScale: $homeCardSizeScale,
                        hideCardFooters: $hideCardFooters,
                        showCardDetailsOnHover: $showCardDetailsOnHover
                    )
                }
        } else {
            // Invisible spacer to keep layout stable
            Color.clear
                .frame(width: CiderPanelDesign.trafficLightTapTarget, height: CiderPanelDesign.trafficLightTapTarget)
        }
    }

}

private struct SidebarProfilePanel<ExpandedViewOptions: View, CompactViewOptions: View, AIQuickActions: View>: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var syncService = SyncService.shared
    @ObservedObject private var updaterService = SparkleUpdaterService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var updateBadgePulse = false
    @State private var updateBadgePulseToken = 0

    @Binding var isExpanded: Bool
    @Binding var showAIQuickActions: Bool

    let onOpenSettings: () -> Void
    let onSyncNow: () -> Void
    let onCreateNew: () -> Void
    let onOpenAI: () -> Void
    let expandedViewOptions: () -> ExpandedViewOptions
    let compactViewOptions: () -> CompactViewOptions
    let aiQuickActions: () -> AIQuickActions

    var body: some View {
        Group {
            if isExpanded {
                expandedBody
            } else {
                compactBody
            }
        }
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Text("PROFILE")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)
                    .tracking(2)

                Spacer(minLength: 0)

                Button {
                    isExpanded = false
                } label: {
                    Image(systemName: "chevron.down")
                        .font(CiderFont.microSemibold)
                        .foregroundColor(CiderColors.quaternary)
                        .frame(width: 22, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Collapse profile controls")
            }

            HStack(alignment: .center, spacing: Spacing.sm) {
                Circle()
                    .fill(authService.isLoggedIn ? CiderColors.controlAccent.opacity(0.18) : CiderColors.surfaceInput)
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(CiderFont.bodyMedium)
                            .foregroundColor(authService.isLoggedIn ? CiderColors.controlAccent : CiderColors.tertiary)
                    }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(authService.isLoggedIn ? authService.accountEmail : "Account")
                        .font(CiderFont.labelMedium)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    Text(authService.isLoggedIn ? "Legacy sign-in saved" : "Local storage only")
                        .font(CiderFont.caption)
                        .foregroundColor(authService.isLoggedIn ? CiderColors.success : CiderColors.tertiary)
                        .lineLimit(1)
                }
            }

            syncStatusBadge

            VStack(spacing: Spacing.xs) {
                if updaterService.shouldShowSidebarUpdateReminder {
                    expandedUpdateReminderButton
                }
                HomeOverviewQuickActionButton(
                    title: "Settings",
                    systemImage: "gearshape",
                    action: onOpenSettings
                )
                HomeOverviewQuickActionButton(
                    title: "Sync Unavailable",
                    systemImage: "externaldrive.badge.xmark",
                    disabled: true,
                    action: {}
                )
                HomeOverviewQuickActionButton(
                    title: "New",
                    systemImage: "plus",
                    action: onCreateNew
                )
                expandedViewOptions()
                HomeOverviewQuickActionButton(
                    title: "AI",
                    systemImage: "sparkles",
                    detail: "Chat",
                    action: {
                        showAIQuickActions = false
                        onOpenAI()
                    }
                )
            }

            if showAIQuickActions {
                aiQuickActions()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, CiderBorder.innerStrokeInset)
        .padding(.vertical, Spacing.xs)
    }

    private var compactBody: some View {
        VStack(spacing: Spacing.xs) {
            Button {
                isExpanded = true
            } label: {
                HStack(spacing: Spacing.sm) {
                    Circle()
                        .fill(authService.isLoggedIn ? CiderColors.controlAccent.opacity(0.18) : CiderColors.surfaceInput)
                        .frame(width: 24, height: 24)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(CiderFont.captionSemibold)
                                .foregroundColor(authService.isLoggedIn ? CiderColors.controlAccent : CiderColors.tertiary)
                        }
                        .overlay(alignment: .topTrailing) {
                            if updaterService.shouldShowSidebarUpdateReminder {
                                updateReminderBadge
                                    .offset(x: 2, y: -2)
                            }
                        }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(authService.isLoggedIn ? authService.accountEmail : "Account")
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(CiderColors.primary)
                            .lineLimit(1)
                        Text(compactSyncStatusText)
                            .font(CiderFont.micro)
                            .foregroundColor(authService.isLoggedIn ? CiderColors.success : CiderColors.tertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.up")
                        .font(CiderFont.microSemibold)
                        .foregroundColor(CiderColors.quaternary)
                }
                .padding(.leading, Spacing.xs)
                .padding(.trailing, Spacing.sm)
                .padding(.top, Spacing.xs)
                .padding(.bottom, Spacing.xxs)
                .frame(minHeight: BookmarksDesign.folderSidebarRowMinHeight + 2)
                .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Expand profile controls")

            Divider()
                .overlay(CiderColors.borderSubtle.opacity(0.75))

            HStack(spacing: Spacing.xs) {
                compactIconButton(
                    systemImage: "gearshape",
                    help: "Settings",
                    action: onOpenSettings
                )

                compactIconButton(
                    systemImage: "externaldrive.badge.xmark",
                    help: "Sync unavailable",
                    disabled: true,
                    action: {}
                )
                compactNewButton
                compactAIButton
                compactViewOptions()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, CiderBorder.innerStrokeInset)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .stroke(CiderColors.borderSubtle, lineWidth: CiderBorder.innerStrokeWidth)
                )
        )
        .onAppear {
            triggerUpdateBadgePulse()
        }
        .onChange(of: updaterService.availableUpdateIdentifier) { _, _ in
            triggerUpdateBadgePulse()
        }
        .onChange(of: updaterService.shouldShowSidebarUpdateReminder) { _, _ in
            triggerUpdateBadgePulse()
        }
        .onChange(of: reduceMotion) { _, _ in
            triggerUpdateBadgePulse()
        }
    }

    private var compactNewButton: some View {
        Button {
            onCreateNew()
        } label: {
            Image(systemName: "plus")
                .font(CiderFont.bodyMedium)
            .foregroundColor(CiderColors.secondary)
            .frame(width: CiderPanelDesign.trafficLightTapTarget, height: CiderPanelDesign.trafficLightTapTarget)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Create new item")
    }

    private var compactAIButton: some View {
        Button {
            showAIQuickActions = false
            onOpenAI()
        } label: {
            Image(systemName: "sparkles")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.controlAccent)
                .frame(width: CiderPanelDesign.trafficLightTapTarget, height: CiderPanelDesign.trafficLightTapTarget)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.controlAccent.opacity(0.12))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open AI chat")
        .contextMenu {
            Button(showAIQuickActions ? "Hide Quick Actions" : "Show Quick Actions") {
                showAIQuickActions.toggle()
            }
            Button("Pop Out Chat") {
                NotificationCenter.default.post(
                    name: .floatCiderSurface,
                    object: CiderFloatableSurface.aiAssistant,
                    userInfo: [CiderFloatingPanelManager.surfaceUserInfoKey: CiderFloatableSurface.aiAssistant]
                )
            }
        }
    }

    private func compactIconButton(
        systemImage: String,
        help: String,
        accessibilityLabel: String? = nil,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(CiderFont.bodyMedium)
                .foregroundColor(disabled ? CiderColors.quaternary : CiderColors.secondary)
                .frame(width: CiderPanelDesign.trafficLightTapTarget, height: CiderPanelDesign.trafficLightTapTarget)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
        .accessibilityLabel(Text(accessibilityLabel ?? help))
    }

    private var expandedUpdateReminderButton: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                updaterService.checkForUpdates()
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.controlAccent)
                        .frame(width: 18, height: 18)

                    Text("Update Available")
                        .font(CiderFont.labelMedium)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    Spacer(minLength: Spacing.sm)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, minHeight: HomeOverviewDesign.quickActionButtonHeight, alignment: .leading)
            .help("Check for updates")

            Button {
                updaterService.dismissCurrentSidebarUpdateReminder()
            } label: {
                Image(systemName: "xmark")
                    .font(CiderFont.microSemibold)
                    .foregroundColor(CiderColors.quaternary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Hide this update reminder")
            .accessibilityLabel("Hide this update reminder")
        }
        .padding(.horizontal, Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: HomeOverviewDesign.quickActionButtonHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(CiderColors.controlAccent.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(CiderColors.controlAccent.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private var updateReminderBadge: some View {
        let isPulsing = !reduceMotion && updateBadgePulse

        return Circle()
            .fill(CiderColors.controlAccent)
            .frame(width: 7, height: 7)
            .shadow(color: CiderColors.controlAccent.opacity(isPulsing ? 0.45 : 0.25), radius: isPulsing ? 5 : 2)
            .scaleEffect(isPulsing ? 1.08 : 1)
            .accessibilityHidden(true)
    }

    private func triggerUpdateBadgePulse() {
        updateBadgePulseToken += 1
        let pulseToken = updateBadgePulseToken

        var resetTransaction = Transaction()
        resetTransaction.disablesAnimations = true
        withTransaction(resetTransaction) {
            updateBadgePulse = false
        }

        guard updaterService.shouldShowSidebarUpdateReminder, !reduceMotion else { return }

        DispatchQueue.main.async {
            guard pulseToken == updateBadgePulseToken else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatCount(3, autoreverses: true)) {
                updateBadgePulse = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.7) {
            guard pulseToken == updateBadgePulseToken else { return }
            var resetTransaction = Transaction()
            resetTransaction.disablesAnimations = true
            withTransaction(resetTransaction) {
                updateBadgePulse = false
            }
        }
    }

    private var compactSyncStatusText: String {
        "Local storage only"
    }

    @ViewBuilder
    private var syncStatusBadge: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "externaldrive")
                .foregroundColor(CiderColors.tertiary)
            Text("Local storage only")
        }
        .font(CiderFont.caption)
        .foregroundColor(CiderColors.tertiary)
        .lineLimit(1)
    }
}
