import SwiftUI

extension CiderPanelView {

    // MARK: - Sidebar Footer

    var sidebarFooterView: some View {
        VStack(spacing: Spacing.sm) {
            Divider()
                .background(CiderColors.separator)
                .padding(.bottom, Spacing.xs)

            HStack(spacing: Spacing.sm) {
                // Settings gear
                Button {
                    NotificationCenter.default.post(name: .openCiderSettings, object: nil)
                } label: {
                    Image(systemName: "gearshape")
                        .font(CiderFont.bodyMedium)
                        .foregroundColor(CiderColors.secondary)
                        .frame(width: CiderPanelDesign.trafficLightTapTarget, height: CiderPanelDesign.trafficLightTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings")

                Spacer(minLength: 0)

                // + pill button
                Button {
                    showNewItemPicker.toggle()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "plus")
                            .font(CiderFont.captionSemibold)
                        Text("New")
                            .font(CiderFont.bodyMedium)
                    }
                    .foregroundColor(CiderColors.secondary)
                    .padding(.horizontal, Spacing.sm)
                    .frame(height: CiderPanelDesign.trafficLightTapTarget)
                    .background(
                        Capsule(style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help("Create new item")
                .popover(isPresented: $showNewItemPicker, arrowEdge: .bottom) {
                    newItemPickerContent
                }

                // AI Chat toggle — reopens in last-used mode (docked tab or floating panel)
                Button {
                    if aiChatDocked {
                        if aiChatVisible && selectedTab?.id == CiderTab.aiChat.id {
                            // Already viewing AI tab — close it
                            aiChatVisible = false
                            selectedTab = tabBeforeAIChat
                            var config = CiderConfig.load()
                            config.aiChatVisible = false
                            config.save()
                        } else {
                            // Open/reopen as docked tab
                            aiChatVisible = true
                            tabBeforeAIChat = selectedTab
                            selectedFolderID = nil
                            selectedSourceID = nil
                            selectedTagIDs = []
                            selectedTab = .aiChat
                            var config = CiderConfig.load()
                            config.aiChatVisible = true
                            config.save()
                        }
                    } else {
                        NotificationCenter.default.post(name: .toggleAIChatPanel, object: nil)
                    }
                } label: {
                    Image(systemName: "sparkles")
                        .font(CiderFont.bodyMedium)
                        .foregroundColor(
                            (aiChatVisible && aiChatDocked && selectedTab?.id == CiderTab.aiChat.id)
                            ? CiderColors.controlAccent : CiderColors.secondary
                        )
                        .frame(width: CiderPanelDesign.trafficLightTapTarget, height: CiderPanelDesign.trafficLightTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Toggle AI Chat")

                Spacer(minLength: 0)

                // View options
                viewOptionsButton
            }
        }
        .padding(.top, Spacing.sm)
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.sm)
        .frame(width: BookmarksDesign.folderSidebarWidth)
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
            onCreateWhiteboard: { [self] name in
                let canvas = WhiteboardStorage.shared.createCanvas(name: name)
                let savedView = savedViewStorage.createWhiteboardView(name: name, canvasID: canvas.id)
                savedViewStorage.addToTabOrder(savedView.id)
                selectedFolderID = nil
                selectedTab = .savedView(id: savedView.id, name: savedView.name)
            },
            onDismiss: { [self] in
                showNewItemPicker = false
            }
        )
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
                        cardSizeScale: $homeCardSizeScale
                    )
                }
        } else if let savedViewID = selectedTab?.savedViewID {
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
                savedViewStorage.savedView(for: savedViewID)?.filterSpec.entityTypes ?? Set(LibraryEntityType.allCases)
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
