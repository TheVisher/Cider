import SwiftUI

struct KanbanCardMetadataInspectorView: View {
    let board: KanbanBoard
    let column: KanbanColumn
    let card: KanbanCard
    @Binding var draft: KanbanCardDraft
    var onSave: () -> Void
    var onMove: (String) -> Void
    var onDelete: () -> Void
    var onExportMarkdown: () -> Void
    var onOpenLinkedRef: ((LibraryEntityRef) -> Void)?

    @State private var isBoardExpanded = true
    @State private var isPlanningExpanded = true
    @State private var isLinkedExpanded = true
    @State private var isActionsExpanded = true
    @State private var isDatesExpanded = true

    @ObservedObject private var bookmarks = VaultBookmarkService.shared
    @ObservedObject private var notes = NotesStorage.shared
    @ObservedObject private var dateCards = DateCardStorage.shared
    @ObservedObject private var contacts = ContactStorage.shared
    @ObservedObject private var todos = TodoCardStorage.shared
    @ObservedObject private var files = VaultFileService.shared

    init(
        board: KanbanBoard,
        column: KanbanColumn,
        card: KanbanCard,
        draft: Binding<KanbanCardDraft>,
        onSave: @escaping () -> Void,
        onMove: @escaping (String) -> Void,
        onDelete: @escaping () -> Void,
        onExportMarkdown: @escaping () -> Void,
        onOpenLinkedRef: ((LibraryEntityRef) -> Void)? = nil
    ) {
        self.board = board
        self.column = column
        self.card = card
        _draft = draft
        self.onSave = onSave
        self.onMove = onMove
        self.onDelete = onDelete
        self.onExportMarkdown = onExportMarkdown
        self.onOpenLinkedRef = onOpenLinkedRef
    }

    var body: some View {
        ItemMetadataPanel {
            TextField("Card title", text: $draft.title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(1...3)
                .onSubmit { onSave() }
                .padding(.bottom, Spacing.md)

            ItemMetadataDivider()

            ItemMetadataSectionView(title: "Board", isExpanded: $isBoardExpanded) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    metadataLine("Board", board.name)
                    Picker("Status", selection: Binding(
                        get: { column.id },
                        set: { onMove($0) }
                    )) {
                        ForEach(board.columns) { column in
                            Text(column.name).tag(column.id)
                        }
                    }
                    .labelsHidden()
                }
            }

            ItemMetadataDivider()

            ItemMetadataSectionView(title: "Planning", isExpanded: $isPlanningExpanded) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Picker("Priority", selection: $draft.priority) {
                        Text("None").tag(KanbanPriority?.none)
                        ForEach(KanbanPriority.allCases, id: \.self) { priority in
                            Text(priority.rawValue.capitalized).tag(Optional(priority))
                        }
                    }

                    Picker("Color", selection: $draft.color) {
                        Text("None").tag(KanbanCardColor?.none)
                        ForEach(KanbanCardColor.allCases, id: \.self) { color in
                            Text(color.rawValue.capitalized).tag(Optional(color))
                        }
                    }

                    field("Agent") {
                        TextField("Agent", text: $draft.agent)
                            .textFieldStyle(.plain)
                            .onSubmit { onSave() }
                    }

                    field("Tags") {
                        TextField("Comma-separated", text: $draft.tagsText)
                            .textFieldStyle(.plain)
                            .onSubmit { onSave() }
                    }
                }
            }

            ItemMetadataDivider()

            kanbanLinkedSection

            ItemMetadataDivider()

            ItemMetadataSectionView(title: "Actions", isExpanded: $isActionsExpanded) {
                Button {
                    onExportMarkdown()
                } label: {
                    Label("Export Markdown", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(CiderSecondaryButtonStyle())
            }

            ItemMetadataDivider()

            ItemMetadataSectionView(title: "Dates", isExpanded: $isDatesExpanded) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    metadataLine("Created", card.created.formatted(date: .abbreviated, time: .omitted))
                    if let completed = card.completed {
                        metadataLine("Completed", completed.formatted(date: .abbreviated, time: .omitted))
                    }
                }
            }
        } footer: {
            ItemMetadataInfoFooter(
                rows: footerRows,
                onDelete: onDelete
            )
        }
    }

    private var footerRows: [ItemMetadataRow] {
        var rows = [
            ItemMetadataRow(
                id: "created",
                symbol: "calendar.badge.plus",
                title: "Created",
                value: card.created.formatted(date: .abbreviated, time: .shortened)
            ),
            ItemMetadataRow(
                id: "status",
                symbol: "rectangle.stack",
                title: "Status",
                value: column.name
            ),
            ItemMetadataRow(
                id: "type",
                symbol: "square.3.layers.3d",
                title: "Type",
                value: "Kanban Card"
            )
        ]

        if let completed = card.completed {
            rows.insert(
                ItemMetadataRow(
                    id: "completed",
                    symbol: "checkmark.circle",
                    title: "Completed",
                    value: completed.formatted(date: .abbreviated, time: .shortened)
                ),
                at: 1
            )
        }

        return rows
    }

    private var kanbanLinkedSection: some View {
        ItemMetadataSectionView(title: "Linked", isExpanded: $isLinkedExpanded) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                addLinkMenu

                if linkedRows.isEmpty {
                    ItemMetadataEmptyText(text: "Link specs, docs, or related work.")
                } else {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        ForEach(linkedRows) { row in
                            linkedRow(row)
                        }
                    }
                }
            }
        }
    }

    private var addLinkMenu: some View {
        Menu {
            if visibleCandidateGroups.isEmpty {
                Text("No items available")
            } else {
                ForEach(visibleCandidateGroups) { group in
                    Menu(group.title) {
                        ForEach(group.candidates) { candidate in
                            Button(candidate.title) {
                                addLink(candidate.ref)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: Spacing.xxs) {
                Image(systemName: "plus")
                    .font(CiderFont.badgeSemibold)
                Text("Add Link")
                    .font(CiderFont.caption)
            }
            .foregroundColor(visibleCandidateGroups.isEmpty ? CiderColors.quaternary : CiderColors.controlAccent)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .disabled(visibleCandidateGroups.isEmpty)
        .help(visibleCandidateGroups.isEmpty ? "No items available to link" : "Add linked item")
    }

    private func linkedRow(_ row: ItemMetadataRow) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            if let ref = row.ref,
               let onOpenLinkedRef {
                Button {
                    onOpenLinkedRef(ref)
                } label: {
                    linkedMetadataRow(row)
                }
                .buttonStyle(.plain)
            } else {
                linkedMetadataRow(row)
            }

            if let ref = row.ref {
                Button {
                    removeLink(ref)
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                        .frame(width: DetailToolbarDesign.iconButtonSize, height: DetailToolbarDesign.iconButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove link")
            }
        }
    }

    private func linkedMetadataRow(_ row: ItemMetadataRow) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: row.symbol)
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.tertiary)
                .frame(width: Spacing.md)

            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Text(row.title)
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(2)
                if !row.value.isEmpty {
                    Text(row.value)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    private var linkedRows: [ItemMetadataRow] {
        ItemLinkService.shared.summaries(for: draft.linkedEntities).map(ItemMetadataRow.related)
    }

    private var visibleCandidateGroups: [ItemMetadataLinkCandidateGroup] {
        let linkedIDs = Set(draft.linkedEntities.map(\.id))
        return candidateGroups.compactMap { group in
            let candidates = group.candidates.filter { !linkedIDs.contains($0.ref.id) }
            guard !candidates.isEmpty else { return nil }
            return ItemMetadataLinkCandidateGroup(title: group.title, candidates: candidates)
        }
    }

    private var candidateGroups: [ItemMetadataLinkCandidateGroup] {
        [
            candidateGroup(title: "Bookmarks", candidates: bookmarks.bookmarks.map {
                ItemMetadataLinkCandidate(
                    ref: LibraryEntityRef(type: .bookmark, entityID: $0.id),
                    title: $0.title,
                    subtitle: $0.hostDisplay
                )
            }),
            candidateGroup(title: "Notes", candidates: notes.notes.map {
                ItemMetadataLinkCandidate(
                    ref: LibraryEntityRef(type: .note, entityID: $0.id),
                    title: $0.title,
                    subtitle: $0.relativePath.isEmpty ? "Note" : $0.relativePath
                )
            }),
            candidateGroup(title: "Todos", candidates: todos.todoCards.map {
                ItemMetadataLinkCandidate(
                    ref: LibraryEntityRef(type: .todo, entityID: $0.id),
                    title: $0.title,
                    subtitle: "Todo"
                )
            }),
            candidateGroup(title: "Date Cards", candidates: dateCards.dateCards.map {
                ItemMetadataLinkCandidate(
                    ref: LibraryEntityRef(type: .dateCard, entityID: $0.id),
                    title: $0.title,
                    subtitle: "Date card"
                )
            }),
            candidateGroup(title: "Contacts", candidates: contacts.contacts.map {
                ItemMetadataLinkCandidate(
                    ref: LibraryEntityRef(type: .contact, entityID: $0.id),
                    title: $0.displayName,
                    subtitle: $0.relationshipLabel.isEmpty ? "Contact" : $0.relationshipLabel
                )
            }),
            candidateGroup(title: "Files", candidates: files.files.map {
                ItemMetadataLinkCandidate(
                    ref: LibraryEntityRef(type: .vaultFile, entityID: $0.id),
                    title: $0.displayTitle,
                    subtitle: $0.relativePath
                )
            })
        ]
    }

    private func candidateGroup(
        title: String,
        candidates: [ItemMetadataLinkCandidate]
    ) -> ItemMetadataLinkCandidateGroup {
        ItemMetadataLinkCandidateGroup(title: title, candidates: candidates)
    }

    private func addLink(_ ref: LibraryEntityRef) {
        guard !draft.linkedEntities.contains(ref) else { return }
        draft.linkedEntities.append(ref)
        onSave()
    }

    private func removeLink(_ ref: LibraryEntityRef) {
        draft.linkedEntities.removeAll { $0 == ref }
        onSave()
    }

    private func metadataLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
            Spacer(minLength: Spacing.sm)
            Text(value)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
            content()
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceSubtle)
                )
        }
    }
}
