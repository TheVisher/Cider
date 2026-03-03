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

            Label("Folders", systemImage: "folder")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.secondary)
                .padding(.top, Spacing.xs)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(topLevelFolders) { folder in
                        rootFolderGroup(folder)
                    }
                }
                .padding(.horizontal, CiderBorder.innerStrokeInset)
                .padding(.bottom, Spacing.xs)
            }

            if topLevelFolders.isEmpty {
                Text("No folders yet. Create one to organize your items.")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.tertiary)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.bottom, Spacing.xs)
            }

            tagsSection

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

            if enableLinkedSources && (!sources.isEmpty || onAddSource != nil) {
                sourcesSection
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.sm)
        .frame(width: BookmarksDesign.folderSidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .onReceive(NotificationCenter.default.publisher(for: .showFolderCreationField)) { _ in
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
                Button {
                    onOpenTagManager?()
                } label: {
                    Label("Tags", systemImage: "tag")
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

                Button {
                    withAnimation(reduceMotion ? .none : .snappy) {
                        tagsCollapsed.wrappedValue.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(CiderFont.micro)
                        .foregroundColor(CiderColors.quaternary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                }
                .buttonStyle(.plain)
            }

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
                Label("Sources", systemImage: "folder.badge.gear")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.secondary)

                Spacer(minLength: 0)

                if let onAddSource {
                    Button(action: onAddSource) {
                        Image(systemName: "plus")
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(CiderColors.secondary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Add linked source folder")
                }
            }

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
        let isExpanded = expandedFolderIDs.contains(folder.id)

        return VStack(alignment: .leading, spacing: 0) {
            RootFolderHeaderRow(
                title: folder.name,
                itemCount: itemsInFolder(folder.id),
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
                DispatchQueue.main.async {
                    for item in items {
                        if item.type == "bookmark",
                           let bookmark = bookmarks.first(where: { $0.id == item.id }) {
                            _ = onAssignBookmarkToFolder?(bookmark, targetFolderID)
                        } else if item.type == "note",
                                  let note = notes.first(where: { $0.id == item.id }) {
                            _ = onAssignNoteToFolder?(note, targetFolderID)
                        } else if item.type == "datecard" {
                            DateCardStorage.shared.assignDateCard(item.id, toFolder: targetFolderID)
                        } else if item.type == "contact" {
                            ContactStorage.shared.assignContact(item.id, toFolder: targetFolderID)
                        }
                    }
                }
            }
            return true
        }

        // Check for bookmark drag payload
        for provider in providers where provider.hasItemConformingToTypeIdentifier(Self.bookmarkDragTypeIdentifier) {
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

        // Check for note drag payload
        for provider in providers where provider.hasItemConformingToTypeIdentifier(Self.noteDragTypeIdentifier) {
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
        // Use explicit UTF-8 plain text type — loadObject(ofClass: NSString.self)
        // picks the "best" text-compatible type, which may resolve to public.url or
        // public.file-url data instead of our internal Cider ID when those are registered.
        for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
            provider.loadDataRepresentation(forTypeIdentifier: "public.utf8-plain-text") { data, _ in
                guard let data, let raw = String(data: data, encoding: .utf8) else { return }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

                if let items = MultiDragPayload.decodeFromText(trimmed) {
                    DispatchQueue.main.async {
                        for item in items {
                            if item.type == "bookmark",
                               let bookmark = bookmarks.first(where: { $0.id == item.id }) {
                                _ = onAssignBookmarkToFolder?(bookmark, targetFolderID)
                            } else if item.type == "note",
                                      let note = notes.first(where: { $0.id == item.id }) {
                                _ = onAssignNoteToFolder?(note, targetFolderID)
                            } else if item.type == "datecard" {
                                DateCardStorage.shared.assignDateCard(item.id, toFolder: targetFolderID)
                            } else if item.type == "contact" {
                                ContactStorage.shared.assignContact(item.id, toFolder: targetFolderID)
                            }
                        }
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
}

// MARK: - Root Folder Header Row

struct RootFolderHeaderRow: View {
    let title: String
    let itemCount: Int
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
                Image(systemName: "folder.fill")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(iconColor)
                    .opacity(shouldShowChevron ? 0 : 1)

                Image(systemName: "chevron.down")
                    .font(CiderFont.captionBold)
                    .foregroundColor(iconColor)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .opacity(shouldShowChevron ? 1 : 0)
            }
            .frame(width: 20, height: BookmarksDesign.folderSidebarRowMinHeight + 2)
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
        .modifier(CardContextMenuModifier { [onRename, onAddSubFolder, onDelete] in
            var items: [CardMenuItem] = []
            if let onRename {
                items.append(.action(title: "Rename", callback: onRename))
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
        isIconHovered || showChevronIcon
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
                        .frame(width: 14, height: 14)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: 14, height: 14)
            }

            Image(systemName: "folder")
                .font(CiderFont.bodySemibold)
                .foregroundColor(iconColor)

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
        .modifier(CardContextMenuModifier { [onRename, onAddSubFolder, onDelete] in
            var items: [CardMenuItem] = []
            if let onRename {
                items.append(.action(title: "Rename", callback: onRename))
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
