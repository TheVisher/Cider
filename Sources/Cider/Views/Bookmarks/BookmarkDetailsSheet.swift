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

    @State private var isEditingNotes = false
    @State private var saveDebounceTask: Task<Void, Never>?
    @State private var fileSize: String?

    @State private var isSourceExpanded = true
    @State private var isFolderExpanded = true
    @State private var isTagsExpanded = true
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

                    sectionDivider
                    folderSection
                        .padding(.vertical, Spacing.md)

                    sectionDivider
                    tagsSection
                        .padding(.vertical, Spacing.md)

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
                    .font(.system(size: 9, weight: .semibold))
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

    // MARK: - Tags

    @ViewBuilder
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("Tags", isExpanded: $isTagsExpanded)

            if isTagsExpanded {
                TextField("Add tags, comma separated", text: $draft.tagsText)
                    .font(CiderFont.body(scale: textScale))
                    .textFieldStyle(.roundedBorder)
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

    private var hasAIData: Bool {
        guard let bookmark else { return false }
        return bookmark.aiSummary != nil
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
                        HStack(spacing: Spacing.xs) {
                            ForEach(colors, id: \.self) { hex in
                                if let color = Color(hex: hex) {
                                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                                        .fill(color)
                                        .frame(width: 20, height: 20)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                                                .stroke(CiderColors.borderSubtle, lineWidth: CiderBorder.innerStrokeWidth)
                                        )
                                        .help(hex)
                                }
                            }
                        }
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
                    .font(.system(size: 9, weight: .semibold))
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

    @ViewBuilder
    private var heroContent: some View {
        if let thumbnailImage {
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
