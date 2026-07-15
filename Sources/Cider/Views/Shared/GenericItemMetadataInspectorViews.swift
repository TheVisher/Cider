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
    var folderID: UUID?
    var labelIDs: [UUID] = []
    var linkedRef: LibraryEntityRef
    var extraRows: [ItemMetadataRow] = []
    var onOpenLinkedRef: ((LibraryEntityRef) -> Void)?
    var canOpenLinkedRef: ((LibraryEntityRef) -> Bool)?
    var onFolderChanged: ((UUID?) -> Void)?
    var onToggleLabel: ((UUID) -> Void)?
    var onDelete: (() -> Void)?
    var onOpenHubNavigationTarget: ((LibraryHubNavigationTarget) -> Void)? = nil

    @State private var isLinkedExpanded = true
    @State private var isFolderExpanded = true
    @State private var isLabelsExpanded = true
    @State private var isDetailsExpanded = true
    @State private var isHubFacetsExpanded = true
    @State private var hubFacetPresentation: LibraryHubFacetPresentationModel?

    private var hubFacetRowModel: LibraryHubFacetChipRowModel {
        LibraryHubFacetChipRowModel(
            presentation: hubFacetPresentation,
            supportsOpenHubActions: onOpenHubNavigationTarget != nil
        )
    }

    var body: some View {
        ItemMetadataPanel {
            Text(title)
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(3)
                .padding(.bottom, Spacing.md)

            if hubFacetRowModel.isVisible {
                ItemMetadataDivider()

                LibraryHubFacetChipSectionView(
                    model: hubFacetRowModel,
                    isExpanded: $isHubFacetsExpanded,
                    onOpenHubAction: openHubAction
                )
            }

            ItemMetadataDivider()

            ItemMetadataSectionView(title: "Folder", isExpanded: $isFolderExpanded) {
                ItemMetadataFolderPicker(folderID: folderID) { folderID in
                    onFolderChanged?(folderID)
                }
            }

            ItemMetadataDivider()

            ItemMetadataSectionView(title: "Tags", isExpanded: $isLabelsExpanded) {
                ItemMetadataTagsPicker(
                    labelIDs: labelIDs,
                    onToggleLabel: { labelID in onToggleLabel?(labelID) },
                    onCreateAndAssignLabel: createAndAssignLabel
                )
            }

            ItemMetadataDivider()

            ItemMetadataLinkedSection(
                rows: relatedRows,
                isExpanded: $isLinkedExpanded,
                sourceRef: linkedRef,
                onOpenLinkedRef: onOpenLinkedRef,
                canOpenLinkedRef: canOpenLinkedRef
            )

            if !extraRows.isEmpty {
                ItemMetadataDivider()

                ItemMetadataSectionView(title: "Details", isExpanded: $isDetailsExpanded) {
                    ItemMetadataRowsView(rows: extraRows)
                }
            }
        } footer: {
            ItemMetadataInfoFooter(
                rows: ItemMetadataInfoRows.rows(
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    typeLabel: typeLabel
                ),
                onDelete: onDelete
            )
        }
        .task(id: linkedRef.id) {
            refreshHubFacetPresentation()
        }
    }

    private func createAndAssignLabel() {
        let label = CardLabelStorage.shared.createLabel(
            name: "New Tag",
            colorHex: CardLabelStorage.randomPresetColor()
        )
        onToggleLabel?(label.id)
    }

    private var relatedRows: [ItemMetadataRow] {
        let refs = (try? ItemLinkService.shared.relatedRefs(for: linkedRef)) ?? []
        return ItemLinkService.shared.summaries(for: refs).map(ItemMetadataRow.related)
    }

    private func refreshHubFacetPresentation() {
        hubFacetPresentation = try? CiderItemContextService()
            .libraryHubFacetPresentation(for: linkedRef)
        isHubFacetsExpanded = MetadataRailExpansionPolicy.defaultExpanded(
            for: .intelligence,
            hasContent: hubFacetRowModel.isVisible
        )
    }

    private func openHubAction(_ action: LibraryHubFacetChipRowModel.OpenAction) {
        guard action.isEnabled,
              action.readOnly,
              !action.promotesTruth,
              let target = action.target
        else { return }
        onOpenHubNavigationTarget?(target)
    }
}

extension BasicItemMetadataInspectorView {
    init(
        dateCard: DateCard,
        onOpenLinkedRef: ((LibraryEntityRef) -> Void)? = nil,
        canOpenLinkedRef: ((LibraryEntityRef) -> Bool)? = nil,
        onFolderChanged: ((UUID?) -> Void)? = nil,
        onToggleLabel: ((UUID) -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onOpenHubNavigationTarget: ((LibraryHubNavigationTarget) -> Void)? = nil
    ) {
        self.init(
            title: dateCard.title,
            typeLabel: "Date Card",
            createdAt: dateCard.createdAt,
            updatedAt: dateCard.updatedAt,
            folderID: dateCard.folderID,
            labelIDs: dateCard.labelIDs,
            linkedRef: .dateCard(dateCard.id),
            extraRows: DateCardMetadataRows.rows(for: dateCard),
            onOpenLinkedRef: onOpenLinkedRef,
            canOpenLinkedRef: canOpenLinkedRef,
            onFolderChanged: onFolderChanged,
            onToggleLabel: onToggleLabel,
            onDelete: onDelete,
            onOpenHubNavigationTarget: onOpenHubNavigationTarget
        )
    }

    init(
        todo: TodoCard,
        onOpenLinkedRef: ((LibraryEntityRef) -> Void)? = nil,
        canOpenLinkedRef: ((LibraryEntityRef) -> Bool)? = nil,
        onFolderChanged: ((UUID?) -> Void)? = nil,
        onToggleLabel: ((UUID) -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onOpenHubNavigationTarget: ((LibraryHubNavigationTarget) -> Void)? = nil
    ) {
        self.init(
            title: todo.title,
            typeLabel: "Todo",
            createdAt: todo.createdAt,
            updatedAt: todo.updatedAt,
            folderID: todo.folderID,
            labelIDs: todo.labelIDs,
            linkedRef: .todo(todo.id),
            extraRows: TodoMetadataRows.rows(for: todo),
            onOpenLinkedRef: onOpenLinkedRef,
            canOpenLinkedRef: canOpenLinkedRef,
            onFolderChanged: onFolderChanged,
            onToggleLabel: onToggleLabel,
            onDelete: onDelete,
            onOpenHubNavigationTarget: onOpenHubNavigationTarget
        )
    }

    init(
        file: VaultFile,
        onOpenLinkedRef: ((LibraryEntityRef) -> Void)? = nil,
        canOpenLinkedRef: ((LibraryEntityRef) -> Bool)? = nil,
        onOpenHubNavigationTarget: ((LibraryHubNavigationTarget) -> Void)? = nil
    ) {
        self.init(
            title: file.displayTitle,
            typeLabel: "File",
            createdAt: file.createdAt,
            updatedAt: file.modifiedAt,
            folderID: file.folderID,
            labelIDs: file.labelIDs,
            linkedRef: .vaultFile(file.id),
            extraRows: Self.fileRows(for: file),
            onOpenLinkedRef: onOpenLinkedRef,
            canOpenLinkedRef: canOpenLinkedRef,
            onOpenHubNavigationTarget: onOpenHubNavigationTarget
        )
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

                    sectionDivider
                    linkedSection

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
                    ItemMetadataActionButton(title: "Open", systemImage: "arrow.up.forward.app") {
                        CiderOpenPolicy.shared.openIfAllowed(.localFile(file.absoluteURL))
                    }

                    ItemMetadataActionButton(title: "Finder", systemImage: "folder") {
                        CiderOpenPolicy.shared.openIfAllowed(.revealInFinder(file.absoluteURL))
                    }
                }
            }
        }
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("Folder", isExpanded: $isFolderExpanded)

            if isFolderExpanded {
                ItemMetadataFolderPicker(folderID: folderIDDraft) { folderID in
                    assignFolder(folderID)
                }
            }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("Tags", isExpanded: $isTagsExpanded)

            if isTagsExpanded {
                ItemMetadataTagsPicker(
                    labelIDs: labelIDsDraft,
                    onToggleLabel: toggleLabel,
                    onCreateAndAssignLabel: createAndAssignLabel
                )
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
        ItemMetadataLinkedSection(
            rows: linkedSummaries.map(ItemMetadataRow.related),
            isExpanded: $isLinkedExpanded,
            sourceRef: LibraryEntityRef(type: .vaultFile, entityID: file.id),
            onOpenLinkedRef: onOpenLinkedRef,
            canOpenLinkedRef: canOpenLinkedRef,
            onLinkedItemsChanged: refreshLinkedSummaries
        )
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
        ItemMetadataInfoFooter(
            rows: ItemMetadataInfoRows.rows(
                createdAt: file.createdAt,
                updatedAt: file.modifiedAt,
                typeLabel: "File",
                additionalRows: fileInfoRows
            ),
            onDelete: onDelete
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

    private var hasIntelligence: Bool {
        presentation.ocrText != nil || !presentation.colors.isEmpty
    }

    private var fileInfoRows: [ItemMetadataRow] {
        var rows = [
            ItemMetadataRow(id: "kind", symbol: file.fileType.systemImageName, title: "Kind", value: presentation.kind)
        ]
        if let fileType = presentation.fileType {
            rows.append(ItemMetadataRow(id: "file-type", symbol: "doc", title: "File Type", value: fileType))
        }
        rows.append(ItemMetadataRow(id: "size", symbol: "externaldrive", title: "Size", value: presentation.size))
        return rows
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
