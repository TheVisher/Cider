import SwiftUI

struct BookmarkDetailsDraft: Equatable {
    let id: UUID
    let originalURLString: String
    var sourceURL: String
    let hostDisplay: String
    let hasURL: Bool
    let createdAt: Date
    let updatedAt: Date
    var title: String
    var tagsText: String
    var labelIDs: [UUID]
    var notes: String
    var folderID: UUID?

    init(bookmark: Bookmark) {
        id = bookmark.id
        originalURLString = bookmark.urlString
        sourceURL = bookmark.urlString
        hostDisplay = bookmark.hostDisplay
        hasURL = bookmark.hasURL
        createdAt = bookmark.createdAt
        updatedAt = bookmark.updatedAt
        title = bookmark.title
        tagsText = bookmark.tags.joined(separator: ", ")
        labelIDs = bookmark.labelIDs
        notes = bookmark.notes
        folderID = bookmark.folderID
    }
}

// MARK: - Metadata Sidebar (shared by detail surfaces)

struct BookmarkMetadataSidebar: View {
    @Binding var draft: BookmarkDetailsDraft
    var bookmark: Bookmark?
    var errorMessage: String?
    var folders: [Folder]
    var width: CGFloat
    var showBackground: Bool = true
    var onDelete: (() -> Void)?
    var onFolderChanged: ((UUID?) -> Void)?
    var onOpenURL: () -> Void
    var onCopyURL: () -> Void
    var onSave: () -> Void
    var onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.textScale) private var textScale
    @ObservedObject private var labelStorage = CardLabelStorage.shared

    @State private var isEditingNotes = false
    @State private var saveDebounceTask: Task<Void, Never>?
    @State private var fileSize: String?
    @State private var newTagText: String = ""
    @State private var copiedHex: String?
    @State private var showAddTagPicker = false

    @State private var isSourceExpanded = true
    @State private var isImagesExpanded = true
    @State private var isFolderExpanded = true
    @State private var isTagsExpanded = true
    @State private var isKeywordsExpanded = false
    @State private var isNotesExpanded = true
    @State private var isPropertiesExpanded = true
    @State private var isAIExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            // ── Scrollable content ──────────────────────────────────────
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    titleSection
                        .padding(.bottom, Spacing.md)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(CiderFont.bodyMedium(scale: textScale))
                            .foregroundColor(CiderColors.destructive)
                            .padding(.bottom, Spacing.md)
                    }

                    sectionDivider
                    sourceSection
                        .padding(.vertical, Spacing.md)

                    if bookmark?.isCarousel == true {
                        sectionDivider
                        imagesSection
                            .padding(.vertical, Spacing.md)
                    }

                    sectionDivider
                    folderSection
                        .padding(.vertical, Spacing.md)

                    sectionDivider
                    tagsSection
                        .padding(.vertical, Spacing.md)

                    if !parsedTags.isEmpty {
                        sectionDivider
                        keywordsSection
                            .padding(.vertical, Spacing.md)
                    }

                    sectionDivider
                    notesSection
                        .padding(.vertical, Spacing.md)

                    if hasAIData {
                        sectionDivider
                        aiSection
                            .padding(.vertical, Spacing.md)
                    }
                }
                .padding(Spacing.md)
            }
            .frame(maxHeight: .infinity)

            // ── Pinned footer ───────────────────────────────────────────
            footerSection
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background {
            if showBackground {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(CiderColors.surfaceInput)
            }
        }
        .overlay {
            if showBackground {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(CiderColors.borderStrong, lineWidth: CiderBorder.innerStrokeWidth)
            }
        }
        .shadow(
            color: showBackground ? CiderColors.shadowMedium : .clear,
            radius: showBackground ? BookmarksDesign.detailsFloatingLiftBlur : 0,
            x: 0,
            y: showBackground ? BookmarksDesign.detailsFloatingLiftYOffset : 0
        )
        .onChange(of: draft) { _, _ in scheduleSave() }
        .onChange(of: draft.id) { _, _ in
            isEditingNotes = false
            saveDebounceTask?.cancel()
            fileSize = nil
            newTagText = ""
            copiedHex = nil
        }
        .task(id: bookmark?.id) {
            fileSize = nil
            guard let url = bookmark?.originalImageFileURL ?? bookmark?.thumbnailFileURL else { return }
            let size = await Task.detached(priority: .utility) {
                (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64
            }.value
            guard !Task.isCancelled else { return }
            var t = Transaction(animation: .none)
            t.disablesAnimations = true
            withTransaction(t) {
                fileSize = size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
            }
        }
    }

    // MARK: - Section Header

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
                    .font(.system(size: 9 * CiderFont.scale, weight: .semibold))
                    .foregroundColor(CiderColors.tertiary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : -90))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sectionDivider: some View {
        Divider()
            .background(CiderColors.separator)
    }

    // MARK: - Title

    @ViewBuilder
    private var titleSection: some View {
        TextField("Title", text: $draft.title, axis: .vertical)
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
    }

    // MARK: - Source

    @ViewBuilder
    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("Source", isExpanded: $isSourceExpanded)

            if isSourceExpanded {
                if draft.hasURL {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(draft.sourceURL)
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
                        Button(action: onOpenURL) {
                            Label("Open", systemImage: "link")
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

                        Button(action: onCopyURL) {
                            Label("Copy", systemImage: "doc.on.doc")
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

                        if hasOpenableImageSource {
                            Button(action: openOriginalImage) {
                                Image(systemName: "photo")
                                    .font(CiderFont.bodyMedium(scale: textScale))
                                    .foregroundColor(CiderColors.secondary)
                                    .frame(
                                        width: BookmarksDesign.buttonTapTarget,
                                        height: BookmarksDesign.buttonTapTarget
                                    )
                            }
                            .buttonStyle(.plain)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .fill(CiderColors.surfaceInput)
                            )
                            .help("Open original image")
                        }
                    }
                } else {
                    TextField("Add a source", text: $draft.sourceURL)
                        .font(CiderFont.body(scale: textScale))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    // MARK: - Images (Carousel)

    @ViewBuilder
    private var imagesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("Images (\(bookmark?.imageCount ?? 0))", isExpanded: $isImagesExpanded)

            if isImagesExpanded, let bookmark, let paths = bookmark.carouselImagePaths, !paths.isEmpty {
                let urls = bookmark.carouselImageFileURLs
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 60, maximum: 80), spacing: Spacing.xs)], spacing: Spacing.xs) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                        CarouselMetadataThumbnail(url: url) {
                            BookmarksStorage.shared.removeCarouselImage(for: bookmark.id, at: index)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Folder

    @ViewBuilder
    private var folderSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("Folder", isExpanded: $isFolderExpanded)

            if isFolderExpanded {
                Menu {
                    Button("No Folder") {
                        draft.folderID = nil
                        onFolderChanged?(nil)
                    }
                    if !folders.isEmpty { Divider() }
                    ForEach(folders) { folder in
                        Button(folder.name) {
                            draft.folderID = folder.id
                            onFolderChanged?(folder.id)
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

    // MARK: - Tags (CardLabel-based)

    private var assignedLabels: [CardLabel] {
        draft.labelIDs.compactMap { id in
            labelStorage.labels.first(where: { $0.id == id })
        }
    }

    private var unassignedLabels: [CardLabel] {
        let assigned = Set(draft.labelIDs)
        return labelStorage.labels.filter { !assigned.contains($0.id) }
    }

    private func toggleLabel(_ labelID: UUID) {
        if let idx = draft.labelIDs.firstIndex(of: labelID) {
            draft.labelIDs.remove(at: idx)
        } else {
            draft.labelIDs.append(labelID)
        }
        scheduleSave()
    }

    @ViewBuilder
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

                    // + Add Tag button with menu
                    Menu {
                        if unassignedLabels.isEmpty && labelStorage.labels.isEmpty {
                            Button("New Tag...") {
                                let newLabel = CardLabelStorage.shared.createLabel(
                                    name: "New Tag",
                                    colorHex: CardLabelStorage.randomPresetColor()
                                )
                                draft.labelIDs.append(newLabel.id)
                                scheduleSave()
                            }
                        } else {
                            ForEach(unassignedLabels) { label in
                                Button {
                                    toggleLabel(label.id)
                                } label: {
                                    HStack(spacing: Spacing.xs) {
                                        Circle()
                                            .fill(Color(hex: label.colorHex) ?? CiderColors.secondary)
                                            .frame(width: 8, height: 8)
                                        Text(label.name)
                                    }
                                }
                            }

                            Divider()

                            Button("New Tag...") {
                                let newLabel = CardLabelStorage.shared.createLabel(
                                    name: "New Tag",
                                    colorHex: CardLabelStorage.randomPresetColor()
                                )
                                draft.labelIDs.append(newLabel.id)
                                scheduleSave()
                            }
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "plus")
                                .font(.system(size: 8 * CiderFont.scale, weight: .semibold))
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

    // MARK: - Keywords (AI text tags, read-only)

    private var parsedTags: [String] {
        draft.tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    @ViewBuilder
    private var keywordsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("Keywords", isExpanded: $isKeywordsExpanded)

            if isKeywordsExpanded {
                TagFlowLayout(spacing: Spacing.xs) {
                    ForEach(parsedTags, id: \.self) { tag in
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

    // MARK: - Notes

    @ViewBuilder
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("Notes", isExpanded: $isNotesExpanded)

            if isNotesExpanded {
                if !draft.notes.isEmpty || isEditingNotes {
                    if isEditingNotes {
                        VStack(alignment: .trailing, spacing: Spacing.xs) {
                            TextEditor(text: $draft.notes)
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
                                isEditingNotes = false
                            }
                            .buttonStyle(CiderSecondaryButtonStyle())
                        }
                    } else {
                        Text(draft.notes.isEmpty ? "" : draft.notes)
                            .font(CiderFont.body(scale: textScale))
                            .foregroundColor(CiderColors.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { isEditingNotes = true }
                    }
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

    // MARK: - AI Section

    // Show the AI section for any URL bookmark — summary and related items arrive async.
    private var hasAIData: Bool {
        guard let bookmark else { return false }
        return draft.hasURL
            || bookmark.aiSummary != nil
            || !(bookmark.dominantColors ?? []).isEmpty
    }

    @ViewBuilder
    private var aiSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("Intelligence", isExpanded: $isAIExpanded)

            if isAIExpanded, let bookmark {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    if let summary = bookmark.aiSummary, !summary.isEmpty {
                        Text(summary)
                            .font(CiderFont.body(scale: textScale))
                            .foregroundColor(CiderColors.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let colors = bookmark.dominantColors, !colors.isEmpty {
                        colorsSubsection(colors: colors)
                    }

                    RelatedItemsView(bookmarkID: bookmark.id)
                }
            }
        }
    }

    @ViewBuilder
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
                                    .frame(width: 44, height: 22)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                                            .stroke(CiderColors.borderSubtle, lineWidth: CiderBorder.innerStrokeWidth)
                                    )

                                Group {
                                    if copiedHex == hex {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 8 * CiderFont.scale, weight: .semibold))
                                            .foregroundColor(CiderColors.success)
                                    } else {
                                        Text(hex.uppercased())
                                            .font(CiderFont.caption(scale: textScale))
                                            .foregroundColor(CiderColors.tertiary)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(height: 12)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Copy \(hex.uppercased())")
                    }
                }
            }
        }
    }

    // MARK: - Footer (pinned to bottom)

    @ViewBuilder
    private var footerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Divider()
                .background(CiderColors.separator)

            propertiesHeader

            if isPropertiesExpanded {
                propertiesGrid
                    .padding(.bottom, Spacing.xxs)
            }

            if let onDelete {
                Divider()
                    .background(CiderColors.separator)

                Button("Delete", action: onDelete)
                    .buttonStyle(CiderDestructiveButtonStyle())
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(Spacing.md)
    }

    @ViewBuilder
    private var propertiesHeader: some View {
        Button {
            withAnimation(reduceMotion ? .none : .snappy) {
                isPropertiesExpanded.toggle()
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Text("Info")
                    .font(CiderFont.bodyMedium(scale: textScale))
                    .foregroundColor(CiderColors.tertiary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up")
                    .font(.system(size: 9 * CiderFont.scale, weight: .semibold))
                    .foregroundColor(CiderColors.tertiary)
                    .rotationEffect(.degrees(isPropertiesExpanded ? 0 : -90))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var propertiesGrid: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            propertyRow("Created", value: draft.createdAt.formatted(date: .abbreviated, time: .shortened))
            propertyRow("Updated", value: draft.updatedAt.formatted(date: .abbreviated, time: .shortened))
            propertyRow("Type", value: itemType)
            if shouldShowSize {
                propertyRow("Size", value: fileSize ?? "—")
            }
        }
    }

    // Show a Size row for image and file bookmarks (not for web URLs — thumbnail
    // size is irrelevant there). Computed without disk I/O so it's ready on first
    // render, preventing layout shift when the async size value arrives.
    private var shouldShowSize: Bool {
        !draft.hasURL || draft.originalURLString.lowercased().hasPrefix("file:")
    }

    private func propertyRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Text(label)
                .font(CiderFont.caption(scale: textScale))
                .foregroundColor(CiderColors.tertiary)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .font(CiderFont.caption(scale: textScale))
                .foregroundColor(CiderColors.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Helpers

    private var itemType: String {
        if bookmark?.isCarousel == true { return "Carousel (\(bookmark?.imageCount ?? 0))" }
        if bookmark?.isAnimatedImage == true { return "GIF" }
        if !draft.hasURL { return "Image" }
        if draft.originalURLString.lowercased().hasPrefix("file:") { return "File" }
        return "Bookmark"
    }

    private var currentFolderName: String {
        guard let fid = draft.folderID else { return "No Folder" }
        return folders.first(where: { $0.id == fid })?.name ?? "No Folder"
    }

    private var hasOpenableImageSource: Bool {
        if let originalFileURL = bookmark?.originalImageFileURL {
            return FileManager.default.fileExists(atPath: originalFileURL.path)
        }
        if let remote = bookmark?.thumbnailRemoteURLString {
            return URL(string: remote) != nil
        }
        return false
    }

    private func openOriginalImage() {
        // Carousel: open all images in Preview
        if let bookmark, bookmark.isCarousel {
            let urls = bookmark.carouselImageFileURLs.filter {
                FileManager.default.fileExists(atPath: $0.path)
            }
            if !urls.isEmpty {
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.open(urls, withApplicationAt: URL(fileURLWithPath: "/System/Applications/Preview.app"), configuration: config)
                return
            }
        }

        if let originalFileURL = bookmark?.originalImageFileURL,
           FileManager.default.fileExists(atPath: originalFileURL.path) {
            NSWorkspace.shared.open(originalFileURL)
            return
        }
        if let remote = bookmark?.thumbnailRemoteURLString,
           let remoteURL = URL(string: remote) {
            NSWorkspace.shared.open(remoteURL)
        }
    }

    private func scheduleSave() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            onSave()
        }
    }

}

// MARK: - Hero Preview

struct BookmarkDetailsHeroPreview: View {
    let bookmark: Bookmark?
    let draft: BookmarkDetailsDraft
    var isPageMode: Bool = false

    @Environment(\.textScale) private var textScale
    @State private var thumbnailImage: NSImage?

    private var palette: (Color, Color) {
        let seed = bookmark?.urlString ?? draft.originalURLString
        let pairs: [(NSColor, NSColor)] = [
            (.systemBlue, .systemTeal),
            (.systemIndigo, .systemBlue),
            (.systemOrange, .systemYellow),
            (.systemPink, .systemRed),
            (.systemMint, .systemGreen),
            (.systemCyan, .systemBlue),
        ]
        let index = abs(seed.hashValue) % pairs.count
        return (Color(pairs[index].0), Color(pairs[index].1))
    }

    var body: some View {
        if isPageMode {
            heroContent
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .shadow(color: CiderColors.shadowMedium, radius: 12, x: 0, y: 4)
                .task(id: thumbnailFingerprint) {
                    await loadThumbnailAsync()
                }
        } else {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(stageBackground)
                .overlay {
                    heroContent
                }
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(CiderColors.borderStrong, lineWidth: CiderBorder.innerStrokeWidth)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .task(id: thumbnailFingerprint) {
                    await loadThumbnailAsync()
                }
        }
    }

    @State private var carouselPage = 0

    @ViewBuilder
    private var heroContent: some View {
        if let bookmark, bookmark.isCarousel {
            CarouselHeroView(bookmark: bookmark, currentPage: $carouselPage)
        } else if let gifURL = bookmark?.animatedImageFileURL {
            AnimatedGIFView(url: gifURL, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(Spacing.md)
                .shadow(color: CiderColors.shadowMedium, radius: 8, x: 0, y: 3)
        } else if let thumbnailImage {
            Image(nsImage: thumbnailImage)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(Spacing.md)
                .shadow(color: CiderColors.shadowMedium, radius: 8, x: 0, y: 3)
        } else {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Spacer(minLength: 0)
                Text(String(draft.hostDisplay.prefix(1)).uppercased())
                    .font(.system(size: BookmarksDesign.detailsHeroFallbackLetterSize * textScale, weight: .black))
                    .foregroundColor(CiderColors.textOnColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Spacing.md)
        }
    }

    private var stageBackground: some ShapeStyle {
        if thumbnailImage != nil {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        CiderColors.stageGradientStart,
                        CiderColors.stageGradientEnd,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(
            LinearGradient(
                colors: [palette.0.opacity(CiderColors.gradientTint), palette.1.opacity(CiderColors.gradientTint)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var thumbnailFingerprint: String {
        let path = bookmark?.thumbnailFileURL?.path ?? ""
        let ts = String(bookmark?.metadataUpdatedAt?.timeIntervalSince1970 ?? -1)
        let remote = bookmark?.thumbnailRemoteURLString ?? ""
        return "\(path)|\(ts)|\(remote)"
    }

    private func loadThumbnailAsync() async {
        guard let fileURL = bookmark?.thumbnailFileURL else {
            thumbnailImage = nil
            return
        }

        let image: NSImage? = await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }.value

        guard !Task.isCancelled else { return }
        thumbnailImage = image
    }
}

// MARK: - Carousel Hero View

struct CarouselHeroView: View {
    let bookmark: Bookmark
    @Binding var currentPage: Int

    @State private var isHovered = false

    private var urls: [URL] { bookmark.carouselImageFileURLs }

    var body: some View {
        ZStack {
            CarouselPageImage(url: urls[currentPage], fillMode: .fit)
                .id(currentPage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .overlay {
                    CarouselScrollWheelOverlay { delta in
                        navigatePage(delta: delta)
                    }
                }

            // Navigation arrows on hover
            if isHovered, urls.count > 1 {
                HStack {
                    if currentPage > 0 {
                        carouselArrow(systemName: "chevron.left") {
                            navigatePage(delta: -1)
                        }
                    }
                    Spacer()
                    if currentPage < urls.count - 1 {
                        carouselArrow(systemName: "chevron.right") {
                            navigatePage(delta: 1)
                        }
                    }
                }
                .padding(.horizontal, Spacing.sm)
            }

            // Page dots
            if urls.count > 1 {
                VStack {
                    Spacer()
                    HStack(spacing: Spacing.xs) {
                        ForEach(0..<urls.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentPage ? CiderColors.textOnColor : CiderColors.textOnColor.opacity(0.4))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                    .padding(.horizontal, Spacing.sm)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.45))
                    )
                    .padding(.bottom, Spacing.sm)
                }
            }
        }
        .focusable()
        .onKeyPress(.leftArrow) { navigatePage(delta: -1); return .handled }
        .onKeyPress(.rightArrow) { navigatePage(delta: 1); return .handled }
        .onHover { isHovered = $0 }
    }

    private func navigatePage(delta: Int) {
        let target = max(0, min(currentPage + delta, urls.count - 1))
        guard target != currentPage else { return }
        withAnimation(.snappy) {
            currentPage = target
        }
    }

    private func carouselArrow(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(CiderColors.textOnColor)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.black.opacity(0.55)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Carousel Metadata Thumbnail

struct CarouselMetadataThumbnail: View {
    let url: URL
    let onDelete: () -> Void

    @State private var image: NSImage?
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
                .contextMenu {
                    Button("Open in Preview") {
                        NSWorkspace.shared.open(url)
                    }
                    Divider()
                    Button("Remove", role: .destructive) {
                        onDelete()
                    }
                }

            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(CiderColors.textOnColor)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.black.opacity(0.7)))
                }
                .buttonStyle(.plain)
                .padding(Spacing.xxs)
            }
        }
        .onHover { isHovered = $0 }
        .task(id: url) {
            image = await loadImage()
        }
    }

    private func loadImage() async -> NSImage? {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 160,
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }.value
    }
}
