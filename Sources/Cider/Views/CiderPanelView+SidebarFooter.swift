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
            // AI Quick Actions + Assistant button
            aiSidebarSection

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

    // MARK: - AI Sidebar Section

    @ViewBuilder
    var aiSidebarSection: some View {
        VStack(spacing: Spacing.xs) {
            // Header: sparkles + label + chevron, click to expand
            Button {
                withAnimation(reduceMotion ? .none : .snappy) {
                    aiSectionExpanded.toggle()
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "sparkles")
                        .font(CiderFont.bodyMedium)
                        .foregroundColor(CiderColors.controlAccent)
                    Text("AI")
                        .font(CiderFont.labelMedium)
                        .foregroundColor(CiderColors.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(CiderColors.quaternary)
                        .rotationEffect(.degrees(aiSectionExpanded ? 90 : 0))
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceSubtle)
                )
                .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Spacing.sm)

            // Expanded: quick actions + open chat button
            if aiSectionExpanded {
                VStack(spacing: Spacing.xxs) {
                    // Context-sensitive quick actions
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

                    // Open full chat
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
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(CiderColors.quaternary)
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Spacing.sm)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// Quick actions based on current context.
    /// Captures item names at render time so they survive detail panel closing.
    private var aiQuickActions: [AIQuickAction] {
        var actions: [AIQuickAction] = []
        let vm = AIAssistantViewModel.shared

        // Context-specific actions (capture names so they work even if detail closes)
        if let bookmark = vm.context.currentBookmark {
            let title = bookmark.title
            actions.append(AIQuickAction(icon: "text.quote", label: "Summarize Bookmark") {
                sendQuickMessage("Summarize the bookmark \"\(title)\"")
            })
            actions.append(AIQuickAction(icon: "rectangle.stack", label: "Find Similar") {
                sendQuickMessage("Find bookmarks similar to \"\(title)\"")
            })
            actions.append(AIQuickAction(icon: "tag", label: "Suggest Tags") {
                sendQuickMessage("What tags would you suggest for the bookmark \"\(title)\"?")
            })
        } else if let note = vm.context.currentNote {
            let title = note.title
            actions.append(AIQuickAction(icon: "text.quote", label: "Summarize Note") {
                sendQuickMessage("Summarize the note \"\(title)\"")
            })
        } else if let folder = vm.context.currentFolder {
            let name = folder.name
            actions.append(AIQuickAction(icon: "folder.badge.gearshape", label: "Organize Folder") {
                sendQuickMessage("How should I organize the items in the \"\(name)\" folder?")
            })
        }

        // General actions (always available)
        actions.append(AIQuickAction(icon: "chart.bar", label: "Library Summary") {
            sendQuickMessage("Give me a summary of my entire library")
        })
        actions.append(AIQuickAction(icon: "clock", label: "Recent Activity") {
            sendQuickMessage("What did I save in the last 7 days?")
        })
        actions.append(AIQuickAction(icon: "exclamationmark.circle", label: "Overdue Tasks") {
            sendQuickMessage("Do I have any overdue todos?")
        })

        return actions
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
