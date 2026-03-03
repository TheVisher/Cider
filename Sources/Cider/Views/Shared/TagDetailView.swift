import SwiftUI

/// Shows either a tag manager (all tags grid) or a filtered items view for selected tags.
struct TagDetailView: View {
    var tagIDs: Set<UUID>
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
    var onToggleLabelBulk: ((UUID) -> Void)? = nil
    @Binding var scrollToItemID: String?
    var focusedItemID: String? = nil

    @ObservedObject private var labelStorage = CardLabelStorage.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showCreateForm = false
    @State private var showHygiene = false
    @State private var hygieneGroups: [SimilarTagGroup] = []
    @State private var dismissedGroupIDs: Set<UUID> = []

    var body: some View {
        if showManager {
            tagManagerView
        } else if !tagIDs.isEmpty {
            filteredTagView
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
                    runHygiene()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "wand.and.stars")
                            .font(CiderFont.captionSemibold)
                        Text("Tag Hygiene")
                            .font(CiderFont.captionSemibold)
                    }
                    .foregroundColor(CiderColors.secondary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )
                }
                .buttonStyle(.plain)

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

            // Tags grid + hygiene section
            ScrollView(.vertical, showsIndicators: false) {
                if showHygiene {
                    hygieneSection
                }

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
                                allLabels: labelStorage.labels,
                                onSelect: { onSelectTag(label.id) },
                                onRename: { newName in renameTag(label, to: newName) },
                                onSetColor: { hex in setTagColor(label, hex: hex) },
                                onMergeInto: { targetID in mergeTag(label.id, into: targetID) },
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

    // MARK: - Tag Hygiene Section

    private var hygieneSection: some View {
        let visibleGroups = hygieneGroups.filter { !dismissedGroupIDs.contains($0.id) }
        let unusedTags = labelStorage.labels.filter { itemCount(for: $0.id) == 0 }

        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "wand.and.stars")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.controlAccent)

                Text("Tag Hygiene")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)

                Spacer(minLength: 0)

                Button {
                    withAnimation(reduceMotion ? .none : .snappy) {
                        showHygiene = false
                    }
                } label: {
                    Text("Done")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.controlAccent)
                }
                .buttonStyle(.plain)
            }

            if !visibleGroups.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Similar Tags (\(visibleGroups.count) groups)")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.secondary)

                    ForEach(visibleGroups) { group in
                        SimilarGroupRow(
                            group: group,
                            itemCountForLabel: { itemCount(for: $0) },
                            onMerge: { targetID in
                                let sourceIDs = group.labels.map(\.id).filter { $0 != targetID }
                                CardLabelStorage.shared.mergeLabels(sourceIDs: sourceIDs, into: targetID)
                                dismissedGroupIDs.insert(group.id)
                                hygieneGroups.removeAll { $0.id == group.id }
                            },
                            onDismiss: {
                                withAnimation(reduceMotion ? .none : .snappy) {
                                    _ = dismissedGroupIDs.insert(group.id)
                                }
                            }
                        )
                    }
                }
            }

            if !unusedTags.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Unused Tags (\(unusedTags.count))")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.secondary)

                    ForEach(unusedTags) { tag in
                        HStack(spacing: Spacing.sm) {
                            Circle()
                                .fill(Color(hex: tag.colorHex) ?? CiderColors.secondary)
                                .frame(width: 8, height: 8)

                            Text(tag.name)
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.primary)

                            Text("0 items")
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.tertiary)

                            Spacer(minLength: 0)

                            Button {
                                CardLabelStorage.shared.deleteLabel(tag.id)
                            } label: {
                                Text("Delete")
                                    .font(CiderFont.captionSemibold)
                                    .foregroundColor(CiderColors.destructive)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, Spacing.xxs)
                    }
                }
            }

            if visibleGroups.isEmpty && unusedTags.isEmpty {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "checkmark.circle")
                        .font(CiderFont.bodyMedium)
                        .foregroundColor(CiderColors.success)

                    Text("All tags look clean!")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.secondary)
                }
                .padding(.vertical, Spacing.sm)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(CiderColors.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(CiderColors.borderDefault, lineWidth: CiderBorder.innerStrokeWidth)
        )
        .padding(.horizontal, Spacing.md + Spacing.xxs)
        .padding(.top, Spacing.sm)
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

    // MARK: - Filtered Tag View (Single or Multi-Tag)

    private var filteredTagView: some View {
        let resolvedLabels = tagIDs.compactMap { labelStorage.label(for: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let totalCount = tagIDs.reduce(0) { $0 + itemCount(for: $1) }

        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: Spacing.sm) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.secondary)
                }
                .buttonStyle(.plain)

                if resolvedLabels.count == 1, let label = resolvedLabels.first {
                    Circle()
                        .fill(Color(hex: label.colorHex) ?? CiderColors.secondary)
                        .frame(width: 10, height: 10)

                    Text(label.name)
                        .font(CiderFont.subheadingSemibold)
                        .foregroundColor(CiderColors.primary)
                } else {
                    Image(systemName: "tag")
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.secondary)

                    Text("\(resolvedLabels.count) tags")
                        .font(CiderFont.subheadingSemibold)
                        .foregroundColor(CiderColors.primary)
                }

                Text("\(totalCount) items")
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
                activeLabelIDs: tagIDs,
                onToggleLabelBulk: onToggleLabelBulk,
                scrollToItemID: $scrollToItemID,
                focusedItemID: focusedItemID
            )
        }
    }

    // MARK: - Actions

    private func itemCount(for labelID: UUID) -> Int {
        CardLabelStorage.shared.itemCount(for: labelID)
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
        if tagIDs.contains(id), tagIDs.count <= 1 {
            onBack()
        }
        CardLabelStorage.shared.deleteLabel(id)
    }

    private func mergeTag(_ sourceID: UUID, into targetID: UUID) {
        CardLabelStorage.shared.mergeLabels(sourceIDs: [sourceID], into: targetID)
    }

    private func runHygiene() {
        hygieneGroups = TagSimilarity.findSimilarGroups(in: labelStorage.labels)
        dismissedGroupIDs.removeAll()
        withAnimation(reduceMotion ? .none : .snappy) {
            showHygiene = true
        }
    }
}

// MARK: - Similar Group Row

private struct SimilarGroupRow: View {
    let group: SimilarTagGroup
    let itemCountForLabel: (UUID) -> Int
    let onMerge: (UUID) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Text(group.reason)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .italic()

                Spacer(minLength: 0)

                Button(action: onDismiss) {
                    Text("Dismiss")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: Spacing.xs) {
                ForEach(group.labels) { label in
                    HStack(spacing: Spacing.xxs) {
                        Circle()
                            .fill(Color(hex: label.colorHex) ?? CiderColors.secondary)
                            .frame(width: 6, height: 6)
                        Text(label.name)
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.primary)
                    }
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )
                }
            }

            let target = TagSimilarity.suggestedTarget(in: group)
            Button {
                onMerge(target.id)
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.triangle.merge")
                        .font(CiderFont.captionSemibold)
                    Text("Merge All \u{2192} \"\(target.name)\"")
                        .font(CiderFont.captionSemibold)
                }
                .foregroundColor(CiderColors.controlAccent)
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
        )
    }
}

// MARK: - Tag Manager Card

private struct TagManagerCard: View {
    let label: CardLabel
    let itemCount: Int
    let allLabels: [CardLabel]
    var onSelect: () -> Void
    var onRename: (String) -> Void
    var onSetColor: (String) -> Void
    var onMergeInto: (UUID) -> Void
    var onDelete: () -> Void

    @State private var isHovered = false
    @State private var isRenaming = false
    @State private var renamingText = ""
    @State private var showColorPicker = false
    @State private var showMergePopover = false
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
                .action(title: "Merge Into\u{2026}") {
                    showMergePopover = true
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
        .popover(isPresented: $showMergePopover, arrowEdge: .bottom) {
            MergeTargetPopover(
                sourceLabel: label,
                allLabels: allLabels,
                onMerge: { targetID in
                    onMergeInto(targetID)
                    showMergePopover = false
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

// MARK: - Merge Target Popover

private struct MergeTargetPopover: View {
    let sourceLabel: CardLabel
    let allLabels: [CardLabel]
    let onMerge: (UUID) -> Void

    private var otherLabels: [CardLabel] {
        allLabels.filter { $0.id != sourceLabel.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Merge \"\(sourceLabel.name)\" into\u{2026}")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.secondary)

            if otherLabels.isEmpty {
                Text("No other tags to merge into.")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.tertiary)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: Spacing.xxs) {
                        ForEach(otherLabels) { target in
                            Button {
                                onMerge(target.id)
                            } label: {
                                HStack(spacing: Spacing.sm) {
                                    Circle()
                                        .fill(Color(hex: target.colorHex) ?? CiderColors.secondary)
                                        .frame(width: 8, height: 8)

                                    Text(target.name)
                                        .font(CiderFont.body)
                                        .foregroundColor(CiderColors.primary)
                                        .lineLimit(1)

                                    Spacer(minLength: 0)

                                    let count = CardLabelStorage.shared.itemCount(for: target.id)
                                    Text("\(count) item\(count == 1 ? "" : "s")")
                                        .font(CiderFont.caption)
                                        .foregroundColor(CiderColors.tertiary)
                                }
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xs)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .padding(Spacing.md)
        .frame(width: 240)
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
