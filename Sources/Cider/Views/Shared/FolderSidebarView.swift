import SwiftUI
import UniformTypeIdentifiers

struct FolderSidebarView: View {
    let folders: [Folder]
    let bookmarks: [Bookmark]
    let notes: [Note]
    @Binding var selectedFolderID: UUID?
    @Binding var expandedFolderIDs: Set<UUID>
    var onCreateFolder: ((String, UUID?) -> Folder?)?
    var onAssignBookmarkToFolder: ((Bookmark, UUID?) -> Bool)?
    var onAssignNoteToFolder: ((Note, UUID?) -> Bool)?
    var onRenameFolder: ((UUID, String) -> Void)?
    var onSetFolderIcon: ((UUID, String?) -> Void)?
    var onDeleteFolder: ((UUID) -> Void)?
    var onSelectSubFolder: ((UUID) -> Void)?
    var searchText: Binding<String> = .constant("")
    var onTriggerSearch: (() -> Void)?
    var showBackground: Bool = true
    var enableLinkedSources: Bool = false

    // Tags
    var labels: [CardLabel] = []
    var selectedTagIDs: Binding<Set<UUID>> = .constant([])
    var tagsCollapsed: Binding<Bool> = .constant(false)
    var onToggleTag: ((UUID) -> Void)? = nil
    var onClearTags: (() -> Void)? = nil
    var onOpenTagManager: (() -> Void)? = nil

    // Sources (optional — all default to no-ops so existing call sites compile unchanged)
    var sources: [ExternalSource] = []
    var selectedSourceID: Binding<UUID?> = .constant(nil)
    var onAddSource: (() -> Void)? = nil
    var onSelectSource: ((UUID) -> Void)? = nil
    var onToggleSourceTab: ((UUID) -> Void)? = nil
    var onToggleSourceLibrary: ((UUID) -> Void)? = nil
    var onRemoveSource: ((UUID) -> Void)? = nil

    @ObservedObject private var registry = ExternalSourceRegistry.shared

    @Environment(\.textScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isFolderCreationFieldVisible = false
    @State private var draftFolderName = ""
    @State private var subFolderParentID: UUID?
    @State private var draftSubFolderName = ""
    @State private var renamingFolderID: UUID?
    @State private var renamingFolderName = ""
    @State private var tagsExpanded = false
    @State private var foldersCollapsed = false
    @State private var sourcesCollapsed = false
    @State private var foldersHeaderHovered = false
    @State private var sourcesHeaderHovered = false
    @State private var tagsHeaderHovered = false

    private var topLevelFolders: [Folder] {
        childFolders(of: nil)
    }

    private static let multiDragTypeIdentifier = "com.cider.multi-drag"
    private static let bookmarkDragTypeIdentifier = "com.cider.bookmark-id"
    private static let noteDragTypeIdentifier = "com.cider.note-id"

    private var folderDropTypeIdentifiers: [String] {
        [
            Self.multiDragTypeIdentifier,
            Self.bookmarkDragTypeIdentifier,
            Self.noteDragTypeIdentifier,
            UTType.text.identifier,
            UTType.plainText.identifier,
            UTType.utf8PlainText.identifier,
            // NOTE: Do NOT add image types here. .onDrop proxies providers and
            // exposes only one matching type — if image types are accepted,
            // public.png wins over public.utf8-plain-text, stripping the text
            // payload that carries the internal bookmark/note ID.
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Live search field
            HStack(spacing: Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.tertiary)

                TextField("Search", text: searchText)
                    .textFieldStyle(.plain)
                    .font(CiderFont.label)
                    .foregroundColor(CiderColors.primary)

                if !searchText.wrappedValue.isEmpty {
                    Button {
                        searchText.wrappedValue = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(CiderFont.captionMedium)
                            .foregroundColor(CiderColors.tertiary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("\u{2318}K")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.quaternary)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.separatorLight)
            )

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    // MARK: Folders
                    HStack(spacing: Spacing.xs) {
                        ZStack {
                            Image(systemName: "folder")
                                .font(CiderFont.bodySemibold)
                                .foregroundColor(CiderColors.secondary)
                                .opacity(foldersHeaderHovered ? 0 : 1)

                            Image(systemName: "chevron.down")
                                .font(CiderFont.captionBold)
                                .foregroundColor(CiderColors.secondary)
                                .rotationEffect(.degrees(foldersCollapsed ? -90 : 0))
                                .opacity(foldersHeaderHovered ? 1 : 0)
                        }
                        .animation(reduceMotion ? .none : .smooth, value: foldersHeaderHovered)

                        Text("Folders")
                            .font(CiderFont.bodySemibold)
                            .foregroundColor(CiderColors.secondary)

                        Spacer(minLength: 0)
                    }
                    .padding(.top, Spacing.xs)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(reduceMotion ? .none : .snappy) {
                            foldersCollapsed.toggle()
                        }
                    }
                    .hoverState($foldersHeaderHovered)

                    if !foldersCollapsed {
                        if topLevelFolders.isEmpty {
                            Text("No folders yet. Create one to organize your items.")
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.tertiary)
                                .padding(.horizontal, Spacing.xs)
                                .padding(.bottom, Spacing.xs)
                        } else {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                ForEach(topLevelFolders) { folder in
                                    rootFolderGroup(folder)
                                }
                            }
                            .padding(.horizontal, CiderBorder.innerStrokeInset)
                            .padding(.bottom, Spacing.xs)
                        }

                        if isFolderCreationFieldVisible {
                            HStack(spacing: Spacing.sm) {
                                TextField("New folder name", text: $draftFolderName)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit {
                                        commitFolderCreation()
                                    }

                                Button("Create") {
                                    commitFolderCreation()
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(CiderColors.controlAccent)
                            }
                        }
                    }

                    // MARK: Sources
                    if enableLinkedSources && (!sources.isEmpty || onAddSource != nil) {
                        sourcesSection
                    }

                    // MARK: Tags
                    tagsSection
                }
            }
        }
        .padding(.horizontal, Spacing.sm)
        .frame(width: BookmarksDesign.folderSidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .onReceive(NotificationCenter.default.publisher(for: .showFolderCreationField).receive(on: DispatchQueue.main)) { _ in
            toggleFolderCreationField()
        }
        .background {
            if showBackground {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(CiderColors.surfaceElevated)
            }
        }
        .overlay {
            if showBackground {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(CiderColors.borderDefault, lineWidth: CiderBorder.innerStrokeWidth)
            }
        }
    }

    // MARK: - Tags Section

    private var tagsShowMoreThreshold: Int { 8 }

    @ViewBuilder
    private var tagsSection: some View {
        let isCollapsed = tagsCollapsed.wrappedValue
        let hasActiveFilters = !selectedTagIDs.wrappedValue.isEmpty
        let searchQuery = searchText.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseLabels = searchQuery.isEmpty ? labels : labels.filter { $0.name.localizedStandardContains(searchQuery) }
        let visibleLabels = tagsExpanded ? baseLabels : Array(baseLabels.prefix(tagsShowMoreThreshold))
        let hasMore = baseLabels.count > tagsShowMoreThreshold

        VStack(alignment: .leading, spacing: Spacing.xs) {
            Divider()
                .background(CiderColors.separator)
                .padding(.vertical, Spacing.xxs)

            HStack(spacing: Spacing.xs) {
                ZStack {
                    Image(systemName: "tag")
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.secondary)
                        .opacity(tagsHeaderHovered ? 0 : 1)

                    Image(systemName: "chevron.down")
                        .font(CiderFont.captionBold)
                        .foregroundColor(CiderColors.secondary)
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                        .opacity(tagsHeaderHovered ? 1 : 0)
                }
                .animation(reduceMotion ? .none : .smooth, value: tagsHeaderHovered)

                Button {
                    onOpenTagManager?()
                } label: {
                    Text("Tags")
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.secondary)
                }
                .buttonStyle(.plain)

                if hasActiveFilters {
                    Button {
                        onClearTags?()
                    } label: {
                        Text("Clear")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.controlAccent)
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(reduceMotion ? .none : .snappy) {
                    tagsCollapsed.wrappedValue.toggle()
                }
            }
            .hoverState($tagsHeaderHovered)

            if !isCollapsed {
                if labels.isEmpty {
                    Text("No tags yet")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)
                        .padding(.horizontal, Spacing.xs)
                } else {
                    TagFlowLayout(spacing: Spacing.xs) {
                        ForEach(visibleLabels) { label in
                            SidebarTagPill(
                                label: label,
                                isSelected: selectedTagIDs.wrappedValue.contains(label.id),
                                onTap: {
                                    onToggleTag?(label.id)
                                }
                            )
                        }

                        if hasMore {
                            Button {
                                withAnimation(reduceMotion ? .none : .snappy) {
                                    tagsExpanded.toggle()
                                }
                            } label: {
                                HStack(spacing: Spacing.xxs) {
                                    Image(systemName: tagsExpanded ? "chevron.up" : "ellipsis")
                                        .font(CiderFont.micro)
                                    Text(tagsExpanded ? "Less" : "\(labels.count - tagsShowMoreThreshold) more")
                                        .font(CiderFont.caption)
                                }
                                .foregroundColor(CiderColors.controlAccent)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xxs + 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, CiderBorder.innerStrokeInset)
                }
            }
        }
    }

    // MARK: - Sources Section

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Divider()
                .background(CiderColors.separator)
                .padding(.vertical, Spacing.xs)

            HStack(spacing: Spacing.xs) {
                ZStack {
                    Image(systemName: "folder.badge.gear")
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.secondary)
                        .opacity(sourcesHeaderHovered ? 0 : 1)

                    Image(systemName: "chevron.down")
                        .font(CiderFont.captionBold)
                        .foregroundColor(CiderColors.secondary)
                        .rotationEffect(.degrees(sourcesCollapsed ? -90 : 0))
                        .opacity(sourcesHeaderHovered ? 1 : 0)
                }
                .animation(reduceMotion ? .none : .smooth, value: sourcesHeaderHovered)

                Text("Sources")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.secondary)

                Spacer(minLength: 0)

                if let onAddSource {
                    Button(action: onAddSource) {
                        Image(systemName: "plus")
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(CiderColors.secondary)
                            .frame(width: FolderSidebarItemDesign.folderIconSize, height: FolderSidebarItemDesign.folderIconSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Add linked source folder")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(reduceMotion ? .none : .snappy) {
                    sourcesCollapsed.toggle()
                }
            }
            .hoverState($sourcesHeaderHovered)

            if !sourcesCollapsed {
                ForEach(sources) { source in
                    sourceSidebarRow(source)
                }

                if sources.isEmpty {
                    Text("No sources linked.")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)
                        .padding(.horizontal, Spacing.xs)
                }
            }
        }
    }

    private func sourceSidebarRow(_ source: ExternalSource) -> some View {
        let isSelected = selectedSourceID.wrappedValue == source.id
        let fileCount = registry.files(for: source.id).count

        return HStack(spacing: Spacing.xs) {
            Image(systemName: "folder.badge.gear")
                .font(CiderFont.bodySemibold)
                .foregroundColor(isSelected ? CiderColors.controlAccent : CiderColors.secondary)

            Text(source.displayName)
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)

            Spacer(minLength: Spacing.xs)

            if fileCount > 0 {
                Text("\(fileCount)")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.tertiary)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .frame(minHeight: BookmarksDesign.folderSidebarRowMinHeight)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isSelected ? CiderColors.selectedFill : CiderColors.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(isSelected ? CiderColors.selectedBorder : CiderColors.borderDefault,
                        lineWidth: CiderBorder.innerStrokeWidth)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectSource?(source.id)
        }
        .modifier(CardContextMenuModifier { [onToggleSourceLibrary, onToggleSourceTab, onRemoveSource] in
            var items: [CardMenuItem] = []
            if let onToggleSourceLibrary {
                items.append(.action(title: source.showInLibrary ? "Remove from Library" : "Show in Library") {
                    onToggleSourceLibrary(source.id)
                })
            }
            if let onToggleSourceTab {
                items.append(.action(title: source.isTabPinned ? "Unpin Tab" : "Pin as Tab") {
                    onToggleSourceTab(source.id)
                })
            }
            items.append(.separator)
            items.append(.action(title: "Open in Finder") {
                NSWorkspace.shared.open(URL(fileURLWithPath: source.path))
            })
            if let onRemoveSource {
                items.append(.destructive(title: "Remove Source") {
                    onRemoveSource(source.id)
                })
            }
            return items
        })
    }

    private func commitFolderRename() {
        guard let id = renamingFolderID else { return }
        let trimmed = renamingFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onRenameFolder?(id, trimmed)
        }
        renamingFolderID = nil
    }

    // MARK: - Root Folder Group

    private func rootFolderGroup(_ folder: Folder) -> some View {
        let children = childFolders(of: folder.id)
        let hasChildren = !children.isEmpty || subFolderParentID == folder.id
        let isExpanded = hasChildren && expandedFolderIDs.contains(folder.id)

        return VStack(alignment: .leading, spacing: 0) {
            RootFolderHeaderRow(
                title: folder.name,
                folderIcon: folder.icon,
                folderIconIsEmoji: folder.iconIsEmoji,
                itemCount: itemsInFolder(folder.id),
                hasChildren: hasChildren,
                isExpanded: isExpanded,
                isSelected: selectedFolderID == folder.id,
                isRenaming: renamingFolderID == folder.id,
                renamingName: $renamingFolderName,
                dropTypeIdentifiers: folderDropTypeIdentifiers,
                onTap: {
                    selectFolder(folder.id)
                    withAnimation(reduceMotion ? .none : .snappy) {
                        if isExpanded {
                            expandedFolderIDs.remove(folder.id)
                        } else {
                            expandedFolderIDs.insert(folder.id)
                        }
                    }
                },
                onToggleCollapse: {
                    withAnimation(reduceMotion ? .none : .snappy) {
                        if isExpanded {
                            expandedFolderIDs.remove(folder.id)
                        } else {
                            expandedFolderIDs.insert(folder.id)
                        }
                    }
                },
                onDropTargetChanged: { targeted in
                    guard targeted else { return }
                    expandedFolderIDs.insert(folder.id)
                },
                onDropProviders: { providers in
                    handleFolderDrop(providers: providers, targetFolderID: folder.id)
                },
                onRename: {
                    renamingFolderName = folder.name
                    renamingFolderID = folder.id
                },
                onCommitRename: { commitFolderRename() },
                onCancelRename: { renamingFolderID = nil },
                onSetIcon: { icon in onSetFolderIcon?(folder.id, icon) },
                onDelete: { onDeleteFolder?(folder.id) },
                onAddSubFolder: {
                    subFolderParentID = folder.id
                    draftSubFolderName = ""
                    expandedFolderIDs.insert(folder.id)
                }
            )

            if isExpanded || subFolderParentID == folder.id {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(children) { child in
                        subFolderBranch(child, depth: 1)
                    }

                    if subFolderParentID == folder.id {
                        subFolderCreationField(depth: 1)
                    }
                }
                .padding(.top, Spacing.xs)
                .padding(.leading, Spacing.md)
            }
        }
    }

    // MARK: - Sub-Folder Branch

    private func subFolderBranch(_ folder: Folder, depth: Int) -> AnyView {
        let children = childFolders(of: folder.id)
        let isExpanded = expandedFolderIDs.contains(folder.id)
        let hasChildrenOrSubCreation = !children.isEmpty || subFolderParentID == folder.id

        return AnyView(VStack(alignment: .leading, spacing: Spacing.xs) {
            SubFolderRow(
                title: folder.name,
                folderIcon: folder.icon,
                folderIconIsEmoji: folder.iconIsEmoji,
                itemCount: itemsInFolder(folder.id),
                hasChildren: hasChildrenOrSubCreation,
                isExpanded: isExpanded || subFolderParentID == folder.id,
                isSelected: selectedFolderID == folder.id,
                isRenaming: renamingFolderID == folder.id,
                renamingName: $renamingFolderName,
                dropTypeIdentifiers: folderDropTypeIdentifiers,
                onTap: {
                    selectFolder(folder.id)
                    if hasChildrenOrSubCreation {
                        withAnimation(reduceMotion ? .none : .snappy) {
                            if isExpanded {
                                expandedFolderIDs.remove(folder.id)
                            } else {
                                expandedFolderIDs.insert(folder.id)
                            }
                        }
                    }
                },
                onToggleExpand: hasChildrenOrSubCreation ? {
                    withAnimation(reduceMotion ? .none : .snappy) {
                        if isExpanded {
                            expandedFolderIDs.remove(folder.id)
                        } else {
                            expandedFolderIDs.insert(folder.id)
                        }
                    }
                } : nil,
                onDropTargetChanged: { targeted in
                    guard targeted, !children.isEmpty else { return }
                    expandedFolderIDs.insert(folder.id)
                },
                onDropProviders: { providers in
                    handleFolderDrop(providers: providers, targetFolderID: folder.id)
                },
                onRename: {
                    renamingFolderName = folder.name
                    renamingFolderID = folder.id
                },
                onCommitRename: { commitFolderRename() },
                onCancelRename: { renamingFolderID = nil },
                onSetIcon: { icon in onSetFolderIcon?(folder.id, icon) },
                onDelete: { onDeleteFolder?(folder.id) },
                onAddSubFolder: {
                    subFolderParentID = folder.id
                    draftSubFolderName = ""
                    expandedFolderIDs.insert(folder.id)
                }
            )

            if isExpanded || subFolderParentID == folder.id {
                ForEach(children) { child in
                    subFolderBranch(child, depth: depth + 1)
                        .padding(.leading, Spacing.md)
                }

                if subFolderParentID == folder.id {
                    subFolderCreationField(depth: depth + 1)
                        .padding(.leading, Spacing.md)
                }
            }
        })
    }

    private func subFolderCreationField(depth: Int) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "folder.badge.plus")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.controlAccent)

            TextField("Sub folder name", text: $draftSubFolderName)
                .textFieldStyle(.plain)
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.primary)
                .onSubmit { commitSubFolderCreation() }
                .onExitCommand { cancelSubFolderCreation() }

            Button(action: commitSubFolderCreation) {
                Image(systemName: "checkmark")
                    .font(CiderFont.microBold)
                    .foregroundColor(CiderColors.controlAccent)
            }
            .buttonStyle(.plain)

            Button(action: cancelSubFolderCreation) {
                Image(systemName: "xmark")
                    .font(CiderFont.microBold)
                    .foregroundColor(CiderColors.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.sm)
        .frame(minHeight: BookmarksDesign.folderSidebarRowMinHeight)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.accentSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(CiderColors.accentBorder, lineWidth: CiderBorder.innerStrokeWidth)
        )
    }

    // MARK: - Actions

    private func selectFolder(_ folderID: UUID?) {
        guard selectedFolderID != folderID else { return }
        selectedFolderID = folderID
        if let folderID {
            expandPath(to: folderID)
        }
    }

    private func toggleFolderCreationField() {
        withAnimation(reduceMotion ? .none : .snappy) {
            isFolderCreationFieldVisible.toggle()
            if !isFolderCreationFieldVisible {
                draftFolderName = ""
            }
        }
    }

    private func commitFolderCreation() {
        guard let onCreateFolder else { return }
        let trimmed = draftFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let created = onCreateFolder(trimmed, nil)
        guard let created else { return }

        draftFolderName = ""
        isFolderCreationFieldVisible = false
        selectFolder(created.id)
    }

    private func commitSubFolderCreation() {
        guard let onCreateFolder, let parentID = subFolderParentID else { return }
        let trimmed = draftSubFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let created = onCreateFolder(trimmed, parentID)
        draftSubFolderName = ""
        subFolderParentID = nil

        if let created {
            expandedFolderIDs.insert(parentID)
            selectFolder(created.id)
        }
    }

    private func cancelSubFolderCreation() {
        draftSubFolderName = ""
        subFolderParentID = nil
    }

    // MARK: - Folder Helpers

    func childFolders(of parentID: UUID?) -> [Folder] {
        folders
            .filter { $0.parentID == parentID }
            .sorted { lhs, rhs in
                let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if nameComparison != .orderedSame {
                    return nameComparison == .orderedAscending
                }
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    func itemsInFolder(_ folderID: UUID) -> Int {
        let bookmarkCount = bookmarks.filter { $0.folderID == folderID }.count
        let noteCount = notes.filter { $0.folderID == folderID }.count
        return bookmarkCount + noteCount
    }

    private func expandPath(to folderID: UUID) {
        let folderByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        var cursorID: UUID? = folderID
        var visited = Set<UUID>()

        while let currentID = cursorID,
              !visited.contains(currentID),
              let folder = folderByID[currentID] {
            visited.insert(currentID)
            cursorID = folder.parentID
        }

        for id in visited where id != folderID {
            expandedFolderIDs.insert(id)
        }
    }

    // MARK: - Drop Handling

    private func handleFolderDrop(providers: [NSItemProvider], targetFolderID: UUID?) -> Bool {
        // Check for multi-drag payload
        for provider in providers where provider.registeredTypeIdentifiers.contains(Self.multiDragTypeIdentifier) {
            provider.loadDataRepresentation(forTypeIdentifier: Self.multiDragTypeIdentifier) { data, _ in
                guard let data, let items = MultiDragPayload.decode(from: data) else { return }
                let localBookmarks = bookmarks
                let localNotes = notes
                let localFolders = folders
                Task { @MainActor in
                    performBulkMove(items: items, targetFolderID: targetFolderID, bookmarks: localBookmarks, notes: localNotes, folders: localFolders)
                }
            }
            return true
        }

        // Check for bookmark drag payload — use registeredTypeIdentifiers.contains (not
        // hasItemConformingToTypeIdentifier) because custom UTIs aren't in the system conformance
        // tree. This matches the pattern used for multi-drag above.
        for provider in providers where provider.registeredTypeIdentifiers.contains(Self.bookmarkDragTypeIdentifier) {
            provider.loadDataRepresentation(forTypeIdentifier: Self.bookmarkDragTypeIdentifier) { data, _ in
                guard let data,
                      let rawID = String(data: data, encoding: .utf8),
                      let bookmarkID = UUID(uuidString: rawID) else {
                    return
                }
                DispatchQueue.main.async {
                    if let bookmark = bookmarks.first(where: { $0.id == bookmarkID }) {
                        _ = onAssignBookmarkToFolder?(bookmark, targetFolderID)
                    }
                }
            }
            return true
        }

        // Check for note drag payload — same pattern as bookmark above.
        for provider in providers where provider.registeredTypeIdentifiers.contains(Self.noteDragTypeIdentifier) {
            provider.loadDataRepresentation(forTypeIdentifier: Self.noteDragTypeIdentifier) { data, _ in
                guard let data,
                      let rawID = String(data: data, encoding: .utf8),
                      let noteID = UUID(uuidString: rawID) else {
                    return
                }
                DispatchQueue.main.async {
                    if let note = notes.first(where: { $0.id == noteID }) {
                        _ = onAssignNoteToFolder?(note, targetFolderID)
                    }
                }
            }
            return true
        }

        // Text fallback for multi-drag or single bookmark/note IDs
        // Use hasItemConformingToTypeIdentifier instead of canLoadObject(ofClass: NSString.self)
        // because canLoadObject only returns true for object-mode registrations (NSItemProvider(object:)),
        // not for registerDataRepresentation-based registrations used by bookmark drag providers.
        for provider in providers where provider.hasItemConformingToTypeIdentifier("public.utf8-plain-text") {
            provider.loadDataRepresentation(forTypeIdentifier: "public.utf8-plain-text") { data, _ in
                guard let data, let raw = String(data: data, encoding: .utf8) else { return }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

                if let items = MultiDragPayload.decodeFromText(trimmed) {
                    let localBookmarks = bookmarks
                    let localNotes = notes
                    let localFolders = folders
                    Task { @MainActor in
                        performBulkMove(items: items, targetFolderID: targetFolderID, bookmarks: localBookmarks, notes: localNotes, folders: localFolders)
                    }
                    return
                }

                if let bookmarkID = BookmarkDragPayload.bookmarkID(from: trimmed) {
                    DispatchQueue.main.async {
                        if let bookmark = bookmarks.first(where: { $0.id == bookmarkID }) {
                            _ = onAssignBookmarkToFolder?(bookmark, targetFolderID)
                        }
                    }
                } else if let noteID = NoteDragPayload.noteID(from: trimmed) {
                    DispatchQueue.main.async {
                        if let note = notes.first(where: { $0.id == noteID }) {
                            _ = onAssignNoteToFolder?(note, targetFolderID)
                        }
                    }
                }
            }
            return true
        }

        return false
    }

    /// Moves all multi-drag items to targetFolderID and records a single bulkMoved undo action.
    @MainActor
    private func performBulkMove(
        items: [MultiDragPayload.Item],
        targetFolderID: UUID?,
        bookmarks: [Bookmark],
        notes: [Note],
        folders: [Folder]
    ) {
        var bulkMoveItems: [BulkMoveItem] = []
        let folderName = folders.first(where: { $0.id == targetFolderID })?.name ?? "Unfiled"

        for item in items {
            switch item.type {
            case "bookmark":
                if let bookmark = bookmarks.first(where: { $0.id == item.id }) {
                    bulkMoveItems.append(BulkMoveItem(
                        itemID: bookmark.id,
                        itemType: .bookmark,
                        title: bookmark.title,
                        fromFolderID: bookmark.folderID
                    ))
                    BookmarksStorage.shared.assignBookmark(bookmark.id, toFolder: targetFolderID)
                }
            case "note":
                if let note = notes.first(where: { $0.id == item.id }) {
                    bulkMoveItems.append(BulkMoveItem(
                        itemID: note.id,
                        itemType: .note,
                        title: note.title,
                        fromFolderID: note.folderID
                    ))
                    NotesStorage.shared.assignNote(note.id, toFolder: targetFolderID)
                }
            case "datecard":
                if let dateCard = DateCardStorage.shared.dateCard(for: item.id) {
                    bulkMoveItems.append(BulkMoveItem(
                        itemID: dateCard.id,
                        itemType: .dateCard,
                        title: dateCard.title,
                        fromFolderID: dateCard.folderID
                    ))
                    DateCardStorage.shared.assignDateCard(item.id, toFolder: targetFolderID)
                }
            case "contact":
                if let contact = ContactStorage.shared.contact(for: item.id) {
                    bulkMoveItems.append(BulkMoveItem(
                        itemID: contact.id,
                        itemType: .contact,
                        title: contact.displayName,
                        fromFolderID: contact.folderID
                    ))
                    ContactStorage.shared.assignContact(item.id, toFolder: targetFolderID)
                }
            default:
                break
            }
        }

        if !bulkMoveItems.isEmpty {
            CiderUndoManager.shared.record(.bulkMoved(bulkMoveItems, toFolderID: targetFolderID, folderName: folderName))
        }
    }
}

// MARK: - Root Folder Header Row

struct RootFolderHeaderRow: View {
    let title: String
    let folderIcon: String?
    let folderIconIsEmoji: Bool
    let itemCount: Int
    let hasChildren: Bool
    let isExpanded: Bool
    let isSelected: Bool
    let isRenaming: Bool
    @Binding var renamingName: String
    let dropTypeIdentifiers: [String]
    let onTap: () -> Void
    let onToggleCollapse: () -> Void
    let onDropTargetChanged: (Bool) -> Void
    let onDropProviders: ([NSItemProvider]) -> Bool
    var onRename: (() -> Void)?
    var onCommitRename: (() -> Void)?
    var onCancelRename: (() -> Void)?
    var onSetIcon: ((String?) -> Void)?
    var onDelete: (() -> Void)?
    var onAddSubFolder: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDropTargeted = false
    @State private var isHovered = false
    @State private var isIconHovered = false
    @State private var showChevronIcon = false
    @State private var chevronRevertTask: DispatchWorkItem?
    @FocusState private var isRenameFocused: Bool

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // Icon area: click here to toggle collapse
            ZStack {
                folderIconView
                    .opacity(shouldShowChevron ? 0 : 1)

                Image(systemName: "chevron.down")
                    .font(CiderFont.captionBold)
                    .foregroundColor(iconColor)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .opacity(shouldShowChevron ? 1 : 0)
            }
            .frame(width: FolderSidebarItemDesign.folderIconSize, height: BookmarksDesign.folderSidebarRowMinHeight + 2)
            .contentShape(Rectangle())
            .onTapGesture {
                onToggleCollapse()
            }
            .hoverState($isIconHovered)
            .animation(reduceMotion ? .none : .smooth, value: shouldShowChevron)

            if isRenaming {
                TextField("Folder name", text: $renamingName)
                    .textFieldStyle(.plain)
                    .font(CiderFont.labelSemibold)
                    .foregroundColor(CiderColors.primary)
                    .focused($isRenameFocused)
                    .onSubmit { onCommitRename?() }
                    .onExitCommand { onCancelRename?() }
                    .task {
                        try? await Task.sleep(for: .milliseconds(150))
                        isRenameFocused = true
                    }
            } else {
                Text(title)
                    .font(CiderFont.labelSemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.xs)

            if !isRenaming, itemCount > 0 {
                Text("\(itemCount)")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.tertiary)
            }
        }
        .padding(.leading, Spacing.xs)
        .padding(.trailing, Spacing.sm)
        .frame(minHeight: BookmarksDesign.folderSidebarRowMinHeight + 2)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(borderColor, lineWidth: CiderBorder.innerStrokeWidth)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isRenaming {
                onTap()
                triggerChevronFlash()
            }
        }
        .animation(reduceMotion ? .none : .snappy, value: isDropTargeted)
        .animation(reduceMotion ? .none : .snappy, value: isHovered)
        .animation(reduceMotion ? .none : .snappy, value: isExpanded)
        .hoverState($isHovered)
        .onDrop(
            of: dropTypeIdentifiers,
            isTargeted: $isDropTargeted,
            perform: onDropProviders
        )
        .onChange(of: isDropTargeted) { _, targeted in
            onDropTargetChanged(targeted)
        }
        .modifier(CardContextMenuModifier { [onRename, onSetIcon, onAddSubFolder, onDelete, folderIcon] in
            var items: [CardMenuItem] = []
            if let onRename {
                items.append(.action(title: "Rename", callback: onRename))
            }
            if let onSetIcon {
                items.append(.submenu(title: "Icon", children: FolderIconMenuItems.build(
                    currentIcon: folderIcon, onSetIcon: onSetIcon
                )))
            }
            if let onAddSubFolder {
                items.append(.action(title: "Add Sub Folder", callback: onAddSubFolder))
            }
            if let onDelete {
                items.append(.separator)
                items.append(.destructive(title: "Delete Folder", callback: onDelete))
            }
            return items
        })
    }

    private var shouldShowChevron: Bool {
        hasChildren && (isHovered || showChevronIcon)
    }

    private func triggerChevronFlash() {
        chevronRevertTask?.cancel()
        showChevronIcon = true

        let task = DispatchWorkItem { [reduceMotion] in
            withAnimation(reduceMotion ? .none : .smooth) {
                showChevronIcon = false
            }
        }
        chevronRevertTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: task)
    }

    @ViewBuilder
    private var folderIconView: some View {
        if let icon = folderIcon, folderIconIsEmoji {
            Text(icon)
                .font(CiderFont.heading)
        } else if let icon = folderIcon {
            Image(systemName: icon)
                .font(CiderFont.bodySemibold)
                .foregroundColor(iconColor)
        } else {
            Image(systemName: "folder.fill")
                .font(CiderFont.bodySemibold)
                .foregroundColor(iconColor)
        }
    }

    private var iconColor: Color {
        if isDropTargeted || isSelected {
            return CiderColors.controlAccent
        }
        return CiderColors.secondary
    }

    private var backgroundColor: Color {
        if isDropTargeted {
            return CiderColors.dropTargetFill
        }
        if isSelected {
            return CiderColors.selectedFill
        }
        if isHovered {
            return CiderColors.surfaceHover
        }
        return CiderColors.surfaceElevated
    }

    private var borderColor: Color {
        if isDropTargeted {
            return CiderColors.dropTargetBorder
        }
        if isSelected {
            return CiderColors.selectedBorder
        }
        return CiderColors.borderDefault
    }
}

// MARK: - Sub-Folder Row

struct SubFolderRow: View {
    let title: String
    let folderIcon: String?
    let folderIconIsEmoji: Bool
    let itemCount: Int
    let hasChildren: Bool
    let isExpanded: Bool
    let isSelected: Bool
    let isRenaming: Bool
    @Binding var renamingName: String
    let dropTypeIdentifiers: [String]
    let onTap: () -> Void
    let onToggleExpand: (() -> Void)?
    let onDropTargetChanged: (Bool) -> Void
    let onDropProviders: ([NSItemProvider]) -> Bool
    var onRename: (() -> Void)?
    var onCommitRename: (() -> Void)?
    var onCancelRename: (() -> Void)?
    var onSetIcon: ((String?) -> Void)?
    var onDelete: (() -> Void)?
    var onAddSubFolder: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDropTargeted = false
    @State private var isHovered = false
    @FocusState private var isRenameFocused: Bool

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if hasChildren {
                Button(action: { onToggleExpand?() }) {
                    Image(systemName: "chevron.right")
                        .font(CiderFont.micro)
                        .foregroundColor(CiderColors.quaternary)
                        .frame(width: FolderSidebarItemDesign.subFolderIconSize, height: FolderSidebarItemDesign.subFolderIconSize)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: FolderSidebarItemDesign.subFolderIconSize, height: FolderSidebarItemDesign.subFolderIconSize)
            }

            subFolderIconView

            if isRenaming {
                TextField("Folder name", text: $renamingName)
                    .textFieldStyle(.plain)
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.primary)
                    .focused($isRenameFocused)
                    .onSubmit { onCommitRename?() }
                    .onExitCommand { onCancelRename?() }
                    .task {
                        try? await Task.sleep(for: .milliseconds(150))
                        isRenameFocused = true
                    }
            } else {
                Text(title)
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.xs)

            if !isRenaming {
                Text("\(itemCount)")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.tertiary)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .frame(minHeight: BookmarksDesign.folderSidebarRowMinHeight)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(borderColor, lineWidth: CiderBorder.innerStrokeWidth)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isRenaming {
                onTap()
            }
        }
        .animation(reduceMotion ? .none : .snappy, value: isDropTargeted)
        .animation(reduceMotion ? .none : .snappy, value: isHovered)
        .animation(reduceMotion ? .none : .snappy, value: isExpanded)
        .hoverState($isHovered)
        .onDrop(
            of: dropTypeIdentifiers,
            isTargeted: $isDropTargeted,
            perform: onDropProviders
        )
        .onChange(of: isDropTargeted) { _, targeted in
            onDropTargetChanged(targeted)
        }
        .modifier(CardContextMenuModifier { [onRename, onSetIcon, onAddSubFolder, onDelete, folderIcon] in
            var items: [CardMenuItem] = []
            if let onRename {
                items.append(.action(title: "Rename", callback: onRename))
            }
            if let onSetIcon {
                items.append(.submenu(title: "Icon", children: FolderIconMenuItems.build(
                    currentIcon: folderIcon, onSetIcon: onSetIcon
                )))
            }
            if let onAddSubFolder {
                items.append(.action(title: "Add Sub Folder", callback: onAddSubFolder))
            }
            if let onDelete {
                items.append(.separator)
                items.append(.destructive(title: "Delete Folder", callback: onDelete))
            }
            return items
        })
    }

    @ViewBuilder
    private var subFolderIconView: some View {
        if let icon = folderIcon, folderIconIsEmoji {
            Text(icon)
                .font(CiderFont.subheading)
        } else if let icon = folderIcon {
            Image(systemName: icon)
                .font(CiderFont.bodySemibold)
                .foregroundColor(iconColor)
        } else {
            Image(systemName: "folder")
                .font(CiderFont.bodySemibold)
                .foregroundColor(iconColor)
        }
    }

    private var iconColor: Color {
        if isDropTargeted || isSelected {
            return CiderColors.controlAccent
        }
        return CiderColors.secondary
    }

    private var backgroundColor: Color {
        if isDropTargeted {
            return CiderColors.dropTargetFill
        }
        if isSelected {
            return CiderColors.selectedFill
        }
        if isHovered {
            return CiderColors.surfaceHover
        }
        return CiderColors.surfaceElevated
    }

    private var borderColor: Color {
        if isDropTargeted {
            return CiderColors.dropTargetBorder
        }
        if isSelected {
            return CiderColors.selectedBorder
        }
        return CiderColors.borderDefault
    }
}

// MARK: - Folder Icon Menu Items

enum FolderIconMenuItems {
    private static let sfSymbols: [(name: String, label: String)] = [
        ("star.fill", "Star"),
        ("heart.fill", "Heart"),
        ("bolt.fill", "Bolt"),
        ("flame.fill", "Flame"),
        ("leaf.fill", "Leaf"),
        ("book.fill", "Book"),
        ("briefcase.fill", "Briefcase"),
        ("hammer.fill", "Tools"),
        ("paintbrush.fill", "Design"),
        ("music.note", "Music"),
        ("film", "Film"),
        ("gamecontroller.fill", "Games"),
        ("cart.fill", "Shopping"),
        ("airplane", "Travel"),
        ("graduationcap.fill", "Education"),
        ("stethoscope", "Health"),
        ("banknote.fill", "Finance"),
        ("house.fill", "Home"),
        ("person.2.fill", "People"),
        ("globe", "Web"),
        ("lock.fill", "Private"),
        ("archivebox.fill", "Archive"),
    ]

    private static let emojis: [(emoji: String, label: String)] = [
        ("🎨", "Art"), ("🎵", "Music"), ("📚", "Books"), ("💡", "Ideas"),
        ("🔥", "Fire"), ("⭐", "Star"), ("💎", "Gem"), ("🎯", "Target"),
        ("🚀", "Rocket"), ("🌈", "Rainbow"), ("🍕", "Food"), ("☕", "Coffee"),
        ("🏠", "Home"), ("✈️", "Travel"), ("🎬", "Film"), ("📷", "Photo"),
    ]

    private static func sfSymbolImage(_ name: String) -> NSImage? {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        img?.isTemplate = true
        return img
    }

    static func build(currentIcon: String?, onSetIcon: @escaping (String?) -> Void) -> [CardMenuItem] {
        var items: [CardMenuItem] = []

        items.append(.submenu(title: "Symbol", children: sfSymbols.map { symbol in
            let title = symbol.name == currentIcon ? "\(symbol.label) ✓" : symbol.label
            return .action(title: title, image: sfSymbolImage(symbol.name)) { onSetIcon(symbol.name) }
        }))

        items.append(.submenu(title: "Emoji", children: emojis.map { item in
            let title = item.emoji == currentIcon ? "\(item.emoji)  \(item.label) ✓" : "\(item.emoji)  \(item.label)"
            return .action(title: title) { onSetIcon(item.emoji) }
        }))

        if currentIcon != nil {
            items.append(.separator)
            items.append(.action(title: "Remove Icon") { onSetIcon(nil) })
        }

        return items
    }
}
