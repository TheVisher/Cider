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
    @ObservedObject private var dateCardStorage = DateCardStorage.shared
    @ObservedObject private var contactStorage = ContactStorage.shared
    @ObservedObject private var stackStorage = CardStackStorage.shared
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

    private var cardSizing: LibraryCardSizing {
        LibraryCardSizing(scale: savedView.layoutSpec.cardSizeScale)
    }

    private var filteredItems: [LibraryItemV2] {
        libraryViewModel.filteredItems(
            using: savedView.filterSpec,
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
                onSave: { title, details, startAt, endAt, allDay, location, amount, labelIDs in
                    saveDateCard(
                        existingCard: context.existingCard,
                        title: title,
                        details: details,
                        startAt: startAt,
                        endAt: endAt,
                        allDay: allDay,
                        location: location,
                        amount: amount,
                        labelIDs: labelIDs
                    )
                },
                onDelete: { dateCard in
                    _ = dateCardStorage.deleteDateCard(dateCard.id)
                }
            )
        }
        .sheet(item: $contactEditorContext) { context in
            ContactEditorSheet(
                existingContact: context.existingContact,
                onSave: { displayName, relationshipLabel, birthday, notes, labelIDs, addBirthdayDateCard in
                    saveContact(
                        existingContact: context.existingContact,
                        displayName: displayName,
                        relationshipLabel: relationshipLabel,
                        birthday: birthday,
                        notes: notes,
                        labelIDs: labelIDs,
                        addBirthdayDateCard: addBirthdayDateCard
                    )
                },
                onDelete: { contact in
                    _ = contactStorage.deleteContact(contact.id)
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    filterChip(for: .bookmark, label: "Bookmarks")
                    filterChip(for: .note, label: "Notes")
                    filterChip(for: .dateCard, label: "Date Cards")
                    filterChip(for: .contact, label: "Contacts")
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

    private func saveDateCard(
        existingCard: DateCard?,
        title: String,
        details: String,
        startAt: Date,
        endAt: Date?,
        allDay: Bool,
        location: String,
        amount: Double?,
        labelIDs: [UUID]
    ) {
        if var existingCard {
            existingCard.title = title
            existingCard.details = details
            existingCard.startAt = startAt
            existingCard.endAt = endAt
            existingCard.allDay = allDay
            existingCard.location = location
            existingCard.amount = amount
            existingCard.labelIDs = labelIDs
            _ = dateCardStorage.updateDateCard(existingCard)
            return
        }

        var created = dateCardStorage.createDateCard(
            title: title,
            startAt: startAt,
            endAt: endAt,
            allDay: allDay,
            amount: amount
        )
        created.details = details
        created.location = location
        created.amount = amount
        created.labelIDs = labelIDs
        _ = dateCardStorage.updateDateCard(created)
    }

    private func saveContact(
        existingContact: ContactCard?,
        displayName: String,
        relationshipLabel: String,
        birthday: Date?,
        notes: String,
        labelIDs: [UUID],
        addBirthdayDateCard: Bool
    ) {
        if var existingContact {
            existingContact.displayName = displayName
            existingContact.relationshipLabel = relationshipLabel
            existingContact.birthday = birthday
            existingContact.notes = notes
            existingContact.labelIDs = labelIDs
            _ = contactStorage.updateContact(existingContact)
            if addBirthdayDateCard, let birthday {
                createOrUpdateBirthdayDateCard(for: existingContact, birthday: birthday)
            }
            return
        }

        var created = contactStorage.createContact(displayName: displayName)
        created.relationshipLabel = relationshipLabel
        created.birthday = birthday
        created.notes = notes
        created.labelIDs = labelIDs
        _ = contactStorage.updateContact(created)

        if addBirthdayDateCard, let birthday {
            createOrUpdateBirthdayDateCard(for: created, birthday: birthday)
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
                DateCardListRow(dateCard: dateCard) {
                    editorContext = DateCardEditorContext(existingCard: dateCard, defaultDate: dateCard.startAt)
                }
            )
        case .contact:
            if case .contact(let contact) = item {
                return AnyView(
                    ContactListRow(contact: contact) {
                        contactEditorContext = ContactEditorContext(existingContact: contact)
                    }
                )
            }
            return AnyView(genericRow(item))
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
                        .contextMenu {
                            addToStackMenu(for: item)
                        }
                }
            case .grid:
                let columns = [GridItem(.adaptive(minimum: cardSizing.cardMinWidth), spacing: Spacing.md)]
                LazyVGrid(columns: columns, spacing: Spacing.md) {
                    ForEach(filteredItems) { item in
                        itemCard(item)
                            .contextMenu {
                                addToStackMenu(for: item)
                            }
                    }
                }
            case .masonry:
                MasonryLayout(
                    minimumColumnWidth: cardSizing.cardMinWidth,
                    itemSpacing: Spacing.md
                ) {
                    ForEach(filteredItems) { item in
                        itemCard(item)
                            .contextMenu {
                                addToStackMenu(for: item)
                            }
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
            DateCardCardView(dateCard: dateCard) {
                editorContext = DateCardEditorContext(existingCard: dateCard, defaultDate: dateCard.startAt)
            }
        case .contact:
            if case .contact(let contact) = item {
                ContactCardCardView(contact: contact) {
                    contactEditorContext = ContactEditorContext(existingContact: contact)
                }
            } else {
                GenericLibraryItemCard(item: item)
            }
        }
    }

    private func createOrUpdateBirthdayDateCard(for contact: ContactCard, birthday: Date) {
        var refreshedContact = contactStorage.contact(for: contact.id) ?? contact
        let targetStart = nextBirthdayOccurrence(from: birthday)

        if let linkedDateCardID = refreshedContact.linkedEntities.first(where: { $0.type == .dateCard })?.entityID,
           var existingBirthdayCard = dateCardStorage.dateCard(for: linkedDateCardID) {
            existingBirthdayCard.title = "\(refreshedContact.displayName) Birthday"
            existingBirthdayCard.details = "Birthday reminder linked to \(refreshedContact.displayName)."
            existingBirthdayCard.startAt = targetStart
            existingBirthdayCard.endAt = nil
            existingBirthdayCard.allDay = true
            existingBirthdayCard.location = ""
            existingBirthdayCard.recurrenceRule = DateCardRecurrenceRule(frequency: .yearly, interval: 1)
            if !existingBirthdayCard.linkedEntities.contains(where: { $0.type == .contact && $0.entityID == refreshedContact.id }) {
                existingBirthdayCard.linkedEntities.append(LibraryEntityRef(type: .contact, entityID: refreshedContact.id))
            }
            _ = dateCardStorage.updateDateCard(existingBirthdayCard)
            if !refreshedContact.linkedEntities.contains(where: { $0.type == .dateCard && $0.entityID == existingBirthdayCard.id }) {
                refreshedContact.linkedEntities.append(LibraryEntityRef(type: .dateCard, entityID: existingBirthdayCard.id))
                _ = contactStorage.updateContact(refreshedContact)
            }
            return
        }

        var createdBirthdayCard = dateCardStorage.createDateCard(
            title: "\(refreshedContact.displayName) Birthday",
            startAt: targetStart,
            endAt: nil,
            allDay: true
        )
        createdBirthdayCard.details = "Birthday reminder linked to \(refreshedContact.displayName)."
        createdBirthdayCard.recurrenceRule = DateCardRecurrenceRule(frequency: .yearly, interval: 1)
        createdBirthdayCard.linkedEntities.append(LibraryEntityRef(type: .contact, entityID: refreshedContact.id))
        _ = dateCardStorage.updateDateCard(createdBirthdayCard)

        if !refreshedContact.linkedEntities.contains(where: { $0.type == .dateCard && $0.entityID == createdBirthdayCard.id }) {
            refreshedContact.linkedEntities.append(LibraryEntityRef(type: .dateCard, entityID: createdBirthdayCard.id))
            _ = contactStorage.updateContact(refreshedContact)
        }
    }

    private func nextBirthdayOccurrence(from birthday: Date, now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let monthDay = calendar.dateComponents([.month, .day], from: birthday)
        let year = calendar.component(.year, from: now)

        guard
            let month = monthDay.month,
            let day = monthDay.day,
            let candidate = calendar.date(from: DateComponents(year: year, month: month, day: day))
        else {
            return birthday
        }

        if candidate >= calendar.startOfDay(for: now) {
            return candidate
        }

        return calendar.date(from: DateComponents(year: year + 1, month: month, day: day)) ?? candidate
    }

    @ViewBuilder
    private func addToStackMenu(for item: LibraryItemV2) -> some View {
        if stackStorage.stacks.isEmpty {
            Button("Create Stack and Add") {
                let created = stackStorage.createStack(name: "New Stack")
                addManualItem(item, to: created)
            }
        } else {
            Menu("Add to Stack") {
                ForEach(stackStorage.stacks) { stack in
                    let alreadyIncluded = stack.manualItemRefs.contains(entityRef(for: item))
                    Button(alreadyIncluded ? "\(stack.name) (Added)" : stack.name) {
                        addManualItem(item, to: stack)
                    }
                    .disabled(alreadyIncluded)
                }
            }
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

private struct DateCardEditorContext: Identifiable {
    let id = UUID()
    let existingCard: DateCard?
    let defaultDate: Date
}

private struct ContactEditorContext: Identifiable {
    let id = UUID()
    let existingContact: ContactCard?
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
        }
    }
}

private struct DateCardListRow: View {
    let dateCard: DateCard
    let onOpen: () -> Void

    var body: some View {
        Button {
            onOpen()
        } label: {
            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.hairline) {
                    Text(dateCard.startAt.formatted(.dateTime.month(.abbreviated)))
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                    Text(dateCard.startAt.formatted(.dateTime.day()))
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.primary)
                }
                .frame(width: 42, alignment: .leading)

                VStack(alignment: .leading, spacing: 1) {
                    Text(dateCard.title)
                        .font(CiderFont.subheadingMedium)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    HStack(spacing: Spacing.xs) {
                        Text(dateCard.allDay ? "All Day" : dateCard.startAt.formatted(.dateTime.hour().minute()))
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.tertiary)
                        if !dateCard.location.isEmpty {
                            Text("\u{00B7}")
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.quaternary)
                            Text(dateCard.location)
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.tertiary)
                                .lineLimit(1)
                        }
                    }

                    if let amount = dateCard.amount {
                        Text(Self.currencyFormatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount))
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.tertiary)
                    }
                }

                Spacer(minLength: Spacing.sm)

                if dateCard.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(CiderFont.bodyMedium)
                        .foregroundColor(CiderColors.controlAccent)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.surfaceSubtle)
            )
        }
        .buttonStyle(.plain)
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
