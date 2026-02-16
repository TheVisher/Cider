import AppKit
import SwiftUI

struct BookmarksPanelView: View {
    @ObservedObject var viewModel: BookmarksViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var panelWindow: NSWindow?
    @State private var detailsDraft: BookmarkDetailsDraft?
    @State private var detailsErrorMessage: String?
    @State private var restoreFrameAfterDetailsClose: NSRect?
    @State private var isPresentingDetailsWithResize = false
    @FocusState private var isSearchFieldFocused: Bool

    private var selectedDetailsBookmark: Bookmark? {
        guard let detailsDraft else { return nil }
        return viewModel.bookmarks.first(where: { $0.id == detailsDraft.id })
    }

    var body: some View {
        ZStack {
            AcrylicPanelBackground(cornerRadius: BookmarksDesign.panelCornerRadius)

            VStack(spacing: 0) {
                titleBar

                if !viewModel.isCollapsed {
                    Divider()
                        .background(CiderColors.separator)

                    ZStack {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            TextField("Search bookmarks", text: $viewModel.searchText)
                                .textFieldStyle(.roundedBorder)
                                .focused($isSearchFieldFocused)

                            BookmarksBrowserView(
                                bookmarks: viewModel.filteredBookmarks,
                                folders: viewModel.folders,
                                displayMode: Binding(
                                    get: { viewModel.displayMode },
                                    set: { viewModel.setDisplayMode($0) }
                                ),
                                cardSizeScale: Binding(
                                    get: { viewModel.cardSizeScale },
                                    set: { viewModel.setCardSizeScale($0) }
                                ),
                                onOpenBookmark: {
                                    clearSearchFocus()
                                    viewModel.open($0)
                                },
                                onShowBookmarkDetails: { presentDetails(for: $0) },
                                onDeleteBookmark: {
                                    clearSearchFocus()
                                    viewModel.delete($0)
                                },
                                onAddBookmark: { viewModel.addBookmark(urlString: $0, title: $1) },
                                onAssignThumbnailFromDroppedString: { viewModel.assignThumbnail(for: $0, droppedString: $1) },
                                onAssignThumbnailFromLocalFileURL: { viewModel.assignThumbnail(for: $0, fileURL: $1) },
                                onAssignThumbnailFromImageData: { viewModel.assignThumbnail(for: $0, imageData: $1, preferredFileExtension: $2) },
                                onAssignBookmarkToFolder: { viewModel.assign($0, toFolder: $1) },
                                onCreateFolder: { viewModel.createFolder(name: $0, parentID: $1) }
                            )
                        }
                        .blur(radius: detailsDraft == nil ? 0 : BookmarksDesign.detailsContentBlurRadius)
                        .animation(reduceMotion ? .none : .snappy, value: detailsDraft != nil)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.md)

                        if let detailsDraft {
                            detailsOverlay(detailsDraft: detailsDraft)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(
            BookmarksPanelWindowAccessor(window: $panelWindow)
        )
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        handlePanelWidthChange(proxy.size.width)
                    }
                    .onChange(of: proxy.size.width) { _, width in
                        handlePanelWidthChange(width)
                    }
            }
        )
        .overlay(alignment: .bottomTrailing) {
            if !viewModel.isCollapsed {
                BookmarksResizeHandle()
            }
        }
        .padding(.horizontal, BookmarksDesign.panelTopPadding)
        .padding(.top, BookmarksDesign.panelTopPadding)
        .padding(
            .bottom,
            viewModel.isCollapsed
                ? BookmarksDesign.panelCollapsedBottomPadding
                : BookmarksDesign.panelTopPadding
        )
        .onChange(of: viewModel.isCollapsed) { _, isCollapsed in
            guard isCollapsed else { return }
            closeDetails(restorePanel: false)
        }
        .onChange(of: viewModel.bookmarks.map(\.id)) { _, bookmarkIDs in
            guard let detailsDraft else { return }
            if !bookmarkIDs.contains(detailsDraft.id) {
                closeDetails(restorePanel: false)
            }
        }
        .onAppear {
            clearSearchFocus()
        }
    }

    @ViewBuilder
    private func detailsOverlay(detailsDraft: BookmarkDetailsDraft) -> some View {
        let draftBinding = Binding(
            get: { self.detailsDraft ?? detailsDraft },
            set: { next in
                self.detailsDraft = next
                detailsErrorMessage = nil
            }
        )

        GeometryReader { proxy in
            let sheetWidth = resolvedDetailsSheetWidth(for: proxy.size.width)
            let sheetHeight = resolvedDetailsSheetHeight(for: proxy.size.height)

            ZStack {
                CiderColors.backdropSubtle
                    .contentShape(Rectangle())
                    .onTapGesture {
                        closeDetails(restorePanel: true)
                    }

                BookmarkDetailsSheet(
                    draft: draftBinding,
                    bookmark: selectedDetailsBookmark,
                    errorMessage: detailsErrorMessage,
                    onOpenURL: openDetailsURL,
                    onCopyURL: copyDetailsURL,
                    onSave: saveDetails,
                    onCancel: { closeDetails(restorePanel: true) }
                )
                .frame(width: sheetWidth)
                .frame(maxHeight: sheetHeight)
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.xxl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .transition(.opacity)
    }

    private func presentDetails(for bookmark: Bookmark) {
        clearSearchFocus()
        detailsDraft = BookmarkDetailsDraft(bookmark: bookmark)
        detailsErrorMessage = nil
        ensurePanelWidthForDetails()
    }

    private func closeDetails(restorePanel: Bool) {
        clearSearchFocus()
        isPresentingDetailsWithResize = false
        detailsDraft = nil
        detailsErrorMessage = nil
        guard restorePanel else {
            restoreFrameAfterDetailsClose = nil
            return
        }
        restorePanelFrameIfNeeded()
    }

    private func saveDetails() {
        guard let detailsDraft else { return }
        guard let selectedBookmark = selectedDetailsBookmark else {
            detailsErrorMessage = "This bookmark is no longer available."
            return
        }

        let parsedTags = detailsDraft.tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let didSave = viewModel.updateDetails(
            for: selectedBookmark,
            title: detailsDraft.title,
            notes: detailsDraft.notes,
            tags: parsedTags
        )

        if didSave {
            closeDetails(restorePanel: true)
        } else {
            detailsErrorMessage = "Could not save bookmark details."
        }
    }

    private func copyDetailsURL() {
        guard let detailsDraft else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(detailsDraft.urlString, forType: .string)
    }

    private func openDetailsURL() {
        guard let detailsDraft,
              let url = URL(string: detailsDraft.urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func ensurePanelWidthForDetails() {
        guard let panelWindow else { return }

        let requiredWidth = max(BookmarksDesign.detailsRequiredPanelWidth, BookmarksDesign.panelMinWidth)
        guard panelWindow.frame.width + 0.5 < requiredWidth else {
            isPresentingDetailsWithResize = false
            return
        }

        if restoreFrameAfterDetailsClose == nil {
            restoreFrameAfterDetailsClose = panelWindow.frame
        }
        isPresentingDetailsWithResize = true

        let targetFrame = expandedDetailsFrame(
            from: panelWindow.frame,
            targetWidth: requiredWidth,
            screenVisibleFrame: panelWindow.screen?.visibleFrame ?? panelWindow.frame
        )

        guard abs(targetFrame.width - panelWindow.frame.width) > 0.5
                || abs(targetFrame.minX - panelWindow.frame.minX) > 0.5 else {
            return
        }

        panelWindow.setFrame(targetFrame, display: true, animate: false)
    }

    private func restorePanelFrameIfNeeded() {
        guard let restoreFrameAfterDetailsClose,
              let panelWindow else { return }
        defer { self.restoreFrameAfterDetailsClose = nil }

        let targetFrame = expandedDetailsFrame(
            from: restoreFrameAfterDetailsClose,
            targetWidth: restoreFrameAfterDetailsClose.width,
            screenVisibleFrame: panelWindow.screen?.visibleFrame ?? panelWindow.frame
        )

        panelWindow.setFrame(targetFrame, display: true, animate: !reduceMotion)
    }

    private func clearSearchFocus() {
        isSearchFieldFocused = false
        panelWindow?.makeFirstResponder(nil)
    }

    private func expandedDetailsFrame(
        from frame: NSRect,
        targetWidth: CGFloat,
        screenVisibleFrame: NSRect
    ) -> NSRect {
        let clampedWidth = min(
            max(targetWidth, BookmarksDesign.panelMinWidth),
            screenVisibleFrame.width
        )
        let clampedHeight = min(frame.height, screenVisibleFrame.height)
        let preferredX = frame.maxX - clampedWidth
        let x = min(
            max(preferredX, screenVisibleFrame.minX),
            screenVisibleFrame.maxX - clampedWidth
        )
        let y = min(
            max(frame.minY, screenVisibleFrame.minY),
            screenVisibleFrame.maxY - clampedHeight
        )
        return NSRect(x: x, y: y, width: clampedWidth, height: clampedHeight)
    }

    private func handlePanelWidthChange(_ width: CGFloat) {
        guard detailsDraft != nil else { return }

        if isPresentingDetailsWithResize {
            if width + 0.5 >= BookmarksDesign.detailsRequiredPanelWidth {
                isPresentingDetailsWithResize = false
            }
            return
        }

        if width + 0.5 < BookmarksDesign.detailsRequiredPanelWidth {
            closeDetails(restorePanel: false)
        }
    }

    private func resolvedDetailsSheetWidth(for containerWidth: CGFloat) -> CGFloat {
        let horizontalInset = Spacing.xxxl * 2
        let availableWidth = max(containerWidth - horizontalInset, 1)
        let minimumWidth = min(BookmarksDesign.detailsSheetMinWidth, availableWidth)
        let preferredWidth = max(minimumWidth, availableWidth * BookmarksDesign.detailsSheetPreferredWidthRatio)
        return min(preferredWidth, BookmarksDesign.detailsSheetMaxWidth)
    }

    private func resolvedDetailsSheetHeight(for containerHeight: CGFloat) -> CGFloat {
        let verticalInset = Spacing.xxxl * 2
        let availableHeight = max(containerHeight - verticalInset, 1)
        let minimumHeight = min(BookmarksDesign.detailsSheetMinHeight, availableHeight)
        let preferredHeight = max(minimumHeight, availableHeight * BookmarksDesign.detailsSheetPreferredHeightRatio)
        return min(preferredHeight, BookmarksDesign.detailsSheetMaxHeight)
    }

    @ViewBuilder
    private var titleBar: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: NotesDesign.trafficLightSpacing) {
                BookmarksTrafficLightButton(color: .systemRed, symbol: "xmark", help: "Close bookmarks panel") {
                    NotificationCenter.default.post(name: .dismissBookmarks, object: nil)
                }
                BookmarksTrafficLightButton(
                    color: .systemYellow,
                    symbol: "minus",
                    help: viewModel.isCollapsed ? "Expand bookmarks" : "Collapse to strip"
                ) {
                    NotificationCenter.default.post(name: .toggleBookmarksCollapse, object: nil)
                }
                BookmarksTrafficLightButton(
                    color: .systemGreen,
                    symbol: "safari",
                    help: "Capture active browser tab"
                ) {
                    _ = viewModel.captureBookmarkFromActiveBrowserOrClipboard()
                }
            }

            Text("Bookmarks")
                .font(CiderFont.subheadingSemibold)
                .foregroundColor(CiderColors.primary)

            Text("\(viewModel.filteredBookmarks.count)")
                .font(CiderFont.labelMedium)
                .foregroundColor(CiderColors.tertiary)

            Spacer(minLength: Spacing.sm)

            Button {
                _ = viewModel.captureBookmarkFromActiveBrowserOrClipboard()
            } label: {
                Label("Capture", systemImage: "safari")
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.controlAccent)
                    .padding(.horizontal, Spacing.sm)
                    .frame(minHeight: BookmarksDesign.buttonTapTarget)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.selectedFill)
                    )
            }
            .buttonStyle(.plain)
            .help("Capture active browser tab (Option+Shift+B)")
        }
        .background(BookmarksTitleBarDragRegion())
        .padding(.horizontal, Spacing.md)
        .frame(height: BookmarksDesign.toolbarHeight)
    }
}

struct BookmarkDetailsDraft: Equatable {
    let id: UUID
    let urlString: String
    let hostDisplay: String
    let createdAt: Date
    let updatedAt: Date
    var title: String
    var tagsText: String
    var notes: String

    init(bookmark: Bookmark) {
        id = bookmark.id
        urlString = bookmark.urlString
        hostDisplay = bookmark.hostDisplay
        createdAt = bookmark.createdAt
        updatedAt = bookmark.updatedAt
        title = bookmark.title
        tagsText = bookmark.tags.joined(separator: ", ")
        notes = bookmark.notes
    }
}

struct BookmarkDetailsSheet: View {
    @Binding var draft: BookmarkDetailsDraft
    var bookmark: Bookmark?
    var errorMessage: String?
    let onOpenURL: () -> Void
    let onCopyURL: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void

    @Environment(\.textScale) private var textScale

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header
            canvas
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: BookmarksDesign.detailsSheetMinHeight, maxHeight: BookmarksDesign.detailsSheetMaxHeight)
        .background(
            ZStack {
                VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
                CiderColors.acrylicOverlayTint
                CiderColors.surfaceSubtle
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg - CiderBorder.innerStrokeInset, style: .continuous)
                .stroke(CiderColors.borderPanel, lineWidth: CiderBorder.innerStrokeWidth)
                .padding(CiderBorder.innerStrokeInset)
        )
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: NotesDesign.trafficLightSpacing) {
                BookmarksTrafficLightButton(
                    color: .systemRed,
                    symbol: "xmark",
                    help: "Close details",
                    action: onCancel
                )
                BookmarksTrafficLightButton(
                    color: .systemYellow,
                    symbol: "minus",
                    help: "Close details",
                    action: onCancel
                )
                BookmarksTrafficLightButton(
                    color: .systemGreen,
                    symbol: "safari",
                    help: "Open bookmark",
                    action: onOpenURL
                )
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var canvas: some View {
        GeometryReader { proxy in
            let sidebarWidth = resolvedSidebarWidth(for: proxy.size.width)
            ZStack {
                RoundedRectangle(
                    cornerRadius: BookmarksDesign.detailsCanvasCornerRadius,
                    style: .continuous
                )
                .fill(CiderColors.surfaceHighlight)

                leftContent
                    .padding(.leading, Spacing.lg)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.lg)
                    .padding(.trailing, sidebarWidth + Spacing.xl)

                HStack {
                    Spacer(minLength: 0)
                    sidebar(width: sidebarWidth)
                        .padding(.vertical, BookmarksDesign.detailsCanvasInset)
                        .padding(.trailing, BookmarksDesign.detailsCanvasInset)
                }
            }
        }
    }

    @ViewBuilder
    private var leftContent: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            BookmarkDetailsHeroPreview(bookmark: bookmark, draft: draft)
                .frame(maxWidth: .infinity)
                .frame(
                    minHeight: BookmarksDesign.detailsHeroMinHeight,
                    maxHeight: BookmarksDesign.detailsHeroMaxHeight
                )
                .shadow(
                    color: CiderColors.shadowMedium,
                    radius: BookmarksDesign.detailsFloatingLiftBlur,
                    x: 0,
                    y: BookmarksDesign.detailsFloatingLiftYOffset
                )

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(draft.title)
                    .font(CiderFont.heroTitle(scale: textScale))
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(3)

                HStack(spacing: Spacing.xs) {
                    Text(draft.hostDisplay)
                        .font(CiderFont.labelMedium(scale: textScale))
                        .foregroundColor(CiderColors.secondary)
                    Text("•")
                        .font(CiderFont.captionSemibold(scale: textScale))
                        .foregroundColor(CiderColors.tertiary)
                    Text(draft.updatedAt.formatted(.relative(presentation: .named)))
                        .font(CiderFont.label(scale: textScale))
                        .foregroundColor(CiderColors.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func sidebar(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Metadata")
                .font(CiderFont.bodySemibold(scale: textScale))
                .foregroundColor(CiderColors.tertiary)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("URL")
                    .font(CiderFont.bodyMedium(scale: textScale))
                    .foregroundColor(CiderColors.tertiary)
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(draft.urlString)
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
            }

            HStack(spacing: Spacing.sm) {
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
                    Label("Copy URL", systemImage: "doc.on.doc")
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

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Title")
                    .font(CiderFont.bodyMedium(scale: textScale))
                    .foregroundColor(CiderColors.tertiary)
                TextField("Bookmark title", text: $draft.title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Tags")
                    .font(CiderFont.bodyMedium(scale: textScale))
                    .foregroundColor(CiderColors.tertiary)
                TextField("Comma-separated tags", text: $draft.tagsText)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Notes")
                    .font(CiderFont.bodyMedium(scale: textScale))
                    .foregroundColor(CiderColors.tertiary)
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
            }

            BookmarkDetailsPlaceholderSection(
                title: "Folders",
                subtitle: "Folder assignment coming soon",
                icon: "folder"
            )
            BookmarkDetailsPlaceholderSection(
                title: "Backlinks",
                subtitle: "Linked bookmarks coming soon",
                icon: "link.badge.plus"
            )
            BookmarkDetailsPlaceholderSection(
                title: "Attachments",
                subtitle: "Files and references coming soon",
                icon: "paperclip"
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(CiderFont.bodyMedium(scale: textScale))
                    .foregroundColor(CiderColors.destructive)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Updated \(draft.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(CiderFont.caption(scale: textScale))
                    .foregroundColor(CiderColors.tertiary)
                Text("Created \(draft.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(CiderFont.caption(scale: textScale))
                    .foregroundColor(CiderColors.tertiary)
            }

            HStack(spacing: Spacing.sm) {
                Spacer(minLength: 0)

                Button("Cancel", action: onCancel)
                    .buttonStyle(CiderSecondaryButtonStyle())

                Button("Save", action: onSave)
                    .buttonStyle(CiderAccentButtonStyle())
            }
        }
        .padding(Spacing.md)
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(CiderColors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(CiderColors.borderStrong, lineWidth: CiderBorder.innerStrokeWidth)
        )
        .shadow(
            color: CiderColors.shadowMedium,
            radius: BookmarksDesign.detailsFloatingLiftBlur,
            x: 0,
            y: BookmarksDesign.detailsFloatingLiftYOffset
        )
    }

    private func resolvedSidebarWidth(for containerWidth: CGFloat) -> CGFloat {
        let maxCandidate = containerWidth * BookmarksDesign.detailsSidebarWidthRatio
        return min(
            max(maxCandidate, BookmarksDesign.detailsSidebarMinWidth),
            BookmarksDesign.detailsSidebarMaxWidth
        )
    }
}

struct BookmarkDetailsHeroPreview: View {
    let bookmark: Bookmark?
    let draft: BookmarkDetailsDraft

    @Environment(\.textScale) private var textScale
    @State private var thumbnailImage: NSImage?
    @State private var loadedThumbnailPath: String?

    private var palette: (Color, Color) {
        let seed = bookmark?.urlString ?? draft.urlString
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
            .onAppear(perform: loadThumbnailIfNeeded)
            .onChange(of: bookmark?.thumbnailRelativePath) { _, _ in
                loadThumbnailIfNeeded()
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

    private func loadThumbnailIfNeeded() {
        let path = bookmark?.thumbnailFileURL?.path
        guard loadedThumbnailPath != path else { return }
        loadedThumbnailPath = path

        guard let path else {
            thumbnailImage = nil
            return
        }
        thumbnailImage = NSImage(contentsOfFile: path)
    }
}

struct BookmarkDetailsPlaceholderSection: View {
    let title: String
    let subtitle: String
    let icon: String

    @Environment(\.textScale) private var textScale

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Label(title, systemImage: icon)
                .font(CiderFont.captionSemibold(scale: textScale))
                .foregroundColor(CiderColors.tertiary)

            Text(subtitle)
                .font(CiderFont.body(scale: textScale))
                .foregroundColor(CiderColors.quaternary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.xxs)
    }
}

private struct BookmarksPanelWindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if window !== view.window {
                window = view.window
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if window !== nsView.window {
                window = nsView.window
            }
        }
    }
}

private struct BookmarksTitleBarDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> BookmarksTitleBarDragRegionNSView {
        BookmarksTitleBarDragRegionNSView(frame: .zero)
    }

    func updateNSView(_ nsView: BookmarksTitleBarDragRegionNSView, context: Context) {}
}

private final class BookmarksTitleBarDragRegionNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

// MARK: - Resize Handle

private struct BookmarksResizeHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> BookmarksResizeHandleNSView {
        let view = BookmarksResizeHandleNSView()
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    func updateNSView(_ nsView: BookmarksResizeHandleNSView, context: Context) {}
}

private final class BookmarksResizeHandleNSView: NSView {
    private var trackingArea: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool { false }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 16, height: 16)
    }

    override var isFlipped: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func draw(_ dirtyRect: NSRect) {
        let symbol = NSImage(
            systemSymbolName: "arrow.down.backward.and.arrow.up.forward",
            accessibilityDescription: "Resize"
        )?.withSymbolConfiguration(.init(pointSize: 9, weight: .medium))
        if let symbol {
            let size = symbol.size
            let origin = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
            symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 0.35)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.frameResize(position: .bottomRight, directions: [.inward, .outward]).push()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.pop()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = self.window else { return }

        let initialFrame = window.frame
        let initialMouse = NSEvent.mouseLocation

        var keepRunning = true
        while keepRunning {
            guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }

            switch next.type {
            case .leftMouseDragged:
                let mouse = NSEvent.mouseLocation
                let dx = mouse.x - initialMouse.x
                let dy = mouse.y - initialMouse.y

                let width = max(BookmarksDesign.panelMinWidth, initialFrame.width + dx)
                let height = max(BookmarksDesign.panelMinHeight, initialFrame.height - dy)
                let y = initialFrame.origin.y + (initialFrame.height - height)

                window.setFrame(
                    NSRect(x: initialFrame.origin.x, y: y, width: width, height: height),
                    display: true
                )

            case .leftMouseUp:
                keepRunning = false

            default:
                break
            }
        }
    }
}

struct BookmarksTrafficLightButton: View {
    let color: NSColor
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(color))
                .frame(width: NotesDesign.trafficLightDiameter, height: NotesDesign.trafficLightDiameter)
                .overlay {
                    if isHovered {
                        Image(systemName: symbol)
                            .font(.system(size: NotesDesign.trafficLightSymbolSize, weight: .semibold))
                            .foregroundColor(CiderColors.trafficLightSymbol)
                    }
                }
                .frame(width: NotesDesign.trafficLightTapTarget, height: NotesDesign.trafficLightTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverState($isHovered)
        .help(help)
    }
}
