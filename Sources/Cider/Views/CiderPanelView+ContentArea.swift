import SwiftUI

extension CiderPanelView {

    // MARK: - Content Area

    var isEditorActive: Bool {
        selectedNote != nil || notesViewModel.activeExternalFile != nil
    }

    var isNoteDetailOpen: Bool { isEditorActive }
    var isNoteDetailSlideOut: Bool { isNoteDetailOpen && noteDetailViewMode == .slideOut }
    var isNoteDetailFullPanel: Bool { isNoteDetailOpen && noteDetailViewMode == .fullPanel }
    var isNoteDetailPageMode: Bool { isNoteDetailOpen && noteDetailViewMode == .page }

    /// Active detail view mode based on what's currently open
    var detailViewMode: DetailViewMode {
        if isNoteDetailOpen { return noteDetailViewMode }
        return bookmarkDetailViewMode
    }

    var contentArea: some View {
        VStack(spacing: 0) {
            ZStack {
                tabContentBody
                    .opacity(isAnyDetailPageMode ? 0 : 1)
                    .allowsHitTesting(!isAnyDetailPageMode)

                if isAnyDetailPageMode {
                    detailPageView
                }
            }

        }
        .animation(reduceMotion ? .none : .snappy, value: isAnyDetailOpen)
        .clipShape(RoundedRectangle(cornerRadius: CiderPanelDesign.cornerRadius, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { contentAreaWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, w in contentAreaWidth = w }
            }
        )
    }

    @ViewBuilder
    var tabContentBody: some View {
        if !selectedTagIDs.isEmpty {
            TagDetailView(
                tagIDs: selectedTagIDs,
                showManager: false,
                bookmarksViewModel: bookmarksViewModel,
                notesViewModel: notesViewModel,
                libraryViewModel: libraryViewModel,
                displayMode: $homeDisplayMode,
                cardSizeScale: $homeCardSizeScale,
                selectedItemIDs: $selectedItemIDs,
                onOpenNote: { note in openNoteDetail(note) },
                onShowBookmarkDetails: { openBookmarkDetails($0) },
                onEditDateCard: { dateCard in
                    newEventEditorContext = DateCardEditorContext(existingCard: dateCard, defaultDate: dateCard.startAt)
                },
                onEditContact: { contact in
                    newContactEditorContext = ContactEditorContext(existingContact: contact)
                },
                onOpenDateCard: { openDateCardDetail($0) },
                onOpenContact: { openContactDetail($0) },
                onOpenTodo: { openTodoDetail($0) },
                onOpenVaultFile: { openVaultFileDetail($0) },
                onOpenSession: { openSessionDetail($0) },
                onSelectTag: { id in
                    selectedTagIDs = [id]
                },
                onBack: {
                    selectedTagIDs.removeAll()
                },
                onToggleLabelBulk: { toggleTagOnSelected($0) },
                scrollToItemID: $scrollToItemID,
                focusedItemID: focusedItemID
            )
        } else if let sourceID = selectedSourceID,
           let source = externalSourceStorage.source(for: sourceID) {
            SourceDetailView(
                source: source,
                displayMode: $homeDisplayMode,
                cardSizeScale: $homeCardSizeScale
            )
        } else if let folderID = selectedFolderID {
            FolderDetailView(
                bookmarksViewModel: bookmarksViewModel,
                notesViewModel: notesViewModel,
                folderID: folderID,
                displayMode: $homeDisplayMode,
                cardSizeScale: $homeCardSizeScale,
                selectedItemIDs: $selectedItemIDs,
                subFoldersCollapsed: $subFoldersCollapsed,
                searchText: debouncedSearchText,
                onSelectSubFolder: { subFolderID in
                    selectedFolderID = subFolderID
                    expandPathToFolder(subFolderID)
                },
                onOpenNote: { note in openNoteDetail(note) },
                onShowBookmarkDetails: { openBookmarkDetails($0) },
                onEditDateCard: { dateCard in
                    newEventEditorContext = DateCardEditorContext(existingCard: dateCard, defaultDate: dateCard.startAt)
                },
                onEditContact: { contact in
                    newContactEditorContext = ContactEditorContext(existingContact: contact)
                },
                onOpenDateCard: { openDateCardDetail($0) },
                onOpenContact: { openContactDetail($0) },
                onOpenTodo: { openTodoDetail($0) },
                onOpenVaultFile: { openVaultFileDetail($0) },
                onOpenSession: { openSessionDetail($0) },
                onToggleLabelBulk: { toggleTagOnSelected($0) },
                scrollToItemID: $scrollToItemID,
                focusedItemID: focusedItemID
            )
        } else if let tab = selectedTab {
            switch tab {
            case .savedView(let id, _):
                if let savedView = savedViewStorage.savedView(for: id) {
                    if case .whiteboard(let canvasID) = savedView.kind {
                        WhiteboardTabView(canvasID: canvasID, viewModel: whiteboardViewModel)
                    } else if savedView.isOnboarding {
                        OnboardingTabView(onDismiss: {
                            dismissOnboardingTab(id: id)
                        })
                    } else if savedView.isBlank {
                        blankTabWelcome(savedViewID: id)
                    } else {
                        HomeDashboardView(
                            bookmarksViewModel: bookmarksViewModel,
                            notesViewModel: notesViewModel,
                            libraryViewModel: libraryViewModel,
                            selectedFolderID: nil,
                            displayMode: $homeDisplayMode,
                            cardSizeScale: $homeCardSizeScale,
                            continueSectionCollapsed: .constant(true),
                            selectedItemIDs: $selectedItemIDs,
                            sortMode: sortModeBinding(for: id),
                            entityFilter: entityFilterBinding(for: id),
                            searchText: debouncedSearchText,
                            onOpenNote: { note in openNoteDetail(note) },
                            onShowBookmarkDetails: { openBookmarkDetails($0) },
                            onEditDateCard: { dateCard in
                                newEventEditorContext = DateCardEditorContext(
                                    existingCard: dateCard,
                                    defaultDate: dateCard.startAt
                                )
                            },
                            onEditContact: { contact in
                                newContactEditorContext = ContactEditorContext(existingContact: contact)
                            },
                            onOpenDateCard: { openDateCardDetail($0) },
                            onOpenContact: { openContactDetail($0) },
                            onOpenTodo: { openTodoDetail($0) },
                            onOpenVaultFile: { openVaultFileDetail($0) },
                            onOpenSession: { openSessionDetail($0) },
                            onlyUnassigned: savedView.filterSpec.onlyUnassigned,
                            activeLabelIDs: savedView.filterSpec.labelIDs,
                            onToggleLabelBulk: { toggleTagOnSelected($0) },
                            showComingUp: savedView.layoutSpec.showComingUpSection,
                            scrollToItemID: $scrollToItemID,
                            focusedItemID: focusedItemID
                        )
                    }
                } else {
                    EmptyStateView(
                        icon: "square.grid.2x2",
                        title: "Saved view not found"
                    )
                }
            case .search(_, let query):
                SearchTabContent(
                    query: query,
                    bookmarks: bookmarksViewModel.bookmarks,
                    notes: notesViewModel.notes,
                    onOpenBookmark: { bookmark in
                        if NSEvent.modifierFlags.contains(.command) {
                            bookmarksViewModel.open(bookmark)
                        } else {
                            openBookmarkDetails(bookmark)
                        }
                    },
                    onOpenNote: { note in
                        openNoteDetail(note)
                    },
                    onOpenDateCard: { openDateCardDetail($0) },
                    onOpenContact: { openContactDetail($0) },
                    onOpenTodo: { openTodoDetail($0) }
                )
            case .externalSource(let id, _):
                if let source = externalSourceStorage.source(for: id) {
                    SourceDetailView(
                        source: source,
                        displayMode: $homeDisplayMode,
                        cardSizeScale: $homeCardSizeScale
                    )
                } else {
                    EmptyStateView(
                        icon: "folder.badge.gear",
                        title: "Source not found"
                    )
                }
            case .tag:
                TagDetailView(
                    tagIDs: [],
                    showManager: true,
                    bookmarksViewModel: bookmarksViewModel,
                    notesViewModel: notesViewModel,
                    libraryViewModel: libraryViewModel,
                    displayMode: $homeDisplayMode,
                    cardSizeScale: $homeCardSizeScale,
                    selectedItemIDs: $selectedItemIDs,
                    onOpenNote: { note in openNoteDetail(note) },
                    onShowBookmarkDetails: { openBookmarkDetails($0) },
                    onEditDateCard: { dateCard in
                        newEventEditorContext = DateCardEditorContext(existingCard: dateCard, defaultDate: dateCard.startAt)
                    },
                    onEditContact: { contact in
                        newContactEditorContext = ContactEditorContext(existingContact: contact)
                    },
                    onOpenDateCard: { openDateCardDetail($0) },
                    onOpenContact: { openContactDetail($0) },
                    onOpenTodo: { openTodoDetail($0) },
                    onOpenVaultFile: { openVaultFileDetail($0) },
                    onOpenSession: { openSessionDetail($0) },
                    onSelectTag: { id in
                        selectedTagIDs = [id]
                    },
                    onToggleLabelBulk: { toggleTagOnSelected($0) },
                    scrollToItemID: $scrollToItemID,
                    focusedItemID: focusedItemID
                )
            }
        } else {
            noTabsEmptyState
        }
    }

    @ViewBuilder
    func blankTabWelcome(savedViewID: UUID) -> some View {
        let closed = savedViewStorage.savedViews.filter {
            !savedViewStorage.tabOrder.contains($0.id) && !$0.isOnboarding
        }

        VStack(spacing: Spacing.xl) {
            Spacer()

            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 36))
                .foregroundColor(CiderColors.tertiary)

            VStack(spacing: Spacing.sm) {
                Text("New Tab")
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(CiderColors.primary)

                Text("Configure this tab to show exactly what you need.")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            VStack(alignment: .leading, spacing: Spacing.md) {
                blankTabHint(icon: "line.3.horizontal.decrease.circle", text: "Filter by bookmarks, notes, events, or contacts")
                blankTabHint(icon: "arrow.up.arrow.down", text: "Sort by date added, modified, title, or event date")
                blankTabHint(icon: "tray", text: "Toggle \"Unassigned Only\" to create an inbox")
                blankTabHint(icon: "square.grid.2x2", text: "Switch between list, grid, and masonry layouts")
                blankTabHint(icon: "textformat.size", text: "Adjust card size with the slider")
            }

            Button("Open View Options") {
                isHomeViewOptionsVisible = true
            }
            .buttonStyle(CiderAccentButtonStyle())

            Button("Show All Items") {
                activateBlankTab(savedViewID)
            }
            .buttonStyle(.plain)
            .font(CiderFont.labelMedium)
            .foregroundColor(CiderColors.controlAccent)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            closedTabsGrid(closed)
        }
    }

    @ViewBuilder
    private func closedTabsGrid(_ closed: [SavedView]) -> some View {
        VStack(spacing: Spacing.sm) {
            Divider()
                .padding(.horizontal, Spacing.lg)

            Text("Closed Tabs")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)

            if closed.isEmpty {
                Text("Closed tabs appear here")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.quaternary)
                    .frame(minHeight: 32)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100, maximum: 160), spacing: Spacing.sm)],
                    spacing: Spacing.sm
                ) {
                    ForEach(closed) { sv in
                        ClosedTabCard(
                            savedView: sv,
                            onReopen: { reopenTab(sv.id) },
                            onDelete: { deleteClosedTab(sv) }
                        )
                    }
                }
                .padding(.horizontal, Spacing.lg)
            }
        }
        .padding(.bottom, Spacing.md)
    }

    private func blankTabHint(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.controlAccent)
                .frame(width: 20, alignment: .center)
            Text(text)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.secondary)
        }
    }

    func activateBlankTab(_ savedViewID: UUID) {
        guard var savedView = savedViewStorage.savedView(for: savedViewID) else { return }
        savedView.isBlank = false
        savedViewStorage.updateSavedView(savedView)
    }

    func dismissOnboardingTab(id: UUID) {
        savedViewStorage.removeFromTabOrder(id)
        savedViewStorage.deleteSavedView(id)
        var config = CiderConfig.load()
        config.hasCompletedOnboarding = true
        config.save()
        selectedTab = allTabs.first
    }

    func openOrCreateOnboardingTab() {
        // Check if an onboarding tab already exists in the tab bar
        if let existing = savedViewStorage.savedViews.first(where: { $0.isOnboarding }),
           savedViewStorage.tabOrder.contains(existing.id) {
            selectedTab = .savedView(id: existing.id, name: existing.name)
            selectedFolderID = nil
            return
        }
        // Create a new onboarding tab at the front
        let welcome = savedViewStorage.createSavedView(
            name: "Welcome",
            filterSpec: SavedViewFilterSpec(),
            isBlank: true,
            isOnboarding: true
        )
        savedViewStorage.insertInTabOrder(welcome.id, at: 0)
        selectedTab = .savedView(id: welcome.id, name: welcome.name)
        selectedFolderID = nil
    }

    // MARK: - noTabsEmptyState

    var noTabsEmptyState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(CiderColors.tertiary)
            Text("No tabs open")
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.secondary)
            Text("Create a tab to start organizing")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
            Button("New Tab") { showNewItemPicker = true }
                .buttonStyle(CiderAccentButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ClosedTabCard

private struct ClosedTabCard: View {
    let savedView: SavedView
    let onReopen: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var icon: String {
        if case .whiteboard = savedView.kind { return "scribble" }
        return "square.grid.2x2"
    }

    var body: some View {
        Button(action: onReopen) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(CiderFont.captionMedium)
                    .foregroundColor(isHovered ? CiderColors.primary : CiderColors.tertiary)
                Text(savedView.name)
                    .font(CiderFont.label)
                    .foregroundColor(isHovered ? CiderColors.primary : CiderColors.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if isHovered {
                    Spacer(minLength: 0)
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(CiderFont.captionMedium)
                            .foregroundColor(CiderColors.destructive)
                            .padding(Spacing.xxs)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(0.8)))
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isHovered ? CiderColors.separatorLight : CiderColors.surfaceInput)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? .none : .snappy, value: isHovered)
    }
}
