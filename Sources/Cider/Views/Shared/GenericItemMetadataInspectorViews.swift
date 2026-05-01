import SwiftUI

extension LibraryEntityRef {
    static func dateCard(_ id: UUID) -> LibraryEntityRef {
        LibraryEntityRef(type: .dateCard, entityID: id)
    }

    static func todo(_ id: UUID) -> LibraryEntityRef {
        LibraryEntityRef(type: .todo, entityID: id)
    }

    static func vaultFile(_ id: UUID) -> LibraryEntityRef {
        LibraryEntityRef(type: .vaultFile, entityID: id)
    }
}

struct BasicItemMetadataInspectorView: View {
    let title: String
    let typeLabel: String
    let createdAt: Date
    let updatedAt: Date
    var folderName: String?
    var labelIDs: [UUID] = []
    var linkedRef: LibraryEntityRef
    var extraRows: [ItemMetadataRow] = []
    var onOpenLinkedRef: ((LibraryEntityRef) -> Void)?
    var canOpenLinkedRef: ((LibraryEntityRef) -> Bool)?

    @ObservedObject private var labelStorage = CardLabelStorage.shared
    @State private var isLinkedExpanded = true
    @State private var isFolderExpanded = true
    @State private var isLabelsExpanded = true
    @State private var isDetailsExpanded = true
    @State private var isInfoExpanded = true

    var body: some View {
        ItemMetadataInspectorView {
            Text(title)
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(3)
                .padding(.bottom, Spacing.md)

            sectionDivider

            ItemMetadataSectionView(title: "Linked", isExpanded: $isLinkedExpanded) {
                let rows = relatedRows
                if rows.isEmpty {
                    Text("No linked items.")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.quaternary)
                } else {
                    ItemMetadataRowsView(
                        rows: rows,
                        onOpenRef: onOpenLinkedRef,
                        canOpenRef: canOpenLinkedRef
                    )
                }
            }

            if let folderName = trimmedFolderName {
                sectionDivider

                ItemMetadataSectionView(title: "Folder", isExpanded: $isFolderExpanded) {
                    ItemMetadataRowsView(rows: [
                        ItemMetadataRow(id: "folder", symbol: "folder", title: folderName)
                    ])
                }
            }

            let labelRows = labelRows
            if !labelRows.isEmpty {
                sectionDivider

                ItemMetadataSectionView(title: "Labels", isExpanded: $isLabelsExpanded) {
                    ItemMetadataRowsView(rows: labelRows)
                }
            }

            if !extraRows.isEmpty {
                sectionDivider

                ItemMetadataSectionView(title: "Details", isExpanded: $isDetailsExpanded) {
                    ItemMetadataRowsView(rows: extraRows)
                }
            }

            sectionDivider

            ItemMetadataSectionView(title: "Info", isExpanded: $isInfoExpanded) {
                ItemMetadataRowsView(rows: ItemMetadataInfoRows.rows(
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    typeLabel: typeLabel
                ))
            }
        }
    }

    private var sectionDivider: some View {
        Divider().background(CiderColors.separator)
    }

    private var trimmedFolderName: String? {
        guard let folderName else { return nil }
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var labelRows: [ItemMetadataRow] {
        labelIDs.compactMap { id in
            guard let label = labelStorage.labels.first(where: { $0.id == id }) else { return nil }
            return ItemMetadataRow(id: "label-\(label.id.uuidString)", symbol: "tag", title: label.name)
        }
    }

    private var relatedRows: [ItemMetadataRow] {
        let refs = (try? ItemLinkService.shared.relatedRefs(for: linkedRef)) ?? []
        return ItemLinkService.shared.summaries(for: refs).map(ItemMetadataRow.related)
    }
}

extension BasicItemMetadataInspectorView {
    init(
        dateCard: DateCard,
        onOpenLinkedRef: ((LibraryEntityRef) -> Void)? = nil,
        canOpenLinkedRef: ((LibraryEntityRef) -> Bool)? = nil
    ) {
        self.init(
            title: dateCard.title,
            typeLabel: "Date Card",
            createdAt: dateCard.createdAt,
            updatedAt: dateCard.updatedAt,
            folderName: Self.folderName(for: dateCard.folderID),
            labelIDs: dateCard.labelIDs,
            linkedRef: .dateCard(dateCard.id),
            extraRows: DateCardMetadataRows.rows(for: dateCard),
            onOpenLinkedRef: onOpenLinkedRef,
            canOpenLinkedRef: canOpenLinkedRef
        )
    }

    init(
        todo: TodoCard,
        onOpenLinkedRef: ((LibraryEntityRef) -> Void)? = nil,
        canOpenLinkedRef: ((LibraryEntityRef) -> Bool)? = nil
    ) {
        self.init(
            title: todo.title,
            typeLabel: "Todo",
            createdAt: todo.createdAt,
            updatedAt: todo.updatedAt,
            folderName: Self.folderName(for: todo.folderID),
            labelIDs: todo.labelIDs,
            linkedRef: .todo(todo.id),
            extraRows: TodoMetadataRows.rows(for: todo),
            onOpenLinkedRef: onOpenLinkedRef,
            canOpenLinkedRef: canOpenLinkedRef
        )
    }

    init(
        file: VaultFile,
        onOpenLinkedRef: ((LibraryEntityRef) -> Void)? = nil,
        canOpenLinkedRef: ((LibraryEntityRef) -> Bool)? = nil
    ) {
        self.init(
            title: file.displayTitle,
            typeLabel: "File",
            createdAt: file.createdAt,
            updatedAt: file.modifiedAt,
            folderName: Self.folderName(for: file.folderID),
            labelIDs: file.labelIDs,
            linkedRef: .vaultFile(file.id),
            extraRows: Self.fileRows(for: file),
            onOpenLinkedRef: onOpenLinkedRef,
            canOpenLinkedRef: canOpenLinkedRef
        )
    }

    private static func folderName(for folderID: UUID?) -> String? {
        guard let folderID else { return nil }
        return VaultFolderService.shared.legacyFolders.first(where: { $0.id == folderID })?.name
    }

    private static func fileRows(for file: VaultFile) -> [ItemMetadataRow] {
        var rows = [
            ItemMetadataRow(id: "kind", symbol: file.fileType.systemImageName, title: "Kind", value: file.fileType.displayName)
        ]

        let fileExtension = (file.filename as NSString).pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fileExtension.isEmpty {
            rows.append(ItemMetadataRow(id: "file-type", symbol: "doc", title: "File Type", value: fileExtension.uppercased()))
        }

        rows.append(ItemMetadataRow(id: "size", symbol: "externaldrive", title: "Size", value: ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file)))

        return rows
    }
}

struct VaultFileMetadataPresentation: Equatable {
    let title: String
    let sourcePath: String
    let kind: String
    let fileType: String?
    let size: String
    let colors: [String]
    let notes: String?
    let ocrText: String?
    let keywords: [String]

    init(file: VaultFile) {
        title = file.displayTitle
        sourcePath = file.relativePath
        kind = file.fileType.displayName
        let ext = (file.filename as NSString).pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        fileType = ext.isEmpty ? nil : ext.uppercased()
        size = ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file)
        colors = (file.dominantColors ?? []).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let trimmedNotes = file.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        let trimmedOCR = (file.ocrText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        ocrText = trimmedOCR.isEmpty ? nil : trimmedOCR
        keywords = file.tags.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

struct VaultFileMetadataInspectorView: View {
    let file: VaultFile
    var onOpenLinkedRef: ((LibraryEntityRef) -> Void)?
    var canOpenLinkedRef: ((LibraryEntityRef) -> Bool)?
    var onFolderChanged: ((UUID?) -> Void)?
    var onDelete: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.textScale) private var textScale
    @ObservedObject private var labelStorage = CardLabelStorage.shared
    @State private var linkedSummaries: [ItemLinkSummary] = []
    @State private var titleDraft = ""
    @State private var notesDraft = ""
    @State private var folderIDDraft: UUID?
    @State private var labelIDsDraft: [UUID] = []
    @State private var isEditingNotes = false
    @State private var copiedHex: String?

    @State private var isSourceExpanded = true
    @State private var isFolderExpanded = true
    @State private var isTagsExpanded = true
    @State private var isKeywordsExpanded = false
    @State private var isLinkedExpanded = true
    @State private var isNotesExpanded = true
    @State private var isIntelligenceExpanded = true
    @State private var isInfoExpanded = true

    private var presentation: VaultFileMetadataPresentation {
        VaultFileMetadataPresentation(file: file)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    titleSection
                        .padding(.bottom, Spacing.md)

                    sectionDivider
                    sourceSection
                        .padding(.vertical, Spacing.md)

                    sectionDivider
                    folderSection
                        .padding(.vertical, Spacing.md)

                    sectionDivider
                    tagsSection
                        .padding(.vertical, Spacing.md)

                    if !presentation.keywords.isEmpty {
                        sectionDivider
                        keywordsSection
                            .padding(.vertical, Spacing.md)
                    }

                    if !linkedSummaries.isEmpty {
                        sectionDivider
                        linkedSection
                            .padding(.vertical, Spacing.md)
                    }

                    sectionDivider
                    notesSection
                        .padding(.vertical, Spacing.md)

                    if hasIntelligence {
                        sectionDivider
                        intelligenceSection
                            .padding(.vertical, Spacing.md)
                    }
                }
                .padding(Spacing.md)
            }
            .frame(maxHeight: .infinity)

            footerSection
        }
        .frame(width: BookmarksDesign.detailsSidebarFixedWidth)
        .frame(maxHeight: .infinity)
        .background(CiderColors.surfaceInput)
        .overlay(alignment: .leading) {
            CiderColors.separator
                .frame(width: Spacing.hairline)
        }
        .onAppear(perform: syncDrafts)
        .onChange(of: file.id) { _, _ in
            linkedSummaries = []
            copiedHex = nil
            isEditingNotes = false
            syncDrafts()
        }
        .task(id: file.id) {
            refreshLinkedSummaries()
        }
    }

    private var sectionDivider: some View {
        Divider().background(CiderColors.separator)
    }

    private func sectionHeader(_ title: String, isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(reduceMotion ? .none : .snappy) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Text(title)
                    .font(CiderFont.bodyMedium(scale: textScale))
                    .foregroundColor(CiderColors.tertiary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up")
                    .font(CiderFont.micro)
                    .foregroundColor(CiderColors.tertiary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : -90))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var titleSection: some View {
        TextField("Title", text: $titleDraft, axis: .vertical)
            .font(CiderFont.bodySemibold(scale: textScale))
            .foregroundColor(CiderColors.primary)
            .lineLimit(1...5)
            .textFieldStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.surfaceInput)
            )
            .onSubmit(saveTitle)
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("Source", isExpanded: $isSourceExpanded)

            if isSourceExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(presentation.sourcePath)
                        .font(CiderFont.label(scale: textScale))
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: BookmarksDesign.detailsSheetURLMinHeight)
                .padding(.horizontal, Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )

                HStack(spacing: Spacing.xs) {
                    metadataButton(title: "Open", systemImage: "arrow.up.forward.app") {
                        NSWorkspace.shared.open(file.absoluteURL)
                    }

                    metadataButton(title: "Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([file.absoluteURL])
                    }
                }
            }
        }
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("Folder", isExpanded: $isFolderExpanded)

            if isFolderExpanded {
                Menu {
                    Button("No Folder") {
                        assignFolder(nil)
                    }
                    if !folders.isEmpty { Divider() }
                    ForEach(folders) { folder in
                        Button(folder.name) {
                            assignFolder(folder.id)
                        }
                    }
                } label: {
                    HStack {
                        Label(currentFolderName, systemImage: "folder")
                            .font(CiderFont.body(scale: textScale))
                            .foregroundColor(CiderColors.secondary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(CiderFont.caption(scale: textScale))
                            .foregroundColor(CiderColors.tertiary)
                    }
                    .padding(.horizontal, Spacing.sm)
                    .frame(minHeight: BookmarksDesign.buttonTapTarget)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )
                }
                .menuStyle(.borderlessButton)
            }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("Tags", isExpanded: $isTagsExpanded)

            if isTagsExpanded {
                TagFlowLayout(spacing: Spacing.xs) {
                    ForEach(assignedLabels) { label in
                        TagPillView(
                            label: label,
                            onRemove: { toggleLabel(label.id) }
                        )
                    }

                    Menu {
                        if unassignedLabels.isEmpty && labelStorage.labels.isEmpty {
                            Button("New Tag...") {
                                createAndAssignLabel()
                            }
                        } else {
                            ForEach(unassignedLabels) { label in
                                Button {
                                    toggleLabel(label.id)
                                } label: {
                                    HStack(spacing: Spacing.xs) {
                                        Circle()
                                            .fill(Color(hex: label.colorHex) ?? CiderColors.secondary)
                                            .frame(width: BookmarksDesign.tagColorDotSize, height: BookmarksDesign.tagColorDotSize)
                                        Text(label.name)
                                    }
                                }
                            }

                            Divider()

                            Button("New Tag...") {
                                createAndAssignLabel()
                            }
                        }
                    } label: {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "plus")
                                .font(CiderFont.badgeSemibold)
                            Text("Add Tag")
                                .font(CiderFont.caption(scale: textScale))
                        }
                        .foregroundColor(CiderColors.controlAccent)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                                .fill(CiderColors.accentSubtle)
                        )
                    }
                    .menuStyle(.borderlessButton)
                }
            }
        }
    }

    private var keywordsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("Keywords", isExpanded: $isKeywordsExpanded)

            if isKeywordsExpanded {
                TagFlowLayout(spacing: Spacing.xs) {
                    ForEach(presentation.keywords, id: \.self) { tag in
                        Text(tag)
                            .font(CiderFont.label(scale: textScale))
                            .foregroundColor(CiderColors.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.xxs)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                                    .fill(CiderColors.surfaceInput)
                            )
                    }
                }
            }
        }
    }

    private var linkedSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("Linked", isExpanded: $isLinkedExpanded)

            if isLinkedExpanded {
                ItemMetadataRowsView(
                    rows: linkedSummaries.map(ItemMetadataRow.related),
                    onOpenRef: onOpenLinkedRef,
                    canOpenRef: canOpenLinkedRef
                )
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("Notes", isExpanded: $isNotesExpanded)

            if isNotesExpanded {
                if isEditingNotes {
                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        TextEditor(text: $notesDraft)
                            .font(CiderFont.label(scale: textScale))
                            .frame(
                                minHeight: BookmarksDesign.detailsSheetNotesMinHeight,
                                idealHeight: BookmarksDesign.detailsSheetNotesHeight,
                                maxHeight: BookmarksDesign.detailsSheetNotesHeight
                            )
                            .padding(Spacing.xxs)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .fill(CiderColors.surfaceInput)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

                        Button("Done") {
                            saveNotes()
                            isEditingNotes = false
                        }
                        .buttonStyle(CiderSecondaryButtonStyle())
                    }
                } else if let notes = presentation.notes {
                    Text(notes)
                        .font(CiderFont.body(scale: textScale))
                        .foregroundColor(CiderColors.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentShape(Rectangle())
                        .onTapGesture { isEditingNotes = true }
                } else {
                    Button {
                        isEditingNotes = true
                    } label: {
                        Label("Add note", systemImage: "plus")
                            .font(CiderFont.body(scale: textScale))
                            .foregroundColor(CiderColors.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: BookmarksDesign.buttonTapTarget)
                    .padding(.horizontal, Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )
                }
            }
        }
    }

    private var intelligenceSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("Intelligence", isExpanded: $isIntelligenceExpanded)

            if isIntelligenceExpanded {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    if let ocrText = presentation.ocrText {
                        Text(ocrText)
                            .font(CiderFont.body(scale: textScale))
                            .foregroundColor(CiderColors.secondary)
                            .lineLimit(6)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !presentation.colors.isEmpty {
                        colorsSubsection(colors: presentation.colors)
                    }
                }
            }
        }
    }

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Divider().background(CiderColors.separator)

            sectionHeader("Info", isExpanded: $isInfoExpanded)

            if isInfoExpanded {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    propertyRow("Created", value: file.createdAt.formatted(date: .abbreviated, time: .shortened))
                    propertyRow("Updated", value: file.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    propertyRow("Type", value: "File")
                    propertyRow("Kind", value: presentation.kind)
                    if let fileType = presentation.fileType {
                        propertyRow("File Type", value: fileType)
                    }
                    propertyRow("Size", value: presentation.size)
                }
                .padding(.bottom, Spacing.xxs)
            }

            if let onDelete {
                Divider().background(CiderColors.separator)

                Button("Delete", action: onDelete)
                    .buttonStyle(CiderDestructiveButtonStyle())
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(Spacing.md)
    }

    private func metadataButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(CiderFont.bodyMedium(scale: textScale))
                .foregroundColor(CiderColors.secondary)
                .frame(minHeight: BookmarksDesign.buttonTapTarget)
                .padding(.horizontal, Spacing.sm)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceInput)
        )
    }

    private func colorsSubsection(colors: [String]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Colors")
                .font(CiderFont.caption(scale: textScale))
                .foregroundColor(CiderColors.tertiary)

            HStack(spacing: Spacing.sm) {
                ForEach(colors, id: \.self) { hex in
                    if let color = Color(hex: hex) {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(hex.uppercased(), forType: .string)
                            copiedHex = hex
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(1.2))
                                guard !Task.isCancelled else { return }
                                copiedHex = nil
                            }
                        } label: {
                            VStack(spacing: Spacing.xxs) {
                                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                                    .fill(color)
                                    .frame(width: BookmarksDesign.colorSwatchWidth, height: BookmarksDesign.colorSwatchHeight)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                                            .stroke(CiderColors.borderSubtle, lineWidth: CiderBorder.innerStrokeWidth)
                                    )

                                Group {
                                    if copiedHex == hex {
                                        Image(systemName: "checkmark")
                                            .font(CiderFont.badgeSemibold)
                                            .foregroundColor(CiderColors.success)
                                    } else {
                                        Text(hex.uppercased())
                                            .font(CiderFont.caption(scale: textScale))
                                            .foregroundColor(CiderColors.tertiary)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(height: BookmarksDesign.colorSwatchLabelHeight)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Copy \(hex.uppercased())")
                    }
                }
            }
        }
    }

    private func propertyRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Text(label)
                .font(CiderFont.caption(scale: textScale))
                .foregroundColor(CiderColors.tertiary)
                .frame(width: BookmarksDesign.propertyLabelWidth, alignment: .leading)
            Text(value)
                .font(CiderFont.caption(scale: textScale))
                .foregroundColor(CiderColors.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var hasIntelligence: Bool {
        presentation.ocrText != nil || !presentation.colors.isEmpty
    }

    private var folderName: String? {
        guard let folderID = folderIDDraft else { return nil }
        return folders.first(where: { $0.id == folderID })?.name
    }

    private var currentFolderName: String {
        folderName ?? "No Folder"
    }

    private var folders: [Folder] {
        VaultFolderService.shared.legacyFolders
    }

    private var assignedLabels: [CardLabel] {
        labelIDsDraft.compactMap { id in
            labelStorage.labels.first(where: { $0.id == id })
        }
    }

    private var unassignedLabels: [CardLabel] {
        let assigned = Set(labelIDsDraft)
        return labelStorage.labels.filter { !assigned.contains($0.id) }
    }

    private func syncDrafts() {
        titleDraft = file.title?.isEmpty == false ? file.title ?? file.displayTitle : file.displayTitle
        notesDraft = file.notes
        folderIDDraft = file.folderID
        labelIDsDraft = file.labelIDs
    }

    private func saveTitle() {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultTitle = (file.filename as NSString).deletingPathExtension
        VaultFileStorage.shared.updateTitle(file, title: trimmed.isEmpty || trimmed == defaultTitle ? nil : trimmed)
        VaultFileService.shared.refreshMetadata()
    }

    private func saveNotes() {
        VaultFileStorage.shared.updateNotes(file, notes: notesDraft)
        VaultFileService.shared.refreshMetadata()
    }

    private func assignFolder(_ folderID: UUID?) {
        folderIDDraft = folderID
        onFolderChanged?(folderID)
    }

    private func toggleLabel(_ labelID: UUID) {
        if let index = labelIDsDraft.firstIndex(of: labelID) {
            labelIDsDraft.remove(at: index)
            VaultFileStorage.shared.removeLabel(file, labelID: labelID)
        } else {
            labelIDsDraft.append(labelID)
            VaultFileStorage.shared.assignLabel(file, labelID: labelID)
        }
        VaultFileService.shared.refreshMetadata()
    }

    private func createAndAssignLabel() {
        let newLabel = CardLabelStorage.shared.createLabel(
            name: "New Tag",
            colorHex: CardLabelStorage.randomPresetColor()
        )
        toggleLabel(newLabel.id)
    }

    private func refreshLinkedSummaries() {
        let ref = LibraryEntityRef(type: .vaultFile, entityID: file.id)
        let refs = (try? ItemLinkService.shared.relatedRefs(for: ref)) ?? []
        linkedSummaries = ItemLinkService.shared.summaries(for: refs)
    }
}

enum DateCardMetadataRows {
    static func rows(for dateCard: DateCard) -> [ItemMetadataRow] {
        var rows = [
            ItemMetadataRow(id: "date", symbol: "calendar", title: "Date", value: dateValue(for: dateCard)),
            ItemMetadataRow(id: "time", symbol: "clock", title: "Time", value: timeValue(for: dateCard))
        ]

        let location = dateCard.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !location.isEmpty {
            rows.append(ItemMetadataRow(id: "location", symbol: "mappin.and.ellipse", title: "Location", value: location))
        }

        if let amount = dateCard.amount {
            rows.append(ItemMetadataRow(id: "amount", symbol: "dollarsign.circle", title: "Amount", value: currencyFormatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)))
        }

        return rows
    }

    private static func dateValue(for dateCard: DateCard) -> String {
        guard let endAt = dateCard.endAt,
              !Calendar.current.isDate(dateCard.startAt, inSameDayAs: endAt) else {
            return dateFormatter.string(from: dateCard.startAt)
        }

        return "\(dateFormatter.string(from: dateCard.startAt)) - \(dateFormatter.string(from: endAt))"
    }

    private static func timeValue(for dateCard: DateCard) -> String {
        if dateCard.allDay {
            return "All day"
        }

        let start = timeFormatter.string(from: dateCard.startAt)
        guard let endAt = dateCard.endAt else {
            return start
        }

        return "\(start) - \(timeFormatter.string(from: endAt))"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

enum TodoMetadataRows {
    static func rows(for todo: TodoCard) -> [ItemMetadataRow] {
        var rows = [
            ItemMetadataRow(
                id: "status",
                symbol: todo.isCompleted ? "checkmark.circle.fill" : "circle",
                title: "Status",
                value: todo.isCompleted ? "Completed" : "Open"
            )
        ]

        if let dueDate = todo.dueDate {
            rows.append(ItemMetadataRow(id: "due", symbol: "calendar", title: "Due", value: dateFormatter.string(from: dueDate)))
        }

        if let priority = todo.priority {
            rows.append(ItemMetadataRow(id: "priority", symbol: priority.icon, title: "Priority", value: priority.displayName))
        }

        return rows
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
