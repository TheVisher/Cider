import SwiftUI

protocol DisplayModeOption: Hashable, CaseIterable {
    var displayName: String { get }
    var icon: String { get }
}

extension BookmarkDisplayMode: DisplayModeOption {}
extension NoteDisplayMode: DisplayModeOption {}
extension LibraryDisplayMode: DisplayModeOption {}

struct ViewOptionsDropdown<Mode: DisplayModeOption>: View {
    @Binding var displayMode: Mode
    @Binding var cardSizeScale: Double
    var hideCardFooters: Binding<Bool>? = nil
    var showCardDetailsOnHover: Binding<Bool>? = nil

    // Home-tab-only extras — nil means the section is hidden
    var sortMode: Binding<LibrarySortMode>? = nil
    var entityFilter: Binding<Set<LibraryEntityType>>? = nil
    var tagFilter: Binding<Set<UUID>>? = nil
    var onlyUnassigned: Binding<Bool>? = nil
    var showComingUp: Binding<Bool>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let sortMode {
                sortSection(sortMode)
                Divider().background(CiderColors.separator)
            }

            if let entityFilter {
                entityFilterSection(entityFilter)
                Divider().background(CiderColors.separator)
            }

            if let tagFilter {
                tagFilterSection(tagFilter)
                Divider().background(CiderColors.separator)
            }

            if let onlyUnassigned {
                unassignedToggle(onlyUnassigned)
                Divider().background(CiderColors.separator)
            }

            if let showComingUp {
                comingUpToggle(showComingUp)
                Divider().background(CiderColors.separator)
            }

            // Card Size
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Card Size")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.secondary)

                HStack(spacing: Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.tertiary)

                    Slider(value: $cardSizeScale, in: 0...3)
                        .controlSize(.small)

                    Image(systemName: "magnifyingglass")
                        .font(CiderFont.subheadingMedium)
                        .foregroundColor(CiderColors.tertiary)
                }
            }

            if let hideCardFooters {
                Divider()
                    .background(CiderColors.separator)

                CardDetailsToggleSection(
                    hideCardFooters: hideCardFooters,
                    showCardDetailsOnHover: showCardDetailsOnHover
                )
            }

            Divider()
                .background(CiderColors.separator)

            // View
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("View")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.secondary)

                HStack(spacing: Spacing.sm) {
                    ForEach(Array(Mode.allCases), id: \.self) { mode in
                        ViewModeIcon(
                            icon: mode.icon,
                            displayName: mode.displayName,
                            isSelected: displayMode == mode,
                            onTap: {
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    displayMode = mode
                                }
                            }
                        )
                    }
                }
            }
        }
        .padding(Spacing.md)
        .frame(width: ViewOptionsDesign.popoverWidth)
    }

    // MARK: - Sort Section

    @ViewBuilder
    private func sortSection(_ binding: Binding<LibrarySortMode>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Sort By")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.secondary)

            VStack(spacing: Spacing.xxs) {
                ForEach(SortGroup.allCases, id: \.self) { group in
                    SortRow(
                        group: group,
                        currentMode: binding.wrappedValue,
                        onTap: {
                            if group.contains(binding.wrappedValue) {
                                // Toggle direction
                                binding.wrappedValue = group.isAscending(binding.wrappedValue)
                                    ? group.descending
                                    : group.ascending
                            } else {
                                binding.wrappedValue = group.defaultMode
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Unassigned Toggle

    @ViewBuilder
    private func unassignedToggle(_ binding: Binding<Bool>) -> some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Unassigned Only")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.secondary)
                Text("Show items not in any folder")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: binding)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }

    // MARK: - Coming Up Toggle

    @ViewBuilder
    private func comingUpToggle(_ binding: Binding<Bool>) -> some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Show Coming Up")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.secondary)
                Text("Approaching and overdue events")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: binding)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }

    // MARK: - Tag Filter Section

    @ViewBuilder
    private func tagFilterSection(_ binding: Binding<Set<UUID>>) -> some View {
        let labels = CardLabelStorage.shared.labels
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Text("Tags")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.secondary)

                if !binding.wrappedValue.isEmpty {
                    Spacer(minLength: 0)
                    Button {
                        binding.wrappedValue.removeAll()
                    } label: {
                        Text("Clear")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.controlAccent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if labels.isEmpty {
                Text("No tags")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    TagFlowLayout(spacing: Spacing.xs) {
                        ForEach(labels) { label in
                            TagFilterChip(
                                label: label,
                                isOn: binding.wrappedValue.contains(label.id),
                                onTap: {
                                    if binding.wrappedValue.contains(label.id) {
                                        binding.wrappedValue.remove(label.id)
                                    } else {
                                        binding.wrappedValue.insert(label.id)
                                    }
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: TagPopoverDesign.filterScrollMaxHeight)
            }
        }
    }

    // MARK: - Entity Filter Section

    @ViewBuilder
    private func entityFilterSection(_ binding: Binding<Set<LibraryEntityType>>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Content")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.secondary)

            let columns = [GridItem(.flexible(), spacing: Spacing.xs), GridItem(.flexible(), spacing: Spacing.xs)]
            LazyVGrid(columns: columns, spacing: Spacing.xs) {
                ForEach(LibraryEntityType.allCases, id: \.self) { type in
                    EntityFilterChip(
                        type: type,
                        isOn: binding.wrappedValue.contains(type),
                        onTap: {
                            if binding.wrappedValue.contains(type) {
                                // Keep at least one type active
                                if binding.wrappedValue.count > 1 {
                                    binding.wrappedValue.remove(type)
                                }
                            } else {
                                binding.wrappedValue.insert(type)
                            }
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Sort Group

private enum SortGroup: CaseIterable {
    case dateAdded, lastModified, title, eventDate

    var label: String {
        switch self {
        case .dateAdded: "Date Added"
        case .lastModified: "Last Modified"
        case .title: "Title"
        case .eventDate: "Event Date"
        }
    }

    var ascending: LibrarySortMode {
        switch self {
        case .dateAdded: .createdAscending
        case .lastModified: .updatedAscending
        case .title: .titleAscending
        case .eventDate: .dateUpcoming
        }
    }

    var descending: LibrarySortMode {
        switch self {
        case .dateAdded: .createdDescending
        case .lastModified: .updatedDescending
        case .title: .titleDescending
        case .eventDate: .dateFarthest
        }
    }

    var defaultMode: LibrarySortMode {
        switch self {
        case .dateAdded: .createdDescending
        case .lastModified: .updatedDescending
        case .title: .titleAscending
        case .eventDate: .dateUpcoming
        }
    }

    func contains(_ mode: LibrarySortMode) -> Bool {
        mode == ascending || mode == descending
    }

    func isAscending(_ mode: LibrarySortMode) -> Bool {
        mode == ascending
    }
}

// MARK: - Sort Row

private struct SortRow: View {
    let group: SortGroup
    let currentMode: LibrarySortMode
    let onTap: () -> Void

    @State private var isHovered = false

    private var isSelected: Bool { group.contains(currentMode) }
    private var showsAscending: Bool { group.isAscending(currentMode) }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.xs) {
                Text(group.label)
                    .font(CiderFont.body)
                    .foregroundColor(isSelected ? CiderColors.controlAccent : CiderColors.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: showsAscending ? "chevron.up" : "chevron.down")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.controlAccent)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    .fill(isSelected ? CiderColors.accentSelected : isHovered ? CiderColors.surfaceHover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverState($isHovered)
    }
}

// MARK: - Entity Filter Chip

private struct EntityFilterChip: View {
    let type: LibraryEntityType
    let isOn: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var label: String {
        switch type {
        case .bookmark: "Bookmarks"
        case .note: "Notes"
        case .dateCard: "Events"
        case .contact: "Contacts"
        case .todo: "Todos"
        case .externalFile: "Sources"
        case .vaultFile: "Images"
        case .session: "Sessions"
        }
    }

    var icon: String {
        switch type {
        case .bookmark: "bookmark"
        case .note: "note.text"
        case .dateCard: "calendar"
        case .contact: "person.crop.circle"
        case .todo: "checklist"
        case .externalFile: "folder.badge.gear"
        case .vaultFile: "photo"
        case .session: "rectangle.stack"
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(CiderFont.captionMedium)
                    .foregroundColor(isOn ? CiderColors.controlAccent : CiderColors.tertiary)
                Text(label)
                    .font(CiderFont.caption)
                    .foregroundColor(isOn ? CiderColors.controlAccent : CiderColors.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    .fill(isOn ? CiderColors.accentSelected : isHovered ? CiderColors.surfaceHover : CiderColors.surfaceInput)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverState($isHovered)
    }
}

// MARK: - Tag Filter Chip

private struct TagFilterChip: View {
    let label: CardLabel
    let isOn: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.xxs) {
                Circle()
                    .fill(Color(hex: label.colorHex) ?? CiderColors.secondary)
                    .frame(width: TagDotDesign.groupRowDotSize, height: TagDotDesign.groupRowDotSize)
                Text(label.name)
                    .font(CiderFont.caption)
                    .foregroundColor(isOn ? CiderColors.controlAccent : CiderColors.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs + 1)
            .background(
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    .fill(isOn ? CiderColors.accentSelected : isHovered ? CiderColors.surfaceHover : CiderColors.surfaceInput)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverState($isHovered)
    }
}

// MARK: - Card Details Toggle

private struct CardDetailsToggleSection: View {
    @Binding var hideCardFooters: Bool
    var showCardDetailsOnHover: Binding<Bool>?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Text("Hide card details")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.secondary)
                Spacer(minLength: 0)
                Toggle("", isOn: $hideCardFooters)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            if hideCardFooters, let showCardDetailsOnHover {
                HStack(spacing: Spacing.sm) {
                    Text("Show on hover")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)
                    Spacer(minLength: 0)
                    Toggle("", isOn: showCardDetailsOnHover)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
                .padding(.leading, Spacing.sm)
            }
        }
        .onChange(of: hideCardFooters) { _, _ in persistCardFooterSettings() }
        .onChange(of: showCardDetailsOnHover?.wrappedValue) { _, _ in persistCardFooterSettings() }
    }

    private func persistCardFooterSettings() {
        var config = CiderConfig.load()
        config.hideCardFooters = hideCardFooters
        config.showCardDetailsOnHover = showCardDetailsOnHover?.wrappedValue ?? true
        config.save()
    }
}

// MARK: - View Mode Icon

private struct ViewModeIcon: View {
    let icon: String
    let displayName: String
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Image(systemName: icon)
            .font(CiderFont.subheadingSemibold)
            .foregroundColor(isSelected ? CiderColors.controlAccent : isHovered ? CiderColors.primary : CiderColors.secondary)
            .frame(width: ViewOptionsDesign.segmentButtonWidth, height: ViewOptionsDesign.segmentButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isSelected ? CiderColors.accentSelected : isHovered ? CiderColors.surfaceHover : CiderColors.surfaceInput)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .hoverState($isHovered)
            .help(displayName)
    }
}
