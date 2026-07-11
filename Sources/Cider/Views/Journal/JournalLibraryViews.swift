import SwiftUI

struct JournalLibraryCardView: View {
    let container: JournalLibraryContainer
    let onOpen: () -> Void
    var isSelected: Bool = false
    var isFocused: Bool = false
    var onSelect: (() -> Void)? = nil
    var onShiftSelect: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        Button {
            let flags = NSEvent.modifierFlags
            if let onSelect, flags.contains(.command) {
                onSelect()
            } else if let onShiftSelect, flags.contains(.shift) {
                onShiftSelect()
            } else {
                onOpen()
            }
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "book.closed")
                        .font(CiderFont.subheadingSemibold)
                        .foregroundColor(CiderColors.controlAccent)

                    Text(container.title)
                        .font(CiderFont.subheadingSemibold)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)
                }

                Text("\(container.entryCount) daily entries")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.secondary)
                    .lineLimit(1)

                Text("Open the Journal Library viewer")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(2)
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 132)
        }
        .buttonStyle(.plain)
        .cardContainer(isHovered: isHovered, isSelected: isSelected, isFocused: isFocused)
        .overlay(alignment: .topLeading) {
            if isSelected {
                SelectionCheckmark()
                    .padding(Spacing.sm)
            }
        }
        .hoverState($isHovered, animation: .snappy)
    }
}

struct JournalDetailContentView: View {
    let projection: JournalLibraryReadModel
    @ObservedObject var notesViewModel: NotesViewModel
    @Binding var selectedEntryID: String?

    private var selectedDay: JournalLibraryDay? {
        if let selectedEntryID {
            return projection.days.first {
                $0.id == selectedEntryID || $0.sourceEntries.contains { $0.id == selectedEntryID }
            } ?? projection.defaultDay
        }
        return projection.defaultDay
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let selectedDay {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(selectedDay.displayTitle)
                        .font(CiderFont.subheadingSemibold)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(2)

                    Text(selectedDay.isAggregate ? "\(selectedDay.sourceEntries.count) preserved source notes" : selectedDay.displayTitle)
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.tertiary)
                }
                .padding(Spacing.md)

                Divider()
                    .background(CiderColors.separator)

                if selectedDay.isAggregate {
                    JournalAggregateDayView(day: selectedDay)
                } else {
                    InlineNoteEditorView(viewModel: notesViewModel)
                }
            } else {
                EmptyStateView(icon: "book.closed", title: "No journal entries")
                    .padding(Spacing.md)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            selectedEntryID = selectedDay?.id
            selectJournalNoteIfNeeded()
        }
        .onChange(of: selectedEntryID) { _, _ in selectJournalNoteIfNeeded() }
        .onChange(of: projection.days) { _, _ in selectJournalNoteIfNeeded() }
    }

    private func selectJournalNoteIfNeeded() {
        guard let day = selectedDay else {
            notesViewModel.setRichDisplayContentOverride(nil)
            notesViewModel.clearSelectedNote()
            return
        }
        guard let entry = day.editableEntry else {
            notesViewModel.setRichDisplayContentOverride(nil)
            notesViewModel.clearSelectedNote()
            return
        }
        let displayContent = entry.preparedDisplayContent(timestampFormat: CiderConfig.load().journalTimestampFormat)
        if notesViewModel.selectedNote?.id != entry.note.id {
            notesViewModel.selectNote(entry.note, richDisplayContentOverride: displayContent)
        } else {
            notesViewModel.setRichDisplayContentOverride(displayContent)
        }
    }
}

private struct JournalAggregateDayView: View {
    let day: JournalLibraryDay

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                ForEach(day.sourceEntries) { entry in
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(entry.note.title)
                            .font(CiderFont.bodySemibold)
                            .foregroundColor(CiderColors.primary)

                        Text(entry.note.relativePath)
                            .font(CiderFont.captionMonospacedMedium)
                            .foregroundColor(CiderColors.tertiary)
                            .textSelection(.enabled)

                        MarkdownContentView(
                            text: entry.preparedDisplayContent(
                                timestampFormat: CiderConfig.load().journalTimestampFormat
                            )
                        )
                    }
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CiderColors.surfaceInput)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
            }
            .padding(Spacing.md)
        }
    }
}

struct JournalNavigationPanelView: View {
    let projection: JournalLibraryReadModel
    @Binding var selectedEntryID: String?

    @State private var expandedNodeIDs: Set<String> = []

    var body: some View {
        ItemMetadataPanel {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Journal Navigation")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)
                    .textCase(.uppercase)

                if projection.navigation.isEmpty {
                    ItemMetadataEmptyText(text: "No daily journal entries yet.")
                } else {
                    ForEach(projection.navigation) { node in
                        nodeView(node, depth: 0)
                    }
                }
            }
        }
    }

    private func nodeView(_ node: JournalNavigationNode, depth: Int) -> AnyView {
        let isExpanded = expandedNodeIDs.contains(node.id)
        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    if let entryID = node.entryID {
                        selectedEntryID = entryID
                    } else if isExpanded {
                        expandedNodeIDs.remove(node.id)
                    } else {
                        expandedNodeIDs.insert(node.id)
                    }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        if node.children.isEmpty {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 4))
                                .foregroundColor(CiderColors.quaternary)
                                .frame(width: 12)
                        } else {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(CiderFont.captionSemibold)
                                .foregroundColor(CiderColors.tertiary)
                                .frame(width: 12)
                        }

                        Text(node.title)
                            .font(node.entryID == nil ? CiderFont.bodyMedium : CiderFont.body)
                            .foregroundColor(node.entryID == selectedEntryID ? CiderColors.controlAccent : CiderColors.primary)
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .padding(.leading, CGFloat(depth) * Spacing.md)
                    .padding(.vertical, Spacing.xxs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    ForEach(node.children) { child in
                        nodeView(child, depth: depth + 1)
                    }
                }
            }
        )
    }
}

struct JournalMetadataPanelView: View {
    let projection: JournalLibraryReadModel

    var body: some View {
        ItemMetadataPanel {
            ItemMetadataSectionView(title: "Details", isExpanded: .constant(true)) {
                ItemMetadataRowsView(rows: [
                    ItemMetadataRow(id: "type", symbol: "book.closed", title: "Type", value: "Journal"),
                    ItemMetadataRow(id: "entries", symbol: "doc.text", title: "Entries", value: "\(projection.entries.count)")
                ])
            }
        }
    }
}

struct JournalNavigationToggleButton: View {
    @Binding var isVisible: Bool
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isVisible ? CiderColors.accentSubtle : CiderColors.separatorSubtle)
                .frame(width: NotesDesign.toolbarButtonSize, height: NotesDesign.toolbarButtonSize)
                .overlay {
                    Image(systemName: isVisible ? "list.bullet.rectangle.fill" : "list.bullet.rectangle")
                        .font(CiderFont.toolbarIcon)
                        .foregroundColor(isVisible ? CiderColors.controlAccent : CiderColors.secondary)
                }
        }
        .buttonStyle(.plain)
        .help(isVisible ? "Hide journal navigation" : "Show journal navigation")
    }
}
