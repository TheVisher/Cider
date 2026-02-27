import SwiftUI

/// Shows either a tag manager (all tags grid) or a single-tag filtered items view.
struct TagDetailView: View {
    var tagID: UUID?
    var showManager: Bool
    @ObservedObject var bookmarksViewModel: BookmarksViewModel
    @ObservedObject var notesViewModel: NotesViewModel
    @ObservedObject var libraryViewModel: LibraryViewModel
    @Binding var displayMode: LibraryDisplayMode
    @Binding var cardSizeScale: Double
    @Binding var selectedItemIDs: Set<String>
    var onOpenNote: (Note) -> Void = { _ in }
    var onShowBookmarkDetails: (Bookmark) -> Void = { _ in }
    var onEditDateCard: (DateCard) -> Void = { _ in }
    var onEditContact: (ContactCard) -> Void = { _ in }
    var onOpenDateCard: (DateCard) -> Void = { _ in }
    var onOpenContact: (ContactCard) -> Void = { _ in }
    var onSelectTag: (UUID) -> Void = { _ in }
    var onBack: () -> Void = {}

    @ObservedObject private var labelStorage = CardLabelStorage.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showCreateForm = false

    var body: some View {
        if showManager {
            tagManagerView
        } else if let tagID, let label = labelStorage.label(for: tagID) {
            singleTagView(label)
        } else {
            tagManagerView
        }
    }

    // MARK: - Tag Manager (All Tags Grid)

    private var tagManagerView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: Spacing.sm) {
                Image(systemName: "tag")
                    .font(CiderFont.subheadingSemibold)
                    .foregroundColor(CiderColors.secondary)

                Text("Tags")
                    .font(CiderFont.subheadingSemibold)
                    .foregroundColor(CiderColors.primary)

                Spacer(minLength: 0)

                Button {
                    showCreateForm = true
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "plus")
                            .font(CiderFont.captionSemibold)
                        Text("New Tag")
                            .font(CiderFont.captionSemibold)
                    }
                    .foregroundColor(CiderColors.controlAccent)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.accentSubtle)
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showCreateForm, arrowEdge: .bottom) {
                    InlineTagCreationForm { name, colorHex in
                        CardLabelStorage.shared.createLabel(name: name, colorHex: colorHex)
                        showCreateForm = false
                    }
                }
            }
            .padding(.horizontal, Spacing.md + Spacing.xxs)
            .padding(.vertical, Spacing.sm)

            Divider()
                .padding(.horizontal, Spacing.md + Spacing.xxs)

            // Tags grid
            ScrollView(.vertical, showsIndicators: false) {
                if labelStorage.labels.isEmpty {
                    emptyTagsState
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 180), spacing: Spacing.sm)],
                        spacing: Spacing.sm
                    ) {
                        ForEach(labelStorage.labels) { label in
                            TagManagerCard(
                                label: label,
                                itemCount: itemCount(for: label.id),
                                onSelect: { onSelectTag(label.id) },
                                onRename: { newName in renameTag(label, to: newName) },
                                onSetColor: { hex in setTagColor(label, hex: hex) },
                                onDelete: { deleteTag(label.id) }
                            )
                        }
                    }
                    .padding(.horizontal, Spacing.md + Spacing.xxs)
                    .padding(.vertical, Spacing.sm)
                }
            }
        }
    }

    private var emptyTagsState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "tag")
                .font(.system(size: 32))
                .foregroundColor(CiderColors.quaternary)

            Text("No tags yet")
                .font(CiderFont.subheadingMedium)
                .foregroundColor(CiderColors.tertiary)

            Text("Create tags to organize your items across folders.")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.quaternary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xxl)
    }

    // MARK: - Single Tag View (Filtered Items)

    private func singleTagView(_ label: CardLabel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: Spacing.sm) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.secondary)
                }
                .buttonStyle(.plain)

                Circle()
                    .fill(Color(hex: label.colorHex) ?? CiderColors.secondary)
                    .frame(width: 10, height: 10)

                Text(label.name)
                    .font(CiderFont.subheadingSemibold)
                    .foregroundColor(CiderColors.primary)

                Text("\(itemCount(for: label.id)) items")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.tertiary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.md + Spacing.xxs)
            .padding(.vertical, Spacing.sm)

            Divider()
                .padding(.horizontal, Spacing.md + Spacing.xxs)

            // Filtered items using HomeDashboardView with label filter
            HomeDashboardView(
                bookmarksViewModel: bookmarksViewModel,
                notesViewModel: notesViewModel,
                libraryViewModel: libraryViewModel,
                selectedFolderID: nil,
                displayMode: $displayMode,
                cardSizeScale: $cardSizeScale,
                continueSectionCollapsed: .constant(true),
                selectedItemIDs: $selectedItemIDs,
                sortMode: .constant(.createdDescending),
                entityFilter: .constant(Set(LibraryEntityType.allCases)),
                onOpenNote: onOpenNote,
                onShowBookmarkDetails: onShowBookmarkDetails,
                onEditDateCard: onEditDateCard,
                onEditContact: onEditContact,
                onOpenDateCard: onOpenDateCard,
                onOpenContact: onOpenContact,
                activeLabelIDs: Set([label.id])
            )
        }
    }

    // MARK: - Actions

    private func itemCount(for labelID: UUID) -> Int {
        let bookmarkCount = bookmarksViewModel.bookmarks.filter { $0.labelIDs.contains(labelID) }.count
        let noteCount = notesViewModel.notes.filter { $0.labelIDs.contains(labelID) }.count
        let dateCardCount = DateCardStorage.shared.dateCards.filter { $0.labelIDs.contains(labelID) }.count
        let contactCount = ContactStorage.shared.contacts.filter { $0.labelIDs.contains(labelID) }.count
        return bookmarkCount + noteCount + dateCardCount + contactCount
    }

    private func renameTag(_ label: CardLabel, to newName: String) {
        var updated = label
        updated.name = newName
        CardLabelStorage.shared.updateLabel(updated)
    }

    private func setTagColor(_ label: CardLabel, hex: String) {
        var updated = label
        updated.colorHex = hex
        CardLabelStorage.shared.updateLabel(updated)
    }

    private func deleteTag(_ id: UUID) {
        if tagID == id {
            onBack()
        }
        CardLabelStorage.shared.deleteLabel(id)
    }
}

// MARK: - Tag Manager Card

private struct TagManagerCard: View {
    let label: CardLabel
    let itemCount: Int
    var onSelect: () -> Void
    var onRename: (String) -> Void
    var onSetColor: (String) -> Void
    var onDelete: () -> Void

    @State private var isHovered = false
    @State private var isRenaming = false
    @State private var renamingText = ""
    @State private var showColorPicker = false
    @FocusState private var isRenameFocused: Bool

    var body: some View {
        Button(action: { if !isRenaming { onSelect() } }) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Circle()
                        .fill(tintColor)
                        .frame(width: 12, height: 12)

                    if isRenaming {
                        TextField("Tag name", text: $renamingText)
                            .textFieldStyle(.plain)
                            .font(CiderFont.labelSemibold)
                            .foregroundColor(CiderColors.primary)
                            .focused($isRenameFocused)
                            .onSubmit { commitRename() }
                            .onExitCommand { isRenaming = false }
                            .task {
                                try? await Task.sleep(for: .milliseconds(150))
                                isRenameFocused = true
                            }
                    } else {
                        Text(label.name)
                            .font(CiderFont.labelSemibold)
                            .foregroundColor(CiderColors.primary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                Text("\(itemCount) item\(itemCount == 1 ? "" : "s")")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .cardContainer(isHovered: isHovered)
        .hoverState($isHovered, animation: .snappy)
        .modifier(CardContextMenuModifier {
            [
                .action(title: "Open") { onSelect() },
                .action(title: "Rename") {
                    renamingText = label.name
                    isRenaming = true
                },
                .action(title: "Set Color") {
                    showColorPicker = true
                },
                .separator,
                .destructive(title: "Delete Tag") { onDelete() }
            ]
        })
        .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
            TagColorPickerPopover(
                selectedHex: label.colorHex,
                onSelect: { hex in
                    onSetColor(hex)
                    showColorPicker = false
                }
            )
        }
    }

    private var tintColor: Color {
        Color(hex: label.colorHex) ?? CiderColors.secondary
    }

    private func commitRename() {
        let trimmed = renamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onRename(trimmed)
        }
        isRenaming = false
    }
}

// MARK: - Tag Color Picker Popover

private struct TagColorPickerPopover: View {
    let selectedHex: String
    let onSelect: (String) -> Void

    private let presets = CardLabelStorage.tagColorPresets

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Tag Color")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 28), spacing: Spacing.xs)], spacing: Spacing.xs) {
                ForEach(presets, id: \.hex) { preset in
                    let isSelected = preset.hex.lowercased() == selectedHex.lowercased()
                    Button {
                        onSelect(preset.hex)
                    } label: {
                        Circle()
                            .fill(Color(hex: preset.hex) ?? CiderColors.secondary)
                            .frame(width: 24, height: 24)
                            .overlay {
                                if isSelected {
                                    Circle()
                                        .stroke(Color.white, lineWidth: 2)
                                        .frame(width: 18, height: 18)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(preset.name)
                }
            }
        }
        .padding(Spacing.md)
        .frame(width: 200)
    }
}

// MARK: - Inline Tag Creation Form (Popover)

private struct InlineTagCreationForm: View {
    let onCreate: (String, String) -> Void

    @State private var name = ""
    @State private var selectedColorHex: String = CardLabelStorage.randomPresetColor()

    private let presets = CardLabelStorage.tagColorPresets

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("New Tag")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.secondary)

            TextField("Tag name", text: $name)
                .textFieldStyle(.plain)
                .font(CiderFont.body)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )
                .onSubmit(commit)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 28), spacing: Spacing.xs)], spacing: Spacing.xs) {
                ForEach(presets, id: \.hex) { preset in
                    let isSelected = preset.hex.lowercased() == selectedColorHex.lowercased()
                    Button {
                        selectedColorHex = preset.hex
                    } label: {
                        Circle()
                            .fill(Color(hex: preset.hex) ?? CiderColors.secondary)
                            .frame(width: 24, height: 24)
                            .overlay {
                                if isSelected {
                                    Circle()
                                        .stroke(Color.white, lineWidth: 2)
                                        .frame(width: 18, height: 18)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(preset.name)
                }
            }

            Button(action: commit) {
                Text("Create Tag")
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.textOnColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  ? CiderColors.separatorMedium : CiderColors.controlAccent)
                    )
            }
            .buttonStyle(.plain)
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(Spacing.md)
        .frame(width: 220)
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onCreate(trimmed, selectedColorHex)
    }
}

