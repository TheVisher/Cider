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
                    NotificationCenter.default.post(name: .toggleAIAssistantPanel, object: nil)
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
            } else if let savedViewID = selectedTab?.savedViewID,
                      let savedView = savedViewStorage.savedView(for: savedViewID),
                      savedView.kind != .dashboard {
                expandedFilterButton(isEnabled: true) {
                    isHomeViewOptionsVisible.toggle()
                }
                .popover(isPresented: $isHomeViewOptionsVisible) {
                    ViewOptionsDropdown(
                        displayMode: $homeDisplayMode,
                        cardSizeScale: $homeCardSizeScale,
                        hideCardFooters: $hideCardFooters,
                        showCardDetailsOnHover: $showCardDetailsOnHover,
                        sortMode: sortModeBinding(for: savedViewID),
                        entityFilter: entityFilterBinding(for: savedViewID),
                        tagFilter: tagFilterBinding(for: savedViewID),
                        onlyUnassigned: onlyUnassignedBinding(for: savedViewID),
                        showComingUp: showComingUpBinding(for: savedViewID)
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
            } else if let savedViewID = selectedTab?.savedViewID,
                      let savedView = savedViewStorage.savedView(for: savedViewID),
                      savedView.kind != .dashboard {
                compactFilterButton(isEnabled: true) {
                    isHomeViewOptionsVisible.toggle()
                }
                .popover(isPresented: $isHomeViewOptionsVisible) {
                    ViewOptionsDropdown(
                        displayMode: $homeDisplayMode,
                        cardSizeScale: $homeCardSizeScale,
                        hideCardFooters: $hideCardFooters,
                        showCardDetailsOnHover: $showCardDetailsOnHover,
                        sortMode: sortModeBinding(for: savedViewID),
                        entityFilter: entityFilterBinding(for: savedViewID),
                        tagFilter: tagFilterBinding(for: savedViewID),
                        onlyUnassigned: onlyUnassignedBinding(for: savedViewID),
                        showComingUp: showComingUpBinding(for: savedViewID)
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
                let card = DateCardStorage.shared.createDateCard(
                    title: title,
                    startAt: date,
                    allDay: allDay
                )
                DispatchQueue.main.async {
                    self.newEventEditorContext = DateCardEditorContext(
                        existingCard: card,
                        defaultDate: date
                    )
                }
            },
            onCreateContact: { [self] name, relationship in
                var contact = ContactStorage.shared.createContact(displayName: name)
                if !relationship.isEmpty {
                    contact.relationshipLabel = relationship
                    ContactStorage.shared.updateContact(contact)
                }
                DispatchQueue.main.async {
                    self.newContactEditorContext = ContactEditorContext(existingContact: contact)
                }
            },
            onCreateTodo: { card in
                TodoCardStorage.shared.addTodoCard(card)
            },
            onOpenTodoEditor: {
                newTodoEditorContext = TodoEditorContext(existingCard: nil)
            },
            onCreateFolder: { name, parentID in
                bvm.createFolder(name: name, parentID: parentID)
            },
            onCreateTab: { [self] name, entityTypes in
                let filter = SavedViewFilterSpec(entityTypes: entityTypes)
                let savedView = savedViewStorage.createSavedView(name: name, filterSpec: filter)
                savedViewStorage.addToTabOrder(savedView.id)
                selectedFolderID = nil
                selectedTab = .savedView(id: savedView.id, name: savedView.name)
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
                NotificationCenter.default.post(name: .toggleAIAssistantPanel, object: nil)
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.controlAccent)
                        .frame(width: 14, alignment: .center)
                    Text("Open Chat")
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
        // Show panel (no-op if already visible — won't toggle it off)
        NotificationCenter.default.post(name: .showAIAssistantPanel, object: nil)
        // Small delay to let the panel appear before sending
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            AIAssistantViewModel.shared.send(message)
        }
    }

    var showFolderViewOptions: Bool {
        selectedFolderID != nil
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
        } else if let savedViewID = selectedTab?.savedViewID,
                  let savedView = savedViewStorage.savedView(for: savedViewID),
                  savedView.kind != .dashboard {
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
                        showCardDetailsOnHover: $showCardDetailsOnHover,
                        sortMode: sortModeBinding(for: savedViewID),
                        entityFilter: entityFilterBinding(for: savedViewID),
                        tagFilter: tagFilterBinding(for: savedViewID),
                        onlyUnassigned: onlyUnassignedBinding(for: savedViewID),
                        showComingUp: showComingUpBinding(for: savedViewID)
                    )
                }
        } else {
            // Invisible spacer to keep layout stable
            Color.clear
                .frame(width: CiderPanelDesign.trafficLightTapTarget, height: CiderPanelDesign.trafficLightTapTarget)
        }
    }

    func onlyUnassignedBinding(for savedViewID: UUID) -> Binding<Bool> {
        Binding(
            get: {
                savedViewStorage.savedView(for: savedViewID)?.filterSpec.onlyUnassigned ?? false
            },
            set: { newValue in
                guard var savedView = savedViewStorage.savedView(for: savedViewID) else { return }
                savedView.filterSpec.onlyUnassigned = newValue
                if savedView.isBlank { savedView.isBlank = false }
                savedViewStorage.updateSavedView(savedView)
            }
        )
    }

    func tagFilterBinding(for savedViewID: UUID) -> Binding<Set<UUID>> {
        Binding(
            get: {
                savedViewStorage.savedView(for: savedViewID)?.filterSpec.labelIDs ?? []
            },
            set: { newValue in
                guard var savedView = savedViewStorage.savedView(for: savedViewID) else { return }
                savedView.filterSpec.labelIDs = newValue
                if savedView.isBlank && !newValue.isEmpty { savedView.isBlank = false }
                savedViewStorage.updateSavedView(savedView)
            }
        )
    }

    func entityFilterBinding(for savedViewID: UUID) -> Binding<Set<LibraryEntityType>> {
        Binding(
            get: {
                savedViewStorage.savedView(for: savedViewID)?.filterSpec.entityTypes ?? LibraryEntityType.activeCases
            },
            set: { newValue in
                guard var savedView = savedViewStorage.savedView(for: savedViewID) else { return }
                savedView.filterSpec.entityTypes = newValue
                if savedView.isBlank && !newValue.isEmpty { savedView.isBlank = false }
                savedViewStorage.updateSavedView(savedView)
            }
        )
    }

    func sortModeBinding(for savedViewID: UUID) -> Binding<LibrarySortMode> {
        Binding(
            get: {
                savedViewStorage.savedView(for: savedViewID)?.sortSpec.mode ?? .createdDescending
            },
            set: { newValue in
                guard var savedView = savedViewStorage.savedView(for: savedViewID) else { return }
                savedView.sortSpec.mode = newValue
                if savedView.isBlank { savedView.isBlank = false }
                savedViewStorage.updateSavedView(savedView)
            }
        )
    }

    func showComingUpBinding(for savedViewID: UUID) -> Binding<Bool> {
        Binding(
            get: {
                savedViewStorage.savedView(for: savedViewID)?.layoutSpec.showComingUpSection ?? true
            },
            set: { newValue in
                guard var savedView = savedViewStorage.savedView(for: savedViewID) else { return }
                savedView.layoutSpec.showComingUpSection = newValue
                savedViewStorage.updateSavedView(savedView)
            }
        )
    }

}

private struct SidebarProfilePanel<ExpandedViewOptions: View, CompactViewOptions: View, AIQuickActions: View>: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var syncService = SyncService.shared
    @ObservedObject private var updaterService = SparkleUpdaterService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    Text(authService.isLoggedIn ? authService.accountEmail : "Sign In")
                        .font(CiderFont.labelMedium)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    Text(authService.isLoggedIn ? "Signed in" : "Sync across devices")
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
                expandedViewOptions()
                HomeOverviewQuickActionButton(
                    title: "AI",
                    systemImage: "sparkles",
                    detail: showAIQuickActions ? "Hide" : nil,
                    action: {
                        showAIQuickActions.toggle()
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

                    VStack(alignment: .leading, spacing: 1) {
                        Text(authService.isLoggedIn ? authService.accountEmail : "Sign In")
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
                    systemImage: authService.isLoggedIn ? "arrow.triangle.2.circlepath" : "person.crop.circle.badge.plus",
                    help: authService.isLoggedIn ? "Sync Now" : "Sign In",
                    disabled: authService.isLoggedIn && syncService.isSyncing,
                    action: {
                        if authService.isLoggedIn {
                            onSyncNow()
                        } else {
                            onOpenSettings()
                        }
                    }
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
            showAIQuickActions.toggle()
        } label: {
            Image(systemName: "sparkles")
                .font(CiderFont.bodySemibold)
                .foregroundColor(showAIQuickActions ? CiderColors.controlAccent : CiderColors.secondary)
                .frame(width: CiderPanelDesign.trafficLightTapTarget, height: CiderPanelDesign.trafficLightTapTarget)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(showAIQuickActions ? CiderColors.controlAccent.opacity(0.12) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("AI")
        .contextMenu {
            Button("Open Chat", action: onOpenAI)
        }
    }

    private func compactIconButton(
        systemImage: String,
        help: String,
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

    private var compactSyncStatusText: String {
        if syncService.isSyncing { return "Syncing now" }
        if authService.isLoggedIn { return "Signed in" }
        return "Sync across devices"
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
