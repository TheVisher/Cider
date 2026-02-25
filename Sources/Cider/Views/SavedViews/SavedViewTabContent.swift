import SwiftUI

struct SavedViewTabContent: View {
    let savedView: SavedView
    @ObservedObject var libraryViewModel: LibraryViewModel
    var folders: [Folder] = []
    var onOpenBookmark: ((Bookmark) -> Void)? = nil
    var onOpenNote: ((Note) -> Void)? = nil
    var onDeleteBookmark: ((Bookmark) -> Void)? = nil
    var onDeleteNote: ((Note) -> Void)? = nil
    var onRenameNote: ((Note, String) -> Void)? = nil
    var onMoveBookmarkToFolder: ((Bookmark, UUID?) -> Void)? = nil
    var onMoveNoteToFolder: ((Note, UUID?) -> Void)? = nil
    var onOpenDateCard: ((DateCard) -> Void)? = nil
    var onOpenContact: ((ContactCard) -> Void)? = nil
    @ObservedObject private var dateCardStorage = DateCardStorage.shared
    @ObservedObject private var contactStorage = ContactStorage.shared
    @ObservedObject private var labelStorage = CardLabelStorage.shared
    @ObservedObject private var stackStorage = CardStackStorage.shared
    var searchText: String = ""
    var onUpdateSavedView: ((SavedView) -> Void)? = nil
    var onDeleteSavedView: ((UUID) -> Void)? = nil

    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var calendarMode: CalendarProjectionMode = .month
    @State private var calendarAnchorDate = Date()
    @State private var editorContext: DateCardEditorContext?
    @State private var contactEditorContext: ContactEditorContext?
    @State private var isStackManagerPresented = false
    @State private var stackManagerInitialSelectionID: UUID?
    @State private var selectedStackSurfaceID: StackSurfaceSelection?
    @State private var selectedStackSurfaceSnapshot: StackSurfaceResult?

    private var cardSizing: LibraryCardSizing {
        LibraryCardSizing(scale: savedView.layoutSpec.cardSizeScale)
    }

    private var effectiveFilterSpec: SavedViewFilterSpec {
        let sidebarQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if sidebarQuery.isEmpty {
            return savedView.filterSpec
        }
        // Combine sidebar search with any existing persistent textQuery
        var spec = savedView.filterSpec
        if spec.textQuery.isEmpty {
            spec.textQuery = sidebarQuery
        } else {
            spec.textQuery = spec.textQuery + " " + sidebarQuery
        }
        return spec
    }

    private var filteredItems: [LibraryItemV2] {
        libraryViewModel.filteredItems(
            using: effectiveFilterSpec,
            sort: savedView.sortSpec
        )
    }

    private var surfacedStacks: [StackSurfaceResult] {
        libraryViewModel.surfacedStacks(from: filteredItems)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xs) {
                headerRow
                filterChipsRow
                if !surfacedStacks.isEmpty {
                    surfacedStacksSection
                }

                if savedView.layoutSpec.showsCalendarProjection {
                    calendarControlsRow
                    CalendarProjectionView(
                        items: filteredItems,
                        mode: calendarMode,
                        anchorDate: calendarAnchorDate,
                        showsGhostCells: savedView.layoutSpec.showsGhostCells,
                        onSelectDay: { day in
                            editorContext = DateCardEditorContext(existingCard: nil, defaultDate: day)
                        },
                        onSelectDateCard: { dateCard in
                            editorContext = DateCardEditorContext(existingCard: dateCard, defaultDate: dateCard.startAt)
                        }
                    )
                } else {
                    listGridMasonryContent
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $editorContext) { context in
            DateCardEditorSheet(
                existingCard: context.existingCard,
                defaultDate: context.defaultDate,
                onSave: { title, details, startAt, endAt, allDay, location, amount, labelIDs, recurrenceRule in
                    LibraryItemEditor.saveDateCard(
                        existingCard: context.existingCard,
                        title: title,
                        details: details,
                        startAt: startAt,
                        endAt: endAt,
                        allDay: allDay,
                        location: location,
                        amount: amount,
                        labelIDs: labelIDs,
                        recurrenceRule: recurrenceRule
                    )
                },
                onDelete: { dateCard in
                    _ = dateCardStorage.deleteDateCard(dateCard.id)
                    let trashItem = TrashStorage.shared.trashDateCard(dateCard, ciderDir: StoragePaths.ciderDataDirectoryURL())
                    CiderUndoManager.shared.record(.deletedToTrash(itemType: .dateCard, trashItem: trashItem))
                }
            )
        }
        .sheet(item: $contactEditorContext) { context in
            ContactEditorSheet(
                existingContact: context.existingContact,
                onSave: { draftContactID, displayName, relationshipLabel, birthday, notes, labelIDs, addBirthdayDateCard, email, phone, address, hasAvatar in
                    LibraryItemEditor.saveContact(
                        draftContactID: draftContactID,
                        existingContact: context.existingContact,
                        displayName: displayName,
                        relationshipLabel: relationshipLabel,
                        birthday: birthday,
                        notes: notes,
                        labelIDs: labelIDs,
                        addBirthdayDateCard: addBirthdayDateCard,
                        email: email,
                        phone: phone,
                        address: address,
                        hasAvatar: hasAvatar
                    )
                },
                onDelete: { contact in
                    _ = contactStorage.deleteContact(contact.id)
                    let trashItem = TrashStorage.shared.trashContact(contact, ciderDir: StoragePaths.ciderDataDirectoryURL())
                    CiderUndoManager.shared.record(.deletedToTrash(itemType: .contact, trashItem: trashItem))
                }
            )
        }
        .sheet(isPresented: $isStackManagerPresented) {
            StackManagerSheet(
                availableItems: filteredItems,
                initialSelectedStackID: stackManagerInitialSelectionID
            )
        }
        .sheet(item: $selectedStackSurfaceID) { selection in
            if let surface = surfacedStacks.first(where: { $0.id == selection.id }) {
                StackDetailSheet(
                    surface: surface,
                    onOpenBookmark: { bookmark in
                        onOpenBookmark?(bookmark)
                    },
                    onOpenNote: { note in
                        onOpenNote?(note)
                    },
                    onOpenDateCard: { dateCard in
                        editorContext = DateCardEditorContext(existingCard: dateCard, defaultDate: dateCard.startAt)
                    },
                    onOpenContact: { contact in
                        contactEditorContext = ContactEditorContext(existingContact: contact)
                    }
                )
                .onAppear {
                    selectedStackSurfaceSnapshot = surface
                }
            } else if let snapshot = selectedStackSurfaceSnapshot, snapshot.id == selection.id {
                StackDetailSheet(
                    surface: snapshot,
                    onOpenBookmark: { bookmark in
                        onOpenBookmark?(bookmark)
                    },
                    onOpenNote: { note in
                        onOpenNote?(note)
                    },
                    onOpenDateCard: { dateCard in
                        editorContext = DateCardEditorContext(existingCard: dateCard, defaultDate: dateCard.startAt)
                    },
                    onOpenContact: { contact in
                        contactEditorContext = ContactEditorContext(existingContact: contact)
                    }
                )
            } else {
                VStack(spacing: Spacing.md) {
                    Image(systemName: "square.stack.3d.up")
                        .font(CiderFont.emptyStateIcon)
                        .foregroundColor(CiderColors.tertiary)
                    Text("Stack no longer surfaced")
                        .font(CiderFont.subheading)
                        .foregroundColor(CiderColors.secondary)
                    Text("Adjust rules or mark an item incomplete to surface it again.")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(Spacing.lg)
                .frame(minWidth: 420, minHeight: 280)
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: savedView.layoutSpec.showsCalendarProjection ? "calendar" : "line.3.horizontal.decrease.circle")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)

            if isRenaming {
                TextField("View name", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.secondary)
                    .onSubmit { commitRename() }
                    .frame(maxWidth: 220, alignment: .leading)
            } else {
                Text(savedView.name)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.secondary)
            }

            Text("\(filteredItems.count)")
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.quaternary)

            Spacer(minLength: Spacing.xs)

            if isRenaming {
                Button {
                    commitRename()
                } label: {
                    Image(systemName: "checkmark")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.controlAccent)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)

                Button {
                    isRenaming = false
                    draftName = savedView.name
                } label: {
                    Image(systemName: "xmark")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    draftName = savedView.name
                    isRenaming = true
                } label: {
                    Image(systemName: "pencil")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Rename view")

                Button {
                    onDeleteSavedView?(savedView.id)
                } label: {
                    Image(systemName: "trash")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.destructive)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Delete view")

                Button {
                    toggleCalendarProjection()
                } label: {
                    Image(systemName: savedView.layoutSpec.showsCalendarProjection ? "list.bullet" : "calendar")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help(savedView.layoutSpec.showsCalendarProjection ? "Show list view" : "Show calendar view")

                Button {
                    editorContext = DateCardEditorContext(existingCard: nil, defaultDate: calendarAnchorDate)
                } label: {
                    Image(systemName: "calendar.badge.plus")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Create date card")

                Button {
                    contactEditorContext = ContactEditorContext(existingContact: nil)
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Create contact card")

                Button {
                    stackManagerInitialSelectionID = nil
                    isStackManagerPresented = true
                } label: {
                    Image(systemName: "square.stack.3d.up")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Manage stacks")
            }
        }
        .padding(.bottom, Spacing.xs)
        .onAppear {
            if draftName.isEmpty {
                draftName = savedView.name
            }
        }
    }

    private var calendarControlsRow: some View {
        HStack(spacing: Spacing.xs) {
            modeButton(.week, label: "Week")
            modeButton(.month, label: "Month")

            Spacer(minLength: Spacing.xs)

            Button {
                shiftCalendarAnchor(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)

            Text(calendarHeaderTitle)
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.secondary)

            Button {
                shiftCalendarAnchor(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)

            Button {
                calendarAnchorDate = Date()
            } label: {
                Text("Today")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.tertiary)
            }
            .buttonStyle(.plain)

            Button {
                toggleGhostCells()
            } label: {
                Image(systemName: savedView.layoutSpec.showsGhostCells ? "square.dashed" : "square")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(savedView.layoutSpec.showsGhostCells ? "Hide ghost cells" : "Show ghost cells")
        }
        .padding(.bottom, Spacing.sm)
    }

    private var filterChipsRow: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Spacer(minLength: 0)

                Menu {
                    sortButton(.createdDescending, label: "Created (Newest)")
                    sortButton(.createdAscending, label: "Created (Oldest)")
                    sortButton(.updatedDescending, label: "Updated (Newest)")
                    sortButton(.updatedAscending, label: "Updated (Oldest)")
                    sortButton(.titleAscending, label: "Title (A-Z)")
                    sortButton(.titleDescending, label: "Title (Z-A)")
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.tertiary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.hairline)
                        .background(
                            Capsule(style: .continuous)
                                .fill(CiderColors.separatorLight)
                        )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    filterChip(for: .bookmark, label: "Bookmarks")
                    filterChip(for: .note, label: "Notes")
                    filterChip(for: .dateCard, label: "Date Cards")
                    filterChip(for: .contact, label: "Contacts")
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    completedChip
                    ForEach(labelStorage.labels) { label in
                        labelFilterChip(label)
                    }
                }
            }

            HStack(spacing: Spacing.xs) {
                displayModeChip(.list, label: "List")
                displayModeChip(.grid, label: "Grid")
                displayModeChip(.masonry, label: "Masonry")
            }
        }
        .padding(.bottom, Spacing.sm)
    }

    private var surfacedStacksSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "square.stack.3d.up")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)
                Text("Surfaced Stacks")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)
            }

            let columns = [GridItem(.adaptive(minimum: 220), spacing: Spacing.md)]
            LazyVGrid(columns: columns, spacing: Spacing.md) {
                ForEach(surfacedStacks) { surface in
                    StackCardView(surface: surface) {
                        selectedStackSurfaceID = StackSurfaceSelection(id: surface.id)
                    } onTogglePinned: { stack in
                        var updated = stack
                        updated.isPinned.toggle()
                        _ = stackStorage.updateStack(updated)
                    } onManage: { stack in
                        stackManagerInitialSelectionID = stack.id
                        isStackManagerPresented = true
                    }
                }
            }
        }
        .padding(.bottom, Spacing.sm)
    }

    private func filterChip(for type: LibraryEntityType, label: String) -> some View {
        let isOn = savedView.filterSpec.entityTypes.contains(type)
        return Button {
            toggleEntityType(type)
        } label: {
            Text(label)
                .font(CiderFont.captionMedium)
                .foregroundColor(isOn ? CiderColors.primary : CiderColors.tertiary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.hairline)
                .background(
                    Capsule(style: .continuous)
                        .fill(isOn ? CiderColors.separatorMedium : CiderColors.separatorLight)
                )
        }
        .buttonStyle(.plain)
    }

    private func toggleEntityType(_ type: LibraryEntityType) {
        var nextTypes = savedView.filterSpec.entityTypes
        if nextTypes.contains(type) {
            if nextTypes.count == 1 {
                return
            }
            nextTypes.remove(type)
        } else {
            nextTypes.insert(type)
        }

        var updated = savedView
        updated.filterSpec.entityTypes = nextTypes
        onUpdateSavedView?(updated)
    }

    private var completedChip: some View {
        let isOn = savedView.filterSpec.includeCompleted
        return Button {
            var updated = savedView
            updated.filterSpec.includeCompleted.toggle()
            onUpdateSavedView?(updated)
        } label: {
            Text("Completed")
                .font(CiderFont.captionMedium)
                .foregroundColor(isOn ? CiderColors.primary : CiderColors.tertiary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.hairline)
                .background(
                    Capsule(style: .continuous)
                        .fill(isOn ? CiderColors.separatorMedium : CiderColors.separatorLight)
                )
        }
        .buttonStyle(.plain)
    }

    private func labelFilterChip(_ label: CardLabel) -> some View {
        let isOn = savedView.filterSpec.labelIDs.contains(label.id)
        return Button {
            var updated = savedView
            if updated.filterSpec.labelIDs.contains(label.id) {
                updated.filterSpec.labelIDs.remove(label.id)
            } else {
                updated.filterSpec.labelIDs.insert(label.id)
            }
            onUpdateSavedView?(updated)
        } label: {
            Text(label.name)
                .font(CiderFont.captionMedium)
                .foregroundColor(isOn ? CiderColors.primary : CiderColors.tertiary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.hairline)
                .background(
                    Capsule(style: .continuous)
                        .fill(isOn ? CiderColors.separatorMedium : CiderColors.separatorLight)
                )
        }
        .buttonStyle(.plain)
    }

    private func sortButton(_ mode: LibrarySortMode, label: String) -> some View {
        Button(label) {
            var updated = savedView
            updated.sortSpec.mode = mode
            onUpdateSavedView?(updated)
        }
    }

    private func displayModeChip(_ mode: LibraryDisplayMode, label: String) -> some View {
        let isOn = savedView.layoutSpec.displayMode == mode
        return Button {
            var updated = savedView
            updated.layoutSpec.displayMode = mode
            onUpdateSavedView?(updated)
        } label: {
            Text(label)
                .font(CiderFont.captionMedium)
                .foregroundColor(isOn ? CiderColors.primary : CiderColors.tertiary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.hairline)
                .background(
                    Capsule(style: .continuous)
                        .fill(isOn ? CiderColors.separatorMedium : CiderColors.separatorLight)
                )
        }
        .buttonStyle(.plain)
    }

    private func commitRename() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draftName = savedView.name
            isRenaming = false
            return
        }
        var updated = savedView
        updated.name = trimmed
        onUpdateSavedView?(updated)
        isRenaming = false
    }

    private func toggleCalendarProjection() {
        var updated = savedView
        updated.layoutSpec.showsCalendarProjection.toggle()
        onUpdateSavedView?(updated)
    }

    private func toggleGhostCells() {
        var updated = savedView
        updated.layoutSpec.showsGhostCells.toggle()
        onUpdateSavedView?(updated)
    }

    private func modeButton(_ mode: CalendarProjectionMode, label: String) -> some View {
        let isSelected = calendarMode == mode
        return Button {
            calendarMode = mode
        } label: {
            Text(label)
                .font(CiderFont.captionMedium)
                .foregroundColor(isSelected ? CiderColors.primary : CiderColors.tertiary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.hairline)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? CiderColors.separatorMedium : CiderColors.separatorLight)
                )
        }
        .buttonStyle(.plain)
    }

    private var calendarHeaderTitle: String {
        let formatter = DateFormatter()
        switch calendarMode {
        case .week:
            let calendar = Calendar.current
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: calendarAnchorDate) else {
                return "Week"
            }
            formatter.dateFormat = "MMM d"
            let start = formatter.string(from: weekInterval.start)
            let end = formatter.string(from: weekInterval.end.addingTimeInterval(-1))
            return "\(start) - \(end)"
        case .month:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: calendarAnchorDate)
        }
    }

    private func shiftCalendarAnchor(by delta: Int) {
        let calendar = Calendar.current
        let component: Calendar.Component = (calendarMode == .week) ? .weekOfYear : .month
        if let next = calendar.date(byAdding: component, value: delta, to: calendarAnchorDate) {
            calendarAnchorDate = next
        }
    }

    private func itemRow(_ item: LibraryItemV2) -> some View {
        switch item {
        case .bookmark(let bookmark):
            return AnyView(
                BookmarkListRow(
                    bookmark: bookmark,
                    searchText: "",
                    cardSizing: cardSizing.bookmarkSizing,
                    folders: folders,
                    onShowDetails: { onOpenBookmark?(bookmark) },
                    onOpen: { onOpenBookmark?(bookmark) },
                    onDelete: { onDeleteBookmark?(bookmark) },
                    onMoveToFolder: { folderID in onMoveBookmarkToFolder?(bookmark, folderID) }
                )
            )
        case .note(let note):
            return AnyView(
                NoteListRow(
                    note: note,
                    cardSizing: cardSizing.noteSizing,
                    searchText: "",
                    folderName: folderName(for: note),
                    folders: folders,
                    isSelected: false,
                    onOpen: { onOpenNote?(note) },
                    onRename: { newTitle in onRenameNote?(note, newTitle) },
                    onDelete: { onDeleteNote?(note) },
                    onMoveToFolder: { folderID in onMoveNoteToFolder?(note, folderID) }
                )
            )
        case .dateCard(let dateCard):
            return AnyView(
                DateCardListRow(
                    dateCard: dateCard,
                    onOpen: {
                        if let cb = onOpenDateCard { cb(dateCard) }
                        else { editorContext = DateCardEditorContext(existingCard: dateCard, defaultDate: dateCard.startAt) }
                    },
                    onToggleComplete: { DateCardStorage.shared.markCompleted(dateCard.id, completed: !dateCard.isCompleted) },
                    folders: folders,
                    onMoveToFolder: { folderID in
                        let oldFolderID = dateCard.folderID
                        DateCardStorage.shared.assignDateCard(dateCard.id, toFolder: folderID)
                        let folderName = folders.first(where: { $0.id == folderID })?.name ?? "Unfiled"
                        CiderUndoManager.shared.record(.movedToFolder(
                            itemType: .dateCard, itemID: dateCard.id, title: dateCard.title,
                            fromFolderID: oldFolderID, toFolderID: folderID, folderName: folderName
                        ))
                    },
                    onDelete: {
                        _ = DateCardStorage.shared.deleteDateCard(dateCard.id)
                        let trashItem = TrashStorage.shared.trashDateCard(dateCard, ciderDir: StoragePaths.ciderDataDirectoryURL())
                        CiderUndoManager.shared.record(.deletedToTrash(itemType: .dateCard, trashItem: trashItem))
                    }
                )
            )
        case .contact:
            if case .contact(let contact) = item {
                return AnyView(
                    ContactListRow(
                        contact: contact,
                        onOpen: {
                            if let cb = onOpenContact { cb(contact) }
                            else { contactEditorContext = ContactEditorContext(existingContact: contact) }
                        },
                        folders: folders,
                        onMoveToFolder: { folderID in
                            let oldFolderID = contact.folderID
                            ContactStorage.shared.assignContact(contact.id, toFolder: folderID)
                            let folderName = folders.first(where: { $0.id == folderID })?.name ?? "Unfiled"
                            CiderUndoManager.shared.record(.movedToFolder(
                                itemType: .contact, itemID: contact.id, title: contact.displayName,
                                fromFolderID: oldFolderID, toFolderID: folderID, folderName: folderName
                            ))
                        },
                        onDelete: {
                            _ = ContactStorage.shared.deleteContact(contact.id)
                            let trashItem = TrashStorage.shared.trashContact(contact, ciderDir: StoragePaths.ciderDataDirectoryURL())
                            CiderUndoManager.shared.record(.deletedToTrash(itemType: .contact, trashItem: trashItem))
                        }
                    )
                )
            }
            return AnyView(genericRow(item))
        case .externalFile(let file):
            return AnyView(
                SourceCardView(
                    file: file,
                    width: .infinity,
                    onOpen: {
                        NotificationCenter.default.post(
                            name: Notification.Name("cider.openExternalFile"),
                            object: nil,
                            userInfo: ["fileURL": file.path]
                        )
                    },
                    onDelete: { try? FileManager.default.trashItem(at: file.path, resultingItemURL: nil) }
                )
            )
        }
    }

    private func genericRow(_ item: LibraryItemV2) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon(for: item))
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.controlAccent)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(CiderFont.subheadingMedium)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)

                Text(subtitle(for: item))
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.sm)

            Text(item.updatedDate.formatted(.relative(presentation: .named)))
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.quaternary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
        )
    }

    @ViewBuilder
    private var listGridMasonryContent: some View {
        if filteredItems.isEmpty {
            emptyStateInline
        } else {
            switch savedView.layoutSpec.displayMode {
            case .list:
                ForEach(filteredItems) { item in
                    itemRow(item)
                        .modifier(CardContextMenuModifier {
                            contextMenuItems(for: item)
                        })
                }
            case .grid:
                let columns = [GridItem(.adaptive(minimum: cardSizing.cardMinWidth), spacing: Spacing.md)]
                LazyVGrid(columns: columns, spacing: Spacing.md) {
                    ForEach(filteredItems) { item in
                        itemCard(item)
                            .modifier(CardContextMenuModifier {
                                contextMenuItems(for: item)
                            })
                    }
                }
            case .masonry:
                MasonryLayout(
                    minimumColumnWidth: cardSizing.cardMinWidth,
                    itemSpacing: Spacing.md
                ) {
                    ForEach(filteredItems) { item in
                        itemCard(item)
                            .modifier(CardContextMenuModifier {
                                contextMenuItems(for: item)
                            })
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func itemCard(_ item: LibraryItemV2) -> some View {
        switch item {
        case .bookmark(let bookmark):
            BookmarkCard(
                bookmark: bookmark,
                searchText: "",
                mode: savedView.layoutSpec.displayMode == .grid ? .grid : .masonry,
                cardSizing: cardSizing.bookmarkSizing,
                folders: folders,
                onShowDetails: { onOpenBookmark?(bookmark) },
                onOpen: { onOpenBookmark?(bookmark) },
                onDelete: { onDeleteBookmark?(bookmark) },
                onMoveToFolder: { folderID in onMoveBookmarkToFolder?(bookmark, folderID) }
            )
        case .note(let note):
            NoteCardView(
                note: note,
                mode: savedView.layoutSpec.displayMode == .grid ? .grid : .masonry,
                cardSizing: cardSizing.noteSizing,
                searchText: "",
                folderName: folderName(for: note),
                folders: folders,
                onOpen: { onOpenNote?(note) },
                onRename: { newTitle in onRenameNote?(note, newTitle) },
                onDelete: { onDeleteNote?(note) },
                onMoveToFolder: { folderID in onMoveNoteToFolder?(note, folderID) }
            )
        case .dateCard(let dateCard):
            DateCardCardView(
                dateCard: dateCard,
                onOpen: {
                    if let cb = onOpenDateCard { cb(dateCard) }
                    else { editorContext = DateCardEditorContext(existingCard: dateCard, defaultDate: dateCard.startAt) }
                },
                onToggleComplete: { DateCardStorage.shared.markCompleted(dateCard.id, completed: !dateCard.isCompleted) },
                folders: folders,
                onMoveToFolder: { folderID in
                    let oldFolderID = dateCard.folderID
                    DateCardStorage.shared.assignDateCard(dateCard.id, toFolder: folderID)
                    let folderName = folders.first(where: { $0.id == folderID })?.name ?? "Unfiled"
                    CiderUndoManager.shared.record(.movedToFolder(
                        itemType: .dateCard, itemID: dateCard.id, title: dateCard.title,
                        fromFolderID: oldFolderID, toFolderID: folderID, folderName: folderName
                    ))
                },
                onDelete: {
                    _ = DateCardStorage.shared.deleteDateCard(dateCard.id)
                    let trashItem = TrashStorage.shared.trashDateCard(dateCard, ciderDir: StoragePaths.ciderDataDirectoryURL())
                    CiderUndoManager.shared.record(.deletedToTrash(itemType: .dateCard, trashItem: trashItem))
                }
            )
        case .contact:
            if case .contact(let contact) = item {
                ContactCardCardView(
                    contact: contact,
                    onOpen: {
                        if let cb = onOpenContact { cb(contact) }
                        else { contactEditorContext = ContactEditorContext(existingContact: contact) }
                    },
                    folders: folders,
                    onMoveToFolder: { folderID in
                        let oldFolderID = contact.folderID
                        ContactStorage.shared.assignContact(contact.id, toFolder: folderID)
                        let folderName = folders.first(where: { $0.id == folderID })?.name ?? "Unfiled"
                        CiderUndoManager.shared.record(.movedToFolder(
                            itemType: .contact, itemID: contact.id, title: contact.displayName,
                            fromFolderID: oldFolderID, toFolderID: folderID, folderName: folderName
                        ))
                    },
                    onDelete: {
                        _ = ContactStorage.shared.deleteContact(contact.id)
                        let trashItem = TrashStorage.shared.trashContact(contact, ciderDir: StoragePaths.ciderDataDirectoryURL())
                        CiderUndoManager.shared.record(.deletedToTrash(itemType: .contact, trashItem: trashItem))
                    }
                )
            } else {
                GenericLibraryItemCard(item: item)
            }
        case .externalFile(let file):
            SourceCardView(
                file: file,
                width: cardSizing.bookmarkSizing.cardMinWidth,
                onOpen: {
                    NotificationCenter.default.post(
                        name: Notification.Name("cider.openExternalFile"),
                        object: nil,
                        userInfo: ["fileURL": file.path]
                    )
                },
                onDelete: { try? FileManager.default.trashItem(at: file.path, resultingItemURL: nil) }
            )
        }
    }

    private func contextMenuItems(for item: LibraryItemV2) -> [CardMenuItem] {
        var items: [CardMenuItem] = []
        items.append(contentsOf: addToStackMenuItems(for: item))
        items.append(contentsOf: linkMenuItems(for: item))
        items.append(contentsOf: linkedItemsMenuItems(for: item))
        return items
    }

    private func addToStackMenuItems(for item: LibraryItemV2) -> [CardMenuItem] {
        if stackStorage.stacks.isEmpty {
            return [.action(title: "Create Stack and Add") {
                let created = stackStorage.createStack(template: .blank, nameOverride: "New Stack")
                addManualItem(item, to: created)
            }]
        } else {
            let children: [CardMenuItem] = stackStorage.stacks.map { stack in
                let alreadyIncluded = stack.manualItemRefs.contains(entityRef(for: item))
                if alreadyIncluded {
                    return .action(title: "\(stack.name) (Added)") {}
                } else {
                    return .action(title: stack.name) {
                        addManualItem(item, to: stack)
                    }
                }
            }
            return [.submenu(title: "Add to Stack", children: children)]
        }
    }

    private func linkMenuItems(for item: LibraryItemV2) -> [CardMenuItem] {
        switch item {
        case .dateCard(let dateCard):
            if contactStorage.contacts.isEmpty {
                return [.submenu(title: "Link Contact", children: [
                    .action(title: "No contacts available") {}
                ])]
            }
            let children: [CardMenuItem] = contactStorage.contacts.map { contact in
                let alreadyLinked = dateCard.linkedEntities.contains(
                    LibraryEntityRef(type: .contact, entityID: contact.id)
                )
                if alreadyLinked {
                    return .action(title: "\(contact.displayName) (Linked)") {}
                } else {
                    return .action(title: contact.displayName) {
                        link(dateCardID: dateCard.id, contactID: contact.id)
                    }
                }
            }
            return [.submenu(title: "Link Contact", children: children)]
        case .contact(let contact):
            if dateCardStorage.dateCards.isEmpty {
                return [.submenu(title: "Link Date Card", children: [
                    .action(title: "No date cards available") {}
                ])]
            }
            let children: [CardMenuItem] = dateCardStorage.dateCards.map { dateCard in
                let alreadyLinked = contact.linkedEntities.contains(
                    LibraryEntityRef(type: .dateCard, entityID: dateCard.id)
                )
                if alreadyLinked {
                    return .action(title: "\(dateCard.title) (Linked)") {}
                } else {
                    return .action(title: dateCard.title) {
                        link(dateCardID: dateCard.id, contactID: contact.id)
                    }
                }
            }
            return [.submenu(title: "Link Date Card", children: children)]
        case .bookmark, .note, .externalFile:
            return []
        }
    }

    private func linkedItemsMenuItems(for item: LibraryItemV2) -> [CardMenuItem] {
        let refs = linkedEntityRefs(for: item)
        guard !refs.isEmpty else { return [] }
        let children: [CardMenuItem] = refs.compactMap { ref in
            guard let title = titleForLinkedRef(ref) else { return nil }
            return .action(title: title) {
                openLinkedRef(ref)
            }
        }
        guard !children.isEmpty else { return [] }
        return [.submenu(title: "Linked Items", children: children)]
    }

    private func linkedEntityRefs(for item: LibraryItemV2) -> [LibraryEntityRef] {
        switch item {
        case .dateCard(let dateCard):
            return dateCard.linkedEntities
        case .contact(let contact):
            return contact.linkedEntities
        case .bookmark, .note, .externalFile:
            return []
        }
    }

    private func titleForLinkedRef(_ ref: LibraryEntityRef) -> String? {
        switch ref.type {
        case .bookmark:
            return BookmarksStorage.shared.bookmarks.first(where: { $0.id == ref.entityID })?.title
        case .note:
            return NotesStorage.shared.notes.first(where: { $0.id == ref.entityID })?.title
        case .dateCard:
            return dateCardStorage.dateCard(for: ref.entityID)?.title
        case .contact:
            return contactStorage.contact(for: ref.entityID)?.displayName
        case .externalFile:
            return nil
        }
    }

    private func openLinkedRef(_ ref: LibraryEntityRef) {
        switch ref.type {
        case .bookmark:
            if let bookmark = BookmarksStorage.shared.bookmarks.first(where: { $0.id == ref.entityID }) {
                onOpenBookmark?(bookmark)
            }
        case .note:
            if let note = NotesStorage.shared.notes.first(where: { $0.id == ref.entityID }) {
                onOpenNote?(note)
            }
        case .dateCard:
            if let dateCard = dateCardStorage.dateCard(for: ref.entityID) {
                editorContext = DateCardEditorContext(existingCard: dateCard, defaultDate: dateCard.startAt)
            }
        case .contact:
            if let contact = contactStorage.contact(for: ref.entityID) {
                contactEditorContext = ContactEditorContext(existingContact: contact)
            }
        case .externalFile:
            break
        }
    }

    private func link(dateCardID: UUID, contactID: UUID) {
        guard var dateCard = dateCardStorage.dateCard(for: dateCardID),
              var contact = contactStorage.contact(for: contactID) else { return }

        let contactRef = LibraryEntityRef(type: .contact, entityID: contactID)
        if !dateCard.linkedEntities.contains(contactRef) {
            dateCard.linkedEntities.append(contactRef)
            _ = dateCardStorage.updateDateCard(dateCard)
        }

        let dateRef = LibraryEntityRef(type: .dateCard, entityID: dateCardID)
        if !contact.linkedEntities.contains(dateRef) {
            contact.linkedEntities.append(dateRef)
            _ = contactStorage.updateContact(contact)
        }
    }

    private func addManualItem(_ item: LibraryItemV2, to stack: CardStack) {
        var updated = stack
        let ref = entityRef(for: item)
        guard !updated.manualItemRefs.contains(ref) else { return }
        updated.manualItemRefs.append(ref)
        _ = stackStorage.updateStack(updated)
    }

    private func entityRef(for item: LibraryItemV2) -> LibraryEntityRef {
        switch item {
        case .bookmark(let bookmark):
            return LibraryEntityRef(type: .bookmark, entityID: bookmark.id)
        case .note(let note):
            return LibraryEntityRef(type: .note, entityID: note.id)
        case .dateCard(let dateCard):
            return LibraryEntityRef(type: .dateCard, entityID: dateCard.id)
        case .contact(let contact):
            return LibraryEntityRef(type: .contact, entityID: contact.id)
        case .externalFile(let file):
            return LibraryEntityRef(type: .externalFile, entityID: file.id)
        }
    }

    private func icon(for item: LibraryItemV2) -> String {
        switch item {
        case .bookmark:
            return "bookmark"
        case .note:
            return "note.text"
        case .dateCard:
            return "calendar"
        case .contact:
            return "person.crop.circle"
        case .externalFile:
            return "folder.badge.gear"
        }
    }

    private func subtitle(for item: LibraryItemV2) -> String {
        switch item {
        case .bookmark(let bookmark):
            return bookmark.hostDisplay
        case .note:
            return "Note"
        case .dateCard(let dateCard):
            return dateCard.location.isEmpty ? "Date Card" : dateCard.location
        case .contact(let contact):
            return contact.relationshipLabel.isEmpty ? "Contact" : contact.relationshipLabel
        case .externalFile(let file):
            return file.sourceName
        }
    }

    private var emptyStateInline: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: savedView.layoutSpec.showsCalendarProjection ? "calendar" : "line.3.horizontal.decrease.circle")
                .font(CiderFont.emptyStateIcon)
                .foregroundColor(CiderColors.tertiary)

            Text("No items in \(savedView.name)")
                .font(CiderFont.subheading)
                .foregroundColor(CiderColors.secondary)

            Text("Adjust filters or add more content to this saved view.")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.xl)
    }

    private func folderName(for note: Note) -> String? {
        guard let folderID = note.folderID else { return nil }
        return folders.first(where: { $0.id == folderID })?.name
    }
}

private struct StackSurfaceSelection: Identifiable {
    let id: UUID
}

private struct GenericLibraryItemCard: View {
    let item: LibraryItemV2
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.controlAccent)
                Text(item.title)
                    .font(CiderFont.subheadingSemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(2)
            }
            Text(subtitle)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
                .lineLimit(2)
            Text(item.updatedDate.formatted(.relative(presentation: .named)))
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.quaternary)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardContainer(isHovered: isHovered)
        .hoverState($isHovered, animation: .snappy)
    }

    private var icon: String {
        switch item {
        case .bookmark: "bookmark"
        case .note: "note.text"
        case .dateCard: "calendar"
        case .contact: "person.crop.circle"
        case .externalFile: "folder.badge.gear"
        }
    }

    private var subtitle: String {
        switch item {
        case .bookmark(let bookmark):
            bookmark.hostDisplay
        case .note:
            "Note"
        case .dateCard(let dateCard):
            dateCard.location.isEmpty ? "Date Card" : dateCard.location
        case .contact(let contact):
            contact.relationshipLabel.isEmpty ? "Contact" : contact.relationshipLabel
        case .externalFile(let file):
            file.sourceName
        }
    }
}

