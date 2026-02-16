import SwiftUI
import UniformTypeIdentifiers

struct FolderSidebarView: View {
    let folders: [Folder]
    let bookmarks: [Bookmark]
    let notes: [Note]
    let projects: [Project]
    @Binding var selectedFolderID: UUID?
    @Binding var expandedFolderIDs: Set<UUID>
    var onCreateFolder: ((String, UUID?) -> Folder?)?
    var onAssignBookmarkToFolder: ((Bookmark, UUID?) -> Bool)?
    var onAssignNoteToFolder: ((Note, UUID?) -> Bool)?
    var onOpenProject: ((UUID) -> Void)?
    var onCreateProject: (() -> Void)?
    var onDeleteProject: ((UUID) -> Void)?
    var onRenameProject: ((UUID, String) -> Void)?
    var onDeleteFolder: ((UUID) -> Void)?
    var onSelectSubFolder: ((UUID) -> Void)?
    var onTriggerSearch: (() -> Void)?
    var onCreateBookmark: (() -> Void)?
    var onCreateNote: (() -> Void)?
    var onCaptureBrowserTab: (() -> Void)?
    var onPasteFromClipboard: (() -> Void)?

    @Environment(\.textScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isFolderCreationFieldVisible = false
    @State private var draftFolderName = ""
    @State private var subFolderParentID: UUID?
    @State private var draftSubFolderName = ""
    @State private var renamingProjectID: UUID?
    @State private var renamingProjectName = ""

    private var topLevelFolders: [Folder] {
        childFolders(of: nil)
    }

    private static let bookmarkDragTypeIdentifier = "com.cider.bookmark-id"

    private var folderDropTypeIdentifiers: [String] {
        [
            Self.bookmarkDragTypeIdentifier,
            UTType.text.identifier,
            UTType.plainText.identifier,
            UTType.utf8PlainText.identifier,
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Search trigger
            if let onTriggerSearch {
                Button(action: onTriggerSearch) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(CiderColors.tertiary)

                        Text("Search")
                            .font(.system(size: 12))
                            .foregroundColor(CiderColors.tertiary)

                        Spacer(minLength: 0)

                        Text("\u{2318}K")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(CiderColors.quaternary)
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.separator.opacity(0.25))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Label("Folders", systemImage: "folder")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(CiderColors.secondary)

            FolderSidebarAllItemsRow(
                itemCount: bookmarks.count + notes.count,
                isSelected: selectedFolderID == nil,
                dropTypeIdentifiers: folderDropTypeIdentifiers,
                onTap: { selectFolder(nil) },
                onDropProviders: { providers in
                    handleFolderDrop(providers: providers, targetFolderID: nil)
                }
            )

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
                    .font(.system(size: 11))
                    .foregroundColor(CiderColors.tertiary)
                    .padding(.horizontal, Spacing.xs)
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

            if !projects.isEmpty || onCreateProject != nil {
                projectsSection
            }

            Spacer(minLength: 0)

            Divider()
                .background(CiderColors.separator)

            HStack(spacing: Spacing.sm) {
                Button {
                    NotificationCenter.default.post(name: .openCiderSettings, object: nil)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(CiderColors.secondary)
                        .frame(width: BookmarksDesign.buttonTapTarget, height: BookmarksDesign.buttonTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings")

                Spacer(minLength: 0)

                Menu {
                    Button(action: toggleFolderCreationField) {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    if let onCreateProject {
                        Button(action: onCreateProject) {
                            Label("New Project", systemImage: "tray.full")
                        }
                    }
                    if let onCreateBookmark {
                        Button(action: onCreateBookmark) {
                            Label("New Bookmark", systemImage: "bookmark")
                        }
                    }
                    if let onCreateNote {
                        Button(action: onCreateNote) {
                            Label("New Note", systemImage: "note.text")
                        }
                    }
                    if onCaptureBrowserTab != nil || onPasteFromClipboard != nil {
                        Divider()
                    }
                    if let onCaptureBrowserTab {
                        Button(action: onCaptureBrowserTab) {
                            Label("Capture Browser Tab", systemImage: "safari")
                        }
                    }
                    if let onPasteFromClipboard {
                        Button(action: onPasteFromClipboard) {
                            Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(CiderColors.secondary)
                        .frame(width: BookmarksDesign.buttonTapTarget, height: BookmarksDesign.buttonTapTarget)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Create new item")
            }
        }
        .padding(Spacing.sm)
        .frame(width: BookmarksDesign.folderSidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: CiderBorder.innerStrokeWidth)
        )
    }

    // MARK: - Projects Section

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Divider()
                .background(CiderColors.separator)
                .padding(.vertical, Spacing.xxs)

            Label("Projects", systemImage: "tray.full")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(CiderColors.secondary)

            ForEach(projects) { project in
                projectSidebarRow(project)
            }

            if projects.isEmpty {
                Text("No projects yet.")
                    .font(.system(size: 11))
                    .foregroundColor(CiderColors.tertiary)
                    .padding(.horizontal, Spacing.xs)
            }
        }
    }

    private func projectSidebarRow(_ project: Project) -> some View {
        let count = ProjectStorage.shared.itemCount(for: project.id)
        let isRenaming = renamingProjectID == project.id
        return HStack(spacing: Spacing.xs) {
            Image(systemName: "tray.full")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(CiderColors.controlAccent)

            if isRenaming {
                TextField("Project name", text: $renamingProjectName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CiderColors.primary)
                    .onSubmit { commitProjectRename() }
                    .onExitCommand { renamingProjectID = nil }
            } else {
                Text(project.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.xs)

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(CiderColors.tertiary)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .frame(minHeight: BookmarksDesign.folderSidebarRowMinHeight)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: CiderBorder.innerStrokeWidth)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isRenaming {
                onOpenProject?(project.id)
            }
        }
        .contextMenu {
            Button {
                renamingProjectName = project.name
                renamingProjectID = project.id
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                onDeleteProject?(project.id)
            } label: {
                Label("Delete Project", systemImage: "trash")
            }
        }
    }

    private func commitProjectRename() {
        guard let id = renamingProjectID else { return }
        let trimmed = renamingProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onRenameProject?(id, trimmed)
        }
        renamingProjectID = nil
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
                dropTypeIdentifiers: folderDropTypeIdentifiers,
                onTap: {
                    selectFolder(folder.id)
                    if !isExpanded {
                        _ = withAnimation(reduceMotion ? .none : .snappy) {
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
                dropTypeIdentifiers: folderDropTypeIdentifiers,
                onTap: {
                    selectFolder(folder.id)
                    if !isExpanded && hasChildrenOrSubCreation {
                        _ = withAnimation(reduceMotion ? .none : .snappy) {
                            expandedFolderIDs.insert(folder.id)
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(CiderColors.controlAccent)

            TextField("Sub folder name", text: $draftSubFolderName)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(CiderColors.primary)
                .onSubmit { commitSubFolderCreation() }
                .onExitCommand { cancelSubFolderCreation() }

            Button(action: commitSubFolderCreation) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(CiderColors.controlAccent)
            }
            .buttonStyle(.plain)

            Button(action: cancelSubFolderCreation) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(CiderColors.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.sm)
        .frame(minHeight: BookmarksDesign.folderSidebarRowMinHeight)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.controlAccent.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(CiderColors.controlAccent.opacity(0.3), lineWidth: CiderBorder.innerStrokeWidth)
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

        for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
            provider.loadObject(ofClass: NSString.self) { item, _ in
                guard let raw = item as? String else { return }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let prefix = "cider-bookmark-id:"
                guard trimmed.hasPrefix(prefix),
                      let bookmarkID = UUID(uuidString: String(trimmed.dropFirst(prefix.count))) else {
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

        return false
    }
}

// MARK: - All Items Row

private struct FolderSidebarAllItemsRow: View {
    let itemCount: Int
    let isSelected: Bool
    let dropTypeIdentifiers: [String]
    let onTap: () -> Void
    let onDropProviders: ([NSItemProvider]) -> Bool

    @State private var isDropTargeted = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "tray.2")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isSelected ? CiderColors.controlAccent : CiderColors.secondary)

            Text("All Items")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)

            Spacer(minLength: Spacing.xs)

            Text("\(itemCount)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(CiderColors.tertiary)
        }
        .padding(.horizontal, Spacing.sm)
        .frame(minHeight: BookmarksDesign.folderSidebarRowMinHeight)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isSelected ? CiderColors.controlAccent.opacity(0.14)
                      : isHovered ? Color.white.opacity(0.1)
                      : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(isSelected ? CiderColors.controlAccent.opacity(0.48) : Color.white.opacity(0.12),
                        lineWidth: CiderBorder.innerStrokeWidth)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { isHovered = $0 }
        .onDrop(of: dropTypeIdentifiers, isTargeted: $isDropTargeted, perform: onDropProviders)
    }
}

// MARK: - Root Folder Header Row

struct RootFolderHeaderRow: View {
    let title: String
    let itemCount: Int
    let isExpanded: Bool
    let isSelected: Bool
    let dropTypeIdentifiers: [String]
    let onTap: () -> Void
    let onToggleCollapse: () -> Void
    let onDropTargetChanged: (Bool) -> Void
    let onDropProviders: ([NSItemProvider]) -> Bool
    var onDelete: (() -> Void)?
    var onAddSubFolder: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDropTargeted = false
    @State private var isHovered = false
    @State private var isIconHovered = false
    @State private var showChevronIcon = false
    @State private var chevronRevertTask: DispatchWorkItem?

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // Icon area: click here to toggle collapse
            ZStack {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(iconColor)
                    .opacity(shouldShowChevron ? 0 : 1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(iconColor)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .opacity(shouldShowChevron ? 1 : 0)
            }
            .frame(width: 20, height: BookmarksDesign.folderSidebarRowMinHeight + 2)
            .contentShape(Rectangle())
            .onTapGesture {
                onToggleCollapse()
            }
            .onHover { isIconHovered = $0 }
            .animation(reduceMotion ? .none : .smooth, value: shouldShowChevron)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)

            Spacer(minLength: Spacing.xs)

            if itemCount > 0 {
                Text("\(itemCount)")
                    .font(.system(size: 10, weight: .medium))
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
            onTap()
            triggerChevronFlash()
        }
        .animation(reduceMotion ? .none : .snappy, value: isDropTargeted)
        .animation(reduceMotion ? .none : .snappy, value: isHovered)
        .animation(reduceMotion ? .none : .snappy, value: isExpanded)
        .onHover { hovering in
            isHovered = hovering
        }
        .onDrop(
            of: dropTypeIdentifiers,
            isTargeted: $isDropTargeted,
            perform: onDropProviders
        )
        .onChange(of: isDropTargeted) { _, targeted in
            onDropTargetChanged(targeted)
        }
        .contextMenu {
            if let onAddSubFolder {
                Button(action: onAddSubFolder) {
                    Label("Add Sub Folder", systemImage: "folder.badge.plus")
                }
            }
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Folder", systemImage: "trash")
                }
            }
        }
    }

    private var shouldShowChevron: Bool {
        isIconHovered || showChevronIcon
    }

    private func triggerChevronFlash() {
        chevronRevertTask?.cancel()
        showChevronIcon = true

        let task = DispatchWorkItem {
            withAnimation(.smooth) {
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
            return CiderColors.controlAccent.opacity(0.2)
        }
        if isSelected {
            return CiderColors.controlAccent.opacity(0.14)
        }
        if isHovered {
            return Color.white.opacity(0.1)
        }
        return Color.white.opacity(0.06)
    }

    private var borderColor: Color {
        if isDropTargeted {
            return CiderColors.controlAccent.opacity(0.72)
        }
        if isSelected {
            return CiderColors.controlAccent.opacity(0.48)
        }
        return Color.white.opacity(0.12)
    }
}

// MARK: - Sub-Folder Row

struct SubFolderRow: View {
    let title: String
    let itemCount: Int
    let hasChildren: Bool
    let isExpanded: Bool
    let isSelected: Bool
    let dropTypeIdentifiers: [String]
    let onTap: () -> Void
    let onToggleExpand: (() -> Void)?
    let onDropTargetChanged: (Bool) -> Void
    let onDropProviders: ([NSItemProvider]) -> Bool
    var onDelete: (() -> Void)?
    var onAddSubFolder: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDropTargeted = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if hasChildren {
                Button(action: { onToggleExpand?() }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(iconColor)

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)

            Spacer(minLength: Spacing.xs)

            Text("\(itemCount)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(CiderColors.tertiary)
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
        .onTapGesture(perform: onTap)
        .animation(reduceMotion ? .none : .snappy, value: isDropTargeted)
        .animation(reduceMotion ? .none : .snappy, value: isHovered)
        .animation(reduceMotion ? .none : .snappy, value: isExpanded)
        .onHover { hovering in
            isHovered = hovering
        }
        .onDrop(
            of: dropTypeIdentifiers,
            isTargeted: $isDropTargeted,
            perform: onDropProviders
        )
        .onChange(of: isDropTargeted) { _, targeted in
            onDropTargetChanged(targeted)
        }
        .contextMenu {
            if let onAddSubFolder {
                Button(action: onAddSubFolder) {
                    Label("Add Sub Folder", systemImage: "folder.badge.plus")
                }
            }
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Folder", systemImage: "trash")
                }
            }
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
            return CiderColors.controlAccent.opacity(0.2)
        }
        if isSelected {
            return CiderColors.controlAccent.opacity(0.14)
        }
        if isHovered {
            return Color.white.opacity(0.1)
        }
        return Color.white.opacity(0.06)
    }

    private var borderColor: Color {
        if isDropTargeted {
            return CiderColors.controlAccent.opacity(0.72)
        }
        if isSelected {
            return CiderColors.controlAccent.opacity(0.48)
        }
        return Color.white.opacity(0.12)
    }
}
